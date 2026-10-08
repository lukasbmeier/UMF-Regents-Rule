extends Node
## MOVEMENT PLAYTEST: the real fishing scene, a real server, and scripted keys.
##
## This is the automated version of "press Play and walk around". It drives the SAME input
## actions a player presses (Input.action_press), through the SAME LocalInputComponent, into
## the SAME predicted body, against a live module, and measures what the player would feel:
##
##   spawn        the body starts standing ON the floor, not in it, and can walk at once
##   responsive   the body moves on the very frame the key goes down (no input latency)
##   no snapback  across walking, sprinting and turning, the body never jumps backwards
##   elevated     standing on geometry above ground_y is not undone by the server
##   ack latency  how long the server takes to confirm an input, p50/p95/max
##
## Run it with artificial latency to see prediction hold up:
##   godot --headless --path . res://tests/playtest/movement_playtest.tscn -- --latency=100
## Driven by tests/playtest_test.sh. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 120.0
const STEP_TIMEOUT_SEC: float = 25.0
## Reported, not asserted: frames the body slid against the held direction (momentum).
const SNAPBACK_EPS: float = 0.01
## Asserted: a change in per-frame displacement no model acceleration can produce.
const SNAPBACK_EPS_2ND: float = 0.05

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false

var _entity: SpaceTimeEntity = null
var _body: CharacterBody3D = null
var _movement: SpaceTimeMovementComponent = null
var _input: LocalInputComponent = null

## seq -> local usec it was sampled. Filled from LocalInputComponent.input_sampled.
var _sent_at: Dictionary[int, int] = {}
var _acked_seq: int = 0
var _ack_ms: Array[float] = []
var _reconciles: Array[float] = []
var _teleports: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	print("== movement playtest (simulated latency: %s) ==" % _latency_label())

	if not await _step_bind():
		_finish()
		return
	await _step_spawn()
	await _step_walk_from_spawn()
	await _step_sprint_and_turn()
	await _step_responsiveness()
	await _step_direction_change()
	await _step_jumping()
	await _step_correction_glide()
	await _step_correction_while_moving()
	await _step_elevated()
	_report_ack_latency()
	_finish()


# --- steps -----------------------------------------------------------------------------

func _step_bind() -> bool:
	var ok: bool = await _until(func() -> bool:
		if EntityRegistry.local_entity_id < 0:
			return false
		var e: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		return e != null and e.is_bound(), "the local player to spawn and bind")
	_check(ok, "local player spawned and bound")
	if not ok:
		return false
	_entity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	_body = _entity.body
	_movement = _entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_input = _entity.find_component(LocalInputComponent) as LocalInputComponent
	_check(_movement != null and _movement.mode == SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED,
		"the local player's movement is predicted locally")
	_check(_input != null, "the local player samples input")
	if _movement == null or _input == null or _body == null:
		return false

	_input.input_sampled.connect(func(f: InputFrame) -> void: _sent_at[f.seq] = Time.get_ticks_usec())
	_movement.reconciled.connect(func(err: float) -> void: _reconciles.append(err))
	SignalBus.entity_teleported.connect(func(eid: int) -> void:
		if eid == _entity.entity_id:
			_teleports += 1)
	return true


## The capsule must stand ON the floor. The model's `pos.y == ground_y` means feet on the
## ground, so the body's origin has to be at its feet. If it is at the capsule's centre, the
## lower half starts inside the floor and move_and_slide cannot get it out sideways.
func _step_spawn() -> void:
	print("-- spawn --")
	await _frames(20)
	var bottom: float = _capsule_bottom_y()
	print("   origin y %.3f, capsule bottom y %.3f" % [_body.global_position.y, bottom])
	_check(bottom >= -0.05,
		"the capsule starts on top of the floor, not inside it (bottom at y=%.3f)" % bottom)
	var predicted: MovementState = _movement.get_predicted_state()
	_check(_body.is_on_floor() or (predicted != null and predicted.grounded),
		"the player starts grounded")


