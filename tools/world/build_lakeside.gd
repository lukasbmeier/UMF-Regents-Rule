extends Node3D
## GENERATES THE LAKESIDE. Writes `res://game/world/lakeside.tscn` and everything it loads:
##
##   game/world/terrain/data/          Terrain3D regions (heights, texture control, colour, foliage)
##   game/world/terrain/lakeside_*.tres the terrain's material and asset list
##   shared/world/lakeside.json        what the SERVER knows about this level (spawn, water, spots)
##   shared/world/lakeside_depth.bin   the lake's depth grid, for casts (see `_bake`)
##
##   godot --headless --path . res://tools/world/build_lakeside.tscn [-- --map=<png>]
##   godot --headless --path . --import        # only needed the first time, for new resources
##
## A scene rather than a `-s` script because Terrain3D must be inside a running tree to import:
## created from `SceneTree._init` it hangs.
##
## RE-RUNNING OVERWRITES. The level is code, so a hand edit to `lakeside.tscn` or a stroke of
## the Terrain3D brushes is lost the next time this runs. Change the shape in `lakeside_shape.gd`
## and the layout here, and re-run. Everything is seeded: the same code writes the same world.
##
## Layout, south to north: the village terrace and its square (spawn), the ramp and the dock, the
## lake. Reed Bay is the lobe on the west shore, Rocky Point the spit from the east shore looking
## out at the Deep Hole, near the middle. Paths run from the square to all three. Hills close the
## world in. Where each fishing spot sits is decided by the rods (lakeside_shape.gd SPOTS).

const SCENE_PATH: String = "res://game/world/lakeside.tscn"
const TERRAIN_DIR: String = "res://game/world/terrain/"
const DATA_DIR: String = TERRAIN_DIR + "data"
const ASSETS_PATH: String = TERRAIN_DIR + "lakeside_assets.tres"
const MATERIAL_PATH: String = TERRAIN_DIR + "lakeside_material.tres"
const TEXTURES_DIR: String = TERRAIN_DIR + "textures/"
const BAKE_JSON: String = "res://shared/world/lakeside.json"
const BAKE_DEPTH: String = "res://shared/world/lakeside_depth.bin"
const LEVEL_SCRIPT: String = "res://game/world/lakeside_level.gd"
const WATER_SCRIPT: String = "res://game/world/lake_water.gd"
const WATER_SHADER: String = "res://game/world/lake_water.gdshader"
const BUILDINGS: String = "res://game/world/buildings/"
const NATURE: String = "res://game/world/kits/nature/"
const PROPS: String = "res://game/world/kits/props/fantasypropsmegakit/Meshes/"
const VILLAGE: String = "res://game/world/kits/village/medievalvillagemegakit/"


## Terrain3D texture ids, in the order the asset list holds them.
enum Tex { GRASS, DIRT, ROCK, SAND, MUD, FOREST }
const TEXTURE_NAMES: Array[String] = ["grass", "dirt", "rock", "sand", "mud", "forest"]
## Metres per texture repeat, as Terrain3D's uv_scale (repeats per metre).
const TEXTURE_UV: Array[float] = [0.11, 0.14, 0.07, 0.12, 0.10, 0.12]
## Terrain3D multiplies each texture by this. The painted grass reads as lime under the sun and
## the kits' own greens; this pulls it back toward them without repainting the textures.
const TEXTURE_TINT: Array[Color] = [Color(0.8, 0.84, 0.74), Color(0.95, 0.93, 0.9), Color.WHITE,
	Color(0.96, 0.94, 0.9), Color.WHITE, Color(0.9, 0.9, 0.86)]

## The deepest a player may wade. The lake barrier runs along this depth contour.
const WADE_DEPTH: float = 0.7
## Depth a float needs to count as "in the water" (the server's rule, written into the bake).
const MIN_CAST_DEPTH: float = 0.5

## The dock: deck height, and its footprint as rectangles [x0, z0, x1, z1] (main pier + head).
const DECK_Y: float = 0.9
const DOCK_PIER: Rect2 = Rect2(-2.0, 22.0, 4.0, 38.0)      # x -2..2, z 22..60
const DOCK_HEAD: Rect2 = Rect2(-5.0, 22.0, 10.0, 6.0)      # x -5..5, z 22..28

## The establishing shot (see `_make_markers`).
const OVERVIEW_EYE: Vector3 = Vector3(-64.0, 44.0, 172.0)
const OVERVIEW_TARGET: Vector3 = Vector3(4.0, 0.0, 16.0)

## Where a new player appears: the top of the ramp, looking down the dock at the lake.
const SPAWN: Vector3 = Vector3(0.0, LakesideShape.TERRACE_HEIGHT + 0.05, 76.0)

## Buildings: [scene, centre x, centre z, yaw degrees, floor offset (metres below ground)].
## A ring round the square in four quarters, the paths running between them, every door turned
## to face the path or square in front of it (houses_a/_d open on local +Z, house_c on +X). House
## C's door is a storey up — in the kit's sample its ground floor is buried — so it sinks one
## storey. The tower closes the square's south side.
const BUILDING_PLAN: Array[Array] = [
	# north of the paths, doors south
	["house_c", -16.0, 76.0, -90.0, 3.0],
	["houses_d", -33.0, 80.0, 0.0, 0.0],
	["houses_d", -48.0, 70.0, 20.0, 0.0],
	["houses_d", 16.0, 78.0, 0.0, 0.0],
	["house_c", 33.0, 77.0, -90.0, 3.0],
	["houses_d", 50.0, 74.0, -30.0, 0.0],
	# south of the paths, doors north
	["houses_a", -30.0, 112.0, 180.0, 0.0],
	["houses_d", -52.0, 104.0, 150.0, 0.0],
	["house_c", 24.0, 112.0, 90.0, 3.0],
	["houses_d", 42.0, 108.0, 180.0, 0.0],
	["tower", 0.0, 118.0, 45.0, 0.3],
]

