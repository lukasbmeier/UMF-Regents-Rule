@tool
class_name PatternDef extends ContentDef
## A PATTERN (`docs/regents_rule/MATERIALS.md`, owner 2026-10-23): a bar, an axe head, a handle, an axe.
## One column of the MATERIAL TABLE: crossed with every material of its family (`MaterialDef`), each cell
## is a real item ("Iron axe head") and the recipe that makes it from the pattern's PARTS (`PartSlot`: a
## head, a handle, a binding; as many as it needs). What the item IS (its kit, its tool, how it stacks)
## is the pattern's; its tier, Power and trait are the material's (`MaterialTable`).

## Its key ("axe_head", "handle"), unique among patterns.
@export var key: StringName = &""
## Its items' names: `{m}` is the material's prefix ("{m} axe head": "Iron axe head").
@export var name_format: String = "{m}"
## The materials it is made of (its core's family).
@export var family: MaterialDef.Family = MaterialDef.Family.METAL
## Holes in the table: materials of its family it is NOT made of (no copper axe head yet).
@export var not_made_of: Array[MaterialDef] = []
@export_group("The item")
## How many fit in one bag slot (1: a part with a quality, a tool, a weapon).
@export_range(1, 100000) var max_stack: int = 1000
## A tool's tag ("axe", "pick"): its cells work nodes up to their material's tier. Empty: not a tool.
@export var tool_tag: StringName = &""
## A weapon's kit ("sword", "axe"): its cells fight with it at their material's Power. Empty: not a weapon.
@export var weapon_kit: StringName = &""
## A part's kind ("handle"): another pattern's player-picked slot takes any item of it.
@export var part_tag: StringName = &""
## Its cells give their material's trait (a handle: oak's Steady).
@export var carries_trait: bool = false
@export_group("The recipe")
## The station it is made at ("furnace", "anvil", "workbench").
@export var station: StringName = &"workbench"
## The skill it trains.
@export var skill: SkillDef
## What it takes, slot by slot.
@export var parts: Array[PartSlot] = []
## How many a batch makes.
@export_range(1, 1000) var output_qty: int = 1
## Where a made one's quality comes from (none: it stacks).
@export var quality: RecipeDef.Quality = RecipeDef.Quality.NONE
@export_group("New cells start with")
## A new cell's recipe XP and AFK time, before its material's `work_scale_pct` (then tune the recipe).
@export_range(0, 10000) var xp: int = 10
@export_range(500, 120000, 100, "suffix:ms") var afk_ms: int = 3000
## A new cell's round (a copy: then tune it on the recipe), none: AFK only.
@export var minigame: Resource
## A new cell's look in the hand, and its words (`{m}` is the material's prefix).
@export var held_scene: PackedScene
@export_multiline var description: String = ""
@export_group("")
## MAKE THE TABLE (as on a material): writes every cell that is missing or out of date.
@export_tool_button("Make the table", "Reload") var make_table: Callable = _make_table


func content_type() -> StringName:
	return &"pattern"


func why_no_workbench() -> String:
	return "the Materials bench (the table as a grid) is MATERIALS.md step 7; until then Make the table, and the items' own"


func summary() -> String:
	var names: PackedStringArray = PackedStringArray()
	for s: PartSlot in parts:
		if s != null:
			names.append("%d %s" % [s.qty, s.name])
	return "%s: %s" % [station, ", ".join(names)]


func to_bake() -> Dictionary:
	var slots: Array = []
	for s: PartSlot in parts:
		slots.append(s.to_bake() if s != null else {})
	var skips: Array = []
	for m: MaterialDef in not_made_of:
		skips.append(ContentDef.ref(m))
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"name_format": name_format,
		"family": int(family),
		"not_made_of": skips,
		"max_stack": max_stack,
		"tool_tag": String(tool_tag),
		"weapon_kit": String(weapon_kit),
		"part_tag": String(part_tag),
		"carries_trait": carries_trait,
		"station": String(station),
		"skill": ContentDef.ref(skill),
		"parts": slots,
		"output_qty": output_qty,
		"quality": int(quality),
	}


## Its cell's name for `m`: "{m} axe head" with "Iron" is "Iron axe head", with "" is "Axe head".
func item_name(m: MaterialDef) -> String:
	var s: String = name_format.replace("{m}", m.prefix if m != null else "").strip_edges()
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.left(1).to_upper() + s.substr(1)


## Whether `m` has a cell in this column: its family, and not one of the holes.
func made_of(m: MaterialDef) -> bool:
	if m == null or m.family != family:
		return false
	for x: MaterialDef in not_made_of:
		if x != null and x.id == m.id:
			return false
	return true


## The slots the player picks at the station (the recipe's part slots), in order.
func pick_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in parts.size():
		if parts[i] != null and parts[i].takes == PartSlot.Takes.ANY_MATERIAL:
			out.append(i)
	return out


## The first slot the player picks (the recipe's `part_slot`, for older builds), or -1.
func pick_slot() -> int:
	var all: PackedInt32Array = pick_slots()
	return all[0] if not all.is_empty() else -1


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (\"axe_head\", \"handle\")")
	if not name_format.contains("{m}"):
		out.append("its `name_format` has no {m}, so every material's cell has one name")
	if skill == null:
		out.append("its recipe trains no skill: set `skill`")
	if parts.is_empty() or parts.has(null):
		out.append("its recipe takes nothing (or an empty slot): set `parts`")
	var cores: int = 0
	for s: PartSlot in parts:
		if s == null:
			continue
		out.append_array(s.validate())
		cores += 1 if s.core else 0
		if s.pattern != null and s.pattern.id == id and s.takes != PartSlot.Takes.RAW and s.takes != PartSlot.Takes.ITEM:
			out.append("its %s slot takes its own pattern" % s.name)
	if cores != 1:
		out.append("one slot is its core (the material's own), not %d: tick `core` on one" % cores)
	if (tool_tag != &"" or weapon_kit != &"" or quality != RecipeDef.Quality.NONE) and max_stack != 1:
		out.append("a tool, a weapon or an item with a quality does not stack: `max_stack` 1")
	if carries_trait and part_tag == &"":
		out.append("its cells carry their material's trait but are no part: set `part_tag` (\"handle\")")
	if quality == RecipeDef.Quality.FROM_ROUND and minigame == null:
		out.append("its quality comes from a round it does not start with: set `minigame`")
	for m: MaterialDef in not_made_of:
		if m != null and m.family != family:
			out.append("%s is not of its family, so it is no hole in it" % m.display_name)
	return out


func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	for d: ContentDef in all_of_type:
		var p: PatternDef = d as PatternDef
		if p != null and p.id != id and p.key == key:
			out.append("its key \"%s\" is %s's too" % [key, p.display_name])
	return out


func _make_table() -> void:
	var result: Dictionary = MaterialTable.generate()
	for line: String in result["lines"] as Array:
		print(line)
	for e: String in result["errors"] as Array:
		push_error("Make the table: " + e)
	MaterialTable.rescan_editor()
