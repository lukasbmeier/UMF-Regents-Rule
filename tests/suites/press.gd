extends "res://tests/suite_base.gd"
## The `press` suite (tests/test_runner.gd runs it; `-- --only=press` runs it alone).
## THE SERVER-TIMED PRESS (DECISIONS #210): the client's twin of the sweep and a press's quality (the
## same numbers as server/tests/timed_press.rs); the component that acknowledges a press challenge on
## arrival, draws the marker from the server's clock, predicts each press and hears it judged; the
## interact key pressing it while one is played; the bar on the HUD; every entity given one. The
## server's side: tests/integration_test.sh; a real client at a real latency: tests/press_playtest.sh.


func run() -> void:
	_run_model()
	await _run_component()
	await _run_rules_page()
	_run_every_entity_has_one()


class _ChallengeRow extends RefCounted:
	var id: int = 0
	var entity_id: int = 0
	var kind: int = 1
	var seed: int = 0
	var difficulty: float = 0.5
	var issued_at: int = 0
	var expires_at: int = 0
	var payload: String = ""
	func _init(p_id: int, eid: int, p_kind: int = 1, p_seed: int = 12345) -> void:
		id = p_id
		entity_id = eid
		kind = p_kind
		seed = p_seed
		issued_at = ClockSync.server_usec()
		expires_at = issued_at + 30_000_000


class _SweepRow extends RefCounted:
	var challenge_id: int = 0
	var entity_id: int = 0
	var starts_at: int = 0
	var period_ms: int = 2000
	var half_width: float = 0.1
	var rounds: int = 3
	var seen_ms: int = 0
	var at_ms: Array = []
	var positions: Array = []
	var qualities: Array = []
	var credit_ms: int = 0
	var done: bool = false
	func _init(cid: int, eid: int, started_s_ago: float, p_qualities: Array = [], p_done: bool = false) -> void:
		challenge_id = cid
		entity_id = eid
		starts_at = ClockSync.server_usec() - int(started_s_ago * 1_000_000.0)
		qualities = p_qualities
		positions = p_qualities.map(func(_q: float) -> float: return 0.5)
		done = p_done


func _run_model() -> void:
	print("== press: the client's twin of the sweep (server/tests/timed_press.rs's numbers) ==")
	_check(ChallengeModel.sweep_position(-0.5, 2.0) == 0.0 and ChallengeModel.sweep_position(0.0, 2.0) == 0.0,
		"before it begins: at the start")
	_check(is_equal_approx(ChallengeModel.sweep_position(0.5, 2.0), 0.5) and is_equal_approx(ChallengeModel.sweep_position(1.0, 2.0), 1.0)
		and is_equal_approx(ChallengeModel.sweep_position(1.5, 2.0), 0.5) and is_equal_approx(ChallengeModel.sweep_position(2.5, 2.0), 0.5),
		"there and back: half way at a quarter period, the far end at a half, half way back, round again")
	_check(ChallengeModel.press_quality(0.5, 0.5, 0.1) == 1.0 and absf(ChallengeModel.press_quality(0.55, 0.5, 0.1) - 0.5) < 1e-5
		and ChallengeModel.press_quality(0.7, 0.5, 0.1) == 0.0, "a press's quality: centre 1, half way 0.5, outside 0")
	_check(ChallengeModel.press_credit_ms(160, 120) == 80 and ChallengeModel.press_credit_ms(400, 120) == 120 and ChallengeModel.press_credit_ms(0, 120) == 0,
		"the credit: half the round trip, at most the cap, none unmeasured")


## A bound local player with a timed-press component (and an interaction component, for the key).
func _player(eid: int) -> SpaceTimeEntity:
	var ent := SpaceTimeEntity.new()
	ent.definition = load("res://foundation/content/character/humanoid.tres") as EntityDefinition
	get_tree().root.add_child(ent)
	ent.entity_id = eid
	ent.is_local_authority = true
	var tp := TimedPressComponent.new()
	ent.add_runtime_component(tp)
	tp.bind(ent, {})
	var ic := InteractionComponent.new()
	ent.add_runtime_component(ic)
	ic.bind(ent, {})
	ic.set_physics_process(false)
	ent._is_bound = true
	EntityRegistry.register(eid, ent)
	return ent


