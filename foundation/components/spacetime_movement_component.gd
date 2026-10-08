class_name SpaceTimeMovementComponent extends SpaceTimeComponent
## Movement, per ARCHITECTURE §7 and PHASE4_SPEC §1/§4.
##
## LOCAL_PREDICTED (the entity this client owns) runs the shared `MovementModel` against the real
## level every physics tick and applies the result immediately — that is what makes input feel
## instant. Every predicted state is remembered by input `seq`. When the server echoes a row it
## says "I have processed your inputs up to seq N and the entity is HERE"; we compare that with
## what we predicted AT seq N, never with where we are now (which is ~100 ms further along).
## Comparing with "now" is what made Phase 3 rubber-band: at a sprint the echo is always most of
## a metre behind, so every row looked like an error.
##
## Remote entities (REMOTE_INTERPOLATED) are rendered in the PAST, at
## `server_now - interp_delay`, interpolated between the two authoritative snapshots bracketing
## that instant. Rendering in the past is what makes a 20 Hz stream look continuous without
## inventing motion: the samples on both sides are real.
##
## Discrete events (`jumped`, `landed`, `move_state_changed`) are detected from the
## AUTHORITATIVE row sequence, never from the interpolated view.

## Local signals, for siblings in this scene (AnimationTree, VFX, audio).
signal predicted_state_changed(state: MovementState)
signal jumped()
signal landed(impact_speed: float)
signal move_state_changed(old_state: int, new_state: int)
## The server disagreed with our prediction by `error` metres and we corrected. Small ones glide
## (see `get_visual_offset`); ones past `reconcile_snap_threshold` snap.
signal reconciled(error: float)
## LOCAL_PREDICTED: a discrete event (&"jumped" / &"landed") fired from the PREDICTION, the moment
## it happened, identified by the input seq that caused it. `jumped`/`landed` fire alongside.
signal event_predicted(kind: StringName, event_id: int)
## A predicted event did not happen after all: the server overrode the path it was on. A jump
## sound has already played and cannot unplay; an ability or an animation state can cancel.
signal event_revoked(kind: StringName, event_id: int)

enum Mode {
	## The entity this client owns: predicted locally, reconciled against the server by input seq.
	LOCAL_PREDICTED,
	## Someone else's entity: buffer snapshots and render interpolated, delayed.
	REMOTE_INTERPOLATED,
	## Apply each authoritative row the moment it lands, no buffering or smoothing. For
	## entities that move rarely or teleport by nature.
	SERVER_DRIVEN,
	## Task 13: this process IS the authority (headless sidecar). Not implemented yet.
	SERVER_AUTHORITY,
}

const TABLE: StringName = &"movement_state"
## SERVER_AUTHORITY only: the frames a client submitted, waiting to be simulated.
const INPUT_TABLE: StringName = &"input_queue"
## SERVER_AUTHORITY: most input frames replayed in one physics tick. A client that stalled and
## reconnected arrives with a backlog; replaying all of it at once would fling the entity across
## the level in a single step, and replaying it a few frames per tick would take a minute of
## slow motion. Take the newest few, and tell the client it was moved (SIDECAR_SPEC §3).
const MAX_CATCHUP_FRAMES: int = 8
## SERVER_AUTHORITY: how far a teleport row has to be from where we already are before we believe
## somebody else wrote it. Squared metres.
const ADOPT_EPSILON_SQ: float = 0.0025
## Enough history to cover interpolation delay plus jitter at the 20 Hz server tick.
const RING_SIZE: int = 32
## How far past the newest snapshot we will project with velocity before simply holding.
## Beyond this the guess is worse than standing still.
const MAX_EXTRAPOLATION_USEC: int = 100_000
## Prediction history cap. ~4 s at 60 Hz: far more than any sane round trip. Beyond it the
## server has stopped acknowledging us (disconnected) and old entries are useless.
const MAX_HISTORY: int = 256
## Below this a visual offset is invisible; clear it instead of decaying it forever.
const OFFSET_EPSILON: float = 0.001
## A gap between snapshots longer than this is the entity having been idle, not the rate of the
## stream, and must not feed the adaptive delay. Nor may an arrival this far off the estimated
## timeline be averaged in: it re-anchors it. Without both, a remote player whose row was
## minutes old at spawn got a minutes-long "adaptive" delay and froze (DECISIONS #75).
const TIMELINE_DISCONTINUITY_USEC: int = 500_000
## However jittery the stream, never draw someone more than this far in the past.
const MAX_INTERP_DELAY_SEC: float = 0.5
## Rejoining the real path after the buffer ran dry (projective velocity blending). The blend
## runs from "where we were heading" to the real path with a smoothstep weight, so position AND
## velocity are continuous at both ends. Its length is derived, not fixed: removing a position
## error e smoothly needs peak acceleration 6e/D^2, changing velocity by dv needs 1.5dv/D, and D
## is chosen so neither exceeds REJOIN_MAX_ACCEL. A fixed 100 ms linear glide lurched by
## 0.12 m/frame when a dry spell met a turn (DECISIONS #76).
const REJOIN_MAX_ACCEL: float = 60.0
const REJOIN_MIN_SEC: float = 0.1
const REJOIN_MAX_SEC: float = 0.35
## The remote render clock advances exactly one physics step per tick, plus or minus at most
## this much while it converges on its target. Every input to that target — the arrival
## estimate, the adaptive delay — wobbles under jitter, and each wobble used to jump render
## time and so the drawn position. Slewed instead, time runs 6% fast or slow for a moment and
## the entity's drawn speed changes by millimetres per frame. (DECISIONS #75)
const RENDER_CLOCK_SLEW_USEC: int = 1_000
## Spans shorter than this interpolate with Hermite curves through each snapshot's position AND
## velocity; longer ones (the entity sat idle, its velocity is stale) fall back to a straight
## line. Straight lines between samples put every change of velocity at a sample corner: a
## walker turning 90 degrees across a sparse stretch drew a 6 cm/frame kink. Hermite is
## velocity-continuous through the turn, and identical to linear for straight-line motion.
const HERMITE_MAX_SPAN_USEC: int = 250_000

@export var mode: Mode = Mode.REMOTE_INTERPOLATED
@export var config: MovementConfig

