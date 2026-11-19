@tool
class_name RegentsGladeVista extends Node3D
## THE GLADE'S VALLEY & ATMOSPHERE (visual parity with the login showcase): wraps a flat playable glade in a 360-degree
## sculpted valley (forested hills, a northern hilltop keep, an eastern watchtower bluff, a mountain tarn, snowy horizon
## ridges), drives the level's existing `WorldEnvironment` and `Sun` from a `ShowcaseMood` resource using
## `showcase_sky.gdshader`, and adds living camp warmth (firepit, flickering firelight, flames, embers, sunlit dust and
## meadow fireflies).
##
## Presentation only (hard rule 11): zero collisions, zero server state, zero changes to the level's markers or bake.
## Everything built here is added with `INTERNAL_MODE_BACK`, so opening and saving the level in the editor never bloats
## the `.tscn`. A headless process (the referee, unit suites) builds nothing automatically; suites call `build()` when
## testing it.

const NATURE: String = "res://game/regents/art/nature/"
const PROPS: String = "res://game/regents/art/props/"
const SKY_SHADER: Shader = preload("res://game/regents/showcase/showcase_sky.gdshader")
const GROUND_SHADER: Shader = preload("res://game/regents/showcase/showcase_ground.gdshader")
const WATER_SHADER: Shader = preload("res://game/regents/showcase/showcase_water.gdshader")
const DEFAULT_MOOD: ShowcaseMood = preload("res://game/regents/showcase/moods/frontier.tres")

const TREES: Array[String] = [
	"CommonTree_1", "CommonTree_2", "CommonTree_3",
	"TallThick_1", "TallThick_2", "TallThick_3",
	"TwistedTree_1", "TwistedTree_2", "TwistedTree_3",
]
## Cohesive forest palette (same strategy as ShowcaseWorld): most TallThick / TwistedTree take natural forest greens
## and warm autumn tints while `KIT_LEAVES` keep the kit's own leaves as accents.
const LEAF_LOOKS: Dictionary[String, Array] = {
	"TallThick": ["Leaves_GiantPine_C", Color(0.82, 0.95, 0.8)],
	"TwistedTree": ["Leaves_NormalTree_C", Color(1.0, 0.92, 0.7)],
}
const KIT_LEAVES: float = 0.12

## Keep and eastern watchtower geometry constants.
const KEEP_TOP_M: float = 28.0
const KEEP_FOOTING_M: float = 4.0
const TOWER_TOP_M: float = 22.0
const TOWER_FOOTING_M: float = 4.0
## Outer valley geometry lives on visual layer 2 so Camera3D and Sun see it normally, while camp OmniLights
## (`light_cull_mask = 1`) never render distant valley meshes or forest trees into local shadow maps.
const OUTER_LAYER: int = 2
## Outer trees beyond this radius skip shadow casting (outside the sun's near shadow reach).
const TREE_SHADOW_RADIUS_M: float = 125.0

## The level's mood (dawn, day, golden, dusk, night, or frontier). Changing it relights the level live.
@export var mood: ShowcaseMood = DEFAULT_MOOD:
	set(v):
		mood = v
		if _built:
			apply_mood()
## Sibling WorldEnvironment and DirectionalLight3D driven by `mood`.
@export var world_environment: NodePath = ^"../WorldEnvironment"
@export var sun_light: NodePath = ^"../Sun"
## Optional Terrain3D sibling (e.g. `../Terrain3D` on continent.tscn). When set, Vista uses the real terrain's
## heights instead of generating a procedural Land/Lake shell, and places landmarks & framing woods right on it.
@export var terrain: NodePath = ^""
## Water/sea cutoff when `terrain` is set (trees and rim foliage never spawn below `terrain_water_y + 1.2`).
@export var terrain_water_y: float = -6.0
## Outer radius of the backdrop forest ring when `terrain` is set (fills the continent's empty camp belt).
@export_range(120.0, 450.0, 5.0, "suffix:m") var terrain_forest_reach_m: float = 225.0
@export var vista_seed: int = 19
## Density multiplier (1.0 = full valley).
@export_range(0.2, 1.0, 0.05) var detail: float = 1.0

