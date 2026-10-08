extends "res://tests/suite_base.gd"
## The `mouse_capture` suite (tests/test_runner.gd runs it; `-- --only=mouse_capture` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_mouse_capture_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


# --- MouseCapture (the cursor policy) --------------------------------------------------

## Reported: "the mouse is not captured and can leave the window". Mouse look needs the cursor
## locked to the window; getting it back has to be possible; and two instances on one machine
## must not fight over it. That is a state machine, so it is tested as one.
##
## The POLICY runs headless. The EFFECT — writing Input.mouse_mode — is skipped when there is
## no display server, and the headless server reports MOUSE_MODE_VISIBLE whatever you set it
## to, so `_last_applied_mode` is what a test can actually check.
func _run_mouse_capture_tests() -> void:
	print("== MouseCapture ==")
	_check(_autoload("MouseCapture") != null, "MouseCapture is registered as an autoload")

	var log: Array[bool] = []
	var cb := func(c: bool) -> void: log.append(c)
	MouseCapture.capture_changed.connect(cb)

	# A known starting point: no player, focused, nothing released.
	MouseCapture.want_capture(false)
	MouseCapture._set_focused(true)
	MouseCapture.recapture()
	log.clear()
	_check(not MouseCapture.is_captured(), "the cursor is free until gameplay asks for it")

	# (a) a local player asking is what captures it.
	MouseCapture.want_capture(true)
	_check(MouseCapture.is_captured() and log == [true],
		"a local player with mouse look captures the cursor")
	MouseCapture.want_capture(true)
	_check(log == [true], "asking twice announces once, so UI does not flicker")

	# (b) Escape gives it back, and it STAYS back.
	MouseCapture.release()
	_check(not MouseCapture.is_captured() and log == [true, false], "Escape frees the cursor")
	_check(MouseCapture.released_by_player(),
		"and the HUD can tell that the player did it deliberately")
	MouseCapture._set_focused(false)
	MouseCapture._set_focused(true)
	_check(not MouseCapture.is_captured(),
		"alt-tabbing away and back does not silently re-grab a cursor the player asked for")

	# (c) a click inside the window takes it back.
	MouseCapture.recapture()
	_check(MouseCapture.is_captured() and log.size() == 3 and log[2],
		"clicking in the window recaptures (%s)" % str(log))

	# (d) TWO INSTANCES ON ONE MACHINE. Losing focus has to release, or the other window can
	# never be clicked into — which is how this project is played and tested.
	MouseCapture._set_focused(false)
	_check(not MouseCapture.is_captured(), "losing focus releases the cursor for the other instance")
	MouseCapture._set_focused(true)
	_check(MouseCapture.is_captured(),
		"coming back takes it again, because the player never pressed Escape")

	# (e) the player going away always hands it back: a disconnect must not strand the cursor.
	MouseCapture.want_capture(false)
	_check(not MouseCapture.is_captured() and not MouseCapture.is_wanted(),
		"a despawned player releases the cursor")
	MouseCapture.release()
	MouseCapture.want_capture(true)
	_check(MouseCapture.is_captured(),
		"and a fresh player starts captured even if the last one ended released")

	# (f) THE GUARD on the effect. Negative-tested: with the guard lifted the same transitions
	# DO write a mode, so that check is the only thing keeping a headless run from taking the
	# developer's cursor.
	MouseCapture.want_capture(false)
	MouseCapture._last_applied_mode = -1
	MouseCapture.want_capture(true)
	MouseCapture.want_capture(false)
	_check(MouseCapture._last_applied_mode == -1,
		"with no display server the cursor mode is never written")
	MouseCapture._touch_display = true
	MouseCapture.want_capture(true)
	_check(MouseCapture._last_applied_mode == Input.MOUSE_MODE_CAPTURED,
		"with one, it is (mode %d)" % MouseCapture._last_applied_mode)
	MouseCapture.want_capture(false)
	_check(MouseCapture._last_applied_mode == Input.MOUSE_MODE_VISIBLE,
		"and released again on the way out")
	MouseCapture._touch_display = false
	MouseCapture._last_applied_mode = -1
	MouseCapture.capture_changed.disconnect(cb)
