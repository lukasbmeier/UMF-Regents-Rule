extends Node
## REMOTE SMOOTHNESS PLAYTEST: how one real client draws ANOTHER real client moving.
##
## Two processes, one scene, told apart by `--role=`:
##   walker    walks a square (hold forward, turn 90 degrees every 1.5 s), then teleports
##   observer  finds the walker's entity and records where it DRAWS it every physics frame
##
## The observer asserts what a player watching someone else would notice:
##   visible     the walker is seen to cover ground
##   continuous  no frame-to-frame change in motion bigger than walking can produce: no
##               lurches between packets, no stop-start where the buffer ran dry
##   no stalls   the drawn walker never freezes mid-walk while it is really moving
##   teleport    a teleport is ONE snap, announced with entity_teleported, not a glide across
##
## Driven by tests/remote_playtest.sh, which runs both at a chosen simulated latency. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 90.0
const STEP_TIMEOUT_SEC: float = 30.0
## Seconds the walker walks, and the length of each side of its square.
const WALK_SEC: float = 9.0
const SIDE_SEC: float = 1.5
## The walker's model accelerates at most 40 m/s^2: 0.011 m change in per-frame displacement.
## Interpolation between 20 Hz snapshots adds a kink at each sample; a stall or lurch between
## packets is several times larger. 0.05 m sits well above the first and well below the second.
const LURCH_EPS: float = 0.05

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "observer"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr("--role=".length())
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	if _role == "walker":
		await _walk(me)
	else:
		await _observe(me)
	_finish()


# --- walker ------------------------------------------------------------------------------

func _walk(me: SpaceTimeEntity) -> void:
	print("== remote playtest: WALKER (entity %d) ==" % me.entity_id)
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	# Start from open floor. Walking into a wall is a genuine instant stop, which the observer
	# rightly draws as a lurch: the first version turned on wall-clock timers from wherever it
	# spawned, drifted, and sometimes walked into the north wall — the netcode was blamed for a
	# collision it drew correctly. The square below (-Z, -X, +Z, +X from here, ~7.5 m a side)
	# stays inside x -8..-0.5, z 0.5..8: clear of every wall, ramp, step and the platform.
	var tp_seen: Array[bool] = [false]
	var tcb := func(eid: int) -> void:
		if eid == me.entity_id:
			tp_seen[0] = true
	SignalBus.entity_teleported.connect(tcb)
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(-0.5, 0.0, 8.0)], ["vector3[f32,f32,f32]"])
	var deadline: int = Time.get_ticks_msec() + 10_000
	while not tp_seen[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	SignalBus.entity_teleported.disconnect(tcb)
	# Give the observer time to connect and settle before there is anything to watch.
	await get_tree().create_timer(4.0).timeout
	# Sides counted in PHYSICS frames, so the route is the same every run.
	var side_frames: int = int(SIDE_SEC * 60.0)
	var yaw: float = 0.0
	input.set_look(yaw, 0.0)
	Input.action_press(&"move_forward")
	for side: int in range(int(WALK_SEC / SIDE_SEC)):
		for f: int in range(side_frames):
			await get_tree().physics_frame
		yaw = wrapf(yaw + PI * 0.5, -PI, PI)
		input.set_look(yaw, 0.0)
	Input.action_release(&"move_forward")
	await get_tree().create_timer(1.0).timeout
	# The observer's last check: a teleport arrives as one snap.
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(-6.0, 0.5, 6.0)], ["vector3[f32,f32,f32]"])
	await get_tree().create_timer(4.0).timeout
	_check(true, "walker finished its route")


# --- observer ----------------------------------------------------------------------------

