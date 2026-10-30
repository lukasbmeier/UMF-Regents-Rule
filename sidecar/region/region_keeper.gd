class_name RegionKeeper extends Node
## WHAT A REGION REFEREE RUNS (DECISIONS #288): four times a second it looks at every NPC (a bot: an
## `npc_brain` row and no player) and every body in what it watches, takes from the module those standing in
## its cells (`drive_npcs`) and lets go of those it ran that have walked `hand_on_m` past its edge. The
## module's `npc_driver` rows say what it runs; `on_mine` and `on_not_mine` start and stop running each
## (build the bot, fly the body; let it go). The module gives an NPC to one referee at a time, so a neighbour
## taking one waits for this one to let go, and one that has gone (crashed) loses its NPCs after a few
## seconds to whoever's cells they stand in.
##
## SERVER-ONLY (hard rule 7b).

## How often it looks.
const POLL_S: float = 0.25

var region: RefereeRegion = null
var world_id: int = 0
## Off in tests: decided, not sent.
var send: bool = true
## Start running entity `eid` (it is ours now) / stop (it is not).
var on_mine: Callable = Callable()
var on_not_mine: Callable = Callable()
## Who this referee is (default: the connection's identity). A test sets its own.
var identity: PackedByteArray = PackedByteArray()
## TESTING: the rows of a table (default: the client cache).
var rows_of: Callable = Callable()

## What it runs now, as the module says (and as it has started running).
var _mine: Dictionary[int, bool] = {}
## What it has let go of while the module's row still says it is ours (the release on its way): not run
## again unless it walks back in.
var _letting_go: Dictionary[int, bool] = {}
var _accum: float = 0.0
## Calls sent, for the log and tests.
var taken: int = 0
var let_go: int = 0


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_S:
		return
	_accum = 0.0
	poll()


## Whether it runs `eid` now.
func drives(eid: int) -> bool:
	return _mine.has(eid)


## One look: reconcile what it runs with the module's rows, then ask for what has come in and let go of
## what has gone out. What it asked: {take: [ids], release: [ids]}.
func poll() -> Dictionary:
	var me: PackedByteArray = identity if not identity.is_empty() else SpaceTimeSync.local_identity
	var driven: Dictionary[int, bool] = {}
	for r: RefCounted in _rows(&"npc_driver"):
		if int(r.get(&"world_id")) == world_id:
			driven[int(r.get(&"entity_id"))] = (r.get(&"driver") as PackedByteArray) == me
	# The module's word first: what it says is ours, we run; what it no longer says is, we stop.
	for eid: int in _letting_go.keys():
		if not driven.get(eid, false):
			_letting_go.erase(eid)   # the module heard
	for eid: int in driven:
		if driven[eid] and not _mine.has(eid) and not _letting_go.has(eid):
			_start(eid)
	for eid: int in _mine.keys():
		if not driven.get(eid, false):
			_stop(eid)
	var people: Dictionary[int, bool] = {}
	for p: RefCounted in _rows(&"player"):
		people[int(p.get(&"entity_id"))] = true
	var npcs: Dictionary[int, bool] = {}
	for b: RefCounted in _rows(&"npc_brain"):
		npcs[int(b.get(&"entity_id"))] = true
	for b: RefCounted in _rows(&"body_state"):
		npcs[int(b.get(&"entity_id"))] = true
	var seen: Array[Dictionary] = []
	for m: RefCounted in _rows(&"movement_state"):
		var eid: int = int(m.get(&"entity_id"))
		if int(m.get(&"world_id")) != world_id or people.has(eid) or not npcs.has(eid):
			continue
		var pos: Vector3 = m.get(&"pos") as Vector3
		if _letting_go.has(eid) and region.runs(pos, true):
			_letting_go.erase(eid)   # back in before the module heard: ours to run again
			_start(eid)
		seen.append({"id": eid, "pos": pos, "mine": bool(driven.get(eid, false))})
	var ask: Dictionary = decide(seen, region)
	var release: Array[int] = []
	release.assign(ask["release"])
	for eid: int in release:
		_stop(eid)   # at once: the next referee waits for the module to hear it
		_letting_go[eid] = true
	var take: Array[int] = []
	take.assign(ask["take"])
	if send and not (take.is_empty() and release.is_empty()):
		taken += take.size()
		let_go += release.size()
		SpaceTimeSync.call_reducer(&"drive_npcs", [world_id, take, release], ["u32", "u64", "u64"])
	return ask


## What to take and let go of, from what it sees: [{id, pos, mine}]. Takes what stands in its cells and is
## not its own; lets go of its own that are `hand_on_m` past its edge. (Whether a take is granted is the
## module's: another referee's NPC is not.)
static func decide(seen: Array[Dictionary], r: RefereeRegion) -> Dictionary:
	var take: Array[int] = []
	var release: Array[int] = []
	for s: Dictionary in seen:
		var mine: bool = bool(s["mine"])
		var pos: Vector3 = s["pos"] as Vector3
		if not mine and r.runs(pos, false):
			take.append(int(s["id"]))
		elif mine and not r.runs(pos, true):
			release.append(int(s["id"]))
	take.sort()
	release.sort()
	return {"take": take, "release": release}


func _start(eid: int) -> void:
	_mine[eid] = true
	if on_mine.is_valid():
		on_mine.call(eid)


func _stop(eid: int) -> void:
	if not _mine.has(eid):
		return
	_mine.erase(eid)
	if on_not_mine.is_valid():
		on_not_mine.call(eid)


func _rows(table: StringName) -> Array:
	if rows_of.is_valid():
		return rows_of.call(table) as Array
	return SpaceTimeSync.find_rows(table, func(_r: RefCounted) -> bool: return true)
