extends "res://tests/suite_base.gd"
## The `quality` suite (DECISIONS #282): the graphics presets set their settings together and a
## hand-changed one makes them Custom; what each choice does to a level (its effects, lights,
## LOD and the designer's detail groups), never past what the level was authored with; the old
## `shadows` setting read as the new one; and the renderer choice's files and start guard
## (`RendererChoice`), on files of the suite's own. The renderer really switching (the engine
## reading the file, the restart) is `tests/render_test.sh`'s.

const TEST_FILE: String = "user://quality_test.cfg"
const OVERRIDE_FILE: String = "user://quality_test_renderer.cfg"
const GUARD_FILE: String = "user://quality_test_guard.cfg"


func run() -> void:
	print("== quality ==")
	for f: String in [TEST_FILE, OVERRIDE_FILE, GUARD_FILE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Settings.use_file(TEST_FILE)
	_presets()
	await _level()
	_old_shadows()
	_gpus()
	await _animation_rate()
	_renderer_files()
	_start_guard()
	await _panel()
	Settings.use_defaults()
	for f: String in [TEST_FILE, OVERRIDE_FILE, GUARD_FILE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_HIGH and GraphicsQuality.effects == GraphicsQuality.Effects.FULL
		and GraphicsQuality.shadows_on and GraphicsQuality.detail == GraphicsQuality.Detail.HIGH,
		"back on the defaults: High, the full look")


func _members() -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in Settings.PRESET_KEYS:
		out[k] = Settings.get_value(k)
	return out


func _presets() -> void:
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_HIGH and Settings.matching_quality() == Settings.QUALITY_HIGH,
		"a fresh install on this machine (no GPU: headless) is on High, and its settings are High's")
	_check(Settings.QUALITY_PRESETS[Settings.QUALITY_HIGH] == {&"render_scale": 100.0, &"anti_aliasing": 2,
		&"shadow_quality": 3, &"effects": 2, &"detail": 2, &"max_fps": 0},
		"High is the look every machine had before presets: full scale, TAA, High shadows, every effect, unlimited frames")
	for i: int in range(Settings.QUALITY_PRESETS.size()):
		Settings.set_value(&"quality", i)
		var want: Dictionary = {}
		for k: StringName in Settings.PRESET_KEYS:
			want[k] = Settings._valid(Settings.entry(k), Settings.QUALITY_PRESETS[i][k])
		_check(_members() == want and int(Settings.get_value(&"quality")) == i,
			"choosing %s sets every one of its settings (%s)" % [Settings.entry(&"quality")["choices"][i], str(_members())])
	Settings.set_value(&"quality", Settings.QUALITY_LOW)
	_check(Engine.max_fps == 60 or DisplayServer.get_name() == "headless", "Low caps the frame rate at 60 (on a display)")
	_check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.7) and not get_tree().root.use_taa,
		"Low draws the 3D world at 70%% and without TAA (%.2f)" % get_tree().root.scaling_3d_scale)
	Settings.set_value(&"render_scale", 90.0)
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_CUSTOM,
		"changing one of them by hand makes the quality Custom")
	Settings.set_value(&"quality", Settings.QUALITY_CUSTOM)
	_check(float(Settings.get_value(&"render_scale")) == 90.0 and int(Settings.get_value(&"shadow_quality")) == 0,
		"choosing Custom changes nothing")
	for k: StringName in Settings.PRESET_KEYS:
		Settings.set_value(k, Settings.QUALITY_PRESETS[1][k])
	_check(int(Settings.get_value(&"quality")) == 1, "setting each by hand to Medium's values is Medium again")
	Settings.use_file(TEST_FILE)
	_check(int(Settings.get_value(&"quality")) == 1 and float(Settings.get_value(&"render_scale")) == 85.0,
		"the quality and its settings are saved and read back")
	Settings.set_value(&"render_scale", 60.0)
	Settings.use_file(TEST_FILE)
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_CUSTOM and float(Settings.get_value(&"render_scale")) == 60.0,
		"a Custom quality is read back as Custom, its settings as they were (no preset runs over them)")
	Settings.reset(Settings.VIDEO)
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_HIGH and Settings.matching_quality() == Settings.QUALITY_HIGH,
		"Reset puts the Video tab back on this machine's quality")


