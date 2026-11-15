class_name VfxFireBlast extends VfxEffect
## A FIREBALL BURSTING (fireball's splash: 3 m): a white flash, a banded ball of fire that swells and burns away from
## inside, a ring of heat racing out along the ground, a bubble that bends the air, embers and dark chunks thrown up,
## smoke rolling off, a scorch left glowing, a light that flares; and the camera shakes. Put it on the ground where
## the missile ends.

@export_group("Size")
## The splash's radius (m): the fireball's `splash_m`.
@export_range(0.5, 10.0, 0.1, "suffix:m") var splash_m: float = 3.0
## How hard the camera shakes (0: not at all).
@export_range(0.0, 1.0, 0.05) var shake: float = 0.45
@export_group("Parts")
@export_range(0, 200) var embers: int = 70
@export_range(0, 60) var chunks: int = 14
@export_range(0, 60) var smoke: int = 18
@export var bend_air: bool = true
@export var light_color: Color = Color(1.0, 0.5, 0.15)

var _flash: MeshInstance3D = null
var _ball: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _bubble: MeshInstance3D = null
var _scorch: MeshInstance3D = null
var _bursts: Array[GPUParticles3D] = []
var _light: OmniLight3D = null


func _build() -> void:
	duration_s = maxf(duration_s, 2.6)
	var heat: GradientTexture1D = VfxKit.fire_heat()
	_flash = clocked(VfxKit.shape_node(VfxKit.sphere(0.5), VfxKit.energy(true, heat, {
		"heat_bias": 0.6, "noise_heat": 0.3, "rim_fade": 1.0, "intensity": 2.0}), "Flash")) as MeshInstance3D
	_ball = clocked(VfxKit.shape_node(VfxKit.sphere(1.0, 48), VfxKit.energy(true, heat, {
		"tile_a": Vector2(3, 2), "scroll_a": Vector2(0.1, 0.5), "tile_b": Vector2(5, 3), "scroll_b": Vector2(-0.2, 0.9),
		"warp": 0.55, "bands": 5.0, "displace": 0.35, "heat_bias": -0.1, "fresnel_heat": -0.35, "rim_fade": 0.25,
		"intensity": 1.8, "erode_softness": 0.07, "edge_width": 0.1, "edge_heat": 0.9, "depth_fade": 0.35}), "Ball")) as MeshInstance3D
	_ring = clocked(VfxKit.shape_node(VfxKit.disc(1.0), VfxKit.circle({
		"ring_color": Color(1.0, 0.6, 0.2), "ring_radius": 0.9, "ring_width": 0.09, "inner_width": 0.0, "rune_count": 0.0,
		"wisp": 0.7, "wisp_tile": 3.0, "glow": 4.0}), "HeatRing")) as MeshInstance3D
	_ring.position.y = 0.04
	if bend_air:
		_bubble = clocked(VfxKit.shape_node(VfxKit.sphere(1.0), VfxKit.distort({"radial": false, "strength": 0.035, "band_width": 0.35}), "Bubble")) as MeshInstance3D
	_scorch = clocked(VfxKit.shape_node(VfxKit.disc(splash_m * 1.7), VfxKit.energy(false,
		VfxKit.ramp(PackedColorArray([Color(0.02, 0.015, 0.01, 0.0), Color(0.03, 0.02, 0.015, 0.8), Color(0.08, 0.03, 0.01, 0.9), Color(3.0, 0.8, 0.1, 1.0)]),
			PackedFloat32Array([0.0, 0.3, 0.75, 1.0])), {
		"tile_a": Vector2(2, 2), "scroll_a": Vector2.ZERO, "tile_b": Vector2(5, 5), "scroll_b": Vector2.ZERO,
		"radial_fade": 0.75, "noise_heat": 1.1, "heat_bias": -0.05, "intensity": 1.0, "erode_softness": 0.2}), "Scorch")) as MeshInstance3D
	_scorch.position.y = 0.02
	# Embers flung up and out, falling back.
	var ember_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 75.0, Vector2(5.0, 11.0) * splash_m / 3.0,
		Vector3(0, -9.8, 0), VfxKit.ramp(PackedColorArray([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 1), Color(0.7, 0.1, 0.02, 0.0)])), 1.0, 0.3), 0.4)
	ember_move.particle_flag_align_y = true
	ember_move.damping_min = 0.3
	ember_move.damping_max = 0.8
	_add_burst(VfxKit.particles(embers, 1.1, VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 5.0), Vector2(0.05, 0.4), ember_move, true, 1.0))
	# Puffs of flame swelling round the blast's skin.
	var puff_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 90.0, Vector2(1.0, 4.0) * splash_m / 3.0,
		Vector3(0, 1.0, 0), VfxKit.ramp(PackedColorArray([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.08, 0.9), Color(0.5, 0.08, 0.0, 0.0)])), 1.6, 0.2), splash_m * 0.25)
	puff_move.damping_min = 2.0
	puff_move.damping_max = 4.0
	_add_burst(VfxKit.particles(24, 0.6, VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 1.4, {"falloff": 1.5}), Vector2(1.0, 1.0) * splash_m / 3.0, puff_move, true, 1.0))
	# Dark chunks of earth thrown up, tumbling.
	var chunk_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 55.0, Vector2(4.0, 8.0) * splash_m / 3.0,
		Vector3(0, -14, 0), VfxKit.ramp(PackedColorArray([Color(0.12, 0.09, 0.07, 1), Color(0.12, 0.09, 0.07, 1), Color(0.12, 0.09, 0.07, 0.0)]), PackedFloat32Array([0.0, 0.8, 1.0])), 1.0, 0.6), 0.3)
	chunk_move.angle_min = 0.0
	chunk_move.angle_max = 360.0
	chunk_move.angular_velocity_min = -500.0
	chunk_move.angular_velocity_max = 500.0
	_add_burst(VfxKit.particles(chunks, 1.2, VfxKit.sprite(false, VfxKit.Shape.SHARD, VfxKit.Facing.CAMERA, 1.0), Vector2(0.16, 0.16), chunk_move, true, 1.0))
	# Smoke rolling up and off, lit orange as it starts.
	var smoke_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 45.0, Vector2(0.6, 2.2) * splash_m / 3.0,
		Vector3(0, 0.9, 0), VfxKit.ramp(PackedColorArray([Color(0.6, 0.3, 0.12, 1.0), Color(0.24, 0.2, 0.18, 0.85), Color(0.42, 0.4, 0.38, 0.0)]), PackedFloat32Array([0.0, 0.25, 1.0])), 0.8, 2.6), splash_m * 0.3)
	smoke_move.damping_min = 0.8
	smoke_move.damping_max = 1.6
	_add_burst(VfxKit.particles(smoke, 2.2, VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0, {"lumps": 0.8}), Vector2(1.2, 1.2) * splash_m / 3.0, smoke_move, true, 0.85))
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = splash_m * 3.0
	_light.position.y = 1.0
	add_child(_light)


