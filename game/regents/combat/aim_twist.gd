class_name AimTwist extends SkeletonModifier3D
## THE UPPER BODY TURNS TO WHERE A SHOT GOES (Luke, 2026-11-11: arrows and spells "dont come from where you think
## they would ... point the hand and the bow less to the left and more to the center of the screen"; 2026-11-12: "if
## tab target hand and bow should point towards them"). The aim poses are upper-body poses over walking legs, so the
## turn of the hips the clips were made with is lost and the bow points off to the left; the camera sits over the
## right shoulder, so the crosshair's point is right of straight ahead; and a Tab target is wherever it is. While a
## shot is aimed, this turns the spine (shared over `spine_bones`, so a wide turn is not one sharp twist) from the way
## the BODY faces to the `target`, less where the pose itself already points (`pose_points`: how far left of straight
## ahead and how far above level, measured once per pose: `tests/aim_shot.tscn` prints what is left over).
##
## From the body's facing, not from the hands (its first version aligned the line between the bow's two hands): the
## hands move all through a draw and a cast, and the bow swung about as the string hand reached for the arrow.
##
## It also keeps where the `muzzle_bone` is, turned (`muzzle`): where a shot is seen to leave (`ShotLook`).
##
## Presentation only (hard rule 11): it reads the pose and a point, and decides nothing. It runs before the held
## item's wrist and off-hand modifiers (it is the skeleton's first child), which then follow the turned arm.

## The bones turned, from the lowest up: each takes an equal share of the turn round; the last tips up or down.
@export var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The most it turns, either way and up or down.
@export_range(0.0, 180.0, 1.0, "radians_as_degrees") var max_yaw: float = deg_to_rad(95.0)
@export_range(0.0, 90.0, 1.0, "radians_as_degrees") var max_pitch: float = deg_to_rad(40.0)
## How fast it comes in and goes out (1/s).
@export var ease_rate: float = 10.0

## Where the shot goes (world), the way the body faces (world, flat), and where the pose points by itself (radians:
## x to the left of the body's facing, y above level).
var target: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3.FORWARD
var pose_points: Vector2 = Vector2.ZERO
## Whether a shot is being aimed now: the turn eases in while it is, out when it is not.
var aiming: bool = false
## How much of the turn shows now, 0 to 1 (tests read it), and the turn last made (radians: yaw, pitch).
var weight: float = 0.0
var turned: Vector2 = Vector2.ZERO
## The bone a shot is seen to leave from (a bow's bow hand, the casting hand), where it is in the world as last
## posed (the turn in it), and when that was (msec; -1: never).
var muzzle_bone: StringName = &""
var muzzle: Vector3 = Vector3.ZERO
var muzzle_msec: int = -1


## Aim at `at` from now on: the body faces `body_facing`, the pose by itself points `points` off it.
func aim(at: Vector3, body_facing: Vector3, points: Vector2) -> void:
	target = at
	facing = body_facing
	pose_points = points
	aiming = true


## No shot is aimed: the turn eases out.
func rest() -> void:
	aiming = false


func _process_modification_with_delta(delta: float) -> void:
	weight = move_toward(weight, 1.0 if aiming else 0.0, ease_rate * delta)
	var skel: Skeleton3D = get_skeleton()
	if skel == null:
		return
	var to_world: Transform3D = skel.global_transform
	turned = Vector2.ZERO
	var bones: Array[int] = []
	for b: StringName in spine_bones:
		var i: int = skel.find_bone(String(b))
		if i >= 0:
			bones.append(i)
	if weight > 0.0 and not bones.is_empty():
		var chest: Vector3 = to_world * skel.get_bone_global_pose(bones[bones.size() - 1]).origin
		var turn: Vector2 = turn_from(facing, pose_points, target - chest, max_yaw, max_pitch) * weight
		turned = turn
		# Turned in the world, through each bone's own joint (the skeleton's frame may be turned and scaled): round,
		# a share a bone; then up or down at the last, about the side of the way it now points.
		var frame: Basis = to_world.basis.orthonormalized()
		var round_share: Basis = Basis(Vector3.UP, turn.x / float(bones.size()))
		for i: int in bones:
			_turn_bone(skel, i, frame.inverse() * round_share * frame)
		var now_facing: Vector3 = Basis(Vector3.UP, turn.x) * facing
		_turn_bone(skel, bones[bones.size() - 1], frame.inverse() * rotation_for(now_facing, Vector2(0.0, turn.y)) * frame)
	var m: int = skel.find_bone(String(muzzle_bone)) if muzzle_bone != &"" else -1
	if m >= 0:
		muzzle = to_world * skel.get_bone_global_pose(m).origin
		muzzle_msec = Time.get_ticks_msec()


