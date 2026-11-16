@tool
class_name RegentsFigure extends ModularCharacter
## A PLAYER'S BODY IN REGENT'S RULE (W1; Luke 2026-11-14, `GAME.md` "THE WARDROBE: WHO WEARS WHAT", W2, W4, W8):
## the root of the genre's two looks (`game/regents/looks/peasant_m.tscn`, `peasant_f.tscn`), which are all the
## adventurer offers. EVERY PLAYER STARTS IN THE PEASANT CLOTHES in colors of their own (`RegentsColors`, keys on the
## `appearance` text), with hair, beard, brows and skin as the foundation offers them. No other outfit is picked:
## Ranger, Wizard and Knight are ARMOR, worn later (the `worn` table, W2); the Noble is for NPCs.
##
## THE ONE PLACE THAT DECIDES WHAT A BODY WEARS AND IN WHICH PALETTE:
##   - its pieces: the look's own Peasant pieces, with ARMOR over them through `wear_armor` (slot -> piece scene, the
##     foundation's `wear`): a slot with no armor shows the player's own Peasant piece (W4);
##   - its palettes, per outfit (`palette_for`): an armor outfit's tier palette from `outfit_palettes` (W2 sets them:
##     leather by animal, cloth by fiber, metal by bar), every other outfit (the Peasant) in the player's colors;
##   - dressed after EVERY assembly and re-dress (the foundation's `assembled`, DECISIONS #313), so a reassembly
##     never loses the colors, with materials SHARED by palette (`Wardrobe.dress_shared`: 300 players in a few
##     palettes are a few materials, not 300).
## Presentation only (hard rule 11): it shows the row and never decides.

## The foundation's keys for picking a piece or a pack colorway: a player never picks these (Peasant only); an old
## text that has them is read without them.
const CLOTHES_KEYS: Array[String] = ["torso", "arms", "legs", "feet", "head", "shoulders", "neck"]

## The player's own colors (null: the Peasant as painted, today's look).
var colors: DyePalette = null
## ARMOR'S PALETTES (W2): outfit name ("Knight", "Ranger", "Wizard") -> its tier's palette. An outfit not here wears
## the player's colors.
var outfit_palettes: Dictionary[String, DyePalette] = {}
## How many surfaces the last dressing dyed (tests).
var dyed: int = 0


func _init() -> void:
	assembled.connect(_on_assembled)


## The appearance text, read without the clothes keys, then the player's colors kept for the dressing.
func apply_appearance(appearance: String) -> void:
	colors = RegentsColors.palette_of(appearance)
	super.apply_appearance(without_clothes(appearance))


## What the picker offers: the foundation's choices but the clothes (pieces and their pack colorways), then a FREE
## COLOR for each dye slot with its suggested swatches (`color_options`), when the picker can show one.
func appearance_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in super.appearance_options():
		if not is_clothes_key(String(o.get("key", ""))):
			out.append(o)
	if picker_has_colors():
		out.append_array(color_options())
	return out


## THE FIVE COLOR OPTIONS, in the foundation picker's color kind (template 1.8.4): a free color per dye slot, its value
## 0xRRGGBB + 1 as `RegentsColors` reads it, and a row of suggested swatches.
static func color_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: StringName in RegentsColors.KEYS:
		out.append({"key": String(k), "label": RegentsColors.LABELS[k], "color": true, "swatches": RegentsColors.swatches(k)})
	return out


## Whether the foundation's picker shows a color option (`CharacterPicker.COLOR_OPTIONS`, template 1.8.4). Before it,
## the color options are not offered: the old picker would show them as lists and drop the colors on Done.
static func picker_has_colors() -> bool:
	var picker: Script = load("res://foundation/ui/character_picker.gd") as Script
	return picker != null and bool(picker.get_script_constant_map().get("COLOR_OPTIONS", false))


## ARMOR ON (W2): `pieces` slot -> piece scene (a slot left out shows the Peasant piece), `palettes` outfit -> tier
## palette. Dressed at once, whether or not the pieces changed.
func wear_armor(pieces: Dictionary[StringName, PackedScene], palettes: Dictionary[String, DyePalette] = {}) -> void:
	outfit_palettes = palettes.duplicate()
	if not wear(pieces) and skeleton() != null:
		_on_assembled()


## The palette `outfit`'s pieces wear on this body (null: as the foundation dressed them).
func palette_for(outfit: String) -> DyePalette:
	return outfit_palettes.get(outfit, colors) as DyePalette


static func is_clothes_key(key: String) -> bool:
	return CLOTHES_KEYS.has(key) or CLOTHES_KEYS.has(key.trim_suffix(CharacterLooks.DYE))


## `text` without the clothes keys (the look and every other choice kept).
static func without_clothes(text: String) -> String:
	var picked: Dictionary = Appearance.choices(text)
	for k: Variant in picked.keys():
		if is_clothes_key(String(k)):
			picked.erase(k)
	return Appearance.make(Appearance.look_name(text), picked)


func _on_assembled() -> void:
	if Engine.is_editor_hint():
		return
	dyed = Wardrobe.dress_shared(self, palette_for)
