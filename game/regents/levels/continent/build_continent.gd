extends Node3D
## GENERATES THE CONTINENT (Luke, 2026-10-24: the main continent of his map, ~3 km, the camp in the
## centre-west lowlands; a greybox to test the ring and streaming in a world bigger than the glade).
## Writes `continent.tscn` beside this file and everything it loads, then bakes it:
##
##   terrain/data/                   Terrain3D regions (heights, texture control, colour)
##   terrain/continent_assets.tres   the ground's textures (terrain/textures/: generated noise, tinted)
##   continent.tscn                  the level: LevelInfo (level 21, streamed), its Cells, the sea, the wall
##   continent_cells/                one scene per 64 m cell (the bake's cut, for players' games)
##   shared/world/continent.json     what the SERVER knows (spawn, the sea's depth grid, every point)
##
##   godot --headless --path . res://game/regents/levels/continent/build_continent.tscn
##   godot --headless --path . --import        # the first time, for the new resources
##   tools\publish.cmd                          # the server takes the bake
##
## A scene rather than a `-s` script: Terrain3D must be inside a running tree to import.
##
## RE-RUNNING OVERWRITES. The level is code: a hand edit to `continent.tscn` or a Terrain3D brush stroke is
## lost the next time this runs. The shape is `continent_shape.gd` (and the map); the camp is the frontier
## glade's (`frontier.tscn`: its nodes, stations, dummies, foes and decor, copied in at the origin); the
## rest is a TEST placement (nodes, skeleton camps, decor), seeded, for bots and the ring to have
## something to visit. Luke's own placement replaces it.

const FRONTIER: String = "res://game/regents/levels/frontier.tscn"
const NATURE: String = "res://game/regents/art/nature/"
const SOLID_PROPS: String = "res://game/regents/levels/solid_props.gd"

## WHICH WORLD (PROGRESS step 25): "continent" (level 21, the map at Luke's ~3 km) or "expanse" (level 22, the
## same map at Skyrim's size, ~37 km2 of land, for the load test's 300 players spread over a world:
## `build_expanse.tscn`). Everything else below is the same code; the continent's settings are the defaults,
## so the continent comes out as it always has.
@export var world: String = "continent"

## Where it is written: the folder, its scene, the terrain's data, assets and textures.
var _dir: String = "res://game/regents/levels/continent/"
var _scene_path: String = _dir + "continent.tscn"
var _data_dir: String = _dir + "terrain/data"
var _assets_path: String = _dir + "terrain/continent_assets.tres"
var _textures_dir: String = _dir + "terrain/textures/"
## The level's number and name.
var _level_id: int = 21
var _level_name: String = "continent"
## Metres between the terrain's vertices (the server needs none of it: it is the client's and referee's).
var _spacing: float = 2.0
## The landmass's widest side, and how much taller its hills and mountains are (ContinentShape).
var _width_m: float = ContinentShape.WIDTH_M
var _relief: float = 1.0
## The share of the decor kept (the expanse thins it: its cells are many).
var _decor_share: float = 1.0
## The bake also writes the ground's height (LevelInfo.bake_ground: the load test's bots walk on it).
var _bake_ground: bool = false
## Terrain3D's region, vertices a side (its default).
const REGION_VERTS: float = 256.0
## Metres between the server's depth samples (the bake's grid; 4 is its coarsest).
const BAKE_SPACING: float = 4.0
## Sea round the landmass that the terrain still covers, m.
const MARGIN_M: float = 200.0
const WADE_DEPTH: float = 0.7
## The camp's own ground: nothing scattered this close to the origin.
const CAMP_CLEAR_M: float = 220.0
## The test placement: skeleton camps, how far apart, and how far from the start.
var _camp_count: int = 16
const SKELETON_SPACING_M: float = 320.0
const SKELETON_FROM_START_M: float = 350.0
## Harvest zones on the world map: at least this many nodes of a kind in a square this wide.
const ZONE_M: float = 384.0
const ZONE_MIN: int = 4

enum Tex { GRASS, ROCK, SAND }
const TEXTURE_NAMES: Array[String] = ["grass", "rock", "sand"]
const TEXTURE_COLOR: Array[Color] = [Color(0.42, 0.6, 0.27), Color(0.55, 0.53, 0.5), Color(0.82, 0.76, 0.56)]

