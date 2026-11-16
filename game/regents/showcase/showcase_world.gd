class_name ShowcaseWorld extends Node3D
## THE SHOWCASE'S VALLEY (2026-11-15): a place made to be looked at, for the login screen, the vista lab and the
## battle lab (the pictures and clips sent to the composers). Everything is made here in code from a seed: the land
## (a meadow camp, hills of forest, a lake, the keep on its hill, snowy ridges far off), its paint
## (`showcase_ground.gdshader`), the sky (`showcase_sky.gdshader`: clouds, sun, moon, stars), the nature kit's trees,
## rocks and grass as MultiMeshes, a keep of stone blocks, the camp's fire, fireflies and dust. A `ShowcaseMood`
## lights it (dawn, day, golden hour, dusk, night; `moods/`). No image file, no AI-made asset (`GAME.md`, "No AI
## disclosure"): noise, math and the kit's CC0 models.
##
## Not the game's world: no server, no collision, no level bake. `ground_at(x, z)` is the ground as drawn, for whoever stands
## on it (a `ShowcaseActor`'s `ground`).
##
## Coordinates: the camp's fire is at the origin; north (-Z) the valley opens to the keep (left) and the lake (right)
## with the ridges behind them.

const NATURE: String = "res://game/regents/art/nature/"
const PROPS: String = "res://game/regents/art/props/"
const TREES: Array[String] = ["CommonTree_1", "CommonTree_2", "CommonTree_3", "TallThick_1", "TallThick_2",
	"TallThick_3", "TwistedTree_1", "TwistedTree_2", "TwistedTree_3"]
## The showcase's forest colors: each tree kind's leaves, by the kit's leaf pictures (the kit draws TallThick blue and
## TwistedTree red; here most are green and a few keep the kit's color as autumn). [kind, leaf picture or "", tint].
const LEAF_LOOKS: Dictionary[String, Array] = {
	"TallThick": ["Leaves_GiantPine_C", Color(0.82, 0.95, 0.8)],
	"TwistedTree": ["Leaves_NormalTree_C", Color(1.0, 0.92, 0.7)],
}
## The share of trees that keep the kit's own leaves (the red and blue accents).
const KIT_LEAVES: float = 0.12
const SKY_SHADER: Shader = preload("res://game/regents/showcase/showcase_sky.gdshader")
const GROUND_SHADER: Shader = preload("res://game/regents/showcase/showcase_ground.gdshader")
const WATER_SHADER: Shader = preload("res://game/regents/showcase/showcase_water.gdshader")

## The time of day. Changing it relights the world at once (no rebuild).
@export var mood: ShowcaseMood = null:
	set(v):
		mood = v
		if _built:
			apply_mood()
## The same seed, the same valley.
@export var world_seed: int = 7
## How much is drawn: 1 the labs' full valley; the login screen less (its land coarser, fewer trees and grass).
@export_range(0.2, 1.0, 0.05) var detail: float = 1.0
@export_group("The land")
## The keep on its hill, and the lake (x, z) and its radius (m).
@export var keep_at: Vector2 = Vector2(-62.0, -128.0)
## The keep's hilltop is flat this far round it (m): its walls (17 m out) and towers stand on it, never over a slope
## (Luke, 2026-11-15: the keep floated). It falls away to the hill's sides over the next 16 m.
@export_range(0.0, 60.0, 0.5, "suffix:m") var keep_flat_m: float = 24.0
@export var lake_at: Vector2 = Vector2(48.0, -62.0)
@export_range(5.0, 120.0, 1.0, "suffix:m") var lake_radius: float = 34.0
@export var water_y: float = -1.4
## The flat ground round the camp (m), and how far the land reaches (m).
@export_range(5.0, 60.0, 1.0, "suffix:m") var camp_flat_m: float = 22.0
@export_range(200.0, 2000.0, 10.0, "suffix:m") var reach_m: float = 950.0

