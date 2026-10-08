class_name LevelBaker extends RefCounted
## A LEVEL SCENE, AS THE SERVER WILL KNOW IT (DECISIONS #175): the bake `LevelInfo` describes, read
## off the scene. The scene must be in a tree with its physics running (its collision registered):
## `tools/world/bake_level.gd` instances it and waits for that, and so do the tests.
##
## The format is the one the lakeside's generator writes (`server/build.rs`, `LevelBake`): a JSON
## header and a depth grid, one byte a cell, the water's depth in decimetres (0 dry, at most 25.5 m),
## row-major from the north-west corner, cropped to the wet cells and two cells round them.

## Ground the rays start above and give up below, beyond the bounds' own top and bottom.
const RAY_MARGIN: float = 50.0
## Cells kept round the wet ones.
const CROP_MARGIN: int = 2
## A whisker off the cell centre: a heightmap lets a ray exactly on a triangle edge slip through.
const RAY_NUDGE: float = 0.0031
## The level's own collision layer (`SpaceTimeEntity.WORLD_MASK`; written out, because the baker runs
## from a `-s` script, before the autoloads that entity script names exist).
const WORLD_MASK: int = 1


## The scene's LevelInfo, or null.
static func find_info(root: Node) -> LevelInfo:
	if root is LevelInfo:
		return root as LevelInfo
	for n: Node in root.find_children("*", "", true, false):
		if n is LevelInfo:
			return n as LevelInfo
	return null


## Bake `root` into `out_dir`. Returns {ok, error, doc, json, bin, wet, width, height}. `settings`
## stands in for a scene with no LevelInfo (the generated lakeside: its markers carry their facts
## as metadata): level_name, level_id, water_y, wade_depth, min_cast_depth, grid_spacing, bounds.
static func bake(root: Node3D, out_dir: String = "res://shared/world/", settings: Dictionary = {}) -> Dictionary:
	var info: LevelInfo = find_info(root)
	var s: Dictionary = settings.duplicate()
	if info != null:
		s = {"level_name": info.level_name, "level_id": info.level_id, "water_y": info.water_y,
			"wade_depth": info.wade_depth, "min_cast_depth": info.min_cast_depth,
			"grid_spacing": info.grid_spacing,
			"bounds": AABB(info.global_transform * info.bake_bounds.position, info.bake_bounds.size)}
	if str(s.get("level_name", "")).is_empty():
		return {"ok": false, "error": "no LevelInfo with a Level Name in %s" % root.name}
	var level_name: String = str(s["level_name"])
	var water: float = float(s.get("water_y", 0.0))
	var step: float = float(s.get("grid_spacing", 1.0))
	var bounds: AABB = s.get("bounds", AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80)))
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var cols: int = maxi(1, int(floor(bounds.size.x / step)) + 1)
	var rows: int = maxi(1, int(floor(bounds.size.z / step)) + 1)
	var top: float = bounds.end.y + RAY_MARGIN
	var bottom: float = bounds.position.y - RAY_MARGIN
	var full := PackedByteArray()
	full.resize(cols * rows)
	var lo := Vector2i(cols, rows)
	var hi := Vector2i(-1, -1)
	for j: int in range(rows):
		for i: int in range(cols):
			var x: float = bounds.position.x + i * step
			var z: float = bounds.position.z + j * step
			var q := PhysicsRayQueryParameters3D.create(Vector3(x + RAY_NUDGE, top, z + RAY_NUDGE),
				Vector3(x + RAY_NUDGE, bottom, z + RAY_NUDGE), WORLD_MASK)
			var hit: Dictionary = space.intersect_ray(q)
			var dm: int = 0
			if not hit.is_empty():
				var ground: float = (hit["position"] as Vector3).y
				dm = clampi(roundi((water - ground) * 10.0), 0, 255)
			full[j * cols + i] = dm
			if dm > 0:
				lo = Vector2i(mini(lo.x, i), mini(lo.y, j))
				hi = Vector2i(maxi(hi.x, i), maxi(hi.y, j))
	if hi.x < 0:
		lo = Vector2i(0, 0)
		hi = Vector2i(0, 0)
	lo = Vector2i(maxi(lo.x - CROP_MARGIN, 0), maxi(lo.y - CROP_MARGIN, 0))
	hi = Vector2i(mini(hi.x + CROP_MARGIN, cols - 1), mini(hi.y + CROP_MARGIN, rows - 1))
	var w: int = hi.x - lo.x + 1
	var h: int = hi.y - lo.y + 1
	var grid := PackedByteArray()
	grid.resize(w * h)
	var wet: int = 0
	for j: int in range(h):
		for i: int in range(w):
			var v: int = full[(lo.y + j) * cols + lo.x + i]
			grid[j * w + i] = v
			wet += 1 if v > 0 else 0
	var doc: Dictionary = {
		"_comment": "BAKED from %s by tools/world/bake_level.gd (LevelInfo, DECISIONS #175). The server compiles this in (build.rs); the client's LevelBake reads it. Do not edit: move the markers in the scene and bake again." % (root.scene_file_path if not root.scene_file_path.is_empty() else str(root.name)),
		"level": level_name,
		"id": int(s.get("level_id", 1)),
		"scene": root.scene_file_path,
		"water_y": water,
		"spawn": _vec(_spawn_of(root)),
		"wade_depth": float(s.get("wade_depth", 0.7)),
		"min_cast_depth": float(s.get("min_cast_depth", 0.5)),
		"depth_grid": {
			"file": level_name + "_depth.bin",
			"origin_x": bounds.position.x + lo.x * step,
			"origin_z": bounds.position.z + lo.y * step,
			"spacing": step,
			"width": w,
			"height": h,
			"unit": "decimetres of water, 0 = dry",
		},
		"spots": _spots_of(root),
		"points": _points_of(root),
	}
	var json_path: String = out_dir.path_join(level_name + ".json")
	var bin_path: String = out_dir.path_join(level_name + "_depth.bin")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var bf: FileAccess = FileAccess.open(bin_path, FileAccess.WRITE)
	if bf == null:
		return {"ok": false, "error": "cannot write %s" % bin_path}
	bf.store_buffer(grid)
	bf.close()
	var jf: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	jf.store_string(JSON.stringify(doc, "  ", false) + "\n")
	jf.close()
	return {"ok": true, "error": "", "doc": doc, "json": json_path, "bin": bin_path, "wet": wet,
		"width": w, "height": h}


