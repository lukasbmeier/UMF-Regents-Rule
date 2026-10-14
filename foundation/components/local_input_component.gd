class_name LocalInputComponent extends SpaceTimeComponent
## Samples local input into `InputFrame`s, once per physics tick, on the owning client only.
##
## Phase 3 SAMPLES ONLY. Nothing is sent and nothing moves: `input_sampled` is emitted for
## whoever wants it, and Phase 4 connects it to `SpaceTimeMovementComponent.push_input` and
## `SpaceTimeSync.submit_input`. Keeping sampling separate from sending means the frame shape,
## the sequence numbering and the camera-relative maths are all settled and tested before
## prediction starts depending on them.
##
## It is a `SpaceTimeComponent` with no required tables, so it lives under `Components/` and is
## bound like everything else — that is how it learns `entity` and `is_local_authority` without
## a second wiring path. `ARCHITECTURE` §3 draws it as a sibling `Input` node; being under
## `Components/` is the same thing with less machinery (DECISIONS #44).

## One sampled frame. Phase 4's listener is the movement component.
signal input_sampled(frame: InputFrame)

const ACTION_FORWARD: StringName = &"move_forward"
const ACTION_BACK: StringName = &"move_back"
const ACTION_LEFT: StringName = &"move_left"
const ACTION_RIGHT: StringName = &"move_right"
const ACTION_JUMP: StringName = &"jump"
const ACTION_SPRINT: StringName = &"sprint"
## Only matters when MovementConfig.dash_impulse > 0. Bound to Q here if the project has not
## mapped it, so turning dash on in the config is the only step a genre needs.
const ACTION_DASH: StringName = &"dash"
## Use the character's first ability (DECISIONS #226: the wolf's Pounce). The left mouse button.
const ACTION_ATTACK: StringName = &"attack"
## The slow-walk modifier: a plain key press RUNS (DECISIONS #100).
const ACTION_SLOW: StringName = &"move_slow"
## Held: the camera keeps turning but the character does not, so you can look around while
## running in a straight line. Movement stays relative to the BODY while it is held.
const ACTION_FREELOOK: StringName = &"camera_freelook"

@export var mouse_sensitivity: float = 0.003
## Multiplies mouse look. A genre that uses the mouse for something else for a while — winding a
## reel, steering a thrown thing — turns this down rather than taking the mouse away, and puts it
## back after. 1.0 is untouched; below 1 the camera rig also leaves the wheel alone.
var look_scale: float = 1.0
## Stops the camera going over the top. Degrees from horizontal.
@export var pitch_limit_deg: float = 89.0
## Ask `MouseCapture` for the cursor while this player is alive: mouse look needs it locked to
## the window. THE AUTOLOAD OWNS THE POLICY — Escape frees it, a click takes it back, losing
## focus hands it to the other window, and a display-less run never touches it at all. Turn
## this off for a genre that plays with a visible cursor (top-down, point and click); mouse
## look then reads raw motion the way it did before there was a capture policy.
@export var capture_mouse: bool = true
## Off in unit tests, which have no server.
@export var send_to_server: bool = true
## Frames per `submit_input` call. Matches `movement_config.json`'s input_batch_size.
@export var batch_size: int = 3

var _seq: int = 0
var _first_seq: int = 0
## Jump held off since a skill check came up, until the key is let go (DECISIONS #218).
var _jump_held_off: bool = false
## Frames still to press dash for (`dash_once`: an ability's lunge), and whether the dash key itself
## dashes (not for a character whose ability lunges: DECISIONS #232).
var _dash_frames: int = 0
var dash_key: bool = true
var _client_tick: int = 0
## Where the CAMERA looks. Mouse motion always moves this one.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Where the BODY is told to face: the camera's yaw, frozen while free look is held. This is
## what goes on the wire and what `move_dir` is relative to, so releasing free look does not
## teleport the character's heading.
var _body_yaw: float = 0.0
var _movement: SpaceTimeMovementComponent = null
## Frames sampled but not yet sent. Flushed in batches to keep reducer volume sane
## (DECISIONS #15: 60 Hz client, batch 3 → 20 calls/s per player).
var _outbox: Array[InputFrame] = []
## True while this component is the one holding MouseCapture's standing request.
var _wants_cursor: bool = false
## Why the body is being held facing the camera while it stands still (`hold_facing`). A set
## rather than a flag so two things aiming at once cannot switch each other off.
var _face_holds: Dictionary[StringName, bool] = {}
## Reasons the player is held still (`hold_still`): a page over the game (the lobby screen) that
## the movement keys must not walk them out from under.
var _still_holds: Dictionary[StringName, bool] = {}


