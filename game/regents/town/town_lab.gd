extends Node3D
## THE TOWN LAB (Luke, 2026-11-15: "another wardrobe like lab that shows some preset village sets for colors to show
## how unique each can look using exact same models"): open `res://game/regents/town/town_lab.tscn` and press F6 (no
## server). The same little street (three `KitHouse`s, the kit's House D, a stretch of `CastleWall` with towers) in
## every preset `SettlementStyle` (`styles/`), and a style to change live.
##
##   1 Presets   every preset's street side by side           2 One     one street, its style changed in the panel
##   3 Seeds     one style, six streets: each building's nudge   4 Houses  one house in every preset, in a row
##   5 Roofs     the towers' roofs side by side, in the panel's style (`CastleWall.roof_style`)
##   Left / Right   the next street (Presets, Seeds)    L   day, dusk, night    H   the panel
##   right mouse, drag   turn round it        wheel   nearer, farther
##   Save style   writes the panel's style to `styles/custom_<time>.tres` (in the editor)
##
## How it works: `SettlementStyle` (the colors, the weather, each building's spread), `TownKit` (which kit material is
## which slot; dress, merge), `town_surface.gdshader` (the dye). The plan: `docs/regents_rule/SETTLEMENTS_PREP.md`.
## Presentation only: nothing here is in the game yet.
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/town/town_lab.tscn -- <out dir>` saves each view
## as `<out>/townlab_<name>.png`, then quits.

const STYLES_DIR: String = "res://game/regents/town/styles/"
const DEMO_D: String = "res://game/regents/town/houses/demo_house_d.tscn"
const STREET_SHADER: Shader = preload("res://game/regents/town/town_street.gdshader")
const MODES: PackedStringArray = ["Presets", "One", "Seeds", "Houses", "Roofs"]
const LIGHTS: PackedStringArray = ["Day", "Dusk", "Night"]
## A street's footprint (m): the sets are laid out this far apart.
const SET_STEP: Vector2 = Vector2(62, 92)
const PANEL_W: int = 360
## The Roofs view's towers (Luke, 2026-11-15: "we need to workshop the roofs"): title, `CastleWall.RoofStyle`,
## slate, flare, pitch, round towers.
const ROOF_TRIES: Array[Array] = [
	["Cone", CastleWall.RoofStyle.CONE, false, 0.0, 1.8, true],
	["Bell", CastleWall.RoofStyle.CONE, false, 0.45, 2.2, true],
	["Slate bell", CastleWall.RoofStyle.CONE, true, 0.5, 2.6, true],
	["Courses", CastleWall.RoofStyle.STEPPED, false, 0.3, 2.0, true],
	["The kit's own", CastleWall.RoofStyle.KIT, false, 0.0, 2.0, true],
	["Turret", CastleWall.RoofStyle.TURRET, false, 0.4, 2.2, true],
	["Open", CastleWall.RoofStyle.OPEN, false, 0.0, 2.0, true],
	["Square, hipped", CastleWall.RoofStyle.CONE, false, 0.3, 1.3, false],
]

var mode: int = 0
var light: int = 0
var styles: Array[SettlementStyle] = []
## The lab's own style (One): a copy of a preset, changed by the panel.
var style: SettlementStyle = null
## Which street the camera looks at.
var focus: int = -1
## The streets built for this mode (the suite reads them).
var sets: Array[Settlement] = []
## Each street's paving material, in `sets`' order (Presets, One, Seeds).
var streets: Array[ShaderMaterial] = []

var _root: Node3D = null
var _cam: Camera3D = null
var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _yaw: float = 0.35
var _pitch: float = -0.38
var _dist: float = 190.0
var _center: Vector3 = Vector3.ZERO
var _dragging: bool = false
var _info: Label = null
var _panel: PanelContainer = null
var _ui: VBoxContainer = null
var _preset_pick: int = 1
var _quiet: bool = false


func _ready() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(STYLES_DIR)
	files.sort()
	for f: String in files:
		if f.ends_with(".tres") and not f.begins_with("custom_"):
			styles.append(load(STYLES_DIR + f) as SettlementStyle)
	style = styles[mini(_preset_pick, styles.size() - 1)].copy()
	_build_world()
	_build_ui()
	set_light(0)
	show_mode(0)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_shoot.call_deferred(args[0])


func _build_world() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	sky.sky_material = _sky
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 400.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.43, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	_root = Node3D.new()
	_root.name = "Streets"
	add_child(_root)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	add_child(_cam)


## One street under a settlement of style `s`, at `at`: what every mode shows.
func make_street(s: SettlementStyle, at: Vector3, title: String, street_seed: int = 0) -> Settlement:
	var st := Settlement.new()
	st.style = s
	st.town_seed = street_seed
	st.position = at
	var a := KitHouse.new()
	a.width = 3
	a.depth = 3
	a.floors = 2
	a.ground = KitHouse.Finish.UNEVEN_BRICK
	a.upper = KitHouse.Finish.PLASTER
	a.house_seed = 11
	a.position = Vector3(-15, 0, 2)
	st.add_child(a)
	var b := KitHouse.new()
	b.width = 2
	b.depth = 2
	b.floors = 1
	b.ground = KitHouse.Finish.WOOD_WEAR
	b.upper = KitHouse.Finish.WOOD_WEAR
	b.tiles = KitHouse.Tiles.FLAT
	b.house_seed = 12
	b.position = Vector3(-4, 0, 4)
	st.add_child(b)
	var d: Node3D = TownKit.instance_building(load(DEMO_D) as PackedScene)
	d.position = Vector3(7, 0, 2)
	st.add_child(d)
	var c := KitHouse.new()
	c.width = 4
	c.depth = 3
	c.floors = 3
	c.ground = KitHouse.Finish.PLASTER
	c.upper = KitHouse.Finish.WOOD_BRICK
	c.stone_gables = true
	c.round_openings = false
	c.house_seed = 13
	c.position = Vector3(21, 0, 1)
	st.add_child(c)
	var w := CastleWall.new()
	w.corners = PackedVector3Array([Vector3(-24, 0, -14), Vector3(30, 0, -14)])
	w.closed = false
	w.gates = PackedInt32Array([0])
	w.height = 8.0
	w.thickness = 2.2
	w.tower_radius = 3.0
	w.tower_height = 12.0
	st.add_child(w)
	# The street in front: the style's paving (code-made stones, never a wall's texture).
	var road := MeshInstance3D.new()
	road.name = "Street"
	var pm := PlaneMesh.new()
	pm.size = Vector2(56, 9)
	road.mesh = pm
	road.position = Vector3(3, 0.03, 10.5)
	var rm := ShaderMaterial.new()
	rm.shader = STREET_SHADER
	road.material_override = rm
	st.add_child(road)
	streets.append(rm)
	paint_street(rm, s)
	# Furnished: a small market down the street, things at the doors (the same dice for every street).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	TownFurnish.market(st, Vector3(3, 0, 10.5), Vector2(26, 4.5), 2.6, 4.0, rng)
	for h: KitHouse in [a, b, c]:
		TownFurnish.door(h, rng, 1.0, 0.5, 1.0)
	var label := Label3D.new()
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 160
	label.outline_size = 36
	label.pixel_size = 0.02
	label.position = Vector3(3, 22, 0)
	label.no_depth_test = true
	st.add_child(label)
	_root.add_child(st)
	sets.append(st)
	return st


## A street's material from a style's paving.
static func paint_street(m: ShaderMaterial, s: SettlementStyle) -> void:
	m.set_shader_parameter(&"paving", s.paving_color())
	m.set_shader_parameter(&"paving_mix", s.paving_mix)
	m.set_shader_parameter(&"paving_pattern", s.paving_pattern)


## One roof to try: a short wall between two towers topped as `spec` says (`ROOF_TRIES`), in the lab's style.
func make_roof_try(spec: Array, at: Vector3) -> Settlement:
	var st := Settlement.new()
	st.style = style
	st.position = at
	var w := CastleWall.new()
	w.corners = PackedVector3Array([Vector3(-8, 0, 0), Vector3(8, 0, 0)])
	w.closed = false
	w.gates = PackedInt32Array()
	w.height = 9.0
	w.thickness = 2.2
	w.tower_radius = 3.5
	w.tower_height = 14.0
	w.roof_style = spec[1] as CastleWall.RoofStyle
	w.roof_slate = bool(spec[2])
	w.roof_flare = float(spec[3])
	w.roof_pitch = float(spec[4])
	w.round_towers = bool(spec[5])
	st.add_child(w)
	var label := Label3D.new()
	label.text = str(spec[0])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.outline_size = 24
	label.pixel_size = 0.02
	label.position = Vector3(0, 30, 0)
	label.no_depth_test = true
	st.add_child(label)
	_root.add_child(st)
	sets.append(st)
	return st


func _clear() -> void:
	for c: Node in _root.get_children():
		c.free()
	sets.clear()
	streets.clear()


func show_mode(m: int) -> void:
	mode = posmod(m, MODES.size())
	_clear()
	match mode:
		0:
			for i: int in styles.size():
				var col: int = i % 4
				var row: int = floori(i / 4.0)
				make_street(styles[i], Vector3((col - 1.5) * SET_STEP.x, 0, (row - 0.5) * SET_STEP.y), styles[i].title)
		1:
			make_street(style, Vector3.ZERO, style.title)
		2:
			for i: int in 6:
				var col: int = i % 3
				var row: int = floori(i / 3.0)
				make_street(style, Vector3((col - 1.0) * SET_STEP.x, 0, (row - 0.5) * SET_STEP.y), "%s, seed %d" % [style.title, i], i * 7919)
		3:
			for i: int in styles.size():
				var st := Settlement.new()
				st.style = styles[i]
				st.position = Vector3((i - (styles.size() - 1) * 0.5) * 11.0, 0, 0)
				var h := KitHouse.new()
				h.width = 2
				h.depth = 3
				h.floors = 2
				h.ground = KitHouse.Finish.UNEVEN_BRICK
				h.upper = KitHouse.Finish.PLASTER
				h.house_seed = 5
				st.add_child(h)
				var label := Label3D.new()
				label.text = styles[i].title
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.font_size = 64
				label.outline_size = 16
				label.pixel_size = 0.01
				label.position = Vector3(0, 13, 0)
				st.add_child(label)
				_root.add_child(st)
				sets.append(st)
		4:
			for i: int in ROOF_TRIES.size():
				var col: int = i % 4
				var row: int = floori(i / 4.0)
				make_roof_try(ROOF_TRIES[i], Vector3((col - 1.5) * 34.0, 0, (row - 0.5) * 46.0))
	focus = -1
	_frame_mode()
	_fill_panel()
	_refresh_info()


## The camera over the whole mode: [distance, pitch, yaw, center height] per mode.
func _frame_mode() -> void:
	var frames: Array[Vector4] = [Vector4(175, -0.5, 0.2, 0), Vector4(62, -0.24, 0.3, 6), Vector4(150, -0.5, 0.2, 0),
		Vector4(58, -0.16, 0.0, 5), Vector4(150, -0.3, 0.15, 8)]
	var f: Vector4 = frames[mode]
	_center = Vector3(0, f.w, 0)
	_dist = f.x
	_pitch = f.y
	_yaw = f.z
	_place_camera()


## The camera on street i (Left / Right), or back over them all (out of range).
func set_focus(i: int) -> void:
	if sets.is_empty():
		return
	if i < 0 or i >= sets.size():
		focus = -1
		_frame_mode()
		_refresh_info()
		return
	focus = i
	_center = sets[focus].position + Vector3(3, 6, 0)
	_dist = 52.0
	_yaw = 0.25
	_pitch = -0.22
	if mode == 4:
		_center = sets[focus].position + Vector3(0, 13, 0)
		_dist = 34.0
		_pitch = -0.12
	_place_camera()
	_refresh_info()


func _place_camera() -> void:
	var off := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at_from_position(_center + off, _center)


func set_light(i: int) -> void:
	light = posmod(i, LIGHTS.size())
	match light:
		0:
			_sun.rotation_degrees = Vector3(-46, -35, 0)
			_sun.light_color = Color(1.0, 0.96, 0.9)
			_sun.light_energy = 1.25
			_sky.sky_top_color = Color(0.35, 0.52, 0.78)
			_sky.sky_horizon_color = Color(0.72, 0.78, 0.84)
			_env.ambient_light_energy = 1.0
			TownKit.set_night(0.0)
		1:
			_sun.rotation_degrees = Vector3(-9, -110, 0)
			_sun.light_color = Color(1.0, 0.62, 0.36)
			_sun.light_energy = 1.0
			_sky.sky_top_color = Color(0.24, 0.26, 0.45)
			_sky.sky_horizon_color = Color(0.95, 0.6, 0.38)
			_env.ambient_light_energy = 0.6
			TownKit.set_night(0.5)
		2:
			_sun.rotation_degrees = Vector3(-55, 40, 0)
			_sun.light_color = Color(0.55, 0.65, 0.95)
			_sun.light_energy = 0.12
			_sky.sky_top_color = Color(0.01, 0.015, 0.04)
			_sky.sky_horizon_color = Color(0.05, 0.06, 0.1)
			_env.ambient_light_energy = 0.25
			TownKit.set_night(1.0)
	_refresh_info()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist / 1.12, 8.0)
			_place_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.12, 600.0)
			_place_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch - mm.relative.y * 0.006, -1.45, 0.2)
		_place_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_5:
			show_mode(k - KEY_1)
		elif k == KEY_RIGHT:
			set_focus(focus + 1)
		elif k == KEY_LEFT:
			set_focus(sets.size() - 1 if focus == -1 else focus - 1)
		elif k == KEY_L:
			set_light(light + 1)
		elif k == KEY_H:
			_panel.visible = not _panel.visible


# THE PANEL: the style's colors and weather (One, Seeds), the preset to start from, the light, saving.

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(14, 10)
	_info.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_info.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_info.add_theme_constant_override(&"outline_size", 5)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_info)
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_W
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_ui = VBoxContainer.new()
	_ui.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	scroll.add_child(_ui)
	layer.add_child(_panel)


func _fill_panel() -> void:
	if _ui == null:
		return
	_quiet = true
	for c: Node in _ui.get_children():
		c.free()
	var modes := HBoxContainer.new()
	for i: int in MODES.size():
		_button(modes, MODES[i], show_mode.bind(i))
	_ui.add_child(modes)
	var lights := HBoxContainer.new()
	for i: int in LIGHTS.size():
		_button(lights, LIGHTS[i], set_light.bind(i))
	_ui.add_child(lights)
	if mode == 1 or mode == 2:
		_heading("Start from")
		var names: PackedStringArray = []
		for s: SettlementStyle in styles:
			names.append(s.title)
		var pick := OptionButton.new()
		for n: String in names:
			pick.add_item(n)
		pick.selected = _preset_pick
		pick.item_selected.connect(_pick_preset)
		_ui.add_child(pick)
		_heading("Colors (alpha: how much; 0 keeps the kit's painting)")
		for slot: StringName in SettlementStyle.SLOTS:
			_color_row(String(slot).capitalize(), style.get(slot) as Color, _set_field.bind(slot))
		_heading("Weather")
		for n: StringName in [&"wear", &"moss", &"grime", &"grime_height", &"snow", &"fade"]:
			_slider(String(n).capitalize(), float(style.get(n)), _range_of(n), _set_field.bind(n))
		for c: StringName in [&"wear_color", &"moss_color", &"grime_color"]:
			_color_row(String(c).capitalize(), style.get(c) as Color, _set_field.bind(c))
		_heading("Each building")
		for n: StringName in [&"jitter_hue", &"jitter_value", &"jitter_wear"]:
			_slider(String(n).capitalize(), float(style.get(n)), _range_of(n), _set_field.bind(n))
		_heading("Streets (the paving color is the Paving slot above)")
		_color_row("Paving mix", style.paving_mix, _set_field.bind(&"paving_mix"))
		var laying := OptionButton.new()
		laying.add_item("Cobbles")
		laying.add_item("Setts")
		laying.selected = style.paving_pattern
		laying.item_selected.connect(func(i: int) -> void: _set_field(i, &"paving_pattern"))
		_ui.add_child(laying)
		_heading("Night")
		_color_row("Window light", style.window_light, _set_field.bind(&"window_light"))
		_slider("Lit share", style.lit_share, Vector2(0, 1), _set_field.bind(&"lit_share"))
		var save := HBoxContainer.new()
		_button(save, "Save style", func() -> void: print("saved: ", save_style()))
		_ui.add_child(save)
	else:
		_heading("Presets (%d)" % styles.size())
		for s: SettlementStyle in styles:
			var l := Label.new()
			l.text = "%s: %s" % [s.title, s.note]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_ui.add_child(l)
	_quiet = false


static func _range_of(n: StringName) -> Vector2:
	match n:
		&"wear":
			return Vector2(0, 1.5)
		&"grime_height":
			return Vector2(0.2, 4.0)
		&"jitter_hue":
			return Vector2(0, 0.15)
		&"jitter_value":
			return Vector2(0, 0.5)
	return Vector2(0, 1)


func _pick_preset(i: int) -> void:
	if _quiet:
		return
	_preset_pick = i
	style = styles[i].copy()
	show_mode(mode)


## A panel change: onto the lab's style, then onto every material made for it.
func _set_field(v: Variant, field: StringName) -> void:
	if _quiet:
		return
	style.set(field, v)
	TownKit.refresh(style)
	for i: int in mini(sets.size(), streets.size()):
		if sets[i].style == style:
			paint_street(streets[i], style)


## The lab's style to `styles/custom_<time>.tres` (in the editor: res:// is read-only in an export).
func save_style() -> String:
	var path: String = STYLES_DIR + "custom_%d.tres" % int(Time.get_unix_time_from_system())
	style.title = "%s (custom)" % style.title.trim_suffix(" (custom)")
	var err: Error = ResourceSaver.save(style, path)
	return path if err == OK else ""


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	_ui.add_child(l)


func _button(parent: Control, text: String, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(act)
	parent.add_child(b)
	return b


func _color_row(text: String, c: Color, act: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var pick := ColorPickerButton.new()
	pick.color = c
	pick.edit_alpha = true
	pick.custom_minimum_size = Vector2(160, 26)
	pick.color_changed.connect(func(col: Color) -> void: act.call(col))
	row.add_child(pick)
	_ui.add_child(row)


func _slider(text: String, v: float, span: Vector2, act: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = span.x
	s.max_value = span.y
	s.step = 0.01
	s.value = v
	s.custom_minimum_size = Vector2(170, 0)
	s.value_changed.connect(func(x: float) -> void: act.call(x))
	row.add_child(s)
	_ui.add_child(row)


func _refresh_info() -> void:
	if _info == null:
		return
	var what: String = MODES[mode]
	if focus >= 0 and focus < sets.size():
		what += ": " + (str(ROOF_TRIES[focus][0]) if mode == 4 else sets[focus].style.title)
	_info.text = "THE TOWN LAB   %s   %s   (1-5 modes, Left/Right a street, L light, H panel, right mouse turn, wheel zoom)" % [
		what, LIGHTS[light]]


## The shots: each mode, each preset's street close, the presets at dusk and by night, a style changed live; then quit.
func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_panel.visible = false
	await _snap(dir, "presets_day", func() -> void: show_mode(0))
	for i: int in styles.size():
		await _snap(dir, "street_%d_%s" % [i + 1, styles[i].title.to_snake_case()], set_focus.bind(i))
	await _snap(dir, "presets_night", func() -> void:
		show_mode(0)
		set_light(2))
	await _snap(dir, "presets_dusk", func() -> void: set_light(1))
	await _snap(dir, "houses_day", func() -> void:
		set_light(0)
		show_mode(3))
	await _snap(dir, "roofs_day", func() -> void: show_mode(4))
	for i: int in ROOF_TRIES.size():
		await _snap(dir, "roof_%d_%s" % [i + 1, str(ROOF_TRIES[i][0]).to_snake_case()], set_focus.bind(i))
	await _snap(dir, "seeds_day", func() -> void: show_mode(2))
	await _snap(dir, "one_day", func() -> void: show_mode(1))
	await _snap(dir, "one_edited", func() -> void:
		_set_field(Color(0.55, 0.75, 0.85, 1.0), &"plaster")
		_set_field(Color(0.15, 0.2, 0.3, 1.0), &"roof")
		_set_field(0.6, &"snow"))
	AppExit.quit(get_tree(), 0)


func _snap(dir: String, shot: String, setup: Callable) -> void:
	setup.call()
	for f: int in 8:
		await get_tree().process_frame
	var path: String = dir.path_join("townlab_%s.png" % shot)
	get_viewport().get_texture().get_image().save_png(path)
	print("shot: ", path)
