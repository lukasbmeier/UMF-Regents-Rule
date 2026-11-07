class_name ShapeModel extends RefCounted
## SMITHING'S MINIGAME, SHAPE TO THE OUTLINE (owner, 2026-10-19): the hot bar is a row of columns, each
## a height. Strike a column: it is beaten down `hammer_drop` (no lower than nothing) and `spread_pct` of
## that is pushed into each neighbor. Match the part's outline. The bar is workable until it cools
## (`heat_ms` after the round begins or after a reheat); a strike on a cold bar does nothing. Reheating
## (column -1) takes `reheat_ms`. The score is how close the bar ends to the outline.
## TWO STRIKES (MINIGAMES_PREP.md §3.1, 2026-11-05): the strike above is the HEAVY one (roughing out); a LIGHT TAP
## (column `TAP + c`) beats column c down `tap_drop` and pushes `tap_spread_pct` into its neighbors (finishing the
## line). `tap_drop` 0 switches taps off: a tap is then ignored, so a round from before taps replays unchanged.
## THE BANDS' RULES (Luke, 2026-11-05, after playing; `GAME.md` "The anvil's bands, A TEST"), each off at 0:
## - HEATS, NOT A CLOCK (`max_reheats`): only so many reheats; the part is SET DOWN (`DONE`) when the smith is happy
##   (`duration_ms` is then only a cap); each reheat lowers the part's CEILING (`reheat_cost_pm`).
## - THE TEMPLATE (`hide_outline`): the outline shows only while the template is laid on the bar (`LAY`, `LIFT`); the
##   round starts with it on; NO STRIKES while it is (a reheat may). Each lay may cost the ceiling (`lay_cost_pm`).
## - THE OUTLINE VARIES (`outline_vary`): every round's is the part's shape moved a little from the seed (the same
##   metal to beat off), so no one learns one round's hits by heart.
## - HEAT COLORS (`red_ms`): in a heat's last `red_ms` the bar is red: a strike does not move it, it CRACKS it
##   (`crack_cost_pm` off the ceiling).
## - THE QUENCH (`quench_lo_pm` .. `quench_hi_pm`, the bar's heat in thousandths): set down in that window, the part
##   gains `quench_bonus_pm`; outside it, it loses up to `quench_loss_pm` (a window's width out: all of it). Never
##   above the ceiling, never below nothing: a quench never destroys the part.
## Inputs are (time, column): column -1 a reheat, `TAP + c` a tap, `DONE`, `LAY`, `LIFT` (positive, so an old
## server ignores them as columns off the bar). A PURE MODEL (its Rust twin: `genre::regents::shape`, the golden file
## from `game/regents/tests/make_skill_goldens.py`); the live minigame plays `strike()`.

const IGNORED: int = 0
const STRUCK: int = 1
const COLD: int = 2      # struck, but the bar was too cold to move
const REHEAT: int = 3
const HELD: int = 4      # mid-swing or mid-reheat: held, and struck the moment it ends
const CRACKED: int = 5   # struck red: it did not move, it cracked
const SET_DOWN: int = 6
const TEMPLATE: int = 7  # the template laid on or lifted off
const REHEAT_COLUMN: int = -1
## A light tap on column c is sent as column `TAP + c`.
const TAP: int = 1000
## Set the part down (and quench it, when the round has a quench); lay the template on; lift it off.
const DONE: int = 2000
const LAY: int = 2001
const LIFT: int = 2002

var params: ShapeParams
var heights: PackedInt32Array
## This round's outline (the part's, varied by the seed).
var outline: PackedInt32Array
var hot_until_ms: int = 0
var next_ok_ms: int = 0
var last_t_ms: int = -1
var strikes: int = 0
var colds: int = 0
var reheats: int = 0
var lays: int = 0
var cracks: int = 0
## The template is on the bar.
var laid: bool = false
## When the part was set down (-1: not yet).
var done_ms: int = -1
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
	m.outline = round_outline(seed_value, p)
	m.hot_until_ms = p.heat_ms
	m.laid = p.hide_outline > 0
	return m


