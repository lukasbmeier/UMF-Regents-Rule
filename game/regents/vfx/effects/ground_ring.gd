class_name VfxGroundRing extends VfxEffect
## A RING THAT LANDS (the staff's Frost Ring; the imp's Cinder Ring): ONE FAMILY (Luke, 2026-11-14: "the frost ring
## and cinder ring should be more similar and cohesive"; he loved the ice shards coming up from the ground). A magic
## circle draws itself on the ground, its runes turning, and FILLS from the middle with a bright front for the time
## before it lands (the warning: when the fill reaches the edge, it lands); motes rise from it, faster as it comes.
## Then it LANDS: pieces punch up through it in a wave from the middle out (FROST: ice shards that stand, then crack
## away; FIRE: tongues of flame that leap and burn out), a ring races out along the ground, and what the element
## throws off (frost rolling low and glints; embers and smoke). Put it on the ground at the ring's middle.

enum Element { FROST, FIRE }

@export var element: Element = Element.FROST
@export_group("Size and time")
## The ring's radius (m): the spell's `radius_m`.
@export_range(0.5, 10.0, 0.1, "suffix:m") var radius_m: float = 4.0
## From the circle showing to its landing (s): the spell's `delay_ms`.
@export_range(0.1, 4.0, 0.05, "suffix:s") var warn_s: float = 1.0
@export_range(0.0, 1.0, 0.05) var shake: float = 0.25
@export_group("The circle")
@export var color: Color = Color(0.55, 0.85, 1.0)
## The dark ground beneath it (a foe's wants more: it must read at a glance) and how strong its fill is.
@export_range(0.0, 1.0, 0.05) var shade: float = 0.18
@export_range(0.0, 1.0, 0.05) var fill_alpha: float = 0.3
@export_range(0.0, 48.0, 1.0) var runes: float = 16.0
@export_group("What rises")
@export_range(0, 60) var pieces: int = 30
## The shortest and the tallest (m).
@export var height_m: Vector2 = Vector2(1.0, 2.6)
## How far they lean out from the middle (degrees, at most).
@export_range(0.0, 60.0, 1.0, "suffix:deg") var lean_deg: float = 30.0
## Which layout (any number: another throw of them).
@export var layout_seed: int = 7
@export var light_color: Color = Color(0.5, 0.8, 1.0)

var _circle: MeshInstance3D = null
var _shock: MeshInstance3D = null
## [pivot, how far out (0..1), its height]
var _shards: Array[Array] = []
var _motes: GPUParticles3D = null
var _landing: Array[GPUParticles3D] = []
var _light: OmniLight3D = null
var _landed: bool = false


func _fire() -> bool:
	return element == Element.FIRE


func _build() -> void:
	duration_s = maxf(duration_s, warn_s + (1.9 if not _fire() else 1.5))
	_circle = clocked(VfxKit.shape_node(VfxKit.disc(radius_m * 2.0), VfxKit.circle({
		"ring_color": color, "rune_color": color.lightened(0.35), "fill_color": Color(color.darkened(0.25), fill_alpha),
		"ring_radius": 0.95, "ring_width": 0.035, "inner_radius": 0.64, "inner_width": 0.012,
		"rune_inner": 0.69, "rune_outer": 0.89, "rune_count": runes, "rune_stroke": 0.09,
		"rune_spin": 0.4 if not _fire() else -0.6, "rune_seed": 5.0 if not _fire() else 9.0,
		"ticks": 48.0, "tick_length": 0.03, "shade": shade, "wisp": 0.25, "glow": 2.6, "fill_front": 0.05}), "Circle")) as MeshInstance3D
	_circle.position.y = 0.03
	_shock = clocked(VfxKit.shape_node(VfxKit.disc(1.0), VfxKit.circle({
		"ring_color": color.lightened(0.4), "ring_radius": 0.9, "ring_width": 0.025, "inner_width": 0.0, "rune_count": 0.0,
		"wisp": 0.4, "glow": 3.0}), "Shock")) as MeshInstance3D
	_shock.position.y = 0.05
	var look: ShaderMaterial = _flame() if _fire() else _ice()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	for i: int in pieces:
		var out: float = sqrt(rng.randf_range(0.12, 0.95))
		var ang: float = TAU * (float(i) + rng.randf_range(-0.35, 0.35)) / float(maxi(pieces, 1))
		var h: float = rng.randf_range(height_m.x, height_m.y) * lerpf(1.0, 0.7, out)
		var pivot := Node3D.new()
		pivot.position = Vector3(cos(ang), 0.0, sin(ang)) * radius_m * out
		pivot.rotation = Vector3(0.0, -ang, 0.0)
		pivot.rotate_object_local(Vector3.FORWARD, deg_to_rad(lean_deg * out * rng.randf_range(0.5, 1.0)))
		pivot.rotate_object_local(Vector3.UP, rng.randf_range(0.0, TAU))
		add_child(pivot)
		var foot: float = rng.randf_range(0.12, 0.24) * h * (1.6 if _fire() else 1.0)
		var mesh: MeshInstance3D = clocked(VfxKit.shape_node(VfxKit.spike(foot, h, 5 if not _fire() else 10), look), pivot) as MeshInstance3D
		mesh.position.y = h * 0.5 - 0.15
		_shards.append([pivot, out, h])
	# Rising from the circle as it waits: cold motes, or embers.
	var mote_move: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 15.0, Vector2(0.3, 1.2), Vector3(0, 0.4, 0),
		VfxKit.ramp(PackedColorArray([Color(color, 0.0), Color(color.lightened(0.3), 1.0), Color(color, 0.0)])), 1.0, 0.4), 0.0, radius_m * 0.95)
	_motes = clocked(VfxKit.particles(70, 1.0, VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 3.0), Vector2(0.07, 0.07), mote_move, false)) as GPUParticles3D
	if _fire():
		_build_fire_landing()
	else:
		_build_frost_landing()
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = radius_m * 2.5
	_light.position.y = 1.0
	add_child(_light)


