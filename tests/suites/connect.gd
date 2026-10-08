extends "res://tests/suite_base.gd"
## The `connect` suite (tests/test_runner.gd runs it; `-- --only=connect` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_connect_tests()



# --- the connect screen ---------------------------------------------------------------

## THE FRONT DOOR. A friend who types an address wrong, or whose host forgot the firewall, meets
## this code first, and nothing else in the suite would notice it misbehaving: every harness
## connects headless and never sees it. What is checked here is what can be checked without a
## server — the address rules, the per-identity profiles, the greeting rule, the screen's own
## states, and that a menu's buttons can be clicked at all. `tests/connect_playtest.sh` drives the
## same screen against a live module.
func _run_connect_tests() -> void:
	print("== connect screen ==")

	# --- addresses: what a player types, and what is dialled -------------------------------
	var cases: Array = [
		["192.168.1.20", "http://192.168.1.20:3000"],
		["  192.168.1.20  ", "http://192.168.1.20:3000"],
		["192.168.1.20:4000", "http://192.168.1.20:4000"],
		["localhost", "http://localhost:3000"],
		["myhost.example", "http://myhost.example:3000"],
		["http://127.0.0.1:3000", "http://127.0.0.1:3000"],
		["http://127.0.0.1:3000/", "http://127.0.0.1:3000"],
		["https://db.example.com", "https://db.example.com"],
		["HTTP://Host:3000", "http://Host:3000"],
		["ws://host:3000", "http://host:3000"],
		["wss://host", "https://host"],
		["[::1]:3000", "http://[::1]:3000"],
		["[::1]", "http://[::1]:3000"],
		["", ""],
		["   ", ""],
		["ftp://host", ""],
		["host:abc", ""],
		["host:0", ""],
		["host:70000", ""],
		["::1", ""],
		["my host", ""],
		["http://host:3000/v1/database", ""],
		["user@host", ""],
		["[::1", ""],
	]
	var bad: Array[String] = []
	for c: Array in cases:
		var got: String = ConnectSettings.normalize_host(String(c[0]))
		if got != String(c[1]):
			bad.append("\"%s\" -> \"%s\" (want \"%s\")" % [c[0], got, c[1]])
	_check(bad.is_empty(), "every address normalises as documented: %s" % ", ".join(bad))

	# --- profiles: one per identity, and flags never write -----------------------------------
	ConnectSettings.use_profile("")
	_check(ConnectSettings.path() == "user://connect.cfg", "the default identity uses connect.cfg")
	ConnectSettings.use_profile("dev2")
	_check(ConnectSettings.path() == "user://connect_dev2.cfg",
		"editor slot 2 keeps its own file, next to its own identity token")
	# A process under a test suite never reads the player's profile (DECISIONS #179).
	var was_db: String = OS.get_environment("UMF_DB")
	OS.set_environment("UMF_DB", "umf-test")
	ConnectSettings.use_profile("dev1")
	var under_suite: String = ConnectSettings.path()
	ConnectSettings.use_profile("")
	var default_under_suite: String = ConnectSettings.path()
	if was_db.is_empty():
		OS.unset_environment("UMF_DB")
	else:
		OS.set_environment("UMF_DB", was_db)
	_check(under_suite == "user://connect_dev1.umf-test.cfg" and default_under_suite == "user://connect.umf-test.cfg",
		"under a test suite, editor slot 1's profile is the suite database's, not the player's (%s, %s)"
			% [under_suite, default_under_suite])
	for tag: String in ["unit_a", "unit_b"]:
		ConnectSettings.use_profile(tag)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ConnectSettings.path()))
	ConnectSettings.use_profile("unit_a")
	_check(ConnectSettings.host("http://fallback:3000") == "http://fallback:3000"
		and ConnectSettings.player_name() == "" and not ConnectSettings.auto_connect(),
		"a fresh profile falls back to the shipped defaults")
	ConnectSettings.save("http://10.0.0.5:3000", "Ailsa", true)
	ConnectSettings.use_profile("unit_b")
	ConnectSettings.save("http://10.0.0.9:3000", "Bram", false)
	ConnectSettings.use_profile("unit_a")
	_check(ConnectSettings.host("x") == "http://10.0.0.5:3000"
		and ConnectSettings.player_name() == "Ailsa" and ConnectSettings.auto_connect(),
		"a profile reads back what it saved")
	ConnectSettings.save_auto_connect(false)
	_check(ConnectSettings.host("x") == "http://10.0.0.5:3000"
		and ConnectSettings.player_name() == "Ailsa" and not ConnectSettings.auto_connect(),
		"ticking auto-connect off keeps the address and name")
	ConnectSettings.use_profile("unit_b")
	_check(ConnectSettings.player_name() == "Bram",
		"two instances on one machine remember two names (%s)" % ConnectSettings.player_name())
	for tag: String in ["unit_a", "unit_b"]:
		ConnectSettings.use_profile(tag)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ConnectSettings.path()))
	ConnectSettings.use_profile("")

	# --- who gets greeted ---------------------------------------------------------------------
	# (display, forced, --autoconnect, --host, saved auto) -> greet?
	var rules: Array = [
		[[true, false, false, false, false], true, "a player starting the game is asked where to"],
		[[false, false, false, false, false], false, "a headless process has nobody to ask"],
		[[false, true, false, false, false], true, "--connect-screen shows it even headless"],
		[[true, false, true, false, false], false, "--autoconnect skips the greeting"],
		[[true, false, false, true, false], false, "--host= skips the greeting"],
		[[true, false, false, false, true], false, "so does a ticked 'connect automatically'"],
		[[true, true, true, true, true], true, "and --connect-screen beats all of them"],
	]
	for r: Array in rules:
		var a: Array = r[0]
		_check(ConnectScreen.should_greet(a[0], a[1], a[2], a[3], a[4]) == bool(r[1]), String(r[2]))

	# --- the screen on its own ------------------------------------------------------------
	var screen: ConnectScreen = (load("res://foundation/ui/connect_screen.tscn") as PackedScene) \
		.instantiate() as ConnectScreen
	get_tree().root.add_child(screen)
	var asked: Array[Array] = []
	screen.connect_requested.connect(func(h: String, n: String, auto: bool) -> void:
		asked.append([h, n, auto]))
	_check(not screen.is_open() and not screen.visible,
		"the screen stays out of the way until someone opens it")
	screen.open("my host", "Ailsa", false)
	screen.submit()
	_check(asked.is_empty() and screen.is_open() and not screen.is_connecting(),
		"an address that cannot be one is refused on the form, not dialled")
	_check(screen.status_text().contains("not a server address"),
		"and the player is told why: \"%s\"" % screen.status_text())

	screen.open("127.0.0.1", "  Ailsa ", true)
	screen.submit()
	_check(asked.size() == 1 and asked[0] == ["http://127.0.0.1:3000", "Ailsa", true],
		"Connect hands boot the normalised address, the trimmed name and the tick: %s" % str(asked))
	_check(screen.is_connecting() and (screen.get_node("%Host") as LineEdit).text \
		== "http://127.0.0.1:3000",
		"the field shows the address as it was understood")
	_check(not (screen.get_node("%Host") as LineEdit).editable,
		"and cannot be edited while that address is being tried")

	# Cancel. The adapter is not connected here, so its terminal signal changes no state; the
	# screen still has to come back to the form rather than wait for a signal that will not come.
	(screen.get_node("%Connect") as Button).pressed.emit()
	_check(screen.is_open() and not screen.is_connecting() and screen.status_text() == "Cancelled.",
		"Cancel returns to the form and says so (\"%s\")" % screen.status_text())
	_check(SpaceTimeSync.last_disconnect_requested,
		"and the adapter records that this disconnect was asked for")

	# An address that never answers is given up on, with the address in the explanation.
	screen.first_connect_timeout_sec = 0.05
	screen.submit()
	for i: int in range(8):
		await get_tree().process_frame
	_check(screen.is_open() and not screen.is_connecting()
		and screen.status_text().contains("No answer from http://127.0.0.1:3000"),
		"an attempt that never answers is ended and explained: \"%s\"" % screen.status_text())
	_check(screen.status_text().contains("--listen-addr 0.0.0.0:3000"),
		"with the one thing a host most often forgets")

	# The session-ended messages: dropped versus left.
	screen._on_world_ready()
	_check(not screen.is_open(), "the world arriving puts the screen away")
	SpaceTimeSync.last_disconnect_requested = false
	screen._on_state(SpaceTimeSync.ConnectionState.DISCONNECTED)
	_check(screen.is_open() and screen.status_text().begins_with("Lost connection"),
		"a session that DROPPED brings the form back saying so: \"%s\"" % screen.status_text())
	screen._on_world_ready()
	SpaceTimeSync.last_disconnect_requested = true
	screen._on_state(SpaceTimeSync.ConnectionState.DISCONNECTED)
	_check(screen.is_open() and screen.status_text() == "Disconnected.",
		"one the player LEFT does not call it lost: \"%s\"" % screen.status_text())
	screen.queue_free()

	# --- a click on a menu is for the menu ----------------------------------------------------
	# MouseCapture sees every click before the GUI does. Before this, the first click with the
	# cursor free always recaptured it and was swallowed, so no menu button could be pressed.
	var layer := CanvasLayer.new()
	var button := Button.new()
	button.text = "Resume"
	button.position = Vector2(40.0, 40.0)
	button.size = Vector2(160.0, 40.0)
	layer.add_child(button)
	get_tree().root.add_child(layer)
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	MouseCapture.want_capture(true)
	MouseCapture.release()
	await get_tree().process_frame
	var vp: Viewport = get_viewport()
	# Headless never tracks hover (no display server sends mouse-enter), and a Button only takes
	# a MOUSE press while hovered. A window would send this notification as the pointer arrived;
	# everything after it is the real input path.
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_click(vp, Vector2(120.0, 60.0))
	await get_tree().process_frame
	_check(presses[0] == 1, "the click reaches the button (%d presses)" % presses[0])
	_check(not MouseCapture.is_captured(), "and does not take the cursor back")
	_click(vp, Vector2(900.0, 500.0))
	await get_tree().process_frame
	_check(MouseCapture.is_captured(), "a click on the world still does")
	_check(presses[0] == 1, "without pressing anything on the way")
	MouseCapture.want_capture(false)
	layer.queue_free()
	await get_tree().process_frame

	# --- FULLSCREEN: F11, Alt+Enter and the menu's button (the windowed half, where the mode really
	# changes, is tests/render_test.sh). Headless, there is no window to change: the keys are still
	# read, the button is greyed and says why, and nothing is asked of the display.
	var key: Callable = func(code: Key, alt: bool = false, pressed: bool = true, echo: bool = false) -> InputEventKey:
		var e := InputEventKey.new()
		e.keycode = code
		e.alt_pressed = alt
		e.pressed = pressed
		e.echo = echo
		return e
	_check(WindowMode.is_toggle_key(key.call(KEY_F11)) and WindowMode.is_toggle_key(key.call(KEY_ENTER, true))
			and WindowMode.is_toggle_key(key.call(KEY_KP_ENTER, true)),
		"F11 and Alt+Enter toggle fullscreen")
	_check(not WindowMode.is_toggle_key(key.call(KEY_ENTER)) and not WindowMode.is_toggle_key(key.call(KEY_F11, false, false))
			and not WindowMode.is_toggle_key(key.call(KEY_F11, false, true, true)) and not WindowMode.is_toggle_key(key.call(KEY_F10)),
		"and plain Enter, a key coming up, a held key repeating or F10 do not")
	_check(WindowMode.cannot() == WindowMode.NO_WINDOW and WindowMode.toggle() == WindowMode.NO_WINDOW,
		"a headless process says it has no window, and leaves the display alone")
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	await get_tree().process_frame
	var fs_button: Button = menu.get_node(^"%Fullscreen") as Button
	menu.call("_refresh_fullscreen")
	_check(fs_button != null and fs_button.disabled and fs_button.tooltip_text == WindowMode.NO_WINDOW
			and fs_button.text.contains("F11"),
		"the Escape menu offers Fullscreen (F11), greyed here with the reason: %s" % (fs_button.tooltip_text if fs_button != null else "-"))
	menu.queue_free()
	await get_tree().process_frame


## A real click: the pointer moves there first, which is what gives the GUI its hover.
func _click(vp: Viewport, at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	vp.push_input(move)
	for pressed: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = at
		b.global_position = at
		vp.push_input(b)