var _shape: LakesideShape = null
var _rng := RandomNumberGenerator.new()
var _heights: PackedFloat32Array = PackedFloat32Array()
var _terrain: Terrain3D = null
var _root: Node3D = null
var _mesh_ids: Dictionary[String, int] = {}
## Trunks and boulders the scatter placed, for the collider body: [position, radius, height].
var _solids: Array[Array] = []
## Everything the scatter must keep clear of, as circles [centre, radius], filled by the layout.
var _keep_clear: Array[Array] = []
var _map_path: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map_path = arg.substr(6)
	await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	_rng.seed = 0x1A4E51DE
	_shape = LakesideShape.new()

	_root = Node3D.new()
	_root.name = "Lakeside"
	add_child(_root)

	_sample_heights()
	print("build_lakeside: heights sampled (%d ms)" % (Time.get_ticks_msec() - t0))
	_make_environment()
	_make_terrain()
	print("build_lakeside: terrain imported (%d ms)" % (Time.get_ticks_msec() - t0))
	_make_village()
	_make_dock()
	_make_props()
	_scatter_nature()
	print("build_lakeside: %d foliage kinds scattered (%d ms)" % [_mesh_ids.size(), Time.get_ticks_msec() - t0])
	_make_colliders()
	_make_water()
	_make_barrier()
	_make_markers()
	_save_terrain()
	_bake()
	if not _map_path.is_empty():
		_write_map(_map_path)
	_save_scene()
	print("build_lakeside: done in %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


# =============================================================================================
# THE GROUND
# =============================================================================================

func _sample_heights() -> void:
	var n: int = LakesideShape.SIZE
	_heights.resize(n * n)
	for j: int in range(n):
		for i: int in range(n):
			var p: Vector2 = _world_xz(i, j)
			_heights[j * n + i] = _shape.height(p.x, p.y) + _ramp_offset(p.x, p.y)


## World XZ of height-grid pixel (i, j). Pixel (0, 0) is the north-west corner.
static func _world_xz(i: int, j: int) -> Vector2:
	return Vector2(float(i) - LakesideShape.HALF, float(j) - LakesideShape.HALF)


## Grid height at a world point (nearest pixel; the grid is 1 m).
func _h(x: float, z: float) -> float:
	var n: int = LakesideShape.SIZE
	var i: int = clampi(roundi(x + LakesideShape.HALF), 0, n - 1)
	var j: int = clampi(roundi(z + LakesideShape.HALF), 0, n - 1)
	return _heights[j * n + i]


## Slope as rise over run, from the grid.
func _slope(x: float, z: float) -> float:
	var dx: float = (_h(x + 1.0, z) - _h(x - 1.0, z)) * 0.5
	var dz: float = (_h(x, z + 1.0) - _h(x, z - 1.0)) * 0.5
	return Vector2(dx, dz).length()


## The ramp from the terrace down to the dock: along the dock line, the terrace edge is cut
## down to deck height so the dock starts at ground level. Returns what to ADD to the shape.
func _ramp_offset(x: float, z: float) -> float:
	var across: float = smoothstep(7.5, 3.5, absf(x))
	var along: float = smoothstep(46.0, 52.0, z) * (1.0 - smoothstep(72.0, 78.0, z))
	var w: float = across * along
	if w <= 0.0:
		return 0.0
	# Deck height at the shore end, rising to the terrace over 12 m.
	var target: float = lerpf(DECK_Y - 0.04, LakesideShape.TERRACE_HEIGHT, smoothstep(60.0, 72.0, z))
	var h: float = _shape.height(x, z)
	# Only ever cut down: underwater the lake carve is left alone.
	if h <= target:
		return 0.0
	return (target - h) * w


func _make_terrain() -> void:
	var t: Terrain3D = Terrain3D.new()
	t.name = "Terrain3D"
	_root.add_child(t, true)
	_own(t)
	_terrain = t

	# Old regions would load underneath the new ones: start from an empty directory.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	var d: DirAccess = DirAccess.open(DATA_DIR)
	for f: String in d.get_files():
		if f.begins_with("terrain3d") and f.ends_with(".res"):
			d.remove(f)
	t.data_directory = DATA_DIR
	t.vertex_spacing = 1.0
	t.mesh_lods = 7
	t.mesh_size = 48
	t.collision_mode = Terrain3DCollision.FULL_GAME
	t.collision_layer = SpaceTimeEntity.WORLD_MASK
	t.collision_mask = 0

	var mat: Terrain3DMaterial = t.material
	mat.world_background = Terrain3DMaterial.NONE
	mat.auto_shader = false
	mat.texture_filtering = Terrain3DMaterial.LINEAR
	var params: Dictionary = mat.get("_shader_parameters") as Dictionary
	if params.has("blend_sharpness"):
		mat.set_shader_param(&"blend_sharpness", 0.9)

	var assets := Terrain3DAssets.new()
	for id: int in range(TEXTURE_NAMES.size()):
		var ta := Terrain3DTextureAsset.new()
		ta.name = TEXTURE_NAMES[id]
		ta.albedo_texture = load(TEXTURES_DIR + TEXTURE_NAMES[id] + "_albedo.png") as Texture2D
		ta.normal_texture = load(TEXTURES_DIR + TEXTURE_NAMES[id] + "_normal.png") as Texture2D
		ta.uv_scale = TEXTURE_UV[id]
		ta.albedo_color = TEXTURE_TINT[id]
		ta.detiling_rotation = 0.15 if id == Tex.GRASS or id == Tex.FOREST else 0.05
		ta.detiling_shift = 0.2
		assets.set_texture(id, ta)
	t.assets = assets

	var n: int = LakesideShape.SIZE
	var height_img: Image = Image.create_empty(n, n, false, Image.FORMAT_RF)
	var control_img: Image = Image.create_empty(n, n, false, Image.FORMAT_RF)
	var color_img: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var tint := FastNoiseLite.new()
	tint.seed = 606
	tint.frequency = 0.008
	for j: int in range(n):
		for i: int in range(n):
			var p: Vector2 = _world_xz(i, j)
			var h: float = _heights[j * n + i]
			height_img.set_pixel(i, j, Color(h, 0.0, 0.0, 1.0))
			var paint: Vector3i = _paint(p.x, p.y, h)
			var bits: int = Terrain3DUtil.enc_base(paint.x) | Terrain3DUtil.enc_overlay(paint.y) \
				| Terrain3DUtil.enc_blend(paint.z)
			control_img.set_pixel(i, j, Color(Terrain3DUtil.as_float(bits), 0.0, 0.0, 1.0))
			color_img.set_pixel(i, j, _tint(p.x, p.y, h, tint.get_noise_2d(p.x, p.y)))
	t.data.import_images([height_img, control_img, color_img], Vector3(-LakesideShape.HALF, 0.0, -LakesideShape.HALF), 0.0, 1.0)


## Which texture a pixel is, as (base, overlay, blend 0..255).
func _paint(x: float, z: float, h: float) -> Vector3i:
	var bay: float = smoothstep(1.4, 0.8, Vector2(x, z).distance_to(LakesideShape.BAY_CENTRE) / LakesideShape.BAY_RADIUS)
	if h < -1.5:
		return Vector3i(Tex.MUD, Tex.SAND, int(255.0 * 0.25 * smoothstep(-3.0, -1.5, h)))
	if h < 0.25:
		var bed: int = Tex.MUD if bay > 0.5 else Tex.SAND
		var other: int = Tex.SAND if bed == Tex.MUD else Tex.MUD
		return Vector3i(bed, other, int(255.0 * smoothstep(-0.2, -1.5, h) * 0.8))

	var fw: float = _shape.forest_weight(x, z)
	var pw: float = _shape.path_weight(x, z)
	var g: float = _slope(x, z)
	var base: int = Tex.FOREST if fw > 0.65 else Tex.GRASS
	var over: int = Tex.FOREST
	var blend: float = fw if base == Tex.GRASS else 0.0
	# Beach: sand up from the water line.
	var sand: float = smoothstep(0.95, 0.35, h)
	if sand > blend:
		over = Tex.SAND
		blend = sand
	# Rock on anything steep, and on Rocky Point's spit.
	var point: float = smoothstep(LakesideShape.POINT_RADIUS + 3.0, LakesideShape.POINT_RADIUS - 2.0,
		LakesideShape._segment_distance(Vector2(x, z), LakesideShape.POINT_A, LakesideShape.POINT_B))
	var rock: float = maxf(smoothstep(0.62, 1.0, g), point * 0.85)
	if rock > blend:
		over = Tex.ROCK
		blend = rock
	# Paths and the square are dirt, and win over everything but water.
	var square: float = smoothstep(15.0, 10.0, Vector2(x, z).distance_to(LakesideShape.SQUARE))
	var dirt: float = maxf(pw, square)
	if dirt > 0.05:
		over = Tex.DIRT
		blend = maxf(dirt, blend * 0.3)
	return Vector3i(base, over, clampi(int(blend * 255.0), 0, 255))


## Colour map: a gentle large-scale tint so the ground is not one flat green, and a dark, glossy
## band where the ground is wet. Alpha is roughness, 0.5 meaning "as the texture says".
func _tint(x: float, z: float, h: float, noise: float) -> Color:
	var c := Color(1.0 + 0.05 * noise, 1.0 + 0.03 * noise, 1.0 - 0.05 * noise, 0.5)
	var wet: float = smoothstep(0.45, 0.05, h) * smoothstep(-0.8, -0.1, h)
	c = Color(c.r * (1.0 - 0.28 * wet), c.g * (1.0 - 0.25 * wet), c.b * (1.0 - 0.2 * wet), 0.5 - 0.25 * wet)
	# The hills read darker and bluer with distance under fog anyway; lift them a touch.
	var hill: float = smoothstep(8.0, 30.0, h)
	return Color(c.r * (1.0 - 0.06 * hill), c.g * (1.0 - 0.02 * hill), c.b, c.a)


func _save_terrain() -> void:
	var t: Terrain3D = _terrain
	var err: int = ResourceSaver.save(t.assets, ASSETS_PATH)
	if err != OK:
		push_error("build_lakeside: could not save %s (%s)" % [ASSETS_PATH, error_string(err)])
	t.assets.take_over_path(ASSETS_PATH)
	err = ResourceSaver.save(t.material, MATERIAL_PATH)
	if err != OK:
		push_error("build_lakeside: could not save %s (%s)" % [MATERIAL_PATH, error_string(err)])
	t.material.take_over_path(MATERIAL_PATH)
	t.data.save_directory(DATA_DIR)


# =============================================================================================
# THE VILLAGE AND THE DOCK
# =============================================================================================

func _make_village() -> void:
	var village := Node3D.new()
	village.name = "Village"
	_root.add_child(village)
	_own(village)
	var ground: float = LakesideShape.TERRACE_HEIGHT
	for b: Array in BUILDING_PLAN:
		var scene: PackedScene = load(BUILDINGS + str(b[0]) + ".tscn") as PackedScene
		var node: Node3D = scene.instantiate() as Node3D
		node.name = _unique_name(village, str(b[0]).to_pascal_case())
		# The building's own frame has the footprint off-centre; centre it on the plan point.
		var box: AABB = _aabb(node, Transform3D.IDENTITY)
		var centre := Vector3(box.position.x + box.size.x * 0.5, 0.0, box.position.z + box.size.z * 0.5)
		var yaw: float = deg_to_rad(float(b[3]))
		var basis := Basis(Vector3.UP, yaw)
		var at := Vector3(float(b[1]), ground - float(b[4]), float(b[2]))
		node.transform = Transform3D(basis, at - basis * centre)
		village.add_child(node)
		node.owner = _root
		var r: float = maxf(box.size.x, box.size.z) * 0.5 + 3.0
		_keep_clear.append([Vector2(at.x, at.z), r])
	# The square stays open, and so does the spawn point, and the view from the overview camera
	# (nothing tall between it and the lake for its first stretch).
	_keep_clear.append([LakesideShape.SQUARE, 16.0])
	for k: int in range(1, 5):
		var along: Vector3 = OVERVIEW_EYE.lerp(OVERVIEW_TARGET, 0.07 * float(k))
		_keep_clear.append([Vector2(along.x, along.z), 12.0 + 4.0 * float(k)])
	_keep_clear.append([Vector2(SPAWN.x, SPAWN.z), 6.0])


func _make_dock() -> void:
	var dock := Node3D.new()
	dock.name = "Dock"
	_root.add_child(dock)
	_own(dock)
	var tile: PackedScene = load(VILLAGE + "Wall/Floor_WoodDark.gltf") as PackedScene
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.22, 0.15)
	wood.roughness = 0.92
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.13
	post_mesh.bottom_radius = 0.15
	post_mesh.height = 1.0
	post_mesh.radial_segments = 8
	post_mesh.rings = 1
	post_mesh.material = wood
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.18, 0.22, 1.0)
	beam_mesh.material = wood

	# Deck: 2 m tiles over both rectangles, each cell once.
	var cells: Dictionary[Vector2i, bool] = {}
	for rect: Rect2 in [DOCK_PIER, DOCK_HEAD]:
		var x: float = rect.position.x + 1.0
		while x < rect.end.x:
			var z: float = rect.position.y + 1.0
			while z < rect.end.y:
				cells[Vector2i(roundi(x), roundi(z))] = true
				z += 2.0
			x += 2.0
	var keys: Array[Vector2i] = cells.keys()
	keys.sort()
	for c: Vector2i in keys:
		var t: Node3D = tile.instantiate() as Node3D
		t.name = "Deck_%d_%d" % [c.x, c.y]
		t.position = Vector3(float(c.x), DECK_Y - 0.01, float(c.y))
		dock.add_child(t)
		t.owner = _root

	# Posts down to the bed every 4 m along the edges, and the beams they carry.
	var posts: Array[Vector2] = []
	var z_post: float = DOCK_PIER.end.y - 1.0
	while z_post >= DOCK_PIER.position.y:
		posts.append(Vector2(DOCK_PIER.position.x + 0.1, z_post))
		posts.append(Vector2(DOCK_PIER.end.x - 0.1, z_post))
		z_post -= 4.0
	for x_post: float in [DOCK_HEAD.position.x + 0.1, -2.5, 2.5, DOCK_HEAD.end.x - 0.1]:
		posts.append(Vector2(x_post, DOCK_HEAD.position.y + 0.1))
	posts.append(Vector2(DOCK_HEAD.position.x + 0.1, DOCK_HEAD.end.y - 0.1))
	posts.append(Vector2(DOCK_HEAD.end.x - 0.1, DOCK_HEAD.end.y - 0.1))
	var k: int = 0
	for p: Vector2 in posts:
		var bed: float = minf(_h(p.x, p.y), DECK_Y - 0.4) - 0.3
		var top: float = DECK_Y - 0.03
		var post := MeshInstance3D.new()
		post.name = "Post%d" % k
		post.mesh = post_mesh
		post.scale = Vector3(1.0, top - bed, 1.0)
		post.position = Vector3(p.x, (top + bed) * 0.5, p.y)
		dock.add_child(post)
		post.owner = _root
		k += 1
	for x_beam: float in [DOCK_PIER.position.x + 0.1, DOCK_PIER.end.x - 0.1]:
		var beam := MeshInstance3D.new()
		beam.name = "Beam%s" % ("W" if x_beam < 0.0 else "E")
		beam.mesh = beam_mesh
		beam.scale = Vector3(1.0, 1.0, DOCK_PIER.size.y)
		beam.position = Vector3(x_beam, DECK_Y - 0.14, DOCK_PIER.get_center().y)
		dock.add_child(beam)
		beam.owner = _root

	# Lamp posts at the head's outer corners: a tall post with the kit's wall lantern on it.
	var lantern: PackedScene = load(PROPS + "Lantern_Wall.gltf") as PackedScene
	for side: float in [-1.0, 1.0]:
		var x_l: float = side * (DOCK_HEAD.end.x - 0.25)
		var pole := MeshInstance3D.new()
		pole.name = "LampPost%s" % ("W" if side < 0.0 else "E")
		pole.mesh = post_mesh
		pole.scale = Vector3(0.8, 2.4, 0.8)
		pole.position = Vector3(x_l, DECK_Y + 1.2, DOCK_HEAD.position.y + 0.3)
		dock.add_child(pole)
		pole.owner = _root
		var lamp: Node3D = lantern.instantiate() as Node3D
		lamp.name = "Lantern%s" % ("W" if side < 0.0 else "E")
		# The lantern hangs off a wall bracket along its +Z; face it out over the water.
		lamp.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(x_l, DECK_Y + 1.15, DOCK_HEAD.position.y + 0.2))
		dock.add_child(lamp)
		lamp.owner = _root
		var light := OmniLight3D.new()
		light.name = "LanternLight%s" % ("W" if side < 0.0 else "E")
		light.light_color = Color(1.0, 0.72, 0.4)
		light.light_energy = 1.4
		light.omni_range = 7.0
		light.position = Vector3(x_l, DECK_Y + 1.6, DOCK_HEAD.position.y - 0.4)
		dock.add_child(light)
		light.owner = _root

	for c: Vector2 in [Vector2(0.0, 66.0), Vector2(0.0, 56.0), Vector2(0.0, 46.0), Vector2(0.0, 36.0)]:
		_keep_clear.append([c, 6.5])
	_keep_clear.append([Vector2(0.0, 25.0), 9.0])