var _shape: ContinentShape = null
var _rng := RandomNumberGenerator.new()
var _root: Node3D = null
var _info: LevelInfo = null
var _cells: Node3D = null
var _terrain: Terrain3D = null
## The terrain's grid: its north-west corner (world), size in vertices, heights.
var _origin: Vector2 = Vector2.ZERO
var _w: int = 0
var _h: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
## Every point placed, for unique ids and the summary.
var _counts: Dictionary[String, int] = {}
## The glade's node points' radii, by tag (a tree's, a rock's), so the scattered ones match.
var _radius_by_tag: Dictionary[String, float] = {}


func _ready() -> void:
	await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	_rng.seed = 0xC0417E17
	if not _configure():
		AppExit.quit(get_tree(), 1)
		return
	_shape = ContinentShape.new(_width_m, _relief)
	_root = Node3D.new()
	_root.name = "Continent"
	add_child(_root)
	_make_info()
	_sample_heights()
	print("build_continent: heights %dx%d (%d ms)" % [_w, _h, Time.get_ticks_msec() - t0])
	_make_terrain()
	print("build_continent: terrain imported (%d ms)" % (Time.get_ticks_msec() - t0))
	_make_sea()
	_make_barrier()
	_make_camp()
	_scatter()
	_make_environment()
	_save_terrain()
	if not _save_scene():
		AppExit.quit(get_tree(), 1)
		return
	print("build_continent: scene written (%d ms): %s" % [Time.get_ticks_msec() - t0, str(_counts)])
	var ok: bool = await _bake()
	print("build_continent: done in %d ms" % (Time.get_ticks_msec() - t0))
	AppExit.quit(get_tree(), 0 if ok else 1)


## The settings of `world`: the continent's are the defaults above.
func _configure() -> bool:
	match world:
		"continent":
			return true
		"expanse":
			# Skyrim's land is about 37 km2; the continent's is 2.7 at 3 km across: 3.7 times as wide.
			_dir = "res://game/regents/levels/expanse/"
			_scene_path = _dir + "expanse.tscn"
			_data_dir = _dir + "terrain/data"
			_assets_path = _dir + "terrain/expanse_assets.tres"
			_textures_dir = _dir + "terrain/textures/"
			_level_id = 22
			_level_name = "expanse"
			_spacing = 4.0
			_width_m = ContinentShape.WIDTH_M * 3.7
			_relief = 2.0
			_decor_share = 0.4
			_bake_ground = true
			# The continent's camps to its land, 16 to 2.7 km2: about 220 on 37.
			_camp_count = 220
			return true
	push_error("build_continent: no world '%s' (continent, expanse)" % world)
	return false


# =============================================================================================
# THE LEVEL
# =============================================================================================

func _make_info() -> void:
	_info = LevelInfo.new()
	_info.name = "LevelInfo"
	_info.level_name = _level_name
	_info.level_id = _level_id
	_info.water_y = ContinentShape.SEA_Y
	_info.wade_depth = WADE_DEPTH
	_info.grid_spacing = BAKE_SPACING
	_info.bake_ground = _bake_ground
	var ext: Rect2 = _shape.extent.grow(MARGIN_M * 0.75)
	_info.bake_bounds = AABB(Vector3(ext.position.x, -40.0, ext.position.y), Vector3(ext.size.x, 260.0, ext.size.y))
	_info.streamed = true
	_root.add_child(_info)
	_own(_info)
	_cells = Node3D.new()
	_cells.name = String(LevelCells.CELLS_NODE)
	_info.add_child(_cells)
	_own(_cells)
	var world := Node3D.new()
	world.name = "WorldRoot"
	_root.add_child(world)
	_own(world)
	var spawn := LevelSpawn.new()
	spawn.name = "Spawn"
	spawn.position = Vector3(0.0, 0.0, 8.0)
	_root.add_child(spawn)
	_own(spawn)


