@tool
class_name CharacterLooks extends RefCounted
## GENRE CONTENT. What a player may change about a look in the character picker (DECISIONS #166,
## #178): EVERY PIECE, slot by slot (torso, arms, legs, feet, headwear, shoulders, neck, hair, beard,
## eyebrows) from the pieces made for that look's body, the colours of the four clothing slots, the
## skin and the hair colour. A look is the starting point; any of it can be swapped.
##
## A chosen look travels as TEXT on the `appearance` row (`Appearance`): the look's file name, then
## the choices that differ from it, "ranger_f;torso=3;torso_dye=2;hairstyle=3;skin=4". The
## foundation only reads the part before the first `;` (which look); `ModularCharacter.
## apply_appearance` hands the rest here. An index of 0, or a key that is missing, keeps the look's
## own. Unknown keys and indices out of range are ignored, so text from a newer build never breaks
## an older one.
##
## ADD A PIECE: import it (`tools/characters/import_quaternius_characters.py`), then append it to its
## slot's list for its body below. ADD A COLOUR: append it to SKINS or HAIRS. Never reorder or
## remove an entry: players' choices are stored by position.

const TEXTURES: String = "res://game/characters/quaternius/textures/"
const PIECES: String = "res://game/characters/quaternius/models/"

## THE PIECES, slot by slot and body by body: [name shown, model file(s)] (the file in PIECES without
## `.gltf`; several joined by `+` are worn together; "" wears nothing in that slot). A choice
## replaces EVERY piece the look wears in that slot. A slot whose list for a body has fewer than two
## entries is not offered to that body. `dye` slots also offer their piece's colourways.
const SLOTS: Array[Dictionary] = [
	{"key": "torso", "label": "Torso", "dye": true,
		"female": [["Peasant", "Female_Peasant_Body"], ["Ranger", "Female_Ranger_Body"],
			["Noble", "Female_Noble_Body"], ["Wizard", "Female_Wizard_Body"]],
		"male": [["Peasant", "Male_Peasant_Body"], ["Ranger", "Male_Ranger_Body"],
			["Noble", "Male_Noble_Body"], ["Wizard", "Male_Wizard_Body"]]},
	{"key": "arms", "label": "Arms", "dye": true,
		"female": [["Peasant", "Female_Peasant_Arms"], ["Ranger", "Female_Ranger_Arms"],
			["Noble", "Female_Noble_Arms"], ["Wizard", "Female_Wizard_Arms"]],
		"male": [["Peasant", "Male_Peasant_Arms"], ["Ranger", "Male_Ranger_Arms"],
			["Noble", "Male_Noble_Arms"], ["Wizard", "Male_Wizard_Arms"]]},
	{"key": "legs", "label": "Legs", "dye": true,
		"female": [["Peasant", "Female_Peasant_Legs"], ["Ranger", "Female_Ranger_Legs"],
			["Noble", "Female_Noble_Legs"], ["Wizard", "Female_Wizard_Legs"]],
		"male": [["Peasant", "Male_Peasant_Legs"], ["Ranger", "Male_Ranger_Legs"],
			["Noble", "Male_Noble_Legs"], ["Wizard", "Male_Wizard_Legs"]]},
	{"key": "feet", "label": "Feet", "dye": true,
		"female": [["Peasant", "Female_Peasant_Feet"], ["Ranger", "Female_Ranger_Feet"],
			["Noble", "Female_Noble_Feet"], ["Wizard", "Female_Wizard_Feet"]],
		"male": [["Peasant", "Male_Peasant_Feet"], ["Ranger boots", "Male_Ranger_Feet_Boots"],
			["Noble", "Male_Noble_Feet"], ["Wizard", "Male_Wizard_Feet"]]},
	{"key": "head", "label": "Headwear",
		"female": [["None", ""], ["Hood", "Female_Ranger_Head_Hood"], ["Crown", "Female_Noble_Head_Crown"]],
		"male": [["None", ""], ["Hood", "Male_Ranger_Head_Hood"], ["Crown", "Male_Noble_Head_Crown"]]},
	{"key": "shoulders", "label": "Shoulders",
		"female": [["None", ""], ["Pauldron", "Female_Noble_Acc_Pauldron"],
			["Lion pauldron", "Female_Noble_Acc_Pauldron_Lion"], ["Ranger pauldrons", "Female_Ranger_Acc_Pauldrons"]],
		"male": [["None", ""], ["Pauldron", "Male_Noble_Acc_Pauldron"],
			["Lion pauldron", "Male_Noble_Acc_Pauldron_Lion"], ["Ranger pauldron", "Male_Ranger_Acc_Pauldron"]]},
	{"key": "neck", "label": "Neck",
		"female": [["None", ""], ["Gorget", "Female_Noble_Acc_Gorget"]],
		"male": [["None", ""], ["Gorget", "Male_Noble_Acc_Gorget"]]},
	{"key": "hairstyle", "label": "Hair",
		"female": [["None", ""], ["Bob", "Hair_Bob"], ["Buns", "Hair_Buns"], ["Long", "Hair_Long"],
			["Ponytail", "Hair_Ponytail_2"]],
		"male": [["None", ""], ["Buzzed", "Hair_Buzzed"], ["Balding", "Hair_Balding"], ["Ponytail", "Hair_Ponytail"]]},
	{"key": "beard", "label": "Beard",
		"female": [],
		"male": [["None", ""], ["Beard", "Hair_Beard"], ["Moustache", "Hair_Moustache"],
			["Mutton chops", "Hair_MuttonChops"], ["Moustache and chops", "Hair_Moustache+Hair_MuttonChops"]]},
	{"key": "brows", "label": "Eyebrows",
		"female": [["Fine", "Eyebrows_Female"]],
		"male": [["Regular", "Eyebrows_Regular"], ["Thick", "Eyebrows_Thick"]]},
]

