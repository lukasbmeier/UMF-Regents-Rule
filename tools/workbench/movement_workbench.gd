@tool
class_name MovementWorkbench extends Workbench
## THE MOVEMENT WORKBENCH (DECISIONS #205, reworked by #207): what a movement profile FEELS like.
## Each test is measured by the real movement model (`MovementModel.simulate`, the one prediction
## and the sidecar run) on flat ground, then PERFORMED: the character it is tried on runs, stops,
## jumps and turns along the path at the real speed (slower if you like), with a ruler under it,
## the moments that matter labelled where they happen, and its speed over its head. The dots are the
## whole path. Change a number in the Inspector and the test plays again.
##
##   accelerate   "Start and stop": from standing to a full sprint, then let go: how long to running
##                speed and to sprinting speed, and how far it slides to a stop
##   jump         a standing jump: how high, how long in the air
##   flaps        a jump with every flap at the top of each rise: the height each flap reaches
##   reverse      "Turn around": sprinting one way, then the other: how long until it goes back

const DT: float = 1.0 / 60.0
const TRACE_COLOURS: Dictionary = {&"accelerate": Color(0.4, 0.8, 1.0), &"jump": Color(1.0, 0.8, 0.3),
	&"flaps": Color(1.0, 0.55, 0.3), &"reverse": Color(0.6, 1.0, 0.5)}
## How long a sprint is held in "Start and stop" before letting go (s).
const SPRINT_HOLD_S: float = 1.2

var _trace: MultiMeshInstance3D = null
var _label: Label3D = null
var _speed_label: Label3D = null
var _marks: Node3D = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}
## How fast the performance plays (1: as in the game).
var replay_speed: float = 1.0
## Play the performance again and again.
var replay_loop: bool = false
## The last test, performed: [{pos, vel, grounded}] a frame each.
var _timeline: Array = []
var _replay_t: float = -1.0
var _replay_offset: Vector3 = Vector3.ZERO
var _last_test: StringName = &""
var _shown_clip: StringName = &""


func content_type() -> StringName:
	return &"movement"


func test_actions() -> Array[StringName]:
	return [&"accelerate", &"jump", &"flaps", &"reverse"]


func test_label(action: StringName) -> String:
	match action:
		&"accelerate": return "Start and stop"
		&"reverse": return "Turn around"
	return super(action)


func test_info(action: StringName) -> String:
	match action:
		&"accelerate": return "From standing to a full sprint, then let go: time to running and sprinting speed, and the slide to a stop"
		&"jump": return "A standing jump: how high, how long in the air"
		&"flaps": return "A jump, then each flap at the top of each rise: the height each one reaches"
		&"reverse": return "Sprinting one way, then the other: how long until it is going back"
	return ""


func tries_on_character() -> bool:
	return true


## A character that moves by this profile, else the humanoid.
func default_character() -> EntityDefinition:
	var p: ContentDef = item
	var user: EntityDefinition = character_using(func(d: ContentDef) -> bool: return (d as EntityDefinition).movement_profile == p)
	return user if user != null else super()


func controls() -> Array[Dictionary]:
	return [character_control(),
		{"name": &"replay_speed", "label": "Replay speed", "kind": "number", "value": replay_speed, "min": 0.1, "max": 2.0, "step": 0.05,
			"tooltip": "1: as fast as in the game; lower to watch it closely"},
		{"name": &"replay_loop", "label": "Loop", "kind": "toggle", "value": replay_loop}]


func set_control(n: StringName, value: Variant) -> void:
	match n:
		&"replay_speed":
			replay_speed = float(value)
		&"replay_loop":
			replay_loop = bool(value)
		_:
			super(n, value)


func bench_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _timeline.is_empty():
		out.append({"name": &"replay", "label": "Replay", "tooltip": "Play the last test again"})
	return out


func do_action(action: StringName) -> Dictionary:
	if action == &"replay":
		_replay_t = 0.0
		return {}
	return super(action)


