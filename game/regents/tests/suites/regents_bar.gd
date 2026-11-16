extends "res://tests/suite_base.gd"
## THE ABILITY BAR (`-- --only=regents_bar`; Luke's B5, B7, B11, B12, 2026-11-13, `ABILITIES_PREP.md` §7 step 1),
## with no server:
##   - its two looks (round, square) and the setting that picks one; the lab opens and fires a slot
##   - its keys are actions, rebindable: the bar shows what a slot is bound to, and a rebinding moves the press
##   - its model for each kit: ready, cooling, locked (with what opens it), the mana it cannot pay, empty (with what
##     goes there); the stance and the fight it shows (and their negatives); the ring toward the next unlock
##   - what the old text line said is in the weapon's tooltip, with no role or mechanic names


## Mouse buttons that reached `_unhandled_input` (where the game's swing reads them).
var _clicks: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_clicks += 1


## A left click as the playtests send one (at the window's corner; a headless window is 64 px, so the bar covers it).
func _click_through() -> int:
	_clicks = 0
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)
	await get_tree().process_frame
	return _clicks


func run() -> void:
	_run_looks()
	_run_keys()
	_run_models()
	_run_ring()
	_run_item_twin()
	await _run_bag_picks()
	await _run_changes()
	_run_words()
	await _run_drawn()
	await _run_lab()


func _run_looks() -> void:
	var round_look: RegentsBarStyle = RegentsAbilityBar.look(0)
	var square_look: RegentsBarStyle = RegentsAbilityBar.look(1)
	_check(round_look != null and square_look != null and round_look.shape == RegentsBarStyle.Shape.ROUND
		and square_look.shape == RegentsBarStyle.Shape.SQUARE, "the bar's two looks: round and square, each a .tres")
	_check(RegentsAbilityBar.LOOKS.size() == RegentsAbilityBar.LOOK_NAMES.size(), "every look has its name in the setting")
	RegentsAbilityBar.define_setting()
	var e: Dictionary = Settings.entry(RegentsAbilityBar.SETTING)
	_check(not e.is_empty() and e["kind"] == Settings.Kind.CHOICE and e["tab"] == Settings.GAME and int(e["default"]) == 0,
		"the setting: Game, \"Ability bar\", round by default")


func _run_keys() -> void:
	CombatComponent.bind_keys()
	var labels: PackedStringArray = PackedStringArray()
	for a: StringName in CombatComponent.SLOT_ACTIONS:
		labels.append(CombatComponent.key_label(a))
	_check(",".join(labels) == "Q,E,R,F" and CombatComponent.key_label(CombatComponent.POTION_ACTION) == "G",
		"the slots' keys by default: Q E R F, the potion G (%s)" % ",".join(labels))
	var all_defined: bool = true
	for a: StringName in CombatComponent.SLOT_ACTIONS + [CombatComponent.POTION_ACTION]:
		all_defined = all_defined and Settings.entry(a).get("kind", -1) == Settings.Kind.KEY
	_check(all_defined, "every slot's key and the potion's is a rebindable key in Settings (B5: a setting, not a constant)")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	var one := InputEventKey.new()
	one.physical_keycode = KEY_1
	one.pressed = true
	_check(CombatComponent.slot_of(q) == 0 and CombatComponent.slot_of(e) == 1 and CombatComponent.slot_of(one) == -1,
		"Q presses the first slot, E the second; 1 none")
	_check(InputMap.has_action(&"interact") and e.is_action(&"interact"), "E is still the world's key too (out of stance)")
	var kept: Variant = Settings.get_value(CombatComponent.SLOT_ACTIONS[0])
	Settings.set_value(CombatComponent.SLOT_ACTIONS[0], Settings.event_to_text(one))
	_check(CombatComponent.slot_of(one) == 0 and CombatComponent.slot_of(q) == -1 and CombatComponent.key_label(CombatComponent.SLOT_ACTIONS[0]) == "1",
		"rebound to 1: 1 presses the first slot, Q no longer does, and the bar says 1")
	Settings.set_value(CombatComponent.SLOT_ACTIONS[0], kept)
	_check(CombatComponent.slot_of(q) == 0 and CombatComponent.slot_of(one) == -1, "back to Q")


func _slots(m: Dictionary) -> Array:
	return m.get("slots", []) as Array


func _slot(m: Dictionary, i: int) -> Dictionary:
	return _slots(m)[i] as Dictionary


func _state(m: Dictionary, i: int) -> StringName:
	return StringName(String(_slot(m, i).get("state", "")))


