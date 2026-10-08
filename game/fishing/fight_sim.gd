class_name FightSim extends RefCounted
## GENRE CODE. THE FIGHT — Fishing for Compliments' "THE PUMP" — and the twin of
## `server/src/genre/fight.rs`, which the module REPLAYS a submitted fight through to decide what
## really happened. Read that file's header for the design; this one is held to it bit for bit.
##
## PUMP (the cast button) held LOADS the rod; let go and the pump resolves, graded against the
## catch's SWEET BAND, into SLACK; slack becomes line only while the reel is worked (the crank).
## GIVE (the other button) is the release valve, the answer to a run. Overloading past the band
## breaks the line — except on a snag, where heaving is the only way out.
##
## PARITY RULES, and they are not optional (DECISIONS #140). Break one and the client lands
## catches the server says it snapped:
##   - every value is a GDScript float (f64) and every operation is in the Rust file's ORDER —
##     `a * b * c` is `(a * b) * c` on both sides, and a reordering is a different number;
##   - min, max, clamp, lerp and move_toward are the helpers at the bottom of this file, written
##     as Godot defines them, never the built-ins (whose Rust namesakes differ at -0.0);
##   - randomness is the xorshift32 below, never RandomNumberGenerator;
##   - time is `tick()`, one fixed step of 1 / TICK_HZ, never the frame's delta;
##   - `shared/golden/fishing/fight.json` pins every field at checkpoints through scripted fights,
##     and `tests/suites/fight.gd` replays it at max_err = 0.
##
## Beyond the twin: signals for presentation (they change nothing), and read-outs for the HUD.

signal pumped(grade: Grade, metres: float)
signal run_started()
signal snagged()
signal snag_freed()

enum State { FIGHTING, LANDED, SNAPPED }
enum Behavior { HOLDING, RUNNING, RESTING, SNAGGED }
enum Grade { EARLY, GOOD, PERFECT, LATE }

const PATH: String = "res://shared/fishing/fight.json"
## Largest number of runs a submitted log may carry (`MAX_RUNS` in fight.rs).
const MAX_RUNS: int = 4096

## Every tunable the fight reads (FightParams in fight.rs). `params_for` fills one in.
class Params extends RefCounted:
	var distance_rate: float
	var give_factor_idle: float
	var give_factor_dead: float
	var cast_to_fight: float
	var fight_min_m: float
	var fight_max_m: float
	var spent_power_floor: float
	var spent_wind_penalty: float
	var drag_setting: float
	var tension_response: float
	var tension_release: float
	var drag_slip: float
	var slip_metres: float
	var drag_slip_max: float
	var shock_gain: float
	var shock_threshold: float
	var snap_grace_seconds: float
	var snap_tension: float
	var overload_fatigue: float
	var fatigue_recover: float
	var bare_reel_fraction: float
	var bare_reel_tension: float
	var spent_reel_fraction: float
	var rest_reel_fraction: float
	var spent_reel_strain: float
	var run_reel_strain: float
	var pull_response: float
	var load_rate: float
	var load_slow_start: float
	var band_approach_s: float
	var overload_limit: float
	var pump_recover: float
	var snag_load_transfer: float
	var snag_break_load: float
	var pump_metres: float
	var weak_yield: float
	var perfect_yield: float
	var perfect_fraction: float
	var load_to_tension: float
	var release_dump: float
	var overload_tension: float
	var pump_stress: float
	var stress_settle: float
	var pump_stamina_mult: float
	var crank_window: float
	var crank_rate: float
	var lateral_speed: float
	var lateral_range: float
	var lateral_run_mult: float
	var wander_min: float
	var wander_max: float
	var give_tension_relief: float
	var give_run_damping: float
	var run_take: float
	var shake_per_pump: float
	var shake_decay: float
	var hitstop_perfect: float
	var hitstop_snag_free: float
	var perfect_drag_bonus: float
	var late_start_tension: float
	var clean_catch_max_peak_tension: float
	var deadlift_load_mult: float
	var deadlift_creep: float
	var perfect_set: bool = false
	var late_set: bool = false
	var deadlift: bool = false

