class_name TutorialComponent extends SpaceTimeComponent
## THE PLAYER'S TUTORIAL (Luke, 2026-11-01: ROLES_PREP.md §4, T1-T5; "make your own sword" first, then the fight
## with it): where this character is in the lessons (`LessonDef`, in order), from their `tutorial` row, and E on
## the camp's GUIDE (an entity of kind `GUIDE_KIND`), which it claims from the foundation's `InteractionComponent`
## before anything else is asked. The SERVER ticks each lesson, seeing its deed done (`server/src/game/regents.rs`,
## `lesson_done`); this only reads the row and asks to begin or set the lessons aside. What the guide says beyond
## the lessons' own words is here (`greeting`, `again`, `farewell`), for a designer to edit in the Inspector.

const TABLE: StringName = &"tutorial"
## The guide's entity kind (`content/character/guide.tres`; the server's `ENTITY_GUIDE`).
const GUIDE_KIND: int = 120
## The row's `state` (the server's `TUTORIAL_*`); NONE: no row (a server from before the tutorial).
const NONE: int = -1
const OFFERED: int = 0
const ON: int = 1
const FINISHED: int = 2
const SET_ASIDE: int = 3

## The row changed (its state or the lessons done).
signal changed()
## The server ticked `lesson` (seen while bound: not the ones done before this session).
signal lesson_ticked(lesson: LessonDef)
## Every lesson is done.
signal finished()
## E was pressed on the guide `target` (the HUD's to answer: the offer, or the lesson again).
signal guide_pressed(target: int)

## The guide's name on the card.
@export var guide_name: String = "Drillmaster"
## What the guide says, offering the lessons.
@export_multiline var greeting: String = "New to the frontier? I can show you the basics: we make you a sword, then you learn to fight with it. Mostly by doing."
## What the guide says, offering them again (finished, or set aside).
@export_multiline var again: String = "Back for another go? We start from the first."
## What the guide says when the last lesson is done.
@export_multiline var farewell: String = "That's all I can teach you. The skeletons east of camp won't wait for you to be ready."

var state: int = NONE
## The lessons done (ids), in the order the server ticked them.
var done: PackedInt32Array = PackedInt32Array()
var _interaction: InteractionComponent = null
var _also: Callable = Callable()


func required_tables() -> Array[StringName]:
	return [TABLE]


## A server from before the tutorial has no such table: nothing is offered then.
func optional_tables() -> Array[StringName]:
	return [TABLE]


func _on_bound() -> void:
	if not is_local_authority:
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_interaction = ent.find_component(InteractionComponent) as InteractionComponent if ent != null else null
	if _interaction != null:
		# Ours first, then whatever claimed E before (the skilling's nodes and stations).
		_also = _interaction.interact_handler
		_interaction.interact_handler = claim_press


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	var was: PackedInt32Array = done
	var was_state: int = state
	state = int(new.get(&"state")) if new != null else NONE
	done = PackedInt32Array()
	if new != null:
		for v: Variant in new.get(&"done"):
			done.append(int(v))
	if old != null and is_bound():
		for id: int in done:
			if not was.has(id):
				var l: LessonDef = LessonDef.by_id(id)
				if l != null:
					lesson_ticked.emit(l)
		if state == FINISHED and was_state == ON:
			finished.emit()
	changed.emit()


## E went down on `target`: claimed when it is the guide; else the handler before ours is asked.
func claim_press(target: int) -> bool:
	if is_guide(target):
		guide_pressed.emit(target)
		return true
	return bool(_also.call(target)) if _also.is_valid() else false


## Whether entity `target` is the camp's guide.
static func is_guide(target: int) -> bool:
	var e: SpaceTimeEntity = EntityRegistry.get_entity(target) as SpaceTimeEntity
	return e != null and e.definition != null and e.definition.kind == GUIDE_KIND


## Every lesson, in order.
static func lessons() -> Array[LessonDef]:
	return LessonDef.all()


## The lesson now: the first in order not yet done (null when none is, or the lessons are not under way).
func current() -> LessonDef:
	if state != ON:
		return null
	for l: LessonDef in lessons():
		if not done.has(l.id):
			return l
	return null


## Where `current()` is in the run (1-based), of how many.
func place() -> Vector2i:
	var all: Array[LessonDef] = lessons()
	var l: LessonDef = current()
	return Vector2i(all.find(l) + 1 if l != null else all.size(), all.size())


## Begin the lessons (the guide's offer taken; at the guide: the server checks).
func begin() -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"tutorial_begin", [], [])


## Not now.
func set_aside() -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"tutorial_set_aside", [], [])
