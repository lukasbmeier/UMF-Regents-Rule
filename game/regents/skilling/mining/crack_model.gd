class_name CrackModel extends RefCounted
## MINING'S MINIGAME, CRACK THE ROCK: FOLLOW THE SEAM (owner, 2026-10-19, replacing glowing weak points
## anywhere on the face). A seam runs across the rock as a faint crack outline: `notches` notches, the
## even seams top to bottom, the odd ones left to right, each notch wandering up to `bend_pm` across from
## the last. Strike the next notch (within `radius_pm`) and the crack opens to it; open the whole seam and
## the rock splits (`split_ms`), and the next seam begins. A strike anywhere else jars the pick: staggered
## for `stagger_ms`. A strike during a swing or a split is HELD (the latest one) and lands the moment it
## ends; one while staggered is lost.
##
## A PURE MODEL, like ChopModel: the seed, the rock's `CrackParams` and the strikes (time, x, y) decide
## the round, so the server replays it (`genre::regents::crack`, held to the same golden file:
## `game/regents/tests/make_skill_goldens.py`). The live minigame plays through `strike()`.

const IGNORED: int = 0   # outside the round, out of order, staggered, off the face
const HIT: int = 1       # on the next notch: the crack opens
const JAR: int = 2       # off the seam: staggered
const HELD: int = 3      # mid-swing or mid-split: held, and struck the moment it ends

var params: CrackParams
## Every notch of every seam, flat (x, y) in thousandths, seam after seam.
var points: PackedInt32Array
## The next notch to strike (counting every seam's).
var k: int = 0
var hits: int = 0
var jars: int = 0
var combo: int = 0
var best_combo: int = 0
## Seams opened end to end: the rock split.
var splits: int = 0
var next_ok_ms: int = 0
var last_t_ms: int = -1
var staggered: bool = false
var held: bool = false
var held_at_ms: int = 0
var held_x: int = 0
var held_y: int = 0
## Strikes landed, counted, and the latest's outcome, time and place: the live view follows these.
var acts: int = 0
var last_act: int = IGNORED
var last_act_ms: int = 0
var last_act_at: Vector2i = Vector2i.ZERO


static func start(seed_value: int, p: CrackParams) -> CrackModel:
	var m: CrackModel = CrackModel.new()
	m.params = p
	m.points = seams(seed_value, p, seam_count(p))
	return m


## Enough seams for any round: one notch a swing.
static func seam_count(p: CrackParams) -> int:
	return (p.duration_ms / p.swing_ms + 1) / p.notches + 2


## `count` seams' notches from the seed, flat (x, y). A prefix does not depend on `count`.
static func seams(seed_value: int, p: CrackParams, count: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var lo: int = p.margin_pm
	var hi: int = 1000 - p.margin_pm
	var span: int = maxi(0, hi - lo)
	var st: int = SkillRandom.seed_state(seed_value)
	for s: int in count:
		st = SkillRandom.next_u32(st)
		var across: int = lo + (st >> 8) % (span + 1)
		for i: int in p.notches:
			var along: int = lo + span * i / (p.notches - 1)
			if i > 0:
				st = SkillRandom.next_u32(st)
				across = clampi(across + (st >> 8) % (2 * p.bend_pm + 1) - p.bend_pm, lo, hi)
			if s % 2 == 0:
				out.append(across)
				out.append(along)
			else:
				out.append(along)
				out.append(across)
	return out


## Notch `i` (counting every seam's) as a place.
func notch(i: int) -> Vector2i:
	var j: int = (i % (points.size() / 2)) * 2
	return Vector2i(points[j], points[j + 1])


## The seam notch `i` is on, and its place along that seam.
func seam_of(i: int) -> int:
	return i / params.notches


## A strike at `t_ms` on (x, y). Returns what it did.
func strike(t_ms: int, x: int, y: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	settle(t_ms)
	if t_ms < 0 or t_ms > params.duration_ms:
		return IGNORED
	if x < 0 or x > 1000 or y < 0 or y > 1000:
		return IGNORED
	if t_ms < next_ok_ms:
		if staggered:
			return IGNORED
		held = true
		held_at_ms = next_ok_ms
		held_x = x
		held_y = y
		return HELD
	return _strike(t_ms, x, y)


## Land a held strike whose swing or split ended by `t_ms`. Returns what it did (IGNORED: none landed).
func settle(t_ms: int) -> int:
	if not held or held_at_ms > t_ms:
		return IGNORED
	held = false
	if held_at_ms > params.duration_ms:
		return IGNORED
	return _strike(held_at_ms, held_x, held_y)


## The round to its end: a strike still held lands if its swing ends in time.
func finish() -> void:
	settle(params.duration_ms)


func _strike(t_ms: int, x: int, y: int) -> int:
	acts += 1
	last_act_ms = t_ms
	last_act_at = Vector2i(x, y)
	var at: Vector2i = notch(k)
	var dx: int = x - at.x
	var dy: int = y - at.y
	if dx * dx + dy * dy <= params.radius_pm * params.radius_pm:
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		k += 1
		staggered = false
		if k % params.notches == 0:
			splits += 1
			next_ok_ms = t_ms + maxi(params.swing_ms, params.split_ms)
		else:
			next_ok_ms = t_ms + params.swing_ms
		last_act = HIT
		return HIT
	jars += 1
	combo = 0
	next_ok_ms = t_ms + params.stagger_ms
	staggered = true
	last_act = JAR
	return JAR


func score_pm() -> int:
	return mini(1000, hits * 1000 / params.target_hits)


func result() -> Dictionary:
	return {"hits": hits, "jars": jars, "best_combo": best_combo, "splits": splits, "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, x, y) triples, in the order sent.
static func play(seed_value: int, p: CrackParams, inputs: PackedInt32Array) -> Dictionary:
	var m: CrackModel = start(seed_value, p)
	var i: int = 0
	while i + 2 < inputs.size():
		m.strike(inputs[i], inputs[i + 1], inputs[i + 2])
		i += 3
	m.finish()
	return m.result()