## What a hooked thing IS in a fight (Profile in fight.rs).
class Profile extends RefCounted:
	var alive: bool
	var distance_scale: float
	var hold_force: float
	var run_power: float
	var rest_force: float
	var band_centre: float
	var band_width: float
	var band_centre_spent: float
	var band_width_spent: float
	var pump_yield: float
	var panic_gain: float
	var burst_drain: float
	var burst_regen: float
	var burst_recover: float
	var stamina_drain: float
	var never_tires: bool
	var dead_load: float
	var snag_interval_min: float
	var snag_interval_max: float
	var snag_duration: float
	var snag_load: float

var params: Params
var profile: Profile
var state: State = State.FIGHTING
var behavior: Behavior = Behavior.HOLDING
var distance: float = 0.0
var start_distance: float = 0.0
## The cast's real range, for showing: `start_distance` is the fight's length, which is not the
## same number (`fight_length`). Nothing in the simulation reads it.
var cast_range_m: float = 0.0
var tension: float = 0.0
## How far the rod is loaded, 0..overload_limit: THE number the player dials.
var load: float = 0.0
var band_lo: float = 0.0
var band_hi: float = 0.0
var slack: float = 0.0
var fatigue: float = 0.0
var overloading: bool = false
var crank_left: float = 0.0
var lateral: float = 0.0
var combo: int = 0
var best_combo: int = 0
var shake: float = 0.0
var hitstop: float = 0.0
var stress: float = 0.0
var burst: float = 1.0
var stamina: float = 1.0
var elapsed: float = 0.0
var peak_tension: float = 0.0
var distance_lost: float = 0.0
var pumps_good: int = 0
var pumps_total: int = 0
var runs: int = 0
var giving: bool = false
## The last pump's grade, or -1 before the first.
var last_grade: int = -1
## Ticks consumed, hit-stop included.
var ticks: int = 0

var _pull: float = 0.0
var _pull_prev: float = 0.0
var _deadlift_floor: float = 0.0
var _over_limit_time: float = 0.0
var _snag_at: float = 0.0
var _snag_until: float = 0.0
var _recover_until: float = 0.0
var _was_loading: bool = false
var _armed: bool = false
var _bare_pull: float = 0.0
var _lat_target: float = 0.0
var _lat_timer: float = 0.0
var _overload_time: float = 0.0
var _rng: int = 0

static var _doc: Dictionary = {}


# =============================================================================================
# DATA: shared/fishing/fight.json, and the gear from shared/fishing/fishing.json
# =============================================================================================

static func doc() -> Dictionary:
	if _doc.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary:
			push_error("FightSim: %s is missing or malformed" % PATH)
			return _doc
		_doc = parsed as Dictionary
	return _doc


static func tick_hz() -> int:
	return int(doc().get("tick_hz", 60))


## The fixed step, 1 / TICK_HZ.
static func dt() -> float:
	return 1.0 / float(tick_hz())


## The most ticks the module replays (`max_ticks` in fight.rs).
static func max_ticks() -> int:
	return int(float(doc().get("max_fight_s", 120.0)) * float(tick_hz()))


## The file's numbers, before gear.
static func base_params() -> Params:
	var p := Params.new()
	var src: Dictionary = doc().get("params", {}) as Dictionary
	for k: String in src:
		p.set(k, float(src[k]))
	return p


## The fight's numbers for this cast: the gear multiplies the tuned defaults — the ROD how much
## line a pump lifts, the REEL how fast the crank takes slack, the LINE where it snaps — and the
## hook-set and the deadlift ride along. Exactly `params_for` in fight.rs.
static func params_for(rod: int, reel: int, line: int, hookset: FishingData.HookSet, deadlift: bool) -> Params:
	var p: Params = base_params()
	p.snap_tension = float(FishingData.gear("line", line).get("tension_ceiling", 100.0)) / 100.0
	p.crank_rate = p.crank_rate * float(FishingData.gear("reel", reel).get("reel_speed", 1.0))
	p.pump_metres = p.pump_metres * float(FishingData.gear("rod", rod).get("reel_power", 1.0))
	p.perfect_set = hookset == FishingData.HookSet.PERFECT
	p.late_set = hookset == FishingData.HookSet.LATE
	p.deadlift = deadlift
	return p