## Ascending by `t`: [{t: int (server usec), state: MovementState}]
var _ring: Array[Dictionary] = []
var _auth: MovementState = null
var _auth_usec: int = 0
## Highest input seq the server has folded into this entity's state.
var _last_processed_seq: int = 0
var _render: MovementState = MovementState.new()
# --- SERVER_AUTHORITY -----------------------------------------------------------------------
## What this process has simulated. Distinct from `_auth` (what the database says) because we
## are the one who puts it there: `_auth` is the echo of our own writes.
var _sim: MovementState = null
## Highest input seq folded into `_sim`. Goes on the wire as `last_processed_seq`.
var _sim_seq: int = 0
var _sim_dirty: bool = false
## Have we simulated at least one frame since the state last came from outside? A row can CLAIM
## an entity is grounded while putting it in the air — `spawn_npc` writes `grounded: true` at
## whatever height it is given — and an entity trusted to be asleep on that claim hangs there.
var _sim_verified: bool = false
var _sim_teleport: bool = false
## Frames waiting to be simulated, ascending by seq.
var _queue: Array[InputFrame] = []
var _world_id_seen: int = -1
## REMOTE: exponential average of the gap between consecutive snapshots, for the adaptive delay.
var _snapshot_interval_usec: float = 0.0

# --- REMOTE timeline (DECISIONS #75) --------------------------------------------------------
## Snapshots are placed on the ENTITY'S OWN clock, not the server's processing clock. The server
## processes a client's inputs in irregular clumps — batching, tick phase and network jitter
## hand one tick two frames and the next four — so stamping rows with `server_ts` described a
## walker moving at a steady 5 m/s as lurching between 3.3 and 6.7. `last_processed_seq` says
## exactly which 1/60 s each position belongs to, so a client-driven entity's snapshots are
## spaced by seq; an entity nobody drives (lps not advancing) falls back to server time.
var _tl_last_t: int = 0
var _tl_last_lps: int = -1
var _tl_last_server_ts: int = 0
## entity timeline ~= _physics_clock_usec() + offset, estimated from arrivals.
var _tl_offset_usec: float = 0.0
var _tl_has_offset: bool = false
## Mean deviation of arrivals from that estimate: how much buffer the delay must add.
var _tl_jitter_usec: float = 0.0
## Telemetry: frames drawn past the newest snapshot (extrapolated), and how many separate times
## the buffer ran dry. Both should be ~0; the overlay and the remote playtest report them.
var _extrapolated_frames: int = 0
var _dry_events: int = 0
var _was_dry: bool = false
## When the buffer runs dry we project ahead on the last velocity; when the real path arrives it
## rarely agrees — if the entity was turning, not at all. See REJOIN_MAX_ACCEL.
var _blend_active: bool = false
var _blend_p0: Vector3 = Vector3.ZERO
var _blend_v0: Vector3 = Vector3.ZERO
var _blend_tau: float = 0.0
var _blend_dur: float = 0.1
## Drawn minus ideal, this frame. Zero unless a rejoin blend is in progress. Telemetry.
var _remote_offset: Vector3 = Vector3.ZERO
var _drawn_prev: Vector3 = Vector3.ZERO
var _drawn_step: Vector3 = Vector3.ZERO
var _drawn_valid: bool = false
var _render_t: int = 0
var _render_t_valid: bool = false
## Per-frame diagnostics for the frame just drawn (remote): which branch drew it and what it
## spanned. OFF by default — it would build a Dictionary per remote entity per tick; the remote
## playtest switches it on for the entity it watches, to explain any discontinuity it measures.
var diagnostics_enabled: bool = false
var _frame_diag: Dictionary = {}

# --- LOCAL_PREDICTED ----------------------------------------------------------------------
## What this client believes, ahead of any server confirmation. The body sits exactly here.
var _predicted: MovementState = null
## seq -> predicted state AFTER applying that frame. Keyed by the seq the server echoes back.
var _history: Dictionary[int, MovementState] = {}
## Frames the server has not acknowledged yet, oldest first. Replayed after a correction.
var _pending: Array[InputFrame] = []
## The server's correction epoch we have applied; stamped onto every frame we send. The server
## bumps it when it overrides us, and consumes frames from an older epoch without moving —
## that is what stops our in-flight frames dragging it back to the path it just rejected.
var _epoch: int = 0
## Frames at or below this seq were sent under an old epoch. The server consumed them without
## moving, so rows acknowledging them carry nothing to reconcile against.
var _epoch_floor_seq: int = 0
var _newest_seq: int = 0
## Where the VISUAL is drawn relative to the body, decaying to zero. Corrections move the body
## at once (it is the simulation) and let the visual catch up, so a correction is a glide rather
## than a pop. Applied to the `Visual` node and the camera pivot; never to the body.
var _visual_offset: Vector3 = Vector3.ZERO
var _offset_decay_per_sec: float = 0.0
var _reconcile_count: int = 0
var _snap_count: int = 0
var _last_error: float = 0.0
## Predicted discrete events the server has not acknowledged yet: [{seq: int, kind: StringName}].
## For the LOCAL entity, events come from the prediction (instant) rather than from rows (which
## arrive a round trip later — at 200 ms, a jump sound 200 ms after the jump).
var _pending_events: Array[Dictionary] = []

## Rows arrive whenever the network delivers them, which is not a physics tick. Everything that
## moves the body is deferred to the next tick (`apply_pending_rows`): with physics
## interpolation on, a transform changed between ticks is drawn as a smear. Only the newest row
## matters — it acknowledges everything before it — but teleport flags are OR-ed so one cannot
## be lost when two rows land in the same frame.
var _row_queued: bool = false
var _q_state: MovementState = null
var _q_lps: int = 0
var _q_epoch: int = 0
var _q_teleport: bool = false
## REMOTE: a teleport arrived; reset interpolation on the tick that draws it.
var _snap_render: bool = false

## Test seam. Empty in production, where the clock is `ClockSync`. Set to a Callable returning
## microseconds to drive interpolation deterministically.
var _clock_override: Callable = Callable()


func required_tables() -> Array[StringName]:
	# The mode is chosen in `SpaceTimeEntity._finish_bind()`, which runs AFTER routing is set up,
	# so this cannot ask `mode`. It asks the same question the entity will: is this an authority?
	if is_authority_process():
		return [TABLE, INPUT_TABLE]
	return [TABLE]


