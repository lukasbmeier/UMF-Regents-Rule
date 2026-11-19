extends Node3D
## THE MOTION LAB (Luke, 2026-11-17: "a lab that showcases motion made in code": a spinning advance, a leaping strike
## and a blade from the sky, a spinning dash, an axe that hooks and pulls, "and whatever other melee"): open
## `res://game/regents/motion/motion_lab.tscn` and press F6 (no server). The game's adventurer and skeletons, each move
## (`MotionMove`, played by `MotionLayer`) built of CLIPS FOR THE BODY and CODE FOR WHAT A CLIP CANNOT DO (Luke, after
## the first cut, all code, turned stiff poses like a doll: "rebuild it with the clips"): human-made clips from our
## Quaternius libraries (CC0) that the game never used (a back flip, a ground pound, a sword dash, an overhand throw, a
## launch into the air and a kip-up), time-warped, chained and blended; and on top, the code: a spin, a jump stretched
## to an ability's distance, an arm turned to a target, a foe hauled in. No animation from a generator. Each move is a
## `.tres` in `game/regents/motion/moves/` (its clips and curves in the Inspector; play it again).
##
##   the list (or Up / Down)   pick a move; it plays
##   Space                      play it again          L   loop it
##   C                          compare: beside it, the same clips with the code off
##   P                          pause; then , and . step a frame back and on; the time bar: drag to any moment
##   the speed buttons ( [ ] )  full speed down to a tenth
##   right mouse, drag          turn round the stage    wheel   nearer, farther
##
## FEEDBACK: pause on the moment that looks wrong and give its time (the bar shows it): "Leap slam 0.84: the feet slide".
##
## Presentation only (hard rule 11): nothing here is judged; each timeline says who is hit. The body's travel is
## carried here; in the game it would be the server's (a lunge, a push: `ABILITY_LIMITS.md` §5).
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/motion/motion_lab.tscn -- <out dir>` plays every
## move and saves a contact sheet of six moments of each (`<out>/motion_<name>.png`), then quits. A second argument, a
## move's name, shoots that one only; the word `compare` among the arguments shoots the clips-only twin beside it, the
## word `dense` twelve moments evenly through it.
## CLIP SHEETS (choosing a clip for a move): `-- <out dir> clips [library/name ...]` saves eight frames of each clip
## (the candidates in `SHEET_CLIPS` when none are named), four clips to a sheet (`clips_<n>.png`, the order printed).
## THE CLIP BROWSER (the list's last entry, Luke 2026-11-18: "I don't see a way to play the retargeted animation with
## different weapons"): any clip of any library (`MotionClip.LIBRARIES`: Quaternius's, the cuts, Mixamo's) on the
## adventurer, holding any item that has a held scene (or nothing) at any size, with the scrubber, speeds and compare.
## `held=<scene>` among them holds that held item instead of the sword (`held=res://game/regents/combat/weapons/
## yew_bow.tscn`), `scale=<x>` draws it that many times its size (its model only: the hold stays where it is).

signal ticked()

const MOVES: String = "res://game/regents/motion/moves/"
const FX: String = "res://game/regents/vfx/effects/"
const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const SKELETON: EntityDefinition = preload("res://game/regents/content/character/skeleton_warrior.tres")
const SKELETON_FOE: FoeDef = preload("res://game/regents/content/foe/skeleton_warrior.tres")
const SWORD: ItemDef = preload("res://game/regents/content/item/steel_sword.tres")
const AXE: ItemDef = preload("res://game/regents/content/item/steel_axe.tres")
const SPEEDS: Array[float] = [1.0, 0.5, 0.25, 0.1]
const SHOT_SIZE: Vector2i = Vector2i(640, 360)
## Where the clip-only twin stands, beside the coded one (compare).
const TWIN_AT: Vector3 = Vector3(-4.5, 0.0, 0.0)
const DUMMIES: int = 3
## The clips a clip sheet shows when none are named: the libraries' moves a melee ability could be built from.
const SHEET_CLIPS: Array[String] = ["core/BackFlip", "extra/JogToFlip", "extra/Sword_GroundPound_RM",
	"extra/Sword_Dash_RM", "extra/NinjaJump_Start", "extra/NinjaJump_Land", "extra/Sword_Aerial_A", "extra/Sword_Aerial_B",
	"extra/Sword_Aerial_Combo", "extra/OverhandThrow", "extra/Melee_Hook", "extra/Shield_Dash_RM", "extra/LiftAir_RM",
	"extra/LiftAir_Fall", "extra/LiftAir_Fall_Impact", "extra/Hit_Knockback_RM", "extra/KipUp", "extra/Sword_Heavy_C",
	"extra/Sword_Heavy_D", "extra/Sword_UpperCut_RM", "extra/DoubleJump", "core/Jump_Start", "extra/Sword_Light_B",
	"extra/Sword_Heavy_A", "extra/Sword_Heavy_B", "extra/Sword_Regular_B", "core/Sword_Attack", "core/Sprint"]

