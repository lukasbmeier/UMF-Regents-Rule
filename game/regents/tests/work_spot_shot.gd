extends Node3D
## THE WORK SPOT, SHOWN (PROGRESS step 44; windowed, no server): a character pressed against a big rock and a big
## tree (and standing too far from them, as near the server's 3 m as allowed), swinging the real tool in the world's
## clip, shot at the swing's deepest frame where it stopped walking ("off"), then stepped back by `WorkSpot.step_back`
## with the adventurer's own `swing_reach_m` ("on"). Writes `<out>/<case>_off.png`, `_on.png` and prints the gap
## between the tool and the node's drawn surface (negative: inside it).
##   godot --path . res://game/regents/tests/work_spot_shot.tscn -- <out dir>

## [node def id, entity id (picks its model), tool, clip, the skill's pose, name, meters farther than touching]
const CASES: Array = [
	[40005, 2, "res://game/regents/skilling/mining/pickaxe.tscn", &"extra/Mining", &"pose.mine", "rock", 0.0],
	[40004, 1, "res://game/regents/skilling/mining/pickaxe.tscn", &"extra/Mining", &"pose.mine", "copper", 0.0],
	[40002, 2, "res://game/regents/skilling/woodcutting/axe.tscn", &"extra/TreeChopping", &"pose.chop", "oak", 0.0],
	[40003, 1, "res://game/regents/skilling/woodcutting/axe.tscn", &"extra/TreeChopping", &"pose.chop", "yew", 0.0],
	[40001, 1, "res://game/regents/skilling/woodcutting/axe.tscn", &"extra/TreeChopping", &"pose.chop", "tree", 0.0],
	[40004, 1, "res://game/regents/skilling/mining/pickaxe.tscn", &"extra/Mining", &"pose.mine", "copper_far", 1.5],
	[40003, 1, "res://game/regents/skilling/woodcutting/axe.tscn", &"extra/TreeChopping", &"pose.chop", "yew_far", 2.5],
]
## The server's reach from the node's center (`regents.work_reach_m`): no case stands farther.
const WORK_REACH_M: float = 3.0
const CAPSULE_R: float = 0.4

var out_dir: String = "user://"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	get_window().size = Vector2i(960, 720)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.55, 0.25)
	ground.material_override = gm
	add_child(ground)
	for c: Array in CASES:
		await _case(c)
	AppExit.quit(get_tree(), 0)


