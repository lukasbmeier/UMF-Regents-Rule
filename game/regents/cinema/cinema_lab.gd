class_name CinemaLab extends Node3D
## CINEMATIC, DIALOG, FLASHBACK & TRAILER PROOF-OF-CONCEPT (`res://game/regents/cinema/cinema_lab.tscn`, press F6).
## Runs completely offline on top of the real `frontier.tscn` glade without touching `regents_game.tscn` or the server.
##
##   1. Dialog & Cuts       — Dialogue Manager 3-style branching script + 4 visual styles + Voice-Over + shot cuts
##   2. Flashbacks          — Decision-driven memories compared side-by-side:
##                            (A) In-Place Memory Echo (hides present actors, memory grade shader, spawns past actors)
##                            (B) Isolated 3D Diorama Stage (torchlit `own_world_3d` SubViewport)
##   3. Trailer & Director  — 3-shot choreographed trailer (forge dolly, slow-mo clash, crane reveal) +
##                            Interactive Director Free-Cam (WASD/QE, RMB look, wheel FOV, [/] speed, K/P dolly rail)

enum Part {
	DIALOG,
	FLASHBACK,
	TRAILER,
}

enum FlashbackMode {
	NONE,
	ECHO,
	STAGE,
}

const FRONTIER_SCENE: PackedScene = preload("res://game/regents/levels/frontier.tscn")
const DEF_ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const DEF_GUIDE: EntityDefinition = preload("res://game/regents/content/character/guide.tres")
const DEF_SKELETON_WARRIOR: EntityDefinition = preload("res://game/regents/content/character/skeleton_warrior.tres")
const DEF_SKELETON_ARCHER: EntityDefinition = preload("res://game/regents/content/character/skeleton_archer.tres")
const DEF_IMP: EntityDefinition = preload("res://game/regents/content/character/imp.tres")
const FOE_SKELETON_ARCHER: FoeDef = preload("res://game/regents/content/foe/skeleton_archer.tres")
const FOE_IMP: FoeDef = preload("res://game/regents/content/foe/imp.tres")
const WEAPON_SWORD: PackedScene = preload("res://game/regents/combat/weapons/iron_sword.tscn")
const WEAPON_STAFF: PackedScene = preload("res://game/regents/combat/weapons/yew_staff.tscn")
const WEAPON_HAMMER: PackedScene = preload("res://game/regents/skilling/smithing/hammer.tscn")
const PROP_ANVIL: PackedScene = preload("res://game/regents/art/props/Anvil.gltf")
const PROP_FIREPIT: PackedScene = preload("res://game/regents/art/props/FirePit.gltf")
const PROP_SHIELD: PackedScene = preload("res://game/regents/art/props/Shield_Wooden.gltf")
const PROP_SWORD: PackedScene = preload("res://game/regents/art/props/Sword_Bronze.gltf")
const PROP_ROCK: PackedScene = preload("res://game/regents/art/nature/Rock_Big_1.gltf")

var active_part: Part = Part.DIALOG
var active_flashback: FlashbackMode = FlashbackMode.NONE
var voice_enabled: bool = true
var trailer_playing: bool = false
var director_active: bool = false
var ui_hidden: bool = false

var dialogue: CinemaDialogue = CinemaDialogue.new()
var balloon: CinemaBalloon = null

var _world: Node3D = null
var _camera: Camera3D = null
var _cam_attrs: CameraAttributesPractical = null
var _voice_player: AudioStreamPlayer = null

## Actors
var _present_root: Node3D = null
var _drillmaster: Mannequin = null
var _chronicler: Mannequin = null
var _adventurer: Mannequin = null

var _echo_root: Node3D = null
var _echo_captain: Mannequin = null
var _echo_adventurer: Mannequin = null
var _echo_archer: Mannequin = null
var _echo_imp: Mannequin = null

var _trailer_root: Node3D = null
var _tr_anvil: Node3D = null
var _tr_firepit: Node3D = null
var _tr_smith: Mannequin = null
var _tr_hero: Mannequin = null
var _tr_warrior: Mannequin = null
var _tr_archer: Mannequin = null
var _tr_sparks: CPUParticles3D = null
var _actor_rigs: Dictionary = {}

## Camera interpolation
var _cam_from: Transform3D = Transform3D.IDENTITY
var _cam_to: Transform3D = Transform3D.IDENTITY
var _cam_fov_from: float = 48.0
var _cam_fov_to: float = 48.0
var _cam_dof_from: float = 4.5
var _cam_dof_to: float = 4.5
var _cam_t: float = 1.0
var _cam_dur: float = 0.7

## UI & Overlays
var _ui_layer: CanvasLayer = null
var _memory_grade: ColorRect = null
var _stage_container: SubViewportContainer = null
var _stage_viewport: SubViewport = null
var _stage_camera: Camera3D = null
var _stage_captain: Mannequin = null
var _stage_hero: Mannequin = null
var _stage_foe: Mannequin = null
var _stage_elapsed: float = 0.0

var _letterbox_top: ColorRect = null
var _letterbox_bot: ColorRect = null
var _letterbox_weight: float = 0.0
var _letterbox_target: float = 1.0

var _top_bar: PanelContainer = null
var _style_row: HBoxContainer = null
var _flashback_row: HBoxContainer = null
var _trailer_row: HBoxContainer = null
var _voice_btn: Button = null
var _part_buttons: Array[Button] = []
var _style_buttons: Array[Button] = []

var _title_overlay: Control = null
var _title_main: Label = null
var _title_sub: Label = null
var _director_panel: PanelContainer = null
var _director_info: Label = null

## Trailer & Director state
var _trailer_time: float = 0.0
var _trailer_shot: int = -1
var _trailer_cue: int = 0
var _fb_impact_timer: float = -1.0
var _fb_impact_outcome: String = ""
var _dir_yaw: float = 0.0
var _dir_pitch: float = -0.2
var _dir_fov: float = 45.0
var _dir_dragging: bool = false
var _dolly_curve: Curve3D = Curve3D.new()
var _dolly_yaws: Array[float] = []
var _dolly_pitches: Array[float] = []
var _dolly_fovs: Array[float] = []
var _dolly_playing: bool = false
var _dolly_t: float = 0.0
var _dolly_duration: float = 5.0


func _ready() -> void:
	_build_world()
	_build_actors()
	_build_overlays_and_ui()
	_connect_dialogue()
	set_part(Part.DIALOG)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_actor_rigs.clear()


func _build_world() -> void:
	_world = FRONTIER_SCENE.instantiate() as Node3D
	add_child(_world)

	_camera = Camera3D.new()
	_camera.name = "CinemaCamera"
	_camera.fov = 48.0
	_cam_attrs = CameraAttributesPractical.new()
	_cam_attrs.dof_blur_far_enabled = true
	_cam_attrs.dof_blur_far_distance = 12.0
	_cam_attrs.dof_blur_far_transition = 10.0
	_cam_attrs.dof_blur_amount = 0.08
	_camera.attributes = _cam_attrs
	add_child(_camera)
	_camera.current = true

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayer"
	if AudioServer.get_bus_index(&"Voice") >= 0:
		_voice_player.bus = &"Voice"
	add_child(_voice_player)