## How much line a cast `range_m` out puts between the angler and a catch whose
## `distance_scale` is 1: THE CAST IS THE FIGHT LENGTH, within the range the fight was tuned for.
## Exactly `fight_length` in fight.rs.
static func fight_length(p: Params, range_m: float) -> float:
	return _clamp(range_m * p.cast_to_fight, p.fight_min_m, p.fight_max_m)


## A catch's fight profile, or null for a key the file does not have.
static func profile_of(catch_key: String) -> Profile:
	var src: Dictionary = (doc().get("profiles", {}) as Dictionary).get(catch_key, {}) as Dictionary
	if src.is_empty():
		return null
	var p := Profile.new()
	for k: String in src:
		var v: Variant = src[k]
		p.set(k, bool(v) if v is bool else float(v))
	return p


# =============================================================================================
# THE FIGHT
# =============================================================================================

## A fight against `p_profile` from a cast `p_cast_m` out. `pump_held`: the button is still down
## from the click that set the hook, and must be let go once before it loads the rod.
func _init(p_params: Params, p_profile: Profile, seed: int, p_cast_m: float, pump_held: bool) -> void:
	params = p_params
	profile = p_profile
	cast_range_m = p_cast_m
	start_distance = fight_length(params, p_cast_m) * profile.distance_scale
	distance = start_distance
	tension = params.late_start_tension if params.late_set else 0.0
	peak_tension = tension
	_armed = not pump_held
	_rng = seed & 0xFFFFFFFF
	if _rng == 0:
		_rng = 0x9E3779B9
	_update_band()
	_pull = _target_pull()
	_pull_prev = _pull
	_schedule_snag()


func _next_u32() -> int:
	var x: int = _rng
	x = x ^ ((x << 13) & 0xFFFFFFFF)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & 0xFFFFFFFF)
	_rng = x
	return x


func _randf_range(from: float, to: float) -> float:
	var u: float = float(_next_u32() >> 8) / 16777216.0
	return from + (to - from) * u


func _schedule_snag() -> void:
	_snag_at = elapsed + _randf_range(profile.snag_interval_min, profile.snag_interval_max)


## One fixed step. `loading`: PUMP held. `giving_now`: GIVE held. `crank`: 0..255.
func tick(loading: bool, giving_now: bool, crank_q: int) -> void:
	if state != State.FIGHTING:
		return
	ticks += 1
	var delta: float = dt()
	if hitstop > 0.0:
		hitstop = _max(hitstop - delta, 0.0)
		return
	var crank: float = float(crank_q) / 255.0
	elapsed += delta
	shake = _max(shake - params.shake_decay * delta, 0.0)
	_step_pump(delta, loading, giving_now)
	_step_crank(delta, crank)
	if _check_landed():
		return
	if profile.alive:
		_step_alive(delta)
	else:
		_step_dead(delta)
	_update_band()
	_step_wander(delta)
	_step_pull(delta)
	_step_line(delta, giving_now)
	_step_drift(delta, giving_now)
	peak_tension = _max(peak_tension, tension)
	_check_snap(delta)
	_check_landed()


func _check_landed() -> bool:
	if state == State.FIGHTING and distance <= 0.0:
		distance = 0.0
		state = State.LANDED
	return state != State.FIGHTING