## A level as a designer makes one: an Environment with every effect, one with SSAO left off, a sun
## with shadows reaching 80 m, a lamp with none, the designer's detail groups.
func _level() -> void:
	var level := Node3D.new()
	level.name = "QualityLevel"
	var env := Environment.new()
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.glow_enabled = true
	env.ssr_enabled = true
	env.sdfgi_enabled = true
	env.volumetric_fog_enabled = true
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	level.add_child(we)
	var plain := Environment.new()   # the camera's: no SSAO, glow only
	plain.glow_enabled = true
	var copy: Environment = null   # made below from the level's, its effects then turned off (a minimap's)
	var cam := Camera3D.new()
	cam.environment = plain
	level.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	level.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = false
	level.add_child(lamp)
	var high := Node3D.new()
	high.add_to_group(GraphicsQuality.GROUP_HIGH)
	level.add_child(high)
	var medium := Node3D.new()
	medium.add_to_group(GraphicsQuality.GROUP_MEDIUM)
	level.add_child(medium)
	var hidden := Node3D.new()   # authored hidden: no detail level shows it
	hidden.visible = false
	hidden.add_to_group(GraphicsQuality.GROUP_HIGH)
	level.add_child(hidden)
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = MultiMesh.new()
	grass.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grass.multimesh.instance_count = 100
	grass.add_to_group(GraphicsQuality.GROUP_DENSITY)
	level.add_child(grass)
	Settings.set_value(&"quality", Settings.QUALITY_HIGH)
	get_tree().root.add_child(level)
	await get_tree().process_frame
	var effects := func(e: Environment) -> Array[bool]:
		return [e.ssao_enabled, e.glow_enabled, e.ssil_enabled, e.ssr_enabled, e.sdfgi_enabled, e.volumetric_fog_enabled]
	_check(effects.call(env) == [true, true, true, true, true, true] and effects.call(plain) == [false, true, false, false, false, false]
		and sun.shadow_enabled and sun.directional_shadow_max_distance == 80.0 and high.visible and medium.visible
		and grass.multimesh.visible_instance_count == -1 and get_tree().root.mesh_lod_threshold == 1.0,
		"on High a level entering the tree is drawn as it was made")

	Settings.set_value(&"quality", Settings.QUALITY_LOW)
	_check(effects.call(env) == [false, false, false, false, false, false] and env.fog_enabled,
		"Low: no screen effects at all (the fog of the distance stays)")
	_check(not sun.shadow_enabled and sun.directional_shadow_max_distance == 40.0 and not lamp.shadow_enabled,
		"Low: no light casts a shadow, and the sun's would reach half as far")
	_check(not high.visible and not medium.visible and grass.multimesh.visible_instance_count == 25
		and get_tree().root.mesh_lod_threshold == 4.0,
		"Low: both detail groups hidden, a quarter of the grass, coarser LODs")

	Settings.set_value(&"quality", 1)
	_check(effects.call(env) == [true, true, false, false, false, false] and effects.call(plain) == [false, true, false, false, false, false],
		"Medium: SSAO and glow where the level has them, nothing it left off turned on")
	_check(sun.shadow_enabled and sun.directional_shadow_max_distance == 60.0 and not high.visible and medium.visible
		and grass.multimesh.visible_instance_count == 50,
		"Medium: shadows on, 3/4 of their reach; detail_high hidden, detail_medium shown; half the grass")

	copy = env.duplicate() as Environment   # carries the level's meta: must not carry its "as authored"
	copy.ssao_enabled = false
	copy.glow_enabled = false
	var minimap := Camera3D.new()
	minimap.environment = copy
	level.add_child(minimap)

	var late := WorldEnvironment.new()   # a level that streams in after the choice
	var late_env := Environment.new()
	late_env.ssil_enabled = true
	late.environment = late_env
	level.add_child(late)
	_check(not late_env.ssil_enabled, "a node entering the tree later takes the choice at once")

	Settings.set_value(&"quality", Settings.QUALITY_HIGH)
	_check(effects.call(env) == [true, true, true, true, true, true] and effects.call(plain) == [false, true, false, false, false, false]
		and late_env.ssil_enabled and sun.shadow_enabled and sun.directional_shadow_max_distance == 80.0
		and not lamp.shadow_enabled and high.visible and not hidden.visible and grass.multimesh.visible_instance_count == -1,
		"back on High, exactly as authored: the lamp still casts none, the hidden node stays hidden")
	_check(not copy.ssao_enabled and not copy.glow_enabled,
		"a copy of the level's Environment with its effects turned off (a minimap's) keeps them off")
	level.queue_free()
	await get_tree().process_frame