func _run_models() -> void:
	var c: CombatComponent = CombatComponent.new()
	var sk: SkillingComponent = SkillingComponent.new()
	# Nothing wielded.
	var m: Dictionary = RegentsAbilityBar.model_for(c, sk)
	_check(String((m["weapon"] as Dictionary)["tip"]).contains("No weapon") and _slots(m).size() == 4
		and _slots(m).all(func(d: Dictionary) -> bool: return StringName(String(d["state"])) == RegentsAbilitySlot.EMPTY)
		and not bool(m["stance"]), "nothing wielded: four empty slots, the weapon's says so (\"I opens the bag\"), no stance")
	# The sword, mastery 1.
	var sword: KitDef = KitDef.by_key(&"sword")
	c.kit = sword
	c.weapon = ItemDef.by_id(40019)
	m = RegentsAbilityBar.model_for(c, sk)
	var q: Dictionary = _slot(m, 0)
	_check(_state(m, 0) == RegentsAbilitySlot.READY and String(q["key"]) == "Q" and String(q["name"]) == "Lunge"
		and int(q["ability_id"]) == sword.skills[0].id, "the sword: Lunge on Q, ready")
	_check(String(q["tip"]).contains("Lunge") and String(q["tip"]).contains("forward") and String(q["tip"]).contains("6 s"),
		"Lunge's words: it carries you forward, ready again after 6 s (%s)" % String(q["tip"]).replace("\n", " / "))
	_check(_state(m, 1) == RegentsAbilitySlot.LOCKED and _state(m, 2) == RegentsAbilitySlot.LOCKED and _state(m, 3) == RegentsAbilitySlot.EMPTY,
		"a new sword: E and R locked (its pool opens at 5 and 20), F empty")
	_check(String(_slot(m, 3)["tip"]).contains("chest") and String((m["potion"] as Dictionary)["tip"]).contains("Potions"),
		"each empty slot says what goes there (B7): the chest's, potions")
	_check(not bool(m["stance"]) and not bool(m["combat"]), "no target, no swing, no hit: out of stance, out of a fight")
	c.target_id = 7
	m = RegentsAbilityBar.model_for(c, sk)
	_check(bool(m["stance"]) and not bool(m["combat"]), "a target picked: in stance, and still not in a fight")
	c.note_fight()
	m = RegentsAbilityBar.model_for(c, sk)
	_check(bool(m["combat"]), "a hit just now: in a fight (the bar glows)")
	c.fought_ms = Time.get_ticks_msec() - int(c.fight_s * 1000.0) - 1
	_check(not bool(RegentsAbilityBar.model_for(c, sk)["combat"]), "past fight_s since the last hit: out of the fight")
	# A cooldown.
	c.spell_ready_ms[sword.skills[0].id] = Time.get_ticks_msec() + 4000
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 0) == RegentsAbilitySlot.COOLING and float(_slot(m, 0)["left"]) > 3.5 and is_equal_approx(float(_slot(m, 0)["total"]), 6.0),
		"Lunge used: cooling, about 4 s left of its 6")
	c.spell_ready_ms.clear()
	_check(_state(RegentsAbilityBar.model_for(c, sk), 0) == RegentsAbilitySlot.READY, "its cooldown over: ready again")
	# The roll.
	var roll: Dictionary = m["roll"] as Dictionary
	_check(String(roll["key"]) == CombatComponent.key_label(CombatComponent.ACTION_DODGE) and String(roll["tip"]).contains("Roll"),
		"the roll's slot, on its key (%s)" % String(roll["key"]))
	# THE STAFF BY ITS ITEM (ABILITIES_PREP.md §7 step 2): Fireball on Q and Blink on F from level 1; E a pick at 5.
	var staff: KitDef = KitDef.by_key(&"staff")
	c.kit = staff
	c.weapon = ItemDef.by_id(40023)
	var mana: ResourceComponent = ResourceComponent.new()
	c.pool_for_tests = mana
	_fill(mana, staff.resource.id, staff.resource.max_amount)
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 0) == RegentsAbilitySlot.READY and String(_slot(m, 0)["name"]) == "Fireball" and _state(m, 3) == RegentsAbilitySlot.READY
		and String(_slot(m, 3)["name"]) == "Blink" and _state(m, 1) == RegentsAbilitySlot.LOCKED and _state(m, 2) == RegentsAbilitySlot.LOCKED
		and String(_slot(m, 2)["note"]) == "lvl 20",
		"a new staff: Fireball on Q, Blink on F, E locked (its pick at 5), R locked (its last pick at 20)")
	_check(String(_slot(m, 1)["note"]) == "lvl 5" and String(_slot(m, 1)["tip"]).contains("Frost Ring") and String(_slot(m, 1)["tip"]).contains("Gale"),
		"E says when it opens and what it offers (%s)" % String(_slot(m, 1)["tip"]))
	_check(String((m["pool"] as Dictionary)["kind"]) == "mana" and is_equal_approx(float((m["pool"] as Dictionary)["most"]), staff.resource.max_amount),
		"the staff's mana beside the slots")
	_fill(mana, staff.resource.id, 5.0)
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 0) == RegentsAbilitySlot.COST, "5 mana: Fireball shows it cannot be paid")
	_fill(mana, staff.resource.id, staff.resource.max_amount)
	var lvl5: int = RegentsAbilityBar._xp_for(staff.skill, 5)
	sk.xp[staff.skill.id] = lvl5
	c.weapon_data_for_tests = JSON.stringify({"q": 650, "x": lvl5})
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 1) == RegentsAbilitySlot.CHOOSE and String(_slot(m, 1)["tip"]).contains("Frost Ring or Gale"),
		"level 5, nothing chosen: E asks you to choose (%s)" % String(_slot(m, 1)["tip"]))
	sk.xp[staff.skill.id] = RegentsAbilityBar._xp_for(staff.skill, 3)
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 1) == RegentsAbilitySlot.LOCKED and int(m["usable"]) == 3 and int(m["level"]) == 5 and String(m["ring_tip"]).contains("counting as 3"),
		"NEGATIVE (B2): a level-5 staff in a Sorcery-3 hand counts as 3: E locked (%s)" % String(m["ring_tip"]))
	sk.xp[staff.skill.id] = 1000000
	c.weapon_data_for_tests = JSON.stringify({"q": 650, "x": lvl5, "k": [40014, 0, 0]})
	m = RegentsAbilityBar.model_for(c, sk)
	_check(_state(m, 0) == RegentsAbilitySlot.READY and String(_slot(m, 1)["name"]) == "Frost Ring" and _state(m, 1) == RegentsAbilitySlot.READY
		and _state(m, 3) == RegentsAbilitySlot.READY, "Frost Ring picked at 5: Fireball, Frost Ring, Blink ready")
	_check(c.on_slot(1) != null and c.on_slot(1).id == 40014 and c.on_slot(2) == null and c.skill_key_is_skill(1, false),
		"E presses Frost Ring now; R has nothing")
	_check(String(_slot(m, 3)["tip"]).contains("Carries you") and String(_slot(m, 1)["tip"]).contains("circle"),
		"each spell in its own words: Blink carries you, Frost Ring is a circle")
	c.weapon_data_for_tests = JSON.stringify({"q": 650, "x": lvl5, "k": [40016, 0, 0]})
	_check(String(RegentsAbilityBar.model_for(c, sk)["slots"][1]["name"]) == "Gale", "Gale picked instead: Gale on E")
	c.weapon_data_for_tests = ""
	# The bow: arrows beside.
	c.kit = KitDef.by_key(&"bow")
	c.weapon = ItemDef.by_id(40020)
	c.target_id = -1
	m = RegentsAbilityBar.model_for(c, sk)
	_check(String((m["pool"] as Dictionary)["kind"]) == "arrows" and String((m["pool"] as Dictionary)["text"]).contains("arrows")
		and String((m["weapon"] as Dictionary)["tip"]).contains("draw"), "the bow: its arrows beside, draw and loose in its tooltip")
	mana.free()
	sk.free()
	c.free()