## Lines of sight kept clear of trees and rocks: [from, to, radius] (the stage gives its shots' views, before the
## world enters the tree), so a camera never starts inside a trunk.
var clear_paths: Array[Array] = []
## Trodden ground where people fight or work: (x, z, radius m). No bushes, ferns or tall grass there, the short grass
## thin.
var clearings: Array[Vector3] = []
var sun: DirectionalLight3D = null
var moon: DirectionalLight3D = null
var environment: Environment = null
var fire_light: OmniLight3D = null
var _sky_mat: ShaderMaterial = null
var _ground_mat: ShaderMaterial = null
var _window_mat: StandardMaterial3D = null
var _torch_lights: Array[OmniLight3D] = []
var _fireflies: GPUParticles3D = null
var _dust: GPUParticles3D = null
var _embers: GPUParticles3D = null
var _flames: GPUParticles3D = null
var _hills: FastNoiseLite = null
var _ridges: FastNoiseLite = null
var _bumps: FastNoiseLite = null
var _forest: FastNoiseLite = null
var _built: bool = false
## The land's grid as drawn: its lines (both axes) and the height at each crossing (`ground_at` reads it).
var _xs: PackedFloat32Array = PackedFloat32Array()
var _hs: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
## Every tree, rock and blade placed (world transforms), by kind: what the suite checks (headless keeps no
## MultiMesh transforms).
var placed: Dictionary[String, int] = {}


func _ready() -> void:
	build()


## Make the valley (once; `_ready` does it).
func build() -> void:
	if _built:
		return
	_built = true
	_make_noises()
	_build_environment()
	_build_land()
	_build_water()
	_build_keep()
	_build_camp()
	_scatter()
	_build_air()
	if mood == null:
		mood = load("res://game/regents/showcase/moods/golden.tres") as ShowcaseMood
	apply_mood()


# ------------------------------------------------------------------------------------------------ the land

func _make_noises() -> void:
	_hills = FastNoiseLite.new()
	_hills.seed = world_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0075
	_hills.fractal_octaves = 4
	_ridges = FastNoiseLite.new()
	_ridges.seed = world_seed + 11
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 0.0032
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_bumps = FastNoiseLite.new()
	_bumps.seed = world_seed + 23
	_bumps.frequency = 0.045
	_bumps.fractal_octaves = 2
	_forest = FastNoiseLite.new()
	_forest.seed = world_seed + 37
	_forest.frequency = 0.018
	_forest.fractal_octaves = 3


## The ground's height (m) under (x, z).
func height_at(x: float, z: float) -> float:
	if _hills == null:
		_make_noises()
	var r: float = Vector2(x, z).length()
	var flat: float = smoothstep(camp_flat_m * 0.6, camp_flat_m * 1.8, r)
	var h: float = _bumps.get_noise_2d(x, z) * 0.35 * (0.3 + 0.7 * flat)
	h += smoothstep(camp_flat_m, 120.0, r) * (_hills.get_noise_2d(x, z) * 0.5 + 0.55) * 24.0
	h += smoothstep(170.0, 380.0, r) * (_ridges.get_noise_2d(x, z) * 0.5 + 0.5) * 120.0
	h += smoothstep(120.0, 300.0, r) * 18.0
	# The keep's hill, round and broad, its top flat enough to build on.
	var k: float = Vector2(x, z).distance_to(keep_at)
	if k < 70.0:
		h = maxf(h, 21.0 * exp(-pow(k / 34.0, 2.0)))
	if k < keep_flat_m + 16.0:
		h = lerpf(h, KEEP_TOP_M, 1.0 - smoothstep(keep_flat_m, keep_flat_m + 16.0, k))
	# The lake's bowl.
	var l: float = Vector2(x, z).distance_to(lake_at)
	var bowl: float = 1.0 - smoothstep(lake_radius * 0.55, lake_radius * 1.25, l)
	h = lerpf(h, water_y - 4.5, bowl)
	return h


## The ground AS DRAWN under (x, z): the land mesh's own triangles, never the smooth shape between its points (out
## where the grid is wide a steep slope cuts across them, and a thing set on the shape floats or sinks). Whatever
## stands on the land stands here. Before the land is built: the shape.
func ground_at(x: float, z: float) -> float:
	var n: int = _xs.size() - 1
	if n < 1:
		return height_at(x, z)
	var i: int = clampi(_xs.bsearch(x) - 1, 0, n - 1)
	var j: int = clampi(_xs.bsearch(z) - 1, 0, n - 1)
	var fx: float = clampf((x - _xs[i]) / maxf(_xs[i + 1] - _xs[i], 0.0001), 0.0, 1.0)
	var fz: float = clampf((z - _xs[j]) / maxf(_xs[j + 1] - _xs[j], 0.0001), 0.0, 1.0)
	var h00: float = _hs[j * (n + 1) + i]
	var h10: float = _hs[j * (n + 1) + i + 1]
	var h01: float = _hs[(j + 1) * (n + 1) + i]
	var h11: float = _hs[(j + 1) * (n + 1) + i + 1]
	# The two triangles of a cell as `_build_land` draws them: (i, j) (i+1, j) (i, j+1), then (i+1, j) (i+1, j+1) (i, j+1).
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)


