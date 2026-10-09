@tool
class_name ContentDock extends VBoxContainer
## THE CONTENT DOCK (docs/CONTENT_TOOLING_SPEC.md §2, DECISIONS #200): the editor's bottom panel
## for content. Left, every content type with its count and a red mark when something is wrong;
## middle, that type's pieces (search, New); right, the chosen piece (it opens in the Inspector,
## which is the content editor) and its workbench when it has one. Above, the toolbar: Validate,
## Bake, Publish, Play, and whatever a later step adds (`model.add_action`). Below, what was said.
##
## It draws `ContentDockModel` and passes clicks to it; anything that needs the editor itself goes
## through `bridge` (`ContentDockBridge`), so the dock is built and clicked in a headless test.

var model: ContentDockModel = null
var bridge: ContentDockBridge = null

var _types: ItemList
var _items: ItemList
var _search: LineEdit
var _owner: OptionButton
var _new_name: LineEdit
var _new_button: Button
var _title: Label
var _detail: Label
var _workbench: Button
var _show_file: Button
var _toolbar: HBoxContainer
var _status: Label
var _log: RichTextLabel
var _type_order: Array[StringName] = []
var _item_paths: Array[String] = []
var _selected_path: String = ""
var _task: ProjectTask = null


## Build it. `bridge` defaults to one that does nothing (tests).
func setup(m: ContentDockModel = null, b: ContentDockBridge = null) -> void:
	model = m if m != null else ContentDockModel.new()
	bridge = b if b != null else ContentDockBridge.new()
	if model.actions.is_empty():
		model.add_action(&"validate", "Validate", "Check every piece of content, as the bake will", validate)
		model.add_action(&"bake", "Bake", "Write the content the server compiles in (shared/content/)", bake)
		model.add_action(&"publish", "Publish", "tools/publish.sh: bake, build, publish this game's database (keeps its data)", publish)
		model.add_action(&"play", "Play", "Run the game (Debug > Customize Run Instances sets how many)", func() -> void: bridge.play())
		model.add_action(&"keep_live", "Keep live tuning", "Make the rule values an admin set on this game's server (the Rules page in game) this game's defaults: they are written into the rule sets; then Bake or Publish", keep_live_tuning)
	_build()
	refresh()


## Redraw from the files (after a save, a new piece, a bake).
func refresh() -> void:
	var keep_type: StringName = selected_type()
	_types.clear()
	_type_order.clear()
	for row: Dictionary in model.type_rows():
		var label: String = "%s  (%d)%s" % [row["type"], row["count"], "" if String(row["owner"]).is_empty() else "  · " + String(row["owner"])]
		var i: int = _types.add_item(label)
		if int(row["problems"]) > 0:
			_types.set_item_custom_fg_color(i, Color(1.0, 0.45, 0.4))
			_types.set_item_text(i, label + "  ⚠ %d" % row["problems"])
		_type_order.append(row["type"])
	var at: int = _type_order.find(keep_type)
	if at < 0 and not _type_order.is_empty():
		at = 0
	if at >= 0:
		_types.select(at)
	_refresh_items()


func selected_type() -> StringName:
	var sel: PackedInt32Array = _types.get_selected_items() if _types != null else PackedInt32Array()
	return _type_order[sel[0]] if not sel.is_empty() and sel[0] < _type_order.size() else &""


## The pieces listed now, as paths (for tests and the toolbar).
func listed_paths() -> Array[String]:
	return _item_paths.duplicate()


## Choose a piece: it opens in the Inspector.
func select_path(path: String) -> void:
	var at: int = _item_paths.find(path)
	if at >= 0:
		_items.select(at)
	_select(path)


func validate() -> void:
	var found: Array[Dictionary] = model.check()
	_say("Validate: %s" % ("everything is fine" if found.is_empty() else "%d problem(s)" % found.size()))
	_say_problems(found)
	if found.is_empty() and not model.stale.is_empty():
		_say("  the bake is out of date (%s): Bake, or Publish" % ", ".join(model.stale))
	refresh()