## [name, what it shows, the method, the moments to shoot (s), the camera: yaw, pitch (deg), distance, focus]
var showcases: Array[Array] = [
	["Leaping strike", "A sprint, a hop into an overhead strike, a landing crouch (after a moba's Q). Sprint, Sword_Aerial_B, NinjaJump_Land. leaping_strike.tres",
		"_leaping_strike", [0.25, 0.45, 0.62, 0.8, 0.95, 1.3], [75.0, -10.0, 6.0, Vector3(0, 1.0, -2.5)]],
	["Spinning advance", "Walking through three skeletons in a spin, the sword arm straight out and the blade along it (after a moba's E). Sword_Light_Combo's spin-cut, its arm held out; four turns of code. spinning_advance.tres",
		"_spinning_advance", [0.15, 0.45, 0.8, 1.2, 1.6, 2.0], [65.0, -18.0, 6.5, Vector3(0, 1.0, -3.5)]],
	["Sky blade", "The sword raised slowly to the sky, a blade of light falls on the foe with the slam (after a moba's R). Sword_Heavy_D, its raise slowed. sky_blade.tres",
		"_sky_blade", [0.4, 0.9, 1.15, 1.3, 1.5, 2.2], [70.0, -6.0, 7.2, Vector3(0, 2.4, -3.0)]],
	["Spinning dash", "Seven meters in a spinning lunge, cutting what it passes (after a moba's spinning slash). Sword_Dash_RM stretched; the spin and the hop are the code's. spinning_dash.tres",
		"_spinning_dash", [0.08, 0.2, 0.35, 0.5, 0.65, 0.9], [80.0, -12.0, 6.5, Vector3(0, 1.0, -3.5)]],
	["Hook pull", "The axe swept out sideways, its head turned to hook a foe three meters off, and yanked back with the foe on it (after a moba's apprehend). Sword_Heavy_C, its wrist rolled by code; the foe Hit_Knockback_RM turned round. hook_pull.tres, dragged.tres",
		"_hook_pull", [0.3, 0.5, 0.62, 0.75, 0.9, 1.4], [80.0, -10.0, 5.0, Vector3(0, 1.0, -1.6)]],
	["Leap slam", "A rising cut launches it, six meters through the air, the ground pound throws three skeletons up; they land and kip up. Sword_UpperCut_RM, Sword_GroundPound_RM; LiftAir, KipUp. leap_slam.tres, knocked_up.tres",
		"_leap_slam", [0.25, 0.5, 0.8, 1.05, 1.6, 3.0], [70.0, -10.0, 8.5, Vector3(0, 1.2, -3.5)]],
	["Back flip", "A skeleton's cut, answered with a back flip out of its reach. BackFlip, carried 2.5 m back. backflip.tres",
		"_backflip", [0.35, 0.5, 0.65, 0.8, 1.0, 1.6], [90.0, -6.0, 6.8, Vector3(0, 1.2, 0.6)]],
	["Blade waltz", "Gone in a flash, a cut on each of three skeletons from a new side, back in sight beside the last (after a moba's alpha strike). Sword_Light_A each time; the leaps between are the code's. waltz_cut.tres",
		"_blade_waltz", [0.12, 0.3, 0.5, 0.72, 0.95, 1.4], [70.0, -22.0, 8.0, Vector3(0, 1.0, -4.5)]],
	["Roundhouse kick", "A high spinning kick that sends a skeleton flying four meters; it lands and kips up. Kick; LiftAir, KipUp. roundhouse_kick.tres, kicked.tres",
		"_roundhouse_kick", [0.3, 0.48, 0.6, 0.8, 1.3, 2.4], [80.0, -8.0, 6.5, Vector3(0, 1.0, -2.5)]],
	["Shoulder charge", "A sprint into a shoulder-first dash; the foe thrown back and getting up. Sprint, Shield_Dash_RM; Hit_Knockback_RM, KipUp. shoulder_charge.tres, tumble.tres",
		"_shoulder_charge", [0.2, 0.5, 0.75, 1.0, 1.6, 2.8], [75.0, -10.0, 7.5, Vector3(0, 1.0, -5.0)]],
	["Clip browser", "Any clip of any library, holding any weapon at any size: pick them on the right. The clip alone (no code), its root's travel left out.",
		"_browse", [0.1, 0.3, 0.5, 0.7, 0.9, 1.1], [60.0, -8.0, 4.2, Vector3(0, 1.1, 0)]],
]
## The browser's index in `showcases`.
const BROWSER: int = 10
## The clip browser's choice: a library (a `MotionClip.LIBRARIES` key), a clip in it, a held item's scene ("" nothing)
## and its size.
var browse_library: String = "mx_great_sword"
var browse_clip: StringName = &"great_sword_attack"
var browse_held: String = "res://game/regents/combat/weapons/yew_bow.tscn"
var browse_scale: float = 1.4
var _br_panel: PanelContainer = null
var _br_libs: OptionButton = null
var _br_filter: LineEdit = null
var _br_list: ItemList = null
var _br_helds: OptionButton = null
var _br_held_paths: PackedStringArray = PackedStringArray()
var _br_scale_label: Label = null
var _br_size: HSlider = null

var current: int = 0
var looping: bool = false
var compare: bool = false
var speed_index: int = 0
## The lab's own time since a showcase's moves began (slowed with it), and whether they have (after the settle): what
## the shots wait on.
var clock: float = 0.0
var started: bool = false
## THE SCRUBBER: held still (P), or on its way to a moment (`seek`: it plays there fast, then holds); each showcase's
## length as last played (s).
var paused: bool = false
var _seek_to: float = -1.0
var _lengths: Dictionary[int, float] = {}
var _real_us: int = 0
## The slowest frame lately (s), as a seek plans its steps.
var _dt_guard: float = 1.0 / 60.0
## What is left of the settle before a play's clock starts (s, the lab's time).
var _settle_left: float = 0.0
var _bar: HSlider = null
var _time_label: Label = null
var _pause_button: Button = null
var _dragging: bool = false
## The lab moving the bar itself (its length, the clock): never a seek.
var _syncing: bool = false

## The coded pack (always there) and the clip-only twin's (compare).
var coded: Pack = null
var plain: Pack = null

var _stage: Node3D = null
var _cam: Camera3D = null
var _yaw: float = 70.0
var _pitch: float = -10.0
var _dist: float = 8.0
var _focus: Vector3 = Vector3(0, 1, -3)
var _shake: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _run: int = 0
var _running: bool = false
var _shooting: bool = false
var _ui: CanvasLayer = null
var _list: VBoxContainer = null
var _about: Label = null
var _speed_label: Label = null
var _loop_button: Button = null
var _compare_button: Button = null


## ONE SIDE OF THE STAGE: a swordsman, an axeman, the skeletons, each with a motion layer; `coded` false: the layers
## are off (the clip alone), every body still carried as far.
class Pack extends RefCounted:
	var origin: Vector3 = Vector3.ZERO
	var coded: bool = true
	var sword: ShowcaseActor = null
	var axe: ShowcaseActor = null
	var dummies: Array[ShowcaseActor] = []
	## The clip browser's adventurer: what it holds is changed at will.
	var browser: ShowcaseActor = null
	## What the browser's adventurer holds now (its scene's path) and at what size.
	var browser_held: String = ""
	var browser_scale: float = 1.0
	var layers: Dictionary = {}
	var trail: MotionTrail = null
	var tag: Label3D = null

	func layer(a: ShowcaseActor) -> MotionLayer:
		return layers.get(a) as MotionLayer

	func all() -> Array[ShowcaseActor]:
		var out: Array[ShowcaseActor] = [sword, axe, browser]
		out.append_array(dummies)
		return out

	## A point of the timeline's (as if the pack stood at the world's middle), where this pack stands it.
	func at(p: Vector3) -> Vector3:
		return origin + p


