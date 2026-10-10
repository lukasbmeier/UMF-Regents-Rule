extends "res://tests/suite_base.gd"
## The `settings` suite (tests/test_runner.gd runs it; `-- --only=settings` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_settings_tests()



## SETTINGS (DECISIONS #165). The player's own choices: checked against their definitions,
## applied (buses, mouse look, key bindings), saved and read back, drawn by the panel from the
## definitions (a game's own included), and reachable from the Escape menu, which also shows the
## log. On a file of its own: the player's settings.cfg is never touched by a test.
const SETTINGS_TEST_FILE: String = "user://settings_test.cfg"


func _run_settings_tests() -> void:
	print("== settings ==")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_FILE))
	Settings.use_file(SETTINGS_TEST_FILE)
	_check(Array(Settings.tabs()).slice(0, 4) == [Settings.VIDEO, Settings.AUDIO, Settings.CONTROLS, Settings.GAME],
		"the foundation's tabs, in order (%s)" % str(Settings.tabs()))
	for bus: StringName in [&"Master", Settings.BUS_MUSIC, Settings.BUS_EFFECTS, Settings.BUS_AMBIENCE, Settings.BUS_VOICE]:
		_check(AudioServer.get_bus_index(bus) >= 0, "the audio bus '%s' exists (default_bus_layout.tres)" % bus)
	_check(float(Settings.get_value(&"master_volume")) == 100.0 and float(Settings.get_value(&"music_volume")) == 70.0
		and Settings.look_sensitivity() == 1.0 and not Settings.invert_look(),
		"a fresh install has the defaults")

	# --- values are checked against their definitions -------------------------------------
	Settings.set_value(&"render_scale", 10.0)
	_check(float(Settings.get_value(&"render_scale")) == 50.0, "a slider is clamped to its range (10 -> %s)" % Settings.get_value(&"render_scale"))
	Settings.set_value(&"mouse_sensitivity", 1.234)
	_check(is_equal_approx(Settings.look_sensitivity(), 1.25), "and snapped to its step (1.234 -> %s)" % Settings.look_sensitivity())
	Settings.set_value(&"max_fps", 99)
	_check(int(Settings.get_value(&"max_fps")) == 0, "a choice out of range is the default")
	Settings.set_value(&"vsync", "yes")
	_check(Settings.get_value(&"vsync") == true, "a value of the wrong kind is the default")
	var heard: Array[StringName] = []
	var on_changed := func(k: StringName, _v: Variant) -> void: heard.append(k)
	Settings.changed.connect(on_changed)
	Settings.set_value(&"master_volume", 40.0)
	Settings.set_value(&"master_volume", 40.0)
	Settings.set_value(&"music_volume", 0.0)
	Settings.changed.disconnect(on_changed)
	_check(heard == [&"master_volume", &"music_volume"], "a change is announced once, a repeat not at all (%s)" % str(heard))
	var master: int = AudioServer.get_bus_index(&"Master")
	var music: int = AudioServer.get_bus_index(Settings.BUS_MUSIC)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(0.4)) and not AudioServer.is_bus_mute(master),
		"the master volume sets the bus (%.1f dB)" % AudioServer.get_bus_volume_db(master))
	_check(AudioServer.is_bus_mute(music), "music at 0 is muted")

	# --- the player's mouse ----------------------------------------------------------------
	var input: LocalInputComponent = _make_input_component(true)
	input.capture_mouse = false
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 10)
	var turned: Array[Vector2] = []
	for setting: Array in [[1.0, false], [2.0, false], [1.0, true]]:
		Settings.set_value(&"mouse_sensitivity", setting[0])
		Settings.set_value(&"invert_y", setting[1])
		input._look_yaw = 0.0
		input._look_pitch = 0.0
		input._unhandled_input(motion)
		turned.append(Vector2(input._look_yaw, input._look_pitch))
	_check(is_equal_approx(turned[1].x, 2.0 * turned[0].x) and is_equal_approx(turned[1].y, 2.0 * turned[0].y),
		"twice the sensitivity turns the view twice as far (%s, %s)" % [turned[0], turned[1]])
	_check(is_equal_approx(turned[2].y, -turned[0].y) and is_equal_approx(turned[2].x, turned[0].x) and turned[0].y != 0.0,
		"inverted, moving the mouse down looks the other way, and left and right are unchanged")
	input.queue_free()

	# --- key bindings ----------------------------------------------------------------------
	var space: String = Settings.event_to_text(_key_event(KEY_SPACE))
	_check(Settings.get_value(&"jump") == space and Settings.binding_label(space) == "Space",
		"jump ships on Space (%s, shown as \"%s\")" % [Settings.get_value(&"jump"), Settings.binding_label(space)])
	Settings.set_value(&"jump", Settings.event_to_text(_key_event(KEY_J)))
	_check(_bound_to(&"jump", KEY_J) and not _bound_to(&"jump", KEY_SPACE),
		"rebinding jump puts J on the action and takes Space off")
	Settings.set_value(&"interact", Settings.event_to_text(_key_event(KEY_W)))
	_check(Settings.clashes(&"interact", String(Settings.get_value(&"interact"))) == PackedStringArray(["Move forward"]),
		"a binding another action has is pointed out (%s)" % str(Settings.clashes(&"interact", String(Settings.get_value(&"interact")))))
	Settings.set_value(&"interact", "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	_check(Settings.binding_label(String(Settings.get_value(&"interact"))) == "Middle mouse"
		and InputMap.action_has_event(&"interact", Settings.text_to_event("mouse:%d" % MOUSE_BUTTON_MIDDLE)),
		"a mouse button can be bound")
	Settings.set_value(&"jump", "nonsense")
	_check(Settings.get_value(&"jump") == space and _bound_to(&"jump", KEY_SPACE),
		"a binding that is not a key or a button is the shipped one")
	Settings.set_value(&"jump", Settings.event_to_text(_key_event(KEY_J)))

	# --- saved, and read back ----------------------------------------------------------------
	Settings.use_file(SETTINGS_TEST_FILE)
	_check(float(Settings.get_value(&"master_volume")) == 40.0 and float(Settings.get_value(&"render_scale")) == 50.0
		and _bound_to(&"jump", KEY_J) and Settings.binding_label(String(Settings.get_value(&"interact"))) == "Middle mouse",
		"everything changed is read back from the file")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_TEST_FILE)
	_check(cfg.has_section_key("audio", "master_volume") and cfg.has_section_key("keys", "jump"),
		"the file is sectioned by tab, bindings under [keys]")
	Settings.reset(Settings.CONTROLS)
	_check(_bound_to(&"jump", KEY_SPACE) and not _bound_to(&"jump", KEY_J) and Settings.look_sensitivity() == 1.0,
		"Reset puts a tab's settings back, bindings included")

	# --- a game's own setting, and the panel ------------------------------------------------
	Settings.define(&"test_gauge", "Testing", "Show the test gauge", Settings.Kind.TOGGLE, true)
	_check(Settings.tabs().has("Testing") and Settings.get_value(&"test_gauge") == true,
		"a game defines its own setting, on its own tab")
	var panel := SettingsPanel.new()
	get_tree().root.add_child(panel)
	panel.open()
	await get_tree().process_frame
	var tabs: TabContainer = panel.find_child("Tabs", true, false) as TabContainer
	_check(tabs != null and tabs.get_tab_count() == Settings.tabs().size(),
		"the panel has a tab per settings tab (%d)" % (tabs.get_tab_count() if tabs != null else -1))
	_check(panel.control_for(&"test_gauge") is CheckButton, "and draws the game's setting without being told about it")
	(panel.control_for(&"test_gauge") as CheckButton).button_pressed = false
	_check(Settings.get_value(&"test_gauge") == false, "clicking a toggle changes the setting")
	var slider: HSlider = panel.control_for(&"effects_volume").get_node(^"Slider") as HSlider
	slider.value = 25.0
	_check(float(Settings.get_value(&"effects_volume")) == 25.0
		and (panel.control_for(&"effects_volume").get_node(^"Value") as Label).text == "25%",
		"dragging a slider changes the setting and its label")
	var bind: Button = panel.control_for(&"sprint").get_node(^"Bind") as Button
	bind.pressed.emit()
	_check(panel.listening() == &"sprint" and bind.text.begins_with("Press a key"), "clicking a binding waits for a key")
	panel._input(_key_event(KEY_ESCAPE))
	_check(panel.listening() == &"" and panel.is_open() and Settings.binding_label(String(Settings.get_value(&"sprint"))) == bind.text,
		"Escape cancels the wait, and leaves the binding and the panel")
	bind.pressed.emit()
	panel._input(_key_event(KEY_K))
	_check(_bound_to(&"sprint", KEY_K) and bind.text == "K", "the next key pressed is the binding (%s)" % bind.text)
	Settings.set_value(&"fullscreen", true)
	_check((panel.control_for(&"fullscreen") as CheckButton).button_pressed, "a change made elsewhere (F11) shows in an open panel")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	var closed: Array[bool] = [false]
	panel.closed.connect(func() -> void: closed[0] = true)
	panel._input(esc)
	_check(not panel.is_open() and closed[0], "Escape closes the panel")
	panel.queue_free()

	# --- the Escape menu ---------------------------------------------------------------------
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var settings_button: Button = menu.find_child("Settings", true, false) as Button
	var logs_button: Button = menu.find_child("Logs", true, false) as Button
	_check(settings_button != null and logs_button != null, "the Escape menu has Settings and Open log folder")
	settings_button.pressed.emit()
	_check(menu.settings_panel().is_open() and not (menu.get_node(^"Center") as Control).visible and menu.is_page_open(),
		"Settings opens the settings in place of the menu")
	menu.settings_panel()._input(esc)
	_check(not menu.settings_panel().is_open() and (menu.get_node(^"Center") as Control).visible and not menu.is_page_open(),
		"and Escape there goes back to the menu, not out of it")
	var extra: Button = menu.add_button("Journal")
	_check(extra.get_index() == menu.find_child("Disconnect", true, false).get_index() - 1,
		"a genre adds a button of its own, above Disconnect")
	var shown: String = PauseMenu.open_log_folder()
	_check(shown.begins_with(ProjectSettings.globalize_path("user://")),
		"Open log folder shows this game's user folder (%s)" % shown)
	menu.queue_free()

	# Back to the defaults, and no file.
	Settings.reset("Testing")
	for tab: String in [Settings.VIDEO, Settings.AUDIO, Settings.CONTROLS]:
		Settings.reset(tab)
	Settings.use_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_FILE))
	_check(_bound_to(&"jump", KEY_SPACE) and _bound_to(&"sprint", KEY_SHIFT) and _bound_to(&"interact", KEY_E),
		"the bindings are the shipped ones again")


func _key_event(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	return k


func _bound_to(action: StringName, code: Key) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var k: InputEventKey = ev as InputEventKey
		if k != null and (k.physical_keycode == code or k.keycode == code):
			return true
	return false