func _build_land() -> void:
	var n: int = int(lerpf(90.0, 230.0, detail))
	var xs: PackedFloat32Array = PackedFloat32Array()
	xs.resize(n + 1)
	for i: int in range(n + 1):
		# Denser near the camp, wide steps out at the ridges.
		var t: float = float(i) / float(n) * 2.0 - 1.0
		xs[i] = signf(t) * pow(absf(t), 1.75) * reach_m
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var x: float = xs[i]
			var z: float = xs[j]
			verts[j * (n + 1) + i] = Vector3(x, height_at(x, z), z)
	_xs = xs
	_hs.resize(verts.size())
	for k2: int in range(verts.size()):
		_hs[k2] = verts[k2].y
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var l: Vector3 = verts[j * (n + 1) + maxi(i - 1, 0)]
			var r: Vector3 = verts[j * (n + 1) + mini(i + 1, n)]
			var d: Vector3 = verts[maxi(j - 1, 0) * (n + 1) + i]
			var u: Vector3 = verts[mini(j + 1, n) * (n + 1) + i]
			normals[j * (n + 1) + i] = (u - d).cross(r - l).normalized()
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var k: int = 0
	for j: int in range(n):
		for i: int in range(n):
			var a: int = j * (n + 1) + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + n + 1
			idx[k + 3] = a + 1
			idx[k + 4] = a + n + 2
			idx[k + 5] = a + n + 1
			k += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_SHADER
	_ground_mat.set_shader_parameter(&"grain", _noise_texture(world_seed + 5, 0.02, false))
	_ground_mat.set_shader_parameter(&"water_y", water_y)
	_ground_mat.set_shader_parameter(&"camp", Vector3(0.0, 7.5, 0.0))
	mesh.surface_set_material(0, _ground_mat)
	var land := MeshInstance3D.new()
	land.name = "Land"
	land.mesh = mesh
	add_child(land)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = Vector2(lake_radius * 3.2, lake_radius * 3.2)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var ripples: NoiseTexture2D = _noise_texture(world_seed + 9, 0.06, false)
	ripples.as_normal_map = true
	ripples.bump_strength = 6.0
	mat.set_shader_parameter(&"ripples", ripples)
	water.material_override = mat
	water.position = Vector3(lake_at.x, water_y, lake_at.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


# ------------------------------------------------------------------------------------------------ the keep

## The regent's keep: a curtain wall and its towers, the keep in the middle, battlements, roofs, lit windows. Stone
## blocks and cones only; it is seen from far off.
## The keep's hilltop height (m).
const KEEP_TOP_M: float = 21.0
## How far every wall, tower and the hall go on down into the hill below the keep's floor (m): no gap shows under one
## where the drawn ground dips between its points.
const KEEP_FOOTING_M: float = 3.0


func _build_keep() -> void:
	var root := Node3D.new()
	root.name = "Keep"
	root.position = Vector3(keep_at.x, ground_at(keep_at.x, keep_at.y) - 0.5, keep_at.y)
	add_child(root)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.6, 0.56)
	stone.albedo_texture = _noise_texture(world_seed + 41, 0.09, true)
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.12, 0.12, 0.12)
	stone.roughness = 0.95
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.2, 0.25, 0.38)
	roof.roughness = 0.7
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(0.1, 0.07, 0.04)
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.62, 0.25)
	var wall_r: float = 17.0
	var towers: int = 6
	for i: int in range(towers):
		var a: float = TAU * float(i) / float(towers) + 0.3
		var p: Vector3 = Vector3(cos(a), 0.0, sin(a)) * wall_r
		var b: float = TAU * float(i + 1) / float(towers) + 0.3
		var q: Vector3 = Vector3(cos(b), 0.0, sin(b)) * wall_r
		var span: float = p.distance_to(q)
		var dir: Vector3 = (q - p).normalized()
		var along: float = atan2(-dir.z, dir.x)
		_block(root, (p + q) * 0.5 + Vector3(0.0, (9.0 - KEEP_FOOTING_M) * 0.5, 0.0), Vector3(span, 9.0 + KEEP_FOOTING_M, 2.2), along, stone)
		var outward: Vector3 = ((p + q) * 0.5).normalized()
		var steps: int = int(span / 1.6)
		for s: int in range(1, steps):
			if s % 2 == 0:
				continue
			var at: Vector3 = p + dir * (float(s) * span / float(steps)) + outward * 0.8 + Vector3(0.0, 9.5, 0.0)
			_block(root, at, Vector3(0.9, 1.0, 0.6), along, stone)
		_tower(root, p, 3.2, 13.0 + float(i % 2) * 3.0, stone, roof)
	# The keep and its high tower.
	_block(root, Vector3(0.0, (18.0 - KEEP_FOOTING_M) * 0.5, 0.0), Vector3(12.0, 18.0 + KEEP_FOOTING_M, 10.0), 0.3, stone)
	_tower(root, Vector3(4.5, 0.0, -3.0), 3.0, 30.0, stone, roof)
	var hall_roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(12.6, 5.0, 10.6)
	hall_roof.mesh = prism
	hall_roof.material_override = roof
	hall_roof.position = Vector3(0.0, 20.5, 0.0)
	hall_roof.rotation.y = 0.3
	root.add_child(hall_roof)
	# Windows in rows on the keep (both long sides), and torches on the gate.
	var rows: Array[float] = [6.0, 10.0, 14.0]
	for y: float in rows:
		for c: int in range(4):
			var off: float = -3.9 + float(c) * 2.6
			for side: float in [-1.0, 1.0]:
				var w := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.7, 1.3, 0.2)
				w.mesh = box
				w.material_override = _window_mat
				w.position = Basis(Vector3.UP, 0.3) * Vector3(off, y, side * 5.05)
				w.rotation.y = 0.3
				w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(w)
	for side: float in [-1.0, 1.0]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(1.0, 0.55, 0.2)
		torch.omni_range = 9.0
		# The gate faces the camp.
		var ga: float = atan2(-keep_at.y, -keep_at.x)
		var gate: Vector3 = Vector3(cos(ga), 0.0, sin(ga)) * (wall_r + 1.5)
		var across: Vector3 = Vector3(-sin(ga), 0.0, cos(ga))
		torch.position = gate + across * side * 2.4 + Vector3(0.0, 6.0, 0.0)
		root.add_child(torch)
		_torch_lights.append(torch)


