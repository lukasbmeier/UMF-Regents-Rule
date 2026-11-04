class_name NpcNav extends RefCounted
## WHERE A BOT CAN WALK (milestone 7, DECISIONS #230): a navigation mesh baked from the level's own
## collision, one per body size, so a bot goes round a hedge instead of into it, and a small body
## (a hen) is routed under a hole a big one (the wolf) is not. Baked once per level and body size,
## on first asking (a second or two for a farm), and kept.
##
## A BIG LEVEL IS WALKED A TILE AT A TIME (Regent's Rule's continent, 2026-10-29): a level wider than two
## tiles (`TILE_M`) is never baked whole (the navigation server refuses a mesh that size, and trying
## stalled the referee); each tile is baked on first asking round a point in it, with half a tile all
## round, so a way from that point stays on one map. A way that leaves it ends at its edge (a brain
## walks the last stretch straight). Every bake runs on the navigation server's thread; until it is
## taken in, `path` is empty and a brain goes straight.
##
## ONE BAKE AT A TIME (template 1.5.3, Regent's Rule's Skyrim-size world): every awake camp asked for its
## tile at once, each read the level on the main thread (178 ms a tile there) and held a 256 m bake at
## 0.15 m on the workers; in five minutes one of ~50 finished, and the referee's frames sat at 147 ms. Now
## a tile asked for waits in a queue (`MAX_BAKES` at once), and is read from the level only when its bake
## starts. And a level's bounds are found once, not by searching all its nodes on every brain's every ask.
##
## WALLS ENTITIES PUT UP ARE IN IT (template 1.7.2, DECISIONS #304: Regent's Rule's skeletons walked
## through the copper mine's ore). The referee gives every wall it builds (`set_wall`, `drop_wall`: a rock,
## a tree's trunk, a shut gate, as its genre or character sizes it, only while it is up) and each is carved
## into the bakes as an obstruction its body keeps its radius from. A wall placed, moved, raised or let
## down after a map was baked marks the maps it touches; each is baked again (`REBAKE_AFTER_MS` after the
## first change, never sooner than `REBAKE_GAP_MS` after its last bake began), in the same queue, one at a
## time, off the main thread, its old map walked until the new one is in. The level's collision a tile was
## read from is kept (`SOURCE_KEEP` tiles), so a re-bake does not read the level again on the main thread.
## A shut gate is in the map too: a brain that means to open it walks to it (`go_to` ends at the nearest
## point it can reach).
##
## What a body still does NOT see here: other bodies. A brain meets those as it walks.
##
## SERVER-ONLY (hard rule 7b).

## How far below and above a body's feet a path may step.
const MAX_CLIMB: float = 0.3
## Cell size: a 0.9 m gap must stay a gap at a 0.28 m radius.
const CELL: float = 0.15
## A big level's tiles, a side (each baked with half a tile round it: 256 m square). A level whose bounds
## are wider than two tiles is tiled; a smaller one is baked whole.
const TILE_M: float = 128.0
## Bakes running at once; the rest wait their turn, first asked, first baked.
const MAX_BAKES: int = 1
## A map a wall changed is baked again this long after the first change (the rest of a burst comes with it).
const REBAKE_AFTER_MS: int = 1000
## ...and never sooner than this after its last bake began (a busy mine re-bakes its tile at most this often).
const REBAKE_GAP_MS: int = 5000
## How many tiles' level collision is kept for re-bakes (the newest used). A tile not kept is read again.
const SOURCE_KEEP: int = 4
## A wall's obstruction reaches this far below its feet, so the ground it stands on is covered.
const WALL_BELOW_M: float = 0.5

