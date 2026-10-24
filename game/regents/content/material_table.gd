@tool
class_name MaterialTable extends RefCounted
## THE MATERIAL TABLE (`docs/regents_rule/MATERIALS.md` §2, owner 2026-10-23): every material
## (`MaterialDef`) crossed with every pattern of its family (`PatternDef`) is a CELL, a real item with its
## recipe, so the bag, loot lines, stacks, the tool picker and Power work on cells as on any item.
##
## Cells are ordinary content files (`content/item/`, `content/recipe/`), marked (`ItemDef.material` and
## `pattern`, `RecipeDef.from_table`), so the bake, the server and the client need nothing new. Making
## the table (`generate`: Make the table on any material or pattern, or
## `game/regents/tools/make_material_table.gd`) writes the cells that are missing and sets, on the ones
## there, only what the table decides:
##   an item     its name, stack, tool and tier, weapon and Power, part and trait (`ITEM_FIELDS`)
##   a recipe    its name, station, skill, inputs, output, how many it makes, quality, part slots
##               (`RECIPE_FIELDS`)
## Everything else is the designer's and stays: an item's id, colour, looks and words; a recipe's id, XP,
## rank, AFK time, how many of each input, its round. A new cell starts those from its pattern and
## material ("New cells start with"). A cell written by hand (`ItemDef.by_hand`) is left alone.
## A file is never deleted: a cell the table no longer makes is a problem to settle by hand (its id may
## be in players' bags). The bake refuses a table out of date (`MaterialDef.validate_with`: `problems`).

const ITEM_FIELDS: PackedStringArray = ["display_name", "max_stack", "tool_tag", "tool_tier", "tool_speed_pct",
	"weapon_kit", "weapon_damage_pct", "part_tag", "handle_trait", "part_weapon_trait"]
const RECIPE_FIELDS: PackedStringArray = ["display_name", "station", "skill", "inputs", "output", "output_qty",
	"quality", "part_slot", "part_slots"]
const HOW: String = "Make the table (the button on any material or pattern)"


## Every material, by id.
static func materials() -> Array[MaterialDef]:
	var out: Array[MaterialDef] = []
	for d: ContentDef in ContentLibrary.items(&"material"):
		if d is MaterialDef:
			out.append(d as MaterialDef)
	return out


## Every pattern, by id.
static func patterns() -> Array[PatternDef]:
	var out: Array[PatternDef] = []
	for d: ContentDef in ContentLibrary.items(&"pattern"):
		if d is PatternDef:
			out.append(d as PatternDef)
	return out


## THE TABLE: every cell there should be, [{material, pattern}], by material then pattern.
static func plan() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ps: Array[PatternDef] = patterns()
	for m: MaterialDef in materials():
		for p: PatternDef in ps:
			if p.made_of(m):
				out.append({"material": m, "pattern": p})
	return out


## The items that are cells of `m` (by id), whatever their pattern.
static func cells_of(m: MaterialDef) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for it: ItemDef in _items():
		if m != null and it.material != null and it.material.id == m.id:
			out.append(it)
	return out


## THE CELL of `m` in `p`, or null.
static func cell(m: MaterialDef, p: PatternDef) -> ItemDef:
	var found: Array[ItemDef] = _cells(_items(), m, p)
	return found[0] if not found.is_empty() else null


## What the table makes the cell of `m` in `p`: {field: value} over `ITEM_FIELDS`.
static func item_wants(m: MaterialDef, p: PatternDef) -> Dictionary:
	var tool: bool = p.tool_tag != &""
	var weapon: bool = p.weapon_kit != &""
	return {
		"display_name": p.item_name(m),
		"max_stack": p.max_stack,
		"tool_tag": p.tool_tag,
		"tool_tier": m.tier if tool else 0,
		"tool_speed_pct": m.tool_speed_pct if tool else 100,
		"weapon_kit": p.weapon_kit,
		"weapon_damage_pct": m.weapon_damage_pct if weapon else 100,
		"part_tag": p.part_tag,
		"handle_trait": m.part_trait if p.carries_trait else null,
		"part_weapon_trait": m.part_weapon_trait if p.carries_trait else null,
	}