func bake() -> void:
	var r: Dictionary = model.bake()
	if bool(r["ok"]):
		for l: String in r["summary"] as Array:
			_say(l)
	else:
		_say("Bake refused: nothing was written")
		_say_problems(r["problems"])
	bridge.files_changed()
	refresh()


func publish() -> void:
	if _task != null and _task.is_running():
		_say("Publish is already running")
		return
	_task = ProjectTask.new()
	_task.line.connect(func(t: String) -> void: _say("  " + t))
	_task.finished.connect(func(code: int) -> void:
		_say("Publish %s" % ("done" if code == 0 else "FAILED (exit %d): see above" % code))
		_status.text = ""
		bridge.files_changed()
		refresh())
	_say("Publish: tools/publish.sh (bake, build, publish; keeps the data)")
	if _task.start("tools/publish.sh"):
		_status.text = "publishing…"


func keep_live_tuning() -> void:
	if _task != null and _task.is_running():
		_say("Wait for the running task to finish")
		return
	var lines := PackedStringArray()
	_task = ProjectTask.new()
	_task.line.connect(func(t: String) -> void: lines.append(t))
	_task.finished.connect(func(code: int) -> void:
		_status.text = ""
		if code != 0:
			_say("Keep live tuning: could not read the server (is it running?)")
			for l: String in lines:
				_say("  " + l)
			return
		var rows: Array[Dictionary] = ContentDockModel.parse_live(lines)
		if rows.is_empty():
			_say("Keep live tuning: no rule was changed on the server (%s)" % (lines[0] if not lines.is_empty() else ""))
			return
		var r: Dictionary = model.keep_live(rows)
		_say("Keep live tuning: %d kept" % (r["kept"] as Array).size())
		for k: String in r["kept"] as Array:
			_say("  " + k)
		for p: String in r["problems"] as Array:
			_say("  ⚠ " + p)
		_say("  Publish to make them the defaults; then Reset them in the game's Rules page (or leave them: they now equal the defaults).")
		bridge.files_changed()
		refresh())
	if _task.start("tools/rules_live.sh"):
		_status.text = "reading the server's rules…"


func _process(_delta: float) -> void:
	if _task != null and _task.is_running():
		_task.poll()


func _build() -> void:
	for c: Node in get_children():
		c.queue_free()
	custom_minimum_size = Vector2(0, 220)
	_toolbar = HBoxContainer.new()
	add_child(_toolbar)
	for a: Dictionary in model.actions:
		var b := Button.new()
		b.text = a["label"]
		b.tooltip_text = a["tooltip"]
		b.name = "Action_" + String(a["id"])
		b.pressed.connect(a["run"] as Callable)
		_toolbar.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)
	_status = Label.new()
	_toolbar.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_types = ItemList.new()
	_types.name = "Types"
	_types.custom_minimum_size = Vector2(180, 0)
	_types.item_selected.connect(func(_i: int) -> void: _refresh_items())
	split.add_child(_types)

	var right := HSplitContainer.new()
	split.add_child(right)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(260, 0)
	right.add_child(middle)
	_search = LineEdit.new()
	_search.placeholder_text = "search: name, id or file"
	_search.text_changed.connect(func(_t: String) -> void: _refresh_items())
	middle.add_child(_search)
	_items = ItemList.new()
	_items.name = "Items"
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.item_selected.connect(func(i: int) -> void: _select(_item_paths[i]))
	middle.add_child(_items)
	var new_row := HBoxContainer.new()
	middle.add_child(new_row)
	_owner = OptionButton.new()
	_owner.tooltip_text = "Who it belongs to: the foundation (every game has it) or a genre"
	new_row.add_child(_owner)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "name"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_name.text_submitted.connect(func(_t: String) -> void: _create())
	new_row.add_child(_new_name)
	_new_button = Button.new()
	_new_button.text = "New"
	_new_button.name = "New"
	_new_button.tooltip_text = "Make a piece of this type with the next free id, in its folder"
	_new_button.pressed.connect(_create)
	new_row.add_child(_new_button)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(detail)
	_title = Label.new()
	_title.text = "Choose a piece: it opens in the Inspector"
	detail.add_child(_title)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail)
	var buttons := HBoxContainer.new()
	detail.add_child(buttons)
	_workbench = Button.new()
	_workbench.text = "Open workbench"
	_workbench.tooltip_text = "Where this piece is made and tested against the real animations and level (a workbench)"
	_workbench.disabled = true
	_workbench.pressed.connect(func() -> void: bridge.open_scene(_workbench_of(_selected_path)))
	buttons.add_child(_workbench)
	_show_file = Button.new()
	_show_file.text = "Show in FileSystem"
	_show_file.disabled = true
	_show_file.pressed.connect(func() -> void: bridge.show_file(_selected_path))
	buttons.add_child(_show_file)
	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.meta_clicked.connect(func(meta: Variant) -> void: select_path(String(meta)))
	detail.add_child(_log)


