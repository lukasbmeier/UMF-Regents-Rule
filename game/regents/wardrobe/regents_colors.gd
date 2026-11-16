class_name RegentsColors extends RefCounted
## A PLAYER'S OWN CLOTHES COLORS ON THE `appearance` TEXT (Luke's W8 and W2, 2026-11-14: "all players start as
## peasant outfit but can pick the color they want"). One key per dye slot, `main`, `accent`, `under`, `trim`,
## `leather`, each the color as a number: 0xRRGGBB + 1 ("peasant_m;main=4876943;hair=3"). 0, or a key missing,
## keeps the Peasant's own painting there.
##
## WHY A NUMBER, NOT "#rrggbb": the module takes only `a-z 0-9 _;=,.-` in a look (`set_appearance`), and the
## foundation's `Appearance.choices` / `make` (which the character picker writes with) keep whole numbers only. A
## number is add-only (rule 17): an old client's `CharacterLooks` ignores keys it does not know, and an old text
## with no keys is dressed as it always was.
## A value that is not a color (text, too big, negative) is ignored, never a crash.

## The dye slots a player colors, in the order the picker lists them (`DyePalette.CLOTH`'s names).
const KEYS: Array[StringName] = [&"main", &"accent", &"under", &"trim", &"leather"]
## What a player sees each called (American spelling: what a player reads).
const LABELS: Dictionary[StringName, String] = {&"main": "Main color", &"accent": "Accent", &"under": "Under",
	&"trim": "Trim", &"leather": "Leather"}
## The largest value a key can hold (white).
const MAX_VALUE: int = 0xFFFFFF + 1


## A color as a key's value (its alpha is dropped: a player's color is always a whole dye).
static func encode(c: Color) -> int:
	return ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1


## A key's value as a color, or a color with alpha 0 when it is no color (0: the painting's own; out of range).
static func decode(value: int) -> Color:
	if value < 1 or value > MAX_VALUE:
		return Color(1, 1, 1, 0)
	var v: int = value - 1
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, 255)


## The colors named in `text`: {slot: Color}, only the valid ones.
static func colors_in(text: String) -> Dictionary[StringName, Color]:
	var out: Dictionary[StringName, Color] = {}
	var c: Dictionary = Appearance.choices(text)
	for k: StringName in KEYS:
		var col: Color = decode(int(c.get(String(k), 0)))
		if col.a > 0.0:
			out[k] = col
	return out


## `text` with the colors `colors` ({slot: Color}; alpha 0 takes a slot's color off): the look and every other
## choice kept.
static func with_colors(text: String, colors: Dictionary) -> String:
	var picked: Dictionary = Appearance.choices(text)
	for k: Variant in colors:
		if not KEYS.has(StringName(str(k))):
			continue
		var col: Color = colors[k] as Color
		picked[String(k)] = encode(col) if col.a > 0.0 else 0
	return Appearance.make(Appearance.look_name(text), picked)


## THE PLAYER'S PALETTE from `text`: the Peasant's dye with their colors (a slot they did not color keeps the
## painting). Null when the text names none (today's look, as it was). Shared: the same colors give the same
## palette object, so bodies in the same colors share their materials too (`Wardrobe.dress_shared`).
static func palette_of(text: String) -> DyePalette:
	var colors: Dictionary[StringName, Color] = colors_in(text)
	if colors.is_empty():
		return null
	var key: String = ""
	for k: StringName in KEYS:
		key += "%s=%s;" % [k, (colors[k] as Color).to_html(false) if colors.has(k) else "-"]
	var held: WeakRef = _palettes.get(key, null) as WeakRef
	var kept: DyePalette = held.get_ref() as DyePalette if held != null else null
	if kept != null:
		return kept
	var p := DyePalette.new()
	p.title = "A player's own colors"
	for k: StringName in colors:
		p.set(k, colors[k])
	p.set_meta(&"share_key", key)
	if _palettes.size() >= 256:   # the gone ones' keys swept now and then
		for k: String in _palettes.keys():
			if (_palettes[k] as WeakRef).get_ref() == null:
				_palettes.erase(k)
	_palettes[key] = weakref(p)
	return p


## The suggested swatches the picker shows beside each slot's free color. PLACEHOLDER: the four `starter_*` palettes'
## colors (oat, blue, red, forest), until Luke picks a row of his own (`WAITING_ON_LUKE.md`).
static func swatches(slot: StringName) -> Array[Color]:
	var out: Array[Color] = []
	for r: Resource in Wardrobe.load_all(Wardrobe.PALETTES):
		var p: DyePalette = r as DyePalette
		if p == null or not p.resource_path.get_file().begins_with("starter_"):
			continue
		var c: Color = p.get(slot) as Color
		if c.a > 0.0 and not out.has(c):
			out.append(c)
	return out


## key -> WeakRef of its palette: kept only while a body wears it (W4: players come and go).
static var _palettes: Dictionary[String, WeakRef] = {}
