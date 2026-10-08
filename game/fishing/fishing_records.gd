class_name FishingRecords extends RefCounted
## GENRE CODE. THE JOURNAL AND THE ALL-TIME RECORDS (DECISIONS #171): what each angler has ever
## caught, and the biggest of each kind anyone has, across every round and session.
##
## Like the standings (`FishingStandings`), assembled from what the components already hold: every
## `catch` row ever landed reaches its catcher's `FishingComponent` (it is append-only and owned by
## them), and their `NameplateComponent` has their name. So nothing is kept for the journal's sake,
## and it cannot disagree with the rest of the screen. It counts the anglers of this world.


## One row per catalogue entry, in catalogue order: {key, name, category, word, rarity, count,
## best_kg, best_coins, first_round, first_session}. `count` 0 is one still to catch.
static func journal(fishing: FishingComponent) -> Array[Dictionary]:
	var mine: Dictionary[String, Dictionary] = {}
	if fishing != null:
		for c: Dictionary in fishing.all_catches():
			var key: String = str(c["key"])
			var row: Dictionary = mine.get(key, {"count": 0, "best_kg": 0.0, "best_coins": 0,
				"first_round": int(c["round"]), "first_session": int(c["session"])})
			row["count"] = int(row["count"]) + 1
			row["best_kg"] = maxf(float(row["best_kg"]), float(c["kg"]))
			row["best_coins"] = maxi(int(row["best_coins"]), int(c["coins"]))
			mine[key] = row
	var out: Array[Dictionary] = []
	for d: Variant in FishingData.doc().get("catches", []):
		var def: Dictionary = d as Dictionary
		var key: String = str(def["id"])
		var cat: Dictionary = FishingData.category(str(def["category"]))
		var row: Dictionary = mine.get(key, {"count": 0, "best_kg": 0.0, "best_coins": 0,
			"first_round": -1, "first_session": -1})
		row["key"] = key
		row["name"] = str(def.get("name", key))
		row["category"] = str(def["category"])
		row["word"] = str(cat.get("word", def["category"]))
		row["rarity"] = int(cat.get("rarity", 0))
		out.append(row)
	return out


## The categories of which `journal` has nothing yet, by their word, rarest first.
static func missing(rows: Array[Dictionary]) -> PackedStringArray:
	var have: Dictionary[String, bool] = {}
	var all: Dictionary[String, int] = {}
	for r: Dictionary in rows:
		all[str(r["word"])] = int(r["rarity"])
		if int(r["count"]) > 0:
			have[str(r["word"])] = true
	var words: Array[String] = []
	for w: String in all:
		if not have.has(w):
			words.append(w)
	words.sort_custom(func(a: String, b: String) -> bool: return all[a] > all[b])
	return PackedStringArray(words)


## How many kinds a journal has caught.
static func kinds_caught(rows: Array[Dictionary]) -> int:
	var n: int = 0
	for r: Dictionary in rows:
		if int(r["count"]) > 0:
			n += 1
	return n


## The biggest of each kind anyone here has landed, rarest first, then heaviest:
## {key, name, kg, who, is_local}.
static func biggest() -> Array[Dictionary]:
	var best: Dictionary[String, Dictionary] = {}
	for a: Dictionary in _anglers_catches():
		for c: Dictionary in a["catches"] as Array[Dictionary]:
			var key: String = str(c["key"])
			if not best.has(key) or float(c["kg"]) > float(best[key]["kg"]):
				best[key] = {"key": key, "name": str(FishingData.catch_def(key).get("name", key)),
					"kg": float(c["kg"]), "who": a["name"], "is_local": a["is_local"]}
	var out: Array[Dictionary] = []
	out.assign(best.values())
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var rx: int = FishingData.rarity_of(str(x["key"]))
		var ry: int = FishingData.rarity_of(str(y["key"]))
		if rx != ry:
			return rx > ry
		return float(x["kg"]) > float(y["kg"]))
	return out


## Every angler here who has caught anything, all time, most coins first:
## {name, catches, coins, best_key, best_kg, is_local}.
static func anglers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Dictionary in _anglers_catches():
		var caught: Array[Dictionary] = a["catches"]
		if caught.is_empty():
			continue
		var coins: int = 0
		for c: Dictionary in caught:
			coins += int(c["coins"])
		var top: Dictionary = FishingStandings.best_catch(caught)
		out.append({"name": a["name"], "catches": caught.size(), "coins": coins,
			"best_key": str(top.get("key", "")), "best_kg": float(top.get("kg", 0.0)), "is_local": a["is_local"]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["coins"]) != int(y["coins"]):
			return int(x["coins"]) > int(y["coins"])
		return String(x["name"]) < String(y["name"]))
	return out


static func _anglers_catches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in EntityRegistry.all_entity_ids():
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		var fishing: FishingComponent = ent.find_component(FishingComponent) as FishingComponent if ent != null else null
		if fishing == null:
			continue
		var plate: NameplateComponent = ent.find_component(NameplateComponent) as NameplateComponent
		out.append({"name": plate.display_name() if plate != null else "Player %d" % id,
			"is_local": EntityRegistry.is_local(id), "catches": fishing.all_catches()})
	return out
