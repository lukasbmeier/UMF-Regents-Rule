class_name TimedPressComponent extends SpaceTimeComponent
## THE SERVER-TIMED PRESS, PLAYED (docs/FOUNDATION_SYSTEMS.md milestone 4, DECISIONS #210): a skill
## check where a marker sweeps across a bar and the player presses while it is in the target.
##
## The server judges every press by its own clock: this sends only "pressed" (`challenge_press`). What
## it does here is what makes that fair and readable:
##   it ACKNOWLEDGES each one the moment it arrives (`challenge_seen`): the server times that round
##   trip itself, and credits each press with half the quickest (the time a press takes to arrive);
##   it draws the sweep from the server's clock (`ClockSync`), from the sweep frozen on its row
##   (`timed_press`), so the marker is where the server will judge it;
##   it PREDICTS each press's result at once (the same sums, `ChallengeModel`), and the server's
##   judgement replaces it a round trip later (`judged`);
##   it CALIBRATES the bar from those judgements (DECISIONS #213): each says when the server took the
##   press to be, which this client compares with when it drew it; the median of the last few is how
##   far its estimate of the server's clock is out, and the marker is drawn that much on (at most
##   `MAX_CALIBRATION_S`). Luke saw a press on the line in Great judged Good: the clock this client
##   draws by comes from row timestamps, which may arrive later than half a round trip. The server
##   still judges every press; this only makes what the player sees agree with it.
## The interact key presses it while one is being played (`InteractionComponent`); the HUD's
## `TimingBar` draws it. Every entity has one (`SpaceTimeEntity`), only the local player's plays.

## A press was sent: its round and what this client predicts for it.
signal pressed(challenge_id: int, round: int, predicted: float)
## The server judged a press: its round, the quality, where the marker was, what was predicted.
signal judged(challenge_id: int, round: int, quality: float, position: float, predicted: float)

const TABLE_CHALLENGE: StringName = &"challenge"
const TABLE_SWEEP: StringName = &"timed_press"
## How far the calibration may move the bar, and how many judgements it is the median of.
const MAX_CALIBRATION_S: float = 0.3
const CALIBRATION_SAMPLES: int = 7

## challenge id -> {seed, difficulty}: this entity's timed-press challenges.
var _challenges: Dictionary = {}
## challenge id -> {starts_usec, period_s, half, rounds, qualities, positions, done}.
var _sweeps: Dictionary = {}
## challenge id -> predicted qualities, in order.
var _predicted: Dictionary = {}
var _acked: Dictionary = {}
## The last press judged: {challenge_id, round, quality, position, predicted, at_msec}, or empty.
var last_judged: Dictionary = {}
## How far on (s) the bar is drawn from this client's estimate of the server's clock: the median of
## `_offsets`, the server's judged time less the time each press was drawn at. Kept for the session.
var calibration_s: float = 0.0
var _offsets: Array[float] = []
## challenge id -> the uncalibrated elapsed seconds each press was made at.
var _pressed_at: Dictionary = {}
## challenge id -> where the marker was DRAWN when each press was made (0..1).
var _pressed_pos: Dictionary = {}


func required_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_SWEEP]


func optional_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_SWEEP]


func rebind(initial_rows: Dictionary[StringName, RefCounted], history: Dictionary[StringName, Array] = {}) -> void:
	_challenges.clear()
	_sweeps.clear()
	super(initial_rows, history)


# --- read API ------------------------------------------------------------------------------------

## The timed press being played now (the oldest with presses left), or -1.
func current() -> int:
	var ids: Array = _challenges.keys()
	ids.sort()
	for id: int in ids:
		var s: Dictionary = _sweeps.get(id, {})
		if not s.is_empty() and not bool(s["done"]) and presses_made(id) < int(s["rounds"]):
			return id
	return -1


## Presses made on `id`: those the server has judged, or more if this client has sent them since.
func presses_made(id: int) -> int:
	var s: Dictionary = _sweeps.get(id, {})
	var judged_n: int = (s.get("qualities", []) as Array).size() if not s.is_empty() else 0
	return maxi(judged_n, (_predicted.get(id, []) as Array).size())


## How many presses `id` takes.
func rounds(id: int) -> int:
	return int((_sweeps.get(id, {}) as Dictionary).get("rounds", 0))


## Seconds since `id`'s marker began to move (negative: still to start), by the server's clock as
## calibrated by its own judgements (`calibration_s`).
func elapsed(id: int) -> float:
	return _raw_elapsed(id) + calibration_s


## The same by this client's estimate of the server's clock alone.
func _raw_elapsed(id: int) -> float:
	var s: Dictionary = _sweeps.get(id, {})
	if s.is_empty():
		return 0.0
	return float(ClockSync.server_usec() - int(s["starts_usec"])) / 1_000_000.0


## Where the marker was drawn when each of `id`'s presses was made (0..1), in order: what the player
## saw, beside where the server judged it (`judged_positions`).
func pressed_positions(id: int) -> Array:
	return (_pressed_pos.get(id, []) as Array).duplicate()


## Where the server judged each of `id`'s presses (0..1), in order.
func judged_positions(id: int) -> Array:
	return ((_sweeps.get(id, {}) as Dictionary).get("positions", []) as Array).duplicate()