func _old_shadows() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", 0)   # the old Low
	cfg.save(TEST_FILE)
	Settings.use_file(TEST_FILE)
	Settings._defined = false   # what a start does with that file: no preset runs while defining
	Settings._define_foundation()
	Settings._defined = true
	_check(int(Settings.get_value(&"shadow_quality")) == 1,
		"a saved `shadows` (Low, from before Off existed) is read as Shadows: Low (%s)" % Settings.get_value(&"shadow_quality"))
	var older := ConfigFile.new()
	older.set_value("video", "render_scale", 80.0)   # a file from before presets: no quality in it
	older.save(TEST_FILE)
	Settings.use_file(TEST_FILE)
	_check(int(Settings.get_value(&"quality")) == Settings.QUALITY_CUSTOM and float(Settings.get_value(&"render_scale")) == 80.0,
		"a file from before presets, with its render scale changed, shows Custom, not High")
	Settings.reset(Settings.VIDEO)


func _gpus() -> void:
	var cases: Dictionary = {
		"Intel(R) Iris(R) Plus Graphics": true, "Intel(R) Iris(R) Plus Graphics 655": true,
		"Intel(R) UHD Graphics 620": true, "Intel(R) UHD Graphics 630": true, "Intel(R) HD Graphics 4600": true,
		"Intel(R) HD Graphics 520": true, "Intel(R) Iris(R) Pro Graphics 580": true,
		"Intel(R) Iris(R) Xe Graphics": false, "Intel(R) UHD Graphics 770": false, "Intel(R) Arc(TM) A770 Graphics": false,
		"Intel(R) Graphics": false, "Intel(R) Arc(TM) Graphics": false, "AMD Radeon RX 9060 XT": false,
		"AMD Radeon(TM) Graphics": false, "Apple M1": false, "NVIDIA GeForce GTX 1050": false, "": false,
	}
	var wrong: Array[String] = []
	for name: String in cases:
		if RendererChoice.is_legacy_gpu(name) != bool(cases[name]):
			wrong.append(name)
	_check(wrong.is_empty(), "Intel's pre-Xe graphics are the weak GPUs, nothing newer or anyone else's (wrong: %s)" % str(wrong))


## How often another character is posed, by Detail (AnimationRate), and a tree paced at that rate:
## posed only once its interval is owed, with all the time owed, and caught up on going back to
## every frame, its process mode never switched (a switch restarts what a tree plays). (A real remote character under a camera is the `remote_animation` suite's.)
func _animation_rate() -> void:
	var L: int = GraphicsQuality.Detail.LOW
	var M: int = GraphicsQuality.Detail.MEDIUM
	var H: int = GraphicsQuality.Detail.HIGH
	var got: Array[float] = [AnimationRate.hz(L, 5.0, true, false), AnimationRate.hz(L, 30.0, true, false),
		AnimationRate.hz(L, 100.0, true, false), AnimationRate.hz(L, 5.0, false, false),
		AnimationRate.hz(M, 10.0, true, false), AnimationRate.hz(M, 40.0, true, false), AnimationRate.hz(M, 90.0, false, false),
		AnimationRate.hz(H, 500.0, false, false), AnimationRate.hz(L, 500.0, false, true)]
	_check(got == [30.0, 15.0, 8.0, 5.0, 0.0, 20.0, 8.0, 0.0, 0.0],
		"the rates: Low 30 near, 15, 8 far, 5 off screen; Medium every frame near, 20, 8 off screen; High and your own always every frame (%s)" % str(got))
	_check(AnimationRate.phase(1) != AnimationRate.phase(2) and AnimationRate.phase(7) >= 0.0 and AnimationRate.phase(7) < 1.0,
		"each entity starts at its own point in the interval, so a crowd does not pose on one frame")

	# A tree whose one clip moves a node 1 m a second.
	var root := Node3D.new()
	var mover := Node3D.new()
	mover.name = "Mover"
	root.add_child(mover)
	var anim := Animation.new()
	anim.length = 10.0
	var track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, ^"Mover:position:x")
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, 10.0, 10.0)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"move", anim)
	var tree := AnimationTree.new()
	tree.add_animation_library(&"", lib)
	var node := AnimationNodeAnimation.new()
	node.animation = &"move"
	tree.tree_root = node
	AnimationRate.Pacer.take(tree)
	root.add_child(tree)
	tree.root_node = tree.get_path_to(root)
	get_tree().root.add_child(root)
	tree.active = true
	var pacer := AnimationRate.Pacer.new()
	var dt: float = 1.0 / 60.0
	for i: int in range(3):   # playing already, every frame, as a character's tree is
		pacer.step(tree, AnimationRate.EVERY_FRAME, dt, 0.001)
	var walked: float = mover.position.x
	await get_tree().process_frame
	_check(mover.position.x == walked and walked > 0.0,
		"a paced tree is the pacer's: a frame going by does not move it (%.3f m)" % mover.position.x)
	pacer.step(tree, 10.0, dt, 0.001)
	var base: float = mover.position.x
	for i: int in range(4):
		pacer.step(tree, 10.0, dt, 0.001)
	var before: float = mover.position.x - base
	pacer.step(tree, 10.0, dt, 0.001)
	var after: float = mover.position.x - base
	_check(absf(before) < 0.0001 and is_equal_approx(snappedf(after, 0.001), 0.1),
		"at 10 Hz the tree waits five 60 Hz frames, then poses with all the time owed (+%.3f, then +%.3f m)" % [before, after])
	for i: int in range(3):
		pacer.step(tree, 10.0, dt, 0.001)
	pacer.step(tree, AnimationRate.EVERY_FRAME, dt, 0.0)
	_check(tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		and is_equal_approx(snappedf(mover.position.x - base, 0.001), 0.167),
		"back to every frame, it catches up on the time it was owed, this frame's too, and its mode never changed (+%.3f m)" % (mover.position.x - base))

	var model := Node3D.new()
	var plain := MeshInstance3D.new()
	var ranged := MeshInstance3D.new()
	ranged.visibility_range_end = 30.0
	model.add_child(plain)
	model.add_child(ranged)
	AnimationRate.apply_range(model, L)
	var low: Array[float] = [plain.visibility_range_end, ranged.visibility_range_end]
	AnimationRate.apply_range(model, H)
	_check(low == [80.0, 30.0] and plain.visibility_range_end == 0.0 and ranged.visibility_range_end == 30.0,
		"a character's draw distance on Low is 80 m, unlimited on High, and a piece with its own range keeps it (%s)" % str(low))
	model.free()
	root.queue_free()
	await get_tree().process_frame


