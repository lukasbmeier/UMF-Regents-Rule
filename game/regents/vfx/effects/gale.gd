class_name VfxGale extends VfxEffect
## GALE (the staff's F: everything within 8 m and 60 degrees of where you look is thrown back): a funnel of wind
## bursts from the hands, curved blades of air sweep out across the cone, streaks race ahead, dust and leaves are
## torn up off the ground and flung. Put it at the caster's feet, facing the way the gust goes.

@export_group("Reach")
@export_range(1.0, 20.0, 0.5, "suffix:m") var reach_m: float = 8.0
@export_range(10.0, 180.0, 1.0, "suffix:deg") var angle_deg: float = 60.0
@export_range(0.0, 1.0, 0.05) var shake: float = 0.15
@export_group("Look")
@export var color: Color = Color(0.82, 0.96, 1.0)
@export_range(1, 8) var blades: int = 5
@export var dust_color: Color = Color(0.45, 0.4, 0.32)
@export var leaf_color: Color = Color(0.35, 0.5, 0.2)

## [mesh, when it starts (s), its height]
var _blades: Array[Array] = []
var _funnel: MeshInstance3D = null
var _bursts: Array[GPUParticles3D] = []


func _wind() -> GradientTexture1D:
	# Only the noise's high parts show: strands of air, never a sheet.
	return VfxKit.ramp(PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, 0.28), Color(1.3, 1.4, 1.4, 0.6)]),
		PackedFloat32Array([0.0, 0.5, 0.72, 1.0]))


func _build() -> void:
	duration_s = maxf(duration_s, 1.2)
	for i: int in blades:
		var f: float = float(i) / float(maxi(blades - 1, 1))
		var mesh: MeshInstance3D = clocked(VfxKit.shape_node(VfxKit.arc(0.86, 1.0, angle_deg + 6.0, lerpf(-0.3, 0.3, f)), VfxKit.energy(true, _wind(), {
			"tile_a": Vector2(5, 1), "scroll_a": Vector2(-3.0, 0), "tile_b": Vector2(9, 1), "scroll_b": Vector2(-5.0, 0.2),
			"warp": 0.35, "bands": 0.0, "heat_bias": 0.08, "intensity": 1.4, "erode_softness": 0.3, "edge_heat": 0.0,
			"uv_fade": Vector4(0.35, 0.45, 0.6, 0.6)}), "Blade%d" % i)) as MeshInstance3D
		var h: float = lerpf(0.35, 1.9, f)
		mesh.position.y = h
		mesh.rotation.z = lerpf(-0.12, 0.12, f) * (1.0 if i % 2 == 0 else -1.0)
		_blades.append([mesh, 0.03 * float(i) + (0.02 if i % 2 == 1 else 0.0), h])
	# The funnel from the hands: a cone lying along the gust, its wind twisting through it.
	_funnel = clocked(VfxKit.shape_node(VfxKit.tube(1.4, 0.12, 1.0, 32), VfxKit.energy(true, _wind(), {
		"tile_a": Vector2(3, 1), "scroll_a": Vector2(2.0, 2.5), "tile_b": Vector2(5, 2), "scroll_b": Vector2(3.0, 4.0),
		"bands": 0.0, "intensity": 1.3, "fresnel_heat": 0.35, "alpha_scale": 0.7, "rim_fade": 0.75, "erode_softness": 0.3,
		"edge_heat": 0.0, "uv_fade": Vector4(0, 0, 0.45, 0.95)}), "Funnel")) as MeshInstance3D
	_funnel.rotation.x = PI / 2.0   # its top (the narrow end) back at the hands, its mouth ahead
	var spread: float = angle_deg * 0.45
	var streak: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.FORWARD, spread, Vector2(14.0, 22.0), Vector3.ZERO,
		VfxKit.ramp(PackedColorArray([Color(color, 0.0), Color(color, 0.9), Color(color, 0.0)])), 1.0, 0.6), 0.4)
	streak.particle_flag_align_y = true
	streak.damping_min = 8.0
	streak.damping_max = 14.0
	streak.emission_shape_offset = Vector3(0, 1.2, -0.6)
	_add_burst(VfxKit.particles(60, 0.55, VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 2.5), Vector2(0.05, 1.1), streak, true, 0.8))
	var dust: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3(0, 0.12, -1), spread, Vector2(6.0, 11.0), Vector3(0, 0.3, 0),
		VfxKit.ramp(PackedColorArray([Color(dust_color, 0.0), Color(dust_color, 0.5), Color(dust_color.lightened(0.15), 0.0)]), PackedFloat32Array([0.0, 0.15, 1.0])), 0.5, 1.8), 0.2, 1.2)
	dust.damping_min = 4.0
	dust.damping_max = 7.0
	_add_burst(VfxKit.particles(16, 1.0, VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0), Vector2(0.9, 0.9), dust, true, 0.7))
	var leaf: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3(0, 0.35, -1), spread, Vector2(8.0, 15.0), Vector3(0, -3.0, 0),
		VfxKit.ramp(PackedColorArray([leaf_color, leaf_color, Color(leaf_color, 0.0)]), PackedFloat32Array([0.0, 0.8, 1.0])), 1.0, 0.8), 0.3, 1.6)
	leaf.angle_max = 360.0
	leaf.angular_velocity_min = -720.0
	leaf.angular_velocity_max = 720.0
	leaf.damping_min = 3.0
	leaf.damping_max = 6.0
	_add_burst(VfxKit.particles(18, 1.2, VfxKit.sprite(false, VfxKit.Shape.SHARD, VfxKit.Facing.CAMERA, 1.0), Vector2(0.09, 0.09), leaf, true, 0.6))


func _add_burst(p: GPUParticles3D) -> void:
	clocked(p)
	_bursts.append(p)


func _start() -> void:
	for p: GPUParticles3D in _bursts:
		burst(p)
	if shake > 0.0:
		shook.emit(shake, 0.25)


func _animate(a: float, _t: float) -> void:
	# Each blade sweeps out to the cone's reach, thinning and fading as it goes.
	for b: Array in _blades:
		var mesh: MeshInstance3D = b[0] as MeshInstance3D
		var from: float = float(b[1])
		var go: float = span(a, from, from + 0.42)
		mesh.visible = a >= from and go < 1.0
		var r: float = lerpf(0.6, reach_m, ease_out(go))
		mesh.scale = Vector3(r, 1.0, r)
		fx(mesh, &"fx_alpha", (1.0 - ease_in(go)) * span(a, from, from + 0.12))
		fx(mesh, &"fx_erosion", 0.15 + 0.85 * span(a, from + 0.2, from + 0.45))
	# The funnel: thrusts out from the hands and is gone in half a second.
	var fu: float = span(a, 0.0, 0.45)
	_funnel.visible = fu < 1.0
	var length: float = lerpf(0.5, 4.0, ease_out(span(a, 0.0, 0.2)))
	_funnel.scale = Vector3(lerpf(0.4, 1.0, ease_out(fu)), length, lerpf(0.4, 1.0, ease_out(fu)))
	_funnel.position = Vector3(0.0, 1.25, -0.4 - length * 0.5)
	fx(_funnel, &"fx_alpha", 1.0 - ease_in(fu))
