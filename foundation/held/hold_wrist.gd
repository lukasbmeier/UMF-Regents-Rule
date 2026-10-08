class_name HoldWrist extends SkeletonModifier3D
## THE HAND HOLDING AN ITEM (DECISIONS #158, #160), after the animation and before the item is
## placed. First its FINGERS: a clip that opens the hand (a jump) has them closed back round the
## item (`HeldItem.close_fist_now`, `GripFit.close_fist`). Then its WRIST: an item carried steady
## keeps its direction to the body while the arm swings; left at that, its handle turns in the fist
## and the fingers show through it. This turns the hand about the wrist to lay the fist's line along
## the item (`GripFit.wrist_turn`, up to `ItemGrip.wrist_turn_deg`), as far as the item's steady
## grips are showing.
##
## `HeldItem.attach` adds one beside the skeleton's other modifiers; it asks its item how far to
## turn (`HeldItem.wrist_turn_now`). Presentation only.

## The item whose hand this turns.
var item: HeldItem = null


func _process_modification_with_delta(_delta: float) -> void:
	if item == null or not is_instance_valid(item):
		return
	var sk: Skeleton3D = get_skeleton()
	var bone: int = item.hand_bone()
	if sk == null or bone < 0:
		return
	item.close_fist_now(sk)
	var turn: Basis = item.wrist_turn_now(sk)
	if turn.is_equal_approx(Basis.IDENTITY):
		return
	var hand: Transform3D = sk.get_bone_global_pose(bone)
	var parent: int = sk.get_bone_parent(bone)
	var above: Transform3D = sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local: Transform3D = above.affine_inverse() * Transform3D(turn * hand.basis, hand.origin)
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
