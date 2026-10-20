extends "res://tests/suite_base.gd"
## The `ui_kit` suite (tests/test_runner.gd runs it; `-- --only=ui_kit` runs it alone).
## THE GAME'S LOOK (DECISIONS #265): one UiStyle draws every control (merged into the default theme, so a
## control under a CanvasLayer under a plain Node gets it too); a reskin is a different style file; the
## window frees the cursor, closes on Escape and on its button; the slot shows its count and initials.


func run() -> void:
	print("== ui kit: the game's look ==")
	var style: UiStyle = UiStyle.current()
	_check(style != null and style.panel_bg.is_equal_approx(Color(0.1, 0.12, 0.15, 0.96)),
		"with no umf/ui/style the game has the foundation's: the Escape menu's dark blue panel")
	UiStyle.apply()
	# A control the way a genre's HUD has one: under a CanvasLayer, under a plain Node.
	var holder := Node.new()
	add_child(holder)
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	var title := UiKit.heading("Bag")
	var b := Button.new()
	layer.add_child(title)
	layer.add_child(b)
	await get_tree().process_frame
	_check(title.get_theme_color(&"font_color").is_equal_approx(style.accent) and title.get_theme_font_size(&"font_size") == style.title_size,
		"a heading under a CanvasLayer under a plain Node is in the style's title look (%s)" % title.get_theme_color(&"font_color"))
	var normal: StyleBoxFlat = b.get_theme_stylebox(&"normal") as StyleBoxFlat
	_check(normal != null and normal.bg_color.is_equal_approx(style.button_bg), "and a button in the style's colour")
	# A reskin: a different file, everything follows.
	var gold := UiStyle.new()
	gold.accent = Color(0.95, 0.8, 0.35)
	gold.button_bg = Color(0.3, 0.2, 0.1)
	UiStyle.use(gold)
	await get_tree().process_frame
	_check(title.get_theme_color(&"font_color").is_equal_approx(gold.accent)
		and (b.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.is_equal_approx(gold.button_bg),
		"another style file reskins what is already on screen")
	UiStyle.use(style)
	var good_line: Label = UiKit.line("x", &"good")
	_check(UiKit.colour(&"bad").is_equal_approx(style.bad) and good_line.get_theme_color(&"font_color").is_equal_approx(style.good),
		"a line in a role's colour takes it from the style")
	good_line.free()
	# The window.
	var w := UiWindow.new()
	w.title = "Bag"
	layer.add_child(w)
	var opened: Array[bool] = []
	w.closed.connect(func() -> void: opened.append(false))
	w.open()
	await get_tree().process_frame
	_check(w.is_open() and MouseCapture.is_held_free(), "open: shown, and the cursor is free while it is")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	w._input(esc)
	_check(not w.is_open() and opened == [false] and not MouseCapture.is_held_free(), "Escape closes it (once), and the cursor is the game's again")
	w.open()
	(w.find_child("Close", true, false) as Button).pressed.emit()
	_check(not w.is_open() and opened.size() == 2, "its ✕ closes it too")
	var w2 := UiWindow.new()
	layer.add_child(w2)
	w.open()
	w2.open()
	w.close()
	_check(MouseCapture.is_held_free(), "two windows: closing one leaves the cursor free for the other")
	w2.close()
	_check(not MouseCapture.is_held_free(), "and closing both gives it back")
	# The slot.
	var s := UiSlot.new()
	layer.add_child(s)
	s.count = 1
	_check(s._count_label.text == "", "a slot of one shows no number")
	s.count = 12
	_check(s._count_label.text == "12" and UiSlot.initials("Copper ore") == "CO" and UiSlot.initials("Logs") == "Lo", "twelve shows 12; Copper ore is CO, Logs is Lo")
	s.tint = Color(0.8, 0.5, 0.3)
	s.selected = true
	_check((s.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color.is_equal_approx(style.slot_selected), "picked: the style's picked edge")
	s.selected = false
	_check((s.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color.is_equal_approx(Color(0.8, 0.5, 0.3)), "not: the item's own colour")
	# Its grade (#267): the edge is the grade's colour, thicker; none (or one the style lacks) is as before.
	s.grade = 2
	var graded: StyleBoxFlat = s.get_theme_stylebox(&"normal") as StyleBoxFlat
	_check(graded.border_color.is_equal_approx(style.grade_colors[2]) and graded.border_width_left == 2,
		"graded 2: the edge is the style's third grade colour, two wide")
	s.grade = 1
	_check((s.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color.is_equal_approx(style.grade_colors[1]), "graded 1: the second")
	s.selected = true
	var picked: StyleBoxFlat = s.get_theme_stylebox(&"normal") as StyleBoxFlat
	_check(picked.border_color.is_equal_approx(style.grade_colors[1]) and not picked.bg_color.is_equal_approx(style.slot_bg),
		"graded and picked: the grade's edge stays; the fill says it is picked")
	s.selected = false
	s.grade = 9
	var lacking: StyleBoxFlat = s.get_theme_stylebox(&"normal") as StyleBoxFlat
	_check(lacking.border_color.is_equal_approx(Color(0.8, 0.5, 0.3)) and lacking.border_width_left == 1, "a grade the style has no colour for: the item's own edge")
	s.grade = -1
	_check((s.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color.is_equal_approx(Color(0.8, 0.5, 0.3)), "no grade: the item's own again")
	# Icons drawn from a model (#271): where a piece's lives, none until drawn, nothing without a renderer.
	var melee: ContentDef = load("res://foundation/content/ability/melee.tres") as ContentDef
	_check(melee.rendered_icon_path() == "res://foundation/icons/ability_%d.png" % melee.id and melee.icon() == null and melee.icon_scene() == null,
		"a piece's drawn icon lives beside its content (%s); none until drawn" % melee.rendered_icon_path())
	_check(await IconRender.render(PackedScene.new(), self) == null, "no renderer (headless) or nothing to see: no picture")
	var gl: Label = UiKit.grade_line("Fine iron axe", 1)
	_check(gl.get_theme_color(&"font_color").is_equal_approx(style.grade_colors[1]), "a grade line: its name in the grade's colour")
	gl.free()
	holder.queue_free()
	await get_tree().process_frame
