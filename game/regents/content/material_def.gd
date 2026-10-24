@tool
class_name MaterialDef extends ContentDef
## A MATERIAL (`docs/regents_rule/MATERIALS.md`, owner 2026-10-23): iron, copper, oak, yew. One row of the
## MATERIAL TABLE: crossed with every pattern of its family (`PatternDef`: a bar, an axe head, a handle),
## each cell is a real item with its recipe, made by `MaterialTable` (Make the table, below). Adding a
## material is this one resource: its cells appear with its tier, its Power and its trait.
##
## As a CORE (the head, the blade; the wood of a bow later) it sets the made item's tier and Power. As a
## SECONDARY part (a handle) it gives its trait.

enum Family { METAL, WOOD }

## Its key ("iron", "oak"), unique among materials.
@export var key: StringName = &""
## The word for it in its items' names ("Iron" makes "Iron axe head"; empty for plain wood: "Handle").
@export var prefix: String = ""
## Which patterns it is made into (a pattern of the same family).
@export var family: Family = Family.METAL
## ITS TIER: the material level (`LOOT_AND_STYLES.md` §0). A tool's tier, the band of a weapon's Power.
@export_range(1, 20) var tier: int = 1
## What it is gathered as (iron ore, oak logs): its bar or its handle is made from this. None for an alloy
## (steel): then its cells that take it are made by hand (`ItemDef.by_hand`).
@export var raw: ItemDef
@export_group("As a core")
## A weapon's damage at this tier, in percent of its kit's (the tier's Power: iron 100). Tier dominates:
## the best of one tier never reaches the worst of the next (an item's `validate` checks).
@export_range(10, 500, 1, "suffix:%") var weapon_damage_pct: int = 100
## A tool's work time at this tier, in percent of the base (iron 85: quicker).
@export_range(10, 200, 1, "suffix:%") var tool_speed_pct: int = 100
@export_group("As a secondary part")
## The trait it offers a TOOL as a secondary part (oak: Steady). None: a plain part.
@export var part_trait: TraitDef
## The trait it offers a WEAPON as a secondary part (oak: Heavy, iron: Brutal). An axe is a tool first.
@export var part_weapon_trait: TraitDef
@export_group("New cells start with")
## A new cell's recipe: the pattern's XP and AFK time in percent (harder materials, more of both).
@export_range(10, 1000, 1, "suffix:%") var work_scale_pct: int = 100
## A new cell's recipe needs this rank at least (the rank its node needs).
@export_range(1, 99) var rank: int = 1
## A new cell's colour in the bag, until it has an icon.
@export var color: Color = Color(0.7, 0.7, 0.7)
@export_group("")
## MAKE THE TABLE: writes every cell of every material and pattern that is missing or out of date (what
## `MaterialTable` decides; your tuned numbers stay). The bake refuses a table that is out of date.
@export_tool_button("Make the table", "Reload") var make_table: Callable = _make_table


func content_type() -> StringName:
	return &"material"


func why_no_workbench() -> String:
	return "the Materials bench (the table as a grid) is MATERIALS.md step 7; until then Make the table, and the items' own"


func summary() -> String:
	return "%s, tier %d: %d cell(s)" % [Family.keys()[family].capitalize(), tier, MaterialTable.cells_of(self).size()]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"prefix": prefix,
		"family": int(family),
		"tier": tier,
		"raw": ContentDef.ref(raw),
		"weapon_damage_pct": weapon_damage_pct,
		"tool_speed_pct": tool_speed_pct,
		"part_trait": ContentDef.ref(part_trait),
		"part_weapon_trait": ContentDef.ref(part_weapon_trait),
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (\"iron\", \"oak\")")
	if part_trait != null and not part_trait.applies_to.has(&"tool"):
		out.append("its part trait (%s) is not one a tool may have: its `applies_to` lacks \"tool\"" % part_trait.display_name)
	if part_weapon_trait != null and not ItemDef._for_weapons(part_weapon_trait):
		out.append("its weapon trait (%s) is not one a weapon may have" % part_weapon_trait.display_name)
	return out


## Keys are unique; and THE TABLE'S CELLS OF THIS MATERIAL are as `MaterialTable` would make them (the
## bake refuses a table out of date, naming what to do).
func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	for d: ContentDef in all_of_type:
		var m: MaterialDef = d as MaterialDef
		if m != null and m.id != id and m.key == key:
			out.append("its key \"%s\" is %s's too" % [key, m.display_name])
	out.append_array(MaterialTable.problems(self))
	return out


func _make_table() -> void:
	var result: Dictionary = MaterialTable.generate()
	for line: String in result["lines"] as Array:
		print(line)
	for e: String in result["errors"] as Array:
		push_error("Make the table: " + e)
	MaterialTable.rescan_editor()


## The material with key `material_key`, or null.
static func by_key(material_key: StringName) -> MaterialDef:
	for d: ContentDef in RegentsContent.items(&"material"):
		var m: MaterialDef = d as MaterialDef
		if m != null and m.key == material_key:
			return m
	return null
