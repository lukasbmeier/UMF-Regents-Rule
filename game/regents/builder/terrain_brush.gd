@tool
class_name RegentsTerrainBrush extends RefCounted
## TERRAIN3D SCULPTING, TEXTURE PAINTING & AUTO-LEVELING FOUNDATIONS (WB3, WB4, WB6;
## `docs/regents_rule/WORLD_BUILDER_PREP.md` §3, §4).
##
## Works on a live `Terrain3D` node (`terrain`) and keeps a synchronized height/texture/color grid so both
## windowed Creative Mode and fast headless unit checks can sculpt, paint, carve ramps, level building
## footprints, and undo/redo (`restore_snapshot`) with zero friction.

enum Mode {
	RAISE,
	LOWER,
	SMOOTH,
	FLATTEN,
	TERRACE,
	RAMP,
	PAINT_TEXTURE,
	PAINT_COLOR,
	AUTO_SLOPE,
}

enum Tex {
	GRASS = 0,
	ROCK = 1,
	SAND = 2,
	DIRT = 3,
	COBBLE = 4,
}

const MODE_NAMES: PackedStringArray = [
	"Raise", "Lower", "Smooth", "Flatten", "Terrace", "Ramp", "Paint Texture", "Paint Tint", "Auto-Slope"
]
const TEX_NAMES: PackedStringArray = ["Grass", "Rock", "Sand", "Dirt", "Cobble"]
const TEX_COLORS: Array[Color] = [
	Color(0.42, 0.60, 0.27),
	Color(0.55, 0.53, 0.50),
	Color(0.82, 0.76, 0.56),
	Color(0.52, 0.39, 0.26),
	Color(0.48, 0.49, 0.52),
]

var terrain: Terrain3D = null
var spacing: float = 2.0
var water_y: float = -6.0
var origin: Vector2 = Vector2(-256.0, -256.0)
var width: int = 257
var height: int = 257

## Brush settings
var mode: Mode = Mode.RAISE
var radius_m: float = 8.0
var strength: float = 1.5
var falloff: float = 0.65
var flatten_y: float = 0.0
var terrace_step_m: float = 3.0
var paint_tex: int = Tex.GRASS
var paint_color: Color = Color(0.9, 0.9, 0.9, 1.0)

## Backing grid (always maintained; mirrored to `terrain.data` when `terrain` has allocated regions).
var _heights: PackedFloat32Array = PackedFloat32Array()
var _tex_ids: PackedByteArray = PackedByteArray()
var _colors: PackedColorArray = PackedColorArray()


func _init(p_terrain: Terrain3D = null, p_extent_m: float = 512.0, p_spacing: float = 2.0) -> void:
	terrain = p_terrain
	spacing = maxf(p_spacing, 0.5)
	if terrain != null:
		spacing = maxf(terrain.vertex_spacing, 0.5)
	_init_grid(p_extent_m)


func _init_grid(extent_m: float) -> void:
	var half: float = extent_m * 0.5
	origin = Vector2(-half, -half)
	width = maxi(3, int(round(extent_m / spacing)) + 1)
	height = width
	var count: int = width * height
	_heights.resize(count)
	_heights.fill(0.0)
	_tex_ids.resize(count)
	_tex_ids.fill(Tex.GRASS)
	_colors.resize(count)
	_colors.fill(Color.WHITE)
	if terrain != null and terrain.data != null and terrain.data.get_region_count() > 0:
		sync_from_terrain()


## Reads heights and texture IDs from `terrain.data` into the backing grid.
func sync_from_terrain() -> void:
	if terrain == null or terrain.data == null or terrain.data.get_region_count() == 0:
		return
	for j: int in height:
		for i: int in width:
			var p: Vector2 = _xz(i, j)
			var h: float = terrain.data.get_height(Vector3(p.x, 0.0, p.y))
			var idx: int = j * width + i
			if not is_nan(h):
				_heights[idx] = h
			var base_id: int = terrain.data.get_control_base_id(Vector3(p.x, 0.0, p.y))
			if base_id >= 0:
				_tex_ids[idx] = clampi(base_id, 0, TEX_NAMES.size() - 1)


## Fill the grid (and `terrain` if present) as a blank flat canvas at `base_y` (WB3: Start From Scratch).
func init_blank(base_y: float = 0.0, base_tex: int = Tex.GRASS) -> void:
	_heights.fill(base_y)
	_tex_ids.fill(clampi(base_tex, 0, TEX_NAMES.size() - 1))
	_colors.fill(Color.WHITE)
	_push_all_to_terrain()