## Turn bone `i` (and all it carries) by `rot`, a rotation in the skeleton's frame, about its own joint.
func _turn_bone(skel: Skeleton3D, i: int, rot: Basis) -> void:
	var pose: Transform3D = skel.get_bone_global_pose(i)
	pose.basis = rot * pose.basis
	skel.set_bone_global_pose(i, pose)


## THE TURN that takes a pose from where it points to `want` (world): the body faces `body_facing`, and the pose by
## itself points `points` off that (x to the left, y above level, radians). x: the turn round, about the world's up
## (positive: to the left); y: about the aim's side (positive tips DOWN, as `rotation_for` turns). Each held within
## its limit. Nothing for a want with no length along the ground.
static func turn_from(body_facing: Vector3, points: Vector2, want: Vector3, yaw_limit: float, pitch_limit: float) -> Vector2:
	var face_flat := Vector2(body_facing.x, body_facing.z)
	var want_flat := Vector2(want.x, want.z)
	if face_flat.length() < 0.001 or want_flat.length() < 0.001:
		return Vector2.ZERO
	var to_want: float = -face_flat.angle_to(want_flat)   # Godot's yaw about +Y: positive is to the left
	var want_up: float = atan2(want.y, want_flat.length())
	return Vector2(clampf(wrapf(to_want - points.x, -PI, PI), -yaw_limit, yaw_limit), clampf(-(want_up - points.y), -pitch_limit, pitch_limit))


## The rotation (world) that turns `line` by `turn` (`turn_for`): its pitch about the line's own side first, then
## its yaw about the world's up.
static func rotation_for(line: Vector3, turn: Vector2) -> Basis:
	var side: Vector3 = Vector3.UP.cross(Vector3(line.x, 0.0, line.z))
	var tip: Basis = Basis(side.normalized(), turn.y) if side.length_squared() > 0.000001 else Basis.IDENTITY
	return Basis(Vector3.UP, turn.x) * tip


## THE TURN that points the line `line` (world) along `want` (world): x the yaw about the world's up, y the pitch
## about the line's own side (positive: up), each held within its limit. Nothing for a line or a want with no
## length along the ground. (What is left to turn: the picture tool measures a pose's hands against its target by it.)
static func turn_for(line: Vector3, want: Vector3, yaw_limit: float, pitch_limit: float) -> Vector2:
	var line_flat := Vector2(line.x, line.z)
	var want_flat := Vector2(want.x, want.z)
	if line_flat.length() < 0.001 or want_flat.length() < 0.001:
		return Vector2.ZERO
	# Godot's yaw about +Y turns -Z toward -X: the angle from the line to the want, seen from above, negated.
	var yaw: float = -line_flat.angle_to(want_flat)
	var line_up: float = atan2(line.y, line_flat.length())
	var want_up: float = atan2(want.y, want_flat.length())
	# About the side axis (up x forward), a positive turn tips the line DOWN: so the pitch is negated to raise it.
	return Vector2(clampf(yaw, -yaw_limit, yaw_limit), clampf(-(want_up - line_up), -pitch_limit, pitch_limit))