func _renderer_files() -> void:
	var o: String = OVERRIDE_FILE
	RendererChoice.write(RendererChoice.Choice.COMPATIBILITY, o)
	var cfg := ConfigFile.new()
	cfg.load(o)
	_check(RendererChoice.override_method(o) == RendererChoice.COMPATIBILITY
		and cfg.get_value("rendering", "renderer/rendering_method.mobile", "") == RendererChoice.COMPATIBILITY,
		"choosing Compatibility writes the engine's override file (for every platform's renderer)")
	RendererChoice.write(RendererChoice.Choice.AUTOMATIC, o)
	_check(not FileAccess.file_exists(o), "Automatic, from a chosen Compatibility, is the game's own renderer: no file")
	RendererChoice.switch(RendererChoice.REASON_GPU, o, GUARD_FILE)
	RendererChoice.write(RendererChoice.Choice.AUTOMATIC, o)
	_check(RendererChoice.override_method(o) == RendererChoice.COMPATIBILITY
		and RendererChoice.method_for(RendererChoice.Choice.AUTOMATIC, o) == RendererChoice.COMPATIBILITY,
		"Automatic keeps the switch it made by itself")
	RendererChoice.write(RendererChoice.Choice.GAME, o)
	_check(not FileAccess.file_exists(o) and RendererChoice.method_for(RendererChoice.Choice.GAME, o) == RendererChoice.project_method()
		and RendererChoice.project_method() == "forward_plus",
		"the game's own renderer (Forward+) removes it")
	Settings.use_file(TEST_FILE, PackedStringArray([o, GUARD_FILE]))
	Settings.set_value(&"renderer", RendererChoice.Choice.COMPATIBILITY)
	_check(RendererChoice.override_method(o) == RendererChoice.COMPATIBILITY and Settings.renderer_needs_restart(),
		"Settings ▸ Renderer ▸ Compatibility writes the file, and waits for a restart")
	Settings.set_value(&"renderer", RendererChoice.Choice.AUTOMATIC)
	var real: String = RendererChoice.OVERRIDE_PATH
	var before: String = FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>"
	Settings.use_file(TEST_FILE)
	Settings.set_value(&"renderer", RendererChoice.Choice.COMPATIBILITY)
	var after: String = FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>"
	_check(not FileAccess.file_exists(o) and Settings.renderer_paths() == PackedStringArray(["", ""]) and after == before,
		"a settings file that is not the player's own writes no renderer file (the player's is untouched)")
	Settings.set_value(&"renderer", RendererChoice.Choice.AUTOMATIC)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD_FILE))