func _block(parent: Node3D, at: Vector3, size: Vector3, yaw: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.rotation.y = yaw
	parent.add_child(mi)


func _tower(parent: Node3D, at: Vector3, radius: float, height: float, stone: Material, roof: Material) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.08
	cyl.height = height + KEEP_FOOTING_M
	cyl.radial_segments = 16
	body.mesh = cyl
	body.material_override = stone
	body.position = at + Vector3(0.0, (height - KEEP_FOOTING_M) * 0.5, 0.0)
	parent.add_child(body)
	var lip := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = radius * 1.18
	ring.bottom_radius = radius * 1.18
	ring.height = 1.2
	ring.radial_segments = 16
	lip.mesh = ring
	lip.material_override = stone
	lip.position = at + Vector3(0.0, height + 0.4, 0.0)
	parent.add_child(lip)
	var cone := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius * 1.3
	c.height = radius * 2.6
	c.radial_segments = 16
	cone.mesh = c
	cone.material_override = roof
	cone.position = at + Vector3(0.0, height + 1.0 + radius * 1.3, 0.0)
	parent.add_child(cone)


# ------------------------------------------------------------------------------------------------ the camp

## The camp round the fire at the origin: the fire pit and its flames, a stall, the anvil, a weapon stand, the
## workbench, a training dummy. Whoever stands here is the lab's.
func _build_camp() -> void:
	var camp := Node3D.new()
	camp.name = "Camp"
	add_child(camp)
	_prop(camp, "FirePit", Vector3(0.0, 0.0, 0.0), 0.0, 1.0)
	_prop(camp, "Stall_Empty", Vector3(-4.6, 0.0, 3.4), 0.9, 1.15)
	_prop(camp, "Anvil", Vector3(3.6, 0.0, 3.0), -0.6, 1.0)
	_prop(camp, "WeaponStand", Vector3(-3.2, 0.0, -2.6), 2.2, 1.0)
	_prop(camp, "Workbench", Vector3(5.2, 0.0, -1.2), -1.4, 1.0)
	_prop(camp, "Shield_Wooden", Vector3(-2.7, 0.35, -2.2), 2.0, 1.0)
	_prop(camp, "Dummy", Vector3(7.5, 0.0, 5.5), -2.4, 1.0)
	fire_light = OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.56, 0.22)
	fire_light.omni_range = 14.0
	fire_light.omni_attenuation = 1.4
	fire_light.position = Vector3(0.0, 1.0, 0.0)
	fire_light.shadow_enabled = true
	camp.add_child(fire_light)
	_flames = _particles("Flames", 48, 0.7, Color(1.0, 0.5, 0.14), Vector2(0.32, 0.46), Vector3(0.0, 1.3, 0.0),
		0.2, Vector3(0.0, 0.6, 0.0), true)
	_flames.position = Vector3(0.0, 0.35, 0.0)
	camp.add_child(_flames)
	_embers = _particles("Embers", 40, 2.6, Color(1.0, 0.6, 0.2), Vector2(0.05, 0.05), Vector3(0.0, 1.4, 0.0),
		0.3, Vector3(0.0, 0.25, 0.0), true)
	(_embers.process_material as ParticleProcessMaterial).turbulence_enabled = true
	(_embers.process_material as ParticleProcessMaterial).turbulence_noise_strength = 2.5
	_embers.position = Vector3(0.0, 0.6, 0.0)
	camp.add_child(_embers)