## No tables: this component produces input, it does not mirror server state.
func required_tables() -> Array[StringName]:
	return []


## Required by the base contract even though `required_tables()` is empty, so this can never
## be called — the entity only routes tables a component asked for. Implemented rather than
## left abstract because `@abstract` on the base makes every subclass declare it.
func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	if not InputMap.has_action(ACTION_DASH):
		InputMap.add_action(ACTION_DASH)
		var q := InputEventKey.new()
		q.physical_keycode = KEY_Q
		InputMap.action_add_event(ACTION_DASH, q)
	if not InputMap.has_action(ACTION_ATTACK):
		InputMap.add_action(ACTION_ATTACK)
		var lmb := InputEventMouseButton.new()
		lmb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(ACTION_ATTACK, lmb)
	if not InputMap.has_action(ACTION_SLOW):
		InputMap.add_action(ACTION_SLOW)
		var ctrl := InputEventKey.new()
		ctrl.physical_keycode = KEY_CTRL
		InputMap.action_add_event(ACTION_SLOW, ctrl)
	dash_key = not lunges_by_ability((entity as SpaceTimeEntity).definition if entity is SpaceTimeEntity else null)
	# A remote entity's scene carries this component too; it just never runs.
	set_physics_process(is_local_authority)
	set_process_unhandled_input(is_local_authority)
	if not is_local_authority:
		return
	# Siblings are found through the entity, never by node path (ARCHITECTURE §3).
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null:
		_movement = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if _movement == null:
		push_warning("LocalInputComponent: no movement component on entity %d; input will be "
			% entity_id + "sampled and sent but nothing will move locally.")
	if capture_mouse:
		_wants_cursor = true
		MouseCapture.want_capture(true)


