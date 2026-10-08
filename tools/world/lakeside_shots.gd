extends Node3D
## Renders the lakeside from fixed viewpoints to PNGs, to look at a change without playing it.
##
##   godot --path . --resolution 1600x900 res://tools/world/lakeside_shots.tscn -- --out=<dir> [--only=<name>]
##   ... -- --out=<dir> --shot=<name>:<eye x,y,z>:<target x,y,z>[:<fov>]   (any number; ad hoc views)
##   ... -- --angler=<x,z>:<tx,tz>   an angler at (x, z) with a line out to (tx, tz), for the line
##
## Needs a window (it reads the framebuffer), so not `--headless`. Each shot waits for the
## terrain and its foliage to settle around the camera before it is taken: Terrain3D builds the
## instancer's cells and the clipmap for wherever the camera IS, a few frames after it gets there.

const LEVEL: String = "res://game/world/lakeside.tscn"
const SETTLE_FRAMES: int = 50

## [name, eye, target, fov]
const SHOTS: Array[Array] = [
	["overview", Vector3(-64.0, 44.0, 172.0), Vector3(4.0, 0.0, 16.0), 60.0],
	["spawn", Vector3(0.0, 3.9, 80.0), Vector3(0.0, 1.0, 20.0), 70.0],
	["dock_end", Vector3(0.0, 2.6, 26.0), Vector3(-6.0, 0.0, -40.0), 70.0],
	["village_from_dock", Vector3(-3.0, 2.8, 32.0), Vector3(0.0, 5.0, 100.0), 70.0],
	["reed_bay", Vector3(-86.0, 7.0, 52.0), Vector3(-118.0, 0.0, 12.0), 70.0],
	["rocky_point", Vector3(74.0, 3.8, -42.0), Vector3(36.0, 0.0, -50.0), 70.0],
	["north_shore", Vector3(-10.0, 3.0, -108.0), Vector3(0.0, 2.0, 40.0), 70.0],
	["square", Vector3(18.0, 4.5, 108.0), Vector3(-6.0, 2.0, 88.0), 70.0],
	["aerial", Vector3(0.0, 240.0, 150.0), Vector3(0.0, 0.0, -10.0), 60.0],
]


func _ready() -> void:
	var out: String = "user://lakeside_shots"
	var only: String = ""
	var shots: Array[Array] = SHOTS.duplicate()
	var custom: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg.begins_with("--shot="):
			var parts: PackedStringArray = arg.substr(7).split(":")
			var eye: PackedFloat64Array = parts[1].split_floats(",")
			var at: PackedFloat64Array = parts[2].split_floats(",")
			shots.append([parts[0], Vector3(eye[0], eye[1], eye[2]), Vector3(at[0], at[1], at[2]),
				float(parts[3]) if parts.size() > 3 else 70.0])
			custom.append(parts[0])
	if not custom.is_empty() and only.is_empty():
		only = ",".join(custom)
	# Rendering experiments without editing the project (A/B a lighting change on the same views):
	#   --taa  --msaa=<0..3>  --normal-bias=<m>  --shadow-bias=<m>  --blur=<x>  --filter=<0..5>
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--taa":
			get_viewport().use_taa = true
		elif arg.begins_with("--msaa="):
			get_viewport().msaa_3d = int(arg.substr(7)) as Viewport.MSAA
		elif arg.begins_with("--filter="):
			RenderingServer.directional_soft_shadow_filter_set_quality(
				int(arg.substr(9)) as RenderingServer.ShadowQuality)
	DirAccess.make_dir_recursive_absolute(out)
	var level: Node3D = (load(LEVEL) as PackedScene).instantiate() as Node3D
	add_child(level)
	# --lineup: every angler look standing along the dock's head, idling, for a look at the
	# characters in the level's own light (tools/characters/, DECISIONS #139).
	if OS.get_cmdline_user_args().has("--lineup"):
		_lineup(level)
	# --angler=<x>,<z>:<tx>,<tz>: an angler standing at (x, z), idling, with a line out to (tx, tz)
	# on the water — the line and the float at a real distance in the level's own light.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--angler="):
			_angler(level as LakesideLevel, arg.substr(9))
	var sun: DirectionalLight3D = level.get_node_or_null(^"Sun") as DirectionalLight3D
	for arg: String in OS.get_cmdline_user_args():
		if sun != null and arg.begins_with("--normal-bias="):
			sun.shadow_normal_bias = float(arg.substr(14))
		elif sun != null and arg.begins_with("--shadow-bias="):
			sun.shadow_bias = float(arg.substr(14))
		elif sun != null and arg.begins_with("--blur="):
			sun.shadow_blur = float(arg.substr(7))
	var cam := Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	for shot: Array in shots:
		if not only.is_empty() and not only.split(",").has(str(shot[0])):
			continue
		cam.fov = float(shot[3])
		cam.look_at_from_position(shot[1] as Vector3, shot[2] as Vector3)
		for i: int in range(SETTLE_FRAMES):
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = out.path_join(str(shot[0]) + ".png")
		img.save_png(path)
		print("lakeside_shots: %s" % path)
	get_tree().quit()


