class_name RendererChoice extends RefCounted
## WHICH RENDERER THIS MACHINE STARTS ON (DECISIONS #282). Godot picks its renderer once, as it
## starts, from the project's settings; nothing can change it while the game runs. A friend's Intel
## Iris Plus crashed on Forward+ and could only play with `--rendering-method gl_compatibility` on
## the command line. So the choice is a file the ENGINE reads at start: `project.godot`'s
## `application/config/project_settings_override` names `user://renderer.cfg`, and that file, when it
## exists, says `rendering/renderer/rendering_method`. The editor never reads it (Godot skips the
## override in the editor), so a player's choice cannot change the project.
##
## Settings ▸ Video ▸ Renderer (`Settings`'s `renderer`) writes it; the game's own renderer means no
## file. AUTOMATIC (the default) also writes it by itself, then restarts the game once:
##   - on a weak integrated GPU (`LEGACY_GPUS`: Intel's HD, UHD and Iris Plus/Pro families, whose
##     drivers are frozen and crash or crawl on Forward+), before anything is drawn;
##   - after a start that never got going (THE START GUARD, exported builds only): every start writes
##     `user://renderer_guard.cfg` (the renderer, `ok = false`) and marks it `ok` once a world has been
##     on screen for `GOOD_START_S` or the game quits through `AppExit`. A start that finds the last
##     one on the same renderer never marked crashed there: it switches to Compatibility.
## The next start says so once (`take_announcement`, a notice in the world).
##
## A renderer named on the command line (`--rendering-method`) is the player's: nothing is changed.
## Tests (and UMF_SETTINGS=none) never write either file unless they pass their own paths.

const OVERRIDE_PATH: String = "user://renderer.cfg"
const GUARD_PATH: String = "user://renderer_guard.cfg"
const COMPATIBILITY: String = "gl_compatibility"

## Settings' `renderer` choices, by index (stored by position: append, never reorder).
enum Choice { AUTOMATIC, GAME, COMPATIBILITY }

## A world on screen this long, and the start counts as good.
const GOOD_START_S: float = 5.0

## Adapter names (lower case) of GPUs that start on Compatibility under Automatic: Intel's integrated
## graphics before Xe (Gen 7.5 to Gen 11: HD, UHD 6xx, Iris Plus, Iris Pro, plain Iris 5xx/6xx). Their
## Windows drivers are on Intel's legacy branch (no fixes since 2024). Iris Xe, Arc and the plain
## "Intel(R) Graphics" of newer chips are NOT listed: they run Forward+.
const LEGACY_GPUS: PackedStringArray = [
	"intel(r) hd graphics", "intel hd graphics",
	"intel(r) uhd graphics 6", "intel(r) uhd graphics 61", "intel(r) uhd graphics 62", "intel(r) uhd graphics 63",
	"intel(r) iris(r) plus", "intel iris plus", "intel(r) iris(r) pro", "intel iris pro",
	"intel(r) iris(r) graphics 5", "intel(r) iris(r) graphics 6",
]

## Why Automatic switched, for the notice.
const REASON_GPU: String = "gpu"
const REASON_CRASH: String = "crash"


## Whether `adapter` (RenderingServer.get_video_adapter_name()) is one `LEGACY_GPUS` names.
static func is_legacy_gpu(adapter: String) -> bool:
	var a: String = adapter.to_lower()
	if a.contains("iris(r) xe") or a.contains("iris xe") or a.contains("arc"):
		return false
	for p: String in LEGACY_GPUS:
		if a.begins_with(p):
			return true
	return false


## The renderer this process runs on ("forward_plus", "mobile", "gl_compatibility"; "dummy" headless).
static func running() -> String:
	return RenderingServer.get_current_rendering_method()


## The project's own renderer (what runs with no override file). Not the setting itself: with the
## file in place that IS the file's. The editor writes the project's renderer into its feature tags,
## which the file never names.
static func project_method() -> String:
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	if features.has("GL Compatibility"):
		return COMPATIBILITY
	if features.has("Mobile"):
		return "mobile"
	return "forward_plus"


## Whether the command line named the renderer (then it is the player's, and nothing is written).
static func from_command_line() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	return args.has("--rendering-method") or args.has("--rendering-driver")


