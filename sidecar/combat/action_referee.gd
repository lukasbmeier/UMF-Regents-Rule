class_name ActionReferee extends Node3D
## THE WORLD'S REFEREE (FOUNDATION_SYSTEMS milestone 5, OPEN_ITEMS A1, DECISIONS #226): judges every
## ability its content marks `judged` as it lands, against the level's walls and everyone where its
## user saw them, and tells the module (`resolve_action`).
##
##   1. every `movement_state` row of the world goes into that entity's history (`TransformHistory`):
##      where it was, as the server stamped it
##   2. an `action_request` row is a use waiting for its landing time (`due_at`, the user's wind-up
##      after the use)
##   3. a little after it lands (`SETTLE_USEC`, so the user's own row from that moment is here), it is
##      judged: the user where it was then, everyone else where they were `rewind_ms` earlier (what
##      the user saw: its view delay, capped by `foundation.rewind_max_ms`, favouring the attacker), the
##      ability's sweep (`LungeJudge`) against the level
##
## Walls entities put up (DECISIONS #229: a shut gate) are in its space as they are now, built from
## their characters' `blocker_size` (`EntityBlocker`), so a pounce through a shut gate stops at it.
##
## Who can be hit: people (a player, an NPC person, any playable character), not a nest or a prop;
## and only in a status that is targetable and hittable (a downed hen is not hit again). The module
## checks the same again: this only proposes.
##
## SERVER-ONLY (hard rule 7b).

## How long after a use lands it is judged: the user's own row from that moment has to have come.
const SETTLE_USEC: int = 80_000
## The tables it reads.
const TABLES: Array[StringName] = [&"movement_state", &"action_request", &"entity", &"status_state", &"player", &"ability_def"]

var world_id: int = 0
## Off in tests: judged, not sent.
var send: bool = true

## Judged so far, and how: [{request_id, hit_id, reach, rewind_ms}], newest last (the last 32).
var judged: Array[Dictionary] = []

var _histories: Dictionary[int, TransformHistory] = {}
var _kinds: Dictionary[int, int] = {}
var _statuses: Dictionary[int, int] = {}
var _offline: Dictionary[int, bool] = {}
var _players: Dictionary[int, bool] = {}
## request id -> {actor_id, ability_id, rewind_ms, due_usec}
var _pending: Dictionary[int, Dictionary] = {}
var _defs_by_kind: Dictionary[int, EntityDefinition] = {}
var _hitboxes: Dictionary[int, Dictionary] = {}
## ability id -> {reach, radius, height}: its sweep, from its `ability_def` row (or `set_sweep`).
var _sweeps: Dictionary[int, Dictionary] = {}
## entity id -> the wall it puts up, here (DECISIONS #229).
var _walls: Dictionary[int, EntityBlocker] = {}


func _ready() -> void:
	if not SpaceTimeSync.row_event.is_connected(on_row):
		SpaceTimeSync.row_event.connect(on_row)


## The characters it knows (each one's hitbox is its scene's collision shape).
func know(defn: EntityDefinition) -> void:
	if defn != null:
		_defs_by_kind[defn.kind] = defn


func pending_count() -> int:
	return _pending.size()


func history(entity_id: int) -> TransformHistory:
	return _histories.get(entity_id, null)


# --- the rows -------------------------------------------------------------------------------

func on_row(ev: RowEvent) -> void:
	if not TABLES.has(ev.table):
		return
	var row: RefCounted = ev.current()
	if row == null:
		return
	var eid: int = int(row.get(&"entity_id")) if row.get(&"entity_id") != null else -1
	match ev.table:
		&"ability_def":
			_sweeps.erase(int(row.get(&"ability_id")))   # read again, as it is now
		&"movement_state":
			if int(row.get(&"world_id")) != world_id:
				return
			if ev.kind == RowEvent.Kind.DELETED:
				_histories.erase(eid)
				_drop_wall(eid)
				return
			record(eid, int(row.get(&"server_ts")), row.get(&"pos") as Vector3, float(row.get(&"yaw")))
		&"action_request":
			if int(row.get(&"world_id")) != world_id:
				return
			var rid: int = int(row.get(&"id"))
			if ev.kind == RowEvent.Kind.DELETED:
				_pending.erase(rid)
				return
			_pending[rid] = {"actor_id": int(row.get(&"actor_id")), "ability_id": int(row.get(&"ability_id")),
				"rewind_ms": int(row.get(&"rewind_ms")), "due_usec": int(row.get(&"due_at"))}
		&"entity":
			if ev.kind == RowEvent.Kind.DELETED:
				_kinds.erase(eid)
				_histories.erase(eid)
				_drop_wall(eid)
			else:
				_kinds[eid] = int(row.get(&"kind"))
				_place_wall(eid)
		&"status_state":
			if ev.kind == RowEvent.Kind.DELETED:
				_statuses.erase(eid)
			else:
				_statuses[eid] = int(row.get(&"status"))
			_place_wall(eid)
		&"player":
			if ev.kind == RowEvent.Kind.DELETED:
				_players.erase(eid)
				_offline.erase(eid)
			else:
				_players[eid] = true
				_offline[eid] = not bool(row.get(&"online"))


