class_name CameraRig extends Node3D
## Drives the entity's camera from its `CameraRigConfig`. Attach to the `CameraRig` node of an
## entity scene; it finds the look angles itself.
##
## This is presentation only. It reads input angles and never produces gameplay events
## (hard rule 11), so nothing here can desync anything.
##
## SMOOTHNESS. Physics runs at 60 Hz; a monitor may refresh at 144. With physics interpolation
## on, the player's body is DRAWN between physics ticks. A camera parented to that body would
## still be placed only once per tick, so the view would step at 60 Hz while the world moved
## smoothly — judder that reads as lag. So the rig is `top_level`, never interpolated itself,
## and every rendered frame it places itself from the body's interpolated transform. Mouse look
## is applied at the same moment, so turning responds at the display's rate, not the tick's.

@export var config: CameraRigConfig

var _camera: Camera3D
var _input: LocalInputComponent
## Where the wheel has put the boom, and where it is on its way to. A separate flag rather than
## a negative sentinel: zooming in past the limit drives the target below zero for a moment, and
## a sentinel there reads as "never initialised" and snaps the camera back out to the preset.
var _boom: float = 0.0
var _boom_target: float = 0.0
var _boom_ready: bool = false
var _entity: SpaceTimeEntity
var _movement: SpaceTimeMovementComponent
## Someone else this camera follows instead of its own entity (spectating, DECISIONS #206), or null.
var _follow: SpaceTimeEntity = null
## The first-person set-up has been made for this entity (its own body hidden, facing held).
var _first_person_done: bool = false


func _ready() -> void:
	_camera = _find_camera()
	_entity = _owning_entity()
	if config == null:
		config = CameraRigConfig.new()
	if _entity != null:
		# Placed explicitly every frame from the interpolated body, so it must neither inherit
		# the body's per-tick transform nor be interpolated a second time.
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _camera != null:
		_camera.fov = config.fov
		# `_ready()` runs when the spawner adds the entity to the tree, which is BEFORE
		# `bind()` decides whether this entity is ours — so the rig cannot answer that
		# question here, and answering it anyway left every camera off and the game rendering
		# nothing. It stays off until `SpaceTimeEntity` calls `activate()`. A rig with no
		# owning entity is somebody previewing `player.tscn` on its own; let that one look.
		_camera.current = _entity == null


## Take the view. Called by `SpaceTimeEntity` once the entity's role is known (see `_ready`).
## This is the ONLY place that turns a camera on: two rigs racing for `current` is how a remote
## player's viewpoint ends up on screen.
func activate() -> void:
	if _camera == null:
		_camera = _find_camera()
	if _camera != null:
		_camera.current = true


## FOLLOW ANOTHER ENTITY (a player who is out watches a teammate), or null for its own again. The
## look is still this player's: they orbit whoever they watch.
func follow(target: SpaceTimeEntity) -> void:
	_follow = target


## Whom it follows (null: its own entity).
func following() -> SpaceTimeEntity:
	return _follow if is_instance_valid(_follow) else null


func _process(delta: float) -> void:
	if _camera == null:
		return
	if _input == null:
		_resolve_siblings()
	_apply(delta)


## The rig is a sibling of Components/, so it asks the entity for its components rather than
## reaching across the tree by path.
func _resolve_siblings() -> void:
	if _entity == null:
		_entity = _owning_entity()
	if _entity == null or not _entity.is_bound():
		return
	_input = _entity.find_component(LocalInputComponent) as LocalInputComponent
	_movement = _entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	apply_first_person()