func _ready() -> void:
	_build_world()
	coded = _make_pack(Vector3.ZERO, true)
	plain = _make_pack(TWIN_AT, false)
	_build_ui()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("compare"):
		compare = true
		args.remove_at(args.find("compare"))
	if args.has("dense"):
		args.remove_at(args.find("dense"))
	if args.size() >= 2 and args[1] == "clips":
		_clip_sheets.call_deferred(args[0], args.slice(2))
	elif not args.is_empty() and not args[0].begins_with("--"):   # (the test runner passes its own "--only=")
		_shoot.call_deferred(args[0], args[1] if args.size() > 1 else "")
	else:
		_select.call_deferred(0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- the stage

func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.82)
	sky_mat.sky_horizon_color = Color(0.7, 0.78, 0.84)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.012
	env.fog_light_color = Color(0.7, 0.77, 0.83)
	env.fog_aerial_perspective = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.light_color = Color(1, 0.92, 0.78)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-38, 35, 0)
	add_child(sun)
	# The ground: grass broken by a noise, and a pale line every 2 m along the way the moves go (no image).
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
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
	gm.uv1_scale = Vector3(50, 50, 50)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var mark := StandardMaterial3D.new()
	mark.albedo_color = Color(0.85, 0.82, 0.7)
	mark.roughness = 1.0
	for z: int in range(0, 14, 2):
		for x: float in [1.6, TWIN_AT.x + 1.6]:
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.5, 0.01, 0.06)
			m.mesh = b
			m.material_override = mark
			m.position = Vector3(x, 0.005, -float(z))
			add_child(m)
	_stage = Node3D.new()
	_stage.name = "Effects"
	add_child(_stage)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_place_camera()


func _make_pack(origin: Vector3, is_coded: bool) -> Pack:
	var p := Pack.new()
	p.origin = origin
	p.coded = is_coded
	p.sword = _actor(p, ADVENTURER, 4, SWORD.held_scene, null)
	p.axe = _actor(p, ADVENTURER, 1, AXE.held_scene, null)
	for i: int in DUMMIES:
		p.dummies.append(_actor(p, SKELETON, 0, null, SKELETON_FOE))
	p.browser = _actor(p, ADVENTURER, 4, null, null)
	p.trail = MotionTrail.new()
	p.trail.name = "Trail"
	add_child(p.trail)
	p.tag = Label3D.new()
	p.tag.text = "clips + code" if is_coded else "clips alone"
	p.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.tag.font_size = 56
	p.tag.outline_size = 12
	p.tag.pixel_size = 0.006
	p.tag.position = origin + Vector3(0.0, 2.6, 0.6)
	p.tag.visible = false
	add_child(p.tag)
	return p


func _actor(p: Pack, def: EntityDefinition, look: int, weapon: PackedScene, foe: FoeDef) -> ShowcaseActor:
	var a: ShowcaseActor = ShowcaseActor.make(def, look, weapon, foe)
	a.position = Vector3(0.0, -50.0, 0.0)
	add_child(a)
	var l: MotionLayer = MotionLayer.attach(a, a.model, a.skeleton)
	l.enabled = p.coded
	p.layers[a] = l
	a.visible = false
	return a


func _place_camera() -> void:
	var dir := Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	var offset: Vector3 = (dir * cos(deg_to_rad(-_pitch)) + Vector3.UP * sin(deg_to_rad(-_pitch))) * _dist
	var shake: Vector3 = Vector3.ZERO
	if _shake_left > 0.0:
		var k: float = _shake * (_shake_left / maxf(_shake_total, 0.001))
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * k * 0.25
	var focus: Vector3 = _focus
	if compare:
		# The twin stands beside along x: seen from further round (toward the moves' start), the two side by side.
		focus += Vector3(TWIN_AT.x * 0.5, 0.0, 0.0)
		var yaw_c: float = deg_to_rad(_yaw - 55.0)
		dir = Vector3(sin(yaw_c), 0.0, cos(yaw_c))
		offset = (dir * cos(deg_to_rad(-_pitch)) + Vector3.UP * sin(deg_to_rad(-_pitch))) * _dist * 1.2
	_cam.position = focus + offset + shake
	_cam.look_at(focus + shake * 0.5, Vector3.UP)