## Play as this profile: the game, with the player's character moving by it (`--movement=`).
func play_args() -> PackedStringArray:
	if item == null or item.resource_path.is_empty():
		return PackedStringArray()
	return PackedStringArray(["--movement=" + item.resource_path])


func load_item(def: ContentDef) -> void:
	_build_props()
	var p: MovementProfileDef = def as MovementProfileDef
	_label.text = "" if p == null else "%s  ·  run %s  ·  sprint %s m/s  ·  jump %s m/s  ·  %d flap(s)%s" % [
		p.display_name, p.run_speed, p.sprint_speed, p.jump_velocity, p.flap_charges,
		"" if character == null else "  ·  on %s" % character.display_name]
	# An edit plays the last test again, so a change is seen as it is made.
	if not _last_test.is_empty() and p != null and is_inside_tree():
		_measure_and_show(_last_test)


func run_test(action: StringName) -> String:
	var p: MovementProfileDef = item as MovementProfileDef
	if p == null:
		return "nothing on the bench"
	return _measure_and_show(action)


func _measure_and_show(action: StringName) -> String:
	var p: MovementProfileDef = item as MovementProfileDef
	var cfg: MovementConfig = p.apply_to(MovementConfig.shared())
	var m: Dictionary = measure_config(cfg, action)
	last_measure = m
	_last_test = action
	_draw(m.get("trace", []) as Array, TRACE_COLOURS.get(action, Color.WHITE))
	_timeline = m.get("timeline", []) as Array
	_replay_offset = Vector3.ZERO
	_replay_t = 0.0
	_draw_marks(action, m, cfg)
	panel_changed.emit()
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


