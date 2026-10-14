extends Node3D
## THE REPLAY VIEWER (DECISIONS #235): plays back a round the world's referee recorded
## (`SessionRecorder`, `user://recordings/`). Open `tools/replay/replay_viewer.tscn` and press F6 (Run
## Current Scene): the newest recording plays over its level, seen from above.
##
##   Space          play / pause            the slider    any moment of the round
##   1 / 2 / 3      speed x1, x4, x16       H             where people were hurt, downed, hit or missed
##   mouse wheel    zoom                    right drag    turn the view
##   [ / ]          the recording before / after this one
##
## Everyone is a capsule in their kind's colour, named; the list on the right is what happened, and
## clicking a line jumps there. Nothing here connects to a server: it reads the file.

const DIR: String = "user://recordings"
## A file to open instead of the newest (a path, absolute or user://).
@export_file("*.jsonl") var recording: String = ""

var header: Dictionary = {}
## [{t, e: {id: [kind, pos, yaw, status]}}], oldest first
var frames: Array[Dictionary] = []
## [{t, ev, ...}], oldest first
var events: Array[Dictionary] = []

var _t: float = 0.0
var _playing: bool = true
var _speed: float = 1.0
var _files: PackedStringArray = PackedStringArray()
var _file_index: int = -1
var _level: Node3D = null
var _bodies: Dictionary[int, Node3D] = {}
var _heat: Node3D = null
var _cam_pivot: Node3D = null
var _cam: Camera3D = null
var _ui: Control = null
var _slider: HSlider = null
var _clock: Label = null
var _list: ItemList = null
var _drag: bool = false


func _ready() -> void:
	_build_view()
	_files = list_recordings()
	if not recording.is_empty():
		open(recording)
	elif not _files.is_empty():
		_file_index = _files.size() - 1
		open(_files[_file_index])
	else:
		_clock.text = "No recordings yet in %s: play a round with a referee running." % ProjectSettings.globalize_path(DIR)


## Every recording, oldest first.
static func list_recordings() -> PackedStringArray:
	var out := PackedStringArray()
	var d: DirAccess = DirAccess.open(DIR)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".jsonl"):
			out.append(DIR.path_join(f))
	out.sort()
	return out


## READ A RECORDING: {header, frames, events} (frames' entities by id: [kind, pos, yaw, status]).
static func read(path: String) -> Dictionary:
	var out: Dictionary = {"header": {}, "frames": [] as Array[Dictionary], "events": [] as Array[Dictionary]}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty():
			continue
		var d: Variant = JSON.parse_string(line)
		if not (d is Dictionary):
			continue
		var row: Dictionary = d
		if row.has("recording"):
			out["header"] = row
		elif row.has("e"):
			var e: Dictionary = {}
			for a: Variant in row["e"] as Array:
				var v: Array = a
				e[int(v[0])] = [int(v[1]), Vector3(float(v[2]), float(v[3]), float(v[4])), float(v[5]), int(v[6])]
			(out["frames"] as Array[Dictionary]).append({"t": float(row["t"]), "e": e})
		elif row.has("ev"):
			(out["events"] as Array[Dictionary]).append(row)
	return out


## Where everyone was at `t`: {id: [kind, pos, yaw, status]}, between the frames either side.
static func state_at(p_frames: Array[Dictionary], t: float) -> Dictionary:
	if p_frames.is_empty():
		return {}
	if t <= float(p_frames[0]["t"]):
		return p_frames[0]["e"]
	var lo: int = 0
	var hi: int = p_frames.size() - 1
	if t >= float(p_frames[hi]["t"]):
		return p_frames[hi]["e"]
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if float(p_frames[mid]["t"]) <= t:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = p_frames[lo]["e"]
	var b: Dictionary = p_frames[hi]["e"]
	var k: float = (t - float(p_frames[lo]["t"])) / maxf(float(p_frames[hi]["t"]) - float(p_frames[lo]["t"]), 0.0001)
	var out: Dictionary = {}
	for id: int in a:
		var va: Array = a[id]
		if not b.has(id):
			out[id] = va
			continue
		var vb: Array = b[id]
		out[id] = [va[0], (va[1] as Vector3).lerp(vb[1] as Vector3, k), lerp_angle(float(va[2]), float(vb[2]), k), va[3] if k < 0.5 else vb[3]]
	return out


