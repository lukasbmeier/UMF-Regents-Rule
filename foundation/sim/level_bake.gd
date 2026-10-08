class_name LevelBake extends RefCounted
## A level's geography as the SERVER knows it: where players appear, how deep the water is at
## any point, which named spots it holds. Read from `res://shared/world/<level>.json` and the
## depth grid beside it — the same two files `server/build.rs` compiles into the module.
##
## PARITY. The Rust twin is `server/src/level.rs`, and both must give the same answer for every
## point (`shared/golden/level/<level>_probes.json`; `cargo test --test level` and the headless
## runner both check it). A float the aim ring shows landing in the water has to be a float the
## server accepts, so the client asks THIS, not the terrain: the terrain interpolates between
## samples and the module cannot. Nearest cell, in f64 (GDScript's float — the Rust side widens
## its f32 input to match), and "is this water" compares whole decimetres, so nothing depends
## on a tolerance.
##
## A level's bake is written from its SCENE (`LevelInfo`, `tools/world/bake_level.gd`, DECISIONS
## #175), or by its generator (the lakeside: `tools/world/build_lakeside.gd`).

const DIR: String = "res://shared/world/"

var level: String = ""
## Its number: what a world's `world_level` row says it runs (0 is none).
var id: int = 0
## The client scene that shows it ("" when the bake does not say).
var scene: String = ""
## What else the designer marked (`LevelPoint`): {id, kind, x, y, z, radius, tags}.
var points: Array[Dictionary] = []
var water_y: float = 0.0
var spawn: Vector3 = Vector3.ZERO
var wade_depth: float = 0.0
## A float needs at least this much water under it, in decimetres.
var min_cast_dm: int = 0
var origin_x: float = 0.0
var origin_z: float = 0.0
var spacing: float = 1.0
var width: int = 0
var height: int = 0
## Smallest first; the first spot containing a point is the most specific.
var spots: Array[Dictionary] = []

var _depth: PackedByteArray = PackedByteArray()


## The bake for `level`, or null (with an error) if it is missing or malformed.
static func load_level(level_name: String) -> LevelBake:
	var path: String = DIR + level_name + ".json"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LevelBake: %s is missing" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("LevelBake: %s is not a JSON object" % path)
		return null
	var d: Dictionary = parsed as Dictionary
	var b := LevelBake.new()
	b.level = str(d.get("level", level_name))
	b.id = int(d.get("id", 0))
	b.scene = str(d.get("scene", ""))
	for p: Variant in d.get("points", []):
		b.points.append(p as Dictionary)
	b.water_y = float(d.get("water_y", 0.0))
	var s: Array = d.get("spawn", [0.0, 0.0, 0.0]) as Array
	b.spawn = Vector3(float(s[0]), float(s[1]), float(s[2]))
	b.wade_depth = float(d.get("wade_depth", 0.0))
	b.min_cast_dm = roundi(float(d.get("min_cast_depth", 0.0)) * 10.0)
	var g: Dictionary = d.get("depth_grid", {}) as Dictionary
	b.origin_x = float(g.get("origin_x", 0.0))
	b.origin_z = float(g.get("origin_z", 0.0))
	b.spacing = float(g.get("spacing", 1.0))
	b.width = int(g.get("width", 0))
	b.height = int(g.get("height", 0))
	var bin_path: String = DIR + str(g.get("file", ""))
	b._depth = FileAccess.get_file_as_bytes(bin_path)
	if b._depth.size() != b.width * b.height:
		push_error("LevelBake: %s is %d bytes, its header says %dx%d" % [bin_path, b._depth.size(), b.width, b.height])
		return null
	for spot: Variant in d.get("spots", []):
		b.spots.append(spot as Dictionary)
	return b


## Every level baked into `shared/world/`, by name.
static func all_names() -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## The baked level with this number, or null (0, the greybox, has none).
static func by_id(level_id: int) -> LevelBake:
	if level_id <= 0:
		return null
	for n: String in all_names():
		var path: String = DIR + n + ".json"
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary 				and int((json.data as Dictionary).get("id", -1)) == level_id:
			return load_level(n)
	return null


## Every point of one kind, in the bake's order.
func points_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in points:
		if str(p.get("kind", "")) == kind:
			out.append(p)
	return out


## The grid cell whose centre is nearest (x, z), or (-1, -1) off the grid.
func cell(x: float, z: float) -> Vector2i:
	var i: float = floorf((x - origin_x) / spacing + 0.5)
	var j: float = floorf((z - origin_z) / spacing + 0.5)
	# A NaN fails every comparison, so it would sail through the range check below.
	if not is_finite(i) or not is_finite(j):
		return Vector2i(-1, -1)
	if i < 0.0 or j < 0.0 or i >= float(width) or j >= float(height):
		return Vector2i(-1, -1)
	return Vector2i(int(i), int(j))


## Water depth at a point in whole decimetres; 0 on land and off the grid.
func depth_dm_at(x: float, z: float) -> int:
	var c: Vector2i = cell(x, z)
	if c.x < 0:
		return 0
	return _depth[c.y * width + c.x]


## Water depth at a point in metres.
func depth_at(x: float, z: float) -> float:
	return float(depth_dm_at(x, z)) / 10.0


## Deep enough for a float.
func is_water(x: float, z: float) -> bool:
	return depth_dm_at(x, z) >= min_cast_dm


## Somewhere a player may stand (REVIEW 0.23.1 B2): land, water shallow enough to wade, a deck
## (the bake reads the dock's planks as dry), or off the grid. Deeper than `wade_depth` counts only
## when the point's cell AND its eight neighbours all are: the barrier follows the terrain, not
## this grid, so a player against it stands up to a cell from a cell that reads too deep. The
## module refuses a Tier A claim that leaves standable ground for anywhere this says no.
func can_stand(x: float, z: float) -> bool:
	var c: Vector2i = cell(x, z)
	if c.x < 0:
		return true
	var wade_dm: int = roundi(wade_depth * 10.0)
	for dj: int in range(-1, 2):
		for di: int in range(-1, 2):
			var i: int = c.x + di
			var j: int = c.y + dj
			if i < 0 or j < 0 or i >= width or j >= height or _depth[j * width + i] <= wade_dm:
				return true
	return false


## The named spot containing a point, or {} for open water.
func spot_at(x: float, z: float) -> Dictionary:
	for s: Dictionary in spots:
		var dx: float = x - float(s["x"])
		var dz: float = z - float(s["z"])
		var r: float = float(s["radius"])
		if dx * dx + dz * dz <= r * r:
			return s
	return {}