func _process(delta: float) -> void:
	clock += delta
	if not started:
		_settle_left -= delta
	_drive_seek()
	_show_time()
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
	_place_camera()
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
			KEY_SPACE:
				_set_paused(false)
				replay()
			KEY_P:
				_set_paused(not paused)
			KEY_PERIOD:
				seek(clock + 1.0 / 60.0)
			KEY_COMMA:
				seek(clock - 1.0 / 60.0)
			KEY_L:
				_set_loop(not looping)
			KEY_C:
				_set_compare(not compare)
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
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiStyle.current().theme()
	_ui.add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Motion lab: moves made in code"
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
	_compare_button = _button(row, "Compare (C)", func() -> void: _set_compare(not compare))
	_compare_button.toggle_mode = true
	var speeds := HBoxContainer.new()
	col.add_child(speeds)
	_speed_label = Label.new()
	speeds.add_child(_speed_label)
	for i: int in SPEEDS.size():
		var s: int = i
		_button(speeds, "%sx" % _speed_text(SPEEDS[i]), func() -> void: _set_speed(s))
	_set_speed(0)
	var scrub := HBoxContainer.new()
	scrub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	scrub.offset_top = -84
	scrub.offset_bottom = -48
	scrub.offset_left = 16
	scrub.offset_right = -16
	root.add_child(scrub)
	_pause_button = _button(scrub, "Pause (P)", func() -> void: _set_paused(not paused))
	_button(scrub, "<  (,)", func() -> void: seek(clock - 1.0 / 60.0))
	_button(scrub, "(.)  >", func() -> void: seek(clock + 1.0 / 60.0))
	_bar = HSlider.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.min_value = 0.0
	_bar.max_value = 3.0
	_bar.step = 1.0 / 120.0
	_bar.focus_mode = Control.FOCUS_NONE
	_bar.drag_started.connect(func() -> void: _dragging = true)
	_bar.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		seek(_bar.value))
	_bar.value_changed.connect(func(v: float) -> void:
		if not _dragging and not _syncing:
			seek(v))
	scrub.add_child(_bar)
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(150, 0)
	scrub.add_child(_time_label)
	_about = Label.new()
	_about.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_about.offset_top = -40
	_about.offset_left = 16
	_about.add_theme_font_size_override(&"font_size", 18)
	_about.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_about)
	var hint := Label.new()
	hint.text = "right mouse: turn   wheel: nearer   Up/Down: move   [ ]: speed   C: compare   P: pause   , .: a frame"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint.position = Vector2(-760, 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(hint)
	_build_browser(root)


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
	if not paused and _seek_to < 0.0:
		Engine.time_scale = SPEEDS[i]
	if _speed_label != null:
		_speed_label.text = "Speed %sx  " % _speed_text(SPEEDS[i])


func _set_loop(on: bool) -> void:
	looping = on
	if _loop_button != null:
		_loop_button.button_pressed = on
	if on and not _running:
		replay()


func _set_compare(on: bool) -> void:
	compare = on
	if _compare_button != null:
		_compare_button.button_pressed = on
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
	if _br_panel != null:
		_br_panel.visible = i == BROWSER
	if i == BROWSER:
		_about.text = _browse_words()
	_seek_to = -1.0
	_set_paused(false)
	replay()


# ---------------------------------------------------------------- the scrubber

## Hold still (the camera still turns), or go on at the chosen speed.
func _set_paused(on: bool) -> void:
	paused = on
	if not on:
		_seek_to = -1.0
	Engine.time_scale = 0.0 if on else SPEEDS[speed_index]
	if _pause_button != null:
		_pause_button.text = "Play (P)" if on else "Pause (P)"


## GO TO the moment `t` s into the showcase and hold there: on from here if it is ahead, else played again from the
## start; either way run there fast and stopped exactly on it (the same timeline, the same frames, every time).
func seek(t: float) -> void:
	var length: float = _length_of(current)
	var target: float = clampf(t, 0.0, length)
	if not started or target < clock - 0.0001:
		_run += 1
		clock = 0.0
		started = false
		_play(_run)
	_seek_to = target
	paused = true
	if _pause_button != null:
		_pause_button.text = "Play (P)"


## How long showcase `i` runs (as last played; before that, its last moment to shoot and a little).
func _length_of(i: int) -> float:
	if i == BROWSER:
		var clip: Animation = MotionClip.find(StringName("%s/%s" % [browse_library, browse_clip]))
		return clip.length if clip != null else 1.0
	if _lengths.has(i):
		return _lengths[i]
	var moments: Array = showcases[i][3] as Array
	return float(moments[moments.size() - 1]) + 0.6


## Each frame while seeking: as fast as it can go (the settle at the start fastest), slowing to land on the moment.
func _drive_seek() -> void:
	var now_us: int = Time.get_ticks_usec()
	var real_dt: float = clampf(float(now_us - _real_us) / 1000000.0, 0.001, 0.1) if _real_us > 0 else 1.0 / 60.0
	_real_us = now_us
	if _seek_to < 0.0:
		return
	if not started:
		# The settle, fast, closing in on its end as on a moment: the frame the timeline starts in is a short one (a big
		# one would step the cast before the clock counts it, and the same moment would differ play to play).
		_dt_guard = maxf(real_dt, _dt_guard * 0.8)
		Engine.time_scale = clampf(maxf(_settle_left, 0.0) * 0.5 / _dt_guard, 0.001, 8.0)
		return
	var left: float = _seek_to - clock
	if left <= 0.0005:
		_seek_to = -1.0
		Engine.time_scale = 0.0
		return
	# Half of what is left each frame, planned on the slowest frame lately: a frame that runs long (the real time varies,
	# more so with much else loaded) never carries it past.
	_dt_guard = maxf(real_dt, _dt_guard * 0.8)
	Engine.time_scale = clampf(left * 0.5 / _dt_guard, 0.001, 8.0)


func _show_time() -> void:
	if _bar == null:
		return
	_syncing = true
	if not _dragging:
		_bar.set_value_no_signal(0.0)
	_bar.max_value = _length_of(current)
	if not _dragging:
		_bar.set_value_no_signal(clock if started else 0.0)
	_syncing = false
	_time_label.text = "%.2f s / %.2f s%s" % [clock if started else 0.0, _length_of(current), "  (held)" if paused and _seek_to < 0.0 else ""]


# ---------------------------------------------------------------- playing

## Clear the stage and play the current move from the start.
func replay() -> void:
	_run += 1
	clock = 0.0
	started = false
	_play(_run)


func _play(run: int) -> void:
	_reset()
	_running = true
	# A moment for the cast to settle (a skeleton felled by the last move stands up again), then the clock starts. Counted
	# on the lab's own clock (`_settle_left`), so a seek can close in on its end.
	_settle_left = 0.5
	while _settle_left > 0.0005:
		await ticked
		if run != _run:
			return
	clock = 0.0
	started = true
	var method: String = String(showcases[current][2])
	var done: Array[bool] = [false, false]
	_side(method, run, coded, done, 0)
	if compare:
		_side(method, run, plain, done, 1)
	else:
		done[1] = true
	while not (done[0] and done[1]):
		await ticked
		if run != _run:
			return
	if run == _run:
		_lengths[current] = clock
	await _wait(0.8, run)
	_running = false
	if run == _run and looping and not _shooting and not paused:
		replay()


func _side(method: String, run: int, p: Pack, done: Array[bool], i: int) -> void:
	match method:
		"_leaping_strike":
			await _leaping_strike(run, p)
		"_spinning_advance":
			await _spinning_advance(run, p)
		"_sky_blade":
			await _sky_blade(run, p)
		"_spinning_dash":
			await _spinning_dash(run, p)
		"_hook_pull":
			await _hook_pull(run, p)
		"_leap_slam":
			await _leap_slam(run, p)
		"_backflip":
			await _backflip(run, p)
		"_shoulder_charge":
			await _shoulder_charge(run, p)
		"_blade_waltz":
			await _blade_waltz(run, p)
		"_roundhouse_kick":
			await _roundhouse_kick(run, p)
		"_browse":
			await _browse(run, p)
	done[i] = true


func _reset() -> void:
	for c: Node in _stage.get_children():
		c.queue_free()
	for p: Pack in [coded, plain]:
		p.tag.visible = compare
		p.trail.emitting = false
		for a: ShowcaseActor in p.all():
			p.layer(a).stop()
			a.visible = false
			a.play(&"locomotion.idle")
			a.walk_to(p.at(Vector3(0.0, -50.0, 0.0)), 0.0)


## Stand `a` of pack `p` at `local` (the timeline's), facing `toward` (local), seen.
func _stand(p: Pack, a: ShowcaseActor, local: Vector3, toward: Vector3) -> void:
	a.visible = true
	a.walk_to(p.at(local), 0.0)
	a.face(p.at(toward), true)
	a.play(&"locomotion.idle")


## Play `move_name` on `a`: its layer from now, facing `toward` (world), reaching for `at`; its clip at its time.
func _go(run: int, p: Pack, a: ShowcaseActor, move_name: String, toward: Vector3, at: Vector3 = Vector3.INF) -> MotionMove:
	var m: MotionMove = load(MOVES + move_name + ".tres") as MotionMove
	p.layer(a).play(m, toward - a.position, at)
	if m.clip != &"":
		_clip_later(run, a, m.clip, m.clip_at * m.length_s)
	return m


func _clip_later(run: int, a: ShowcaseActor, clip: StringName, after_s: float) -> void:
	if after_s > 0.0 and not await _wait(after_s, run):
		return
	a.act(clip)


## Wait `s` seconds of the lab's (slowed) time; false when another play began meanwhile.
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


func _spawn(scene: String, at: Vector3, prep: Callable = Callable()) -> VfxEffect:
	var fx: VfxEffect = (load(FX + scene + ".tscn") as PackedScene).instantiate() as VfxEffect
	if prep.is_valid():
		prep.call(fx)
	fx.shook.connect(_on_shook)
	fx.position = at
	_stage.add_child(fx)
	return fx


func _on_shook(strength: float, seconds: float) -> void:
	shake(strength, seconds)


func shake(strength: float, seconds: float) -> void:
	_shake = strength
	_shake_left = seconds
	_shake_total = seconds


## A blow landing on `a`: a flash at its chest and its flinch (`clip`; empty: none, a move of its own follows).
func _hit(a: ShowcaseActor, clip: StringName = &"react.hit") -> void:
	_spawn("parry_flash", a.position + Vector3(0.0, 1.2, 0.0))
	if clip != &"":
		a.act(clip)


## A slam's ring on the ground at `at`, `radius` m.
func _slam_ring(at: Vector3, radius: float) -> void:
	_spawn("meteor_ring", at, func(fx: VfxEffect) -> void:
		var r: VfxGroundRing = fx as VfxGroundRing
		r.element = VfxGroundRing.Element.FIRE
		r.radius_m = radius
		r.warn_s = 0.1
		r.duration_s = 1.1
		r.shake = 0.0
		r.color = Color(1.0, 0.82, 0.45)
		r.light_color = Color(1.0, 0.8, 0.5)
		# Low and few: the slam's mark on the ground, never a wall of fire hiding the bodies the lab is about.
		r.pieces = 10
		r.height_m = Vector2(0.25, 0.8)
		r.fill_alpha = 0.15)


## The weapon's blade trail for pack `p` on `a`, on for `seconds`.
func _trail(run: int, p: Pack, a: ShowcaseActor, seconds: float) -> void:
	p.trail.follow(a.held)
	p.trail.emitting = true
	if await _wait(seconds, run):
		p.trail.emitting = false


# ---------------------------------------------------------------- the moves

func _leaping_strike(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -6))
	_stand(p, foe, Vector3(0, 0, -5.4), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "leaping_strike", foe.position)
	_trail(run, p, h, m.length_s * 0.7)
	if not await _wait(m.impact_at * m.length_s, run):
		return
	_hit(foe, &"react.stagger")
	if p.coded:
		shake(0.35, 0.25)
	await _wait(m.length_s * (1.0 - m.impact_at), run)