## The round's outline: the part's, moved by up to `outline_vary` in three smooth bumps drawn from the seed (after
## the bar's own draws), the total kept so every variant takes as much beating off.
static func round_outline(seed_value: int, p: ShapeParams) -> PackedInt32Array:
	var n: int = p.outline.size()
	var out: PackedInt32Array = p.outline.duplicate()
	if p.outline_vary <= 0 or n == 0:
		return out
	var st: int = SkillRandom.seed_state(seed_value)
	for _i: int in n:
		st = SkillRandom.next_u32(st)   # the bar's own draws
	var offs: PackedInt32Array = PackedInt32Array()
	offs.resize(n)
	offs.fill(0)
	for _k: int in 3:
		st = SkillRandom.next_u32(st)
		var c: int = (st >> 8) % n
		st = SkillRandom.next_u32(st)
		var a: int = (st >> 8) % (2 * p.outline_vary + 1) - p.outline_vary
		for j: int in range(-2, 3):
			if c + j >= 0 and c + j < n:
				offs[c + j] += (1 if a >= 0 else -1) * (absi(a) * (3 - absi(j)) / 3)
	var total: int = 0
	for i: int in n:
		out[i] = maxi(1, p.outline[i] + offs[i])
		total += out[i] - p.outline[i]
	st = SkillRandom.next_u32(st)
	var at: int = (st >> 8) % n
	for _guard: int in 100000:
		if total == 0:
			break
		if total > 0 and out[at] > 1:
			out[at] -= 1
			total -= 1
		elif total < 0:
			out[at] += 1
			total += 1
		at = (at + 1) % n
	return out


## A strike at `t_ms` on `column` (REHEAT_COLUMN: put it back in the fire; `DONE`, `LAY`, `LIFT`). Returns what it
## did. During a swing or a reheat a strike is HELD (the latest one) and lands the moment that ends: no click is
## dropped. Setting down and the template are instant, never held. After the part is set down, nothing counts.
func strike(t_ms: int, column: int) -> int:
	if t_ms < last_t_ms or done_ms >= 0:
		return IGNORED
	last_t_ms = t_ms
	settle(t_ms)
	if t_ms < 0 or t_ms > params.duration_ms or not is_valid_column(column):
		return IGNORED
	if column == DONE:
		held = false
		done_ms = t_ms
		return SET_DOWN
	if column == LAY or column == LIFT:
		if laid == (column == LAY):
			return IGNORED
		laid = column == LAY
		lays += int(column == LAY)
		return TEMPLATE
	if t_ms < next_ok_ms:
		held = true
		held_at_ms = next_ok_ms
		held_column = column
		return HELD
	return _strike(t_ms, column)


## A column this round takes: a reheat, a heavy strike on the bar, a tap (taps on), setting down (heats on), the
## template (a template round).
func is_valid_column(column: int) -> bool:
	if column >= DONE:
		if column == DONE:
			return params.max_reheats > 0
		return params.hide_outline > 0 and (column == LAY or column == LIFT)
	if column >= TAP:
		return params.tap_drop > 0 and column - TAP < heights.size()
	return column >= REHEAT_COLUMN and column < heights.size()


## Land a held strike whose swing or reheat ended by `t_ms`. Returns what it did (IGNORED: none landed).
func settle(t_ms: int) -> int:
	if not held or held_at_ms > t_ms:
		return IGNORED
	held = false
	if held_at_ms > params.duration_ms:
		return IGNORED
	return _strike(held_at_ms, held_column)


## The round to its end: a strike still held lands if it is in time (not after the part was set down).
func finish() -> void:
	if done_ms < 0:
		settle(params.duration_ms)


func _strike(t_ms: int, column: int) -> int:
	var did: int = _land(t_ms, column)
	if did != IGNORED:
		acts += 1
		last_act_ms = t_ms
		last_act_column = column
		last_act = did
	return did