## A disconnect, a despawn or a scene change must give the cursor back, or the player is left
## with no pointer and no window to press Escape in.
func _exit_tree() -> void:
	if _wants_cursor:
		_wants_cursor = false
		MouseCapture.want_capture(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_authority:
		return
	if event.is_action_pressed(ACTION_ATTACK) and (not capture_mouse or MouseCapture.is_captured()) and not is_held_still():
		use_first_ability()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	# Only turn when the cursor is actually ours. Without this the view keeps swinging while
	# the pointer is free — over a menu, or on its way out of the window — which is the other
	# half of "the mouse is not captured": not just that it escapes, but that it still steers.
	if capture_mouse and not MouseCapture.is_captured():
		return
	if is_held_still():
		return
	# The player's own multiplier and inversion (Settings, DECISIONS #165) on top of the game's.
	var sens: float = mouse_sensitivity * look_scale * Settings.look_sensitivity()
	var up: float = -1.0 if Settings.invert_look() else 1.0
	_look_yaw = wrapf(_look_yaw - motion.relative.x * sens, -PI, PI)
	var limit: float = deg_to_rad(pitch_limit_deg)
	_look_pitch = clampf(_look_pitch - motion.relative.y * sens * up, -limit, limit)


## The character's first ability, used now, ahead in the way it faces: the predicted id, or -1 (it has
## none, it is cooling down).
func use_first_ability() -> int:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null or ent.definition == null or ent.definition.abilities.is_empty() or ent.definition.abilities[0] == null:
		return -1
	var act: SpaceTimeActionComponent = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	if act == null:
		return -1
	return act.request_use(ent.definition.abilities[0].id, 0, Vector3(-sin(_body_yaw), 0.0, -cos(_body_yaw)))


func _physics_process(_delta: float) -> void:
	# Not before it is bound and known to be this player's own: a bot's (a sidecar builds one from the
	# same scene) waited on its rows sampling a keyboard nobody has, an error a frame.
	if not is_local_authority:
		return
	sample()


# --- read / control ------------------------------------------------------------------

func get_look_yaw() -> float:
	return _look_yaw


func get_look_pitch() -> float:
	return _look_pitch


## Point the look angles somewhere without a mouse event. Used by tests, cutscenes and by
## respawn code that needs to face a new direction.
func set_look(yaw: float, pitch: float) -> void:
	var limit: float = deg_to_rad(pitch_limit_deg)
	_look_yaw = wrapf(yaw, -PI, PI)
	_body_yaw = _look_yaw
	_look_pitch = clampf(pitch, -limit, limit)


## Where the body is being told to face, which is the camera's yaw unless free look is held.
func get_body_yaw() -> float:
	return _body_yaw


## AIMING. While any reason is held, the body turns to face where the camera looks whether or
## not it is moving — a cast, a bow, a throw has to be thrown by someone facing that way. It
## goes on the wire (`InputFrame.face`), so the module turns the body for everyone else too; it
## keeps its last heading when the last reason lets go. Free look does not apply while held:
## the aim IS where the camera looks. A genre holds its own reason and releases only that.
func hold_facing(reason: StringName, on: bool) -> void:
	if on:
		_face_holds[reason] = true
	else:
		_face_holds.erase(reason)


func is_facing_held() -> bool:
	return not _face_holds.is_empty()


## HOLD THE PLAYER STILL while a page covers the game (DECISIONS #182: the lobby screen): the
## movement keys, jump and the mouse are not read, so nothing walks or turns behind it. Frames
## still go out (standing still is a state too). Each holder releases only its own reason.
func hold_still(reason: StringName, on: bool) -> void:
	if on:
		_still_holds[reason] = true
	else:
		_still_holds.erase(reason)


func is_held_still() -> bool:
	return not _still_holds.is_empty()


func last_seq() -> int:
	return _seq


## The seq of the first frame this process sampled, or 0 before it has sampled one. For tests: a
## restarted client's first frame must come after the count the server already holds.
func first_seq() -> int:
	return _first_seq


## Whether a skill check is waiting for this player's press (their TimedPressComponent).
func _check_up() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var tp: TimedPressComponent = ent.find_component(TimedPressComponent) as TimedPressComponent if ent != null else null
	return tp != null and tp.wants_press()


## Build one frame from the current input state and emit it. Called every physics tick, and
## directly by tests so they do not have to wait on frames.
func sample() -> InputFrame:
	var f: InputFrame = InputFrame.new()
	# seq is monotonic per entity and is what reconciliation keys on (DECISIONS #16). It must
	# never repeat or go backwards, so it is incremented here and nowhere else.
	# PER ENTITY, not per process (DECISIONS #149): a RESTARTED client — same identity, same
	# entity — would count from 1 while the server still holds the last run's count, and the
	# server drops every frame at or below it. That was seconds of play ignored for every minute of
	# the run before, then one correction the length of everything walked meanwhile (snapped
	# 53.56 m from the dock back to the spawn). So carry on from the count the server holds.
	if _movement != null:
		_seq = maxi(_seq, _movement.get_last_processed_seq())
	_seq += 1
	if _first_seq == 0:
		_first_seq = _seq
	f.seq = _seq
	f.client_tick = _client_tick
	_client_tick += 1
	var aiming: bool = not _face_holds.is_empty()
	if aiming or not _free_look():
		_body_yaw = _look_yaw
	f.face = aiming
	var still: bool = is_held_still()
	f.move_dir = Vector2.ZERO if still else _sample_move_dir()
	f.look_yaw = _body_yaw
	f.look_pitch = _look_pitch
	# NO JUMP DURING A SKILL CHECK (DECISIONS #218): its key is Space too, and a hen that jumped off her
	# nest to press it would let go of the nest. Held off until the key is let go after the check.
	if _check_up():
		_jump_held_off = true
	elif not Input.is_action_pressed(ACTION_JUMP):
		_jump_held_off = false
	f.jump = not still and not _jump_held_off and Input.is_action_pressed(ACTION_JUMP)
	f.sprint = not still and Input.is_action_pressed(ACTION_SPRINT)
	f.dash = not still and ((dash_key and Input.is_action_pressed(ACTION_DASH)) or _dash_frames > 0)
	_dash_frames = maxi(_dash_frames - 1, 0)
	f.slow = not still and Input.is_action_pressed(ACTION_SLOW)
	f.client_pos = _body_position()

	# Drive the local player. The movement component stamps the frame with where this step put
	# us (`client_pos`, the Tier A claim: the exact value it remembers for this seq, so the
	# server's echo can be compared bit for bit) and with its correction epoch.
	if _movement != null and _movement.mode == SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED:
		_movement.push_input(f)

	input_sampled.emit(f)
	_queue_for_send(f)
	return f


## Press dash on the next frame sampled: an ability's lunge (`SpaceTimeActionComponent`, DECISIONS #232).
func dash_once() -> void:
	_dash_frames = 1


## Whether a character dashes only by an ability (one of its abilities lunges).
static func lunges_by_ability(defn: EntityDefinition) -> bool:
	if defn == null:
		return false
	for a: AbilityDef in defn.abilities:
		if a != null and a.lunges:
			return true
	return false


## Batch frames to the server. One reducer call per `input_batch_size` frames rather than per
## frame; the server validates seq monotonicity, so a dropped batch costs a stutter, not sync.
func _queue_for_send(f: InputFrame) -> void:
	if not send_to_server:
		return
	_outbox.append(f)
	if _outbox.size() < batch_size:
		return
	var batch: Array[InputFrame] = _outbox.duplicate()
	_outbox.clear()
	var req: ReducerRequest = SpaceTimeSync.submit_input(batch)
	if req != null and _movement != null:
		req.settled.connect(_on_batch_settled)


## A batch that never reached the server will never be acknowledged. Tell prediction, so it does
## not wait on those seqs or compare against them.
func _on_batch_settled(req: ReducerRequest) -> void:
	if req.outcome == ReducerRequest.Outcome.OK or _movement == null:
		return
	_movement.on_input_batch_failed(req.seq_from, req.seq_to)


# --- internals -----------------------------------------------------------------------

## Camera-relative, magnitude clamped to 1. Analogue sticks below full deflection keep their
## magnitude; digital diagonals would otherwise be 1.41x faster than cardinals.
func _sample_move_dir() -> Vector2:
	var raw: Vector2 = Vector2(
		Input.get_action_strength(ACTION_RIGHT) - Input.get_action_strength(ACTION_LEFT),
		Input.get_action_strength(ACTION_BACK) - Input.get_action_strength(ACTION_FORWARD))
	if raw.length() > 1.0:
		raw = raw.normalized()
	if raw == Vector2.ZERO:
		return raw
	# "Forward" means where the camera looks, not where the body faces.
	return raw.rotated(-_camera_yaw())


## The yaw `move_dir` is relative to: the one the body is being told to face. Equal to the
## camera's except during free look, when holding a direction has to keep going where the
## character is pointed rather than curving after the camera.
func _camera_yaw() -> float:
	return _body_yaw


func _free_look() -> bool:
	return InputMap.has_action(ACTION_FREELOOK) and Input.is_action_pressed(ACTION_FREELOOK)


func _body_position() -> Vector3:
	if entity == null:
		return Vector3.ZERO
	var b: CharacterBody3D = entity.body
	return b.position if b != null else Vector3.ZERO
