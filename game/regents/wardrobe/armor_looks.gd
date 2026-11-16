@tool
class_name ArmorLooks extends Resource
## HOW WORN ARMOR LOOKS (W2; Luke's W1-W4, `GAME.md` "W1-W8 ANSWERED"): the one table a designer edits,
## `game/regents/wardrobe/armor_looks.tres`. Its `entries` say which outfit pieces each armor pattern puts on (metal:
## the Knight's; leather: the Ranger's; cloth: the Wizard's); its `palettes` say which palette each MATERIAL wears
## (metal by its bar, leather by its animal, cloth by its fiber). A new armor piece made of a known pattern and
## material needs nothing here; a new pattern needs a row, a new material a palette.
##
## Read by `ArmorLookComponent`, which hands `dress_for`'s answer to `RegentsFigure.wear_armor`. Presentation only.

const PATH: String = "res://game/regents/wardrobe/armor_looks.tres"
## The `worn` row's columns, in the order a palette is chosen (the last wins for an outfit worn twice: the chest's).
const SLOT_COLUMNS: Array[StringName] = [&"head_item", &"legs_item", &"chest_item", &"trinket_item"]

@export var entries: Array[ArmorLookEntry] = []
## Material key (copper, iron, steel, soft_leather, supple_leather, linen) -> the palette its pieces wear.
@export var palettes: Dictionary[StringName, DyePalette] = {}

static var _current: ArmorLooks = null


## The game's table.
static func current() -> ArmorLooks:
	if _current == null:
		_current = load(PATH) as ArmorLooks
	return _current


## The row for `pattern` in `material` (its own row first, else the pattern's), or null.
func entry_for(pattern: StringName, material: StringName) -> ArmorLookEntry:
	var any: ArmorLookEntry = null
	for e: ArmorLookEntry in entries:
		if e == null or e.pattern != pattern:
			continue
		if e.material == material and not material.is_empty():
			return e
		if e.material.is_empty():
			any = e
	return any


## WHAT A BODY WEARS for the items `items` (the `worn` row's item ids, any order; 0 for nothing) on `body`:
## [pieces: {slot: PackedScene or null}, palettes: {outfit: DyePalette}]. An item that is not armor, or has no
## material or pattern (the practice pieces), puts on nothing. A helm that hides the hair takes it off
## (`Wardrobe.HIDES_HAIR`: a closed helm the hair and beard, a hood the hair).
func dress_for(items: Array[int], body: StringName) -> Array:
	var pieces: Dictionary[StringName, PackedScene] = {}
	var outfit_palettes: Dictionary[String, DyePalette] = {}
	for id: int in items:
		if id == 0:
			continue
		var it: ItemDef = ItemDef.by_id(id)
		if it == null or it.armor_slot.is_empty() or it.material == null or it.pattern == null:
			continue
		var e: ArmorLookEntry = entry_for(it.pattern.key, it.material.key)
		if e == null:
			continue
		var palette: DyePalette = palettes.get(it.material.key, null) as DyePalette
		var wanted: Dictionary[StringName, String] = e.pieces_for(body)
		for slot: StringName in wanted:
			var file: String = wanted[slot]
			var path: String = piece_path(file)
			pieces[slot] = load(path) as PackedScene if not path.is_empty() else null
			if not path.is_empty() and palette != null:
				outfit_palettes[outfit_of(file)] = palette
			if slot == &"head":
				for part: String in Wardrobe.HIDES_HAIR:
					if file.ends_with(part):
						pieces[&"hairstyle"] = null
						if Wardrobe.HIDES_HAIR[part] == "all":
							pieces[&"beard"] = null
	return [pieces, outfit_palettes]


## A piece file's path among `Wardrobe.PIECE_DIRS`, or "" (none, or "" asked).
static func piece_path(file: String) -> String:
	if file.is_empty():
		return ""
	for dir: String in Wardrobe.PIECE_DIRS:
		if ResourceLoader.exists(dir + file + ".gltf"):
			return dir + file + ".gltf"
	return ""


## The outfit a piece file is from ("Male_Knight_Arms" -> Knight).
static func outfit_of(file: String) -> String:
	var bits: PackedStringArray = file.split("_", false, 2)
	return bits[1] if bits.size() >= 2 else ""
