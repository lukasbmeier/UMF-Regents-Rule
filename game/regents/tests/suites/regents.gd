extends "res://tests/suite_base.gd"
## REGENT'S RULE'S `regents` suite (`-- --only=regents` runs it alone), with no server:
##   - the skilling chain's content: skills and their curves, nodes, recipes, stations, items, all valid
##     and linked as the chain needs (logs -> handle, ore -> bar -> head, head + handle + rivets -> axe)
##   - woodcutting's branch dodge (`ChopModel`): the trunk from a seed (the challenge's own generator);
##     every chop rule; a perfect player scores in full; a replay of the inputs scores what was played
##   - every model against its golden file (the Rust twins are held to the same files)
##   - the minigames (`SkillMinigames`, each `SkillMinigame`): keep every input, play through the model,
##     and their end says the replay agrees; a faster tool swings faster; the skilling lab opens them all
##   - working, shown: each skill's pose in the adventurer's set, each tool a held item fitted to it

const L: int = ChopModel.SIDE_LEFT
const R: int = ChopModel.SIDE_RIGHT


func run() -> void:
	_run_content()
	_run_trunk()
	_run_golden()
	_run_skill_goldens()
	_run_chops()
	_run_perfect_and_replay()
	_run_looks()
	_run_registry()
	await _run_minigame()
	await _run_chain_minigames()
	await _run_lab()
	await _run_recipe_bench()
	_run_combat()


## Combat's client side, with no server: kits, the combo's steps, the stance, the keys, the skill bar.
func _run_combat() -> void:
	print("== regents: combat ==")
	var sword: KitDef = KitDef.by_key(&"sword")
	var axe: KitDef = KitDef.by_key(&"axe")
	_check(sword != null and axe != null and sword.validate().is_empty() and axe.validate().is_empty(), "the sword and axe kits, valid")
	_check(sword.light.size() == 3 and sword.heavy != null and sword.skills.size() == 1 and sword.rank_for(0) == 1 and sword.rank_for(1) == 3,
		"the sword: a three-swing combo, a heavy, Lunge on Q at rank 1 (E would be 3)")
	for a: AbilityDef in sword.light + axe.light + [sword.heavy, axe.heavy]:
		_check(a.judged and a.reach_m > 1.0 and a.wind_up_ms >= AbilityDef.MIN_WIND_UP_MS and a.key == &"regents.combat",
			"%s: judged by the referee along the body's facing, reaching %.1f m, on the combat component's keys" % [a.display_name, a.reach_m])
	var iron_sword: ItemDef = ItemDef.by_id(40019)
	_check(iron_sword.weapon_kit == &"sword" and iron_sword.held_scene != null and ItemDef.by_id(40001).weapon_kit == &"axe",
		"the iron sword fights as a sword; the bronze axe is a weapon too")
	var bad: ItemDef = iron_sword.duplicate() as ItemDef
	bad.max_stack = 5
	_check(bad.validate().any(func(e: String) -> bool: return e.contains("weapon does not stack")), "a stacking weapon is refused")
	var dummy: EntityDefinition = load("res://game/regents/content/character/dummy.tres") as EntityDefinition
	# No blocker: a referee drives the dummy (its stand-still brain makes it someone to hit), and a body the
	# referee simulates with a blocker of its own is pushed away by it (found 2026-10-19; a template fix).
	_check(dummy.kind == 102 and dummy.visual_scene != null and dummy.blocker_size == Vector3.ZERO, "the training dummy: kind 102, its model, no blocker")
	var c: CombatComponent = CombatComponent.new()
	_check(not c.in_stance() and c.next_light_step(0) == -1, "nothing wielded: no stance, no swing")
	c.kit = sword
	var now: int = 100000
	_check(c.next_light_step(now) == 0, "the first tap: the combo's first swing")
	c.combo_step = 0
	c.combo_ms = now - 300
	_check(c.next_light_step(now) == 1, "inside the window: the second")
	c.combo_step = 2
	_check(c.next_light_step(now) == 0, "after the third: the first again")
	c.combo_step = 0
	c.combo_ms = now - sword.combo_window_ms - 1
	_check(c.next_light_step(now) == 0, "too late: the combo starts over")
	_check(not c.in_stance(), "a weapon, no target, no swing: no stance (Q and E work stations)")
	c.target_id = 7
	_check(c.in_stance(), "a target picked: in stance (Q E R F are skills)")
	c.weapon = iron_sword
	var bar: String = RegentsHud.skill_bar(c, null)
	_check(bar.contains("Iron sword") and bar.contains("LMB Slash") and bar.contains("Q Lunge") and bar.contains("RMB block"), "the skill bar: %s" % bar)
	c.free()
	CombatComponent.bind_keys()
	var ctrl_dodges: bool = false
	for e: InputEvent in InputMap.action_get_events(&"dash"):
		ctrl_dodges = ctrl_dodges or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_CTRL)
	var slow_ctrl: bool = false
	for e: InputEvent in InputMap.action_get_events(&"move_slow"):
		slow_ctrl = slow_ctrl or (e is InputEventKey and ((e as InputEventKey).physical_keycode == KEY_CTRL or (e as InputEventKey).keycode == KEY_CTRL))
	var dash_q: bool = false
	for e: InputEvent in InputMap.action_get_events(&"dash"):
		dash_q = dash_q or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q)
	_check(ctrl_dodges and not slow_ctrl and not dash_q, "Ctrl rolls (the foundation's dash), not Q (a skill here); slow-walk is on Alt")
	_run_swing_timeline()
	_run_foes()


