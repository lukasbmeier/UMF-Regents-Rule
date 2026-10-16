class_name GreyboxThrower extends Node
## THE GREYBOX'S THROW (DECISIONS #246, #248, #249): hold G to charge, let go to throw the foundation's
## ball where you look; up and down with the mouse while charging spins it (the release angle). The
## bar shows the charge (`ChargeBar`), the camera follows the ball through the air and comes back as it
## lands or you move (`FlightCam`; Settings, Game, Follow what you throw). The ball leaves the hand at
## once (the thrower's own flight, `BodyLaunch`) and the referee's rows take over.
##
## A game's own throw is its genre's (a disc golfer's backhand on the left mouse button); this is the
## template's, to try the mechanism with. Its key is added while the greybox runs, not in project.godot.

const BALL_ID: int = 1
const ACTION: StringName = &"greybox_throw"
## The slowest and fastest throw.
const MIN_SPEED: float = 6.0
## Where it leaves the hand: up from the feet, ahead of the body.
const HAND_UP: float = 1.4
const HAND_AHEAD: float = 0.5
## Spin a full release angle gives (rad/s, about the way it goes: a curve as it rolls).
const ANGLE_SPIN: float = 25.0

var charge: AimCharge = null
var flight_cam: FlightCam = null
var bar: ChargeBar = null


func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var g := InputEventKey.new()
		g.physical_keycode = KEY_G
		InputMap.action_add_event(ACTION, g)
	charge = AimCharge.new()
	charge.name = "Charge"
	charge.actions = [ACTION]
	charge.charge_s = 1.0
	add_child(charge)
	charge.released.connect(func(_s: int, power: float, _over: bool, aim: Vector3, angle: float) -> void: throw(power, aim, angle))
	flight_cam = FlightCam.new()
	flight_cam.name = "FlightCam"
	add_child(flight_cam)
	var layer := CanvasLayer.new()
	layer.name = "ChargeLayer"
	add_child(layer)
	bar = ChargeBar.new()
	bar.name = "ChargeBar"
	bar.source = charge
	bar.sweet_from = 0.7
	bar.sweet_to = 0.95
	layer.add_child(bar)


## Throw the ball with `power` (0..1) of its speed range along `aim` (none: where the camera looks),
## spun by `angle` (-1..1). The throw's number, or -1 with nobody to throw it.
func throw(power: float, aim: Vector3 = Vector3.ZERO, angle: float = 0.0) -> int:
	var me: Node3D = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id) as Node3D
	var def: BodyDef = BodyDef.by_id(BALL_ID)
	if me == null or def == null or me.get_parent() == null:
		return -1
	if aim == Vector3.ZERO:
		var cam: Camera3D = get_viewport().get_camera_3d()
		aim = -cam.global_basis.z if cam != null else -me.global_basis.z
	var flat: Vector3 = Vector3(aim.x, 0.0, aim.z).normalized() if Vector2(aim.x, aim.z).length() > 0.01 else -me.global_basis.z
	var origin: Vector3 = me.global_position + Vector3.UP * HAND_UP + flat * HAND_AHEAD
	var speed: float = lerpf(MIN_SPEED, def.max_speed_mps * 0.9, clampf(power, 0.0, 1.0))
	var vel: Vector3 = (aim.normalized() + Vector3.UP * 0.15).normalized() * speed
	var spin: Vector3 = flat.cross(Vector3.UP) * -8.0 + Vector3.UP * angle * ANGLE_SPIN
	if spin.length() > def.max_spin_rps:
		spin = spin.normalized() * def.max_spin_rps
	var id: int = BodyLaunch.throw_body(me.get_parent(), def, origin, vel, Vector3.ZERO, spin)
	var flight: Node3D = me.get_parent().get_node_or_null(NodePath("Throw%d" % id)) as Node3D
	if flight != null and flight_cam != null:
		flight_cam.follow_throw(id, flight)
	return id