func _spinning_advance(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -6))
	var spots: Array[Vector3] = [Vector3(-0.9, 0, -3.5), Vector3(1.0, 0, -5.0), Vector3(-0.4, 0, -6.6)]
	for i: int in DUMMIES:
		_stand(p, p.dummies[i], spots[i], Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "spinning_advance", p.at(Vector3(0, 0, -6)))
	# Walking as long as it spins, no longer (Luke: "the spinning goes on too long after it finishes").
	h.walk_to(p.at(Vector3(0, 0, -6.2)), 6.2 / (0.84 * m.length_s))
	_trail(run, p, h, 0.86 * m.length_s)
	# A skeleton the sword passes is cut, at most twice (a flinch at every turn looked like a twitch).
	var hits: Dictionary = {}
	var last_hit: Dictionary = {}
	var t: float = 0.0
	while t < 0.84 * m.length_s:
		await ticked
		if run != _run:
			return
		t = p.layer(h).t if p.layer(h).playing() else m.length_s
		for d: ShowcaseActor in p.dummies:
			var near: bool = Vector2(d.position.x - h.position.x, d.position.z - h.position.z).length() < 1.9
			if near and int(hits.get(d, 0)) < 2 and t - float(last_hit.get(d, -9.0)) > 0.55:
				last_hit[d] = t
				hits[d] = int(hits.get(d, 0)) + 1
				_hit(d)
	await _wait(0.16 * m.length_s, run)


func _sky_blade(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -6))
	_stand(p, foe, Vector3(0, 0, -6.0), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "sky_blade", foe.position)
	var fall_from: float = (m.impact_at - 0.1) * m.length_s
	var land: float = m.impact_at * m.length_s
	if not await _wait(fall_from, run):
		return
	var blade: Node3D = _sky_sword(foe.position + Vector3(0, 15.0, 0))
	var t: float = 0.0
	while t < land - fall_from:
		await ticked
		if run != _run:
			return
		t += get_process_delta_time()
		var k: float = clampf(t / (land - fall_from), 0.0, 1.0)
		blade.position = foe.position + Vector3(0.0, lerpf(15.0, 0.6, k * k), 0.0)
	_hit(foe, &"react.death")
	_slam_ring(foe.position, 2.6)
	if p.coded:
		shake(0.7, 0.4)
	if await _wait(0.6, run):
		blade.queue_free()
	await _wait(m.length_s - land - 0.6, run)


## The blade of light: the sword itself, eight times its size, point down, glowing (no image: its own mesh).
func _sky_sword(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	_stage.add_child(holder)
	var item: Node3D = SWORD.held_scene.instantiate() as Node3D
	holder.add_child(item)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(2.2, 1.9, 1.1, 0.7)   # over 1: the glow catches it
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.85, 0.45)
	glow.emission_energy_multiplier = 3.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for n: Node in item.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = glow
	# Point down: the item's blade (base to tip, its own frame) turned onto the world's down, then scaled.
	var blade: Array = SwingTrail.blade_of_item(item as HeldItem, 0.0) if item is HeldItem else []
	var along: Vector3 = ((blade[1] as Vector3) - (blade[0] as Vector3)).normalized() if blade.size() == 2 else Vector3.UP
	item.basis = MotionBones.arc(along, Vector3.DOWN, 1.0) * Basis.from_scale(Vector3.ONE * 8.0)
	var tip: Vector3 = item.basis * (blade[1] as Vector3) if blade.size() == 2 else Vector3.ZERO
	item.position = -tip
	return holder


