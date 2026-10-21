class_name ChatBox extends CanvasLayer
## CHAT (DECISIONS #273; owner, 2026-10-20, after the friends' playtest: "sorely missed"). Bottom left:
## the last lines said in this world (`chat_message` rows: the server's `send_chat`), fading when nobody
## has spoken for a while. Enter opens a line to write in; Enter sends it, Escape (or an empty line)
## closes it. The player is held still while they write, so typing "w" does not walk them. A new line
## also shows over the speaker's head for a few seconds.
##
## Boot adds one to every game scene with a display, outside the HUD (like `Notices`), so a genre that
## brings its own HUD keeps it.

const ACTION: StringName = &"chat"
const STILL_REASON: StringName = &"chat"
## Lines shown at once.
const SHOWN: int = 8
## Seconds after the last line before the box fades (it comes back with the next line, or Enter).
const FADE_S: float = 12.0
## Seconds a line stays over the speaker's head.
const BUBBLE_S: float = 6.0
## How far above the entity's origin the line shows (just over the nameplate's 2.05 m).
const BUBBLE_HEIGHT: float = 2.45
## A row older than this when it arrives (what was said before you came) is not shown over a head.
const BUBBLE_FRESH_USEC: int = 10_000_000
## How far up from the screen's bottom edge the box sits, px (clear of a bar along the bottom).
const BOTTOM_GAP: float = 140.0

## The longest line the box lets you write (the server keeps at most `chat::MAX_BYTES` bytes of it).
static var max_chars: int = 200

var _panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit
## id -> {world, entity, name, text, at}
var _lines: Dictionary = {}
var _held: LocalInputComponent = null
var _quiet_s: float = 0.0
var _bubbles: Dictionary = {}   # entity id -> Label3D


func _ready() -> void:
	layer = 45
	ensure_action()
	_panel = PanelContainer.new()
	_panel.name = "Chat"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16.0
	_panel.offset_top = -BOTTOM_GAP
	_panel.offset_bottom = -BOTTOM_GAP
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.bbcode_enabled = false
	_log.fit_content = true
	_log.scroll_active = false
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size = Vector2(404, 0)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_log.add_theme_constant_override(&"outline_size", 4)
	box.add_child(_log)
	_input = LineEdit.new()
	_input.name = "Input"
	_input.max_length = max_chars
	_input.placeholder_text = "Say something (Enter to send, Esc to cancel)"
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_key)
	box.add_child(_input)
	# Tab stays in the line (it would move the focus, and the keys would walk the player); losing the
	# focus any other way closes it.
	_input.focus_next = _input.get_path()
	_input.focus_previous = _input.get_path()
	_input.focus_exited.connect(func() -> void:
		if _input.visible:
			close())
	_panel.modulate.a = 0.0
	# Every row as it arrives, not `EntityRegistry.global_row_event`: a line names its speaker
	# (`entity_id`), so the registry routes it to the speaker's entity, never to the world's bus.
	if not SpaceTimeSync.row_event.is_connected(_on_row):
		SpaceTimeSync.row_event.connect(_on_row)
	if not InterestManager.world_changed.is_connected(_on_world):
		InterestManager.world_changed.connect(_on_world)


func _exit_tree() -> void:
	if SpaceTimeSync.row_event.is_connected(_on_row):
		SpaceTimeSync.row_event.disconnect(_on_row)
	if InterestManager.world_changed.is_connected(_on_world):
		InterestManager.world_changed.disconnect(_on_world)
	_hold(false)


## The Enter key (and the keypad's), given to every game (a project may bind it otherwise in its Input Map).
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	for code: Key in [KEY_ENTER, KEY_KP_ENTER]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(ACTION, key)


func _unhandled_input(event: InputEvent) -> void:
	if not _input.visible and event.is_action_pressed(ACTION) and not event.is_echo() and SpaceTimeSync.is_connected_to_server():
		get_viewport().set_input_as_handled()
		open()


func _process(delta: float) -> void:
	if _input.visible:
		_panel.modulate.a = 1.0
		return
	_quiet_s += delta
	if _lines.is_empty():
		_panel.modulate.a = 0.0
	elif _quiet_s > FADE_S:
		_panel.modulate.a = maxf(0.0, _panel.modulate.a - delta)


## Open the line to write in: the player held still until it closes.
func open() -> void:
	_input.visible = true
	_input.text = ""
	_input.grab_focus()
	_panel.modulate.a = 1.0
	_hold(true)


func close() -> void:
	_input.visible = false   # first: letting go of the focus below would close it again
	_input.text = ""
	_input.release_focus()
	_quiet_s = 0.0
	_hold(false)


func is_typing() -> bool:
	return _input.visible