## A pool at `level` now (as the server's row would say).
func _fill(pool: ResourceComponent, resource_id: int, level: float) -> void:
	var row := RegentsBarLab.PoolRow.new()
	row.resource_id = resource_id
	row.stored = level
	row.at = ClockSync.server_usec()
	pool._apply(row)


func _run_ring() -> void:
	var staff: KitDef = KitDef.by_key(&"staff")
	var p: Dictionary = RegentsItemLevel.progress(staff, 0, 1)
	_check(int(p["level"]) == 1 and int(p["next"]) == 5 and is_zero_approx(float(p["frac"])), "a new staff: level 1, the ring empty toward 5")
	var to5: int = RegentsAbilityBar._xp_for(staff.skill, 5)
	p = RegentsItemLevel.progress(staff, to5 / 2, 33)
	_check(absf(float(p["frac"]) - 0.5) < 0.02, "half the XP to level 5: the ring half full (%.2f)" % float(p["frac"]))
	p = RegentsItemLevel.progress(staff, to5, 33)
	_check(int(p["level"]) == 5 and int(p["next"]) == 12 and float(p["frac"]) < 0.01, "level 5: the ring starts over toward 12")
	p = RegentsItemLevel.progress(staff, 1000000, 2)
	_check(int(p["level"]) == SkillDef.RANK_TOP and int(p["usable"]) == 2 and int(p["next"]) == 0 and is_equal_approx(float(p["frac"]), 1.0),
		"the top: every unlock passed, the ring full; in a mastery-2 hand it counts as 2")
	var pts: PackedVector2Array = RegentsAbilityBar.ring_points(Rect2(0, 0, 200, 60), true)
	_check(pts[0].is_equal_approx(pts[pts.size() - 1]), "the ring's path closes on itself")
	var half: PackedVector2Array = RegentsAbilityBar.along(pts, 0.5)
	_check(half.size() >= 2 and half[half.size() - 1].y > 30.0 and RegentsAbilityBar.along(pts, 0.0).is_empty(),
		"half the ring ends on the far side; none draws nothing")