func _refresh_items() -> void:
	var type: StringName = selected_type()
	_items.clear()
	_item_paths.clear()
	for row: Dictionary in model.item_rows(type, _search.text):
		var def: ContentDef = row["def"]
		var i: int = _items.add_item("%d  %s%s" % [def.id, def.display_name, "" if row["owner"] == ContentLibrary.FOUNDATION else "  · " + String(row["owner"])])
		if int(row["problems"]) > 0:
			_items.set_item_custom_fg_color(i, Color(1.0, 0.45, 0.4))
		_items.set_item_tooltip(i, String(row["path"]))
		_item_paths.append(row["path"])
	var keep: String = _owner.get_item_text(_owner.selected) if _owner.selected >= 0 else ""
	_owner.clear()
	for o: String in model.owners_for(type):
		_owner.add_item(o)
	var at: int = -1
	for i: int in _owner.item_count:
		if _owner.get_item_text(i) == keep:
			at = i
	if at < 0 and _owner.item_count > 0:
		at = _owner.item_count - 1   # a genre before the foundation: most new content is a genre's
	if at >= 0:
		_owner.select(at)
	_new_button.disabled = type == &""
	var still: int = _item_paths.find(_selected_path)
	if still >= 0:
		_items.select(still)


func _select(path: String) -> void:
	_selected_path = path
	var def: ContentDef = load(path) as ContentDef if ResourceLoader.exists(path) else null
	_title.text = "%s  %d  %s" % [def.content_type(), def.id, def.display_name] if def != null else path
	var lines: PackedStringArray = PackedStringArray([path])
	for p: Dictionary in model.problems_for(path):
		lines.append("⚠ " + String(p["text"]))
	_detail.text = "\n".join(lines)
	_workbench.disabled = _workbench_of(path).is_empty()
	_show_file.disabled = path.is_empty()
	if def != null:
		bridge.edit(def)


func _workbench_of(path: String) -> String:
	var def: ContentDef = load(path) as ContentDef if ResourceLoader.exists(path) else null
	var scene: String = def.workbench_scene() if def != null else ""
	return scene if not scene.is_empty() and ResourceLoader.exists(scene) else ""


func _create() -> void:
	var type: StringName = selected_type()
	if type == &"" or _owner.selected < 0:
		return
	var errors: Array[String] = []
	var path: String = model.create(type, _owner.get_item_text(_owner.selected), _new_name.text, errors)
	if path.is_empty():
		_say("New: " + "; ".join(errors))
		return
	_new_name.text = ""
	_say("New: %s" % path)
	bridge.files_changed()
	refresh()
	select_path(path)


func _say_problems(found: Array) -> void:
	for p: Dictionary in found:
		var path: String = p["path"]
		if path.is_empty():
			_say("  ⚠ " + String(p["text"]))
		else:
			_log.append_text("  ⚠ [url=%s]%s[/url]: %s\n" % [path, path.trim_prefix("res://"), String(p["text"]).replace("[", "[lb]")])


func _say(text: String) -> void:
	_log.append_text(text.replace("[", "[lb]") + "\n")


## The text in the dock's log (tests).
func log_text() -> String:
	return _log.get_parsed_text()
