class_name LakesideLevel extends Node3D
## GENRE CODE. The lakeside at runtime: answers "is that water, how deep, which spot" for the
## client, and keeps Terrain3D pointed at whichever camera is drawing.
##
## THE LEVEL IS GENERATED. `tools/world/build_lakeside.tscn` writes this scene, its terrain and
## its bake (`shared/world/lakeside.json` + depth grid); editing the scene by hand and re-running
## the generator loses the edit. The bake is what the SERVER knows about the level (build.rs
## compiles it in), and the water questions below go to the same bake through `LevelBake` —
## never to the terrain — so the client's answer and the server's cannot drift apart.
##
## Terrain3D centres its mesh and LODs on one camera. Left to itself it takes the first one it
## finds and keeps it, which in this game is the overview camera the connect screen looks
## through — and the terrain would stay centred on the overview for the whole match, detailed
## where nobody is and coarse under the player's feet. So the current camera is followed here,
## every frame, and the overview is only the fallback while nobody has one.

const LEVEL_NAME: String = "lakeside"
## How a component finds the level it is standing in: `get_first_node_in_group(GROUP)`.
const GROUP: StringName = &"fishing_level"

## WHICH BAKE THIS LEVEL ANSWERS FROM (`shared/world/<name>.json`): any fishing level uses this
## script with its own name (DECISIONS #175: a level built in the editor, like `meadow`). Terrain
## and Water are optional: a level without Terrain3D measures nothing from it, and one without a
## LakeWater shows no ripples.
@export var level_name: String = LEVEL_NAME

@export var terrain_path: NodePath = ^"Terrain3D"
@export var water_path: NodePath = ^"Water"
@export var fallback_camera_path: NodePath = ^"OverviewCamera"

var _terrain: Terrain3D = null
var _water: LakeWater = null
var _fallback: Camera3D = null
var _followed: Camera3D = null
var _bake: LevelBake = null


func _ready() -> void:
	add_to_group(GROUP)
	_terrain = get_node_or_null(terrain_path) as Terrain3D
	_water = get_node_or_null(water_path) as LakeWater
	_fallback = get_node_or_null(fallback_camera_path) as Camera3D
	_bake = LevelBake.load_level(level_name)
	if _fallback != null and get_viewport().get_camera_3d() == null:
		_fallback.make_current()
	_follow_camera()


func _process(_delta: float) -> void:
	_follow_camera()


# --- queries --------------------------------------------------------------------------------

## The level's bake: the server's view of it. Null only if the bake files are missing.
func bake() -> LevelBake:
	return _bake


## The lake's surface height.
func water_y() -> float:
	return _bake.water_y if _bake != null else 0.0


## How deep the water is at a point, as the server sees it; 0 on dry land and off the lake.
func water_depth(p: Vector3) -> float:
	return _bake.depth_at(p.x, p.z) if _bake != null else 0.0


## True where a float would land in water the server will accept.
func is_water(p: Vector3) -> bool:
	return _bake != null and _bake.is_water(p.x, p.z)


## The named spot containing a point, or {} for open water.
func spot_at(p: Vector3) -> Dictionary:
	return _bake.spot_at(p.x, p.z) if _bake != null else {}


## Ground height under a point, from the terrain itself (for placing things, not for rules).
## NAN off the edge of the world.
func ground_height(p: Vector3) -> float:
	if _terrain == null or _terrain.data == null:
		return NAN
	return _terrain.data.get_height(p)


func water() -> LakeWater:
	return _water


func terrain() -> Terrain3D:
	return _terrain


# --- internals ------------------------------------------------------------------------------

func _follow_camera() -> void:
	if _terrain == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null and _fallback != null:
		_fallback.make_current()
		cam = _fallback
	if cam != null and cam != _followed:
		_followed = cam
		_terrain.set_camera(cam)
