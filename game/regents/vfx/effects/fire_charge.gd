class_name VfxFireCharge extends VfxEffect
## A SPELL GATHERING IN THE HAND (fireball's 0.6 s cast; frost's too, in its colors): a small sun that swells, its
## skin boiling, motes drawn into it from round the hand, and a light that grows. Put it at the casting hand.

@export_group("Look")
## How wide it is when full (m).
@export_range(0.05, 1.0, 0.01, "suffix:m") var size_m: float = 0.32
## The heat ramp: fire (0), frost (1), arcane (2).
@export_enum("Fire", "Frost", "Arcane") var element: int = 0
## Motes drawn in a second, and from how far (m).
@export_range(0, 200) var motes_per_s: int = 70
@export_range(0.1, 2.0, 0.05, "suffix:m") var mote_reach_m: float = 0.7
@export var light_color: Color = Color(1.0, 0.55, 0.2)

var _core: MeshInstance3D = null
var _shell: MeshInstance3D = null
var _motes: GPUParticles3D = null
var _light: OmniLight3D = null


func _build() -> void:
	var heat: GradientTexture1D = VfxKit.fire_heat() if element == 0 else (VfxKit.frost_heat() if element == 1 else VfxKit.arcane_heat())
	_core = clocked(VfxKit.shape_node(VfxKit.sphere(0.5), VfxKit.energy(true, heat, {
		"tile_a": Vector2(2, 1), "scroll_a": Vector2(0.4, -1.2), "tile_b": Vector2(3, 2), "scroll_b": Vector2(-0.3, -2.0),
		"heat_bias": 0.45, "fresnel_heat": -0.6, "rim_fade": 0.9, "intensity": 4.0}), "Core")) as MeshInstance3D
	_shell = clocked(VfxKit.shape_node(VfxKit.sphere(0.5), VfxKit.energy(true, heat, {
		"tile_a": Vector2(3, 2), "scroll_a": Vector2(0.6, -1.6), "tile_b": Vector2(4, 3), "scroll_b": Vector2(-0.5, -2.4),
		"warp": 0.45, "bands": 4.0, "displace": 0.12, "heat_bias": -0.05, "fresnel_heat": 0.3, "rim_fade": 0.4,
		"intensity": 2.5, "alpha_scale": 0.8}), "Shell")) as MeshInstance3D
	var mote_color: Color = heat.gradient.sample(0.8)
	var move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 0.0, Vector2.ZERO, Vector3.ZERO,
		VfxKit.ramp(PackedColorArray([Color(mote_color, 0.0), mote_color, Color(1, 1, 1, 1)])), 0.6, 1.0), mote_reach_m, true)
	move.radial_accel_min = -mote_reach_m * 10.0
	move.radial_accel_max = -mote_reach_m * 8.0
	_motes = clocked(VfxKit.particles(roundi(float(motes_per_s) * 0.4), 0.4,
		VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 4.0), Vector2(0.06, 0.06), move, false), null) as GPUParticles3D
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	add_child(_light)


func _start() -> void:
	_motes.emitting = true


func _animate(a: float, t: float) -> void:
	var grow: float = ease_out(t)
	var flick: float = 1.0 + 0.08 * sin(a * 41.0) + 0.05 * sin(a * 73.0)
	_core.scale = Vector3.ONE * size_m * 0.55 * maxf(grow, 0.05) * flick
	_shell.scale = Vector3.ONE * size_m * maxf(grow, 0.05) * (2.0 - flick)
	_light.light_energy = 2.5 * grow * flick
	_motes.emitting = t < 0.85


func _end() -> void:
	_motes.emitting = false
