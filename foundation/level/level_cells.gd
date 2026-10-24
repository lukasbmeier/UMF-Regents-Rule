class_name LevelCells extends RefCounted
## A STREAMED LEVEL, CUT INTO CELLS (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §5). The
## designer keeps ONE level scene. With `LevelInfo.streamed` on, the bake also cuts everything under its
## `Cells` node (props, trees, buildings, markers) into one scene per world cell (`Cells.cell_m`, 64 m),
## by where each child stands, beside the level scene:
##
##   <level folder>/<level_name>_cells/cells.json     which cells there are, and their scenes
##   <level folder>/<level_name>_cells/<x>_<z>.tscn    one cell's children (x, z: its squares)
##
## A client's `LevelStreamer` then frees the level's own `Cells` children and loads the cells round its
## player instead; the server, referees and sidecars keep the level whole. Everything not under `Cells`
## (terrain, sky, water, a far mesh) is always there. Never edit the cut files: move things in the
## level and bake again (the bake deletes the old cells first).

## The node under a streamed level's root whose children are cut into cells.
const CELLS_NODE: StringName = &"Cells"
const MANIFEST: String = "cells.json"


## The folder a level's cells are cut into: beside its scene.
static func folder_for(scene_path: String, level_name: String) -> String:
	return scene_path.get_base_dir().path_join(level_name + "_cells")


## The `Cells` node of a streamed level under `root`, or null.
static func cells_node(root: Node) -> Node3D:
	var info: LevelInfo = LevelBaker.find_info(root)
	if info == null or not info.streamed:
		return null
	return info.get_node_or_null(NodePath(CELLS_NODE)) as Node3D


## Cut `root`'s streamed content into `folder`. Returns {ok, error, cells (chunk -> scene path), path}.
## Each child of `Cells` goes whole into the cell its origin stands in: a building on an edge is one
## cell's, never split.
static func cut(root: Node3D, folder: String) -> Dictionary:
	var info: LevelInfo = LevelBaker.find_info(root)
	var cells: Node3D = cells_node(root)
	if info == null or cells == null:
		return {"ok": false, "error": "not a streamed level with a %s node" % CELLS_NODE}
	var by_cell: Dictionary[int, Array] = {}
	for child: Node in cells.get_children():
		var n3: Node3D = child as Node3D
		if n3 == null:
			continue
		var c: int = Cells.chunk_of(n3.global_position)
		if not by_cell.has(c):
			by_cell[c] = []
		by_cell[c].append(n3)
	var abs_folder: String = ProjectSettings.globalize_path(folder)
	_clear(abs_folder)
	DirAccess.make_dir_recursive_absolute(abs_folder)
	var listed: Dictionary = {}
	for c: int in by_cell:
		var sq: Vector2i = Cells.squares(c)
		var cell_root := Node3D.new()
		cell_root.name = "Cell_%d_%d" % [sq.x, sq.y]
		for n3: Node3D in by_cell[c]:
			# Kept where it stood under `Cells`: a cell loads back under that same node.
			var copy: Node3D = n3.duplicate() as Node3D
			cell_root.add_child(copy)
			_own(copy, cell_root)
		var packed := PackedScene.new()
		var err: Error = packed.pack(cell_root)
		var file: String = "%d_%d.tscn" % [sq.x, sq.y]
		if err == OK:
			err = ResourceSaver.save(packed, folder.path_join(file))
		cell_root.free()
		if err != OK:
			return {"ok": false, "error": "cannot write cell %s (%s)" % [file, error_string(err)]}
		listed[str(c)] = file
	var doc: Dictionary = {
		"_comment": "CUT from %s by the level bake (LevelCells, template 1.0, DECISIONS #278): the cells of a streamed level and their scenes. Do not edit: move things under the level's Cells node and bake again." % root.scene_file_path,
		"level": info.level_name,
		"cell_m": Cells.cell_m(),
		"cells": listed,
	}
	var path: String = folder.path_join(MANIFEST)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot write %s" % path}
	f.store_string(JSON.stringify(doc, "  ", true) + "\n")
	f.close()
	var out: Dictionary[int, String] = {}
	for k: String in listed:
		out[int(k)] = folder.path_join(str(listed[k]))
	return {"ok": true, "error": "", "cells": out, "path": path}


## A cut level's cells: chunk -> scene path. Empty when it was never cut or was cut at another cell size.
static func read(folder: String) -> Dictionary[int, String]:
	var out: Dictionary[int, String] = {}
	var path: String = folder.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return out
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		return out
	var d: Dictionary = doc as Dictionary
	if not is_equal_approx(float(d.get("cell_m", 0.0)), Cells.cell_m()):
		push_warning("LevelCells: %s was cut at %s m cells, the game's are %s m: bake the level again"
			% [path, d.get("cell_m"), Cells.cell_m()])
		return out
	var cells: Dictionary = d.get("cells", {}) as Dictionary
	for k: Variant in cells:
		out[int(str(k))] = folder.path_join(str(cells[k]))
	return out


## Every node of a copy belongs to its cell's scene, but an instanced scene's insides stay that
## scene's (saved as the instance, not inlined).
static func _own(n: Node, owner_root: Node) -> void:
	n.owner = owner_root
	if not n.scene_file_path.is_empty():
		return
	for c: Node in n.get_children():
		_own(c, owner_root)


static func _clear(abs_folder: String) -> void:
	var d: DirAccess = DirAccess.open(abs_folder)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".tscn") or f.ends_with(".json") or f.ends_with(".uid"):
			d.remove(f)
