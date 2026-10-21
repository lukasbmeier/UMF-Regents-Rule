class_name ChronicleLauncher extends Node
## STARTS THE HOST'S CHRONICLE FOR AN EDITOR RUN (DECISIONS #276), so a designer's playtest is kept for
## looking back as a host's is (`tools/host.sh` starts one too): when this client is the admin, run from
## the editor against a server on this machine, and nothing is recording the database yet, it starts
## `tools/telemetry/chronicle.py` beside it (`--parent-alive=<file>`). The chronicle ends a few seconds
## after this game does, the way the referee does (`RefereeLauncher.touch_alive` / `is_alive`). A second
## instance (Luke plays two) finds the chronicle's lock fresh and starts nothing; so does a run while the
## telemetry page or a host already records.
##
## Outside an editor run it does nothing. The chronicle is a separate process from the project folder (a
## Python script, standard library only); nothing here uses its code. No Python on this machine: nothing
## is recorded and the log says so once.

const CHRONICLE: String = "res://tools/telemetry/chronicle.py"
## How long after connecting it looks (the authority rows that say who is admin arrive first).
const SETTLE_S: float = 3.0
## The chronicle's lock is fresh while touched in the last this-many seconds (chronicle.py LOCK_FRESH_S).
const LOCK_FRESH_S: float = 10.0
const ALIVE_EVERY_S: float = 1.0

## Off: never starts one (a test).
@export var enabled: bool = true

## The process started, if any (0: none).
var started_pid: int = 0
## Why it did not start one ("" when it did or has not looked yet).
var reason: String = ""

var _wait: float = 0.0
var _looked: bool = false
var _alive_path: String = ""
var _alive_t: float = 0.0


func _process(delta: float) -> void:
	if not _alive_path.is_empty():
		_alive_t += delta
		if _alive_t >= ALIVE_EVERY_S:
			_alive_t = 0.0
			RefereeLauncher.touch_alive(_alive_path)
	if not enabled or _looked:
		return
	if not SpaceTimeSync.is_connected_to_server() or not InterestManager.has_world():
		return
	_wait += delta
	if _wait < SETTLE_S:
		return
	_looked = true
	reason = why_not()
	if not reason.is_empty():
		print("[Chronicle] not starting one: ", reason)
		return
	start()


func _exit_tree() -> void:
	if not _alive_path.is_empty():
		DirAccess.remove_absolute(_alive_path)


## Why this run should not start a chronicle, or "" when it should.
func why_not() -> String:
	if not OS.has_feature("editor"):
		return "not an editor run"
	if not Roles.is_local_admin():
		return "this client is not the admin"
	if SpaceTimeSync.config == null or not RefereeLauncher.is_local_host(SpaceTimeSync.config.host):
		return "the server is not on this machine"
	if not FileAccess.file_exists(CHRONICLE):
		return "this project has no chronicle"
	if lock_fresh(lock_path(SpaceTimeSync.database_name(SpaceTimeSync.config))):
		return "the database is already being recorded"
	return ""


## The lock file of the chronicle that records `db` (chronicle.py `default_file` + ".lock").
static func lock_path(db: String) -> String:
	return ProjectSettings.globalize_path("res://build/telemetry/%s.sqlite.lock" % db)


## Whether a chronicle holds `path`: touched in the last `LOCK_FRESH_S` seconds.
static func lock_fresh(path: String, fresh_s: float = LOCK_FRESH_S) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path)) < fresh_s


## The Python to run it with: PYTHON if set, else the first of python, py, python3 that answers.
static func python() -> String:
	var named: String = OS.get_environment("PYTHON")
	var tries: PackedStringArray = [named] if not named.is_empty() else PackedStringArray()
	tries.append_array(["python", "py", "python3"])
	for p: String in tries:
		var out: Array = []
		if OS.execute(p, ["--version"], out, true) == 0:
			return p
	return ""


func start() -> void:
	var py: String = python()
	if py.is_empty():
		reason = "no Python on this machine (tools/telemetry needs it)"
		print("[Chronicle] not starting one: ", reason)
		return
	_alive_path = ProjectSettings.globalize_path("user://chronicle_parent_%d.alive" % OS.get_process_id())
	RefereeLauncher.touch_alive(_alive_path)
	var db: String = SpaceTimeSync.database_name(SpaceTimeSync.config)
	var args: PackedStringArray = [ProjectSettings.globalize_path(CHRONICLE), "--db=" + db, "--parent-alive=" + _alive_path]
	started_pid = OS.create_process(py, args)
	print("[Chronicle] recording %s for looking back (pid %d): tools\\telemetry.cmd shows it" % [db, started_pid])
