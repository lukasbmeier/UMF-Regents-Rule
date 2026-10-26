extends "res://tests/suite_base.gd"
## The `cells` suite (template 1.0, DECISIONS #278): the client's twin of `server/src/cell.rs`. A ring
## client asks the server for cells by number, so a place both sides put in different cells is a
## neighbour that is never sent. Held to the same cases as the module (`shared/golden/cells.json`).


func run() -> void:
	_run_cells_tests()
	await get_tree().process_frame


func _run_cells_tests() -> void:
	print("== Cells: the world in squares, as the module cuts it ==")
	_check(Cells.cell_m() == 64.0 and Cells.ring_radius() == 1 and Cells.stream_radius() == 2
		and Cells.hysteresis_m() == 4.0, "the numbers are the game's (shared/rules.json cells)")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/golden/cells.json"))
	var cases: Array = (doc as Dictionary).get("cases", []) as Array if doc is Dictionary else []
	_check(cases.size() >= 10, "the shared cases are there (%d)" % cases.size())
	var wrong: Array[String] = []
	for c: Variant in cases:
		var d: Dictionary = c as Dictionary
		var p := Vector3(float(d["x"]), 0.0, float(d["z"]))
		var got: int = Cells.chunk_of(p)
		if got != int(d["chunk"]):
			wrong.append("(%s, %s): %d, the module says %d" % [d["x"], d["z"], got, int(d["chunk"])])
	_check(wrong.is_empty(), "every shared case is in the cell the module says: %s" % ", ".join(wrong))

	for xz: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(511, -512), Vector2i(17, -300)]:
		_check(Cells.squares(Cells.at(xz.x, xz.y)) == xz, "a cell is its squares and back %s" % xz)
	_check(Cells.chunk_of(Vector3(0, 500, 0)) == Cells.chunk_of(Vector3.ZERO), "height is not a cell")

	var c: int = Cells.at(3, -7)
	var r1: PackedInt64Array = Cells.ring(c, 1)
	_check(r1.size() == 9 and r1.has(c) and r1.has(Cells.at(4, -6)) and r1.has(Cells.at(2, -8))
		and not r1.has(Cells.at(5, -7)), "a ring of one is the cell and its eight neighbours")
	_check(Cells.ring(c, 2).size() == 25, "a ring of two is 5 x 5")
	_check(Cells.ring(Cells.at(-512, -512), 1).size() == 4, "at the grid's corner, only the cells that exist")

	# The centre moves only once the player is well inside a new cell.
	var home: int = Cells.chunk_of(Vector3(32, 0, 32))
	_check(Cells.recentre(-1, Vector3(32, 0, 32)) == home, "no centre yet: where they are")
	_check(Cells.recentre(home, Vector3(65.0, 0, 32)) == home, "1 m over the edge: the centre stays")
	_check(Cells.recentre(home, Vector3(63.0, 0, 32)) == home, "back over it: still home")
	var east: int = Cells.chunk_of(Vector3(70, 0, 32))
	_check(Cells.recentre(home, Vector3(68.5, 0, 32)) == east, "4.5 m in: the centre follows")
	_check(Cells.recentre(east, Vector3(70, 0, 1.0)) == east, "walking along an edge it did not cross is no move")
	_check(Cells.recentre(home, Vector3(68.5, 0, 64.5)) == home,
		"crossing at a corner, deep in one axis but not the other: wait (it may be going north)")
	_check(Cells.recentre(home, Vector3(300, 0, 32)) == Cells.chunk_of(Vector3(300, 0, 32)), "a teleport far away: at once")
	_check(Cells.recentre(Cells.chunk_of(Vector3(600, 0, 32)), Vector3(0.0, 0, 8)) == Cells.chunk_of(Vector3(0.0, 0, 8)),
		"a teleport from far away to a spot ON an edge (Regent's Rule's spawn): at once, not held where they were")