## The props kit dressing the square, the stalls and the dock. [scene, x, z, yaw°, on-deck?]
const PROP_PLAN: Array[Array] = [
	# Market stalls round the square, facing in, the north side open to the dock.
	["Stall_Vegetables_Full", -12.0, 104.0, 30.0, false],
	["Stall_Potions", 12.0, 104.0, -30.0, false],
	["Stall_Cart_Empty", -14.0, 90.0, 105.0, false],
	["Stall_Empty", 14.0, 90.0, -105.0, false],
	["FarmCrate_Apple", -10.6, 102.4, 30.0, false],
	["Barrel_Holder", 15.5, 101.5, -60.0, false],
	["FirePit", 0.0, 104.0, 0.0, false],
	["Bench", -4.5, 108.0, 180.0, false],
	["Bench", 4.5, 108.0, 180.0, false],
	["Table_Large", 21.0, 88.0, 90.0, false],
	["Stool", 22.2, 87.0, 0.0, false],
	["Stool", 22.2, 89.2, 0.0, false],
	["Barrel", 24.0, 86.5, 0.0, false],
	["Barrel", 24.8, 87.4, 40.0, false],
	["Wagon", 56.0, 94.0, 70.0, false],
	["Crate_Wooden", -20.0, 100.5, 15.0, false],
	["Crate_Wooden", -20.6, 101.6, 50.0, false],
	["Workbench", -22.0, 88.5, 90.0, false],
	["Dummy", 8.0, 121.0, 200.0, false],
	# The dock: gear by the root, a bench at the head.
	["Barrel", -1.4, 55.5, 0.0, true],
	["Crate_Wooden", 1.35, 56.2, 20.0, true],
	["Crate_Wooden", 1.4, 55.2, -10.0, true],
	["Rope_2", -1.2, 46.0, 30.0, true],
	["Bucket_Wooden_1", 1.4, 38.0, 0.0, true],
	["Rope_1", 1.2, 30.4, 0.0, true],
	["Bench", -4.3, 25.0, 90.0, true],
	["Chest_Wood", 4.3, 26.6, 90.0, true],
	["Bucket_Metal", 4.2, 23.0, 0.0, true],
]