## MEASURE a movement config, by simulating it (pure: no scene, no server). For `action` (above, and
## `top_speeds`: the speed a plain move and a sprint settle at). With `status`, every press goes
## through it first (`StatusDef.filter_input`: a downed character's jump is no jump), as in the game.
## Returns its numbers, `trace` (the path as points, to draw) and `timeline` (where it is each
## frame, to perform: {pos, vel, grounded}).
static func measure_config(cfg: MovementConfig, action: StringName, status: StatusDef = null) -> Dictionary:
	var s := MovementState.new()
	s.grounded = true
	var trace: Array[Vector3] = []
	var timeline: Array = []
	var step: Callable = func(st: MovementState, f: InputFrame) -> MovementState:
		var next: MovementState = MovementModel.simulate(st, status.filter_input(f) if status != null else f, cfg, DT)
		timeline.append({"pos": next.pos, "vel": next.vel, "grounded": next.grounded})
		return next
	match action:
		&"top_speeds":
			var out: Dictionary = {}
			for gait: String in ["run", "sprint"]:
				var g := MovementState.new()
				g.grounded = true
				for i: int in 180:
					var f := InputFrame.new()
					f.move_dir = Vector2(0, -1)
					f.sprint = gait == "sprint"
					g = step.call(g, f)
					if gait == "sprint":
						trace.append(g.pos)
				out[gait] = Vector2(g.vel.x, g.vel.z).length()
			out["trace"] = trace
			out["timeline"] = timeline
			return out
		&"accelerate":
			# How long a plain move takes to running speed (measured on its own)...
			var plain := MovementState.new()
			plain.grounded = true
			var to_run: float = _time_to(cfg, plain, Vector2(0, -1), false, cfg.run_speed, [])
			# ...then ONE performance: standing, a full sprint, let go, stopped.
			var t: int = 0
			var to_sprint: float = -1.0
			var at_run: Vector3 = Vector3.INF
			var at_sprint: Vector3 = Vector3.INF
			while t < int(SPRINT_HOLD_S / DT):
				var f := InputFrame.new()
				f.move_dir = Vector2(0, -1)
				f.sprint = true
				s = step.call(s, f)
				trace.append(s.pos)
				t += 1
				var speed: float = Vector2(s.vel.x, s.vel.z).length()
				if at_run == Vector3.INF and speed >= cfg.run_speed * 0.99:
					at_run = s.pos
				if to_sprint < 0.0 and speed >= cfg.sprint_speed * 0.99:
					to_sprint = t * DT
					at_sprint = s.pos
			var let_go: Vector3 = s.pos
			var n: int = 0
			while Vector2(s.vel.x, s.vel.z).length() > 0.05 and n < 600:
				s = step.call(s, InputFrame.new())
				trace.append(s.pos)
				n += 1
			for i: int in 20:   # a moment standing still at the end
				timeline.append({"pos": s.pos, "vel": Vector3.ZERO, "grounded": true})
			return {"to_run_s": to_run, "to_sprint_s": maxf(to_sprint, 0.0), "stop_m": (s.pos - let_go).length(),
				"trace": trace, "timeline": timeline,
				"events": [{"pos": at_run, "text": "running speed (%.2f s)" % to_run}, {"pos": at_sprint, "text": "sprinting speed (%.2f s)" % maxf(to_sprint, 0.0)},
					{"pos": let_go, "text": "let go"}, {"pos": s.pos, "text": "stopped: slid %.2f m" % (s.pos - let_go).length()}]}
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
				s = step.call(s, f)
				t += 1
				trace.append(Vector3(t * DT * 0.6, s.pos.y, 0.0))
				if not s.grounded:
					air += 1
				if before_vy > 0.0 and s.vel.y <= 0.0:
					apexes.append(s.pos.y)
					press = action == &"flaps" and s.flaps_used < cfg.flap_charges
				if s.grounded and t > 2:
					break
			for i: int in 20:
				timeline.append({"pos": s.pos, "vel": Vector3.ZERO, "grounded": true})
			var events: Array = []
			for i: int in apexes.size():
				events.append({"pos": Vector3(0, apexes[i], 0), "text": ("jump %.2f m" if i == 0 else "flap %d: %.2f m") % ([apexes[i]] if i == 0 else [i, apexes[i]])})
			var jump_h: float = apexes[0] if not apexes.is_empty() else 0.0
			return {"height_m": jump_h, "air_s": air * DT, "flap_heights_m": apexes.slice(1), "trace": trace, "timeline": timeline, "events": events}
		&"reverse":
			for i: int in int(1.0 / DT):
				var f := InputFrame.new()
				f.move_dir = Vector2(0, -1)
				f.sprint = true
				s = step.call(s, f)
				trace.append(s.pos)
			var turned_at: Vector3 = s.pos
			var frames: int = 0
			while s.vel.z <= 0.0 and frames < 600:
				var f := InputFrame.new()
				f.move_dir = Vector2(0, 1)
				f.sprint = true
				s = step.call(s, f)
				trace.append(s.pos)
				frames += 1
			var going_back: Vector3 = s.pos
			for i: int in 40:
				var f := InputFrame.new()
				f.move_dir = Vector2(0, 1)
				f.sprint = true
				s = step.call(s, f)
				trace.append(s.pos)
			return {"frames": frames, "trace": trace, "timeline": timeline,
				"events": [{"pos": turned_at, "text": "turns round"}, {"pos": going_back, "text": "going back after %.2f s" % (frames * DT)}]}
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


# --- the performance ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if _replay_t < 0.0 or _timeline.is_empty():
		return
	var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
	_replay_t += delta * replay_speed
	var i: int = int(_replay_t / DT)
	if i >= _timeline.size():
		if replay_loop:
			_replay_t = 0.0
			i = 0
		else:
			_replay_t = -1.0
			i = _timeline.size() - 1
	var f: Dictionary = _timeline[i]
	var vel: Vector3 = f["vel"]
	var h: float = Vector2(vel.x, vel.z).length()
	if m != null:
		m.position = (f["pos"] as Vector3) + _replay_offset
		if h > 0.2:
			m.rotation.y = atan2(-vel.x, -vel.z)
		var clip: StringName = performance_clip(f, item as MovementProfileDef)
		if clip != _shown_clip:
			_shown_clip = clip
			m.play(clip)
	if _speed_label != null:
		_speed_label.position = (f["pos"] as Vector3) + _replay_offset + Vector3(0, 2.2, 0)
		_speed_label.text = "%.1f m/s" % h if bool(f["grounded"]) else "%.1f m/s  ·  %.2f m up" % [h, (f["pos"] as Vector3).y]