func _start_guard() -> void:
	var g: String = GUARD_FILE
	var A: int = RendererChoice.Choice.AUTOMATIC
	var amd: String = "AMD Radeon RX 9060 XT"
	_check(RendererChoice.on_start(A, "Intel(R) Iris(R) Plus Graphics", "forward_plus", false, g) == RendererChoice.REASON_GPU,
		"Automatic on Forward+ with an Iris Plus switches before anything is drawn (the friend's laptop)")
	_check(RendererChoice.on_start(RendererChoice.Choice.GAME, "Intel(R) Iris(R) Plus Graphics", "forward_plus", false, g) == "",
		"but not when the player chose the full renderer")
	_check(RendererChoice.on_start(A, "Intel(R) Iris(R) Plus Graphics", RendererChoice.COMPATIBILITY, false, g) == "",
		"nor once it is on Compatibility")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g))
	_check(RendererChoice.on_start(A, amd, "forward_plus", true, g) == "", "a first start on a good GPU carries on")
	var cfg := ConfigFile.new()
	cfg.load(g)
	_check(cfg.get_value("start", "method", "") == "forward_plus" and cfg.get_value("start", "ok", true) == false,
		"and is recorded as not yet good")
	_check(RendererChoice.on_start(A, amd, "forward_plus", true, g) == RendererChoice.REASON_CRASH,
		"an exported start after one that never got going on Forward+ switches (it crashed)")
	_check(RendererChoice.on_start(A, amd, "forward_plus", false, g) == "",
		"from the editor it does not (Stop is not a crash)")
	RendererChoice.mark_good(g)
	_check(RendererChoice.on_start(A, amd, "forward_plus", true, g) == "", "after a start marked good, the next carries on")
	_check(RendererChoice.on_start(RendererChoice.Choice.GAME, amd, "forward_plus", true, g) == "",
		"a chosen renderer is never switched")
	RendererChoice.switch(RendererChoice.REASON_CRASH, OVERRIDE_FILE, g)
	_check(RendererChoice.override_method(OVERRIDE_FILE) == RendererChoice.COMPATIBILITY
		and RendererChoice.on_start(A, amd, RendererChoice.COMPATIBILITY, true, g) == "",
		"the switch writes Compatibility, and its own restart is not counted as a crash")
	var said: String = RendererChoice.take_announcement(g)
	_check(said.contains("Compatibility") and RendererChoice.take_announcement(g) == "",
		"the next start says why, once (\"%s\")" % said)
	_check(RendererChoice.on_start(A, amd, "dummy", true, "") == "" and RendererChoice.on_start(A, amd, "dummy", true, g) == "",
		"a test (no guard file) and a headless process are never switched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g))


func _panel() -> void:
	Settings.use_file(TEST_FILE, PackedStringArray([OVERRIDE_FILE, GUARD_FILE]))
	var panel := SettingsPanel.new()
	get_tree().root.add_child(panel)
	panel.open()
	await get_tree().process_frame
	var quality: OptionButton = panel.control_for(&"quality") as OptionButton
	_check(quality != null and quality.item_count == 4, "the panel shows Graphics quality: Low, Medium, High, Custom")
	quality.select(Settings.QUALITY_LOW)
	quality.item_selected.emit(Settings.QUALITY_LOW)
	_check((panel.control_for(&"shadow_quality") as OptionButton).selected == 0
		and (panel.control_for(&"effects") as OptionButton).selected == 0
		and is_equal_approx((panel.control_for(&"render_scale").get_node(^"Slider") as HSlider).value, 70.0),
		"choosing Low there moves Shadows, Lighting effects and Render scale with it")
	(panel.control_for(&"detail") as OptionButton).item_selected.emit(2)
	_check(quality.selected == Settings.QUALITY_CUSTOM, "and changing one shows Custom")
	var row: Control = panel.restart_row(&"renderer")
	(panel.control_for(&"renderer") as OptionButton).item_selected.emit(RendererChoice.Choice.COMPATIBILITY)
	_check(row != null and row.visible and row.get_node_or_null(^"RestartNow") is Button,
		"choosing a renderer this game is not running on offers Restart now")
	(panel.control_for(&"renderer") as OptionButton).item_selected.emit(RendererChoice.Choice.AUTOMATIC)
	panel.queue_free()
	Settings.reset(Settings.VIDEO)
