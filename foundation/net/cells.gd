class_name Cells
## THE WORLD IN SQUARES (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §3-§5): the client's twin
## of the module's `server/src/cell.rs`. Every row of a placed thing carries the cell it is in
## (`chunk`); a client with ring interest asks only for the cells round it (`InterestManager`), and a
## streamed level loads the scenery of a wider ring (`LevelStreamer`). The numbers are the game's, in
## `res://shared/rules.json` `cells` (the same file the module compiles in): the side of a cell, the
## rings, the hysteresis. Both sides are held to `res://shared/golden/cells.json` (the `cells` suite and
## `server/tests/cell.rs`).

## Cells along each side of the grid: 1024, half either side of the origin.
const GRID: int = 1024
const HALF: int = GRID / 2

## What a game whose rules.json predates the cells takes (the module's defaults too, `build.rs`).
const DEFAULTS: Dictionary = {"cell_m": 64.0, "ring": 1, "stream_ring": 2, "hysteresis_m": 4.0}


## The side of a cell, m.
static func cell_m() -> float:
	return float(_rule("cell_m"))


## Cells either side of a ring client's own that it is sent (1: 3 x 3).
static func ring_radius() -> int:
	return int(_rule("ring"))


## Cells either side that a streamed level loads (2: 5 x 5).
static func stream_radius() -> int:
	return int(_rule("stream_ring"))


## How far inside a new cell a ring client goes before its centre moves, m.
static func hysteresis_m() -> float:
	return float(_rule("hysteresis_m"))


## Which square along one axis a coordinate is in (0 at the origin's, negative west or north of it).
## In f32, as the module works it out, so a place on an edge is in the same cell on both sides.
static func axis(v: float, side: float = -1.0) -> int:
	var m: float = side if side > 0.0 else cell_m()
	var q: float = PackedFloat32Array([v / m])[0]
	return clampi(floori(q), -HALF, HALF - 1)


## The cell at squares `x`, `z`, clamped to the grid.
static func at(x: int, z: int) -> int:
	return (clampi(x, -HALF, HALF - 1) + HALF) * GRID + (clampi(z, -HALF, HALF - 1) + HALF)


## The cell `pos` is in (its height does not count).
static func chunk_of(pos: Vector3, side: float = -1.0) -> int:
	return at(axis(pos.x, side), axis(pos.z, side))


## The squares a cell is at: Vector2i(x, z).
static func squares(chunk: int) -> Vector2i:
	return Vector2i(chunk / GRID - HALF, chunk % GRID - HALF)


## The cells within `r` squares of `chunk` (itself and its neighbours), each once, row by row; those
## past the grid's edge left out.
static func ring(chunk: int, r: int) -> PackedInt64Array:
	var c: Vector2i = squares(chunk)
	var out := PackedInt64Array()
	for x: int in range(c.x - r, c.x + r + 1):
		for z: int in range(c.y - r, c.y + r + 1):
			if x >= -HALF and x < HALF and z >= -HALF and z < HALF:
				out.append(at(x, z))
	return out


## Where a ring's centre should be for someone at `pos` whose centre is `centre` (-1: none yet): it
## moves only once they are `margin` m inside another cell, so walking along an edge never churns. A jump past
## the cells next to the centre (a teleport, a respawn) moves it at once, wherever in its cell they land
## (Regent's Rule's spawn is ON an edge: back from far away, a player kept a ring 600 m off, sent nothing).
static func recentre(centre: int, pos: Vector3, margin: float = -1.0, side: float = -1.0) -> int:
	var here: int = chunk_of(pos, side)
	if centre < 0 or here == centre:
		return here
	var m: float = side if side > 0.0 else cell_m()
	var h: float = margin if margin >= 0.0 else hysteresis_m()
	var sq: Vector2i = squares(here)
	# How far inside its own cell the place is, on the nearer of each axis's two edges.
	var in_x: float = minf(pos.x - sq.x * m, (sq.x + 1) * m - pos.x)
	var in_z: float = minf(pos.z - sq.y * m, (sq.y + 1) * m - pos.z)
	var old: Vector2i = squares(centre)
	if absi(sq.x - old.x) > 1 or absi(sq.y - old.y) > 1:
		return here
	# Only the axes it crossed need the margin: a step along an edge it did not cross is not a move.
	var deep: bool = (sq.x == old.x or in_x >= h) and (sq.y == old.y or in_z >= h)
	return here if deep else centre


static func _rule(key: String) -> Variant:
	var cells: Variant = Rules.doc().get("cells", {})
	if cells is Dictionary and (cells as Dictionary).has(key):
		return (cells as Dictionary)[key]
	return DEFAULTS[key]
