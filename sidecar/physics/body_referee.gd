class_name BodyReferee extends Node3D
## THE WORLD'S BODIES, FLOWN (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246): every thrown thing in
## its world (an entity of kind 3 with a `body_state` row) is a `FlyingBody` here, against the level
## this sidecar loaded, the other bodies, and a stand-in for each person (a capsule where their newest
## row puts them: players move themselves, so this only follows them). It is the one place bodies move,
## whether the sidecar also moves everyone (a SIDECAR world) or only referees (`--referee`).
##
##   each server tick   one `write_body_batch`: every body that moved (its place, speed, turn, spin, at
##                      rest, and its frames since launch, which every client's timeline runs on)
##   a hit              faster than its def's contact speed: `report_body_contacts` (what it hit: a
##                      person or a body by entity id, 0 for the level)
##   the server moves   a body (a teleport row not its own echo: `place_entity`): taken from the row
##
## SERVER-ONLY (hard rule 7b).

const TABLES: Array[StringName] = [&"body_state", &"movement_state", &"entity", &"player", &"status_state", &"npc_brain"]
## A body's write echoed back puts it where it already is; a teleport row further than this is the
## server moving it.
const ADOPT_M: float = 0.05
## A body passes through the one who threw it this long (frames): it leaves their hand inside their own
## stand-in, and would be thrown off it. After that it may hit them (a ball bounced back).
const CLEAR_OWNER_FRAMES: int = 30

var world_id: int = 0
## Off in tests: gathered, not sent.
var send: bool = true
@export var tick_hz: float = 20.0

## entity id -> FlyingBody
var _bodies: Dictionary[int, FlyingBody] = {}
## entity id -> AnimatableBody3D: the people, as bodies meet them.
var _proxies: Dictionary[int, AnimatableBody3D] = {}
var _kinds: Dictionary[int, int] = {}
var _players: Dictionary[int, bool] = {}
var _offline: Dictionary[int, bool] = {}
var _brained: Dictionary[int, bool] = {}
var _statuses: Dictionary[int, int] = {}
var _defs_by_kind: Dictionary[int, EntityDefinition] = {}
## body entity id -> its thrower's entity id, while it is still clearing their hand.
var _clearing: Dictionary[int, int] = {}
## entity id -> the at-rest flag last written (what a body at rest no longer needs to say again).
var _written_rest: Dictionary[int, bool] = {}
var _owed: Dictionary[int, bool] = {}
var _contacts: Array[Dictionary] = []
var _accum: float = 0.0
## Sent so far (tests, the log).
var writes_sent: int = 0
var contacts_sent: int = 0


func _ready() -> void:
	if not SpaceTimeSync.row_event.is_connected(on_row):
		SpaceTimeSync.row_event.connect(on_row)


## The characters it knows (each one's stand-in is its body's capsule).
func know(defn: EntityDefinition) -> void:
	if defn != null:
		_defs_by_kind[defn.kind] = defn


func body(entity_id: int) -> FlyingBody:
	return _bodies.get(entity_id, null)


func proxy(entity_id: int) -> AnimatableBody3D:
	return _proxies.get(entity_id, null)


func body_count() -> int:
	return _bodies.size()


# --- the rows -----------------------------------------------------------------------------------

func on_row(ev: RowEvent) -> void:
	if not TABLES.has(ev.table):
		return
	var row: RefCounted = ev.current()
	if row == null:
		return
	var eid: int = int(row.get(&"entity_id")) if row.get(&"entity_id") != null else -1
	var gone: bool = ev.kind == RowEvent.Kind.DELETED
	match ev.table:
		&"body_state":
			if int(row.get(&"world_id")) != world_id:
				return
			if gone:
				_drop_body(eid)
			else:
				_follow_body(eid)
		&"movement_state":
			if int(row.get(&"world_id")) != world_id:
				if _proxies.has(eid):
					_drop_proxy(eid)   # gone to another world
				return
			if gone:
				_drop_proxy(eid)
				return
			if _bodies.has(eid):
				_body_row(eid, row)
			elif SpaceTimeSync.get_row(&"body_state", eid) != null:
				_follow_body(eid)
			else:
				_place_proxy(eid, row.get(&"pos") as Vector3)
		&"entity":
			if gone:
				_kinds.erase(eid)
				_drop_body(eid)
				_drop_proxy(eid)
			else:
				_kinds[eid] = int(row.get(&"kind"))
		&"player":
			if gone:
				_players.erase(eid)
				_offline.erase(eid)
			else:
				_players[eid] = true
				_offline[eid] = not bool(row.get(&"online"))
			_refresh_proxy(eid)
		&"status_state":
			if gone:
				_statuses.erase(eid)
			else:
				_statuses[eid] = int(row.get(&"status"))
			_refresh_proxy(eid)
		&"npc_brain":
			if gone:
				_brained.erase(eid)
			else:
				_brained[eid] = true


