class_name CatchJournal extends CenterContainer
## GENRE UI. THE CATCH JOURNAL (DECISIONS #171): every kind in the catalogue, what you have caught
## of each (how many, the biggest, the best paid) and what you have not, with the rarities still
## missing; and the RECORDS: the biggest of each kind anyone here has landed, and the anglers by
## what their catches have earned, all time. Read from `FishingRecords`, which reads the components.
##
## A page of the Escape menu (`PauseMenu.open_page`): the HUD adds a Journal button there and opens
## it with J. Escape or Back closes it.

signal closed()

const PANEL_SIZE: Vector2 = Vector2(640, 520)
const UNKNOWN: String = "???"

var _tabs: TabContainer = null


func _init() -> void:
	name = "CatchJournal"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	_build()
	visible = true
	(find_child("Back", true, false) as Button).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override(&"panel", SettingsPanel._panel_style())
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override(&"font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_tabs.add_child(_journal_tab())
	_tabs.add_child(_records_tab())
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 34)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(close)
	box.add_child(back)


func _journal_tab() -> Control:
	var rows: Array[Dictionary] = FishingRecords.journal(_local_fishing())
	var page := VBoxContainer.new()
	page.name = "My catches"
	var missing: PackedStringArray = FishingRecords.missing(rows)
	var summary := Label.new()
	summary.name = "Summary"
	summary.text = "%d of %d kinds caught%s" % [FishingRecords.kinds_caught(rows), rows.size(),
		"" if missing.is_empty() else "  ·  still to find: " + ", ".join(missing)]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(summary)
	var grid: GridContainer = _grid(["", "Kind", "Caught", "Biggest", "Best paid"])
	grid.name = "Grid"
	var last_word: String = ""
	for r: Dictionary in rows:
		var caught: bool = int(r["count"]) > 0
		var word: String = str(r["word"])
		_cell(grid, word.capitalize() if word != last_word else "", Color(1, 1, 1, 0.5))
		last_word = word
		_cell(grid, str(r["name"]) if caught else UNKNOWN, _rarity_colour(int(r["rarity"])) if caught else Color(1, 1, 1, 0.35))
		_cell(grid, str(r["count"]) if caught else "–")
		_cell(grid, "%.2f kg" % float(r["best_kg"]) if caught else "–")
		_cell(grid, "%d" % int(r["best_coins"]) if caught else "–")
	page.add_child(_scrolled(grid))
	return page


func _records_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Records"
	var head := Label.new()
	head.text = "The biggest of each, by anyone here, ever"
	page.add_child(head)
	var big: GridContainer = _grid(["Kind", "Weight", "Landed by"])
	big.name = "Biggest"
	var biggest: Array[Dictionary] = FishingRecords.biggest()
	for r: Dictionary in biggest:
		var mine: Color = Color(0.7, 1.0, 0.75) if bool(r["is_local"]) else Color.WHITE
		_cell(big, str(r["name"]), _rarity_colour(FishingData.rarity_of(str(r["key"]))))
		_cell(big, "%.2f kg" % float(r["kg"]))
		_cell(big, str(r["who"]), mine)
	if biggest.is_empty():
		_cell(big, "Nothing landed yet.")
		_cell(big, "")
		_cell(big, "")
	var lower := VBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_child(_scrolled(big))
	var head2 := Label.new()
	head2.text = "Anglers, by what their catches have paid"
	lower.add_child(head2)
	var who: GridContainer = _grid(["", "Angler", "Catches", "Coins", "Best catch"])
	who.name = "Anglers"
	var rank: int = 0
	for a: Dictionary in FishingRecords.anglers():
		rank += 1
		var mine: Color = Color(0.7, 1.0, 0.75) if bool(a["is_local"]) else Color.WHITE
		_cell(who, FishingStandings.ordinal(rank), Color(1, 1, 1, 0.6))
		_cell(who, str(a["name"]), mine)
		_cell(who, str(a["catches"]))
		_cell(who, str(a["coins"]))
		_cell(who, "%s (%.1f kg)" % [str(FishingData.catch_def(str(a["best_key"])).get("name", "")), float(a["best_kg"])])
	lower.add_child(_scrolled(who))
	page.add_child(lower)
	return page


func _local_fishing() -> FishingComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	return ent.find_component(FishingComponent) as FishingComponent if ent != null else null


func _grid(headers: Array[String]) -> GridContainer:
	var g := GridContainer.new()
	g.columns = headers.size()
	g.add_theme_constant_override(&"h_separation", 18)
	g.add_theme_constant_override(&"v_separation", 4)
	for h: String in headers:
		_cell(g, h, Color(0.75, 0.85, 1.0))
	return g


func _cell(g: GridContainer, text: String, colour: Color = Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = colour
	g.add_child(l)


func _scrolled(c: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 150)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.add_child(c)
	return s


## The HUD's rarity colours: trash grey, decent white, good green, strange blue, illegal gold.
static func _rarity_colour(rarity: int) -> Color:
	match rarity:
		0: return Color(0.8, 0.8, 0.8)
		1: return Color(1.0, 1.0, 1.0)
		2: return Color(0.55, 1.0, 0.55)
		3: return Color(0.55, 0.75, 1.0)
		_: return Color(1.0, 0.82, 0.35)