func _make_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	_root.add_child(props)
	_own(props)
	for p: Array in PROP_PLAN:
		var scene: PackedScene = load(PROPS + str(p[0]) + ".gltf") as PackedScene
		if scene == null:
			push_error("build_lakeside: missing prop %s" % str(p[0]))
			continue
		var node: Node3D = scene.instantiate() as Node3D
		node.name = _unique_name(props, str(p[0]))
		var x: float = float(p[1])
		var z: float = float(p[2])
		var y: float = DECK_Y if bool(p[4]) else _h(x, z)
		node.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[3]))), Vector3(x, y, z))
		props.add_child(node)
		node.owner = _root
	# Bunting across the square, between the two front stalls' posts.
	var bunting: PackedScene = load(PROPS + "Banner_SmallTriangles_Long.gltf") as PackedScene
	var b: Node3D = bunting.instantiate() as Node3D
	b.name = "Bunting"
	b.transform = Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(0.9, 1.0, 1.0)), Vector3(0.0, LakesideShape.TERRACE_HEIGHT + 5.2, 100.0))
	props.add_child(b)
	b.owner = _root


# =============================================================================================
# NATURE
# =============================================================================================

## Mesh assets: [name, visible range m, casts shadows]. Order is id order.
const FOLIAGE: Array[Array] = [
	["CommonTree_1", 460.0, true], ["CommonTree_2", 460.0, true], ["CommonTree_3", 460.0, true],
	["CommonTree_4", 460.0, true], ["CommonTree_5", 460.0, true],
	["Birch_1", 460.0, true], ["Birch_2", 460.0, true], ["Birch_3", 460.0, true],
	["Birch_4", 460.0, true], ["Birch_5", 460.0, true],
	["Pine_1", 460.0, true], ["Pine_2", 460.0, true], ["Pine_3", 460.0, true],
	["Pine_4", 460.0, true], ["Pine_5", 460.0, true],
	["GiantPine_1", 520.0, true], ["GiantPine_2", 520.0, true], ["GiantPine_3", 520.0, true],
	["GiantPine_4", 520.0, true], ["GiantPine_5", 520.0, true],
	["TallThick_1", 520.0, true], ["TallThick_2", 520.0, true], ["TallThick_3", 520.0, true],
	["TallThick_4", 520.0, true], ["TallThick_5", 520.0, true],
	["TwistedTree_1", 520.0, true], ["TwistedTree_2", 520.0, true], ["TwistedTree_3", 520.0, true],
	["CherryBlossom_1", 460.0, true], ["CherryBlossom_2", 460.0, true], ["CherryBlossom_5", 460.0, true],
	["DeadTree_1", 400.0, true], ["DeadTree_3", 400.0, true],
	["Bush_Common_Flowers", 140.0, true], ["Bush_Large", 180.0, true], ["Bush_Large_Flowers", 180.0, true],
	["Bush_Long_1", 140.0, true], ["Bush_Long_2", 140.0, true],
	["Grass_Common_Short", 60.0, false], ["Grass_Common_Tall", 70.0, false],
	["Grass_Wide_Short", 60.0, false], ["Grass_Wide_Tall", 80.0, false],
	["Grass_Wispy_Short", 60.0, false], ["Grass_Wispy_Tall", 80.0, false], ["Grass_Wheat", 80.0, false],
	["Clover_1", 45.0, false], ["Clover_2", 45.0, false],
	["Flower_1_Group", 80.0, false], ["Flower_2_Group", 80.0, false], ["Flower_3_Group", 80.0, false],
	["Flower_4_Group", 80.0, false], ["Flower_7_Group", 80.0, false],
	["Flower_3_Single", 50.0, false], ["Flower_4_Single", 50.0, false],
	["Plant_1_Big", 70.0, false], ["Plant_2", 60.0, false], ["Plant_2_Big", 90.0, false],
	["Plant_4", 60.0, false], ["Plant_5", 60.0, false],
	["Fern_1", 60.0, false], ["Fern_2", 60.0, false],
	["Mushroom_Common", 35.0, false], ["Mushroom_RedCap", 40.0, false], ["Mushroom_Laetiporus", 40.0, false],
	["Rock_Big_1", 480.0, true], ["Rock_Big_2", 480.0, true],
	["Rock_Medium_1", 300.0, true], ["Rock_Medium_2", 300.0, true], ["Rock_Medium_3", 300.0, true],
	["Rock_Medium_4", 300.0, true],
	["Pebble_Round_1", 30.0, false], ["Pebble_Round_3", 30.0, false], ["Pebble_Square_2", 30.0, false],
	["Pebble_Square_5", 30.0, false],
	["Plant_7_Big", 90.0, false], ["Plant_7", 70.0, false], ["Flower_6", 70.0, false], ["Flower_6_2", 70.0, false],
	["RockPath_Round_Small_1", 90.0, false], ["RockPath_Round_Small_2", 90.0, false],
]

## Trunk radius at scale 1, by name prefix, for the collider body.
const TRUNKS: Dictionary[String, float] = {
	"CommonTree": 0.28, "Birch": 0.24, "Pine": 0.3, "GiantPine": 0.55, "TallThick": 0.45,
	"TwistedTree": 0.6, "CherryBlossom": 0.45, "DeadTree": 0.35,
}