func _lineup(level: Node3D) -> void:
	var defn: EntityDefinition = load("res://game/fishing/fisher_definition.tres") as EntityDefinition
	var looks: Array[PackedScene] = defn.visual_variants.duplicate()
	looks.append((load("res://game/fishing/rival_definition.tres") as EntityDefinition).visual_for(0))
	for i: int in range(looks.size()):
		var model: Node3D = looks[i].instantiate() as Node3D
		level.add_child(model)
		model.position = Vector3(-4.0 + 8.0 * float(i) / float(looks.size() - 1), 0.9, 25.0)
		# Facing the camera, which stands on the pier looking north at them.
		model.rotation.y = deg_to_rad(defn.visual_yaw_deg + 180.0)
		_idle(model, defn.animation_set)


func _angler(level: LakesideLevel, spec: String) -> void:
	var ends: PackedStringArray = spec.split(":")
	var at: PackedFloat64Array = ends[0].split_floats(",")
	var to: PackedFloat64Array = ends[1].split_floats(",")
	var defn: EntityDefinition = load("res://game/fishing/fisher_definition.tres") as EntityDefinition
	var body := Node3D.new()
	level.add_child(body)
	for i: int in range(2):
		await get_tree().physics_frame
	# The world's collision, not the terrain's height: the dock's deck is not terrain.
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at[0] + 0.137, 60.0, at[1] + 0.071),
		Vector3(at[0] + 0.137, -40.0, at[1] + 0.071), SpaceTimeEntity.WORLD_MASK)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
	var ground: float = (hit["position"] as Vector3).y if not hit.is_empty() else level.ground_height(Vector3(at[0], 0.0, at[1]))
	body.global_position = Vector3(at[0], maxf(ground, level.water_y()), at[1])
	body.look_at(Vector3(to[0], body.global_position.y, to[1]), Vector3.UP)
	var model: Node3D = defn.visual_for(0).instantiate() as Node3D
	body.add_child(model)
	model.rotation.y = deg_to_rad(defn.visual_yaw_deg)
	var skel: Skeleton3D = _idle(model, defn.animation_set)
	var fx := FishingFx.new()
	body.add_child(fx)
	fx.hold_rod(skel)
	fx.place_at(Vector3(to[0], level.water_y(), to[1]))


## Loops `model` in its idle clip; returns its skeleton, or null.
static func _idle(model: Node3D, set: AnimationSet) -> Skeleton3D:
	var skel: Skeleton3D = null
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
	if skel == null or set == null:
		return skel
	var tree := AnimationTree.new()
	for lib_name: StringName in set.libraries:
		tree.add_animation_library(lib_name, set.libraries[lib_name])
	var node := AnimationNodeAnimation.new()
	AnimationTreeBuilder.apply_clip(node, set, AnimationSet.IDLE)
	node.use_custom_timeline = true
	node.loop_mode = Animation.LOOP_LINEAR
	tree.tree_root = node
	model.add_child(tree)
	tree.root_node = tree.get_path_to(skel.get_parent())
	tree.active = true
	return skel
