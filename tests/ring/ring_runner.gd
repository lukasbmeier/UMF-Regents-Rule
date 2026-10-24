extends Node
## RING INTEREST ON A REAL SERVER (template 1.0, DECISIONS #278): driven by tests/ring_test.sh, which
## publishes a fresh module and has the admin place three NPCs: NEAR in the spawn's cell, EAST two cells
## east, WEST two cells west (both outside a 3 x 3 ring round the spawn). This client asks only for the
## cells round it (`NetConfig.interest = RING`), and must:
##   see NEAR and nobody else;
##   keep NEAR (the same node, no despawn) while the admin walks it into the next cell, inside the ring;
##   gain EAST and keep NEAR when it moves a cell east; lose both far beyond; never lose itself;
##   see them again when it comes back.
## The CLI the shell uses moves NEAR (`spacetime call ... write_movement_batch`, the admin's).

const STEP_SEC: float = 20.0

var _passes: int = 0
var _failures: int = 0
var _ids: Dictionary[String, int] = {}
var _deleted: Dictionary[int, int] = {}


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		for k: String in ["near", "east", "west"]:
			if a.begins_with("--%s=" % k):
				_ids[k] = int(a.get_slice("=", 1))
	SpaceTimeSync.row_event.connect(func(ev: RowEvent) -> void:
		if ev.table == &"entity" and ev.kind == RowEvent.Kind.DELETED:
			if ev.entity_id == EntityRegistry.local_entity_id:
				print("   (our entity row deleted: centre %d, sets %s)" % [InterestManager.centre, str(SpaceTimeSync._sets.keys())])
			_deleted[ev.entity_id] = _deleted.get(ev.entity_id, 0) + 1)
	_run.call_deferred()


func _run() -> void:
	print("== a ring client ==")
	var ok: bool = await _until(_me_spawned, "our player")
	_check(ok, "connected, our player spawned")
	_check(InterestManager.is_ring(), "the scene's config asks for RING interest")
	ok = await _until(_has_cells, "the cells round us")
	_check(ok, "the ring round our place has arrived (centre %d)" % InterestManager.centre)
	var me: int = EntityRegistry.local_entity_id
	var me_node: Node = EntityRegistry.get_entity(me)
	_check(await _until(func() -> bool: return _has("near"), "NEAR"), "NEAR, in our cell, is there")
	await _settle(1.0)
	_check(not _has("east") and not _has("west"), "EAST and WEST, two cells off, are not sent at all")

	print("== a neighbour walks into the next cell, inside the ring ==")
	var near_node: Node = EntityRegistry.get_entity(_ids["near"])
	_move(_ids["near"], 70.0, 10.0)
	ok = await _until(func() -> bool: return _x_of("near") > 60.0, "NEAR at x 70")
	_check(ok, "it arrives where it went (x %.1f)" % _x_of("near"))
	_check(EntityRegistry.get_entity(_ids["near"]) == near_node and _deleted.get(_ids["near"], 0) == 0,
		"the same node all the way: never deleted and spawned again (%d deletes)" % _deleted.get(_ids["near"], 0))

	print("== we move a cell east ==")
	_teleport(150.0, 10.0)
	ok = await _until(func() -> bool: return InterestManager.centre == Cells.chunk_of(Vector3(150, 0, 10)), "the ring re-centred")
	_check(ok, "the ring follows us")
	_check(await _until(func() -> bool: return _has("east"), "EAST"), "EAST comes into view")
	_check(_has("near") and EntityRegistry.get_entity(_ids["near"]) == near_node, "NEAR, a cell behind, stays (the same node)")
	_check(not _has("west"), "WEST stays out")

	print("== far beyond ==")
	_teleport(290.0, 10.0)
	_check(await _until(func() -> bool: return not _has("near") and not _has("east"), "both gone"),
		"two cells and more behind: both leave our world")
	_check(EntityRegistry.get_entity(me) == me_node and _deleted.get(me, 0) == 0,
		"and we never left ours (%d deletes of our own entity)" % _deleted.get(me, 0))

	print("== home again ==")
	_teleport(10.0, 10.0)
	_check(await _until(func() -> bool: return _has("near") and not _has("east"), "NEAR back"),
		"NEAR (a cell east of home) is back, EAST is not")
	_check(EntityRegistry.get_entity(me) == me_node, "still ourselves")
	print("\n%d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


func _me_spawned() -> bool:
	return EntityRegistry.local_entity_id >= 0 and EntityRegistry.get_entity(EntityRegistry.local_entity_id) != null


func _has_cells() -> bool:
	var set: SubscriptionSet = InterestManager.ring_set()
	if InterestManager.centre < 0 or set == null:
		return false
	for q: String in set.queries:
		if q.contains("chunk = "):
			return true
	return false


func _has(k: String) -> bool:
	return _ids.has(k) and EntityRegistry.get_entity(_ids[k]) != null


func _x_of(k: String) -> float:
	var n: Node3D = EntityRegistry.get_entity(_ids.get(k, -1)) as Node3D if _ids.has(k) else null
	var row: RefCounted = SpaceTimeSync.get_row(&"movement_state", _ids.get(k, -1))
	return float((row.get(&"pos") as Vector3).x) if row != null else (n.global_position.x if n != null else -999.0)


func _teleport(x: float, z: float) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(x, 0.0, z)], ["vector3[f32,f32,f32]"])


## The admin moves an NPC (the CLI is the database's owner, an authority).
func _move(eid: int, x: float, z: float) -> void:
	var db: String = OS.get_environment("UMF_DB")
	var w: String = '[{"entity_id":%d,"pos":{"x":%s,"y":0.0,"z":%s},"vel":{"x":0.0,"y":0.0,"z":0.0},"yaw":0.0,"grounded":true,"move_state":0,"last_processed_seq":0,"teleport_flag":false}]' % [eid, x, z]
	var out: Array = []
	# Windows hands a program one command line: the JSON's quotes must be escaped to arrive.
	var arg: String = w.replace("\"", "\\\"") if OS.get_name() == "Windows" else w
	var code: int = OS.execute("spacetime", ["call", db, "write_movement_batch", "0", arg], out, true)
	print("   (moved %d: exit %d %s)" % [eid, code, "
".join(PackedStringArray(out)).strip_edges().right(200)])


func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _until(pred: Callable, what: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STEP_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	printerr("  TIMEOUT waiting for ", what)
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)