## THE CLIENT'S TWIN of the server's item rules (`RegentsItemLevel`; the native suite's `item_levels_and_picks` holds the
## Rust to the same cases).
func _run_item_twin() -> void:
	var staff: KitDef = KitDef.by_key(&"staff")
	var data: String = "{\"q\":650,\"h\":40016,\"p\":[40016,40012],\"t\":[40001],\"x\":300,\"k\":[40014,0,0]}"
	_check(RegentsItemLevel.xp_of(data) == 300 and RegentsItemLevel.picks_of(data) == [40014, 0, 0] and RegentsItemLevel.xp_of("{\"q\":1}") == 0
		and RegentsItemLevel.picks_of("") == [0, 0, 0], "the item's XP and picks read from its row")
	_check(RegentsItemLevel.level(staff, 60) == 5 and RegentsItemLevel.level(staff, 280) == 12 and RegentsItemLevel.usable(20, 12) == 12
		and RegentsItemLevel.usable(5, 0) == 1, "its level on the kind's curve; used up to the holder's mastery")
	_check(staff.skill_slots == PackedInt32Array([0, 1, 3, 1, 2]) and staff.unlock_levels == PackedInt32Array([1, 5, 12, 20]) and staff.validate().is_empty(),
		"the staff's layout: Fireball the base, Frost Ring and Gale options, Blink on F, Meteor (placeholder) the ult; 1, 5, 12, 20")
	var fireball: AbilityDef = staff.skills[0]
	var frost: AbilityDef = staff.skills[1]
	var blink: AbilityDef = staff.skills[2]
	var gale: AbilityDef = staff.skills[3]
	var meteor: AbilityDef = staff.skills[4]
	# STEP 76'S RULE (a kit with no ult of its own: its last pick takes the option E did not) on a staff without its ult.
	var no_ult: KitDef = staff.duplicate() as KitDef
	no_ult.skills = staff.skills.slice(0, 4)
	no_ult.skill_slots = PackedInt32Array([0, 1, 3, 1])
	var none: Array[int] = [0, 0, 0]
	var took_frost: Array[int] = [frost.id, 0, 0]
	_check(RegentsItemLevel.slot_refusal(staff, fireball, 1, none).is_empty() and RegentsItemLevel.slot_refusal(staff, blink, 1, none).is_empty(), "Fireball and Blink from 1")
	_check(RegentsItemLevel.slot_refusal(staff, frost, 33, none).contains("not chosen"), "NEGATIVE: Frost Ring unpicked, at any level")
	_check(RegentsItemLevel.slot_refusal(staff, frost, 4, took_frost).contains("level 5"), "NEGATIVE: picked, but it counts as 4")
	_check(RegentsItemLevel.slot_refusal(staff, frost, 5, took_frost).is_empty() and not RegentsItemLevel.slot_refusal(staff, gale, 5, took_frost).is_empty(),
		"Frost Ring picked: it, not Gale")
	_check(RegentsItemLevel.pick_refusal(staff, 0, frost, 4, none).contains("level 5") and RegentsItemLevel.pick_refusal(staff, 0, frost, 5, none).is_empty()
		and RegentsItemLevel.pick_refusal(staff, 0, gale, 5, none).is_empty(), "the first pick: opens at 5, Frost Ring or Gale")
	_check(not RegentsItemLevel.pick_refusal(staff, 0, fireball, 5, none).is_empty() and not RegentsItemLevel.pick_refusal(staff, 0, blink, 5, none).is_empty(),
		"NEGATIVE: not the base, not F")
	_check(RegentsItemLevel.pick_refusal(staff, 0, gale, 5, took_frost).contains("change it instead") and RegentsItemLevel.pick_refusal(staff, 0, frost, 5, took_frost).contains("already"),
		"NEGATIVE: a chosen pick is changed, not chosen again (B13); the same again: already")
	_check(RegentsItemLevel.pick_refusal(staff, 1, gale, 12, took_frost).contains("E holds one") and RegentsItemLevel.pick_refusal(staff, 1, gale, 11, took_frost).contains("level 12"),
		"NEGATIVE: the second pick opens at 12, and E holds one ability")
	var open: Array[Dictionary] = RegentsItemLevel.open_picks(staff, 5, none)
	_check(open.size() == 1 and int(open[0]["n"]) == 0 and (open[0]["options"] as Array[AbilityDef]).size() == 2 and RegentsItemLevel.open_picks(staff, 19, took_frost).is_empty()
		and RegentsItemLevel.open_picks(staff, 4, none).is_empty(), "open picks: the first at 5 offers two; none once taken until 20 (no upgrades yet), none below 5")
	_check(not RegentsItemLevel.has_ults(no_ult) and RegentsItemLevel.pick_refusal(no_ult, 2, gale, 20, took_frost).is_empty()
		and RegentsItemLevel.pick_refusal(no_ult, 2, gale, 19, took_frost).contains("level 20") and RegentsItemLevel.pick_refusal(no_ult, 2, frost, 20, took_frost).contains("another pick"),
		"R on a kit with no ult: at 20 the last pick takes Gale; NEGATIVES: at 19, and Frost Ring again")
	var both: Array[int] = [frost.id, 0, gale.id]
	_check(RegentsItemLevel.bar(no_ult, both)[2] == gale and RegentsItemLevel.slot_refusal(no_ult, gale, 20, both).is_empty()
		and RegentsItemLevel.slot_refusal(no_ult, gale, 19, both).contains("level 20"), "no ult: Gale on R from 20; NEGATIVE: shut at 19")
	var open_n: Array[Dictionary] = RegentsItemLevel.open_picks(no_ult, 33, took_frost)
	_check(open_n.size() == 1 and int(open_n[0]["n"]) == 2 and (open_n[0]["options"] as Array[AbilityDef]) == [gale], "no ult, at 33 with Frost Ring: R's pick open, offering Gale")
	# THE STAFF'S ULT (armor run P1): R takes Meteor only; the option E left over no longer goes there.
	_check(RegentsItemLevel.has_ults(staff) and RegentsItemLevel.pick_refusal(staff, 2, meteor, 20, took_frost).is_empty()
		and RegentsItemLevel.pick_refusal(staff, 2, meteor, 19, took_frost).contains("level 20"),
		"the staff's ult: Meteor (placeholder) at the last pick from 20; NEGATIVE: at 19")
	_check(RegentsItemLevel.pick_refusal(staff, 2, gale, 20, took_frost).contains("last picks") and not RegentsItemLevel.pick_refusal(staff, 0, meteor, 5, none).is_empty(),
		"NEGATIVES: with an ult, Gale is no last pick; Meteor is no first pick")
	var stale: Array[int] = [frost.id, 0, gale.id]
	_check(RegentsItemLevel.slot_refusal(staff, gale, 33, stale).contains("not chosen") and RegentsItemLevel.bar(staff, stale)[2] == null,
		"NEGATIVE: a staff that took Gale on R before the ult: Gale no longer fires from R (change the pick)")
	var with_ult: Array[int] = [frost.id, 0, meteor.id]
	_check(RegentsItemLevel.bar(staff, with_ult)[2] == meteor and RegentsItemLevel.slot_refusal(staff, meteor, 20, with_ult).is_empty()
		and RegentsItemLevel.slot_refusal(staff, meteor, 19, with_ult).contains("level 20"), "Meteor on R from 20; NEGATIVE: shut at 19")
	var open_r: Array[Dictionary] = RegentsItemLevel.open_picks(staff, 33, took_frost)
	_check(open_r.size() == 1 and int(open_r[0]["n"]) == 2 and (open_r[0]["options"] as Array[AbilityDef]) == [meteor], "at 33 with Frost Ring: R's pick open, offering Meteor")
	var bar: Array[AbilityDef] = RegentsItemLevel.bar(staff, took_frost)
	_check(bar[0] == fireball and bar[1] == frost and bar[2] == null and bar[3] == blink, "the bar: Fireball, Frost Ring, nothing, Blink")
	var sword: KitDef = KitDef.by_key(&"sword")
	var sword_open: Array[Dictionary] = RegentsItemLevel.open_picks(sword, 33, none)
	_check(RegentsItemLevel.bar(sword, none)[0] == sword.skills[0] and sword.skills[0].display_name == "Lunge" and sword_open.size() == 3
		and (sword_open[0]["options"] as Array[AbilityDef]).size() == 3 and int(sword_open[2]["n"]) == 2
		and (sword_open[2]["options"] as Array[AbilityDef]) == sword.skills_in(KitDef.SLOT_ULT)
		and RegentsItemLevel.open_picks(sword, 4, none).is_empty(),
		"the sword's placeholder pool: Lunge on Q; at 33 three for E (either pick) and its ult for R; NEGATIVE: nothing open at 4")
	for key: StringName in [&"sword", &"axe", &"bow", &"staff"]:
		var k: KitDef = KitDef.by_key(key)
		var ok: bool = (k.validate().is_empty() and k.skills_in(KitDef.SLOT_BASE).size() == 1 and k.skills_in(KitDef.SLOT_ULT).size() == 1
			and k.skills_in(KitDef.SLOT_OPTION).size() >= 2)
		for a: AbilityDef in k.skills_in(KitDef.SLOT_OPTION) + k.skills_in(KitDef.SLOT_ULT):
			ok = ok and (a.display_name.ends_with("(placeholder)") or a.display_name in ["Frost Ring", "Gale"])
		_check(ok, "%s: one Q, options for E, one ult on R, every new one named (placeholder)" % key)
	var bad: KitDef = staff.duplicate() as KitDef
	bad.skill_slots = PackedInt32Array([0, 0, 3, 1])
	_check(bad.validate().any(func(e: String) -> bool: return e.contains("one base")), "NEGATIVE: two bases refused")
	bad.skill_slots = PackedInt32Array([0, 1])
	_check(bad.validate().any(func(e: String) -> bool: return e.contains("a slot per skill")), "NEGATIVE: a slot short refused")
	# The press refuses what the server would.
	var c: CombatComponent = CombatComponent.new()
	c.kit = staff
	c.mastery_for_tests = 33
	var said: Array[String] = []
	c.refused.connect(func(why: String) -> void: said.append(why))
	c.weapon_data_for_tests = JSON.stringify({"x": 0})
	c.press("skill", 1)
	_check(said.size() == 1 and said[0] == "Nothing on that key yet", "a new staff: E has nothing (%s)" % str(said))
	c.weapon_data_for_tests = JSON.stringify({"x": 0, "k": [frost.id, 0, 0]})
	said.clear()
	c.press("skill", 1)
	_check(said.size() == 1 and said[0].contains("Frost Ring: opens at the weapon's level 5"), "NEGATIVE: picked on a level-1 staff, refused here first (%s)" % str(said))
	c.free()


