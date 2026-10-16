class_name GreyboxThrower extends Node
## THE GREYBOX'S THROW (DECISIONS #246): G throws the foundation's ball where the camera looks, so a
## body the referee flies can be tried with no genre in the game. Hold G longer to throw harder (up to
## the ball's max speed). The ball leaves the hand at once (the thrower's own flight, `BodyLaunch`) and
## the referee's rows take over; anyone else sees the referee's.
##
## A game's own throw is its genre's (a disc golfer's backhand); this is the template's to try the
## mechanism with.

const BALL_ID: int = 1
## The slowest and fastest throw, and how long G takes to go from one to the other.
const MIN_SPEED: float = 6.0
const CHARGE_S: float = 1.0
## Where it leaves the hand: up from the feet, ahead of the body.
const HAND_UP: float = 1.4
const HAND_AHEAD: float = 0.5

var _held_s: float = -1.0


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.physical_keycode != KEY_G or key.echo:
		return
	if key.pressed:
		_held_s = 0.0
	elif _held_s >= 0.0:
		throw(minf(_held_s / CHARGE_S, 1.0))
		_held_s = -1.0
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _held_s >= 0.0:
		_held_s += delta


## Throw the ball with `power` (0..1) of its speed range where the camera looks. The throw's number,
## or -1 with nobody to throw it.
func throw(power: float) -> int:
	var me: Node3D = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id) as Node3D
	var cam: Camera3D = get_viewport().get_camera_3d()
	var def: BodyDef = BodyDef.by_id(BALL_ID)
	if me == null or cam == null or def == null or me.get_parent() == null:
		return -1
	var aim: Vector3 = -cam.global_basis.z
	var flat: Vector3 = Vector3(aim.x, 0.0, aim.z).normalized() if Vector2(aim.x, aim.z).length() > 0.01 else -me.global_basis.z
	var origin: Vector3 = me.global_position + Vector3.UP * HAND_UP + flat * HAND_AHEAD
	var speed: float = lerpf(MIN_SPEED, def.max_speed_mps * 0.9, clampf(power, 0.0, 1.0))
	var vel: Vector3 = (aim + Vector3.UP * 0.15).normalized() * speed
	var spin: Vector3 = flat.cross(Vector3.UP) * -8.0   # topspin
	return BodyLaunch.throw_body(me.get_parent(), def, origin, vel, Vector3.ZERO, spin)