## [level instance id, radius, height(, tile)] -> the map RID its mesh is on, its region, and the point a
## taken-in map is checked at (the tile's centre, or the level's origin).
static var _maps: Dictionary = {}
static var _regions: Dictionary = {}
static var _centres: Dictionary = {}
## Tiles asked for and not yet started: [key, mesh, level (weak), bounds, radius, height, where], oldest first.
static var _queued: Array = []
static var _baking: int = 0
## A level's bake bounds by its instance id (found once: a big level has tens of thousands of nodes).
static var _bounds_of: Dictionary = {}
## key -> the area its map is baked from (an empty AABB: the whole level), its body, and its level (weak).
static var _areas: Dictionary = {}
static var _bodies: Dictionary = {}
static var _levels: Dictionary = {}
## Keys waiting in `_queued` (a key is never queued twice: its bake reads the walls when it starts).
static var _queued_keys: Dictionary = {}
## key -> when its last bake began (ticks msec); key -> when it is to be baked again (a wall changed).
static var _began: Dictionary = {}
static var _dirty: Dictionary = {}
## Keys whose bake is running now.
static var _in_bake: Dictionary = {}
## Walls entities put up (DECISIONS #304): id -> {"xf": Transform3D, "boxes": Array[AABB], "area": AABB}.
static var _walls: Dictionary = {}
## The level's collision as read for an area: "<level id>|<area>" -> NavigationMeshSourceGeometryData3D,
## and those keys, the newest used last.
static var _sources: Dictionary = {}
static var _source_order: Array[String] = []

## Times a bake read the level (tests count them), and re-bakes begun because a wall changed.
static var reads: int = 0
static var rebakes: int = 0


## A path from `from` to `to` for a body of `radius` by `height` in `level` (the level node the
## sidecar loaded), as points to walk through; empty when there is no level or no way. The first
## call for a level and size bakes its mesh (and returns empty while the server takes it in).
static func path(level: Node3D, from: Vector3, to: Vector3, radius: float, height: float) -> PackedVector3Array:
	if level == null or not level.is_inside_tree():
		return PackedVector3Array()
	if not ready(level, radius, height, from):
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map_for(level, radius, height, from), from, to, true)


## Whether the walk map for `level` and that body is baked and taken in by the navigation server (it
## bakes it on its own thread and takes it in over a few frames). Bakes it if it is not yet. `at`: where,
## on a tiled level (its tile's map).
static func ready(level: Node3D, radius: float, height: float, at: Vector3 = Vector3.ZERO) -> bool:
	if level == null or not level.is_inside_tree():
		return false
	var map: RID = map_for(level, radius, height, at)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var key: String = _key(level, radius, height, at)
	var region: RID = _regions.get(key, RID())
	if not region.is_valid() or NavigationServer3D.region_get_iteration_id(region) == 0:
		return false
	# The map holds the region's polygons once a point on it belongs to the region.
	return NavigationServer3D.map_get_closest_point_owner(map, _centres.get(key, level.global_position)) == region


## The map for `level` and a body of `radius` by `height` (on a tiled level, the tile `at` is in), its bake
## begun if it is not yet.
static func map_for(level: Node3D, radius: float, height: float, at: Vector3 = Vector3.ZERO) -> RID:
	if not _dirty.is_empty():
		_requeue_due()
	var key: String = _key(level, radius, height, at)
	if _maps.has(key):
		return _maps[key]
	var level_bounds: AABB = _bounds(level)
	var tiled: bool = is_tiled(level_bounds)
	var bounds: AABB = area_of(level_bounds, at)
	var mesh: NavigationMesh = _new_mesh(radius, height, bounds)
	var map: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	# Its region goes on the map with its first mesh (as the bake ends): put on the map empty at once, the
	# mesh set later was now and then never taken in (Godot 4.7.1, found 2026-11-03).
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.map_set_active(map, true)
	_maps[key] = map
	_regions[key] = region
	_centres[key] = bounds.get_center() if tiled else level.global_position
	_areas[key] = bounds
	_bodies[key] = Vector2(radius, height)
	_levels[key] = weakref(level)
	var where: String = (" round (%.0f, %.0f)" % [bounds.get_center().x, bounds.get_center().z]) if tiled else ""
	_queue(key, mesh, level, bounds, radius, height, where)
	_start_bakes()
	return map


