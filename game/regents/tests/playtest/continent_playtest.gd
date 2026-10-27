extends Node
## THE CONTINENT, WALKED (game/regents/tests/continent_playtest.sh starts one, its world on the continent,
## level 21; PROGRESS step 23): a real client on ring interest in a world bigger than one ring.
##   - the continent is shown, streamed: only the cells round the player are loaded, not the whole level
##   - the ring: the nodes it is sent are all in the 3 x 3 cells round it, a fraction of the world's
##   - a streamed cell's rocks and bushes are solid
##   - far away (a teleport), the ring and the cells follow: the camp's tree is gone, the trees there come,
##     the camp's cells are freed; the player stands on the ground there
##   - a cell over (a step east), a node both rings share is the same one, never despawned and spawned
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 180.0
const LEVEL: int = 21
const TREE_1: Vector3 = Vector3(-9.0, 0.0, -6.0)

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var me: SpaceTimeEntity
var streamer: LevelStreamer
var bake: LevelBake


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	var loader: LevelLoader = get_tree().current_scene.find_child("LevelLoader", true, false) as LevelLoader
	streamer = get_tree().current_scene.find_child("LevelStreamer", true, false) as LevelStreamer
	bake = LevelBake.by_id(LEVEL)
	_check(loader != null and streamer != null and bake != null, "the game has its level loader and streamer; level 21 is baked")
	if loader == null or streamer == null or bake == null:
		_finish()
		return
	await _until(func() -> bool: return loader.level_id() == LEVEL, 15.0)
	_check(loader.level_id() == LEVEL, "the world runs the continent, and it is the level shown (%d)" % loader.level_id())
	var total_cells: int = LevelCells.read(LevelCells.folder_for(loader.level().scene_file_path, "continent")).size()
	var total_nodes: int = bake.points_of("node").size()
	await _until(func() -> bool: return not streamer.loaded_cells().is_empty() and InterestManager.centre >= 0, 10.0)
	await _until(func() -> bool: return me.global_position.distance_to(Vector3(0, 0, 8)) < 3.0, 5.0)

	# --- AT THE CAMP ---
	_check(InterestManager.is_ring() and InterestManager.centre == Cells.chunk_of(me.global_position),
		"ring interest, round the player's cell (%d)" % InterestManager.centre)
	_check_streamed("at the camp", total_cells)
	await _until(func() -> bool: return _node_ids().size() > 10, 8.0)
	_check_ring("at the camp", total_nodes)
	_check(await _node_at(TREE_1) > 0, "the camp's tree_1 is there, as in the glade")
	_check(_solid_bodies() > 0, "the cells loaded round the camp have solid rocks (%d bodies)" % _solid_bodies())
	var camp_spot: Vector3 = me.global_position + Vector3(0.0, 0.5, 0.0)
	# THE WORLD MAP'S DISCOVERY (Luke, 2026-10-26): the nodes near the spawn are seen, by the server's word
	# (`node_seen`, sent to us only); the camp's farther ones are not. Then M: every point of interest on it.
	var reach: float = HotRules.number(&"regents.seen_reach_m")
	await _until(func() -> bool: return not RegentsDiscovery.seen_points().is_empty(), 6.0)
	await get_tree().create_timer(2.5).timeout
	var seen: Dictionary = RegentsDiscovery.seen_points()
	var near_ok: bool = true
	var far_one: String = ""
	for pt: Dictionary in bake.points_of("node"):
		var d: float = Vector2(float(pt["x"]) - me.global_position.x, float(pt["z"]) - me.global_position.z).length()
		if d < reach - 3.0 and not seen.has(String(pt["id"])):
			near_ok = false
		if d > reach + 8.0 and seen.has(String(pt["id"])):
			far_one = String(pt["id"])
	_check(not seen.is_empty() and near_ok and far_one.is_empty(),
		"the nodes within %.0f m of the spawn are discovered, none beyond (%d seen%s)" % [reach, seen.size(), ", but " + far_one if not far_one.is_empty() else ""])
	var hud: RegentsHud = null
	for n: Node in get_tree().root.find_children("*", "", true, false):
		if n is RegentsHud:
			hud = n as RegentsHud
			break
	if hud != null:
		hud.toggle_world_map()
		var wm: RegentsWorldMap = hud.world_map
		var pois: int = 0
		for ic: Dictionary in RegentsWorldMap.icons_of(bake):
			pois += 1 if String(ic["kind"]) == "poi" else 0
		_check(wm != null and wm.is_open() and wm.level_id == LEVEL and pois >= 40, "M opens the world map on the continent, %d places of interest on it" % pois)
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(OS.get_environment("MAP_SHOT") if not OS.get_environment("MAP_SHOT").is_empty() else "user://world_map.png")
		hud.toggle_world_map()
		_check(wm != null and not wm.is_open(), "and M again closes it")
	else:
		_check(false, "the game's HUD is here")
	# A TOOL IS NOT A PERSON (DECISIONS #272; Luke's playtest 2026-10-24, "Player 39 is showing"): the
	# database's CLI has a player at the spawn, an admin with no name, never drawn, though on the ring the
	# admins' rows come in their own subscription, after the players'.
	await _until(func() -> bool: return not _tools().is_empty() and _tools_drawn() == 0, 3.0)
	_check(not _tools().is_empty() and _tools_drawn() == 0, "the database's CLI player (%s) is here and hidden as a tool (%d not)"
		% [str(_tools()), _tools_drawn()])

	# --- FAR AWAY ---
	var far: Vector3 = _far_tree()
	_check(far != Vector3.INF, "a scattered tree 600-900 m out, with land a cell east of it: %s" % str(far))
	if far == Vector3.INF:
		_finish()
		return
	var stand: Vector3 = far + Vector3(2.0, 1.0, 0.0)
	var camp_cell: int = Cells.chunk_of(Vector3.ZERO)
	SpaceTimeSync.call_reducer(&"teleport", [stand], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return Vector2(me.global_position.x, me.global_position.z).distance_to(Vector2(stand.x, stand.z)) < 1.5, 6.0)
	await _until(func() -> bool: return InterestManager.centre == Cells.chunk_of(stand) and _node_near(far) > 0, 10.0)
	_check(InterestManager.centre == Cells.chunk_of(stand), "the ring moved with them (centre %d, there %d)" % [InterestManager.centre, Cells.chunk_of(stand)])
	_check(_node_near(far) > 0, "the tree out there is sent and drawn")
	await _until(func() -> bool: return _node_near(TREE_1) < 0, 6.0)
	_check(_node_near(TREE_1) < 0, "the camp's tree_1 is no longer sent (it is 600 m behind)")
	await _until(func() -> bool: return not streamer.loaded_cells().has(camp_cell), 6.0)
	# The cells there load on a thread (only the first ever load at once): the ground is the terrain, always there.
	await _until(func() -> bool: return streamer.loaded_cells().has(Cells.chunk_of(me.global_position)), 6.0)
	_check_streamed("far out", total_cells)
	_check(not streamer.loaded_cells().has(camp_cell), "the camp's cell is freed behind them")
	_check_ring("far out", total_nodes)
	# THE MINIMAP out here (Luke's playtest, 2026-10-24: "minimap doesn't update out here"): pictured round
	# them. Only in a window (WINDOWED=1): headless, nothing is drawn and no picture is taken.
	if DisplayServer.get_name() != "headless":
		var mini: RegentsMinimap = get_tree().root.find_children("*", "RegentsMinimap", true, false).front() as RegentsMinimap 			if not get_tree().root.find_children("*", "RegentsMinimap", true, false).is_empty() else null
		var at2 := Vector2(me.global_position.x, me.global_position.z)
		await _until(func() -> bool: return mini != null and not RegentsMinimap.leaves_picture(at2, RegentsMinimap.RADIUS_MAX_M, mini.area_origin, mini.area_m), 6.0)
		_check(mini != null and not RegentsMinimap.leaves_picture(at2, RegentsMinimap.RADIUS_MAX_M, mini.area_origin, mini.area_m),
			"the minimap is pictured round them out here (%s, %.0f m from %s)" % [str(at2), mini.area_m if mini != null else 0.0, str(mini.area_origin) if mini != null else "-"])
	await get_tree().create_timer(2.0).timeout
	var ground: float = _ground_below(me.global_position)
	_check(not is_nan(ground) and absf(me.global_position.y - ground) < 0.6,
		"they stand on the continent's ground there (y %.2f, ground %.2f)" % [me.global_position.y, ground])

	# --- ONE CELL OVER: what both rings share stays ---
	var before: Dictionary[int, int] = _node_instances()
	var east: Vector3 = stand + Vector3(Cells.cell_m(), 0.0, 0.0)
	east.y = bake_ground(east) + 1.0
	SpaceTimeSync.call_reducer(&"teleport", [east], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return InterestManager.centre == Cells.chunk_of(east), 8.0)
	await get_tree().create_timer(1.5).timeout
	var after: Dictionary[int, int] = _node_instances()
	var shared: int = 0
	var respawned: Array[int] = []
	for id: int in before:
		if not after.has(id):
			continue
		shared += 1
		if after[id] != before[id]:
			respawned.append(id)
	_check(InterestManager.centre == Cells.chunk_of(east), "a cell east, the ring re-centred")
	_check(shared > 0 and respawned.is_empty(), "the %d nodes both rings share were kept, none spawned again (%s)" % [shared, str(respawned)])

	# --- BACK TO THE CAMP: what left the ring and came back is whole (Luke's "Player 39": the CLI's player,
	# spawned again from its cells' rows, never had its `player` row again, and was drawn) ---
	var tools_before: Array[int] = _tools()
	var home: Vector3 = camp_spot
	for attempt: int in 4:   # the ring must follow at once, though the spawn is ON a cell's edge (#7)
		SpaceTimeSync.call_reducer(&"teleport", [home], ["vector3[f32,f32,f32]"])
		await _until(func() -> bool: return InterestManager.centre == Cells.chunk_of(home), 3.0)
		if InterestManager.centre == Cells.chunk_of(home):
			break
	await _until(func() -> bool: return _node_near(TREE_1) > 0, 8.0)
	await _until(func() -> bool: return not _tools().is_empty() and _tools_drawn() == 0, 3.0)
	_check(tools_before.is_empty() and not _tools().is_empty() and _tools_drawn() == 0,
		"back at the camp (centre %d, home %d) the CLI's player is spawned again and still hidden as a tool (%s, %d not; at %s)"
			% [InterestManager.centre, Cells.chunk_of(home), str(_tools()), _tools_drawn(), str(me.global_position)])
	print("   cells loaded %d of %d; nodes drawn %d of %d; entities in the registry %d" % [streamer.loaded_cells().size(),
		total_cells, _node_ids().size(), total_nodes, EntityRegistry.all_entity_ids().size()])
	_finish()


