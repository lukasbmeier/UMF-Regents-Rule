class_name RefereeRegion extends RefCounted
## A REGION REFEREE'S PART OF THE WORLD (DECISIONS #288): the cells it RUNS (`cells`: squares, as `Cells`
## numbers them, inclusive at both ends) and a `border` round them it WATCHES but does not run, so a sweep,
## a brain's eyes and a body's flight near its edge see what is just over it. What it runs: the NPCs and
## bodies standing in its cells (taken through the module, `drive_npcs`, so one referee drives each), and
## the swings of the players standing there. An NPC is handed on `hand_on_m` past the edge, not on it, so
## one pacing along an edge is not passed back and forth.
##
## SERVER-ONLY (hard rule 7b).

## The cells it runs: x0, z0 (position) to x1, z1 (end, inclusive).
var x0: int = 0
var z0: int = 0
var x1: int = 0
var z1: int = 0
## How many cells deep the border it watches is.
var border: int = 1
## How far past its edge an NPC it drives walks before it is handed on.
var hand_on_m: float = 8.0
## The side of a cell (`Cells.cell_m`); a test sets its own.
var side_m: float = -1.0
## The cells the level has (squares; `clip_to`): what it asks for stops there. Empty: the region's own.
var clip: Rect2i = Rect2i()


## `--region=x0,z0,x1,z1` (squares, inclusive), or null when the text is not four whole numbers.
static func parse(spec: String) -> RefereeRegion:
	var parts: PackedStringArray = spec.split(",", false)
	if parts.size() != 4:
		return null
	for p: String in parts:
		if not p.strip_edges().is_valid_int():
			return null
	var r := RefereeRegion.new()
	r.x0 = mini(int(parts[0]), int(parts[2]))
	r.z0 = mini(int(parts[1]), int(parts[3]))
	r.x1 = maxi(int(parts[0]), int(parts[2]))
	r.z1 = maxi(int(parts[1]), int(parts[3]))
	return r


func _side() -> float:
	return side_m if side_m > 0.0 else Cells.cell_m()


## Whether it runs what stands at `pos`: inside its cells, or, for what it already runs (`mine`), no more
## than `hand_on_m` past their edge.
func runs(pos: Vector3, mine: bool = false) -> bool:
	var m: float = _side()
	var slack: float = hand_on_m if mine else 0.0
	return pos.x >= x0 * m - slack and pos.x < (x1 + 1) * m + slack \
		and pos.z >= z0 * m - slack and pos.z < (z1 + 1) * m + slack


## Whether it watches cell squares `x`, `z` (its cells and the border round them).
func watches(x: int, z: int) -> bool:
	return x >= x0 - border and x <= x1 + border and z >= z0 - border and z <= z1 + border


## Ask for no cell the level does not have (its bake bounds, a cell round them): a region at the world's edge
## runs to the grid's, and a query for each of its 500 empty columns cost the server more than all the play
## (Regent's Rule's load test: reducers queued 260 ms at 50 players). An empty `bounds`: no clip.
func clip_to(bounds: AABB) -> void:
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		clip = Rect2i()
		return
	var m: float = _side()
	var a := Vector2i(Cells.axis(bounds.position.x, m) - 1, Cells.axis(bounds.position.z, m) - 1)
	var b := Vector2i(Cells.axis(bounds.end.x, m) + 1, Cells.axis(bounds.end.z, m) + 1)
	clip = Rect2i(a, b - a + Vector2i.ONE)


## The cells it watches, one range of chunks a column (`Cells.at`: a column's chunks are consecutive):
## [Vector2i(first, last), ...], west to east, within the level (`clip`). What it subscribes, a query per
## column per cell table. None when its region and the level do not meet.
func columns() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i(maxi(x0 - border, -Cells.HALF), maxi(z0 - border, -Cells.HALF))
	var hi := Vector2i(mini(x1 + border, Cells.HALF - 1), mini(z1 + border, Cells.HALF - 1))
	if clip.has_area():
		lo = Vector2i(maxi(lo.x, clip.position.x), maxi(lo.y, clip.position.y))
		hi = Vector2i(mini(hi.x, clip.end.x - 1), mini(hi.y, clip.end.y - 1))
	if lo.x > hi.x or lo.y > hi.y:
		return out
	for x: int in range(lo.x, hi.x + 1):
		out.append(Vector2i(Cells.at(x, lo.y), Cells.at(x, hi.y)))
	return out


func describe() -> String:
	return "cells %d,%d to %d,%d (and %d round)" % [x0, z0, x1, z1, border]