func _step_pump(delta: float, loading: bool, giving_now: bool) -> void:
	overloading = false
	if not _armed:
		if not loading:
			_armed = true
		_was_loading = false
		giving = giving_now
		return
	var can_load: bool = loading and not giving_now and slack <= 0.001 and elapsed >= _recover_until
	if can_load:
		var reach: float = band_hi if band_hi > 0.0 else 1.0
		var ramp: float = _clamp(load / _max(reach, 0.05), 0.0, 1.0)
		var rate: float = params.load_rate * _lerp(params.load_slow_start, 1.0, ramp)
		# THE YELLOW: from the band's edge to the sweet spot, never faster than band_approach_s.
		if params.band_approach_s > 0.0 and band_hi > band_lo and load >= band_lo:
			var sweet: float = _perfect_lo()
			if load < sweet:
				rate = _min(rate, (sweet - band_lo) / params.band_approach_s)
		load = _min(load + rate * delta, params.overload_limit)
		if behavior == Behavior.SNAGGED:
			_overload_time += delta
			if load >= params.snag_break_load:
				_free_snag()
		elif load > band_hi:
			overloading = true
			fatigue = _min(fatigue + params.overload_fatigue * delta, params.snap_tension)
			_overload_time += delta
			var over: float = (load - band_hi) if band_hi > 0.0 else load * 0.4
			tension += params.overload_tension * over * delta
			if band_hi > 0.0 and _overload_time > 0.25:
				_overload_time = 0.0
	elif _was_loading and load > 0.0:
		_resolve_pump()
	_was_loading = can_load
	giving = giving_now


func _resolve_pump() -> void:
	var quality: float = _pump_quality(load)
	var grade: Grade = grade_at(load)
	var yield_m: float = params.pump_metres * profile.pump_yield * quality
	slack += yield_m
	crank_left = params.crank_window
	pumps_total += 1
	if grade == Grade.PERFECT:
		pumps_good += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		hitstop = params.hitstop_perfect
	else:
		combo = 0
	shake = _min(shake + params.shake_per_pump * (0.4 + quality), 1.5)
	if profile.alive and behavior != Behavior.RUNNING:
		stress = _clamp(stress + params.pump_stress * load, 0.0, 1.0)
	if not profile.never_tires:
		stamina = _max(stamina - profile.stamina_drain * load * params.pump_stamina_mult, 0.0)
	tension = _max(tension - params.release_dump * 0.35, 0.0)
	load = 0.0
	_overload_time = 0.0
	_recover_until = elapsed + params.pump_recover
	last_grade = grade
	pumped.emit(grade, yield_m)


func _step_wander(delta: float) -> void:
	if not profile.alive:
		lateral = _move_toward(lateral, 0.0, delta * 0.6)
		return
	_lat_timer -= delta
	if _lat_timer <= 0.0:
		_lat_target = _randf_range(-1.0, 1.0)
		_lat_timer = _randf_range(params.wander_min, params.wander_max)
	var speed: float = params.lateral_speed
	if behavior == Behavior.RUNNING:
		speed *= params.lateral_run_mult
	lateral = _move_toward(lateral, _lat_target, speed * delta)


## Winding with nothing on offer (`step_bare_reel` in fight.rs): it pays when the fish is spent
## or resting, barely against a fresh one, and not at all against a run — which it only loads.
func _step_bare_reel(delta: float, crank: float) -> void:
	_bare_pull = 0.0
	if crank <= 0.01 or distance <= 0.0 or giving:
		return
	if behavior == Behavior.RUNNING:
		_bare_pull = crank * params.bare_reel_tension * params.run_reel_strain
		return
	if tension > effective_drag():
		return
	distance = _max(distance - crank * params.crank_rate * bare_reel_win() * delta, 0.0)
	_bare_pull = crank * params.bare_reel_tension * _lerp(1.0, params.spent_reel_strain, worn())
	shake = _min(shake + crank * 0.2 * delta, 1.2)


## 0 fresh .. 1 spent, as far as winding is concerned: a resting fish counts as spent, dead
## weight and a catch that never tires never are.
func worn() -> float:
	if not profile.alive or profile.never_tires:
		return 0.0
	if behavior == Behavior.RESTING:
		return 1.0
	return 1.0 - stamina


## The share of the crank rate a bare reel wins right now (running: none).
func bare_reel_win() -> float:
	if behavior == Behavior.RUNNING:
		return 0.0
	if behavior == Behavior.RESTING and profile.alive and not profile.never_tires:
		return params.rest_reel_fraction
	return _lerp(params.bare_reel_fraction, params.spent_reel_fraction, worn())