## `input_queue` is a collection, and an entity nobody is driving legitimately has no rows in it.
## Without this, every spawn in the sidecar would sit out its whole bind timeout (DECISIONS #69).
func optional_tables() -> Array[StringName]:
	return [INPUT_TABLE]


## True when this process simulates worlds instead of watching one. Set by the NetConfig the
## sidecar connects with; false everywhere a player runs.
static func is_authority_process() -> bool:
	return SpaceTimeSync.config != null and SpaceTimeSync.config.authority_process


# --- read API ------------------------------------------------------------------------

## What the entity is being drawn at right now. For remote entities this is the interpolated
## value, which deliberately lags the authoritative one.
func get_render_state() -> MovementState:
	return _render


## The newest state the server sent. Gameplay questions ("where is it really?") ask this.
func get_authoritative_state() -> MovementState:
	return _auth


## World-space offset of the visual from the body. Zero except while gliding out a correction.
func get_visual_offset() -> Vector3:
	return _visual_offset


## LOCAL_PREDICTED only. Null in the passive modes.
func get_predicted_state() -> MovementState:
	return _predicted


func snapshot_count() -> int:
	return _ring.size()


## The server's acknowledgement of our input stream. 0 until the first row arrives.
func get_last_processed_seq() -> int:
	return _last_processed_seq


## LOCAL_PREDICTED: inputs sent but not yet acknowledged. Roughly round-trip ÷ 16 ms.
func pending_count() -> int:
	return _pending.size()


func get_epoch() -> int:
	return _epoch


## Debug/telemetry: how many corrections, how many of them snapped, and the last error.
func get_reconcile_stats() -> Dictionary:
	return {"reconciles": _reconcile_count, "snaps": _snap_count, "last_error": _last_error}


## REMOTE: the delay this entity is currently rendered behind the server, in seconds.
func get_interp_delay_sec() -> float:
	return _interp_delay_sec()


## REMOTE: what is left of a rejoin glide (world space). Zero unless the buffer just ran dry.
func get_remote_offset() -> Vector3:
	return _remote_offset


## REMOTE: how the last frame was drawn — branch, render time, delay, the snapshot span.
func get_frame_diagnostics() -> Dictionary:
	return _frame_diag


## REMOTE: the buffered snapshots, [[t_usec, pos, vel], ...]. Diagnostics only.
func get_snapshot_dump() -> Array:
	var out: Array = []
	for e: Dictionary in _ring:
		var st: MovementState = e["state"]
		out.append([int(e["t"]), st.pos, st.vel])
	return out


## REMOTE telemetry: {extrapolated_frames, dry_events}. A dry event is the buffer running out,
## the entity being projected forward on its last velocity until the next snapshot arrived.
func get_interp_stats() -> Dictionary:
	return {"extrapolated_frames": _extrapolated_frames, "dry_events": _dry_events}


# --- LOCAL_PREDICTED: driving ----------------------------------------------------------

## Drive the local player. `LocalInputComponent` calls this once per physics tick.
##
## Runs the SHARED model — the same `MovementModel` the sidecar runs — then resolves collision
## against the real level with `move_and_slide`. Stamps the frame with our correction epoch and
## with where it put us (`client_pos`, the Tier A claim), and remembers the result by seq.
func push_input(frame: InputFrame) -> void:
	assert(mode == Mode.LOCAL_PREDICTED,
		"push_input is only valid in LOCAL_PREDICTED; this component is in mode %d" % mode)
	if mode != Mode.LOCAL_PREDICTED:
		return
	if _predicted == null:
		_predicted = _auth.duplicate() if _auth != null else MovementState.new()
	var before: MovementState = _predicted
	_predicted = _step(_predicted, frame)
	frame.epoch = _epoch
	frame.client_pos = _predicted.pos
	frame.move_state = _predicted.move_state
	_emit_predicted(before, _predicted, frame.seq)
	_history[frame.seq] = _predicted
	_pending.append(frame)
	_newest_seq = frame.seq
	_trim_prediction_buffers()
	_set_render(_predicted)
	predicted_state_changed.emit(_predicted)


## A submit_input call failed (disconnect, timeout). Those frames never reached the server, so
## there is nothing to compare them against: forget them. The positions we reported AFTER them
## are absolute, so the server simply takes up from the next frame it does receive.
func on_input_batch_failed(seq_from: int, seq_to: int) -> void:
	var kept: Array[InputFrame] = []
	for f: InputFrame in _pending:
		if f.seq < seq_from or f.seq > seq_to:
			kept.append(f)
		else:
			_history.erase(f.seq)
	_pending = kept


## One predicted step. Yaw follows the look direction, exactly as the module sets it from the
## frame, so a replayed history and the server agree about facing as well as position.
func _step(from: MovementState, frame: InputFrame) -> MovementState:
	# A resolver means "there is a world": the model then lets move_and_slide decide the ground
	# (DECISIONS #80). With no body in a world to resolve against, pass none, and the model uses
	# its flat ground plane — exactly what it does in the golden harness.
	var b: CharacterBody3D = entity.body if entity != null else null
	var resolver: Callable = _resolve_with_body if b != null and b.is_inside_tree() else Callable()
	var next: MovementState = MovementModel.simulate(from, frame, _config(), _dt(), resolver)
	# Facing follows the camera only while there is movement input: a body that turns while you
	# stand still pirouettes as you look around. The exception is AIMING (`frame.face`): a cast
	# thrown behind you has to be thrown by someone facing that way. `module.rs` applies the same
	# rule to the same frame, so the two never disagree (DECISIONS #100, #136).
	if frame.face or frame.move_dir.length_squared() > 0.0:
		next.yaw = frame.look_yaw
	return next


