class_name MotionBones extends SkeletonModifier3D
## THE BONES OF A MOVE MADE IN CODE (`MotionMove`, played by `MotionLayer`): first the move's CLIPS (`MotionClip`: each
## human-made clip sampled at its time-warped time and blended over the pose under it, on its mask; its root's height
## kept, its travel along the ground left to the layer, which carries the body); then, on that pose, the spine bent
## forward and twisted (each a share over `spine_bones`, so a wide bend is no one sharp kink), the weapon arm raised,
## spread and pointed at a target. As `AimTwist` turns the chest for a shot: each turn is made in the world about the
## BODY's own axes (its up, its right, its forward: `body_up`, `body_forward`, given by the layer each frame, so a body
## mid-flip bends about itself), through each bone's own joint, and all a bone carries follows it. It runs before the
## held item's wrist (it is put first among the skeleton's modifiers), so the weapon follows the arm.
##
## Presentation only (hard rule 11): it reads a pose and decides nothing.

## The spine's bones, from the lowest up: each takes an equal share of a bend and a twist.
@export var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The weapon arm, shoulder to hand (the right, the hand a weapon is held in).
@export var upper_arm: StringName = &"upperarm_r"
@export var fore_arm: StringName = &"lowerarm_r"
@export var hand: StringName = &"hand_r"

## The pose to bend to (the layer sets it each frame; null: nothing).
var pose: MotionMove.Pose = null
## The body's own up and forward now (world), and where the arm points (world; INF: nowhere).
var body_up: Vector3 = Vector3.UP
var body_forward: Vector3 = Vector3.FORWARD
var target: Vector3 = Vector3.INF
## Which way the arm is "out to the side": 1 its right (a right hand's), -1 its left.
var side_sign: float = 1.0
## Bones whose places (world) are kept after each bend, in `seen`: a modifier's bend lives only while the skeleton
## draws, so a reader outside it (a suite, an effect at the hand) gets the clip's pose; this is the bent one.
var watch: Array[StringName] = []
var seen: Dictionary[StringName, Vector3] = {}
## The move playing and how far in (s): its clips are sampled here (the layer sets them each frame; null: none).
var move: MotionMove = null
var t: float = 0.0
## How much of the clips' root rising it keeps (the layer's `lift_scale`).
var root_height_scale: float = 1.0

## Per clip, per skeleton: [bone, track type, track] for each of its tracks this skeleton has.
var _tracks: Dictionary[Animation, Array] = {}
## Per mask: whether each bone is in it.
var _masks: Dictionary[int, PackedByteArray] = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skel: Skeleton3D = get_skeleton()
	if skel == null:
		return
	if move != null:
		for c: MotionClip in move.clips:
			var w: float = c.weight(t, move.length_s)
			if w > 0.0:
				_blend_clip(skel, c, w)
	if pose != null and not pose.is_rest():
		_bend(skel)
	for b: StringName in watch:
		var i: int = skel.find_bone(String(b))
		if i >= 0:
			seen[b] = skel.global_transform * skel.get_bone_global_pose(i).origin


## Clip `c` at the move's time, `w` of the way over the pose under it, on its mask. The root's place along the ground is
## left as it was (the layer carries the body that far instead); its height is the clip's, times `root_height`.
func _blend_clip(skel: Skeleton3D, c: MotionClip, w: float) -> void:
	var a: Animation = c.clip()
	if a == null:
		return
	var ct: float = c.clip_time(t, move.length_s)
	var in_mask: PackedByteArray = _mask(skel, c.mask)
	for entry: Variant in _tracks_of(skel, a):
		var e: PackedInt32Array = entry as PackedInt32Array
		var bone: int = e[0]
		if in_mask[bone] == 0:
			continue
		match e[1]:
			Animation.TYPE_ROTATION_3D:
				var q: Quaternion = a.rotation_track_interpolate(e[2], ct)
				skel.set_bone_pose_rotation(bone, skel.get_bone_pose_rotation(bone).slerp(q, w))
			Animation.TYPE_POSITION_3D:
				var p: Vector3 = a.position_track_interpolate(e[2], ct)
				var now: Vector3 = skel.get_bone_pose_position(bone)
				if skel.get_bone_name(bone) == "root":
					skel.set_bone_pose_position(bone, Vector3(now.x, lerpf(now.y, p.y * c.root_height * root_height_scale, w), now.z))
				else:
					skel.set_bone_pose_position(bone, now.lerp(p, w))
			Animation.TYPE_SCALE_3D:
				var sc: Vector3 = a.scale_track_interpolate(e[2], ct)
				skel.set_bone_pose_scale(bone, skel.get_bone_pose_scale(bone).lerp(sc, w))


func _tracks_of(skel: Skeleton3D, a: Animation) -> Array:
	if _tracks.has(a):
		return _tracks[a]
	var out: Array = []
	for i: int in a.get_track_count():
		var ty: int = a.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var bone: int = skel.find_bone(String(a.track_get_path(i).get_concatenated_subnames()))
		if bone >= 0:
			out.append(PackedInt32Array([bone, ty, i]))
	_tracks[a] = out
	return out