func _scatter_nature() -> void:
	var assets: Terrain3DAssets = _terrain.assets
	for id: int in range(FOLIAGE.size()):
		var f: Array = FOLIAGE[id]
		var ma := Terrain3DMeshAsset.new()
		ma.name = str(f[0])
		ma.scene_file = load(NATURE + str(f[0]) + ".gltf") as PackedScene
		ma.lod0_range = float(f[1])
		ma.fade_margin = minf(8.0, float(f[1]) * 0.1)
		ma.cast_shadows = 1 if bool(f[2]) else 0
		assets.set_mesh_asset(id, ma)
		_mesh_ids[str(f[0])] = id

	var groups: Dictionary[String, Array] = {}   # mesh name -> Array[Transform3D]
	var patch := FastNoiseLite.new()
	patch.seed = 909
	patch.frequency = 0.045
	var grove := FastNoiseLite.new()
	grove.seed = 910
	grove.frequency = 0.012

	# --- trees -----------------------------------------------------------------------------
	_grid(8.5, func(x: float, z: float, h: float, g: float) -> void:
		if h < 0.9 or g > 1.15 or _blocked(x, z, 5.0):
			return
		var fw: float = _shape.forest_weight(x, z)
		var lowland: float = 1.0 - smoothstep(9.0, 20.0, h)
		var highland: float = smoothstep(5.0, 16.0, h)
		var p_broad: float = fw * 0.9 * lowland
		var p_conifer: float = (fw * 0.55 + highland * 0.55) * smoothstep(3.0, 9.0, h)
		# Lone trees in the meadows round the lake, so they are not bare.
		var p_lone: float = 0.035 * (1.0 - fw) * lowland
		if _shape.terrace_weight(x, z) > 0.1:
			return
		var roll: float = _rng.randf()
		var model: String = ""
		if roll < p_broad:
			# Birches are autumn orange in this kit: groves of them, not a scatter.
			var birch: bool = grove.get_noise_2d(x, z) > 0.32
			model = ("Birch_%d" if birch else "CommonTree_%d") % _rng.randi_range(1, 5)
		elif roll < p_broad + p_conifer:
			# The kit's own palette: Pine and GiantPine are green, TallThick is a BLUE fir.
			# Blue is an accent here, not a third of the forest.
			var r: float = _rng.randf()
			if h > 14.0 and r < 0.4:
				model = "GiantPine_%d" % _rng.randi_range(1, 5)
			elif r < 0.9:
				model = "Pine_%d" % _rng.randi_range(1, 5)
			else:
				model = "TallThick_%d" % _rng.randi_range(1, 5)
		elif roll < p_broad + p_conifer + p_lone:
			model = "CommonTree_%d" % _rng.randi_range(1, 5)
		if model.is_empty():
			return
		_place(groups, model, x, z, h, _rng.randf_range(0.8, 1.25), 0.0, 0.25))

	# --- bushes and understorey --------------------------------------------------------------
	_grid(5.5, func(x: float, z: float, h: float, g: float) -> void:
		if h < 0.7 or g > 1.0 or _blocked(x, z, 2.5) or _shape.terrace_weight(x, z) > 0.1:
			return
		var fw: float = _shape.forest_weight(x, z)
		var edge: float = clampf(fw * (1.0 - fw) * 4.0, 0.0, 1.0)
		if _rng.randf() > 0.07 + 0.35 * edge + 0.12 * fw:
			return
		var kinds: Array[String] = ["Bush_Common_Flowers", "Bush_Large", "Bush_Large_Flowers", "Bush_Long_1", "Bush_Long_2"]
		_place(groups, kinds[_rng.randi() % kinds.size()], x, z, h, _rng.randf_range(0.7, 1.2), 0.1, 0.35))

	_grid(3.2, func(x: float, z: float, h: float, g: float) -> void:
		if h < 1.0 or g > 1.1 or _blocked(x, z, 1.5):
			return
		var fw: float = _shape.forest_weight(x, z)
		if fw < 0.35 or _rng.randf() > fw * 0.7:
			return
		var r: float = _rng.randf()
		var model: String = "Fern_%d" % _rng.randi_range(1, 2)
		if r < 0.12:
			model = ["Mushroom_Common", "Mushroom_RedCap", "Mushroom_Laetiporus"][_rng.randi() % 3]
		elif r < 0.3:
			model = "Plant_1_Big"
		_place(groups, model, x, z, h, _rng.randf_range(0.7, 1.3), 0.15, 0.05))

	# --- the meadow ------------------------------------------------------------------------
	_grid(1.7, func(x: float, z: float, h: float, g: float) -> void:
		if h < 0.45 or g > 0.95 or _blocked(x, z, 0.0):
			return
		if _shape.path_weight(x, z) > 0.02:
			return
		var fw: float = _shape.forest_weight(x, z)
		var clump: float = patch.get_noise_2d(x, z) * 0.5 + 0.5
		# The village is trodden: a clump here and there, thicker toward the terrace's edge.
		var trodden: float = 1.0 - 0.75 * _shape.terrace_weight(x, z)
		if _rng.randf() > (0.35 + 0.6 * clump) * (1.0 - 0.7 * fw) * trodden:
			return
		var r: float = _rng.randf()
		var model: String = ""
		if r < 0.28:
			model = "Grass_Common_Short"
		elif r < 0.45:
			model = "Grass_Wide_Short"
		elif r < 0.6:
			model = "Grass_Wispy_Short"
		elif r < 0.72:
			model = "Grass_Common_Tall"
		elif r < 0.8:
			model = "Grass_Wide_Tall"
		elif r < 0.86:
			model = "Grass_Wispy_Tall"
		elif r < 0.9:
			model = "Grass_Wheat"
		else:
			model = "Clover_%d" % _rng.randi_range(1, 2)
		_place(groups, model, x, z, h, _rng.randf_range(0.45, 0.8), 0.12, 0.03))

	_grid(3.6, func(x: float, z: float, h: float, g: float) -> void:
		if h < 0.6 or g > 0.8 or _blocked(x, z, 1.0):
			return
		if _shape.path_weight(x, z) > 0.02 or _shape.terrace_weight(x, z) > 0.2:
			return
		var bloom: float = patch.get_noise_2d(x * 0.7 + 400.0, z * 0.7) * 0.5 + 0.5
		if _rng.randf() > smoothstep(0.45, 0.8, bloom) * 0.7 * (1.0 - _shape.forest_weight(x, z)):
			return
		var kinds: Array[String] = ["Flower_1_Group", "Flower_2_Group", "Flower_3_Group", "Flower_4_Group",
			"Flower_7_Group", "Flower_3_Single", "Flower_4_Single", "Plant_2", "Plant_4", "Plant_5"]
		_place(groups, kinds[_rng.randi() % kinds.size()], x, z, h, _rng.randf_range(0.6, 1.0), 0.1, 0.03))

	# --- stone -----------------------------------------------------------------------------
	_grid(15.0, func(x: float, z: float, h: float, g: float) -> void:
		if h < 1.5 or _blocked(x, z, 4.0):
			return
		var p: float = 0.1 + 0.4 * smoothstep(0.5, 1.1, g) + 0.2 * smoothstep(12.0, 30.0, h)
		if _rng.randf() > p:
			return
		var big: bool = _rng.randf() < 0.3
		var model: String = ("Rock_Big_%d" % _rng.randi_range(1, 2)) if big else ("Rock_Medium_%d" % _rng.randi_range(1, 4))
		_place(groups, model, x, z, h, _rng.randf_range(0.7, 1.4), 0.25, 0.3, true))

	_grid(2.4, func(x: float, z: float, h: float, g: float) -> void:
		if h < -0.4 or h > 0.6 or _blocked(x, z, 0.5) or _rng.randf() > 0.3:
			return
		var kinds: Array[String] = ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_2", "Pebble_Square_5"]
		_place(groups, kinds[_rng.randi() % kinds.size()], x, z, h, _rng.randf_range(0.8, 1.6), 0.2, 0.02))

	# --- the water's edge -------------------------------------------------------------------
	# Reeds stand in the shallows: thick in Reed Bay, in clumps elsewhere. They grow from the bed,
	# so they poke through the surface by however much deeper than the bed they are tall.
	_grid(1.3, func(x: float, z: float, h: float, _g: float) -> void:
		if h > 0.15 or h < -0.9 or _blocked(x, z, 0.0):
			return
		var bay: float = smoothstep(1.3, 0.9, Vector2(x, z).distance_to(LakesideShape.BAY_CENTRE) / LakesideShape.BAY_RADIUS)
		var clump: float = smoothstep(0.55, 0.85, patch.get_noise_2d(x + 900.0, z) * 0.5 + 0.5)
		if _rng.randf() > 0.75 * bay + 0.5 * clump:
			return
		var kinds: Array[String] = ["Grass_Wide_Tall", "Grass_Wispy_Tall", "Plant_2_Big", "Grass_Wide_Tall"]
		_place(groups, kinds[_rng.randi() % kinds.size()], x, z, h, _rng.randf_range(0.8, 1.25), 0.1, 0.0))

	# Lily pads float ON the surface, in the calm shallows.
	_grid(2.6, func(x: float, z: float, h: float, _g: float) -> void:
		if h > -0.4 or h < -1.8 or _blocked(x, z, 0.0):
			return
		var bay: float = smoothstep(1.4, 0.8, Vector2(x, z).distance_to(LakesideShape.BAY_CENTRE) / LakesideShape.BAY_RADIUS)
		var clump: float = smoothstep(0.6, 0.85, patch.get_noise_2d(x - 700.0, z + 300.0) * 0.5 + 0.5)
		if _rng.randf() > 0.6 * bay + 0.45 * clump:
			return
		var r: float = _rng.randf()
		var model: String = "Plant_7_Big" if r < 0.5 else ("Plant_7" if r < 0.8 else "Flower_6%s" % ("" if r < 0.9 else "_2"))
		# The lily models stand a little proud of their origin; sit the pads ON the surface.
		var lift: float = -0.08 if model.begins_with("Plant_7") else -0.02
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.2))
		_add(groups, model, Transform3D(basis, Vector3(x, LakesideShape.WATER + lift, z))))

	# --- hand-placed landmarks ---------------------------------------------------------------
	var landmarks: Array[Array] = [
		["TwistedTree_1", -42.0, -112.0, 1.0], ["TwistedTree_2", 52.0, -110.0, 1.1],
		["TwistedTree_3", -136.0, -14.0, 0.95], ["TwistedTree_1", 120.0, -52.0, 0.9],
		["CherryBlossom_1", -58.0, 60.0, 0.85], ["CherryBlossom_2", 60.0, 60.0, 0.8],
		["CherryBlossom_5", -14.0, 128.0, 0.8], ["CherryBlossom_1", 54.0, 124.0, 0.75],
		["DeadTree_1", 68.0, -36.0, 0.9], ["DeadTree_3", -142.0, 30.0, 0.85],
		["Rock_Big_1", 98.0, -47.0, 1.2], ["Rock_Big_2", 82.0, -37.0, 1.0],
		["Rock_Medium_3", 70.0, -48.0, 1.1], ["Rock_Medium_1", 64.0, -41.0, 0.9],
		["Rock_Medium_4", 90.0, -33.0, 1.0], ["Rock_Big_2", 110.0, -43.0, 0.9],
	]
	for lm: Array in landmarks:
		var x: float = float(lm[1])
		var z: float = float(lm[2])
		_place(groups, str(lm[0]), x, z, _h(x, z), float(lm[3]), 0.0, 0.3, str(lm[0]).begins_with("Rock"))
	# Stepping stones out to the reeds at the bay's edge.
	for i: int in range(7):
		var sx: float = -96.0 - float(i) * 1.6
		var sz: float = 52.0 - float(i) * 1.9
		var stone: String = "RockPath_Round_Small_%d" % (1 + i % 2)
		_add(groups, stone, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(sx, _h(sx, sz) + 0.02, sz)))

	var total: int = 0
	for model: String in groups:
		var xforms: Array[Transform3D] = []
		xforms.assign(groups[model])
		total += xforms.size()
		_terrain.instancer.add_transforms(_mesh_ids[model], xforms, PackedColorArray(), true)
	print("build_lakeside: %d instances of %d meshes, %d colliders" % [total, groups.size(), _solids.size()])