func _spinning_dash(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -7))
	_stand(p, p.dummies[0], Vector3(0.9, 0, -3.0), Vector3.ZERO)
	_stand(p, p.dummies[1], Vector3(-0.8, 0, -5.2), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "spinning_dash", p.at(Vector3(0, 0, -7)))
	_trail(run, p, h, m.length_s + 0.1)
	var hit: Array[ShowcaseActor] = []
	var t: float = 0.0
	while t < m.length_s:
		await ticked
		if run != _run:
			return
		t += get_process_delta_time()
		for d: ShowcaseActor in [p.dummies[0], p.dummies[1]]:
			if not hit.has(d) and Vector2(d.position.x - h.position.x, d.position.z - h.position.z).length() < 1.6:
				hit.append(d)
				_hit(d)


func _hook_pull(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.axe
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -3))
	_stand(p, foe, Vector3(0, 0, -3.0), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	# THE AXE ITSELF HOOKS (Luke, 2026-11-18: "turns the axe sideways and pulls with the axe, not the red line", closer
	# in): the arm reaches past the foe's near side at the waist, the head turned sideways behind it, and yanks.
	var behind: Vector3 = foe.position + (foe.position - h.position).normalized() * 0.35 + Vector3(0.0, 1.0, 0.0)
	var m: MotionMove = _go(run, p, h, "hook_pull", foe.position, behind)
	_trail(run, p, h, 0.62 * m.length_s)
	var catch_at: float = m.impact_at * m.length_s
	if not await _wait(catch_at, run):
		return
	_hit(foe, &"")
	_go(run, p, foe, "dragged", h.position)
	if p.coded:
		shake(0.25, 0.2)
	await _wait(m.length_s - catch_at, run)


func _leap_slam(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -6))
	var land: Vector3 = Vector3(0, 0, -6.0)
	var spots: Array[Vector3] = [Vector3(1.4, 0, -6.6), Vector3(-1.3, 0, -6.4), Vector3(0.2, 0, -8.0)]
	for i: int in DUMMIES:
		_stand(p, p.dummies[i], spots[i], land)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "leap_slam", p.at(land))
	_trail(run, p, h, m.length_s * 0.75)
	if not await _wait(m.impact_at * m.length_s, run):
		return
	_slam_ring(h.position + h.facing() * 0.6, 3.2)
	if p.coded:
		shake(0.8, 0.45)
	for d: ShowcaseActor in p.dummies:
		_go(run, p, d, "knocked_up", h.position)
	await _wait(2.9, run)   # the skeletons land and kip up (knocked_up.tres)


func _backflip(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -2))
	_stand(p, foe, Vector3(0, 0, -1.9), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	foe.act(&"ability.40017")
	if not await _wait(0.2, run):
		return
	var m: MotionMove = _go(run, p, h, "backflip", foe.position)
	await _wait(m.length_s + 0.2, run)


func _shoulder_charge(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -7))
	_stand(p, foe, Vector3(0, 0, -7.2), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "shoulder_charge", foe.position)
	if not await _wait(m.impact_at * m.length_s, run):
		return
	_hit(foe, &"")
	_go(run, p, foe, "tumble", h.position)
	if p.coded:
		shake(0.45, 0.3)
	await _wait(2.5, run)   # the foe thrown back and getting up (tumble.tres)


func _blade_waltz(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -5))
	var spots: Array[Vector3] = [Vector3(-1.6, 0, -3.4), Vector3(1.8, 0, -4.6), Vector3(-0.5, 0, -6.4)]
	for i: int in DUMMIES:
		_stand(p, p.dummies[i], spots[i], Vector3(0, 0, -1))
	if not await _wait(0.1, run):
		return
	# Gone in a flash; then, for each foe, there from a new side (each a third of the way round from the last), a cut.
	var from: Vector3 = h.position
	var side: float = 0.0
	for i: int in DUMMIES:
		var d: ShowcaseActor = p.dummies[i]
		_spawn("parry_flash", from + Vector3(0.0, 1.1, 0.0))
		h.visible = false
		p.trail.emitting = false
		p.trail.clear()
		if not await _wait(0.07, run):
			return
		side += TAU / 3.0
		var stand_at: Vector3 = d.position + Vector3(sin(side), 0.0, cos(side)) * 1.1
		h.walk_to(stand_at, 0.0)
		h.face(d.position, true)
		h.visible = true
		_spawn("parry_flash", stand_at + Vector3(0.0, 1.1, 0.0))
		var m: MotionMove = _go(run, p, h, "waltz_cut", d.position)
		_trail(run, p, h, m.length_s)
		if not await _wait(m.impact_at * m.length_s, run):
			return
		_hit(d)
		if not await _wait((1.0 - m.impact_at) * m.length_s, run):
			return
		from = stand_at
	await _wait(0.6, run)


func _roundhouse_kick(run: int, p: Pack) -> void:
	var h: ShowcaseActor = p.sword
	var foe: ShowcaseActor = p.dummies[0]
	_stand(p, h, Vector3.ZERO, Vector3(0, 0, -2))
	_stand(p, foe, Vector3(0, 0, -1.3), Vector3.ZERO)
	if not await _wait(0.1, run):
		return
	var m: MotionMove = _go(run, p, h, "roundhouse_kick", foe.position)
	if not await _wait(m.impact_at * m.length_s, run):
		return
	_hit(foe, &"")
	_go(run, p, foe, "kicked", h.position)
	if p.coded:
		shake(0.4, 0.25)
	await _wait(2.3, run)   # the foe flies, lands and kips up (kicked.tres)


# ---------------------------------------------------------------- shots

## A move's name as a file name ("Leap slam" -> "leap_slam").
# ---------------------------------------------------------------- the clip browser

