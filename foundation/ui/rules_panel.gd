class_name RulesPanel extends PanelContainer
## THE HOT RULES, TUNED WHILE THE GAME RUNS (CONTENT_TOOLING_SPEC §4, DECISIONS #201): a page of the
## Escape menu, offered to the admin only. Every rule with its live value, its bounds and what it
## does; a change goes to the server (`set_rule`) and reaches every player at once. Reset puts a
## rule back to this build's default. What is set here lives ON THIS SERVER until reset; to make a
## tuning the game's default, use the Content dock's "Keep live tuning" in the editor.

signal closed

var _list: VBoxContainer
var _status: Label
var _rows: Dictionary = {}     # key -> { spin / check / edit, live: Label }
var _built: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(640, 460)
	HotRules.changed.connect(_on_changed)


func open() -> void:
	if not _built:
		_build()
	_refresh_all()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


## The keys the page lists (tests).
func listed_keys() -> Array:
	return _rows.keys()


func _build() -> void:
	_built = true
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Rules (admin) — live on THIS server, for every player"
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var keys: Array = HotRules.defaults().keys()
	keys.sort()
	for key: String in keys:
		_add_row(StringName(key), HotRules.defaults()[key])
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(close)
	box.add_child(back)


func _add_row(key: StringName, info: Dictionary) -> void:
	var entry: RuleEntry = info["entry"]
	var row := HBoxContainer.new()
	row.tooltip_text = entry.description
	_list.add_child(row)
	var name_label := Label.new()
	name_label.text = String(key)
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.tooltip_text = entry.description
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_label)
	var editor: Control
	match entry.kind:
		RuleEntry.Kind.FLAG:
			var c := CheckBox.new()
			c.toggled.connect(func(on: bool) -> void: _send(key, 1.0 if on else 0.0, ""))
			editor = c
		RuleEntry.Kind.TEXT:
			var e := LineEdit.new()
			e.custom_minimum_size = Vector2(200, 0)
			e.text_submitted.connect(func(t: String) -> void: _send(key, 0.0, t))
			editor = e
		_:
			var s := SpinBox.new()
			s.min_value = entry.minimum
			s.max_value = entry.maximum
			s.step = 1.0 if entry.kind == RuleEntry.Kind.INTEGER else maxf((entry.maximum - entry.minimum) / 1000.0, 0.001)
			s.suffix = entry.unit
			s.custom_minimum_size = Vector2(160, 0)
			s.get_line_edit().text_submitted.connect(func(_t: String) -> void: _send(key, s.value, ""))
			s.value_changed.connect(func(v: float) -> void:
				if not s.get_line_edit().has_focus():
					_send(key, v, ""))
			editor = s
	row.add_child(editor)
	var live := Label.new()
	live.custom_minimum_size = Vector2(120, 0)
	row.add_child(live)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Back to this build's default"
	reset.pressed.connect(func() -> void: _reset(key))
	row.add_child(reset)
	_rows[key] = {"editor": editor, "live": live, "entry": entry}


func _refresh_all() -> void:
	for key: StringName in _rows:
		_refresh(key)


func _refresh(key: StringName) -> void:
	var r: Dictionary = _rows[key]
	var entry: RuleEntry = r["entry"]
	var editor: Control = r["editor"]
	editor.set_block_signals(true)
	match entry.kind:
		RuleEntry.Kind.FLAG:
			(editor as CheckBox).button_pressed = HotRules.flag(key)
		RuleEntry.Kind.TEXT:
			(editor as LineEdit).text = HotRules.text(key)
		_:
			(editor as SpinBox).value = HotRules.number(key)
	editor.set_block_signals(false)
	(r["live"] as Label).text = "set by admin" if HotRules.is_overridden(key) else ("live" if HotRules.is_live(key) else "offline: default")


func _send(key: StringName, number: float, text: String) -> void:
	_status.text = "setting %s…" % key
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"set_rule", [String(key), number, text], ["string", "f64", "string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		_status.text = ("%s set" % key) if r.is_ok() else ("%s: %s" % [key, r.error_message])
		if is_instance_valid(self) and _rows.has(key):
			_refresh(key))


func _reset(key: StringName) -> void:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"reset_rule", [String(key)], ["string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		_status.text = ("%s back to the default" % key) if r.is_ok() else ("%s: %s" % [key, r.error_message]))


func _on_changed(key: StringName) -> void:
	if visible and _rows.has(key):
		_refresh(key)
