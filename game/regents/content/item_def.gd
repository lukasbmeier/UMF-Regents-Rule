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
## As a tool's HANDLE, the TRAIT it gives what it is made into (Tinkers'-style: the handle's wood; oak:
## Steady, yew: Springy; template DECISIONS #275). Always the tool's, whatever its grade (owner, 2026-10-21).
@export var handle_trait: TraitDef
@export_group("How it shows")
## What a tool looks like in the hand while it works (a `HeldItem` scene), if it is a tool.
@export var held_scene: PackedScene
## Its look when it is not in a hand (an arrow): its icon is drawn from it (else from `held_scene`).
@export var world_model: PackedScene
## A hand-drawn icon, used before the one drawn from its model (template DECISIONS #271).
@export var icon_picture: Texture2D
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
		"handle_trait": ContentDef.ref(handle_trait),
	}


## Its icon is drawn from its model: its look apart (`world_model`), else its held scene.
func icon_scene() -> PackedScene:
	return world_model if world_model != null else held_scene


## Its hand-drawn icon, else the one drawn from its model (`tools/render_icons.tscn`), else none.
func icon() -> Texture2D:
	return icon_picture if icon_picture != null else super()


## What its handle's trait does, in words ("Steady: nodes are 20% less likely to run out; work 5% slower"),
## or "" when it gives none.
func handle_trait_text() -> String:
	if handle_trait == null:
		return ""
	return "%s: %s%s" % [handle_trait.display_name, handle_trait.gives, ("; " + handle_trait.costs) if not handle_trait.costs.is_empty() else ""]


## THE TRAITS a bag row's item has (`"t":[ids]` in its `instance_data`). A tool made before traits were
## (it noted only its handle, `"h"`) has its handle's. The server's twin: `traits_of_row`.
static func trait_ids(instance_data: String) -> Array[int]:
	var ids: Array[int] = Traits.ids_of(instance_data)
	if ids.is_empty():
		var h: ItemDef = ItemDef.by_id(int(RegentsGrade.data_of(instance_data).get("h", -1)))
		if h != null and h.handle_trait != null:
			ids.append(h.handle_trait.id)
	return ids


## WHAT IT IS, for traits (`TraitDef.applies_to`): a tool ("tool" and its tag, "axe"), a weapon ("weapon",
## its kit's key, and "melee", "bow" or "staff" by how its kit fights), ammo ("ammo"). The server's twin:
## `item_tags` (genre/regents/mod.rs).
func tags() -> Array[StringName]:
	var out: Array[StringName] = []
	if tool_tag != &"":
		out.append_array([&"tool", tool_tag])
	if weapon_kit != &"":
		out.append_array([&"weapon", weapon_kit])
		var kit: KitDef = KitDef.by_key(weapon_kit)
		out.append(&"bow" if kit != null and kit.draws else (&"staff" if kit != null and kit.casts() else &"melee"))
	if ammo_for != &"":
		out.append(&"ammo")
	return out


func validate() -> Array[String]:
	var out: Array[String] = super()
	if tool_tag != &"" and tool_tier < 1:
		out.append("a tool works tier 1 at least: set `tool_tier`")
	if tool_tag != &"" and max_stack != 1:
		out.append("a tool does not stack: `max_stack` 1")
	if weapon_kit != &"" and max_stack != 1:
		out.append("a weapon does not stack: `max_stack` 1")
	if part_tag == &"" and handle_trait != null:
		out.append("it has a handle trait but is no part: set `part_tag` (\"handle\")")
	if handle_trait != null and not handle_trait.applies_to.has(&"tool"):
		out.append("its handle trait (%s) is not one a tool may have: its `applies_to` lacks \"tool\"" % handle_trait.display_name)
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
