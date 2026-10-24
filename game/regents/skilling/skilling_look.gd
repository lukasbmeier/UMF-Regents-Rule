class_name SkillingLook extends SpaceTimeComponent
## SKILLING, SHOWN, on every player's character (presentation only: it reads state, AGENTS.md rule 11):
## while they work (their `afk_work` row, which every client has, or a round the local player is playing)
## the body plays the skill's pose (`SkillDef.pose`: the chop, the pick's swing, the bellows, the hammer)
## held through the driver, and the tool is in the hand: the one they work with (`ItemDef.held_scene`, from
## the AFK row: a copper axe or an iron one) or the skill's own (`SkillDef.tool_scene`: the smith's hammer).
## Both go when they stop, the tool once the pose has blended out. Tools live in the bag (design #15), so
## a tool is shown only while it is used.

## The pose's weight under which the tool leaves the hand.
const PUT_AWAY_UNDER: float = 0.08
## The pose before the skills had their own (kept for the tests and the look of an unknown skill).
const POSE_CHOP: StringName = &"pose.chop"

## What is in the hand, and which scene it is.
var tool: HeldItem = null
var tool_scene: PackedScene = null
var pose: StringName = &""
var _skilling: SkillingComponent = null
var _driver: AnimationDriverComponent = null
var _health: SpaceTimeHealthComponent = null
var _was_working: bool = false


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
	_health = ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent


## Whether this character is working now: AFK (anyone's, from their row), or in a round (our own). Never
## while dead: the death plays alone (a playtest, 2026-10-20: slain mid-chop, the chop went on over it).
func working() -> bool:
	if _health != null and _health.is_dead():
		return false
	return _skilling != null and (_skilling.afk_target >= 0 or _skilling.round_id >= 0)


## Kept from woodcutting's first build: chopping is working with an axe.
func chopping() -> bool:
	return working() and pose == POSE_CHOP


func _process(_delta: float) -> void:
	if _driver == null or not is_bound():
		return
	var now: bool = working()
	if now:
		var skill: SkillDef = _skilling.working_skill()
		pose = skill.pose if skill != null and skill.pose != &"" else POSE_CHOP
		_driver.hold_pose(pose, 1.0)
		var item: ItemDef = _skilling.working_tool()
		var want: PackedScene = item.held_scene if item != null and item.held_scene != null else (skill.tool_scene if skill != null else null)
		if want != tool_scene:
			_drop_tool()
			tool_scene = want
		if tool == null and tool_scene != null:
			var skel: Skeleton3D = skeleton_of(entity)
			if skel != null:
				tool = HeldItem.attach(skel, tool_scene)
				if tool != null:
					tool.driver = _driver
	elif _was_working:
		_driver.release_pose()
	_was_working = now
	if not now and tool != null and (_driver.pose_clip() != _clip() or _driver.pose_weight() < PUT_AWAY_UNDER):
		_drop_tool()
		tool_scene = null


func _drop_tool() -> void:
	if tool != null:
		tool.queue_free()
		tool = null


func _clip() -> StringName:
	var ref: AnimationClipRef = _driver.animation_set.clip(pose) if _driver.animation_set != null and pose != &"" else null
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
