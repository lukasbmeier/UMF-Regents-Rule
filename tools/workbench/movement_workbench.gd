@tool
class_name MovementWorkbench extends Workbench
## THE MOVEMENT WORKBENCH (DECISIONS #205): what a movement profile FEELS like, measured by the real
## movement model (`MovementModel.simulate`, the one prediction and the sidecar run) on flat ground,
## and drawn: every test leaves its path on the floor or in the air beside the character. Change a
## number in the Inspector, run the test again, see the difference.
##
##   accelerate   from standing to running and to sprinting: how long each takes; and from a sprint,
##                how far it slides to a stop
##   jump         a standing jump: how high, how long in the air
##   flaps        a jump with every flap at the top of each rise: the height each flap reaches
##   reverse      sprinting one way, then the other: how many frames until it is going back

const DT: float = 1.0 / 60.0
const TRACE_COLOURS: Dictionary = {&"accelerate": Color(0.4, 0.8, 1.0), &"jump": Color(1.0, 0.8, 0.3),
	&"flaps": Color(1.0, 0.55, 0.3), &"reverse": Color(0.6, 1.0, 0.5)}

var _trace: MultiMeshInstance3D = null
var _label: Label3D = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}


func content_type() -> StringName:
	return &"movement"


func test_actions() -> Array[StringName]:
	return [&"accelerate", &"jump", &"flaps", &"reverse"]


func load_item(def: ContentDef) -> void:
	_build_props()
	var p: MovementProfileDef = def as MovementProfileDef
	_label.text = "" if p == null else "%s  ·  run %s  ·  sprint %s m/s  ·  jump %s m/s  ·  %d flap(s)" % [
		p.display_name, p.run_speed, p.sprint_speed, p.jump_velocity, p.flap_charges]


func run_test(action: StringName) -> String:
	var p: MovementProfileDef = item as MovementProfileDef
	if p == null:
		return "nothing on the bench"
	var cfg: MovementConfig = p.apply_to(MovementConfig.shared())
	var m: Dictionary = measure_config(cfg, action)
	last_measure = m
	_draw(m.get("trace", []) as Array, TRACE_COLOURS.get(action, Color.WHITE))
	match action:
		&"accelerate":
			return "running speed in %.2f s, sprinting speed in %.2f s; from a sprint it slides %.2f m to a stop" % [
				m["to_run_s"], m["to_sprint_s"], m["stop_m"]]
		&"jump":
			return "jumps %.2f m high, %.2f s in the air" % [m["height_m"], m["air_s"]]
		&"flaps":
			if p.flap_charges == 0:
				return "no flaps (flap_charges is 0): a jump of %.2f m" % m["height_m"]
			return "jump %.2f m, then each flap at the top: %s" % [m["height_m"],
				", ".join((m["flap_heights_m"] as Array).map(func(h: float) -> String: return "%.2f m" % h))]
		&"reverse":
			return "a sprint turned round is going the other way after %d frames (%.2f s)" % [m["frames"], m["frames"] * DT]
	return "no such test"


## MEASURE a movement config, by simulating it (pure: no scene, no server). For `action` (above).
## Returns its numbers and `trace`, the path as points.
static func measure_config(cfg: MovementConfig, action: StringName) -> Dictionary:
	var s := MovementState.new()
	s.grounded = true
	var trace: Array[Vector3] = []
	match action:
		&"accelerate":
			var to_run: float = _time_to(cfg, s, Vector2(0, -1), false, cfg.run_speed, trace)
			var s2 := MovementState.new()
			s2.grounded = true
			var to_sprint: float = _time_to(cfg, s2, Vector2(0, -1), true, cfg.sprint_speed, [])
			# At full sprint, let go: how far it slides.
			var start: Vector3 = s2.pos
			var t: int = 0
			while Vector2(s2.vel.x, s2.vel.z).length() > 0.05 and t < 600:
				s2 = MovementModel.simulate(s2, InputFrame.new(), cfg, DT)
				trace.append(s2.pos + Vector3(1.0, 0, 0))
				t += 1
			return {"to_run_s": to_run, "to_sprint_s": to_sprint, "stop_m": (s2.pos - start).length(), "trace": trace}
		&"jump", &"flaps":
			# Every apex (the top of a rise): the first is the jump's; with `flaps`, a fresh press at
			# each apex while charges last, so each later apex is a flap's.
			var apexes: Array[float] = []
			var air: int = 0
			var press: bool = true
			var t: int = 0
			while t < 1200:
				var f := InputFrame.new()
				f.jump = press
				press = false
				var before_vy: float = s.vel.y
				s = MovementModel.simulate(s, f, cfg, DT)
				t += 1
				trace.append(Vector3(t * DT * 0.6, s.pos.y, 0.0))
				if not s.grounded:
					air += 1
				if before_vy > 0.0 and s.vel.y <= 0.0:
					apexes.append(s.pos.y)
					press = action == &"flaps" and s.flaps_used < cfg.flap_charges
				if s.grounded and t > 2:
					break
			var jump_h: float = apexes[0] if not apexes.is_empty() else 0.0
			return {"height_m": jump_h, "air_s": air * DT, "flap_heights_m": apexes.slice(1), "trace": trace}
		&"reverse":
			_time_to(cfg, s, Vector2(0, -1), true, cfg.sprint_speed, [])
			var frames: int = 0
			while s.vel.z <= 0.0 and frames < 600:
				var f := InputFrame.new()
				f.move_dir = Vector2(0, 1)
				f.sprint = true
				s = MovementModel.simulate(s, f, cfg, DT)
				trace.append(s.pos)
				frames += 1
			return {"frames": frames, "trace": trace}
	return {}


static func _time_to(cfg: MovementConfig, s: MovementState, dir: Vector2, sprint: bool, speed: float, trace: Array) -> float:
	var t: int = 0
	while Vector2(s.vel.x, s.vel.z).length() < speed * 0.99 and t < 600:
		var f := InputFrame.new()
		f.move_dir = dir
		f.sprint = sprint
		var next: MovementState = MovementModel.simulate(s, f, cfg, DT)
		s.pos = next.pos
		s.vel = next.vel
		s.grounded = next.grounded
		trace.append(s.pos)
		t += 1
	return t * DT


func _draw(points: Array, colour: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	mm.mesh = dot
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i] as Vector3))
	_trace.multimesh = mm
	(_trace.material_override as StandardMaterial3D).albedo_color = colour


func _build_props() -> void:
	if _trace != null:
		return
	_trace = MultiMeshInstance3D.new()
	_trace.name = "Trace"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trace.material_override = mat
	add_child(_trace)
	_label = Label3D.new()
	_label.name = "Info"
	_label.position = Vector3(0, 3.0, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.005
	add_child(_label)
