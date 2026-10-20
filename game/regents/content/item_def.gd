@tool
class_name ItemDef extends ContentDef
## AN ITEM (Regent's Rule): something in a bag. A material (logs, ore, a bird's nest) or a TOOL (an
## axe, a pick), which works a node of its `tool_tag` up to its `tool_tier` from the bag, never from a
## slot (owner, 2026-10-18, design #15: the best matching tool in the bag is used). The server seeds an
## `item_def` row from each (`game/regents.rs`), and stacks and grants by it.
##
## The genre's own for now: items become the foundation's with modular gear (design §7.3-§7.4, M16/M24),
## and this moves down then.

## How many fit in one bag slot (1: does not stack: a tool).
@export_range(1, 100000) var max_stack: int = 1000
@export_group("As a tool")
## What it works: "axe" (trees), "pick" (veins). Empty: not a tool.
@export var tool_tag: StringName = &""
## The highest node tier it works.
@export_range(0, 20) var tool_tier: int = 0
## How long its work takes, in percent of the base (a better axe: 85). A crafted tool's quality takes up
## to a tenth more off.
@export_range(10, 200, 1, "suffix:%") var tool_speed_pct: int = 100
@export_group("As a weapon")
## The kit it fights with (a `KitDef`'s key: "sword", "axe", "bow"): wielded, it gives that kit's
## combo, heavy and skills. Empty: not a weapon. A tool may be one too (the axe, owner 2026-10-19).
@export var weapon_kit: StringName = &""
## Its damage, in percent of what its kit's abilities do (100: as authored; a better weapon higher).
## A smithed weapon's quality adds up to a fifth more.
@export_range(10, 500, 1, "suffix:%") var weapon_damage_pct: int = 100
@export_group("As ammo")
## The kit it is shot from ("bow"; owner 2026-10-20: arrows are crafted ammo): each shot takes one from
## the bag. Empty: not ammo.
@export var ammo_for: StringName = &""
## Its hits, in percent of the shot's (a better arrowhead higher).
@export_range(10, 500, 1, "suffix:%") var ammo_damage_pct: int = 100
@export_group("As a part")
## What kind of part it is ("handle"): a recipe's part slot (`RecipeDef.part_slot`) takes any item of
## the same kind, so one Iron axe recipe takes a plain, an oak or a yew handle (owner, 2026-10-19).
@export var part_tag: StringName = &""
## As a tool's HANDLE, its trait (Tinkers'-style: the handle's wood): the tool's swing, in percent (yew:
## lighter, faster), and quality it adds to the tool (oak: sturdier), in thousandths.
@export_range(50, 150, 1, "suffix:%") var handle_speed_pct: int = 100
@export_range(0, 1000, 10, "suffix:‰") var handle_quality_pm: int = 0
@export_group("How it shows")
## What a tool looks like in the hand while it works (a `HeldItem` scene), if it is a tool.
@export var held_scene: PackedScene
## Its colour in the bag until it has an icon.
@export var color: Color = Color(0.75, 0.6, 0.4)
@export_multiline var description: String = ""

static var _by_id: Dictionary[int, ItemDef] = {}


func content_type() -> StringName:
	return &"item"


func why_no_workbench() -> String:
	return "a few numbers for now; items get their bench with modular gear (a core and a handle on the character)"


func summary() -> String:
	if tool_tag != &"":
		return "A tool: %s, tier %d" % [tool_tag, tool_tier]
	return "Stacks to %d" % max_stack


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"max_stack": max_stack,
		"tool_tag": String(tool_tag),
		"tool_tier": tool_tier,
		"tool_speed_pct": tool_speed_pct,
		"weapon_kit": String(weapon_kit),
		"weapon_damage_pct": weapon_damage_pct,
		"ammo_for": String(ammo_for),
		"ammo_damage_pct": ammo_damage_pct,
		"part_tag": String(part_tag),
		"handle_speed_pct": handle_speed_pct,
		"handle_quality_pm": handle_quality_pm,
	}


## What its handle trait does, in words ("" when it has none worth saying).
func handle_trait() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if handle_speed_pct != 100:
		parts.append("%d%% %s swing" % [absi(100 - handle_speed_pct), "faster" if handle_speed_pct < 100 else "slower"])
	if handle_quality_pm > 0:
		parts.append("+%d quality" % (handle_quality_pm / 10))
	return ", ".join(parts)


func validate() -> Array[String]:
	var out: Array[String] = super()
	if tool_tag != &"" and tool_tier < 1:
		out.append("a tool works tier 1 at least: set `tool_tier`")
	if tool_tag != &"" and max_stack != 1:
		out.append("a tool does not stack: `max_stack` 1")
	if weapon_kit != &"" and max_stack != 1:
		out.append("a weapon does not stack: `max_stack` 1")
	if part_tag == &"" and (handle_speed_pct != 100 or handle_quality_pm != 0):
		out.append("it has a handle trait but is no part: set `part_tag` (\"handle\")")
	if weapon_kit != &"":
		# Tier dominates (owner, 2026-10-20): against every other weapon of its kit.
		var kin: Array[ItemDef] = [self]
		for d: ContentDef in RegentsContent.items(&"item"):
			var other: ItemDef = d as ItemDef
			if other != null and other.id != id and other.weapon_kit == weapon_kit:
				kin.append(other)
		out.append_array(RegentsGrade.tier_overlaps(kin).duplicate())
	return out


## The item with content id `item_id`, or null.
static func by_id(item_id: int) -> ItemDef:
	if Engine.is_editor_hint() or _by_id.is_empty():
		var all: Dictionary[int, ItemDef] = {}
		for d: ContentDef in RegentsContent.items(&"item"):
			var it: ItemDef = d as ItemDef
			if it != null:
				all[it.id] = it
		if Engine.is_editor_hint():
			return all.get(item_id, null)
		_by_id = all
	return _by_id.get(item_id, null)