func _sample_heights() -> void:
	var ext: Rect2 = _shape.extent.grow(MARGIN_M)
	# Terrain3D puts an import's corner on its region grid (`REGION_VERTS` vertices a side): one that is not
	# on it lands the whole terrain up to a region away (found 2026-10-24: 248 m and 346 m off).
	var region_m: float = REGION_VERTS * _spacing
	_origin = (ext.position / region_m).floor() * region_m
	_w = int(ceil((ext.end.x - _origin.x) / _spacing)) + 1
	_h = int(ceil((ext.end.y - _origin.y) / _spacing)) + 1
	_heights.resize(_w * _h)
	for j: int in range(_h):
		for i: int in range(_w):
			var p: Vector2 = _xz(i, j)
			_heights[j * _w + i] = _shape.height(p.x, p.y)


## World XZ of terrain vertex (i, j).
func _xz(i: int, j: int) -> Vector2:
	return _origin + Vector2(float(i), float(j)) * _spacing


## The terrain's height at (x, z) (nearest vertex), and its slope (rise over run).
func _ground(x: float, z: float) -> float:
	var i: int = clampi(roundi((x - _origin.x) / _spacing), 0, _w - 1)
	var j: int = clampi(roundi((z - _origin.y) / _spacing), 0, _h - 1)
	return _heights[j * _w + i]


func _slope(x: float, z: float) -> float:
	var dx: float = (_ground(x + _spacing, z) - _ground(x - _spacing, z)) / (2.0 * _spacing)
	var dz: float = (_ground(x, z + _spacing) - _ground(x, z - _spacing)) / (2.0 * _spacing)
	return Vector2(dx, dz).length()


func _make_terrain() -> void:
	var t := Terrain3D.new()
	t.name = "Terrain3D"
	_root.add_child(t, true)
	_own(t)
	_terrain = t
	# Old regions would load underneath the new ones: start from an empty directory.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_data_dir))
	var d: DirAccess = DirAccess.open(_data_dir)
	for f: String in d.get_files():
		if f.begins_with("terrain3d") and f.ends_with(".res"):
			d.remove(f)
	t.data_directory = _data_dir
	t.vertex_spacing = _spacing
	t.mesh_lods = 7
	t.mesh_size = 48
	# The referee walks foes everywhere: the whole terrain is solid, not only round a camera.
	t.collision_mode = Terrain3DCollision.FULL_GAME
	t.collision_layer = SpaceTimeEntity.WORLD_MASK
	t.collision_mask = 0
	var mat: Terrain3DMaterial = t.material
	mat.world_background = Terrain3DMaterial.NONE
	mat.auto_shader = false
	mat.texture_filtering = Terrain3DMaterial.LINEAR
	var assets := Terrain3DAssets.new()
	for id: int in range(TEXTURE_NAMES.size()):
		var ta := Terrain3DTextureAsset.new()
		ta.name = TEXTURE_NAMES[id]
		ta.albedo_texture = _saved(_noise_texture(900 + id, false), "%s_albedo" % TEXTURE_NAMES[id])
		ta.normal_texture = _saved(_noise_texture(950 + id, true), "%s_normal" % TEXTURE_NAMES[id])
		ta.albedo_color = TEXTURE_COLOR[id]
		ta.uv_scale = 0.12
		ta.detiling_rotation = 0.15
		assets.set_texture(id, ta)
	t.assets = assets
	var height_img: Image = Image.create_empty(_w, _h, false, Image.FORMAT_RF)
	var control_img: Image = Image.create_empty(_w, _h, false, Image.FORMAT_RF)
	var color_img: Image = Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	var tint := FastNoiseLite.new()
	tint.seed = 4061
	tint.frequency = 1.0 / 90.0
	for j: int in range(_h):
		for i: int in range(_w):
			var p: Vector2 = _xz(i, j)
			var h: float = _heights[j * _w + i]
			height_img.set_pixel(i, j, Color(h, 0.0, 0.0, 1.0))
			var tex: int = _paint(p.x, p.y, h)
			var bits: int = Terrain3DUtil.enc_base(tex) | Terrain3DUtil.enc_overlay(tex) | Terrain3DUtil.enc_blend(0)
			control_img.set_pixel(i, j, Color(Terrain3DUtil.as_float(bits), 0.0, 0.0, 1.0))
			var v: float = 0.88 + 0.12 * tint.get_noise_2d(p.x, p.y)
			color_img.set_pixel(i, j, Color(v, v, v, 1.0))
	t.data.import_images([height_img, control_img, color_img], Vector3(_origin.x, 0.0, _origin.y), 0.0, 1.0)