## The streamer has only the cells round the player loaded, each within its ring of them.
func _check_streamed(where: String, total: int) -> void:
	var cells: Array[int] = streamer.loaded_cells()
	var mine: Vector2i = Cells.squares(Cells.chunk_of(me.global_position))
	var out_of_reach: Array[int] = []
	for c: int in cells:
		var sq: Vector2i = Cells.squares(c)
		if maxi(absi(sq.x - mine.x), absi(sq.y - mine.y)) > Cells.stream_radius() + 1:
			out_of_reach.append(c)
	_check(not cells.is_empty() and cells.size() <= 49 and cells.size() < total and out_of_reach.is_empty(),
		"%s: %d of the continent's %d cells loaded, all round the player (beyond: %s)" % [where, cells.size(), total, str(out_of_reach)])


## Every node drawn is in the 3 x 3 cells round the ring's centre, and they are a fraction of the world's.
func _check_ring(where: String, total: int) -> void:
	var ring: PackedInt64Array = Cells.ring(InterestManager.centre, Cells.ring_radius())
	var outside: int = 0
	var ids: Array[int] = _node_ids()
	for id: int in ids:
		if not ring.has(Cells.chunk_of((EntityRegistry.get_entity(id) as Node3D).global_position)):
			outside += 1
	_check(not ids.is_empty() and ids.size() * 4 < total and outside == 0,
		"%s: %d of the world's %d nodes sent, none outside the 3 x 3 cells (%d outside)" % [where, ids.size(), total, outside])