func _add_burst(p: GPUParticles3D) -> void:
	clocked(p)
	_bursts.append(p)


func _start() -> void:
	for p: GPUParticles3D in _bursts:
		burst(p)
	if shake > 0.0:
		shook.emit(shake, 0.35)


func _animate(a: float, _t: float) -> void:
	# The flash: swells in a tenth of a second, gone by a fifth.
	var fl: float = span(a, 0.0, 0.18)
	_flash.visible = fl < 1.0
	_flash.scale = Vector3.ONE * splash_m * lerpf(0.2, 0.9, ease_out(span(a, 0.0, 0.08)))
	fx(_flash, &"fx_alpha", 1.0 - fl)
	# The ball: swells fast, then burns away from inside, cooling as it goes.
	var grow: float = ease_out(span(a, 0.0, 0.35))
	_ball.scale = Vector3.ONE * splash_m * lerpf(0.15, 0.78, grow) * Vector3(1.0, 0.85, 1.0)
	_ball.position.y = splash_m * 0.12 * grow
	fx(_ball, &"fx_erosion", ease_in(span(a, 0.12, 0.95)))
	fx(_ball, &"fx_heat", lerpf(0.25, -0.35, span(a, 0.0, 0.7)))
	_ball.visible = a < 0.95
	# The heat ring: out along the ground, fading.
	var rr: float = ease_out(span(a, 0.0, 0.45))
	_ring.scale = Vector3.ONE * splash_m * lerpf(0.3, 2.6, rr)
	fx(_ring, &"fx_alpha", 1.0 - rr)
	_ring.visible = rr < 1.0
	if _bubble != null:
		var br: float = span(a, 0.0, 0.32)
		_bubble.scale = Vector3.ONE * splash_m * lerpf(0.3, 1.5, ease_out(br))
		fx(_bubble, &"fx_alpha", 1.0 - br)
		_bubble.visible = br < 1.0
	# The scorch: glowing at first, cooling, then gone.
	fx(_scorch, &"fx_heat", lerpf(0.25, -0.2, span(a, 0.1, 1.4)))
	fx(_scorch, &"fx_erosion", span(a, 1.6, duration_s))
	_light.light_energy = 9.0 * (1.0 - ease_out(span(a, 0.0, 0.55)))
