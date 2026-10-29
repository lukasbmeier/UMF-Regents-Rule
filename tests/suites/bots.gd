extends "res://tests/suite_base.gd"
## The `bots` suite (milestone 7, DECISIONS #230): what a bot's brain can do beyond walking, and what
## the sidecar builds for one.
##   - a referee builds only bots (`EntitySpawner.spawn_filter`), and lets one go (`release`)
##   - a brain is made by name, a genre's from its path
##   - a brain asks to hold, let go and use an ability, and its component sends each once
##   - it walks a route point by point, round what is in the way
##   - the walk map: a small body is routed under a low hole a big one is not
## The server's side (add_bot, a referee driving a bot in a MODULE world): tests/integration_test.sh.


func run() -> void:
	_run_filter()
	_run_make()
	_run_acts()
	_run_route()
	await _run_nav()
	await _run_nav_tiled()
	_run_ground()
	_run_tree()


func _run_filter() -> void:
	print("== bots: a referee builds only its bots ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.scene = load(PLAYER_SCENE) as PackedScene
	var root := Node3D.new()
	add_child(root)
	var prev_ready: bool = spawner._world_ready
	var prev_root: NodePath = spawner.world_root_path
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(root)
	spawner._world_ready = true
	var bots: Array[int] = [8802]
	spawner.spawn_filter = func(eid: int, _kind: int) -> bool: return bots.has(eid)
	for eid: int in [8801, 8802]:
		_buffer_player_rows(reg, eid)
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	_check(spawner.get_entity_node(8801) == null, "a player's entity: not built here")
	_check(spawner.get_entity_node(8802) != null, "a bot's: built")
	var gone: Array[int] = []
	var on_gone := func(eid: int) -> void: gone.append(eid)
	SignalBus.entity_despawned.connect(on_gone)
	spawner.release(8802)
	SignalBus.entity_despawned.disconnect(on_gone)
	_check(spawner.get_entity_node(8802) == null and gone == [8802], "released: its node gone, said once (its rows are the server's)")
	spawner.spawn_filter = Callable()
	spawner._world_ready = prev_ready
	spawner.world_root_path = prev_root
	reg.take_buffered(8801)
	root.queue_free()


func _run_make() -> void:
	print("== bots: brains by name ==")
	_check(NpcBrainComponent.make_brain(&"wander", 1) is WanderBrain and NpcBrainComponent.make_brain(&"chase", 1) is ChaseBrain, "the foundation's by name")
	var stand: NpcBrain = NpcBrainComponent.make_brain(&"stand", 1)
	_check(stand is StandBrain and stand.state == &"standing", "one by its path (the brains folder's stand.gd), as a genre's are")
	_check(NpcBrainComponent.make_brain(&"../../tests/suite_base", 1) == null, "nothing outside the brains' folder")


func _run_acts() -> void:
	print("== bots: a brain asks to do things ==")
	var b := StandBrain.new()
	b.hold(77)
	b.let_go()
	b.use_ability(10000, Vector3(0, 0, -1), 5)
	var acts: Array[Dictionary] = b.take_acts()
	_check(acts.size() == 3 and acts[0]["do"] == "hold" and int(acts[0]["target"]) == 77 and int(acts[0]["verb"]) == 0
		and acts[1]["do"] == "let_go" and acts[2]["do"] == "ability" and int(acts[2]["ability"]) == 10000 and int(acts[2]["target"]) == 5,
		"hold, let go, an ability: asked in order")
	_check(b.take_acts().is_empty(), "and each is taken once")
	b.call_as(&"wiggle_as")
	b.call_as(&"come_out_as", [3], ["u8"])
	var genre: Array[Dictionary] = b.take_acts()
	_check(genre.size() == 2 and genre[0]["do"] == "reducer" and genre[0]["reducer"] == &"wiggle_as" and (genre[1]["args"] as Array) == [3]
		and (genre[1]["types"] as Array) == ["u8"], "a genre's own reducer, as the bot (DECISIONS #239): its name, its arguments")


class _Paths extends NpcWorldView:
	var way: PackedVector3Array = PackedVector3Array()
	func path(_from: Vector3, _to: Vector3, _radius: float, _height: float) -> PackedVector3Array:
		return way


func _run_route() -> void:
	print("== bots: walking a route ==")
	var b := StandBrain.new()
	var me := MovementState.new()
	var w := _Paths.new()
	w.way = PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -5), Vector3(5, 0, -5)])
	b.go_to(Vector3(5, 0, -5), me, w)
	_check(b.route().size() == 2, "a route round the corner (%d points to pass)" % b.route().size())
	var f: InputFrame = b.frame(me)
	_check(f.move_dir.is_equal_approx(Vector2(0, -1)), "it heads for the first point, not the goal (%s)" % str(f.move_dir))
	me.pos = Vector3(0, 0, -4.8)
	f = b.frame(me)
	_check(b.route().size() == 1 and f.move_dir.x > 0.9, "past it, it turns for the next (%s)" % str(f.move_dir))
	me.pos = Vector3(4.8, 0, -5)
	f = b.frame(me)
	_check(not b.has_goal() and f.move_dir == Vector2.ZERO, "there: it stops")
	w.way = PackedVector3Array()
	b.go_to(Vector3(3, 0, 0), me, w)
	_check(b.route().is_empty() and b.frame(me).move_dir.length() > 0.9, "no way known: straight at it")