## Fill the grid (and `terrain` if present) from a procedural noise island/continent (WB3: Start From Procedural Base).
func init_procedural(seed_val: int = 4021, hill_amp_m: float = 16.0, ridge_amp_m: float = 42.0, camp_flat_m: float = 45.0) -> void:
	var hills := FastNoiseLite.new()
	hills.seed = seed_val
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 1.0 / 180.0
	hills.fractal_octaves = 4
	var ridges := FastNoiseLite.new()
	ridges.seed = seed_val + 17
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.frequency = 1.0 / 240.0
	ridges.fractal_octaves = 3
	var max_r: float = float(width - 1) * spacing * 0.46
	for j: int in height:
		for i: int in width:
			var p: Vector2 = _xz(i, j)
			var dist: float = p.length()
			var coast_t: float = clampf((max_r - dist) / maxf(max_r * 0.25, 1.0), -1.0, 1.0)
			var h: float = 0.0
			if coast_t <= 0.0:
				h = water_y - 1.0 + coast_t * 8.0
			else:
				var n_hill: float = hills.get_noise_2d(p.x, p.y) * 0.5 + 0.5
				var n_ridge: float = maxf(0.0, ridges.get_noise_2d(p.x, p.y))
				h = 1.2 + hill_amp_m * n_hill * coast_t + ridge_amp_m * n_ridge * n_ridge * smoothstep(0.2, 0.8, coast_t)
			if dist < camp_flat_m * 1.8:
				h = lerpf(0.0, h, smoothstep(camp_flat_m, camp_flat_m * 1.8, dist))
			_heights[j * width + i] = h
	apply_auto_slope_all()
	_push_all_to_terrain()


## Create and configure a `Terrain3D` node ready for the World Builder.
## `parent` (if given) receives `t` so `Terrain3DData` is initialized inside the scene tree before `init_blank` / `init_procedural`.
static func create_terrain_node(_extent_m: float = 512.0, vertex_spacing: float = 2.0, parent: Node3D = null) -> Terrain3D:
	var t := Terrain3D.new()
	t.name = "Terrain3D"
	if parent != null:
		parent.add_child(t, true)
		t.owner = parent
	t.change_region_size(Terrain3D.SIZE_64)
	t.vertex_spacing = vertex_spacing
	t.mesh_lods = 6
	t.mesh_size = 48
	t.collision_mode = Terrain3DCollision.FULL_GAME
	t.collision_layer = SpaceTimeEntity.WORLD_MASK
	t.collision_mask = 0
	var mat: Terrain3DMaterial = t.material
	if mat != null:
		mat.world_background = Terrain3DMaterial.NONE
		mat.auto_shader = false
		mat.texture_filtering = Terrain3DMaterial.LINEAR
	const TEX_DIR: String = "res://game/regents/levels/continent/terrain/textures/"
	const BASE_STEMS: PackedStringArray = ["grass", "rock", "sand", "sand", "rock", "rock"]
	var assets := Terrain3DAssets.new()
	for id: int in TEX_NAMES.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = TEX_NAMES[id].to_lower()
		var stem: String = BASE_STEMS[clampi(id, 0, BASE_STEMS.size() - 1)]
		var alb_path: String = TEX_DIR + stem + "_albedo.res"
		var nrm_path: String = TEX_DIR + stem + "_normal.res"
		if ResourceLoader.exists(alb_path):
			ta.albedo_texture = load(alb_path) as Texture2D
		if ResourceLoader.exists(nrm_path):
			ta.normal_texture = load(nrm_path) as Texture2D
		ta.albedo_color = TEX_COLORS[id]
		ta.uv_scale = 0.12
		ta.detiling_rotation = 0.15
		assets.set_texture(id, ta)
	t.assets = assets
	return t


## World height at `(wx, wz)` (bilinearly sampled on the grid, or from `terrain.data`).
func height_at(wx: float, wz: float) -> float:
	var fx: float = clampf((wx - origin.x) / spacing, 0.0, float(width - 1))
	var fz: float = clampf((wz - origin.y) / spacing, 0.0, float(height - 1))
	var i0: int = mini(int(floor(fx)), width - 2)
	var j0: int = mini(int(floor(fz)), height - 2)
	var tx: float = fx - float(i0)
	var tz: float = fz - float(j0)
	var idx: int = j0 * width + i0
	var top: float = lerpf(_heights[idx], _heights[idx + 1], tx)
	var bot: float = lerpf(_heights[idx + width], _heights[idx + width + 1], tx)
	return lerpf(top, bot, tz)


