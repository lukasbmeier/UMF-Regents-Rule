extends "res://tests/suite_base.gd"
## The `config` suite (tests/test_runner.gd runs it; `-- --only=config` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_config_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- movement config: one source of truth, and the feel it promises ---------------------

## Frames (60 Hz) until `pred` holds, stepping the pure model from `s` with `input`.
func _frames_until(s: MovementState, input: InputFrame, cfg: MovementConfig, pred: Callable,
		limit: int = 120) -> Array:
	var dist: float = 0.0
	for n: int in range(1, limit + 1):
		var next: MovementState = MovementModel.simulate(s, input, cfg, 1.0 / 60.0)
		dist += Vector2(next.pos.x - s.pos.x, next.pos.z - s.pos.z).length()
		s = next
		if bool(pred.call(s)):
			return [n, dist, s]
	return [-1, dist, s]


func _run_config_tests() -> void:
	print("== movement config ==")
	# The JSON is the single source (DECISIONS #81). The client read the hardcoded defaults and
	# the server read the JSON, so an edit to the JSON changed only the server. Now the client
	# reads the JSON too, and the defaults must still equal it so tests that construct
	# MovementConfig.new() measure the same game.
	var shared: MovementConfig = MovementConfig.shared()
	var defaults := MovementConfig.new()
	var drift: PackedStringArray = []
	for field: StringName in MovementConfig.FIELDS:
		if not is_equal_approx(float(shared.get(field)), float(defaults.get(field))):
			drift.append("%s json=%s default=%s" % [field, shared.get(field), defaults.get(field)])
	_check(drift.is_empty(), "MovementConfig defaults equal shared/movement_config.json (%s)"
		% (", ".join(drift) if not drift.is_empty() else "all fields"))

	# THE FEEL CONTRACT. "Movement is very glidy" is a tuning complaint; these numbers are what
	# fixed it, and a retune that brings the glide back fails here, not in a playtest months later.
	var sprinting := MovementState.new()
	sprinting.grounded = true
	sprinting.vel = Vector3(0.0, 0.0, -shared.sprint_speed)
	var back := InputFrame.new()
	back.move_dir = Vector2(0.0, 1.0)
	back.sprint = true
	var rev: Array = _frames_until(sprinting, back, shared, func(s: MovementState) -> bool:
		return s.vel.z >= 0.9 * shared.sprint_speed * shared.back_speed_mult)
	print("   sprint reversal to 90%% the other way: %d frames (%.0f ms)" % [rev[0], float(rev[0]) * 1000.0 / 60.0])
	_check(rev[0] > 0 and rev[0] <= 15, "reversing a sprint takes at most 0.25 s (%d frames)" % rev[0])

	var let_go := InputFrame.new()
	var stop: Array = _frames_until(sprinting, let_go, shared, func(s: MovementState) -> bool:
		return Vector2(s.vel.x, s.vel.z).length() < 0.05)
	print("   stop from a sprint: %d frames (%.0f ms), sliding %.2f m" % [stop[0], float(stop[0]) * 1000.0 / 60.0, stop[1]])
	_check(stop[0] > 0 and stop[0] <= 12, "letting go of a sprint stops within 0.2 s (%d frames)" % stop[0])
	_check(float(stop[1]) < 0.8, "and slides under 0.8 m (%.2f m)" % float(stop[1]))

	var rest := MovementState.new()
	rest.grounded = true
	var fwd := InputFrame.new()
	fwd.move_dir = Vector2(0.0, -1.0)
	var go: Array = _frames_until(rest, fwd, shared, func(s: MovementState) -> bool:
		return -s.vel.z >= 0.9 * shared.run_speed)
	_check(go[0] > 0 and go[0] <= 6, "reaching running speed takes at most 0.1 s (%d frames)" % go[0])
