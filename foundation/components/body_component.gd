class_name BodyComponent extends SpaceTimeComponent
## A BODY, ON SCREEN (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246): something thrown that the
## world's referee flies. Its place is its `movement_state` (the movement component interpolates it
## as it does anyone's); this draws its look (its `BodyDef`'s), its turn (from `body_state`, at the
## very moment its place is drawn: `get_render_seq`) and, for whoever threw it, their own flight.
##
## THE THROWER'S FLIGHT: the thrower's game started flying it on the click (`BodyLaunch`). When this
## body's rows come, this takes that flight over and draws it instead of the rows; each row (the
## referee at frame N) is compared with the flight at frame N, and the flight is moved toward it: a
## share of the gap each row (`foundation.body_correct_share`), all of it past `foundation.body_snap_m`.
## At rest it glides to where the referee put it and is the rows' from then on.

const STATE_TABLE: StringName = &"body_state"
const MOVE_TABLE: StringName = &"movement_state"
## How long the thrower's flight glides to the referee's resting place.
const SETTLE_GLIDE_S: float = 0.3
## How far past its newest row a body is guessed ahead (its movement component's 100 ms is a person's): a
## body bounces off walls, and a guess with the old velocity draws it in the wall, then back out.
const GUESS_AHEAD_USEC: int = 25_000

var def: BodyDef = null
var def_id: int = -1
var owner_id: int = 0
var launch_id: int = 0
var at_rest: bool = false

## frame -> Quaternion, the newest few rows' turns.
var _turns: Dictionary[int, Quaternion] = {}
var _visual: Node3D = null
var _model: Node3D = null
## The thrower's own flight, while it is drawn.
var _flight: FlyingBody = null
var _glide_from: Transform3D = Transform3D.IDENTITY
var _glide_s: float = -1.0
## Rows compared with the thrower's flight, and the last gap (m): for tests and the debug overlay.
var corrections: int = 0
var snaps: int = 0
var last_gap: float = 0.0


func required_tables() -> Array[StringName]:
	return [STATE_TABLE, MOVE_TABLE]


## Its movement row is the movement component's to wait for; this only listens to it.
func optional_tables() -> Array[StringName]:
	return [MOVE_TABLE]


## The thrower's own flight, while it is drawn (null: the rows are).
func flight() -> FlyingBody:
	return _flight


func _on_bound() -> void:
	_visual = entity.get_node_or_null(^"Visual") as Node3D
	_build_look()
	var mover: SpaceTimeMovementComponent = entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if mover != null:
		mover.max_extrapolation_usec = GUESS_AHEAD_USEC
		mover.timeline_by_server_ts = true
	if owner_id != 0 and owner_id == EntityRegistry.local_entity_id and not at_rest:
		_flight = BodyLaunch.take(launch_id)
		if _flight != null:
			_flight.tree_exiting.connect(func() -> void: _flight = null)
			var drawn: Node3D = _flight.get_node_or_null(^"Visual") as Node3D
			if drawn != null:
				drawn.visible = false   # this body's own look draws it from now
	_set_process_for_body()


func _build_look() -> void:
	if def == null or _visual == null or _model != null:
		return
	var placeholder: Node = _visual.get_node_or_null(^"Model")
	if placeholder != null:
		_visual.remove_child(placeholder)
		placeholder.queue_free()
	_model = def.make_visual()
	_model.name = "Model"
	_visual.add_child(_model)


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if new == null:
		return
	if table == STATE_TABLE:
		_on_state(new)
	elif table == MOVE_TABLE and _flight != null:
		_compare(new)


func _on_state(row: RefCounted) -> void:
	var first: bool = def_id < 0
	def_id = int(row.get(&"def_id"))
	owner_id = int(row.get(&"owner_id"))
	launch_id = int(row.get(&"launch_id"))
	if first or def == null:
		def = BodyDef.by_id(def_id)
		if is_bound():
			_build_look()
	var f: int = int(row.get(&"frames"))
	_turns[f] = Quaternion(FlyingBody.basis_of(row.get(&"rot") as Vector3))
	if _turns.size() > 16:
		_turns.erase(_turns.keys().min())
	var was: bool = at_rest
	at_rest = bool(row.get(&"at_rest"))
	if at_rest and not was and _flight != null:
		_settle()