## Collision resolver handed to the model. Client and sidecar both pass a CharacterBody3D-backed
## one, which is what makes their results agree (ARCHITECTURE §6).
func _resolve_with_body(prev: MovementState, next: MovementState) -> MovementState:
	var b: CharacterBody3D = entity.body if entity != null else null
	if b == null or not b.is_inside_tree():
		return next
	# move_and_slide() takes its timestep from WHERE it is called: the physics step inside a
	# physics frame, the RENDER frame's delta anywhere else. Called outside, a jump from a slow
	# frame moved the body a metre in one step. Every caller here runs in the physics tick
	# (input sampling, and corrections deferred to it); anything else is a bug, so say so.
	if not Engine.is_in_physics_frame():
		push_error("SpaceTimeMovementComponent: collision resolved outside a physics frame; "
			+ "move_and_slide would use the render delta. Call push_input from _physics_process.")
	b.floor_max_angle = deg_to_rad(_config().max_slope_deg)
	b.global_position = prev.pos
	b.velocity = next.vel
	b.move_and_slide()
	var out: MovementState = next.duplicate()
	out.pos = b.global_position
	out.vel = b.velocity
	# The floor is whatever move_and_slide stood us on. No `ground_y` fallback: that tolerance
	# band is exactly where the body used to hover (DECISIONS #80).
	out.grounded = b.is_on_floor()
	return out


## Queue one `input_queue` row, keeping the queue ascending by seq. Rows arrive in insert order
## in practice, but a subscription applying mid-tick can deliver a backlog in any order, and
## replaying frames out of order simulates a different path than the client walked.
func _enqueue_input(row: RefCounted) -> void:
	var frame: InputFrame = InputFrame.from_row(row.get(&"frame"))
	if frame.seq <= _sim_seq:
		return
	var i: int = _queue.size()
	while i > 0 and _queue[i - 1].seq > frame.seq:
		i -= 1
	if i > 0 and _queue[i - 1].seq == frame.seq:
		return   # already queued
	_queue.insert(i, frame)


## Whatever is already in the cache for this entity. `bind()` hands over one row per table, so
## without this a sidecar taking over a world would start from the newest queued frame and throw
## the rest of the backlog away. Same shape as the inventory component's cold start.
func _load_input_backlog() -> void:
	var tbl: Object = SpaceTimeSync.get_table(INPUT_TABLE)
	if tbl == null or not tbl.has_method(&"find_by_entity_id"):
		return   # no SDK (unit tests) or no index — rows still arrive by event
	var rows: Variant = tbl.call(&"find_by_entity_id", entity_id)
	if not (rows is Array):
		return
	for row: RefCounted in rows:
		_enqueue_input(row)


func _config() -> MovementConfig:
	if config == null:
		config = MovementConfig.shared()
	return config


func _dt() -> float:
	return 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))


func _trim_prediction_buffers() -> void:
	while _pending.size() > MAX_HISTORY:
		_pending.pop_front()
	if _history.size() > MAX_HISTORY:
		var floor_seq: int = _newest_seq - MAX_HISTORY
		for s: int in _history.keys():
			if s <= floor_seq:
				_history.erase(s)


# --- SERVER_AUTHORITY: being the server ------------------------------------------------

## The state this process has simulated for the entity, which is what the database will be told.
func get_authority_state() -> MovementState:
	return _sim


## How many frames are waiting to be simulated. Telemetry; the sidecar reports the worst one.
func authority_backlog() -> int:
	return _queue.size()


## The highest input seq folded into the simulated state. What the next write will acknowledge.
func authority_seq() -> int:
	return _sim_seq


## SERVER_AUTHORITY: hand the simulation a frame from something other than a client's queue — an
## NPC brain. The frame is numbered and queued exactly as a player's would be, so NPCs and
## players are moved by the same code down to the seq bookkeeping (`docs/SIDECAR_SPEC.md` §3);
## a brain that produced positions instead would be a second motion implementation.
##
## Seqs are assigned here rather than by the brain: an NPC has no client to number its frames,
## and `last_processed_seq` still has to advance monotonically on the wire.
func push_authority_input(frame: InputFrame) -> void:
	if mode != Mode.SERVER_AUTHORITY:
		push_error("push_authority_input is only valid in SERVER_AUTHORITY (mode %d)" % mode)
		return
	var highest: int = _queue[_queue.size() - 1].seq if not _queue.is_empty() else _sim_seq
	frame.seq = highest + 1
	_queue.append(frame)


## The write this entity owed was not accepted. Owe it again.
##
## `take_authority_write()` clears the flag optimistically, which is right for the common case
## and silently wrong for the other one: an entity that has stopped moving never becomes dirty
## again, so a single refused write leaves the database holding a stale row indefinitely. A
## sidecar that starts before it has been registered as an authority does exactly that, and the
## only symptom is an entity frozen where it was when the process came up.
func mark_authority_dirty() -> void:
	if mode == Mode.SERVER_AUTHORITY:
		_sim_dirty = true


## The write this entity owes the database, or an EMPTY dictionary when its state has not moved
## since the last one. Clears the dirty flag, so the caller must actually send what it takes.
##
## Keys match `MovementWrite` in `server/src/module.rs` field for field; `AuthoritySync` batches
## a world's worth into one `write_movement_batch` per server tick.
func take_authority_write() -> Dictionary:
	if mode != Mode.SERVER_AUTHORITY or _sim == null or not _sim_dirty:
		return {}
	_sim_dirty = false
	var teleport: bool = _sim_teleport
	_sim_teleport = false
	return {
		"entity_id": entity_id,
		"pos": _sim.pos,
		"vel": _sim.vel,
		"yaw": _sim.yaw,
		"grounded": _sim.grounded,
		"move_state": _sim.move_state,
		"last_processed_seq": _sim_seq,
		"teleport_flag": teleport,
	}


## One authoritative tick, at the physics rate. The sidecar IS the server for this entity: it
## replays the client's own frames through the SAME `MovementModel` the client predicted with and
## the SAME `move_and_slide` resolver, which is the whole reason the two agree (ARCHITECTURE §6).
func _step_authority() -> void:
	if _sim == null:
		return
	if _queue.size() > MAX_CATCHUP_FRAMES:
		_queue = _queue.slice(_queue.size() - MAX_CATCHUP_FRAMES)
		_sim_teleport = true   # we skipped part of this client's history; say so rather than lie
	var ran: int = 0
	while ran < MAX_CATCHUP_FRAMES and not _queue.is_empty():
		var frame: InputFrame = _queue.pop_front()
		if frame.seq <= _sim_seq:
			continue   # already folded in: a duplicate row, or a replay
		_sim = _step(_sim, frame)
		_sim_seq = frame.seq
		ran += 1
	if ran == 0:
		# Nobody drove this entity this tick. Gravity and friction still have to act, or a player
		# who stops sending input hangs in the air exactly where they let go. An entity that is
		# already still is left alone: simulating it would write a row per tick for every idle
		# player in the world.
		if _sim_verified and _sim.grounded and _sim.vel.length_squared() <= 0.0:
			return
		_sim = _step(_sim, InputFrame.new())
		_sim_verified = true
	_sim_dirty = true
	_set_render(_sim)


