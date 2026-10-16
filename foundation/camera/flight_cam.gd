class_name FlightCam extends Node
## THE FLIGHT CAM (FOUNDATION_SYSTEMS milestone 14, DECISIONS #248): the player's camera follows what
## they threw through the air, and comes back to them. A genre adds one to its game scene and calls
## `follow_throw` as it throws (or `follow_body` to watch anyone's: spectating a disc).
##
##   from the throw     it watches the thrower's own flight (`BodyLaunch`), the moment it leaves the hand
##   its body arrives   it watches what draws it (the same flight, kept near the referee's, then the rows)
##   it comes to rest   it holds there `hold_s`, then the camera glides back
##   the player moves   back at once (they are running after it)
##
## Off when the player turned "Follow what you throw" off (Settings, Game). Presentation only.

## How it follows (none: the foundation's `follow_cam.tres`).
@export var follow: FollowCamConfig
## How long it stays on what it followed once that is at rest.
@export_range(0.0, 10.0, 0.1, "suffix:s") var hold_s: float = 1.2
## The player moving faster than this brings the camera back.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var return_on_move_mps: float = 1.0
## Moving in this long after it starts following does not bring it back (a throw on the run).
@export_range(0.0, 3.0, 0.05, "suffix:s") var move_grace_s: float = 0.5
## Off in tests (the setting is the player's, and a test's machine has its own).
var obey_setting: bool = true
var _since_s: float = 0.0

## What it follows: the thrower's own flight until its body arrives, then the body's entity.
var _flight: Node3D = null
var _launch_id: int = 0
var _body_id: int = -1
var _rested_s: float = -1.0
var _rig: CameraRig = null


## Whether it follows something now.
func is_following() -> bool:
	return _flight != null or _body_id >= 0


## The entity it follows (-1: none, or still the throw's own flight).
func body_id() -> int:
	return _body_id


## FOLLOW A THROW: the thrower's own flight now (`BodyLaunch.fly`'s, `throw_body`'s number), its body when
## it arrives. False when the player turned the flight cam off, or there is no camera of theirs.
func follow_throw(launch_id: int, flight: Node3D) -> bool:
	if not _allowed() or _local_rig() == null:
		return false
	_flight = flight
	_launch_id = launch_id
	_body_id = -1
	_rested_s = -1.0
	_since_s = 0.0
	_rig.watch(flight, follow)
	set_process(true)
	return true


## FOLLOW A BODY already in the world (anyone's: spectating), until it rests.
func follow_body(entity_id: int) -> bool:
	if not _allowed() or _local_rig() == null:
		return false
	_flight = null
	_launch_id = 0
	_body_id = entity_id
	_rested_s = -1.0
	_since_s = 0.0
	var target: Node3D = _target_of(entity_id)
	if target == null:
		return false
	_rig.watch(target, follow)
	set_process(true)
	return true


## Back to the player now.
func stop() -> void:
	_flight = null
	_body_id = -1
	_launch_id = 0
	_rested_s = -1.0
	if _rig != null and is_instance_valid(_rig):
		_rig.stop_watching()
	set_process(false)


func _process(delta: float) -> void:
	if not is_following():
		set_process(false)
		return
	_since_s += delta
	if _since_s > move_grace_s and _player_moving():
		stop()
		return
	if _body_id < 0:
		_body_id = _body_of_throw(_launch_id)
	var body: BodyComponent = _body_component(_body_id)
	var target: Node3D = _target_of(_body_id) if body != null else (_flight if is_instance_valid(_flight) else null)
	if target == null:
		stop()
		return
	if _rig.watching() != target:
		_rig.watch(target, follow)
	if body != null and body.at_rest:
		_rested_s = maxf(_rested_s, 0.0) + delta
		if _rested_s >= hold_s:
			stop()


func _allowed() -> bool:
	return not obey_setting or bool(Settings.get_value(&"flight_cam"))


func _local_rig() -> CameraRig:
	if _rig == null or not is_instance_valid(_rig):
		var me: Node = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id)
		_rig = me.get_node_or_null(^"CameraRig") as CameraRig if me != null else null
	return _rig


## Use this rig (tests).
func use_rig(rig: CameraRig) -> void:
	_rig = rig


func _player_moving() -> bool:
	if return_on_move_mps <= 0.0:
		return false
	var me: SpaceTimeEntity = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if me != null else null
	if mv == null or mv.get_render_state() == null:
		return false
	var v: Vector3 = mv.get_render_state().vel
	return Vector2(v.x, v.z).length() > return_on_move_mps


## The body entity of this game's throw `launch_id`, or -1 while it has not arrived.
static func _body_of_throw(launch_id: int) -> int:
	for n: Node in EntitySpawner.entity_nodes():
		var e: SpaceTimeEntity = n as SpaceTimeEntity
		if e == null or not e.is_bound():
			continue
		var b: BodyComponent = e.find_component(BodyComponent) as BodyComponent
		if b != null and b.launch_id == launch_id and b.owner_id == EntityRegistry.local_entity_id:
			return e.entity_id
	return -1


static func _body_component(entity_id: int) -> BodyComponent:
	if entity_id < 0:
		return null
	var e: SpaceTimeEntity = EntitySpawner.get_entity_node(entity_id) as SpaceTimeEntity
	return e.find_component(BodyComponent) as BodyComponent if e != null else null


## What draws body `entity_id` now: the thrower's flight while it is drawn, else its look.
static func _target_of(entity_id: int) -> Node3D:
	var b: BodyComponent = _body_component(entity_id)
	if b == null:
		return null
	if b.flight() != null:
		return b.flight()
	return b.entity.get_node_or_null(^"Visual") as Node3D