func _case(c: Array) -> void:
	# The node, as the world draws it.
	var node_ent := Node3D.new()
	var comps := Node.new()
	comps.name = "Components"
	node_ent.add_child(comps)
	var vis := Node3D.new()
	vis.name = "Visual"
	node_ent.add_child(vis)
	add_child(node_ent)
	var nc := NodeComponent.new()
	nc.entity_id = int(c[1])
	comps.add_child(nc)
	nc.entity = node_ent
	nc._set_def(NodeDef.by_id(int(c[0])))
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Walk in from +X until the capsule meets what blocks the way.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(6, 1.0, 0), Vector3(0, 1.0, 0))
	var hit: Dictionary = space.intersect_ray(q)
	var stop_x: float = (hit["position"] as Vector3).x + CAPSULE_R if not hit.is_empty() else 1.5
	stop_x = minf(stop_x + float(c[6]), maxf(stop_x, WORK_REACH_M - 0.05))
	# The worker: an entity with Visual/Model, facing the node (-Z toward -X: yaw 90 degrees).
	var who := Node3D.new()
	add_child(who)
	who.position = Vector3(stop_x, 0, 0)
	who.rotation.y = deg_to_rad(90.0)
	var wvis := Node3D.new()
	wvis.name = "Visual"
	who.add_child(wvis)
	var worker: Worker = Worker.make(load(String(c[2])) as PackedScene)
	worker.name = "Model"
	wvis.add_child(worker)
	var tool: HeldItem = worker.tool
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(stop_x * 0.6, 1.4, 4.6)
	cam.look_at(Vector3(stop_x * 0.6 - 0.2, 1.1, 0))
	cam.make_current()
	var clip: StringName = c[3]
	worker.player.play(clip)
	worker.player.pause()
	var length: float = worker.player.get_animation(clip).length
	# The swing's front by height (0.1 m bands above the feet): the farthest any point of the tool goes ahead.
	var front: Dictionary[int, float] = {}
	var tt: float = 0.0
	while tt < length:
		await _pose(worker, tt)
		var fwd0: Vector3 = -wvis.global_basis.z
		for n: Node in tool.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			for pt: Vector3 in RegentsSolid.hull_of(mi.mesh).points:
				var w: Vector3 = mi.global_transform * pt - wvis.global_position
				var band: int = floori(w.y / 0.1)
				front[band] = maxf(float(front.get(band, -INF)), w.dot(fwd0))
		tt += 1.0 / 60.0
	var bands: Array = front.keys()
	bands.sort()
	var line: String = ""
	for b: int in bands:
		if front[b] > 0.6:
			line += " Vector2(%.2f, %.2f)," % [b * 0.1 + 0.05, front[b]]
	print("FRONT %s:%s" % [c[5], line])
	# Off: where it stopped walking, at the swing's deepest frame.
	var off: Vector2 = await _deepest(worker, nc, wvis, tool, length)
	await _pose(worker, off.y)
	await _shot("%s/%s_off.png" % [out_dir, c[5]])
	# On: stepped back to the work spot (the adventurer's own reach for the skill, the server's reach kept).
	var sk: SkillingComponent = SkillingComponent.new()
	var prof: PackedVector2Array = sk.swing_front[StringName(c[4])]
	var fwd: Vector3 = -wvis.global_basis.z
	var step: float = WorkSpot.step_back(nc, who.global_position, fwd, prof, sk.work_spot_clearance_m, WORK_REACH_M + nc.def.radius_for(nc.entity_id) - WorkSpot.REACH_MARGIN_M)
	sk.free()
	who.position -= Vector3(fwd.x, 0.0, fwd.z).normalized() * step
	await get_tree().process_frame
	var on: Vector2 = await _deepest(worker, nc, wvis, tool, length)
	await _pose(worker, on.y)
	await _shot("%s/%s_on.png" % [out_dir, c[5]])
	print("WORKSPOT %s: stopped %.2f m from the node's center, stepped back %.2f m; the swing's least gap to the drawn surface: off %.2f m, on %.2f m"
		% [c[5], stop_x, step, off.x, on.x])
	who.queue_free()
	node_ent.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _pose(worker: Worker, at: float) -> void:
	worker.player.seek(at, true)
	await get_tree().process_frame
	await get_tree().process_frame


## Through the whole clip: the least gap between the tool and the drawn surface, and when (x: gap, y: t).
func _deepest(worker: Worker, nc: NodeComponent, wvis: Node3D, tool: HeldItem, length: float) -> Vector2:
	var best: Vector2 = Vector2(INF, 0.0)
	var t: float = 0.0
	while t < length:
		await _pose(worker, t)
		var g: float = _gap(nc, wvis, tool)
		if g < best.x:
			best = Vector2(g, t)
		t += 1.0 / 60.0
	return best


## The least distance, over every point of the tool's hull, from the point forward to the node's drawn surface
## (negative: that point is inside it). Each point looks straight ahead from behind the body at its own height.
func _gap(nc: NodeComponent, wvis: Node3D, tool: HeldItem) -> float:
	var fwd: Vector3 = -wvis.global_basis.z
	var best: float = INF
	for n: Node in tool.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for p: Vector3 in RegentsSolid.hull_of(mi.mesh).points:
			var w: Vector3 = mi.global_transform * p
			var f: float = (w - wvis.global_position).dot(fwd)
			var from: Vector3 = w - fwd * (f + 0.6)
			var s: float = nc.surface_along(from, fwd, 6.0)
			if s < INF:
				best = minf(best, s - 0.6 - f)
	return best


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)


## The character: one of the adventurer's looks, the set's clips on a plain AnimationPlayer, the real tool by its grip
## (`HeldItem.attach`), as the world holds it.
class Worker extends Node3D:
	var player: AnimationPlayer = null
	var tool: HeldItem = null

	static func make(tool_scene: PackedScene) -> Worker:
		var w := Worker.new()
		var def: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
		var model: Node3D = def.visual_variants[0].instantiate() as Node3D
		w.add_child(model)
		model.rotation.y = deg_to_rad(def.visual_yaw_deg)
		var skel: Skeleton3D = null
		for n: Node in model.find_children("*", "Skeleton3D", true, false):
			skel = n as Skeleton3D
		w.player = AnimationPlayer.new()
		model.add_child(w.player)
		for lib: StringName in def.animation_set.libraries:
			if def.animation_set.libraries[lib] != null:
				w.player.add_animation_library(lib, def.animation_set.libraries[lib])
		w.player.root_node = w.player.get_path_to(skel.get_parent())
		w.tool = HeldItem.attach(skel, tool_scene)
		return w