## IN FIRST PERSON (DECISIONS #223), for the player's own entity: its own model is not drawn for them
## (it casts its shadow still; everyone else sees it whole), and its body faces where they look,
## standing still too, as in any first-person game. (Luke: the wolf's own greybox sat in front of the
## camera, and the view swung while the body stayed put until he moved.) Once per entity: a new look
## or character builds a new entity and a new rig.
func apply_first_person() -> void:
	if _first_person_done or config == null or not config.first_person or _entity == null or not _entity.is_local_authority:
		return
	_first_person_done = true
	if _input != null:
		_input.hold_facing(&"first_person", true)
	var visual: Node = _entity.get_node_or_null(^"Visual")
	if visual != null:
		for g: Node in visual.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _apply(delta: float) -> void:
	var yaw: float = _input.get_look_yaw() if _input != null else global_rotation.y
	var pitch: float = _input.get_look_pitch() if _input != null else 0.0
	pitch = clampf(pitch, deg_to_rad(config.pitch_min_deg), deg_to_rad(config.pitch_max_deg))

	# Anchor on where the body is DRAWN this frame, plus any correction glide still in progress,
	# so the camera and the player model always move together.
	var watched: SpaceTimeEntity = following()
	if watched != null:
		global_position = watched.get_global_transform_interpolated().origin + Vector3(0.0, config.pivot_height, 0.0)
	elif _entity != null:
		var anchor: Vector3 = _entity.get_global_transform_interpolated().origin
		if _movement != null:
			anchor += _movement.get_visual_offset()
		global_position = anchor + Vector3(0.0, config.pivot_height, 0.0)
	else:
		position = Vector3(0.0, config.pivot_height, 0.0)

	# The rig owns WORLD yaw, so `move_dir` is camera-relative however the body is turned; the
	# camera owns pitch so the body never tips over.
	global_rotation = Vector3(0.0, yaw, 0.0)

	if config.first_person:
		_camera.position = Vector3.ZERO
		_camera.rotation = Vector3(pitch, 0.0, 0.0)
		return

	var desired: Vector3 = Vector3(config.shoulder_offset, 0.0, _zoom(delta))
	desired = desired.rotated(Vector3.RIGHT, pitch)
	if config.collide_with_world:
		desired = _pull_in(desired)
	if config.follow_smoothing > 0.0:
		_camera.position = _camera.position.lerp(desired, 1.0 - exp(-config.follow_smoothing * delta))
	else:
		_camera.position = desired
	_camera.rotation = Vector3(pitch, 0.0, 0.0)


## The boom length the wheel has asked for, eased. Presentation only — nothing here reaches
## the movement state, so zooming can never desync anything.
func _zoom(delta: float) -> float:
	if not _boom_ready:
		_boom = config.boom_length
		_boom_target = config.boom_length
		_boom_ready = true
	_boom_target = clampf(_boom_target, minf(config.boom_min, config.boom_max),
		maxf(config.boom_min, config.boom_max))
	if config.zoom_smoothing > 0.0 and delta > 0.0:
		_boom = lerpf(_boom, _boom_target, 1.0 - exp(-config.zoom_smoothing * delta))
	else:
		_boom = _boom_target
	return _boom


func _unhandled_input(event: InputEvent) -> void:
	if config == null or config.first_person or _input == null:
		return   # only the local player's rig has an input component to be found
	if not _boom_ready:
		_boom = config.boom_length
		_boom_target = config.boom_length
		_boom_ready = true
	# The wheel is the camera's only while the mouse is: a genre that has taken the mouse for
	# something else (`LocalInputComponent.look_scale` below 1 — a reel being wound) has the wheel
	# too, or every notch of the crank would also swing the camera in and out.
	if _input.look_scale < 1.0:
		return
	if event.is_action_pressed(&"camera_zoom_in"):
		_boom_target -= config.zoom_step
	elif event.is_action_pressed(&"camera_zoom_out"):
		_boom_target += config.zoom_step
	# The limit is applied in ONE place, `_zoom`, so that it is a thing a test can take away:
	# clamping here as well made the guard unfalsifiable — either copy could go and the camera
	# still stopped where it should.


## Shorten the boom so the camera stops in front of geometry instead of inside it.
func _pull_in(desired: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null:
		return desired
	var from: Vector3 = global_position
	var to: Vector3 = to_global(desired)
	# World geometry only. Entities (layer 2) are other players and props rendered where they
	# were ~100 ms ago; letting them shorten the boom makes the camera twitch whenever someone
	# walks behind you.
	var query := PhysicsRayQueryParameters3D.create(from, to, SpaceTimeEntity.WORLD_MASK)
	if _entity != null:
		query.exclude = [_entity.get_rid()] if following() == null else [_entity.get_rid(), following().get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	var hit_local: Vector3 = to_local(hit["position"])
	return hit_local * maxf(0.0, 1.0 - config.collision_padding / maxf(0.001, hit_local.length()))


func _find_camera() -> Camera3D:
	for child: Node in get_children():
		var cam: Camera3D = child as Camera3D
		if cam != null:
			return cam
	return null


func _owning_entity() -> SpaceTimeEntity:
	var p: Node = get_parent()
	return p as SpaceTimeEntity