## The swing's timeline on the client (owner, 2026-10-19: animation-locked, a buffer, committed, cancels).
## THE FIRST ENEMIES (owner, 2026-10-19): the skeleton camp's content holds together.
func _run_foes() -> void:
	print("== regents: foes ==")
	var foes: Array[FoeDef] = FoeDef.all()
	_check(foes.size() == 2, "two foes: %s" % ", ".join(foes.map(func(f: FoeDef) -> String: return String(f.key))))
	var genre: Resource = load("res://game/regents/genre.tres")
	var defs: Array = genre.get(&"entity_definitions") as Array
	for f: FoeDef in foes:
		_check(f.validate().is_empty(), "%s is valid content: %s" % [f.display_name, str(f.validate())])
		_check(defs.has(f.character), "%s's character is the genre's, so a client can draw it" % f.display_name)
		_check(f.character.brain == &"regents/foe" and f.character.animation_set != null and f.character.visual_scene != null,
			"%s has the foe brain, the adventurer's animations and its Bestiary model" % f.display_name)
		for a: AbilityDef in f.kit.abilities():
			_check(f.character.animation_set.has_exact(StringName("ability.%d" % a.id)), "%s plays its %s" % [f.display_name, a.display_name])
	_check(FoeDef.by_kind(103) != null and FoeDef.by_kind(103).kit.key == &"sword" and FoeDef.by_kind(104).kit.key == &"axe",
		"the warrior fights with the sword kit, the axeman with the axe kit (the weapons their models carry)")
	var bad := FoeDef.new()
	bad.loot.append(null)
	_check(bad.validate().size() >= 3, "a foe with no key, character, kit or whole loot is refused: %s" % str(bad.validate()))


func _run_swing_timeline() -> void:
	var axe: KitDef = KitDef.by_key(&"axe")
	var aset: AnimationSet = axe.timing_set
	for a: AbilityDef in axe.abilities():
		var sem: StringName = StringName("ability.%d" % a.id)
		var clip_ms: int = roundi(AnimationTreeBuilder.clip_length(aset, sem) / aset.clip(sem).speed_scale * 1000.0)
		_check(axe.lock_ms(a) == maxi(clip_ms, a.wind_up_ms + KitDef.MIN_RECOVERY_MS) and axe.lock_ms(a) > a.wind_up_ms,
			"%s locks for its clip's length (%d ms), past its wind-up (%d)" % [a.display_name, axe.lock_ms(a), a.wind_up_ms])
		_check(a.cooldown_ms <= axe.lock_ms(a) or axe.skills.has(a), "%s: its cooldown (%d) never outlasts its lock: a queued swing is never refused for it" % [a.display_name, a.cooldown_ms])
	var c: CombatComponent = CombatComponent.new()
	c.kit = axe
	var chop: AbilityDef = axe.light[0]
	c.swing_ability = chop
	c.swing_at_ms = 0
	c.swing_hit_ms = chop.wind_up_ms
	c.swing_lock_ms = axe.lock_ms(chop)
	c.combo_step = 0
	_check(c.swinging(10) and not c.may_start(axe.heavy, -1, 300), "a chop just begun holds you: no heavy 300 ms in")
	_check(c.may_start(axe.heavy, -1, axe.lock_ms(chop)), "free when its clip ends (%d ms)" % axe.lock_ms(chop))
	_check(not c.may_start(axe.light[1], 1, chop.wind_up_ms), "the combo's second waits for the first to land")
	_check(c.may_start(axe.light[1], 1, chop.wind_up_ms + axe.chain_ms), "and chains just after it lands (%d ms)" % (chop.wind_up_ms + axe.chain_ms))
	c.swing_cancelled = true
	_check(not c.swinging(10) and c.may_start(axe.heavy, -1, 10), "a swing a roll cancelled holds nothing")
	c.free()
	var adv: PackedScene = load("res://game/regents/adventurer.tscn") as PackedScene
	var body: Node = adv.instantiate()
	var drv: AnimationDriverComponent = body.get_node_or_null(^"Components/Animation") as AnimationDriverComponent
	var cfg: MovementConfig = MovementConfig.shared()
	_check(drv != null and drv.action_cancel_speed > cfg.walk_speed and drv.action_cancel_speed < cfg.run_speed,
		"a committed swing walks (%.1f m/s) under the speed that cuts it (%.1f); running (%.1f) cuts its recovery" % [cfg.walk_speed, drv.action_cancel_speed if drv != null else 0.0, cfg.run_speed])
	body.free()
	var swinging_status: StatusDef = load("res://game/regents/content/status/swinging.tres") as StatusDef
	var adv_cfg: MovementConfig = (load("res://game/regents/content/movement/adventurer.tres") as MovementProfileDef).apply_to(cfg)
	var in_swing: MovementConfig = swinging_status.apply_to(adv_cfg)
	_check(in_swing.run_speed >= adv_cfg.walk_speed and in_swing.run_speed < adv_cfg.walk_speed * 1.1 and not swinging_status.can_sprint,
		"the server's Swinging bound (%.2f m/s) lets the committed walk (%.1f) through, and no faster" % [in_swing.run_speed, adv_cfg.walk_speed])
	_check(swinging_status.can_dash and in_swing.dash_impulse > 0.0 and is_equal_approx(in_swing.dash_impulse, adv_cfg.dash_impulse),
		"and leaves the roll whole (a dash of %.0f in a swing, as out of one: DECISIONS #256)" % in_swing.dash_impulse)
	var adv_set: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	_check(adv_set.root_motion_bone == &"root", "the swings play in place: their root travel is taken out (%s)" % adv_set.root_motion_bone)


