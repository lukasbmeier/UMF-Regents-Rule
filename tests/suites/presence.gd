extends "res://tests/suite_base.gd"
## The `presence` suite (tests/test_runner.gd runs it; `-- --only=presence` runs it alone).
## WHO IS HERE (DECISIONS #202): a player who disconnects leaves the world after the grace the hot
## rule `foundation.offline_linger_s` gives (hidden, and nothing collides with or aims at them), and
## comes back when they connect; one already gone when we arrive is never shown; an NPC (no player
## row) is always here. And the game's brief notices reach the screen.


func run() -> void:
	await _run_presence_tests()
	await _run_notice_tests()


class _PlayerRow extends RefCounted:
	var entity_id: int = 0
	var online: bool = true
	func _init(eid: int, on: bool) -> void:
		entity_id = eid
		online = on


class _NamedRow extends RefCounted:
	var entity_id: int = 0
	var online: bool = true
	var name: String = ""
	var identity: PackedByteArray
	func _init(eid: int, n: String, id: PackedByteArray) -> void:
		entity_id = eid
		name = n
		identity = id


class _RuleRow extends RefCounted:
	var key: String = "foundation.offline_linger_s"
	var number: float = 0.3
	var text: String = ""
	var overridden: bool = true


func _body(eid: int) -> SpaceTimeEntity:
	var b := SpaceTimeEntity.new()
	get_tree().root.add_child(b)   # in the tree first, as the spawner does (hard rule 8)
	b.entity_id = eid
	b.collision_layer = 3
	b.collision_mask = 5
	return b


func _run_presence_tests() -> void:
	print("== presence: who is here ==")
	HotRules.reset()
	var linger := _RuleRow.new()
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, &"hot_rule", null, linger))
	_check(is_equal_approx(HotRules.number(PresenceComponent.LINGER_RULE), 0.3), "the grace is the hot rule's (0.3 s here)")

	var body: SpaceTimeEntity = _body(8801)
	var p := PresenceComponent.new()
	body.add_child(p)
	p.bind(body, {&"player": _PlayerRow.new(8801, true)})
	await get_tree().process_frame
	_check(body.visible and p.is_present() and body.collision_layer == 3, "a player who is connected is in the world")
	p.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"player", _PlayerRow.new(8801, true), _PlayerRow.new(8801, false)))
	await get_tree().process_frame
	_check(body.visible and p.is_present(), "one who just disconnected is still there during the grace")
	await get_tree().create_timer(0.45).timeout
	_check(not body.visible and not p.is_present() and body.collision_layer == 0 and body.collision_mask == 5,
		"after it, gone: hidden, and nothing collides with them or aims at them (no layer); they still stand on the world (mask kept, DECISIONS #211)")
	p.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"player", _PlayerRow.new(8801, false), _PlayerRow.new(8801, true)))
	await get_tree().process_frame
	_check(body.visible and p.is_present() and body.collision_layer == 3 and body.collision_mask == 5,
		"connected again: back where they were, colliding as before")
	body.queue_free()

	var gone: SpaceTimeEntity = _body(8802)
	var q := PresenceComponent.new()
	gone.add_child(q)
	q.bind(gone, {&"player": _PlayerRow.new(8802, false)})
	await get_tree().process_frame
	_check(not gone.visible and not q.is_present(), "a player already gone when we arrive is never shown")
	gone.queue_free()

	var npc: SpaceTimeEntity = _body(8803)
	var r := PresenceComponent.new()
	npc.add_child(r)
	r.bind(npc, {})
	await get_tree().create_timer(0.4).timeout
	_check(npc.visible and r.is_present(), "an NPC (no player row) is always here")
	npc.queue_free()
	# A tool is not a person (#272): an admin who never said a name (the CLI) is never seen; a named admin
	# (the designer playing from the editor) and a nameless player who is no admin (a test client) are.
	PresenceComponent.admin_check = func(identity: Variant) -> bool: return identity == PackedByteArray([1])
	var cli: SpaceTimeEntity = _body(8804)
	var t := PresenceComponent.new()
	cli.add_child(t)
	t.bind(cli, {&"player": _NamedRow.new(8804, "", PackedByteArray([1]))})
	await get_tree().process_frame
	_check(not cli.visible, "the database's CLI (an admin, no name): never seen")
	t.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"player", _NamedRow.new(8804, "", PackedByteArray([1])), _NamedRow.new(8804, "Luke", PackedByteArray([1]))))
	await get_tree().process_frame
	_check(cli.visible, "an admin with a name (playing from the editor): seen")
	cli.queue_free()
	var anon: SpaceTimeEntity = _body(8805)
	var u := PresenceComponent.new()
	anon.add_child(u)
	u.bind(anon, {&"player": _NamedRow.new(8805, "", PackedByteArray([2]))})
	await get_tree().process_frame
	_check(anon.visible, "a nameless player who is no admin (a test client): seen")
	anon.queue_free()
	PresenceComponent.admin_check = Callable()
	var player_scene: Node = (load("res://foundation/entities/player.tscn") as PackedScene).instantiate()
	_check(player_scene.get_node_or_null(^"Components/Presence") is PresenceComponent,
		"every player scene has it (foundation/entities/player.tscn, which a genre's player instances)")
	player_scene.free()
	HotRules.reset()


func _run_notice_tests() -> void:
	print("== presence: notices ==")
	var n := Notices.new()
	get_tree().root.add_child(n)
	SignalBus.notification_requested.emit("The name 'Luke' is taken", 1)
	SignalBus.notification_requested.emit("", 0)
	await get_tree().process_frame
	_check(n.shown() == PackedStringArray(["The name 'Luke' is taken"]),
		"a notice reaches the screen; an empty one does not (%s)" % str(n.shown()))
	for i: int in 6:
		n.show_notice("notice %d" % i)
	await get_tree().process_frame
	_check(n.shown().size() == Notices.MAX_SHOWN and n.shown()[n.shown().size() - 1] == "notice 5",
		"only the latest few stay up")
	n.queue_free()