func _observe(me: SpaceTimeEntity) -> void:
	print("== remote playtest: OBSERVER (entity %d, simulated latency %d ms) =="
		% [me.entity_id, SpaceTimeSync.get_simulated_latency().x])

	# The walker is whichever other player starts moving.
	var target: SpaceTimeEntity = null
	var mv: SpaceTimeMovementComponent = null
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	var starts: Dictionary[int, Vector3] = {}
	while target == null and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		for id: int in EntityRegistry.all_entity_ids():
			if id == me.entity_id:
				continue
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e == null or not e.is_bound() or e.definition == null or e.definition.kind != 0:
				continue
			var m: SpaceTimeMovementComponent = e.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
			if m == null:
				continue
			var p: Vector3 = m.get_render_state().pos
			if not starts.has(id):
				starts[id] = p
			elif p.distance_to(starts[id]) > 0.5:
				target = e
				mv = m
	_check(target != null, "the observer sees another player start to move")
	if target == null:
		return
	_check(mv.mode == SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED,
		"someone else's player is interpolated, not predicted")
	print("   watching entity %d" % target.entity_id)
	mv.diagnostics_enabled = true   # explain any lurch measured below
	# The same entity, animated: a remote character is driven by `move_state` and the mirrored
	# jump/land events alone (DECISIONS #94), which only a second real client can exercise.
	var anim: AnimationDriverComponent = target.find_component(
		AnimationDriverComponent) as AnimationDriverComponent
	var anim_peak: float = 0.0
	_check(anim != null and anim.is_animating(),
		"the other player is a rigged character with a live animation tree")

	var teleports: Array[int] = []
	SignalBus.entity_teleported.connect(func(eid: int) -> void:
		if eid == target.entity_id:
			teleports.append(Engine.get_physics_frames()))

	# Record the drawn position every physics frame until the walker's teleport lands.
	var trace: Array[Vector3] = []
	var frames_at: Array[int] = []
	var glide: Array[float] = []
	var seen_states: Array[int] = []
	var diags: Array[Dictionary] = []
	deadline = Time.get_ticks_msec() + int((WALK_SEC + 12.0) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		trace.append(mv.get_render_state().pos)
		frames_at.append(Engine.get_physics_frames())
		glide.append(mv.get_remote_offset().length())
		seen_states.append(mv.get_authoritative_state().move_state if mv.get_authoritative_state() != null else -1)
		if anim != null:
			anim_peak = maxf(anim_peak, anim.speed_blend())
		var dg2: Dictionary = mv.get_frame_diagnostics().duplicate()
		dg2["ring"] = mv.get_snapshot_dump()
		diags.append(dg2)
		if not teleports.is_empty() and Engine.get_physics_frames() > teleports[0] + 30:
			break

	# Analyse the WALK only: everything before the teleport.
	var walk_end: int = trace.size()
	if not teleports.is_empty():
		walk_end = frames_at.find(teleports[0])
		if walk_end < 0:
			walk_end = trace.size()
	var path: float = 0.0
	var lurches: int = 0
	var worst: float = 0.0
	var stalls: int = 0
	var moving_frames: int = 0
	for i: int in range(2, walk_end):
		var d1: Vector3 = trace[i - 1] - trace[i - 2]
		var d2: Vector3 = trace[i] - trace[i - 1]
		var h1: float = Vector2(d1.x, d1.z).length()
		var h2: float = Vector2(d2.x, d2.z).length()
		path += h2
		if h1 > 0.02:
			moving_frames += 1
			if h2 < 0.002:
				stalls += 1   # was walking last frame, frozen this frame
		var change: float = Vector2(d2.x - d1.x, d2.z - d1.z).length()
		if change > LURCH_EPS:
			lurches += 1
			worst = maxf(worst, change)
			print("   lurch at frame %d: change %.3f, glide offset %.3f -> %.3f, steps %.3f -> %.3f"
				% [i, change, glide[i - 1], glide[i], h1, h2])
			for k: int in range(maxi(0, i - 3), mini(diags.size(), i + 2)):
				var dg: Dictionary = diags[k]
				print("      frame %d: %s  render_t step %s  delay %.1f ms  newest ahead %.1f ms  span %.1f ms"
					% [k, dg.get("branch", "?"),
						str(int(dg.get("render_t", 0)) - int(diags[k - 1].get("render_t", 0))) if k > 0 else "-",
						float(dg.get("delay_ms", 0.0)), float(dg.get("newest_ahead_ms", 0.0)), float(dg.get("span_ms", 0.0))])
			var ring: Array = diags[i].get("ring", [])
			var rt: int = int(diags[i].get("render_t", 0))
			for e: Array in ring:
				var dt_ms: float = float(int(e[0]) - rt) / 1000.0
				if dt_ms > -150.0 and dt_ms < 120.0:
					print("      snapshot %+7.1f ms  pos (%.3f, %.3f)  vel (%.2f, %.2f)" % [dt_ms, (e[1] as Vector3).x, (e[1] as Vector3).z, (e[2] as Vector3).x, (e[2] as Vector3).z])
	print("   drew the walker covering %.2f m over %d frames (%d moving)" % [path, walk_end, moving_frames])
	var istats: Dictionary = mv.get_interp_stats()
	print("   lurches: %d (worst %.3f m/frame change); stalls mid-walk: %d; interp delay %.0f ms"
		% [lurches, worst, stalls, mv.get_interp_delay_sec() * 1000.0])
	print("   buffer ran dry %d times (%d frames extrapolated)"
		% [int(istats["dry_events"]), int(istats["extrapolated_frames"])])
	_check(path > 20.0, "the walker is seen to cover ground (%.2f m)" % path)
	_check(lurches == 0, "the remote walker is drawn continuously: no lurches (%d, worst %.3f)" % [lurches, worst])
	_check(stalls <= 1, "the remote walker never freezes mid-walk (%d stalls)" % stalls)

	# What the walker is DOING, as someone else sees it (PHASE4_SPEC §2.5). Tier A has no
	# simulation to decide it: the walker's model classifies each frame and the module mirrors
	# it. This is what a remote animation will play from.
	var walking: int = 0
	var idle_after: int = 0
	var moving_seen: int = 0
	for i: int in range(2, walk_end):
		var h: float = Vector2(trace[i].x - trace[i - 1].x, trace[i].z - trace[i - 1].z).length()
		if h > 0.05:
			moving_seen += 1
			if seen_states[i] == MovementState.Move.RUN:
				walking += 1
	for i: int in range(maxi(0, walk_end - 40), walk_end):
		if seen_states[i] == MovementState.Move.IDLE:
			idle_after += 1
	print("   remote move_state: RUN on %d of %d moving frames; IDLE in the last 40 before the teleport: %d"
		% [walking, moving_seen, idle_after])
	_check(moving_seen > 0 and walking >= int(0.9 * moving_seen),
		"the observer sees the walker as RUN while it runs (%d/%d)" % [walking, moving_seen])
	_check(idle_after > 0, "and as IDLE once it stops")
	if anim != null:
		print("   remote locomotion blend peaked at %.2f, state %s"
			% [anim_peak, anim.current_state()])
		_check(anim_peak > 0.3,
			"and animates it as walking, from those rows alone (blend %.2f)" % anim_peak)

	# The teleport: exactly one announcement, and one snap rather than a slide across the map.
	_check(teleports.size() == 1, "the walker's teleport is announced once (%d)" % teleports.size())
	if walk_end < trace.size() - 1:
		# The signal fires when the row is processed; the snap is drawn on the next physics
		# tick. Find the one big step in the few frames after the announcement.
		var jump: float = 0.0
		var jump_at: int = walk_end
		for i: int in range(maxi(1, walk_end), mini(trace.size(), walk_end + 6)):
			var step: float = trace[i].distance_to(trace[i - 1])
			if step > jump:
				jump = step
				jump_at = i
		var after: float = 0.0
		for i: int in range(jump_at + 1, trace.size()):
			after = maxf(after, trace[i].distance_to(trace[i - 1]))
		print("   teleport drawn as a %.2f m jump; largest step after it %.3f m" % [jump, after])
		_check(jump > 5.0, "the teleport is drawn as ONE snap (%.2f m in a single frame)" % jump)
		_check(after < 0.2, "after the teleport the walker is not sliding across the map (%.3f m)" % after)


# --- helpers -----------------------------------------------------------------------------

func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var id: int = EntityRegistry.local_entity_id
		if id >= 0:
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.is_bound():
				return e
		await get_tree().process_frame
	_check(false, "local player spawned and bound")
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: remote playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release(&"move_forward")
	print("\n%s: %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