## A move that is clip `clip_name` (`<library>/<clip>`) from `from_s` to `to_s` (0: its end), nothing else.
static func clip_move(clip_name: StringName, from_s: float = 0.0, to_s: float = 0.0) -> MotionMove:
	var clip: Animation = MotionClip.find(clip_name)
	var end_s: float = to_s if to_s > 0.0 else (clip.length if clip != null else 1.0)
	var m := MotionMove.new()
	m.length_s = maxf(end_s - from_s, 0.01)
	var mc := MotionClip.new()
	mc.animation = clip_name
	mc.from_s = from_s
	mc.to_s = end_s
	mc.blend_in_s = 0.0
	mc.blend_out_s = 0.0
	m.clips = [mc]
	return m


## Every item with a held scene, once a scene: [its scene's path, a name] (found, so a new weapon shows by itself).
static func held_items() -> Array[Array]:
	var out: Array[Array] = []
	var seen: Dictionary[String, bool] = {}
	var dir: String = "res://game/regents/content/item/"
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	files.sort()
	for f: String in files:
		var file: String = f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var item: ItemDef = load(dir + file) as ItemDef
		if item == null or item.held_scene == null or seen.has(item.held_scene.resource_path):
			continue
		seen[item.held_scene.resource_path] = true
		out.append([item.held_scene.resource_path, item.display_name])
	return out


func _held_name(path: String) -> String:
	for h: Array in held_items():
		if String(h[0]) == path:
			return String(h[1])
	return "nothing" if path.is_empty() else path.get_file().get_basename()


func _browse_words() -> String:
	return "Clip browser   %s/%s, holding %s at %.2fx" % [browse_library, browse_clip, _held_name(browse_held), browse_scale]


## Choose the browser's clip (a library and a clip in it): played from the start. False when there is no such clip.
func browse(library: String, clip: StringName) -> bool:
	if MotionClip.find(StringName("%s/%s" % [library, clip])) == null:
		return false
	var refill: bool = library != browse_library
	browse_library = library
	browse_clip = clip
	_lengths.erase(BROWSER)
	if _br_libs != null:
		for k: int in _br_libs.item_count:
			if _br_libs.get_item_text(k) == library:
				_br_libs.select(k)
	if refill:
		_fill_clips(false)
	elif _br_list != null:
		for k: int in _br_list.item_count:
			if _br_list.get_item_text(k) == String(clip):
				_br_list.select(k)
				_br_list.ensure_current_is_visible()
	if current == BROWSER:
		_select(BROWSER)
	return true


## Choose what the browser's adventurer holds ("" nothing) and its size: seen at once.
func browse_hold(path: String, size: float) -> void:
	browse_held = path
	browse_scale = clampf(size, 0.25, 3.0)
	for p: Pack in [coded, plain]:
		_hold(p)
	if _br_scale_label != null:
		_br_scale_label.text = "Size %.2fx" % browse_scale
	if _br_size != null:
		_br_size.set_value_no_signal(browse_scale)
	if _br_helds != null:
		_br_helds.select(maxi(_br_held_paths.find(browse_held), 0))
	if current == BROWSER and _about != null:
		_about.text = _browse_words()


## Pack `p`'s browser adventurer holds the chosen item at the chosen size (its model only: the hold stays put).
func _hold(p: Pack) -> void:
	var a: ShowcaseActor = p.browser
	if p.browser_held != browse_held:
		if a.held != null and is_instance_valid(a.held):
			a.held.free()
		a.held = null
		if not browse_held.is_empty():
			var scene: PackedScene = load(browse_held) as PackedScene
			a.held = HeldItem.attach(a.skeleton, scene) if scene != null else null
		p.browser_held = browse_held
		p.browser_scale = 1.0
	if a.held != null and not is_equal_approx(p.browser_scale, browse_scale):
		for c: Node in a.held.get_children():
			var c3: Node3D = c as Node3D
			if c3 != null and not (c3 is Marker3D) and not (c3 is BowString):
				c3.scale *= browse_scale / p.browser_scale
		p.browser_scale = browse_scale


func _browse(run: int, p: Pack) -> void:
	var a: ShowcaseActor = p.browser
	_hold(p)
	_stand(p, a, Vector3.ZERO, Vector3(0.0, 0.0, -5.0))
	var m: MotionMove = clip_move(StringName("%s/%s" % [browse_library, browse_clip]))
	var l: MotionLayer = p.layer(a)
	l.carry = false
	l.play(m, Vector3(0.0, 0.0, -1.0))
	await _wait(m.length_s, run)
	l.carry = true


