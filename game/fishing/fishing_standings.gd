class_name FishingStandings extends RefCounted
## GENRE CODE. Who is winning: one row per angler in a session, best first.
##
## Assembled from what the components already hold rather than from a table of its own. Every
## member of my session is in my world, so every one of them is a spawned entity here, and each
## entity's own components carry its share: `SessionComponent` the score, `NameplateComponent`
## the name, `FishingComponent` the catches. Nothing is subscribed, cached or kept in step for
## the scoreboard's sake — which also means it cannot disagree with the rest of the screen.
##
## An entity with no session membership is not a competitor, so it is left out rather than listed
## at zero. (The rival angler of a module-run world is a member, DECISIONS #169: he plays the round,
## and shows up once he has scored.) So is a member who is neither here nor
## scored: every identity that ever connected keeps its membership, including each `spacetime
## sql` from a terminal, and a board of nameless zeroes nobody can account for is worse than a
## short one. Someone who scored and then left still counts — it was their round too.


## Rows for `session_id`, round `round`, sorted by score (then by name, so ties do not shuffle
## from one frame to the next). Each row:
##   entity_id, name, score, coins, catches (this round), best_catch ("" for none), best_kg,
##   is_local, online.
static func build(session_id: int, round: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if session_id < 0:
		return rows
	for id: int in EntityRegistry.all_entity_ids():
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if ent == null:
			continue
		var sess: SessionComponent = ent.find_component(SessionComponent) as SessionComponent
		if sess == null or sess.get_session_id() != session_id:
			continue
		var plate: NameplateComponent = ent.find_component(NameplateComponent) as NameplateComponent
		var fishing: FishingComponent = ent.find_component(FishingComponent) as FishingComponent
		var caught: Array[Dictionary] = fishing.catches_in(session_id, round) \
			if fishing != null else [] as Array[Dictionary]
		var best: Dictionary = best_catch(caught)
		var online: bool = plate != null and plate.is_online()
		if not online and sess.get_score() == 0 and caught.is_empty():
			continue
		rows.append({
			"entity_id": id,
			"name": plate.display_name() if plate != null else "Player %d" % id,
			"score": sess.get_score(),
			"coins": sess.get_coins(),
			"catches": caught.size(),
			"best_catch": str(best.get("key", "")),
			"best_kg": float(best.get("kg", 0.0)),
			"is_local": EntityRegistry.is_local(id),
			"online": online,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return String(a["name"]) < String(b["name"]))
	return rows


## The catch worth boasting about: the rarest, and among equally rare the heaviest. Rarity first
## because a small Golden Koi is a better story than a large carp. `rarity_of` defaults to the
## catalog (`FishingData`); tests hand in their own.
static func best_catch(caught: Array[Dictionary], rarity_of: Callable = Callable()) -> Dictionary:
	var lookup: Callable = rarity_of if rarity_of.is_valid() else FishingData.rarity_of
	var best: Dictionary = {}
	for c: Dictionary in caught:
		if best.is_empty() or _beats(c, best, lookup):
			best = c
	return best


static func _beats(a: Dictionary, b: Dictionary, rarity_of: Callable) -> bool:
	var ra: int = int(rarity_of.call(str(a["key"])))
	var rb: int = int(rarity_of.call(str(b["key"])))
	if ra != rb:
		return ra > rb
	return float(a["kg"]) > float(b["kg"])


## "1st", "2nd", "3rd", "4th" … for the rank column.
static func ordinal(n: int) -> String:
	var suffix: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