func _prop(parent: Node3D, scene_name: String, at: Vector3, yaw: float, s: float) -> void:
	var scene: PackedScene = load(PROPS + scene_name + ".gltf") as PackedScene
	if scene == null:
		return
	var n: Node3D = scene.instantiate() as Node3D
	n.position = Vector3(at.x, ground_at(at.x, at.z) + at.y, at.z)
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)


# ------------------------------------------------------------------------------------------------ trees, rocks, grass

func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 3
	var trees: Dictionary[String, Array] = {}
	for t: String in TREES:
		trees[t] = []
		trees[t + "/kit"] = []
	var want: int = int(1100.0 * detail)
	var tries: int = 0
	var count: int = 0
	while count < want and tries < want * 12:
		tries += 1
		var r: float = lerpf(camp_flat_m + 4.0, 260.0, pow(rng.randf(), 0.8))
		var a: float = rng.randf() * TAU
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		if not _treeable(x, z, r):
			continue
		var f: float = _forest.get_noise_2d(x, z)
		if f < -0.05 + rng.randf() * 0.15:
			continue
		var kind: String = TREES[rng.randi() % TREES.size()]
		if r < 60.0 and kind.begins_with("Twisted"):
			kind = "CommonTree_%d" % (rng.randi() % 3 + 1)
		var s: float = rng.randf_range(0.85, 1.45)
		if rng.randf() < KIT_LEAVES:
			kind += "/kit"
		trees[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(x, ground_at(x, z) - 0.2, z)))
		count += 1
	for kind: String in trees:
		var model: String = kind.get_slice("/", 0)
		var leaves: Array = []
		if not kind.ends_with("/kit"):
			for k: String in LEAF_LOOKS:
				if model.begins_with(k):
					leaves = LEAF_LOOKS[k]
		_multimesh(NATURE + model + ".gltf", trees[kind], 0.0, Color.WHITE, kind, leaves)
	# Rocks on the slopes and a few at the camp's edge.
	var rocks: Dictionary[String, Array] = {"Rock_Big_1": [], "Rock_Medium_1": [], "Rock_Medium_2": []}
	for i: int in range(int(260.0 * detail)):
		var r: float = lerpf(camp_flat_m * 0.7, 230.0, rng.randf())
		var a: float = rng.randf() * TAU
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		if Vector2(x, z).distance_to(lake_at) < lake_radius * 0.7 or Vector2(x, z).distance_to(keep_at) < 22.0:
			continue
		var ra: float = atan2(x, -z)
		if r < 120.0 and ra > -0.75 and ra < 0.85:
			continue
		var kind: String = rocks.keys()[rng.randi() % 3]
		var s: float = rng.randf_range(0.8, 2.6) * (1.0 + smoothstep(60.0, 220.0, r))
		if in_view(x, z, 2.6 * s) or in_clearing(x, z, 3.0 * s):
			continue
		rocks[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)),
			Vector3(x, ground_at(x, z) - 0.4 * s, z)))
	for kind: String in rocks:
		_multimesh(NATURE + kind + ".gltf", rocks[kind], 0.0, Color.WHITE, kind)
	# Grass, flowers, ferns and bushes round the camp and down to the lake.
	var low: Array[Array] = [
		["Grass_Common_Short", 14000, 0.4, 0.8, Color(0.75, 0.86, 0.55), 0.04, 70.0],
		["Grass_Common_Tall", 2600, 0.45, 0.8, Color(0.7, 0.8, 0.5), 0.06, 80.0],
		["Flower_3_Group", 900, 0.4, 0.7, Color.WHITE, 0.03, 60.0],
		["Fern_1", 500, 0.6, 1.0, Color(0.8, 0.9, 0.7), 0.03, 90.0],
		["Bush_Large", 180, 0.7, 1.2, Color.WHITE, 0.0, 110.0],
		["Bush_Long_1", 160, 0.7, 1.1, Color.WHITE, 0.0, 110.0],
	]
	for spec: Array in low:
		var placed_at: Array = []
		var n: int = int(float(spec[1]) * detail)
		var reach: float = float(spec[6])
		for i: int in range(n):
			var r: float = reach * sqrt(rng.randf())
			var a: float = rng.randf() * TAU
			var x: float = cos(a) * r
			var z: float = sin(a) * r - r * 0.25
			# Nothing low grows on the lake's mud flat (it reads as growing out of the water).
			if r < 6.5 or ground_at(x, z) < water_y + 1.3:
				continue
			if _bumps.get_noise_2d(x * 1.7, z * 1.7) < -0.35:
				continue
			var tall: bool = String(spec[0]) != "Grass_Common_Short" and String(spec[0]) != "Flower_3_Group"
			var cleared: bool = in_clearing(x, z)
			if cleared and (tall or rng.randf() < 0.7):
				continue
			if tall and in_view(x, z):
				continue
			var s: float = rng.randf_range(float(spec[2]), float(spec[3]))
			placed_at.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
				Vector3(x, ground_at(x, z) - 0.03, z)))
		_multimesh(NATURE + String(spec[0]) + ".gltf", placed_at, float(spec[5]), spec[4] as Color, String(spec[0]))