## The round's length (its last frame).
func length() -> float:
	return float(frames[frames.size() - 1]["t"]) if not frames.is_empty() else 0.0


func open(path: String) -> void:
	var r: Dictionary = read(path)
	header = r["header"]
	frames = r["frames"]
	events = r["events"]
	_t = 0.0
	for b: Node3D in _bodies.values():
		b.queue_free()
	_bodies.clear()
	_load_level(String(header.get("level", "")))
	_slider.max_value = maxf(length(), 0.1)
	_list.clear()
	for ev: Dictionary in events:
		_list.add_item("%6.1f  %s" % [float(ev["t"]), describe(ev, header)])
	_build_heat()
	print("[Replay] %s: %d frames, %d events, %.0f s" % [path, frames.size(), events.size(), length()])


## What an event says, in words, with the names the header knows.
static func describe(ev: Dictionary, p_header: Dictionary) -> String:
	var who := func(id: Variant) -> String:
		var names: Dictionary = p_header.get("names", {})
		return String(names.get(str(int(id)), "#%d" % int(id)))
	match String(ev["ev"]):
		"status":
			return "%s: status %d -> %d" % [who.call(ev["id"]), int(ev["from"]), int(ev["to"])]
		"action":
			return "%s used %d on %s: %s" % [who.call(ev["actor"]), int(ev["ability"]), who.call(ev["target"]) if int(ev["target"]) != 0 else "nobody",
				"hit" if int(ev["outcome"]) == SpaceTimeActionComponent.Outcome.HIT else "missed" if int(ev["outcome"]) == SpaceTimeActionComponent.Outcome.MISS else "outcome %d" % int(ev["outcome"])]
		"hold":
			return "hold %d done on #%d (%d doing it)" % [int(ev["hold"]), int(ev["target"]), int(ev["doers"])]
		"noise":
			return "noise %d by %s" % [int(ev["kind"]), who.call(ev["source"]) if int(ev["source"]) != 0 else "the world"]
		"phase":
			return "phase %d" % int(ev["phase"])
		"standings":
			return "standings %s" % JSON.stringify(ev["scores"])
	return JSON.stringify(ev)


func _load_level(path: String) -> void:
	if _level != null:
		_level.queue_free()
		_level = null
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path) as PackedScene
	_level = scene.instantiate() as Node3D if scene != null else null
	if _level == null:
		return
	add_child(_level)
	move_child(_level, 0)
	# Its own cameras and lights for play are not the viewer's: the viewer's camera, a plain light.
	for c: Node in _level.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	for env: Node in _level.find_children("*", "WorldEnvironment", true, false):
		env.queue_free()


