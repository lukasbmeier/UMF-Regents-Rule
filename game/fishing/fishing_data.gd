class_name FishingData extends RefCounted
## GENRE CODE. The fishing content, from `res://shared/fishing/fishing.json` — the same file
## `server/build.rs` compiles into the module (`server/src/genre/fishing.rs`). What a catch is,
## what lives in each spot, what the gear does, and every timing the cast and the bite run on.
##
## The client uses it to SHOW things — a catch's name and model, what a spot is known for, how
## far a rod reaches, when the float twitches. It never uses it to decide anything: the module
## rolls the catch and grades the hook-set, and the client is told.
##
## ONE EXCEPTION, AND IT HAS A TWIN: `grade_hookset` is what the player sees the instant they
## press, a round trip before the server's verdict. So it must be the server's verdict. It is
## computed exactly as `genre::fishing::grade_hookset` computes it — every value and threshold
## rounded to f32, the window a single f32 product — and both run
## `shared/golden/fishing/hookset.json`.

const PATH: String = "res://shared/fishing/fishing.json"

enum HookSet { NONE = -1, PERFECT, GOOD, LATE }

static var _doc: Dictionary = {}
static var _catches: Dictionary[String, Dictionary] = {}
static var _categories: Dictionary[String, Dictionary] = {}


## The whole document. Loaded once; an unreadable file is an error and an empty document.
static func doc() -> Dictionary:
	if _doc.is_empty():
		var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("FishingData: %s is missing" % PATH)
			return _doc
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if not parsed is Dictionary:
			push_error("FishingData: %s is not a JSON object" % PATH)
			return _doc
		_doc = parsed as Dictionary
		for c: Variant in _doc.get("catches", []):
			var d: Dictionary = c as Dictionary
			_catches[str(d["id"])] = d
		for c: Variant in _doc.get("categories", []):
			var d: Dictionary = c as Dictionary
			_categories[str(d["id"])] = d
	return _doc


static func timing(key: String) -> float:
	return float((doc().get("timing", {}) as Dictionary).get(key, 0.0))


static func cast_setting(key: String) -> float:
	return float((doc().get("cast", {}) as Dictionary).get(key, 0.0))


## A catch by id, or {} if the catalog has no such thing.
static func catch_def(id: String) -> Dictionary:
	doc()
	return _catches.get(id, {})


static func category(id: String) -> Dictionary:
	doc()
	return _categories.get(id, {})


## A catch's category's rarity (0 = trash upward); -1 for an unknown catch.
static func rarity_of(catch_id: String) -> int:
	var def: Dictionary = catch_def(catch_id)
	if def.is_empty():
		return -1
	return int(category(str(def["category"])).get("rarity", 0))


## Where the props kit keeps a junk catch's model, or "" for a fish (which has none).
static func model_path(catch_id: String) -> String:
	var m: String = str(catch_def(catch_id).get("model", ""))
	if m.is_empty():
		return ""
	return "res://game/world/kits/props/fantasypropsmegakit/Meshes/%s.gltf" % m


## A spot's loot table: {bite_speed, loot{category: weight}}; open water for "" or an unknown id.
static func spot_loot(spot_id: String) -> Dictionary:
	var spots: Dictionary = doc().get("spots", {}) as Dictionary
	if not spot_id.is_empty() and spots.has(spot_id):
		return spots[spot_id] as Dictionary
	return doc().get("open_water", {}) as Dictionary


## The rod tier that reaches a spot at all (0 for open water): the level puts it beyond every
## lesser rod's reach. Shown, never enforced here — the reach is the server's range check.
static func min_rod(spot_id: String) -> int:
	return int(spot_loot(spot_id).get("min_rod", 0))


## WHICH WATER A ROD OPENS (FfC: "'cast 32m -> 40m' is a number; 'opens The Marina' is a reason"):
## the names of `bake`'s spots whose `min_rod` is this tier.
static func spots_opened_by(rod_tier: int, bake: LevelBake) -> PackedStringArray:
	var out := PackedStringArray()
	if bake == null:
		return out
	for s: Dictionary in bake.spots:
		if min_rod(str(s.get("id", ""))) == rod_tier:
			out.append(str(s.get("name", s.get("id", ""))))
	return out


