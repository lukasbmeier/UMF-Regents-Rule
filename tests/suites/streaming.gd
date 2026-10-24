extends "res://tests/suite_base.gd"
## The `streaming` suite (template 1.0, DECISIONS #278): a streamed level is cut into a scene per cell
## by its bake (`LevelCells`), and a player's game loads only the cells round them (`LevelStreamer`).
## A level built here, 9 x 9 cells with a marker in each, cut into user://, then walked across.

const FOLDER: String = "user://streaming_test/stream_test_cells"


func run() -> void:
	await _run_streaming_tests()


func _level(n: int) -> Node3D:
	var root := Node3D.new()
	root.name = "StreamTest"
	root.scene_file_path = "user://streaming_test/stream_test.tscn"
	var info := LevelInfo.new()
	info.name = "LevelInfo"
	info.level_name = "stream_test"
	info.streamed = true
	root.add_child(info)
	var cells := Node3D.new()
	cells.name = "Cells"
	info.add_child(cells)
	var m: float = Cells.cell_m()
	for x: int in range(-n, n + 1):
		for z: int in range(-n, n + 1):
			var p := Node3D.new()
			p.name = "P_%d_%d" % [x, z]
			p.position = Vector3((x + 0.5) * m, 0.0, (z + 0.5) * m)
			cells.add_child(p)
			p.owner = root
	# Two on either side of one edge: each is its own cell's.
	for xz: Array in [["EdgeWest", 63.9], ["EdgeEast", 64.1]]:
		var e := Node3D.new()
		e.name = str(xz[0])
		e.position = Vector3(float(xz[1]), 0.0, 10.0)
		cells.add_child(e)
		e.owner = root
	info.owner = root
	cells.owner = root
	return root


func _has_marker(cell_node: Node, marker: String) -> bool:
	return cell_node.get_node_or_null(NodePath(marker)) != null


func _run_streaming_tests() -> void:
	print("== LevelStreamer: the scenery round you, loaded as you go ==")
	var level: Node3D = _level(4)
	add_child(level)
	var cut: Dictionary = LevelCells.cut(level, FOLDER)
	_check(bool(cut.get("ok", false)), "a streamed level is cut (%s)" % cut.get("error", ""))
	var cells: Dictionary[int, String] = LevelCells.read(FOLDER)
	_check(cells.size() == 81, "one scene per cell with something in it: 81 (%d)" % cells.size())
	var origin: int = Cells.chunk_of(Vector3(32, 0, 32))
	var o_scene: PackedScene = load(cells.get(origin, "")) as PackedScene if cells.has(origin) else null
	var o_node: Node = o_scene.instantiate() if o_scene != null else null
	_check(o_node != null and _has_marker(o_node, "P_0_0") and _has_marker(o_node, "EdgeEast") == false
		and o_node.get_child_count() == 2 and _has_marker(o_node, "EdgeWest"),
		"a cell holds what stands in it, and an edge's two sides are two cells' (the origin's: P_0_0, EdgeWest)")
	var east_cell: int = Cells.chunk_of(Vector3(64.1, 0, 10))
	var e_scene: PackedScene = load(cells.get(east_cell, "")) as PackedScene if cells.has(east_cell) else null
	var e_node: Node = e_scene.instantiate() if e_scene != null else null
	_check(e_node != null and _has_marker(e_node, "EdgeEast") and _has_marker(e_node, "P_1_0"), "and EdgeEast is the next one's")
	_check(o_node != null and (o_node.get_node("P_0_0") as Node3D).position == Vector3(32, 0, 32),
		"kept where it stood under Cells")
	for n: Node in [o_node, e_node]:
		if n != null:
			n.free()

	# --- walking it ---
	var holder: Node3D = level.get_node("LevelInfo/Cells") as Node3D
	var streamer := LevelStreamer.new()
	var me := Node3D.new()
	add_child(me)
	me.global_position = Vector3(32, 0, 32)
	streamer.follow = me
	add_child(streamer)
	streamer.set_process(false)   # stepped by hand below
	streamer.step()
	var loaded: Array[int] = streamer.loaded_cells()
	_check(loaded.size() == 25 and holder.get_child_count() == 25,
		"the 5 x 5 round us is there at once, and the level's own copy is gone (%d loaded, %d under Cells)"
			% [loaded.size(), holder.get_child_count()])
	_check(loaded.has(Cells.at(-2, -2)) and loaded.has(Cells.at(2, 2)) and not loaded.has(Cells.at(3, 0)),
		"two cells either side, no more")

	me.global_position = Vector3(2.5 * Cells.cell_m(), 0, 32)   # two cells east
	for i: int in range(200):
		streamer.step()
		if streamer._pending.is_empty():
			break
		await get_tree().process_frame
	loaded = streamer.loaded_cells()
	var xs: Dictionary[int, bool] = {}
	for c: int in loaded:
		xs[Cells.squares(c).x] = true
	_check(loaded.has(Cells.at(4, 0)) and loaded.has(Cells.at(4, 2)), "walking east, the cells ahead come in (on a thread)")
	_check(not xs.has(-2) and xs.has(-1) and loaded.size() == 30,
		"the cells a ring and one behind are kept, those further freed (%d loaded, columns %s)" % [loaded.size(), str(xs.keys())])
	await get_tree().process_frame
	_check(holder.get_child_count() == 30, "and gone from the tree (%d)" % holder.get_child_count())

	# --- what it leaves alone ---
	streamer.queue_free()
	level.queue_free()
	await get_tree().process_frame
	var whole: Node3D = _level(1)
	(whole.get_node("LevelInfo") as LevelInfo).streamed = false
	add_child(whole)
	var s2 := LevelStreamer.new()
	s2.follow = me
	add_child(s2)
	s2.set_process(false)
	s2.step()
	_check(s2.loaded_cells().is_empty() and (whole.get_node("LevelInfo/Cells") as Node).get_child_count() == 11,
		"a level that is not streamed is left whole")
	(whole.get_node("LevelInfo") as LevelInfo).streamed = true
	whole.scene_file_path = "user://streaming_test/never_cut.tscn"
	(whole.get_node("LevelInfo") as LevelInfo).level_name = "never_cut"
	s2.step()
	_check(s2.loaded_cells().is_empty() and (whole.get_node("LevelInfo/Cells") as Node).get_child_count() == 11,
		"a streamed level never cut is shown whole (and said)")
	var prev_cfg: NetConfig = SpaceTimeSync.config
	var auth := NetConfig.new()
	auth.authority_process = true
	SpaceTimeSync.config = auth
	_check(not s2.streams(), "an authority's process never streams: it keeps the whole level")
	SpaceTimeSync.config = prev_cfg
	s2.queue_free()
	whole.queue_free()
	me.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))