## Is (x, z) on trodden ground (or within `margin_m` of it)?
func in_clearing(x: float, z: float, margin_m: float = 0.0) -> bool:
	for c: Vector3 in clearings:
		if Vector2(x, z).distance_to(Vector2(c.x, c.y)) < c.z + margin_m:
			return true
	return false


## Is (x, z) in a camera's line of sight (or within `margin_m` of it: a big thing's bulk)?
func in_view(x: float, z: float, margin_m: float = 0.0) -> bool:
	var p: Vector2 = Vector2(x, z)
	for path: Array in clear_paths:
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		var a2: Vector2 = Vector2(a.x, a.z)
		var b2: Vector2 = Vector2(b.x, b.z)
		var ab: Vector2 = b2 - a2
		var t: float = clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) < float(path[2]) + margin_m:
			return true
	return false


func _treeable(x: float, z: float, r: float) -> bool:
	if in_view(x, z):
		return false
	if Vector2(x, z).distance_to(lake_at) < lake_radius * 1.15:
		return false
	if Vector2(x, z).distance_to(keep_at) < 30.0:
		return false
	# Keep a clear line from the camp north to the keep and the lake.
	var a: float = atan2(x, -z)
	if r < 110.0 and a > -0.75 and a < 0.85:
		return r > 70.0 and _forest.get_noise_2d(x, z) > 0.2
	var h: float = ground_at(x, z)
	var hx: float = ground_at(x + 2.0, z) - h
	var hz: float = ground_at(x, z + 2.0) - h
	return h < 70.0 and Vector2(hx, hz).length() < 1.6