## The suffix of a slot's colourway key: "torso_dye".
const DYE: String = "_dye"

## Skin tones: which of the pack's two skin textures, and a tint over it.
const SKINS: Array[Dictionary] = [
	{"name": "Fair", "dark": false, "tint": Color(1.0, 0.95, 0.9)},
	{"name": "Light", "dark": false, "tint": Color(0.95, 0.83, 0.74)},
	{"name": "Olive", "dark": false, "tint": Color(0.86, 0.74, 0.6)},
	{"name": "Tan", "dark": false, "tint": Color(0.8, 0.62, 0.48)},
	{"name": "Brown", "dark": true, "tint": Color(1.0, 0.95, 0.92)},
	{"name": "Deep", "dark": true, "tint": Color(0.82, 0.74, 0.7)},
]

const HAIRS: Array[Dictionary] = [
	{"name": "Black", "color": Color(0.06, 0.05, 0.05)},
	{"name": "Dark brown", "color": Color(0.2, 0.12, 0.07)},
	{"name": "Brown", "color": Color(0.36, 0.22, 0.11)},
	{"name": "Auburn", "color": Color(0.46, 0.18, 0.08)},
	{"name": "Ginger", "color": Color(0.72, 0.36, 0.13)},
	{"name": "Blonde", "color": Color(0.82, 0.66, 0.38)},
	{"name": "Platinum", "color": Color(0.9, 0.86, 0.76)},
	{"name": "Grey", "color": Color(0.55, 0.55, 0.57)},
	{"name": "White", "color": Color(0.9, 0.9, 0.92)},
	{"name": "Teal", "color": Color(0.16, 0.5, 0.52)},
]

## The outfits whose colourways can be swapped, by the name in their pieces' files.
const OUTFITS: Array[String] = ["Peasant", "Ranger", "Noble", "Wizard", "Knight"]


## What the picker offers for `look` (as it is dressed now): one entry per key, each with its
## choices (index 0 is the look's own) and, where it helps, a colour per choice to draw. A slot's
## colourway sits `beside` its piece.
static func options(look: ModularCharacter) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wearing: Array[PackedScene] = look.wearing()
	for slot: Dictionary in SLOTS:
		var list: Array = slot_list(slot, look.body)
		if list.size() < 2:
			continue
		var key: String = String(slot["key"])
		var names: PackedStringArray = PackedStringArray(["As designed"])
		for entry: Array in list:
			names.append(String(entry[0]))
		out.append({"key": key, "label": String(slot["label"]), "choices": names, "swatches": []})
		if not bool(slot.get("dye", false)):
			continue
		var piece: PackedScene = _worn_in(slot, wearing)
		var ways: Array[Texture2D] = colourways(outfit_of_file(piece.resource_path if piece != null else ""))
		if ways.size() > 1:
			var dyes: PackedStringArray = PackedStringArray(["As designed"])
			for i: int in range(ways.size()):
				dyes.append("Colours %d" % (i + 1))
			out.append({"key": key + DYE, "label": "%s colours" % String(slot["label"]), "choices": dyes,
				"swatches": [], "beside": key})
	var skins: PackedStringArray = PackedStringArray(["As designed"])
	var skin_swatches: Array[Color] = [Color(0, 0, 0, 0)]
	for s: Dictionary in SKINS:
		skins.append(String(s["name"]))
		skin_swatches.append(_skin_swatch(s))
	var hairs: PackedStringArray = PackedStringArray(["As designed"])
	var hair_swatches: Array[Color] = [Color(0, 0, 0, 0)]
	for h: Dictionary in HAIRS:
		hairs.append(String(h["name"]))
		hair_swatches.append(h["color"] as Color)
	out.append({"key": "skin", "label": "Skin", "choices": skins, "swatches": skin_swatches})
	out.append({"key": "hair", "label": "Hair colour", "choices": hairs, "swatches": hair_swatches})
	return out


