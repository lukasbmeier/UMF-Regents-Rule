extends "res://tests/suite_base.gd"
## The `traits` suite (DECISIONS #275): what a trait is allowed to be, and what an item's traits make of a
## number. The same cases as `server/tests/traits.rs`, so the client predicts what the server decides.
##   - the bake refuses a pure gain, a cost it does not say, an atom that changes nothing
##   - an item's `instance_data` carries its traits; its card has a line for each
##   - an atom works at its action only, under its condition only; traits multiply and add; the dial scales


func _atom(what: StringName, on: StringName, mult: float, value: float = 0.0, condition: String = "always", threshold: float = 30.0,
		against: StringName = &"", cost: bool = false) -> TraitAtom:
	var a := TraitAtom.new()
	a.what = what
	a.on = on
	a.mult = mult
	a.value = value
	a.condition = condition
	a.threshold_pct = threshold
	a.against = against
	a.cost = cost
	return a


func _trait(id: int, key: StringName, tags: Array[StringName], atoms: Array[TraitAtom], gives: String = "it gives", costs: String = "it costs") -> TraitDef:
	var d := TraitDef.new()
	d.id = id
	d.key = key
	d.display_name = String(key).capitalize()
	d.applies_to = tags
	d.atoms = atoms
	d.gives = gives
	d.costs = costs
	return d


func run() -> void:
	var balanced: TraitDef = _trait(1, &"balanced", [&"weapon"], [_atom(&"recovery", &"basic", 0.85), _atom(&"damage", &"skill", 0.9, 0.0, "always", 30.0, &"", true)],
		"basics recover 15% faster", "abilities do 10% less damage")
	var brutal: TraitDef = _trait(2, &"brutal", [&"weapon"], [_atom(&"damage", &"", 1.25, 0.0, "target_below"), _atom(&"damage", &"", 0.9, 0.0, "target_above", 30.0, &"", true)])
	var hunters: TraitDef = _trait(3, &"hunters", [&"bow"], [_atom(&"damage", &"", 1.15, 0.0, "against", 30.0, &"beast"), _atom(&"damage", &"", 0.85, 0.0, "against", 30.0, &"humanoid", true)])
	var thirsting: TraitDef = _trait(4, &"thirsting", [&"weapon"], [_atom(&"heal_on_hit", &"basic", 1.0, 5.0), _atom(&"healing_received", &"", 0.85, 0.0, "always", 30.0, &"", true)])

	# --- What a trait may be ---
	_check(balanced.validate().is_empty() and brutal.validate().is_empty() and hunters.validate().is_empty(), "a trait that trades, or works only sometimes: fine (%s)" % str(balanced.validate()))
	var pure: TraitDef = _trait(9, &"pure", [&"weapon"], [_atom(&"damage", &"", 1.2)], "more damage", "")
	_check(pure.validate().any(func(e: String) -> bool: return e.contains("pure gain")), "a pure gain is refused: every trait trades")
	var mute: TraitDef = _trait(9, &"mute", [&"weapon"], [_atom(&"damage", &"", 1.2), _atom(&"recovery", &"", 1.1, 0.0, "always", 30.0, &"", true)], "more damage", "")
	_check(mute.validate().any(func(e: String) -> bool: return e.contains("does not say it")), "a cost it does not say is refused")
	var idle: TraitDef = _trait(9, &"idle", [&"weapon"], [_atom(&"damage", &"", 1.0, 0.0, "target_below")])
	_check(idle.validate().any(func(e: String) -> bool: return e.contains("changes nothing")), "an atom that changes nothing is refused")
	var nowhere: TraitDef = _trait(9, &"nowhere", [], [_atom(&"damage", &"", 1.1, 0.0, "target_below")])
	_check(nowhere.validate().any(func(e: String) -> bool: return e.contains("applies to nothing")), "a trait for no item is refused")
	var baked: Dictionary = balanced.to_bake()
	_check(baked["key"] == "balanced" and baked["applies_to"] == ["weapon"] and (baked["atoms"] as Array).size() == 2
		and (baked["atoms"] as Array)[1]["cost"] == true and (baked["atoms"] as Array)[1].has("condition"),
		"baked as the server's build reads it (key, applies_to, atoms with their condition and cost)")
	_check(balanced.fits([&"weapon", &"melee"]) and not balanced.fits([&"tool"]), "it fits an item with one of its tags")

	# --- On an item ---
	var was: Dictionary = Traits.by_id.duplicate()
	Traits.by_id.clear()
	for d: TraitDef in [balanced, brutal, hunters, thirsting]:
		Traits.by_id[d.id] = d
	_check(Traits.ids_of("") == ([] as Array[int]) and Traits.ids_of("{\"q\":734}") == ([] as Array[int]), "no traits: none")
	_check(Traits.ids_of("{\"q\":734,\"h\":40017,\"t\":[1,4]}") == ([1, 4] as Array[int]), "its data carries their ids")
	var card: Array[Dictionary] = Traits.lines("{\"t\":[1]}")
	_check(card.size() == 1 and card[0]["name"] == "Balanced" and card[0]["gives"] == "basics recover 15% faster" and card[0]["costs"] == "abilities do 10% less damage",
		"its card: a line for each, what it gives and what it costs")

	# --- What they make of a number (the server's cases) ---
	var near: Callable = func(a: float, b: float) -> bool: return absf(a - b) < 1e-5
	_check(near.call(Traits.mult([1], &"recovery", [&"basic"]), 0.85) and near.call(Traits.mult([1], &"recovery", [&"heavy"]), 1.0)
		and near.call(Traits.mult([1], &"damage", [&"skill"]), 0.9), "at its action only: a basic recovers faster, an ability pays")
	_check(near.call(Traits.mult([1], &"recovery", [&"basic", &"combo_last"]), 0.85), "an action may be several things")
	_check(near.call(Traits.mult([2], &"damage", [&"heavy"], 20.0), 1.25) and near.call(Traits.mult([2], &"damage", [&"heavy"], 80.0), 0.9)
		and near.call(Traits.mult([2], &"damage", [&"heavy"]), 1.0), "below 30%: a quarter more; above: a tenth less; not knowing: neither")
	_check(near.call(Traits.mult([3], &"damage", [], -1.0, &"beast"), 1.15) and near.call(Traits.mult([3], &"damage", [], -1.0, &"humanoid"), 0.85)
		and near.call(Traits.mult([3], &"damage", [], -1.0, &"undead"), 1.0), "against a family")
	_check(near.call(Traits.mult([1, 2], &"damage", [&"skill"], 10.0), 0.9 * 1.25) and near.call(Traits.value([4], &"heal_on_hit", [&"basic"]), 5.0),
		"two traits multiply; an amount adds")
	var rule: StringName = Traits.STRENGTH_RULE
	var live: Dictionary = HotRules.get(&"_live")
	var had: Variant = live.get(rule)
	live[rule] = {"number": 50.0, "text": "", "overridden": true}
	_check(near.call(Traits.mult([1], &"recovery", [&"basic"]), 0.925) and near.call(Traits.value([4], &"heal_on_hit", [&"basic"]), 2.5),
		"the dial at 50%: half the change")
	live[rule] = {"number": 0.0, "text": "", "overridden": true}
	_check(near.call(Traits.mult([1], &"recovery", [&"basic"]), 1.0), "at 0: traits are off")
	if had == null:
		live.erase(rule)
	else:
		live[rule] = had
	Traits.by_id.clear()
	for k: int in was:
		Traits.by_id[k] = was[k]
	await get_tree().process_frame
