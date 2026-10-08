@tool
class_name OffHand extends RefCounted
## THE OTHER HAND ON THE ITEM (DECISIONS #172): an item held in both hands in some animations has
## the hand that is not gripping it put ON it by IK, as much as those animations are showing. What
## is held, where and how is the item's DATA, on its `ItemGrip` ("Off hand" group): the animations,
## the arm, the point on the item the fingers hold (a node in the item's scene, by name, which may
## move: a reel's turning knob), where the wrist sits from that point, and where the elbow points.
##
## The game (`HeldItem`) and the editor preview (`held_item_preview.gd`) run this same code, so the
## preview shows the hand where the game will. Static, engine types only: a tool script's preview
## may call it (EDITOR PREVIEWS, AGENTS.md).
##
## A clip cannot know where a held item's moving part is: left to its own left hand, a fishing clip
## floated it off the reel, hung it in the air while waiting, and put it through her chest casting
## (#161-#163). An IK on the arm, pointed from the BODY (never from the item, #162), is what holds on.

## The skeleton nodes made for one hand, by their names under the skeleton.
const IK_NAME: String = "OffHand_IK"
const TARGET_NAME: String = "OffHand_Target"
const POLE_NAME: String = "OffHand_Pole"


## Whether `grip` holds an item in both hands at all.
static func used(grip: ItemGrip) -> bool:
	return grip != null and not grip.off_hand_animations.is_empty() and grip.off_hand_arm.size() == 3 \
		and not String(grip.off_hand_point).is_empty()


## How much of the both-hands animations is showing, 0..1, from per-animation weights.
static func weight(grip: ItemGrip, animations: Dictionary) -> float:
	if not used(grip):
		return 0.0
	var w: float = 0.0
	for a: StringName in grip.off_hand_animations:
		w += float(animations.get(a, 0.0))
	return clampf(w, 0.0, 1.0)


## The node in `item` the other hand holds, or null.
static func point_of(item: Node, grip: ItemGrip) -> Node3D:
	if item == null or not used(grip):
		return null
	return item.find_child(String(grip.off_hand_point), true, false) as Node3D


## Make the arm's IK, its target and its elbow's pole under `skel`; returns the IK (null when the
## skeleton has no such arm). Idempotent: an existing set is returned.
static func make_ik(skel: Skeleton3D, grip: ItemGrip) -> TwoBoneIK3D:
	if skel == null or not used(grip):
		return null
	var existing: TwoBoneIK3D = skel.get_node_or_null(IK_NAME) as TwoBoneIK3D
	if existing != null:
		return existing
	for bone: StringName in grip.off_hand_arm:
		if skel.find_bone(String(bone)) < 0:
			push_warning("OffHand: the skeleton has no %s bone; the other hand cannot hold the item" % bone)
			return null
	var target := Marker3D.new()
	target.name = TARGET_NAME
	skel.add_child(target)
	var pole := Marker3D.new()
	pole.name = POLE_NAME
	skel.add_child(pole)
	var ik := TwoBoneIK3D.new()
	ik.name = IK_NAME
	skel.add_child(ik)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, String(grip.off_hand_arm[0]))
	ik.set_middle_bone_name(0, String(grip.off_hand_arm[1]))
	ik.set_end_bone_name(0, String(grip.off_hand_arm[2]))
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	ik.active = false
	return ik


## Take the IK and its markers off `skel`.
static func remove_ik(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for n: String in [IK_NAME, TARGET_NAME, POLE_NAME]:
		var node: Node = skel.get_node_or_null(n)
		if node != null:
			node.queue_free()


## How far the arm reaches, shoulder to wrist, at rest.
static func reach(skel: Skeleton3D, grip: ItemGrip) -> float:
	return skel.get_bone_rest(skel.find_bone(String(grip.off_hand_arm[1]))).origin.length() \
		+ skel.get_bone_rest(skel.find_bone(String(grip.off_hand_arm[2]))).origin.length()


## Where the WRIST goes for the fingers on `point` (`grip.off_hand_wrist` from it, in the item's
## frame `item_basis`), pulled in to `grip.off_hand_reach` of the arm from the shoulder: an arm at
## full stretch pins instead of moving.
static func wrist_target(skel: Skeleton3D, grip: ItemGrip, point: Vector3, item_basis: Basis) -> Vector3:
	var shoulder: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone(String(grip.off_hand_arm[0]))).origin
	var wrist: Vector3 = point + item_basis * grip.off_hand_wrist
	return shoulder + (wrist - shoulder).limit_length(reach(skel, grip) * grip.off_hand_reach)


## Where the elbow is pulled toward: `grip.off_hand_elbow` from the shoulder in the BODY's terms —
## out past that shoulder (away from the other one), up the spine, forward.
static func elbow_pole(skel: Skeleton3D, grip: ItemGrip) -> Vector3:
	var arm: int = skel.find_bone(String(grip.off_hand_arm[0]))
	var shoulder: Vector3 = skel.global_transform * skel.get_bone_global_pose(arm).origin
	var other_name: String = _mirror(String(grip.off_hand_arm[0]))
	var other: int = skel.find_bone(other_name)
	var spine_from: int = skel.find_bone(String(grip.off_hand_spine[0])) if grip.off_hand_spine.size() == 2 else -1
	var spine_to: int = skel.find_bone(String(grip.off_hand_spine[1])) if grip.off_hand_spine.size() == 2 else -1
	if other < 0 or spine_from < 0 or spine_to < 0:
		return shoulder + skel.global_basis * grip.off_hand_elbow
	var out: Vector3 = (shoulder - skel.global_transform * skel.get_bone_global_pose(other).origin).normalized()
	var up: Vector3 = (skel.global_transform * skel.get_bone_global_pose(spine_to).origin
		- skel.global_transform * skel.get_bone_global_pose(spine_from).origin).normalized()
	# Out x up is forward for a LEFT arm (her left, then up: in front of her); a right arm's is back.
	var forward: Vector3 = out.cross(up).normalized()
	if other_name.ends_with("_l"):
		forward = -forward
	return shoulder + out * grip.off_hand_elbow.x + up * grip.off_hand_elbow.y + forward * grip.off_hand_elbow.z


## Place the IK's target and pole for the fingers on `point`, and set how much it holds on.
static func place(skel: Skeleton3D, grip: ItemGrip, ik: TwoBoneIK3D, point: Node3D, item_basis: Basis,
		amount: float) -> void:
	if skel == null or ik == null or point == null:
		return
	ik.influence = clampf(amount, 0.0, 1.0)
	ik.active = amount > 0.0
	if not ik.active:
		return
	var target: Node3D = skel.get_node_or_null(TARGET_NAME) as Node3D
	var pole: Node3D = skel.get_node_or_null(POLE_NAME) as Node3D
	if target != null:
		target.global_position = wrist_target(skel, grip, point.global_position, item_basis)
	if pole != null:
		pole.global_position = elbow_pole(skel, grip)


## The bone on the body's other side: upperarm_l <-> upperarm_r.
static func _mirror(bone: String) -> String:
	if bone.ends_with("_l"):
		return bone.left(-2) + "_r"
	if bone.ends_with("_r"):
		return bone.left(-2) + "_l"
	return bone