func _build_actors() -> void:
	# Present-day camp conversation group around (0, 0, 10.5)
	_present_root = Node3D.new()
	_present_root.name = "PresentActors"
	add_child(_present_root)

	_drillmaster = _spawn_mannequin(_present_root, "Drillmaster", DEF_GUIDE, 0, Vector3(1.15, 0.0, 9.6), WEAPON_SWORD)
	_chronicler = _spawn_mannequin(_present_root, "Chronicler", DEF_ADVENTURER, 2, Vector3(-0.95, 0.0, 9.8), WEAPON_STAFF)
	_adventurer = _spawn_mannequin(_present_root, "Adventurer", DEF_ADVENTURER, 0, Vector3(0.0, 0.0, 11.5), WEAPON_SWORD)
	_face_toward(_drillmaster, _adventurer.position)
	_face_toward(_chronicler, _adventurer.position)
	_face_toward(_adventurer, Vector3(0.0, 0.0, 9.7))

	# In-Place Memory Echo actors (hidden until Flashback Echo triggers)
	_echo_root = Node3D.new()
	_echo_root.name = "EchoActors"
	_echo_root.visible = false
	add_child(_echo_root)

	_echo_captain = _spawn_mannequin(_echo_root, "EchoCaptain", DEF_ADVENTURER, 6, Vector3(0.4, 0.0, 9.8), WEAPON_SWORD)
	_echo_adventurer = _spawn_mannequin(_echo_root, "EchoHero", DEF_ADVENTURER, 0, Vector3(-0.8, 0.0, 10.6), WEAPON_SWORD)
	_echo_archer = _spawn_mannequin(_echo_root, "EchoArcher", DEF_SKELETON_ARCHER, 0, Vector3(4.8, 0.0, 7.6), null, FOE_SKELETON_ARCHER)
	_echo_imp = _spawn_mannequin(_echo_root, "EchoImp", DEF_IMP, 0, Vector3(3.7, 0.0, 10.1), null, FOE_IMP)
	_face_toward(_echo_captain, _echo_imp.position)
	_face_toward(_echo_adventurer, _echo_imp.position)
	_face_toward(_echo_archer, _echo_captain.position)
	_face_toward(_echo_imp, _echo_adventurer.position)

	# Trailer actors + props (Forge near (-2, 0, 16.5) and clash near (14.4, 0, 5.8))
	_trailer_root = Node3D.new()
	_trailer_root.name = "TrailerActors"
	_trailer_root.visible = false
	add_child(_trailer_root)

	_tr_anvil = PROP_ANVIL.instantiate() as Node3D
	_tr_anvil.name = "TrailerAnvil"
	_tr_anvil.position = Vector3(-2.0, 0.0, 16.5)
	_trailer_root.add_child(_tr_anvil)

	_tr_firepit = PROP_FIREPIT.instantiate() as Node3D
	_tr_firepit.name = "TrailerFirepit"
	_tr_firepit.position = Vector3(-5.2, 0.0, 14.6)
	_trailer_root.add_child(_tr_firepit)

	_tr_smith = _spawn_mannequin(_trailer_root, "TrailerSmith", DEF_GUIDE, 0, Vector3(-2.0, 0.0, 17.4), WEAPON_HAMMER)
	_tr_hero = _spawn_mannequin(_trailer_root, "TrailerHero", DEF_ADVENTURER, 4, Vector3(-0.3, 0.0, 16.8), WEAPON_SWORD)
	_tr_warrior = _spawn_mannequin(_trailer_root, "TrailerWarrior", DEF_SKELETON_WARRIOR, 0, Vector3(16.4, 0.0, 5.2))
	_tr_archer = _spawn_mannequin(_trailer_root, "TrailerArcher", DEF_SKELETON_ARCHER, 0, Vector3(18.0, 0.0, 3.4), null, FOE_SKELETON_ARCHER)
	_face_toward(_tr_smith, _tr_anvil.position)
	_face_toward(_tr_hero, _tr_smith.position)
	_face_toward(_tr_warrior, Vector3(13.9, 0.0, 5.9))
	_face_toward(_tr_archer, Vector3(13.9, 0.0, 5.9))

	_tr_sparks = CPUParticles3D.new()
	_tr_sparks.position = Vector3(14.35, 1.15, 5.85)
	_tr_sparks.amount = 36
	_tr_sparks.lifetime = 0.55
	_tr_sparks.one_shot = false
	_tr_sparks.explosiveness = 0.85
	_tr_sparks.initial_velocity_min = 2.2
	_tr_sparks.initial_velocity_max = 6.0
	_tr_sparks.spread = 60.0
	var spark_mesh: BoxMesh = BoxMesh.new()
	spark_mesh.size = Vector3(0.035, 0.035, 0.035)
	var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.72, 0.24, 1.0)
	spark_mesh.material = spark_mat
	_tr_sparks.mesh = spark_mesh
	_tr_sparks.emitting = false
	_trailer_root.add_child(_tr_sparks)