## A walk map's mesh, before it is baked: for a body of `radius` by `height`, from `bounds` (empty: all).
static func _new_mesh(radius: float, height: float, bounds: AABB) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	# In whole cells (the baker would round them, and say so), the radius up, the height up.
	mesh.agent_radius = ceilf(maxf(radius, CELL) / CELL - 0.001) * CELL
	mesh.agent_height = ceilf(maxf(height, CELL * 2.0) / 0.1 - 0.001) * 0.1
	mesh.agent_max_climb = MAX_CLIMB
	mesh.agent_max_slope = 45.0
	mesh.cell_size = CELL
	mesh.cell_height = 0.1
	# The level's collision, not its meshes: tall grass is drawn, never walked into.
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = SpaceTimeEntity.WORLD_MASK | SpaceTimeEntity.BARRIER_MASK
	if bounds.size != Vector3.ZERO:
		mesh.filter_baking_aabb = bounds
	return mesh


## Into the queue, once (a key already waiting reads the walls as they are when it starts).
static func _queue(key: String, mesh: NavigationMesh, level: Node3D, bounds: AABB, radius: float, height: float, where: String) -> void:
	if _queued_keys.has(key):
		return
	_queued_keys[key] = true
	_queued.append([key, mesh, weakref(level), bounds, radius, height, where])


## Start queued bakes while fewer than `MAX_BAKES` run. Reading the level's collision is the main thread's
## (the parser's rule), so it is done here, for one tile at a time; the bake is the navigation server's.
static func _start_bakes() -> void:
	while _baking < MAX_BAKES and not _queued.is_empty():
		var q: Array = _queued.pop_front()
		var key: String = q[0]
		_queued_keys.erase(key)
		var mesh: NavigationMesh = q[1]
		var level: Node3D = (q[2] as WeakRef).get_ref() as Node3D
		var region: RID = _regions.get(key, RID())
		if level == null or not level.is_inside_tree() or not region.is_valid():
			continue   # its level was let go (another level shown), or the maps were cleared
		var bounds: AABB = q[3]
		var parse_from: int = Time.get_ticks_msec()
		var source: NavigationMeshSourceGeometryData3D = _source_with_walls(level, mesh, bounds)
		var parse_ms: int = Time.get_ticks_msec() - parse_from
		var started: int = Time.get_ticks_msec()
		_began[key] = started
		_dirty.erase(key)
		_in_bake[key] = true
		var radius: float = q[4]
		var height: float = q[5]
		var where: String = q[6]
		var walls: int = source.get_projected_obstructions().size() - _kept_obstructions(level, bounds)
		_baking += 1
		# On the navigation server's thread: a big tile takes a second or more, and the referee must not wait.
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func() -> void:
			_baking = maxi(0, _baking - 1)
			_in_bake.erase(key)
			if region.is_valid() and _regions.values().has(region):
				NavigationServer3D.region_set_navigation_mesh(region, mesh)
				if not NavigationServer3D.region_get_map(region).is_valid():
					NavigationServer3D.region_set_map(region, _maps.get(key, RID()))
			print("[Sidecar] a walk map for bodies %.2f m by %.2f m%s: %d polygons, %d wall boxes, read in %d ms, baked in %d ms (%d waiting)" % [radius,
				height, where, mesh.get_polygon_count(), walls, parse_ms, Time.get_ticks_msec() - started, _queued.size()])
			_start_bakes())


## What a bake of `bounds` is made from: the level's collision there (read once and kept, `SOURCE_KEEP`
## areas), and every wall up in it, each box an obstruction from below its feet to its top.
static func _source_with_walls(level: Node3D, mesh: NavigationMesh, bounds: AABB) -> NavigationMeshSourceGeometryData3D:
	var skey: String = _source_key(level, bounds)
	var kept: NavigationMeshSourceGeometryData3D = _sources.get(skey, null)
	if kept == null:
		kept = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(mesh, kept, level)
		add_ground(level, bounds, kept)
		reads += 1
		_sources[skey] = kept
	_source_order.erase(skey)
	_source_order.append(skey)
	while _source_order.size() > SOURCE_KEEP:
		_sources.erase(_source_order.pop_front())
	# A source of its own (the arrays are shared until written): the walls are this bake's.
	var source := NavigationMeshSourceGeometryData3D.new()
	source.set_vertices(kept.get_vertices())
	source.set_indices(kept.get_indices())
	source.set_projected_obstructions(kept.get_projected_obstructions())
	for id: int in _walls:
		var w: Dictionary = _walls[id]
		if bounds.size != Vector3.ZERO and not bounds.intersects(w["area"] as AABB):
			continue
		var xf: Transform3D = w["xf"]
		var boxes: Array[AABB] = w["boxes"]
		for b: AABB in boxes:
			var outline := PackedVector3Array()
			for c: Vector3 in [b.position, b.position + Vector3(b.size.x, 0, 0),
					b.position + Vector3(b.size.x, 0, b.size.z), b.position + Vector3(0, 0, b.size.z)]:
				outline.append(xf * c)
			var bottom: float = xf.origin.y + b.position.y - WALL_BELOW_M
			source.add_projected_obstruction(outline, bottom, b.size.y + WALL_BELOW_M, false)
	return source