## Where `entity_id` was at server time `ts_usec` (its movement row).
func record(entity_id: int, ts_usec: int, pos: Vector3, yaw: float) -> void:
	var h: TransformHistory = _histories.get(entity_id, null)
	if h == null:
		h = TransformHistory.new()
		_histories[entity_id] = h
	h.push(ts_usec, pos, yaw)
	if _walls.has(entity_id) or _wall_kind(entity_id):
		_place_wall(entity_id)


## What it knows of an entity, set directly (tests; and a sidecar that already has it).
func set_entity(entity_id: int, kind: int, status: int = 0, player: bool = false, online: bool = true) -> void:
	_kinds[entity_id] = kind
	_statuses[entity_id] = status
	if player:
		_players[entity_id] = true
		_offline[entity_id] = not online
	_place_wall(entity_id)


# --- walls entities put up (DECISIONS #229) ------------------------------------------------

## The wall entity `entity_id` puts up here, if its character has one (null: none, or not yet placed).
func wall_of(entity_id: int) -> EntityBlocker:
	return _walls.get(entity_id, null)


func _wall_kind(entity_id: int) -> bool:
	var defn: EntityDefinition = _defs_by_kind.get(int(_kinds.get(entity_id, -1)), null)
	return defn != null and defn.has_blocker()


## Its wall where the entity stands now (its newest row), up or down as its status says.
func _place_wall(entity_id: int) -> void:
	if not _wall_kind(entity_id):
		_drop_wall(entity_id)
		return
	var h: TransformHistory = _histories.get(entity_id, null)
	if h == null or h.is_empty():
		return
	var wall: EntityBlocker = _walls.get(entity_id, null)
	if wall == null:
		wall = EntityBlocker.make(_defs_by_kind[int(_kinds[entity_id])], entity_id)
		add_child(wall)
		_walls[entity_id] = wall
	var at: Dictionary = h.at(h.newest_usec())
	wall.global_transform = Transform3D(Basis(Vector3.UP, float(at["yaw"])), at["pos"] as Vector3)
	wall.follow_status(int(_statuses.get(entity_id, StatusDef.NORMAL)))


func _drop_wall(entity_id: int) -> void:
	var wall: EntityBlocker = _walls.get(entity_id, null)
	if wall != null:
		_walls.erase(entity_id)
		wall.queue_free()


func add_request(request_id: int, actor_id: int, ability_id: int, rewind_ms: int, due_usec: int) -> void:
	_pending[request_id] = {"actor_id": actor_id, "ability_id": ability_id, "rewind_ms": rewind_ms, "due_usec": due_usec}


# --- judging --------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _pending.is_empty() or not ClockSync.has_sync():
		return
	settle(ClockSync.server_usec())


