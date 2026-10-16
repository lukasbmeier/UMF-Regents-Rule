class_name FeedbackPage extends PanelContainer
## SEND FEEDBACK (DECISIONS #244, Luke 2026-10-15: "feedback that can be sent back in with their context
## of the game and timestamps"; "a point in time alert that brings more attention"). F8 at any moment, or
## Send feedback in the Escape menu: the moment is MARKED as the key is pressed (the server's time, and
## how the game was running then: `Telemetry.moment()`), then the player picks what it is about and
## writes, and `send_feedback` takes it to the host. The server adds who, where and in what part of the
## game from its own rows; the host's window says it arrived (`tools/host.sh`), `tools/feedback.sh`
## lists them.
##
## A page of the Escape menu (`PauseMenu.open_page`): `open`, `close`, `closed`. The player is held still
## while it is up, so writing does not walk them (the menu itself does not stop them).

signal closed

const ACTION: StringName = &"feedback"
const CATEGORIES: PackedStringArray = ["Bug", "Lag", "Idea", "Other"]
const STILL_REASON: StringName = &"feedback_page"

var _category: OptionButton = null
var _text: TextEdit = null
var _send: Button = null
var _said: Label = null
var _marked_usec: int = 0
var _context: Dictionary = {}
var _held: LocalInputComponent = null


func _ready() -> void:
	visible = false
	name = "FeedbackPage"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Send feedback"
	title.add_theme_font_size_override(&"font_size", 22)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "What happened just now? It goes to whoever hosts, with when and where it was."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_category = OptionButton.new()
	for c: String in CATEGORIES:
		_category.add_item(c)
	box.add_child(_category)
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 140)
	_text.placeholder_text = "The wolf went through the gate... / a lag spike as I jumped..."
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_text)
	_said = Label.new()
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_said)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_send = Button.new()
	_send.text = "Send"
	_send.pressed.connect(send)
	row.add_child(_send)


## The F8 key, given to every game (a project may bind it otherwise in its Input Map).
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F8
	InputMap.action_add_event(ACTION, key)


## MARK THE MOMENT: now, by the server's clock, and how the game was running. Called as the key is
## pressed, before the player writes a word.
func mark() -> void:
	_marked_usec = ClockSync.server_usec()
	_context = {"perf": SpaceTimeSync.telemetry.moment() if SpaceTimeSync.telemetry != null else {},
		"fps": Engine.get_frames_per_second(), "server_clock_synced": ClockSync.has_sync()}
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent if me != null else null
	if input != null:
		_context["look"] = [snappedf(input.get_look_yaw(), 0.01), snappedf(input.get_look_pitch(), 0.01)]


func marked_usec() -> int:
	return _marked_usec


func context() -> Dictionary:
	return _context


func open() -> void:
	if _marked_usec == 0:
		mark()
	_said.text = ""
	_send.disabled = false
	visible = true
	_text.grab_focus()
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	_held = me.find_component(LocalInputComponent) as LocalInputComponent if me != null else null
	if _held != null:
		_held.hold_still(STILL_REASON, true)


func close() -> void:
	visible = false
	_marked_usec = 0
	_text.text = ""
	if _held != null and is_instance_valid(_held):
		_held.hold_still(STILL_REASON, false)
	_held = null
	closed.emit()


## Send what they wrote with the moment marked. Thanks on screen when the host has it, and the page closes.
func send() -> ReducerRequest:
	var text: String = _text.text.strip_edges()
	if text.is_empty():
		_said.text = "Write a few words first."
		return null
	_send.disabled = true
	_said.text = "Sending..."
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"send_feedback", [_marked_usec, _category.selected, text,
		SpaceTimeSync.bindings_fingerprint(), Telemetry.platform(), JSON.stringify(_context)],
		["i64", "u8", "string", "string", "string", "string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if not is_inside_tree():
			return
		if r.is_ok():
			_said.text = "Sent. Thank you!"
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if visible:
					close())
		else:
			_send.disabled = false
			_said.text = "Not sent: " + r.error_message)
	return req


## For tests: what the page would send.
func set_message(category: int, text: String) -> void:
	_category.select(category)
	_text.text = text