## Adopt a row we did not write. Another authority (an admin teleport, a session move) can
## reposition an entity this process owns, and it has to win: we are authoritative over its
## MOTION, not over where the game decides it belongs.
func _adopt_authority_row(state: MovementState, lps: int, teleport: bool) -> void:
	if not teleport:
		return   # an ordinary row: our own write echoed back. We are the authority on its motion.
	# A teleport row is either the echo of one we asked for or somebody else moving the entity out
	# from under us. POSITION tells them apart and needs no bookkeeping: our own echo says where we
	# already are. Tracking "a bump is owed to me" instead looked tidier and was wrong — a genuine
	# teleport arriving before our echo was swallowed by it.
	if _sim != null and state.pos.distance_squared_to(_sim.pos) < ADOPT_EPSILON_SQ:
		return
	_sim = state.duplicate()
	_sim_seq = maxi(_sim_seq, lps)
	_sim_verified = false   # the new position is a claim like any other until we have stepped it
	_queue.clear()   # frames from before a teleport describe a place the entity no longer is
	_sim_dirty = false
	_set_render(_sim)


# --- row handling --------------------------------------------------------------------

func _on_bound() -> void:
	if mode == Mode.SERVER_AUTHORITY:
		# Current truth is whatever the database says; we take over from there. On a cold start
		# that is where the world was when the last authority stopped (SIDECAR_SPEC §3).
		_sim = _auth.duplicate() if _auth != null else MovementState.new()
		_sim_seq = _last_processed_seq
		_sim_verified = false
		_load_input_backlog()
	if mode == Mode.LOCAL_PREDICTED and _auth != null:
		_predicted = _auth.duplicate()
	# Start where the server says, rather than at the origin for one frame.
	if _auth != null:
		_set_render(_auth.duplicate())
		_reset_interpolation()


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table == INPUT_TABLE:
		# Deletes arrive too: `write_movement_batch` prunes the rows we told it we had consumed.
		# Those are already folded into `_sim`, so there is nothing to undo.
		if new != null and mode == Mode.SERVER_AUTHORITY:
			_enqueue_input(new)
		return
	if table != TABLE:
		return
	if new == null:
		# Row gone: the entity is despawning. Leave the last render state alone.
		return

	var state: MovementState = MovementState.from_row(new)
	var t: int = int(new.get(&"server_ts"))
	var teleport: bool = bool(new.get(&"teleport_flag"))
	var lps: int = int(new.get(&"last_processed_seq"))
	var row_epoch: int = int(new.get(&"correction_epoch")) if new.get(&"correction_epoch") != null else 0
	var world: int = int(new.get(&"world_id")) if new.get(&"world_id") != null else 0

	var prev: MovementState = _auth
	var first: bool = prev == null
	_auth = state
	_auth_usec = t
	_last_processed_seq = lps
	if mode == Mode.SERVER_AUTHORITY:
		# We wrote most of these rows; the interesting case is the one we did not.
		_adopt_authority_row(state, lps, teleport)
		return
	if mode != Mode.LOCAL_PREDICTED:
		t = _timeline_t(lps, t)

	if mode == Mode.LOCAL_PREDICTED:
		if first or _predicted == null:
			# The row that exists at bind is where we start, and whatever epoch it carries is
			# the one our first frame must claim. `_on_bound` places the body.
			_epoch = row_epoch
			_predicted = state.duplicate()
		else:
			_row_queued = true
			_q_state = state
			_q_lps = lps
			_q_epoch = row_epoch
			_q_teleport = _q_teleport or teleport
		# No `_detect_transitions` here: the local entity's events come from the prediction,
		# a round trip before these rows could report them.
		return

	# A different world is a different place: nothing buffered from the old one is a path.
	if world != _world_id_seen:
		_world_id_seen = world
		if not first:
			_ring.clear()
			teleport = true

	if teleport:
		# Everything buffered describes a path the entity did not take. Drop it and snap, or
		# the entity would smoothly glide across the map to its new position. The next tick
		# draws it there (holding the only snapshot left) and resets interpolation.
		_ring.clear()
		_push_snapshot(t, state)
		_snap_render = true
		_remote_offset = Vector3.ZERO
		_blend_active = false
		_drawn_valid = false
		if not first:
			SignalBus.entity_teleported.emit(entity_id)
	else:
		_push_snapshot(t, state)

	_detect_transitions(prev, state)


## Place a row on this entity's timeline and learn how that timeline lines up with our clock.
func _timeline_t(lps: int, server_ts: int) -> int:
	var t: int
	if _tl_last_lps < 0:
		t = server_ts                                          # anchor
	elif lps > _tl_last_lps:
		t = _tl_last_t + (lps - _tl_last_lps) * _seq_usec()   # the client's own 60 Hz
	else:
		# Nobody is driving it: an exact shift of server time, so even an out-of-order row
		# (impossible on this transport, but cheap to get right) sorts into place.
		t = _tl_last_t + (server_ts - _tl_last_server_ts)
	_tl_last_t = t
	_tl_last_lps = lps
	_tl_last_server_ts = server_ts

	var sample: float = float(t - _physics_clock_usec())
	if not _tl_has_offset or absf(sample - _tl_offset_usec) > TIMELINE_DISCONTINUITY_USEC:
		_tl_offset_usec = sample
		_tl_has_offset = true
	else:
		var dev: float = sample - _tl_offset_usec
		# Slow on purpose: every change to the offset shifts render time, and render time must
		# glide. 5% of a 30 ms deviation is 1.5 ms — under a centimetre at a run.
		_tl_offset_usec += dev * 0.05
		_tl_jitter_usec = lerpf(_tl_jitter_usec, absf(dev), 0.05)
	return t


func _seq_usec() -> int:
	return 1_000_000 / int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))


