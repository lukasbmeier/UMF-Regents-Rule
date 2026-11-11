class_name SkinStage extends SubViewportContainer
## SKINNING'S 3D STAGE: THE CUT LINE (`HERBALISM_HUNTING_PREP.md` H4; Luke's M7: a 3D stage in the panel, the tool
## floating, no character). The carcass lies on the grass seen from above; the cut lines are drawn over its flank
## by `SkinMinigame` (where the hide is on screen comes from here: `hide_to_screen`); the KNIFE floats over it, its point
## at the mouse, dipping into the hide while it is held and hovering when it is not. A cut slices (a soft sound, a fleck
## of red), a tear rips (a harsher one), a line done thuds. PRESENTATION ONLY: it decides nothing. Its own world.
##
## Designers: open `skin_stage.tscn` to move the camera, the sun, a carcass, or where the cuts run: `HideLeft` and
## `HideRight` are the two ends of a cut (the hide's 100 and 900 across; its middle line runs between them, at their
## height). The knife is `knife.tscn` (a placeholder until a model is found). The sounds are `art/sound/skinning/`.
## EVERY CARCASS IS PLACED HERE, under `Carcasses` (Luke, 2026-11-11: the wolf's round showed bare grass, it lay at
## the deer's place and falls on its other side): one child a carcass scene (a skinning NodeDef's first model), each
## moved, turned and sized by hand so its flank lies under the two markers; the round shows its own and hides the
## rest. A NEW CREATURE: instance its carcass scene under `Carcasses`, hide the others with their eyes, and place it.
## Its size here is the stage's own (a close-up), not the world's `model_scale`.

## How high the knife's point hovers over the hide while it is not held (m).
@export var hover_m: float = 0.05
## How far the knife leans back from upright, held and hovering (radians).
@export var lean_held: float = 0.55
@export var lean_hover: float = 0.85
## The knife (a placeholder until a model is found).
@export var knife_scene: PackedScene = preload("res://game/regents/skilling/skinning/knife.tscn")

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _stage3d: Node3D = $Viewport/Stage
@onready var _carcasses: Node3D = $Viewport/Stage/Carcasses
@onready var _left: Marker3D = $Viewport/Stage/HideLeft
@onready var _right: Marker3D = $Viewport/Stage/HideRight
@onready var _flecks: CPUParticles3D = $Viewport/Stage/Flecks
@onready var _slice: AudioStreamPlayer = $Slice
@onready var _tear: AudioStreamPlayer = $Tear
@onready var _done: AudioStreamPlayer = $Done

var _knife: Node3D = null
var _head: Vector3 = Vector3.ZERO
var _shown_at: Vector3 = Vector3.ZERO
var _shown_lean: float = 0.85
var _placed: bool = false
var _slice_next_ms: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the mouse
	_knife = knife_scene.instantiate() as Node3D
	var head: Node3D = _knife.get_node_or_null(^"Head") as Node3D
	_head = head.position if head != null else Vector3.ZERO
	_stage3d.add_child(_knife)
	_shown_lean = lean_hover


## The round's carcass: the one placed under `Carcasses` whose scene is `node`'s model is shown, the rest hidden.
func set_carcass(node: NodeDef) -> void:
	if node == null or node.models.is_empty() or _carcasses == null:
		return
	var scene: PackedScene = node.models[0]
	var shown: Node3D = null
	var first: Node3D = null
	for c: Node in _carcasses.get_children():
		var placed: Node3D = c as Node3D
		if placed == null:
			continue
		if first == null:
			first = placed
		placed.visible = placed.scene_file_path == scene.resource_path
		if placed.visible:
			shown = placed
	if shown != null:
		return
	# Not placed on the stage yet: where the first lies, so the round shows something, and it says so.
	push_warning("SkinStage: %s is not placed on the stage: instance %s under Carcasses in skin_stage.tscn and place it" % [node.display_name, scene.resource_path])
	var made: Node3D = scene.instantiate() as Node3D
	if made == null:
		return
	if first != null:
		made.transform = first.transform
	_carcasses.add_child(made)


## Whether `node`'s carcass is placed on the stage (a child of `Carcasses` that is its model).
func has_carcass(node: NodeDef) -> bool:
	if node == null or node.models.is_empty() or _carcasses == null:
		return false
	for c: Node in _carcasses.get_children():
		if c.scene_file_path == node.models[0].resource_path:
			return true
	return false


## The carcass the stage shows now (null: none).
func shown_carcass() -> Node3D:
	if _carcasses == null:
		return null
	for c: Node in _carcasses.get_children():
		var placed: Node3D = c as Node3D
		if placed != null and placed.visible:
			return placed
	return null


## Panel point of the hide's (x, y) (thousandths): `HideLeft` is (100, 500), `HideRight` (900, 500), the same scale both
## ways, y down the screen.
func hide_to_screen(x: float, y: float) -> Vector2:
	var l: Vector2 = _to_panel(camera.unproject_position(_left.global_position))
	var r: Vector2 = _to_panel(camera.unproject_position(_right.global_position))
	var along: Vector2 = (r - l) / 800.0
	var down: Vector2 = Vector2(-along.y, along.x)
	return l + along * (x - 100.0) + down * (y - 500.0)


func _to_panel(vp: Vector2) -> Vector2:
	var vs: Vector2 = Vector2(viewport.size)
	return vp * size / vs if vs.x > 0.0 and vs.y > 0.0 else vp


## The 3D point on the hide (at the markers' height) under panel point `at`.
func _on_hide(at: Vector2) -> Vector3:
	var vs: Vector2 = Vector2(viewport.size)
	var vp: Vector2 = at * vs / size if size.x > 0.0 and size.y > 0.0 else at
	var from: Vector3 = camera.project_ray_origin(vp)
	var dir: Vector3 = camera.project_ray_normal(vp)
	var h: float = (_left.global_position.y + _right.global_position.y) * 0.5
	if absf(dir.y) < 0.0001:
		return from
	return from + dir * ((h - from.y) / dir.y)


## The knife over panel point `at`: in the hide (`held`) or hovering; `cutting`: on the line.
func knife(at: Vector2, held: bool, cutting: bool) -> void:
	if _knife == null:
		return
	var point: Vector3 = _on_hide(at) + Vector3.UP * (0.0 if held else hover_m)
	var lean: float = lean_held if held else lean_hover
	var k: float = 1.0 if not _placed else clampf(get_process_delta_time() * 25.0, 0.0, 1.0)
	_placed = true
	_shown_at = _shown_at.lerp(point, k)
	_shown_lean = lerpf(_shown_lean, lean, k)
	# Point down, leaning back toward the camera; its point (`Head`) at the spot.
	var b: Basis = Basis(Vector3.RIGHT, PI - _shown_lean) * Basis(Vector3.UP, 0.4 if cutting else 0.0)
	_knife.transform = Transform3D(b, _shown_at - b * _head)


## A cut ran this tick: a soft slice now and then.
func slice() -> void:
	var now: int = Time.get_ticks_msec()
	if now >= _slice_next_ms:
		_slice_next_ms = now + 180
		_slice.pitch_scale = randf_range(0.9, 1.15)
		_slice.play()


## The knife tore the hide: a rip and a fleck of red where it is.
func tear() -> void:
	if not _tear.playing:
		_tear.pitch_scale = randf_range(0.9, 1.1)
		_tear.play()
	_flecks.global_position = _shown_at
	_flecks.restart()


## A line cut to its end.
func line_done() -> void:
	_done.play()
