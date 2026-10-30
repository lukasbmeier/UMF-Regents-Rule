class_name ContinentShape extends RefCounted
## THE CONTINENT'S SHAPE, READ OFF LUKE'S MAP (2026-10-24: "build the main continent here ... so we can test
## the chunk loading in a space bigger than the glade"). `continent_map.webp` is the source: its green is
## land, its grey-brown ridge is the mountain spine, everything else (parchment, the coast's wash) is sea.
## Only the largest landmass is kept (the islands are left out, as asked). The widest side of that landmass
## is `WIDTH_M` metres, and the starting camp's point (`CAMP_PX`, the centre-west lowlands) is the world's
## origin, flattened to y = 0, so the frontier glade's camp drops in unchanged.
##
## A GREYBOX: no regions, roads or towns (those are Luke's, later). Change the map, a number here, and run
## `build_continent.tscn` again; nothing is hand-edited. Everything is seeded: the same map gives the same
## world.

const MAP_PATH: String = "res://game/regents/levels/continent/continent_map.webp"
## The landmass's widest side, metres (Luke: "about 3 km").
const WIDTH_M: float = 3000.0
## The camp, as a point on the map (pixels): the big plain west of the ridge.
const CAMP_PX: Vector2 = Vector2(572.0, 508.0)
## The sea's surface. Below the camp (y = 0), so the glade's points stand on dry ground.
const SEA_Y: float = -6.0
## The camp's flat ground: whole to this radius, blended into the land by the second.
const CAMP_FLAT_M: float = 85.0
const CAMP_BLEND_M: float = 175.0
## The land: how high the shore rises in its first metres, the hills inland, the mountains.
const SHORE_RISE_M: float = 6.0
const SHORE_WIDTH_M: float = 120.0
const HILL_M: float = 14.0
const MOUNTAIN_M: float = 70.0
const MOUNTAIN_PEAK_M: float = 90.0
## The sea floor: how far it falls past the shore, and its deepest.
const SEA_SLOPE: float = 0.06
const SEA_DEEPEST_M: float = 14.0

## The map, classified, at its own resolution: 1 land, 0 sea (smoothed at the coast).
var land: PackedFloat32Array = PackedFloat32Array()
## How much of a mountain each pixel is, 0-1 (smoothed).
var ridge: PackedFloat32Array = PackedFloat32Array()
## Distance to the coast, pixels: positive on land, negative at sea.
var coast: PackedFloat32Array = PackedFloat32Array()
var map_w: int = 0
var map_h: int = 0
## Metres per map pixel, and the landmass's extent in world metres (x0, z0, x1, z1).
var m_per_px: float = 1.0
var extent: Rect2 = Rect2()

var _hills := FastNoiseLite.new()
var _peaks := FastNoiseLite.new()
## The same map at another size (the expanse, PROGRESS step 25: Skyrim's size for the load test): the landmass's
## widest side, and how much taller its hills and mountains stand. The continent's are the defaults.
var width_m: float = WIDTH_M
var relief: float = 1.0


func _init(p_width_m: float = WIDTH_M, p_relief: float = 1.0) -> void:
	width_m = p_width_m
	relief = p_relief
	_hills.seed = 4021
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 1.0 / 420.0
	_hills.fractal_octaves = 4
	_peaks.seed = 4022
	_peaks.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_peaks.frequency = 1.0 / 260.0
	_peaks.fractal_octaves = 4
	_read_map()


# =============================================================================================
# THE GROUND
# =============================================================================================

