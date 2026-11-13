extends Node3D
## THE GLADE'S LOOK, SHOT (PROGRESS step 59; windowed, no server): the frontier glade as a player's camera sees it,
## from the same few places every time, so a change to its light, ground, foliage or grass is compared picture to
## picture. Its gathering nodes are drawn with their content's own models (in the game an entity draws them), its
## stations as plain blocks, and a gray post a person's height stands 4.5 m in front of each camera for scale.
## Writes `<out>/<view>.png`.
##   godot --path . res://game/regents/tests/glade_shot.tscn -- <out dir> [res://a/level.tscn]

const NODE_DIR: String = "res://game/regents/content/node/"
## [name, the eye, what it looks at]
const VIEWS: Array[Array] = [
	["camp", Vector3(2.0, 2.6, 6.5), Vector3(2.0, 1.0, 16.0)],
	["woods", Vector3(-3.0, 2.4, -1.0), Vector3(-10.0, 1.5, -7.0)],
	["meadow", Vector3(-6.0, 2.4, 9.0), Vector3(-13.0, 0.8, 3.0)],
	["rock", Vector3(-4.5, 2.2, 8.5), Vector3(-9.5, 1.2, 12.1)],
	["east", Vector3(14.0, 2.6, 6.0), Vector3(33.0, 1.0, -1.0)],
	["wide", Vector3(22.0, 9.0, 34.0), Vector3(0.0, 0.0, 10.0)],
]
const SETTLE_FRAMES: int = 24

var out_dir: String = "user://"
var level_path: String = "res://game/regents/levels/frontier.tscn"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		level_path = args[1]
	get_window().size = Vector2i(1280, 720)
	var level: Node3D = (load(level_path) as PackedScene).instantiate() as Node3D
	add_child(level)
	_draw_points(level)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	var post := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	post.mesh = capsule
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.62, 0.6, 0.58)
	post.material_override = gray
	add_child(post)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for view: Array in VIEWS:
		var eye: Vector3 = view[1]
		var at: Vector3 = view[2]
		cam.position = eye
		cam.look_at(at)
		var ahead: Vector3 = Vector3(at.x - eye.x, 0.0, at.z - eye.z).normalized() * 4.5
		post.position = Vector3(eye.x + ahead.x, 0.9, eye.z + ahead.z)
		for _i: int in range(SETTLE_FRAMES):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file: String = out_dir.path_join(String(view[0]) + ".png")
		get_viewport().get_texture().get_image().save_png(file)
		print("[shot] %s" % file)
	AppExit.quit(get_tree(), 0)


## Every gathering node's model where its point is, every station a block.
func _draw_points(level: Node3D) -> void:
	var defs: Dictionary[String, NodeDef] = {}
	for file: String in DirAccess.get_files_at(NODE_DIR):
		if file.ends_with(".tres"):
			var def: NodeDef = load(NODE_DIR + file) as NodeDef
			if def != null:
				defs[def.display_name] = def
	var n: int = 0
	for found: Node in level.find_children("*", "Marker3D", true, false):
		var point: LevelPoint = found as LevelPoint
		if point == null:
			continue
		n += 1
		if point.kind == "station":
			var block := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.2, 1.0, 0.8)
			block.mesh = box
			block.position = point.global_position + Vector3(0.0, 0.5, 0.0)
			add_child(block)
		elif point.kind == "node" and not point.tags.is_empty() and defs.has(point.tags[0]):
			var def: NodeDef = defs[point.tags[0]]
			if def.models.is_empty():
				continue
			var model: Node3D = def.models[n % def.models.size()].instantiate() as Node3D
			add_child(model)
			var s: float = def.model_scale
			model.global_transform = Transform3D(Basis(Vector3.UP, float(n) * 2.4).scaled(Vector3(s, s, s)), point.global_position)
