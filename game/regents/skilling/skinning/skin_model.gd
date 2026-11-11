class_name SkinModel extends RefCounted
## SKINNING'S CUT LINE (`HERBALISM_HUNTING_PREP.md` H4, Luke 2026-11-07: "DRAG the knife along the cut line ... off the
## line tears the hide"). A PURE MODEL: its Rust twin is `genre::regents::skin`, the golden file
## `shared/golden/regents/skin.json` comes from a third copy (`game/regents/tests/make_skill_goldens.py`); change a rule
## in all three. Whole numbers; division TRUNCATES toward zero.
##
## THE HIDE is 1000 x 1000. A LINE, drawn from the seed's stream as it starts (the first at the start): its way (draw
## % 2: 0 left to right, 1 right to left), then for each of its `points` points k: across at 100 + k * 800 / (points -
## 1) (from the right, 1000 less that, when it runs right to left), and up or down at 500 + (draw % (2 x wobble + 1)) -
## wobble. Each draw is (next_u32 >> 8). Each stretch between two points has its length, the integer square root
## (`isqrt`, the floor) of its squared length (never under 1).
## THE CUT'S END (the tip) is on stretch `seg`, `f` thousandths along it: (P + (Q - P) x f / 1000).
## AN INPUT (time, x, y): x and y in 0..1000 the knife IN the hide there (pressed, or moved while pressed); x = -1 the
## knife LIFTED. Anything else, an input before the last one, or outside 0..duration, is nothing.
## A TICK of 50 ms (tick k runs once every input before (k + 1) x 50 ms has been taken), the knife in the hide at K:
##   ON THE LINE: K within `near` of the line through the tip's stretch (cross^2 <= near^2 x len^2), or of the line
##   through the next stretch when there is one; NEAR THE TIP: within `reach` of it (squared). Both: it CUTS: K's place
##   along the stretch (dot x 1000 / len^2; 0 when the dot is not over 0), when past f, moves f there, but at most
##   cut_speed x 1000 / length (at least 1) a tick (a knife on the next stretch's line and PAST THE BEND into it, its
##   dot along that stretch over 0, counts as 1000: the cut runs to the bend); at 1000 the tip moves to the next stretch (f 0), or, on the last,
##   the LINE IS DONE: worth 1000 less `tear_pm` a tear (never under 0), the knife LIFTS, the next line is drawn.
##   Otherwise it TEARS (one tear on this line).
## At the round's end a line part cut is worth (its worth as above) x (seg x 1000 + f) / (points - 1) / 1000 x
## `part_keep_pm` / 1000. THE SCORE: the lines' worth over `target_lines`, never past 1000.

const TICK_MS: int = 50
const LIFT: int = -1
## What an input did (the live game's look).
const IGNORED: int = 0
const PRESSED: int = 1
const MOVED: int = 2
const LIFTED: int = 3
## What a tick did.
const CUT: int = 1
const TORN: int = 2
const LINE_DONE: int = 3

var params: SkinParams
## The line being cut: its points (hide units) and each stretch's length.
var px: PackedInt32Array = PackedInt32Array()
var py: PackedInt32Array = PackedInt32Array()
var seg_len: PackedInt32Array = PackedInt32Array()
var rng_state: int = 0
## The next tick to run; the line being cut (0 the first); the tip: its stretch and how far along it (thousandths).
var tick: int = 0
var line: int = 0
var seg: int = 0
var f: int = 0
## The knife: in the hide or not, and where.
var down: bool = false
var kx: int = 0
var ky: int = 0
## This line's tears; the round's lines done, clean ones, every tear.
var tears: int = 0
var lines: int = 0
var clean: int = 0
var torn: int = 0
## What the lines are worth so far (thousandths each).
var worth: int = 0
var over: bool = false
var finished: bool = false
var last_t_ms: int = -1
## What the last tick did (CUT, TORN, LINE_DONE), when, and how many ticks did something (the live view's).
var last_event: int = IGNORED
var last_event_ms: int = -100000
var events: int = 0


static func start(seed_value: int, p: SkinParams) -> SkinModel:
	var m: SkinModel = SkinModel.new()
	m.params = p
	m.rng_state = SkillRandom.seed_state(seed_value)
	m._draw_line()
	return m


static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


## The line, drawn from where the seed's stream stands.
func _draw_line() -> void:
	var p: SkinParams = params
	var n: int = maxi(2, p.points)
	px.resize(0)
	py.resize(0)
	seg_len.resize(0)
	rng_state = SkillRandom.next_u32(rng_state)
	var back: bool = (rng_state >> 8) % 2 == 1
	for k: int in n:
		var u: int = 100 + k * 800 / (n - 1)
		rng_state = SkillRandom.next_u32(rng_state)
		px.append(1000 - u if back else u)
		py.append(500 + (rng_state >> 8) % (2 * p.wobble + 1) - p.wobble)
	for k: int in n - 1:
		var dx: int = px[k + 1] - px[k]
		var dy: int = py[k + 1] - py[k]
		seg_len.append(maxi(1, isqrt(dx * dx + dy * dy)))
	seg = 0
	f = 0
	tears = 0


static func total_ticks(p: SkinParams) -> int:
	return p.duration_ms / TICK_MS


## Where the cut's end is now (hide units).
func tip() -> Vector2i:
	var dx: int = px[seg + 1] - px[seg]
	var dy: int = py[seg + 1] - py[seg]
	return Vector2i(px[seg] + dx * f / 1000, py[seg] + dy * f / 1000)


