@tool
class_name WorkbenchPanel extends VBoxContainer
## THE WORKBENCH PANEL (WORKBENCHES 2, DECISIONS #207), beside the Inspector: the controls of the
## workbench that is open. Luke, testing the first benches: the piece's fields were folded inside
## the bench's `item` in the Inspector, so it was never clear what was being changed. Now the
## INSPECTOR SHOWS THE PIECE (every field its own) and this panel shows the BENCH:
##
##   the piece      its name, type and owner, its badge (green / amber / red, and why), the others of
##                  its type to step to, and "Edit in Inspector"
##   tests          one button each, saying what it plays (tooltip)
##   settings       the bench's own (`Workbench.controls()`): which animation, which look, which
##                  character it is tried on, how fast to replay
##   actions        the bench's own, then Play as this, Save, New from this, Copy into a genre
##   what happened  the last test's sentence, and the bench's status
##
## It draws what the bench declares and passes clicks back, so a new bench needs no panel code.
## Anything needing the editor goes through `bridge`, and Play through `dock` (to publish first), so
## the panel is built and clicked in the `workbench` suite.

var bridge: ContentDockBridge = null
## The Content dock, for Play as this (it publishes first when the content changed). May be null.
var dock: ContentDock = null
var bench: Workbench = null

var _title: Label
var _badge: Label
var _pieces: OptionButton
var _piece_list: Array[ContentDef] = []
var _tests: HFlowContainer
var _controls: GridContainer
var _actions: HFlowContainer
var _result: Label
var _redraw_queued: bool = false
## The pieces benches were opened FROM (a character, then its movement): "Back" returns to the last.
var _came_from: Array[ContentDef] = []
var _back: Button
## The settings drawn now, without their values (`_shape_of`).
var _shape: String = ""
const BADGE_COLOURS: Dictionary = {"red": Color(1.0, 0.42, 0.38), "amber": Color(1.0, 0.78, 0.3), "green": Color(0.45, 0.85, 0.5)}


func setup(b: ContentDockBridge = null, d: ContentDock = null) -> void:
	bridge = b if b != null else ContentDockBridge.new()
	dock = d
	_build()
	show_bench(null)


## Show `b`'s controls (null: say how to open one).
func show_bench(b: Workbench) -> void:
	if bench != null and is_instance_valid(bench) and bench.panel_changed.is_connected(_queue_redraw):
		bench.panel_changed.disconnect(_queue_redraw)
	bench = b
	_shape = ""
	# Back on the bench a later one was reached from (by Back, or its tab): that step is done.
	if bench != null and bench.item != null and not _came_from.is_empty() and _came_from.back() == bench.item:
		_came_from.pop_back()
	if bench != null:
		bench.panel_changed.connect(_queue_redraw)
	redraw()


## Draw everything again from the bench. When the bench's settings are the same ones as before (only
## their values moved: a number being dragged), they are updated in place rather than rebuilt, so a
## field being edited keeps its focus.
func redraw() -> void:
	_redraw_queued = false
	for box: Node in [_tests, _actions]:
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var on: bool = bench != null and is_instance_valid(bench)
	var wanted: Array[Dictionary] = []
	if on:
		wanted = bench.controls()
	var shape: String = _shape_of(wanted)
	if shape == _shape and on:
		_update_values(wanted)
	else:
		_shape = shape
		for c: Node in _controls.get_children():
			_controls.remove_child(c)
			c.queue_free()
		for c: Dictionary in wanted:
			_add_control(c)
	_pieces.visible = on
	if not on:
		_back.visible = false
		_title.text = "No workbench open"
		_badge.text = "Content panel (bottom): choose a piece, then Open workbench."
		_badge.remove_theme_color_override(&"font_color")
		_result.text = ""
		return
	var def: ContentDef = bench.item
	_back.visible = not _came_from.is_empty()
	if _back.visible:
		_back.text = "← Back to %s (%s)" % [_came_from.back().display_name, _came_from.back().content_type()]
	_title.text = "%s workbench%s" % [String(bench.content_type()).capitalize(),
		"" if def == null else "  ·  %s (%s %d, %s)" % [def.display_name, def.content_type(), def.id, ContentLibrary.owner_of_path(def.resource_path)]]
	var b: Dictionary = bench.badge()
	_badge.text = String(b["level"]).to_upper() + ("" if (b["sentences"] as Array).is_empty() else ": " + "; ".join(b["sentences"] as Array))
	if bench.read_only_here():
		_badge.text += "