@export_group("Valley layout")
## Playable glade radius kept tucked safely below y = 0 so Ground/Field owns the flat floor with zero z-fighting.
@export_range(30.0, 120.0, 1.0, "suffix:m") var flat_radius_m: float = 58.0
## How far out the valley terrain and mountain ridges extend.
@export_range(300.0, 1800.0, 10.0, "suffix:m") var reach_m: float = 950.0
## The Regent's keep on its northern hill, and how far its hilltop stays flat.
@export var keep_at: Vector2 = Vector2(-68.0, -158.0)
@export_range(12.0, 50.0, 0.5, "suffix:m") var keep_flat_m: float = 24.0
## Eastern watchtower bluff beyond the skeleton camp.
@export var tower_at: Vector2 = Vector2(138.0, -34.0)
@export_range(6.0, 24.0, 0.5, "suffix:m") var tower_flat_m: float = 10.0
## Scenic mountain tarn nestled above y = 0 on a northeastern shelf (never intersects Ground/Field at y = 0).
@export var lake_at: Vector2 = Vector2(108.0, -128.0)
@export_range(12.0, 80.0, 1.0, "suffix:m") var lake_radius: float = 34.0
@export var water_y: float = 2.2
## Warm camp firepit location inside the frontier camp.
@export var fire_at: Vector3 = Vector3(-3.6, 0.0, 11.4)

@export_group("")
@export_tool_button("Rebuild Vista", "Reload") var rebuild_button: Callable = rebuild

var fire_light: OmniLight3D = null
var moon_light: DirectionalLight3D = null
var placed: Dictionary[String, int] = {}

var _root: Node3D = null
var _sky_mat: ShaderMaterial = null
var _ground_mat: ShaderMaterial = null
var _window_mat: StandardMaterial3D = null
var _torch_lights: Array[OmniLight3D] = []
var _fireflies: GPUParticles3D = null
var _dust: GPUParticles3D = null
var _flames: GPUParticles3D = null
var _embers: GPUParticles3D = null
var _hills: FastNoiseLite = null
var _ridges: FastNoiseLite = null
var _bumps: FastNoiseLite = null
var _forest: FastNoiseLite = null
var _xs: PackedFloat32Array = PackedFloat32Array()
var _hs: PackedFloat32Array = PackedFloat32Array()
var _terrain_node: Terrain3D = null
var _built: bool = false
var _clock: float = 0.0

static var _dot: GradientTexture2D = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	build()


## Has this vista been built yet (headless processes skip `_ready` until `build()` is called).
func is_built() -> bool:
	return _built


## Rebuild everything from scratch (used by the Inspector button and tests).
func rebuild() -> void:
	_clear_built()
	build()


## Build the surrounding valley, landmarks, forest perimeter, camp fire and atmosphere once.
func build() -> void:
	if _built:
		return
	_built = true
	placed.clear()
	_torch_lights.clear()
	_make_noises()
	_terrain_node = get_node_or_null(terrain) as Terrain3D if not terrain.is_empty() else null
	_root = Node3D.new()
	_root.name = "_VistaGenerated"
	add_child(_root, false, Node.INTERNAL_MODE_BACK)
	if not _uses_terrain():
		_build_land()
		_build_water()
	_build_keep()
	_build_watchtower()
	_build_camp()
	_scatter()
	_build_air()
	_build_moon()
	if mood == null:
		mood = DEFAULT_MOOD
	apply_mood()


func _uses_terrain() -> bool:
	return _terrain_node != null and is_instance_valid(_terrain_node)


func _clear_built() -> void:
	_built = false
	placed.clear()
	_torch_lights.clear()
	fire_light = null
	moon_light = null
	_fireflies = null
	_dust = null
	_flames = null
	_embers = null
	_window_mat = null
	_ground_mat = null
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null


# ------------------------------------------------------------------------------------------------ the land

func _make_noises() -> void:
	_hills = FastNoiseLite.new()
	_hills.seed = vista_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0068
	_hills.fractal_octaves = 4
	_ridges = FastNoiseLite.new()
	_ridges.seed = vista_seed + 11
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 0.0030
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_bumps = FastNoiseLite.new()
	_bumps.seed = vista_seed + 23
	_bumps.frequency = 0.04
	_bumps.fractal_octaves = 2
	_forest = FastNoiseLite.new()
	_forest.seed = vista_seed + 37
	_forest.frequency = 0.017
	_forest.fractal_octaves = 3


