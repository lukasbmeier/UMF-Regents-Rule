extends "res://tests/suite_base.gd"
## The `match` suite (tests/test_runner.gd runs it; `-- --only=match` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_match_tests()



class FakeMatchRow extends RefCounted:
	var session_id: int = 1
	var world_id: int = 0
	var first_round: int
	var started: bool
	var number: int
	func _init(first: int, s: bool, n: int) -> void:
		first_round = first
		started = s
		number = n


class FakeOnlineRow extends RefCounted:
	var identity: PackedByteArray = PackedByteArray([1, 2, 3])
	var entity_id: int
	var name: String
	var online: bool = true
	func _init(eid: int, n: String) -> void:
		entity_id = eid
		name = n


## THE MATCH, THE LOBBY SCREEN, THE SPLASH (DECISIONS #182, #183): the round a player sees counts
## from 1 in the match; the lobby screen stands everyone on its stage, holds the player still, opens
## on a match's lobby and goes when its first round starts (or on Join, arriving mid-match); the
## in-world lobby keeps out of its way; the splash plays, can be skipped, and says the game's name.
func _run_match_tests() -> void:
	print("== the match, the lobby screen, the splash ==")
	# --- the round a player sees ---------------------------------------------------------------
	var sess := SessionComponent.new()
	add_child(sess)
	sess._session_id = 1
	sess._round = 1490
	_check(sess.get_match_round() == 1490 and sess.is_match_started(),
		"with no match row (an older server) the round is the session's own, and nothing waits")
	var heard: Array[Array] = []
	sess.match_changed.connect(func(st: bool, n: int) -> void: heard.append([st, n]))
	sess._on_global_row(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.MATCH_TABLE, null, FakeMatchRow.new(1490, false, 2)))
	_check(sess.get_match_round() == 1 and not sess.is_match_started() and sess.match_number() == 2 and heard == [[false, 2]],
		"a match begun on the session's round 1490 shows it as round 1, its lobby waiting (%s)" % str(heard))
	sess._round = 1493
	_check(sess.get_match_round() == 4, "three rounds on, it is round 4 (%d)" % sess.get_match_round())
	var elsewhere := FakeMatchRow.new(7, true, 9)
	elsewhere.session_id = 2
	sess._on_global_row(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.MATCH_TABLE, null, elsewhere))
	_check(sess.match_number() == 2 and heard.size() == 1, "another session's match is not ours")
	sess.queue_free()
	_check(Rules.doc()["sessions"][0].has("match") and int(Rules.doc()["sessions"][0]["match"]["end_after_empty_s"]) > 0,
		"rules.json says how long a world may be empty before its match ends")

	# --- held still while a page covers the game -------------------------------------------------
	var input: LocalInputComponent = _make_input_component(true)
	_release_all_actions()
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	input.hold_still(&"lobby_screen", true)
	var still: InputFrame = input.sample()
	_check(still.move_dir == Vector2.ZERO and not still.jump and input.is_held_still(),
		"held still, the movement keys and jump are not read")
	var yaw_before: float = input.get_look_yaw()
	var turn := InputEventMouseMotion.new()
	turn.relative = Vector2(300.0, 0.0)
	input._unhandled_input(turn)
	_check(is_equal_approx(input.get_look_yaw(), yaw_before), "nor is the mouse")
	input.hold_still(&"lobby_screen", false)
	var free: InputFrame = input.sample()
	_check(free.move_dir != Vector2.ZERO and free.jump, "let go, they are again")
	_release_all_actions()
	# Freed now, not at the frame's end: its exit hands the cursor back, and the player below asks for it.
	var input_owner: Node = input.entity
	input.free()
	input_owner.queue_free()

	# --- the lobby screen, in a world with two players ---------------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(CHARACTER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5701
	for eid: int in [5701, 5702]:
		_buffer_player_rows(reg, eid)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(eid, false, 0)))
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"player", null, FakeOnlineRow.new(eid, "Ailsa" if eid == 5701 else "Bram")))
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(5701) as SpaceTimeEntity
	var my_sess: SessionComponent = me.find_component(SessionComponent) as SessionComponent
	var my_input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	my_sess._session_kind = 0
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._phase_ends_at_usec = ClockSync.server_usec() + 365 * 24 * 3_600_000_000
	my_sess._apply_match_row(FakeMatchRow.new(1, false, 1))
	var panel := LobbyPanel.new()
	add_child(panel)
	var screen := LobbyScreen.new()
	add_child(screen)
	for i: int in range(3):
		await get_tree().process_frame
	_check(screen.visible and LobbyScreen.showing(get_tree()) == screen,
		"a match waiting for its players: the lobby screen is open")
	_check(not panel.visible, "and the in-world lobby panel keeps out of its way")
	_check(my_input != null and my_input.is_held_still() and not MouseCapture.is_captured(),
		"the player is held still behind it, and has the cursor")
	_check(MouseCapture.is_held_free() and not MouseCapture.released_by_player(),
		"a page holding the cursor, not the player releasing it: the Escape menu stays shut")
	var escape := InputEventAction.new()
	escape.action = MouseCapture.RELEASE_ACTION
	escape.pressed = true
	MouseCapture._input(escape)
	_check(MouseCapture.released_by_player(), "Escape still opens the menu over it (wanted %s, held %s, captured %s)"
		% [MouseCapture.is_wanted(), MouseCapture.is_held_free(), MouseCapture.is_captured()])
	MouseCapture.recapture()
	_check(not MouseCapture.is_captured() and not MouseCapture.released_by_player(),
		"and Resume comes back to the lobby screen, the cursor still free")
	var models: Dictionary[int, Node3D] = screen.stage_models()
	_check(models.size() == 2 and models.has(5701) and models.has(5702),
		"both players stand on its stage (%s)" % str(models.keys()))
	var ours: Node3D = models.get(5701)
	_check(ours != null and ours.find_children("*", "Skeleton3D", true, false).size() == 1
		and ours.find_children("*", "Label3D", true, false).size() == 1,
		"each in their look, with their name over their head")
	_check(ours != null and models.get(5702) != null and ours.position.x < (models.get(5702) as Node3D).position.x,
		"ourselves first")
	var ready_button: Button = screen.find_child("Ready", true, false) as Button
	var join_button: Button = screen.find_child("Join", true, false) as Button
	var status: Label = screen.find_child("Status", true, false) as Label
	_check(ready_button.visible and not join_button.visible and status.text.contains("0 of 2"),
		"Ready, not Join, and how many are ready: \"%s\"" % status.text)
	ready_button.pressed.emit()
	await get_tree().process_frame
	_check(not screen.said().is_empty(), "Ready asks the server, and a refusal is said (offline: \"%s\")" % screen.said())
	var press := InputEventAction.new()
	press.action = LobbyPanel.ACTION_READY
	press.pressed = true
	screen._unhandled_input(press)
	_check(not screen.said().is_empty(), "R asks too")
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5702, true, 0)))
	for i: int in range(2):
		await get_tree().process_frame
	_check(status.text.contains("1 of 2"), "Bram is ready: \"%s\"" % status.text)
	# The match starts: the screen goes, the game is theirs.
	my_sess._phase = SessionComponent.Phase.PLAYING
	my_sess._apply_match_row(FakeMatchRow.new(1, true, 1))
	for i: int in range(2):
		await get_tree().process_frame
	_check(not screen.visible and not my_input.is_held_still() and screen.stage_models().is_empty(),
		"its first round starts: the screen goes, the player is free, the stage is cleared")
	_check(not MouseCapture.is_held_free(), "and the cursor is the game's again")
	# A new match (after everyone left and came back): its lobby is everyone's again.
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._apply_match_row(FakeMatchRow.new(9, false, 2))
	for i: int in range(2):
		await get_tree().process_frame
	_check(screen.visible, "a new match opens its lobby screen again")
	# Arriving in the middle of a match: Join instead of Ready.
	screen.queue_free()
	my_sess._phase = SessionComponent.Phase.PLAYING
	my_sess._apply_match_row(FakeMatchRow.new(9, true, 2))
	var late := LobbyScreen.new()
	add_child(late)
	for i: int in range(2):
		await get_tree().process_frame
	join_button = late.find_child("Join", true, false) as Button
	ready_button = late.find_child("Ready", true, false) as Button
	_check(late.visible and join_button.visible and not ready_button.visible
		and (late.find_child("Status", true, false) as Label).text.contains("under way"),
		"arriving mid-match, the screen offers Join, not Ready")
	join_button.pressed.emit()
	await get_tree().process_frame
	_check(not late.visible and not my_input.is_held_still(), "and Join takes them into the game")
	late.queue_free()
	var harness := LobbyScreen.new()
	harness.auto_join = true
	add_child(harness)
	for i: int in range(2):
		await get_tree().process_frame
	_check(not harness.visible, "a harness that connects for the player goes straight into a match under way")
	harness.queue_free()
	var off := LobbyScreen.new()
	off.enabled = false
	add_child(off)
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._apply_match_row(FakeMatchRow.new(11, false, 3))
	for i: int in range(2):
		await get_tree().process_frame
	_check(not off.visible and panel.visible, "with no window it never shows, and the in-world lobby is back")
	off.queue_free()
	panel.queue_free()
	for eid: int in [5701, 5702]:
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the splash ----------------------------------------------------------------------------------
	var game_scene: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	var state: SceneState = game_scene.get_state()
	var splash_scene: PackedScene = null
	for i: int in range(state.get_node_count()):
		if state.get_node_name(i) == &"Boot":
			for k: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, k) == &"splash_screen":
					splash_scene = state.get_node_property_value(i, k) as PackedScene
	_check(splash_scene != null and splash_scene.resource_path == "res://game/splash_screen.tscn",
		"the game's Boot plays the game's splash")
	var splash: SplashScreen = splash_scene.instantiate() as SplashScreen if splash_scene != null else null
	if splash == null:
		return
	add_child(splash)
	var done: Array[bool] = [false]
	splash.finished.connect(func() -> void: done[0] = true)
	_check((splash.find_child("Title", true, false) as Label).text == Genres.title() and not Genres.title().is_empty(),
		"it says the game's name from shared/game.json (%s)" % Genres.title())
	_check(not splash.lines.is_empty() and splash.lines.has(splash.shown_line()) and is_equal_approx(splash.hold_sec, 5.0),
		"and a tip, one of its own (\"%s\"), for five seconds" % splash.shown_line())
	var plain := SplashScreen.new()
	_check(splash._ripples.visible == splash.ripples and not plain.ripples,
		"water ripples only when the game's splash asks for them (a fishing game's does; the default does not)")
	plain.free()
	splash.play()
	splash._process(0.0)
	_check(splash.visible and splash._root.modulate.a == 1.0 and (splash.find_child("Splash", true, false) as Control).get_child(0) is ColorRect
		and ((splash.find_child("Splash", true, false) as Control).get_child(0) as ColorRect).color.a == 1.0,
		"from its first frame an opaque background covers the level (nothing of it shows through)")
	_check(splash._content.modulate.a < 0.05, "while the words start to fade in on it")
	splash._process(splash.fade_sec)
	_check(splash.visible and is_equal_approx(splash._root.modulate.a, 1.0) and not done[0], "it fades in and holds")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	splash._input(click)
	splash._process(splash.fade_sec * 0.5)
	_check(not done[0] and splash._root.modulate.a < 1.0, "a click fades it out at once")
	splash._process(splash.fade_sec)
	_check(done[0] and not splash.visible and not splash.is_playing(),
		"well before its time was up (%.1f of %.1f s)" % [splash.fade_sec * 2.5, splash.fade_sec * 2.0 + splash.hold_sec])
	splash.queue_free()
	var whole: SplashScreen = splash_scene.instantiate() as SplashScreen
	add_child(whole)
	var ended: Array[bool] = [false]
	whole.finished.connect(func() -> void: ended[0] = true)
	whole.play()
	var t: float = 0.0
	var seen: Array[String] = []
	while not ended[0] and t < 10.0:
		whole._process(0.05)
		t += 0.05
		if not seen.has(whole.shown_line()):
			seen.append(whole.shown_line())
	_check(seen.size() >= 2 and seen.size() <= whole.lines.size(), "its lines change every %.1f s (%d shown in %.1f s)" % [whole.line_sec, seen.size(), t])
	_check(ended[0] and absf(t - (whole.hold_sec + 2.0 * whole.fade_sec)) < 0.11,
		"left alone, it is done after its fade in, hold and fade out (%.2f s)" % t)
	whole.queue_free()
	# Turned off in Settings (testing): Boot goes straight on.
	var boot: Node = (load("res://foundation/boot.gd") as GDScript).new() as Node
	boot.set(&"splash_screen", splash_scene)
	var was: Variant = Settings.get_value(&"splash_at_start")
	_check(bool(boot.call(&"wants_splash", true)) == bool(was), "Boot plays it when the setting is on (it is %s)" % str(was))
	Settings.set_value(&"splash_at_start", false)
	_check(not bool(boot.call(&"wants_splash", true)), "and not when a player turns it off (Settings, Game: Splash screen at start)")
	Settings.set_value(&"splash_at_start", was)
	_check(not bool(boot.call(&"wants_splash", false)), "nor without a window")
	boot.free()
