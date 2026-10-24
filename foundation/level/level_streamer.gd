class_name LevelStreamer extends Node
## THE SCENERY ROUND YOU, LOADED AS YOU GO (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §5).
## A level with `LevelInfo.streamed` on was cut by its bake into a scene per 64 m cell (`LevelCells`).
## In a player's game this frees the level's own copy of what is under its `Cells` node and loads the
## cells round the player and the camera instead (`shared/rules.json` `cells.stream_ring`: 5 x 5), on a
## thread, freeing those that fall a cell further behind. The first cells load at once, so nobody spawns
## over nothing. Godot has no 3D world streaming of its own.
##
## Boot adds one to every game. It does nothing for a level that is not streamed, and nothing in an
## authority's process (a referee or sidecar keeps the whole level: it judges everyone, everywhere).
## A level that is streamed but was never cut is shown whole, with a warning to bake it.

## A cell's scenery was added (under the level's `Cells` node), or freed.
signal cell_loaded(chunk: int)
signal cell_unloaded(chunk: int)

## How often the rings are looked at, s.
const CHECK_SEC: float = 0.25

## What the rings are round, instead of the camera and our player: for a test, or a cutscene's view.
var follow: Node3D = null

## The streamed level being shown, its cut cells (chunk -> scene path), and the cells loaded now.
var _info: LevelInfo = null
var _cells: Dictionary[int, String] = {}
var _loaded: Dictionary[int, Node3D] = {}
var _pending: Dictionary[int, String] = {}
var _holder: Node3D = null
var _since: float = CHECK_SEC
var _warned: Dictionary[String, bool] = {}


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SEC:
		return
	_since = 0.0
	step()


## One look at the rings: take a newly shown level, finish what loaded, load what is wanted, free what
## is far behind. Called every `CHECK_SEC`; a test calls it directly.
func step() -> void:
	_take_level()
	if _holder == null:
		return
	_finish_pending()
	var at: Array[Vector3] = focuses()
	if at.is_empty():
		return
	var r: int = Cells.stream_radius()
	var wanted: Dictionary[int, bool] = _rings(at, r)
	var first: bool = _loaded.is_empty() and _pending.is_empty()
	for c: int in wanted:
		if _loaded.has(c) or _pending.has(c) or not _cells.has(c):
			continue
		if first:
			_add(c, load(_cells[c]) as PackedScene)   # the first cells at once: nobody spawns over nothing
		else:
			ResourceLoader.load_threaded_request(_cells[c], "PackedScene")
			_pending[c] = _cells[c]
	var keep: Dictionary[int, bool] = _rings(at, r + 1)
	for c: int in _loaded.keys():
		if not keep.has(c):
			_free(c)


## The places the rings are round: `follow`, else the camera and our own player.
func focuses() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if follow != null and follow.is_inside_tree():
		out.append(follow.global_position)
		return out
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		out.append(cam.global_position)
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D \
		if EntityRegistry.local_entity_id >= 0 else null
	if me != null and me.is_inside_tree():
		out.append(me.global_position)
	return out


## The cells loaded now (for tests and the debug overlay).
func loaded_cells() -> Array[int]:
	var out: Array[int] = []
	out.assign(_loaded.keys())
	return out


## Whether this process streams at all: an authority's never does.
func streams() -> bool:
	return SpaceTimeSync.config == null or not SpaceTimeSync.config.authority_process


func _take_level() -> void:
	if _info != null and is_instance_valid(_info) and _info.is_inside_tree():
		return
	_release()
	if not streams():
		return
	for n: Node in get_tree().get_nodes_in_group(LevelInfo.GROUP):
		var info: LevelInfo = n as LevelInfo
		if info == null or not info.streamed or not info.is_inside_tree():
			continue
		var holder: Node3D = info.get_node_or_null(NodePath(LevelCells.CELLS_NODE)) as Node3D
		if holder == null:
			continue
		var root: Node = info if info.owner == null else info.owner
		var folder: String = LevelCells.folder_for(root.scene_file_path, info.level_name)
		var cells: Dictionary[int, String] = LevelCells.read(folder)
		if cells.is_empty():
			if not _warned.has(folder):
				_warned[folder] = true
				push_warning("LevelStreamer: %s is streamed but has no cells in %s: bake it (LevelInfo, Bake For The Server). Shown whole." % [info.level_name, folder])
			continue
		# The level's own copy goes: from now on the cells round us are what is there.
		for c: Node in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		_info = info
		_holder = holder
		_cells = cells
		print("[LevelStreamer] %s: %d cells, %d x %d round us" % [info.level_name, cells.size(), 2 * Cells.stream_radius() + 1, 2 * Cells.stream_radius() + 1])
		return


func _release() -> void:
	for c: int in _loaded.keys():
		_free(c)
	_pending.clear()
	_info = null
	_holder = null
	_cells = {}


func _finish_pending() -> void:
	for c: int in _pending.keys():
		var path: String = _pending[c]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_pending.erase(c)
				_add(c, ResourceLoader.load_threaded_get(path) as PackedScene)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(c)
				push_warning("LevelStreamer: cell %s did not load" % path)


func _add(c: int, scene: PackedScene) -> void:
	if scene == null or _holder == null or _loaded.has(c):
		return
	var node: Node3D = scene.instantiate() as Node3D
	_holder.add_child(node)
	_loaded[c] = node
	cell_loaded.emit(c)


func _free(c: int) -> void:
	var node: Node3D = _loaded.get(c, null)
	_loaded.erase(c)
	if node != null and is_instance_valid(node):
		node.queue_free()
	cell_unloaded.emit(c)


static func _rings(at: Array[Vector3], r: int) -> Dictionary[int, bool]:
	var out: Dictionary[int, bool] = {}
	for p: Vector3 in at:
		for c: int in Cells.ring(Cells.chunk_of(p), r):
			out[c] = true
	return out
