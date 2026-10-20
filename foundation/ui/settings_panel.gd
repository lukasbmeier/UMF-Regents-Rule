class_name SettingsPanel extends CenterContainer
## THE SETTINGS SCREEN (DECISIONS #165): one tab per `Settings` tab, one row per setting, drawn
## from the definitions, so a game's own settings appear here without anyone editing this file.
## A change applies and saves at once; there is no Apply button to forget.
##
## Opened from the Escape menu and from the connect screen (both build it with `SettingsPanel.new()`
## and call `open()`); `closed` says when the player is done. Escape closes it, unless a key is
## being rebound, when Escape cancels that.

signal closed()

const PANEL_SIZE: Vector2 = Vector2(560, 470)

var _tabs: TabContainer = null
## Per setting key, the control that shows it, refreshed when the value changes elsewhere (F11).
var _controls: Dictionary[StringName, Control] = {}
var _notes: Dictionary[StringName, Label] = {}
## The action waiting for a key, or &"".
var _listening: StringName = &""
var _built: bool = false


func _init() -> void:
	name = "SettingsPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	Settings.changed.connect(_on_changed)


## Show it, built fresh from the definitions (a game may have added some since).
func open() -> void:
	_build()
	visible = true
	var first: Control = _first_control()
	if first != null:
		first.grab_focus()


func close() -> void:
	if not visible:
		return
	_stop_listening()
	visible = false
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	closed.emit()


func is_open() -> bool:
	return visible


## The action a press would rebind now, or &"" (tests).
func listening() -> StringName:
	return _listening


## The control drawn for a setting (tests drive it like a player).
func control_for(key: StringName) -> Control:
	return _controls.get(key)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening != &"":
		var key: InputEventKey = event as InputEventKey
		var button: InputEventMouseButton = event as InputEventMouseButton
		if key != null and key.pressed and not key.echo:
			get_viewport().set_input_as_handled()
			if key.keycode == KEY_ESCAPE:
				_stop_listening()
			else:
				_take(Settings.event_to_text(key))
		elif button != null and button.pressed:
			get_viewport().set_input_as_handled()
			_take(Settings.event_to_text(button))
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# --- building --------------------------------------------------------------------------------

func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_controls.clear()
	_notes.clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override(&"font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for tab: String in Settings.tabs():
		_tabs.add_child(_build_tab(tab))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	box.add_child(buttons)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Reset this tab"
	reset.custom_minimum_size = Vector2(0, 34)
	reset.pressed.connect(func() -> void:
		Settings.reset(_tabs.get_tab_title(_tabs.current_tab))
		_refresh_all())
	buttons.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 34)
	back.pressed.connect(close)
	buttons.add_child(back)
	var where := Label.new()
	where.text = "Saved on this computer%s." % ("" if Settings.path().is_empty()
		else " (%s)" % ProjectSettings.globalize_path(Settings.path()))
	where.modulate = Color(1, 1, 1, 0.45)
	where.add_theme_font_size_override(&"font_size", 11)
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(where)
	_built = true


func _build_tab(tab: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tab
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(pad)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(grid)
	for e: Dictionary in Settings.entries(tab):
		var label := Label.new()
		label.text = String(e["label"])
		label.tooltip_text = String(e["tooltip"])
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		grid.add_child(_build_control(e))
	return scroll


func _build_control(e: Dictionary) -> Control:
	var key: StringName = e["key"]
	var c: Control = null
	match int(e["kind"]):
		Settings.Kind.TOGGLE:
			var t := CheckButton.new()
			t.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
			c = t
		Settings.Kind.SLIDER:
			var row := HBoxContainer.new()
			var s := HSlider.new()
			s.name = "Slider"
			s.min_value = float(e["min"])
			s.max_value = float(e["max"])
			s.step = float(e["step"])
			s.custom_minimum_size = Vector2(170, 0)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var shown := Label.new()
			shown.name = "Value"
			shown.custom_minimum_size = Vector2(56, 0)
			shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			s.value_changed.connect(func(v: float) -> void:
				shown.text = _format(e, v)
				Settings.set_value(key, v))
			row.add_child(s)
			row.add_child(shown)
			c = row
		Settings.Kind.CHOICE:
			var o := OptionButton.new()
			for choice: String in e["choices"] as PackedStringArray:
				o.add_item(choice)
			o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
			c = o
		Settings.Kind.KEY:
			var row := HBoxContainer.new()
			var b := Button.new()
			b.name = "Bind"
			b.custom_minimum_size = Vector2(150, 0)
			b.pressed.connect(func() -> void: _listen(key))
			var note := Label.new()
			note.name = "Note"
			note.modulate = Color(1.0, 0.75, 0.45)
			note.add_theme_font_size_override(&"font_size", 11)
			row.add_child(b)
			row.add_child(note)
			_notes[key] = note
			c = row
	c.name = String(key)
	c.tooltip_text = String(e["tooltip"])
	_controls[key] = c
	_refresh(key)
	return c


# --- showing values --------------------------------------------------------------------------

func _refresh_all() -> void:
	for key: StringName in _controls:
		_refresh(key)


func _refresh(key: StringName) -> void:
	var c: Control = _controls.get(key)
	var e: Dictionary = Settings.entry(key)
	if c == null or e.is_empty():
		return
	var v: Variant = Settings.get_value(key)
	match int(e["kind"]):
		Settings.Kind.TOGGLE:
			(c as CheckButton).set_pressed_no_signal(bool(v))
		Settings.Kind.SLIDER:
			(c.get_node(^"Slider") as HSlider).set_value_no_signal(float(v))
			(c.get_node(^"Value") as Label).text = _format(e, float(v))
		Settings.Kind.CHOICE:
			(c as OptionButton).select(int(v))
		Settings.Kind.KEY:
			var b: Button = c.get_node(^"Bind") as Button
			b.text = "Press a key…  (Esc cancels)" if _listening == key else Settings.binding_label(String(v))
			var clash: PackedStringArray = Settings.clashes(key, String(v))
			(_notes[key] as Label).text = "" if clash.is_empty() else "also " + ", ".join(clash)


func _format(e: Dictionary, v: float) -> String:
	var f: String = String(e["format"])
	if f.is_empty():
		return str(snappedf(v, float(e["step"])))
	return f % (roundi(v) if f.contains("%d") else v)


func _on_changed(key: StringName, _value: Variant) -> void:
	if visible:
		_refresh(key)
		if Settings.entry(key).get("kind", -1) == Settings.Kind.KEY:
			_refresh_all()   # a clash note elsewhere may have appeared or gone


# --- rebinding -------------------------------------------------------------------------------

func _listen(action: StringName) -> void:
	var was: StringName = _listening
	_listening = action
	if was != &"":
		_refresh(was)
	_refresh(action)


func _take(text: String) -> void:
	var action: StringName = _listening
	_listening = &""
	if not text.is_empty():
		Settings.set_value(action, text)
	_refresh_all()


func _stop_listening() -> void:
	var was: StringName = _listening
	_listening = &""
	if was != &"":
		_refresh(was)


func _first_control() -> Control:
	if _tabs == null or _tabs.get_tab_count() == 0:
		return null
	return _tabs.get_tab_bar()


## The game's panel (`UiStyle`, DECISIONS #265): the Escape menu's, and every window's.
static func _panel_style() -> StyleBoxFlat:
	return UiStyle.current().panel_style()