## GAME time, advancing exactly one step per physics tick. Render time must come from this, not
## the wall clock: Godot runs physics as a fixed-step accumulator, so a rendered frame may run
## two ticks back to back or none, and consecutive ticks can be 0 ms or 33 ms apart in wall
## time. Sampled at those instants, the wall clock drew one tick with no motion and the next
## with double — a lurch of exactly one frame's travel — and physics interpolation then renders
## that unevenness faithfully at the display's rate.
func _physics_clock_usec() -> int:
	return Engine.get_physics_frames() * _seq_usec()


## PHASE4_SPEC §1, with the correction-epoch protocol (DECISIONS #71).
func _reconcile(state: MovementState, lps: int, row_epoch: int, teleport: bool) -> void:
	var cfg: MovementConfig = _config()

	# --- the server OVERRODE us: teleport, speed clamp, a correction ----------------------
	# Every frame produced so far went out under the old epoch; the server consumes those without
	# moving and will never acknowledge them against anything. Rows for them are skipped via
	# `_epoch_floor_seq`.
	#
	# A TELEPORT drops them: the old inputs belong to a place we have left. Any other override
	# REPLAYS them from the corrected state, keeping our motion — dropping them made a correction
	# while walking cost a whole round trip of movement, which at 150 ms popped instead of
	# gliding. The server grants the first frame of the new epoch a budget for exactly this
	# replay, bounded by real elapsed time (DECISIONS #72).
	if row_epoch != _epoch:
		_epoch = row_epoch
		_epoch_floor_seq = _newest_seq
		_history.clear()
		var drawn_at: Vector3 = _predicted.pos + _visual_offset
		_predicted = state.duplicate()
		if teleport:
			_pending.clear()
			_revoke_events_after(-1)   # everything predicted belongs to the place we left
		else:
			while not _pending.is_empty() and _pending[0].seq <= lps:
				_pending.pop_front()
			_predicted = _replay_pending(_predicted, lps, false)
			_pending.clear()   # all old-epoch; nothing left to acknowledge
		_set_render(_predicted)
		var err: float = drawn_at.distance_to(_predicted.pos)
		_last_error = err
		_reconcile_count += 1
		if teleport or err >= cfg.reconcile_snap_threshold:
			_snap_count += 1
			_set_visual_offset(Vector3.ZERO)
			_reset_interpolation()
			if teleport:
				SignalBus.entity_teleported.emit(entity_id)
		else:
			_set_visual_offset(drawn_at - _predicted.pos)
		reconciled.emit(err)
		return

	# --- an ordinary acknowledgement ----------------------------------------------------
	while not _pending.is_empty() and _pending[0].seq <= lps:
		_pending.pop_front()
	while not _pending_events.is_empty() and int(_pending_events[0]["seq"]) <= lps:
		_pending_events.pop_front()   # confirmed: the server has processed the input that caused it
	if lps <= _epoch_floor_seq:
		return   # acknowledges a frame from before our last override; nothing to compare
	var hist: MovementState = _history.get(lps, null)
	for s: int in _history.keys():
		if s <= lps:
			_history.erase(s)
	if hist == null:
		return   # evicted (a very long stall) or never predicted; the next row will do

	var error: float = hist.pos.distance_to(state.pos)
	if error < cfg.reconcile_accept_epsilon:
		return

	_last_error = error
	_reconcile_count += 1
	var drawn: Vector3 = _predicted.pos + _visual_offset
	if error >= cfg.reconcile_snap_threshold:
		_snap_count += 1
		_predicted = state.duplicate()
		_pending.clear()
		_history.clear()
		_revoke_events_after(lps)
		_set_render(_predicted)
		_set_visual_offset(Vector3.ZERO)
		_reset_interpolation()
		reconciled.emit(error)
		return

	# Smooth band: rewind to the server's state and replay what it has not seen yet. The body
	# jumps to the corrected present; the visual glides there from where it was drawn.
	_predicted = _replay_pending(state.duplicate(), lps, true)
	_set_render(_predicted)
	_set_visual_offset(drawn - _predicted.pos)
	reconciled.emit(error)


## Re-simulate every pending input from `from`, and reconcile the predicted EVENTS with what the
## replay says happened: an event the corrected path no longer contains is revoked, one it
## newly contains is announced now (late, but true).
func _replay_pending(from: MovementState, after_seq: int, keep_history: bool) -> MovementState:
	var s: MovementState = from
	var replayed: Array[Dictionary] = []
	for f: InputFrame in _pending:
		var before: MovementState = s
		s = _step(s, f)
		if keep_history:
			_history[f.seq] = s
		for kind: StringName in _discrete_events(before, s):
			replayed.append({"seq": f.seq, "kind": kind, "before": before, "after": s})
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _pending_events:
		if int(ev["seq"]) <= after_seq:
			kept.append(ev)   # older than the correction: not in question
			continue
		var still: bool = false
		for r: Dictionary in replayed:
			if int(r["seq"]) == int(ev["seq"]) and r["kind"] == ev["kind"]:
				still = true
		if still:
			kept.append(ev)
		else:
			event_revoked.emit(ev["kind"], int(ev["seq"]))
	for r: Dictionary in replayed:
		var known: bool = false
		for ev: Dictionary in kept:
			if int(ev["seq"]) == int(r["seq"]) and ev["kind"] == r["kind"]:
				known = true
		if not known:
			_announce(r["kind"], int(r["seq"]), r["before"], r["after"])
			kept.append({"seq": int(r["seq"]), "kind": r["kind"]})
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seq"]) < int(b["seq"]))
	_pending_events = kept
	return s


## Revoke every pending predicted event newer than `after_seq` (-1: all of them).
func _revoke_events_after(after_seq: int) -> void:
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _pending_events:
		if int(ev["seq"]) > after_seq:
			event_revoked.emit(ev["kind"], int(ev["seq"]))
		else:
			kept.append(ev)
	_pending_events = kept


## The discrete events between two consecutive states.
static func _discrete_events(prev: MovementState, cur: MovementState) -> Array[StringName]:
	var out: Array[StringName] = []
	if prev.grounded and not cur.grounded and cur.vel.y > 0.0:
		out.append(&"jumped")
	elif not prev.grounded and cur.grounded:
		out.append(&"landed")
	return out


