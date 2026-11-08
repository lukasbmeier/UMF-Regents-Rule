class_name BeatModel extends RefCounted
## SMELTING AS A RHYTHM TRACK (Luke, 2026-11-07: "Full rhythm track"), then the pour. A PURE MODEL: its Rust twin is
## `genre::regents::beat`, the golden file `shared/golden/regents/beat.json` comes from a third copy
## (`game/regents/tests/make_skill_goldens.py`); change a rule in all three.
##
## THE TRACK, from the seed: the mold's line is drawn first; then, for each beat i, three draws (rest, off-beat,
## draw), always all three. Beat i is at (lead_beats + i) * beat_ms. Its note is there unless the beat is a rest
## (never a bar's first, i % 4 == 0) or inside a long draw (a draw started at beat j covers beats j..j + hold_beats:
## its end beat has no note, the release is there). A beat's note is a DRAW (start and end) when its roll says so
## and it ends by the last beat. An OFF-BEAT note half a beat later when its roll says so and no draw covers it
## (a draw's end beat may have one).
##
## A PRESS (DOWN, code 1; UP, code 2; one button: a second DOWN while down, or an UP while up, is ignored):
## - On the track (before the track's end): a DOWN meets the earliest note not yet played within `good_ms` of it:
##   within `perfect_ms` full value (1000), else `good_pm`. A DRAW is paid when let go: in full when let go no sooner
##   than `good_ms` before its end (or held through it), else for the share of it held. A DOWN that meets no note is
##   a STRAY: `stray_pm` off the track's total.
## - In the pour (from the track's end): a DOWN from `pour_ready_ms` in tilts the crucible, an UP stops it; the mold
##   fills `pour_rate` each 50 ms tick it pours, ticks counted from the track's end, run whole as in `SmeltModel`.
## A press out of order (before the last one) or outside 0..duration is ignored. A note never played is missed (0).
## THE SCORE: the track (points less strays, over the notes, 0-1000) and the pour (as `SmeltModel`), weighted
## `track_weight_pct`; with no pour, the track alone.

const TICK_MS: int = 50
const DOWN: int = 1
const UP: int = 2
## The second button: skims a slag note (a round with no slag ignores it).
const SKIM: int = 3
## What a press did (for the live game's look and sound).
const IGNORED: int = 0
const PERFECT: int = 1
const GOOD: int = 2
const STRAY: int = 3
const RELEASED: int = 4
const POUR: int = 5
const STOP: int = 6
## The slag notes' own stream: the seed folded with this ("slag"), one draw a note.
const SLAG_SALT: int = 0x736C6167

var params: BeatParams
var target: int = 0
## The notes: their times and their ends (a tap's end is its time), in order.
var note_t: PackedInt32Array = PackedInt32Array()
var note_end: PackedInt32Array = PackedInt32Array()
## Which notes are slag (1): skimmed, never pumped (band 2's test).
var slag: PackedByteArray = PackedByteArray()
## What each note earned (-1: not played yet), and how it was hit (PERFECT, GOOD; 0 not hit).
var got: PackedInt32Array = PackedInt32Array()
var hit: PackedInt32Array = PackedInt32Array()
var down: bool = false
## The draw being held (-1: none), and what its press earned.
var holding: int = -1
var hold_pts: int = 0
var strays: int = 0
## The pour: the next tick to run, the fill, whether it pours now, whether it ever did.
var pour_tick: int = 0
var fill: int = 0
var pouring: bool = false
var poured: bool = false
var last_t_ms: int = -1


static func start(seed_value: int, p: BeatParams) -> BeatModel:
	var m: BeatModel = BeatModel.new()
	m.params = p
	var st: int = SkillRandom.next_u32(SkillRandom.seed_state(seed_value))
	m.target = p.target_lo + (st >> 8) % maxi(1, p.target_hi - p.target_lo + 1)
	var covered: int = -1   # the last beat a draw covers
	for i: int in p.beats:
		st = SkillRandom.next_u32(st)
		var r_rest: int = (st >> 8) % 1000
		st = SkillRandom.next_u32(st)
		var r_off: int = (st >> 8) % 1000
		st = SkillRandom.next_u32(st)
		var r_hold: int = (st >> 8) % 1000
		var on_t: int = (p.lead_beats + i) * p.beat_ms
		if i > covered and not (i % 4 != 0 and r_rest < p.rest_pm):
			if p.hold_beats > 0 and r_hold < p.hold_pm and i + p.hold_beats <= p.beats - 1:
				m._add(on_t, on_t + p.hold_beats * p.beat_ms)
				covered = i + p.hold_beats
			else:
				m._add(on_t, on_t)
		if i >= covered and r_off < p.offbeat_pm:
			m._add(on_t + p.beat_ms / 2, on_t + p.beat_ms / 2)
	m.slag.resize(m.note_t.size())
	if p.slag_pm > 0:
		var sst: int = SkillRandom.seed_state(seed_value ^ SLAG_SALT)
		for j: int in m.note_t.size():
			sst = SkillRandom.next_u32(sst)
			m.slag[j] = 1 if (sst >> 8) % 1000 < p.slag_pm and m.note_end[j] == m.note_t[j] else 0
	return m


