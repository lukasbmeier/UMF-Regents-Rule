extends Node
## Settings — THIS MACHINE'S choices: video, audio and controls (DECISIONS #165).
##
## Saved to `user://settings.cfg`, one file per machine rather than per identity (ConnectSettings
## is per identity): the screen, the speakers and the mouse belong to the machine, whoever plays.
##
## EVERY SETTING IS DATA. `define()` adds one (a key, the tab it shows on, its label, its kind and
## default, and what applying it does); the settings panel (`foundation/ui/settings_panel.gd`)
## draws whatever is defined, in order. A game adds its own the same way, from its own scripts,
## and never edits the panel: fishing names its cast and give buttons with `define_key`.
##
## Code that cares reads a value (`get_value`, or the shortcuts below) and listens to `changed`;
## nothing else stores a copy. The foundation's own are applied here: the window, frame pacing and
## rendering, the audio buses (`res://default_bus_layout.tres`), mouse look (read by
## LocalInputComponent) and key bindings (InputMap).
##
## GRAPHICS QUALITY (DECISIONS #282): `quality` (Low / Medium / High) sets the video settings in
## `QUALITY_PRESETS` together; changing one of them by hand makes it Custom. What the levels' own
## effects, lights and designer groups do is `GraphicsQuality`; which renderer the game starts on is
## `RendererChoice` (`renderer`, used at the next start). A fresh install starts on High, or on Low
## when the game runs on Compatibility or on a weak GPU (`RendererChoice.LEGACY_GPUS`).
##
## TESTS AND HARNESSES keep off the player's file: a process started by a test suite (UMF_DB set,
## DECISIONS #154) or with UMF_SETTINGS=none runs on the defaults and saves nothing, so a player who
## chose fullscreen does not get a fullscreen test window. UMF_SETTINGS=<path> uses another file.

signal changed(key: StringName, value: Variant)

const DEFAULT_PATH: String = "user://settings.cfg"

enum Kind { TOGGLE, SLIDER, CHOICE, KEY }

## The tabs the foundation fills, in order. A game may add its own tab by naming it.
const VIDEO: String = "Video"
const AUDIO: String = "Audio"
const CONTROLS: String = "Controls"
const GAME: String = "Game"

## The buses sounds are sent to, by name (`res://default_bus_layout.tres`); each has a volume here.
const BUS_MUSIC: StringName = &"Music"
const BUS_EFFECTS: StringName = &"Effects"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_VOICE: StringName = &"Voice"

## THE QUALITY PRESETS, Low, Medium, High (the index is `quality`'s value; Custom is the next one).
## Each names a value for every setting in `PRESET_KEYS`. High is the game's full look, and was every
## machine's look before presets existed. The costs behind Low and Medium: DECISIONS #282.
const QUALITY_PRESETS: Array[Dictionary] = [
	{&"render_scale": 70.0, &"anti_aliasing": 1, &"shadow_quality": 0, &"effects": 0, &"detail": 0, &"max_fps": 2},
	{&"render_scale": 85.0, &"anti_aliasing": 1, &"shadow_quality": 2, &"effects": 1, &"detail": 1, &"max_fps": 0},
	{&"render_scale": 100.0, &"anti_aliasing": 2, &"shadow_quality": 3, &"effects": 2, &"detail": 2, &"max_fps": 0},
]
const PRESET_KEYS: Array[StringName] = [&"render_scale", &"anti_aliasing", &"shadow_quality", &"effects", &"detail", &"max_fps"]
const QUALITY_LOW: int = 0
const QUALITY_HIGH: int = 2
const QUALITY_CUSTOM: int = 3

## The actions the foundation lets a player rebind. A game adds its own with `define_key`.
const FOUNDATION_KEYS: Array[Array] = [
	[&"move_forward", "Move forward"], [&"move_back", "Move back"],
	[&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"jump", "Jump"], [&"sprint", "Sprint"], [&"move_slow", "Walk slowly"],
	[&"interact", "Interact"], [&"skill_check", "Skill check"], [&"ping", "Ping"], [&"camera_freelook", "Look around (hold)"],
	[&"lobby_ready", "Ready (lobby)"], [&"lobby_team", "Change team (lobby)"],
	[&"lobby_character", "Play another character (lobby)"],
]

