class_name RegentsDiscovery extends Node
## WHAT YOU HAVE DISCOVERED (Luke, 2026-10-26): the world map names a node you have been near ("Coal rock")
## and calls any other by its skill ("Mining ???"). Once a second this tells the server which nodes drawn
## round you are within `regents.seen_reach_m` and not yet seen (`saw_nodes`); the server measures again
## from where it has you and keeps a `node_seen` row per node, sent to you only. Presentation asks; the
## server decides (hard rule 13).

const SEEN_TABLE: StringName = &"node_seen"
const NODE_TABLE: StringName = &"gather_node"
const REACH_RULE: StringName = &"regents.seen_reach_m"
## How often it looks round (seconds).
const LOOK_EVERY_S: float = 1.0
## The most a call names (the server's limit).
const MOST_AT_ONCE: int = 32

var _look_in: float = 0.0
## Point ids asked about and not yet answered (a refused call lets them go again).
var _asked: Dictionary[String, bool] = {}


func _process(delta: float) -> void:
	_look_in -= delta
	if _look_in > 0.0:
		return
	_look_in = LOOK_EVERY_S
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
	if me == null:
		return
	var near: Array = near_unseen(me.global_position, HotRules.number(REACH_RULE), seen_points())
	var ids: Array[int] = []
	var points: Array[String] = []
	for pair: Array in near:
		if _asked.has(String(pair[1])):
			continue
		ids.append(int(pair[0]))
		points.append(String(pair[1]))
		if ids.size() >= MOST_AT_ONCE:
			break
	if ids.is_empty():
		return
	for p: String in points:
		_asked[p] = true
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"saw_nodes", [ids], ["u64"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.outcome != ReducerRequest.Outcome.OK:
			for p: String in points:
				_asked.erase(p))


## The nodes drawn here within `reach` m of `at` (flat) whose points are not in `seen`: [[entity id, point id]].
static func near_unseen(at: Vector3, reach: float, seen: Dictionary) -> Array:
	var out: Array = []
	for row: Variant in SpaceTimeSync.find_rows(NODE_TABLE, func(_r: RefCounted) -> bool: return true):
		var r: RefCounted = row
		var point: String = String(r.get(&"point_id"))
		if seen.has(point):
			continue
		var eid: int = int(r.get(&"entity_id"))
		var e: Node3D = EntityRegistry.get_entity(eid) as Node3D
		if e != null and Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() <= reach:
			out.append([eid, point])
	return out


## The points of the nodes this character has seen: {point id: true}.
static func seen_points() -> Dictionary:
	var out: Dictionary = {}
	var me: int = EntityRegistry.local_entity_id
	for row: Variant in SpaceTimeSync.find_rows(SEEN_TABLE, func(_r: RefCounted) -> bool: return true):
		var r: RefCounted = row
		if int(r.get(&"entity_id")) == me:
			out[String(r.get(&"point_id"))] = true
	return out