## Surface normal at `(wx, wz)`.
func normal_at(wx: float, wz: float) -> Vector3:
	var dx: float = (height_at(wx + spacing, wz) - height_at(wx - spacing, wz)) / (2.0 * spacing)
	var dz: float = (height_at(wx, wz + spacing) - height_at(wx, wz - spacing)) / (2.0 * spacing)
	return Vector3(-dx, 1.0, -dz).normalized()


## Slope (rise over run) at `(wx, wz)`.
func slope_at(wx: float, wz: float) -> float:
	var dx: float = (height_at(wx + spacing, wz) - height_at(wx - spacing, wz)) / (2.0 * spacing)
	var dz: float = (height_at(wx, wz + spacing) - height_at(wx, wz - spacing)) / (2.0 * spacing)
	return Vector2(dx, dz).length()


## Texture ID at `(wx, wz)`.
func texture_at(wx: float, wz: float) -> int:
	var i: int = clampi(roundi((wx - origin.x) / spacing), 0, width - 1)
	var j: int = clampi(roundi((wz - origin.y) / spacing), 0, height - 1)
	return int(_tex_ids[j * width + i])


## Vertex tint color at `(wx, wz)`.
func color_at(wx: float, wz: float) -> Color:
	var i: int = clampi(roundi((wx - origin.x) / spacing), 0, width - 1)
	var j: int = clampi(roundi((wz - origin.y) / spacing), 0, height - 1)
	return _colors[j * width + i]


## Apply one brush stroke at `(wx, wz)`. Returns an undo snapshot dictionary `{indices, heights, tex_ids, colors}`.
func apply_stroke(wx: float, wz: float, override_mode: int = -1) -> Dictionary:
	var m: Mode = (override_mode as Mode) if override_mode >= 0 else mode
	var r: float = maxf(radius_m, 0.5)
	var reach: float = maxf(r, spacing)
	var i0: int = clampi(floori((wx - reach - origin.x) / spacing), 0, width - 1)
	var i1: int = clampi(ceili((wx + reach - origin.x) / spacing), 0, width - 1)
	var j0: int = clampi(floori((wz - reach - origin.y) / spacing), 0, height - 1)
	var j1: int = clampi(ceili((wz + reach - origin.y) / spacing), 0, height - 1)
	var ni: int = clampi(roundi((wx - origin.x) / spacing), 0, width - 1)
	var nj: int = clampi(roundi((wz - origin.y) / spacing), 0, height - 1)
	var snap: Dictionary = _capture_rect(i0, j0, i1, j1)
	var old_heights: PackedFloat32Array = _heights.duplicate() if m == Mode.SMOOTH else PackedFloat32Array()

	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = _xz(i, j)
			var d: float = p.distance_to(Vector2(wx, wz))
			var is_center: bool = (i == ni and j == nj)
			if d > r and not is_center:
				continue
			var w: float = 1.0 if (is_center and r <= spacing) else _falloff_weight(d / r)
			var idx: int = j * width + i
			match m:
				Mode.RAISE:
					_heights[idx] += strength * w
				Mode.LOWER:
					_heights[idx] -= strength * w
				Mode.SMOOTH:
					var avg: float = _neighbor_average(old_heights, i, j)
					_heights[idx] = lerpf(old_heights[idx], avg, clampf(w * minf(strength * 0.5, 1.0), 0.0, 1.0))
				Mode.FLATTEN:
					_heights[idx] = lerpf(_heights[idx], flatten_y, w)
				Mode.TERRACE:
					var step_m: float = maxf(terrace_step_m, 0.5)
					var snapped: float = roundf(_heights[idx] / step_m) * step_m
					_heights[idx] = lerpf(_heights[idx], snapped, w)
				Mode.PAINT_TEXTURE:
					if is_center or d <= r:
						_tex_ids[idx] = clampi(paint_tex, 0, TEX_NAMES.size() - 1)
				Mode.PAINT_COLOR:
					_colors[idx] = _colors[idx].lerp(paint_color, w)
				Mode.AUTO_SLOPE:
					_tex_ids[idx] = _auto_tex_for(p.x, p.y, _heights[idx])
	_sync_rect_to_terrain(i0, j0, i1, j1)
	return snap


