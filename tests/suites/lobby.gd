extends "res://tests/suite_base.gd"
## The `lobby` suite (tests/test_runner.gd runs it; `-- --only=lobby` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_lobby_tests()



func _run_lobby_tests() -> void:
	print("== the lobby ==")
	var lobby: Dictionary = Rules.lobby(0)
	var plan: Dictionary = {}
	for k: Variant in (JSON.parse_string(FileAccess.get_file_as_string("res://shared/rules.json")) as Dictionary)["sessions"]:
		if int((k as Dictionary)["kind"]) == 0:
			plan = ((k as Dictionary).get("lobby", {}) as Dictionary)
	_check(bool(lobby.get("ready_up", false)) == bool(plan.get("ready_up", false))
		and int(lobby.get("min_players", 0)) == int(plan.get("min_players", 0))
		and Rules.teams(0).size() == (plan.get("teams", []) as Array).size(),
		"the default kind's lobby is shared/rules.json's: ready-up %s, %d players, %d teams"
			% [lobby.get("ready_up", false), int(lobby.get("min_players", 0)), Rules.teams(0).size()])
	_check(Rules.lobby(77).is_empty() and Rules.teams(77).is_empty(), "a kind with no lobby has none")
	var sess := SessionComponent.new()
	add_child(sess)
	var heard: Array[Array] = []
	sess.lobby_changed.connect(func(r: bool, t: int) -> void: heard.append([r, t]))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(9, true, 2))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(9, true, 2))
	_check(sess.is_ready() and sess.team() == 2 and heard == [[true, 2]],
		"a member's ready and team come from its row, announced once (%s)" % str(heard))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, FakeLobbyRow.new(9, true, 2), null)
	_check(not sess.is_ready() and sess.team() == 0, "and go with it")
	_check(sess.optional_tables().has(SessionComponent.LOBBY_TABLE), "a kind with no lobby is not waited for")
	sess.queue_free()
	var panel := LobbyPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_check(not panel.should_show() and not panel.visible, "with no local player in a lobby, the panel is not shown")
	var prev_local: int = EntityRegistry.local_entity_id
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(CHARACTER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5601
	_buffer_player_rows(reg, 5601)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5601, false, 0)))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(5601, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(5601) as SpaceTimeEntity
	var my_sess: SessionComponent = me.find_component(SessionComponent) as SessionComponent
	my_sess._session_kind = 0
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._phase_ends_at_usec = ClockSync.server_usec() + 20_000_000
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Array[Dictionary] = panel.members()
	_check(panel.visible and rows.size() >= 1 and bool(rows[0]["is_local"]) and not bool(rows[0]["ready"]),
		"in a lobby, the panel lists who is here, us not ready yet")
	var hint: Label = panel.find_child("Hint", true, false) as Label
	_check(hint.text.contains("ready"), "and says the key to be ready (%s)" % hint.text.replace("\n", " / "))
	var press := InputEventAction.new()
	press.action = LobbyPanel.ACTION_READY
	press.pressed = true
	panel._unhandled_input(press)
	await get_tree().process_frame
	_check(not panel.said().is_empty(), "the key asks the server, and a refusal is said (offline: \"%s\")" % panel.said())
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5601, true, 0)))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(panel.members()[0]["ready"]), "once the server says ready, the panel does")
	my_sess._phase = SessionComponent.Phase.PLAYING
	await get_tree().process_frame
	_check(not panel.visible, "and it goes when the round starts")
	spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(5601, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	panel.queue_free()