## The outer valley's height (m) under (x, z). Inside `flat_radius_m` it stays cleanly tucked beneath Ground/Field
## at y = -0.25; outside, it rises seamlessly through y = 0 into forested hills and 360-degree alpine ridges.
func height_at(x: float, z: float) -> float:
	if _hills == null:
		_make_noises()
	var r: float = Vector2(x, z).length()
	var inner_blend: float = smoothstep(flat_radius_m, flat_radius_m + 14.0, r)
	if inner_blend <= 0.0001:
		return -0.25
	var hill_noise: float = _hills.get_noise_2d(x, z) * 0.5 + 0.58
	var ridge_noise: float = _ridges.get_noise_2d(x, z) * 0.5 + 0.52
	var bump: float = _bumps.get_noise_2d(x, z) * 0.55
	# Guaranteed gentle rise out of the flat glade rim so Ground/Field never pokes through outer hills.
	var rim_lift: float = smoothstep(flat_radius_m, flat_radius_m + 32.0, r) * 4.5
	var hills: float = smoothstep(flat_radius_m + 4.0, 175.0, r) * hill_noise * 24.0
	var ridges: float = smoothstep(190.0, 440.0, r) * ridge_noise * 135.0
	var base_rise: float = smoothstep(140.0, 340.0, r) * 20.0
	var h: float = rim_lift + hills + ridges + base_rise + bump * smoothstep(flat_radius_m + 6.0, flat_radius_m + 30.0, r)
	# Keep a gentle valley window toward the northern keep and eastern watchtower so landmarks read clearly from camp.
	var keep_vec: Vector2 = keep_at.normalized()
	var dir2: Vector2 = Vector2(x, z) / maxf(r, 0.001)
	var toward_keep: float = smoothstep(0.82, 0.96, dir2.dot(keep_vec))
	if r < keep_at.length() - 25.0:
		h = lerpf(h, minf(h, 6.5), toward_keep * 0.65)
	var tower_vec: Vector2 = tower_at.normalized()
	var toward_tower: float = smoothstep(0.88, 0.98, dir2.dot(tower_vec))
	if r < tower_at.length() - 20.0:
		h = lerpf(h, minf(h, 5.5), toward_tower * 0.6)
	# The northern keep's hill, broad and wooded so its slopes stay lush green and its walls never hang.
	var dk: float = Vector2(x, z).distance_to(keep_at)
	if dk < 96.0:
		h = maxf(h, KEEP_TOP_M * exp(-pow(dk / 50.0, 2.0)))
	if dk < keep_flat_m + 30.0:
		h = lerpf(h, KEEP_TOP_M, 1.0 - smoothstep(keep_flat_m, keep_flat_m + 30.0, dk))
	# The eastern watchtower bluff.
	var dt: float = Vector2(x, z).distance_to(tower_at)
	if dt < 60.0:
		h = maxf(h, TOWER_TOP_M * exp(-pow(dt / 28.0, 2.0)))
	if dt < tower_flat_m + 18.0:
		h = lerpf(h, TOWER_TOP_M, 1.0 - smoothstep(tower_flat_m, tower_flat_m + 18.0, dt))
	# The northeastern tarn bowl: bed sits cleanly above y = 0.25 so Ground/Field (at y = 0) never pokes through.
	var dl: float = Vector2(x, z).distance_to(lake_at)
	if dl < lake_radius * 1.4:
		var bowl: float = 1.0 - smoothstep(lake_radius * 0.5, lake_radius * 1.3, dl)
		h = lerpf(h, 0.28, bowl)
	return lerpf(-0.25, h, inner_blend)


## Height AS DRAWN on the valley mesh triangles (or the sibling Terrain3D when `terrain` is configured).
func ground_at(x: float, z: float) -> float:
	if _uses_terrain():
		if _terrain_node.data != null:
			var th: float = _terrain_node.data.get_height(Vector3(x, 0.0, z))
			if not is_nan(th):
				return th
		return 0.0
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
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)


func _build_land() -> void:
	var n: int = int(lerpf(80.0, 136.0, detail))
	var xs := PackedFloat32Array()
	xs.resize(n + 1)
	for i: int in range(n + 1):
		var t: float = float(i) / float(n) * 2.0 - 1.0
		xs[i] = signf(t) * pow(absf(t), 1.65) * reach_m
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
	_ground_mat.set_shader_parameter(&"grain", _noise_texture(vista_seed + 5, 0.02, false))
	# Keep shore band below y = 0 so the green meadow rim around the glade never turns sandy.
	_ground_mat.set_shader_parameter(&"water_y", -10.0)
	_ground_mat.set_shader_parameter(&"snow_from_m", 88.0)
	_ground_mat.set_shader_parameter(&"dry_from_m", 20.0)
	# Camp dirt on showcase_ground is disabled (radius 0) because RegentsGroundPaint owns the inner glade.
	_ground_mat.set_shader_parameter(&"camp", Vector3(0.0, 0.0, 0.0))
	mesh.surface_set_material(0, _ground_mat)
	var land := MeshInstance3D.new()
	land.name = "Land"
	land.mesh = mesh
	land.layers = OUTER_LAYER
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(land)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Lake"
	var plane := PlaneMesh.new()
	plane.size = Vector2(lake_radius * 2.6, lake_radius * 2.6)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var ripples: NoiseTexture2D = _noise_texture(vista_seed + 9, 0.06, false)
	ripples.as_normal_map = true
	ripples.bump_strength = 6.0
	mat.set_shader_parameter(&"ripples", ripples)
	water.material_override = mat
	water.position = Vector3(lake_at.x, water_y, lake_at.y)
	water.layers = OUTER_LAYER
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(water)


# ------------------------------------------------------------------------------------------------ landmarks