## Visit a jittered grid over the whole map, calling `visit(x, z, height, slope)`.
func _grid(cell: float, visit: Callable) -> void:
	var lo: float = -LakesideShape.HALF + 2.0
	var hi: float = LakesideShape.HALF - 2.0
	var z: float = lo
	while z < hi:
		var x: float = lo
		while x < hi:
			var px: float = x + _rng.randf() * cell
			var pz: float = z + _rng.randf() * cell
			visit.call(px, pz, _h(px, pz), _slope(px, pz))
			x += cell
		z += cell


## True where the layout keeps ground clear (buildings, the square, the dock, spawn) — or where
## the extra `margin` would reach a path.
func _blocked(x: float, z: float, margin: float) -> bool:
	for c: Array in _keep_clear:
		var r: float = float(c[1]) + margin
		if Vector2(x, z).distance_squared_to(c[0] as Vector2) < r * r:
			return true
	if margin > 0.0 and _path_distance(x, z) < 1.8 + margin:
		return true
	return false


func _path_distance(x: float, z: float) -> float:
	return LakesideShape.path_distance(x, z)


## Stand a mesh on the ground: random yaw, a small lean, sunk a little so it does not float on
## a slope. Trees and rocks also get a collider.
func _place(groups: Dictionary[String, Array], model: String, x: float, z: float, h: float,
		s: float, lean: float, sink: float, solid_rock: bool = false) -> void:
	var yaw: float = _rng.randf() * TAU
	var tilt := Vector3(_rng.randf_range(-lean, lean), 0.0, _rng.randf_range(-lean, lean))
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis.from_euler(tilt)
	basis = basis.scaled(Vector3.ONE * s)
	_add(groups, model, Transform3D(basis, Vector3(x, h - sink * s, z)))
	for prefix: String in TRUNKS:
		if model.begins_with(prefix):
			_solids.append([Vector3(x, h, z), TRUNKS[prefix] * s, 5.0])
			return
	if solid_rock:
		var r: float = (1.3 if model.begins_with("Rock_Big") else 0.9) * s
		_solids.append([Vector3(x, h, z), r, 2.4 * s])


func _add(groups: Dictionary[String, Array], model: String, xf: Transform3D) -> void:
	if not _mesh_ids.has(model):
		push_error("build_lakeside: %s is not in FOLIAGE" % model)
		return
	if not groups.has(model):
		groups[model] = []
	groups[model].append(xf)


## One static body for every trunk and boulder, on the world layer: the camera boom stops at
## a trunk exactly as it stops at a wall.
func _make_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "NatureColliders"
	body.collision_layer = SpaceTimeEntity.WORLD_MASK
	body.collision_mask = 0
	_root.add_child(body)
	_own(body)
	var shapes: Dictionary[String, CylinderShape3D] = {}
	var k: int = 0
	for s: Array in _solids:
		var r: float = snappedf(float(s[1]), 0.05)
		var h: float = snappedf(float(s[2]), 0.5)
		var key: String = "%.2f_%.1f" % [r, h]
		if not shapes.has(key):
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = h
			shapes[key] = cyl
		var cs := CollisionShape3D.new()
		cs.name = "S%d" % k
		cs.shape = shapes[key]
		var p: Vector3 = s[0]
		cs.position = Vector3(p.x, p.y + h * 0.5 - 0.3, p.z)
		body.add_child(cs)
		cs.owner = _root
		k += 1


