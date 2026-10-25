extends Node
## THE RENDERER, CHOSEN WITH NO COMMAND LINE (DECISIONS #282). Run by tests/render_test.sh in steps,
## each its own process (the renderer is picked as a process starts):
##
##   --step=where      print the user folder (the script backs up the player's renderer files there)
##   --step=default    no file: the game's own renderer (Forward+); then Settings ▸ Renderer ▸
##                     Compatibility writes the file
##   --step=compat     the ENGINE read the file: Compatibility, nothing on the command line; the file
##                     is removed again
##   --step=restart    Forward+ again; Automatic's switch (as on an Iris Plus) writes the file and the
##                     game restarts ITSELF; the new process (same arguments) finds Compatibility and
##                     the notice owed, writes RESULT_FILE and quits
##
## Prints `RENDER PASS`/`RENDER FAIL` per check and exits 1 on any failure.

const GUARD: String = "user://render_test_guard.cfg"
const RESULT_FILE: String = "user://render_test_result.txt"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var step: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--step="):
			step = arg.get_slice("=", 1)
	var method: String = RendererChoice.running()
	match step:
		"where":
			print("RENDER USERDIR ", OS.get_user_data_dir())
			print("RENDER PASS: where")
			AppExit.quit(get_tree(), 0)
			return
		"default":
			_expect(method == "forward_plus" and RendererChoice.override_method() == "",
				"with no file the game starts on its own renderer (%s)" % method)
			Settings.use_file("user://render_test_settings.cfg", PackedStringArray([RendererChoice.OVERRIDE_PATH, GUARD]))
			Settings.set_value(&"renderer", RendererChoice.Choice.COMPATIBILITY)
			_expect(RendererChoice.override_method() == RendererChoice.COMPATIBILITY and Settings.renderer_needs_restart(),
				"Settings ▸ Renderer ▸ Compatibility writes the file the engine reads, and waits for a restart")
			Settings.use_defaults()
		"compat":
			_expect(method == RendererChoice.COMPATIBILITY and not RendererChoice.from_command_line(),
				"the next start is on Compatibility, read from the file: nothing on the command line (%s)" % method)
			_expect(Settings.machine_quality() == Settings.QUALITY_LOW,
				"and a fresh install there starts on Low")
			_expect(RendererChoice.project_method() == "forward_plus"
				and RendererChoice.method_for(RendererChoice.Choice.GAME) == "forward_plus",
				"the game's own renderer is still Forward+ while the file says otherwise (so choosing Full asks for a restart)")
			RendererChoice.write(RendererChoice.Choice.GAME)
			_expect(not FileAccess.file_exists(RendererChoice.OVERRIDE_PATH), "choosing the game's own renderer removes it")
		"restart":
			if FileAccess.file_exists(GUARD) and ConfigFile.new().load(GUARD) == OK and _second_run():
				return
			_expect(method == "forward_plus", "the restart test starts on Forward+ (%s)" % method)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_FILE))
			RendererChoice.switch(RendererChoice.REASON_GPU, RendererChoice.OVERRIDE_PATH, GUARD)
			print("RENDER restarting onto Compatibility")
			RendererChoice.restart(get_tree())
			print("RENDER PASS: restart asked")
			return
		_:
			_expect(false, "a --step= (%s)" % step)
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


## The restarted process: on Compatibility, with the notice owed. Its verdict goes to RESULT_FILE
## (nobody is reading its output).
func _second_run() -> bool:
	var said: String = RendererChoice.take_announcement(GUARD)
	if said.is_empty():
		return false   # an old guard from another run: this is the first process
	var ok: bool = RendererChoice.running() == RendererChoice.COMPATIBILITY
	RendererChoice.write(RendererChoice.Choice.GAME)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD))
	var f: FileAccess = FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	f.store_string("%s %s | %s" % ["PASS" if ok else "FAIL", RendererChoice.running(), said])
	f.close()
	AppExit.quit(get_tree(), 0 if ok else 1)
	return true


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("RENDER PASS ", msg)
	else:
		_failures += 1
		printerr("RENDER FAIL ", msg)