## The recipe bench: a recipe's numbers worked out from the content and the hot rules' defaults.
func _run_recipe_bench() -> void:
	print("== regents: the recipe bench ==")
	var bar: RecipeDef = RecipeDef.by_id(40001)
	_check(bar.workbench_scene() == "res://game/regents/workbench/recipe_workbench.tscn", "a recipe has its bench (%s)" % bar.workbench_scene())
	var bench: RecipeWorkbench = (load(bar.workbench_scene()) as PackedScene).instantiate() as RecipeWorkbench
	add_child(bench)
	bench.item = bar
	await get_tree().process_frame
	var share: int = int(RecipeWorkbench.rule(&"craft_work_share_pct"))
	_check(share == 60 and RecipeWorkbench.batch_xp(bar) == bar.craft_xp(share), "it reads the hot rules' defaults (a %d %% share)" % share)
	var sheet: String = await bench.run_named_test(&"sheet")
	_check(sheet.contains("2 Copper ore") and sheet.contains("1 Copper bar") and sheet.contains("XP a batch: %d" % RecipeWorkbench.batch_xp(bar)), "the sheet: %s" % sheet)
	await bench.run_named_test(&"per_hour")
	var afk: Dictionary = bench.last_measure.get("afk", {})
	_check(int(afk.get("batches", 0)) == 3_600_000 / bar.afk_ms and int((afk.get("eats", {}) as Dictionary).get("Copper ore", 0)) == 2 * int(afk.get("batches", 0)),
		"an hour AFK: %d bars, eating twice as much ore" % int(afk.get("batches", 0)))
	_check(int(afk.get("xp_hour", 0)) < int(afk.get("xp_fresh", 0)) and int(afk.get("xp_hour", 0)) > int(afk.get("xp_fresh", 0)) / 2,
		"an hour of one recipe wears stale: %d XP, not %d" % [int(afk.get("xp_hour", 0)), int(afk.get("xp_fresh", 0))])
	await bench.run_named_test(&"chain")
	var raw: Dictionary = bench.last_measure.get("raw", {})
	_check(is_equal_approx(float(raw.get("Copper ore", 0.0)), 2.0) and float(bench.last_measure.get("minutes", 0.0)) > 0.0, "a bar's chain: two copper ore")
	var axe: RecipeDef = RecipeDef.by_id(40006)
	bench.item = axe
	await get_tree().process_frame
	await bench.run_named_test(&"chain")
	var axe_raw: Dictionary = bench.last_measure.get("raw", {})
	_check(axe_raw.has("Iron ore") and axe_raw.has("Copper ore") and axe_raw.has("Logs"), "the axe's chain goes back to iron ore, copper ore and logs: %s" % str(axe_raw))
	bench.item = bar
	_check((await bench.run_named_test(&"against")).contains("gathering Copper ore"), "against gathering: %s" % bench.last_result)
	bench.queue_free()
	await get_tree().process_frame


func _params(permille: int = 450) -> ChopParams:
	var p: ChopParams = ChopParams.new()
	p.duration_ms = 10000
	p.swing_ms = 300
	p.stagger_ms = 800
	p.branch_permille = permille
	p.safe_segments = 2
	p.target_chops = 22
	return p


## A model on `p` whose trunk is `trunk` (bottom first), padded with bare pieces.
func _model_with(p: ChopParams, trunk: Array[int]) -> ChopModel:
	var m: ChopModel = ChopModel.start(1, p)
	var segs: PackedInt32Array = m.segments
	for i: int in segs.size():
		segs[i] = trunk[i] if i < trunk.size() else ChopModel.BRANCH_NONE
	m.segments = segs
	return m


