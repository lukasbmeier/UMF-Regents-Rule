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
## As a part (a handle, a binding), the TRAIT it offers a TOOL it is made into (Tinkers'-style: the handle's
## wood; oak: Steady, yew: Springy; template DECISIONS #275). The player picks which offered traits the item
## keeps, as many as its grade holds (owner, 2026-10-23). The name is from when only handles had one.
@export var handle_trait: TraitDef
## The trait it offers a WEAPON (oak: Heavy, iron rivets: Brutal). An item that is both (an axe) takes the
## tool's. None: nothing for weapons.
@export var part_weapon_trait: TraitDef
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
@export_group("In the material table")
## A CELL of the material table (`docs/regents_rule/MATERIALS.md`): made of this material in this
## pattern. `MaterialTable` keeps its name, stack, tool, weapon, part and trait as the two say (Make the
## table); its colour, looks and words are yours. Both empty: an item written by hand (ore, rivets).
@export var material: MaterialDef
@export var pattern: PatternDef
## The cell is yours: the table leaves it and its recipe alone (an alloy made from two ores, say).
@export var by_hand: bool = false

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
		"weapon_trait": ContentDef.ref(part_weapon_trait),
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


## THE TRAITS a bag row's item has (`"t":[ids]` in its `instance_data`; `"t":[]` none ON PURPOSE, chosen at
## the station). A tool made before traits were (it noted only its handle, `"h"`) has its handle's. The
## server's twin: `traits_of_row`.
static func trait_ids(instance_data: String) -> Array[int]:
	var ids: Array[int] = Traits.ids_of(instance_data)
	if ids.is_empty() and not instance_data.contains("\"t\":["):
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
	if part_weapon_trait != null and not _for_weapons(part_weapon_trait):
		out.append("its weapon trait (%s) is not one a weapon may have: its `applies_to` names no weapon" % part_weapon_trait.display_name)
	if part_tag == &"" and part_weapon_trait != null:
		out.append("it has a weapon trait but is no part: set `part_tag`")
	if (material == null) != (pattern == null):
		out.append("a cell of the material table names both its material and its pattern (or neither: an item by hand)")
	if by_hand and material == null:
		out.append("`by_hand` is for a cell of the material table; an item with no material is by hand already")
	if weapon_kit != &"":
		# Tier dominates (owner, 2026-10-20): against every other weapon of its kit.
		var kin: Array[ItemDef] = [self]
		for d: ContentDef in RegentsContent.items(&"item"):
			var other: ItemDef = d as ItemDef
			if other != null and other.id != id and other.weapon_kit == weapon_kit:
				kin.append(other)
		out.append_array(RegentsGrade.tier_overlaps(kin).duplicate())
	return out


## Whether trait `t` is one a weapon may have (any of "weapon", "melee", "bow", "staff").
static func _for_weapons(t: TraitDef) -> bool:
	for tag: StringName in [&"weapon", &"melee", &"bow", &"staff"]:
		if t.applies_to.has(tag):
			return true
	return false


## THE TRAIT this part offers `made` (what it is assembled into): the tool trait for a tool (an axe too), else
## the weapon trait for a weapon; only one that fits `made` (`TraitDef.applies_to` against its tags). Null for
## none. The server's twin: `offered_for` (genre/regents/mod.rs).
func trait_for(made: ItemDef) -> TraitDef:
	if made == null:
		return null
	var t: TraitDef = handle_trait if made.tool_tag != &"" else (part_weapon_trait if made.weapon_kit != &"" else null)
	if t == null:
		return null
	for tag: StringName in made.tags():
		if t.applies_to.has(tag):
			return t
	return null


## WHAT IT IS MADE INTO (owner, 2026-10-23: "more intuitive ... as to what you can expect when you get to the
## workbench"): every recipe's output that takes it, or takes any part of its kind; names, sorted.
func uses() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for r: RecipeDef in RecipeDef.all():
		if r.output == null:
			continue
		var takes_it: bool = r.inputs.has(self)
		for slot: int in r.pick_slots():
			takes_it = takes_it or (part_tag != &"" and r.inputs[slot] != null and r.inputs[slot].part_tag == part_tag)
		if takes_it and not out.has(r.output.display_name):
			out.append(r.output.display_name)
	out.sort()
	return out


## The part's traits in words: "On tools: Steady (gives; costs)", "On weapons: Heavy (...)"; empty for none.
func part_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for pair: Array in [["tools", handle_trait], ["weapons", part_weapon_trait]]:
		var t: TraitDef = pair[1]
		if t != null:
			out.append("On %s: %s (%s%s)" % [pair[0], t.display_name, t.gives, "; " + t.costs if not t.costs.is_empty() else ""])
	return out


## ITS TOOLTIP: its name, its words, the traits it gives as a part (only the one for `made`, when given), and
## what it is made into.
func tooltip_for(made: ItemDef = null) -> String:
	var lines: PackedStringArray = PackedStringArray([display_name])
	if not description.is_empty():
		lines.append(description)
	if made != null:
		var t: TraitDef = trait_for(made)
		lines.append("On the %s: %s" % [made.display_name.to_lower(), "%s (%s%s)" % [t.display_name, t.gives, "; " + t.costs if not t.costs.is_empty() else ""] if t != null else "no trait"])
	else:
		lines.append_array(part_lines())
	var u: PackedStringArray = uses()
	if not u.is_empty():
		lines.append("Makes: " + ", ".join(u))
	return "\n".join(lines)


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
