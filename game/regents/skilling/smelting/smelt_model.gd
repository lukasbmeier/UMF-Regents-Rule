class_name SmeltModel extends RefCounted
## SMELTING'S MINIGAME, BELLOWS THEN POUR (owner, 2026-10-19), in ticks of 50 ms.
##   HEAT (the first `heat_ms`): every tick the furnace cools `cool_per_tick`; a pump of the bellows adds
##        `pump_heat` (`pump_ms` only stops a macro: every press a hand can mash counts, owner
##        2026-10-19). A band drifts (a triangle wave around `band_center`, its phase from the seed) and
##        narrows; a tick inside it counts for the heat, a tick past `burn_line` against it.
##   POUR (the next `pour_ms`): from `pour_ready_ms` in (so mashing the bellows never tilts it), press to
##        tilt the crucible, release to stop, tilt again to top up; while it pours the mould fills
##        `pour_rate` a tick. It is scored by how near the line (from the seed) the fill ends; past the
##        brim (1000) it spilled.
## Inputs are (time, code): 1 pump, 2 pour, 3 stop. A PURE MODEL (its Rust twin: `genre::regents::smelt`,
## the golden file from `game/regents/tests/make_skill_goldens.py`); the live minigame plays through
## `press()` and `advance_to()`.

const TICK_MS: int = 50
const PUMP: int = 1
const POUR: int = 2
const STOP: int = 3
const IGNORED: int = 0
const DONE: int = 1

var params: SmeltParams
var phase_offset: int = 0
var target: int = 0
## The next tick to run, the heat, the fill.
var tick: int = 0
var heat: int = 0
var fill: int = 0
var pouring: bool = false
var poured: bool = false
var in_band: int = 0
var burnt: int = 0
var next_pump_ms: int = 0
var last_t_ms: int = -1


static func start(seed_value: int, p: SmeltParams) -> SmeltModel:
	var m: SmeltModel = SmeltModel.new()
	m.params = p
	var st: int = SkillRandom.next_u32(SkillRandom.seed_state(seed_value))
	m.phase_offset = (st >> 8) % maxi(1, p.band_period_ticks)
	st = SkillRandom.next_u32(st)
	m.target = p.target_lo + (st >> 8) % maxi(1, p.target_hi - p.target_lo + 1)
	m.heat = p.start_heat
	return m


static func heat_ticks(p: SmeltParams) -> int:
	return p.heat_ms / TICK_MS


static func total_ticks(p: SmeltParams) -> int:
	return p.heat_ms / TICK_MS + p.pour_ms / TICK_MS


## A triangle wave from -1000 to 1000 over `period` ticks.
static func tri(x: int, period: int) -> int:
	var u: int = x % period
	var v: int = u * 4000 / period
	if v <= 1000:
		return v
	if v <= 3000:
		return 2000 - v
	return v - 4000


## The band at tick `k` of the heat: its middle and half-width.
func band(k: int) -> Vector2i:
	var p: SmeltParams = params
	var centre: int = p.band_center + p.band_amp * tri(k + phase_offset, maxi(1, p.band_period_ticks)) / 1000
	var half: int = p.band_half_start + (p.band_half_end - p.band_half_start) * k / maxi(1, heat_ticks(p))
	return Vector2i(centre, half)


func in_heat() -> bool:
	return tick < heat_ticks(params)


## Whether the crucible may tilt at `t_ms`: `pour_ready_ms` after the heat ends.
func pour_ready(t_ms: int) -> bool:
	return t_ms >= params.heat_ms + params.pour_ready_ms


## Run every tick that ends by `t_ms`.
func advance_to(t_ms: int) -> void:
	var total: int = total_ticks(params)
	while (tick + 1) * TICK_MS <= t_ms and tick < total:
		_tick()
		tick += 1


func _tick() -> void:
	if tick < heat_ticks(params):
		heat = maxi(0, heat - params.cool_per_tick)
		var b: Vector2i = band(tick)
		if absi(heat - b.x) <= b.y:
			in_band += 1
		if heat > params.burn_line:
			burnt += 1
	elif pouring:
		fill += params.pour_rate


## An input at `t_ms`: PUMP (in the heat), POUR or STOP (in the pour). Returns DONE or IGNORED.
func press(t_ms: int, code: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	if t_ms < 0 or t_ms > total_ticks(params) * TICK_MS:
		return IGNORED
	advance_to(t_ms)
	if code == PUMP:
		if not in_heat() or t_ms < next_pump_ms:
			return IGNORED
		heat = mini(1000, heat + params.pump_heat)
		next_pump_ms = t_ms + params.pump_ms
		return DONE
	if code == POUR:
		if in_heat() or pouring or not pour_ready(t_ms):
			return IGNORED
		pouring = true
		poured = true
		return DONE
	if code == STOP:
		if not pouring:
			return IGNORED
		pouring = false
		return DONE
	return IGNORED


## The round to its end (every tick run).
func finish() -> void:
	advance_to(total_ticks(params) * TICK_MS)


func heat_score() -> int:
	return clampi((in_band - burnt) * 1000 / maxi(1, heat_ticks(params)), 0, 1000)


func pour_score() -> int:
	if fill > 1000:
		return 0
	return maxi(0, 1000 - absi(fill - target) * 1000 / params.pour_tolerance)


func score_pm() -> int:
	return (heat_score() * params.heat_weight_pct + pour_score() * (100 - params.heat_weight_pct)) / 100


func result() -> Dictionary:
	return {"in_band": in_band, "burnt": burnt, "fill": fill, "target": target, "heat_pm": heat_score(),
		"pour_pm": pour_score(), "score_pm": score_pm()}


## A whole round replayed from its inputs: flat (time, code) pairs, in the order sent; run to its end.
static func play(seed_value: int, p: SmeltParams, inputs: PackedInt32Array) -> Dictionary:
	var m: SmeltModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.press(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()
