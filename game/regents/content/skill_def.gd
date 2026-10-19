@tool
class_name SkillDef extends ContentDef
## A SKILL (design §3, #3): Woodcutting, Mining, Smelting, Smithing, Crafting. A character's MASTERY of it
## is XP the server keeps (`skill_xp`); the rank comes from `xp_to_rank`, so the cap can grow later
## without a migration (owner, 2026-10-18: v1 ranks 1-10, production higher). Nodes and recipes name the
## rank they need. While a player works at it, the body plays `pose` with `tool_scene` in the hand.

## Its key, as the server and a node's or recipe's content name it.
@export var key: StringName = &""
## XP to reach each rank from 2 up (cumulative: rank 2 at the first, rank 3 at the second...).
@export var xp_to_rank: PackedInt32Array = PackedInt32Array([60, 150, 280, 450, 680, 980, 1350, 1800, 2400])
@export_group("How it shows")
## The animation set's pose while working at it (a semantic name: `pose.chop`).
@export var pose: StringName = &""
## What is in the hand while working at it (a `HeldItem` scene), or nothing.
@export var tool_scene: PackedScene
@export var color: Color = Color(0.8, 0.8, 0.8)

static var _by_key: Dictionary[StringName, SkillDef] = {}
static var _by_id: Dictionary[int, SkillDef] = {}


func content_type() -> StringName:
	return &"skill"


func why_no_workbench() -> String:
	return "a name, a curve and a pose: its minigames are played in the skilling lab (game/regents/skilling/skilling_lab.tscn)"


func summary() -> String:
	return "Rank %d at %d XP" % [xp_to_rank.size() + 1, xp_to_rank[xp_to_rank.size() - 1] if not xp_to_rank.is_empty() else 0]


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "key": String(key), "xp_to_rank": Array(xp_to_rank)}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (woodcutting, mining...)")
	for i: int in range(1, xp_to_rank.size()):
		if xp_to_rank[i] <= xp_to_rank[i - 1]:
			out.append("`xp_to_rank` must rise: rank %d needs more XP than rank %d" % [i + 2, i + 1])
			break
	return out


## The rank `xp` reaches (1 with none).
func rank_of(xp: int) -> int:
	var r: int = 1
	for need: int in xp_to_rank:
		if xp >= need:
			r += 1
	return r


## XP into the current rank and XP the next rank needs (both 0 at the cap).
func progress(xp: int) -> Vector2i:
	var r: int = rank_of(xp)
	if r > xp_to_rank.size():
		return Vector2i.ZERO
	var from: int = xp_to_rank[r - 2] if r >= 2 else 0
	return Vector2i(xp - from, xp_to_rank[r - 1] - from)


static func by_key(skill_key: StringName) -> SkillDef:
	_fill()
	return _by_key.get(skill_key, null)


static func by_id(skill_id: int) -> SkillDef:
	_fill()
	return _by_id.get(skill_id, null)


static func all() -> Array[SkillDef]:
	_fill()
	var out: Array[SkillDef] = []
	out.assign(_by_id.values())
	out.sort_custom(func(a: SkillDef, b: SkillDef) -> bool: return a.id < b.id)
	return out


static func _fill() -> void:
	if not Engine.is_editor_hint() and not _by_id.is_empty():
		return
	_by_key.clear()
	_by_id.clear()
	for d: ContentDef in RegentsContent.items(&"skill"):
		var s: SkillDef = d as SkillDef
		if s != null:
			_by_key[s.key] = s
			_by_id[s.id] = s