## What it knows of an entity, set directly (tests).
func set_entity(entity_id: int, kind: int, player: bool = false, online: bool = true) -> void:
	_kinds[entity_id] = kind
	if player:
		_players[entity_id] = true
		_offline[entity_id] = not online


# --- bodies -------------------------------------------------------------------------------------

## A body's rows are both here: fly it (once), from where they say it is.
func _follow_body(eid: int) -> void:
	if _bodies.has(eid):
		return
	var b_row: RefCounted = SpaceTimeSync.get_row(&"body_state", eid)
	var m_row: RefCounted = SpaceTimeSync.get_row(&"movement_state", eid)
	if b_row == null or m_row == null:
		return
	start_body(eid, int(b_row.get(&"def_id")), m_row.get(&"pos") as Vector3, m_row.get(&"vel") as Vector3,
		b_row.get(&"rot") as Vector3, b_row.get(&"spin") as Vector3, int(b_row.get(&"frames")), bool(b_row.get(&"at_rest")),
		int(b_row.get(&"owner_id")))


## Fly body `eid` (its def `def_id`) from this state. Public for tests. Null when the def is unknown.
func start_body(eid: int, def_id: int, pos: Vector3, vel: Vector3, rot: Vector3, spin: Vector3,
		frames: int = 0, rest: bool = false, owner_id: int = 0) -> FlyingBody:
	var def: BodyDef = BodyDef.by_id(def_id)
	if def == null:
		push_warning("[Bodies] entity %d is body %d, which this game has no BodyDef for: it does not fly" % [eid, def_id])
		return null
	var b: FlyingBody = FlyingBody.make(def)
	b.name = "Body%d" % eid
	b.set_meta(&"entity_id", eid)
	add_child(b)
	b.launch(pos, vel, rot, spin, frames)
	if rest:
		b.place(pos, Vector3.ZERO, rot, Vector3.ZERO, true)
	b.hit.connect(func(other: Object, at: Vector3, normal: Vector3, speed: float) -> void: _on_hit(eid, other, at, normal, speed))
	b.came_to_rest.connect(func() -> void: _owed[eid] = true)
	_bodies[eid] = b
	if owner_id != 0 and frames < CLEAR_OWNER_FRAMES:
		_clearing[eid] = owner_id
		_clear_owner(eid)
	_written_rest[eid] = rest
	_owed[eid] = not rest
	print("[Bodies] world %d: body %d (%s) %s" % [world_id, eid, def.display_name, "at rest" if rest else "in flight"])
	return b


## A movement row of a body we fly: our own write echoed (nothing to do), or the server moving it.
func _body_row(eid: int, row: RefCounted) -> void:
	if not bool(row.get(&"teleport_flag")):
		return
	var b: FlyingBody = _bodies[eid]
	var pos: Vector3 = row.get(&"pos") as Vector3
	if b.global_position.distance_to(pos) < ADOPT_M:
		return
	var b_row: RefCounted = SpaceTimeSync.get_row(&"body_state", eid)
	var rot: Vector3 = b_row.get(&"rot") as Vector3 if b_row != null else Vector3.ZERO
	b.place(pos, row.get(&"vel") as Vector3, rot, Vector3.ZERO, false)
	b.wake()
	_owed[eid] = true


## While a body clears its thrower's hand, it passes through their stand-in; then it no longer does.
func _clear_owner(eid: int) -> void:
	var b: FlyingBody = _bodies.get(eid, null)
	var owner: AnimatableBody3D = _proxies.get(int(_clearing.get(eid, 0)), null)
	if b == null:
		_clearing.erase(eid)
		return
	if b.frames >= CLEAR_OWNER_FRAMES:
		if owner != null:
			b.remove_collision_exception_with(owner)
		_clearing.erase(eid)
	elif owner != null:
		b.add_collision_exception_with(owner)


func _drop_body(eid: int) -> void:
	var b: FlyingBody = _bodies.get(eid, null)
	_clearing.erase(eid)
	_bodies.erase(eid)
	_written_rest.erase(eid)
	_owed.erase(eid)
	if b != null:
		b.queue_free()


