extends Node
## THE WINDOW, for real (DECISIONS #148). A headless run has no window to change, so this one opens
## one (tests/render_test.sh): F11 through the Escape menu — which listens for it whether it is
## open or not — makes the game fullscreen, the whole screen it is on, and F11 again puts it back
## in a window the size it was.
##
## Prints `RENDER PASS`/`RENDER FAIL` per check and exits 1 on any failure.

const SETTLE_FRAMES: int = 90

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	for i: int in range(5):
		await get_tree().process_frame
	var before: Vector2i = DisplayServer.window_get_size()
	_expect(WindowMode.cannot().is_empty() and not WindowMode.is_fullscreen(),
		"the test starts in a window the game may change (%s)" % before)
	_press_f11()
	var full: bool = await _settle(true)
	var screen: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var drawn: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	_expect(full and DisplayServer.window_get_size() == screen and drawn == screen,
		"F11: fullscreen, and the game draws the whole screen (%s on a %s screen)" % [drawn, screen])
	_press_f11()
	var back: bool = await _settle(false)
	_expect(back and DisplayServer.window_get_size() == before,
		"F11 again: back in a window, the size it was (%s)" % DisplayServer.window_get_size())
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


func _press_f11() -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_F11
		e.physical_keycode = KEY_F11
		e.pressed = down
		Input.parse_input_event(e)


## Wait for the window to arrive (or leave) fullscreen, then a few frames for the viewport to follow.
func _settle(fullscreen: bool) -> bool:
	for i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
		if WindowMode.is_fullscreen() == fullscreen:
			for j: int in range(10):
				await get_tree().process_frame
			return true
	return false


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("RENDER PASS ", msg)
	else:
		_failures += 1
		printerr("RENDER FAIL ", msg)