## "" while running on the defaults alone (tests): nothing is read or written.
var _path: String = DEFAULT_PATH
var _cfg: ConfigFile = ConfigFile.new()
## Every definition, in the order defined: {key, tab, label, kind, default, min, max, step,
## choices, format, tooltip, apply}.
var _entries: Array[Dictionary] = []
var _values: Dictionary[StringName, Variant] = {}
var _display: bool = true
## Per action, the binding `_bind` last put on it, so the next one takes it off again.
var _applied_keys: Dictionary[StringName, String] = {}
## The renderer's files (`RendererChoice`): "" unless this is the player's own settings file.
var _renderer_path: String = ""
var _guard_path: String = ""
## While a preset sets its members (they do not make it Custom).
var _applying_preset: bool = false
var _defined: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_display = DisplayServer.get_name() != "headless"
	var env: String = OS.get_environment("UMF_SETTINGS")
	if env == "none" or (env.is_empty() and not OS.get_environment("UMF_DB").is_empty()):
		_path = ""
	elif not env.is_empty():
		_path = env
	if not _path.is_empty():
		_cfg.load(_path)   # a fresh install has no file: every value is its default
	if _path == DEFAULT_PATH:
		_renderer_path = RendererChoice.OVERRIDE_PATH
		_guard_path = RendererChoice.GUARD_PATH
	_define_foundation()
	_defined = true
	_quality_from_members()
	get_tree().node_added.connect(GraphicsQuality.apply_node)
	_start_renderer()


# --- reading -------------------------------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return _values.get(key)


## Mouse look's multiplier (1.0 = the game's own speed).
func look_sensitivity() -> float:
	return float(_values.get(&"mouse_sensitivity", 1.0))


func invert_look() -> bool:
	return bool(_values.get(&"invert_y", false))