## The point `lead` along the line past the cut's tip (over a bend into the next stretch): where a hand keeping the
## cut's pace aims (the readout's players, the bots, the tests). Not a rule: nothing replayed reads it.
func ahead(lead: float) -> Vector2:
	var at: Vector2 = Vector2(tip())
	var left: float = lead
	var k: int = seg
	while left > 0.0 and k < px.size() - 1:
		var to: Vector2 = Vector2(px[k + 1], py[k + 1])
		var d: float = at.distance_to(to)
		if d >= left or k == px.size() - 2:
			return at + (to - at) * minf(1.0, left / maxf(d, 0.001))
		at = to
		left -= d
		k += 1
	return at


## How much of this line is cut, in thousandths.
func done_pm() -> int:
	return (seg * 1000 + f) / maxi(1, px.size() - 1)


## Whether the knife at (x, y) would cut here (on the line, near the tip), as a tick judges it.
func cuts_at(x: int, y: int) -> bool:
	var p: SkinParams = params
	var dx: int = px[seg + 1] - px[seg]
	var dy: int = py[seg + 1] - py[seg]
	var t: Vector2i = tip()
	var ex: int = x - t.x
	var ey: int = y - t.y
	if ex * ex + ey * ey > p.reach * p.reach:
		return false
	var cross: int = dx * (y - py[seg]) - dy * (x - px[seg])
	if cross * cross <= p.near * p.near * (dx * dx + dy * dy):
		return true
	if seg + 2 < px.size():
		var dx2: int = px[seg + 2] - px[seg + 1]
		var dy2: int = py[seg + 2] - py[seg + 1]
		var cross2: int = dx2 * (y - py[seg + 1]) - dy2 * (x - px[seg + 1])
		return cross2 * cross2 <= p.near * p.near * (dx2 * dx2 + dy2 * dy2)
	return false


## Whether (x, y) is on the next stretch (within `near` of its line) and past the bend into it (its dot over 0).
func _past_bend(x: int, y: int) -> bool:
	if seg + 2 >= px.size():
		return false
	var dx2: int = px[seg + 2] - px[seg + 1]
	var dy2: int = py[seg + 2] - py[seg + 1]
	var cross2: int = dx2 * (y - py[seg + 1]) - dy2 * (x - px[seg + 1])
	var dot2: int = dx2 * (x - px[seg + 1]) + dy2 * (y - py[seg + 1])
	return dot2 > 0 and cross2 * cross2 <= params.near * params.near * (dx2 * dx2 + dy2 * dy2)


## Run every tick that ends by `t_ms`.
func advance_to(t_ms: int) -> void:
	var total: int = total_ticks(params)
	while not over and (tick + 1) * TICK_MS <= t_ms and tick < total:
		_tick()
		tick += 1


func _tick() -> void:
	if not down:
		return
	var p: SkinParams = params
	if not cuts_at(kx, ky):
		tears += 1
		torn += 1
		_event(TORN)
		return
	var dx: int = px[seg + 1] - px[seg]
	var dy: int = py[seg + 1] - py[seg]
	var dot: int = dx * (kx - px[seg]) + dy * (ky - py[seg])
	var along: int = dot * 1000 / (dx * dx + dy * dy) if dot > 0 else 0
	if _past_bend(kx, ky):
		along = 1000   # on the next stretch, past the bend: the cut runs to the bend
	if along <= f:
		return
	f = mini(along, f + maxi(1, p.cut_speed * 1000 / seg_len[seg]))
	_event(CUT)
	if f < 1000:
		return
	if seg + 2 < px.size():
		seg += 1
		f = 0
		return
	worth += maxi(0, 1000 - tears * p.tear_pm)
	lines += 1
	if tears == 0:
		clean += 1
	down = false
	line += 1
	_event(LINE_DONE)
	_draw_line()


func _event(what: int) -> void:
	last_event = what
	last_event_ms = (tick + 1) * TICK_MS
	events += 1


## An input at `t_ms`: the knife in the hide at (x, y) (0..1000), or lifted (x = LIFT). Returns PRESSED, MOVED, LIFTED or
## IGNORED.
func press(t_ms: int, x: int, y: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	if t_ms < 0 or t_ms > params.duration_ms:
		return IGNORED
	advance_to(t_ms)
	if over:
		return IGNORED
	if x == LIFT:
		if not down:
			return IGNORED
		down = false
		return LIFTED
	if x < 0 or x > 1000 or y < 0 or y > 1000:
		return IGNORED
	kx = x
	ky = y
	if down:
		return MOVED
	down = true
	return PRESSED


## The round to its end: every tick run, a line part cut worth part of what was cut of it.
func finish() -> void:
	if finished:
		return
	finished = true
	advance_to(total_ticks(params) * TICK_MS)
	over = true
	worth += maxi(0, 1000 - tears * params.tear_pm) * done_pm() / 1000 * params.part_keep_pm / 1000


func score_pm() -> int:
	return mini(1000, worth / maxi(1, params.target_lines))


func result() -> Dictionary:
	return {"lines": lines, "clean": clean, "torn": torn, "worth": worth, "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, x, y) triples, in the order sent; run to its end.
static func play(seed_value: int, p: SkinParams, inputs: PackedInt32Array) -> Dictionary:
	var m: SkinModel = start(seed_value, p)
	var i: int = 0
	while i + 2 < inputs.size():
		m.press(inputs[i], inputs[i + 1], inputs[i + 2])
		i += 3
	m.finish()
	return m.result()
