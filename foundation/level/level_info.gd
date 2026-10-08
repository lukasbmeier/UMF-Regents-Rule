@tool
class_name LevelInfo extends Node3D
## A LEVEL BUILT IN THE EDITOR (DECISIONS #175): put one of these in a level's scene, give it the
## level's name and number, and press BAKE FOR THE SERVER. What the server knows about the level is
## then read off the scene itself:
##
##   the ground       raycast straight down, every `grid_spacing` metres inside `bake_bounds`, on
##                    the world's collision (layer 1): whatever a player would stand on
##   the water        everywhere the ground is below `water_y`, how deep (a dock over the water is
##                    ground: the ray hits its planks first)
##   the spawn        the first `LevelSpawn` in the scene
##   the spots        every `LevelSpot` (a named piece of water: a fishing spot)
##   the points       every `LevelPoint` (anything else: a basket, a tee, a coop, a goal), by kind
##
## into `shared/world/<level_name>.json` and its depth grid, the files `server/build.rs` compiles in
## and the client's `LevelBake` reads. Then republish (`tools/publish.sh`) so the server has it.
## The bake runs headless (`tools/world/bake_level.gd`), the same as from a shell:
##   godot --headless --path . -s res://tools/world/bake_level.gd -- --scene=res://game/world/levels/meadow.tscn
##
## Place markers anywhere under the scene's root. Nothing here runs in the game.

## The bake's name: `shared/world/<level_name>.json`, and what the server calls the level.
@export var level_name: String = ""
## Its number (1-255), unique among the levels: what a world's `world_level` row says it runs.
@export_range(1, 255) var level_id: int = 1
## The level's water surface. A level with no water: put it below the lowest ground.
@export var water_y: float = 0.0
## The deepest a player may wade (the depth contour a barrier should follow).
@export var wade_depth: float = 0.7
## The least water a float needs (the fishing rule).
@export var min_cast_depth: float = 0.5
## Metres between ground samples. The server's grid: keep it 1 unless the level is huge.
@export_range(0.25, 4.0, 0.25) var grid_spacing: float = 1.0
## The region sampled, in the level's space (only its X and Z matter): where the water might be.
@export var bake_bounds: AABB = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))

@export_tool_button("Bake For The Server", "Save") var bake_button: Callable = bake_in_editor

## What the last bake said.
var last_bake: String = ""


## Bake from the editor: the saved scene, through the headless baker (it needs physics running).
func bake_in_editor() -> void:
	var scene: String = owner.scene_file_path if owner != null else scene_file_path
	if scene.is_empty():
		last_bake = "Save the scene first: the bake reads the saved scene."
		push_warning("LevelInfo: " + last_bake)
		return
	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tools/world/bake_level.gd", "--",
		"--scene=" + scene], out, true)
	last_bake = ("Baked: " if code == 0 else "The bake failed: ") + "\n".join(PackedStringArray(out)).strip_edges().get_slice("\n", -1)
	print("LevelInfo: ", "\n".join(PackedStringArray(out)))
	if code == 0:
		print("LevelInfo: republish (tools/publish.sh) so the server has it.")