## Automatically levels the terrain under a building's rotated footprint (`size` = width, depth in meters) to
## `center.y`, cosine-blending a skirt of `blend_m` meters around it (WB4). Returns an undo snapshot.
func flatten_footprint(center: Vector3, yaw: float, size: Vector2, blend_m: float = 4.0, pad_m: float = 0.8) -> Dictionary:
	var hx: float = size.x * 0.5 + pad_m
	var hz: float = size.y * 0.5 + pad_m
	var reach: float = Vector2(hx + blend_m, hz + blend_m).length()
	var i0: int = clampi(floori((center.x - reach - origin.x) / spacing), 0, width - 1)
	var i1: int = clampi(ceili((center.x + reach - origin.x) / spacing), 0, width - 1)
	var j0: int = clampi(floori((center.z - reach - origin.y) / spacing), 0, height - 1)
	var j1: int = clampi(ceili((center.z + reach - origin.y) / spacing), 0, height - 1)
	var snap: Dictionary = _capture_rect(i0, j0, i1, j1)
	var cos_y: float = cos(-yaw)
	var sin_y: float = sin(-yaw)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = _xz(i, j) - Vector2(center.x, center.z)
			var lx: float = absf(p.x * cos_y - p.y * sin_y)
			var lz: float = absf(p.x * sin_y + p.y * cos_y)
			var dx: float = maxf(lx - hx, 0.0)
			var dz: float = maxf(lz - hz, 0.0)
			var out_dist: float = Vector2(dx, dz).length()
			if out_dist > blend_m:
				continue
			var idx: int = j * width + i
			var t: float = 0.0 if blend_m <= 0.001 else smoothstep(0.0, blend_m, out_dist)
			_heights[idx] = lerpf(center.y, _heights[idx], t)
	_sync_rect_to_terrain(i0, j0, i1, j1)
	return snap