func _stone_and_roof_mats() -> Array[StandardMaterial3D]:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.60, 0.56)
	stone.albedo_texture = _noise_texture(vista_seed + 41, 0.09, true)
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.12, 0.12, 0.12)
	stone.roughness = 0.95
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.20, 0.25, 0.38)
	roof.roughness = 0.72
	return [stone, roof]


func _build_keep() -> void:
	var root := Node3D.new()
	root.name = "Keep"
	root.position = Vector3(keep_at.x, ground_at(keep_at.x, keep_at.y) - 0.5, keep_at.y)
	_root.add_child(root)
	var mats: Array[StandardMaterial3D] = _stone_and_roof_mats()
	var stone: StandardMaterial3D = mats[0]
	var roof: StandardMaterial3D = mats[1]
	_window_mat = StandardMaterial3D.new()
	_window_mat.albedo_color = Color(0.10, 0.07, 0.04)
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.62, 0.25)
	var footing: float = 10.0 if _uses_terrain() else KEEP_FOOTING_M
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
		_block(root, (p + q) * 0.5 + Vector3(0.0, (9.5 - footing) * 0.5, 0.0),
			Vector3(span, 9.5 + footing, 2.2), along, stone)
		var outward: Vector3 = ((p + q) * 0.5).normalized()
		var steps: int = int(span / 1.6)
		for s: int in range(1, steps):
			if s % 2 == 0:
				continue
			var at: Vector3 = p + dir * (float(s) * span / float(steps)) + outward * 0.8 + Vector3(0.0, 10.0, 0.0)
			_block(root, at, Vector3(0.9, 1.0, 0.6), along, stone)
		_tower(root, p, 3.2, 13.5 + float(i % 2) * 3.0, footing, stone, roof)
	_block(root, Vector3(0.0, (19.0 - footing) * 0.5, 0.0),
		Vector3(12.5, 19.0 + footing, 10.5), 0.3, stone)
	_tower(root, Vector3(4.5, 0.0, -3.0), 3.1, 32.0, footing, stone, roof)
	var hall_roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(13.0, 5.2, 11.0)
	hall_roof.mesh = prism
	hall_roof.material_override = roof
	hall_roof.position = Vector3(0.0, 21.6, 0.0)
	hall_roof.rotation.y = 0.3
	hall_roof.layers = OUTER_LAYER
	hall_roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hall_roof)
	for y: float in [6.5, 10.5, 14.5]:
		for c: int in range(4):
			var off: float = -3.9 + float(c) * 2.6
			for side: float in [-1.0, 1.0]:
				var w := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.75, 1.35, 0.2)
				w.mesh = box
				w.material_override = _window_mat
				w.position = Basis(Vector3.UP, 0.3) * Vector3(off, y, side * 5.3)
				w.rotation.y = 0.3
				w.layers = OUTER_LAYER
				w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(w)
	for side: float in [-1.0, 1.0]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(1.0, 0.55, 0.2)
		torch.omni_range = 10.0
		torch.light_cull_mask = OUTER_LAYER
		var ga: float = atan2(-keep_at.y, -keep_at.x)
		var gate: Vector3 = Vector3(cos(ga), 0.0, sin(ga)) * (wall_r + 1.5)
		var across: Vector3 = Vector3(-sin(ga), 0.0, cos(ga))
		torch.position = gate + across * side * 2.4 + Vector3(0.0, 6.0, 0.0)
		root.add_child(torch)
		_torch_lights.append(torch)


func _build_watchtower() -> void:
	var root := Node3D.new()
	root.name = "Watchtower"
	root.position = Vector3(tower_at.x, ground_at(tower_at.x, tower_at.y) - 0.5, tower_at.y)
	_root.add_child(root)
	var mats: Array[StandardMaterial3D] = _stone_and_roof_mats()
	var stone: StandardMaterial3D = mats[0]
	var roof: StandardMaterial3D = mats[1]
	var footing: float = 10.0 if _uses_terrain() else TOWER_FOOTING_M
	_tower(root, Vector3.ZERO, 3.0, 17.5, footing, stone, roof)
	_block(root, Vector3(-4.2, (5.5 - footing) * 0.5, 2.0),
		Vector3(8.0, 5.5 + footing, 1.8), 0.45, stone)
	_block(root, Vector3(3.6, (4.2 - footing) * 0.5, -2.5),
		Vector3(6.0, 4.2 + footing, 1.8), -0.6, stone)
	var slit := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.65, 1.3, 0.25)
	slit.mesh = box
	slit.material_override = _window_mat
	slit.position = Vector3(-3.05, 11.5, 0.5)
	slit.rotation.y = PI * 0.5
	slit.layers = OUTER_LAYER
	slit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slit)