func _step_crank(delta: float, crank: float) -> void:
	if crank_left <= 0.0:
		_step_bare_reel(delta, crank)
		return
	_bare_pull = 0.0
	crank_left -= delta
	if slack > 0.0 and crank > 0.01:
		var taken: float = _min(crank * params.crank_rate * delta, slack)
		distance = _max(distance - taken, 0.0)
		slack -= taken
		shake = _min(shake + crank * 0.5 * delta, 1.2)
	if slack <= 0.001:
		slack = 0.0
		crank_left = 0.0
	elif crank_left <= 0.0:
		slack = 0.0


func _pump_quality(at: float) -> float:
	if at < band_lo:
		return params.weak_yield * (at / _max(band_lo, 0.001))
	if at <= band_hi:
		return params.perfect_yield if is_perfect(at) else 1.0
	return _max(1.0 - (at - band_hi) * 2.4, params.weak_yield)


## How a release at `at` would grade right now.
func grade_at(at: float) -> Grade:
	if band_hi <= band_lo:
		return Grade.LATE
	if at < band_lo:
		return Grade.EARLY
	if at > band_hi:
		return Grade.LATE
	return Grade.PERFECT if is_perfect(at) else Grade.GOOD


func is_perfect(at: float) -> bool:
	var half: float = (band_hi - band_lo) * params.perfect_fraction * 0.5
	var mid: float = (band_lo + band_hi) * 0.5
	return at >= mid - half and at <= mid + half


## Where the sweet spot starts: `is_perfect`'s lower edge, computed the same way.
func _perfect_lo() -> float:
	var half: float = (band_hi - band_lo) * params.perfect_fraction * 0.5
	var mid: float = (band_lo + band_hi) * 0.5
	return mid - half


func _update_band() -> void:
	var tired: float = 1.0 if profile.never_tires else stamina
	var centre: float = _lerp(profile.band_centre_spent, profile.band_centre, tired)
	var width: float = _lerp(profile.band_width_spent, profile.band_width, tired)
	if behavior == Behavior.RUNNING or behavior == Behavior.SNAGGED:
		centre = 0.0
		width = 0.0
	band_lo = _max(centre - width * 0.5, 0.0)
	band_hi = _max(centre + width * 0.5, 0.0)


func _free_snag() -> void:
	behavior = Behavior.HOLDING
	_schedule_snag()
	_overload_time = 0.0
	load = 0.0
	shake = 1.4
	hitstop = params.hitstop_snag_free
	tension = _max(tension - 0.25, 0.0)
	snag_freed.emit()


func _step_drift(delta: float, giving_now: bool) -> void:
	if behavior == Behavior.SNAGGED:
		return
	var take: float = _pull * params.distance_rate * params.give_factor_idle
	if behavior == Behavior.RUNNING:
		take = params.run_take
		if giving_now:
			take *= params.give_run_damping
	elif not profile.alive:
		take = _pull * params.distance_rate * params.give_factor_dead
	distance += take * delta
	distance_lost += take * delta


func _step_alive(delta: float) -> void:
	var wind_regen: float = profile.burst_regen / _lerp(params.spent_wind_penalty, 1.0, stamina)
	match behavior:
		Behavior.RUNNING:
			burst -= profile.burst_drain * delta
			if burst <= 0.0:
				burst = 0.0
				behavior = Behavior.RESTING
				stress = 0.0
		Behavior.RESTING:
			burst = _min(burst + wind_regen * delta, 1.0)
			stress = _max(stress - profile.panic_gain * delta, 0.0)
			if burst >= profile.burst_recover:
				behavior = Behavior.HOLDING
		_:
			if stress >= 1.0 and burst > 0.25 and (stamina > 0.0 or profile.never_tires):
				behavior = Behavior.RUNNING
				runs += 1
				shake = 1.2
				run_started.emit()
			else:
				stress = _max(stress - params.stress_settle * delta, 0.0)
			burst = _min(burst + wind_regen * 0.5 * delta, 1.0)


func _step_dead(_delta: float) -> void:
	if behavior == Behavior.SNAGGED:
		if elapsed >= _snag_until:
			behavior = Behavior.HOLDING
			_schedule_snag()
		return
	if elapsed >= _snag_at:
		behavior = Behavior.SNAGGED
		_snag_until = elapsed + profile.snag_duration
		snagged.emit()


