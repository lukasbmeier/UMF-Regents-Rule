extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `standings` suite (`-- --only=standings` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	_run_standings_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## Who won, and what is news. The scoreboard is assembled from components, so its rules are the
## components' rules: which catches belong to which round, which one is "best", and — the one a
## player notices — that a fish landed in a previous session is history, not a new catch.
func _run_standings_tests() -> void:
	print("== standings ==")
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 93
	get_tree().root.add_child(owner_entity)
	var fishing := FishingComponent.new()
	owner_entity.add_child(fishing)
	var announced: Array[String] = []
	fishing.catch_landed.connect(func(c: Dictionary) -> void: announced.append(str(c["key"])))

	# A REJOIN replays every catch this angler ever made. Before, the last one was re-announced:
	# a banner — and with feedback, a splash and a jingle — for a fish from a previous session.
	var initial: Dictionary[StringName, RefCounted] = {
		&"catch": FakeCatchRow.new(1, 93, 7, 2, "carp", 8.1)}
	fishing.bind(owner_entity, initial)
	_check(announced.is_empty(), "a catch that was already true on arrival is not announced")
	_check(fishing.catches_in(7, 2).size() == 1, "but it is on the record for the scoreboard")
	# Every catch the entity was sent arrives at bind, and none of them is news (DECISIONS #180).
	var historian := FakeOwnerEntity.new()
	historian.entity_id = 94
	get_tree().root.add_child(historian)
	var past := FishingComponent.new()
	historian.add_child(past)
	var told: Array[String] = []
	past.catch_landed.connect(func(c: Dictionary) -> void: told.append(str(c["key"])))
	var rows: Array = [FakeCatchRow.new(11, 94, 7, 1, "carp", 8.1), FakeCatchRow.new(12, 94, 7, 1, "bluegill", 0.3),
		FakeCatchRow.new(13, 94, 7, 2, "walleye", 3.0)]
	past.bind(historian, {&"catch": rows[2]}, {&"catch": rows})
	_check(past.all_catches().size() == 3 and told.is_empty(),
		"bind hands over every catch the entity was sent (%d), and announces none" % past.all_catches().size())
	historian.queue_free()

	var landed := FakeCatchRow.new(2, 93, 7, 3, "bluegill", 0.31)
	landed.hookset = 0
	landed.coins = 3
	landed.spot = "reed_bay"
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, landed))
	_check(announced == ["bluegill"], "a catch that ARRIVES is announced, once (%s)" % str(announced))
	var rec: Dictionary = fishing.catches_in(7, 3)[0] if fishing.catches_in(7, 3).size() > 0 else {}
	_check(str(rec.get("key", "")) == "bluegill" and absf(float(rec.get("kg", 0.0)) - 0.31) < 1e-6
			and int(rec.get("hookset", -9)) == 0 and str(rec.get("spot", "")) == "reed_bay"
			and int(rec.get("coins", -1)) == 3 and not bool(rec.get("deadlift", true))
			and int(rec.get("best_combo", -1)) == 3 and is_equal_approx(float(rec.get("fight_s", 0.0)), 11.5)
			and bool(rec.get("clean", false)),
		"and the record carries what the row says: key, kg, hook-set, spot, coins, and how the fight went (%s)" % str(rec))
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(2, 93, 7, 3, "bluegill", 0.31)))
	_check(announced == ["bluegill"], "and a replay of the same row is not news either")
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(3, 93, 7, 3, "anvil", 118.0)))
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(4, 93, 8, 3, "golden_koi", 5.5)))
	var r3: Array[Dictionary] = fishing.catches_in(7, 3)
	_check(r3.size() == 2 and int(r3[0]["id"]) == 2 and int(r3[1]["id"]) == 3,
		"a round's catches are that round's, in order, and not another session's (%s)" % str(r3))
	_check(fishing.catches_in(7, 2).size() == 1 and fishing.catches_in(8, 3).size() == 1,
		"each round and session keeps its own")

	# Best catch: rarity first, then weight.
	var rarity: Dictionary[String, int] = {"minnow": 0, "perch": 0, "koi": 3}
	var lookup: Callable = func(key: String) -> int: return rarity.get(key, -1)
	var small_koi: Dictionary = {"key": "koi", "kg": 0.41}
	var big_minnow: Dictionary = {"key": "minnow", "kg": 0.19}
	var bigger_perch: Dictionary = {"key": "perch", "kg": 0.38}
	var smaller_perch: Dictionary = {"key": "perch", "kg": 0.16}
	var mix: Array[Dictionary] = [big_minnow, small_koi, bigger_perch]
	_check(FishingStandings.best_catch(mix, lookup) == small_koi,
		"a small rare catch beats a large common one: rarity decides first")
	var perches: Array[Dictionary] = [smaller_perch, bigger_perch]
	_check(FishingStandings.best_catch(perches, lookup) == bigger_perch,
		"between equals, the heavier")
	_check(FishingStandings.best_catch([] as Array[Dictionary], lookup).is_empty(),
		"no catch, no best")
	# And with the REAL catalogue, the one the board uses when nobody hands it a lookup: an anvil
	# is heavier than everything, and is still not the catch anyone boasts about.
	var real: Array[Dictionary] = [{"key": "anvil", "kg": 118.0}, {"key": "golden_koi", "kg": 5.5},
		{"key": "carp", "kg": 9.0}]
	_check(str(FishingStandings.best_catch(real).get("key", "")) == "golden_koi",
		"with the shipped catalogue a Golden Koi beats an anvil and a carp (%s)"
			% str(FishingStandings.best_catch(real)))
	_check(FishingData.rarity_of("not_a_catch") == -1, "and a key the catalogue lacks ranks below everything")

	var ords: Array[String] = []
	for n: int in [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111, 112]:
		ords.append(FishingStandings.ordinal(n))
	_check(ords == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd",
		"101st", "111th", "112th"], "ranks read as English (%s)" % ", ".join(ords))
	owner_entity.queue_free()
