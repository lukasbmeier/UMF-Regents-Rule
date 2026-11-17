extends Node3D
## THE VFX LAB (Luke, 2026-11-14: "labs that show case really cool looking vfx", procedural first): open
## `res://game/regents/vfx/vfx_lab.tscn` and press F6 (no server). The adventurer and a foe on a patch of ground in
## the glade's light, and each SHOWCASE plays its effects as they would happen in a fight: the cast in the hand, the
## missile, the blast; the circle, its warning and its landing; and so on.
##
##   the list (or Up / Down)   pick a showcase; it plays
##   Space                      play it again          L   loop it      O   as another player sees it (lighter)
##   the speed buttons ( [ ] )  full speed down to a tenth: watch a blast form
##   Day / Dusk / Night         the light: glow shows most at night
##   right mouse, drag          turn round the stage    wheel   nearer, farther
##
## Each effect is a scene in `game/regents/vfx/effects/` whose root's values (Inspector) are its look: open one,
## change it, run the lab again. How they are built: `VfxEffect`, `VfxKit`, the shaders in `vfx/shaders/`. Nothing
## is an image file. Presentation only (hard rule 11): none of this is in the game's fights yet.
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/vfx/vfx_lab.tscn -- <out dir>` plays every
## showcase and saves a contact sheet of six moments of each (`<out>/vfx_<name>.png`), then quits. A second argument,
## a showcase's name, shoots that one only. The word `others` among the arguments shoots them as ANOTHER player's
## (the lighter version, `VfxEffect.lighter`); O toggles that in the lab. `-- cost` measures both.

## Each frame, after the lab has moved things: what a showcase waits on (its own signal, so a showcase still
## waiting when the lab closes is simply dropped, never resumed on a lab that is gone).
signal ticked()

const FX: String = "res://game/regents/vfx/effects/"
const ADVENTURER: String = "res://game/regents/content/character/adventurer.tres"
const SKELETON: String = "res://game/regents/content/character/skeleton_warrior.tres"
const IMP: String = "res://game/regents/content/character/imp.tres"
const AXE: String = "res://game/regents/content/item/steel_axe.tres"
const SWORD: String = "res://game/regents/content/item/steel_sword.tres"
## How far behind a swing's wind-up the lab's clip lands its blow (the game times it from the server).
const CLIP_LAG_S: float = 0.06
## Where the foe stands (ahead of the adventurer, who faces -Z).
const FOE_AT: Vector3 = Vector3(0.0, 0.0, -9.0)
const SPEEDS: Array[float] = [1.0, 0.5, 0.25, 0.1]
const LIGHTS: PackedStringArray = ["Day", "Dusk", "Night"]
## A contact sheet: 3 x 2 frames of this size.
const SHOT_SIZE: Vector2i = Vector2i(640, 360)

## [name, what it shows, the method that plays it (its name), the moments to shoot (s), the camera: yaw, pitch (deg), distance,
## and its focus]
var showcases: Array[Array] = [
	["Fireball", "Q: a 0.6 s cast, the missile at 20 m/s, a 3 m blast. fire_charge, fire_missile, fire_blast.tscn",
		"_fireball", [0.3, 0.62, 0.8, 1.12, 1.3, 1.9], [72.0, -8.0, 9.0, Vector3(0, 1.1, -4.5)]],
	["Frost Ring", "E: a 1 s cast, then a 4 m circle that lands a second later. frost_charge, frost_ring.tscn",
		"_frost_ring", [0.6, 1.3, 1.85, 2.08, 2.4, 3.4], [50.0, -22.0, 11.5, Vector3(0, 0.8, -6.5)]],
	["Blink", "R: 8 m at once (shown shorter here). blink.tscn", "_blink",
		[0.04, 0.1, 0.16, 0.24, 0.4, 0.7], [110.0, -12.0, 8.0, Vector3(2.2, 1.0, -1.8)]],
	["Gale", "F: everything within 8 m and 60 degrees thrown back. gale.tscn", "_gale",
		[0.06, 0.14, 0.22, 0.32, 0.45, 0.8], [55.0, -22.0, 9.0, Vector3(0, 0.8, -3.5)]],
	["Axe Heavy", "The axe's last hit: its cut follows the axe's real path. blade_cut.tscn", "_axe",
		[0.3, 0.42, 0.5, 0.58, 0.66, 0.9], [70.0, -10.0, 5.0, Vector3(0, 1.0, -1.2)]],
	["Sword String", "The sword's three hits, each cut along the blade: what a plain swing would wear. blade_cut.tscn",
		"_sword", [0.16, 0.24, 0.62, 0.72, 1.12, 1.26], [60.0, -14.0, 5.0, Vector3(0, 1.0, -1.0)]],
	["Axe: old | new", "The same heavy hit at once: on the left the plain trail the game drew before (SwingTrail with its crescent off), on the right the cut it wears now. Hit feedback is not in either.",
		"_compare_axe", [0.3, 0.42, 0.5, 0.58, 0.66, 0.9], [14.0, -22.0, 5.2, Vector3(0, 1.0, -1.0)]],
	["Sword: old | new", "The sword's three hits at once: on the left the plain trail the game drew before, on the right the cut it wears now. Hit feedback is not in either.",
		"_compare_sword", [0.16, 0.24, 0.62, 0.72, 1.12, 1.26], [14.0, -22.0, 5.2, Vector3(0, 1.0, -1.0)]],
	["Parry", "A foe's cut turned at the last moment. parry_flash.tscn", "_parry",
		[0.66, 0.7, 0.74, 0.8, 0.9, 1.1], [75.0, -5.0, 4.2, Vector3(0, 1.3, -0.9)]],
	["Bolt", "Left click: no cast time, a flash in the hand (bolt_cast.tscn), the missile at 32 m/s, a violet flash where it ends: the game's own look (bolt_look.tscn, bolt_hit.tscn).",
		"_bolt", [0.08, 0.12, 0.18, 0.26, 0.4, 0.62], [70.0, -8.0, 7.0, Vector3(0, 1.2, -3.0)]],
	["Meteor", "R: a 2 s cast, standing still, then a 10 m circle that lands 1.5 s later. Its ring is the one the game draws for it (SpellLooks.ring_scene).",
		"_meteor", [1.0, 2.3, 3.0, 3.55, 3.8, 4.6], [45.0, -26.0, 15.0, Vector3(0, 0.6, -7.0)]],
	["Cinder Ring", "The imp's warning (1.5 s) and its blast, under the adventurer. cinder_ring.tscn", "_cinder",
		[0.4, 1.0, 1.6, 1.85, 2.05, 2.6], [40.0, -24.0, 9.5, Vector3(0, 0.6, -1.5)]],
]

var current: int = 0
var looping: bool = false
var speed_index: int = 0
var light_index: int = 0

var _stage: Node3D = null
var _hero_root: Node3D = null
var _hero: Mannequin = null
var _foe_root: Node3D = null
var _foe: Mannequin = null
var _imp_root: Node3D = null
var _imp: Mannequin = null
var _cam: Camera3D = null
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _sky: ProceduralSkyMaterial = null
var _yaw: float = 55.0
var _pitch: float = -12.0
var _dist: float = 13.0
var _focus: Vector3 = Vector3(0, 1, -5)
var _shake: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _run: int = 0
var _running: bool = false
## [effect, the Mannequin, its hand bones, how far ahead of them (m), toward what]: kept in front of the casting hand
## (or between two) as it moves (`_cast_point`).
var _follow: Array[Array] = []
var _about: Label = null
var _stats: Label = null
var _list: VBoxContainer = null
var _speed_label: Label = null
var _loop_button: Button = null
var _shooting: bool = false
var _ui: CanvasLayer = null
## The weapon in the adventurer's hand for a melee showcase (freed by `_reset`).
var _held: HeldItem = null
## THE COMPARISONS: a second adventurer and a second skeleton beside the first pair, each pair under a tag ("Old",
## "New"); hidden but in a comparison.
var _twin_root: Node3D = null
var _twin: Mannequin = null
var _twin_foe_root: Node3D = null
var _twin_foe: Mannequin = null
var _twin_held: HeldItem = null
var _tags: Array[Label3D] = []
## Today's trails being drawn: [the RibbonTrail, the HeldItem, its blade in the item's frame, from, until (the lab's
## clock)], as `SwingTrail` draws one (`_today_cut`).
var _plain: Array[Array] = []
## The lab's own clock since the showcase began (s, slowed with it): the shots wait on it, so a first-use shader
## compile's stall never shifts them.
var clock: float = 0.0
## Every effect played as another player's (the lighter version; O, or `others` on the command line).
var others: bool = false


func _ready() -> void:
	_build_world()
	_build_ui()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("others"):
		others = true
		args.remove_at(args.find("others"))
	if not args.is_empty() and not args[0].begins_with("--"):   # (the test runner passes its own "--only=")
		_shoot.call_deferred(args[0], args[1] if args.size() > 1 else "")
	else:
		_select.call_deferred(0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	AbilityVfxSet.release()   # the Bolt's and Meteor's showcases read the effects table


# ---------------------------------------------------------------- the stage

func _build_world() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.fog_enabled = true
	_env.fog_density = 0.006
	_env.fog_aerial_perspective = 0.5
	_env.ssao_enabled = true
	_env.ssao_light_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_set_light(0)
	# The ground: a patch of grass, its color broken by a noise (no image).
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	var tint := Gradient.new()
	tint.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	tint.colors = PackedColorArray([Color(0.22, 0.33, 0.15), Color(0.32, 0.45, 0.2), Color(0.42, 0.5, 0.26)])
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.color_ramp = tint
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 5
	tex.noise = fn
	gm.albedo_texture = tex
	gm.uv1_scale = Vector3(14, 14, 14)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	# A few standing stones for the light and the bending air to play on.
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.48, 0.47, 0.45)
	stone.roughness = 0.9
	for p: Vector3 in [Vector3(-5.0, 0, -7.0), Vector3(-3.5, 0, -15.0), Vector3(5.5, 0, -17.0), Vector3(-7.0, 0, -1.0)]:
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 2.2, 0.7)
		rock.mesh = box
		rock.material_override = stone
		rock.position = p + Vector3(0, 1.1, 0)
		rock.rotation.y = p.x
		add_child(rock)
	_hero_root = Node3D.new()
	_hero_root.name = "Adventurer"
	add_child(_hero_root)
	_hero = _mannequin(ADVENTURER, _hero_root)
	_foe_root = Node3D.new()
	_foe_root.name = "Foe"
	_foe_root.position = FOE_AT
	_foe_root.rotation.y = PI
	add_child(_foe_root)
	_foe = _mannequin(SKELETON, _foe_root)
	_imp_root = Node3D.new()
	_imp_root.name = "Imp"
	_imp_root.position = Vector3(3.5, 0, -10.0)
	_imp_root.rotation.y = PI + 0.3
	_imp_root.visible = false
	add_child(_imp_root)
	_imp = _mannequin(IMP, _imp_root)
	_twin_root = Node3D.new()
	_twin_root.name = "Twin"
	_twin_root.visible = false
	add_child(_twin_root)
	_twin = _mannequin(ADVENTURER, _twin_root)
	_twin_foe_root = Node3D.new()
	_twin_foe_root.name = "TwinFoe"
	_twin_foe_root.rotation.y = PI
	_twin_foe_root.visible = false
	add_child(_twin_foe_root)
	_twin_foe = _mannequin(SKELETON, _twin_foe_root)
	for i: int in 2:
		var tag := Label3D.new()
		tag.text = "Old" if i == 0 else "New"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 64
		tag.outline_size = 12
		tag.pixel_size = 0.006
		tag.position.y = 2.25
		tag.visible = false
		(_twin_root if i == 0 else _hero_root).add_child(tag)
		_tags.append(tag)
	_stage = Node3D.new()
	_stage.name = "Effects"
	add_child(_stage)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()
	_place_camera()


func _mannequin(path: String, parent: Node3D) -> Mannequin:
	var m := Mannequin.new()
	m.definition = load(path) as EntityDefinition
	parent.add_child(m)
	return m


func _set_light(i: int) -> void:
	light_index = i
	match i:
		0:   # the glade's day (frontier.tscn)
			_sky.sky_top_color = Color(0.36, 0.55, 0.82)
			_sky.sky_horizon_color = Color(0.7, 0.78, 0.84)
			_sky.ground_horizon_color = Color(0.62, 0.66, 0.6)
			_sun.light_color = Color(1, 0.92, 0.78)
			_sun.light_energy = 1.4
			_sun.rotation_degrees = Vector3(-32, 35, 0)
			_env.fog_light_color = Color(0.7, 0.77, 0.83)
			_env.ambient_light_energy = 1.0
		1:   # dusk: a low, warm sun
			_sky.sky_top_color = Color(0.2, 0.25, 0.45)
			_sky.sky_horizon_color = Color(0.85, 0.5, 0.35)
			_sky.ground_horizon_color = Color(0.35, 0.3, 0.28)
			_sun.light_color = Color(1, 0.6, 0.4)
			_sun.light_energy = 0.8
			_sun.rotation_degrees = Vector3(-8, 70, 0)
			_env.fog_light_color = Color(0.6, 0.45, 0.4)
			_env.ambient_light_energy = 0.6
		_:   # night: a faint blue moon
			_sky.sky_top_color = Color(0.02, 0.03, 0.07)
			_sky.sky_horizon_color = Color(0.06, 0.08, 0.14)
			_sky.ground_horizon_color = Color(0.03, 0.04, 0.05)
			_sun.light_color = Color(0.55, 0.65, 1.0)
			_sun.light_energy = 0.15
			_sun.rotation_degrees = Vector3(-45, -30, 0)
			_env.fog_light_color = Color(0.05, 0.06, 0.1)
			_env.ambient_light_energy = 0.25


func _place_camera() -> void:
	var dir: Vector3 = Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	var offset: Vector3 = (dir * cos(deg_to_rad(-_pitch)) + Vector3.UP * sin(deg_to_rad(-_pitch))) * _dist
	var shake: Vector3 = Vector3.ZERO
	if _shake_left > 0.0:
		var k: float = _shake * (_shake_left / maxf(_shake_total, 0.001))
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * k * 0.25
	_cam.position = _focus + offset + shake
	_cam.look_at(_focus + shake * 0.5, Vector3.UP)


func _process(delta: float) -> void:
	clock += delta
	for f: Array in _follow:
		if is_instance_valid(f[0]):
			(f[0] as Node3D).global_position = _cast_point(f[1] as Mannequin, f[2] as Array, float(f[3]), f[4] as Vector3)
	for p: Array in _plain:
		if not is_instance_valid(p[0]) or not is_instance_valid(p[1]) or clock < float(p[3]) or clock > float(p[4]):
			continue
		var held: HeldItem = p[1] as HeldItem
		var blade: Array = p[2] as Array
		(p[0] as RibbonTrail).add_blade(held.global_transform * (blade[0] as Vector3), held.global_transform * (blade[1] as Vector3))
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
	_place_camera()
	if _stats != null:
		var alive: int = 0
		var systems: int = 0
		for p: Node in _stage.find_children("*", "GPUParticles3D", true, false):
			var gp: GPUParticles3D = p as GPUParticles3D
			if gp.is_visible_in_tree():
				systems += 1
				alive += gp.amount
		_stats.text = "%d fps   %d draw calls   %d particle systems (%d particles at most)" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), systems, alive]
	ticked.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_RIGHT:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		_yaw -= rel.x * 0.3
		_pitch = clampf(_pitch - rel.y * 0.3, -80.0, 10.0)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b: MouseButton = (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 2.0)
		elif b == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 60.0)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_O:
				others = not others
				_select(current)
			KEY_SPACE:
				replay()
			KEY_L:
				_set_loop(not looping)
			KEY_UP:
				_select(wrapi(current - 1, 0, showcases.size()))
			KEY_DOWN:
				_select(wrapi(current + 1, 0, showcases.size()))
			KEY_BRACKETLEFT:
				_set_speed(mini(speed_index + 1, SPEEDS.size() - 1))
			KEY_BRACKETRIGHT:
				_set_speed(maxi(speed_index - 1, 0))


# ---------------------------------------------------------------- the panel

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui = layer
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.current().theme()
	layer.add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "VFX lab"
	title.add_theme_font_size_override(&"font_size", 22)
	col.add_child(title)
	_list = VBoxContainer.new()
	col.add_child(_list)
	for i: int in showcases.size():
		var index: int = i
		var b := Button.new()
		b.text = String(showcases[i][0])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _select(index))
		_list.add_child(b)
	col.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	col.add_child(row)
	_button(row, "Play (Space)", replay)
	_loop_button = _button(row, "Loop (L)", func() -> void: _set_loop(not looping))
	_loop_button.toggle_mode = true
	var speeds := HBoxContainer.new()
	col.add_child(speeds)
	_speed_label = Label.new()
	speeds.add_child(_speed_label)
	for i: int in SPEEDS.size():
		var s: int = i
		_button(speeds, "%sx" % _speed_text(SPEEDS[i]), func() -> void: _set_speed(s))
	var lights := HBoxContainer.new()
	col.add_child(lights)
	for i: int in LIGHTS.size():
		var l: int = i
		_button(lights, LIGHTS[i], func() -> void: _set_light(l))
	_set_speed(0)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -64
	bottom.offset_left = 16
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_about = Label.new()
	_about.add_theme_font_size_override(&"font_size", 18)
	bottom.add_child(_about)
	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.7)
	bottom.add_child(_stats)
	var hint := Label.new()
	hint.text = "right mouse: turn   wheel: nearer   Up/Down: showcase   [ ]: speed"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint.position = Vector2(-460, 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(hint)


func _button(parent: Control, text: String, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(act)
	parent.add_child(b)
	return b


func _speed_text(s: float) -> String:
	return "1" if s >= 1.0 else ("1/%d" % roundi(1.0 / s))


func _set_speed(i: int) -> void:
	speed_index = i
	Engine.time_scale = SPEEDS[i]
	if _speed_label != null:
		_speed_label.text = "Speed %sx  " % _speed_text(SPEEDS[i])


func _set_loop(on: bool) -> void:
	looping = on
	if _loop_button != null:
		_loop_button.button_pressed = on
	if on and not _running:
		replay()


func _select(i: int) -> void:
	current = i
	for k: int in _list.get_child_count():
		(_list.get_child(k) as Button).button_pressed = k == i
	var view: Array = showcases[i][4] as Array
	_yaw = float(view[0])
	_pitch = float(view[1])
	_dist = float(view[2])
	_focus = view[3] as Vector3
	_about.text = "%s   %s" % [showcases[i][0], showcases[i][1]]
	replay()


# ---------------------------------------------------------------- playing

## Clear the stage and play the current showcase from the start.
func replay() -> void:
	_run += 1
	clock = 0.0
	_play(_run)


func _play(run: int) -> void:
	_reset()
	_running = true
	await _showcase(String(showcases[current][2]), run)
	if run != _run:
		return
	await _wait(0.8, run)
	_running = false
	if run == _run and looping and not _shooting:
		replay()


func _showcase(method: String, run: int) -> void:
	match method:
		"_fireball":
			await _fireball(run)
		"_frost_ring":
			await _frost_ring(run)
		"_blink":
			await _blink(run)
		"_gale":
			await _gale(run)
		"_axe":
			await _axe(run)
		"_sword":
			await _sword(run)
		"_compare_axe":
			await _compare(run, AXE, [40008], true)
		"_compare_sword":
			await _compare(run, SWORD, [40001, 40002, 40003], false)
		"_parry":
			await _parry(run)
		"_cinder":
			await _cinder(run)
		"_bolt":
			await _bolt(run)
		"_meteor":
			await _meteor(run)


func _reset() -> void:
	for c: Node in _stage.get_children():
		c.queue_free()
	_follow.clear()
	if _held != null and is_instance_valid(_held):
		_held.queue_free()
	_held = null
	if _twin_held != null and is_instance_valid(_twin_held):
		_twin_held.queue_free()
	_twin_held = null
	_plain.clear()
	_twin_root.visible = false
	_twin_foe_root.visible = false
	for tag: Label3D in _tags:
		tag.visible = false
	_hero_root.position = Vector3.ZERO
	_hero_root.rotation = Vector3.ZERO
	_foe_root.position = FOE_AT
	_foe_root.visible = true
	_imp_root.visible = false
	for m: Mannequin in [_hero, _foe, _imp, _twin, _twin_foe]:
		m.play(&"locomotion.idle")
	# A Blink cut off part way leaves whatever it faded faded (the body, the tag above it): put it all back.
	for root: Node3D in [_hero_root, _foe_root, _imp_root, _twin_root, _twin_foe_root]:
		for g: Node in root.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).transparency = 0.0


## Wait `s` seconds of the lab's (slowed) time; false when another play began meanwhile. A Timer of the lab's own:
## freed with the lab, so a wait is dropped when it closes.
func _wait(s: float, run: int) -> bool:
	if s > 0.0:
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = s
		add_child(t)
		t.start()
		await t.timeout
		t.queue_free()
	return run == _run


## An effect from `effects/<scene>.tscn`, at `at`, facing `toward` (a point), aimed at `target`; `prep` sets it up
## before it enters the tree (where it starts).
func _spawn(scene: String, at: Vector3, toward: Vector3 = Vector3.INF, aim: Vector3 = Vector3.ZERO, who: Node3D = null, prep: Callable = Callable()) -> VfxEffect:
	var fx: VfxEffect = (load(FX + scene + ".tscn") as PackedScene).instantiate() as VfxEffect
	fx.target = aim
	fx.caster = who
	if prep.is_valid():
		prep.call(fx)
	fx.lighter = others
	fx.shook.connect(_on_shook)
	# Placed before it enters the tree: it starts (and reads where it is) as it does.
	fx.position = at
	if toward != Vector3.INF:
		var flat: Vector3 = Vector3(toward.x, at.y, toward.z) - at
		if flat.length() > 0.01:
			fx.basis = Basis.looking_at(flat, Vector3.UP)
	_stage.add_child(fx)
	return fx


func _on_shook(strength: float, seconds: float) -> void:
	_shake = strength
	_shake_left = seconds
	_shake_total = seconds


## Where a spell leaves the hand: the hand bone (or the middle of two), `ahead_m` on toward `toward`: in front of the
## palm, never inside the wrist (Luke, 2026-11-14: the fireball "originates from behind the hand").
func _cast_point(m: Mannequin, bones: Array, ahead_m: float, toward: Vector3) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for b: Variant in bones:
		var p: Vector3 = m.bone_position(b as StringName)
		if p != Vector3.INF:
			sum += p
			n += 1
	if n == 0:
		return m.global_position + Vector3(0, 1.3, -0.4)
	var at: Vector3 = sum / float(n)
	var dir: Vector3 = toward - at
	return at + dir.normalized() * ahead_m if dir.length() > 0.01 else at


## A charge kept in front of the casting hand(s) as the pose moves them.
func _charge(scene: String, bones: Array, ahead_m: float, toward: Vector3) -> VfxEffect:
	var fx: VfxEffect = _spawn(scene, _cast_point(_hero, bones, ahead_m, toward))
	_follow.append([fx, _hero, bones, ahead_m, toward])
	return fx


## Put the item at `path` in the adventurer's hand (freed by `_reset`).
func _arm(path: String) -> HeldItem:
	var item: ItemDef = load(path) as ItemDef
	if item == null or item.held_scene == null or _hero.skeleton == null:
		return null
	_held = HeldItem.attach(_hero.skeleton, item.held_scene)
	return _held


## The cut of swing `ability_id` along the held weapon's real path, timed from the swing's start (its wind-up, and
## the lab's clip a little behind it); dust where it ends only for a blow that ends at the ground (`ground`).
func _cut(ability_id: int, ground: bool) -> VfxBladeCut:
	var a: AbilityDef = ContentLibrary.find(&"ability", ability_id) as AbilityDef
	var hit: float = float(a.wind_up_ms) / 1000.0 + CLIP_LAG_S if a != null else 0.3
	var held: HeldItem = _held
	return _spawn("blade_cut", Vector3.ZERO, Vector3.INF, Vector3.ZERO, null, func(fx: VfxEffect) -> void:
		var cut: VfxBladeCut = fx as VfxBladeCut
		cut.weapon = held
		cut.cut_from_s = hit * 0.45
		cut.hit_at_s = hit
		cut.ground_m = 0.55 if ground else 0.0) as VfxBladeCut


# ---------------------------------------------------------------- the showcases

func _fireball(run: int) -> void:
	var aim: Vector3 = FOE_AT + Vector3(0, 1.0, 0)
	_hero.play(&"pose.spell_cast")
	_charge("fire_charge", [&"hand_l"], 0.16, aim)
	if not await _wait(0.6, run):
		return
	_hero.play(&"ability.40012", false)
	if not await _wait(0.06, run):   # the throw comes forward before it lets go
		return
	var from: Vector3 = _cast_point(_hero, [&"hand_l"], 0.3, aim)
	var missile: VfxFireMissile = _spawn("fire_missile", from, Vector3.INF, aim) as VfxFireMissile
	await missile.arrived
	if run != _run:
		return
	_spawn("fire_blast", FOE_AT, Vector3.INF)
	_foe.play(&"react.stagger", false)
	await _wait(2.4, run)


## Two-handed from the start to the end (Luke: it "starts 2 handed but then jumps to one handed"): the channel, its
## charge between both hands, and the two-handed cast to let it go.
func _frost_ring(run: int) -> void:
	var at: Vector3 = FOE_AT + Vector3(0, 0, 1.0)
	_hero.play(&"pose.spell_channel")
	_charge("frost_charge", [&"hand_l", &"hand_r"], 0.2, at + Vector3(0, 1.0, 0))
	if not await _wait(1.0, run):
		return
	_hero.play(&"ability.40014", false)
	_spawn("frost_ring", at, Vector3.INF)
	if not await _wait(1.0, run):
		return
	_foe.play(&"react.hit", false)
	await _wait(1.9, run)


func _blink(run: int) -> void:
	_hero.play(&"ability.40012", false)
	var to := Vector3(4.5, 0.0, -3.5)
	_hero_root.look_at(to, Vector3.UP)
	_spawn("blink", _hero_root.global_position, to, to, _hero_root)
	await _wait(1.1, run)


func _gale(run: int) -> void:
	_foe_root.position = Vector3(0, 0, -5.5)
	_hero.play(&"ability.40014", false)
	_spawn("gale", Vector3.ZERO, Vector3(0, 0, -1))
	if not await _wait(0.12, run):
		return
	_foe.play(&"react.stagger", false)
	var t: float = 0.0
	while t < 0.35:
		await ticked
		if run != _run:
			return
		var d: float = get_process_delta_time()
		t += d
		_foe_root.position.z -= 6.0 * d * (1.0 - t / 0.35)
	await _wait(0.8, run)


## The axe's heavy hit: whatever way the clip swings it, the cut is drawn along it.
func _axe(run: int) -> void:
	_foe_root.position = Vector3(0, 0, -2.0)
	_arm(AXE)
	_hero.play(&"ability.40008", false)
	var cut: VfxBladeCut = _cut(40008, true)
	if not await _wait(cut.hit_at_s, run):
		return
	_foe.play(&"react.hit", false)
	await _wait(1.0, run)


## The sword's string, its three hits one after another, each wearing the cut: what any swing could wear.
func _sword(run: int) -> void:
	_foe_root.position = Vector3(0, 0, -1.9)
	_arm(SWORD)
	for id: int in [40001, 40002, 40003]:
		var a: AbilityDef = ContentLibrary.find(&"ability", id) as AbilityDef
		_hero.play(StringName("ability.%d" % id), false)
		var cut: VfxBladeCut = _cut(id, false)
		if not await _wait(cut.hit_at_s, run):
			return
		_foe.play(&"react.hit", false)
		var gap: float = maxf(float(a.cooldown_ms) / 1000.0, 0.45) - cut.hit_at_s + 0.05 if a != null else 0.3
		if not await _wait(maxf(gap, 0.12), run):
			return
	await _wait(0.8, run)


## TODAY'S TRAIL on swing `ability_id` by `held`, as `SwingTrail` draws a player's (its own values, read from a fresh
## one, so a change to it shows here): the plain ribbon along the blade from late in the wind-up to just after the hit,
## timed as the new cut is (the lab's clip a little behind the wind-up).
func _today_cut(ability_id: int, held: HeldItem) -> void:
	var a: AbilityDef = ContentLibrary.find(&"ability", ability_id) as AbilityDef
	if a == null or held == null:
		return
	var st := SwingTrail.new()
	var blade: Array = SwingTrail.blade_of_item(held, st.blade_from)
	var trail := RibbonTrail.new()
	trail.name = "TodayTrail"
	trail.lifetime_s = st.lifetime_s
	trail.color = st.player_color
	var wind: float = float(a.wind_up_ms) / 1000.0
	var from: float = clock + wind * st.from_wind_up + CLIP_LAG_S
	var until: float = clock + wind + CLIP_LAG_S + float(st.after_hit_ms) / 1000.0
	st.free()
	if blade.size() != 2:
		trail.free()
		return
	_stage.add_child(trail)
	_plain.append([trail, held, blade, from, until])


## TODAY BESIDE NEW: two adventurers swing `weapon` through `ids` at once, each at its own skeleton: on the left the
## trail the game draws today, on the right the new cut (Luke, 2026-11-14: "add to the lab comparison of todays cuts
## with axe and sword and the new cuts before I decide to wire them in or not").
func _compare(run: int, weapon: String, ids: Array, ground: bool) -> void:
	_hero_root.position = Vector3(1.3, 0, 0)
	_foe_root.position = Vector3(1.3, 0, -1.9)
	_twin_root.position = Vector3(-1.3, 0, 0)
	_twin_foe_root.position = Vector3(-1.3, 0, -1.9)
	_twin_root.visible = true
	_twin_foe_root.visible = true
	for tag: Label3D in _tags:
		tag.visible = true
	_arm(weapon)
	var item: ItemDef = load(weapon) as ItemDef
	if item != null and item.held_scene != null and _twin.skeleton != null:
		_twin_held = HeldItem.attach(_twin.skeleton, item.held_scene)
	for id: Variant in ids:
		var a: AbilityDef = ContentLibrary.find(&"ability", int(id)) as AbilityDef
		var clip: StringName = StringName("ability.%d" % int(id))
		_hero.play(clip, false)
		_twin.play(clip, false)
		var cut: VfxBladeCut = _cut(int(id), ground)
		_today_cut(int(id), _twin_held)
		if not await _wait(cut.hit_at_s, run):
			return
		_foe.play(&"react.hit", false)
		_twin_foe.play(&"react.hit", false)
		if ids.size() > 1:
			var gap: float = maxf(float(a.cooldown_ms) / 1000.0, 0.45) - cut.hit_at_s + 0.05 if a != null else 0.3
			if not await _wait(maxf(gap, 0.12), run):
				return
	await _wait(1.0, run)


## The flash where the blow meets the block: at the blocking hand (the one nearer the foe's weapon hand), a little
## out toward the foe; never over the head.
func _parry(run: int) -> void:
	_foe_root.position = Vector3(0, 0, -1.9)
	_arm(SWORD)
	var a: AbilityDef = ContentLibrary.find(&"ability", 40017) as AbilityDef
	var lands: float = float(a.wind_up_ms) / 1000.0 if a != null else 0.66
	_foe.play(&"ability.40017", false)
	if not await _wait(lands - 0.25, run):
		return
	_hero.play(&"pose.block")
	if not await _wait(0.25, run):
		return
	var foe_hand: Vector3 = _foe.bone_position(&"hand_r")
	if foe_hand == Vector3.INF:
		foe_hand = _foe_root.global_position + Vector3(0, 1.2, 0)
	var block: Vector3 = _cast_point(_hero, [&"hand_l"], 0.0, foe_hand)
	var other: Vector3 = _cast_point(_hero, [&"hand_r"], 0.0, foe_hand)
	if other.distance_to(foe_hand) < block.distance_to(foe_hand):
		block = other
	var at: Vector3 = block + (foe_hand - block).normalized() * 0.15
	_spawn("parry_flash", at, foe_hand)
	_foe.play(&"react.stagger", false)
	await _wait(0.9, run)


## THE STAFF'S BOLT as the game draws it: the body's own look (`bolt_look.tscn`, a `ShotLook` with its riding missile)
## flown at the spell's speed from the hand to the foe, its flash where it ends.
func _bolt(run: int) -> void:
	var aim: Vector3 = FOE_AT + Vector3(0, 1.0, 0)
	_hero.play(&"ability.40012", false)
	if not await _wait(0.06, run):   # the throw comes forward before it lets go
		return
	var from: Vector3 = _cast_point(_hero, [&"hand_l"], 0.3, aim)
	var body := Node3D.new()
	body.name = "BoltBody"
	body.position = from
	_stage.add_child(body)
	var row: AbilityVfxEntry = AbilityVfxSet.current().entry(40012)
	if row != null and row.on_cast != null:   # the flash in the hand, as the game plays it (`AbilityVfx._cast_flash`)
		_spawn(row.on_cast.resource_path.get_file().get_basename(), _cast_point(_hero, [row.hand_bone], row.ahead_m, aim), aim)
	var look: ShotLook = (load("res://game/regents/combat/bolt_look.tscn") as PackedScene).instantiate() as ShotLook
	look.lighter = others   # another player's: the lighter version, as the game decides it from the body's owner
	body.add_child(look)
	var speed: float = 32.0
	var was: float = clock
	while is_instance_valid(body) and body.position.distance_to(aim) > 0.05:
		await ticked
		if run != _run or not is_instance_valid(body):
			return
		body.position = body.position.move_toward(aim, speed * (clock - was))
		was = clock
	body.queue_free()
	_foe.play(&"react.hit", false)
	await _wait(0.8, run)


## THE STAFF'S METEOR (placeholder): its charge between both hands through the cast, then the ring the game draws for
## it, as wide as the spell, landing as late as the spell says.
func _meteor(run: int) -> void:
	var spell: SpellDef = SpellDef.by_ability(40048)
	var at: Vector3 = FOE_AT + Vector3(0, 0, 1.0)
	_hero.play(&"pose.spell_channel")
	_charge("fire_charge", [&"hand_l", &"hand_r"], 0.2, at + Vector3(0, 1.0, 0))
	if not await _wait(float(spell.cast_ms) / 1000.0, run):
		return
	for f: Array in _follow:
		if is_instance_valid(f[0]):
			(f[0] as Node).queue_free()
	_follow.clear()
	_hero.play(&"ability.40014", false)
	var ring: VfxGroundRing = SpellLooks.ring_scene(40048, false).instantiate() as VfxGroundRing
	ring.radius_m = spell.radius_m
	ring.warn_s = float(spell.delay_ms) / 1000.0
	ring.lighter = others
	ring.shook.connect(_on_shook)
	ring.position = at
	_stage.add_child(ring)
	if not await _wait(ring.warn_s, run):
		return
	_foe.play(&"react.stagger", false)
	await _wait(1.9, run)


func _cinder(run: int) -> void:
	_foe_root.visible = false
	_imp_root.visible = true
	_imp.play(&"ability.40033", false)
	if not await _wait(0.2, run):
		return
	_spawn("cinder_ring", Vector3(0.0, 0.0, -0.3), Vector3.INF)
	if not await _wait(1.55, run):
		return
	_hero.play(&"react.stagger", false)
	await _wait(1.5, run)


# ---------------------------------------------------------------- shots

## Play each showcase (or only `only`) and save a contact sheet of its moments into `dir`, then quit.
func _shoot(dir: String, only: String) -> void:
	if dir == "cost":
		await _measure()
		return
	_shooting = true
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 720)
	_ui.visible = false
	for i: int in 30:
		await get_tree().process_frame   # the noises are made on a thread: let them land
	# Once through everything unshot, so each shader is compiled before a shot depends on its timing.
	for i: int in showcases.size():
		_select(i)
		for f: int in 12:
			await get_tree().process_frame
	for i: int in showcases.size():
		var name_s: String = String(showcases[i][0])
		if not only.is_empty() and slug(name_s) != slug(only):
			continue
		for li: int in ([0, 2] if only.is_empty() else [light_index]):
			_set_light(li)
			_select(i)
			var sheet := Image.create(SHOT_SIZE.x * 3, SHOT_SIZE.y * 2, false, Image.FORMAT_RGB8)
			var moments: Array = showcases[i][3] as Array
			for k: int in moments.size():
				while clock < float(moments[k]):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, SHOT_SIZE), Vector2i((k % 3) * SHOT_SIZE.x, int(k / 3.0) * SHOT_SIZE.y))
			var file: String = dir.path_join("vfx_%s_%s%s.png" % [slug(name_s), LIGHTS[li].to_lower(), "_others" if others else ""])
			sheet.save_png(file)
			print("saved ", file)
			_run += 1
			await get_tree().create_timer(0.4).timeout
	AppExit.quit(get_tree(), 0)


## WHAT EACH SHOWCASE COSTS (`-- cost`, windowed): the stage with nothing playing, then each showcase through to its
## end, the most it adds at once: draw calls, particles alive, and the GPU's time for a frame (this machine's, at
## 1280 x 720: compare them with each other, not with another machine). Printed, then it quits.
func _measure() -> void:
	_shooting = true
	_ui.visible = false
	get_window().size = Vector2i(1280, 720)
	var vp: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i: int in 30:
		await get_tree().process_frame
	for i: int in showcases.size():   # once through unmeasured: every shader compiled
		_select(i)
		for f: int in 12:
			await get_tree().process_frame
	_run += 1
	_reset()
	var base: Vector2 = await _sample_frames(60)
	print("COST stage alone: %d draw calls, %.2f ms GPU" % [roundi(base.x), base.y])
	for pass_others: bool in [false, true]:
		others = pass_others
		for i: int in showcases.size():
			await _measure_one(i, base)
	AppExit.quit(get_tree(), 0)


## One showcase through to its end: the most it adds at once, printed.
func _measure_one(i: int, base: Vector2) -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	_select(i)
	var peak_draws: float = 0.0
	var peak_parts: int = 0
	var peak_gpu: float = 0.0
	var sum_gpu: float = 0.0
	var frames: int = 0
	await get_tree().process_frame
	while _running:
		await RenderingServer.frame_post_draw
		var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var parts: int = 0
		for p: Node in _stage.find_children("*", "GPUParticles3D", true, false):
			if (p as GPUParticles3D).is_visible_in_tree() and (p as GPUParticles3D).emitting:
				parts += (p as GPUParticles3D).amount
		peak_draws = maxf(peak_draws, draws)
		peak_parts = maxi(peak_parts, parts)
		peak_gpu = maxf(peak_gpu, gpu)
		sum_gpu += gpu
		frames += 1
	print("COST %s%s: +%d draw calls at most, %d particles at most, GPU %.2f ms at most (+%.2f), %.2f ms on average" % [
		showcases[i][0], " (another player's)" if others else "", roundi(peak_draws - base.x), peak_parts, peak_gpu, peak_gpu - base.y, sum_gpu / float(maxi(frames, 1))])


## Over `n` frames: the mean draw calls and the mean GPU time (ms).
func _sample_frames(n: int) -> Vector2:
	var vp: RID = get_viewport().get_viewport_rid()
	var draws: float = 0.0
	var gpu: float = 0.0
	for f: int in n:
		await RenderingServer.frame_post_draw
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return Vector2(draws / float(n), gpu / float(n))


## A showcase's name as a file name and a shot's argument: lower case, every run of other characters one "_"
## ("Axe: old | new" is axe_old_new).
static func slug(s: String) -> String:
	var out: String = ""
	for c: String in s.to_lower():
		var keep: bool = (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if keep:
			out += c
		elif not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")
