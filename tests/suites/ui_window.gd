extends "res://tests/suite_base.gd"
## The `ui_window` suite (tests/test_runner.gd runs it; `-- --only=ui_window` runs it alone).
## WINDOWS THAT RESIZE AND REMEMBER (DECISIONS #310): which edge a press is on; a resize, never below what the
## window holds and never off the screen; a drag kept on the screen; where it was left and its size remembered
## per window and restored when one opens again (and from the settings file); a window that is not resizable or
## not remembered; a double-click on the bar puts it back; the setting that forgets them all.

const PLACES_FILE: String = "user://test_window_places.cfg"
const SCREEN: Vector2 = Vector2(1280, 720)

var _view: SubViewport = null


func run() -> void:
	Settings.use_defaults()
	_run_rules()
	await _run_windows()
	_run_file()
	Settings.use_defaults()
	await get_tree().process_frame


func _run_rules() -> void:
	print("== ui window: edges, a resize, on the screen ==")
	var r := Rect2(100, 100, 400, 300)   # right edge at 500, bottom at 400
	_check(UiWindow.edges_of(r, Vector2(300, 250), 6.0) == 0, "a press in the middle is on no edge")
	_check(UiWindow.edges_of(r, Vector2(900, 250), 6.0) == 0 and UiWindow.edges_of(r, Vector2(300, 90), 6.0) == 0,
		"nor one well outside (10 px off is not the edge)")
	_check(UiWindow.edges_of(r, Vector2(102, 250), 6.0) == UiWindow.EDGE_LEFT, "just inside the left side: the left edge")
	_check(UiWindow.edges_of(r, Vector2(503, 250), 6.0) == UiWindow.EDGE_RIGHT, "just outside the right side: the right edge")
	_check(UiWindow.edges_of(r, Vector2(101, 101), 6.0) == UiWindow.EDGE_LEFT | UiWindow.EDGE_TOP, "the top-left corner: both")
	_check(UiWindow.edges_of(r, Vector2(498, 398), 6.0) == UiWindow.EDGE_RIGHT | UiWindow.EDGE_BOTTOM, "the bottom-right corner: both")

	var min_size := Vector2(200, 150)
	var wider: Rect2 = UiWindow.resized(r, UiWindow.EDGE_RIGHT, Vector2(150, 40), min_size, SCREEN)
	_check(wider == Rect2(100, 100, 550, 300), "the right edge pulled 150 right: 150 wider, nothing else moves (%s)" % wider)
	var left: Rect2 = UiWindow.resized(r, UiWindow.EDGE_LEFT, Vector2(-60, 0), min_size, SCREEN)
	_check(left == Rect2(40, 100, 460, 300), "the left edge pulled 60 left: it grows that way, the right edge stays (%s)" % left)
	var corner: Rect2 = UiWindow.resized(r, UiWindow.EDGE_RIGHT | UiWindow.EDGE_BOTTOM, Vector2(20, 30), min_size, SCREEN)
	_check(corner == Rect2(100, 100, 420, 330), "a corner pulls both (%s)" % corner)
	var squeezed: Rect2 = UiWindow.resized(r, UiWindow.EDGE_LEFT, Vector2(1000, 0), min_size, SCREEN)
	_check(squeezed == Rect2(300, 100, 200, 300), "pulled past its smallest: it stops at its minimum, the far edge stays (%s)" % squeezed)
	var squashed: Rect2 = UiWindow.resized(r, UiWindow.EDGE_TOP, Vector2(0, 1000), min_size, SCREEN)
	_check(squashed.size.y == 150.0 and squashed.end.y == 400.0, "and the same from the top (%s)" % squashed)
	var past: Rect2 = UiWindow.resized(r, UiWindow.EDGE_RIGHT | UiWindow.EDGE_BOTTOM, Vector2(5000, 5000), min_size, SCREEN)
	_check(past.end == SCREEN, "pulled off the screen: it stops at the screen's edge (%s)" % past)
	var up: Rect2 = UiWindow.resized(r, UiWindow.EDGE_LEFT | UiWindow.EDGE_TOP, Vector2(-5000, -5000), min_size, SCREEN)
	_check(up.position == Vector2.ZERO and up.end == r.end, "and off the top-left: at the screen's corner (%s)" % up)

	var off := UiWindow.kept_on_screen(Rect2(1200, 650, 400, 300), min_size, SCREEN)
	_check(off == Rect2(880, 420, 400, 300), "a place half off the screen is moved onto it, its size kept (%s)" % off)
	var huge := UiWindow.kept_on_screen(Rect2(-50, -50, 3000, 2000), min_size, SCREEN)
	_check(huge == Rect2(Vector2.ZERO, SCREEN), "one larger than the screen is the screen (%s)" % huge)
	var tiny := UiWindow.kept_on_screen(Rect2(10, 10, 300, 200), min_size, Vector2(100, 100))
	_check(tiny.size == min_size, "never smaller than it must be, even on a tiny screen (%s)" % tiny)


