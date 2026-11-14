extends "res://tests/suite_base.gd"
## The `roll` suite (tests/test_runner.gd runs it; `-- --only=roll` runs it alone).
## THE DODGE ROLL (DECISIONS #309): the content (what a roll bakes, what it refuses), the foundation's Dodge roll
## and Rolling, a character's `dodge_roll`, and the RollComponent on a real entity: a roll taken (sent, dashed,
## held to its way, announced), refused on its cooldown, held in the air until the ground and lapsing after
## `foundation.roll_hold_ms`, a roll that may begin in the air, the server's refusal, the way it goes, its length
## from a hot rule; every entity given one.

const DODGE: String = "res://foundation/content/ability/dodge_roll.tres"


func run() -> void:
	_run_content()
	_run_direction()
	await _run_component()
	_run_everywhere()
	await get_tree().process_frame


func _run_content() -> void:
	print("== roll: content ==")
	var dodge: AbilityDef = load(DODGE) as AbilityDef
	_check(dodge != null and dodge.rolls and dodge.id == 1, "the foundation's Dodge roll is ability 1 and rolls")
	_check(dodge.validate().is_empty(), "and is valid (%s)" % str(dodge.validate()))
	_check(dodge.roll_status != null and dodge.roll_status.status == 7 and not dodge.roll_status.hittable,
		"its status is the foundation's Rolling (7), which cannot be hit")
	var baked: Dictionary = dodge.to_bake()
	_check(bool(baked.get("rolls", false)) and int(baked["roll_status"]) == 7 and int(baked["roll_ms"]) == 550 and not bool(baked["roll_in_air"]),
		"its bake carries the roll: status 7, 550 ms, not in the air (%s)" % str(baked))
	var plain := AbilityDef.new()
	_check(not plain.to_bake().has("rolls") and not plain.to_bake().has("roll_ms"), "an ability that does not roll bakes as it did: no roll keys (no game's bake goes stale)")

	var bad := AbilityDef.new()
	bad.rolls = true
	_check(_has(bad.validate(), "no status"), "a roll with no status is refused")
	var hittable := StatusDef.new()
	hittable.display_name = "Open"
	bad.roll_status = hittable
	_check(_has(bad.validate(), "can be hit"), "a roll whose status can be hit is refused")
	bad.roll_status = dodge.roll_status
	bad.judged = true
	bad.lunges = true
	var why: Array[String] = bad.validate()
	_check(_has(why, "judged") and _has(why, "lunges"), "a roll that is judged, or lunges, is refused (%s)" % str(why))
	bad.judged = false
	bad.lunges = false
	bad.roll_ms = 0
	_check(_has(bad.validate(), "no time"), "a roll of no length (and no rule) is refused")
	bad.roll_ms_rule = &"foundation.roll_hold_ms"
	_check(not _has(bad.validate(), "no time"), "unless a hot rule gives its length")

	var defn := EntityDefinition.new()
	_check(not defn.to_bake().has("roll"), "a character with no dodge roll bakes as it did")
	_check(not LocalInputComponent.lunges_by_ability(defn), "and its dash key dashes")
	defn.dodge_roll = dodge
	_check(int(defn.to_bake()["roll"]) == 1, "one with the Dodge roll bakes it (the server adds it to what its kind may use)")
	_check(LocalInputComponent.lunges_by_ability(defn), "and its dash key no longer dashes on its own: it rolls")
	defn.dodge_roll = plain
	_check(_has(defn.validate(), "not a roll"), "a dodge roll that is not a roll is refused")


## The way a roll goes: the server's twin is `roll::direction` (server/tests/roll.rs checks the same cases).
func _run_direction() -> void:
	print("== roll: the way it goes ==")
	_check(RollComponent.direction_for(Vector2(0, -1), 0.0).is_equal_approx(Vector2(0, -1)), "facing north, forward: north")
	_check(RollComponent.direction_for(Vector2(1, 0), 0.0).is_equal_approx(Vector2(1, 0)), "right: east")
	_check(RollComponent.direction_for(Vector2.ZERO, 0.0).is_equal_approx(Vector2(0, -1)), "nothing pressed: the way it faces")
	_check(RollComponent.direction_for(Vector2(0, -1), PI / 2.0).is_equal_approx(Vector2(-1, 0)), "turned a quarter left, forward: west")
	_check(RollComponent.direction_for(Vector2.ZERO, PI / 2.0).is_equal_approx(Vector2(-1, 0)), "and nothing pressed: west too")
	_check(is_equal_approx(RollComponent.direction_for(Vector2(1, -1), 0.0).length(), 1.0), "a diagonal goes as far as a straight roll")
	_check(not RollComponent.direction_for(Vector2(0, 1), 0.0).is_equal_approx(Vector2(0, -1)), "backward is not forward")