# =============================================================================================
# WATER, BARRIER, MARKERS
# =============================================================================================

func _make_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(LakesideShape.SIZE, LakesideShape.SIZE)
	water.mesh = plane
	water.position = Vector3(0.0, LakesideShape.WATER, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_SHADER) as Shader
	mat.set_shader_parameter(&"wave_a", _wave_texture(3, 0.03, 4.0))
	mat.set_shader_parameter(&"wave_b", _wave_texture(11, 0.05, 3.0))
	water.material_override = mat
	water.set_script(load(WATER_SCRIPT))
	_root.add_child(water)
	_own(water)


static func _wave_texture(seed_value: int, frequency: float, bump: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = bump
	tex.noise = noise
	return tex


## Nobody wades out past `WADE_DEPTH` and nobody falls off the dock: an invisible wall along
## that depth contour, and round the dock's open sides. Both sides of a wall stop a body (a
## one-sided concave face does not make a one-way door for `move_and_slide`: tested, it blocks
## from both), so the wall is closed rather than a trap door, and the dock's rails go down to
## the bed so there is no swimming under it either.
##
## On physics layer 3, which entity bodies collide with and the camera boom does not: a
## barrier is not a thing, and the camera should not bump into one.
func _make_barrier() -> void:
	var body := StaticBody3D.new()
	body.name = "Barrier"
	body.collision_layer = SpaceTimeEntity.BARRIER_MASK
	body.collision_mask = 0
	_root.add_child(body)
	_own(body)

	var faces := PackedVector3Array()
	var level: float = LakesideShape.WATER - WADE_DEPTH
	var n: int = LakesideShape.SIZE
	var segments: int = 0
	for j: int in range(n - 1):
		for i: int in range(n - 1):
			var a: float = _heights[j * n + i] - level
			var b: float = _heights[j * n + i + 1] - level
			var c: float = _heights[(j + 1) * n + i + 1] - level
			var d: float = _heights[(j + 1) * n + i] - level
			var pts: Array[Vector2] = []
			var corners: Array[Vector2] = [_world_xz(i, j), _world_xz(i + 1, j), _world_xz(i + 1, j + 1), _world_xz(i, j + 1)]
			var vals: Array[float] = [a, b, c, d]
			for e: int in range(4):
				var v0: float = vals[e]
				var v1: float = vals[(e + 1) % 4]
				if (v0 < 0.0) != (v1 < 0.0):
					var t: float = v0 / (v0 - v1)
					pts.append(corners[e].lerp(corners[(e + 1) % 4], t))
			var k: int = 0
			while k + 1 < pts.size():
				segments += _wall(faces, pts[k], pts[k + 1], -6.0, 3.5)
				k += 2
	# The dock's open sides, from the bed to above head height.
	var rail: Array[Vector2] = [
		Vector2(DOCK_PIER.position.x - 0.05, 54.0), Vector2(DOCK_PIER.position.x - 0.05, DOCK_HEAD.end.y),
		Vector2(DOCK_HEAD.position.x - 0.05, DOCK_HEAD.end.y), Vector2(DOCK_HEAD.position.x - 0.05, DOCK_HEAD.position.y - 0.05),
		Vector2(DOCK_HEAD.end.x + 0.05, DOCK_HEAD.position.y - 0.05), Vector2(DOCK_HEAD.end.x + 0.05, DOCK_HEAD.end.y),
		Vector2(DOCK_PIER.end.x + 0.05, DOCK_HEAD.end.y), Vector2(DOCK_PIER.end.x + 0.05, 54.0),
	]
	for r: int in range(rail.size() - 1):
		_wall(faces, rail[r], rail[r + 1], -12.0, DECK_Y + 2.2, true)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "LakeEdge"
	cs.shape = shape
	body.add_child(cs)
	cs.owner = _root
	print("build_lakeside: lake barrier %d segments, %d triangles" % [segments, faces.size() / 3])

	# The edge of the world, behind the hills.
	var edge: float = LakesideShape.HALF - 8.0
	for side: int in range(4):
		var box := BoxShape3D.new()
		var along_x: bool = side < 2
		box.size = Vector3(LakesideShape.SIZE if along_x else 2.0, 120.0, 2.0 if along_x else LakesideShape.SIZE)
		var w := CollisionShape3D.new()
		w.name = "WorldEdge%d" % side
		w.shape = box
		var s: float = -1.0 if side % 2 == 0 else 1.0
		w.position = Vector3(0.0 if along_x else s * edge, 20.0, s * edge if along_x else 0.0)
		body.add_child(w)
		w.owner = _root


## One vertical quad from `a` to `b`, `bottom` to `top`. Skips contour pieces inside the dock's
## footprint (the rails close it instead) unless `force`. Returns 1 if a quad was added.
func _wall(faces: PackedVector3Array, a: Vector2, b: Vector2, bottom: float, top: float,
		force: bool = false) -> int:
	if not force:
		var mid: Vector2 = (a + b) * 0.5
		var pier := Rect2(DOCK_PIER.position - Vector2(0.1, 0.1), DOCK_PIER.size + Vector2(0.2, 0.2))
		var head := Rect2(DOCK_HEAD.position - Vector2(0.1, 0.1), DOCK_HEAD.size + Vector2(0.2, 0.2))
		if pier.has_point(mid) or head.has_point(mid):
			return 0
	var a0 := Vector3(a.x, bottom, a.y)
	var b0 := Vector3(b.x, bottom, b.y)
	var a1 := Vector3(a.x, top, a.y)
	var b1 := Vector3(b.x, top, b.y)
	faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	return 1


## True within `margin` metres of the dock's deck.
static func _over_dock(p: Vector2, margin: float) -> bool:
	for rect: Rect2 in [DOCK_PIER, DOCK_HEAD]:
		if rect.grow(margin).has_point(p):
			return true
	return false


func _make_markers() -> void:
	var spots := Node3D.new()
	spots.name = "Spots"
	_root.add_child(spots)
	_own(spots)
	for s: Array in LakesideShape.SPOTS:
		var m := Marker3D.new()
		m.name = str(s[0]).to_pascal_case()
		var c: Vector2 = s[2]
		m.position = Vector3(c.x, LakesideShape.WATER, c.y)
		m.gizmo_extents = float(s[3])
		m.set_meta(&"spot_id", str(s[0]))
		m.set_meta(&"display_name", str(s[1]))
		spots.add_child(m)
		m.owner = _root

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = SPAWN
	_root.add_child(spawn)
	_own(spawn)

	var world_root := Node3D.new()
	world_root.name = "WorldRoot"
	_root.add_child(world_root)
	_own(world_root)

	# The establishing shot: from the south-west hill, over the village, up the lake. The connect
	# screen looks through it, and so does the terrain until a player camera takes over.
	var cam := Camera3D.new()
	cam.name = "OverviewCamera"
	cam.fov = 60.0
	cam.far = 1200.0
	_root.add_child(cam)
	_own(cam)
	cam.look_at_from_position(OVERVIEW_EYE, OVERVIEW_TARGET)


func _make_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.78)
	sky_mat.sky_horizon_color = Color(0.70, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.62, 0.68, 0.72)
	sky_mat.ground_bottom_color = Color(0.22, 0.26, 0.24)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.84)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_root.add_child(world_env)
	_own(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 32.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	# Where the shadow map's resolution goes (DECISIONS #137). The default splits spend a quarter
	# of the map on everything past 70 m and blur what a third-person camera actually looks at;
	# these keep the first two splits on the player's own few metres and the dock, and the far
	# one on the tree line across the lake, which fog softens anyway.
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	# Twice the default: leaf cards lie at every angle to the sun, and at 1.0 the ones nearly edge-on
	# to it shadow themselves in stripes.
	sun.shadow_normal_bias = 2.0
	_root.add_child(sun)
	_own(sun)


# =============================================================================================
# THE BAKE: what the server knows about this level
# =============================================================================================

## `shared/world/lakeside.json` + `lakeside_depth.bin`. The module compiles both in (build.rs),
## and `LakesideLevel` reads the JSON, so the client's answer to "is that water" and the
## server's come from one file.
##
## The depth grid covers only the lake's bounding box: one byte per square metre, the water's
## depth in DECIMETRES there (0 = dry, capped at 25.5 m), row-major from the north-west corner.
## Taken from the TERRAIN (`get_height`), not from the shape function, so it is the ground the
## player sees and stands on.
func _bake() -> void:
	var water: float = LakesideShape.WATER
	var n: int = LakesideShape.SIZE
	var lo := Vector2i(n, n)
	var hi := Vector2i(-1, -1)
	for j: int in range(n):
		for i: int in range(n):
			if _heights[j * n + i] < water:
				lo = Vector2i(mini(lo.x, i), mini(lo.y, j))
				hi = Vector2i(maxi(hi.x, i), maxi(hi.y, j))
	lo -= Vector2i(2, 2)
	hi += Vector2i(2, 2)
	var w: int = hi.x - lo.x + 1
	var h: int = hi.y - lo.y + 1
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	var wet: int = 0
	for j: int in range(h):
		for i: int in range(w):
			var p: Vector2 = _world_xz(lo.x + i, lo.y + j)
			var ground: float = _terrain.data.get_height(Vector3(p.x, 0.0, p.y))
			var depth: float = 0.0 if is_nan(ground) else water - ground
			var dm: int = clampi(roundi(depth * 10.0), 0, 255)
			# The dock stands over water, and the terrain cannot know it is there: without this a
			# float could "land" on the planks and the server would call it wet.
			if _over_dock(p, 0.6):
				dm = 0
			bytes[j * w + i] = dm
			if dm > 0:
				wet += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_JSON.get_base_dir()))
	var f: FileAccess = FileAccess.open(BAKE_DEPTH, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()

	var origin: Vector2 = _world_xz(lo.x, lo.y)
	var spots: Array[Dictionary] = []
	var ordered: Array[Array] = LakesideShape.SPOTS.duplicate()
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return float(a[3]) < float(b[3]))
	for s: Array in ordered:
		var c: Vector2 = s[2]
		spots.append({"id": s[0], "name": s[1], "x": c.x, "z": c.y, "radius": s[3]})
	var bake: Dictionary = {
		"_comment": "GENERATED by tools/world/build_lakeside.gd. The server compiles this in (build.rs); LakesideLevel reads it. Do not edit: change the generator and re-run it.",
		"level": "lakeside",
		"id": 1,
		"scene": "res://game/world/lakeside.tscn",
		"water_y": water,
		"spawn": [SPAWN.x, SPAWN.y, SPAWN.z],
		"wade_depth": WADE_DEPTH,
		"min_cast_depth": MIN_CAST_DEPTH,
		"depth_grid": {
			"file": BAKE_DEPTH.get_file(),
			"origin_x": origin.x,
			"origin_z": origin.y,
			"spacing": 1.0,
			"width": w,
			"height": h,
			"unit": "decimetres of water, 0 = dry",
		},
		"spots": spots,
	}
	var jf: FileAccess = FileAccess.open(BAKE_JSON, FileAccess.WRITE)
	jf.store_string(JSON.stringify(bake, "  ", false) + "\n")
	jf.close()
	print("build_lakeside: bake %dx%d depth grid at (%.0f, %.0f), %d wet cells" % [w, h, origin.x, origin.y, wet])


