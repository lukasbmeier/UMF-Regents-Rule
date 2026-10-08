class_name PondVisual extends Node3D
## GENRE CODE. What a fishing spot looks and sounds like: water with ripples, a stone rim you
## cannot walk through, reeds, and the lap of water when you are near it.
##
## Presentation only (hard rule 11). Ripples are started by `FishingFx` from state it read — a
## line landing, a nibble, a fish leaving — and nothing here can produce a gameplay event.
##
## THE RIM IS A WALL, AND THAT HAS TWO CONSEQUENCES, both handled here:
##   * The spot entity is itself a physics body (a CharacterBody3D, like every entity). A wall
##     inside it would push it out of its own pond the first time anything simulated it — the
##     sidecar does — so the body is told to ignore its own rim.
##   * The interaction ray stops at the FIRST collider, whatever its layer, so a rim around the
##     water would hide the water from the crosshair. The spot's interaction shape is therefore
##     wider than the rim (fishing_spot.tscn): a ray from outside meets it first, always.

## Radius of the water surface, matching the mesh and the shader's `radius`.
@export var water_radius: float = 1.2
@export var reed_count: int = 7

@onready var _water: MeshInstance3D = $Water
@onready var _rim_body: StaticBody3D = $RimBody

var _material: ShaderMaterial = null
var _clock: float = 0.0
var _slots: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _next_slot: int = 0
var _ripples_started: int = 0
var _grown: bool = false


func _ready() -> void:
	# Every pond ripples on its own, so every pond needs its own copy of the material.
	var shared: ShaderMaterial = _water.get_surface_override_material(0) as ShaderMaterial
	if shared != null:
		_material = shared.duplicate() as ShaderMaterial
		_water.set_surface_override_material(0, _material)
		_material.set_shader_parameter(&"radius", water_radius)
	var body: PhysicsBody3D = get_parent() as PhysicsBody3D
	if body != null and _rim_body != null:
		body.add_collision_exception_with(_rim_body)


func _process(delta: float) -> void:
	# Reeds wait for the first frame: a spot is positioned when its entity BINDS, after _ready,
	# and where they grow depends on where the pond is.
	if not _grown:
		_grown = true
		_grow_reeds()
	_clock += delta
	if _material != null:
		_material.set_shader_parameter(&"now", _clock)


# --- API --------------------------------------------------------------------------------

## World height of the water's surface.
func surface_y() -> float:
	return _water.global_position.y + 0.02


## Where a line cast from `from` should land: on the water, `inset` metres in from the edge
## nearest the caster, so the float sits in the pond rather than on the rim.
func landing_point(from: Vector3, inset: float = 0.45) -> Vector3:
	var centre: Vector3 = global_position
	var flat: Vector3 = Vector3(from.x - centre.x, 0.0, from.z - centre.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var reach: float = maxf(0.0, water_radius - inset)
	var p: Vector3 = centre + flat.normalized() * reach
	return Vector3(p.x, surface_y(), p.z)


## True when a world point lies over the water.
func is_over_water(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() <= water_radius


## Start a ring at a world point. Four at once; the oldest makes way.
func ripple(at: Vector3, strength: float = 1.0) -> void:
	var local: Vector3 = _water.to_local(at)
	_slots[_next_slot] = Vector4(local.x, local.z, _clock, clampf(strength, 0.0, 2.0))
	_next_slot = (_next_slot + 1) % _slots.size()
	_ripples_started += 1
	if _material != null:
		_material.set_shader_parameter(&"ripples", _slots)


## How many ripples this pond has started. For tests: presentation is otherwise only checkable
## by looking at it.
func ripples_started() -> int:
	return _ripples_started


# --- dressing ------------------------------------------------------------------------------

## Reeds and bulrushes around the rim, placed from a fixed seed so every client grows the same
## pond. Built in code rather than laid out in the scene so the count is one number.
func _grow_reeds() -> void:
	var holder := Node3D.new()
	holder.name = "Reeds"
	add_child(holder)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.018
	stem.height = 1.0
	stem.radial_segments = 5
	stem.rings = 1
	var head := CapsuleMesh.new()
	head.radius = 0.028
	head.height = 0.17
	head.radial_segments = 6
	head.rings = 2
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.33, 0.45, 0.19)
	green.roughness = 0.9
	var brown := StandardMaterial3D.new()
	brown.albedo_color = Color(0.36, 0.22, 0.12)
	brown.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7EED5
	# Clustered on the FAR side from the middle of the level, as reeds grow on one bank: players
	# walk up from the middle, and a clump in front of them would stand between rod and water.
	var away: Vector2 = Vector2(global_position.x, global_position.z)
	if away.length() < 0.5:
		away = Vector2(0.0, -1.0)
	var facing: float = away.angle()
	for i: int in range(reed_count):
		var angle: float = facing + rng.randf_range(-0.9, 0.9)
		var r: float = water_radius + rng.randf_range(0.12, 0.3)
		var reed := Node3D.new()
		reed.position = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		reed.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU,
			rng.randf_range(-0.12, 0.12))
		var h: float = rng.randf_range(0.75, 1.15)
		var s := MeshInstance3D.new()
		s.mesh = stem
		s.material_override = green
		s.scale = Vector3(1.0, h, 1.0)
		s.position = Vector3(0.0, h * 0.5, 0.0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		reed.add_child(s)
		if i % 2 == 0:
			var top := MeshInstance3D.new()
			top.mesh = head
			top.material_override = brown
			top.position = Vector3(0.0, h * 0.86, 0.0)
			top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			reed.add_child(top)
		holder.add_child(reed)