func _step_pull(delta: float) -> void:
	var target: float = _target_pull()
	_pull = _move_toward(_pull, target, params.pull_response * delta)


func _target_pull() -> float:
	var f: float = profile.dead_load
	if behavior == Behavior.SNAGGED:
		return f + profile.snag_load
	if not profile.alive:
		return f
	var tired: float = 1.0 if profile.never_tires else stamina
	var arc: float = _lerp(params.spent_power_floor, 1.0, tired)
	match behavior:
		Behavior.RUNNING:
			f += profile.run_power * arc
		Behavior.RESTING:
			f += profile.rest_force
		_:
			f += profile.hold_force * arc
	return f


func _step_line(delta: float, giving_now: bool) -> void:
	var p: Params = params
	var demand: float = load * p.load_to_tension + _pull + _bare_pull
	if behavior == Behavior.SNAGGED:
		demand = _pull + load * p.load_to_tension * p.snag_load_transfer
	if p.deadlift:
		demand *= p.deadlift_load_mult
		demand -= _bare_pull * (p.deadlift_load_mult - 1.0)
		_deadlift_floor += p.deadlift_creep * delta
	var pull_rate: float = (_pull - _pull_prev) / _max(delta, 0.0001)
	if pull_rate > p.shock_threshold:
		tension += (pull_rate - p.shock_threshold) * p.shock_gain * delta
	_pull_prev = _pull
	var rate: float = p.tension_response if demand > tension else p.tension_release
	if giving_now:
		rate = p.give_tension_relief
		demand = _min(demand, _pull)
	tension += (demand - tension) * _min(rate * delta, 1.0)
	var drag: float = effective_drag()
	if tension > drag and behavior != Behavior.SNAGGED:
		var slip: float = _min((tension - drag) * p.drag_slip, p.drag_slip_max) * delta
		tension -= slip
		var paid: float = slip * p.slip_metres
		distance += paid
		distance_lost += paid
	if not overloading:
		fatigue = _max(fatigue - p.fatigue_recover * delta, 0.0)
	tension = _max(tension, _max(_deadlift_floor, fatigue))
	tension = _clamp(tension, 0.0, p.snap_tension)


func _check_snap(delta: float) -> void:
	if tension >= params.snap_tension:
		_over_limit_time += delta
		if _over_limit_time >= params.snap_grace_seconds:
			state = State.SNAPPED
	else:
		_over_limit_time = 0.0


func effective_drag() -> float:
	if params.perfect_set:
		return params.drag_setting + params.perfect_drag_bonus
	return params.drag_setting


func is_armed() -> bool:
	return _armed


func was_clean() -> bool:
	return state == State.LANDED and not params.late_set \
		and peak_tension <= params.clean_catch_max_peak_tension


## Every field the next tick reads, by name, as a float — the same names in the same order as
## `Fight::snapshot` in fight.rs, which is what the golden file pins.
func snapshot() -> Array[Array]:
	var b := func(v: bool) -> float: return 1.0 if v else 0.0
	return [
		["state", float(state)], ["behavior", float(behavior)],
		["distance", distance], ["start_distance", start_distance], ["tension", tension],
		["load", load], ["band_lo", band_lo], ["band_hi", band_hi], ["slack", slack],
		["fatigue", fatigue], ["overloading", b.call(overloading)], ["crank_left", crank_left],
		["lateral", lateral], ["combo", float(combo)], ["best_combo", float(best_combo)],
		["shake", shake], ["hitstop", hitstop], ["stress", stress], ["burst", burst],
		["stamina", stamina], ["elapsed", elapsed], ["peak_tension", peak_tension],
		["distance_lost", distance_lost], ["pumps_good", float(pumps_good)],
		["pumps_total", float(pumps_total)], ["runs", float(runs)], ["giving", b.call(giving)],
		["pull", _pull], ["pull_prev", _pull_prev], ["deadlift_floor", _deadlift_floor],
		["over_limit_time", _over_limit_time], ["snag_at", _snag_at], ["snag_until", _snag_until],
		["recover_until", _recover_until], ["was_loading", b.call(_was_loading)],
		["armed", b.call(_armed)], ["bare_pull", _bare_pull], ["lat_target", _lat_target],
		["lat_timer", _lat_timer], ["overload_time", _overload_time], ["rng", float(_rng)],
		["ticks", float(ticks)],
	]


