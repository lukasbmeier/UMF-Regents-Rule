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

## The actions the foundation lets a player rebind. A game adds its own with `define_key`.
const FOUNDATION_KEYS: Array[Array] = [
	[&"move_forward", "Move forward"], [&"move_back", "Move back"],
	[&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"jump", "Jump"], [&"sprint", "Sprint"], [&"move_slow", "Walk slowly"],
	[&"interact", "Interact"], [&"camera_freelook", "Look around (hold)"],
	[&"lobby_ready", "Ready (lobby)"], [&"lobby_team", "Change team (lobby)"],
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
	_define_foundation()


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
func define(key: StringName, tab: String, label: String, kind: Kind, default: Variant,
		opts: Dictionary = {}) -> void:
	var e: Dictionary = {
		"key": key, "tab": tab, "label": label, "kind": kind, "default": default,
		"min": float(opts.get("min", 0.0)), "max": float(opts.get("max", 1.0)),
		"step": float(opts.get("step", 0.01)),
		"choices": PackedStringArray(opts.get("choices", PackedStringArray())),
		"format": String(opts.get("format", "")), "tooltip": String(opts.get("tooltip", "")),
		"apply": opts.get("apply", Callable()),
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


## Every setting on `tab` back to its default.
func reset(tab: String) -> void:
	for e: Dictionary in entries(tab):
		set_value(e["key"], e["default"])


## Run on the defaults from now on, reading and writing no file (tests).
func use_defaults() -> void:
	_path = ""
	_cfg = ConfigFile.new()
	for e: Dictionary in _entries:
		_values[e["key"]] = _valid(e, e["default"])
		_apply(e)


## Read and write `path` from now on (tests: a file of their own).
func use_file(file: String) -> void:
	_path = file
	_cfg = ConfigFile.new()
	_cfg.load(_path)
	for e: Dictionary in _entries:
		var saved: Variant = _saved(e)
		_values[e["key"]] = _valid(e, saved) if saved != null else _valid(e, e["default"])
		_apply(e)


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
	define(&"max_fps", VIDEO, "Frame rate limit", Kind.CHOICE, 0, {
		"choices": PackedStringArray(["Unlimited", "30", "60", "120", "144", "165", "240"]),
		"apply": func(v: Variant) -> void:
			if _display:
				var label: String = entry(&"max_fps")["choices"][int(v)]
				Engine.max_fps = 0 if not label.is_valid_int() else int(label),
	})
	define(&"render_scale", VIDEO, "Render scale", Kind.SLIDER, 100.0, {
		"min": 50.0, "max": 100.0, "step": 5.0, "format": "%d%%",
		"tooltip": "Below 100% draws the 3D world at a lower resolution (upscaled with FSR): faster, softer.",
		"apply": func(v: Variant) -> void:
			var root: Window = get_tree().root
			root.scaling_3d_scale = float(v) / 100.0
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(v) < 100.0 \
				else Viewport.SCALING_3D_MODE_BILINEAR,
	})
	define(&"anti_aliasing", VIDEO, "Anti-aliasing", Kind.CHOICE, 2, {
		"choices": PackedStringArray(["Off", "FXAA", "TAA"]),
		"tooltip": "TAA is the smoothest; FXAA is cheaper and softer.",
		"apply": func(v: Variant) -> void:
			var root: Window = get_tree().root
			root.use_taa = int(v) == 2
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(v) == 1 \
				else Viewport.SCREEN_SPACE_AA_DISABLED,
	})
	define(&"shadows", VIDEO, "Shadows", Kind.CHOICE, 2, {
		"choices": PackedStringArray(["Low", "Medium", "High"]),
		"apply": func(v: Variant) -> void:
			var size: int = 2048 if int(v) == 0 else 4096
			RenderingServer.directional_shadow_atlas_set_size(size, true)
			# High is what the project ships (soft_shadow_filter_quality = 3).
			var quality: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_HARD,
				RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][int(v)]
			RenderingServer.directional_soft_shadow_filter_set_quality(quality),
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
	define(&"mouse_sensitivity", CONTROLS, "Mouse sensitivity", Kind.SLIDER, 1.0, {
		"min": 0.1, "max": 3.0, "step": 0.05, "format": "%.2f×",
	})
	define(&"invert_y", CONTROLS, "Invert mouse look up and down", Kind.TOGGLE, false)
	for k: Array in FOUNDATION_KEYS:
		if InputMap.has_action(k[0]):
			define_key(k[0], k[1])
	define(&"splash_at_start", GAME, "Splash screen at start", Kind.TOGGLE, true, {
		"tooltip": "The game's name and its tips for a few seconds before connecting. Off: straight to the connect screen (handy while testing).",
	})


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
