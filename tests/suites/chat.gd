extends "res://tests/suite_base.gd"
## The `chat` suite (DECISIONS #273): what was said, shown.
##   - a `chat_message` row is a line in the box, oldest first, the last few only, this world's only; fed
##     as the server's rows are (`SpaceTimeSync.row_event`), through the registry's routing, which sends a
##     row naming an entity to that entity and not to the world's bus (a playtest caught that)
##   - a new line shows over the speaker's head; one said before you came does not
##   - Enter opens a line to write in, holding the player still; sending calls send_chat; Escape closes it
## The server's side (who may say what, how often, how long it is kept): server/tests/chat.rs and
## tests/integration_test.sh.


class FakeChatRow extends RefCounted:
	var id: int
	var world_id: int
	var entity_id: int
	var name: String
	var text: String
	var at: int

	func _init(p_id: int, p_world: int, p_entity: int, p_name: String, p_text: String, p_at: int) -> void:
		id = p_id
		world_id = p_world
		entity_id = p_entity
		name = p_name
		text = p_text
		at = p_at


func run() -> void:
	ChatBox.ensure_action()
	var enter: bool = false
	for e: InputEvent in InputMap.action_get_events(ChatBox.ACTION):
		enter = enter or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_ENTER)
	_check(enter, "Enter is chat in every game")
	var reg: Node = _autoload("EntityRegistry")
	var prev_local: int = reg.local_entity_id
	var me := SpaceTimeEntity.new()
	var d := EntityDefinition.new()
	d.kind = 0
	me.definition = d
	get_tree().root.add_child(me)
	var input: LocalInputComponent = _make_input_component(true)
	me.add_runtime_component(input)
	reg.register(7901, me)
	reg.local_entity_id = 7901
	var friend := SpaceTimeEntity.new()
	friend.definition = d
	get_tree().root.add_child(friend)
	reg.register(7902, friend)
	var chat := ChatBox.new()
	get_tree().root.add_child(chat)
	var synced: bool = ClockSync.has_sync()
	if not synced:
		ClockSync.observe_server_timestamp(ClockSync.local_usec())   # as a connection would have
	var world: int = InterestManager.world_id
	var now: int = ClockSync.server_usec()
	var say := func(id: int, w: int, who: int, name: String, text: String, at: int) -> void:
		SpaceTimeSync.row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, &"chat_message", null, FakeChatRow.new(id, w, who, name, text, at)))
	say.call(2, world, 7902, "Fin", "over here", now - 1000)
	say.call(1, world, 7901, "Luke", "where are you?", now - 2000)
	_check(chat.shown() == PackedStringArray(["Luke: where are you?", "Fin: over here"]), "the lines, oldest first (%s)" % str(chat.shown()))
	_check(chat.bubble_of(7902) == "over here", "a new line over the speaker's head")
	var sync_at: float = ClockSync.get(&"_offset_usec")
	ClockSync.reset()
	say.call(5, world, 7901, "Luke", "before the clock", now)
	_check(chat.bubble_of(7901) == "where are you?", "not knowing the server's time yet: none over a head (history cannot be told from now)")
	ClockSync.observe_server_timestamp(ClockSync.local_usec() + int(sync_at))
	say.call(3, world + 1, 7902, "Fin", "wrong world", now)
	_check(not chat.shown().has("Fin: wrong world"), "a line from another world is not shown")
	say.call(4, world, 7902, "Fin", "earlier on", now - 60_000_000)
	_check(chat.bubble_of(7902) == "over here" and chat.shown()[0] == "Fin: earlier on",
		"what was said before you came: in the log at its time, not over a head")
	for i: int in range(10):
		say.call(10 + i, world, 7902, "Fin", "line %d" % i, now + i)
	_check(chat.shown().size() == ChatBox.SHOWN and chat.shown()[-1] == "Fin: line 9", "only the last %d" % ChatBox.SHOWN)
	SpaceTimeSync.row_event.emit(RowEvent.make(RowEvent.Kind.DELETED, &"chat_message", FakeChatRow.new(19, world, 7902, "Fin", "line 9", now + 9), null))
	_check(chat.shown()[-1] == "Fin: line 9", "pruned on the server: still in the log")
	say.call(30, world, 7902, "", "no name yet", now + 20)
	_check(chat.shown()[-1] == "Player 7902: no name yet", "a player with no name: as their nameplate calls them")
	# Writing.
	chat.open()
	_check(chat.is_typing() and chat.input_line().has_focus(), "Enter: a line to write in, focused")
	_check(input.is_held_still(), "while they write, they are held still (typing 'w' does not walk them)")
	var req: ReducerRequest = chat.send("  hello all  ")
	_check(req != null and req.reducer_name == &"send_chat" and String(req.args[0]) == "hello all", "sent: send_chat(their words)")
	_check(chat.send("   ") == null, "nothing written: nothing sent")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	chat.input_line().gui_input.emit(esc)
	_check(not chat.is_typing() and not input.is_held_still(), "Escape: closed, and they move again")
	chat.open()
	chat.input_line().release_focus()
	_check(not chat.is_typing() and not input.is_held_still(), "the line losing the focus (a click elsewhere): closed, never left holding them")
	chat.open()
	chat.input_line().text_submitted.emit("")
	_check(not chat.is_typing() and not input.is_held_still(), "Enter on an empty line: closed")
	chat.queue_free()
	reg.unregister(7901)
	reg.unregister(7902)
	reg.local_entity_id = prev_local
	if not synced:
		ClockSync.reset()
	me.queue_free()
	friend.queue_free()
	await get_tree().process_frame
