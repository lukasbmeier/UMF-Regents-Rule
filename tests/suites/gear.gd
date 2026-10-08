extends "res://tests/suite_base.gd"
## The `gear` suite (tests/test_runner.gd runs it; `-- --only=gear` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_gear_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## GEAR AND THE SHOP (GENRE_ADAPTERS §1). The server owns the prices, the phase gate and what
## each tier does; this is the client's half — reading the row, and never inventing a tier. Every
## number comes from `shared/fishing/fishing.json`, the file the module charges from, so this
## asks THAT file rather than restating it: a retune must not fail a test that was right.
func _run_gear_tests() -> void:
	print("== gear ==")
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 91
	get_tree().root.add_child(owner_entity)
	var gear := GearComponent.new()
	owner_entity.add_child(gear)
	var no_rows: Dictionary[StringName, RefCounted] = {}
	gear.bind(owner_entity, no_rows)
	var cost := func(track: String, t: int) -> int: return int(FishingData.gear(track, t).get("cost", -2))

	# A NEW ANGLER HAS NO ROW. `gear` is a table an entity legitimately has none in, so it has to
	# be optional as well as required — otherwise every fisher sits out its whole bind timeout
	# before it appears (DECISIONS #69).
	_check(gear.required_tables().has(&"gear") and gear.optional_tables().has(&"gear"),
		"gear is required AND optional: no row is a legitimate state")
	_check(gear.rod_tier() == 0 and gear.reel_tier() == 0 and gear.line_tier() == 0,
		"with no row the angler is on the starting kit")
	_check(gear.next_cost(GearComponent.Kind.ROD) == cost.call("rod", 1) and cost.call("rod", 1) > 0,
		"and the first rod costs what the shared file says (%d)" % gear.next_cost(GearComponent.Kind.ROD))
	_check(gear.item_name(GearComponent.Kind.ROD) == str(FishingData.gear("rod", 0)["name"]),
		"the starting rod has its name from the file (%s)" % gear.item_name(GearComponent.Kind.ROD))

	var changed: Array[int] = []
	# Mutate, never reassign: a lambda captures a local by VALUE, so `changed = [...]` inside one
	# updates a copy and the assertion below would read an empty array however well the code works.
	gear.gear_changed.connect(func(r: int, e: int, l: int) -> void:
		changed.clear()
		changed.append_array([r, e, l]))
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"gear", null, FakeGearRow.new(91, 2, 1, 0)))
	_check(gear.rod_tier() == 2 and gear.reel_tier() == 1 and gear.line_tier() == 0,
		"the row is what the tiers are (%d/%d/%d)"
			% [gear.rod_tier(), gear.reel_tier(), gear.line_tier()])
	_check(changed == [2, 1, 0], "and it announces the change once, as (rod, reel, line) (%s)" % str(changed))
	_check(gear.next_cost(GearComponent.Kind.ROD) == cost.call("rod", 3),
		"prices climb with the tier: the third rod costs %d (%d)"
			% [cost.call("rod", 3), gear.next_cost(GearComponent.Kind.ROD)])
	_check(gear.next_cost(GearComponent.Kind.REEL) == cost.call("reel", 2)
			and gear.next_cost(GearComponent.Kind.LINE) == cost.call("line", 1),
		"and each piece is priced by ITS own tier, not the highest one (reel %d, line %d)"
			% [gear.next_cost(GearComponent.Kind.REEL), gear.next_cost(GearComponent.Kind.LINE)])
	_check(gear.next_name(GearComponent.Kind.REEL) == str(FishingData.gear("reel", 2)["name"]),
		"the shop can name what the next reel is (%s)" % gear.next_name(GearComponent.Kind.REEL))

	# The top tier is a wall, and the HUD has to be able to say so without guessing.
	var top: int = GearComponent.max_tier()
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.UPDATED, &"gear", null, FakeGearRow.new(91, top, 0, 0)))
	_check(gear.next_cost(GearComponent.Kind.ROD) == -1 and gear.next_name(GearComponent.Kind.ROD).is_empty(),
		"a maxed rod has no next price and no next name (%d)" % gear.next_cost(GearComponent.Kind.ROD))

	# A row going away is an angler back on the starting kit, not a stale display.
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.DELETED, &"gear", FakeGearRow.new(91, top, 0, 0), null))
	_check(gear.rod_tier() == 0, "a deleted row drops back to the starting kit")

	# THE FILE ITSELF, as the shop needs it: every track has every tier, the kit you start with
	# is free, and each tier costs more than the last — a cheaper upgrade is a typo, not a sale.
	var bad: Array[String] = []
	for track: String in ["rod", "reel", "line"]:
		var tiers: Array = (FishingData.doc()["gear"] as Dictionary)[track] as Array
		if tiers.size() != top + 1:
			bad.append("%s has %d tiers" % [track, tiers.size()])
			continue
		if cost.call(track, 0) != 0:
			bad.append("%s tier 0 is not free" % track)
		for t: int in range(1, top + 1):
			if cost.call(track, t) <= cost.call(track, t - 1):
				bad.append("%s tier %d is not dearer than %d" % [track, t, t - 1])
			if str(FishingData.gear(track, t).get("name", "")).is_empty():
				bad.append("%s tier %d has no name" % [track, t])
	_check(bad.is_empty(), "every track has %d named tiers, the first free and each dearer (%s)" % [top + 1, str(bad)])
	# And each track does the thing it is sold for: reach, forgiveness, load. Flat numbers along a
	# track would be three names for one purchase (DECISIONS #118).
	_check(FishingData.max_cast_m(top) > FishingData.max_cast_m(0), "a better rod reaches further")
	_check(FishingData.hookset_window_mult(top) > FishingData.hookset_window_mult(0),
		"a better reel is more forgiving on the hook-set")
	_check(float(FishingData.gear("line", top)["max_load_kg"]) > float(FishingData.gear("line", 0)["max_load_kg"]),
		"a better line holds more weight")
	owner_entity.queue_free()


## A `gear` row. Tiers only: the prices and the effects are the server's business.
class FakeGearRow extends RefCounted:
	var entity_id: int = 0
	var rod_tier: int = 0
	var reel_tier: int = 0
	var line_tier: int = 0

	func _init(eid: int, rod: int, reel: int, line: int) -> void:
		entity_id = eid
		rod_tier = rod
		reel_tier = reel
		line_tier = line
