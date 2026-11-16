extends Node3D
## PLAYERS IN THEIR OWN COLORS, SHOT (W1; windowed, no server):
##   "$GODOT" --path . res://game/regents/tests/figure_shot.tscn -- <out dir>
## Saves `figures.png` (four players side by side: the Peasant as painted from an old text, then three in colors of
## their own, one in a Knight's torso over them, as W2 will wear armor) and `picker.png` (the character picker on the
## adventurer: Peasant looks only, hair, beard, brows and skin), then quits.

const LOOKS: Array[Array] = [
	["res://game/regents/looks/peasant_m.tscn", "peasant_m;hair=3"],
	["res://game/regents/looks/peasant_f.tscn", "peasant_f;hair=6"],
	["res://game/regents/looks/peasant_m.tscn", "peasant_m;beard=2;skin=4"],
	["res://game/regents/looks/peasant_m.tscn", "peasant_m;hair=2"],
]


func _ready() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://figure_shot"
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.4, 0.25)
	ground.material_override = gm
	add_child(ground)
	var colors: Array[Dictionary] = [
		{},
		{&"main": Color8(74, 106, 142), &"accent": Color8(74, 74, 78), &"trim": Color8(176, 168, 136)},
		{&"main": Color8(140, 40, 36), &"accent": Color8(220, 190, 120), &"under": Color8(40, 30, 28), &"leather": Color8(60, 40, 30)},
		{&"main": Color8(60, 110, 60), &"trim": Color8(200, 180, 60)},
	]
	var figures: Array[RegentsFigure] = []
	for i: int in LOOKS.size():
		var f: RegentsFigure = (load(String(LOOKS[i][0])) as PackedScene).instantiate() as RegentsFigure
		f.apply_appearance(RegentsColors.with_colors(String(LOOKS[i][1]), colors[i]))
		f.position = Vector3((float(i) - 1.5) * 1.3, 0, 0)
		f.rotation.y = 0.0
		add_child(f)
		figures.append(f)
	figures[3].wear_armor({&"torso": load("res://game/regents/art/outfits/knight/models/Male_Knight_Body_Armor.gltf") as PackedScene},
		{"Knight": load("res://game/regents/wardrobe/palettes/knight_1.tres") as DyePalette})
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 4.6)
	cam.fov = 45.0
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("figures.png"))
	print("saved ", dir.path_join("figures.png"))
	for f: RegentsFigure in figures:
		f.visible = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var picker := CharacterPicker.new()
	picker.definition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	picker.appearance = RegentsColors.with_colors("peasant_f;hair=6", colors[1])
	layer.add_child(picker)
	picker.open()
	for i: int in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("picker.png"))
	print("saved ", dir.path_join("picker.png"), " look: ", picker.current())
	AppExit.quit(get_tree(), 0)