func _node_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in EntityRegistry.all_entity_ids():
		if SkillingComponent.node_of(id) != null and EntityRegistry.get_entity(id) != null:
			out.append(id)
	return out


func _node_instances() -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for id: int in _node_ids():
		out[id] = EntityRegistry.get_entity(id).get_instance_id()
	return out


## The node drawn within 1 m of `at` (flat distance), or -1.
func _node_near(at: Vector3) -> int:
	for id: int in _node_ids():
		var p: Vector3 = (EntityRegistry.get_entity(id) as Node3D).global_position
		if Vector2(p.x, p.z).distance_to(Vector2(at.x, at.z)) < 1.0:
			return id
	return -1


func _node_at(at: Vector3) -> int:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var id: int = _node_near(at)
		if id > 0:
			return id
		await get_tree().process_frame
	return -1


## A scattered tree 600-900 m from the camp, with standable land a cell east of it.
func _far_tree() -> Vector3:
	for p: Dictionary in bake.points_of("node"):
		var at := Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		var d: float = Vector2(at.x, at.z).length()
		var east: Vector3 = at + Vector3(Cells.cell_m() + 2.0, 0.0, 0.0)
		if str(p["id"]).begins_with("w_tree_") and d > 600.0 and d < 900.0 \
				and bake.can_stand(east.x, east.z) and not bake.is_water(east.x, east.z) and not is_nan(bake_ground(east)):
			return at
	return Vector3.INF