func _add(t: int, end: int) -> void:
	note_t.append(t)
	note_end.append(end)
	got.append(-1)
	hit.append(0)


## When the track ends and the pour begins.
static func track_end_ms(p: BeatParams) -> int:
	return (p.lead_beats + p.beats) * p.beat_ms


static func duration_ms(p: BeatParams) -> int:
	return track_end_ms(p) + p.pour_ms


func on_track(t_ms: int) -> bool:
	return t_ms < track_end_ms(params)


## Whether the crucible may tilt at `t_ms`.
func pour_ready(t_ms: int) -> bool:
	return t_ms >= track_end_ms(params) + params.pour_ready_ms


## Run time on to `t_ms`: a draw held to its end is paid; every pour tick that ends by then runs.
func advance_to(t_ms: int) -> void:
	if holding >= 0 and t_ms >= note_end[holding]:
		got[holding] = hold_pts
		holding = -1
	var end: int = track_end_ms(params)
	var ticks: int = params.pour_ms / TICK_MS
	while pour_tick < ticks and end + (pour_tick + 1) * TICK_MS <= t_ms:
		if pouring:
			fill += params.pour_rate
		pour_tick += 1


## A press at `t_ms`: DOWN or UP. Returns what it did.
func press(t_ms: int, code: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	if t_ms < 0 or t_ms > duration_ms(params):
		return IGNORED
	advance_to(t_ms)
	if code == DOWN:
		if down:
			return IGNORED
		down = true
		if not on_track(t_ms):
			if pouring or not pour_ready(t_ms):
				return IGNORED
			pouring = true
			poured = true
			return POUR
		for j: int in note_t.size():
			if got[j] < 0 and j != holding and slag[j] == 0 and absi(t_ms - note_t[j]) <= params.good_ms:
				var perfect: bool = absi(t_ms - note_t[j]) <= params.perfect_ms
				var pts: int = 1000 if perfect else params.good_pm
				hit[j] = PERFECT if perfect else GOOD
				if note_end[j] > note_t[j]:
					holding = j
					hold_pts = pts
				else:
					got[j] = pts
				return hit[j]
		strays += 1
		return STRAY
	if code == SKIM:
		if not on_track(t_ms) or params.slag_pm <= 0:
			return IGNORED
		for j: int in note_t.size():
			if got[j] < 0 and slag[j] == 1 and absi(t_ms - note_t[j]) <= params.good_ms:
				var perfect_skim: bool = absi(t_ms - note_t[j]) <= params.perfect_ms
				got[j] = 1000 if perfect_skim else params.good_pm
				hit[j] = PERFECT if perfect_skim else GOOD
				return hit[j]
		strays += 1
		return STRAY
	if code == UP:
		if not down:
			return IGNORED
		down = false
		if pouring:
			pouring = false
			return STOP
		if holding >= 0:
			var j: int = holding
			holding = -1
			if t_ms >= note_end[j] - params.good_ms:
				got[j] = hold_pts
			else:
				got[j] = hold_pts * maxi(0, t_ms - note_t[j]) / maxi(1, note_end[j] - note_t[j])
			return RELEASED
	return IGNORED


## The round to its end.
func finish() -> void:
	advance_to(duration_ms(params))


## The next note not yet played whose window has not passed at `t_ms` (-1: none): what a player aims at.
func next_note(t_ms: int) -> int:
	for j: int in note_t.size():
		if got[j] < 0 and j != holding and t_ms <= note_t[j] + params.good_ms:
			return j
	return -1


## Whether note `j` is slag (skimmed with the second button).
func is_slag(j: int) -> bool:
	return j >= 0 and j < slag.size() and slag[j] == 1


## How the track has gone so far at `t_ms` (0-1000): what each note passed earned, over the notes passed (what
## the furnace's fire shows). Presentation only; 500 before any note has passed.
func heat_now(t_ms: int) -> int:
	var n: int = 0
	var sum: int = 0
	for j: int in note_t.size():
		if got[j] >= 0:
			sum += got[j]
			n += 1
		elif j != holding and t_ms > note_t[j] + params.good_ms:
			n += 1
	return 500 if n == 0 else clampi((sum - strays * params.stray_pm) / n, 0, 1000)


func track_score() -> int:
	var sum: int = 0
	for j: int in note_t.size():
		sum += maxi(0, got[j])
	return clampi((sum - strays * params.stray_pm) / maxi(1, note_t.size()), 0, 1000)


func pour_score() -> int:
	if fill > 1000:
		return 0
	return maxi(0, 1000 - absi(fill - target) * 1000 / params.pour_tolerance)


func score_pm() -> int:
	var w: int = params.track_weight_pct if params.pour_ms > 0 else 100
	return (track_score() * w + pour_score() * (100 - w)) / 100


func result() -> Dictionary:
	var perfect: int = 0
	var good: int = 0
	for h: int in hit:
		perfect += int(h == PERFECT)
		good += int(h == GOOD)
	return {"notes": note_t.size(), "perfect": perfect, "good": good, "strays": strays, "fill": fill, "target": target,
		"track_pm": track_score(), "pour_pm": pour_score(), "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, code) pairs, in the order sent; run to its end.
static func play(seed_value: int, p: BeatParams, inputs: PackedInt32Array) -> Dictionary:
	var m: BeatModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.press(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