## Draw `transforms` of the model at `path` as one MultiMesh per mesh in it (its materials its own, swaying `sway_m`
## and tinted `tint` if it is foliage).
func _multimesh(path: String, transforms: Array, sway_m: float, tint: Color, kind: String, leaves: Array = []) -> void:
	placed[kind] = placed.get(kind, 0) + transforms.size()
	if transforms.is_empty():
		return
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		found.append(root)
	for nd: Node in found:
		var mi: MeshInstance3D = nd as MeshInstance3D
		if mi.mesh == null:
			continue
		var mesh: Mesh = mi.mesh
		if sway_m > 0.0 or tint != Color.WHITE or not leaves.is_empty():
			mesh = mi.mesh.duplicate() as Mesh
			for i: int in range(mesh.get_surface_count()):
				var mat: ShaderMaterial = mesh.surface_get_material(i) as ShaderMaterial
				if mat == null:
					continue
				var own: ShaderMaterial = mat.duplicate() as ShaderMaterial
				own.set_shader_parameter(&"sway_m", sway_m)
				var base: Variant = mat.get_shader_parameter(&"albedo")
				var t: Color = tint
				if not leaves.is_empty() and mat.resource_name.begins_with("Leaves"):
					own.set_shader_parameter(&"texture_albedo", load(NATURE + String(leaves[0]) + ".png") as Texture2D)
					t = leaves[1] as Color
				own.set_shader_parameter(&"albedo", (base as Color if base is Color else Color.WHITE) * t)
				mesh.surface_set_material(i, own)
		var local: Transform3D = RegentsGroundClutter._under(mi, root)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i: int in range(transforms.size()):
			mm.set_instance_transform(i, (transforms[i] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind
		mmi.multimesh = mm
		if sway_m > 0.0:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	root.free()


# ------------------------------------------------------------------------------------------------ the air

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter(&"cloud_noise", _noise_texture(world_seed + 77, 0.012, false, 512))
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_light_affect = 0.25
	environment.glow_enabled = true
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1
	environment.fog_enabled = true
	environment.fog_sun_scatter = 0.12
	environment.fog_aerial_perspective = 0.6
	environment.fog_sky_affect = 0.15
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.directional_shadow_max_distance = 120.0
	add_child(moon)


func _build_air() -> void:
	_fireflies = _particles("Fireflies", 260, 6.0, Color(0.85, 1.0, 0.45), Vector2(0.06, 0.06), Vector3.ZERO, 0.0,
		Vector3.ZERO, false)
	var fm: ParticleProcessMaterial = _fireflies.process_material as ParticleProcessMaterial
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(30.0, 1.6, 30.0)
	fm.gravity = Vector3.ZERO
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.6
	fm.turbulence_noise_scale = 3.0
	_fireflies.position = Vector3(0.0, 1.6, -8.0)
	_fireflies.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 12, 80))
	add_child(_fireflies)
	_dust = _particles("Dust", 300, 9.0, Color(1.0, 0.95, 0.8, 0.55), Vector2(0.035, 0.035), Vector3.ZERO, 0.0,
		Vector3.ZERO, false)
	var dm: ParticleProcessMaterial = _dust.process_material as ParticleProcessMaterial
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(16.0, 3.0, 16.0)
	dm.gravity = Vector3(0.15, -0.02, 0.0)
	dm.turbulence_enabled = true
	dm.turbulence_noise_strength = 0.6
	_dust.position = Vector3(0.0, 2.5, 0.0)
	_dust.visibility_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 12, 50))
	add_child(_dust)


## A cloud of glowing sprites (soft round points, added light).
func _particles(node_name: String, amount: int, life: float, color: Color, size: Vector2, velocity: Vector3,
		spread_m: float, gravity: Vector3, fire: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	var m := ParticleProcessMaterial.new()
	m.direction = velocity.normalized() if velocity != Vector3.ZERO else Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = velocity.length() * 0.6
	m.initial_velocity_max = velocity.length()
	m.gravity = gravity
	if spread_m > 0.0:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = spread_m
	var fade := Gradient.new()
	if fire:
		fade.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
		fade.colors = PackedColorArray([Color(1, 0.9, 0.6, 0), Color(1, 0.75, 0.35, 1), Color(0.9, 0.3, 0.08, 0.7), Color(0.3, 0.05, 0.02, 0)])
	else:
		fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	if fire:
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 0.6))
		shrink.add_point(Vector2(0.3, 1.0))
		shrink.add_point(Vector2(1.0, 0.15))
		var st := CurveTexture.new()
		st.curve = shrink
		m.scale_curve = st
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = size
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(color.r * 1.1, color.g * 1.1, color.b * 1.1, color.a) if fire else Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, color.a)
	look.albedo_texture = _soft_dot()
	look.disable_receive_shadows = true
	quad.material = look
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static var _dot: GradientTexture2D = null


static func _soft_dot() -> GradientTexture2D:
	if _dot != null:
		return _dot
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	_dot = GradientTexture2D.new()
	_dot.gradient = g
	_dot.fill = GradientTexture2D.FILL_RADIAL
	_dot.fill_from = Vector2(0.5, 0.5)
	_dot.fill_to = Vector2(1.0, 0.5)
	_dot.width = 64
	_dot.height = 64
	return _dot