## What the table makes the recipe of the cell `made` (of `m` in `p`): {field: value} over
## `RECIPE_FIELDS`, plus "input_qty" (a new recipe's, or one whose inputs changed). `cells` finds the
## other cells its slots take ("<material id>:<pattern id>" -> item). A slot it cannot fill adds to `errors`.
static func recipe_wants(m: MaterialDef, p: PatternDef, made: ItemDef, cells: Dictionary, errors: Array[String]) -> Dictionary:
	var ins: Array[ItemDef] = []
	var qty: PackedInt32Array = PackedInt32Array()
	for s: PartSlot in p.parts:
		var it: ItemDef = null
		match s.takes:
			PartSlot.Takes.RAW:
				it = m.raw
				if it == null:
					errors.append("%s has no raw form (`raw`), so its %s cannot take one: make that cell by hand (`by_hand`)" % [m.display_name, p.display_name])
			PartSlot.Takes.SAME_MATERIAL:
				it = cells.get(_k(m, s.pattern), null)
				if it == null:
					errors.append("%s's %s takes %s's %s, which the table does not make (a hole in %s?)" % [m.display_name, p.display_name, m.display_name, _name(s.pattern), _name(s.pattern)])
			PartSlot.Takes.ANY_MATERIAL:
				it = cells.get(_k(s.default_material, s.pattern), null)
				if it == null:
					errors.append("%s's %s slot lists %s's %s, which the table does not make" % [p.display_name, s.name, _name(s.default_material), _name(s.pattern)])
			PartSlot.Takes.ITEM:
				it = s.item
		ins.append(it)
		qty.append(s.qty)
	return {
		"display_name": p.item_name(m),
		"station": p.station,
		"skill": p.skill,
		"inputs": ins,
		"output": made,
		"output_qty": p.output_qty,
		"quality": p.quality,
		"part_slot": p.pick_slot(),
		"part_slots": p.pick_slots(),
		"input_qty": qty,
	}


## WHAT IS OUT OF DATE, one sentence each, naming what to do: a cell missing, a cell or its recipe not
## as the table makes it, a cell or recipe the table no longer makes. `only`: the problems of that
## material's cells (what its `validate_with` reports); null for all.
static func problems(only: MaterialDef = null) -> Array[String]:
	var out: Array[String] = []
	var items: Array[ItemDef] = _items()
	var recipes: Array[RecipeDef] = _recipes()
	var cells: Dictionary = _index(items)
	var planned: Dictionary = {}
	for c: Dictionary in plan():
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		planned[_k(m, p)] = true
		if only != null and m.id != only.id:
			continue
		var found: Array[ItemDef] = _cells(items, m, p)
		if found.is_empty():
			out.append("its %s (%s) has no cell yet: %s" % [p.display_name, p.item_name(m), HOW])
			continue
		if found.size() > 1:
			out.append("two items are its %s: %s" % [p.display_name, " and ".join(PackedStringArray(found.map(func(i: ItemDef) -> String: return _file(i))))])
			continue
		var it: ItemDef = found[0]
		if it.by_hand:
			continue
		var drift: Array[String] = _drift(it, item_wants(m, p))
		if not drift.is_empty():
			out.append("%s is not what the table makes it (%s): %s" % [_file(it), "; ".join(drift), HOW])
		var made_by: Array[RecipeDef] = _recipes_of(recipes, it)
		# Why the table cannot make its recipe at all (no ore to take) comes first: making it would not help.
		var errs: Array[String] = []
		var wants: Dictionary = recipe_wants(m, p, it, cells, errs)
		if made_by.size() > 1:
			out.append("%s has %d recipes from the table: %s; untick `from_table` on all but one" % [_file(it), made_by.size(), ", ".join(PackedStringArray(made_by.map(func(r: RecipeDef) -> String: return _file(r))))])
		elif not errs.is_empty():
			out.append_array(errs)
		elif made_by.is_empty():
			out.append("%s has no recipe from the table: %s" % [_file(it), HOW])
		else:
			var rd: Array[String] = _drift(made_by[0], wants)
			if not rd.is_empty():
				out.append("%s is not what the table makes it (%s): %s" % [_file(made_by[0]), "; ".join(rd), HOW])
	for it: ItemDef in items:
		if it.material == null or it.pattern == null or it.by_hand or planned.has(_k(it.material, it.pattern)):
			continue
		if only == null or it.material.id == only.id:
			out.append("%s is a cell of %s in %s, which the table does not make: tick its `by_hand` to keep it as it is, or make the pattern of %s again" % [_file(it), it.material.display_name, it.pattern.display_name, it.material.display_name])
	return out


