extends Node
## BAKE A LEVEL SCENE FOR THE SERVER (DECISIONS #175): the scene's `LevelInfo` says its name, number,
## water and bounds; its LevelSpawn, LevelSpot and LevelPoint markers say the rest. Writes
## `shared/world/<name>.json` + `<name>_depth.bin` (and a streamed level's cells). `LevelInfo`'s Bake button
## runs this.
##   godot --headless --path . res://tools/world/bake_level.tscn -- --scene=res://foundation/level/example/example_level.tscn
## Then republish (tools/publish.sh) so the server has it.
##
## A SCENE, NOT A `-s` SCRIPT (template 1.6.1): a bare script loads no autoloads, and cutting a streamed level
## into its cells needs `Cells` (which reads the hot rules): run as a script it put every cell's scenery into
## one cell at the grid's corner (Regent's Rule's continent, 2026-10-30, re-baked on Jolt).

## Physics frames to wait for the scene's collision to be in the world.
const SETTLE_FRAMES: int = 8

var _scene: String = ""
var _out: String = "res://shared/world/"
var _root: Node3D = null
var _frames: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr("--scene=".length())
		elif a.begins_with("--out="):
			_out = a.substr("--out=".length())
	if _scene.is_empty() or not ResourceLoader.exists(_scene):
		printerr("bake_level: give --scene=res://<level>.tscn (got '%s')" % _scene)
		get_tree().quit(2)
		return
	_root = (load(_scene) as PackedScene).instantiate() as Node3D
	if _root == null:
		printerr("bake_level: %s is not a 3D scene" % _scene)
		get_tree().quit(2)
		return
	# The scene's own path, as the bake records it.
	_root.scene_file_path = _scene
	add_child(_root)


func _physics_process(_delta: float) -> void:
	if _root == null or _frames < 0:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_frames = -1
	var r: Dictionary = LevelBaker.bake(_root, _out)
	if not bool(r["ok"]):
		printerr("bake_level: ", r["error"])
		get_tree().quit(1)
		return
	print("bake_level: %s -> %s: %dx%d grid, %d wet cells, %d spots, %d points, %d cells, spawn %s" % [_scene, r["json"],
		r["width"], r["height"], r["wet"], (r["doc"]["spots"] as Array).size(),
		(r["doc"]["points"] as Array).size(), (r.get("cells", {}) as Dictionary).size(), str(r["doc"]["spawn"])])
	get_tree().quit(0)
