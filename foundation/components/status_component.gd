class_name StatusComponent extends SpaceTimeComponent
## WHICH STATUS THIS ENTITY IS IN (docs/FOUNDATION_SYSTEMS.md milestone 2, DECISIONS #206), from
## its `status_state` row (none: normal), and everything that follows from it on this client:
##
##   movement   the entity's movement component steps by `movement_config()` and `filter_input()`:
##              a downed player crawls, cannot jump or sprint. Its own player predicts it, the
##              sidecar simulates it, the module bounds it, all from the same `StatusDef`.
##   the body   hidden (`hide_body`: out, escaped), holding the status's pose (`status.downed`)
##   the tag    over its head (`show_on_nameplate`), in the status's colour
##   the view   its own player watches a teammate while in a `spectate` status; Jump picks the next
##
## The server decides every status (`set_status`, a genre's rules, the timers). This only shows it
## and moves by it (hard rule 11). Every entity has one: `SpaceTimeEntity` adds it when its scene
## does not, so a genre's own entity scenes get statuses too.

## The status changed (`from` -> `to`, numbers), or the same one was set again (`from == to`).
signal status_changed(from: int, to: int)

const TABLE: StringName = &"status_state"

var _status: int = StatusDef.NORMAL
var _def: StatusDef = null
var _since_usec: int = 0
var _lasts_ms: int = 0
var _by_entity: int = 0
var _data: String = ""
var _serial: int = -1
## Movement configs already worked out for this status: [base, bursting] -> config.
var _cfg_cache: Dictionary = {}
var _cfg_cache_serial: int = -2

# Presentation state
var _holding_pose: bool = false
var _spectating: SpaceTimeEntity = null
var _rig: CameraRig = null


func required_tables() -> Array[StringName]:
	return [TABLE]


## No row: normal. Nobody waits for one (DECISIONS #69).
func optional_tables() -> Array[StringName]:
	return [TABLE]


func also_reads() -> Array[StringName]:
	return [&"lobby_member"]


# --- read API ------------------------------------------------------------------------------------

## Its status's number.
func status() -> int:
	return _status


## Its status (normal for one this build does not know, from a newer server's genre).
func def() -> StatusDef:
	if _def == null:
		_def = StatusDef.find(_status)
		if _def == null:
			_def = StatusDef.normal()
	return _def


## Seconds since it changed (by the server's clock).
func elapsed_sec() -> float:
	if _since_usec <= 0:
		return INF
	return float(ClockSync.server_usec() - _since_usec) / 1_000_000.0


## Seconds until it ends on its own, or INF when it does not.
func seconds_left() -> float:
	if _lasts_ms <= 0:
		return INF
	return maxf(0.0, float(_lasts_ms) / 1000.0 - elapsed_sec())


## Who put it in its status (0: nobody), and the genre's words about it.
func by_entity() -> int:
	return _by_entity


func data() -> String:
	return _data


## The entity it is watching instead of itself (a spectate status), or null.
func spectating() -> SpaceTimeEntity:
	return _spectating if is_instance_valid(_spectating) else null


# --- movement --------------------------------------------------------------------------------

## The movement config to step by in this status: `base` with the status applied (`StatusDef.apply_to`),
## the burst included while it lasts. The same object frame after frame while nothing changes.
func movement_config(base: MovementConfig) -> MovementConfig:
	var d: StatusDef = def()
	if d.moves_as_usual():
		return base
	if _cfg_cache_serial != _serial:
		_cfg_cache.clear()
		_cfg_cache_serial = _serial
	var bursting: bool = d.bursting_at(elapsed_sec())
	var key: Array = [base.get_instance_id(), bursting]
	var c: MovementConfig = _cfg_cache.get(key) as MovementConfig
	if c == null:
		c = d.apply_to(base, bursting)
		_cfg_cache[key] = c
	return c


## The input to step by in this status: presses it cannot act on taken out (`StatusDef.filter_input`).
func filter_input(frame: InputFrame) -> InputFrame:
	return def().filter_input(frame)


# --- rows ------------------------------------------------------------------------------------

func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	var from: int = _status
	var was_serial: int = _serial
	if new == null:
		_status = StatusDef.NORMAL
		_since_usec = 0
		_lasts_ms = 0
		_by_entity = 0
		_data = ""
		_serial = -1
	else:
		_status = int(new.get(&"status"))
		_since_usec = int(new.get(&"since"))
		_lasts_ms = int(new.get(&"lasts_ms"))
		_by_entity = int(new.get(&"by_entity"))
		_data = String(new.get(&"data"))
		_serial = int(new.get(&"serial"))
	if _serial == was_serial and from == _status:
		return
	_def = null
	_apply_presentation()
	if is_bound():
		print("[Status] entity %d: %s -> %s" % [entity_id, _name_of(from), def().display_name])
		status_changed.emit(from, _status)
		SignalBus.entity_status_changed.emit(entity_id, from, _status)
		if is_local_authority and from != _status:
			_tell_player(from)


