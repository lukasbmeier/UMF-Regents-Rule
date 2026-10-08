class_name WindowMode extends RefCounted
## FULLSCREEN, the player's to toggle: F11 or Alt+Enter anywhere in a game that has the Escape menu
## (PauseMenu listens for them), or the menu's own button. Borderless fullscreen, so Alt+Tab to
## another window behaves.
##
## Not every process that runs the game owns its window. Inside the editor's game view the editor
## does: there, filling the view is the view's own ⋮ menu → Stretch to Fit (its default, Fixed
## Size, keeps the game at the project's 1152 x 648 however big the view is). A headless process
## has no window at all. `cannot()` says which, in words a player can act on, and a window that is
## not ours is left alone.

## Said inside the editor's game view, where a maximised view kept the game at its project size.
const IN_EDITOR: String = "In the editor's game view, the editor owns the window: open the view's ⋮ menu (top right) and pick Stretch to Fit to fill it."
const NO_WINDOW: String = "This process has no window."


static func is_fullscreen() -> bool:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Why this process cannot change its window, or "" when it can.
static func cannot() -> String:
	if DisplayServer.get_name() == "headless":
		return NO_WINDOW
	if Engine.is_embedded_in_editor():
		return IN_EDITOR
	return ""


## Fullscreen, or back to a window. Returns "" when done, or why it could not be.
static func toggle() -> String:
	var why: String = cannot()
	if not why.is_empty():
		return why
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen()
		else DisplayServer.WINDOW_MODE_FULLSCREEN)
	return ""


## F11, or Alt+Enter: the keys every PC game uses for this.
static func is_toggle_key(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.keycode == KEY_F11 or ((key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and key.alt_pressed)