## Which ground (x, z) is: sand by the sea, rock on the mountains and the steep, grass elsewhere.
func _paint(x: float, z: float, h: float) -> int:
	if _shape.coast_distance(x, z) < 22.0 or h < ContinentShape.SEA_Y + 1.6:
		return Tex.SAND
	if _shape.mountain(x, z) > 0.35 or _slope(x, z) > 0.85:
		return Tex.ROCK
	return Tex.GRASS


## A plain tileable noise picture (the ground's grain; its colour comes from the texture asset), or a flat
## normal map with a little of the grain in it. Every texture the same size and format, with mipmaps.
static func _noise_texture(seed_value: int, normal: bool) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.03
	n.fractal_octaves = 3
	var size: int = 256
	# Tileable: Godot's seamless image of the noise (greyscale), turned into the ground's grain.
	var grain: Image = n.get_seamless_image(size, size)
	grain.convert(Image.FORMAT_L8)
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var v: float = grain.get_pixel(x, y).r
			if normal:
				var tilt: float = (v - 0.5) * 0.25
				img.set_pixel(x, y, Color(0.5 + tilt, 0.5 - tilt, 1.0, 0.85))
			else:
				var g: float = 0.78 + 0.22 * v
				img.set_pixel(x, y, Color(g, g, g, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## `tex` saved as a file of its own (Terrain3D wants its textures in files, and the asset list stays small),
## and loaded back from it.
func _saved(tex: ImageTexture, file: String) -> Texture2D:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_textures_dir))
	var path: String = _textures_dir + file + ".res"
	var err: int = ResourceSaver.save(tex, path)
	if err != OK:
		push_error("build_continent: could not save %s (%s)" % [path, error_string(err)])
		return tex
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D


## The sea: one plane at its surface, out past the terrain's edge.
func _make_sea() -> void:
	var mesh := PlaneMesh.new()
	var ext: Rect2 = _shape.extent.grow(MARGIN_M * 6.0)
	mesh.size = ext.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.34, 0.48, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.1
	mesh.material = mat
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = mesh
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(ext.get_center().x, ContinentShape.SEA_Y, ext.get_center().y)
	_root.add_child(sea)
	_own(sea)


## The wading edge: an invisible wall along the depth a player may wade to (`WADE_DEPTH`), so the
## sea stops them where the server's bake says the ground is no longer standable.
func _make_barrier() -> void:
	var body := StaticBody3D.new()
	body.name = "Barrier"
	body.collision_layer = SpaceTimeEntity.BARRIER_MASK
	body.collision_mask = 0
	_root.add_child(body)
	_own(body)
	var faces := PackedVector3Array()
	var level: float = ContinentShape.SEA_Y - WADE_DEPTH
	var bottom: float = ContinentShape.SEA_Y - 30.0
	var top: float = ContinentShape.SEA_Y + 4.0
	for j: int in range(_h - 1):
		for i: int in range(_w - 1):
			var vals: Array[float] = [_heights[j * _w + i] - level, _heights[j * _w + i + 1] - level,
				_heights[(j + 1) * _w + i + 1] - level, _heights[(j + 1) * _w + i] - level]
			if (vals[0] < 0.0) == (vals[1] < 0.0) and (vals[1] < 0.0) == (vals[2] < 0.0) and (vals[2] < 0.0) == (vals[3] < 0.0):
				continue
			var corners: Array[Vector2] = [_xz(i, j), _xz(i + 1, j), _xz(i + 1, j + 1), _xz(i, j + 1)]
			var pts: Array[Vector2] = []
			for e: int in range(4):
				var v0: float = vals[e]
				var v1: float = vals[(e + 1) % 4]
				if (v0 < 0.0) != (v1 < 0.0):
					pts.append(corners[e].lerp(corners[(e + 1) % 4], v0 / (v0 - v1)))
			var k: int = 0
			while k + 1 < pts.size():
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[k + 1]
				faces.append_array([Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(b.x, top, b.y),
					Vector3(a.x, bottom, a.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y)])
				k += 2
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "WadingEdge"
	cs.shape = shape
	body.add_child(cs)
	_own(cs)
	print("build_continent: the wading edge, %d triangles" % (faces.size() / 3))