func _block(parent: Node3D, at: Vector3, size: Vector3, yaw: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.rotation.y = yaw
	mi.layers = OUTER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _tower(parent: Node3D, at: Vector3, radius: float, height: float, footing: float,
		stone: Material, roof: Material) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.08
	cyl.height = height + footing
	cyl.radial_segments = 16
	body.mesh = cyl
	body.material_override = stone
	body.position = at + Vector3(0.0, (height - footing) * 0.5, 0.0)
	body.layers = OUTER_LAYER
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	lip.layers = OUTER_LAYER
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	cone.layers = OUTER_LAYER
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cone)


# ------------------------------------------------------------------------------------------------ camp warmth

## Living camp details placed clear of all stations, spawn, trails and CinemaLab actors.
func _build_camp() -> void:
	var camp := Node3D.new()
	camp.name = "Camp"
	_root.add_child(camp)
	_prop(camp, "FirePit", fire_at, 0.2, 1.0)
	_prop(camp, "Stool", fire_at + Vector3(1.3, 0.0, 0.7), -0.9, 1.0)
	_prop(camp, "Stool", fire_at + Vector3(-1.2, 0.0, -0.9), 0.7, 1.0)
	_prop(camp, "Bench", Vector3(-3.8, 0.0, 21.0), 2.8, 1.0)
	_prop(camp, "Barrel_Holder", Vector3(-5.6, 0.0, 19.6), 0.4, 1.0)
	_prop(camp, "Crate_Wooden", Vector3(-4.5, 0.0, 18.4), 0.35, 1.0)
	_prop(camp, "Barrel", Vector3(-5.5, 0.0, 17.9), 0.0, 1.0)
	_prop(camp, "WeaponStand", Vector3(11.6, 0.0, 22.8), -2.4, 1.0)
	_prop(camp, "Shield_Wooden", Vector3(11.1, 0.35, 22.3), -2.2, 1.0)
	_prop(camp, "Banner_1", Vector3(-8.2, 0.0, 14.8), 0.9, 1.0)
	_prop(camp, "Banner_1", Vector3(12.2, 0.0, 12.2), -0.9, 1.0)
	fire_light = OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.56, 0.22)
	fire_light.omni_range = 15.0
	fire_light.omni_attenuation = 1.4
	fire_light.light_cull_mask = 1
	fire_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	fire_light.position = fire_at + Vector3(0.0, 1.05, 0.0)
	fire_light.shadow_enabled = true
	camp.add_child(fire_light)
	_flames = _particles("Flames", 48, 0.7, Color(1.0, 0.5, 0.14), Vector2(0.32, 0.46),
		Vector3(0.0, 1.3, 0.0), 0.2, Vector3(0.0, 0.6, 0.0), true)
	_flames.position = fire_at + Vector3(0.0, 0.35, 0.0)
	camp.add_child(_flames)
	_embers = _particles("Embers", 40, 2.6, Color(1.0, 0.6, 0.2), Vector2(0.05, 0.05),
		Vector3(0.0, 1.4, 0.0), 0.3, Vector3(0.0, 0.25, 0.0), true)
	(_embers.process_material as ParticleProcessMaterial).turbulence_enabled = true
	(_embers.process_material as ParticleProcessMaterial).turbulence_noise_strength = 2.5
	_embers.position = fire_at + Vector3(0.0, 0.6, 0.0)
	_embers.add_to_group(GraphicsQuality.GROUP_MEDIUM)
	camp.add_child(_embers)


func _prop(parent: Node3D, scene_name: String, at: Vector3, yaw: float, s: float) -> void:
	var scene: PackedScene = load(PROPS + scene_name + ".gltf") as PackedScene
	if scene == null:
		return
	var n: Node3D = scene.instantiate() as Node3D
	n.name = scene_name
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)


# ------------------------------------------------------------------------------------------------ outer forest & slopes