class FakeDef extends RefCounted:
	var ability_id: int
	var cooldown_ms: int = 1500
	var wind_up_ms: int = 100
	var range: float = 0.0
	var damage: float = 0.0
	var data: String = "{\"rolls\":true}"
	func _init(id: int) -> void:
		ability_id = id


func _run_component() -> void:
	print("== roll: the component on a player ==")
	var dodge: AbilityDef = load(DODGE) as AbilityDef
	var defn := EntityDefinition.new()
	defn.dodge_roll = dodge
	var now_us: Array = [10_000_000]
	var ground: Array = [true]
	var reqs: Array[ReducerRequest] = []
	var ent := SpaceTimeEntity.new()
	get_tree().root.add_child(ent)
	ent.entity_id = 9501
	ent.is_local_authority = true
	ent.definition = defn
	var act := SpaceTimeActionComponent.new()
	act._clock_override = func() -> int: return int(now_us[0])
	act._def_override = func(id: int) -> RefCounted: return FakeDef.new(id) if id == 1 else null
	act._reducer_override = func(_ab: int, _tg: int, _aim: Vector3, _pid: int) -> ReducerRequest:
		var r := ReducerRequest.new()
		r.reducer_name = &"use_ability_seen"
		reqs.append(r)
		return r
	ent.add_runtime_component(act)
	var inp := LocalInputComponent.new()
	inp.send_to_server = false
	inp.capture_mouse = false
	ent.add_runtime_component(inp)
	var roll := RollComponent.new()
	roll._clock_override = func() -> int: return int(now_us[0]) / 1000
	roll._grounded_override = func() -> bool: return bool(ground[0])
	roll._keys_override = func() -> Vector2: return Vector2(1, 0)
	ent.add_runtime_component(roll)
	var none: Dictionary[StringName, RefCounted] = {}
	act.bind(ent, none)
	inp.bind(ent, none)
	inp.set_physics_process(false)   # frames are sampled by the test
	roll.bind(ent, none)
	var told: Array = []
	roll.rolled.connect(func(id: int, dir: Vector2) -> void: told.append([id, dir]))

	_check(roll.ability == dodge, "it rolls with its definition's dodge roll")
	_check(roll.key_action() == LocalInputComponent.ACTION_DASH, "on the dash key (the Dodge roll names no key of its own)")
	_check(not inp.dash_key, "and the dash key does not dash on its own")
	_check(not inp.sample().dash, "(a frame without a roll: no dash)")

	# A ROLL TAKEN: sent, dashed at once, held to its way for its length, announced.
	var pid: int = roll.roll()
	_check(pid > 0 and reqs.size() == 1, "on the ground: the roll is asked of the server at once")
	_check(roll.rolling() and roll.roll_until_ms == int(now_us[0]) / 1000 + 550, "it rolls for its 550 ms")
	_check(told.size() == 1 and int(told[0][0]) == 1 and (told[0][1] as Vector2).is_equal_approx(Vector2(1, 0)),
		"the genre is told, with the way it goes (%s)" % str(told))
	var f1: InputFrame = inp.sample()
	inp.sample()
	var f3: InputFrame = inp.sample()
	_check(f1.dash and f1.move_dir.is_equal_approx(Vector2(1, 0)), "the next frame dashes, the way the keys pushed")
	_check(not f3.dash and f3.move_dir.is_equal_approx(Vector2(1, 0)) and inp.is_forced(), "one dash only, and the way is held whatever is pressed")
	_check(roll.cooldown().x > 1.4 and is_equal_approx(roll.cooldown().y, 1.5), "its cooldown runs: %s" % str(roll.cooldown()))

	# Negative: on its cooldown nothing is sent, and the press is not kept for later.
	_check(roll.roll() == -1 and reqs.size() == 1 and roll.asked_ms < 0, "on its cooldown: refused here, nothing sent, nothing waiting")

	# THE SERVER REFUSED IT: it is not rolling, the way is let go.
	reqs[0]._settle(ReducerRequest.Outcome.REJECTED, "use_ability: no roll in the air")
	_check(not roll.rolling() and not inp.is_forced(), "refused by the server: no longer rolling, the way let go")

	# IN THE AIR: held, rolled on landing.
	now_us[0] += 2_000_000
	act.tick()
	ground[0] = false
	told.clear()
	_check(roll.roll() == -1 and reqs.size() == 1 and roll.asked_ms == int(now_us[0]) / 1000, "in the air: nothing sent, the press waits")
	now_us[0] += 300_000
	roll.tick()
	_check(reqs.size() == 1 and roll.asked_ms >= 0, "still in the air: still waiting")
	ground[0] = true
	roll.tick()
	_check(reqs.size() == 2 and roll.rolling() and roll.asked_ms < 0 and told.size() == 1, "it lands: the roll is taken")

	# Negative: a press in the air that waits past `foundation.roll_hold_ms` lapses.
	now_us[0] += 2_000_000
	act.tick()
	ground[0] = false
	roll.roll()
	var pressed_ms: int = roll.asked_ms
	var hold_ms: int = int(HotRules.number(&"foundation.roll_hold_ms"))
	# Ticked through the fall, the press keeps the moment it was made (it does not wait afresh each frame).
	now_us[0] += (hold_ms / 2) * 1000
	roll.tick()
	_check(roll.asked_ms == pressed_ms, "ticked in the air, the press keeps when it was made")
	now_us[0] += (hold_ms / 2 + 1) * 1000
	roll.tick()
	ground[0] = true
	roll.tick()
	_check(hold_ms == 1500 and reqs.size() == 2 and roll.asked_ms < 0, "a press held past %d ms lapses: landing later rolls nothing" % hold_ms)

	# A ROLL THAT MAY BEGIN IN THE AIR does.
	var airborne: AbilityDef = dodge.duplicate() as AbilityDef
	airborne.roll_in_air = true
	roll.ability = airborne
	ground[0] = false
	_check(roll.roll() > 0 and reqs.size() == 3, "one that may roll in the air rolls there")
	roll.ability = dodge

	# Its length from a hot rule, when it names one this game has; an unknown one is its own.
	var ruled: AbilityDef = dodge.duplicate() as AbilityDef
	ruled.roll_ms_rule = &"foundation.roll_hold_ms"
	_check(RollComponent.length_of(ruled) == 1500, "a hot rule gives its length live")
	ruled.roll_ms_rule = &"nobody.no_such_rule"
	_check(RollComponent.length_of(ruled) == 550, "a rule this game does not have: its own roll_ms")
	_check(RollComponent.length_of(null) == 0, "no roll, no length")

	# A character with no dodge roll does not roll.
	var plain_ent := SpaceTimeEntity.new()
	get_tree().root.add_child(plain_ent)
	plain_ent.entity_id = 9502
	plain_ent.is_local_authority = true
	plain_ent.definition = EntityDefinition.new()
	var plain_roll := RollComponent.new()
	plain_ent.add_runtime_component(plain_roll)
	plain_roll.bind(plain_ent, none)
	_check(plain_roll.ability == null and plain_roll.roll() == -1 and plain_roll.key_action() == &"", "a character with no dodge roll does not roll")
	ent.queue_free()
	plain_ent.queue_free()
	await get_tree().process_frame


func _run_everywhere() -> void:
	print("== roll: every entity can roll ==")
	var p: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	p._collect_components()
	var n: int = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is RollComponent).size()
	_check(n == 1, "an entity whose scene has none is given one (player.tscn: %d)" % n)
	p.free()


func _has(reasons: Array[String], words: String) -> bool:
	return reasons.any(func(r: String) -> bool: return r.contains(words))