## The ground's height at (x, z) on the loaded level's collision, or NAN.
func bake_ground(at: Vector3) -> float:
	return _ground_below(Vector3(at.x, 400.0, at.z))


func _ground_below(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = me.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 3.0, at.z), Vector3(at.x, at.y - 600.0, at.z), SpaceTimeEntity.WORLD_MASK)
	q.exclude = [me.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## Solid bodies under the loaded cells (their rocks and bushes, wrapped as each arrived).
func _solid_bodies() -> int:
	var cells_node: Node = get_tree().current_scene.find_child(String(LevelCells.CELLS_NODE), true, false)
	if cells_node == null:
		return 0
	return cells_node.find_children("Solid", "StaticBody3D", true, false).size()


## The entities of the players who are tools (nameless admins: the CLI) that are spawned here.
func _tools() -> Array[int]:
	var out: Array[int] = []
	for row: Variant in SpaceTimeSync.find_rows(&"player", func(_r: RefCounted) -> bool: return true):
		var eid: int = int((row as RefCounted).get(&"entity_id"))
		if _is_tool(row as RefCounted) and EntitySpawner.get_entity_node(eid) != null:
			out.append(eid)
	return out


## A tool's player row: no name, and an admin's identity (the server's own word, read here directly).
func _is_tool(r: RefCounted) -> bool:
	var a: RefCounted = SpaceTimeSync.get_row(&"authority", r.get(&"identity"))
	return String(r.get(&"name")).is_empty() and a != null and int(a.get(&"role")) == Roles.ADMIN


## How many of them are not hidden as tools (one hidden only because it went offline counts: the CLI
## comes and goes, and while it is connected it would be drawn).
func _tools_drawn() -> int:
	var n: int = 0
	for eid: int in _tools():
		var e: SpaceTimeEntity = EntitySpawner.get_entity_node(eid) as SpaceTimeEntity
		if e != null and not e.hidden_reasons().has(&"tool"):
			n += 1
	return n


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + 30_000
	while Time.get_ticks_msec() < deadline:
		var id: int = EntityRegistry.local_entity_id
		if id >= 0:
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.is_bound():
				return e
		await get_tree().process_frame
	_check(false, "local player spawned and bound")
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	_check(false, "finished within %.0f s" % OVERALL_TIMEOUT_SEC)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\ncontinent: %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