## Carves a walkable ramp between `from` and `to` of width `width_m` with a `blend_m` side skirt (WB4).
## Returns an undo snapshot.
func carve_ramp(from: Vector3, to: Vector3, width_m: float = 4.0, blend_m: float = 3.0, tex_id: int = -1) -> Dictionary:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.01:
		return {}
	var half_w: float = width_m * 0.5
	var margin: float = half_w + blend_m
	var lo := Vector2(minf(a.x, b.x) - margin, minf(a.y, b.y) - margin)
	var hi := Vector2(maxf(a.x, b.x) + margin, maxf(a.y, b.y) + margin)
	var i0: int = clampi(floori((lo.x - origin.x) / spacing), 0, width - 1)
	var i1: int = clampi(ceili((hi.x - origin.x) / spacing), 0, width - 1)
	var j0: int = clampi(floori((lo.y - origin.y) / spacing), 0, height - 1)
	var j1: int = clampi(ceili((hi.y - origin.y) / spacing), 0, height - 1)
	var snap: Dictionary = _capture_rect(i0, j0, i1, j1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = _xz(i, j)
			var u: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
			var closest: Vector2 = a + ab * u
			var d: float = p.distance_to(closest)
			if d > margin:
				continue
			var ramp_y: float = lerpf(from.y, to.y, u)
			var idx: int = j * width + i
			if d <= half_w:
				_heights[idx] = ramp_y
				if tex_id >= 0:
					_tex_ids[idx] = clampi(tex_id, 0, TEX_NAMES.size() - 1)
			else:
				var s: float = smoothstep(half_w, margin, d)
				_heights[idx] = lerpf(ramp_y, _heights[idx], s)
	_sync_rect_to_terrain(i0, j0, i1, j1)
	return snap


## Levels the cross-slope along a `Curve3D` (`Path3D` road spline) and paints `tex_id` along it (WB6).
func flatten_road_spline(curve: Curve3D, xform: Transform3D, width_m: float = 3.2, blend_m: float = 2.5,
		tex_id: int = Tex.DIRT) -> Dictionary:
	if curve == null or curve.point_count < 2:
		return {}
	var baked: PackedVector3Array = curve.get_baked_points()
	if baked.size() < 2:
		return {}
	var pts: Array[Vector3] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in baked:
		var wp: Vector3 = xform * p
		wp.y = height_at(wp.x, wp.z)
		pts.append(wp)
		lo = Vector2(minf(lo.x, wp.x), minf(lo.y, wp.z))
		hi = Vector2(maxf(hi.x, wp.x), maxf(hi.y, wp.z))
	var half_w: float = width_m * 0.5
	var margin: float = half_w + blend_m
	var i0: int = clampi(floori((lo.x - margin - origin.x) / spacing), 0, width - 1)
	var i1: int = clampi(ceili((hi.x + margin - origin.x) / spacing), 0, width - 1)
	var j0: int = clampi(floori((lo.y - margin - origin.y) / spacing), 0, height - 1)
	var j1: int = clampi(ceili((hi.y + margin - origin.y) / spacing), 0, height - 1)
	var snap: Dictionary = _capture_rect(i0, j0, i1, j1)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = _xz(i, j)
			var best_d: float = INF
			var best_y: float = 0.0
			for k: int in range(pts.size() - 1):
				var a := Vector2(pts[k].x, pts[k].z)
				var b := Vector2(pts[k + 1].x, pts[k + 1].z)
				var ab: Vector2 = b - a
				var l2: float = ab.length_squared()
				var u: float = clampf((p - a).dot(ab) / maxf(l2, 0.0001), 0.0, 1.0)
				var d: float = p.distance_to(a + ab * u)
				if d < best_d:
					best_d = d
					best_y = lerpf(pts[k].y, pts[k + 1].y, u)
			if best_d > margin:
				continue
			var idx: int = j * width + i
			if best_d <= half_w:
				_heights[idx] = best_y
				if tex_id >= 0:
					_tex_ids[idx] = clampi(tex_id, 0, TEX_NAMES.size() - 1)
			else:
				var s: float = smoothstep(half_w, margin, best_d)
				_heights[idx] = lerpf(best_y, _heights[idx], s)
	_sync_rect_to_terrain(i0, j0, i1, j1)
	return snap


## Auto-paint Sand near `water_y`, Rock on steep slopes (`>= 0.85`), and Grass elsewhere over the whole grid.
func apply_auto_slope_all() -> void:
	for j: int in height:
		for i: int in width:
			var p: Vector2 = _xz(i, j)
			var idx: int = j * width + i
			_tex_ids[idx] = _auto_tex_for(p.x, p.y, _heights[idx])
	_push_all_to_terrain()


## Capture the CURRENT values at the indices in `before_snap` (for Redo before applying an Undo).
func capture_matching(before_snap: Dictionary) -> Dictionary:
	if before_snap.is_empty() or not before_snap.has("indices"):
		return {}
	var indices: PackedInt32Array = before_snap["indices"] as PackedInt32Array
	var hs := PackedFloat32Array()
	var ts := PackedByteArray()
	var cs := PackedColorArray()
	hs.resize(indices.size())
	ts.resize(indices.size())
	cs.resize(indices.size())
	for k: int in indices.size():
		var idx: int = indices[k]
		hs[k] = _heights[idx]
		ts[k] = _tex_ids[idx]
		cs[k] = _colors[idx]
	return {
		"indices": indices.duplicate(),
		"heights": hs,
		"tex_ids": ts,
		"colors": cs,
		"rect": before_snap.get("rect", Vector4i(0, 0, width - 1, height - 1)),
	}


## Restore a snapshot returned by `apply_stroke`, `flatten_footprint`, `carve_ramp`, or `flatten_road_spline`.
func restore_snapshot(snap: Dictionary) -> void:
	if snap.is_empty() or not snap.has("indices"):
		return
	var indices: PackedInt32Array = snap["indices"] as PackedInt32Array
	var hs: PackedFloat32Array = snap["heights"] as PackedFloat32Array
	var ts: PackedByteArray = snap["tex_ids"] as PackedByteArray
	var cs: PackedColorArray = snap["colors"] as PackedColorArray
	for k: int in indices.size():
		var idx: int = indices[k]
		if idx >= 0 and idx < _heights.size():
			_heights[idx] = hs[k]
			_tex_ids[idx] = ts[k]
			_colors[idx] = cs[k]
	var rect: Vector4i = snap.get("rect", Vector4i(0, 0, width - 1, height - 1))
	_sync_rect_to_terrain(rect.x, rect.y, rect.z, rect.w)


func _capture_rect(i0: int, j0: int, i1: int, j1: int) -> Dictionary:
	var indices := PackedInt32Array()
	var hs := PackedFloat32Array()
	var ts := PackedByteArray()
	var cs := PackedColorArray()
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var idx: int = j * width + i
			indices.append(idx)
			hs.append(_heights[idx])
			ts.append(_tex_ids[idx])
			cs.append(_colors[idx])
	return {
		"indices": indices,
		"heights": hs,
		"tex_ids": ts,
		"colors": cs,
		"rect": Vector4i(i0, j0, i1, j1),
	}


func _sync_rect_to_terrain(i0: int, j0: int, i1: int, j1: int) -> void:
	if terrain == null or not terrain.is_inside_tree() or terrain.data == null or terrain.data.get_region_count() == 0:
		return
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = _xz(i, j)
			var idx: int = j * width + i
			var pos := Vector3(p.x, 0.0, p.y)
			if is_nan(terrain.data.get_height(pos)):
				continue
			terrain.data.set_height(pos, _heights[idx])
			var tid: int = int(_tex_ids[idx])
			terrain.data.set_control_base_id(pos, tid)
			terrain.data.set_control_overlay_id(pos, tid)
			terrain.data.set_control_blend(pos, 0.0)
			terrain.data.set_color(pos, _colors[idx])
	terrain.data.update_maps()


func _push_all_to_terrain() -> void:
	if terrain == null or not terrain.is_inside_tree() or terrain.data == null:
		return
	var region_verts: int = int(terrain.region_size) if int(terrain.region_size) > 0 else 64
	var region_m: float = float(region_verts) * spacing
	var end_xz: Vector2 = origin + Vector2(float(width - 1), float(height - 1)) * spacing
	var imp_origin: Vector2 = (origin / region_m).floor() * region_m
	var imp_end: Vector2 = (end_xz / region_m).ceil() * region_m
	var imp_w: int = int(round((imp_end.x - imp_origin.x) / spacing)) + 1
	var imp_h: int = int(round((imp_end.y - imp_origin.y) / spacing)) + 1
	var h_img: Image = Image.create_empty(imp_w, imp_h, false, Image.FORMAT_RF)
	var c_img: Image = Image.create_empty(imp_w, imp_h, false, Image.FORMAT_RF)
	var col_img: Image = Image.create_empty(imp_w, imp_h, false, Image.FORMAT_RGBA8)
	for j: int in imp_h:
		var wz: float = imp_origin.y + float(j) * spacing
		var gj: int = clampi(roundi((wz - origin.y) / spacing), 0, height - 1)
		for i: int in imp_w:
			var wx: float = imp_origin.x + float(i) * spacing
			var gi: int = clampi(roundi((wx - origin.x) / spacing), 0, width - 1)
			var idx: int = gj * width + gi
			h_img.set_pixel(i, j, Color(_heights[idx], 0.0, 0.0, 1.0))
			var tid: int = int(_tex_ids[idx])
			var bits: int = Terrain3DUtil.enc_base(tid) | Terrain3DUtil.enc_overlay(tid) | Terrain3DUtil.enc_blend(0)
			c_img.set_pixel(i, j, Color(Terrain3DUtil.as_float(bits), 0.0, 0.0, 1.0))
			col_img.set_pixel(i, j, _colors[idx])
	terrain.data.import_images([h_img, c_img, col_img], Vector3(imp_origin.x, 0.0, imp_origin.y), 0.0, 1.0)


func _xz(i: int, j: int) -> Vector2:
	return origin + Vector2(float(i), float(j)) * spacing


func _falloff_weight(norm_dist: float) -> float:
	var d: float = clampf(norm_dist, 0.0, 1.0)
	var inner: float = clampf(1.0 - falloff, 0.0, 0.99)
	if d <= inner:
		return 1.0
	var u: float = (d - inner) / maxf(1.0 - inner, 0.001)
	return 0.5 * (1.0 + cos(u * PI))


func _neighbor_average(src: PackedFloat32Array, cx: int, cz: int) -> float:
	var sum: float = 0.0
	var count: int = 0
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var x: int = clampi(cx + dx, 0, width - 1)
			var z: int = clampi(cz + dz, 0, height - 1)
			sum += src[z * width + x]
			count += 1
	return sum / float(maxi(count, 1))


func _auto_tex_for(wx: float, wz: float, h: float) -> int:
	if h <= water_y + 1.6:
		return Tex.SAND
	if slope_at(wx, wz) >= 0.85:
		return Tex.ROCK
	return Tex.GRASS