## The chain's content: valid, linked as the chain needs, the gathering tiers in order.
func _run_content() -> void:
	print("== regents: the chain's content ==")
	var bad: Array[String] = []
	for type: StringName in [&"skill", &"node", &"recipe", &"station", &"item"]:
		for d: ContentDef in ContentLibrary.items(type):
			if not d.validate().is_empty():
				bad.append("%s %s: %s" % [type, d.display_name, str(d.validate())])
	_check(bad.is_empty(), "every skill, node, recipe, station and item is valid%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))
	var keys: Array[StringName] = []
	for sk: SkillDef in SkillDef.all():
		keys.append(sk.key)
	_check(keys == [&"woodcutting", &"mining", &"smelting", &"smithing", &"crafting", &"swordsmanship", &"axemanship"],
		"five working skills and two weapon masteries: %s" % str(keys))
	var wc: SkillDef = SkillDef.by_key(&"woodcutting")
	_check(wc.rank_of(0) == 1 and wc.rank_of(59) == 1 and wc.rank_of(60) == 2 and wc.rank_of(280) == 4 and wc.progress(100) == Vector2i(40, 90),
		"ranks come from the curve: rank 2 at 60 XP, 4 at 280; 100 XP is 40 of rank 3's 90")
	var names: Array[String] = []
	for n: NodeDef in NodeDef.all_by_tier():
		names.append(n.display_name)
	_check(names == ["Tree", "Oak", "Yew", "Copper rock", "Iron rock"], "five nodes, by skill then tier: %s" % str(names))
	var prev: ChopParams = null
	for n: NodeDef in NodeDef.all_by_tier():
		if not (n.minigame is ChopParams):
			continue
		var t: ChopParams = n.minigame as ChopParams
		_check(t.target_chops <= ChopModel.max_chops(t), "%s: a full score is reachable (%d of at most %d)" % [n.display_name, t.target_chops, ChopModel.max_chops(t)])
		if prev != null:
			_check(t.branch_permille > prev.branch_permille and t.target_chops > prev.target_chops, "%s is a harder round than the tier below" % n.display_name)
		prev = t
	var yew: NodeDef = NodeDef.by_id(40003)
	_check(yew.min_tool_tier == 2 and yew.min_rank == 4, "a yew needs a tier 2 axe and woodcutting rank 4")
	# The chain, by what each recipe takes and makes.
	var made: Dictionary[String, Array] = {}
	for r: RecipeDef in RecipeDef.all():
		var ins: Array[String] = []
		for i: ItemDef in r.inputs:
			ins.append(i.display_name)
		made[r.output.display_name] = [String(r.station), ins]
	_check(made.get("Copper bar", []) == ["furnace", ["Copper ore"]] and made.get("Iron bar", []) == ["furnace", ["Iron ore"]],
		"the furnace: ore into bars")
	_check(made.get("Iron axe head", []) == ["anvil", ["Iron bar"]] and made.get("Copper rivets", []) == ["anvil", ["Copper bar"]], "the anvil: bars into a head, rivets")
	_check(made.get("Handle", []) == ["workbench", ["Logs"]] and made.get("Iron axe", []) == ["workbench", ["Iron axe head", "Handle", "Copper rivets"]],
		"the workbench: logs into a handle; a head, a handle and rivets into an iron axe")
	var head: RecipeDef = RecipeDef.by_id(40004)
	var axe: RecipeDef = RecipeDef.by_id(40006)
	_check(head.quality == RecipeDef.Quality.FROM_ROUND and head.minigame is ShapeParams and axe.quality == RecipeDef.Quality.FROM_INPUTS and axe.minigame == null,
		"the head is shaped (as good as its round); the axe is assembled (as good as its head)")
	_check(RecipeDef.at(&"furnace").size() == 2 and RecipeDef.at(&"anvil").size() == 3 and RecipeDef.at(&"workbench").size() == 5 and RecipeDef.at(&"orders").is_empty(),
		"two recipes at the furnace, three at the anvil (rivets, the axe head, the sword blade), five at the workbench (three handles, the axe, the sword), none at the order board")
	_check(made.get("Oak handle", []) == ["workbench", ["Oak logs"]] and made.get("Yew handle", []) == ["workbench", ["Yew logs"]],
		"oak and yew logs carve into their handles")
	_check(RecipeDef.by_id(40001).input_qty[0] == 2 and RecipeDef.by_id(40002).input_qty[0] == 2, "two ores to a bar, never one to one")
	var choices: Array[String] = []
	for it: ItemDef in axe.part_choices():
		choices.append(it.display_name)
	_check(axe.part_slot == 1 and choices == ["Handle", "Oak handle", "Yew handle"], "the iron axe's handle slot takes any handle, plain first: %s" % str(choices))
	_check(RecipeDef.by_id(40001).part_choices().is_empty(), "a recipe with no part slot has no choices")
	var oak_h: ItemDef = ItemDef.by_id(40016)
	var yew_h: ItemDef = ItemDef.by_id(40017)
	_check(oak_h.handle_trait() == "+15 quality" and yew_h.handle_trait() == "10% faster swing" and ItemDef.by_id(40013).handle_trait() == "",
		"the handles' traits, in words: %s / %s" % [oak_h.handle_trait(), yew_h.handle_trait()])
	var bar: RecipeDef = RecipeDef.by_id(40001)
	var ore_xp: int = (NodeDef.by_id(40004)).xp
	_check(RecipeDef.work_xp(bar.inputs[0]) == ore_xp and bar.craft_xp(100) == bar.xp + 2 * ore_xp and bar.craft_xp(0) == bar.xp,
		"craft XP pays for the work in the inputs (the server's numbers: genre::regents::craft_xp)")
	var bad_part: RecipeDef = axe.duplicate() as RecipeDef
	bad_part.part_slot = 0
	_check(bad_part.validate().any(func(e: String) -> bool: return e.contains("no part")), "a part slot on an item that is no part is refused")
	for key: StringName in [&"furnace", &"anvil", &"workbench"]:
		_check(StationDef.by_key(key) != null, "the %s is a station" % key)
	var iron: ItemDef = ItemDef.by_id(40015)
	_check(iron.tool_tag == &"axe" and iron.tool_tier == 2 and iron.tool_speed_pct == 85 and iron.held_scene != null, "the iron axe: tier 2, 85 % of the time, held as its own")


func _run_trunk() -> void:
	print("== regents: the trunk from a seed ==")
	# The challenge's own generator (pinned against Rust by shared/golden/challenge), so the twin agrees.
	var same_gen: bool = true
	for x: int in [1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 123456789]:
		same_gen = same_gen and ChopModel._next_u32(x) == ChallengeModel._next_u32(x)
	for s: int in [0, 1, -1, 0x1234567890ABCDEF, -0x7000000000000000]:
		same_gen = same_gen and ChopModel._seed_state(s) == ChallengeModel._seed_state(s)
	_check(same_gen, "the trunk's generator and seed fold are the challenge's (xorshift32), high bits included")
	var p: ChopParams = _params()
	var a: PackedInt32Array = ChopModel.branches(42, p, 200)
	_check(a == ChopModel.branches(42, p, 200), "a seed makes the same trunk every time")
	_check(ChopModel.branches(42, p, 20) == a.slice(0, 20), "and its bottom does not depend on how much is made")
	_check(a != ChopModel.branches(43, p, 200), "another seed, another trunk")
	_check(a[0] == ChopModel.BRANCH_NONE and a[1] == ChopModel.BRANCH_NONE, "the bottom pieces are safe (safe_segments 2)")
	var n: int = 20000
	var big: PackedInt32Array = ChopModel.branches(7, p, n)
	var left: int = big.count(ChopModel.BRANCH_LEFT)
	var right: int = big.count(ChopModel.BRANCH_RIGHT)
	var rate: float = float(left + right) / float(n - 2)
	_check(rate > 0.43 and rate < 0.47, "45 %% of pieces carry a branch (%.3f over %d)" % [rate, n])
	_check(absf(float(left) / float(left + right) - 0.5) < 0.03, "left and right alike (%d / %d)" % [left, right])
	_check(ChopModel.branches(7, _params(0), 500).count(ChopModel.BRANCH_NONE) == 500, "0 ‰: no branches")
	_check(ChopModel.branches(7, _params(1000), 500).count(ChopModel.BRANCH_NONE) == 2, "1000 ‰: every piece above the safe ones")


## The golden rounds (made by a third, Python version: `game/regents/tests/make_chop_golden.py`), which the
## server's Rust twin is held to as well (`server/tests/regents.rs`).
func _run_golden() -> void:
	print("== regents: the golden rounds ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/regents/chop.json", FileAccess.READ)
	_check(f != null, "shared/golden/regents/chop.json is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var cases: Array = doc.get("cases", []) as Array
	_check(cases.size() >= 10, "it has its cases (%d)" % cases.size())
	var bad: Array[String] = []
	for c: Dictionary in cases:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var pp: Dictionary = c["params"]
		var p: ChopParams = ChopParams.new()
		p.duration_ms = int(pp["duration_ms"])
		p.swing_ms = int(pp["swing_ms"])
		p.stagger_ms = int(pp["stagger_ms"])
		p.branch_permille = int(pp["branch_permille"])
		p.safe_segments = int(pp["safe_segments"])
		p.target_chops = int(pp["target_chops"])
		var want_seg: PackedInt32Array = PackedInt32Array()
		for v: Variant in c["segments"]:
			want_seg.append(int(v))
		var inputs: PackedInt32Array = PackedInt32Array()
		for pair: Array in c["inputs"]:
			inputs.append(int(pair[0]))
			inputs.append(int(pair[1]))
		var e: Dictionary = c["expected"]
		var want: Dictionary = {"clean": int(e["clean"]), "hits": int(e["hits"]), "best_combo": int(e["best_combo"]), "score_pm": int(e["score_pm"])}
		var got: Dictionary = ChopModel.play(seed_value, p, inputs)
		if ChopModel.branches(seed_value, p, want_seg.size()) != want_seg or got != want:
			bad.append("%s: %s, wanted %s" % [c["name"], str(got), str(want)])
	_check(bad.is_empty(), "the GDScript twin plays every golden round exactly%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))


## A params resource from a golden case's numbers (an outline becomes a PackedInt32Array).
func _params_from(res: Resource, pp: Dictionary) -> Resource:
	for key: String in pp:
		var v: Variant = pp[key]
		if v is Array:
			var arr: PackedInt32Array = PackedInt32Array()
			for x: Variant in v:
				arr.append(int(x))
			res.set(key, arr)
		else:
			res.set(key, int(v))
	return res


func _golden_cases(name: String) -> Array:
	var f: FileAccess = FileAccess.open("res://shared/golden/regents/%s.json" % name, FileAccess.READ)
	if f == null:
		_check(false, "shared/golden/regents/%s.json is there" % name)
		return []
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	return doc.get("cases", []) as Array


## The flat inputs of a golden case (rows of 2 or 3).
func _flat(rows: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: Array in rows:
		for v: Variant in r:
			out.append(int(v))
	return out


func _ints(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in d:
		out[k] = int(d[k])
	return out


## Crack the rock, bellows then pour, shape to the outline: the GDScript models against the golden files a
## third (Python) version made, which their Rust twins are held to as well.
func _run_skill_goldens() -> void:
	print("== regents: the chain's golden rounds ==")
	var bad: Array[String] = []
	var crack: Array = _golden_cases("crack")
	for c: Dictionary in crack:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: CrackParams = _params_from(CrackParams.new(), c["params"]) as CrackParams
		var pts: PackedInt32Array = CrackModel.seams(seed_value, p, 3)
		var got: Dictionary = CrackModel.play(seed_value, p, _flat(c["inputs"]))
		if pts != _flat([c["points"]]) or got != _ints(c["expected"]):
			bad.append("crack %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	var smelt: Array = _golden_cases("smelt")
	for c: Dictionary in smelt:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: SmeltParams = _params_from(SmeltParams.new(), c["params"]) as SmeltParams
		var m: SmeltModel = SmeltModel.start(seed_value, p)
		var bands_ok: bool = true
		var i: int = 0
		for b: Array in c["bands"]:
			bands_ok = bands_ok and m.band(i * 7) == Vector2i(int(b[0]), int(b[1]))
			i += 1
		var got: Dictionary = SmeltModel.play(seed_value, p, _flat(c["inputs"]))
		if not bands_ok or got != _ints(c["expected"]):
			bad.append("smelt %s: %s, wanted %s (bands %s)" % [c["name"], str(got), str(c["expected"]), bands_ok])
	var shape: Array = _golden_cases("shape")
	for c: Dictionary in shape:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: ShapeParams = _params_from(ShapeParams.new(), c["params"]) as ShapeParams
		var start: PackedInt32Array = ShapeModel.start(seed_value, p).heights
		var got: Dictionary = ShapeModel.play(seed_value, p, _flat(c["inputs"]))
		if start != _flat([c["start"]]) or got != _ints(c["expected"]):
			bad.append("shape %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	_check(crack.size() >= 6 and smelt.size() >= 6 and shape.size() >= 6 and bad.is_empty(),
		"the GDScript models play every golden round exactly (%d crack, %d smelt, %d shape)%s" % [crack.size(), smelt.size(), shape.size(),
			"" if bad.is_empty() else ": " + "; ".join(bad)])


func _run_chops() -> void:
	print("== regents: chopping ==")
	var p: ChopParams = _params()
	var m: ChopModel = _model_with(p, [0, L, 0, R])
	_check(m.head_branch() == L, "the branch at your head is the piece above the cut")
	_check(m.chop(0, L) == ChopModel.HIT and m.cut == 0 and m.hits == 1 and m.combo == 0, "chopping from the branch's side: hit, the trunk does not drop")
	_check(m.chop(799, R) == ChopModel.IGNORED and m.cut == 0, "staggered: a swing 799 ms after the hit is not swung")
	_check(m.chop(800, R) == ChopModel.CLEAN and m.cut == 1 and m.clean == 1, "at 800 ms (stagger_ms), from the other side: clean, the trunk drops")
	_check(m.head_branch() == ChopModel.BRANCH_NONE and m.chop(1099, R) == ChopModel.HELD and m.cut == 1, "mid-swing (299 ms after a chop): held, not dropped")
	_check(m.settle(1099) == ChopModel.IGNORED and m.settle(1100) == ChopModel.CLEAN and m.cut == 2 and m.head_branch() == R,
		"it swings the moment the swing ends (1100): clean, and the next branch is on your side")
	_check(m.chop(1400, R) == ChopModel.HIT and m.chop(2200, L) == ChopModel.CLEAN, "stay under it and it hits; step across and chop")
	_check(m.best_combo == 2 and m.combo == 1, "a hit ends a combo (best 2, now 1)")
	var q: ChopModel = _model_with(p, [])
	_check(q.chop(0, L) == ChopModel.CLEAN and q.chop(100, L) == ChopModel.HELD and q.chop(200, R) == ChopModel.HELD
		and q.chop(300, R) == ChopModel.HELD and q.side == R and q.clean == 2, "quick side switches: the latest held press swings when the swing ends")
	var e: ChopModel = _model_with(p, [])
	e.chop(9800, L)
	_check(e.chop(9900, R) == ChopModel.HELD and ChopModel.play(1, p, PackedInt32Array([9800, L, 9900, R]))["clean"] == 1,
		"a press held past the round's end never swings")
	var o: ChopModel = _model_with(p, [])
	_check(o.chop(-1, L) == ChopModel.IGNORED and o.chop(0, 0) == ChopModel.IGNORED and o.chop(0, 3) == ChopModel.IGNORED,
		"before the round, or no side: nothing")
	_check(o.chop(500, L) == ChopModel.CLEAN and o.chop(400, L) == ChopModel.IGNORED and o.chop(900, L) == ChopModel.CLEAN,
		"a press earlier than the last one is out of order: nothing")
	_check(o.chop(10000, R) == ChopModel.CLEAN and o.chop(10001, R) == ChopModel.IGNORED and o.clean == 3,
		"the round's last millisecond counts; after it, nothing")
	o.clean = 11
	_check(o.score_pm() == 500, "11 of a 22-log target scores half (%d)" % o.score_pm())
	o.clean = 40
	_check(o.score_pm() == 1000, "more than the target scores no more")


## A player who never misses: a swing every `swing_ms` from the side the next branch is not on.
func _perfect_inputs(seed_value: int, p: ChopParams) -> PackedInt32Array:
	var m: ChopModel = ChopModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		var side: int = R if m.head_branch() == L else (L if m.head_branch() == R else m.side)
		out.append_array(PackedInt32Array([t, side]))
		m.chop(t, side)
		t += p.swing_ms
	return out


func _run_perfect_and_replay() -> void:
	print("== regents: a perfect round, and a replay ==")
	for n: NodeDef in NodeDef.all_by_tier():
		if not (n.minigame is ChopParams):
			continue
		var t: ChopParams = n.minigame as ChopParams
		var r: Dictionary = ChopModel.play(99, t, _perfect_inputs(99, t))
		_check(r["hits"] == 0 and r["clean"] == ChopModel.max_chops(t) and r["score_pm"] == 1000,
			"%s: never under a branch, every swing on time: %d logs, no hits, a full score" % [n.display_name, r["clean"]])
	# Pressing blind (always left) on a branchy tree: hit, staggered, far short.
	var p: ChopParams = _params(600)
	var blind: PackedInt32Array = PackedInt32Array()
	for k: int in 34:
		blind.append_array(PackedInt32Array([k * 300, L]))
	var b: Dictionary = ChopModel.play(5, p, blind)
	_check(b["hits"] > 0 and b["score_pm"] < 1000, "always the left on a branchy tree: hit %d times, scores %d ‰" % [b["hits"], b["score_pm"]])
	# The replay is the inputs': change one side and a different round is scored.
	var perfect: PackedInt32Array = _perfect_inputs(5, p)
	var m: ChopModel = ChopModel.start(5, p)
	var flip: int = -1
	var i: int = 0
	while i + 1 < perfect.size():
		if m.head_branch() != ChopModel.BRANCH_NONE:
			flip = i
			break
		m.chop(perfect[i], perfect[i + 1])
		i += 2
	var tampered: PackedInt32Array = perfect.duplicate()
	tampered[flip + 1] = m.head_branch()
	var pr: Dictionary = ChopModel.play(5, p, perfect)
	var tr: Dictionary = ChopModel.play(5, p, tampered)
	# The stagger puts every later swing off the perfect player's timing, so the hits go on from there.
	_check(flip >= 0 and pr["hits"] == 0 and int(tr["hits"]) >= 1 and tr["clean"] < pr["clean"],
		"one swing moved under a branch: the replay scores the hit and what it cost (%s vs %s)" % [str(tr), str(pr)])


## Working, shown: each skill's pose in the adventurer's set (UAL clips), each tool a held item fitted to its
## skill's pose, and the adventurer carries the skilling and the look of it.
func _run_looks() -> void:
	print("== regents: working, shown ==")
	var adv: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	var aset: AnimationSet = adv.animation_set if adv != null else null
	var clips: Dictionary[StringName, StringName] = {&"pose.chop": &"extra/TreeChopping", &"pose.mine": &"extra/Mining", &"pose.smith": &"extra/Mining",
		&"pose.smelt": &"Push", &"pose.craft": &"Interact"}
	for pose: StringName in clips:
		var ref: AnimationClipRef = aset.clip(pose) if aset != null and aset.has_exact(pose) else null
		_check(ref != null and ref.anim_name == clips[pose] and ref.loop, "the set's %s is %s, looping" % [pose, clips[pose]])
	_check(aset != null and aset.missing_required().is_empty(), "the set still drives a tree (nothing required missing)")
	for sk: SkillDef in SkillDef.all():
		if KitDef.all().any(func(k: KitDef) -> bool: return k.skill == sk):
			continue   # a weapon mastery: trained by fighting, no working pose
		_check(aset.has_exact(sk.pose), "%s works in the set's %s" % [sk.display_name, sk.pose])
	for k: KitDef in KitDef.all():
		var abilities: Array[AbilityDef] = []
		abilities.assign(k.light + k.skills)
		abilities.append(k.heavy)
		for a: AbilityDef in abilities:
			# The driver plays an ability as `ability.<id>` (anything else falls back to Interact: owner, 2026-10-19).
			_check(a.animation == StringName("ability.%d" % a.id) and aset.has_exact(a.animation) and aset.clip(a.animation).anim_name != aset.clip(&"interact").anim_name,
				"the %s kit's %s plays the set's ability.%d, its own clip (%s)" % [k.key, a.display_name, a.id, aset.clip(a.animation).anim_name if aset.has_exact(a.animation) else "none"])
	_check(aset.has_exact(&"ability.40010") and aset.clip(&"ability.40010").anim_name == &"Roll" and aset.has_exact(&"pose.block"), "the roll plays Roll; the block is in the set")
	var tools: Dictionary[String, StringName] = {"res://game/regents/skilling/woodcutting/axe.tscn": &"pose.chop",
		"res://game/regents/skilling/woodcutting/iron_axe.tscn": &"pose.chop", "res://game/regents/skilling/mining/pickaxe.tscn": &"pose.mine",
		"res://game/regents/skilling/smithing/hammer.tscn": &"pose.smith"}
	for path: String in tools:
		var node: Node = (load(path) as PackedScene).instantiate()
		var held: HeldItem = node as HeldItem
		var fitted: bool = false
		if held != null and held.grip != null:
			# Its own grip for the working pose, or one grip for all it uses there (the owner's way since #259).
			fitted = held.grip.universal and held.grip.resolve(tools[path]) != null
			for e: GripEntry in held.grip.entries:
				fitted = fitted or e.animation == tools[path]
		_check(held != null and held.grip.hand == &"hand_r" and fitted, "%s is a held item, held in %s (its own grip there, or its one grip for all)" % [path.get_file(), tools[path]])
		node.free()
	_check(ItemDef.by_id(40001).held_scene != null and ItemDef.by_id(40006).held_scene != null and SkillDef.by_key(&"smithing").tool_scene != null,
		"the bronze axe and pickaxe show as themselves; the smith holds a hammer")
	var player: Node = (load("res://game/regents/adventurer.tscn") as PackedScene).instantiate()
	_check(player.get_node_or_null(^"Components/SkillingLook") is SkillingLook and player.get_node_or_null(^"Components/Skilling") is SkillingComponent,
		"the adventurer carries its skilling and the look of it")
	player.free()


## The minigames in one place: their kinds, the server's challenge kinds, a faster tool's swing.
func _run_registry() -> void:
	print("== regents: the minigames' registry ==")
	_check(SkillMinigames.CHALLENGE == {&"chop": 100, &"crack": 101, &"smelt": 102, &"shape": 103}, "the challenge kinds the server deals them as")
	var chop: ChopParams = _params()
	var fast: ChopParams = SkillMinigames.with_speed(chop, 85) as ChopParams
	_check(fast != chop and fast.swing_ms == 255 and chop.swing_ms == 300, "a tool at 85 %% swings in 255 ms, and the content is left as it was")
	_check(SkillMinigames.with_speed(chop, 100) == chop and SkillMinigames.with_speed(SmeltParams.new(), 50) is SmeltParams,
		"as authored at 100 %%; a station round has no swing to speed")
	_check(SkillMinigames.arity(SkillMinigames.CRACK) == 3 and SkillMinigames.arity(SkillMinigames.SHAPE) == 2, "a strike on the rock is (time, x, y)")
	var baked: Dictionary = SkillMinigames.bake((RecipeDef.by_id(40004)).minigame)
	_check(baked.get("kind", "") == "shape" and (baked.get("outline", []) as Array).size() == 16 and not baked.has("display_name"),
		"a round bakes as its kind and its numbers")


func _run_minigame() -> void:
	print("== regents: the minigame ==")
	var g: ChopMinigame = ChopMinigame.new()
	g.size = Vector2(1280, 720)
	add_child(g)
	var p: ChopParams = _params(500)
	var seen: Array[Dictionary] = []
	g.round_finished.connect(func(live: Dictionary, replayed: Dictionary) -> void:
		seen.append(live)
		seen.append(replayed))
	_check(g.press_at(0, L) == ChopModel.IGNORED and g.inputs.is_empty(), "before a round, a press is nothing and is not kept")
	g.begin(77, p)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var t: int = -50
	var events: Dictionary = {}
	var sides: Array[int] = [L, R, L, R, 0]
	for k: int in 120:
		var side: int = sides[rng.randi_range(0, 4)]
		var ev: int = g.press_at(t, side)
		events[ev] = int(events.get(ev, 0)) + 1
		t += rng.randi_range(-40, 220)
	_check(g.inputs.size() == 240, "every press is kept, the ignored ones too (%d values)" % g.inputs.size())
	_check(events.has(ChopModel.CLEAN) and events.has(ChopModel.HIT) and events.has(ChopModel.IGNORED),
		"a messy player chops, gets hit, and swings when it cannot (%s)" % str(events))
	await get_tree().process_frame
	g.finish()
	_check(seen.size() == 2 and seen[0] == seen[1] and seen[0] == ChopModel.play(77, p, g.inputs),
		"the round's end: what was played is what a replay of its inputs scores (%s)" % (str(seen[0]) if seen.size() > 0 else "none"))
	_check(g.press_at(t, L) == ChopModel.IGNORED and g.inputs.size() == 240, "after the round, presses are nothing")
	g.queue_free()
	await get_tree().process_frame


## Crack the rock, bellows then pour, shape to the outline: played through their UIs, every input kept, and
## what was played is what a replay of the inputs scores.
func _run_chain_minigames() -> void:
	print("== regents: the chain's minigames, played ==")
	var crack: CrackMinigame = CrackMinigame.new()
	crack.size = Vector2(960, 620)
	add_child(crack)
	var rock: CrackParams = (NodeDef.by_id(40004)).minigame as CrackParams
	crack.begin(11, rock)
	var t: int = 0
	var hits: int = 0
	while t < rock.duration_ms:
		if t >= crack.model.next_ok_ms + 250:
			var g: Vector2i = crack.model.notch(crack.model.k)
			hits += int(crack.strike_at(t, g.x, g.y) == CrackModel.HIT)
		t += 10
	crack.strike_at(t, 0, 0)
	crack.finish()
	_check(hits >= 12 and crack.model.splits >= 1 and crack.live_result == crack.replayed_result and crack.inputs.size() % 3 == 0,
		"follow the seam: %d notches struck in order, %d split, every strike kept as (t, x, y), the replay agrees" % [hits, crack.model.splits])
	_check(crack.to_face(crack.from_face(Vector2i(300, 700))).distance_to(Vector2i(300, 700)) <= 1, "a click on the face is where the strike lands")
	crack.queue_free()
	# The seam's rules, one strike at a time.
	var cm: CrackModel = CrackModel.start(11, rock)
	var n0: Vector2i = cm.notch(0)
	var n1: Vector2i = cm.notch(1)
	var first: Vector2i = cm.notch(0)
	var across: bool = true
	for i: int in rock.notches - 1:
		across = across and absi(cm.notch(i + 1).x - cm.notch(i).x) <= rock.bend_pm and cm.notch(i + 1).y > cm.notch(i).y
	_check(first.y == rock.margin_pm and cm.notch(rock.notches - 1).y == 1000 - rock.margin_pm and across,
		"the first seam runs top to bottom, each notch within %d‰ across of the last" % rock.bend_pm)
	_check(cm.notch(rock.notches).x == rock.margin_pm and cm.notch(2 * rock.notches - 1).x == 1000 - rock.margin_pm,
		"the second runs left to right")
	_check(cm.strike(0, n1.x, n1.y) == CrackModel.JAR and cm.jars == 1, "a notch out of order is off the seam: the pick jars")
	_check(cm.strike(100, n0.x, n0.y) == CrackModel.IGNORED and cm.k == 0, "staggered: a strike then is lost")
	_check(cm.strike(rock.stagger_ms, n0.x + rock.radius_pm, n0.y) == CrackModel.HIT and cm.k == 1, "the next notch, at its radius's edge: the crack opens")
	_check(cm.strike(rock.stagger_ms + 10, n1.x, n1.y) == CrackModel.HELD and cm.k == 1, "mid-swing, the next strike is held")
	_check(cm.settle(rock.stagger_ms + rock.swing_ms) == CrackModel.HIT and cm.k == 2, "and lands the moment the pick is back up")
	var full: CrackModel = CrackModel.start(11, rock)
	var tt: int = 0
	for i: int in rock.notches:
		full.strike(tt, full.notch(i).x, full.notch(i).y)
		tt += rock.swing_ms
	_check(full.splits == 1 and full.next_ok_ms == tt - rock.swing_ms + rock.split_ms, "the whole seam opened: the rock splits, and the next seam waits %d ms" % rock.split_ms)
	var smelt: SmeltMinigame = SmeltMinigame.new()
	add_child(smelt)
	var bar: SmeltParams = (RecipeDef.by_id(40001)).minigame as SmeltParams
	smelt.begin(12, bar)
	t = 0
	while t < bar.heat_ms:
		smelt.model.advance_to(t)
		if smelt.model.heat < smelt.model.band(smelt.model.tick).x:
			smelt.press_at(t, SmeltModel.PUMP)
		t += 20
	_check(smelt.press_at(bar.heat_ms + 50, SmeltModel.POUR) == SmeltModel.IGNORED and not smelt.model.pouring,
		"mashing into the pour does not tilt the crucible (%d ms to be ready)" % bar.pour_ready_ms)
	_check(smelt.press_at(bar.heat_ms + 80, SmeltModel.STOP) == SmeltModel.IGNORED, "nor does letting go stop a pour that never began")
	t = bar.heat_ms + bar.pour_ready_ms
	_check(smelt.press_at(t, SmeltModel.POUR) == SmeltModel.DONE and smelt.model.pouring, "ready: holding tilts it")
	while smelt.model.fill < smelt.model.target and t < bar.heat_ms + bar.pour_ms - 100:
		t += 10
		smelt.model.advance_to(t)
	smelt.press_at(t, SmeltModel.STOP)
	smelt.finish()
	var top: SmeltModel = SmeltModel.start(12, bar)
	var ready: int = bar.heat_ms + bar.pour_ready_ms
	top.press(ready, SmeltModel.POUR)
	top.press(ready + 500, SmeltModel.STOP)
	var fill_once: int = top.fill
	_check(fill_once == 10 * bar.pour_rate and top.press(ready + 700, SmeltModel.POUR) == SmeltModel.DONE
		and top.press(ready + 750, SmeltModel.STOP) == SmeltModel.DONE and top.fill == fill_once + bar.pour_rate,
		"a pour stops when let go; tilting again tops it up (one tick: %d)" % bar.pour_rate)
	var sr: Dictionary = smelt.live_result
	_check(int(sr["heat_pm"]) > 600 and int(sr["pour_pm"]) > 800 and smelt.live_result == smelt.replayed_result,
		"bellows then pour: a steady hand keeps the heat (%d) and pours to the line (%d), the replay agrees" % [sr["heat_pm"], sr["pour_pm"]])
	smelt.queue_free()
	var shape: ShapeMinigame = ShapeMinigame.new()
	add_child(shape)
	var part: ShapeParams = (RecipeDef.by_id(40004)).minigame as ShapeParams
	shape.begin(13, part)
	t = 0
	while t < part.duration_ms:
		if t >= shape.model.next_ok_ms:
			if shape.model.hot_until_ms - t < 400:
				shape.strike_at(t, ShapeModel.REHEAT_COLUMN)
			else:
				var best: int = 0
				for i: int in shape.model.heights.size():
					if shape.model.heights[i] - part.outline[i] > shape.model.heights[best] - part.outline[best]:
						best = i
				if shape.model.heights[best] - part.outline[best] <= 0:
					break
				shape.strike_at(t, best)
		t += 10
	shape.finish()
	_check(int(shape.live_result["score_pm"]) > 600 and shape.live_result == shape.replayed_result,
		"shape to the outline: a careful smith comes close (%d), the replay agrees" % shape.live_result["score_pm"])
	shape.queue_free()
	await get_tree().process_frame


## The skilling lab: a button per round in the content; picking one shows that minigame, ready to play.
func _run_lab() -> void:
	print("== regents: the skilling lab ==")
	var lab: Node = (load("res://game/regents/skilling/skilling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	await get_tree().process_frame
	var buttons: Array[Button] = []
	buttons.assign(lab.get("buttons"))
	var game: SkillMinigame = lab.get("game") as SkillMinigame
	_check(buttons.size() == 9 and game is ChopMinigame and game.state == SkillMinigame.State.READY,
		"nine rounds to play (five nodes, four recipes), the first, a tree's, on show (%d)" % buttons.size())
	if buttons.size() == 9:
		buttons[3].pressed.emit()
		game = lab.get("game") as SkillMinigame
		_check(game is CrackMinigame and buttons[3].button_pressed and not buttons[0].button_pressed, "the copper rock's button shows crack the rock, lit alone")
		buttons[5].pressed.emit()
		game = lab.get("game") as SkillMinigame
		_check(game is SmeltMinigame, "a bar's shows bellows then pour")
		game.begin(1, game.params)
		buttons[7].pressed.emit()
		_check(lab.get("game") == game, "mid-round, the round stays as it is")
		game.finish()
		buttons[7].pressed.emit()
		_check(lab.get("game") is ShapeMinigame, "after it, the axe head's button shows shape to the outline")
	lab.queue_free()
	await get_tree().process_frame
