class_name LakesideShape
extends RefCounted
## THE SHAPE OF THE LAKESIDE: what the ground does at any (x, z), in metres, and where the
## features the rest of the world is placed around sit. Input to `build_lakeside.gd` only —
## once the terrain is generated, the TERRAIN is the truth, and everything downstream (the
## server's bake, the fishing rig's depth probe) reads the terrain, not this.
##
## 512 x 512 m, centred on the origin. -Z is north. The water surface is y = 0.
##
##   the lake       an irregular ellipse, 230 x 160 m, north of centre; a shallow shelf at its
##                  edge dropping to about 8 m in the middle
##   Reed Bay       a shallow lobe on the west shore, never much past knee deep
##   Rocky Point    a low peninsula from the east shore, looking out at THE DEEP HOLE
##   the Deep Hole  a pit near the middle, a Yew Longrod's cast from Rocky Point's tip or the dock
##   the village    a flat terrace on the south shore, a dock running north into the lake
##   the hills      rising all round toward the edge of the world, which they hide

const SIZE: int = 512
const HALF: float = 256.0
const WATER: float = 0.0

const LAKE_CENTRE: Vector2 = Vector2(0.0, -24.0)
const LAKE_RADII: Vector2 = Vector2(114.0, 78.0)
const BAY_CENTRE: Vector2 = Vector2(-114.0, 16.0)
const BAY_RADIUS: float = 30.0
const POINT_A: Vector2 = Vector2(104.0, -40.0)
const POINT_B: Vector2 = Vector2(66.0, -44.0)
const POINT_RADIUS: float = 7.0
const POINT_HEIGHT: float = 1.7
const DEEP_HOLE: Vector2 = Vector2(10.0, -27.0)
const DEEP_HOLE_SIGMA: float = 13.0
const DEEP_HOLE_EXTRA: float = 6.0

const TERRACE_CENTRE: Vector2 = Vector2(0.0, 90.0)
const TERRACE_HALF: Vector2 = Vector2(62.0, 34.0)
const TERRACE_HEIGHT: float = 2.2
const TERRACE_EDGE: float = 14.0

## The village square, where players arrive.
const SQUARE: Vector2 = Vector2(0.0, 96.0)
## The dock runs north from the shore along x = 0, out to here.
const DOCK_END: Vector2 = Vector2(0.0, 24.0)

## Named water, for the loot tables. [id, name, centre, radius]
##
## WHERE A SPOT GOES IS GAME DESIGN. A spot's `min_rod` (shared/fishing/fishing.json) is the rod
## that reaches it at all — Fishing for Compliments' gate — and only its placement makes that
## true: no part of it within a lesser rod's reach (+ the server's slack) of anywhere a player
## can stand, and some of it within its own rod's. The first lakeside put the North Drop a
## four-metre lob off the north beach. `cargo test --test level` measures every spot against
## the bake and says how far off one is; the margins here are under a metre, because between the
## rods' reaches there is not much more lake than that.
##   The North Drop  Ash Rod: 28 m out from the north shore
##   The Deep Hole   Yew Longrod: 37 m from Rocky Point's tip and from the dock's end
const SPOTS: Array[Array] = [
	["dock_end", "Dock End", Vector2(0.0, 16.0), 14.0],
	["reed_bay", "Reed Bay", Vector2(-116.0, 14.0), 24.0],
	["deep_hole", "The Deep Hole", Vector2(10.0, -27.0), 12.0],
	["north_drop", "The North Drop", Vector2(-31.0, -51.0), 15.5],
	["village_shallows", "Village Shallows", Vector2(-40.0, 36.0), 12.0],
]

## Dirt paths: polylines, 3 m wide.
##
## Arrays of Vector2, read as `Array` and cast per point. NOT `Array[PackedVector2Array]`: a
## packed array cannot be built in a constant, and bare `[...]` literals under that type stay
## plain Arrays, which a loop typed `for line: PackedVector2Array` silently turns into EMPTY
## arrays — the first generated world had no paths at all, and nothing reported it.
const PATHS: Array[Array] = [
	# square to the dock
	[Vector2(0, 96), Vector2(0, 74), Vector2(0, 58)],
	# west, down to Reed Bay
	[Vector2(0, 96), Vector2(-34, 94), Vector2(-66, 80), Vector2(-96, 58), Vector2(-122, 42)],
	# east, round the shore to Rocky Point
	[Vector2(0, 96), Vector2(38, 94), Vector2(76, 70), Vector2(112, 36), Vector2(128, -8),
		Vector2(118, -34), Vector2(96, -40)],
]

