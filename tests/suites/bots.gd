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
	_run_ground()


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
