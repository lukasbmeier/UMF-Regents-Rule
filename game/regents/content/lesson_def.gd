@tool
class_name LessonDef extends ContentDef
## A LESSON OF THE TUTORIAL (Luke, 2026-11-01: ROLES_PREP.md §4, T1-T5; "make your own sword" first, then the
## fight with it, ending on what its grip's shape does). The camp's guide offers the lessons; each is a try and
## a tick, and the SERVER ticks it, seeing it done (rule 13: the server says you parried, not the client): a
## character's progress is their `tutorial` row. Lessons run in `order`; any one not yet done is ticked when
## its deed happens, so doing them out of order never undoes a thing.
##
## SHOW, DON'T NAME (Luke, 2026-11-01): `words` say what to do, in a few words, never a role's or a move's name.

## What the server sees that ticks it (`server/src/game/regents.rs`, `lesson_done`).
enum Done {
	## A node gave `item` (any item, when none).
	GATHERED,
	## A station made `item` (or, `any_of_its_kind`, any item of its kind: any grip, any sword).
	MADE,
	## The player took `item` in hand (or any of its kind).
	WIELDED,
	## The string's last hit landed and staggered what it hit.
	LAST_HIT,
	## A roll began while a foe's swing in reach was winding up to land inside it.
	ROLLED_THROUGH,
	## A guard press parried a blow.
	PARRIED,
	## The string's first hit, begun soon after a parry.
	RIPOSTE,
	## A held guard took a blow in front.
	BLOCKED,
	## As ROLLED_THROUGH, a swing that goes through any guard (the red glint).
	ROLLED_GLINT,
	## The string's last hit landed with a grip of a shape (not the plain grip).
	SHAPED_LAST_HIT,
}

## Where it comes in the run (smaller first). Two lessons never share one.
@export_range(1, 1000) var order: int = 1
## What ticks it.
@export var done_when: Done = Done.GATHERED
## The item a GATHERED, MADE or WIELDED lesson wants (none: any).
@export var item: ItemDef
## A MADE or WIELDED lesson: any item of `item`'s kind counts (any grip for a grip, any sword for a sword).
@export var any_of_its_kind: bool = false
## Where the player is sent: a level point's id ("workbench", "poi_training"); the HUD points the way.
@export var at: StringName = &""
## What the guide says: a few words (Luke: "mostly play, a few words").
@export_multiline var words: String = ""

static var _all: Array[LessonDef] = []


func content_type() -> StringName:
	return &"lesson"


func why_no_workbench() -> String:
	return "a few words and a deed: played at the camp's yard by talking to its guide (the combat and skilling playtests run it)"


func summary() -> String:
	return "%d. %s" % [order, display_name]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"order": order,
		"done_when": int(done_when),
		"item": ContentDef.ref(item),
		"any_of_its_kind": any_of_its_kind,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if words.strip_edges().is_empty():
		out.append("the guide says nothing: set `words`")
	var wants_item: bool = done_when == Done.GATHERED or done_when == Done.MADE or done_when == Done.WIELDED
	if item != null and not wants_item:
		out.append("an item is set, but this deed names none (only gathered, made, wielded do)")
	if any_of_its_kind and (item == null or not wants_item):
		out.append("`any_of_its_kind` needs an item, on a made or wielded lesson")
	if done_when == Done.WIELDED and item != null and item.weapon_kit == &"":
		out.append("%s is no weapon: it cannot be wielded" % item.display_name)
	for w: String in ["tank", "damage", "support", "finisher"]:
		if words.to_lower().contains(w):
			out.append("its words name a role or a move (\"%s\"): say what to do, never its name" % w)
	return out


func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	for d: ContentDef in all_of_type:
		var l: LessonDef = d as LessonDef
		if l != null and l.id != id and l.order == order:
			out.append("its order %d is %s's too" % [order, l.display_name])
	return out


## Whether `made` (an item made, gathered or taken in hand) is what this lesson wants.
func wants(made: ItemDef) -> bool:
	if item == null:
		return true
	if made == null:
		return false
	if made.id == item.id:
		return true
	if not any_of_its_kind:
		return false
	return (item.part_tag != &"" and made.part_tag == item.part_tag) or (item.weapon_kit != &"" and made.weapon_kit == item.weapon_kit)


## Every lesson, in order.
static func all() -> Array[LessonDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var out: Array[LessonDef] = []
		for d: ContentDef in RegentsContent.items(&"lesson"):
			var l: LessonDef = d as LessonDef
			if l != null:
				out.append(l)
		out.sort_custom(func(a: LessonDef, b: LessonDef) -> bool: return a.order < b.order)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all.duplicate()


## The lesson with content id `lesson_id`, or null.
static func by_id(lesson_id: int) -> LessonDef:
	for l: LessonDef in all():
		if l.id == lesson_id:
			return l
	return null
