@tool
extends EditorPlugin
## THE CONTENT DOCK, in the editor's bottom panel (docs/rules/content.md, DECISIONS #200). This file
## is the only part of it that touches the editor: it docks `ContentDock` and gives it a bridge to
## `EditorInterface`. Excluded from both exports (it is a tool, not part of the game).

var _dock: EditorDock = null
var _panel: ContentDock = null


func _enter_tree() -> void:
	_panel = ContentDock.new()
	_panel.name = "ContentDock"
	_panel.setup(ContentDockModel.new(), EditorBridge.new())
	_dock = EditorDock.new()
	_dock.title = "Content"
	_dock.layout_key = "umf_content"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.add_child(_panel)
	add_dock(_dock)
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_files_changed)
	resource_saved.connect(_on_resource_saved)


func _exit_tree() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_files_changed):
		fs.filesystem_changed.disconnect(_on_files_changed)
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
	_dock = null
	_panel = null


func _on_files_changed() -> void:
	if _panel != null:
		_panel.refresh()


func _on_resource_saved(res: Resource) -> void:
	if _panel != null and res is ContentDef:
		_panel.refresh()


class EditorBridge extends ContentDockBridge:
	func edit(res: Resource) -> void:
		EditorInterface.edit_resource(res)

	func files_changed() -> void:
		EditorInterface.get_resource_filesystem().scan()

	func open_scene(path: String) -> void:
		EditorInterface.open_scene_from_path(path)

	func open_workbench(path: String, def: ContentDef) -> void:
		Workbench.pending = def
		EditorInterface.open_scene_from_path(path)
		# Already open: Godot only switched to its tab, so its _ready will not run again.
		var root: Node = EditorInterface.get_edited_scene_root()
		if root is Workbench and Workbench.pending != null:
			(root as Workbench).item = def
			Workbench.pending = null
			EditorInterface.edit_node(root)

	func show_file(path: String) -> void:
		EditorInterface.get_file_system_dock().navigate_to_path(path)

	func play() -> void:
		EditorInterface.play_main_scene()
