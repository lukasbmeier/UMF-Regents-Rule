extends SceneTree
## FIT A HELD ITEM'S GRIPS AND PHOTOGRAPH THEM, from a shell (DECISIONS #157): the grip preview's
## Fit Every Animation and Save Pictures buttons, for a script or an agent to run and look at.
##
##   godot --path . -s res://tools/held/fit_grip.gd -- --preview=res://game/<genre>/<item>_grip_preview.tscn
##       [--fit]           fit every animation (else only photograph the grips as they are)
##       [--body=both]     the body to fit for: both (the shared grips), female, male
##       [--save]          write the fitted grip file (else it is only photographed)
##
## The pictures go to res://grip_pictures/<grip>.png. It needs a window (not --headless): the
## headless renderer draws nothing.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview_path: String = ""
	var fit: bool = false
	var save: bool = false
	var body: String = "both"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			preview_path = arg.substr(10)
		elif arg == "--fit":
			fit = true
		elif arg == "--save":
			save = true
		elif arg.begins_with("--body="):
			body = arg.substr(7)
	var scene: PackedScene = load(preview_path) as PackedScene if not preview_path.is_empty() else null
	if scene == null:
		printerr("fit_grip: no preview scene (--preview=res://...tscn)")
		AppExit.quit(self, 1)
		return
	var prev: Node3D = scene.instantiate() as Node3D
	prev.set("body", body)
	root.add_child(prev)
	for i: int in range(6):
		await process_frame
	if fit:
		prev.call("fit_every_animation")
		print("fit_grip: ", prev.call("fit_said"))
		var grip: ItemGrip = prev.get("grip") as ItemGrip
		if save and grip != null and not grip.resource_path.is_empty():
			# Saved from a script, the file loses its uid line, and every scene that names it by uid
			# warns and falls back to its path: put the uid back.
			var uid: int = ResourceLoader.get_resource_uid(grip.resource_path)
			var saved: Error = ResourceSaver.save(grip)
			if saved == OK and uid != ResourceUID.INVALID_ID:
				saved = ResourceSaver.set_uid(grip.resource_path, uid)
			print("fit_grip: saved %s (%s, %s)" % [grip.resource_path, error_string(saved),
				ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else "no uid"])
	for i: int in range(4):
		await process_frame
	var written: String = await prev.call("save_pictures_now")
	print("fit_grip: pictures ", written if not written.is_empty() else "NOT written")
	AppExit.quit(self, 0 if not written.is_empty() else 1)