## MAKE THE TABLE: write every missing cell and recipe, and set what the table decides on the others
## (saving only what changed). Returns {made: [paths], updated: [paths], errors: [sentences], lines: [the
## report]}. With `write` false it saves nothing (what would change, for a check).
static func generate(write: bool = true) -> Dictionary:
	var made: Array[String] = []
	var updated: Array[String] = []
	var errors: Array[String] = []
	var items: Array[ItemDef] = _items()
	var recipes: Array[RecipeDef] = _recipes()
	var cells: Dictionary = _index(items)
	var next_item: int = -1
	var next_recipe: int = -1
	var table: Array[Dictionary] = plan()
	# The items first: a recipe's slots take other cells (an iron axe takes the iron axe head).
	for c: Dictionary in table:
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		var found: Array[ItemDef] = _cells(items, m, p)
		if found.size() > 1:
			errors.append("two items are %s's %s: %s" % [m.display_name, p.display_name, " and ".join(PackedStringArray(found.map(func(i: ItemDef) -> String: return _file(i))))])
			continue
		var it: ItemDef = found[0] if not found.is_empty() else null
		if it != null and it.by_hand:
			continue
		if it == null:
			var owner: String = _owner_of(m)
			if next_item < 0:
				next_item = ContentLibrary.next_free_id(&"item", owner)
			it = ItemDef.new()
			it.id = next_item
			next_item += 1
			it.material = m
			it.pattern = p
			it.color = m.color
			it.held_scene = p.held_scene
			it.description = p.description.replace("{m}", m.prefix).strip_edges()
			it.designer_notes = "A CELL OF THE MATERIAL TABLE (%s in %s): made by Make the table." % [m.display_name, p.display_name]
			_apply(it, item_wants(m, p))
			var path: String = _new_path(&"item", owner, it.display_name) if write else "(new) " + it.display_name
			if write and not _save(it, path, errors):
				continue
			made.append(path)
			cells[_k(m, p)] = it
			continue
		if not _drift(it, item_wants(m, p)).is_empty():
			if write:
				_apply(it, item_wants(m, p))
				if not _save(it, it.resource_path, errors):
					continue
			updated.append(it.resource_path)
	for c: Dictionary in table:
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		var it: ItemDef = cells.get(_k(m, p), null)
		if it == null or it.by_hand:
			continue
		var made_by: Array[RecipeDef] = _recipes_of(recipes, it)
		if made_by.size() > 1:
			errors.append("%s has %d recipes from the table; untick `from_table` on all but one" % [_file(it), made_by.size()])
			continue
		var errs: Array[String] = []
		var wants: Dictionary = recipe_wants(m, p, it, cells, errs)
		if not errs.is_empty():
			errors.append_array(errs)
			continue
		if made_by.is_empty():
			var owner: String = _owner_of(m)
			if next_recipe < 0:
				next_recipe = ContentLibrary.next_free_id(&"recipe", owner)
			var r: RecipeDef = RecipeDef.new()
			r.id = next_recipe
			next_recipe += 1
			r.from_table = true
			r.xp = p.xp * m.work_scale_pct / 100
			r.afk_ms = clampi(snappedi(p.afk_ms * m.work_scale_pct / 100, 100), 500, 120000)
			r.min_rank = maxi(1, m.rank)
			r.minigame = p.minigame.duplicate(true) if p.minigame != null else null
			r.designer_notes = "THE RECIPE OF A CELL OF THE MATERIAL TABLE (%s in %s): its numbers are yours to tune." % [m.display_name, p.display_name]
			_apply(r, wants)
			r.input_qty = wants["input_qty"]
			var path: String = _new_path(&"recipe", owner, r.display_name) if write else "(new) recipe " + r.display_name
			if write and not _save(r, path, errors):
				continue
			made.append(path)
			continue
		var rec: RecipeDef = made_by[0]
		var inputs_moved: bool = rec.inputs.size() != (wants["inputs"] as Array).size()
		if not _drift(rec, wants).is_empty():
			if write:
				_apply(rec, wants)
				if inputs_moved:
					rec.input_qty = wants["input_qty"]
				if not _save(rec, rec.resource_path, errors):
					continue
			updated.append(rec.resource_path)
	var lines: Array[String] = []
	lines.append("the material table: %d cell(s), %d made, %d brought up to date%s" % [table.size(), made.size(), updated.size(), "" if write else " (a dry run)"])
	for path: String in made:
		lines.append("  made     " + path.trim_prefix("res://"))
	for path: String in updated:
		lines.append("  updated  " + path.trim_prefix("res://"))
	if write:
		RegentsContent.clear()
	return {"made": made, "updated": updated, "errors": errors, "lines": lines}