func _build_overlays_and_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MinigameLook.theme()
	_ui_layer.add_child(root)

	# Isolated 3D Stage Flashback Viewport (own_world_3d = true)
	_stage_container = SubViewportContainer.new()
	_stage_container.name = "FlashbackStageContainer"
	_stage_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_container.stretch = true
	_stage_container.visible = false
	_stage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage_container)

	_stage_viewport = SubViewport.new()
	_stage_viewport.own_world_3d = true
	_stage_viewport.size = Vector2i(1280, 720)
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage_container.add_child(_stage_viewport)
	_build_diorama_stage(_stage_viewport)

	# Memory Echo fullscreen color-grade + vignette shader
	_memory_grade = ColorRect.new()
	_memory_grade.name = "MemoryEchoShader"
	_memory_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_memory_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_memory_grade.visible = false
	var mem_mat := ShaderMaterial.new()
	mem_mat.shader = Shader.new()
	mem_mat.shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 sepia = vec3(lum * 0.92, lum * 0.98, lum * 1.15);
	vec3 graded = mix(c, sepia, 0.58);
	vec2 d = SCREEN_UV * 2.0 - 1.0;
	float vig = smoothstep(0.42, 1.35, dot(d, d));
	float pulse = 0.04 * sin(TIME * 2.1);
	graded = mix(graded, vec3(0.05, 0.07, 0.12), clamp(vig * 0.72 + pulse, 0.0, 0.85));
	COLOR = vec4(graded, 1.0);
}
"""
	_memory_grade.material = mem_mat
	root.add_child(_memory_grade)

	# Letterbox bars
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color(0.02, 0.02, 0.025, 0.96)
	_letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_letterbox_top.offset_bottom = 0.0
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_letterbox_top)

	_letterbox_bot = ColorRect.new()
	_letterbox_bot.color = Color(0.02, 0.02, 0.025, 0.96)
	_letterbox_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_letterbox_bot.offset_top = 0.0
	_letterbox_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_letterbox_bot)

	# Dialog balloon
	balloon = CinemaBalloon.new()
	balloon.set_world_camera(_camera)
	root.add_child(balloon)
	balloon.advance_requested.connect(func() -> void: dialogue.advance())
	balloon.choice_picked.connect(func(idx: int) -> void: dialogue.choose(idx))

	# Trailer title overlay
	_title_overlay = Control.new()
	_title_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_overlay.visible = false
	root.add_child(_title_overlay)

	var tvbox := VBoxContainer.new()
	tvbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tvbox.offset_left = -420.0
	tvbox.offset_right = 420.0
	tvbox.offset_top = -80.0
	tvbox.offset_bottom = 80.0
	tvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_overlay.add_child(tvbox)

	_title_main = Label.new()
	_title_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_main.add_theme_font_size_override(&"font_size", 46)
	_title_main.add_theme_color_override(&"font_color", MinigameLook.GOLD)
	_title_main.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	_title_main.add_theme_constant_override(&"outline_size", 8)
	tvbox.add_child(_title_main)

	_title_sub = Label.new()
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub.add_theme_font_size_override(&"font_size", 20)
	_title_sub.add_theme_color_override(&"font_color", MinigameLook.INK)
	_title_sub.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	_title_sub.add_theme_constant_override(&"outline_size", 5)
	tvbox.add_child(_title_sub)

	# Director readout panel
	_director_panel = PanelContainer.new()
	_director_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_director_panel.offset_left = 18.0
	_director_panel.offset_right = 560.0
	_director_panel.offset_top = -140.0
	_director_panel.offset_bottom = -20.0
	_director_panel.visible = false
	var dbg := StyleBoxFlat.new()
	dbg.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	dbg.border_color = Color(0.78, 0.62, 0.32, 0.8)
	dbg.set_border_width_all(2)
	dbg.set_corner_radius_all(4)
	dbg.content_margin_left = 12.0
	dbg.content_margin_right = 12.0
	dbg.content_margin_top = 8.0
	dbg.content_margin_bottom = 8.0
	_director_panel.add_theme_stylebox_override(&"panel", dbg)
	root.add_child(_director_panel)

	_director_info = Label.new()
	_director_info.add_theme_font_size_override(&"font_size", 15)
	_director_info.add_theme_color_override(&"font_color", MinigameLook.INK)
	_director_panel.add_child(_director_info)

	# Top Lab Switcher Toolbar
	_top_bar = PanelContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 12.0
	_top_bar.offset_right = -12.0
	_top_bar.offset_top = 8.0
	_top_bar.offset_bottom = 54.0
	var tbg := StyleBoxFlat.new()
	tbg.bg_color = Color(0.06, 0.05, 0.05, 0.86)
	tbg.border_color = Color(0.78, 0.62, 0.32, 0.75)
	tbg.set_border_width_all(1)
	tbg.set_corner_radius_all(4)
	tbg.content_margin_left = 8.0
	tbg.content_margin_right = 8.0
	tbg.content_margin_top = 4.0
	tbg.content_margin_bottom = 4.0
	_top_bar.add_theme_stylebox_override(&"panel", tbg)
	root.add_child(_top_bar)

	var bar_hbox := HBoxContainer.new()
	bar_hbox.add_theme_constant_override(&"separation", 10)
	_top_bar.add_child(bar_hbox)

	var part_names: PackedStringArray = ["1. Dialog & Cuts", "2. Flashbacks", "3. Trailer & Director"]
	for i: int in part_names.size():
		var idx: int = i
		var b := Button.new()
		b.text = part_names[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: set_part(idx as Part))
		bar_hbox.add_child(b)
		_part_buttons.append(b)

	bar_hbox.add_child(VSeparator.new())

	_style_row = HBoxContainer.new()
	_style_row.add_theme_constant_override(&"separation", 4)
	bar_hbox.add_child(_style_row)
	for i: int in CinemaBalloon.STYLE_NAMES.size():
		var s_idx: int = i
		var sb := Button.new()
		sb.text = CinemaBalloon.STYLE_NAMES[i]
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.pressed.connect(func() -> void: set_dialog_style(s_idx as CinemaBalloon.Style))
		_style_row.add_child(sb)
		_style_buttons.append(sb)

	_voice_btn = Button.new()
	_voice_btn.text = "VO: On"
	_voice_btn.focus_mode = Control.FOCUS_NONE
	_voice_btn.pressed.connect(_toggle_voice)
	_style_row.add_child(_voice_btn)

	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.pressed.connect(func() -> void: set_part(active_part))
	_style_row.add_child(restart_btn)

	_flashback_row = HBoxContainer.new()
	_flashback_row.add_theme_constant_override(&"separation", 6)
	_flashback_row.visible = false
	bar_hbox.add_child(_flashback_row)

	var fb_echo := Button.new()
	fb_echo.text = "Style A: Memory Echo"
	fb_echo.focus_mode = Control.FOCUS_NONE
	fb_echo.pressed.connect(func() -> void: launch_flashback_demo(FlashbackMode.ECHO))
	_flashback_row.add_child(fb_echo)

	var fb_stage := Button.new()
	fb_stage.text = "Style B: 3D Diorama Stage"
	fb_stage.focus_mode = Control.FOCUS_NONE
	fb_stage.pressed.connect(func() -> void: launch_flashback_demo(FlashbackMode.STAGE))
	_flashback_row.add_child(fb_stage)

	_trailer_row = HBoxContainer.new()
	_trailer_row.add_theme_constant_override(&"separation", 6)
	_trailer_row.visible = false
	bar_hbox.add_child(_trailer_row)

	var tr_btn := Button.new()
	tr_btn.text = "Play 3-Shot Trailer"
	tr_btn.focus_mode = Control.FOCUS_NONE
	tr_btn.pressed.connect(start_trailer)
	_trailer_row.add_child(tr_btn)

	var dir_btn := Button.new()
	dir_btn.text = "Director Free-Cam"
	dir_btn.focus_mode = Control.FOCUS_NONE
	dir_btn.pressed.connect(start_director)
	_trailer_row.add_child(dir_btn)

	var hide_btn := Button.new()
	hide_btn.text = "Hide UI (H)"
	hide_btn.focus_mode = Control.FOCUS_NONE
	hide_btn.pressed.connect(toggle_ui_visibility)
	_trailer_row.add_child(hide_btn)


func _build_diorama_stage(vp: SubViewport) -> void:
	var stage_root := Node3D.new()
	stage_root.name = "DioramaStage"
	vp.add_child(stage_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.36, 1.0)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.7
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	stage_root.add_child(wenv)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.11, 0.10, 0.12, 1.0)
	fmat.roughness = 0.9
	plane.material = fmat
	floor_mesh.mesh = plane
	stage_root.add_child(floor_mesh)

	var firepit: Node3D = PROP_FIREPIT.instantiate() as Node3D
	firepit.position = Vector3(0.0, 0.0, 0.0)
	stage_root.add_child(firepit)

	var rock_l: Node3D = PROP_ROCK.instantiate() as Node3D
	rock_l.position = Vector3(-4.2, 0.0, -3.5)
	stage_root.add_child(rock_l)

	var rock_r: Node3D = PROP_ROCK.instantiate() as Node3D
	rock_r.position = Vector3(4.5, 0.0, -2.8)
	rock_r.rotation.y = 1.2
	stage_root.add_child(rock_r)

	var shield: Node3D = PROP_SHIELD.instantiate() as Node3D
	shield.position = Vector3(-1.3, 0.15, 0.8)
	shield.rotation = Vector3(-0.35, 0.4, 0.2)
	stage_root.add_child(shield)

	var sword: Node3D = PROP_SWORD.instantiate() as Node3D
	sword.position = Vector3(1.1, 0.1, 0.6)
	sword.rotation = Vector3(1.5, -0.5, 0.2)
	stage_root.add_child(sword)

	var torch := OmniLight3D.new()
	torch.position = Vector3(0.0, 1.6, 0.0)
	torch.light_color = Color(1.0, 0.56, 0.20, 1.0)
	torch.light_energy = 4.5
	torch.omni_range = 12.0
	stage_root.add_child(torch)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35.0, -140.0, 0.0)
	moon.light_color = Color(0.55, 0.68, 0.95, 1.0)
	moon.light_energy = 0.75
	stage_root.add_child(moon)

	_stage_captain = _spawn_mannequin(stage_root, "StageCaptain", DEF_ADVENTURER, 6, Vector3(0.95, 0.0, -0.4), WEAPON_SWORD)
	_stage_hero = _spawn_mannequin(stage_root, "StageHero", DEF_ADVENTURER, 0, Vector3(-1.05, 0.0, 0.2), WEAPON_SWORD)
	_stage_foe = _spawn_mannequin(stage_root, "StageFoe", DEF_SKELETON_WARRIOR, 0, Vector3(0.3, 0.0, -4.2))
	_face_toward(_stage_captain, _stage_foe.position)
	_face_toward(_stage_hero, _stage_foe.position)
	_face_toward(_stage_foe, _stage_hero.position)

	_stage_camera = Camera3D.new()
	_stage_camera.fov = 40.0
	stage_root.add_child(_stage_camera)
	_stage_camera.look_at_from_position(Vector3(-2.6, 1.85, 3.8), Vector3(0.0, 1.25, -0.8))


func _connect_dialogue() -> void:
	dialogue.load_script(CinemaDialogue.FRONTIER_SCRIPT)
	dialogue.line_started.connect(_on_line_started)
	dialogue.choices_presented.connect(_on_choices_presented)
	dialogue.action_triggered.connect(_on_dialogue_action)
	dialogue.dialogue_ended.connect(_on_dialogue_ended)


# --- Public Controls -----------------------------------------------------------------

func set_part(part: Part) -> void:
	active_part = part
	trailer_playing = false
	director_active = false
	_dolly_playing = false
	_fb_impact_timer = -1.0
	Engine.time_scale = 1.0
	_title_overlay.visible = false
	_director_panel.visible = false
	_trailer_root.visible = false
	_tr_sparks.emitting = false
	_exit_flashback()

	for i: int in _part_buttons.size():
		_part_buttons[i].set_pressed_no_signal(i == int(part))
	_style_row.visible = (part != Part.TRAILER)
	_flashback_row.visible = (part == Part.FLASHBACK)
	_trailer_row.visible = (part == Part.TRAILER)
	set_dialog_style(balloon.current_style)

	if part == Part.DIALOG:
		_letterbox_target = 1.0
		_reset_present_cast()
		balloon.visible = true
		dialogue.load_script(CinemaDialogue.FRONTIER_SCRIPT)
		dialogue.start("start")
	elif part == Part.FLASHBACK:
		_letterbox_target = 1.0
		balloon.visible = true
		launch_flashback_demo(FlashbackMode.ECHO)
	elif part == Part.TRAILER:
		balloon.clear_dialogue()
		start_trailer()


func set_dialog_style(s: CinemaBalloon.Style) -> void:
	balloon.set_style(s)
	for i: int in _style_buttons.size():
		_style_buttons[i].set_pressed_no_signal(i == int(s))


func launch_flashback_demo(mode: FlashbackMode) -> void:
	active_part = Part.FLASHBACK
	for i: int in _part_buttons.size():
		_part_buttons[i].set_pressed_no_signal(i == int(Part.FLASHBACK))
	_style_row.visible = true
	_flashback_row.visible = true
	_trailer_row.visible = false
	balloon.visible = true
	dialogue.load_script(CinemaDialogue.FRONTIER_SCRIPT)
	if mode == FlashbackMode.STAGE:
		_enter_flashback(FlashbackMode.STAGE)
	else:
		_enter_flashback(FlashbackMode.ECHO)
	dialogue.start("flashback_prompt")


func start_trailer() -> void:
	active_part = Part.TRAILER
	trailer_playing = true
	director_active = false
	_dolly_playing = false
	_fb_impact_timer = -1.0
	_trailer_time = 0.0
	_trailer_shot = -1
	_trailer_cue = 0
	_letterbox_target = 1.0
	_director_panel.visible = false
	if _present_root != null:
		_present_root.visible = false
	_trailer_root.visible = true
	balloon.clear_dialogue()
	_apply_trailer_shot(0)


func start_director() -> void:
	active_part = Part.TRAILER
	trailer_playing = false
	director_active = true
	_dolly_playing = false
	_fb_impact_timer = -1.0
	Engine.time_scale = 1.0
	_letterbox_target = 0.0
	_title_overlay.visible = false
	if _present_root != null:
		_present_root.visible = false
	_trailer_root.visible = true
	_tr_sparks.position = Vector3(14.35, 1.15, 5.85)
	_tr_sparks.emitting = true
	_tr_hero.position = Vector3(13.9, 0.0, 5.9)
	_tr_warrior.position = Vector3(14.9, 0.0, 5.65)
	_tr_archer.position = Vector3(18.0, 0.0, 3.4)
	_set_actor_mark(_tr_hero, _tr_hero.position, _tr_warrior.position, 0.0)
	_set_actor_mark(_tr_warrior, _tr_warrior.position, _tr_hero.position, 0.0)
	_set_actor_mark(_tr_archer, _tr_archer.position, _tr_hero.position, 0.0)
	_face_toward(_tr_hero, _tr_warrior.position)
	_face_toward(_tr_warrior, _tr_hero.position)
	_face_toward(_tr_archer, _tr_hero.position)
	_fire_actor(_tr_hero, &"pose.block")
	_fire_actor(_tr_warrior, &"ability.40017")
	_fire_actor(_tr_archer, &"pose.bow_aim")
	_director_panel.visible = not ui_hidden
	balloon.clear_dialogue()
	_dir_fov = _camera.fov
	var euler: Vector3 = _camera.rotation
	_dir_pitch = euler.x
	_dir_yaw = euler.y
	_update_director_text()


func toggle_ui_visibility() -> void:
	ui_hidden = not ui_hidden
	if _top_bar != null:
		_top_bar.visible = not ui_hidden
	if _director_panel != null:
		_director_panel.visible = director_active and not ui_hidden


func add_dolly_keyframe() -> void:
	_dolly_curve.add_point(_camera.global_position)
	_dolly_yaws.append(_dir_yaw)
	_dolly_pitches.append(_dir_pitch)
	_dolly_fovs.append(_dir_fov)
	_update_director_text()


func clear_dolly() -> void:
	_dolly_curve.clear_points()
	_dolly_yaws.clear()
	_dolly_pitches.clear()
	_dolly_fovs.clear()
	_dolly_playing = false
	_update_director_text()


func play_dolly() -> void:
	if _dolly_curve.point_count < 2:
		return
	_dolly_playing = true
	_dolly_t = 0.0
	_update_director_text()


func stop_dolly() -> void:
	_dolly_playing = false
	_update_director_text()


# --- Dialogue Callbacks --------------------------------------------------------------

func _on_line_started(line: Dictionary) -> void:
	balloon.visible = true
	var speaker: String = String(line.get("speaker", ""))
	var tags: Dictionary = line.get("tags", {}) as Dictionary
	var pose: StringName = StringName(String(tags.get("pose", "interact")))
	var cam_key: String = String(tags.get("cam", ""))

	var actor: Mannequin = _actor_for(speaker)
	if active_flashback == FlashbackMode.NONE:
		_clear_pose(_drillmaster)
		_clear_pose(_chronicler)
		_clear_pose(_adventurer)
		var listener_pos: Vector3 = _actor_mark_pos(_adventurer) if speaker != "Adventurer" else _chronicler.position
		if actor != null:
			_set_actor_look(actor, listener_pos)
			if speaker != "Adventurer":
				_set_actor_look(_adventurer, actor.position)
				var other: Mannequin = _chronicler if actor == _drillmaster else _drillmaster
				_set_actor_look(other, actor.position)
			else:
				_set_actor_look(_drillmaster, _actor_mark_pos(_adventurer))
				_set_actor_look(_chronicler, _actor_mark_pos(_adventurer))
	if actor != null:
		_fire_actor(actor, pose)
	var def: EntityDefinition = actor.definition if actor != null else DEF_GUIDE
	var look_idx: int = actor.look if actor != null else 0
	var head_pos: Vector3 = (actor.global_position + Vector3(0.0, 1.72, 0.0)) if actor != null else Vector3(0.0, 1.7, 10.0)

	var stream: AudioStream = CinemaDialogue.resolve_voice(line, CinemaDialogue.VOICE_DIR_DEFAULT, true)
	var voiced: bool = stream != null and voice_enabled
	balloon.show_line(line, def, look_idx, head_pos, voiced)
	if voiced and _voice_player != null:
		_voice_player.stream = stream
		_voice_player.play()

	if not cam_key.is_empty():
		_move_camera_preset(cam_key, speaker)


func _on_choices_presented(choices: Array[Dictionary]) -> void:
	balloon.visible = true
	balloon.show_choices(choices)


func _on_dialogue_action(action: String, arg: String) -> void:
	if action == "flashback":
		_enter_flashback(FlashbackMode.STAGE if arg == "stage" else FlashbackMode.ECHO)
	elif action == "end_flashback":
		_exit_flashback()
	elif action == "memory_outcome":
		_fb_impact_outcome = arg
		_fb_impact_timer = 0.42
		if active_flashback == FlashbackMode.STAGE:
			if arg == "shield_wall":
				_set_actor_mark(_stage_captain, Vector3(0.85, 0.0, -1.2), _stage_foe.position, 2.2, 0.35)
				_set_actor_mark(_stage_hero, Vector3(-0.45, 0.0, -1.0), _stage_foe.position, 2.5, 0.45)
				_fire_actor(_stage_captain, &"ability.40022")
				_fire_actor(_stage_hero, &"ability.40003")
			else:
				_set_actor_mark(_stage_hero, Vector3(-1.35, 0.0, 0.9), _stage_foe.position, 2.8, 0.55)
				_fire_actor(_stage_captain, &"ability.40011")
				_fire_actor(_stage_hero, &"ability.40010")
		elif active_flashback == FlashbackMode.ECHO:
			if arg == "shield_wall":
				_set_actor_mark(_echo_captain, Vector3(1.25, 0.0, 9.7), _echo_imp.position, 2.2, 0.35)
				_set_actor_mark(_echo_adventurer, Vector3(0.25, 0.0, 10.3), _echo_imp.position, 2.5, 0.45)
				_fire_actor(_echo_captain, &"ability.40022")
				_fire_actor(_echo_adventurer, &"ability.40003")
			else:
				_set_actor_mark(_echo_adventurer, Vector3(-1.55, 0.0, 11.2), _echo_imp.position, 2.8, 0.55)
				_fire_actor(_echo_captain, &"ability.40011")
				_fire_actor(_echo_adventurer, &"ability.40010")


func _on_dialogue_ended() -> void:
	_exit_flashback()
	balloon.clear_dialogue()
	_move_camera_preset("wide_camp", "")


func _enter_flashback(mode: FlashbackMode) -> void:
	active_flashback = mode
	_fb_impact_timer = -1.0
	if mode == FlashbackMode.ECHO:
		_present_root.visible = false
		_echo_root.visible = true
		_memory_grade.visible = true
		_stage_container.visible = false
		_stage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_echo_captain.position = Vector3(0.4, 0.0, 9.8)
		_echo_adventurer.position = Vector3(-0.8, 0.0, 10.6)
		_echo_archer.position = Vector3(6.8, 0.0, 6.2)
		_echo_imp.position = Vector3(5.9, 0.0, 10.6)
		_set_actor_mark(_echo_captain, _echo_captain.position, _echo_imp.position, 0.0)
		_set_actor_mark(_echo_adventurer, _echo_adventurer.position, _echo_imp.position, 0.0)
		_set_actor_mark(_echo_archer, Vector3(4.8, 0.0, 7.6), _echo_captain.position, 1.8, 0.25)
		_set_actor_mark(_echo_imp, Vector3(3.4, 0.0, 10.0), _echo_adventurer.position, 2.1, 0.35)
		_face_toward(_echo_captain, _echo_imp.position)
		_face_toward(_echo_adventurer, _echo_imp.position)
		_face_toward(_echo_archer, _echo_captain.position)
		_face_toward(_echo_imp, _echo_adventurer.position)
		_clear_pose(_echo_captain)
		_clear_pose(_echo_adventurer)
		_fire_actor(_echo_archer, &"pose.bow_aim")
		_fire_actor(_echo_imp, &"pose.spell_cast")
		balloon.set_world_camera(_camera)
	elif mode == FlashbackMode.STAGE:
		_present_root.visible = false
		_echo_root.visible = false
		_memory_grade.visible = false
		_stage_container.visible = true
		_stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_stage_elapsed = 0.0
		_stage_captain.position = Vector3(0.95, 0.0, -0.4)
		_stage_hero.position = Vector3(-1.05, 0.0, 0.2)
		_stage_foe.position = Vector3(0.3, 0.0, -4.4)
		_set_actor_mark(_stage_captain, _stage_captain.position, _stage_foe.position, 0.0)
		_set_actor_mark(_stage_hero, _stage_hero.position, _stage_foe.position, 0.0)
		_set_actor_mark(_stage_foe, Vector3(0.15, 0.0, -2.2), _stage_hero.position, 1.8, 0.28)
		_face_toward(_stage_captain, _stage_foe.position)
		_face_toward(_stage_hero, _stage_foe.position)
		_face_toward(_stage_foe, _stage_hero.position)
		_clear_pose(_stage_captain)
		_clear_pose(_stage_hero)
		_clear_pose(_stage_foe)
		balloon.set_world_camera(_stage_camera)


func _exit_flashback() -> void:
	active_flashback = FlashbackMode.NONE
	_fb_impact_timer = -1.0
	if _present_root != null:
		_present_root.visible = true
	if _echo_root != null:
		_echo_root.visible = false
	if _memory_grade != null:
		_memory_grade.visible = false
	if _stage_container != null:
		_stage_container.visible = false
	if _stage_viewport != null:
		_stage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if balloon != null and _camera != null:
		balloon.set_world_camera(_camera)


func _actor_for(speaker: String) -> Mannequin:
	if active_flashback == FlashbackMode.ECHO:
		if speaker == "Vanguard Captain":
			return _echo_captain
		if speaker == "Adventurer":
			return _echo_adventurer
	elif active_flashback == FlashbackMode.STAGE:
		if speaker == "Vanguard Captain":
			return _stage_captain
		if speaker == "Adventurer":
			return _stage_hero
	match speaker:
		"Drillmaster":
			return _drillmaster
		"Chronicler":
			return _chronicler
		"Adventurer":
			return _adventurer
	return _drillmaster


# --- Camera Presets ------------------------------------------------------------------

func _move_camera_preset(preset: String, speaker: String) -> void:
	var target_pos: Vector3 = Vector3(-2.6, 2.0, 14.4)
	var look_at_pt: Vector3 = Vector3(0.1, 1.25, 10.2)
	var fov: float = 48.0
	var dof: float = 4.5
	var dur: float = 0.55

	match preset:
		"wide_camp":
			target_pos = Vector3(-2.7, 2.05, 14.4)
			look_at_pt = Vector3(0.1, 1.25, 10.3)
			fov = 48.0
			dof = 5.0
		"over_shoulder_npc":
			var npc: Mannequin = _actor_for(speaker)
			var npc_p: Vector3 = npc.global_position if npc != null else Vector3(0.0, 0.0, 9.7)
			target_pos = _actor_mark_pos(_adventurer) + Vector3(0.68, 1.58, 0.92)
			look_at_pt = npc_p + Vector3(0.0, 1.42, 0.0)
			fov = 38.0
			dof = target_pos.distance_to(look_at_pt)
		"over_shoulder_player":
			target_pos = Vector3(-1.42, 1.62, 8.75)
			look_at_pt = _actor_mark_pos(_adventurer) + Vector3(0.0, 1.45, 0.0)
			fov = 38.0
			dof = target_pos.distance_to(look_at_pt)
		"two_shot":
			target_pos = Vector3(-2.75, 1.50, 11.2)
			look_at_pt = Vector3(0.05, 1.35, 10.2)
			fov = 38.0
			dof = 2.9
		"closeup_npc":
			var focus: Mannequin = _actor_for(speaker)
			var fp: Vector3 = focus.global_position if focus != null else Vector3(0.0, 0.0, 9.7)
			var opp: Vector3 = _actor_mark_pos(_adventurer) if speaker != "Adventurer" else _chronicler.position
			var dir: Vector3 = (opp - fp)
			dir.y = 0.0
			dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK
			target_pos = fp + dir * 1.75 + Vector3(0.24, 1.52, 0.0)
			look_at_pt = fp + Vector3(0.0, 1.46, 0.0)
			fov = 30.0
			dof = 1.9
		"flashback_focus":
			target_pos = Vector3(-2.0, 1.62, 12.4)
			look_at_pt = Vector3(1.8, 1.32, 9.3)
			fov = 40.0
			dof = 4.2
			dur = 0.45
		"flashback_clash":
			target_pos = Vector3(2.6, 1.52, 11.9)
			look_at_pt = Vector3(1.1, 1.28, 9.6)
			fov = 42.0
			dof = 4.0
			dur = 0.35

	var next_xform: Transform3D = _camera.global_transform
	next_xform.origin = target_pos
	next_xform = next_xform.looking_at(look_at_pt, Vector3.UP)
	_cam_from = _camera.global_transform if _camera.global_transform.origin != Vector3.ZERO else next_xform
	_cam_to = next_xform
	_cam_fov_from = _camera.fov
	_cam_fov_to = fov
	_cam_dof_from = _cam_attrs.dof_blur_far_distance
	_cam_dof_to = dof
	_cam_dur = dur
	_cam_t = 0.0


# --- Process Loop (Camera, Trailer, Stage, Director) ---------------------------------

func _process(delta: float) -> void:
	var real_delta: float = delta / maxf(0.05, Engine.time_scale)
	_update_actors(delta, real_delta)

	if _fb_impact_timer >= 0.0:
		_fb_impact_timer -= real_delta
		if _fb_impact_timer < 0.0:
			_trigger_flashback_impact()

	_letterbox_weight = move_toward(_letterbox_weight, _letterbox_target, real_delta * 3.5)
	var bar_h: float = 54.0 * _letterbox_weight
	if _letterbox_top != null:
		_letterbox_top.offset_bottom = bar_h
	if _letterbox_bot != null:
		_letterbox_bot.offset_top = -bar_h

	if active_flashback == FlashbackMode.STAGE and _stage_camera != null:
		_stage_elapsed += real_delta
		var push: float = clampf(_stage_elapsed / 8.0, 0.0, 1.0)
		var pos: Vector3 = Vector3(-2.8, 1.9, 4.0).lerp(Vector3(-1.8, 1.55, 2.5), push)
		_stage_camera.look_at_from_position(pos, Vector3(0.0, 1.22, -0.8))

	if trailer_playing:
		_process_trailer(real_delta)
		return

	if director_active:
		_process_director(real_delta)
		return

	if _cam_t < 1.0:
		_cam_t = minf(1.0, _cam_t + real_delta / maxf(0.01, _cam_dur))
		var w: float = _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		_camera.global_transform = _cam_from.interpolate_with(_cam_to, w)
		_camera.fov = lerpf(_cam_fov_from, _cam_fov_to, w)
		_cam_attrs.dof_blur_far_distance = lerpf(_cam_dof_from, _cam_dof_to, w)


func _process_trailer(real_delta: float) -> void:
	_trailer_time += real_delta
	if _trailer_time < 3.5:
		if _trailer_shot != 0:
			_apply_trailer_shot(0)
		if _trailer_cue < 1 and _trailer_time >= 0.12:
			_trailer_cue = 1
			_fire_actor(_tr_smith, &"ability.40008")
			_fire_actor(_tr_hero, &"item.draw")
		if _trailer_cue < 2 and _trailer_time >= 0.65:
			_trailer_cue = 2
			_tr_sparks.position = _tr_anvil.position + Vector3(0.0, 0.88, 0.0)
			_tr_sparks.emitting = true
		if _trailer_cue < 3 and _trailer_time >= 1.55:
			_trailer_cue = 3
			_tr_sparks.emitting = false
			_set_actor_mark(_tr_hero, Vector3(2.2, 0.0, 14.8), Vector3(14.0, 0.0, 5.9), 1.85, 0.25)
		var u: float = _trailer_time / 3.5
		var pos: Vector3 = Vector3(-3.6, 1.25, 18.8).lerp(Vector3(0.4, 1.45, 18.0), u)
		_camera.look_at_from_position(pos, Vector3(-1.3, 1.05, 16.7))
		_camera.fov = 36.0
	elif _trailer_time < 7.8:
		if _trailer_shot != 1:
			_apply_trailer_shot(1)
		if _trailer_cue < 10 and _trailer_time >= 3.65:
			_trailer_cue = 10
			_fire_actor(_tr_hero, &"ability.40003")
			_fire_actor(_tr_warrior, &"ability.40017")
		if _trailer_cue < 11 and _trailer_time >= 5.10:
			_trailer_cue = 11
			_tr_sparks.position = Vector3(14.35, 1.15, 5.85)
			_tr_sparks.emitting = true
			_fire_actor(_tr_warrior, &"react.stagger")
			_set_actor_mark(_tr_warrior, Vector3(15.6, 0.0, 5.45), _tr_hero.position, 2.2, 0.25)
			_fire_actor(_tr_archer, &"ability.40011")
		if _trailer_cue < 12 and _trailer_time >= 6.45:
			_trailer_cue = 12
			_tr_sparks.emitting = false
			_fire_actor(_tr_hero, &"ability.40023")
		var u: float = (_trailer_time - 3.5) / 4.3
		var angle: float = lerpf(-0.55, 0.65, u)
		var center: Vector3 = Vector3(14.35, 1.25, 5.85)
		var pos: Vector3 = center + Vector3(sin(angle) * 3.8, 0.45, cos(angle) * 3.8)
		_camera.look_at_from_position(pos, center)
		_camera.fov = lerpf(32.0, 26.0, u)
	elif _trailer_time < 12.0:
		if _trailer_shot != 2:
			_apply_trailer_shot(2)
		var u: float = (_trailer_time - 7.8) / 4.2
		var e: float = 1.0 - pow(1.0 - u, 2.0)
		var pos: Vector3 = Vector3(-5.0, 2.4, 18.0).lerp(Vector3(-15.0, 10.5, 25.0), e)
		_camera.look_at_from_position(pos, Vector3(3.0, 1.0, 8.0))
		_camera.fov = lerpf(42.0, 54.0, e)
	else:
		_trailer_time = 0.0
		_trailer_shot = -1
		_trailer_cue = 0


func _apply_trailer_shot(shot: int) -> void:
	_trailer_shot = shot
	_title_overlay.visible = true
	if shot == 0:
		Engine.time_scale = 1.0
		_trailer_cue = 0
		_tr_sparks.emitting = false
		_tr_hero.position = Vector3(-0.3, 0.0, 16.8)
		_set_actor_mark(_tr_hero, _tr_hero.position, _tr_smith.position, 0.0)
		_face_toward(_tr_smith, _tr_anvil.position)
		_face_toward(_tr_hero, _tr_smith.position)
		_clear_pose(_tr_smith)
		_clear_pose(_tr_hero)
		_title_main.text = ""
		_title_sub.text = "SHOT 1/3 — FORGE & CALL TO ARMS"
	elif shot == 1:
		Engine.time_scale = 0.28
		_trailer_cue = 9
		_tr_sparks.emitting = false
		_tr_hero.position = Vector3(12.8, 0.0, 6.2)
		_tr_warrior.position = Vector3(15.9, 0.0, 5.4)
		_tr_archer.position = Vector3(18.0, 0.0, 3.4)
		_set_actor_mark(_tr_hero, Vector3(13.95, 0.0, 5.95), _tr_warrior.position, 3.4, 0.72)
		_set_actor_mark(_tr_warrior, Vector3(14.75, 0.0, 5.75), _tr_hero.position, 3.2, 0.72)
		_set_actor_mark(_tr_archer, _tr_archer.position, _tr_hero.position, 0.0)
		_face_toward(_tr_hero, _tr_warrior.position)
		_face_toward(_tr_warrior, _tr_hero.position)
		_face_toward(_tr_archer, _tr_hero.position)
		_fire_actor(_tr_archer, &"pose.bow_aim")
		_title_main.text = ""
		_title_sub.text = "SHOT 2/3 — 0.28x SLOW-MOTION CLASH"
	else:
		Engine.time_scale = 1.0
		_trailer_cue = 20
		_tr_sparks.emitting = false
		_tr_hero.position = Vector3(0.0, 0.0, 11.4)
		_set_actor_mark(_tr_hero, Vector3(5.2, 0.0, 7.6), Vector3(8.0, 0.0, 6.0), 1.8, 0.28)
		_face_toward(_tr_hero, Vector3(5.2, 0.0, 7.6))
		_clear_pose(_tr_hero)
		_clear_pose(_tr_archer)
		_title_main.text = "REGENT'S RULE"
		_title_sub.text = "SHOT 3/3 — FRONTIER CRANE REVEAL"


func _process_director(real_delta: float) -> void:
	if _dolly_playing and _dolly_curve.point_count >= 2:
		_dolly_t += real_delta / maxf(0.5, _dolly_duration)
		if _dolly_t >= 1.0:
			_dolly_t = 0.0
		var total_len: float = _dolly_curve.get_baked_length()
		var pos: Vector3 = _dolly_curve.sample_baked(_dolly_t * total_len, true)
		var seg_f: float = _dolly_t * float(_dolly_yaws.size() - 1)
		var i0: int = mini(int(seg_f), _dolly_yaws.size() - 1)
		var i1: int = mini(i0 + 1, _dolly_yaws.size() - 1)
		var frac: float = seg_f - float(i0)
		_camera.global_position = pos
		_camera.rotation = Vector3(
			lerp_angle(_dolly_pitches[i0], _dolly_pitches[i1], frac),
			lerp_angle(_dolly_yaws[i0], _dolly_yaws[i1], frac),
			0.0
		)
		_camera.fov = lerpf(_dolly_fovs[i0], _dolly_fovs[i1], frac)
		_update_director_text()
		return

	var fwd: Vector3 = -_camera.global_transform.basis.z
	var right: Vector3 = _camera.global_transform.basis.x
	var move: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += fwd
	if Input.is_key_pressed(KEY_S):
		move -= fwd
	if Input.is_key_pressed(KEY_D):
		move += right
	if Input.is_key_pressed(KEY_A):
		move -= right
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move.length_squared() > 0.001:
		var speed: float = 12.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0
		_camera.global_position += move.normalized() * speed * real_delta
	_camera.rotation = Vector3(_dir_pitch, _dir_yaw, 0.0)
	_camera.fov = lerpf(_camera.fov, _dir_fov, minf(1.0, real_delta * 10.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_H:
			toggle_ui_visibility()
			get_viewport().set_input_as_handled()
			return
	if not director_active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dir_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dir_fov = clampf(_dir_fov - 3.0, 20.0, 85.0)
			_update_director_text()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dir_fov = clampf(_dir_fov + 3.0, 20.0, 85.0)
			_update_director_text()
	elif event is InputEventMouseMotion and _dir_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_dir_yaw = wrapf(_dir_yaw - mm.relative.x * 0.003, -PI, PI)
		_dir_pitch = clampf(_dir_pitch - mm.relative.y * 0.003, -1.45, 1.45)
	elif event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_BRACKETLEFT:
			Engine.time_scale = clampf(Engine.time_scale - 0.15, 0.1, 2.0)
			_update_director_text()
		elif k.keycode == KEY_BRACKETRIGHT:
			Engine.time_scale = clampf(Engine.time_scale + 0.15, 0.1, 2.0)
			_update_director_text()
		elif k.keycode == KEY_K:
			add_dolly_keyframe()
		elif k.keycode == KEY_P:
			if _dolly_playing:
				stop_dolly()
			else:
				play_dolly()
		elif k.keycode == KEY_C:
			clear_dolly()


# --- Helpers -------------------------------------------------------------------------

func _toggle_voice() -> void:
	voice_enabled = not voice_enabled
	if _voice_btn != null:
		_voice_btn.text = "VO: On" if voice_enabled else "VO: Off"
	if not voice_enabled and _voice_player != null:
		_voice_player.stop()


func _update_director_text() -> void:
	if _director_info == null:
		return
	var state_str: String = "DOLLY PLAYING" if _dolly_playing else "FREE-CAM"
	_director_info.text = "DIRECTOR %s   |   FOV: %.0f deg   |   Speed: %.2fx   |   Dolly Keyframes: %d\nWASD/QE: Move (Shift fast)   RMB: Look   Wheel: FOV   [ / ]: Time Scale\nK: Add Keyframe   P: Play/Stop Dolly   C: Clear   H: Toggle UI (--write-movie ready)" % [
		state_str, _dir_fov, Engine.time_scale, _dolly_curve.point_count]


func _spawn_mannequin(parent: Node3D, node_name: String, def: EntityDefinition, look_idx: int, pos: Vector3,
		weapon_scene: PackedScene = null, foe_def: FoeDef = null) -> Mannequin:
	var m: Mannequin = Mannequin.new()
	m.name = node_name
	m.position = pos
	m.look = look_idx
	m.definition = def
	parent.add_child(m)
	var tree_info: Dictionary = _upgrade_mannequin_tree(m)
	var held: HeldItem = null
	if foe_def != null and m.skeleton != null:
		held = _apply_foe_look(m.skeleton, foe_def)
	elif weapon_scene != null and m.skeleton != null:
		held = HeldItem.attach(m.skeleton, weapon_scene)
	if held != null:
		held.set_animation_weights({&"locomotion.idle": 1.0})
	_actor_rigs[m] = {
		"tree": tree_info.get("tree", null),
		"blend": tree_info.get("blend", null),
		"set": def.animation_set if def != null else null,
		"strafing": AnimationTreeBuilder.is_strafing(def.animation_set) if def != null else false,
		"held": held,
		"action_slot": 0,
		"pose": &"",
		"target_pos": pos,
		"look_target": pos + Vector3(0.0, 0.0, -1.0),
		"move_speed": 0.0,
		"move_blend": 0.0,
		"cur_blend": 0.0,
		"held_timer": 0.0,
	}
	return m


static func _upgrade_mannequin_tree(m: Mannequin) -> Dictionary:
	if m == null or m.model == null or m.skeleton == null or m.definition == null or m.definition.animation_set == null:
		return {}
	var old_tree: AnimationTree = m._tree
	if old_tree != null:
		old_tree.active = false
		if old_tree.get_parent() != null:
			old_tree.get_parent().remove_child(old_tree)
		old_tree.free()
		m._tree = null
	var aset: AnimationSet = m.definition.animation_set
	var full_tree: AnimationTree = AnimationTreeBuilder.build(aset)
	if full_tree == null:
		return {}
	m.model.add_child(full_tree)
	full_tree.root_node = full_tree.get_path_to(m.skeleton.get_parent())
	full_tree.active = true
	m._tree = full_tree
	var init_blend: Variant = Vector2.ZERO if AnimationTreeBuilder.is_strafing(aset) else 0.0
	full_tree.set(AnimationTreeBuilder.P_BLEND, init_blend)
	return {"tree": full_tree, "blend": full_tree.tree_root as AnimationNodeBlendTree}


static func _apply_foe_look(skel: Skeleton3D, foe: FoeDef) -> HeldItem:
	for n: Node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if foe.hidden_meshes.has(StringName(mi.name)):
			mi.visible = false
			continue
		if foe.albedo == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var base: BaseMaterial3D = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat: BaseMaterial3D = base.duplicate() as BaseMaterial3D
			mat.albedo_texture = foe.albedo
			mi.set_surface_override_material(i, mat)
	if foe.held_scene != null:
		return HeldItem.attach(skel, foe.held_scene)
	return null


func _reset_present_cast() -> void:
	_drillmaster.position = Vector3(1.15, 0.0, 9.6)
	_chronicler.position = Vector3(-0.95, 0.0, 9.8)
	_adventurer.position = Vector3(0.0, 0.0, 13.4)
	var dest: Vector3 = Vector3(0.0, 0.0, 11.5)
	_set_actor_mark(_drillmaster, _drillmaster.position, dest, 0.0)
	_set_actor_mark(_chronicler, _chronicler.position, dest, 0.0)
	_set_actor_mark(_adventurer, dest, Vector3(0.0, 0.0, 9.7), 1.65, 0.25)
	_face_toward(_drillmaster, dest)
	_face_toward(_chronicler, dest)
	_face_toward(_adventurer, Vector3(0.0, 0.0, 9.7))


func _set_actor_mark(m: Mannequin, target_pos: Vector3, look_target: Vector3, move_speed: float, move_blend: float = 0.25) -> void:
	if m == null or not _actor_rigs.has(m):
		return
	var rig: Dictionary = _actor_rigs[m] as Dictionary
	rig["target_pos"] = target_pos
	rig["look_target"] = look_target
	rig["move_speed"] = move_speed
	rig["move_blend"] = move_blend


func _set_actor_look(m: Mannequin, look_target: Vector3) -> void:
	if m == null or not _actor_rigs.has(m):
		return
	var rig: Dictionary = _actor_rigs[m] as Dictionary
	rig["look_target"] = look_target


func _actor_mark_pos(m: Mannequin) -> Vector3:
	if m == null:
		return Vector3.ZERO
	if _actor_rigs.has(m):
		var rig: Dictionary = _actor_rigs[m] as Dictionary
		return rig.get("target_pos", m.position) as Vector3
	return m.position


func _update_actors(game_delta: float, real_delta: float) -> void:
	for key_v: Variant in _actor_rigs:
		var m: Mannequin = key_v as Mannequin
		if m == null or not is_instance_valid(m) or not m.is_visible_in_tree():
			continue
		var rig: Dictionary = _actor_rigs[key_v] as Dictionary
		var target_pos: Vector3 = rig.get("target_pos", m.position) as Vector3
		var look_target: Vector3 = rig.get("look_target", target_pos) as Vector3
		var move_speed: float = float(rig.get("move_speed", 0.0))
		var move_blend: float = float(rig.get("move_blend", 0.25))
		var diff: Vector3 = target_pos - m.position
		diff.y = 0.0
		var moving: bool = move_speed > 0.01 and diff.length() > 0.03
		if moving:
			m.position = m.position.move_toward(target_pos, move_speed * game_delta)
			var move_yaw: float = _yaw_toward(diff)
			m.rotation.y = lerp_angle(m.rotation.y, move_yaw, minf(1.0, real_delta * 10.0))
		else:
			var look_d: Vector3 = look_target - m.position
			if Vector2(look_d.x, look_d.z).length_squared() > 0.0001:
				m.rotation.y = lerp_angle(m.rotation.y, _yaw_toward(look_d), minf(1.0, real_delta * 8.0))
		var want_blend: float = move_blend if moving else 0.0
		var cur_blend: float = move_toward(float(rig.get("cur_blend", 0.0)), want_blend, real_delta * 6.0)
		rig["cur_blend"] = cur_blend
		var tree: AnimationTree = rig.get("tree", null) as AnimationTree
		if tree != null:
			var val: Variant = Vector2(0.0, cur_blend) if bool(rig.get("strafing", false)) else cur_blend
			tree.set(AnimationTreeBuilder.P_BLEND, val)
		var held: HeldItem = rig.get("held", null) as HeldItem
		var h_timer: float = float(rig.get("held_timer", 0.0))
		if h_timer > 0.0:
			h_timer = maxf(0.0, h_timer - game_delta)
			rig["held_timer"] = h_timer
			if h_timer <= 0.0 and held != null and StringName(rig.get("pose", &"")) == &"":
				var base_sem: StringName = AnimationSet.RUN if move_blend >= 0.5 and moving else (AnimationSet.WALK if moving else AnimationSet.IDLE)
				held.set_animation_weights({base_sem: 1.0})
		elif held != null and StringName(rig.get("pose", &"")) == &"":
			var base_sem: StringName = AnimationSet.RUN if move_blend >= 0.5 and moving else (AnimationSet.WALK if moving else AnimationSet.IDLE)
			held.set_animation_weights({base_sem: 1.0})


func _clear_pose(m: Mannequin) -> void:
	if m == null or not _actor_rigs.has(m):
		return
	var rig: Dictionary = _actor_rigs[m] as Dictionary
	var tree: AnimationTree = rig.get("tree", null) as AnimationTree
	if tree != null:
		tree.set(AnimationTreeBuilder.P_POSE_BLEND, 0.0)
	rig["pose"] = &""


func _fire_actor(m: Mannequin, semantic: StringName) -> void:
	if m == null or not _actor_rigs.has(m):
		return
	var rig: Dictionary = _actor_rigs[m] as Dictionary
	var tree: AnimationTree = rig.get("tree", null) as AnimationTree
	var blend_root: AnimationNodeBlendTree = rig.get("blend", null) as AnimationNodeBlendTree
	var aset: AnimationSet = rig.get("set", null) as AnimationSet
	var held: HeldItem = rig.get("held", null) as HeldItem
	if tree == null or blend_root == null or aset == null:
		return
	if semantic == &"" or semantic == AnimationSet.IDLE:
		_clear_pose(m)
		return
	if aset.clip(semantic) == null:
		return
	var s: String = String(semantic)
	if s.begins_with("pose."):
		var pose_node: AnimationNodeAnimation = blend_root.get_node(AnimationTreeBuilder.NODE_POSE_CLIP) as AnimationNodeAnimation
		if AnimationTreeBuilder.apply_clip(pose_node, aset, semantic, true):
			tree.set(AnimationTreeBuilder.P_POSE_SCALE, 1.0)
			tree.set(AnimationTreeBuilder.P_POSE_BLEND, 1.0)
			rig["pose"] = semantic
			if held != null:
				held.set_animation_weights({semantic: 1.0})
		return
	_clear_pose(m)
	var clip_len: float = maxf(0.45, AnimationTreeBuilder.clip_length(aset, semantic))
	if s.begins_with("react."):
		var hit_node: AnimationNodeAnimation = blend_root.get_node(AnimationTreeBuilder.NODE_HIT_CLIP) as AnimationNodeAnimation
		if AnimationTreeBuilder.apply_clip(hit_node, aset, semantic, false):
			tree.set(AnimationTreeBuilder.P_HIT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif semantic == AnimationSet.INTERACT or semantic == &"item.draw" or semantic == &"item.stow":
		var up_node: AnimationNodeAnimation = blend_root.get_node(AnimationTreeBuilder.NODE_UPPER_CLIP) as AnimationNodeAnimation
		if AnimationTreeBuilder.apply_clip(up_node, aset, semantic, false):
			tree.set(AnimationTreeBuilder.P_UPPER_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		var slot: int = int(rig.get("action_slot", 0))
		var active_req: String = AnimationTreeBuilder.P_ACTION2_REQUEST if slot == 1 else AnimationTreeBuilder.P_ACTION_REQUEST
		var active_flag: String = AnimationTreeBuilder.P_ACTION2_ACTIVE if slot == 1 else AnimationTreeBuilder.P_ACTION_ACTIVE
		if bool(tree.get(active_flag)):
			tree.set(active_req, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
			slot = 1 - slot
		rig["action_slot"] = slot
		var clip_node_name: StringName = AnimationTreeBuilder.NODE_ACTION2_CLIP if slot == 1 else AnimationTreeBuilder.NODE_ACTION_CLIP
		var req_param: String = AnimationTreeBuilder.P_ACTION2_REQUEST if slot == 1 else AnimationTreeBuilder.P_ACTION_REQUEST
		var act_node: AnimationNodeAnimation = blend_root.get_node(clip_node_name) as AnimationNodeAnimation
		if AnimationTreeBuilder.apply_clip(act_node, aset, semantic, false):
			tree.set(req_param, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if held != null:
		held.set_animation_weights({semantic: 1.0})
		rig["held_timer"] = clip_len


func _trigger_flashback_impact() -> void:
	if active_flashback == FlashbackMode.STAGE:
		if _fb_impact_outcome == "shield_wall":
			_fire_actor(_stage_foe, &"react.stagger")
			_set_actor_mark(_stage_foe, Vector3(0.25, 0.0, -3.2), _stage_hero.position, 2.2, 0.25)
		else:
			_fire_actor(_stage_foe, &"react.hit")
	elif active_flashback == FlashbackMode.ECHO:
		if _fb_impact_outcome == "shield_wall":
			_fire_actor(_echo_imp, &"react.stagger")
			_set_actor_mark(_echo_imp, Vector3(4.5, 0.0, 9.7), _echo_captain.position, 2.2, 0.25)
		else:
			_fire_actor(_echo_imp, &"react.hit")
			_fire_actor(_echo_archer, &"react.hit")


static func _yaw_toward(d: Vector3) -> float:
	# Mannequin aligns each model's visual forward to -Z (`visual_yaw_deg = 180`), so -Z tracks target.
	return atan2(-d.x, -d.z)


static func _face_toward(actor: Node3D, target: Vector3) -> void:
	if actor == null:
		return
	var d: Vector3 = target - actor.position
	if Vector2(d.x, d.z).length_squared() > 0.0001:
		actor.rotation.y = _yaw_toward(d)