## The reported bug: "jumping is required before moving". Walk straight away, no jump first.
func _step_walk_from_spawn() -> void:
	print("-- walk from spawn, no jump --")
	_input.set_look(0.0, 0.0)
	await _frames(2)
	var start: Vector3 = _body.global_position
	var trace: Array[Vector3] = await _hold([&"move_forward"], 60)
	var moved: float = _horizontal(trace[-1] - start)
	print("   walked %.2f m in 1.0 s" % moved)
	# A plain key press RUNS: 5 m/s, which covers about 4.7 m in a second from a standstill.
	_check(moved > 3.5, "walking from spawn moves the player without a jump first (%.2f m)" % moved)
	_check_no_snapback(trace, Vector3.FORWARD, "walking")
	await _frames(30)   # let friction stop us


## Sprinting is where a stale-echo comparison bites: the faster you go, the further the
## server's (older) position is behind yours.
func _step_sprint_and_turn() -> void:
	print("-- sprint, then turn and sprint back --")
	var before: int = _reconciles.size()
	_input.set_look(PI, 0.0)   # face +Z
	await _frames(2)
	var start: Vector3 = _body.global_position
	var trace: Array[Vector3] = await _hold([&"move_forward", &"sprint"], 90)
	var moved: float = _horizontal(trace[-1] - start)
	print("   sprinted %.2f m in 1.5 s" % moved)
	_check(moved > 9.0, "sprinting covers ground (%.2f m in 1.5 s)" % moved)
	_check_no_snapback(trace, Vector3.BACK, "sprinting")

	_input.set_look(0.0, 0.0)   # about face, toward -Z
	await _frames(2)
	trace = await _hold([&"move_forward", &"sprint"], 60)
	_check_no_snapback(trace, Vector3.FORWARD, "sprinting after a turn")
	var big: int = 0
	for i: int in range(before, _reconciles.size()):
		if _reconciles[i] > 0.25:
			big += 1
	_check(big == 0, "no large corrections while sprinting (%d over 25 cm)" % big)
	await _frames(30)


## "No visible input latency": the body must move within a frame or two of the key going
## down. Prediction exists for exactly this; with it, latency only shows up in the server
## confirming the move, never in the move itself.
func _step_responsiveness() -> void:
	print("-- responsiveness --")
	_input.set_look(0.0, 0.0)
	await _frames(5)
	var p0: Vector3 = _body.global_position
	Input.action_press(&"move_forward")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p1: Vector3 = _body.global_position
	Input.action_release(&"move_forward")
	var moved_mm: float = _horizontal(p1 - p0) * 1000.0
	print("   moved %.1f mm within 2 physics frames of the key going down" % moved_mm)
	_check(moved_mm > 1.0, "the body responds within two physics frames of input (%.1f mm)" % moved_mm)
	await _frames(20)


