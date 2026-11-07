class_name AnvilStage extends SubViewportContainer
## SMITHING'S 3D STAGE (`MINIGAMES_PREP.md` §5.1 C; Luke's M7, 2026-11-05): the anvil round's panel shows a small 3D
## scene of the game's own models (Quaternius's anvil and bronze hammer, a fire pit behind), lit like the world, with
## the hot bar on the anvil's face as a row of columns glowing by its heat. `ShapeMinigame` puts it behind its 2D
## readouts (the outline, the heat, the words) and tells it what the model says: PRESENTATION ONLY, it decides nothing
## (`ShapeModel` does). Its own world (`own_world_3d`): nothing of the game's world shows in it, nor it there.
##
## Designers: open `anvil_stage.tscn` to move the camera, the lights or the props, or swap a model; the numbers
## below place the bar on the anvil. The sounds are `game/regents/art/sound/smithing/` (`game/regents/tools/make_skill_sounds.py`).

## The bar's middle on the anvil's face, its length, one unit of a column's height in meters, and its depth.
@export var bar_center: Vector3 = Vector3(0.0, 0.561, 0.0)
@export var bar_length: float = 0.62
@export var unit_height: float = 0.0055
@export var bar_depth: float = 0.07
## How brightly the bar glows at full heat, and the forge's light as the bar is hot (and as it is put back in).
@export var hot_glow_energy: float = 3.0
@export var forge_energy: float = 2.4
## How high the hammer is raised between strikes and at the top of a swing (radians), and how long its fall is.
@export var hammer_rest: float = -0.45
@export var hammer_lift: float = -1.05
@export var hammer_fall_s: float = 0.06
## From the hand to the middle of the hammer's head, and from that middle to its face (the model's sizes).
@export var hammer_reach: float = 0.30
@export var hammer_face: float = 0.076

const COLD_METAL: Color = Color(0.30, 0.29, 0.29)
const HOT_METAL: Color = Color(0.55, 0.22, 0.08)
const GLOW: Color = Color(1.0, 0.42, 0.10)
const WHITE_HEAT: Color = Color(1.0, 0.85, 0.55)
## Red heat (a strike now cracks it): a dull, dark red, not the working orange.
const RED_METAL: Color = Color(0.35, 0.07, 0.04)
const RED_GLOW: Color = Color(0.85, 0.08, 0.03)
const CRACK: Color = Color(0.03, 0.02, 0.02)

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _bar_root: Node3D = $Viewport/Stage/Bar
@onready var _hammer: Node3D = $Viewport/Stage/Hammer
@onready var _sparks: CPUParticles3D = $Viewport/Stage/Sparks
@onready var _tap_sparks: CPUParticles3D = $Viewport/Stage/TapSparks
@onready var _forge: OmniLight3D = $Viewport/Stage/ForgeGlow
@onready var _clang: AudioStreamPlayer = $Clang
@onready var _tap: AudioStreamPlayer = $Tap
@onready var _cold: AudioStreamPlayer = $Cold
@onready var _reheat: AudioStreamPlayer = $Reheat

var _n: int = 0
var _columns: Array[MeshInstance3D] = []
var _cracks: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _heights: PackedInt32Array = PackedInt32Array()
var _flash: PackedFloat32Array = PackedFloat32Array()
var _heat: float = 1.0
var _flare: float = 0.0
var _swing_age: float = 10.0
var _aim_x: float = 0.0
var _aim_top: float = 0.0
var _shake: float = 0.0
var _camera_home: Transform3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the clicks
	stretch = true
	_camera_home = camera.transform


## A bar of `n` columns on the anvil.
func build(n: int) -> void:
	for c: MeshInstance3D in _columns + _cracks:
		c.queue_free()
	_columns.clear()
	_cracks.clear()
	_materials.clear()
	_n = n
	_heights.resize(n)
	_heights.fill(0)
	_flash.resize(n)
	_flash.fill(0.0)
	var w: float = bar_length / float(maxi(1, n))
	for i: int in n:
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(w * 0.94, 1.0, bar_depth)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.metallic = 0.55
		mat.roughness = 0.45
		mat.emission_enabled = true
		var col: MeshInstance3D = MeshInstance3D.new()
		col.mesh = mesh
		col.material_override = mat
		col.position = Vector3(column_x(i), bar_center.y, bar_center.z)
		_bar_root.add_child(col)
		_columns.append(col)
		_materials.append(mat)


## The middle of column `i` along the anvil (world x).
func column_x(i: int) -> float:
	var n: int = maxi(1, _n)
	return bar_center.x - bar_length * 0.5 + (float(i) + 0.5) * bar_length / float(n)