## The clip the character plays at one frame of a performance: in the air, its jump; standing,
## idle; moving, the gait its speed is nearest.
static func performance_clip(f: Dictionary, p: MovementProfileDef) -> StringName:
	var vel: Vector3 = f["vel"]
	if not bool(f["grounded"]):
		return AnimationSet.JUMP_LOOP if vel.y < 0.0 else AnimationSet.JUMP_START
	var h: float = Vector2(vel.x, vel.z).length()
	if h < 0.15:
		return AnimationSet.IDLE
	var walk: float = p.walk_speed if p != null else 1.2
	var run: float = p.run_speed if p != null else 5.0
	if h < (walk + run) * 0.5:
		return AnimationSet.WALK
	var sprint: float = p.sprint_speed if p != null else 8.0
	return AnimationSet.RUN if h < (run + sprint) * 0.5 else AnimationSet.SPRINT


## Whether a performance is playing (tests).
func performing() -> bool:
	return _replay_t >= 0.0 and not _timeline.is_empty()


## THE RULER AND THE MOMENTS: a metre scale along the path (or up the jump), and each moment that
## matters labelled where it happens.
func _draw_marks(action: StringName, m: Dictionary, _cfg: MovementConfig) -> void:
	for c: Node in _marks.get_children():
		c.queue_free()
	var vertical: bool = action == &"jump" or action == &"flaps"
	var extent: float = 0.0
	for p: Variant in m.get("trace", []) as Array:
		var v: Vector3 = p
		extent = maxf(extent, v.y if vertical else maxf(absf(v.z), absf(v.x)))
	var steps: int = int(ceil(extent / (0.5 if vertical else 1.0))) + 1
	for k: int in steps + 1:
		var d: float = k * (0.5 if vertical else 1.0)
		var at: Vector3 = Vector3(-0.9, d, 0.0) if vertical else Vector3(-0.6, 0.01, -d)
		var tick := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.01, 0.01) if vertical else Vector3(0.3, 0.01, 0.02)
		tick.mesh = box
		tick.position = at
		_marks.add_child(tick)
		_mark_text(at + (Vector3(-0.35, 0, 0) if vertical else Vector3(-0.45, 0.02, 0)), "%s m" % ("%.1f" % d if vertical else "%d" % int(d)), Color(0.8, 0.8, 0.8), 0.003)
	for e: Variant in m.get("events", []) as Array:
		var ev: Dictionary = e
		var pos: Vector3 = ev["pos"]
		if pos == Vector3.INF:
			continue
		_mark_text(pos + Vector3(0.7, 0.6, 0.0) if not vertical else Vector3(0.9, pos.y, 0.0), String(ev["text"]), Color(1.0, 0.9, 0.5), 0.004)


func _mark_text(at: Vector3, text: String, colour: Color, size: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = size
	l.modulate = colour
	l.outline_size = 6
	_marks.add_child(l)


func _draw(points: Array, colour: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	mm.mesh = dot
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), (points[i] as Vector3) + Vector3(0, 0.03, 0)))
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
	_marks = Node3D.new()
	_marks.name = "Marks"
	add_child(_marks)
	_label = Label3D.new()
	_label.name = "Info"
	_label.position = Vector3(0, 3.0, 1.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.005
	add_child(_label)
	_speed_label = Label3D.new()
	_speed_label.name = "Speed"
	_speed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speed_label.pixel_size = 0.004
	_speed_label.outline_size = 8
	_speed_label.position = Vector3(0, 2.2, 0)
	add_child(_speed_label)
