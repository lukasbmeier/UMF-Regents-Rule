class_name PullModel extends RefCounted
## HERBALISM'S PULL THE ROOT (`HERBALISM_HUNTING_PREP.md` §3, Luke's H3, 2026-11-07; the trowel's work after his play,
## 2026-11-08). A PURE MODEL: its Rust twin is `genre::regents::pull`, the golden file `shared/golden/regents/pull.json`
## comes from a third copy (`game/regents/tests/make_skill_goldens.py`); change a rule in all three.
##
## A ROUND IS A CLUMP (Luke, 2026-11-08): stems pulled one after another until the time runs out; a snap loses the rest
## of that stem, never the round. In TICKS of 50 ms (tick k runs once every input before (k + 1) * 50 ms has been taken).
## EACH STEM, drawn from the seed's stream as it starts (the first at the start), for each of its `snags` side roots:
## its depth (side root k in its own stretch of the root, from 50 + k * (900 / snags), within 900 / snags), its jump
## (`jump_lo`..`jump_hi`), its side (LEFT or RIGHT). Both sides of the stem start PACKED (1000), unless `loose_pm`:
## then, from the soil's OWN stream (`seed ^ LOOSE_SALT`, so the side roots never change), the left side and then the
## right each start LOOSE (0) when the draw's (x >> 8) % 1000 is under `loose_pm` (Luke, 2026-11-09: no chore).
## A TICK: while a trowel stroke runs, or the button is up, the strain eases `strain_ease` (never below 0). Held: the
## strain rises `strain_rise`; the root comes up (`pull_rate` + strain x `pull_gain` / 1000), held back by the packed
## soil (x (1000 - the sides' mean pack x `hold_pm` / 1000) / 1000); every side root it has come up to (its depth or
## past) jumps the strain by its jump, in order. Past 1000 it SNAPS: worth `snap_keep_pm` of what came up (never over
## 1000). Else at 1000 or more it is up WHOLE (1000). A stem done, the next starts on the next tick (both sides packed,
## nothing up, no strain, its own side roots; the button and a stroke running stay as they were).
## A STROKE (LEFT 3, RIGHT 4) at t, unless one is still running (it runs `stroke_ms`, its ticks not pulled): the next
## side root, if on that side, within `show_depth` below what is up and some of the root up, is CUT (it never catches); else that side is
## DUG (its pack down `dig_pm`, never below 0); else nothing (a stroke into dug soil).
## AN INPUT (DOWN 1, UP 2, LEFT 3, RIGHT 4; a DOWN while down or an UP while up is nothing): before the last one, or
## outside 0..duration, is nothing. At the round's end a stem still in the ground is worth `snap_keep_pm` of what came up.
## THE SCORE: what the roots are worth (thousandths), over `target_plants`, never past 1000.

const TICK_MS: int = 50
const LOOSE_SALT: int = 0x6C6F6F73
const DOWN: int = 1
const UP: int = 2
const LEFT: int = 3
const RIGHT: int = 4
## What an input did, and what a tick did (the live game's look and sound).
const IGNORED: int = 0
const DONE: int = 1
const CAUGHT: int = 2
const WHOLE: int = 3
const SNAPPED: int = 4
const CUT: int = 5
const DUG: int = 6
const SCRAPED: int = 7

var params: PullParams
## The stem being pulled's side roots: how deep, how far each jumps the strain, which side (LEFT, RIGHT).
var snag_depth: PackedInt32Array = PackedInt32Array()
var snag_jump: PackedInt32Array = PackedInt32Array()
var snag_side: PackedInt32Array = PackedInt32Array()
var rng_state: int = 0
var soil_state: int = 0
## The next tick to run, whether the button is down, the stem being pulled (0 the first).
var tick: int = 0
var down: bool = false
var plant: int = 0
var strain: int = 0
## How much of the root is up (1000: all of it), the next side root on its way, how packed each side is (1000 packed).
var up_by: int = 0
var next_snag: int = 0
var pack_left: int = 1000
var pack_right: int = 1000
## A stroke runs until this time (ms) and through the ticks before `stroke_to_tick`.
var stroke_until_ms: int = 0
var stroke_to_tick: int = 0
var whole: int = 0
var snapped: int = 0
var caught: int = 0
var cut: int = 0
var dug: int = 0
## What the roots are worth so far (thousandths each).
var worth: int = 0
var over: bool = false
var finished: bool = false
var last_t_ms: int = -1
## The last thing a tick did (CAUGHT, WHOLE, SNAPPED) and when it ended, for the live view.
var last_event: int = IGNORED
var last_event_ms: int = -100000
var events: int = 0


static func start(seed_value: int, p: PullParams) -> PullModel:
	var m: PullModel = PullModel.new()
	m.params = p
	m.rng_state = SkillRandom.seed_state(seed_value)
	m._draw_snags()
	m.soil_state = SkillRandom.seed_state(seed_value ^ LOOSE_SALT)
	m._draw_soil()
	return m