## The ground's height at world (x, z), metres.
func height(x: float, z: float) -> float:
	var p: Vector2 = to_map(x, z)
	var d_m: float = _sample(coast, p) * m_per_px
	var h: float
	if d_m <= 0.0:
		h = SEA_Y - 1.5 - minf(-d_m * SEA_SLOPE, SEA_DEEPEST_M)
	else:
		var inland: float = smoothstep(40.0, 320.0, d_m)
		h = SEA_Y + 1.2 + SHORE_RISE_M * smoothstep(0.0, SHORE_WIDTH_M, d_m)
		h += HILL_M * (1.0 + (relief - 1.0) * 0.5) * (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * inland
		var r: float = _sample(ridge, p)
		if r > 0.0:
			var peak: float = _peaks.get_noise_2d(x, z) * 0.5 + 0.5
			h += r * r * (MOUNTAIN_M + MOUNTAIN_PEAK_M * peak) * relief * smoothstep(0.0, 60.0, d_m)
		h = maxf(h, SEA_Y + 0.9)
	# The camp: flat at 0, blended in.
	var c: float = Vector2(x, z).length()
	if c < CAMP_BLEND_M:
		h = lerpf(0.0, h, smoothstep(CAMP_FLAT_M, CAMP_BLEND_M, c))
	return h


## Whether (x, z) is on the continent (not the sea), and how far from its coast, metres (negative: at sea).
func coast_distance(x: float, z: float) -> float:
	return _sample(coast, to_map(x, z)) * m_per_px


## How much of a mountain (x, z) is, 0-1.
func mountain(x: float, z: float) -> float:
	return _sample(ridge, to_map(x, z))


## World (x, z) as a point on the map, pixels.
func to_map(x: float, z: float) -> Vector2:
	return CAMP_PX + Vector2(x, z) / m_per_px


## A point on the map as world (x, z).
func to_world(p: Vector2) -> Vector2:
	return (p - CAMP_PX) * m_per_px


# =============================================================================================
# READING THE MAP
# =============================================================================================

func _read_map() -> void:
	var img: Image = Image.load_from_file(MAP_PATH)
	if img == null or img.is_empty():
		push_error("ContinentShape: cannot read %s" % MAP_PATH)
		return
	img.convert(Image.FORMAT_RGB8)
	map_w = img.get_width()
	map_h = img.get_height()
	var n: int = map_w * map_h
	# The paint is textured: classify a 5 x 5 average, not one pixel.
	var r: PackedFloat32Array = PackedFloat32Array()
	var g: PackedFloat32Array = PackedFloat32Array()
	var b: PackedFloat32Array = PackedFloat32Array()
	r.resize(n)
	g.resize(n)
	b.resize(n)
	for y: int in range(map_h):
		for x: int in range(map_w):
			var c: Color = img.get_pixel(x, y)
			r[y * map_w + x] = c.r
			g[y * map_w + x] = c.g
			b[y * map_w + x] = c.b
	r = _blur(r, 2)
	g = _blur(g, 2)
	b = _blur(b, 2)
	var green: PackedByteArray = PackedByteArray()
	var grey: PackedByteArray = PackedByteArray()
	green.resize(n)
	grey.resize(n)
	for i: int in range(n):
		var c := Color(r[i], g[i], b[i])
		# Land: yellow to deep green, saturated. Ridge: grey-brown (red at least green), unsaturated.
		green[i] = 1 if c.h > 0.15 and c.h < 0.42 and c.s > 0.32 and c.v > 0.18 else 0
		grey[i] = 1 if c.s < 0.36 and c.v > 0.28 and c.v < 0.8 and c.r >= c.g * 0.98 else 0
	# The ridge counts as land only beside green land (the parchment's pale patches are not mountains).
	var near_green: PackedByteArray = _dilate(green, 12)
	var any_land: PackedByteArray = PackedByteArray()
	any_land.resize(n)
	for i: int in range(n):
		any_land[i] = 1 if green[i] == 1 or (grey[i] == 1 and near_green[i] == 1) else 0
	any_land = _erode(_dilate(any_land, 2), 2)
	var main: PackedByteArray = _largest(any_land)
	main = _fill_holes(main)
	# The mountains: the grey inside the continent, widened a little and smoothed.
	var mtn: PackedFloat32Array = PackedFloat32Array()
	mtn.resize(n)
	var x0: int = map_w
	var y0: int = map_h
	var x1: int = 0
	var y1: int = 0
	for y: int in range(map_h):
		for x: int in range(map_w):
			var i: int = y * map_w + x
			if main[i] == 1:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
				mtn[i] = 1.0 if grey[i] == 1 and green[i] == 0 else 0.0
	# A lone grey speck is a smudge, not a mountain: only grey with grey round it.
	mtn = _blur(mtn, 3)
	coast = _signed_distance(main)
	# The map's dark shading along the shore reads as grey: mountains start a little way inland.
	for i: int in range(n):
		mtn[i] = smoothstep(0.35, 0.8, mtn[i]) * smoothstep(8.0, 18.0, coast[i])
	ridge = _blur(mtn, 4)
	land = PackedFloat32Array()
	land.resize(n)
	for i: int in range(n):
		land[i] = float(main[i])
	m_per_px = width_m / float(maxi(x1 - x0, y1 - y0))
	var a: Vector2 = to_world(Vector2(x0, y0))
	var z: Vector2 = to_world(Vector2(x1, y1))
	extent = Rect2(a, z - a)
	print("ContinentShape: landmass %dx%d px, %.2f m a pixel, extent %s" % [x1 - x0, y1 - y0, m_per_px, str(extent)])


## Bilinear lookup of a map field at `p` (pixels); off the map, the nearest edge.
func _sample(field: PackedFloat32Array, p: Vector2) -> float:
	var fx: float = clampf(p.x, 0.0, float(map_w - 1))
	var fy: float = clampf(p.y, 0.0, float(map_h - 1))
	var x0: int = mini(int(fx), map_w - 2)
	var y0: int = mini(int(fy), map_h - 2)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var i: int = y0 * map_w + x0
	var top: float = lerpf(field[i], field[i + 1], tx)
	var bottom: float = lerpf(field[i + map_w], field[i + map_w + 1], tx)
	return lerpf(top, bottom, ty)


## A box blur of radius `r`, separable.
func _blur(f: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var tmp: PackedFloat32Array = PackedFloat32Array()
	tmp.resize(f.size())
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(f.size())
	var span: float = float(2 * r + 1)
	for y: int in range(map_h):
		var row: int = y * map_w
		var acc: float = 0.0
		for k: int in range(-r, r + 1):
			acc += f[row + clampi(k, 0, map_w - 1)]
		for x: int in range(map_w):
			tmp[row + x] = acc / span
			acc += f[row + clampi(x + r + 1, 0, map_w - 1)] - f[row + clampi(x - r, 0, map_w - 1)]
	for x: int in range(map_w):
		var acc: float = 0.0
		for k: int in range(-r, r + 1):
			acc += tmp[clampi(k, 0, map_h - 1) * map_w + x]
		for y: int in range(map_h):
			out[y * map_w + x] = acc / span
			acc += tmp[clampi(y + r + 1, 0, map_h - 1) * map_w + x] - tmp[clampi(y - r, 0, map_h - 1) * map_w + x]
	return out


## Grow a mask by `r` pixels (a square), or shrink it.
func _dilate(m: PackedByteArray, r: int) -> PackedByteArray:
	var f: PackedFloat32Array = PackedFloat32Array()
	f.resize(m.size())
	for i: int in range(m.size()):
		f[i] = float(m[i])
	f = _blur(f, r)
	var out: PackedByteArray = PackedByteArray()
	out.resize(m.size())
	for i: int in range(m.size()):
		out[i] = 1 if f[i] > 0.0001 else 0
	return out


func _erode(m: PackedByteArray, r: int) -> PackedByteArray:
	var f: PackedFloat32Array = PackedFloat32Array()
	f.resize(m.size())
	for i: int in range(m.size()):
		f[i] = float(m[i])
	f = _blur(f, r)
	var out: PackedByteArray = PackedByteArray()
	out.resize(m.size())
	for i: int in range(m.size()):
		out[i] = 1 if f[i] > 0.9999 else 0
	return out


## The largest 4-connected region of a mask.
func _largest(m: PackedByteArray) -> PackedByteArray:
	var label: PackedInt32Array = PackedInt32Array()
	label.resize(m.size())
	label.fill(-1)
	var best: int = -1
	var best_size: int = 0
	var next: int = 0
	for start: int in range(m.size()):
		if m[start] == 0 or label[start] >= 0:
			continue
		var size: int = _flood(m, label, start, next, 1)
		if size > best_size:
			best_size = size
			best = next
		next += 1
	var out: PackedByteArray = PackedByteArray()
	out.resize(m.size())
	for i: int in range(m.size()):
		out[i] = 1 if label[i] == best else 0
	return out


## The mask with every region of 0s that does not reach the map's edge filled in (lakes, the ridge's gaps).
func _fill_holes(m: PackedByteArray) -> PackedByteArray:
	var label: PackedInt32Array = PackedInt32Array()
	label.resize(m.size())
	label.fill(-1)
	for x: int in range(map_w):
		for y: int in [0, map_h - 1]:
			var i: int = y * map_w + x
			if m[i] == 0 and label[i] < 0:
				_flood(m, label, i, 0, 0)
	for y: int in range(map_h):
		for x: int in [0, map_w - 1]:
			var i: int = y * map_w + x
			if m[i] == 0 and label[i] < 0:
				_flood(m, label, i, 0, 0)
	var out: PackedByteArray = PackedByteArray()
	out.resize(m.size())
	for i: int in range(m.size()):
		out[i] = 0 if label[i] == 0 else 1
	return out


## Label the region of `value`s holding `start` with `id`; its size.
func _flood(m: PackedByteArray, label: PackedInt32Array, start: int, id: int, value: int) -> int:
	var stack: PackedInt32Array = PackedInt32Array([start])
	label[start] = id
	var size: int = 0
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		size += 1
		var x: int = i % map_w
		var y: int = i / map_w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= map_w or ny >= map_h:
				continue
			var j: int = ny * map_w + nx
			if m[j] == value and label[j] < 0:
				label[j] = id
				stack.append(j)
	return size


## Distance to the coast, pixels (a two-pass chamfer): positive inside the mask, negative outside.
func _signed_distance(m: PackedByteArray) -> PackedFloat32Array:
	var inside: PackedFloat32Array = _distance_to(m, 0)
	var outside: PackedFloat32Array = _distance_to(m, 1)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(m.size())
	for i: int in range(m.size()):
		out[i] = inside[i] - 0.5 if m[i] == 1 else -(outside[i] - 0.5)
	return out


## Each pixel's distance to the nearest pixel whose mask is `target`.
func _distance_to(m: PackedByteArray, target: int) -> PackedFloat32Array:
	const BIG: float = 1.0e9
	const D1: float = 1.0
	const D2: float = 1.41421356
	var d: PackedFloat32Array = PackedFloat32Array()
	d.resize(m.size())
	for i: int in range(m.size()):
		d[i] = 0.0 if m[i] == target else BIG
	for y: int in range(map_h):
		for x: int in range(map_w):
			var i: int = y * map_w + x
			var v: float = d[i]
			if x > 0:
				v = minf(v, d[i - 1] + D1)
			if y > 0:
				v = minf(v, d[i - map_w] + D1)
				if x > 0:
					v = minf(v, d[i - map_w - 1] + D2)
				if x < map_w - 1:
					v = minf(v, d[i - map_w + 1] + D2)
			d[i] = v
	for y: int in range(map_h - 1, -1, -1):
		for x: int in range(map_w - 1, -1, -1):
			var i: int = y * map_w + x
			var v: float = d[i]
			if x < map_w - 1:
				v = minf(v, d[i + 1] + D1)
			if y < map_h - 1:
				v = minf(v, d[i + map_w] + D1)
				if x < map_w - 1:
					v = minf(v, d[i + map_w + 1] + D2)
				if x > 0:
					v = minf(v, d[i + map_w - 1] + D2)
			d[i] = v
	return d