# =============================================================================================
# WHAT FILLS IT
# =============================================================================================

## The frontier glade's camp, at the origin: its nodes, stations, dummies, foes and decor, as they are there.
func _make_camp() -> void:
	var glade: Node3D = (load(FRONTIER) as PackedScene).instantiate() as Node3D
	for group: String in ["Nodes", "Stations", "Dummies", "Foes", "Decor", "Places"]:
		var holder: Node = glade.get_node_or_null(group)
		if holder == null:
			push_error("build_continent: the frontier has no %s" % group)
			continue
		for child: Node in holder.get_children():
			var n3: Node3D = child as Node3D
			if n3 == null:
				continue
			var lp: LevelPoint = n3 as LevelPoint
			if lp != null and lp.kind == "node" and not lp.tags.is_empty():
				_radius_by_tag[lp.tags[0]] = lp.radius
			var xf: Transform3D = n3.transform
			n3.owner = null
			holder.remove_child(n3)
			_cells.add_child(n3)
			n3.transform = xf
			_own_tree(n3)
			_count("camp")
	glade.free()


## The TEST placement, cell by cell over the land: forests (trees, oaks, yews), rocks by the hills and the
## mountains (copper, iron, coal: the farther from the start, the better), a few on the plains, the decor;
## then the skeleton camps.
func _scatter() -> void:
	var forest := FastNoiseLite.new()
	forest.seed = 4031
	forest.frequency = 1.0 / 380.0
	var cell: float = 64.0
	var ext: Rect2 = _shape.extent
	var x: float = floor(ext.position.x / cell) * cell
	while x < ext.end.x:
		var z: float = floor(ext.position.y / cell) * cell
		while z < ext.end.y:
			_scatter_cell(Rect2(x, z, cell, cell), forest)
			z += cell
		x += cell
	_skeleton_camps()
	_harvest_zones()


func _scatter_cell(r: Rect2, forest: FastNoiseLite) -> void:
	var c: Vector2 = r.get_center()
	if _shape.coast_distance(c.x, c.y) < 30.0 or c.length() < CAMP_CLEAR_M:
		return
	var far: float = c.length()
	var mtn: float = _shape.mountain(c.x, c.y)
	var h: float = _ground(c.x, c.y)
	var wood: bool = forest.get_noise_2d(c.x, c.y) > 0.1 and mtn < 0.05
	var rocky: bool = mtn > 0.02 or h > ContinentShape.SEA_Y + 20.0
	if wood:
		for _k: int in range(_rng.randi_range(2, 3)):
			var roll: float = _rng.randf()
			var tag: String = "Tree"
			if roll < 0.12 and far > 800.0:
				tag = "Yew"
			elif roll < 0.4 and far > 300.0:
				tag = "Oak"
			_node_point(r, tag)
	elif rocky:
		for _k: int in range(_rng.randi_range(1, 2)):
			var roll: float = _rng.randf()
			var tag: String = "Copper rock"
			if (roll < 0.2 and far > 800.0) or (mtn > 0.2 and roll < 0.45):
				tag = "Coal rock"
			elif roll < 0.55 and far > 400.0:
				tag = "Iron rock"
			_node_point(r, tag)
	else:
		var roll: float = _rng.randf()
		if roll < 0.3:
			_node_point(r, "Tree")
		elif roll < 0.42:
			_node_point(r, "Copper rock")
	# Decor: a little of what the glade has, so a cell is not bare.
	if mtn < 0.3:
		var models: Array[String] = ["Bush_Large", "Bush_Long_1", "Rock_Medium_1", "Rock_Big_1", "Grass_Common_Tall", "Fern_1"]
		for _k: int in range(_rng.randi_range(1, 3)):
			if _decor_share < 1.0 and _rng.randf() > _decor_share:
				continue
			var p: Vector2 = _free_spot(r, 2.0)
			if p.x == INF:
				continue
			var model: String = models[_rng.randi() % models.size()]
			var inst: Node3D = (load(NATURE + model + ".gltf") as PackedScene).instantiate() as Node3D
			inst.name = "%s_%d" % [model.to_lower(), _count("decor")]
			var s: float = _rng.randf_range(0.7, 1.5)
			inst.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, _ground(p.x, p.y), p.y))
			_cells.add_child(inst)
			_own(inst)