func _build_browser(root: Control) -> void:
	_br_panel = PanelContainer.new()
	_br_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_br_panel.position = Vector2(-396, 56)
	_br_panel.custom_minimum_size = Vector2(380, 0)
	_br_panel.visible = false
	root.add_child(_br_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	_br_panel.add_child(col)
	var title := Label.new()
	title.text = "Clip browser"
	title.add_theme_font_size_override(&"font_size", 20)
	col.add_child(title)
	_br_libs = OptionButton.new()
	_br_libs.focus_mode = Control.FOCUS_NONE
	var keys: Array[String] = []
	keys.assign(MotionClip.LIBRARIES.keys())
	for k: String in keys:
		_br_libs.add_item(k)
	_br_libs.select(maxi(keys.find(browse_library), 0))
	_br_libs.item_selected.connect(func(i: int) -> void:
		browse_library = _br_libs.get_item_text(i)
		_fill_clips(true))
	col.add_child(_br_libs)
	_br_filter = LineEdit.new()
	_br_filter.placeholder_text = "filter: slash, block, cast ..."
	_br_filter.text_changed.connect(func(_t: String) -> void: _fill_clips(false))
	col.add_child(_br_filter)
	_br_list = ItemList.new()
	_br_list.custom_minimum_size = Vector2(360, 360)
	_br_list.focus_mode = Control.FOCUS_NONE
	_br_list.item_selected.connect(func(i: int) -> void: browse(browse_library, StringName(_br_list.get_item_text(i))))
	col.add_child(_br_list)
	var held_label := Label.new()
	held_label.text = "Holding"
	col.add_child(held_label)
	_br_helds = OptionButton.new()
	_br_helds.focus_mode = Control.FOCUS_NONE
	_br_held_paths = PackedStringArray([""])
	_br_helds.add_item("Nothing")
	for h: Array in held_items():
		_br_held_paths.append(String(h[0]))
		_br_helds.add_item(String(h[1]))
	_br_helds.select(maxi(_br_held_paths.find(browse_held), 0))
	_br_helds.item_selected.connect(func(i: int) -> void: browse_hold(_br_held_paths[i], browse_scale))
	col.add_child(_br_helds)
	_br_scale_label = Label.new()
	_br_scale_label.text = "Size %.2fx" % browse_scale
	col.add_child(_br_scale_label)
	var size_bar := HSlider.new()
	_br_size = size_bar
	size_bar.min_value = 0.5
	size_bar.max_value = 2.0
	size_bar.step = 0.05
	size_bar.value = browse_scale
	size_bar.focus_mode = Control.FOCUS_NONE
	size_bar.value_changed.connect(func(v: float) -> void: browse_hold(browse_held, v))
	col.add_child(size_bar)
	_fill_clips(false)


## The chosen library's clips, those the filter names; `pick_first`: the first of them is played.
func _fill_clips(pick_first: bool) -> void:
	if _br_list == null:
		return
	_br_list.clear()
	var lib: AnimationLibrary = load(MotionClip.LIBRARIES.get(browse_library, "")) as AnimationLibrary
	if lib == null:
		return
	var names: PackedStringArray = PackedStringArray()
	for n: StringName in lib.get_animation_list():
		names.append(String(n))
	names.sort()
	var want: String = _br_filter.text.strip_edges().to_lower() if _br_filter != null else ""
	for n: String in names:
		if want.is_empty() or n.to_lower().contains(want):
			_br_list.add_item(n)
			if n == String(browse_clip):
				_br_list.select(_br_list.item_count - 1)
				_br_list.ensure_current_is_visible()
	if pick_first and _br_list.item_count > 0:
		_br_list.select(0)
		browse(browse_library, StringName(_br_list.get_item_text(0)))


static func slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


func _shoot(dir: String, only: String) -> void:
	_shooting = true
	var dense: bool = OS.get_cmdline_user_args().has("dense")
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 720)
	_ui.visible = false
	for i: int in 30:
		await get_tree().process_frame
	for i: int in showcases.size():   # once through unshot: every shader compiled
		_select(i)
		for f: int in 12:
			await get_tree().process_frame
	for i: int in showcases.size():
		var name_s: String = String(showcases[i][0])
		if not only.is_empty() and slug(name_s) != slug(only):
			continue
		_select(i)
		var cols: int = 4 if dense else 3
		var rows: int = 3 if dense else 2
		var sheet := Image.create(SHOT_SIZE.x * cols, SHOT_SIZE.y * rows, false, Image.FORMAT_RGB8)
		var moments: Array = showcases[i][3] as Array
		if dense:
			var span: float = _length_of(i)
			moments = []
			for k: int in 12:
				moments.append(span * (float(k) + 0.5) / 12.0)
		for k: int in moments.size():
			while not started or clock < float(moments[k]):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, SHOT_SIZE), Vector2i((k % cols) * SHOT_SIZE.x, int(k / float(cols)) * SHOT_SIZE.y))
		var file: String = dir.path_join("motion_%s%s%s.png" % [slug(name_s), "_compare" if compare else "", "_dense" if dense else ""])
		sheet.save_png(file)
		print("saved ", file)
		_run += 1
		await get_tree().create_timer(0.4).timeout
	AppExit.quit(get_tree(), 0)


## CLIP SHEETS: eight frames of each clip on the swordsman (the body only: carried nowhere), four clips to a sheet.
func _clip_sheets(dir: String, names: PackedStringArray) -> void:
	_shooting = true
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(720, 720)
	_ui.visible = false
	var list: PackedStringArray = PackedStringArray()
	var held_path: String = ""
	var held_scale: float = 1.0
	for n: String in names:
		if n.begins_with("held="):
			held_path = n.trim_prefix("held=")
		elif n.begins_with("scale="):
			held_scale = n.trim_prefix("scale=").to_float()
		else:
			list.append(n)
	if list.is_empty():
		list = PackedStringArray(SHEET_CLIPS)
	_run += 1
	_reset()
	var a: ShowcaseActor = coded.sword
	var l: MotionLayer = coded.layer(a)
	if not held_path.is_empty():
		var scene: PackedScene = load(held_path) as PackedScene
		if scene == null:
			print("no such held item: ", held_path)
		else:
			if a.held != null:
				a.held.queue_free()
			a.held = HeldItem.attach(a.skeleton, scene)
	if a.held != null and not is_equal_approx(held_scale, 1.0):
		# The model only (not the hold point): the grip's offsets stay what they are.
		for c: Node in a.held.get_children():
			var c3: Node3D = c as Node3D
			if c3 != null and not (c3 is Marker3D):
				c3.scale *= held_scale
	a.visible = true
	a.walk_to(Vector3.ZERO, 0.0)
	a.face(Vector3(0, 0, -5), true)
	l.carry = false
	_focus = Vector3(0, 1.1, -0.6)
	_yaw = 90.0
	_pitch = -6.0
	_dist = 5.0
	for i: int in 20:
		await get_tree().process_frame
	const CELL: int = 240
	var sheet: Image = null
	var row: int = 0
	var n: int = 0
	for entry: String in list:
		# `<library>/<name>`, or `<library>/<name>@<from>-<to>`: a part of it (s).
		var c: String = entry.get_slice("@", 0)
		var clip: Animation = MotionClip.find(StringName(c))
		if clip == null:
			print("no such clip: ", c)
			continue
		var from_s: float = 0.0
		var to_s: float = clip.length
		if entry.contains("@"):
			var span: String = entry.get_slice("@", 1)
			from_s = clampf(span.get_slice("-", 0).to_float(), 0.0, clip.length)
			to_s = clampf(span.get_slice("-", 1).to_float(), from_s + 0.01, clip.length)
		var m: MotionMove = clip_move(StringName(c), from_s, to_s)
		if sheet == null:
			sheet = Image.create(CELL * 8, CELL * 4, false, Image.FORMAT_RGB8)
		l.play(m, Vector3(0, 0, -1))
		l.speed = 0.0
		var times: PackedStringArray = []
		for k: int in 8:
			var ts: float = m.length_s * (float(k) + 0.5) / 8.0
			times.append("%.2f" % (from_s + ts))
			l.t = ts
			for f: int in 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.resize(CELL, CELL, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), Vector2i(k * CELL, row * CELL))
		l.speed = 1.0
		l.stop()
		print("clips_%d row %d: %s (%.2f s) at %s" % [n, row, entry, clip.length, " ".join(times)])
		row += 1
		if row == 4:
			sheet.save_png(dir.path_join("clips_%d.png" % n))
			sheet = null
			row = 0
			n += 1
	if sheet != null:
		sheet.save_png(dir.path_join("clips_%d.png" % n))
	l.carry = true
	AppExit.quit(get_tree(), 0)
