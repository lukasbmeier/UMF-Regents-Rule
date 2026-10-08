extends Node
## MouseCapture — the one owner of the mouse cursor.
##
## Mouse look needs the pointer CAPTURED: hidden, locked to the window, and reporting relative
## motion for ever instead of stopping at the screen edge. Without that, looking around ends
## the moment the cursor reaches the edge of the window, and a click outside it lands on
## whatever is behind — which on this project means the OTHER instance you are testing with.
##
## Everything that wants the pointer back — a menu, Escape, the window losing focus — has to be
## able to say so without fighting whoever captured it, so the mode is decided in exactly one
## place from three facts:
##
##   want      gameplay wants mouse look (a local player exists whose input component asked)
##   focused   this window has focus
##   released  the player pressed Escape and has not clicked back in
##
## captured == want and focused and not released and no page holds it free. Escape sets
## `released`; a click inside the
## window clears it; focus changes never touch it, so alt-tabbing to the other instance and
## back leaves you where you were. Two instances on one machine therefore cooperate: whichever
## one you click into takes the cursor and the other one lets go.
##
## POLICY VS EFFECT. The state machine above runs everywhere, headless included, where
## `is_captured()` is still the honest answer to "would the cursor be captured right now".
## Only the EFFECT — writing `Input.mouse_mode` — is skipped when there is no display server.
## That is what keeps the headless suites from having an opinion about the developer's cursor
## while still letting them test the policy itself.

## Emitted on every change, never per frame. UI uses it to show or hide a cursor-driven layer.
signal capture_changed(captured: bool)

## Escape, by Godot's built-in mapping.
const RELEASE_ACTION: StringName = &"ui_cancel"

var _want: bool = false
var _focused: bool = true
var _released: bool = false
## Pages that keep the cursor free while they are up, by reason (`hold_free`).
var _free_holds: Dictionary[StringName, bool] = {}
var _captured: bool = false
## False when there is no display server to have a cursor (headless tests, the sidecar).
var _touch_display: bool = true
## The last cursor mode actually written, or -1 if none ever was. The headless display server
## reports MOUSE_MODE_VISIBLE whatever you set, so `Input.mouse_mode` cannot tell a test whether
## the guard above held — this can.
var _last_applied_mode: int = -1


func _ready() -> void:
	# Escape has to work while the tree is paused, or a pause menu can never be reached.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch_display = DisplayServer.get_name() != "headless"


# --- intent ----------------------------------------------------------------------------

## Gameplay's standing request. `LocalInputComponent` turns it on when the local player binds
## and off when it leaves the tree, so a disconnect always hands the cursor back.
func want_capture(v: bool) -> void:
	if _want == v:
		return
	_want = v
	if v:
		# A fresh request starts from "not released": respawning should not need a click.
		_released = false
	_apply()


## The player asked for the cursor (Escape, or a menu opening). It stays free until they click
## back into the window.
func release() -> void:
	if _released:
		return
	_released = true
	_apply()


## A PAGE OVER THE GAME KEEPS THE CURSOR FREE while it is up (DECISIONS #182: the lobby screen).
## Not the player's release: the Escape menu, which opens for that, does not open for this, and a
## click does not take the cursor back. Escape still opens the menu over the page (and Resume comes
## back to the page). Each holder releases only its own reason.
func hold_free(reason: StringName, on: bool) -> void:
	if on:
		_free_holds[reason] = true
	else:
		_free_holds.erase(reason)
	_apply()


func is_held_free() -> bool:
	return not _free_holds.is_empty()


## Undo `release()`.
func recapture() -> void:
	if not _released:
		return
	_released = false
	_apply()


func toggle() -> void:
	if _released:
		recapture()
	else:
		release()


func is_captured() -> bool:
	return _captured


## True while gameplay wants the cursor, whether or not it currently has it. UI reads this to
## decide between "click to look" and nothing at all.
func is_wanted() -> bool:
	return _want


## True when the player themselves freed the cursor, rather than the window losing focus.
func released_by_player() -> bool:
	return _released


# --- events ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _want:
		return
	if (_captured or (is_held_free() and not _released)) and event.is_action_pressed(RELEASE_ACTION):
		release()
		get_viewport().set_input_as_handled()


## A click takes the cursor back only if NO UI WANTED IT. `_unhandled_input` is exactly that:
## the GUI has already had the event, and a button that took it consumed it. Taking the cursor
## back from `_input` — which runs before the GUI — meant the first click with the cursor free
## was always swallowed here, and no menu button could ever be pressed.
##
## Asking the GUI what is under the pointer (`gui_get_hovered_control`) instead was tried and
## is worse: hover is only tracked once the mouse has MOVED inside the window, so it is stale
## right after Escape and never set at all headless.
##
## Gameplay handlers run before this one (unhandled input travels up the tree, and autoloads
## are its first children), so a genre that ever acts on the left button must ignore clicks
## while `is_captured()` is false: a click with the cursor free is never a gameplay click.
func _unhandled_input(event: InputEvent) -> void:
	if not _want or _captured or is_held_free():
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	recapture()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_focused(false)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_focused(true)


## Split out so tests can drive focus without a window manager.
func _set_focused(v: bool) -> void:
	if _focused == v:
		return
	_focused = v
	_apply()


func _apply() -> void:
	var now: bool = _want and _focused and not _released and _free_holds.is_empty()
	if now == _captured:
		return
	_captured = now
	if _touch_display:
		if now:
			_last_applied_mode = Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_last_applied_mode = Input.MOUSE_MODE_VISIBLE
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	capture_changed.emit(now)