## Every definition on `tab` (all of them for ""), in order.
func entries(tab: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if tab.is_empty() or e["tab"] == tab:
			out.append(e)
	return out


## The tabs, in the order their first setting was defined.
func tabs() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in _entries:
		if not out.has(String(e["tab"])):
			out.append(String(e["tab"]))
	return out


func entry(key: StringName) -> Dictionary:
	for e: Dictionary in _entries:
		if e["key"] == key:
			return e
	return {}


## The file in use, "" when running on the defaults.
func path() -> String:
	return _path


# --- defining ------------------------------------------------------------------------------

## Add a setting (or replace one with the same key: a HUD that enters the tree twice). Its value
## is the saved one when there is a valid one, else `default`, and it is applied at once.
##
##   opts.min / max / step   SLIDER range
##   opts.choices            CHOICE labels (the value is the index)
##   opts.format             SLIDER label, e.g. "%d%%" (given the value)
##   opts.tooltip            shown on hover
##   opts.apply              Callable(value) run whenever the value changes, and now
##   opts.restart_needed     Callable() -> bool: the change waits for a restart (the panel offers one)
func define(key: StringName, tab: String, label: String, kind: Kind, default: Variant,
		opts: Dictionary = {}) -> void:
	var e: Dictionary = {
		"key": key, "tab": tab, "label": label, "kind": kind, "default": default,
		"min": float(opts.get("min", 0.0)), "max": float(opts.get("max", 1.0)),
		"step": float(opts.get("step", 0.01)),
		"choices": PackedStringArray(opts.get("choices", PackedStringArray())),
		"format": String(opts.get("format", "")), "tooltip": String(opts.get("tooltip", "")),
		"apply": opts.get("apply", Callable()),
		"restart_needed": opts.get("restart_needed", Callable()),
	}
	var at: int = _index_of(key)
	if at >= 0:
		_entries[at] = e
	else:
		_entries.append(e)
	var saved: Variant = _saved(e)
	_values[key] = _valid(e, saved) if saved != null else _valid(e, default)
	_apply(e)


## A rebindable action. Its default is the binding the project ships (project.godot), its value
## the event's text (`event_to_text`); applying it puts that event on the action.
func define_key(action: StringName, label: String, tab: String = CONTROLS) -> void:
	if not InputMap.has_action(action):
		push_warning("Settings: no input action '%s' to rebind" % action)
		return
	define(action, tab, label, Kind.KEY, event_to_text(_shipped_event(action)), {
		"apply": func(v: Variant) -> void: _bind(action, String(v)),
	})


# --- changing ------------------------------------------------------------------------------

## Change a setting: checked against its definition, applied, announced, saved.
func set_value(key: StringName, value: Variant) -> void:
	var e: Dictionary = entry(key)
	if e.is_empty():
		push_warning("Settings: no setting '%s'" % key)
		return
	var v: Variant = _valid(e, value)
	if _values.get(key) == v:
		return
	_values[key] = v
	_apply(e)
	changed.emit(key, v)
	_save(e)
	if PRESET_KEYS.has(key) and not _applying_preset:
		_match_quality()


## Every setting on `tab` back to its default.
func reset(tab: String) -> void:
	for e: Dictionary in entries(tab):
		set_value(e["key"], e["default"])


## Run on the defaults from now on, reading and writing no file (tests).
func use_defaults() -> void:
	_path = ""
	_renderer_path = ""
	_guard_path = ""
	_cfg = ConfigFile.new()
	_defined = false   # every member takes its own value: no preset runs over them
	for e: Dictionary in _entries:
		_values[e["key"]] = _valid(e, e["default"])
		_apply(e)
	_defined = true


## Read and write `path` from now on (tests: a file of their own). The renderer's files are left
## alone unless `renderer_files` names some (`[override, guard]`, tests' own).
func use_file(file: String, renderer_files: PackedStringArray = PackedStringArray()) -> void:
	_path = file
	_renderer_path = renderer_files[0] if renderer_files.size() == 2 else ""
	_guard_path = renderer_files[1] if renderer_files.size() == 2 else ""
	_cfg = ConfigFile.new()
	_cfg.load(_path)
	_defined = false
	for e: Dictionary in _entries:
		var saved: Variant = _saved(e)
		_values[e["key"]] = _valid(e, saved) if saved != null else _valid(e, e["default"])
		_apply(e)
	_defined = true
	_quality_from_members()


## A file with no quality in it (saved before presets existed, with a render scale changed) says
## what its settings are: the preset they match, or Custom. Nothing is saved.
func _quality_from_members() -> void:
	var e: Dictionary = entry(&"quality")
	if not e.is_empty() and _saved(e) == null:
		_values[&"quality"] = matching_quality()


# --- graphics quality ----------------------------------------------------------------------

## The quality a fresh install starts on: Low on Compatibility or a weak GPU, else High.
static func machine_quality() -> int:
	if RendererChoice.running() == RendererChoice.COMPATIBILITY \
			or RendererChoice.is_legacy_gpu(RenderingServer.get_video_adapter_name()):
		return QUALITY_LOW
	return QUALITY_HIGH


## The preset the members now match, or Custom.
func matching_quality() -> int:
	for i: int in range(QUALITY_PRESETS.size()):
		var all: bool = true
		for k: StringName in PRESET_KEYS:
			if _values.get(k) != _valid(entry(k), QUALITY_PRESETS[i][k]):
				all = false
				break
		if all:
			return i
	return QUALITY_CUSTOM


func _apply_preset(v: int) -> void:
	if not _defined or v < 0 or v >= QUALITY_PRESETS.size():
		return   # Custom keeps what is set; at start every member has its own saved value
	_applying_preset = true
	for k: StringName in PRESET_KEYS:
		set_value(k, QUALITY_PRESETS[v][k])
	_applying_preset = false


func _match_quality() -> void:
	var q: int = matching_quality()
	if _values.get(&"quality") != q:
		_values[&"quality"] = q
		changed.emit(&"quality", q)
		_save(entry(&"quality"))


## The renderer's files (`RendererChoice`), "" when this process keeps off them (tests).
func renderer_paths() -> PackedStringArray:
	return PackedStringArray([_renderer_path, _guard_path])


## Whether the renderer chosen is not the one running (the panel offers a restart).
func renderer_needs_restart() -> bool:
	return RendererChoice.method_for(int(_values.get(&"renderer", 0)), _renderer_path) != RendererChoice.running()


## This start got going (a world was shown a while, or the game quit on purpose).
func mark_start_good() -> void:
	RendererChoice.mark_good(_guard_path)


## Automatic's look at the machine as the game starts (RendererChoice): switch and restart, or
## carry on and mark the start good once a world has been on screen.
func _start_renderer() -> void:
	if _guard_path.is_empty() or not _display or RendererChoice.from_command_line():
		return
	var reason: String = RendererChoice.on_start(int(_values.get(&"renderer", 0)),
		RenderingServer.get_video_adapter_name(), RendererChoice.running(), OS.has_feature("template"), _guard_path)
	if not reason.is_empty():
		print("Settings: starting again on the Compatibility renderer (%s, %s)" % [reason, RenderingServer.get_video_adapter_name()])
		RendererChoice.switch(reason, _renderer_path, _guard_path)
		RendererChoice.restart.call_deferred(get_tree())
		return
	SignalBus.world_ready.connect(_on_world_shown, CONNECT_ONE_SHOT)


func _on_world_shown() -> void:
	var said: String = RendererChoice.take_announcement(_guard_path)
	if not said.is_empty():
		SignalBus.notification_requested.emit(said, 1)
	await get_tree().create_timer(RendererChoice.GOOD_START_S, true, false, true).timeout
	mark_start_good()


# --- key bindings --------------------------------------------------------------------------

## A binding as text, for the file: "key:<physical keycode>" or "mouse:<button index>".
static func event_to_text(ev: InputEvent) -> String:
	var k: InputEventKey = ev as InputEventKey
	if k != null:
		return "key:%d" % (k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	var m: InputEventMouseButton = ev as InputEventMouseButton
	if m != null:
		return "mouse:%d" % m.button_index
	return ""


static func text_to_event(text: String) -> InputEvent:
	var parts: PackedStringArray = text.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	if parts[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		return k
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	return null


## What a binding is called on screen: the key on THIS keyboard's layout, or the mouse button.
static func binding_label(text: String) -> String:
	var ev: InputEvent = text_to_event(text)
	var k: InputEventKey = ev as InputEventKey
	if k != null:
		# On this keyboard's layout where the display server can say (a headless one cannot).
		var shown: Key = KEY_NONE
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return OS.get_keycode_string(shown if shown != KEY_NONE else k.physical_keycode)
	var m: InputEventMouseButton = ev as InputEventMouseButton
	if m != null:
		match m.button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			_: return "Mouse %d" % m.button_index
	return "(none)"


## The other rebindable actions bound to `text`, by label: a clash the panel points out.
func clashes(action: StringName, text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in _entries:
		if e["kind"] == Kind.KEY and e["key"] != action and _values.get(e["key"]) == text:
			out.append(String(e["label"]))
	return out


func _shipped_event(action: StringName) -> InputEvent:
	var shipped: Variant = ProjectSettings.get_setting("input/%s" % action)
	if shipped is Dictionary:
		for ev: Variant in (shipped as Dictionary).get("events", []) as Array:
			if ev is InputEvent:
				return ev as InputEvent
	var now: Array[InputEvent] = InputMap.action_get_events(action)
	return now[0] if not now.is_empty() else null


## The action's PRIMARY binding becomes `text`; any others it ships with stay.
func _bind(action: StringName, text: String) -> void:
	var ev: InputEvent = text_to_event(text)
	if ev == null or not InputMap.has_action(action):
		return
	# Off come the shipped primary and whatever this put on last time; on goes the new one.
	var shipped: InputEvent = _shipped_event(action)
	var gone: Array[String] = [String(_applied_keys.get(action, ""))]
	if shipped != null:
		gone.append(event_to_text(shipped))
	for old: InputEvent in InputMap.action_get_events(action):
		if gone.has(event_to_text(old)):
			InputMap.action_erase_event(action, old)
	_applied_keys[action] = text
	for old: InputEvent in InputMap.action_get_events(action):
		if event_to_text(old) == text:
			return   # already there (it is one of the extra bindings)
	InputMap.action_add_event(action, ev)


# --- the foundation's own ------------------------------------------------------------------

func _define_foundation() -> void:
	var start: Dictionary = QUALITY_PRESETS[machine_quality()]
	define(&"quality", VIDEO, "Graphics quality", Kind.CHOICE, machine_quality(), {
		"choices": PackedStringArray(["Low", "Medium", "High", "Custom"]),
		"tooltip": "Sets the settings below together. Low is for integrated graphics and older laptops; change any one and it is Custom.",
		"apply": func(v: Variant) -> void: _apply_preset(int(v)),
	})
	define(&"renderer", VIDEO, "Renderer", Kind.CHOICE, RendererChoice.Choice.AUTOMATIC, {
		"choices": PackedStringArray(["Automatic", "Full (%s)" % _method_label(RendererChoice.project_method()),
			"Compatibility (older or integrated graphics)"]),
		"tooltip": "Used from the next start. Automatic picks Compatibility on older Intel graphics, or after the full renderer stopped the game.",
		"apply": func(v: Variant) -> void: RendererChoice.write(int(v), _renderer_path),
		"restart_needed": renderer_needs_restart,
	})
	define(&"fullscreen", VIDEO, "Fullscreen", Kind.TOGGLE, false, {
		"tooltip": "F11 or Alt+Enter at any time.",
		"apply": func(v: Variant) -> void:
			if _display and WindowMode.cannot().is_empty() and bool(v) != WindowMode.is_fullscreen():
				WindowMode.toggle(),
	})
	define(&"vsync", VIDEO, "Vertical sync", Kind.TOGGLE, true, {
		"tooltip": "Off can raise the frame rate and lower latency, and can tear.",
		"apply": func(v: Variant) -> void:
			if _display:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(v)
					else DisplayServer.VSYNC_DISABLED),
	})
	define(&"max_fps", VIDEO, "Frame rate limit", Kind.CHOICE, start[&"max_fps"], {
		"choices": PackedStringArray(["Unlimited", "30", "60", "120", "144", "165", "240"]),
		"apply": func(v: Variant) -> void:
			if _display:
				var label: String = entry(&"max_fps")["choices"][int(v)]
				Engine.max_fps = 0 if not label.is_valid_int() else int(label),
	})
	define(&"render_scale", VIDEO, "Render scale", Kind.SLIDER, start[&"render_scale"], {
		"min": 50.0, "max": 100.0, "step": 5.0, "format": "%d%%",
		"tooltip": "Below 100% draws the 3D world at a lower resolution (upscaled with FSR): faster, softer.",
		"apply": func(v: Variant) -> void:
			var root: Window = get_tree().root
			root.scaling_3d_scale = float(v) / 100.0
			# FSR needs the full renderer; Compatibility stretches.
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(v) < 100.0 and not _compatibility() \
				else Viewport.SCALING_3D_MODE_BILINEAR,
	})
	define(&"anti_aliasing", VIDEO, "Anti-aliasing", Kind.CHOICE, start[&"anti_aliasing"], {
		"choices": PackedStringArray(["Off", "FXAA", "TAA"]),
		"tooltip": "TAA is the smoothest; FXAA is cheaper and softer. Compatibility has neither: TAA is 2x MSAA there, FXAA none.",
		"apply": func(v: Variant) -> void:
			var root: Window = get_tree().root
			var compat: bool = _compatibility()
			root.use_taa = int(v) == 2 and not compat
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(v) == 1 and not compat \
				else Viewport.SCREEN_SPACE_AA_DISABLED
			root.msaa_3d = Viewport.MSAA_2X if int(v) == 2 and compat else Viewport.MSAA_DISABLED,
	})
	# Was `shadows` (Low, Medium, High) before Off existed: a saved one is read as the same choice.
	if _cfg.has_section_key("video", "shadows") and not _cfg.has_section_key("video", "shadow_quality"):
		var old_shadows: Variant = _cfg.get_value("video", "shadows")
		if old_shadows is int:
			_cfg.set_value("video", "shadow_quality", clampi(int(old_shadows) + 1, 1, 3))
	define(&"shadow_quality", VIDEO, "Shadows", Kind.CHOICE, start[&"shadow_quality"], {
		"choices": PackedStringArray(["Off", "Low", "Medium", "High"]),
		"tooltip": "Off is the biggest saving on integrated graphics.",
		"apply": func(v: Variant) -> void:
			RenderingServer.directional_shadow_atlas_set_size(2048 if int(v) <= 1 else 4096, true)
			# High is what the project ships (soft_shadow_filter_quality = 3, soft medium).
			var quality: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_HARD,
				RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][int(v)]
			RenderingServer.directional_soft_shadow_filter_set_quality(quality)
			GraphicsQuality.shadows_on = int(v) > 0
			GraphicsQuality.apply_tree(get_tree().root),
	})
	define(&"effects", VIDEO, "Lighting effects", Kind.CHOICE, start[&"effects"], {
		"choices": PackedStringArray(["Off", "Reduced", "Full"]),
		"tooltip": "The level's ambient occlusion, glow, light bounce, reflections and volumetric fog. Reduced keeps ambient occlusion and glow.",
		"apply": func(v: Variant) -> void:
			GraphicsQuality.effects = int(v)
			GraphicsQuality.apply_tree(get_tree().root),
	})
	define(&"detail", VIDEO, "Detail", Kind.CHOICE, start[&"detail"], {
		"choices": PackedStringArray(["Low", "Medium", "High"]),
		"tooltip": "How far models keep their detail and the sun's shadows reach, and how much of a level's extra detail (grass, clutter) is drawn.",
		"apply": func(v: Variant) -> void:
			GraphicsQuality.detail = int(v)
			GraphicsQuality.apply_tree(get_tree().root),
	})
	define(&"ui_scale", VIDEO, "Interface scale", Kind.SLIDER, 100.0, {
		"min": 75.0, "max": 150.0, "step": 5.0, "format": "%d%%",
		"apply": func(v: Variant) -> void:
			get_tree().root.content_scale_factor = float(v) / 100.0,
	})
	define(&"master_volume", AUDIO, "Master volume", Kind.SLIDER, 100.0,
		_volume_opts(&"Master"))
	define(&"music_volume", AUDIO, "Music", Kind.SLIDER, 70.0, _volume_opts(BUS_MUSIC))
	define(&"effects_volume", AUDIO, "Sound effects", Kind.SLIDER, 100.0, _volume_opts(BUS_EFFECTS))
	define(&"ambience_volume", AUDIO, "Ambience", Kind.SLIDER, 100.0, _volume_opts(BUS_AMBIENCE))
	define(&"voice_volume", AUDIO, "Voices", Kind.SLIDER, 100.0, _volume_opts(BUS_VOICE))
	# FIRST-PERSON COMFORT (DECISIONS #234): the view's width (and, under Game, the stride's bob and a carrier's view).
	define(&"fov_offset", VIDEO, "Field of view", Kind.SLIDER, 0.0, {
		"min": -20.0, "max": 20.0, "step": 1.0, "format": "%+d°",
		"tooltip": "Wider or narrower than each character's own view (its camera's field of view).",
	})
	define(&"mouse_sensitivity", CONTROLS, "Mouse sensitivity", Kind.SLIDER, 1.0, {
		"min": 0.1, "max": 3.0, "step": 0.05, "format": "%.2f×",
	})
	define(&"invert_y", CONTROLS, "Invert mouse look up and down", Kind.TOGGLE, false)
	for k: Array in FOUNDATION_KEYS:
		if InputMap.has_action(k[0]):
			define_key(k[0], k[1])
	define(&"head_bob", GAME, "Head bob in first person", Kind.TOGGLE, false, {
		"tooltip": "The view rises and falls with a first-person character's stride. Off is easier on the stomach.",
	})
	define(&"third_person_carrying", GAME, "Third person while carrying", Kind.TOGGLE, true, {
		"tooltip": "A first-person character carrying someone (the wolf with a hen) sees itself from behind until it puts them down.",
	})
	define(&"flight_cam", GAME, "Follow what you throw", Kind.TOGGLE, true, {
		"tooltip": "The camera follows a thrown disc or ball through the air, and comes back as it lands or you move. Off: it stays with you.",
	})
	define(&"splash_at_start", GAME, "Splash screen at start", Kind.TOGGLE, true, {
		"tooltip": "The game's name and its tips for a few seconds before connecting. Off: straight to the connect screen (handy while testing).",
	})


func _compatibility() -> bool:
	return RendererChoice.running() == RendererChoice.COMPATIBILITY


static func _method_label(method: String) -> String:
	match method:
		"forward_plus": return "Forward+"
		"mobile": return "Mobile"
		RendererChoice.COMPATIBILITY: return "Compatibility"
	return method


func _volume_opts(bus: StringName) -> Dictionary:
	return {
		"min": 0.0, "max": 100.0, "step": 1.0, "format": "%d%%",
		"apply": func(v: Variant) -> void:
			var idx: int = AudioServer.get_bus_index(bus)
			if idx < 0:
				return
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(v), 0.0001) / 100.0))
			AudioServer.set_bus_mute(idx, float(v) <= 0.0),
	}


