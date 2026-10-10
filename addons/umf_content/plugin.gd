@tool
extends EditorPlugin
## THE CONTENT DOCK, in the editor's bottom panel (docs/rules/content.md, DECISIONS #200). This file
## is the only part of it that touches the editor: it docks `ContentDock` and gives it a bridge to
## `EditorInterface`. Excluded from both exports (it is a tool, not part of the game).

var _dock: EditorDock = null
var _panel: ContentDock = null
## The Workbench panel (DECISIONS #207), beside the Inspector: the open bench's controls.
var _bench_dock: EditorDock = null
var _bench_panel: WorkbenchPanel = null


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
	_bench_panel = WorkbenchPanel.new()
	_bench_panel.name = "WorkbenchPanel"
	_bench_panel.setup(_panel.bridge, _panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Workbench"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bench_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bench_panel)
	_bench_dock = EditorDock.new()
	_bench_dock.title = "Workbench"
	_bench_dock.layout_key = "umf_workbench"
	_bench_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_bench_dock.title_color = Color(1.0, 0.8, 0.3)
	_bench_dock.add_child(scroll)
	add_dock(_bench_dock)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(EditorInterface.get_edited_scene_root())
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_files_changed)
	resource_saved.connect(_on_resource_saved)


func _exit_tree() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_files_changed):
		fs.filesystem_changed.disconnect(_on_files_changed)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _bench_dock != null:
		remove_dock(_bench_dock)
		_bench_dock.queue_free()
	_bench_dock = null
	_bench_panel = null
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
	_dock = null
	_panel = null


## The edited scene changed: a workbench's controls go in the Workbench panel, anything else empties it.
func _on_scene_changed(root: Node) -> void:
	if _bench_panel != null:
		_bench_panel.show_bench(root as Workbench)
	# A bench's controls are only in this panel: bring it to the front whenever one opens (Luke's first
	# try with it never found it, docked as a second tab behind another).
	if root is Workbench and _bench_dock != null:
		_bench_dock.make_visible()


func _on_files_changed() -> void:
	if _panel != null:
		_panel.refresh()


func _on_resource_saved(res: Resource) -> void:
	if _panel != null and res is ContentDef:
		_panel.refresh()
		_panel.warn_if_templates(res as ContentDef)


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
		# The PIECE in the Inspector (DECISIONS #207): what is changed there is the piece itself; the
		# bench's controls are in the Workbench panel.
		EditorInterface.edit_resource(def)

	func show_file(path: String) -> void:
		EditorInterface.get_file_system_dock().navigate_to_path(path)

	## The editor's run arguments are a project setting read when a run starts: set for this run
	## only, and put back at once so nothing is saved into project.godot.
	func play(args: PackedStringArray = PackedStringArray()) -> void:
		const KEY: String = "editor/run/main_run_args"
		var before: Variant = ProjectSettings.get_setting(KEY, "")
		if not args.is_empty():
			ProjectSettings.set_setting(KEY, (String(before) + " " + " ".join(args)).strip_edges())
		EditorInterface.play_main_scene()
		ProjectSettings.set_setting(KEY, before)