func _on_hit(eid: int, other: Object, at: Vector3, normal: Vector3, speed: float) -> void:
	var b: FlyingBody = _bodies.get(eid, null)
	if b == null or b.def == null or speed < b.def.contact_speed_mps:
		return
	var other_id: int = 0
	if other is Node and (other as Node).has_meta(&"entity_id"):
		other_id = int((other as Node).get_meta(&"entity_id"))
	elif other is SpaceTimeEntity:
		other_id = (other as SpaceTimeEntity).entity_id
	_contacts.append({"body_id": eid, "other_id": other_id, "pos": at, "normal": normal, "speed": speed})
	if b.at_rest:
		b.wake()


# --- the people, as bodies meet them -------------------------------------------------------------

## Someone a body can hit: a person (a player, kinds 0 and 1, a playable character, anything a brain
## drives) who is here, in a status others can reach (not out, not hidden away).
func is_person(eid: int) -> bool:
	if not _kinds.has(eid):
		return false
	var kind: int = _kinds[eid]
	var defn: EntityDefinition = _defs_by_kind.get(kind, null)
	var person: bool = kind <= 1 or _players.has(eid) or _brained.has(eid) or (defn != null and defn.playable)
	if not person or bool(_offline.get(eid, false)):
		return false
	var st: StatusDef = StatusDef.find(int(_statuses.get(eid, StatusDef.NORMAL)))
	return st == null or st.targetable


func _place_proxy(eid: int, pos: Vector3) -> void:
	if not is_person(eid):
		_drop_proxy(eid)
		return
	var p: AnimatableBody3D = _proxies.get(eid, null)
	if p == null:
		p = _make_proxy(eid)
	p.global_position = pos


func _refresh_proxy(eid: int) -> void:
	var row: RefCounted = SpaceTimeSync.get_row(&"movement_state", eid)
	if row != null and int(row.get(&"world_id")) == world_id:
		_place_proxy(eid, row.get(&"pos") as Vector3)
	elif not is_person(eid):
		_drop_proxy(eid)


func _make_proxy(eid: int) -> AnimatableBody3D:
	var p := AnimatableBody3D.new()
	p.name = "Person%d" % eid
	p.set_meta(&"entity_id", eid)
	p.sync_to_physics = false
	p.collision_layer = FlyingBody.PROXY_LAYER
	p.collision_mask = 0
	var defn: EntityDefinition = _defs_by_kind.get(int(_kinds.get(eid, 0)), null)
	var cap: CapsuleShape3D = defn.body_capsule() if defn != null else null
	if cap == null:
		cap = CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	p.add_child(shape)
	add_child(p)
	_proxies[eid] = p
	return p


func _drop_proxy(eid: int) -> void:
	var p: AnimatableBody3D = _proxies.get(eid, null)
	_proxies.erase(eid)
	if p != null:
		p.queue_free()


# --- writing ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for eid: int in _clearing.keys():
		_clear_owner(eid)
	_accum += delta
	var period: float = 1.0 / maxf(tick_hz, 1.0)
	if _accum < period:
		return
	_accum = minf(_accum - period, period)
	flush()


## This tick's writes and contacts, sent (unless `send` is off). Returns {writes, contacts}.
func flush() -> Dictionary:
	var writes: Array[Dictionary] = []
	for eid: int in _bodies.keys():
		var b: FlyingBody = _bodies[eid]
		var moving: bool = not b.at_rest
		if not moving and not bool(_owed.get(eid, false)) and bool(_written_rest.get(eid, false)):
			continue
		writes.append({"entity_id": eid, "pos": b.global_position, "vel": b.linear_velocity if moving else Vector3.ZERO,
			"rot": b.rot_vector(), "spin": b.angular_velocity if moving else Vector3.ZERO, "at_rest": b.at_rest, "frames": b.frames})
		_written_rest[eid] = b.at_rest
		_owed[eid] = false
	var contacts: Array[Dictionary] = _contacts
	_contacts = []
	if send and SpaceTimeSync.is_connected_to_server():
		if not writes.is_empty():
			SpaceTimeSync.write_body_batch(world_id, writes)
		if not contacts.is_empty():
			SpaceTimeSync.report_body_contacts(world_id, contacts)
	writes_sent += writes.size()
	contacts_sent += contacts.size()
	return {"writes": writes, "contacts": contacts}