func _run_component() -> void:
	print("== press: played on the client ==")
	var me: SpaceTimeEntity = _player(9901)
	var tp: TimedPressComponent = me.find_component(TimedPressComponent) as TimedPressComponent
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	_check(tp.current() == -1 and not tp.wants_press() and not ic.press_timed(), "nothing to press: the key is the interact key")
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"challenge", null, _ChallengeRow.new(41, 9901, 0)))
	_check(tp.current() == -1 and not tp._acked.has(41), "a timing bar (kind 0) is not a timed press: not played, not acknowledged")
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"challenge", null, _ChallengeRow.new(42, 9901)))
	_check(tp._acked.has(42), "a timed press is acknowledged the moment it arrives (the server times the trip)")
	_check(tp.current() == -1, "no sweep yet: nothing to play")
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"timed_press", null, _SweepRow.new(42, 9901, -0.5)))
	_check(tp.current() == 42 and tp.wants_press() and tp.elapsed(42) < 0.0, "its sweep: being played, the marker still to start")
	_check(tp.press() == null and tp.presses_made(42) == 0, "a press before the marker moves is not sent")
	var s: Dictionary = TimingBar.state_for(me)
	_check(bool(s["visible"]) and String(s["text"]) == "Get ready…", "the bar: \"%s\"" % s["text"])

	# The server's clock is not this machine's: the marker follows the server's (ClockSync), as the
	# server judges by it.
	var clock: Node = _autoload("ClockSync")
	var was_offset: float = float(clock.get(&"_offset_usec"))
	clock.set(&"_offset_usec", was_offset + 7_300_000.0)
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"timed_press", null, _SweepRow.new(42, 9901, 0.5)))
	_check(absf(tp.marker(42) - 0.5) < 0.02, "half a second into a 2 s sweep by the server's clock (7.3 s from this one's): the marker half way (%.3f)" % tp.marker(42))
	var centre: float = ChallengeModel.timing_centers(12345).x
	_check(is_equal_approx(tp.target(42, 0), centre), "the first target is the seed's (as the server's)")
	s = TimingBar.state_for(me)
	_check(String(s["text"]) == "Press E  (1 of 3)" and absf(float(s["marker"]) - 0.5) < 0.02, "the bar: \"%s\"" % s["text"])
	var heard: Array = []
	tp.pressed.connect(func(id: int, round: int, predicted: float) -> void: heard.append([id, round, predicted]))
	_check(ic.press_timed(), "the interact key presses it")
	var req: ReducerRequest = tp.press()
	_check(req != null and req.reducer_name == &"challenge_press" and req.args == [42], "a press sends only that it was pressed: challenge_press(42)")
	_check(heard.size() == 2 and int(heard[1][1]) == 1 and tp.presses_made(42) == 2,
		"each press predicted at once, the next round up (%s)" % str(heard))
	var judged: Array = []
	tp.judged.connect(func(id: int, round: int, q: float, _pos: float, predicted: float) -> void: judged.append([id, round, q, predicted]))
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"timed_press", null, _SweepRow.new(42, 9901, 0.6, [0.9])))
	_check(judged.size() == 1 and int(judged[0][1]) == 0 and is_equal_approx(float(judged[0][2]), 0.9) and float(judged[0][3]) >= 0.0,
		"the server's judgement of the first press replaces the guess (%s)" % str(judged))
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"timed_press", null, _SweepRow.new(42, 9901, 0.7, [0.9])))
	_check(judged.size() == 1, "the same row again is no news")
	tp.press()
	_check(tp.current() == -1 and not tp.wants_press(), "three presses made: nothing left to press, the key is the interact key again")
	_check(tp.press() == null, "a fourth is not sent")
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"timed_press", null, _SweepRow.new(42, 9901, 0.9, [0.9, 0.4, 0.0], true)))
	tp.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"challenge", _ChallengeRow.new(42, 9901), null))
	s = TimingBar.state_for(me)
	_check(judged.size() == 3 and bool(s["visible"]) and String(s["text"]) == "Miss", "every press judged; the last word stays a moment: \"%s\"" % s["text"])
	_check(TimingBar.word_for(0.9) == "Great" and TimingBar.word_for(0.4) == "Good" and TimingBar.word_for(0.0) == "Miss", "Great, Good, Miss")
	var bar := TimingBar.new()
	get_tree().root.add_child(bar)
	bar.show_state(s)
	_check(bar.visible, "and drawn")
	bar.queue_free()
	clock.set(&"_offset_usec", was_offset)
	EntityRegistry.unregister(9901)
	me.queue_free()
	await get_tree().process_frame


func _run_rules_page() -> void:
	print("== press: tried from the Rules page ==")
	var page := RulesPanel.new()
	get_tree().root.add_child(page)
	page.open()
	var labels: Array = page.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	_check(labels.has("Easy") and labels.has("Middling") and labels.has("Hard") and labels.has("Put me in it"),
		"the admin's Rules page offers a skill check, easy to hard, beside Try a status")
	var req: ReducerRequest = page.try_skill_check(0.5)
	_check(req != null and req.reducer_name == &"issue_challenge" and req.args.size() == 3 and int(req.args[1]) == ChallengeModel.KIND_TIMED_PRESS
		and is_equal_approx(float(req.args[2]), 0.5), "a skill check is a timed press for yourself: issue_challenge(me, 1, 0.5)")
	_check(labels.has("Go"), "and Go to: the spawn or beside a player")
	req = page.go_to(-1)
	_check(req != null and req.reducer_name == &"teleport", "Go to the spawn teleports the admin there")
	req = page.try_status(StatusDef.DOWNED)
	_check(req != null and req.reducer_name == &"set_status" and int(req.args[1]) == StatusDef.DOWNED and int(req.args[2]) == 0,
		"and Try a status puts you in one for its own length: set_status(me, 2, 0)")
	page.queue_free()
	await get_tree().process_frame


func _run_every_entity_has_one() -> void:
	print("== press: every entity has one, every client subscribes ==")
	var p: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	p._collect_components()
	var n: int = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is TimedPressComponent).size()
	_check(n == 1, "an entity whose scene has none is given one (player.tscn: %d)" % n)
	p.free()
	_check(NetConfig.new().core_tables.has(&"timed_press"), "every client subscribes timed_press (its own rows only: row-level security)")
