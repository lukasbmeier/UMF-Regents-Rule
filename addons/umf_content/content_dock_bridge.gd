@tool
class_name ContentDockBridge extends RefCounted
## WHAT THE CONTENT DOCK ASKS OF THE EDITOR. This one does nothing (a headless test has no
## editor); `plugin.gd` gives the dock one that calls `EditorInterface`. Keeping the editor behind
## this is what lets the dock be built and clicked in the `content` suite.

## Records what was asked, for tests.
var asked: Array[String] = []


## Show a piece in the Inspector.
func edit(res: Resource) -> void:
	asked.append("edit " + res.resource_path)


## Files were written outside the editor's knowledge: rescan the FileSystem dock.
func files_changed() -> void:
	asked.append("files_changed")


## Open a scene (a workbench) in the editor.
func open_scene(path: String) -> void:
	asked.append("open " + path)


## Point the FileSystem dock at a file.
func show_file(path: String) -> void:
	asked.append("show " + path)


## Run the game.
func play() -> void:
	asked.append("play")