var _broad := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init() -> void:
	_setup(_broad, 101, 0.006, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_mid, 202, 0.025, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_ridge, 303, 0.012, 4, FastNoiseLite.TYPE_SIMPLEX)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_shore, 404, 0.018, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_setup(_forest, 505, 0.02, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)


static func _setup(n: FastNoiseLite, seed_value: int, freq: float, octaves: int,
		kind: FastNoiseLite.NoiseType) -> void:
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = kind


# --- the ground -------------------------------------------------------------------------------

## Ground height at (x, z), before the terrain quantises it.
func height(x: float, z: float) -> float:
	var land: float = 2.4 + 2.0 * _broad.get_noise_2d(x, z) + 0.8 * _mid.get_noise_2d(x, z)
	# Hills rising toward the edge, and a wall of them at the edge itself so nobody sees the end
	# of the world.
	var d: float = Vector2(x, (z + 10.0) * 1.05).length()
	land += smoothstep(140.0, 235.0, d) * (14.0 + 24.0 * (_ridge.get_noise_2d(x, z) * 0.5 + 0.5))
	land += smoothstep(205.0, 252.0, maxf(absf(x), absf(z))) * 30.0
	# The village terrace is flat.
	land = lerpf(land, TERRACE_HEIGHT, terrace_weight(x, z))
	# Paths are gently levelled so they do not climb every bump.
	land = lerpf(land, land * 0.6 + TERRACE_HEIGHT * 0.4, path_weight(x, z) * 0.5)

	var q: float = lake_field(x, z)
	var depth: float = 0.5 + 7.5 * smoothstep(1.0, 0.3, q)
	var hole: float = Vector2(x, z).distance_squared_to(DEEP_HOLE)
	depth += DEEP_HOLE_EXTRA * exp(-hole / (2.0 * DEEP_HOLE_SIGMA * DEEP_HOLE_SIGMA))
	# Reed Bay stays shallow whatever the main basin does.
	var b: float = Vector2(x, z).distance_to(BAY_CENTRE) / BAY_RADIUS
	var bay: float = smoothstep(1.3, 0.7, b)
	depth = lerpf(depth, 0.4 + 0.9 * smoothstep(1.0, 0.2, b), bay)
	var wet: float = smoothstep(1.07, 0.93, q)
	var h: float = lerpf(land, -depth, wet)

	# Rocky Point: a low spit of land running out into the water.
	var pd: float = _segment_distance(Vector2(x, z), POINT_A, POINT_B)
	var pw: float = smoothstep(POINT_RADIUS + 6.0, POINT_RADIUS, pd)
	h = lerpf(h, maxf(h, POINT_HEIGHT + 0.5 * _mid.get_noise_2d(x, z)), pw)
	return h


## 0 at the lake's centre, 1 at its shore, more than 1 on land. The main ellipse and Reed Bay,
## joined smoothly, with a noisy edge so the shore is not a drawn curve.
func lake_field(x: float, z: float) -> float:
	var e: float = ((Vector2(x, z) - LAKE_CENTRE) / LAKE_RADII).length()
	e *= 1.0 + 0.12 * _shore.get_noise_2d(x, z)
	var b: float = Vector2(x, z).distance_to(BAY_CENTRE) / BAY_RADIUS
	return _smooth_min(e, b, 0.25)


## 1 on the village terrace, fading to 0 across its edge.
func terrace_weight(x: float, z: float) -> float:
	var p: Vector2 = (Vector2(x, z) - TERRACE_CENTRE).abs()
	var r: float = 10.0
	var q: Vector2 = (p - TERRACE_HALF + Vector2(r, r)).max(Vector2.ZERO)
	var outside: float = q.length() - r
	return smoothstep(TERRACE_EDGE, 0.0, outside)


## 1 on a path's centre line, fading to 0 by its edge.
func path_weight(x: float, z: float) -> float:
	return smoothstep(2.6, 0.9, path_distance(x, z))


## Distance from a point to the nearest path's centre line.
static func path_distance(x: float, z: float) -> float:
	var best: float = INF
	for line: Array in PATHS:
		for i: int in range(line.size() - 1):
			best = minf(best, _segment_distance(Vector2(x, z), line[i] as Vector2, line[i + 1] as Vector2))
	return best


## 0..1: how much this ground wants to be forest.
func forest_weight(x: float, z: float) -> float:
	var f: float = _forest.get_noise_2d(x, z) * 0.5 + 0.5
	var d: float = Vector2(x, (z + 10.0) * 1.05).length()
	# Denser on the hills, thinner in the meadows round the lake, none in the village.
	f += smoothstep(120.0, 200.0, d) * 0.35
	f -= terrace_weight(x, z) * 1.5
	return clampf((f - 0.52) * 2.4, 0.0, 1.0)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _smooth_min(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)
