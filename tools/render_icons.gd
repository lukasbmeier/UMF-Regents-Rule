extends Node
## DRAW EVERY CONTENT ICON (DECISIONS #271): each piece of content whose `icon_scene()` gives a model is
## drawn by `IconRender` into its `rendered_icon_path()` (a PNG beside its content). Needs a window:
##
##   tools\run.cmd: godot --path . res://tools/render_icons.tscn      then   godot --headless --path . --import
##
## (the import makes the pictures textures the game loads). Run it after adding or changing an item with
## a model; `--only=<type>` draws one type. Prints one line per icon and `ICONS: <n> drawn`.

var _only: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_run.call_deferred()


func _run() -> void:
	var drawn: int = 0
	var failed: int = 0
	for f: Dictionary in ContentLibrary.files():
		var def: ContentDef = load(String(f["path"])) as ContentDef
		if def == null or (not _only.is_empty() and String(def.content_type()) != _only):
			continue
		var scene: PackedScene = def.icon_scene()
		if scene == null:
			continue
		var img: Image = await IconRender.render(scene, self)
		var path: String = def.rendered_icon_path()
		if img == null:
			print("  no picture for %s (no renderer, or nothing to see)" % def.display_name)
			failed += 1
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		img.save_png(path)
		print("  %s -> %s" % [def.display_name, path])
		drawn += 1
	print("ICONS: %d drawn, %d without a picture" % [drawn, failed])
	AppExit.quit(get_tree(), 1 if failed > 0 else 0)