## Reported: "some delay between changing directions ... movement right now is very glidy".
## Through the real keys: sprint, then slam the opposite direction, and time the reversal of the
## body's actual velocity (from its drawn positions), then time a stop after letting go.
func _step_direction_change() -> void:
	print("-- direction change --")
	# A known open lane: z = -5 runs clear from the west wall to the platform's corner, and the
	# earlier steps may have left us against the north wall — where a "stop" measures nothing
	# (the first version of this step reported a 0 m slide for exactly that reason).
	var tp_before: int = _teleports
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(-8.0, 0.0, -5.0)], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return _teleports > tp_before, "the teleport to the open lane")
	await _frames(20)
	_input.set_look(-PI * 0.5, 0.0)   # camera-forward is +X
	await _frames(2)
	Input.action_press(&"sprint")
	Input.action_press(&"move_forward")
	await _frames(60)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	var prev: Vector3 = _body.global_position
	var reversed_at: int = -1
	for f: int in range(60):
		await get_tree().physics_frame
		var step: Vector3 = _body.global_position - prev
		prev = _body.global_position
		# Forward is +X: reversed means -X at 90% of the speed this game runs BACKWARDS at,
		# which is a slower gear than forwards on purpose (DECISIONS #100).
		if -step.x * 60.0 >= 0.9 * _movement.config.sprint_speed * _movement.config.back_speed_mult:
			reversed_at = f + 1
			break
	Input.action_release(&"move_back")
	await _frames(40)
	# Now a stop: sprint along the same open lane, let go, time it and measure the slide.
	Input.action_press(&"move_forward")
	await _frames(45)
	Input.action_release(&"move_forward")
	var from: Vector3 = _body.global_position
	prev = from
	var stopped_at: int = -1
	for f: int in range(60):
		await get_tree().physics_frame
		var step2: Vector3 = _body.global_position - prev
		prev = _body.global_position
		if Vector2(step2.x, step2.z).length() * 60.0 < 0.05:
			stopped_at = f + 1
			break
	Input.action_release(&"sprint")
	var slide: float = _horizontal(_body.global_position - from)
	print("   sprint reversal: %d frames; stop: %d frames, sliding %.2f m" % [reversed_at, stopped_at, slide])
	_check(reversed_at > 0 and reversed_at <= 15, "a sprint reverses within 0.25 s through the real keys (%d frames)" % reversed_at)
	_check(stopped_at > 0 and stopped_at <= 13 and slide < 0.8,
		"letting go stops within ~0.2 s and under 0.8 m (%d frames, %.2f m)" % [stopped_at, slide])
	await _frames(20)


## Reported: "jump breaks after a few jumps (or by jumping near a wall) and then I can't jump."
## Through the real keys: a dozen jumps on open floor, then a dozen more pressed against a wall.
## Every one must leave the ground by a metre and come back down grounded.
func _step_jumping() -> void:
	print("-- jumping, open floor then against a wall --")
	var results: PackedStringArray = []
	var failed: int = 0
	for n: int in range(24):
		if n == 12:
			# Walk into the north wall (inner face z = -9.5) and keep pressing into it.
			_input.set_look(0.0, 0.0)
			Input.action_press(&"move_forward")
			await _frames(150)
		var y0: float = _body.global_position.y
		Input.action_press(&"jump")
		await _frames(2)
		Input.action_release(&"jump")
		var peak: float = y0
		var landed: bool = false
		for f: int in range(120):
			await get_tree().physics_frame
			peak = maxf(peak, _body.global_position.y)
			if f > 10 and _movement.get_predicted_state().grounded:
				landed = true
				break
		await _frames(3)
		var ok: bool = landed and peak - y0 > 1.0
		if not ok:
			failed += 1
		results.append("%.2f%s" % [peak - y0, "" if landed else "!"])
	Input.action_release(&"move_forward")
	print("   jump heights: %s" % " ".join(results))
	_check(failed == 0, "24 jumps, open floor and against a wall, each rise over 1 m and land (%d failed)" % failed)
	await _frames(30)


## PHASE4_SPEC section 5: "forcing a divergence produces a glide, not a pop". The server moves us
## 40 cm without flagging a teleport, the way a correction would. The body adopts it at once; the
## DRAWN position glides there over `reconcile_smooth_time`; and it settles after ONE
## correction. That last part is the one that failed on paper before the epoch protocol: stale
## in-flight frames dragged the server back, the client chased it, and they oscillated forever.
func _step_correction_glide() -> void:
	print("-- server correction while standing still --")
	await _frames(30)
	var before_count: int = _reconciles.size()
	var snaps_before: int = _movement.get_reconcile_stats()["snaps"]
	var start: Vector3 = _body.global_position
	var nudge: Vector3 = Vector3(0.4, 0.0, 0.0)
	SpaceTimeSync.call_reducer(&"dev_nudge", [nudge], ["vector3[f32,f32,f32]"])
	var got: bool = await _until(func() -> bool: return _reconciles.size() > before_count,
		"the correction to arrive")
	_check(got, "the server correction reached the client")
	if not got:
		return
	var err: float = _reconciles[before_count]
	var offset_now: float = _movement.get_visual_offset().length()
	print("   correction of %.3f m; glide offset right after: %.3f m" % [err, offset_now])
	_check(absf(err - 0.4) < 0.05, "the correction measured the nudge (%.3f m)" % err)
	_check(_movement.get_reconcile_stats()["snaps"] == snaps_before, "a 40 cm correction glides, it does not snap")
	_check(offset_now > 0.3, "the visual starts where it was drawn, not at the corrected spot")

	var smooth_frames: int = ceili(_movement.config.reconcile_smooth_time * 60.0) + 2
	await _frames(smooth_frames)
	var left: float = _movement.get_visual_offset().length()
	_check(left < 0.001, "the glide finishes within reconcile_smooth_time (%.4f m left)" % left)
	var moved: Vector3 = _body.global_position - start
	_check(moved.distance_to(nudge) < 0.02, "the body ends at the corrected position (moved %s)" % moved)

	# Settled means settled: no chase, no oscillation, for two full seconds.
	var settle_count: int = _reconciles.size()
	await _frames(120)
	_check(_reconciles.size() == settle_count,
		"ONE correction settles it: %d more over the next 2 s" % (_reconciles.size() - settle_count))