# =============================================================================================
# THE LOG: what the client submits and the module replays
# =============================================================================================

## Runs of identical input: each `[ticks, flags, crank]`, flags bit 0 PUMP, bit 1 GIVE. As it
## rides in `submit_challenge_result`: `[n, (ticks, flags, crank) × n]`.
static func encode_log(log_runs: Array[PackedInt32Array]) -> Array[float]:
	var out: Array[float] = [float(log_runs.size())]
	for r: PackedInt32Array in log_runs:
		out.append(float(r[0]))
		out.append(float(r[1]))
		out.append(float(r[2]))
	return out


## Play `log_runs` through a fresh fight from the hook-set, as the module does (`replay`).
static func replay(p: Params, prof: Profile, seed: int, cast_m: float, log_runs: Array) -> FightSim:
	var f := FightSim.new(p, prof, seed, cast_m, true)
	for r: Variant in log_runs:
		var run: Array = r as Array if r is Array else Array(r as PackedInt32Array)
		var flags: int = int(run[1])
		for i: int in range(int(run[0])):
			if f.state != State.FIGHTING:
				return f
			f.tick(flags & 1 != 0, flags & 2 != 0, int(run[2]))
	return f


# =============================================================================================
# READ-OUTS for whoever draws the fight
# =============================================================================================

## How far out the catch is in the WORLD's metres: the cast's range, closing as the fight's
## distance comes in (and growing when it takes line). What the player is told, and where the
## float is drawn; the fight's own `distance` counts in `fight_length`'s metres, which are not the
## ones the aim showed.
func line_out_m() -> float:
	if start_distance <= 0.0:
		return 0.0
	return cast_range_m * distance / start_distance


## 0 at the cast, 1 at the rod tip.
func progress() -> float:
	if start_distance <= 0.0:
		return 1.0
	return clampf(1.0 - distance / start_distance, 0.0, 1.0)


## Tension as a fraction of where THIS line snaps.
func tension_fraction() -> float:
	return tension / maxf(params.snap_tension, 0.01)


## How much of the crank rate winding wins RIGHT NOW, 0..1 — what the reel gauge shows: all of it
## while a heave's slack is there to take; with none, the bare reel's share for how spent the
## fish is (`bare_reel_win`), and nothing while the drag slips (the spool is paying out).
## Presentation; the simulation's own steps decide.
func reel_pays() -> float:
	if slack > 0.0 and crank_left > 0.0:
		return 1.0
	if behavior == Behavior.RUNNING or tension > effective_drag():
		return 0.0
	return bare_reel_win()


## A band to aim at: shut on a run or a snag.
func pump_window_open() -> bool:
	return band_hi > band_lo


func in_band() -> bool:
	return band_hi > band_lo and load >= band_lo and load <= band_hi


func in_perfect() -> bool:
	return band_hi > band_lo and is_perfect(load)


func is_overloaded() -> bool:
	return band_hi > 0.0 and load > band_hi


## Slack on the water: the reel should be worked.
func cranking() -> bool:
	return crank_left > 0.0 and slack > 0.0


# =============================================================================================
# Godot's own definitions, written out (see the header): the twin's arithmetic
# =============================================================================================

## MAX(a, b)
static func _max(a: float, b: float) -> float:
	return a if a > b else b


## MIN(a, b)
static func _min(a: float, b: float) -> float:
	return a if a < b else b


## CLAMP(v, lo, hi)
static func _clamp(v: float, lo: float, hi: float) -> float:
	if v < lo:
		return lo
	return hi if v > hi else v


## Math::lerp
static func _lerp(from: float, to: float, weight: float) -> float:
	return from + (to - from) * weight


## Math::move_toward
static func _move_toward(from: float, to: float, delta: float) -> float:
	var d: float = to - from
	if absf(d) <= delta:
		return to
	var sign: float = 0.0 if d == 0.0 else (-1.0 if d < 0.0 else 1.0)
	return from + sign * delta
