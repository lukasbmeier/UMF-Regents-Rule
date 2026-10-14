class_name NpcNav extends RefCounted
## WHERE A BOT CAN WALK (milestone 7, DECISIONS #230): a navigation mesh baked from the level's own
## collision, one per body size, so a bot goes round a hedge instead of into it, and a small body
## (a hen) is routed under a hole a big one (the wolf) is not. Baked once per level and body size,
## on first asking (a second or two for a farm), and kept.
##
## What a body does NOT see here: walls entities put up (a shut gate, DECISIONS #229) and other
## bodies. A brain meets those as it walks, and decides (open the gate, go round).
##
## SERVER-ONLY (hard rule 7b).

## How far below and above a body's feet a path may step.
const MAX_CLIMB: float = 0.3
## Cell size: a 0.9 m gap must stay a gap at a 0.28 m radius.
const CELL: float = 0.15

## [level instance id, radius, height] -> the map RID its mesh is on, and its region.
static var _maps: Dictionary = {}
static var _regions: Dictionary = {}


## A path from `from` to `to` for a body of `radius` by `height` in `level` (the level node the
## sidecar loaded), as points to walk through; empty when there is no level or no way. The first
## call for a level and size bakes its mesh (and returns empty while the server takes it in).
static func path(level: Node3D, from: Vector3, to: Vector3, radius: float, height: float) -> PackedVector3Array:
	if level == null or not level.is_inside_tree():
		return PackedVector3Array()
	if not ready(level, radius, height):
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map_for(level, radius, height), from, to, true)


## Whether the walk map for `level` and that body is baked and taken in by the navigation server (it
## takes a new mesh in over a few frames, on its own thread). Bakes it if it is not yet.
static func ready(level: Node3D, radius: float, height: float) -> bool:
	if level == null or not level.is_inside_tree():
		return false
	var map: RID = map_for(level, radius, height)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var region: RID = _regions.get(_key(level, radius, height), RID())
	if not region.is_valid() or NavigationServer3D.region_get_iteration_id(region) == 0:
		return false
	# The map holds the region's polygons once a point on it belongs to the region.
	return NavigationServer3D.map_get_closest_point_owner(map, level.global_position) == region


## The map for `level` and a body of `radius` by `height`, baked if it is not yet.
static func map_for(level: Node3D, radius: float, height: float) -> RID:
	var key: String = _key(level, radius, height)
	if _maps.has(key):
		return _maps[key]
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
	var bounds: AABB = _bounds(level)
	if bounds.size != Vector3.ZERO:
		mesh.filter_baking_aabb = bounds
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, level)
	add_ground(level, bounds, source)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var map: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.map_set_active(map, true)
	_maps[key] = map
	_regions[key] = region
	print("[Sidecar] a walk map for bodies %.2f m by %.2f m: %d polygons" % [radius, height, mesh.get_polygon_count()])
	return map


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


static func _key(level: Node3D, radius: float, height: float) -> String:
	return "%d|%.2f|%.2f" % [level.get_instance_id(), radius, height]


## The part of the level worth baking: its LevelInfo's bake bounds, when it has one.
static func _bounds(level: Node3D) -> AABB:
	for n: Node in level.find_children("*", "", true, false):
		if n is LevelInfo:
			return (n as LevelInfo).bake_bounds
	return AABB()


## Forget every map (a test that builds its own levels).
static func clear() -> void:
	for region: RID in _regions.values():
		NavigationServer3D.free_rid(region)
	for map: RID in _maps.values():
		NavigationServer3D.free_rid(map)
	_regions.clear()
	_maps.clear()
