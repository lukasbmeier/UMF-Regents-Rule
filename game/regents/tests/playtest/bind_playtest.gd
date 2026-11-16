extends Node
## EVERY ENTITY BINDS AT ONCE (armor run E2, 2026-11-15). One real client in the frontier camp
## (game/regents/tests/bind_playtest.sh starts it): every entity that comes into its ring, the guide, the
## foes, the dummy, the nodes, must be bound (drawn where its rows say, its components live) as soon as its
## rows are in, not after the foundation's 2 s bind timeout.
##
## WHY: the foes and the guide are built on the foundation's `player.tscn`, whose `SessionComponent` needed a
## `session_member` row before the entity would bind. An NPC is never a session's member, so each of them
## stood frozen at its first rows for 2 s and printed "binding after 2.0s without rows for session_member".
## Prints `BIND <entity> kind=<k> after=<ms>` for each, then the verdict. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 60.0
## The camp: in sight of the guide, the dummy and the foes round it (as the spells-seen playtest stands).
const CAMP_AT: Vector3 = Vector3(7.0, 0.05, 28.0)
## How long after the teleport to keep watching entities arrive.
const WATCH_SEC: float = 8.0
## Bound later than this after it spawned is a stall: the bind timeout (2 s), not rows on their way.
const STALL_MS: int = 1000
## NPC kinds that must be seen, so the run proves something: the guide (120) and a foe (103..109).
const GUIDE_KIND: int = 120

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
## entity -> [kind, bound after msec]: from its node entering the tree (the spawner adds it, then binds it) to its
## `bound` signal. Kept by node until it binds (its id is set by `bind()`).
var _seen: Dictionary[int, Array] = {}
## The entities in the tree that have not bound yet: node -> entered at msec.
var _waiting: Dictionary[Node, int] = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_run.call_deferred()


func _on_node_added(n: Node) -> void:
	var e: SpaceTimeEntity = n as SpaceTimeEntity
	if e == null or e.is_bound():
		return
	_waiting[e] = Time.get_ticks_msec()
	e.bound.connect(_on_bound.bind(e), CONNECT_ONE_SHOT)


func _on_bound(e: SpaceTimeEntity) -> void:
	if not _waiting.has(e):
		return
	var kind: int = e.definition.kind if e.definition != null else -1
	_seen[e.entity_id] = [kind, Time.get_ticks_msec() - _waiting[e]]
	_waiting.erase(e)


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	SpaceTimeSync.call_reducer(&"teleport", [CAMP_AT], ["vector3[f32,f32,f32]"])
	await get_tree().create_timer(WATCH_SEC).timeout
	var stalled: Array[String] = []
	for n: Node in _waiting:
		if is_instance_valid(n):
			stalled.append("an entity that never bound")
	var guides: int = 0
	var foes: int = 0
	var npc_sessions_ok: bool = true
	for eid: int in _seen:
		var kind: int = int(_seen[eid][0])
		var after: int = int(_seen[eid][1])
		print("BIND %d kind=%d after=%d" % [eid, kind, after])
		if after > STALL_MS:
			stalled.append("%d (kind %d, %d ms)" % [eid, kind, after])
		if kind == GUIDE_KIND:
			guides += 1
		elif kind >= 103 and kind <= 109:
			foes += 1
		var e: SpaceTimeEntity = EntityRegistry.get_entity(eid) as SpaceTimeEntity
		if e != null and kind != 0:
			var sess: SessionComponent = e.find_component(SessionComponent) as SessionComponent
			if sess != null and sess.is_in_session():
				npc_sessions_ok = false
	_check(guides >= 1 and foes >= 1, "the camp's NPCs came into the ring: %d guide(s), %d foe(s), %d entities in all"
		% [guides, foes, _seen.size()])
	_check(stalled.is_empty(), "every entity bound within %d ms of spawning%s"
		% [STALL_MS, "" if stalled.is_empty() else ": stalled " + ", ".join(stalled)])
	_check(npc_sessions_ok, "no NPC reads as a session's member (it has no session_member row)")
	_finish()


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
		print("   ok: ", msg)
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: bind playtest exceeded %.0fs" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nbind playtest: %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