func _wall(root: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.position = at


func _run_nav() -> void:
	print("== bots: the walk map (a hen fits under a hole, the wolf does not) ==")
	var level := Node3D.new()
	add_child(level)
	var info := LevelInfo.new()
	info.bake_bounds = AABB(Vector3(-12, -2, -12), Vector3(24, 6, 24))
	level.add_child(info)
	_wall(level, Vector3(0, -0.5, 0), Vector3(24, 1, 24))   # the ground
	# A hedge along z = 0 from x = -12 to 6 (round its east end), with a hole at x = 0: 0.9 m wide, 0.8 m high.
	_wall(level, Vector3(-6.45, 1.2, 0), Vector3(11.1, 2.4, 0.9))
	_wall(level, Vector3(3.45, 1.2, 0), Vector3(5.1, 2.4, 0.9))
	_wall(level, Vector3(0, 1.6, 0), Vector3(0.9, 1.6, 0.9))
	for i: int in 3:
		await get_tree().physics_frame
	NpcNav.map_for(level, 0.28, 0.7)
	NpcNav.map_for(level, 0.4, 1.0)
	# The server takes a new mesh in over a few frames (on its own thread): wait for both.
	var until: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and not (NpcNav.ready(level, 0.28, 0.7) and NpcNav.ready(level, 0.4, 1.0)):
		await get_tree().physics_frame
	_check(NpcNav.ready(level, 0.28, 0.7) and NpcNav.ready(level, 0.4, 1.0), "both walk maps are taken in")
	var length := func(p: PackedVector3Array) -> float:
		var d: float = 0.0
		for i: int in range(1, p.size()):
			d += p[i - 1].distance_to(p[i])
		return d
	var small: PackedVector3Array = NpcNav.path(level, Vector3(0, 0, 3), Vector3(0, 0, -3), 0.28, 0.7)
	var big: PackedVector3Array = NpcNav.path(level, Vector3(0, 0, 3), Vector3(0, 0, -3), 0.4, 1.0)
	print("   a hen's way %.1f m (%d points), the wolf's %.1f m (%d points)" % [length.call(small), small.size(), length.call(big), big.size()])
	_check(small.size() >= 2 and float(length.call(small)) < 7.0, "a hen's way goes under the hole (%.1f m)" % float(length.call(small)))
	_check(big.size() >= 2 and float(length.call(big)) > 12.0, "the wolf's goes round the hedge's end (%.1f m)" % float(length.call(big)))
	_check(NpcNav.path(null, Vector3.ZERO, Vector3.ONE, 0.3, 1.0).is_empty(), "no level: no way (a brain goes straight)")
	NpcNav.clear()
	level.queue_free()
	await get_tree().process_frame


## A level 3 km across (Regent's Rule's continent is 2.5 by 3.3): baked whole, the navigation server refuses
## it (an engine error, which fails this suite) and the referee stalled trying. Tiled, each tile is baked on
## its own, on the server's thread.
func _run_nav_tiled() -> void:
	print("== bots: a big level's walk map, a tile at a time ==")
	var level := Node3D.new()
	add_child(level)
	var info := LevelInfo.new()
	info.bake_bounds = AABB(Vector3(-1500, -20, -1500), Vector3(3000, 40, 3000))
	level.add_child(info)
	_wall(level, Vector3(0, -0.5, 0), Vector3(60, 1, 60))           # ground round the origin
	_wall(level, Vector3(-7, 1.2, 0), Vector3(26, 2.4, 0.9))        # a wall along z = 0, x -20 to 6: round its east end
	_wall(level, Vector3(1000, -0.5, 1000), Vector3(20, 1, 20))     # ground far off, another tile
	for i: int in 3:
		await get_tree().physics_frame
	_check(NpcNav.is_tiled(info.bake_bounds) and not NpcNav.is_tiled(AABB(Vector3(-100, 0, -100), Vector3(200, 10, 200))),
		"3 km is walked in tiles; 200 m is baked whole")
	_check(NpcNav.area_of(info.bake_bounds, Vector3(5, 0, 5)) == AABB(Vector3(-64, -20, -64), Vector3(256, 40, 256)),
		"a tile's bake: its 128 m and half a tile round it (%s)" % str(NpcNav.area_of(info.bake_bounds, Vector3(5, 0, 5))))
	var near: RID = NpcNav.map_for(level, 0.4, 1.8, Vector3(0, 0, 5))
	var far: RID = NpcNav.map_for(level, 0.4, 1.8, Vector3(1000, 0, 1000))
	_check(near != far and NpcNav.map_for(level, 0.4, 1.8, Vector3(60, 0, 60)) == near,
		"one map a tile: another tile's is another, a point in the same tile shares it")
	var until: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until and not (NpcNav.ready(level, 0.4, 1.8, Vector3(0, 0, 5)) and NpcNav.ready(level, 0.4, 1.8, Vector3(1000, 0, 1000))):
		await get_tree().physics_frame
	_check(NpcNav.ready(level, 0.4, 1.8, Vector3(0, 0, 5)) and NpcNav.ready(level, 0.4, 1.8, Vector3(1000, 0, 1000)),
		"both tiles' maps are baked off the main thread and taken in")
	var way: PackedVector3Array = NpcNav.path(level, Vector3(0, 0, 5), Vector3(0, 0, -5), 0.4, 1.8)
	var length: float = 0.0
	for i: int in range(1, way.size()):
		length += way[i - 1].distance_to(way[i])
	_check(way.size() >= 3 and length > 15.0, "a way round the wall's end (%.1f m, %d points; straight is 10)" % [length, way.size()])
	var there: PackedVector3Array = NpcNav.path(level, Vector3(995, 0, 995), Vector3(1005, 0, 1005), 0.4, 1.8)
	_check(there.size() >= 2, "a way on the far tile, on its own map")
	NpcNav.clear()
	level.queue_free()
	await get_tree().process_frame


class _Ground extends Node3D:
	func generate_nav_mesh_source_geometry(_aabb: AABB, _require_nav: bool) -> PackedVector3Array:
		return PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4)])