## The same correction while walking. The owner drops the inputs the server will consume under
## the old epoch, so it loses about one round trip of movement: that is inherent in an
## override. What must hold is that the loss is drawn as a glide and happens once.
func _step_correction_while_moving() -> void:
	print("-- server correction while walking --")
	_input.set_look(0.0, 0.0)
	await _frames(2)
	var before_count: int = _reconciles.size()
	Input.action_press(&"move_forward")
	await _frames(20)
	SpaceTimeSync.call_reducer(&"dev_nudge", [Vector3(0.4, 0.0, 0.0)], ["vector3[f32,f32,f32]"])
	var drawn: Array[Vector3] = [_drawn()]
	for i: int in range(90):
		await get_tree().physics_frame
		drawn.append(_drawn())
	Input.action_release(&"move_forward")
	var count: int = _reconciles.size() - before_count
	var err: float = _reconciles[before_count] if count > 0 else 0.0
	var worst: float = 0.0
	for i: int in range(1, drawn.size()):
		worst = maxf(worst, _horizontal(drawn[i] - drawn[i - 1]))
	print("   %d correction(s), first %.3f m; largest drawn step %.3f m/frame" % [count, err, worst])
	_check(count == 1, "exactly one correction while walking, no chase (%d)" % count)
	# Walking is ~0.08 m/frame; a pop would be the whole error in one frame.
	_check(worst < 0.08 + err * 0.5, "the correction is drawn as a glide, not a pop (largest step %.3f m)" % worst)
	await _frames(30)


## Where the player SEES the body: the simulation position plus any correction glide.
func _drawn() -> Vector3:
	return _body.global_position + _movement.get_visual_offset()


## Standing on something above ground_y. The module cannot see the level; a trust policy that
## runs gravity against a client standing on a box will, sooner or later, drag it through.
func _step_elevated() -> void:
	print("-- standing on raised geometry --")
	var target: Vector3 = Vector3(5.0, 1.75 + 0.05, 5.0)   # on top of the greybox Platform
	var teleports_before: int = _teleports
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"teleport", [target], ["vector3[f32,f32,f32]"])
	_check(req != null, "teleport dispatched")
	var arrived: bool = await _until(func() -> bool: return _teleports > teleports_before,
		"the teleport to land")
	_check(arrived, "the teleport onto the platform arrived")
	await _frames(30)
	var landed_y: float = _body.global_position.y
	print("   landed at y %.3f" % landed_y)
	_check(absf(landed_y - 1.75) < 0.1, "the player stands on the platform top (y=%.3f)" % landed_y)

	# Now stand still for three seconds: long enough for any server-side gravity to win.
	var snaps_before: int = _teleports
	var lowest: float = landed_y
	for i: int in range(180):
		await get_tree().physics_frame
		lowest = minf(lowest, _body.global_position.y)
	print("   lowest y over 3 s standing still: %.3f" % lowest)
	_check(lowest > 1.6,
		"standing on the platform for 3 s, the server never pulls the player through it (lowest y=%.3f)" % lowest)
	_check(_teleports == snaps_before, "no server snap while standing on the platform")