## Say `text` to this world. Null (nothing sent) when there is nothing to say.
func send(text: String) -> ReducerRequest:
	var said: String = text.strip_edges()
	if said.is_empty():
		return null
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"send_chat", [said], ["string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if not r.is_ok() and is_inside_tree():
			SignalBus.notification_requested.emit("Not sent: " + r.error_message, 1))
	return req


func _on_submitted(text: String) -> void:
	send(text)
	close()


func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_input.accept_event()
		close()


func _hold(on: bool) -> void:
	if on:
		var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		_held = me.find_component(LocalInputComponent) as LocalInputComponent if me != null else null
		if _held != null:
			_held.hold_still(STILL_REASON, true)
	elif _held != null:
		if is_instance_valid(_held):
			_held.hold_still(STILL_REASON, false)
		_held = null


func _on_row(ev: RowEvent) -> void:
	if ev.table != &"chat_message":
		return
	if ev.kind == RowEvent.Kind.DELETED:
		return   # pruned on the server: what was shown stays in the log
	var row: RefCounted = ev.current()
	if row == null:
		return
	add_line(int(row.get(&"id")), int(row.get(&"world_id")), int(row.get(&"entity_id")), String(row.get(&"name")),
		String(row.get(&"text")), int(row.get(&"at")))


## One line said (a row arrived; tests call it directly). Over the speaker's head too when it is new.
func add_line(id: int, world: int, entity_id: int, who: String, text: String, at_usec: int) -> void:
	if _lines.has(id):
		return
	# A player who never said a name is called what their nameplate calls them.
	var name: String = who if not who.strip_edges().is_empty() else "Player %d" % entity_id
	_lines[id] = {"world": world, "entity": entity_id, "name": name, "text": text, "at": at_usec}
	_redraw()
	if world == InterestManager.world_id:
		_quiet_s = 0.0
		_panel.modulate.a = 1.0
		# Not knowing the server's time yet, a line cannot be told from history: none over a head.
		if ClockSync.has_sync() and ClockSync.server_usec() - at_usec < BUBBLE_FRESH_USEC:
			_bubble(entity_id, text)


func _on_world(_world: int) -> void:
	_redraw()


## The last `SHOWN` lines of the world this player is in, oldest first.
func _visible_ids() -> Array:
	var ids: Array = []
	for id: int in _lines:
		if int(_lines[id]["world"]) == InterestManager.world_id:
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ta: int = int(_lines[a]["at"])
		var tb: int = int(_lines[b]["at"])
		return ta < tb if ta != tb else a < b)
	return ids.slice(maxi(0, ids.size() - SHOWN))


func _redraw() -> void:
	# Never more than the server keeps (`chat::MAX_KEPT`) of each world, plus a little.
	if _lines.size() > 200:
		var all: Array = _lines.keys()
		all.sort()
		for id: int in all.slice(0, _lines.size() - 200):
			_lines.erase(id)
	_log.clear()
	var style: UiStyle = UiStyle.current()
	var first: bool = true
	for id: int in _visible_ids():
		var l: Dictionary = _lines[id]
		if not first:
			_log.newline()
		first = false
		_log.push_color(style.accent if int(l["entity"]) == EntityRegistry.local_entity_id else style.warn)
		_log.add_text(String(l["name"]) + ": ")
		_log.pop()
		_log.push_color(style.text)
		_log.add_text(String(l["text"]))
		_log.pop()


func _bubble(entity_id: int, text: String) -> void:
	var who: Node3D = EntityRegistry.get_entity(entity_id) as Node3D
	if who == null:
		return
	var old: Label3D = _bubbles.get(entity_id) as Label3D
	if old != null and is_instance_valid(old):
		old.queue_free()
	var l := Label3D.new()
	l.name = "ChatBubble"
	l.text = text
	# Drawn as a nameplate is (`NameplateComponent`): in the world, at its scale, out to its range; but
	# over everything, so a tree's leaves never hide what was said (a playtest: one stood in a canopy).
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.pixel_size = 0.0045
	l.font_size = 40
	l.outline_size = 8
	l.modulate = Color(1.0, 1.0, 1.0, 0.95)
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	l.visibility_range_end = 40.0
	l.width = 480.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.position = Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	who.add_child(l)
	_bubbles[entity_id] = l
	var t: Tween = l.create_tween()
	t.tween_interval(BUBBLE_S)
	t.tween_property(l, ^"modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


# ---- for tests ----

## The lines on screen now, "name: text", oldest first.
func shown() -> PackedStringArray:
	var out := PackedStringArray()
	for id: int in _visible_ids():
		out.append("%s: %s" % [_lines[id]["name"], _lines[id]["text"]])
	return out


## What is over `entity_id`'s head now ("" for nothing).
func bubble_of(entity_id: int) -> String:
	var l: Label3D = _bubbles.get(entity_id) as Label3D
	return l.text if l != null and is_instance_valid(l) and not l.is_queued_for_deletion() else ""


func input_line() -> LineEdit:
	return _input
