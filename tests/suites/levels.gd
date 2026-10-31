extends "res://tests/suite_base.gd"
## The `levels` suite (tests/test_runner.gd runs it; `-- --only=levels` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_level_build_tests()



## LEVELS BUILT IN THE EDITOR (DECISIONS #175): a level scene's markers and collision ARE its
## bake (the foundation's example level, baked again here, is byte for byte what the server compiled
## in: a stale bake fails); the client reads a bake's id, scene and points; and the level on screen
## follows the world's.
## The foundation's example level (foundation/level/example/), level 200.
const EXAMPLE_ID: int = 200
const EXAMPLE_SCENE: String = "res://foundation/level/example/example_level.tscn"


class FakeWorldLevelRow extends RefCounted:
	var world_id: int = 0
	var level_id: int
	func _init(id: int) -> void:
		level_id = id


func _run_level_build_tests() -> void:
	print("== levels built in the editor ==")
	var example_bake: LevelBake = LevelBake.by_id(EXAMPLE_ID)
	_check(example_bake != null and example_bake.level == "example" and example_bake.scene == EXAMPLE_SCENE
		and example_bake.points_of("marker").size() == 1 and LevelBake.by_id(0) == null,
		"the client reads a bake's number, scene and points (the example is %d, the greybox none)" % EXAMPLE_ID)
	# --- the example level, baked again from its scene -----------------------------------------
	var scene: Node3D = (load(EXAMPLE_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	for i: int in range(8):
		await get_tree().physics_frame
	var out: String = "user://bake_check"
	var r: Dictionary = LevelBaker.bake(scene, out)
	_check(bool(r["ok"]), "the example scene bakes (%s)" % r.get("error", ""))
	if bool(r["ok"]):
		var again: PackedByteArray = FileAccess.get_file_as_bytes(r["bin"])
		var shipped: PackedByteArray = FileAccess.get_file_as_bytes("res://shared/world/example_depth.bin")
		var json_again: String = FileAccess.get_file_as_string(r["json"])
		var json_shipped: String = FileAccess.get_file_as_string("res://shared/world/example.json")
		_check(again == shipped and json_again == json_shipped,
			"and the bake is exactly what the server compiled in (else: move nothing, or bake again with LevelInfo's button)")
	var spot: LevelSpot = scene.get_node(^"PondSpot") as LevelSpot
	spot.position.x += 3.0
	var moved: Dictionary = LevelBaker.bake(scene, out)
	_check(float((moved["doc"]["spots"] as Array)[0]["x"]) == 3.0, "a marker moved in the scene moves in the bake")
	var info: LevelInfo = scene.get_node(^"LevelInfo") as LevelInfo
	info.water_y = 5.0
	var flooded: Dictionary = LevelBaker.bake(scene, out)
	_check(int(flooded["wet"]) > int(r["wet"]) * 2, "and the water is read off the ground: raised, it floods the level (%d wet cells, was %d)" % [flooded["wet"], r["wet"]])
	# The ground's height for tools (template 1.5, `bake_ground`): only when asked, the height every ray hit.
	_check(not (r["doc"] as Dictionary).has("ground_grid"), "a level not asked for its ground bakes none (the shipped bake unchanged)")
	info.bake_ground = true
	var grounded: Dictionary = LevelBaker.bake(scene, out)
	var gg: Dictionary = (grounded["doc"] as Dictionary).get("ground_grid", {}) as Dictionary
	var gbytes: PackedByteArray = FileAccess.get_file_as_bytes(out.path_join(str(gg.get("file", "none"))))
	var gw: int = int(gg.get("width", 0))
	var gh: int = int(gg.get("height", 0))
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var hits: int = 0
	var worst: float = 0.0
	for k: int in range(0, gw * gh, maxi(1, (gw * gh) / 40)):
		var gx: float = float(gg["origin_x"]) + float(k % gw) * float(gg["spacing"]) + LevelBaker.RAY_NUDGE
		var gz: float = float(gg["origin_z"]) + float(k / gw) * float(gg["spacing"]) + LevelBaker.RAY_NUDGE
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(gx, 200.0, gz), Vector3(gx, -200.0, gz), LevelBaker.WORLD_MASK))
		var dm: int = gbytes.decode_u16(k * 2) if gbytes.size() >= (k + 1) * 2 else -1
		if hit.is_empty() or dm == LevelBaker.GROUND_NONE:
			continue
		hits += 1
		worst = maxf(worst, absf(float(gg["base_y"]) + float(dm) / 10.0 - (hit["position"] as Vector3).y))
	_check(gbytes.size() == gw * gh * 2 and hits > 10 and worst <= 0.051,
		"asked for, it writes the ground's height over the whole grid (%d x %d, %d samples checked against a ray, off by %.3f m at worst)" % [gw, gh, hits, worst])
	info.bake_ground = false
	scene.queue_free()
	await get_tree().process_frame
	# THE BAKE BUTTON RUNS A SCENE (template 1.6.1): a bare `-s` script has no autoloads, and a streamed level's
	# cut (Cells, which reads the hot rules) then put all its scenery into one cell at the grid's corner.
	var button_src: String = FileAccess.get_file_as_string("res://foundation/level/level_info.gd")
	var baker: Node = (load("res://tools/world/bake_level.tscn") as PackedScene).instantiate()
	_check(button_src.contains("\"res://tools/world/bake_level.tscn\"") and not button_src.contains("\"-s\", \"res://tools/world/bake_level.gd\"")
		and baker != null and baker.get_script() == load("res://tools/world/bake_level.gd"),
		"LevelInfo's Bake button runs the baker as a scene, autoloads and all (never as a bare script)")
	baker.free()
	# (The lakeside's baker-against-generator and barrier checks are fishing's: fishing_levels.)
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
	# A registered entity (a player): moved into the new level, it must still receive its rows.
	var player := SpaceTimeEntity.new()
	player.name = "Mover"
	grey.get_node(^"WorldRoot").add_child(player)
	player.entity_id = 987655   # after it is in the tree: the spawner's order (hard rule 8)
	EntitySpawner._nodes[987655] = player
	EntityRegistry.register(987655, player)
	await get_tree().process_frame
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(0)))
	_check(loader.level() == grey and loader.level_id() == 0, "the level the world already runs is left as it is")
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(EXAMPLE_ID)))
	await get_tree().process_frame
	var shown: Node3D = loader.level()
	_check(loader.level_id() == EXAMPLE_ID and shown != null and shown.scene_file_path == EXAMPLE_SCENE
		and not is_instance_valid(grey) or (is_instance_valid(grey) and grey.is_queued_for_deletion()),
		"when the world runs the example level, its scene (the bake's) replaces the greybox")
	_check(walker.get_parent() == shown.get_node(^"WorldRoot") and walker.global_position.is_equal_approx(Vector3(2, 0, 3))
		and EntitySpawner.get_node(EntitySpawner.world_root_path) == shown.get_node(^"WorldRoot"),
		"and the entities move into its WorldRoot, where they were, where new ones will spawn")
	_check(player.get_parent() == shown.get_node(^"WorldRoot") and EntityRegistry.get_entity(987655) == player,
		"a registered entity moved with them is still registered: its rows still reach it")
	_check(not loader.show_level(77) and loader.level_id() == EXAMPLE_ID, "a level nothing can show is said, and the current one stays")
	# The referee's world moves its entities the same way, through the same call (DECISIONS #253): moved
	# anywhere, an entity still hears its rows.
	var elsewhere := Node3D.new()
	get_tree().root.add_child(elsewhere)
	EntitySpawner.move_entities_to(elsewhere)
	_check(player.get_parent() == elsewhere and walker.get_parent() == elsewhere and EntityRegistry.get_entity(987655) == player
		and walker.global_position.is_equal_approx(Vector3(2, 0, 3)) and EntitySpawner.get_node(EntitySpawner.world_root_path) == elsewhere,
		"the one way entities move between levels (the client's and the referee's): where they stood, still registered")
	elsewhere.queue_free()
	EntitySpawner._nodes.erase(987654)
	EntitySpawner._nodes.erase(987655)
	EntityRegistry.unregister(987655)
	EntitySpawner.world_root_path = prev_root
	game.queue_free()
	await get_tree().process_frame