func _land(t_ms: int, column: int) -> int:
	if column == REHEAT_COLUMN:
		if params.max_reheats > 0 and reheats >= params.max_reheats:
			return IGNORED
		reheats += 1
		next_ok_ms = t_ms + params.reheat_ms
		hot_until_ms = t_ms + params.reheat_ms + params.heat_ms
		return REHEAT
	if laid:
		return IGNORED   # no strikes while the template is on the bar
	next_ok_ms = t_ms + params.swing_ms
	if t_ms >= hot_until_ms:
		colds += 1
		return COLD
	if t_ms >= hot_until_ms - params.red_ms:
		cracks += 1
		return CRACKED
	var tap: bool = column >= TAP
	var c: int = column - TAP if tap else column
	var d: int = mini(heights[c], params.tap_drop if tap else params.hammer_drop)
	heights[c] -= d
	var side: int = d * (params.tap_spread_pct if tap else params.spread_pct) / 100
	if c > 0:
		heights[c - 1] += side
	if c < heights.size() - 1:
		heights[c + 1] += side
	strikes += 1
	return STRUCK


## How hot the bar is at `t_ms`, in thousandths of a heat (1000 fresh from the fire or in it, 0 cold).
func heat_pm(t_ms: int) -> int:
	if hot_until_ms <= t_ms:
		return 0
	return mini(1000, (hot_until_ms - t_ms) * 1000 / params.heat_ms)


## Whether the bar at `t_ms` is red (a strike would crack it).
func is_red(t_ms: int) -> bool:
	return params.red_ms > 0 and t_ms < hot_until_ms and t_ms >= hot_until_ms - params.red_ms


## Reheats left (-1: as many as the clock allows).
func reheats_left() -> int:
	return maxi(0, params.max_reheats - reheats) if params.max_reheats > 0 else -1


## Nothing more can happen: set down, or past the cap, or cold with no reheats left.
func is_over(t_ms: int) -> bool:
	return done_ms >= 0 or t_ms > params.duration_ms or (reheats_left() == 0 and t_ms >= hot_until_ms and not held)


## How far the bar is off the outline, summed over the columns.
func error() -> int:
	var e: int = 0
	for i: int in heights.size():
		e += absi(heights[i] - outline[i])
	return e


## The best the part can be now: what the reheats, the lays and the cracks have cost.
func ceiling_pm() -> int:
	return maxi(0, 1000 - reheats * params.reheat_cost_pm - lays * params.lay_cost_pm - cracks * params.crack_cost_pm)


## The quench's lift (or loss) set down now, or as it was set down; 0 in a round with no quench.
func quench_pm(t_ms: int = -1) -> int:
	var lo: int = params.quench_lo_pm
	var hi: int = params.quench_hi_pm
	if hi <= 0:
		return 0
	var h: int = heat_pm(done_ms if done_ms >= 0 else (t_ms if t_ms >= 0 else params.duration_ms))
	if h >= lo and h <= hi:
		return params.quench_bonus_pm
	var dist: int = lo - h if h < lo else h - hi
	return -mini(params.quench_loss_pm, dist * params.quench_loss_pm / maxi(1, hi - lo))


func raw_pm() -> int:
	return maxi(0, 1000 - error() * 1000 / params.error_scale)


func score_pm() -> int:
	return maxi(0, mini(ceiling_pm(), raw_pm() + quench_pm()))


func result() -> Dictionary:
	return {"strikes": strikes, "colds": colds, "reheats": reheats, "lays": lays, "cracks": cracks, "error": error(),
		"ceiling_pm": ceiling_pm(), "quench_pm": quench_pm(), "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, column) pairs, in the order sent.
static func play(seed_value: int, p: ShapeParams, inputs: PackedInt32Array) -> Dictionary:
	var m: ShapeModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.strike(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
