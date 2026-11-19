class_name MotionPlayer extends Node
## PLAYS THE MOTION LAB'S MOVES IN THE GAME (PROGRESS 110): a fighter's `CombatComponent` makes one and tells it when an
## ability began on it (`began`, on every client: predicted here, or another's arriving) and when a hit landed on it
## (`hit_by`, from its health). An ability with a row in `AbilityMoves` plays its move on this fighter; a hit from one
## whose row has a `victim` move plays that, facing whoever struck.
##
## Presentation only (hard rule 11): what happens is the server's (the swing, the lunge's dash, the push and pull); the
## body is never carried here (`MotionLayer.carry` off), and the move's own height is left out (`lift_scale` 0): the
## server lifts a body itself.

## How long after its ability began a hit may still be its (ms).
const HIT_WINDOW_MS: int = 2500
## How far from a foe the figure stands for a waltz's cut (m), and the gap between two cuts (s).
const WALTZ_STAND_M: float = 1.1
const WALTZ_GAP_S: float = 0.07

var entity: SpaceTimeEntity = null
var layer: MotionLayer = null
var _movement: SpaceTimeMovementComponent = null
var _model: Node3D = null
## The last ability that began here and when (msec): a hit it lands is its.
var last_ability: int = 0
var last_ability_ms: int = -1
## How many moves it has played (tests).
var played: int = 0
## A waltz under way (its count; a new one cancels the old).
var _waltz: int = 0


## One on fighter `e`, its model at the driver's `model_path` (null when it has no model or skeleton yet).
static func make(e: SpaceTimeEntity, driver: AnimationDriverComponent) -> MotionPlayer:
	if e == null or driver == null:
		return null
	var model: Node3D = e.get_node_or_null(driver.model_path) as Node3D
	if model == null:
		return null
	var skel: Skeleton3D = _skeleton_in(model)
	if skel == null:
		return null
	var p := MotionPlayer.new()
	p.name = "MotionPlayer"
	p.entity = e
	p._model = model
	p._movement = e.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	e.add_child(p)
	p.layer = MotionLayer.attach(e, model, skel)
	p.layer.carry = false
	p.layer.lift_scale = 0.0
	var health: SpaceTimeHealthComponent = e.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	if health != null:
		health.damaged.connect(p.hit_by)
	return p


static func _skeleton_in(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var s: Skeleton3D = _skeleton_in(c)
		if s != null:
			return s
	return null


## Ability `ability_id` began on this fighter: its move, if it has one. True when one plays.
func began(ability_id: int) -> bool:
	last_ability = ability_id
	last_ability_ms = Time.get_ticks_msec()
	var row: AbilityMove = AbilityMoves.of(ability_id)
	if row == null or row.move == null or layer == null:
		return false
	_waltz += 1
	if row.waltz:
		_play_waltz(row, _waltz)
		return true
	layer.shift = Vector3.ZERO
	_play(row.move, facing(), ahead(row.ability.reach_m if row.ability != null else 2.0), row.from_s, row.speed)
	return true


## A hit landed on this fighter from `source_id`: the victim move of what struck it, if it began lately.
func hit_by(_amount: float, source_id: int) -> void:
	if layer == null or source_id <= 0:
		return
	var from: SpaceTimeEntity = EntityRegistry.get_entity(source_id) as SpaceTimeEntity
	var theirs: MotionPlayer = from.get_node_or_null(^"MotionPlayer") as MotionPlayer if from != null else null
	if theirs == null or theirs.last_ability_ms < 0 or Time.get_ticks_msec() - theirs.last_ability_ms > HIT_WINDOW_MS:
		return
	var row: AbilityMove = AbilityMoves.of(theirs.last_ability)
	if row == null or row.victim == null:
		return
	var me: Node3D = entity as Node3D
	var to: Vector3 = (from as Node3D).global_position - me.global_position
	_play(row.victim, Vector3(to.x, 0.0, to.z), Vector3.INF, 0.0, 1.0)


func _play(m: MotionMove, toward: Vector3, at: Vector3, from_s: float, speed: float) -> void:
	layer.speed = speed
	layer.play(m, toward, at)
	if from_s > 0.0:
		layer.t = minf(from_s, m.length_s * 0.95)
	played += 1


## The way this fighter faces (world, flat): its movement's yaw.
func facing() -> Vector3:
	var s: MovementState = null
	if _movement != null:
		s = _movement.get_predicted_state() if _movement.is_local_authority else _movement.get_render_state()
	var yaw: float = s.yaw if s != null else (entity as Node3D).global_rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## A point `m` ahead at the chest (a reach with no target of its own).
func ahead(m: float) -> Vector3:
	return (entity as Node3D).global_position + facing() * m + Vector3(0.0, 1.1, 0.0)


## The foes in reach in front (nearest first, at most `n`).
func foes_ahead(reach: float, n: int) -> Array[Node3D]:
	var me: Node3D = entity as Node3D
	var fwd: Vector3 = facing()
	var found: Array[Array] = []
	for id: int in EntityRegistry.all_entity_ids():
		if id == entity.entity_id:
			continue
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e == null or not is_instance_valid(e) or e.find_component(SkillingComponent) != null:
			continue   # players are never a waltz's (no duels yet)
		var h: SpaceTimeHealthComponent = e.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
		if h == null or h.is_dead():
			continue
		var to: Vector3 = (e as Node3D).global_position - me.global_position
		to.y = 0.0
		var d: float = to.length()
		if d < 0.01 or d > reach or rad_to_deg(fwd.angle_to(to / d)) > 75.0:
			continue
		found.append([d, e])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array[Node3D] = []
	for f: Array in found.slice(0, n):
		out.append(f[1] as Node3D)
	return out


## THE WALTZ, SHOWN: the figure gone and there at each foe in reach from a new side, a cut, and back to the body.
func _play_waltz(row: AbilityMove, run: int) -> void:
	var foes: Array[Node3D] = foes_ahead(row.ability.reach_m if row.ability != null else 4.0, row.waltz_count)
	if foes.is_empty():
		layer.shift = Vector3.ZERO
		_play(row.move, facing(), ahead(1.5), row.from_s, row.speed)
		return
	var side: float = atan2(facing().x, facing().z) + PI
	for f: Node3D in foes:
		if not is_instance_valid(f) or run != _waltz:
			break
		side += TAU / 3.0
		var stand: Vector3 = f.global_position + Vector3(sin(side), 0.0, cos(side)) * WALTZ_STAND_M
		_model.visible = false
		await get_tree().create_timer(WALTZ_GAP_S).timeout
		if run != _waltz or not is_instance_valid(f):
			break
		var me: Node3D = entity as Node3D
		layer.shift = Vector3(stand.x - me.global_position.x, 0.0, stand.z - me.global_position.z)
		_model.visible = true
		var to: Vector3 = f.global_position - stand
		_play(row.move, Vector3(to.x, 0.0, to.z), f.global_position + Vector3(0.0, 1.1, 0.0), row.from_s, row.speed)
		await get_tree().create_timer(row.move.length_s / maxf(row.speed, 0.01)).timeout
	if run == _waltz:
		_model.visible = false
		await get_tree().create_timer(WALTZ_GAP_S).timeout
		layer.shift = Vector3.ZERO
		_model.visible = true
