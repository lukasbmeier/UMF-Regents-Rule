extends RefereeGenre
## REGENT'S RULE'S WALLS, FOR ITS REFEREE (template 1.7.2, DECISIONS #304; Luke's play, 2026-11-03, #8196:
## "Sparring skeleton walks right through the copper mine ore"). The referee builds no node or station
## scenes, so it knew nothing stood there. Here each one is sized from the same numbers its client builds its
## collision from, so a foe stops (and paths round) where a player does:
##   - a ROCK: its model's meshes (the one `NodeComponent` picks for that entity id), each mesh's box, times
##     the NodeDef's `model_scale` (the client wraps the same meshes in hulls: `RegentsSolid`)
##   - a TREE: its trunk only (`NodeComponent.TRUNK_RADIUS` x `model_scale`, `TRUNK_HEIGHT` tall); walking
##     under the canopy is fine
##   - a STATION: its body box and each of its pieces' meshes where its StationDef places them; with nothing
##     drawn, the client's fallback box
## A worked-out node puts up nothing: the node character's Blocks In is [Normal] (its status switches it).
## Measured once per model (`_mesh_boxes`). Nothing until the entity's row has come (asked again then).
## SERVER-ONLY (hard rule 7b).

const KIND_NODE: int = 100
const KIND_STATION: int = 101
const TABLE_NODE: StringName = &"gather_node"
const TABLE_STATION: StringName = &"station"

## Each model's mesh boxes, in its own space, by its path.
static var _mesh_boxes: Dictionary[String, Array] = {}


func sizes_kind(kind: int) -> bool:
	return kind == KIND_NODE or kind == KIND_STATION


func wall_tables() -> Array[StringName]:
	return [TABLE_NODE, TABLE_STATION]


func walls(entity_id: int, kind: int) -> Array[AABB]:
	if kind == KIND_NODE:
		var row: RefCounted = SpaceTimeSync.get_row(TABLE_NODE, entity_id)
		return node_walls(NodeDef.by_id(int(row.get(&"def_id"))), entity_id) if row != null else ([] as Array[AABB])
	if kind == KIND_STATION:
		var row: RefCounted = SpaceTimeSync.get_row(TABLE_STATION, entity_id)
		return station_walls(StationDef.by_key(StringName(String(row.get(&"key"))))) if row != null else ([] as Array[AABB])
	return []


## A node's walls: a rock's model, a tree's trunk. Empty for no def.
static func node_walls(d: NodeDef, entity_id: int) -> Array[AABB]:
	var out: Array[AABB] = []
	if d == null:
		return out
	if d.depleted == NodeDef.Depleted.RUBBLE and not d.models.is_empty():
		var scene: PackedScene = d.models[absi(entity_id) % d.models.size()]
		var scaled: Transform3D = Transform3D(Basis.from_scale(Vector3.ONE * d.model_scale), Vector3.ZERO)
		for b: AABB in mesh_boxes(scene):
			out.append(scaled * b)
		return out
	var r: float = NodeComponent.TRUNK_RADIUS * d.model_scale
	out.append(RefereeGenre.box(Vector3(r * 2.0, NodeComponent.TRUNK_HEIGHT, r * 2.0), Vector3(0.0, NodeComponent.TRUNK_HEIGHT * 0.5, 0.0)))
	return out


## A station's walls: its body box and its pieces' meshes; with neither, the client's fallback box.
static func station_walls(d: StationDef) -> Array[AABB]:
	var out: Array[AABB] = []
	if d == null:
		return out
	if d.body_size != Vector3.ZERO:
		out.append(RefereeGenre.box(d.body_size, Vector3(0.0, d.body_size.y * 0.5, 0.0)))
	for i: int in d.pieces.size():
		if d.pieces[i] == null:
			continue
		var t: Transform3D = d.piece_transforms[i] if i < d.piece_transforms.size() else Transform3D.IDENTITY
		for b: AABB in mesh_boxes(d.pieces[i]):
			out.append(t * b)
	if out.is_empty():
		out.append(RefereeGenre.box(Vector3(1.2, 1.2, 1.2), Vector3(0.0, 0.6, 0.0)))
	return out


## The box of every solid mesh in `scene` (not in the "not_solid" group), in the scene root's space.
static func mesh_boxes(scene: PackedScene) -> Array[AABB]:
	var out: Array[AABB] = []
	if scene == null:
		return out
	var key: String = scene.resource_path
	if not key.is_empty() and _mesh_boxes.has(key):
		out.assign(_mesh_boxes[key])
		return out
	var root: Node3D = scene.instantiate() as Node3D
	if root == null:
		return out
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n: Node in meshes:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or mi.is_in_group(&"not_solid"):
			continue
		out.append(RegentsSolid.relative(root, mi) * mi.mesh.get_aabb())
	root.free()
	if not key.is_empty():
		_mesh_boxes[key] = out.duplicate()
	return out