static func _noise_texture(seed: int, frequency: float, cells: bool, size: int = 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = frequency
	n.fractal_octaves = 5
	if cells:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t


# ------------------------------------------------------------------------------------------------ the mood

## Light the valley as `mood` says.
func apply_mood() -> void:
	if mood == null or environment == null:
		return
	var sd: Vector3 = ShowcaseMood.sky_direction(mood.sun_elevation, mood.sun_azimuth)
	var md: Vector3 = ShowcaseMood.sky_direction(mood.moon_elevation, mood.moon_azimuth)
	_aim(sun, sd)
	_aim(moon, md)
	var day: float = smoothstep(-3.0, 4.0, mood.sun_elevation)
	sun.light_color = mood.sun_color
	sun.light_energy = mood.sun_energy * day
	sun.visible = sun.light_energy > 0.001
	moon.light_color = mood.moon_color
	moon.light_energy = mood.moon_energy if mood.moon else 0.0
	moon.visible = moon.light_energy > 0.001
	moon.shadow_enabled = moon.visible and not sun.visible
	_sky_mat.set_shader_parameter(&"sun_dir", sd)
	_sky_mat.set_shader_parameter(&"moon_dir", md)
	_sky_mat.set_shader_parameter(&"zenith_color", mood.zenith_color)
	_sky_mat.set_shader_parameter(&"horizon_color", mood.horizon_color)
	_sky_mat.set_shader_parameter(&"glow_color", mood.glow_color)
	_sky_mat.set_shader_parameter(&"glow_spread", mood.glow_spread)
	_sky_mat.set_shader_parameter(&"sun_color", mood.sun_color)
	_sky_mat.set_shader_parameter(&"sun_visible", smoothstep(-1.5, 0.5, mood.sun_elevation))
	_sky_mat.set_shader_parameter(&"moon_color", mood.moon_color)
	_sky_mat.set_shader_parameter(&"moon_visible", 1.0 if mood.moon else 0.0)
	_sky_mat.set_shader_parameter(&"stars", mood.stars)
	_sky_mat.set_shader_parameter(&"cloud_cover", mood.cloud_cover)
	_sky_mat.set_shader_parameter(&"cloud_lit", mood.cloud_lit_color)
	_sky_mat.set_shader_parameter(&"cloud_shade", mood.cloud_shade_color)
	_sky_mat.set_shader_parameter(&"cloud_speed", mood.cloud_speed)
	_sky_mat.set_shader_parameter(&"ground_color", mood.fog_color.darkened(0.55))
	environment.fog_light_color = mood.fog_color
	environment.fog_density = mood.fog_density
	environment.volumetric_fog_enabled = mood.mist_density > 0.0
	environment.volumetric_fog_density = mood.mist_density
	environment.volumetric_fog_albedo = mood.mist_color
	environment.volumetric_fog_length = 90.0
	environment.volumetric_fog_anisotropy = 0.6
	environment.ambient_light_energy = mood.ambient_energy
	# Part sky, part the air's own color: a night's people are still seen.
	environment.ambient_light_color = mood.horizon_color.lerp(mood.zenith_color, 0.5).lightened(0.3)
	environment.ambient_light_sky_contribution = 0.7
	environment.tonemap_exposure = mood.exposure
	environment.glow_intensity = mood.glow
	_window_mat.emission_energy_multiplier = mood.windows
	for t: OmniLight3D in _torch_lights:
		t.light_energy = mood.windows * 1.5
		t.visible = mood.windows > 0.01
	fire_light.light_energy = mood.fire_energy
	_fireflies.amount_ratio = mood.fireflies
	_fireflies.emitting = mood.fireflies > 0.0
	_dust.amount_ratio = mood.dust
	_dust.emitting = mood.dust > 0.0


static func _aim(light: DirectionalLight3D, from_sky: Vector3) -> void:
	var up: Vector3 = Vector3.UP if absf(from_sky.y) < 0.99 else Vector3.FORWARD
	light.basis = Basis.looking_at(-from_sky, up)


func _process(delta: float) -> void:
	_clock += delta
	if fire_light != null and mood != null:
		# The fire breathes: two slow waves and a quick one.
		var f: float = 0.82 + 0.1 * sin(_clock * 7.3) + 0.06 * sin(_clock * 13.1 + 1.7) + 0.05 * sin(_clock * 2.1)
		fire_light.light_energy = mood.fire_energy * f
