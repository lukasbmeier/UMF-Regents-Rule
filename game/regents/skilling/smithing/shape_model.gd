class_name ShapeModel extends RefCounted
## SMITHING'S MINIGAME, SHAPE TO THE OUTLINE (owner, 2026-10-19): the hot bar is a row of columns, each
## a height. Strike a column: it is beaten down `hammer_drop` (no lower than nothing) and `spread_pct` of
## that is pushed into each neighbour. Match the part's outline. The bar is workable until it cools
## (`heat_ms` after the round begins or after a reheat); a strike on a cold bar does nothing. Reheating
## (column -1) takes `reheat_ms`. The score is how close the bar ends to the outline.
## Inputs are (time, column), column -1 a reheat. A PURE MODEL (its Rust twin: `genre::regents::shape`,
## the golden file from `game/regents/tests/make_skill_goldens.py`); the live minigame plays `strike()`.

const IGNORED: int = 0
const STRUCK: int = 1
const COLD: int = 2      # struck, but the bar was too cold to move
const REHEAT: int = 3
const HELD: int = 4      # mid-swing or mid-reheat: held, and struck the moment it ends
const REHEAT_COLUMN: int = -1

var params: ShapeParams
var heights: PackedInt32Array
var hot_until_ms: int = 0
var next_ok_ms: int = 0
var last_t_ms: int = -1
var strikes: int = 0
var colds: int = 0
var reheats: int = 0
var held: bool = false
var held_at_ms: int = 0
var held_column: int = 0
## Strikes landed, counted, and the latest's outcome, time and column: the live view follows these.
var acts: int = 0
var last_act: int = IGNORED
var last_act_ms: int = 0
var last_act_column: int = -1


static func start(seed_value: int, p: ShapeParams) -> ShapeModel:
	var m: ShapeModel = ShapeModel.new()
	m.params = p
	m.heights = PackedInt32Array()
	var st: int = SkillRandom.seed_state(seed_value)
	for i: int in p.outline.size():
		st = SkillRandom.next_u32(st)
		m.heights.append(p.start_height + (st >> 8) % (p.start_jitter + 1))
	m.hot_until_ms = p.heat_ms
	return m


## A strike at `t_ms` on `column` (REHEAT_COLUMN: put it back in the fire). Returns what it did. During
## a swing or a reheat it is HELD (the latest one) and lands the moment that ends: no click is dropped.
func strike(t_ms: int, column: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	settle(t_ms)
	if t_ms < 0 or t_ms > params.duration_ms or column < REHEAT_COLUMN or column >= heights.size():
		return IGNORED
	if t_ms < next_ok_ms:
		held = true
		held_at_ms = next_ok_ms
		held_column = column
		return HELD
	return _strike(t_ms, column)


## Land a held strike whose swing or reheat ended by `t_ms`. Returns what it did (IGNORED: none landed).
func settle(t_ms: int) -> int:
	if not held or held_at_ms > t_ms:
		return IGNORED
	held = false
	if held_at_ms > params.duration_ms:
		return IGNORED
	return _strike(held_at_ms, held_column)


## The round to its end: a strike still held lands if it is in time.
func finish() -> void:
	settle(params.duration_ms)


func _strike(t_ms: int, column: int) -> int:
	acts += 1
	last_act_ms = t_ms
	last_act_column = column
	last_act = _land(t_ms, column)
	return last_act


func _land(t_ms: int, column: int) -> int:
	if column == REHEAT_COLUMN:
		reheats += 1
		next_ok_ms = t_ms + params.reheat_ms
		hot_until_ms = t_ms + params.reheat_ms + params.heat_ms
		return REHEAT
	next_ok_ms = t_ms + params.swing_ms
	if t_ms >= hot_until_ms:
		colds += 1
		return COLD
	var d: int = mini(heights[column], params.hammer_drop)
	heights[column] -= d
	var side: int = d * params.spread_pct / 100
	if column > 0:
		heights[column - 1] += side
	if column < heights.size() - 1:
		heights[column + 1] += side
	strikes += 1
	return STRUCK


## How far the bar is off the outline, summed over the columns.
func error() -> int:
	var e: int = 0
	for i: int in heights.size():
		e += absi(heights[i] - params.outline[i])
	return e


func score_pm() -> int:
	return maxi(0, 1000 - error() * 1000 / params.error_scale)


func result() -> Dictionary:
	return {"strikes": strikes, "colds": colds, "reheats": reheats, "error": error(), "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, column) pairs, in the order sent.
static func play(seed_value: int, p: ShapeParams, inputs: PackedInt32Array) -> Dictionary:
	var m: ShapeModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.strike(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
