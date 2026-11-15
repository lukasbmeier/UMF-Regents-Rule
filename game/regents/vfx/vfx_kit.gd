class_name VfxKit extends RefCounted
## THE PARTS EFFECTS ARE MADE OF (the VFX lab, 2026-11-14): noises, color ramps, the shaders' materials, particles,
## and the meshes no primitive gives (a slash's arc, a spike). Everything is made here in code, never loaded from an
## image (Luke's "No AI disclosure": procedural first). An effect (`VfxEffect`) builds its look from these in its
## `_build()`; a designer changes the effect's own exported values in the Inspector, not this file.

const ENERGY_ADD: Shader = preload("res://game/regents/vfx/shaders/vfx_energy_add.gdshader")
const ENERGY_MIX: Shader = preload("res://game/regents/vfx/shaders/vfx_energy_mix.gdshader")
const SPRITE_ADD: Shader = preload("res://game/regents/vfx/shaders/vfx_sprite_add.gdshader")
const SPRITE_MIX: Shader = preload("res://game/regents/vfx/shaders/vfx_sprite_mix.gdshader")
const CIRCLE: Shader = preload("res://game/regents/vfx/shaders/vfx_circle.gdshader")
const DISTORT: Shader = preload("res://game/regents/vfx/shaders/vfx_distort.gdshader")

## A particle's shapes (`vfx_sprite.gdshaderinc`).
enum Shape { DOT, STREAK, STAR, PUFF, SHARD, RING }
## How a particle faces: the camera, round its own up (a streak), or its own turn.
enum Facing { CAMERA, AXIAL, OWN }

## Noises already made, shared by every effect (by their recipe).
static var _noises: Dictionary[String, NoiseTexture2D] = {}


## A seamless noise, made once and shared: `cells` (Voronoi-like cells: ice cracks, scales) or smooth (fire, smoke),
## `frequency` its size (higher: smaller detail).
static func noise(seed: int, frequency: float, cells: bool = false, size: int = 256) -> NoiseTexture2D:
	var key: String = "%d/%.4f/%s/%d" % [seed, frequency, cells, size]
	if _noises.has(key):
		return _noises[key]
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = frequency
	if cells:
		fn.noise_type = FastNoiseLite.TYPE_CELLULAR
		fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	else:
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.normalize = true
	tex.generate_mipmaps = true
	tex.noise = fn
	_noises[key] = tex
	return tex


## A color ramp from `colors` spread evenly (or at `offsets`, 0..1): the heat of an energy look, or a particle's color
## over its life.
## A color past 1 glows (the ramp is kept HDR).
static func ramp(colors: PackedColorArray, offsets: PackedFloat32Array = PackedFloat32Array()) -> GradientTexture1D:
	var g := Gradient.new()
	var at: PackedFloat32Array = offsets
	if at.size() != colors.size():
		at = PackedFloat32Array()
		for i: int in colors.size():
			at.append(float(i) / float(maxi(colors.size() - 1, 1)))
	g.offsets = at
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 128
	tex.use_hdr = true
	return tex