static func _source_key(level: Node3D, bounds: AABB) -> String:
	return "%d|%s" % [level.get_instance_id(), str(bounds)]


## The level's own obstructions in a kept read (a NavigationObstacle3D baked in), for the log's wall count.
static func _kept_obstructions(level: Node3D, bounds: AABB) -> int:
	var kept: NavigationMeshSourceGeometryData3D = _sources.get(_source_key(level, bounds), null)
	return kept.get_projected_obstructions().size() if kept != null else 0


# --- walls entities put up (DECISIONS #304) --------------------------------------------------------

## Wall `id` (its entity) stands at `xf` as `boxes` (each from its feet, in its own terms; empty: none,
## or down). The maps it touches, where it was and where it is, are baked again when it changed.
static func set_wall(id: int, xf: Transform3D, boxes: Array[AABB]) -> void:
	if boxes.is_empty():
		drop_wall(id)
		return
	var was: Dictionary = _walls.get(id, {})
	if not was.is_empty() and (was["xf"] as Transform3D).is_equal_approx(xf) and was["boxes"] == boxes:
		return
	var area := AABB()
	var first: bool = true
	for b: AABB in boxes:
		var a: AABB = xf * b
		area = a if first else area.merge(a)
		first = false
	_walls[id] = {"xf": xf, "boxes": boxes.duplicate(), "area": area}
	if not was.is_empty():
		_mark(was["area"] as AABB)
	_mark(area)


## Wall `id` is gone (its entity, or it is down): the maps it was in are baked again.
static func drop_wall(id: int) -> void:
	var was: Dictionary = _walls.get(id, {})
	if was.is_empty():
		return
	_walls.erase(id)
	_mark(was["area"] as AABB)


## The walls the walk maps hold (tests).
static func wall_count() -> int:
	return _walls.size()


## Whether that map is not yet as its walls are: a bake waiting on a change, queued or running (tests).
static func is_dirty(level: Node3D, radius: float, height: float, at: Vector3 = Vector3.ZERO) -> bool:
	var key: String = _key(level, radius, height, at)
	return _dirty.has(key) or _queued_keys.has(key) or _in_bake.has(key)


## Every map whose area `area` touches is to be baked again, `REBAKE_AFTER_MS` from the first change;
## one already waiting to start is left (it reads the walls when it does).
static func _mark(area: AABB) -> void:
	var grown: AABB = area.grow(1.0)
	for key: String in _areas:
		var a: AABB = _areas[key]
		if a.size != Vector3.ZERO and not a.intersects(grown):
			continue
		if _queued_keys.has(key) or _dirty.has(key):
			continue
		_dirty[key] = Time.get_ticks_msec() + REBAKE_AFTER_MS


