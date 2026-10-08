extends SceneTree
## BAKE A LEVEL SCENE FOR THE SERVER (DECISIONS #175): the scene's `LevelInfo` says its name, number,
## water and bounds; its LevelSpawn, LevelSpot and LevelPoint markers say the rest. Writes
## `shared/world/<name>.json` + `<name>_depth.bin`. `LevelInfo`'s Bake button runs this.
##   godot --headless --path . -s res://tools/world/bake_level.gd -- --scene=res://game/world/levels/meadow.tscn
## Then republish (tools/publish.sh) so the server has it.

## Physics frames to wait for the scene's collision to be in the world.
const SETTLE_FRAMES: int = 8

var _scene: String = ""
var _out: String = "res://shared/world/"
var _root: Node3D = null
var _frames: int = 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr("--scene=".length())
		elif a.begins_with("--out="):
			_out = a.substr("--out=".length())
	if _scene.is_empty() or not ResourceLoader.exists(_scene):
		printerr("bake_level: give --scene=res://<level>.tscn (got '%s')" % _scene)
		quit(2)
		return
	_root = (load(_scene) as PackedScene).instantiate() as Node3D
	if _root == null:
		printerr("bake_level: %s is not a 3D scene" % _scene)
		quit(2)
		return
	root.add_child(_root)


func _physics_process(_delta: float) -> bool:
	if _root == null:
		return false
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var r: Dictionary = LevelBaker.bake(_root, _out)
	if not bool(r["ok"]):
		printerr("bake_level: ", r["error"])
		quit(1)
		return true
	print("bake_level: %s -> %s: %dx%d grid, %d wet cells, %d spots, %d points, spawn %s" % [_scene, r["json"],
		r["width"], r["height"], r["wet"], (r["doc"]["spots"] as Array).size(),
		(r["doc"]["points"] as Array).size(), str(r["doc"]["spawn"])])
	quit(0)
	return true