# --- internals -----------------------------------------------------------------------------

func _index_of(key: StringName) -> int:
	for i: int in range(_entries.size()):
		if _entries[i]["key"] == key:
			return i
	return -1


## The value saved for `e`, or null when there is none (or no file).
func _saved(e: Dictionary) -> Variant:
	if _path.is_empty() or not _cfg.has_section_key(_section_of(e), String(e["key"])):
		return null
	return _cfg.get_value(_section_of(e), String(e["key"]))


func _section_of(e: Dictionary) -> String:
	return "keys" if e["kind"] == Kind.KEY else String(e["tab"]).to_lower()


## A value in the shape its definition takes; anything else is the default.
func _valid(e: Dictionary, v: Variant) -> Variant:
	match e["kind"]:
		Kind.TOGGLE:
			return bool(v) if v is bool else bool(e["default"])
		Kind.SLIDER:
			if not (v is float or v is int):
				return float(e["default"])
			return clampf(snappedf(float(v), float(e["step"])), float(e["min"]), float(e["max"]))
		Kind.CHOICE:
			var n: int = (e["choices"] as PackedStringArray).size()
			return int(v) if (v is int or v is float) and int(v) >= 0 and int(v) < n else int(e["default"])
		Kind.KEY:
			return String(v) if v is String and text_to_event(String(v)) != null else String(e["default"])
	return v


func _apply(e: Dictionary) -> void:
	var f: Callable = e["apply"]
	if f.is_valid():
		f.call(_values[e["key"]])


func _save(e: Dictionary) -> void:
	if _path.is_empty():
		return
	_cfg.set_value(_section_of(e), String(e["key"]), _values[e["key"]])
	var err: Error = _cfg.save(_path)
	if err != OK:
		push_warning("Settings: could not save %s (%s)" % [_path, error_string(err)])