func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = vista_seed * 7919 + 3
	var near_trees: Dictionary[String, Array] = {}
	var far_trees: Dictionary[String, Array] = {}
	for t: String in TREES:
		near_trees[t] = []
		near_trees[t + "/kit"] = []
		far_trees[t] = []
		far_trees[t + "/kit"] = []
	var use_t3d: bool = _uses_terrain()
	var want: int = int((560.0 if use_t3d else 950.0) * detail)
	var max_r: float = terrain_forest_reach_m if use_t3d else 295.0
	var tries: int = 0
	var count: int = 0
	while count < want and tries < want * 14:
		tries += 1
		var r: float = lerpf(flat_radius_m + 3.0, max_r, pow(rng.randf(), 0.78))
		var a: float = rng.randf() * TAU
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		if not is_treeable(x, z):
			continue
		var f: float = _forest.get_noise_2d(x, z)
		if r > flat_radius_m + 28.0 and f < -0.06 + rng.randf() * 0.14:
			continue
		var kind: String = TREES[rng.randi() % TREES.size()]
		if r < flat_radius_m + 24.0 and kind.begins_with("Twisted"):
			kind = "CommonTree_%d" % (rng.randi() % 3 + 1)
		var s: float = rng.randf_range(0.9, 1.55)
		if rng.randf() < KIT_LEAVES:
			kind += "/kit"
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(x, ground_at(x, z) - 0.25, z))
		if r <= TREE_SHADOW_RADIUS_M:
			near_trees[kind].append(xf)
		else:
			far_trees[kind].append(xf)
		count += 1
	for kind: String in near_trees:
		var model: String = kind.get_slice("/", 0)
		var leaves: Array = []
		if not kind.ends_with("/kit"):
			for k: String in LEAF_LOOKS:
				if model.begins_with(k):
					leaves = LEAF_LOOKS[k]
		_multimesh_quadrants(NATURE + model + ".gltf", near_trees[kind], 0.0, Color.WHITE, kind, leaves, 0.0, false, true)
		_multimesh_quadrants(NATURE + model + ".gltf", far_trees[kind], 0.0, Color.WHITE, kind, leaves, 0.0, false, false)
	# Outer valley boulders grounding the rising slopes.
	var rocks: Dictionary[String, Array] = {"Rock_Big_1": [], "Rock_Medium_1": [], "Rock_Medium_2": []}
	var rock_count: int = int((110.0 if use_t3d else 180.0) * detail)
	var rock_max_r: float = terrain_forest_reach_m if use_t3d else 235.0
	for i: int in range(rock_count):
		var r: float = lerpf(flat_radius_m + 1.0, rock_max_r, rng.randf())
		var a: float = rng.randf() * TAU
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		if not _outside_landmarks(x, z, 24.0):
			continue
		if use_t3d and ground_at(x, z) < terrain_water_y + 1.2:
			continue
		var kind: String = rocks.keys()[rng.randi() % 3]
		var s: float = rng.randf_range(0.9, 2.5) * (1.0 + smoothstep(75.0, 225.0, r) * 0.7)
		rocks[kind].append(Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.75, 1.15), s)),
			Vector3(x, ground_at(x, z) - 0.45 * s, z)))
	for kind: String in rocks:
		_multimesh_quadrants(NATURE + kind + ".gltf", rocks[kind], 0.0, Color.WHITE, kind, [], 0.0, false, false)
	# Slope rim bushes, ferns, short plush grass and wildflowers masking the flat-to-hill transition seamlessly.
	# [model, count, min_scale, max_scale, height_scale, tint, sway, outer_r]
	var rim: Array[Array] = [
		["Bush_Large", 160, 0.8, 1.35, 0.9, Color.WHITE, 0.0, 125.0],
		["Bush_Long_1", 150, 0.8, 1.25, 0.9, Color.WHITE, 0.0, 125.0],
		["Fern_1", 320, 0.55, 0.92, 0.65, Color(0.8, 0.9, 0.7), 0.025, 110.0],
		["Flower_3_Group", 440, 0.4, 0.68, 0.6, Color.WHITE, 0.025, 108.0],
		["Grass_Common_Short", 4200, 0.58, 0.95, 0.38, Color(0.74, 0.85, 0.54), 0.035, 108.0],
		["Grass_Common_Tall", 1600, 0.44, 0.72, 0.44, Color(0.7, 0.82, 0.5), 0.045, 112.0],
	]
	for spec: Array in rim:
		var placed_at: Array = []
		var n: int = int(float(spec[1]) * detail)
		var outer: float = float(spec[7])
		var inner: float = flat_radius_m + 1.5
		var hs: float = float(spec[4])
		for i: int in range(n):
			var r: float = sqrt(lerpf(inner * inner, outer * outer, rng.randf()))
			var a: float = rng.randf() * TAU
			var x: float = cos(a) * r
			var z: float = sin(a) * r
			var y: float = ground_at(x, z)
			if not use_t3d and y < 0.05:
				continue
			if use_t3d and y < terrain_water_y + 1.2:
				continue
			if not use_t3d and Vector2(x, z).distance_to(lake_at) < lake_radius * 1.12 and y < water_y + 1.2:
				continue
			if _bumps.get_noise_2d(x * 1.6, z * 1.6) < -0.35:
				continue
			var s: float = rng.randf_range(float(spec[2]), float(spec[3]))
			placed_at.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * hs, s)),
				Vector3(x, y - 0.03, z)))
		_multimesh_quadrants(NATURE + String(spec[0]) + ".gltf", placed_at, float(spec[6]), spec[5] as Color,
			String(spec[0]), [], 130.0, true, false)