func _ice() -> ShaderMaterial:
	return VfxKit.energy(false, VfxKit.ramp(PackedColorArray([
		Color(0.04, 0.12, 0.35, 0.92), Color(0.12, 0.42, 0.85, 0.92), Color(0.5, 0.85, 1.0, 0.95), Color(1.6, 1.9, 2.0, 1.0)]),
		PackedFloat32Array([0.0, 0.4, 0.75, 1.0])), {
		"noise_b": VfxKit.noise(5, 0.03, true), "tile_a": Vector2(1, 2), "scroll_a": Vector2.ZERO, "tile_b": Vector2(2, 3),
		"scroll_b": Vector2.ZERO, "noise_heat": 0.6, "heat_bias": 0.05, "fresnel_heat": 0.9, "fresnel_power": 1.6,
		"bands": 4.0, "intensity": 1.0, "erode_softness": 0.05, "edge_width": 0.12, "edge_heat": 1.0})


## A tongue of flame: the fire ramp licking up a cone, its top soft, its skin pushed out by the noise.
func _flame() -> ShaderMaterial:
	return VfxKit.energy(true, VfxKit.fire_heat(), {
		"tile_a": Vector2(2, 1), "scroll_a": Vector2(0.1, 1.6), "tile_b": Vector2(3, 2), "scroll_b": Vector2(-0.15, 2.6),
		"warp": 0.5, "bands": 5.0, "displace": 0.12, "heat_bias": -0.05, "fresnel_heat": -0.25, "rim_fade": 0.3,
		"intensity": 1.8, "uv_fade": Vector4(0, 0, 0.55, 0.05), "erode_softness": 0.06, "edge_heat": 0.8})


func _build_frost_landing() -> void:
	var roll: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3(1, 0.15, 0), 180.0, Vector2(2.0, 5.0), Vector3(0, 0.2, 0),
		VfxKit.ramp(PackedColorArray([Color(0.85, 0.95, 1.0, 0.7), Color(0.75, 0.88, 1.0, 0.45), Color(0.8, 0.9, 1.0, 0.0)]), PackedFloat32Array([0.0, 0.4, 1.0])), 0.8, 2.2), radius_m * 0.2, radius_m * 0.8)
	roll.flatness = 0.85
	roll.damping_min = 2.0
	roll.damping_max = 3.5
	_add_landing(VfxKit.particles(22, 1.6, VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0, {"lumps": 0.9}), Vector2(1.5, 1.5), roll, true, 0.9))
	var glint: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 30.0, Vector2(0.5, 2.5), Vector3(0, -0.5, 0),
		VfxKit.ramp(PackedColorArray([Color(1, 1, 1, 0), Color(0.9, 0.97, 1.0, 1), Color(0.6, 0.85, 1.0, 0)])), 1.0, 0.2), 0.0, radius_m * 0.9)
	_add_landing(VfxKit.particles(30, 0.9, VfxKit.sprite(true, VfxKit.Shape.STAR, VfxKit.Facing.CAMERA, 4.0), Vector2(0.28, 0.28), glint, true, 0.7))
	var chip: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 50.0, Vector2(3.0, 7.0), Vector3(0, -12, 0),
		VfxKit.ramp(PackedColorArray([Color(0.75, 0.92, 1.0, 1), Color(0.75, 0.92, 1.0, 1), Color(0.75, 0.92, 1.0, 0)]), PackedFloat32Array([0.0, 0.8, 1.0])), 1.0, 0.5), 0.0, radius_m * 0.8)
	chip.angle_max = 360.0
	chip.angular_velocity_min = -400.0
	chip.angular_velocity_max = 400.0
	_add_landing(VfxKit.particles(18, 1.0, VfxKit.sprite(true, VfxKit.Shape.SHARD, VfxKit.Facing.CAMERA, 1.2), Vector2(0.09, 0.09), chip, true, 1.0))