## The stem's soil, from where the soil's stream stands: each side packed (1000) or loose (0), the left drawn first.
func _draw_soil() -> void:
	pack_left = 1000
	pack_right = 1000
	if params.loose_pm <= 0:
		return
	soil_state = SkillRandom.next_u32(soil_state)
	if (soil_state >> 8) % 1000 < params.loose_pm:
		pack_left = 0
	soil_state = SkillRandom.next_u32(soil_state)
	if (soil_state >> 8) % 1000 < params.loose_pm:
		pack_right = 0


## The stem's side roots, drawn from where the seed's stream stands.
func _draw_snags() -> void:
	var p: PullParams = params
	var seg: int = 900 / maxi(1, p.snags)
	snag_depth.resize(0)
	snag_jump.resize(0)
	snag_side.resize(0)
	for k: int in p.snags:
		rng_state = SkillRandom.next_u32(rng_state)
		snag_depth.append(50 + k * seg + (rng_state >> 8) % maxi(1, seg))
		rng_state = SkillRandom.next_u32(rng_state)
		snag_jump.append(p.jump_lo + (rng_state >> 8) % maxi(1, p.jump_hi - p.jump_lo + 1))
		rng_state = SkillRandom.next_u32(rng_state)
		snag_side.append(LEFT + (rng_state >> 8) % 2)


static func total_ticks(p: PullParams) -> int:
	return p.duration_ms / TICK_MS


## The side (LEFT, RIGHT) whose soil cracks: the root coming up (some of it up), the next side root within `show_depth`
## below what is up; else 0.
func showing() -> int:
	if over or up_by <= 0 or next_snag >= params.snags or snag_depth[next_snag] - up_by > params.show_depth:
		return 0
	return snag_side[next_snag]


## Whether a stroke is running at `t_ms`.
func stroking(t_ms: int) -> bool:
	return t_ms < stroke_until_ms


## How packed the soil round this stem is, on average (1000: packed, 0: dug round).
func pack() -> int:
	return (pack_left + pack_right) / 2


## Run every tick that ends by `t_ms`.
func advance_to(t_ms: int) -> void:
	var total: int = total_ticks(params)
	while not over and (tick + 1) * TICK_MS <= t_ms and tick < total:
		_tick()
		tick += 1


func _tick() -> void:
	var p: PullParams = params
	if not down or tick < stroke_to_tick:
		strain = maxi(0, strain - p.strain_ease)
		return
	strain += p.strain_rise
	up_by += (p.pull_rate + strain * p.pull_gain / 1000) * (1000 - pack() * p.hold_pm / 1000) / 1000
	while next_snag < p.snags and up_by >= snag_depth[next_snag]:
		strain += snag_jump[next_snag]
		next_snag += 1
		caught += 1
		_event(CAUGHT)
	if strain > 1000:
		worth += mini(up_by, 1000) * p.snap_keep_pm / 1000
		snapped += 1
		_event(SNAPPED)
		_next_plant()
	elif up_by >= 1000:
		worth += 1000
		whole += 1
		_event(WHOLE)
		_next_plant()


func _event(what: int) -> void:
	last_event = what
	last_event_ms = (tick + 1) * TICK_MS
	events += 1


func _next_plant() -> void:
	plant += 1
	_draw_snags()
	strain = 0
	up_by = 0
	next_snag = 0
	_draw_soil()


## An input at `t_ms`: DOWN, UP, LEFT or RIGHT. Returns DONE (the button), CUT, DUG, SCRAPED, or IGNORED.
func press(t_ms: int, code: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	if t_ms < 0 or t_ms > params.duration_ms:
		return IGNORED
	advance_to(t_ms)
	if over:
		return IGNORED
	if code == DOWN and not down:
		down = true
		return DONE
	if code == UP and down:
		down = false
		return DONE
	if (code == LEFT or code == RIGHT) and not stroking(t_ms):
		stroke_until_ms = t_ms + params.stroke_ms
		stroke_to_tick = stroke_until_ms / TICK_MS
		if showing() == code:
			next_snag += 1
			cut += 1
			return CUT
		if code == LEFT and pack_left > 0:
			pack_left = maxi(0, pack_left - params.dig_pm)
			dug += 1
			return DUG
		if code == RIGHT and pack_right > 0:
			pack_right = maxi(0, pack_right - params.dig_pm)
			dug += 1
			return DUG
		return SCRAPED
	return IGNORED


## The round to its end: every tick run, a stem still in the ground worth part of what came up of it.
func finish() -> void:
	if finished:
		return
	finished = true
	advance_to(total_ticks(params) * TICK_MS)
	over = true
	worth += mini(up_by, 1000) * params.snap_keep_pm / 1000


func score_pm() -> int:
	return mini(1000, worth / maxi(1, params.target_plants))


func result() -> Dictionary:
	return {"whole": whole, "snapped": snapped, "caught": caught, "cut": cut, "dug": dug, "worth": worth, "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, code) pairs, in the order sent; run to its end.
static func play(seed_value: int, p: PullParams, inputs: PackedInt32Array) -> Dictionary:
	var m: PullModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.press(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