func _on_bound() -> void:
	# The movement component steps by us (see its `status_source`).
	var mover: SpaceTimeMovementComponent = _sibling(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if mover != null:
		mover.status_source = self
	_apply_presentation()


static func _name_of(n: int) -> String:
	var d: StatusDef = StatusDef.find(n)
	return d.display_name if d != null else "status %d" % n


## The player's own change, in the notices (`Notices`): "You are downed".
func _tell_player(from: int) -> void:
	var d: StatusDef = def()
	if _status == StatusDef.NORMAL:
		SignalBus.notification_requested.emit("You are no longer %s" % _name_of(from).to_lower(), 0)
	else:
		SignalBus.notification_requested.emit("You are %s" % d.display_name.to_lower(), 1)


# --- presentation ------------------------------------------------------------------------------

func _apply_presentation() -> void:
	var d: StatusDef = def()
	_set_hidden(d.hide_body)
	var plate: NameplateComponent = _sibling(NameplateComponent) as NameplateComponent
	if plate != null:
		if d.show_on_nameplate and _status != StatusDef.NORMAL:
			plate.set_tag(d.display_name, d.color)
		else:
			plate.set_tag("", Color.WHITE)
	if is_local_authority and not d.spectate and _spectating != null:
		_watch(null)


func _process(_delta: float) -> void:
	if not is_bound():
		return
	var d: StatusDef = def()
	# The pose is held every frame it applies (hard rule 11: the driver asks nothing of us), and let
	# go once when the status no longer has one.
	var anim: AnimationDriverComponent = _sibling(AnimationDriverComponent) as AnimationDriverComponent
	if anim != null:
		if not d.pose.is_empty():
			anim.hold_pose(d.pose, 1.0, -1.0, true)
			_holding_pose = true
		elif _holding_pose:
			anim.release_pose()
			_holding_pose = false
	if is_local_authority and d.spectate:
		_keep_spectating()


func _set_hidden(hide: bool) -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null:
		ent.set_hidden_by(&"status", hide)


func _sibling(type: Script) -> SpaceTimeComponent:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	return ent.find_component(type) if ent != null else null


# --- spectating --------------------------------------------------------------------------------

## Who this player may watch: other players here, connected, on its team (the lobby's; everyone
## when there are none), and not watching someone themselves. By entity id.
func spectate_candidates() -> Array[int]:
	var mine: int = _team_of(entity_id)
	var out: Array[int] = []
	for eid: int in EntityRegistry.all_entity_ids():
		if eid == entity_id:
			continue
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(eid) as SpaceTimeEntity
		if ent == null or not ent.is_bound():
			continue
		var plate: NameplateComponent = ent.find_component(NameplateComponent) as NameplateComponent
		if plate == null or not plate.is_online():
			continue
		var st: StatusComponent = ent.find_component(StatusComponent) as StatusComponent
		if st != null and st.def().spectate:
			continue
		if _team_of(eid) != mine:
			continue
		out.append(eid)
	out.sort()
	return out


## Watch the next one (Jump, while spectating).
func spectate_next() -> void:
	var c: Array[int] = spectate_candidates()
	if c.is_empty():
		_watch(null)
		return
	var at: int = c.find(_spectating.entity_id) if spectating() != null else -1
	_watch(EntityRegistry.get_entity(c[(at + 1) % c.size()]) as SpaceTimeEntity)


func _keep_spectating() -> void:
	if Input.is_action_just_pressed(LocalInputComponent.ACTION_JUMP):
		spectate_next()
		return
	var now: SpaceTimeEntity = spectating()
	if now == null or not spectate_candidates().has(now.entity_id):
		spectate_next()


func _watch(target: SpaceTimeEntity) -> void:
	if _rig == null:
		var ent: SpaceTimeEntity = entity as SpaceTimeEntity
		_rig = ent.get_node_or_null(^"CameraRig") as CameraRig if ent != null else null
	_spectating = target
	if _rig != null:
		_rig.follow(target)
	if target != null:
		print("[Status] entity %d watches %d" % [entity_id, target.entity_id])


static func _team_of(eid: int) -> int:
	var row: RefCounted = SpaceTimeSync.get_row(&"lobby_member", eid)
	return int(row.get(&"team")) if row != null else 0
