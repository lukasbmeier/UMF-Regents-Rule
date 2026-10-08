class_name LakeWater extends MeshInstance3D
## GENRE CODE. The lake's surface: one big plane at the water line, drawn by
## `lake_water.gdshader`, which works out depth and shoreline from what is behind it.
##
## Presentation only (hard rule 11). Ripples are started by whoever saw something happen — a
## float landing, a fish breaking the surface — and nothing here produces a gameplay event.
## The same contract as `PondVisual`, so `FishingFx` can ripple either.

## Rings alive at once; the oldest makes way. Matches `ripples[8]` in the shader.
const SLOTS: int = 8

var _material: ShaderMaterial = null
var _clock: float = 0.0
var _slots: Array[Vector4] = []
var _next_slot: int = 0
var _ripples_started: int = 0


func _ready() -> void:
	_slots.resize(SLOTS)
	_slots.fill(Vector4.ZERO)
	# One lake per scene, but a scene can be instanced twice (a preview beside the game); each
	# copy's rings are its own.
	var shared: ShaderMaterial = get_surface_override_material(0) as ShaderMaterial
	if shared == null:
		shared = material_override as ShaderMaterial
	if shared != null:
		_material = shared.duplicate() as ShaderMaterial
		material_override = _material


func _process(delta: float) -> void:
	_clock += delta
	if _material != null:
		_material.set_shader_parameter(&"now", _clock)


## World height of the surface.
func surface_y() -> float:
	return global_position.y


## Start a ring at a world point.
func ripple(at: Vector3, strength: float = 1.0) -> void:
	_slots[_next_slot] = Vector4(at.x, at.z, _clock, clampf(strength, 0.0, 2.0))
	_next_slot = (_next_slot + 1) % SLOTS
	_ripples_started += 1
	if _material != null:
		_material.set_shader_parameter(&"ripples", _slots)


## How many rings this lake has started. For tests: presentation is otherwise only checkable by
## looking at it.
func ripples_started() -> int:
	return _ripples_started