The template's piece: read-only in this game. Copy into a genre to change it."
	_badge.add_theme_color_override(&"font_color", BADGE_COLOURS.get(b["level"], Color.WHITE))
	_fill_pieces()
	for t: StringName in bench.test_actions():
		_button(_tests, "Test_" + String(t), bench.test_label(t), bench.test_info(t), press_test.bind(t))
	for a: Dictionary in bench.actions():
		_button(_actions, "Action_" + String(a["name"]).replace(":", "_"), String(a["label"]), String(a.get("tooltip", "")), press_action.bind(StringName(a["name"])))
	_result.text = bench.last_result


## What the settings are, without their values: the same shape is updated in place.
static func _shape_of(cs: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for c: Dictionary in cs:
		parts.append("%s|%s|%s|%s" % [c.get("name", ""), c.get("kind", ""), c.get("label", ""), str((c.get("options", []) as Array).map(func(o: Variant) -> String: return str(o[1]) if o is Array else str(o)))])
	return "
".join(parts)


func _update_values(cs: Array[Dictionary]) -> void:
	for c: Dictionary in cs:
		var ed: Control = control(StringName(c.get("name", "")))
		if ed == null or ed.has_focus():
			continue
		ed.set_block_signals(true)
		if ed is SpinBox:
			(ed as SpinBox).value = float(c.get("value", 0.0))
		elif ed is CheckBox:
			(ed as CheckBox).button_pressed = bool(c.get("value", false))
		ed.set_block_signals(false)


## Run a test, as its button does.
func press_test(t: StringName) -> void:
	if bench == null:
		return
	await bench.run_named_test(t)
	redraw()


## Press an action, as its button does, and do what it asks of the editor.
func press_action(a: StringName) -> void:
	if bench == null:
		return
	var asked: Dictionary = bench.do_action(a)
	if asked.has("edit"):
		bridge.edit(asked["edit"] as Resource)
	if asked.has("play"):
		play(asked["play"] as PackedStringArray)
	if asked.has("open"):
		var other: ContentDef = asked["open"] as ContentDef
		if other != null and not other.workbench_scene().is_empty():
			if bench.item != null and not _came_from.has(bench.item):
				_came_from.append(bench.item)
			bridge.open_workbench(other.workbench_scene(), other)
	redraw()


## Change a setting, as its control does.
func set_control(n: StringName, value: Variant) -> void:
	if bench != null:
		bench.set_control(n, value)
		_queue_redraw()


## PLAY AS THIS: the game, run with `args`. Through the Content dock when there is one: content
## that changed since the bake is published first (the server must know a new character's speed,
## an ability's range), then the game runs.
func play(args: PackedStringArray) -> void:
	if dock != null:
		dock.play_fresh(args)
	else:
		bridge.play(args)


## BACK to the piece the open bench was reached from (its own bench).
func go_back() -> void:
	if _came_from.is_empty():
		return
	var to: ContentDef = _came_from.pop_back()
	if to != null and not to.workbench_scene().is_empty():
		bridge.open_workbench(to.workbench_scene(), to)


## The piece of `index` in the bench's list (the dropdown).
func choose_piece(index: int) -> void:
	if bench == null or index < 0 or index >= _piece_list.size():
		return
	bench.item = _piece_list[index]
	bridge.edit(_piece_list[index])


## The labels of the buttons now shown (tests).
func button_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for box: Node in [_tests, _actions]:
		for c: Node in box.get_children():
			if c is Button:
				out.append((c as Button).text)
	return out


## The control named `n` (tests), or null.
func control(n: StringName) -> Control:
	return _controls.get_node_or_null(NodePath("Control_" + String(n))) as Control


func _queue_redraw() -> void:
	if not _redraw_queued:
		_redraw_queued = true
		redraw.call_deferred()


func _fill_pieces() -> void:
	_pieces.clear()
	_piece_list = bench.items()
	var at: int = -1
	for i: int in _piece_list.size():
		var d: ContentDef = _piece_list[i]
		_pieces.add_item("%d  %s  · %s" % [d.id, d.display_name, ContentLibrary.owner_of_path(d.resource_path)], i)
		if d == bench.item or (bench.item != null and d.resource_path == bench.item.resource_path):
			at = i
	if at >= 0:
		_pieces.select(at)


func _add_control(c: Dictionary) -> void:
	var n: StringName = StringName(c.get("name", ""))
	var kind: String = String(c.get("kind", "choice"))
	var label := Label.new()
	label.text = String(c.get("label", n))
	label.tooltip_text = String(c.get("tooltip", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if kind == "heading":
		label.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
		_controls.add_child(label)
		var note := Label.new()
		note.text = String(c.get("value", ""))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_controls.add_child(note)
		return
	_controls.add_child(label)
	var editor: Control
	match kind:
		"number":
			var spin := SpinBox.new()
			spin.min_value = float(c.get("min", 0.0))
			spin.max_value = float(c.get("max", 1.0))
			spin.step = float(c.get("step", 0.01))
			spin.value = float(c.get("value", 0.0))
			spin.value_changed.connect(func(v: float) -> void: set_control(n, v))
			editor = spin
		"toggle":
			var check := CheckBox.new()
			check.button_pressed = bool(c.get("value", false))
			check.toggled.connect(func(v: bool) -> void: set_control(n, v))
			editor = check
		_:
			var opt := OptionButton.new()
			var values: Array = []
			for o: Variant in c.get("options", []) as Array:
				var pair: Array = o if o is Array else [o, o]
				opt.add_item(String(pair[1]))
				values.append(pair[0])
				if pair[0] == c.get("value"):
					opt.select(opt.item_count - 1)
			opt.item_selected.connect(func(i: int) -> void: set_control(n, values[i]))
			editor = opt
	editor.name = "Control_" + String(n)
	editor.tooltip_text = String(c.get("tooltip", ""))
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls.add_child(editor)


func _button(box: Container, node_name: String, text: String, tip: String, on_press: Callable) -> void:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	box.add_child(b)


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6))
	add_child(l)


func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	custom_minimum_size = Vector2(260, 200)
	_back = Button.new()
	_back.name = "Back"
	_back.visible = false
	_back.tooltip_text = "Back to the bench this one was opened from"
	_back.pressed.connect(go_back)
	add_child(_back)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_badge = Label.new()
	_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_badge)
	var nav := HBoxContainer.new()
	add_child(nav)
	_pieces = OptionButton.new()
	_pieces.name = "Pieces"
	_pieces.tooltip_text = "Every piece of this type: choose one to put it on the bench"
	_pieces.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pieces.item_selected.connect(choose_piece)
	nav.add_child(_pieces)
	var edit := Button.new()
	edit.text = "Edit in Inspector"
	edit.tooltip_text = "Show the piece's fields in the Inspector: what you change there is the piece"
	edit.pressed.connect(func() -> void:
		if bench != null and bench.item != null:
			bridge.edit(bench.item))
	nav.add_child(edit)
	_section("Tests")
	_tests = HFlowContainer.new()
	_tests.name = "Tests"
	add_child(_tests)
	_section("Settings")
	_controls = GridContainer.new()
	_controls.name = "Controls"
	_controls.columns = 2
	add_child(_controls)
	_section("Actions")
	_actions = HFlowContainer.new()
	_actions.name = "Actions"
	add_child(_actions)
	_result = Label.new()
	_result.name = "Result"
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_result)