## Whether an outer-valley tree may stand at (x, z): never inside the playable glade, lake, keep/tower yard,
## steep cliffs, snow peaks, or blocking the narrow vista corridor to the keep / eastern watchtower.
func is_treeable(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	var r: float = p.length()
	if r < flat_radius_m + 2.0:
		return false
	if not _outside_landmarks(x, z, 26.0):
		return false
	# Keep a scenic framing corridor open toward the northern keep and eastern watchtower.
	var keep_dir: Vector2 = keep_at.normalized()
	if r < keep_at.length() - 22.0 and p.normalized().dot(keep_dir) > 0.972:
		return false
	var tower_dir: Vector2 = tower_at.normalized()
	if r < tower_at.length() - 12.0 and p.normalized().dot(tower_dir) > 0.975:
		return false
	var h: float = ground_at(x, z)
	if _uses_terrain():
		if h < terrain_water_y + 1.2 or h > 48.0:
			return false
	elif h < 0.1 or h > 56.0:
		return false
	var hx: float = ground_at(x + 2.0, z) - h
	var hz: float = ground_at(x, z + 2.0) - h
	return Vector2(hx, hz).length() < 1.5


func _outside_landmarks(x: float, z: float, keep_margin: float) -> bool:
	var p := Vector2(x, z)
	if not _uses_terrain() and p.distance_to(lake_at) < lake_radius * 1.15:
		return false
	if p.distance_to(keep_at) < keep_margin:
		return false
	if p.distance_to(tower_at) < 16.0:
		return false
	return true


## Split outer-valley transforms into 4 quadrants (NE/NW/SE/SW) so camera frustum culling skips off-screen sides.
func _multimesh_quadrants(path: String, transforms: Array, sway_m: float, tint: Color, kind: String,
		leaves: Array, draw_dist: float, density_group: bool, shadows: bool) -> void:
	placed[kind] = placed.get(kind, 0) + transforms.size()
	if transforms.is_empty():
		return
	var buckets: Array[Array] = [[], [], [], []]
	for item: Variant in transforms:
		var xf: Transform3D = item as Transform3D
		var q: int = (1 if xf.origin.x >= 0.0 else 0) + (2 if xf.origin.z >= 0.0 else 0)
		buckets[q].append(xf)
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		found.append(root)
	var parts: Array[Array] = []
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
		parts.append([mesh, RegentsGroundClutter._under(mi, root)])
	root.free()
	for q: int in range(4):
		var bucket: Array = buckets[q]
		if bucket.is_empty():
			continue
		for part: Array in parts:
			var mesh: Mesh = part[0] as Mesh
			var local: Transform3D = part[1] as Transform3D
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = bucket.size()
			for i: int in range(bucket.size()):
				mm.set_instance_transform(i, (bucket[i] as Transform3D) * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_q%d" % [kind, q]
			mmi.multimesh = mm
			mmi.layers = OUTER_LAYER
			if not shadows:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if draw_dist > 0.0:
				mmi.visibility_range_end = draw_dist
			if density_group:
				mmi.add_to_group(GraphicsQuality.GROUP_DENSITY)
			_root.add_child(mmi)
			if density_group and not Engine.is_editor_hint():
				GraphicsQuality.apply_node(mmi)


# ------------------------------------------------------------------------------------------------ air & lighting

func _build_air() -> void:
	_fireflies = _particles("Fireflies", 220, 6.0, Color(0.9, 1.0, 0.48), Vector2(0.06, 0.06),
		Vector3.ZERO, 0.0, Vector3.ZERO, false)
	var fm: ParticleProcessMaterial = _fireflies.process_material as ParticleProcessMaterial
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(36.0, 1.8, 36.0)
	fm.gravity = Vector3.ZERO
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.5
	fm.turbulence_noise_scale = 3.0
	_fireflies.position = Vector3(0.0, 1.8, 6.0)
	_fireflies.visibility_aabb = AABB(Vector3(-45, -5, -45), Vector3(90, 12, 90))
	_fireflies.add_to_group(GraphicsQuality.GROUP_MEDIUM)
	_root.add_child(_fireflies)
	_dust = _particles("Dust", 260, 9.0, Color(1.0, 0.94, 0.78, 0.5), Vector2(0.035, 0.035),
		Vector3.ZERO, 0.0, Vector3.ZERO, false)
	var dm: ParticleProcessMaterial = _dust.process_material as ParticleProcessMaterial
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(22.0, 3.0, 22.0)
	dm.gravity = Vector3(0.14, -0.02, 0.0)
	dm.turbulence_enabled = true
	dm.turbulence_noise_strength = 0.6
	_dust.position = Vector3(0.0, 2.5, 10.0)
	_dust.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 12, 60))
	_dust.add_to_group(GraphicsQuality.GROUP_MEDIUM)
	_root.add_child(_dust)


func _build_moon() -> void:
	moon_light = DirectionalLight3D.new()
	moon_light.name = "Moon"
	moon_light.directional_shadow_max_distance = 120.0
	_root.add_child(moon_light)