# --- measurement -------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _movement == null:
		return
	var acked: int = _movement.get_last_processed_seq()
	while _acked_seq < acked:
		_acked_seq += 1
		if _sent_at.has(_acked_seq):
			_ack_ms.append(float(Time.get_ticks_usec() - _sent_at[_acked_seq]) / 1000.0)
			_sent_at.erase(_acked_seq)


func _report_ack_latency() -> void:
	if _ack_ms.is_empty():
		_check(false, "the server acknowledged at least one input")
		return
	var s: Array[float] = _ack_ms.duplicate()
	s.sort()
	var p50: float = s[s.size() / 2]
	var p95: float = s[mini(s.size() - 1, int(s.size() * 0.95))]
	print("-- input ack latency over %d inputs: p50 %.0f ms, p95 %.0f ms, max %.0f ms --"
		% [s.size(), p50, p95, s[-1]])
	var big: int = 0
	for e: float in _reconciles:
		if e > 0.25:
			big += 1
	print("-- corrections: %d total, %d over 25 cm; server snaps: %d --"
		% [_reconciles.size(), big, _teleports])


# --- helpers -----------------------------------------------------------------------------

## Hold actions for `frames` physics frames, recording the body position each frame.
func _hold(actions: Array[StringName], frames: int) -> Array[Vector3]:
	var trace: Array[Vector3] = [_drawn()]
	for a: StringName in actions:
		Input.action_press(a)
	for i: int in range(frames):
		await get_tree().physics_frame
		trace.append(_drawn())
	for a: StringName in actions:
		Input.action_release(a)
	return trace


## Rubber-banding is a DISCONTINUITY: the body's frame-to-frame motion changes by more than any
## acceleration the model can produce. That is the definition that survives a turn — after an
## about-face the body legitimately keeps sliding backwards while it decelerates, which a naive
## "moved against the input" count reports as nine snap-backs.
##
## The model accelerates at most `acceleration` (40 m/s²), i.e. 0.011 m of change in per-frame
## displacement. SNAPBACK_EPS_2ND is ~4.5x that. A server snap of even 10 cm is ~10x over it.
## Horizontal only: landing legitimately stops vertical motion in one frame.
func _check_no_snapback(trace: Array[Vector3], world_dir: Vector3, what: String) -> void:
	var dir: Vector3 = Vector3(world_dir.x, 0.0, world_dir.z).normalized()
	var jumps: int = 0
	var worst: float = 0.0
	var backs: int = 0
	for i: int in range(2, trace.size()):
		var d1: Vector3 = trace[i - 1] - trace[i - 2]
		var d2: Vector3 = trace[i] - trace[i - 1]
		var change: float = Vector2(d2.x - d1.x, d2.z - d1.z).length()
		if change > SNAPBACK_EPS_2ND:
			jumps += 1
			worst = maxf(worst, change)
		if d2.dot(dir) < -SNAPBACK_EPS:
			backs += 1
	print("   %s: %d discontinuities (worst %.3f m/frame change), %d frames sliding against input"
		% [what, jumps, worst, backs])
	_check(jumps == 0, "no rubber-band discontinuity while %s (%d, worst %.3f m/frame change)"
		% [what, jumps, worst])


func _capsule_bottom_y() -> float:
	var shape_node: CollisionShape3D = _body.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return _body.global_position.y
	var cap: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	var half: float = cap.height * 0.5 if cap != null else 0.0
	return shape_node.global_position.y - half


func _horizontal(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame


func _latency_label() -> String:
	var sim: Vector2i = SpaceTimeSync.get_simulated_latency()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--latency="):
			return arg.substr("--latency=".length()) + " ms round trip"
	return "%d ms round trip" % sim.x


func _until(pred: Callable, what: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	printerr("  TIMEOUT after %.0fs waiting for %s" % [STEP_TIMEOUT_SEC, what])
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: playtest exceeded %.0fs overall" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"jump"]:
		Input.action_release(a)
	print("\n%d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