## LOCAL: fire events straight from a predicted step, and remember them until acknowledged.
func _emit_predicted(prev: MovementState, cur: MovementState, seq: int) -> void:
	for kind: StringName in _discrete_events(prev, cur):
		_announce(kind, seq, prev, cur)
		_pending_events.append({"seq": seq, "kind": kind})
	if prev.move_state != cur.move_state:
		move_state_changed.emit(prev.move_state, cur.move_state)


func _announce(kind: StringName, seq: int, prev: MovementState, _cur: MovementState) -> void:
	if kind == &"jumped":
		jumped.emit()
		SignalBus.entity_jumped.emit(entity_id)
	elif kind == &"landed":
		var impact: float = absf(prev.vel.y)
		landed.emit(impact)
		SignalBus.entity_landed.emit(entity_id, impact)
	event_predicted.emit(kind, seq)


func _set_visual_offset(offset: Vector3) -> void:
	_visual_offset = offset
	var smooth: float = maxf(0.001, _config().reconcile_smooth_time)
	# Linear, so the glide is DONE after `reconcile_smooth_time` (PHASE4_SPEC §1 test b).
	_offset_decay_per_sec = offset.length() / smooth
	_apply_visual_offset()


## Discrete events, read off consecutive authoritative rows.
func _detect_transitions(prev: MovementState, cur: MovementState) -> void:
	if prev == null:
		return   # first row is initial state, not a transition
	if prev.grounded and not cur.grounded:
		# Leaving the ground upward is a jump; leaving it downward is walking off a ledge.
		if cur.vel.y > 0.0:
			jumped.emit()
			SignalBus.entity_jumped.emit(entity_id)
	elif not prev.grounded and cur.grounded:
		# Impact speed is how fast it was falling on the frame BEFORE touchdown; by the time
		# the server reports grounded it has already zeroed the vertical velocity.
		var impact: float = absf(prev.vel.y)
		landed.emit(impact)
		SignalBus.entity_landed.emit(entity_id, impact)
	if prev.move_state != cur.move_state:
		move_state_changed.emit(prev.move_state, cur.move_state)


## Insert keeping `_ring` ascending by timestamp. Out-of-order arrivals are placed correctly
## and a repeat of a timestamp replaces it, so a retransmit cannot create a duplicate sample
## that the interpolator would see as a zero-length span.
func _push_snapshot(t: int, state: MovementState) -> void:
	if not _ring.is_empty():
		var gap: int = t - int(_ring[_ring.size() - 1]["t"])
		if gap > 0 and gap <= TIMELINE_DISCONTINUITY_USEC:
			_snapshot_interval_usec = float(gap) if _snapshot_interval_usec == 0.0 \
				else lerpf(_snapshot_interval_usec, float(gap), 0.1)
	var i: int = _ring.size() - 1
	while i >= 0 and int(_ring[i]["t"]) > t:
		i -= 1
	if i >= 0 and int(_ring[i]["t"]) == t:
		_ring[i]["state"] = state
	else:
		_ring.insert(i + 1, {"t": t, "state": state})
	while _ring.size() > RING_SIZE:
		_ring.pop_front()


# --- view ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_bound():
		return
	if mode == Mode.SERVER_AUTHORITY:
		_step_authority()
		return
	apply_pending_rows()
	update_view()
	_decay_visual_offset(delta)


## Apply the newest row that arrived since the last tick. Runs at the top of the physics tick —
## this component sits above `LocalInputComponent` under `Components/`, so a correction lands
## before the next input is predicted on top of it. Public so tests can step it without frames.
func apply_pending_rows() -> void:
	if not _row_queued or mode != Mode.LOCAL_PREDICTED:
		return
	_row_queued = false
	var tp: bool = _q_teleport
	_q_teleport = false
	_reconcile(_q_state, _q_lps, _q_epoch, tp)


## Recompute the rendered state. Separated from `_physics_process` so tests can step it
## deterministically instead of waiting on frames.
func update_view() -> void:
	match mode:
		Mode.LOCAL_PREDICTED:
			pass   # driven by push_input, not by the clock
		Mode.REMOTE_INTERPOLATED:
			_update_interpolated()
			if _snap_render:
				_snap_render = false
				_reset_interpolation()
		Mode.SERVER_DRIVEN:
			if _auth != null:
				_set_render(_auth.duplicate())
		Mode.SERVER_AUTHORITY:
			if _sim != null:
				_set_render(_sim)   # what we simulated IS the truth here; nothing to interpolate
		_:
			pass


## Linear decay of the correction glide. Public for tests that step it without frames.
func _decay_visual_offset(delta: float) -> void:
	if _visual_offset == Vector3.ZERO:
		return
	_visual_offset = _visual_offset.move_toward(Vector3.ZERO, _offset_decay_per_sec * delta)
	if _visual_offset.length() < OFFSET_EPSILON:
		_visual_offset = Vector3.ZERO
	_apply_visual_offset()