func _particles(node_name: String, amount: int, life: float, color: Color, size: Vector2,
		velocity: Vector3, spread_m: float, gravity: Vector3, fire: bool) -> GPUParticles3D:
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
		fade.colors = PackedColorArray([Color(1, 0.9, 0.6, 0), Color(1, 0.75, 0.35, 1),
			Color(0.9, 0.3, 0.08, 0.7), Color(0.3, 0.05, 0.02, 0)])
	else:
		fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1),
			Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
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
	look.albedo_color = Color(color.r * 1.1, color.g * 1.1, color.b * 1.1, color.a) if fire else Color(color.r * 2.6, color.g * 2.6, color.b * 2.6, color.a)
	look.albedo_texture = _soft_dot()
	look.disable_receive_shadows = true
	quad.material = look
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


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


static func _noise_texture(seed_val: int, frequency: float, cells: bool, size: int = 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_val
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


## Apply `mood` to the level's WorldEnvironment, Sun, sky shader, landmarks and air particles.
func apply_mood() -> void:
	if mood == null:
		return
	var we: WorldEnvironment = get_node_or_null(world_environment) as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	var sun: DirectionalLight3D = get_node_or_null(sun_light) as DirectionalLight3D
	var sd: Vector3 = ShowcaseMood.sky_direction(mood.sun_elevation, mood.sun_azimuth)
	var md: Vector3 = ShowcaseMood.sky_direction(mood.moon_elevation, mood.moon_azimuth)
	if sun != null:
		_aim(sun, sd)
		var day: float = smoothstep(-3.0, 4.0, mood.sun_elevation)
		sun.light_color = mood.sun_color
		sun.light_energy = mood.sun_energy * day
		sun.visible = sun.light_energy > 0.001
	if moon_light != null:
		_aim(moon_light, md)
		moon_light.light_color = mood.moon_color
		moon_light.light_energy = mood.moon_energy if mood.moon else 0.0
		moon_light.visible = moon_light.light_energy > 0.001
		moon_light.shadow_enabled = moon_light.visible and (sun == null or not sun.visible)
	if env != null:
		if env.sky == null:
			env.sky = Sky.new()
		var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial
		if sm == null or sm.shader != SKY_SHADER:
			sm = ShaderMaterial.new()
			sm.shader = SKY_SHADER
			sm.set_shader_parameter(&"cloud_noise", _noise_texture(vista_seed + 77, 0.012, false, 512))
			env.sky.sky_material = sm
		elif sm.get_shader_parameter(&"cloud_noise") == null:
			sm.set_shader_parameter(&"cloud_noise", _noise_texture(vista_seed + 77, 0.012, false, 512))
		_sky_mat = sm
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
		env.fog_light_color = mood.fog_color
		env.fog_density = mood.fog_density
		env.volumetric_fog_enabled = mood.mist_density > 0.0
		env.volumetric_fog_density = mood.mist_density
		env.volumetric_fog_albedo = mood.mist_color
		env.volumetric_fog_length = 110.0
		env.volumetric_fog_anisotropy = 0.6
		env.ambient_light_energy = mood.ambient_energy
		env.ambient_light_color = mood.horizon_color.lerp(mood.zenith_color, 0.5).lightened(0.3)
		env.ambient_light_sky_contribution = 0.72
		env.tonemap_exposure = mood.exposure
		env.glow_intensity = mood.glow
		if not Engine.is_editor_hint():
			GraphicsQuality.apply_environment(env)
	if not Engine.is_editor_hint():
		if sun != null:
			GraphicsQuality.apply_light(sun)
		if moon_light != null:
			GraphicsQuality.apply_light(moon_light)
		if fire_light != null:
			GraphicsQuality.apply_light(fire_light)
	if _window_mat != null:
		_window_mat.emission_energy_multiplier = mood.windows
	for t: OmniLight3D in _torch_lights:
		t.light_energy = mood.windows * 1.5
		t.visible = mood.windows > 0.01
	if fire_light != null:
		fire_light.light_energy = mood.fire_energy
	if _fireflies != null:
		_fireflies.amount_ratio = mood.fireflies
		_fireflies.emitting = mood.fireflies > 0.0
	if _dust != null:
		_dust.amount_ratio = mood.dust
		_dust.emitting = mood.dust > 0.0


static func _aim(light: DirectionalLight3D, from_sky: Vector3) -> void:
	var up: Vector3 = Vector3.UP if absf(from_sky.y) < 0.99 else Vector3.FORWARD
	light.basis = Basis.looking_at(-from_sky, up)


func _process(delta: float) -> void:
	if not _built or fire_light == null or mood == null:
		return
	_clock += delta
	var flicker: float = 0.82 + 0.1 * sin(_clock * 7.3) + 0.06 * sin(_clock * 13.1 + 1.7) + 0.05 * sin(_clock * 2.1)
	fire_light.light_energy = mood.fire_energy * flicker