## In the editor, make the FileSystem dock see the files just written.
static func rescan_editor() -> void:
	if not Engine.is_editor_hint() or not Engine.has_singleton(&"EditorInterface"):
		return
	var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
	if fs != null:
		fs.call(&"scan")


## The fields of `def` that are not `wants`' ("weapon_damage_pct: has 90, makes 100").
static func _drift(def: Object, wants: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for f: String in wants:
		if f == "input_qty":
			continue
		var has: Variant = def.get(f)
		if not _same(has, wants[f]):
			out.append("%s: has %s, makes %s" % [f, _show(has), _show(wants[f])])
	return out


static func _apply(def: Object, wants: Dictionary) -> void:
	for f: String in wants:
		if f == "input_qty":
			continue
		if f == "inputs":
			var arr: Array[ItemDef] = []
			for x: Variant in wants[f] as Array:
				arr.append(x as ItemDef)
			def.set(f, arr)
		else:
			def.set(f, wants[f])


## Equal as the table means it: content by id (a cached copy and a fresh one are one piece), arrays
## piece by piece, the rest by value.
static func _same(a: Variant, b: Variant) -> bool:
	if a is ContentDef or b is ContentDef:
		return a is ContentDef and b is ContentDef and (a as ContentDef).id == (b as ContentDef).id \
			and (a as ContentDef).content_type() == (b as ContentDef).content_type()
	if a == null or b == null:
		return a == null and b == null
	if a is Array and b is Array:
		var x: Array = a
		var y: Array = b
		if x.size() != y.size():
			return false
		for i: int in x.size():
			if not _same(x[i], y[i]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	return typeof(a) == typeof(b) and a == b


static func _show(v: Variant) -> String:
	if v is ContentDef:
		return (v as ContentDef).display_name
	if v is Array:
		return "[%s]" % ", ".join(PackedStringArray((v as Array).map(func(x: Variant) -> String: return _show(x))))
	if v == null:
		return "none"
	if v is String or v is StringName:
		return "\"%s\"" % v
	return str(v)


static func _k(m: MaterialDef, p: PatternDef) -> String:
	return "%d:%d" % [m.id if m != null else -1, p.id if p != null else -1]


static func _name(d: ContentDef) -> String:
	return d.display_name if d != null else "?"


static func _file(d: Resource) -> String:
	return d.resource_path.get_file() if not d.resource_path.is_empty() else "a new piece"


static func _items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for d: ContentDef in ContentLibrary.items(&"item"):
		if d is ItemDef:
			out.append(d as ItemDef)
	return out


static func _recipes() -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for d: ContentDef in ContentLibrary.items(&"recipe"):
		if d is RecipeDef:
			out.append(d as RecipeDef)
	return out


static func _cells(items: Array[ItemDef], m: MaterialDef, p: PatternDef) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for it: ItemDef in items:
		if it.material != null and it.pattern != null and it.material.id == m.id and it.pattern.id == p.id:
			out.append(it)
	return out


## Every cell there is, by "<material id>:<pattern id>" (the first, when two claim one).
static func _index(items: Array[ItemDef]) -> Dictionary:
	var out: Dictionary = {}
	for it: ItemDef in items:
		if it.material != null and it.pattern != null and not out.has(_k(it.material, it.pattern)):
			out[_k(it.material, it.pattern)] = it
	return out


static func _recipes_of(recipes: Array[RecipeDef], it: ItemDef) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for r: RecipeDef in recipes:
		if r.from_table and r.output != null and r.output.id == it.id:
			out.append(r)
	return out


static func _owner_of(m: MaterialDef) -> String:
	var owner: String = ContentLibrary.owner_of_path(m.resource_path)
	return owner if not owner.is_empty() else "regents"


static func _new_path(type: StringName, owner: String, display_name: String) -> String:
	var folder: String = ContentLibrary.folder_for(type, owner)
	var stem: String = ContentLibrary.file_stem(display_name)
	var path: String = folder.path_join(stem + ".tres")
	var n: int = 2
	while FileAccess.file_exists(path):
		path = folder.path_join("%s_%d.tres" % [stem, n])
		n += 1
	return path


static func _save(def: Resource, path: String, errors: Array[String]) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err: Error = ResourceSaver.save(def, path)
	if err != OK:
		errors.append("could not save %s: %s" % [path, error_string(err)])
		return false
	# A new piece must know its file before anything links to it: else a recipe saved after it carries a
	# copy of it inside (no file, no id), which the bake refuses. (`FLAG_CHANGE_PATH` did not set it.)
	if def.resource_path != path:
		def.take_over_path(path)
	return true