## THE ABILITIES WINDOW (Luke, 2026-11-14): a weapon's level against your mastery, its four slots as the bar draws them,
## a card per option for each pick open, a card per change with its price; opened from the bag and from the bar's weapon.
func _run_bag_picks() -> void:
	var staff: KitDef = KitDef.by_key(&"staff")
	var lvl5: int = RegentsAbilityBar._xp_for(staff.skill, 5)
	var layer := CanvasLayer.new()
	add_child(layer)
	var inv := SpaceTimeInventoryComponent.new()
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": lvl5}))
	var sk := SkillingComponent.new()
	sk.xp[staff.skill.id] = lvl5
	var cc := CombatComponent.new()
	var win := RegentsAbilitiesWindow.new()
	win.inventory = inv
	win.combat = cc
	win.skilling = sk
	var bag := RegentsBagWindow.new()
	bag.inventory = inv
	bag.combat = cc
	bag.skilling = sk
	bag.abilities = win
	layer.add_child(bag)
	layer.add_child(win)
	bag.picked_row = 1
	bag.open()
	await get_tree().process_frame
	var level: Label = bag.find_child("Level", true, false) as Label
	var open_button: Button = bag.find_child("Abilities_1", true, false) as Button
	_check(level != null and level.text.begins_with("Level 5") and level.text.contains("pick is open") and open_button != null and bag.find_child("Pick_0", true, false) == null,
		"the bag: the staff's level, a pick open, and an Abilities button (the choosing is in its own window now)")
	open_button.pressed.emit()
	await get_tree().process_frame
	_check(win.is_open() and win.row == 1 and win.title.contains("staff"), "Abilities opens the staff's own window (%s)" % win.title)
	var row: Node = win.find_child("Pick_0", true, false)
	_check(row != null and row.find_child("Choose_40014", true, false) != null and row.find_child("Choose_40016", true, false) != null,
		"level 5: a pick open for E: Frost Ring or Gale")
	var slots: Node = win.find_child("Slots", true, false)
	var q_name: Label = win.find_child("Slot_Q", true, false).find_child("Name", true, false) as Label if win.find_child("Slot_Q", true, false) != null else null
	var e_slot: RegentsAbilitySlot = win.find_child("Slot_E", true, false).get_child(0) as RegentsAbilitySlot if win.find_child("Slot_E", true, false) != null else null
	_check(slots != null and slots.get_child_count() == 4 and q_name != null and q_name.text == "Fireball" and e_slot != null and e_slot.state() == RegentsAbilitySlot.CHOOSE,
		"its four slots as the bar draws them: Fireball on Q, E waiting on the pick")
	sk.xp[staff.skill.id] = RegentsAbilityBar._xp_for(staff.skill, 4)
	win.refresh()
	await get_tree().process_frame
	level = win.find_child("Level", true, false) as Label
	_check(win.find_child("Pick_0", true, false) == null and level != null and level.text.contains("counting as 4"),
		"NEGATIVE: in a Sorcery-4 hand it counts as 4: no pick open (%s)" % (level.text if level != null else "none"))
	# R: at 20 the last pick takes the staff's ult (armor run P1: Meteor, a placeholder), never the spell E did not.
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": RegentsAbilityBar._xp_for(staff.skill, 20), "k": [40014, 0, 0]}))
	sk.xp[staff.skill.id] = 100000
	win.refresh()
	await get_tree().process_frame
	row = win.find_child("Pick_2", true, false)
	_check(row != null and row.find_child("Choose_40048", true, false) != null and row.find_child("Choose_40016", true, false) == null
		and row.find_child("Choose_40014", true, false) == null,
		"level 20, Frost Ring on E: the last pick (R) offers Meteor (placeholder); NEGATIVE: not Gale, not Frost Ring")
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": RegentsAbilityBar._xp_for(staff.skill, 20), "k": [40014, 0, 40048]}))
	win.refresh()
	await get_tree().process_frame
	var r_name: Label = win.find_child("Slot_R", true, false).find_child("Name", true, false) as Label
	var e_name: Label = win.find_child("Slot_E", true, false).find_child("Name", true, false) as Label
	_check(r_name.text == "Meteor (placeholder)" and e_name.text == "Frost Ring" and win.find_child("Pick_2", true, false) == null,
		"both taken: Frost Ring on E, Meteor on R, nothing open")
	# The bar's weapon opens it too.
	var bar := RegentsAbilityBar.new()
	bar.follows_setting = false
	bar.style = RegentsAbilityBar.look(0)
	layer.add_child(bar)
	await get_tree().process_frame
	var heard: Array[bool] = [false]
	bar.weapon_pressed.connect(func() -> void: heard[0] = true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bar.weapon_slot._gui_input(click)
	var other: Array[bool] = [false]
	bar.slots[0].pressed.connect(func() -> void: other[0] = true)
	bar.slots[0]._gui_input(click)
	_check(heard[0], "a click on the bar's weapon: its abilities (the HUD opens the window on it)")
	bar.queue_free()
	win.close()
	bag.close()
	layer.queue_free()
	cc.free()
	sk.free()
	inv.free()
	await get_tree().process_frame


## CHANGING A PICK (Luke's B13): the twin of the server's rules (the native `changing_a_pick` holds the Rust to the same
## cases), and the window's change rows with their price.
func _run_changes() -> void:
	var staff: KitDef = KitDef.by_key(&"staff")
	var frost: AbilityDef = staff.skills[1]
	var gale: AbilityDef = staff.skills[3]
	var took_frost: Array[int] = [frost.id, 0, 0]
	var none: Array[int] = [0, 0, 0]
	_check(RegentsItemLevel.change_refusal(staff, 0, gale, 5, took_frost).is_empty(), "Frost Ring to Gale: allowed")
	_check(RegentsItemLevel.change_refusal(staff, 0, gale, 5, none).contains("nothing chosen") and RegentsItemLevel.change_refusal(staff, 0, frost, 5, took_frost).contains("already")
		and not RegentsItemLevel.change_refusal(staff, 0, staff.skills[0], 5, took_frost).is_empty() and RegentsItemLevel.change_refusal(staff, 0, gale, 4, took_frost).contains("level 5"),
		"NEGATIVES: nothing chosen, the same, the base, the pick shut at 4")
	_check(RegentsItemLevel.change_refusal(staff, 0, gale, 33, [frost.id, 0, gale.id]).contains("another pick"), "NEGATIVE: E to Gale while R holds it")
	var yew_staff: ItemDef = ItemDef.by_id(40023)
	var iron_sword: ItemDef = ItemDef.by_id(40019)
	_check(RegentsItemLevel.head_material(iron_sword) != null and RegentsItemLevel.head_material(iron_sword).display_name == "Iron bar"
		and RegentsItemLevel.head_material(yew_staff) != null and RegentsItemLevel.head_material(yew_staff).display_name == "Yew logs",
		"the head's material: an iron sword's Iron bar; a staff's Yew logs")
	var now: int = 1800000000
	var day: int = 86400
	var p: Dictionary = RegentsItemLevel.change_price(yew_staff, "{\"x\":980}", 20, now)
	_check(bool(p["free"]), "level 20, never changed: free")
	p = RegentsItemLevel.change_price(yew_staff, "{\"x\":980}", 19, now)
	_check(not bool(p["free"]) and int(p["qty"]) == 2, "NEGATIVE: level 19: no free change; 2 of the head's material")
	p = RegentsItemLevel.change_price(yew_staff, JSON.stringify({"f": now - 6 * day, "e": 2, "c": now - 6 * day}), 25, now)
	_check(not bool(p["free"]) and int(p["qty"]) == 8, "free used six days ago: paid, and it has doubled twice: 8")
	p = RegentsItemLevel.change_price(yew_staff, JSON.stringify({"f": now - 7 * day, "e": 2, "c": now - 7 * day}), 25, now)
	_check(bool(p["free"]) and int(p["qty"]) == 4, "a week on: free again, and one doubling forgiven (4 if paid)")
	p = RegentsItemLevel.change_price(yew_staff, JSON.stringify({"e": 9, "c": now}), 5, now)
	_check(int(p["qty"]) == 64, "at most five doublings: 64")
	# The window: a chosen pick offers its change, priced.
	var layer := CanvasLayer.new()
	add_child(layer)
	var inv := SpaceTimeInventoryComponent.new()
	var lvl5: int = RegentsAbilityBar._xp_for(staff.skill, 5)
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": lvl5, "k": [frost.id, 0, 0]}))
	var sk := SkillingComponent.new()
	sk.xp[staff.skill.id] = 100000
	var cc := CombatComponent.new()
	var win := RegentsAbilitiesWindow.new()
	win.inventory = inv
	win.combat = cc
	win.skilling = sk
	layer.add_child(win)
	win.show_row(1)
	await get_tree().process_frame
	var price: Label = win.find_child("Price_0", true, false) as Label
	_check(win.find_child("ChangeTo_40016", true, false) != null and price != null and price.text.contains("2 Yew logs, at a workbench") and price.text.contains("Frost Ring"),
		"a level-5 staff with Frost Ring: change E to Gale for 2 Yew logs at a workbench (%s)" % (price.text if price != null else "none"))
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": RegentsAbilityBar._xp_for(staff.skill, 20), "k": [frost.id, 0, 0]}))
	win.refresh()
	await get_tree().process_frame
	price = win.find_child("Price_0", true, false) as Label
	_check(price != null and price.text.contains("free this week"), "at level 20: free this week (%s)" % (price.text if price != null else "none"))
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40023, 1, 0, JSON.stringify({"q": 650, "x": lvl5}))
	win.refresh()
	await get_tree().process_frame
	_check(win.find_child("Change_0", true, false) == null and win.find_child("Pick_0", true, false) != null, "NEGATIVE: nothing chosen: a pick to choose, nothing to change")
	win.close()
	layer.queue_free()
	cc.free()
	sk.free()
	inv.free()
	await get_tree().process_frame