func _build_fire_landing() -> void:
	var sparks: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 35.0, Vector2(5.0, 10.0), Vector3(0, -9.0, 0),
		VfxKit.ramp(PackedColorArray([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 1), Color(0.6, 0.1, 0.0, 0)])), 1.0, 0.3), 0.0, radius_m * 0.9)
	sparks.particle_flag_align_y = true
	_add_landing(VfxKit.particles(70, 1.0, VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 5.0), Vector2(0.05, 0.4), sparks, true, 0.9))
	var puffs: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 25.0, Vector2(1.5, 3.5), Vector3(0, 1.0, 0),
		VfxKit.ramp(PackedColorArray([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.08, 0.9), Color(0.5, 0.08, 0.0, 0.0)])), 1.4, 0.2), 0.0, radius_m * 0.85)
	puffs.damping_min = 2.0
	puffs.damping_max = 3.0
	_add_landing(VfxKit.particles(24, 0.6, VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 1.4, {"falloff": 1.5}), Vector2(0.9, 0.9), puffs, true, 0.9))
	var smoke: ParticleProcessMaterial = VfxKit.from_ring(VfxKit.motion(Vector3.UP, 20.0, Vector2(1.0, 3.0), Vector3(0, 0.8, 0),
		VfxKit.ramp(PackedColorArray([Color(0.6, 0.25, 0.08, 0.9), Color(0.22, 0.18, 0.17, 0.8), Color(0.4, 0.38, 0.37, 0.0)]), PackedFloat32Array([0.0, 0.25, 1.0])), 0.8, 2.4), radius_m * 0.5, radius_m)
	smoke.damping_min = 0.8
	smoke.damping_max = 1.5
	_add_landing(VfxKit.particles(18, 1.8, VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0, {"lumps": 0.8}), Vector2(1.3, 1.3), smoke, true, 0.8))


func _add_landing(p: GPUParticles3D) -> void:
	clocked(p)
	_landing.append(p)


func _start() -> void:
	_landed = false
	_motes.emitting = true
	for s: Array in _shards:
		(s[0] as Node3D).scale = Vector3(1.0, 0.001, 1.0)
		(s[0] as Node3D).visible = false


func _animate(a: float, _t: float) -> void:
	var w: float = span(a, 0.0, warn_s)
	# The circle draws itself round, then fills as the landing comes; flares as it lands; fades after.
	fx(_circle, &"fx_draw", ease_out(span(a, 0.0, 0.3)))
	fx(_circle, &"fx_fill", span(a, 0.1, warn_s) if a < warn_s + 0.05 else -1.0)
	var flare: float = 1.0 - span(a, warn_s, warn_s + 0.4)
	fx(_circle, &"fx_alpha", (1.0 - span(a, warn_s + 0.5, warn_s + 1.3)) * (1.0 + flare * 1.5 * float(a >= warn_s)))
	_motes.emitting = a < warn_s
	_motes.speed_scale = lerpf(0.6, 2.0, w)
	_light.light_energy = 0.8 * w * float(a < warn_s) + 6.0 * flare * float(a >= warn_s)
	if a >= warn_s and not _landed:
		_landed = true
		for p: GPUParticles3D in _landing:
			burst(p)
		if shake > 0.0:
			shook.emit(shake, 0.3)
	# The ring racing out.
	var sr: float = span(a, warn_s, warn_s + 0.45)
	_shock.visible = a >= warn_s and sr < 1.0
	_shock.scale = Vector3.ONE * radius_m * lerpf(0.4, 2.8, ease_out(sr))
	fx(_shock, &"fx_alpha", 1.0 - sr)
	# What rises: a wave from the middle out, each punching up in a tenth of a second. Ice stands, then cracks away;
	# flame leaps on up as it burns out.
	for s: Array in _shards:
		var pivot: Node3D = s[0] as Node3D
		var start: float = warn_s + float(s[1]) * 0.18
		var up: float = span(a, start, start + 0.12)
		pivot.visible = a >= start
		var mesh: GeometryInstance3D = pivot.get_child(0) as GeometryInstance3D
		if _fire():
			var burn: float = span(a, start + 0.1, start + 0.8)
			pivot.scale = Vector3(lerpf(1.0, 0.6, burn), maxf(ease_back(up), 0.001) * lerpf(1.0, 1.5, burn), lerpf(1.0, 0.6, burn))
			fx(mesh, &"fx_erosion", ease_in(burn))
			fx(mesh, &"fx_heat", lerpf(0.25, -0.2, burn))
		else:
			pivot.scale = Vector3(1.0, maxf(ease_back(up), 0.001), 1.0)
			fx(mesh, &"fx_erosion", ease_in(span(a, warn_s + 1.0 + float(s[1]) * 0.25, duration_s - 0.05)))


func _end() -> void:
	_motes.emitting = false