## The referee's row at its frame N against the thrower's flight at N: nearer by a share, or put there.
func _compare(row: RefCounted) -> void:
	var n: int = int(row.get(&"last_processed_seq"))
	var mine: Array = _flight.state_at(n)
	if mine.is_empty():
		return
	var pos: Vector3 = row.get(&"pos") as Vector3
	var vel: Vector3 = row.get(&"vel") as Vector3
	var dpos: Vector3 = pos - (mine[0] as Vector3)
	var dvel: Vector3 = vel - (mine[1] as Vector3)
	last_gap = dpos.length()
	corrections += 1
	if last_gap >= HotRules.number(&"foundation.body_snap_m"):
		snaps += 1
		_flight.shift(dpos, dvel)
	else:
		var k: float = clampf(HotRules.number(&"foundation.body_correct_share"), 0.0, 1.0)
		_flight.shift(dpos * k, dvel * k)


## At rest on the referee's word: the flight's drawing glides to the rows' and the flight goes.
func _settle() -> void:
	_glide_from = _flight.get_global_transform_interpolated()
	_glide_s = 0.0
	_flight.queue_free()
	_flight = null
	_follow_by_frame(true)


func _set_process_for_body() -> void:
	process_priority = 10            # after the movement component has placed the body this frame
	process_physics_priority = 10
	set_process(true)
	set_physics_process(true)
	_follow_by_frame(_flight != null)


## The thrower's flight and the settle glide are drawn every rendered frame from their own smooth
## transform, so the body's look leaves physics interpolation while they are; the rows' turn is set in
## the physics tick with it on.
func _follow_by_frame(on: bool) -> void:
	if _visual == null:
		return
	var mode: Node.PhysicsInterpolationMode = Node.PHYSICS_INTERPOLATION_MODE_OFF if on else Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if _visual.physics_interpolation_mode != mode:
		_visual.physics_interpolation_mode = mode
		if not on and _visual.is_inside_tree():
			_visual.reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if _visual == null or not is_bound() or _flight != null or _glide_s >= 0.0:
		return
	var mover: SpaceTimeMovementComponent = entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_visual.global_basis = Basis(_turn_at(mover.get_render_seq() if mover != null else -1.0))


func _process(delta: float) -> void:
	if _visual == null:
		return
	if _flight != null and is_instance_valid(_flight):
		_visual.global_transform = _flight.get_global_transform_interpolated()
		return
	if _glide_s < 0.0:
		return
	var mover: SpaceTimeMovementComponent = entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var target := Transform3D(Basis(_turn_at(mover.get_render_seq() if mover != null else -1.0)),
		(entity as Node3D).global_position)
	_glide_s += delta
	var w: float = clampf(_glide_s / SETTLE_GLIDE_S, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	_visual.global_transform = _glide_from.interpolate_with(target, w)
	if w >= 1.0:
		_glide_s = -1.0
		_follow_by_frame(false)


## Its turn at frame `seq` (fractional), from the rows' turns either side of it.
func _turn_at(seq: float) -> Quaternion:
	if _turns.is_empty():
		return Quaternion.IDENTITY
	var keys: Array = _turns.keys()
	keys.sort()
	if seq < 0.0 or seq >= float(keys.back()):
		return _turns[keys.back()]
	if seq <= float(keys.front()):
		return _turns[keys.front()]
	for i: int in range(keys.size() - 1):
		var a: int = keys[i]
		var b: int = keys[i + 1]
		if seq >= float(a) and seq <= float(b):
			var f: float = (seq - float(a)) / float(maxi(b - a, 1))
			return (_turns[a] as Quaternion).slerp(_turns[b] as Quaternion, f)
	return _turns[keys.back()]


## Its flight goes with it, when it goes: not when it only moves (a level change reparents every entity).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _flight != null and is_instance_valid(_flight):
		_flight.queue_free()
		_flight = null