## The energy look (`vfx_energy.gdshaderinc`): glowing (`glows`) or covering, with `heat` its ramp, and any of its
## values in `values` (by the shader's names).
static func energy(glows: bool, heat: GradientTexture1D, values: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENERGY_ADD if glows else ENERGY_MIX
	m.set_shader_parameter(&"noise_a", noise(11, 0.012))
	m.set_shader_parameter(&"noise_b", noise(23, 0.02))
	m.set_shader_parameter(&"ramp", heat)
	for k: Variant in values:
		m.set_shader_parameter(StringName(str(k)), values[k])
	return m


## A particle's look (`vfx_sprite.gdshaderinc`).
static func sprite(glows: bool, shape: Shape, facing: Facing = Facing.CAMERA, intensity: float = 3.0, values: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SPRITE_ADD if glows else SPRITE_MIX
	m.set_shader_parameter(&"noise", noise(37, 0.02))
	m.set_shader_parameter(&"shape", int(shape))
	m.set_shader_parameter(&"facing", int(facing))
	m.set_shader_parameter(&"intensity", intensity)
	for k: Variant in values:
		m.set_shader_parameter(StringName(str(k)), values[k])
	return m


## A circle on the ground (`vfx_circle.gdshader`).
static func circle(values: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CIRCLE
	m.set_shader_parameter(&"noise", noise(51, 0.015))
	for k: Variant in values:
		m.set_shader_parameter(StringName(str(k)), values[k])
	return m


## A ripple in the air (`vfx_distort.gdshader`).
static func distort(values: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DISTORT
	m.set_shader_parameter(&"noise", noise(61, 0.02))
	for k: Variant in values:
		m.set_shader_parameter(StringName(str(k)), values[k])
	return m


## A mesh shown with `material`, casting no shadow.
static func shape_node(mesh: Mesh, material: Material, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not node_name.is_empty():
		mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func sphere(radius: float, segments: int = 32) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = maxi(int(segments / 2.0), 4)
	return s


## A flat square lying on the ground, `size` m across (a circle's or a scorch's).
static func disc(size: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	return p


## An open tube (or a cone, `top` 0), `height` tall, centered on its middle: a pillar of light, a flame's wall, the
## gale's funnel. Its UV is exact (Luke, 2026-11-14: the gale's mouth showed a hard rim): U round it, V 0 at the top
## and 1 at the bottom, so a shader's fade at either end reaches the very edge. (Godot's CylinderMesh keeps part of
## its UV for its caps, so a fade there never reached the edge.)
static func tube(bottom: float, top: float, height: float, segments: int = 32, rings: int = 4) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope: float = (bottom - top) / maxf(height, 0.0001)
	for j: int in rings + 1:
		var v: float = float(j) / float(rings)
		var y: float = height * 0.5 - v * height
		var r: float = lerpf(top, bottom, v)
		for i: int in segments + 1:
			var u: float = float(i) / float(segments)
			var a: float = u * TAU
			var out: Vector3 = Vector3(sin(a), 0.0, cos(a))
			st.set_normal((out + Vector3.UP * slope).normalized())
			st.set_uv(Vector2(u, v))
			st.add_vertex(out * r + Vector3(0.0, y, 0.0))
	var row: int = segments + 1
	for j: int in rings:
		for i: int in segments:
			var k: int = j * row + i
			st.add_index(k)
			st.add_index(k + row)
			st.add_index(k + 1)
			st.add_index(k + 1)
			st.add_index(k + row)
			st.add_index(k + row + 1)
	return st.commit()


## A SLASH'S ARC: a flat band round the up axis, `inner` to `outer` m from it, `degrees` wide, centered on -Z (ahead).
## U runs along the arc (0 where it starts, at the left), V across it (0 inner, 1 outer). A positive `lift` raises
## its end above its start (m), a cut that climbs.
static func arc(inner: float, outer: float, degrees: float, lift: float = 0.0, segments: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = deg_to_rad(degrees) * 0.5
	for i: int in segments + 1:
		var u: float = float(i) / float(segments)
		var a: float = lerpf(-half, half, u)
		var y: float = lift * u
		for j: int in 2:
			var r: float = inner if j == 0 else outer
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u, float(j)))
			st.add_vertex(Vector3(sin(a) * r, y, -cos(a) * r))
	for i: int in segments:
		var k: int = i * 2
		st.add_index(k)
		st.add_index(k + 1)
		st.add_index(k + 2)
		st.add_index(k + 1)
		st.add_index(k + 3)
		st.add_index(k + 2)
	return st.commit()


## A SPIKE: a pointed shard of `sides` faces, `radius` at its foot and `height` tall, centered on its middle (as
## `tube`, whose UV it shares).
static func spike(radius: float, height: float, sides: int = 5) -> ArrayMesh:
	return tube(radius, 0.0, height, sides, 2)


## A particle system that draws `amount` quads `size` m across in `look`, each living `life_s`. One shot (a burst,
## all at once by `explosive`) or a stream; in the world (`in_world`: left behind as it moves) or carried with it.
static func particles(amount: int, life_s: float, look: ShaderMaterial, size: Vector2, process: ParticleProcessMaterial, one_shot: bool, explosive: float = 0.0, in_world: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life_s
	p.one_shot = one_shot
	p.explosiveness = explosive
	p.local_coords = not in_world
	p.emitting = false
	p.fixed_fps = 0
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = look
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	return p


## A process material: thrown out along `direction` within `spread` degrees at `speed` (min, max) m/s, pulled by
## `gravity`; colored over its life by `colors` (its alpha: how faded, or how eaten away for a puff); grown from
## `scale_from` to `scale_to` of its size over its life.
static func motion(direction: Vector3, spread: float, speed: Vector2, gravity: Vector3, colors: GradientTexture1D, scale_from: float = 1.0, scale_to: float = 0.0) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = direction
	m.spread = spread
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = gravity
	m.color_ramp = colors
	var curve := Curve.new()
	curve.max_value = maxf(maxf(scale_from, scale_to), 1.0)
	curve.add_point(Vector2(0.0, scale_from))
	curve.add_point(Vector2(1.0, scale_to))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	return m


## Where a process material's particles start: a ball (`surface`: on its skin only) of `radius`.
static func from_ball(m: ParticleProcessMaterial, radius: float, surface: bool = false) -> ParticleProcessMaterial:
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE if surface else ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	return m


## Where a process material's particles start: a flat ring round the up axis, `inner` to `outer` m from it.
static func from_ring(m: ParticleProcessMaterial, inner: float, outer: float) -> ParticleProcessMaterial:
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = outer
	m.emission_ring_inner_radius = inner
	m.emission_ring_height = 0.0
	return m


## Fire, from its hottest (white) to its coolest (a dark red, faint): an energy look's heat.
static func fire_heat() -> GradientTexture1D:
	return ramp(PackedColorArray([Color(0.35, 0.03, 0.0, 0.0), Color(0.75, 0.12, 0.02, 0.7), Color(1.0, 0.38, 0.05, 1.0), Color(1.0, 0.72, 0.25, 1.0), Color(1.0, 0.95, 0.8, 1.0)]),
		PackedFloat32Array([0.0, 0.3, 0.55, 0.8, 1.0]))


## Frost: deep blue, cyan, white.
static func frost_heat() -> GradientTexture1D:
	return ramp(PackedColorArray([Color(0.05, 0.15, 0.45, 0.0), Color(0.15, 0.45, 0.9, 0.75), Color(0.45, 0.85, 1.0, 1.0), Color(0.9, 1.0, 1.0, 1.0)]),
		PackedFloat32Array([0.0, 0.35, 0.7, 1.0]))


## Arcane light: violet into a white-blue.
static func arcane_heat() -> GradientTexture1D:
	return ramp(PackedColorArray([Color(0.2, 0.0, 0.5, 0.0), Color(0.45, 0.15, 1.0, 0.8), Color(0.55, 0.6, 1.0, 1.0), Color(0.92, 0.95, 1.0, 1.0)]),
		PackedFloat32Array([0.0, 0.35, 0.7, 1.0]))


## A ramp over a particle's life: `color` at full, fading (its alpha) to nothing by the end.
static func fade(color: Color, hold: float = 0.3) -> GradientTexture1D:
	return ramp(PackedColorArray([color, color, Color(color.r, color.g, color.b, 0.0)]), PackedFloat32Array([0.0, hold, 1.0]))