## Judge every request that landed at least `SETTLE_USEC` before `now_usec`. What it decided, newest last.
func settle(now_usec: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid: int in _pending.keys():
		var req: Dictionary = _pending[rid]
		if int(req["due_usec"]) + SETTLE_USEC > now_usec:
			continue
		_pending.erase(rid)
		var verdict: Dictionary = judge(rid, req)
		out.append(verdict)
		judged.append(verdict)
		if judged.size() > 32:
			judged.pop_front()
		print("[Referee] request %d (ability %d by %d): %s, the sweep %.2f m, others %d ms back"
			% [rid, int(req["ability_id"]), int(req["actor_id"]),
			("hit %d" % int(verdict["hit_id"])) if int(verdict["hit_id"]) != 0 else "missed",
			float(verdict["reach"]), int(verdict["rewind_ms"])])
		if send:
			SpaceTimeSync.call_reducer(&"resolve_action", [rid, int(verdict["hit_id"])], ["u64", "u64"])
	return out


## One request: {request_id, hit_id, reach, rewind_ms}.
func judge(rid: int, req: Dictionary) -> Dictionary:
	var verdict: Dictionary = {"request_id": rid, "hit_id": 0, "reach": 0.0, "rewind_ms": int(req["rewind_ms"])}
	var actor: int = int(req["actor_id"])
	var sweep: Dictionary = sweep_of(int(req["ability_id"]))
	var mine: TransformHistory = _histories.get(actor, null)
	if sweep.is_empty() or mine == null or mine.is_empty():
		push_warning("[Referee] request %d: %s" % [rid, "its ability is not judged" if sweep.is_empty() else "its user has no position"])
		return verdict
	var due: int = int(req["due_usec"])
	var me: Dictionary = mine.at(due)
	var seen_at: int = due - int(req["rewind_ms"]) * 1000
	var targets: Array = []
	for eid: int in _histories.keys():
		if eid == actor or not may_be_hit(eid):
			continue
		var was: Dictionary = (_histories[eid] as TransformHistory).at(seen_at)
		if was.is_empty():
			continue
		var box: Dictionary = hitbox(_kinds.get(eid, 0))
		targets.append({"id": eid, "pos": was["pos"], "radius": box["radius"], "height": box["height"], "center_y": box["center_y"]})
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	var r: Dictionary = LungeJudge.judge(space, me["pos"], float(me["yaw"]), float(sweep["reach"]), float(sweep["radius"]),
		float(sweep["height"]), targets, LungeJudge.LEVEL_MASK, _bodies())
	verdict["hit_id"] = int(r["hit_id"])
	verdict["reach"] = float(r["reach"])
	return verdict


## Someone it may hit: a person (a player, kinds 0 and 1, a playable character) who is here, in a
## status that is targetable and hittable.
func may_be_hit(eid: int) -> bool:
	if not _kinds.has(eid):
		return false
	var kind: int = _kinds[eid]
	var defn: EntityDefinition = _defs_by_kind.get(kind, null)
	var person: bool = kind <= 1 or _players.has(eid) or (defn != null and defn.playable)
	if not person or bool(_offline.get(eid, false)):
		return false
	var st: StatusDef = StatusDef.find(int(_statuses.get(eid, StatusDef.NORMAL)))
	return st == null or (st.targetable and st.hittable)


## A kind's hitbox: its body (`EntityDefinition.body_capsule`, the scene's capsule resized by the
## character's `collision_radius`/`collision_height`, standing on the ground), as {radius, height,
## center_y above the feet}. A kind it does not know: a person-sized capsule.
func hitbox(kind: int) -> Dictionary:
	if _hitboxes.has(kind):
		return _hitboxes[kind]
	var box: Dictionary = {"radius": 0.4, "height": 1.8, "center_y": 0.9}
	var defn: EntityDefinition = _defs_by_kind.get(kind, null)
	var cap: CapsuleShape3D = defn.body_capsule() if defn != null else null
	if cap != null:
		box = {"radius": cap.radius, "height": cap.height, "center_y": cap.height * 0.5}
	_hitboxes[kind] = box
	return box


## An ability's sweep, set directly (tests).
func set_sweep(ability_id: int, reach: float, radius: float, height: float) -> void:
	_sweeps[ability_id] = {"reach": reach, "radius": radius, "height": height}


## An ability's sweep: its `ability_def` row's data (the bake writes `judged`, `reach`, `radius`,
## `height` there, from the ability's content). Empty when it is not judged.
func sweep_of(ability_id: int) -> Dictionary:
	if _sweeps.has(ability_id):
		return _sweeps[ability_id]
	var row: RefCounted = SpaceTimeSync.get_row(&"ability_def", ability_id)
	if row == null:
		return {}
	var data: Variant = JSON.parse_string(String(row.get(&"data")))
	if not (data is Dictionary) or not bool((data as Dictionary).get("judged", false)):
		return {}
	var d: Dictionary = data
	var sweep: Dictionary = {"reach": float(d.get("reach", 0.0)), "radius": float(d.get("radius", 0.35)), "height": float(d.get("height", 0.6))}
	_sweeps[ability_id] = sweep
	return sweep


## The bodies a sidecar that also moves everyone has in its space: not walls.
func _bodies() -> Array[RID]:
	var out: Array[RID] = []
	for n: Node in EntitySpawner.entity_nodes():
		var b: CollisionObject3D = n as CollisionObject3D
		if b != null:
			out.append(b.get_rid())
	return out