## Whether each bone moves under mask `m`: all; the spine and all it carries (arms, head); the legs.
func _mask(skel: Skeleton3D, m: int) -> PackedByteArray:
	if _masks.has(m):
		return _masks[m]
	var n: int = skel.get_bone_count()
	var out := PackedByteArray()
	out.resize(n)
	var tops: Array[String] = []
	match m:
		MotionClip.Mask.UPPER:
			tops = ["spine_01"]
		MotionClip.Mask.LEGS:
			tops = ["thigh_l", "thigh_r"]
	for i: int in n:
		if tops.is_empty():
			out[i] = 1
			continue
		var b: int = i
		while b >= 0:
			if tops.has(skel.get_bone_name(b)):
				out[i] = 1
				break
			b = skel.get_bone_parent(b)
	_masks[m] = out
	return out


func _bend(skel: Skeleton3D) -> void:
	var frame: Basis = skel.global_transform.basis.orthonormalized()
	var up: Vector3 = body_up.normalized()
	var fwd: Vector3 = (body_forward - up * body_forward.dot(up)).normalized()
	if fwd.length_squared() < 0.5:
		return
	var right: Vector3 = fwd.cross(up).normalized()
	var spine: Array[int] = []
	for b: StringName in spine_bones:
		var i: int = skel.find_bone(String(b))
		if i >= 0:
			spine.append(i)
	if not spine.is_empty():
		var n: float = float(spine.size())
		# Bent forward is about the body's right, the top going forward (a negative turn); twisted left about its up.
		var share: Basis = Basis(up, pose.twist / n) * Basis(right, -pose.bend / n)
		for i: int in spine:
			turn_bone(skel, i, frame.inverse() * share * frame)
	var ua: int = skel.find_bone(String(upper_arm))
	if ua < 0:
		return
	# Raised forward and up: about the body's right, the hand going forward from hanging; spread out: about its
	# forward, the hand going out to its side.
	if absf(pose.raise) + absf(pose.spread) > 0.0001:
		var arm: Basis = Basis(fwd, -pose.spread * side_sign) * Basis(right, pose.raise)
		turn_bone(skel, ua, frame.inverse() * arm * frame)
	if pose.reach > 0.0001 and target != Vector3.INF:
		_point_arm(skel, ua, frame, pose.reach)
	if absf(pose.wrist) > 0.0001:
		_roll_wrist(skel, frame, pose.wrist)


## The weapon hand rolled `angle` about the fore arm's line (elbow to wrist): what it holds turns with it.
func _roll_wrist(skel: Skeleton3D, frame: Basis, angle: float) -> void:
	var fa: int = skel.find_bone(String(fore_arm))
	var h: int = skel.find_bone(String(hand))
	if fa < 0 or h < 0:
		return
	var to_world: Transform3D = skel.global_transform
	var along: Vector3 = to_world * skel.get_bone_global_pose(h).origin - to_world * skel.get_bone_global_pose(fa).origin
	if along.length_squared() < 0.000001:
		return
	turn_bone(skel, h, frame.inverse() * Basis(along.normalized(), angle * side_sign) * frame)


## The arm pointed at `target`, `weight` of the way: the upper arm turned so shoulder-to-hand lies along it, then the
## fore arm turned to lie along the upper arm (a straight arm reaching).
func _point_arm(skel: Skeleton3D, ua: int, frame: Basis, weight: float) -> void:
	var fa: int = skel.find_bone(String(fore_arm))
	var h: int = skel.find_bone(String(hand))
	if fa < 0 or h < 0:
		return
	var to_world: Transform3D = skel.global_transform
	var shoulder: Vector3 = to_world * skel.get_bone_global_pose(ua).origin
	var elbow: Vector3 = to_world * skel.get_bone_global_pose(fa).origin
	var wrist: Vector3 = to_world * skel.get_bone_global_pose(h).origin
	# Straighten first (the fore arm along the upper arm), then point the whole arm.
	var straight: Basis = arc(wrist - elbow, elbow - shoulder, weight)
	turn_bone(skel, fa, frame.inverse() * straight * frame)
	wrist = to_world * skel.get_bone_global_pose(h).origin
	var aim: Basis = arc(wrist - shoulder, target - shoulder, weight)
	turn_bone(skel, ua, frame.inverse() * aim * frame)


## Turn bone `i` (and all it carries) by `rot`, a rotation in the skeleton's frame, about its own joint.
static func turn_bone(skel: Skeleton3D, i: int, rot: Basis) -> void:
	var p: Transform3D = skel.get_bone_global_pose(i)
	p.basis = rot * p.basis
	skel.set_bone_global_pose(i, p)


## The turn (world) that takes direction `from` toward `to`, `weight` of the way (the shortest way round).
static func arc(from: Vector3, to: Vector3, weight: float) -> Basis:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return Basis.IDENTITY
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	var axis: Vector3 = a.cross(b)
	var angle: float = a.angle_to(b) * clampf(weight, 0.0, 1.0)
	if axis.length_squared() < 0.000001 or angle < 0.0001:
		return Basis.IDENTITY
	return Basis(axis.normalized(), angle)