## A gathering node of `tag` somewhere in `r` that is dry, inland and not steep.
func _node_point(r: Rect2, tag: String) -> void:
	var p: Vector2 = _free_spot(r, 4.0)
	if p.x == INF:
		return
	var kind_key: String = tag.to_lower().replace(" ", "_")
	var lp := LevelPoint.new()
	lp.point_id = "w_%s_%d" % [kind_key, _count(kind_key)]
	lp.name = lp.point_id
	lp.kind = "node"
	lp.radius = _radius_by_tag.get(tag, 0.6)
	lp.tags = PackedStringArray([tag])
	lp.position = Vector3(p.x, _ground(p.x, p.y), p.y)
	_cells.add_child(lp)
	_own(lp)


## A random spot in `r` with room (`margin` from its edges) on dry, gentle ground; (INF, INF) if none.
func _free_spot(r: Rect2, margin: float) -> Vector2:
	for attempt: int in range(8):
		var p := Vector2(_rng.randf_range(r.position.x + margin, r.end.x - margin), _rng.randf_range(r.position.y + margin, r.end.y - margin))
		if _shape.coast_distance(p.x, p.y) > 15.0 and _slope(p.x, p.y) < 0.6 and p.length() > CAMP_CLEAR_M:
			return p
	return Vector2(INF, INF)


## Skeleton camps of three (two warriors, an axeman) on open ground, spread out, none near the start.
func _skeleton_camps() -> void:
	var placed: Array[Vector2] = []
	var ext: Rect2 = _shape.extent
	var tries: int = 0
	while placed.size() < _camp_count and tries < maxi(4000, _camp_count * 250):
		tries += 1
		var p := Vector2(_rng.randf_range(ext.position.x, ext.end.x), _rng.randf_range(ext.position.y, ext.end.y))
		if p.length() < SKELETON_FROM_START_M or _shape.coast_distance(p.x, p.y) < 60.0 or _shape.mountain(p.x, p.y) > 0.05:
			continue
		if _slope(p.x, p.y) > 0.35 or placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < SKELETON_SPACING_M):
			continue
		placed.append(p)
		var n: int = placed.size()
		var offsets: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(3.0, 3.5), Vector2(4.0, -3.5)]
		var kinds: Array[String] = ["skeleton_warrior", "skeleton_axeman", "skeleton_warrior"]
		for k: int in range(3):
			var q: Vector2 = p + offsets[k]
			var lp := LevelPoint.new()
			lp.point_id = "w_skeleton_%d_%d" % [n, k + 1]
			lp.name = lp.point_id
			lp.kind = kinds[k]
			lp.radius = 0.5
			lp.position = Vector3(q.x, _ground(q.x, q.y), q.y)
			_cells.add_child(lp)
			_own(lp)
			_count("skeleton")
		_poi("w_poi_skeletons_%d" % n, p, "Skeleton camp")
	print("build_continent: %d skeleton camps" % placed.size())


## POINTS OF INTEREST for the world map (Luke, 2026-10-26): a zone of each kind of rock or wood where at
## least `ZONE_MIN` of its nodes stand in one `ZONE_M` square, named at their middle. No random draws: the
## placement before it is unchanged.
func _harvest_zones() -> void:
	var names: Dictionary[String, String] = {"Copper rock": "Copper mining zone", "Iron rock": "Iron mining zone",
		"Coal rock": "Coal mining zone", "Oak": "Oak woodcutting zone", "Yew": "Yew woodcutting zone"}
	var sums: Dictionary = {}   # "tag|bx|bz" -> [sum, count]
	for child: Node in _cells.get_children():
		var lp: LevelPoint = child as LevelPoint
		if lp == null or lp.kind != "node" or lp.tags.is_empty() or not names.has(lp.tags[0]) or lp.point_id.begins_with("tree_"):
			continue
		var key: String = "%s|%d|%d" % [lp.tags[0], floori(lp.position.x / ZONE_M), floori(lp.position.z / ZONE_M)]
		var acc: Array = sums.get(key, [Vector2.ZERO, 0])
		sums[key] = [(acc[0] as Vector2) + Vector2(lp.position.x, lp.position.z), int(acc[1]) + 1]
	var keys: Array = sums.keys()
	keys.sort()
	var made: int = 0
	for key: String in keys:
		var acc: Array = sums[key]
		if int(acc[1]) < ZONE_MIN:
			continue
		var tag: String = key.split("|")[0]
		made += 1
		_poi("w_poi_zone_%d" % made, (acc[0] as Vector2) / float(acc[1]), names[tag])
	print("build_continent: %d harvest zones" % made)