## The renderer the override file names, "" for none.
static func override_method(path: String = OVERRIDE_PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return String(cfg.get_value("rendering", "renderer/rendering_method", ""))


## The renderer the next start will use for `choice` (Automatic keeps what it chose by itself).
static func method_for(choice: int, path: String = OVERRIDE_PATH) -> String:
	match choice:
		Choice.COMPATIBILITY:
			return COMPATIBILITY
		Choice.GAME:
			return project_method()
	var auto: String = override_method(path)
	return auto if not auto.is_empty() else project_method()


## Write the override file for `choice`: Compatibility names it, the game's own renderer removes the
## file, Automatic leaves what Automatic chose (or nothing). `reason` marks Automatic's own switch.
static func write(choice: int, path: String = OVERRIDE_PATH, reason: String = "") -> void:
	if path.is_empty():
		return
	if choice == Choice.GAME or (choice == Choice.AUTOMATIC and reason.is_empty()
			and _override_reason(path).is_empty()):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	if choice == Choice.AUTOMATIC and reason.is_empty():
		return   # Automatic's own earlier switch stays
	var cfg := ConfigFile.new()
	# The engine reads [rendering]; [umf] is ours (it becomes the harmless setting "umf/reason").
	cfg.set_value("rendering", "renderer/rendering_method", COMPATIBILITY)
	cfg.set_value("rendering", "renderer/rendering_method.mobile", COMPATIBILITY)
	cfg.set_value("umf", "reason", reason if not reason.is_empty() else "chosen")
	var err: Error = cfg.save(path)
	if err != OK:
		push_warning("RendererChoice: could not save %s (%s)" % [path, error_string(err)])


static func _override_reason(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var r: String = String(cfg.get_value("umf", "reason", ""))
	return r if r != "chosen" else ""


## Automatic's decision at a start: "" to carry on, else the reason to switch to Compatibility.
## `exported` turns the start guard on (an editor's Stop is not a crash). Records this start.
static func on_start(choice: int, adapter: String, method: String, exported: bool,
		guard_path: String = GUARD_PATH) -> String:
	if guard_path.is_empty() or method == "dummy":
		return ""
	var guard := ConfigFile.new()
	guard.load(guard_path)
	var last_method: String = String(guard.get_value("start", "method", ""))
	var last_ok: bool = bool(guard.get_value("start", "ok", true))
	guard.set_value("start", "method", method)
	guard.set_value("start", "ok", false)
	guard.set_value("start", "at", Time.get_unix_time_from_system())
	guard.save(guard_path)
	if choice != Choice.AUTOMATIC or method == COMPATIBILITY:
		return ""
	if is_legacy_gpu(adapter):
		return REASON_GPU
	if exported and last_method == method and not last_ok:
		return REASON_CRASH
	return ""


## This start got going: a world was on screen for a while, or the game quit on purpose.
static func mark_good(guard_path: String = GUARD_PATH) -> void:
	if guard_path.is_empty():
		return
	var guard := ConfigFile.new()
	if guard.load(guard_path) != OK or bool(guard.get_value("start", "ok", true)):
		return
	guard.set_value("start", "ok", true)
	guard.save(guard_path)


## Switch to Compatibility for `reason`, to be said at the next start.
static func switch(reason: String, path: String = OVERRIDE_PATH, guard_path: String = GUARD_PATH) -> void:
	write(Choice.AUTOMATIC, path, reason)
	if guard_path.is_empty():
		return
	var guard := ConfigFile.new()
	guard.load(guard_path)
	guard.set_value("start", "ok", true)   # the restart is not a crash
	guard.set_value("notice", "reason", reason)
	guard.save(guard_path)


## The notice owed for Automatic's switch, once: "" when there is none.
static func take_announcement(guard_path: String = GUARD_PATH) -> String:
	if guard_path.is_empty():
		return ""
	var guard := ConfigFile.new()
	if guard.load(guard_path) != OK or not guard.has_section_key("notice", "reason"):
		return ""
	var reason: String = String(guard.get_value("notice", "reason"))
	guard.erase_section("notice")
	guard.save(guard_path)
	if reason == REASON_GPU:
		return "This computer's graphics run best on the Compatibility renderer, so the game uses it. Settings ▸ Video ▸ Renderer to change."
	return "The full renderer stopped the game last time, so it now uses Compatibility. Settings ▸ Video ▸ Renderer to change."


## Restart the game the way it was started (the new renderer takes effect), its own arguments after
## `--` included: `get_cmdline_args` leaves them out, and the restart then lost a game's flags.
static func restart(tree: SceneTree) -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var own: PackedStringArray = OS.get_cmdline_user_args()
	if not own.is_empty():
		args.append("--")
		args.append_array(own)
	OS.set_restart_on_exit(true, args)
	AppExit.quit(tree)
