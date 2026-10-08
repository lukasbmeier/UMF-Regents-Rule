extends "res://tests/suite_base.gd"
## The `levels` suite (tests/test_runner.gd runs it; `-- --only=levels` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_level_build_tests()



## LEVELS BUILT IN THE EDITOR (DECISIONS #175): a level scene's markers and collision ARE its
## bake (the meadow, baked again here, is byte for byte what the server compiled in: a stale bake
## fails); the baker agrees with the lakeside's own generator about its lake; the client reads a
## bake's id, scene and points; and the level on screen follows the world's.
class FakeWorldLevelRow extends RefCounted:
	var world_id: int = 0
	var level_id: int
	func _init(id: int) -> void:
		level_id = id


func _run_level_build_tests() -> void:
	print("== levels built in the editor ==")
	var meadow_bake: LevelBake = LevelBake.by_id(2)
	_check(meadow_bake != null and meadow_bake.level == "meadow" and meadow_bake.scene == "res://game/world/levels/meadow.tscn"
		and meadow_bake.points_of("bench").size() == 1 and LevelBake.by_id(1).level == "lakeside" and LevelBake.by_id(0) == null,
		"the client reads a bake's number, scene and points (meadow is 2, the lakeside 1, the greybox none)")
	# --- the meadow, baked again from its scene ----------------------------------------------
	var scene: Node3D = (load("res://game/world/levels/meadow.tscn") as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	for i: int in range(8):
		await get_tree().physics_frame
	var out: String = "user://bake_check"
	var r: Dictionary = LevelBaker.bake(scene, out)
	_check(bool(r["ok"]), "the meadow scene bakes (%s)" % r.get("error", ""))
	if bool(r["ok"]):
		var again: PackedByteArray = FileAccess.get_file_as_bytes(r["bin"])
		var shipped: PackedByteArray = FileAccess.get_file_as_bytes("res://shared/world/meadow_depth.bin")
		var json_again: String = FileAccess.get_file_as_string(r["json"])
		var json_shipped: String = FileAccess.get_file_as_string("res://shared/world/meadow.json")
		_check(again == shipped and json_again == json_shipped,
			"and the bake is exactly what the server compiled in (else: move nothing, or bake again with LevelInfo's button)")
	var spot: LevelSpot = scene.get_node(^"PondSpot") as LevelSpot
	spot.position.x += 3.0
	var moved: Dictionary = LevelBaker.bake(scene, out)
	_check(float((moved["doc"]["spots"] as Array)[0]["x"]) == 3.0, "a marker moved in the scene moves in the bake")
	var info: LevelInfo = scene.get_node(^"LevelInfo") as LevelInfo
	info.water_y = 5.0
	var flooded: Dictionary = LevelBaker.bake(scene, out)
	_check(int(flooded["wet"]) > int(r["wet"]) * 2, "and the water is read off the ground: raised, it floods the meadow (%d wet cells, was %d)" % [flooded["wet"], r["wet"]])
	scene.queue_free()
	await get_tree().process_frame
	# --- the lakeside: the baker against its generator ------------------------------------------
	var shipped_lake: LevelBake = LevelBake.load_level("lakeside")
	var lake: Node3D = (load(LAKESIDE_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(lake)
	for i: int in range(8):
		await get_tree().physics_frame
	var settings: Dictionary = {"level_name": "lakeside_check", "level_id": 1, "water_y": shipped_lake.water_y,
		"wade_depth": shipped_lake.wade_depth, "min_cast_depth": shipped_lake.min_cast_dm / 10.0, "grid_spacing": 1.0,
		"bounds": AABB(Vector3(shipped_lake.origin_x, -40, shipped_lake.origin_z),
			Vector3(shipped_lake.width - 1, 80, shipped_lake.height - 1))}
	var lr: Dictionary = LevelBaker.bake(lake, out, settings)
	var differ: int = 0
	var cells: int = 0
	var wet_shipped: int = 0
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(lr.get("bin", "")))
	var w: int = int(lr.get("width", 0))
	var ox: float = float(lr["doc"]["depth_grid"]["origin_x"]) if bool(lr["ok"]) else 0.0
	var oz: float = float(lr["doc"]["depth_grid"]["origin_z"]) if bool(lr["ok"]) else 0.0
	for j: int in range(int(lr.get("height", 0))):
		for i: int in range(w):
			var x: float = ox + i
			var z: float = oz + j
			var mine: int = bytes[j * w + i]
			var theirs: int = shipped_lake.depth_dm_at(x, z)
			cells += 1
			wet_shipped += 1 if theirs > 0 else 0
			if absi(mine - theirs) > 1:
				differ += 1
	_check(bool(lr["ok"]) and cells > 1000 and differ < wet_shipped / 50,
		"baked from its scene, the lakeside's lake matches its generator's to a decimetre in all but %d of %d wet cells" % [differ, wet_shipped])
	_check(bool(lr["ok"]) and (lr["doc"]["spots"] as Array).size() == shipped_lake.spots.size()
		and Vector3(lr["doc"]["spawn"][0], lr["doc"]["spawn"][1], lr["doc"]["spawn"][2]).distance_to(shipped_lake.spawn) < 0.01,
		"and its spots and spawn, read off its markers, are the generator's")
	# NOWHERE THE BARRIER LETS A PLAYER GO DOES THE SERVER REFUSE (REVIEW B2). The lake's invisible
	# wall runs along the wading contour and round the dock; a player pressed against it is where
	# `can_stand` must still say yes, or the module would correct an honest client on every frame.
	var edge: CollisionShape3D = lake.find_child("LakeEdge", true, false) as CollisionShape3D
	var wall: ConcavePolygonShape3D = edge.shape as ConcavePolygonShape3D if edge != null else null
	var wall_points: int = 0
	var refused: Array[Vector2] = []
	if wall != null:
		for v: Vector3 in wall.get_faces():
			var p: Vector3 = edge.global_transform * v
			wall_points += 1
			if not shipped_lake.can_stand(p.x, p.z):
				refused.append(Vector2(p.x, p.z))
	_check(wall_points > 1000 and refused.is_empty(),
		"every point of the lake's barrier (%d) is ground the server lets a player stand on (refused: %s)"
			% [wall_points, str(refused.slice(0, 5))])
	lake.queue_free()
	await get_tree().process_frame
	# --- the level on screen follows the world's -------------------------------------------------
	var game := Node3D.new()
	game.name = "LevelGame"
	get_tree().root.add_child(game)
	var grey: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	grey.name = "Greybox"
	game.add_child(grey)
	var loader := LevelLoader.new()
	loader.current = ^"../Greybox"
	loader.current_id = 0
	game.add_child(loader)
	var prev_root: NodePath = EntitySpawner.world_root_path
	EntitySpawner.world_root_path = EntitySpawner.get_path_to(grey.get_node(^"WorldRoot"))
	var walker := Node3D.new()
	walker.name = "Walker"
	grey.get_node(^"WorldRoot").add_child(walker)
	walker.global_position = Vector3(2, 0, 3)
	EntitySpawner._nodes[987654] = walker
	await get_tree().process_frame
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(0)))
	_check(loader.level() == grey and loader.level_id() == 0, "the level the world already runs is left as it is")
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(2)))
	await get_tree().process_frame
	var shown: Node3D = loader.level()
	_check(loader.level_id() == 2 and shown != null and shown.scene_file_path == "res://game/world/levels/meadow.tscn"
		and not is_instance_valid(grey) or (is_instance_valid(grey) and grey.is_queued_for_deletion()),
		"when the world runs the meadow, its scene (the bake's) replaces the greybox")
	_check(walker.get_parent() == shown.get_node(^"WorldRoot") and walker.global_position.is_equal_approx(Vector3(2, 0, 3))
		and EntitySpawner.get_node(EntitySpawner.world_root_path) == shown.get_node(^"WorldRoot"),
		"and the entities move into its WorldRoot, where they were, where new ones will spawn")
	_check(not loader.show_level(77) and loader.level_id() == 2, "a level nothing can show is said, and the current one stays")
	EntitySpawner._nodes.erase(987654)
	EntitySpawner.world_root_path = prev_root
	game.queue_free()
	await get_tree().process_frame