func _update_interpolated() -> void:
	if _ring.is_empty():
		return
	var render_t: int = _render_time_usec()
	var oldest: Dictionary = _ring[0]
	var newest: Dictionary = _ring[_ring.size() - 1]
	if diagnostics_enabled:
		_frame_diag = {"render_t": render_t, "delay_ms": _interp_delay_sec() * 1000.0,
			"newest_ahead_ms": float(int(newest["t"]) - render_t) / 1000.0, "branch": "", "span_ms": 0.0,
			"blending": _blend_active}

	# Behind the buffer: we have no history that old. Hold the oldest we do have.
	if render_t <= int(oldest["t"]):
		if diagnostics_enabled:
			_frame_diag["branch"] = "hold-oldest"
		_draw_remote((oldest["state"] as MovementState).duplicate(), false)
		return

	# Ahead of the buffer: project with the last known velocity, but only briefly.
	if render_t >= int(newest["t"]):
		if diagnostics_enabled:
			_frame_diag["branch"] = "extrapolate"
		_extrapolated_frames += 1
		if not _was_dry:
			_dry_events += 1
		_was_dry = true
		var dt_usec: int = mini(render_t - int(newest["t"]), MAX_EXTRAPOLATION_USEC)
		var s: MovementState = (newest["state"] as MovementState).duplicate()
		s.pos = s.pos + s.vel * (float(dt_usec) / 1_000_000.0)
		_draw_remote(s, false)
		return

	var rejoining: bool = _was_dry
	_was_dry = false
	for i: int in range(_ring.size() - 1):
		var a: Dictionary = _ring[i]
		var b: Dictionary = _ring[i + 1]
		var ta: int = int(a["t"])
		var tb: int = int(b["t"])
		if render_t < ta or render_t > tb:
			continue
		var span: int = tb - ta
		var f: float = 0.0 if span <= 0 else float(render_t - ta) / float(span)
		if diagnostics_enabled:
			_frame_diag["branch"] = "rejoin" if rejoining else ("blend" if _blend_active else "interp")
			_frame_diag["span_ms"] = float(span) / 1000.0
			_frame_diag["f"] = f
		var sa: MovementState = a["state"]
		var sb: MovementState = b["state"]
		var out: MovementState = MovementState.new()
		if span > 0 and span <= HERMITE_MAX_SPAN_USEC:
			var span_sec: float = float(span) / 1_000_000.0
			out.pos = _hermite(sa.pos, sa.vel * span_sec, sb.pos, sb.vel * span_sec, f)
		else:
			out.pos = sa.pos.lerp(sb.pos, f)
		out.vel = sa.vel.lerp(sb.vel, f)
		out.yaw = lerp_angle(sa.yaw, sb.yaw, f)
		# Discrete fields do not interpolate: hold the state we are travelling FROM.
		out.grounded = sa.grounded
		out.move_state = sa.move_state
		_draw_remote(out, rejoining)
		return


## Cubic Hermite between (p0, m0) and (p1, m1), tangents already scaled by the span.
static func _hermite(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, f: float) -> Vector3:
	var f2: float = f * f
	var f3: float = f2 * f
	return p0 * (2.0 * f3 - 3.0 * f2 + 1.0) + m0 * (f3 - 2.0 * f2 + f) 		+ p1 * (-2.0 * f3 + 3.0 * f2) + m1 * (f3 - f2)


## Draw a remote entity at `s` (its ideal position this frame), blending onto it after a dry
## spell instead of jumping.
func _draw_remote(s: MovementState, rejoining: bool) -> void:
	var dt: float = _dt()
	if rejoining and _drawn_valid:
		# Start from where we would have drawn it next, moving as it was moving.
		var v0: Vector3 = _drawn_step / dt
		var p0: Vector3 = _drawn_prev + _drawn_step
		var err: float = p0.distance_to(s.pos)
		var dv: float = (s.vel - v0).length()
		var need: float = maxf(sqrt(6.0 * err / REJOIN_MAX_ACCEL), 1.5 * dv / REJOIN_MAX_ACCEL)
		_blend_dur = clampf(need, REJOIN_MIN_SEC, REJOIN_MAX_SEC)
		_blend_p0 = p0
		_blend_v0 = v0
		_blend_tau = 0.0
		_blend_active = true
	var ideal: Vector3 = s.pos
	if _blend_active:
		var x: float = clampf(_blend_tau / _blend_dur, 0.0, 1.0)
		var w: float = x * x * (3.0 - 2.0 * x)
		s.pos = (_blend_p0 + _blend_v0 * _blend_tau).lerp(ideal, w)
		_blend_tau += dt
		if _blend_tau > _blend_dur:
			_blend_active = false
	_remote_offset = s.pos - ideal
	if _drawn_valid:
		_drawn_step = s.pos - _drawn_prev
	_drawn_prev = s.pos
	_drawn_valid = true
	_set_render(s)


## Put the body where a state says. The body is the simulation and always sits exactly at the
## state; any correction glide is `_visual_offset`, applied to the visual only.
func _set_render(s: MovementState) -> void:
	_render = s
	var b: CharacterBody3D = entity.body if entity != null else null
	if b == null:
		return
	if b.is_inside_tree():
		b.global_position = s.pos
	else:
		b.position = s.pos
	b.rotation.y = s.yaw
	_apply_visual_offset()


func _apply_visual_offset() -> void:
	var b: CharacterBody3D = entity.body if entity != null else null
	if b == null or not b.is_inside_tree():
		return
	var visual: Node3D = b.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.global_position = b.global_position + _visual_offset


## A discontinuity (spawn, teleport, snap) must not be smeared across frames by physics
## interpolation: without this, a 20 m teleport renders as a one-frame streak across the map.
func _reset_interpolation() -> void:
	var b: CharacterBody3D = entity.body if entity != null else null
	if b != null and b.is_inside_tree():
		b.reset_physics_interpolation()


## The instant on this entity's timeline to draw it at. Tests pinning the clock get the exact
## target; in play the clock is slewed so it can never jump (see RENDER_CLOCK_SLEW_USEC).
## Called once per physics tick, from update_view.
func _render_time_usec() -> int:
	var target: int = _server_usec() - int(_interp_delay_sec() * 1_000_000.0)
	if _clock_override.is_valid():
		return target
	var step: int = _seq_usec()
	if not _render_t_valid or absi(target - _render_t) > TIMELINE_DISCONTINUITY_USEC:
		_render_t = target   # first draw, or a real discontinuity: re-anchor
		_render_t_valid = true
		return _render_t
	_render_t += step + clampi(target - (_render_t + step), -RENDER_CLOCK_SLEW_USEC, RENDER_CLOCK_SLEW_USEC)
	return _render_t


## "Now" on this entity's timeline. Tests pin it with `_clock_override`.
func _server_usec() -> int:
	if _clock_override.is_valid():
		return int(_clock_override.call())
	if _tl_has_offset:
		return _physics_clock_usec() + int(_tl_offset_usec)
	return ClockSync.server_usec()


## PHASE4_SPEC §4: at least the configured delay; never less than 1.5 snapshot intervals; and
## enough to cover this entity's measured arrival jitter. Too little and render time outruns
## the newest sample, and the entity visibly stops and lurches between packets.
func _interp_delay_sec() -> float:
	var configured: float = config.remote_interp_delay if config != null else 0.1
	var interval: float = _snapshot_interval_usec / 1_000_000.0
	var jitter: float = _tl_jitter_usec / 1_000_000.0
	return minf(MAX_INTERP_DELAY_SEC, maxf(configured, maxf(1.5 * interval, interval + 3.0 * jitter)))
