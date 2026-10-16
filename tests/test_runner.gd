extends Node

const SUITE_DIR: String = "res://tests/suites/"
## Inferred, not annotated: a preloaded script is usable as a TYPE only through a const it infers.
const SuiteBase := preload("res://tests/suite_base.gd")
## Every suite, in the order they run. ORDER MATTERS: suites share autoloads, and a later one can
## depend on state an earlier one left. A file in tests/suites/ that is not listed here fails the run.
const SUITES: PackedStringArray = [
	"golden",
	"config",
	"rules",
	"row_event",
	"interest",
	"authority",
	"npc",
	"bots",
	"entity_registry",
	"component",
	"challenge",
	"level_bake",
	"entity",
	"spawner",
	"health",
	"single_delivery",
	"movement",
	"zones",
	"noise",
	"record",
	"telemetry",
	"prediction",
	"input",
	"session",
	"inventory",
	"interaction",
	"action",
	"referee",
	"bodies",
	"carry",
	"mouse_capture",
	"connect",
	"version",
	"content",
	"presence",
	"status",
	"hold",
	"press",
	"play_as",
	"workbench",
	"settings",
	"music",
	"looks",
	"genres",
	"match",
	"lobby",
	"levels",
	"camera",
	"animation",
	"character",
	"pose",
	"animation_scene",
	"remote_animation",
	"greybox",
	"equip",
]


## `-- --only=lakeside,characters` runs just those suites, named as `_run_all` names them, for
## iterating on one. Only the full run counts: suites share autoloads, and a later one can
## depend on state an earlier one left.
var _only: PackedStringArray = PackedStringArray()




func _on(suite: String) -> bool:
	return _only.is_empty() or _only.has(suite)




func _ready() -> void:
	# One frame later, not now: during _ready the scene tree root is still "setting up
	# children" and refuses add_child(), which the entity suites need in order to put a
	# CharacterBody3D in the tree. Autoloads are already up by _ready, so this deferral is
	# only about tree state.
	_run_all.call_deferred()


func _run_all() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	var unlisted: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(SUITE_DIR):
		if f.ends_with(".gd") and not SUITES.has(f.get_basename()):
			unlisted.append(f)
	if not unlisted.is_empty():
		printerr("  FAIL: suites in %s that the runner does not list (add them to SUITES): %s" % [SUITE_DIR, unlisted])
		SuiteBase._failures += 1
	for name: String in SUITES:
		if not _on(name):
			continue
		var script: GDScript = load(SUITE_DIR + name + ".gd") as GDScript
		# A suite that does not compile fails the run and the rest go on: without this the runner
		# called .new() on nothing, its coroutine died, and the run hung until killed.
		if script == null or not script.can_instantiate():
			printerr("  FAIL: suite '%s' does not compile (its errors are above)" % name)
			SuiteBase._failures += 1
			continue
		var suite: SuiteBase = script.new() as SuiteBase
		suite.name = name
		add_child(suite)
		await suite.run()
		suite.queue_free()
	# Then every genre's own suites (`game/<genre>/tests/suites/*.gd`, by name), for the genres
	# shared/game.json lists: a genre's tests go with it, and a game without it never runs them.
	for genre: String in Genres.listed():
		var dir: String = "res://game/%s/tests/suites/" % genre
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		files.sort()
		for f: String in files:
			if not f.ends_with(".gd") or not _on(f.get_basename()):
				continue
			var gscript: GDScript = load(dir + f) as GDScript
			if gscript == null or not gscript.can_instantiate():
				printerr("  FAIL: suite '%s' does not compile (its errors are above)" % f)
				SuiteBase._failures += 1
				continue
			var gsuite: SuiteBase = gscript.new() as SuiteBase
			gsuite.name = f.get_basename()
			add_child(gsuite)
			await gsuite.run()
			gsuite.queue_free()
	var passes: int = SuiteBase._passes
	var failures: int = SuiteBase._failures
	print("\n%d passed, %d failed" % [passes, failures])
	# Let queued frees actually run before exiting, so the engine's exit-time leak report
	# reflects real leaks rather than nodes that simply had not been collected yet. The
	# harness fails on unexpected engine errors, and that report is one of them.
	await get_tree().process_frame
	await get_tree().process_frame
	AppExit.quit(get_tree(), 1 if failures > 0 else 0)
