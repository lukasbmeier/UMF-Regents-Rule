class_name CarveModel extends RefCounted
## WOODWORKING'S CARVE (Luke, 2026-11-07: "vertical and have wood you can take off from either side (to allow asymmetry
## for bows/staffs) instead of just being a duplicate of smithing"). A PURE MODEL: its Rust twin is
## `genre::regents::carve`, the golden file `shared/golden/regents/carve.json` comes from a third copy
## (`game/regents/tests/make_skill_goldens.py`); change a rule in all three.
##
## THE STAVE stands upright in rows (row 0 at the top); each row has a LEFT and a RIGHT edge, its distance out from the
## middle line, SIGNED (negative: past the line, on the other side; a curved stave's edge crosses it). From the seed:
## each row's left then right edge, `start_half` give or take `start_jitter`; then one draw, the FLIP (with `mirror` on,
## an odd draw swaps the two profiles: the piece bends the other way); then each profile's one bump (a row, then a size
## up to `outline_vary`; it falls off over three rows either side), left profile first. A CUT (`kind * 1000 + row`: 1
## left deep, 2 left fine, 3 right deep, 4 right fine) takes that edge in by `deep_cut` or `fine_cut`, never past the
## other edge (the wood never goes below nothing) and never back; a cut while the pattern is on is nothing; a cut sooner than
## `swing_ms` after the last is HELD and lands as the swing ends (the latest held wins; it does not land if the pattern
## is on or the piece set down by then). LAY puts the pattern on (each lay costs `lay_cost_pm` of the ceiling: the one
## at the start is free), LIFT takes it off; DONE sets the piece down: nothing after counts. An input before the last
## one, outside 0..duration, or after DONE is nothing.
## THE SCORE: the error is both edges' distance from their profiles, summed over the rows; 1000 less error x 1000 /
## `error_scale`, never above the ceiling nor below 0.

const DONE: int = 5000
const LAY: int = 5001
const LIFT: int = 5002
const LEFT_DEEP: int = 1000
const LEFT_FINE: int = 2000
const RIGHT_DEEP: int = 3000
const RIGHT_FINE: int = 4000
## What an input did (the live game's look and sound).
const IGNORED: int = 0
const CUT: int = 1
const HELD: int = 2
const OTHER: int = 3

var params: CarveParams
var left: PackedInt32Array = PackedInt32Array()
var right: PackedInt32Array = PackedInt32Array()
var target_left: PackedInt32Array = PackedInt32Array()
var target_right: PackedInt32Array = PackedInt32Array()
var laid: bool = false
var lays: int = 0
var cuts: int = 0
var next_ok_ms: int = 0
var held: bool = false
var held_at_ms: int = 0
var held_code: int = 0
var done_ms: int = -1
var last_t_ms: int = -1
## The last cut that landed: its code and when (the live view follows these), and how many have.
var last_cut_code: int = 0
var last_cut_ms: int = -100000


static func start(seed_value: int, p: CarveParams) -> CarveModel:
	var m: CarveModel = CarveModel.new()
	m.params = p
	var n: int = p.left_outline.size()
	var st: int = SkillRandom.seed_state(seed_value)
	var j: int = maxi(0, p.start_jitter)
	for _i: int in n:
		st = SkillRandom.next_u32(st)
		m.left.append(p.start_half + (st >> 8) % (2 * j + 1) - j)
		st = SkillRandom.next_u32(st)
		m.right.append(p.start_half + (st >> 8) % (2 * j + 1) - j)
	st = SkillRandom.next_u32(st)
	var flip: bool = p.mirror > 0 and (st >> 8) % 2 == 1
	var v: int = maxi(0, p.outline_vary)
	for side: int in 2:
		var base: PackedInt32Array = p.left_outline if (side == 0) != flip else p.right_outline
		st = SkillRandom.next_u32(st)
		var r0: int = (st >> 8) % maxi(1, n)
		st = SkillRandom.next_u32(st)
		var a: int = (st >> 8) % (2 * v + 1) - v
		var out: PackedInt32Array = PackedInt32Array()
		for i: int in n:
			out.append(base[i] + a * maxi(0, 3 - absi(i - r0)) / 3)
		if side == 0:
			m.target_left = out
		else:
			m.target_right = out
	m.laid = p.hide_outline > 0
	return m


func rows() -> int:
	return left.size()


func _apply(t_ms: int, code: int) -> void:
	var kind: int = code / 1000
	var row: int = code % 1000
	var depth: int = params.deep_cut if kind == 1 or kind == 3 else params.fine_cut
	if kind <= 2:
		left[row] = maxi(-right[row], left[row] - depth)
	else:
		right[row] = maxi(-left[row], right[row] - depth)
	cuts += 1
	next_ok_ms = t_ms + params.swing_ms
	last_cut_code = code
	last_cut_ms = t_ms


## Land a held cut whose swing has ended by `t_ms`.
func settle(t_ms: int) -> void:
	if not held or held_at_ms > t_ms:
		return
	held = false
	if held_at_ms <= params.duration_ms and done_ms < 0 and not laid:
		_apply(held_at_ms, held_code)


## An input at `t_ms`. Returns what it did.
func press(t_ms: int, code: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	if t_ms < 0 or t_ms > params.duration_ms or done_ms >= 0:
		return IGNORED
	settle(t_ms)
	if code == DONE:
		done_ms = t_ms
		held = false
		return OTHER
	if code == LAY:
		if params.hide_outline > 0 and not laid:
			laid = true
			lays += 1
			return OTHER
		return IGNORED
	if code == LIFT:
		laid = false
		return OTHER
	if code < 1000 or code >= 5000 or code % 1000 >= rows():
		return IGNORED
	if laid:
		return IGNORED
	if t_ms < next_ok_ms:
		held = true
		held_at_ms = next_ok_ms
		held_code = code
		return HELD
	_apply(t_ms, code)
	return CUT


## The round to its end.
func finish() -> void:
	if done_ms < 0:
		settle(params.duration_ms)


func error() -> int:
	var e: int = 0
	for i: int in rows():
		e += absi(left[i] - target_left[i]) + absi(right[i] - target_right[i])
	return e


func ceiling_pm() -> int:
	return maxi(0, 1000 - lays * params.lay_cost_pm)


func score_pm() -> int:
	return mini(maxi(0, 1000 - error() * 1000 / maxi(1, params.error_scale)), ceiling_pm())


func result() -> Dictionary:
	return {"error": error(), "cuts": cuts, "lays": lays, "ceiling_pm": ceiling_pm(), "score_pm": score_pm()}


## The edge furthest past its profile (a cut code that would fit: deep while a deep cut does not go past), or -1 when none
## is past: what a careful carver cuts next, as the profiles are remembered (`left_line`, `right_line`).
func furthest(left_line: PackedInt32Array, right_line: PackedInt32Array) -> int:
	var best: int = 0
	var code: int = -1
	for i: int in rows():
		for side: int in 2:
			var over: int = (left[i] - left_line[i]) if side == 0 else (right[i] - right_line[i])
			if over > best:
				best = over
				var deep: bool = over >= params.deep_cut
				code = (LEFT_DEEP if side == 0 else RIGHT_DEEP) + (0 if deep else 1000) + i
	return code


## A whole round replayed from its inputs: flat (time, code) pairs, in the order sent; run to its end.
static func play(seed_value: int, p: CarveParams, inputs: PackedInt32Array) -> Dictionary:
	var m: CarveModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.press(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