## Where `id`'s marker is now (0..1).
func marker(id: int) -> float:
	var s: Dictionary = _sweeps.get(id, {})
	return ChallengeModel.sweep_position(elapsed(id), float(s.get("period_s", 0.0))) if not s.is_empty() else 0.0


## The centre of the target for press `round` of `id`, and its half-width.
func target(id: int, round: int) -> float:
	var c: Dictionary = _challenges.get(id, {})
	if c.is_empty():
		return 0.5
	var v: Vector3 = ChallengeModel.timing_centers(int(c["seed"]))
	return v[clampi(round, 0, 2)]


func half_width(id: int) -> float:
	return float((_sweeps.get(id, {}) as Dictionary).get("half", 0.0))


## The server's qualities for `id`'s presses so far, and this client's predictions.
func qualities(id: int) -> Array:
	return ((_sweeps.get(id, {}) as Dictionary).get("qualities", []) as Array).duplicate()


func predictions(id: int) -> Array:
	return (_predicted.get(id, []) as Array).duplicate()


## Whether the interact key should press this rather than use what is in front of the player.
func wants_press() -> bool:
	return is_local_authority and current() >= 0


# --- intent ------------------------------------------------------------------------------------

## PRESS: predicted here at once, judged by the server. Nothing before the marker moves (a press
## then would be wasted on the start of the bar) or when every press is made. Returns the request.
func press() -> ReducerRequest:
	var id: int = current()
	if id < 0 or elapsed(id) < 0.0:
		return null
	var round: int = presses_made(id)
	var predicted: float = ChallengeModel.press_quality(marker(id), target(id, round), half_width(id))
	(_predicted.get_or_add(id, []) as Array).append(predicted)
	(_pressed_at.get_or_add(id, []) as Array).append(_raw_elapsed(id))
	(_pressed_pos.get_or_add(id, []) as Array).append(marker(id))
	pressed.emit(id, round, predicted)
	return SpaceTimeSync.call_reducer(&"challenge_press", [id], ["u64"])


# --- rows ------------------------------------------------------------------------------------

func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table == TABLE_CHALLENGE:
		_challenge_row(old, new)
	elif table == TABLE_SWEEP:
		_sweep_row(old, new)


func _challenge_row(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		if old != null:
			_challenges.erase(int(old.get(&"id")))
		return
	if int(new.get(&"kind")) != ChallengeModel.KIND_TIMED_PRESS:
		return
	var id: int = int(new.get(&"id"))
	_challenges[id] = {"seed": int(new.get(&"seed")), "difficulty": float(new.get(&"difficulty"))}
	# The moment it arrives: the server times the trip (its credit for each press is half the quickest).
	if is_local_authority and not _acked.has(id):
		_acked[id] = true
		SpaceTimeSync.call_reducer(&"challenge_seen", [id], ["u64"])


## Press `round` of `id` was judged at `ats[round]` ms after the sweep began: against when this client
## drew it, how far out its clock is. The median of the last few moves the bar.
func _calibrate(id: int, round: int, ats: Array) -> void:
	var made: Array = _pressed_at.get(id, [])
	if round >= made.size() or round >= ats.size():
		return
	_offsets.append(float(ats[round]) / 1000.0 - float(made[round]))
	while _offsets.size() > CALIBRATION_SAMPLES:
		_offsets.pop_front()
	var sorted: Array[float] = _offsets.duplicate()
	sorted.sort()
	calibration_s = clampf(sorted[sorted.size() / 2], -MAX_CALIBRATION_S, MAX_CALIBRATION_S)


func _sweep_row(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		if old != null:
			var gone: int = int(old.get(&"challenge_id"))
			_sweeps.erase(gone)
			_predicted.erase(gone)
			_acked.erase(gone)
			_pressed_at.erase(gone)
			_pressed_pos.erase(gone)
		return
	var id: int = int(new.get(&"challenge_id"))
	var before: int = (( _sweeps.get(id, {}) as Dictionary).get("qualities", []) as Array).size()
	var qs: Array = Array(new.get(&"qualities"))
	var ps: Array = Array(new.get(&"positions"))
	var ats: Array = Array(new.get(&"at_ms"))
	_sweeps[id] = {
		"starts_usec": int(new.get(&"starts_at")),
		"period_s": float(int(new.get(&"period_ms"))) / 1000.0,
		"half": float(new.get(&"half_width")),
		"rounds": int(new.get(&"rounds")),
		"qualities": qs,
		"positions": ps,
		"done": bool(new.get(&"done")),
	}
	for r: int in range(before, qs.size()):
		_calibrate(id, r, ats)
		var guess: Array = _predicted.get(id, [])
		var predicted: float = float(guess[r]) if r < guess.size() else -1.0
		last_judged = {"challenge_id": id, "round": r, "quality": float(qs[r]), "position": float(ps[r]) if r < ps.size() else 0.0,
			"predicted": predicted, "at_msec": Time.get_ticks_msec()}
		if is_bound():
			print("[Press] challenge %d press %d: %.2f (predicted %.2f; bar calibrated %+d ms)" % [id, r + 1, float(qs[r]), predicted, roundi(calibration_s * 1000.0)])
			judged.emit(id, r, float(qs[r]), float(last_judged["position"]), predicted)
			SignalBus.timed_press_judged.emit(entity_id, r, float(qs[r]))