## The maps due again (looked at whenever a map is asked for): into the queue, as a first bake is.
static func _requeue_due() -> void:
	var now: int = Time.get_ticks_msec()
	for key: String in _dirty.keys():
		if now < int(_dirty[key]) or now < int(_began.get(key, -REBAKE_GAP_MS)) + REBAKE_GAP_MS:
			continue
		_dirty.erase(key)
		var level: Node3D = (_levels[key] as WeakRef).get_ref() as Node3D if _levels.has(key) else null
		if level == null or not level.is_inside_tree() or not _regions.has(key):
			continue
		var bounds: AABB = _areas[key]
		var body: Vector2 = _bodies[key]
		var where: String = ", again (its walls changed)"
		if is_tiled(_bounds(level)):
			where = " round (%.0f, %.0f), again (its walls changed)" % [bounds.get_center().x, bounds.get_center().z]
		rebakes += 1
		_queue(key, _new_mesh(body.x, body.y, bounds), level, bounds, body.x, body.y, where)
	_start_bakes()


## Walk maps asked for and not yet started (for tests and the log).
static func waiting() -> int:
	return _queued.size()


## Whether a level with these bounds is walked a tile at a time (wider than two tiles either way).
static func is_tiled(bounds: AABB) -> bool:
	return bounds.size.x > 2.0 * TILE_M or bounds.size.z > 2.0 * TILE_M


## What is baked for a map: the level's bounds, or on a tiled level the tile `at` is in with half a tile
## all round (within the level's height).
static func area_of(bounds: AABB, at: Vector3) -> AABB:
	if not is_tiled(bounds):
		return bounds
	var tx: float = floorf(at.x / TILE_M) * TILE_M
	var tz: float = floorf(at.z / TILE_M) * TILE_M
	return AABB(Vector3(tx - TILE_M * 0.5, bounds.position.y, tz - TILE_M * 0.5),
		Vector3(TILE_M * 2.0, bounds.size.y, TILE_M * 2.0))


## GROUND THAT MAKES ITS OWN COLLISION (DECISIONS #240: a Terrain3D, whose collision is a heightmap
## made in the physics server, not a node the parser finds): every node of the level that can give its
## walkable faces (`generate_nav_mesh_source_geometry(aabb, require_nav)`) adds them. The number added.
static func add_ground(level: Node3D, bounds: AABB, source: NavigationMeshSourceGeometryData3D) -> int:
	var added: int = 0
	var area: AABB = bounds if bounds.size != Vector3.ZERO else AABB(Vector3(-512, -64, -512), Vector3(1024, 128, 1024))
	for n: Node in level.find_children("*", "", true, false):
		if n.has_method(&"generate_nav_mesh_source_geometry"):
			var faces: Variant = n.call(&"generate_nav_mesh_source_geometry", area, false)
			if faces is PackedVector3Array and not (faces as PackedVector3Array).is_empty():
				source.add_faces(faces, Transform3D.IDENTITY)
				added += (faces as PackedVector3Array).size() / 3
	return added


static func _key(level: Node3D, radius: float, height: float, at: Vector3 = Vector3.ZERO) -> String:
	var key: String = "%d|%.2f|%.2f" % [level.get_instance_id(), radius, height]
	if is_tiled(_bounds(level)):
		key += "|%d,%d" % [int(floorf(at.x / TILE_M)), int(floorf(at.z / TILE_M))]
	return key


## The part of the level worth baking: its LevelInfo's bake bounds, when it has one (an empty AABB without).
static func level_bounds(level: Node3D) -> AABB:
	return _bounds(level) if level != null else AABB()


static func _bounds(level: Node3D) -> AABB:
	var id: int = level.get_instance_id()
	if _bounds_of.has(id):
		return _bounds_of[id]
	var found := AABB()
	for n: Node in level.find_children("*", "", true, false):
		if n is LevelInfo:
			found = (n as LevelInfo).bake_bounds
			break
	_bounds_of[id] = found
	return found


## Forget every map, every wall and every kept read of a level (a test that builds its own levels).
static func clear() -> void:
	for region: RID in _regions.values():
		NavigationServer3D.free_rid(region)
	for map: RID in _maps.values():
		NavigationServer3D.free_rid(map)
	_regions.clear()
	_maps.clear()
	_centres.clear()
	_queued.clear()
	_bounds_of.clear()
	_areas.clear()
	_bodies.clear()
	_levels.clear()
	_queued_keys.clear()
	_began.clear()
	_dirty.clear()
	_in_bake.clear()
	_walls.clear()
	_sources.clear()
	_source_order.clear()