## Put the choices in `appearance` on `look`: its fields, the pieces it wears (`worn`) and their
## colourways (`dyes`). Always from the look's own pieces, so applying twice is applying once.
## Returns whether anything changed.
static func apply(look: ModularCharacter, appearance: String) -> bool:
	var c: Dictionary = Appearance.choices(appearance)
	var changed: bool = false
	var skin: int = int(c.get("skin", 0))
	if skin >= 1 and skin <= SKINS.size():
		var s: Dictionary = SKINS[skin - 1]
		var tex: Texture2D = _skin_texture(look.body, bool(s["dark"]))
		if tex != null:
			look.skin_texture = tex
		look.skin_tint = s["tint"] as Color
		changed = true
	var hair: int = int(c.get("hair", 0))
	if hair >= 1 and hair <= HAIRS.size():
		look.hair_color = HAIRS[hair - 1]["color"] as Color
		changed = true
	var wear: Array[PackedScene] = look.parts.duplicate()
	var swapped: bool = false
	for slot: Dictionary in SLOTS:
		var list: Array = slot_list(slot, look.body)
		var pick: int = int(c.get(String(slot["key"]), 0))
		if pick < 1 or pick > list.size():
			continue
		var at: int = wear.size()
		for i: int in range(wear.size() - 1, -1, -1):
			if wear[i] != null and slot_of(wear[i].resource_path) == String(slot["key"]):
				wear.remove_at(i)
				at = i
		var put: Array[PackedScene] = []
		for file: String in String(list[pick - 1][1]).split("+", false):
			var path: String = PIECES + file + ".gltf"
			if ResourceLoader.exists(path):
				put.append(load(path) as PackedScene)
		for i: int in range(put.size()):
			wear.insert(mini(at + i, wear.size()), put[i])
		swapped = true
	var dyes: Dictionary[String, Texture2D] = {}
	for slot: Dictionary in SLOTS:
		var dye: int = int(c.get(String(slot["key"]) + DYE, 0))
		if not bool(slot.get("dye", false)) or dye < 1:
			continue
		var piece: PackedScene = _worn_in(slot, wear)
		if piece == null:
			continue
		var ways: Array[Texture2D] = colourways(outfit_of_file(piece.resource_path))
		if dye <= ways.size():
			dyes[piece.resource_path] = ways[dye - 1]
	if swapped or not dyes.is_empty():
		changed = true
	look.worn.clear()
	if swapped:
		look.worn.assign(wear)
	look.dyes = dyes
	return changed


## A slot's list for a body (`female`, else `male`).
static func slot_list(slot: Dictionary, body: StringName) -> Array:
	return slot.get("female" if body == &"female" else "male", []) as Array


## The key of the slot a piece belongs to, by its file, in either body's list; "" for none.
static func slot_of(path: String) -> String:
	var file: String = path.get_file().get_basename()
	for slot: Dictionary in SLOTS:
		for body: String in ["female", "male"]:
			for entry: Array in slot.get(body, []) as Array:
				if String(entry[1]).split("+", false).has(file):
					return String(slot["key"])
	return ""


## The outfit a piece's file is from ("Female_Ranger_Body" -> Ranger), or "".
static func outfit_of_file(path: String) -> String:
	var file: String = path.get_file()
	for o: String in OUTFITS:
		if file.contains("_%s_" % o):
			return o
	return ""


## An outfit's colourways in the pack, in order: T_<Outfit>_BaseColor, then _2_, _3_ ...
static func colourways(outfit: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if outfit.is_empty():
		return out
	var first: String = TEXTURES + "T_%s_BaseColor.png" % outfit
	if ResourceLoader.exists(first):
		out.append(load(first) as Texture2D)
	for n: int in range(2, 6):
		var path: String = TEXTURES + "T_%s_%d_BaseColor.png" % [outfit, n]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path) as Texture2D)
	return out


## The first piece of `slot` in `wearing`, or null.
static func _worn_in(slot: Dictionary, wearing: Array[PackedScene]) -> PackedScene:
	for p: PackedScene in wearing:
		if p != null and slot_of(p.resource_path) == String(slot["key"]):
			return p
	return null


static func _skin_texture(body: StringName, dark: bool) -> Texture2D:
	var who: String = "Female" if body == &"female" else "Male"
	var path: String = TEXTURES + "T_Regular_%s_%s_BaseColor.png" % [who, "Dark" if dark else "Light"]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Roughly the colour a skin choice shows as, for the picker's swatch.
static func _skin_swatch(s: Dictionary) -> Color:
	var base: Color = Color(0.36, 0.24, 0.17) if bool(s["dark"]) else Color(0.93, 0.76, 0.64)
	return base * (s["tint"] as Color)