# =============================================================================================
# OUTPUT
# =============================================================================================

func _save_scene() -> void:
	_root.set_script(load(LEVEL_SCRIPT))
	var packed := PackedScene.new()
	var err: int = packed.pack(_root)
	if err != OK:
		push_error("build_lakeside: pack failed (%s)" % error_string(err))
		return
	err = ResourceSaver.save(packed, SCENE_PATH)
	if err != OK:
		push_error("build_lakeside: could not save %s (%s)" % [SCENE_PATH, error_string(err)])
		return
	print("build_lakeside: wrote %s" % SCENE_PATH)


## A top-down picture of what was generated, for checking the layout by eye: height shading,
## water, paths, the keep-clear circles, colliders and spots.
func _write_map(path: String) -> void:
	var n: int = LakesideShape.SIZE
	var img: Image = Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for j: int in range(n):
		for i: int in range(n):
			var h: float = _heights[j * n + i]
			var c: Color
			if h < LakesideShape.WATER - WADE_DEPTH:
				c = Color(0.1, 0.25, 0.45).darkened(clampf(-h / 16.0, 0.0, 0.7))
			elif h < LakesideShape.WATER:
				c = Color(0.35, 0.6, 0.7)
			else:
				c = Color(0.35, 0.55, 0.25).lerp(Color(0.7, 0.68, 0.6), clampf(h / 40.0, 0.0, 1.0))
				var p: Vector2 = _world_xz(i, j)
				if _shape.path_weight(p.x, p.y) > 0.5:
					c = Color(0.6, 0.45, 0.3)
			img.set_pixel(i, j, c)
	for s: Array in _solids:
		var p3: Vector3 = s[0]
		_dot(img, Vector2(p3.x, p3.z), maxf(1.0, float(s[1])), Color(0.1, 0.3, 0.1))
	for c2: Array in _keep_clear:
		_ring(img, c2[0] as Vector2, float(c2[1]), Color(1.0, 0.9, 0.2))
	for s2: Array in LakesideShape.SPOTS:
		_ring(img, s2[2] as Vector2, float(s2[3]), Color(1.0, 0.3, 0.3))
	_dot(img, Vector2(SPAWN.x, SPAWN.z), 2.0, Color(1, 1, 1))
	img.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("build_lakeside: map written to %s" % path)


static func _dot(img: Image, p: Vector2, r: float, c: Color) -> void:
	var cx: int = roundi(p.x + LakesideShape.HALF)
	var cy: int = roundi(p.y + LakesideShape.HALF)
	var ri: int = ceili(r)
	for y: int in range(cy - ri, cy + ri + 1):
		for x: int in range(cx - ri, cx + ri + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


static func _ring(img: Image, p: Vector2, r: float, c: Color) -> void:
	for k: int in range(96):
		var a: float = TAU * float(k) / 96.0
		_dot(img, p + Vector2(cos(a), sin(a)) * r, 0.0, c)


# =============================================================================================
# HELPERS
# =============================================================================================

func _own(node: Node) -> void:
	node.owner = _root


static func _unique_name(parent: Node, base: String) -> String:
	var candidate: String = base
	var k: int = 2
	while parent.has_node(NodePath(candidate)):
		candidate = "%s%d" % [base, k]
		k += 1
	return candidate


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var here: Transform3D = xf
	var n3: Node3D = n as Node3D
	if n3 != null:
		here = xf * n3.transform
	var box := AABB()
	var have: bool = false
	var vi: VisualInstance3D = n as VisualInstance3D
	if vi != null:
		box = here * vi.get_aabb()
		have = true
	for c: Node in n.get_children():
		var cb: AABB = _aabb(c, here)
		if cb.size != Vector3.ZERO:
			box = cb if not have else box.merge(cb)
			have = true
	return box