func _run_words() -> void:
	var c: CombatComponent = CombatComponent.new()
	var sk: SkillingComponent = SkillingComponent.new()
	c.kit = KitDef.by_key(&"sword")
	c.weapon = ItemDef.by_id(40019)
	var w: String = RegentsAbilityBar.moves_words(c, sk)
	# The string by its moves' names, the last the plain grip's (no row in a bag: the plain role); never "finisher".
	_check(w.contains("Iron sword") and w.contains("Slash - Slash (second) - Piercing thrust") and w.contains("tap to parry, hold for a light guard")
		and w.contains("roll") and w.contains("Tab"), "the weapon's tooltip says what the text line did: %s" % w.replace("\n", " / "))
	var everything: String = w
	for m: Dictionary in [RegentsAbilityBar.model_for(c, sk)]:
		for d: Dictionary in _slots(m):
			everything += String(d.get("tip", ""))
	for word: String in ["finisher", "tank", "support", "dps", "stance", "role"]:
		_check(not everything.to_lower().contains(word), "no \"%s\" on the bar (show, don't name)" % word)
	sk.free()
	c.free()


func _run_drawn() -> void:
	var bar: RegentsAbilityBar = RegentsAbilityBar.new()
	bar.follows_setting = false
	bar.style = RegentsAbilityBar.look(0)
	add_child(bar)
	await get_tree().process_frame
	_check(bar.slots.size() == 4 and bar.weapon_slot != null and bar.roll_slot != null and bar.potion_slot != null,
		"the bar: the weapon, the roll, four slots, the potion")
	var c: CombatComponent = CombatComponent.new()
	var sk: SkillingComponent = SkillingComponent.new()
	c.kit = KitDef.by_key(&"sword")
	c.weapon = ItemDef.by_id(40019)
	var m: Dictionary = RegentsAbilityBar.model_for(c, sk)
	m["health"] = Vector2(40.0, 100.0)
	bar.show_model(m)
	_check(bar.slots[0].tooltip_text == String(_slot(m, 0)["tip"]) and bar.weapon_slot.tooltip_text.contains("Slash"),
		"hover: each slot's words, the weapon's moves")
	_check(bar.health_bar.visible and is_equal_approx(bar.health_bar.value, 40.0), "health above the slots")
	_check(bar.slots[0].size.x == float(bar.style.slot_size) and bar.potion_slot.size.x == float(bar.style.small_size)
		and bar.slots[1].position.x > bar.slots[0].position.x, "Q E R F in a row, the potion smaller")
	bar.fired(c.kit.skills[0].id)
	_check(bar.slots[0]._flashing() and not bar.slots[1]._flashing(), "Lunge fired: its slot flashes, no other")
	# Out of stance it fades; in it, full.
	for i: int in 30:
		await get_tree().process_frame
	_check(bar.slots[0].modulate.a < 0.9, "out of stance the slots fade (%.2f)" % bar.slots[0].modulate.a)
	c.target_id = 7
	bar.show_model(RegentsAbilityBar.model_for(c, sk))
	for i: int in 30:
		await get_tree().process_frame
	_check(is_equal_approx(bar.slots[0].modulate.a, 1.0) and bar.slots[0].lit, "in stance: full, its edges lit")
	# A click over the bar still reaches the game (found by the combat playtest: a slot that STOPPED the mouse ate the
	# first chop, as it would a swing in play with the cursor over the bar).
	var through: int = await _click_through()
	_check(through == 1, "a left click over the bar reaches the game (%d)" % through)
	var every: Array[RegentsAbilitySlot] = [bar.weapon_slot, bar.roll_slot, bar.potion_slot]
	every.append_array(bar.slots)
	for sl: RegentsAbilitySlot in every:
		sl.mouse_filter = Control.MOUSE_FILTER_STOP
	var eaten: int = await _click_through()
	_check(eaten == 0, "NEGATIVE: slots that stop the mouse eat it (%d)" % eaten)
	bar.set_style(RegentsAbilityBar.look(1))
	_check(bar.slots.size() == 4 and bar.slots[0].style.shape == RegentsBarStyle.Shape.SQUARE and bar.slots[0].size.x == float(RegentsAbilityBar.look(1).slot_size),
		"switched to square: the slots rebuilt in its look")
	bar.queue_free()
	# The game's bar follows the setting.
	RegentsAbilityBar.define_setting()
	var kept: Variant = Settings.get_value(RegentsAbilityBar.SETTING)
	Settings.set_value(RegentsAbilityBar.SETTING, 0)
	var hud_bar: RegentsAbilityBar = RegentsAbilityBar.new()
	add_child(hud_bar)
	_check(hud_bar.style.shape == RegentsBarStyle.Shape.ROUND, "the game's bar: round, as the setting says")
	Settings.set_value(RegentsAbilityBar.SETTING, 1)
	_check(hud_bar.style.shape == RegentsBarStyle.Shape.SQUARE and hud_bar.slots[0].style.shape == RegentsBarStyle.Shape.SQUARE,
		"the setting changed to square: the game's bar is square at once")
	Settings.set_value(RegentsAbilityBar.SETTING, kept)
	hud_bar.queue_free()
	sk.free()
	c.free()
	await get_tree().process_frame


func _run_lab() -> void:
	var scene: PackedScene = load("res://game/regents/ui/bar_lab.tscn") as PackedScene
	_check(scene != null, "the bar lab's scene loads")
	if scene == null:
		return
	var lab: RegentsBarLab = scene.instantiate() as RegentsBarLab
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.bars.size() == 2 and lab.bars[0].style.shape == RegentsBarStyle.Shape.ROUND and lab.bars[1].style.shape == RegentsBarStyle.Shape.SQUARE,
		"the lab: the round bar and the square one")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	lab._unhandled_key_input(q)
	await get_tree().process_frame
	_check(lab.bars[0].slots[0].state() == RegentsAbilitySlot.COOLING and lab.bars[1].slots[0].state() == RegentsAbilitySlot.COOLING,
		"Q in the lab: Lunge cools down on both bars")
	lab._set_kit(&"staff")
	lab.rank = 1
	lab._set_rank(1.0)
	await get_tree().process_frame
	_check(lab.bars[0].slots[1].state() == RegentsAbilitySlot.LOCKED and lab.bars[0].pool_bar.visible, "the staff at rank 1 in the lab: locks, and mana beside")
	lab.queue_free()
	await get_tree().process_frame