## GROUND THAT MAKES ITS OWN COLLISION (DECISIONS #240: Terrain3D): its faces go into the walk map.
func _run_ground() -> void:
	print("== bots: ground that makes its own collision ==")
	var level := Node3D.new()
	var g := _Ground.new()
	level.add_child(g)
	var plain := Node3D.new()
	level.add_child(plain)
	var source := NavigationMeshSourceGeometryData3D.new()
	var n: int = NpcNav.add_ground(level, AABB(), source)
	_check(n == 2 and source.get_vertices().size() == 18, "a node that gives its faces: its two triangles are added (%d)" % n)
	var none := NavigationMeshSourceGeometryData3D.new()
	_check(NpcNav.add_ground(plain, AABB(), none) == 0 and none.get_vertices().is_empty(), "a level without such a node: nothing")
	level.free()
	plain = null


func _run_tree() -> void:
	print("== bots: a brain runs a behaviour tree (LimboAI, DECISIONS #245) ==")
	var task_script: Script = load("res://tests/fixtures/brain_step_task.gd") as Script
	var task: BTAction = task_script.new() as BTAction
	var tree := BehaviorTree.new()
	tree.root_task = task
	var path: String = "user://tests/brain_tree.tres"
	DirAccess.make_dir_recursive_absolute("user://tests")
	_check(ResourceSaver.save(tree, path) == OK, "a tree saved to a file, as a genre's are")
	var b := StandBrain.new()
	var t: Array[int] = [1000]
	b.clock = func() -> int: return t[0]
	_check(b.tree_status() == -1, "before its first step: no word")
	var me := MovementState.new()
	var world := NpcWorldView.new()
	_check(b.run_tree(path, me, world), "a step of it")
	_check(String(b.state) == "step me=true world=true dt=0.20" and b.tree_status() == BT.SUCCESS,
		"its task reached the brain, with this think's me and world, the first step 0.2 s (%s)" % b.state)
	t[0] += 350
	b.run_tree(path, me, world)
	_check(String(b.state).ends_with("dt=0.35"), "the next step's time is the brain's clock's (%s)" % b.state)
	var failing := BehaviorTree.new()
	var no: BTAction = task_script.new() as BTAction
	no.set(&"succeed", false)
	failing.root_task = no
	var path2: String = "user://tests/brain_tree_fails.tres"
	ResourceSaver.save(failing, path2)
	b.run_tree(path2, me, world)
	_check(b.tree_status() == BT.FAILURE, "another tree in its place: its own word (failure)")
	var agent: Node = b._tree_agent
	b = null
	_check(not is_instance_valid(agent), "the brain gone: its tree's agent too")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path2)