func _window(p_title: String) -> UiWindow:
	var w := UiWindow.new()
	w.title = p_title
	w.size_min = Vector2(300, 200)
	_view.add_child(w)
	return w


func _press(p: Vector2, down: bool, double: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.double_click = double
	e.position = p
	e.global_position = p
	return e


func _motion(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	return e


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run_windows() -> void:
	print("== ui window: drag, resize, remember ==")
	_view = SubViewport.new()
	_view.size = Vector2i(SCREEN)
	add_child(_view)
	var w: UiWindow = _window("Bag")
	w.open()
	await _settle()
	_check(w.place_id() == "Bag", "a UiWindow itself is remembered by its title")
	var first: Rect2 = w.get_global_rect()
	_check(first.size == Vector2(300, 200) and first.position.is_equal_approx((SCREEN - first.size) * 0.5),
		"never moved: it opens where the game puts it, at the size it needs (%s)" % first)
	_check(Settings.window_place("Bag").is_empty(), "and nothing is remembered yet")

	# A DRAG by the bar: moved, kept on the screen, remembered as it is let go.
	var bar: Vector2 = first.position + Vector2(40, 10)
	w._on_bar_input(_press(bar, true))
	w._on_bar_input(_motion(bar + Vector2(-200, -100)))
	w._on_bar_input(_press(bar + Vector2(-200, -100), false))
	var moved: Vector2 = first.position + Vector2(-200, -100)
	_check(w.position.is_equal_approx(moved), "dragged by its bar: moved (%s)" % w.position)
	var kept: Dictionary = Settings.window_place("Bag")
	_check(not kept.is_empty() and (kept["position"] as Vector2).is_equal_approx(moved) and kept["size"] == Vector2.ZERO,
		"let go: where it is remembered, its size not (it fits what it holds) (%s)" % str(kept))
	w._on_bar_input(_press(w.position + Vector2(40, 10), true))
	w._on_bar_input(_motion(Vector2(-3000, -3000)))
	w._on_bar_input(_press(Vector2(-3000, -3000), false))
	_check(w.position == Vector2.ZERO, "dragged off the screen: it stops at its edge (%s)" % w.position)

	# A RESIZE by its right edge, then its bottom-right corner.
	w.position = Vector2(200, 150)
	var right_edge := Vector2(w.get_global_rect().end.x - 2.0, 250)
	_check(w.resize_input(_press(right_edge, true)), "a press on its right edge begins a resize (nothing under it hears it)")
	_check(w.resize_input(_motion(right_edge + Vector2(180, 0))), "and the drag carries it")
	_check(w.resize_input(_press(right_edge + Vector2(180, 0), false)), "and the release ends it")
	_check(w.size == Vector2(480, 200) and w.position == Vector2(200, 150), "180 wider, nothing else moved (%s at %s)" % [w.size, w.position])
	kept = Settings.window_place("Bag")
	_check(kept["size"] == Vector2(480, 200) and kept["position"] == Vector2(200, 150), "its size is remembered with its place (%s)" % str(kept))
	var corner: Vector2 = w.get_global_rect().end - Vector2(2, 2)
	w.resize_input(_press(corner, true))
	w.resize_input(_motion(corner + Vector2(5000, 5000)))
	w.resize_input(_press(corner + Vector2(5000, 5000), false))
	_check(w.get_global_rect().end == SCREEN, "pulled off the screen by a corner: it stops at the screen's edge (%s)" % w.get_global_rect())
	var left_edge := Vector2(w.position.x + 1.0, 300)
	var right_end: float = w.get_global_rect().end.x
	w.resize_input(_press(left_edge, true))
	w.resize_input(_motion(left_edge + Vector2(5000, 0)))
	w.resize_input(_press(left_edge + Vector2(5000, 0), false))
	_check(w.size.x == 300.0 and w.get_global_rect().end.x == right_end,
		"squeezed from the left past its smallest: it stops at its minimum (300), its right edge still (%s)" % w.get_global_rect())
	# Negative: a press inside, away from the edges, is not a resize.
	var before: Rect2 = w.get_global_rect()
	_check(not w.resize_input(_press(before.get_center(), true)) and not w.resize_input(_motion(before.get_center() + Vector2(90, 90))),
		"a press in the middle is not a resize (the window's buttons hear it)")
	w.resize_input(_press(before.get_center(), false))
	_check(w.get_global_rect() == before, "and nothing changed")

	# What it holds needs more than the size given: it grows, and keeps the player's size otherwise.
	w.position = Vector2(100, 100)
	w.size = Vector2(500, 300)
	w._user_size = Vector2(500, 300)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(10, 600)
	w.content.add_child(tall)
	w.fit()
	_check(w.size.x == 500.0 and w.size.y >= 600.0, "fit with more to hold: it grows to hold it, the player's width kept (%s)" % w.size)
	tall.free()
	w.fit()
	_check(w.size == Vector2(500, 300) and w.position == Vector2(100, 100), "and fit again: back to the player's size, where it was (%s)" % w.size)

	# NOT RESIZABLE: its edges do nothing.
	var fixed: UiWindow = _window("Fixed")
	fixed.resizable = false
	fixed.open()
	await _settle()
	var fixed_rect: Rect2 = fixed.get_global_rect()
	var fe := Vector2(fixed_rect.end.x - 1.0, fixed_rect.get_center().y)
	fixed._input(_press(fe, true))
	fixed._input(_motion(fe + Vector2(200, 0)))
	fixed._input(_press(fe + Vector2(200, 0), false))
	_check(fixed.get_global_rect() == fixed_rect, "a window that is not resizable keeps its size when its edge is pulled")
	fixed.close()

	# REMEMBERED ACROSS A REOPEN: the same window made again opens where it was left, the size it was made.
	w.position = Vector2(220, 130)
	w._user_size = Vector2(520, 260)
	w.size = w._user_size
	w._keep_place()
	w.close()
	w.queue_free()
	var again: UiWindow = _window("Bag")
	again.open()
	await _settle()
	_check(again.position == Vector2(220, 130) and again.size == Vector2(520, 260) and again.user_size() == Vector2(520, 260),
		"made again: it opens where it was left, at the size it was made (%s at %s)" % [again.size, again.position])
	var other: UiWindow = _window("Bag")
	other.window_id = &"journal"
	other.open()
	await _settle()
	_check(other.place_id() == "journal" and other.position.is_equal_approx((SCREEN - other.size) * 0.5),
		"another window named otherwise opens in its own place, not the bag's (%s)" % other.position)
	var loose: UiWindow = _window("Bag")
	loose.remember = false
	loose.open()
	await _settle()
	_check(loose.position.is_equal_approx((SCREEN - loose.size) * 0.5), "a window that is not remembered opens where the game puts it")
	loose._on_bar_input(_press(loose.position + Vector2(40, 10), true))
	loose._on_bar_input(_motion(loose.position + Vector2(90, 10)))
	loose._on_bar_input(_press(loose.position + Vector2(90, 10), false))
	_check(Settings.window_place("Bag")["position"] == Vector2(220, 130), "and moving it changes nothing remembered")
	other.close()
	loose.close()

	# A PLACE NOW OFF THE SCREEN (a smaller screen since): opened on it.
	Settings.set_window_place("Far", Vector2(5000, 5000), Vector2(400, 300))
	var far: UiWindow = _window("Far")
	far.open()
	await _settle()
	_check(far.get_global_rect() == Rect2(SCREEN - Vector2(400, 300), Vector2(400, 300)), "a place left off the screen opens on it (%s)" % far.get_global_rect())
	far.close()

	# PUT BACK: a double-click on the bar.
	again._on_bar_input(_press(again.position + Vector2(40, 10), true, true))
	_check(again.user_size() == Vector2.ZERO and again.size == Vector2(300, 200) and again.position.is_equal_approx((SCREEN - again.size) * 0.5),
		"a double-click on its bar: back where the game puts it, at the size it needs (%s at %s)" % [again.size, again.position])
	_check(Settings.window_place("Bag").is_empty(), "and its place is forgotten")

	# THE SETTING: off, nothing is remembered and every place is forgotten.
	again._on_bar_input(_press(again.position + Vector2(40, 10), true))
	again._on_bar_input(_motion(again.position + Vector2(140, 10)))
	again._on_bar_input(_press(again.position + Vector2(140, 10), false))
	_check(not Settings.window_place("Bag").is_empty(), "(moved: remembered)")
	Settings.set_value(&"remember_windows", false)
	_check(Settings.window_place("Bag").is_empty() and Settings.window_place("Far").is_empty(), "Remember where windows are, off: every place forgotten")
	Settings.set_window_place("Bag", Vector2(1, 1), Vector2.ZERO)
	_check(Settings.window_place("Bag").is_empty(), "and none kept while it is off")
	Settings.set_value(&"remember_windows", true)
	again.close()
	_view.queue_free()
	await get_tree().process_frame


## The places are in the player's settings file: written, read back by a fresh read of it.
func _run_file() -> void:
	print("== ui window: kept in the settings file ==")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLACES_FILE))
	Settings.use_file(PLACES_FILE)
	Settings.set_window_place("res://game/x/ui/bag_window.gd", Vector2(12, 34), Vector2(400, 300))
	Settings.use_file(PLACES_FILE)   # read again, as the next start does
	var kept: Dictionary = Settings.window_place("res://game/x/ui/bag_window.gd")
	_check(not kept.is_empty() and kept["position"] == Vector2(12, 34) and kept["size"] == Vector2(400, 300),
		"a window's place is in the settings file, read back at the next start (%s)" % str(kept))
	var text: String = FileAccess.get_file_as_string(PLACES_FILE)
	_check(text.contains("[windows]") and text.contains("game_x_ui_bag_window_gd"), "under [windows], keyed by its script (%s)" % text.length())
	Settings.forget_window_place("res://game/x/ui/bag_window.gd")
	Settings.use_file(PLACES_FILE)
	_check(Settings.window_place("res://game/x/ui/bag_window.gd").is_empty(), "forgotten, it is gone from the file too")
	Settings.use_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLACES_FILE))