## What a spot is known for, in words, most likely first: "small fish, decent fish".
static func favoured_words(spot_id: String, count: int = 2) -> PackedStringArray:
	var loot: Dictionary = spot_loot(spot_id).get("loot", {}) as Dictionary
	var ranked: Array[Array] = []
	for cat: String in loot:
		ranked.append([cat, float(loot[cat])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out := PackedStringArray()
	for r: Array in ranked.slice(0, count):
		out.append(str(category(str(r[0])).get("word", r[0])))
	return out


## THE TIME OF DAY AND THE WEATHER (DECISIONS #168): `conditions.times` and `conditions.weather`,
## in order (the server's `fishing_conditions` row holds indices into them). {} when out of range.
static func time_of_day(index: int) -> Dictionary:
	var times: Array = (doc().get("conditions", {}) as Dictionary).get("times", []) as Array
	return times[index] as Dictionary if index >= 0 and index < times.size() else {}


static func weather(index: int) -> Dictionary:
	var ws: Array = (doc().get("conditions", {}) as Dictionary).get("weather", []) as Array
	return ws[index] as Dictionary if index >= 0 and index < ws.size() else {}


static func times_count() -> int:
	return ((doc().get("conditions", {}) as Dictionary).get("times", []) as Array).size()


## What a category (or one catch) likes under `tags` (condition ids), multiplied: 1 for nothing.
## The server's `genre::fishing::likes`, for SHOWING what bites; the server rolls.
static func likes(who: String, tags: PackedStringArray) -> float:
	var all: Dictionary = (doc().get("conditions", {}) as Dictionary).get("likes", {}) as Dictionary
	var mine: Dictionary = all.get(who, {}) as Dictionary
	var m: float = 1.0
	for t: String in tags:
		m *= float(mine.get(t, 1.0))
	return m


## What the conditions favour, in words, most favoured first: the categories and named catches
## whose likes under `tags` are above 1. "strange fish, Channel Catfish".
static func favoured_by(tags: PackedStringArray, count: int = 3) -> PackedStringArray:
	var all: Dictionary = (doc().get("conditions", {}) as Dictionary).get("likes", {}) as Dictionary
	var ranked: Array[Array] = []
	for who: String in all:
		if who.begins_with("_"):
			continue
		var m: float = likes(who, tags)
		if m > 1.001:
			var word: String = str(catch_def(who).get("name", who))
			if not category(who).is_empty():
				word = str(category(who).get("word", who))
			ranked.append([word, m])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out := PackedStringArray()
	for r: Array in ranked.slice(0, count):
		out.append(str(r[0]))
	return out


## The rival angler a module-run world gets (DECISIONS #169): fishing.json's `rival`.
static func rival() -> Dictionary:
	return doc().get("rival", {}) as Dictionary


## One tier of one gear track ("rod", "reel", "line"), clamped to the track.
static func gear(track: String, tier: int) -> Dictionary:
	var tiers: Array = (doc().get("gear", {}) as Dictionary).get(track, []) as Array
	if tiers.is_empty():
		return {}
	return tiers[clampi(tier, 0, tiers.size() - 1)] as Dictionary


static func max_tier() -> int:
	var g: Dictionary = doc().get("gear", {}) as Dictionary
	var n: int = mini((g.get("rod", []) as Array).size(), mini((g.get("reel", []) as Array).size(),
		(g.get("line", []) as Array).size()))
	return n - 1


## How far a rod of this tier can put a float.
static func max_cast_m(rod_tier: int) -> float:
	return float(gear("rod", rod_tier).get("max_cast_m", 24.0))


static func hookset_window_mult(reel_tier: int) -> float:
	return float(gear("reel", reel_tier).get("hookset_window_mult", 1.0))


# --- the hook-set: THE TWIN ----------------------------------------------------------------

## Round to f32, which is what the module holds every one of these numbers as.
static func f32(v: float) -> float:
	return Vector3(v, 0.0, 0.0).x


## The hook-set window with this reel, as the module computes it: one f32 multiply.
static func hookset_window(window_mult: float) -> float:
	return f32(f32(timing("hookset_window_s")) * f32(window_mult))


## Grade a reaction — seconds from the bite to the press — exactly as the server will.
static func grade_hookset(reaction: float, window_mult: float) -> HookSet:
	var r: float = f32(reaction)
	if not is_finite(r) or r < f32(timing("min_reaction_s")):
		return HookSet.NONE
	if r > hookset_window(window_mult):
		return HookSet.NONE
	if r <= f32(timing("hookset_perfect_s")):
		return HookSet.PERFECT
	if r >= f32(timing("hookset_late_s")):
		return HookSet.LATE
	return HookSet.GOOD


static func hookset_word(h: HookSet) -> String:
	match h:
		HookSet.PERFECT:
			return "perfect"
		HookSet.GOOD:
			return "good"
		HookSet.LATE:
			return "late"
		_:
			return "missed"