func _body_for(id: int, kind: int) -> Node3D:
	if _bodies.has(id):
		return _bodies[id]
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 0.9
	m.mesh = cap
	m.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(float(kind) * 0.137, 1.0), 0.7, 0.95)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	n.add_child(m)
	var label := Label3D.new()
	var kinds: Dictionary = header.get("kinds", {})
	var names: Dictionary = header.get("names", {})
	label.text = String(names.get(str(id), kinds.get(str(kind), "#%d" % id)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 1.3
	label.font_size = 40
	n.add_child(label)
	add_child(n)
	_bodies[id] = n
	return n


## WHERE PEOPLE WERE HURT (H): a dot where each status change to injured (1, yellow) or downed (2, red)
## was, and where each ability hit (orange) or missed (blue) was used from.
func _build_heat() -> void:
	if _heat != null:
		_heat.queue_free()
	_heat = Node3D.new()
	_heat.visible = false
	add_child(_heat)
	for ev: Dictionary in events:
		var t: float = float(ev["t"])
		var at: Dictionary = state_at(frames, t)
		var id: int = -1
		var color := Color.WHITE
		match String(ev["ev"]):
			"status":
				if int(ev["to"]) == 1:
					color = Color(1, 0.9, 0.2)
				elif int(ev["to"]) == 2:
					color = Color(1, 0.15, 0.1)
				else:
					continue
				id = int(ev["id"])
			"action":
				id = int(ev["actor"])
				color = Color(1, 0.55, 0.1) if int(ev["outcome"]) == SpaceTimeActionComponent.Outcome.HIT else Color(0.3, 0.6, 1)
			_:
				continue
		if not at.has(id):
			continue
		var dot := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		dot.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot.material_override = mat
		_heat.add_child(dot)
		dot.position = (at[id][1] as Vector3) + Vector3(0, 0.2, 0)


func _process(delta: float) -> void:
	if frames.is_empty():
		return
	if _playing:
		_t = minf(_t + delta * _speed, length())
	_slider.set_value_no_signal(_t)
	var now: Dictionary = state_at(frames, _t)
	for id: int in now:
		var v: Array = now[id]
		var b: Node3D = _body_for(id, int(v[0]))
		b.position = v[1]
		b.rotation.y = float(v[2])
		var st: int = int(v[3])
		b.visible = st != 4 and st != 6   # out, got away
		b.scale = Vector3(1, 0.35, 1) if st == 2 else Vector3.ONE   # downed: lying down
	for id: int in _bodies:
		if not now.has(id):
			_bodies[id].visible = false
	_clock.text = "%s   %5.1f / %.1f s   x%d   %s" % ["▶" if _playing else "❚❚", _t, length(), int(_speed),
		String(_files[_file_index]).get_file() if _file_index >= 0 else recording.get_file()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_playing = not _playing
			KEY_1:
				_speed = 1.0
			KEY_2:
				_speed = 4.0
			KEY_3:
				_speed = 16.0
			KEY_H:
				if _heat != null:
					_heat.visible = not _heat.visible
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				if not _files.is_empty():
					_file_index = clampi(_file_index + (1 if (event as InputEventKey).keycode == KEY_BRACKETRIGHT else -1), 0, _files.size() - 1)
					open(_files[_file_index])
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.position.z = maxf(8.0, _cam.position.z * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.position.z = minf(200.0, _cam.position.z * 1.1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		var mm: InputEventMouseMotion = event
		_cam_pivot.rotation.y -= mm.relative.x * 0.005
		_cam_pivot.rotation.x = clampf(_cam_pivot.rotation.x - mm.relative.y * 0.005, -1.5, -0.2)


func _build_view() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.rotation = Vector3(-1.0, 0.0, 0.0)
	add_child(_cam_pivot)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, 70)
	_cam.current = true
	_cam_pivot.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_clock = Label.new()
	_clock.position = Vector2(16, 12)
	_clock.add_theme_font_size_override(&"font_size", 18)
	_ui.add_child(_clock)
	_slider = HSlider.new()
	_slider.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_slider.offset_left = 16
	_slider.offset_right = -336
	_slider.offset_top = -40
	_slider.offset_bottom = -16
	_slider.step = 0.1
	_slider.value_changed.connect(func(v: float) -> void: _t = v)
	_ui.add_child(_slider)
	_list = ItemList.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_list.offset_left = -320
	_list.offset_top = 12
	_list.offset_bottom = -12
	_list.offset_right = -12
	_list.item_selected.connect(func(i: int) -> void:
		_t = float(events[i]["t"])
		_playing = false)
	_ui.add_child(_list)
	var keys := Label.new()
	keys.text = "Space play/pause · 1/2/3 speed · H where people were hurt · [ ] other recordings · wheel zoom · right-drag turn"
	keys.position = Vector2(16, 40)
	keys.modulate = Color(1, 1, 1, 0.7)
	_ui.add_child(keys)
