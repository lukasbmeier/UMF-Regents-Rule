class_name SkillingLook extends SpaceTimeComponent
## SKILLING, SHOWN, on every player's character (presentation only: it reads state, AGENTS.md rule 11):
## while they chop (their `afk_chop` row, which every client has, or a round the local player is
## playing) the body swings an axe (the set's `pose.chop`, UAL's TreeChopping, held through the
## driver) and the axe is in the hand (`axe_scene`, a `HeldItem` its grips fit to every animation:
## `skilling/woodcutting/axe_grip_preview.tscn`). It stops when they do, and the axe goes once the pose
## has blended out. Tools live in the bag (design #15), so the axe is shown only while it is used.

const POSE_CHOP: StringName = &"pose.chop"
## The pose's weight under which the axe leaves the hand.
const PUT_AWAY_UNDER: float = 0.08

@export var axe_scene: PackedScene = preload("res://game/regents/skilling/woodcutting/axe.tscn")

var axe: HeldItem = null
var _skilling: SkillingComponent = null
var _driver: AnimationDriverComponent = null
var _was_chopping: bool = false


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_skilling = ent.find_component(SkillingComponent) as SkillingComponent
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent


## Whether this character is chopping now: AFK (anyone's, from their row), or in a round (our own).
func chopping() -> bool:
	return _skilling != null and (_skilling.afk_tree >= 0 or _skilling.round_id >= 0)


func _process(_delta: float) -> void:
	if _driver == null or not is_bound():
		return
	var now: bool = chopping()
	if now:
		_driver.hold_pose(POSE_CHOP, 1.0)
		if axe == null:
			var skel: Skeleton3D = skeleton_of(entity)
			if skel != null:
				axe = HeldItem.attach(skel, axe_scene)
				if axe != null:
					axe.driver = _driver
	elif _was_chopping:
		_driver.release_pose()
	_was_chopping = now
	if not now and axe != null and (_driver.pose_clip() != _clip() or _driver.pose_weight() < PUT_AWAY_UNDER):
		axe.queue_free()
		axe = null


func _clip() -> StringName:
	var ref: AnimationClipRef = _driver.animation_set.clip(POSE_CHOP) if _driver.animation_set != null else null
	return ref.anim_name if ref != null else &""


## The character's skeleton (its look, under `Visual/Model`), or null before it has one.
static func skeleton_of(ent: Node) -> Skeleton3D:
	var model: Node = ent.get_node_or_null(^"Visual/Model") if ent != null else null
	if model == null:
		return null
	if model is Skeleton3D:
		return model as Skeleton3D
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null
