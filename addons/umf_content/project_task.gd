@tool
class_name ProjectTask extends RefCounted
## ONE OF THIS PROJECT'S SCRIPTS, RUN FROM THE EDITOR WITHOUT FREEZING IT (DECISIONS #200): the
## Content Dock's Publish, and any later button that runs `tools/<x>.sh` (release, update from the
## template). It starts the script the way `tools\run.cmd` does (Git Bash on Windows, through
## `tools/run_env.sh`, which reads `tools/local.env`), and hands back its output line by line as
## it comes: call `poll()` every frame until `is_running()` is false, then read `exit_code`.

## A line of output arrived (stdout and stderr both).
signal line(text: String)
## The script ended.
signal finished(exit_code: int)

var exit_code: int = -1
var _pid: int = -1
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _partial: String = ""
var _partial_err: String = ""


## Start `script` (a repo-relative path like "tools/publish.sh") with `args`. False, with a line
## saying why, when it cannot start.
func start(script: String, args: PackedStringArray = PackedStringArray()) -> bool:
	var bash: String = bash_path()
	if bash.is_empty():
		line.emit("Git Bash was not found. Install Git for Windows: https://git-scm.com/download/win")
		return false
	var run_env: String = ProjectSettings.globalize_path("res://tools/run_env.sh")
	var argv := PackedStringArray([run_env, script])
	argv.append_array(args)
	var p: Dictionary = OS.execute_with_pipe(bash, argv, false)
	if p.is_empty():
		line.emit("could not start %s" % script)
		return false
	_pid = int(p["pid"])
	_stdio = p["stdio"]
	_stderr = p["stderr"]
	exit_code = -1
	return true


func is_running() -> bool:
	return _pid > 0


## Pass on what the script has written since the last call; notice when it has ended.
func poll() -> void:
	if _pid <= 0:
		return
	_partial = _drain(_stdio, _partial)
	_partial_err = _drain(_stderr, _partial_err)
	if not OS.is_process_running(_pid):
		_partial = _drain(_stdio, _partial)
		_partial_err = _drain(_stderr, _partial_err)
		for rest: String in [_partial, _partial_err]:
			if not rest.is_empty():
				line.emit(rest)
		_partial = ""
		_partial_err = ""
		exit_code = OS.get_process_exit_code(_pid)
		_pid = -1
		_stdio = null
		_stderr = null
		finished.emit(exit_code)


## Stop it.
func cancel() -> void:
	if _pid > 0:
		OS.kill(_pid)


## Where bash is: Git for Windows' on Windows (never WSL's), `bash` elsewhere.
static func bash_path() -> String:
	if OS.get_name() != "Windows":
		return "bash"
	for base: String in [OS.get_environment("ProgramFiles"), OS.get_environment("ProgramW6432"),
			OS.get_environment("LocalAppData").path_join("Programs")]:
		if base.is_empty():
			continue
		var p: String = base.path_join("Git/bin/bash.exe")
		if FileAccess.file_exists(p):
			return p
	return ""


func _drain(pipe: FileAccess, partial: String) -> String:
	if pipe == null:
		return partial
	var chunk: PackedByteArray = pipe.get_buffer(65536)
	if chunk.is_empty():
		return partial
	var text: String = partial + chunk.get_string_from_utf8().replace("\r", "")
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size() - 1:
		line.emit(lines[i])
	return lines[lines.size() - 1]