## The bar now: its columns' heights, its heat (0 cold .. 1 fresh from the fire), the column under the mouse (-1:
## none), whether it is in the fire, and whether it is red (a strike now cracks it: band 3's heat colors).
func show_bar(heights: PackedInt32Array, heat: float, hover: int, in_fire: bool, red: bool = false) -> void:
	if heights.size() != _columns.size():
		build(heights.size())
	_heights = heights.duplicate()
	_heat = heat
	_flare = 1.0 if in_fire else _flare
	for i: int in _columns.size():
		var h: float = maxf(0.001, float(heights[i]) * unit_height)
		var col: MeshInstance3D = _columns[i]
		col.scale = Vector3(1.0, h, 1.0)
		col.position.y = bar_center.y + h * 0.5
		var mat: StandardMaterial3D = _materials[i]
		# The column under the mouse is lighter, never hotter: its glow is the bar's heat alone.
		mat.albedo_color = (RED_METAL if red else COLD_METAL.lerp(HOT_METAL, heat)).lightened(0.22 if i == hover else 0.0)
		mat.emission = (RED_GLOW if red else GLOW).lerp(WHITE_HEAT, _flash[i])
		mat.emission_energy_multiplier = (0.9 if red else hot_glow_energy * (heat * heat)) + _flash[i] * 4.0
	for k: MeshInstance3D in _cracks:
		var c: int = int(k.get_meta(&"column", 0))
		k.position.y = bar_center.y + float(heights[c]) * unit_height * float(k.get_meta(&"at", 0.5))
	if hover >= 0 and hover < _columns.size():
		_aim_x = column_x(hover)
		_aim_top = top_y(hover)


## Where column `i`'s top is (world y).
func top_y(i: int) -> float:
	return bar_center.y + (float(_heights[i]) * unit_height if i >= 0 and i < _heights.size() else 0.0)


## The hammer comes down on column `i`: `heavy` a strike (big sparks, the clang), else a tap; `cold` a strike that
## does nothing (the thud). `heat` pitches the clang down as the bar cools.
func strike(i: int, heavy: bool, cold: bool, heat: float) -> void:
	if i < 0 or i >= _columns.size():
		return
	_aim_x = column_x(i)
	_aim_top = top_y(i)
	_swing_age = 0.0
	if cold:
		_play(_cold, 1.0)
		return
	_flash[i] = 1.0 if heavy else 0.55
	var spot: Vector3 = Vector3(column_x(i), top_y(i), bar_center.z + bar_depth * 0.5)
	var p: CPUParticles3D = _sparks if heavy else _tap_sparks
	p.position = spot
	p.restart()
	_shake = 1.0 if heavy else 0.25
	_play(_clang if heavy else _tap, lerpf(0.82, 1.08, heat))


## Column `i` struck red: it cracks (a dark mark on its face that stays), the thud.
func crack(i: int) -> void:
	if i < 0 or i >= _columns.size():
		return
	_aim_x = column_x(i)
	_aim_top = top_y(i)
	_swing_age = 0.0
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(bar_length / float(maxi(1, _n)) * 0.7, 0.004, 0.004)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = CRACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var mark: MeshInstance3D = MeshInstance3D.new()
	mark.mesh = mesh
	var at: float = 0.3 + 0.15 * float(_cracks.size() % 4)
	mark.set_meta(&"column", i)
	mark.set_meta(&"at", at)
	mark.position = Vector3(column_x(i), top_y(i) * at + bar_center.y * (1.0 - at), bar_center.z + bar_depth * 0.5 + 0.002)
	mark.rotation.z = 0.35 if _cracks.size() % 2 == 0 else -0.35
	_bar_root.add_child(mark)
	_cracks.append(mark)
	_play(_cold, 0.8)


## Back in the fire: the whoosh, the forge flares.
func reheat() -> void:
	_flare = 1.0
	_play(_reheat, 1.0)


func _play(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _process(delta: float) -> void:
	for i: int in _flash.size():
		_flash[i] = maxf(0.0, _flash[i] - delta * 5.0)
	_flare = maxf(0.0, _flare - delta * 0.8)
	_forge.light_energy = forge_energy * (0.35 + 0.65 * _heat + 1.2 * _flare)
	# The hammer: falls fast, rises slower, rests a little raised over the column under the mouse.
	_swing_age += delta
	var angle: float = hammer_rest
	if _swing_age < hammer_fall_s:
		angle = lerpf(hammer_lift, 0.0, _swing_age / hammer_fall_s)
	elif _swing_age < hammer_fall_s + 0.22:
		angle = lerpf(0.0, hammer_rest, (_swing_age - hammer_fall_s) / 0.22)
	var at: Vector3 = Vector3(_aim_x + hammer_reach, _aim_top + hammer_face, bar_center.z)
	_hammer.position = _hammer.position.lerp(at, 1.0 if _swing_age < hammer_fall_s else minf(1.0, delta * 14.0))
	_hammer.rotation = Vector3(0.0, 0.0, angle)
	_shake = maxf(0.0, _shake - delta * 9.0)
	camera.transform = _camera_home
	if _shake > 0.0:
		camera.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.004 * _shake


# --- where things are on screen (the minigame draws its outline over them and turns clicks into columns) ---

## A point on the bar's front face, on screen: `edge` along the bar in columns (0 its left end, n its right), at
## `height` in the model's units.
func screen_point(edge: float, height: float) -> Vector2:
	var n: int = maxi(1, _n)
	var x: float = bar_center.x - bar_length * 0.5 + edge * bar_length / float(n)
	var p: Vector3 = Vector3(x, bar_center.y + height * unit_height, bar_center.z + bar_depth * 0.5)
	return camera.unproject_position(p) * (size / Vector2(maxi(1, viewport.size.x), maxi(1, viewport.size.y)))