func _poi(id: String, at: Vector2, label: String) -> void:
	var lp := LevelPoint.new()
	lp.point_id = id
	lp.name = id
	lp.kind = "poi"
	lp.radius = 10.0
	lp.tags = PackedStringArray([label])
	lp.position = Vector3(at.x, _ground(at.x, at.y), at.y)
	_cells.add_child(lp)
	_own(lp)


func _make_environment() -> void:
	var glade: Node3D = (load(FRONTIER) as PackedScene).instantiate() as Node3D
	var env_node: WorldEnvironment = glade.get_node("WorldEnvironment") as WorldEnvironment
	var env: Environment = env_node.environment.duplicate(true) as Environment
	# Farther to see across a continent: the glade's fog closed it in at a hundred metres.
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_root.add_child(we)
	_own(we)
	var glade_sun: DirectionalLight3D = glade.get_node("Sun") as DirectionalLight3D
	var sun: DirectionalLight3D = glade_sun.duplicate() as DirectionalLight3D
	sun.directional_shadow_max_distance = 140.0
	_root.add_child(sun)
	_own(sun)
	glade.free()
	var cam := Camera3D.new()
	cam.name = "OverviewCamera"
	cam.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-25.0)), Vector3(0.0, 40.0, 90.0))
	_root.add_child(cam)
	_own(cam)
	# The decor's rocks and bushes block, as in the glade (and each cell's as it streams in).
	var solid := Node.new()
	solid.name = "SolidProps"
	solid.set_script(load(SOLID_PROPS))
	solid.set(&"props", NodePath("../LevelInfo/Cells"))
	_root.add_child(solid)
	_own(solid)


# =============================================================================================
# OUTPUT
# =============================================================================================

func _save_terrain() -> void:
	var err: int = ResourceSaver.save(_terrain.assets, _assets_path)
	if err != OK:
		push_error("build_continent: could not save %s (%s)" % [_assets_path, error_string(err)])
	_terrain.assets = load(_assets_path) as Terrain3DAssets
	_terrain.data.save_directory(_data_dir)


func _save_scene() -> bool:
	var packed := PackedScene.new()
	var err: int = packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, _scene_path)
	if err != OK:
		push_error("build_continent: could not save %s (%s)" % [_scene_path, error_string(err)])
		return false
	return true


## Bake what was written: the saved scene loaded into the tree (its terrain solid), as the server will
## know it, and cut into cells for players' games.
func _bake() -> bool:
	_root.queue_free()
	await get_tree().process_frame
	var level: Node3D = (ResourceLoader.load(_scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	level.scene_file_path = _scene_path
	add_child(level)
	for _k: int in range(10):
		await get_tree().physics_frame
	var r: Dictionary = LevelBaker.bake(level)
	if not bool(r["ok"]):
		push_error("build_continent: the bake: %s" % r["error"])
		return false
	print("build_continent: baked %s: %dx%d grid, %d wet, %d points, %d cells" % [r["json"], r["width"], r["height"], r["wet"],
		(r["doc"]["points"] as Array).size(), (r["cells"] as Dictionary).size()])
	return true


# =============================================================================================
# HELPERS
# =============================================================================================

func _own(n: Node) -> void:
	n.owner = _root


## `n` and what was its own scene's (a marker's children), owned by the level; an instanced model's
## insides stay its model's.
func _own_tree(n: Node) -> void:
	n.owner = _root
	if not n.scene_file_path.is_empty():
		return
	for c: Node in n.get_children():
		_own_tree(c)


func _count(what: String) -> int:
	_counts[what] = _counts.get(what, 0) + 1
	return _counts[what]
