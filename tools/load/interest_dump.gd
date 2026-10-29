extends Node
## WHAT A REAL CLIENT OF THIS GAME ASKS FOR, written out for the load test's bots (DECISIONS #284).
## The bots (`tools/load/bots.py`) are not Godot, but they must be sent exactly what a player's game is:
## the same tables, filtered the same way, swapped by the same cells. So the queries come from the
## game's own `InterestManager` and `NetConfig` (its main scene's Boot, with every genre's tables
## merged in, as Boot does), never from a copy in Python.
##
##   godot --headless --path . res://tools/load/interest_dump.tscn -- --out=build/load/interest.json [--interest=ring|world]
##
## `--interest` overrides the game's own (the template's greybox plays WORLD; the harness measures RING).
## The queries are templates: `{world}`, `{cell}` and `{entity}` are filled in by each bot.

const WORLD_MARK: int = 7770777
const CELL_MARK: int = 8880888
const ENTITY_MARK: int = 9990999


func _ready() -> void:
	var out_path: String = "res://build/load/interest.json"
	var interest: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr("--out=".length())
		elif a.begins_with("--interest="):
			interest = a.substr("--interest=".length())
	var cfg: NetConfig = _game_config()
	if interest == "ring":
		cfg.interest = NetConfig.Interest.RING
	elif interest == "world":
		cfg.interest = NetConfig.Interest.WORLD
	elif not interest.is_empty():
		push_error("interest_dump: --interest is ring or world, not '%s'" % interest)
		get_tree().quit(1)
		return
	cfg.authority_process = false
	SpaceTimeSync.config = cfg
	var doc: Dictionary = {
		"interest": "ring" if InterestManager.is_ring(cfg) else "world",
		"world_queries": _marked(InterestManager.build_queries(WORLD_MARK)),
		"cell_queries": [],
		"own_queries": [],
		"cells": {"cell_m": Cells.cell_m(), "ring": Cells.ring_radius(), "hysteresis_m": Cells.hysteresis_m()},
	}
	if InterestManager.is_ring(cfg):
		var cell_qs: Array[String] = []
		var own_qs: Array[String] = []
		for t: StringName in InterestManager.subscribed_tables():
			if not InterestManager.is_cell_table(t, cfg):
				continue
			cell_qs.append(InterestManager.cell_query(t, WORLD_MARK, CELL_MARK))
			if InterestManager.is_follow_table(t, cfg):
				own_qs.append(InterestManager.own_query(t, ENTITY_MARK))
		doc["cell_queries"] = _marked(cell_qs)
		doc["own_queries"] = _marked(own_qs)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("interest_dump: cannot write %s" % out_path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("interest_dump: %s interest, %d world queries, %d per cell, %d of our own -> %s" % [doc["interest"],
		(doc["world_queries"] as Array).size(), (doc["cell_queries"] as Array).size(),
		(doc["own_queries"] as Array).size(), out_path])
	get_tree().quit(0)


## The NetConfig the game's main scene boots with (its Boot's, else the default), genres merged in.
## Boot has no class_name: it is found as the first node with a `net_config` (a game may extend it).
func _game_config() -> NetConfig:
	var cfg: NetConfig = null
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed: PackedScene = load(path) as PackedScene if not path.is_empty() else null
	if packed != null:
		var root: Node = packed.instantiate()
		var boot: Node = _find_boot(root)
		if boot != null and boot.get(&"net_config") is NetConfig:
			cfg = (boot.get(&"net_config") as NetConfig).duplicate() as NetConfig
		root.free()
	if cfg == null:
		cfg = NetConfig.new()
	Genres.merge_tables(cfg, Genres.modules())
	return cfg


func _find_boot(n: Node) -> Node:
	if &"net_config" in n:
		return n
	for c: Node in n.get_children():
		var b: Node = _find_boot(c)
		if b != null:
			return b
	return null


func _marked(queries: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for q: String in queries:
		out.append(q.replace(str(WORLD_MARK), "{world}").replace(str(CELL_MARK), "{cell}")
			.replace(str(ENTITY_MARK), "{entity}"))
	return out