## The first LevelSpawn's position, else a "SpawnPoint" marker's (the generated lakeside's), else
## the origin.
static func _spawn_of(root: Node3D) -> Vector3:
	for n: Node in root.find_children("*", "", true, false):
		if n is LevelSpawn:
			return (n as LevelSpawn).global_position
	var legacy: Node3D = root.find_child("SpawnPoint", true, false) as Node3D
	return legacy.global_position if legacy != null else root.global_position


## Every LevelSpot (or a marker with `spot_id` metadata, the lakeside's), smallest first: the
## first spot containing a point is the most specific one.
static func _spots_of(root: Node3D) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "", true, false):
		if n is LevelSpot:
			var s: LevelSpot = n as LevelSpot
			out.append({"id": s.spot_id, "name": s.display_name if not s.display_name.is_empty() else s.spot_id,
				"x": s.global_position.x, "z": s.global_position.z, "radius": s.radius})
		elif n is Marker3D and n.has_meta(&"spot_id"):
			var m: Marker3D = n as Marker3D
			out.append({"id": str(m.get_meta(&"spot_id")), "name": str(m.get_meta(&"display_name", m.get_meta(&"spot_id"))),
				"x": m.global_position.x, "z": m.global_position.z, "radius": m.gizmo_extents})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["radius"]) < float(b["radius"]))
	return out


static func _points_of(root: Node3D) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "", true, false):
		if n is LevelPoint:
			var p: LevelPoint = n as LevelPoint
			out.append({"id": p.point_id, "kind": p.kind, "x": p.global_position.x, "y": p.global_position.y,
				"z": p.global_position.z, "radius": p.radius, "tags": Array(p.tags)})
	return out


static func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
