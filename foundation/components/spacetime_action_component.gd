class_name SpaceTimeActionComponent extends SpaceTimeComponent
## Actions: PHASE3_SPEC Task 12, with predicted starts per PHASE4_SPEC §3.
##
## `request_use` announces the action IMMEDIATELY — `action_started`, carrying a predicted id —
## and starts the cooldown locally, then asks the server. The module's `action_event` row echoes
## that id back: `action_resolved`. A refusal (the reducer's Err: cooldown, range, the dead do
## not act) or no answer in time: `action_revoked`, and the cooldown is handed back. That is why
## content keeps `wind_up_ms >= 100`: the start animation has a round trip to play before the
## answer lands.
##
## Every entity's actions arrive on the one global stream (`action_event` has no entity_id).
## The ACTOR's component reports each one on the bus (`entity_action`), so it is announced once
## however many entities are listening; a component whose entity is the TARGET reports it
## locally as `action_observed`, for hit reactions.

## Started, predicted: play the wind-up now.
signal action_started(ability_id: int, predicted_id: int)
## The server confirmed it. `outcome` is Outcome.
signal action_resolved(ability_id: int, predicted_id: int, outcome: int, target_id: int)
## It did not happen after all. Cancel the animation; the cooldown is already reset.
signal action_revoked(ability_id: int, predicted_id: int, reason: String)
## Somebody's action involving this entity that THIS client did not predict: a remote player's
## attack, or a hit landing on us.
signal action_observed(actor_id: int, ability_id: int, target_id: int, outcome: int)
## A cooldown ran out.
signal ability_ready(ability_id: int)
## SOMEONE ELSE'S ENTITY BEGAN AN ABILITY (DECISIONS #232): its cooldown row started a new cooldown.
## What a remote character's animation plays its start from (its own client predicted it; nobody else
## hears of a use until it lands).
signal started_elsewhere(ability_id: int)

const STATE_TABLE: StringName = &"ability_state"
const EVENT_TABLE: StringName = &"action_event"
const DEF_TABLE: StringName = &"ability_def"
## Must match OUTCOME_* in server/src/module.rs.
enum Outcome { HIT = 0, MISS = 1 }
## Remembered event ids, so a cache replay on reconnect cannot resolve anything twice.
const MAX_SEEN_EVENTS: int = 512

## Past the ability's wind-up, how long to wait for the server's answer before giving up.
@export var resolve_timeout_ms: int = 1000

var _next_id: int = 1
## predicted_id -> {ability_id, target_id, deadline_usec, ready_before}
var _pending: Dictionary[int, Dictionary] = {}
## ability_id -> local usec it becomes usable again
var _ready_at_usec: Dictionary[int, int] = {}
var _cooling: Dictionary[int, bool] = {}
var _seen_events: Dictionary[int, bool] = {}

## Test seams. Empty in production.
var _reducer_override: Callable = Callable()   # (ability_id, target_id, aim, predicted_id) -> ReducerRequest
var _def_override: Callable = Callable()       # (ability_id) -> RefCounted, an ability_def row
var _clock_override: Callable = Callable()     # () -> local usec


func required_tables() -> Array[StringName]:
	return [STATE_TABLE]


## An entity that has never acted has no cooldown rows.
func optional_tables() -> Array[StringName]:
	return [STATE_TABLE]


func also_reads() -> Array[StringName]:
	return [DEF_TABLE]


# --- intent --------------------------------------------------------------------------------

## Use an ability. Returns the predicted id, or -1 if refused locally (unknown ability, still
## cooling down) — in which case nothing was sent and nothing was announced.
func request_use(ability_id: int, target_id: int = 0, aim: Vector3 = Vector3.ZERO) -> int:
	var def: RefCounted = _def(ability_id)
	if def == null:
		push_warning("SpaceTimeActionComponent: no ability_def %d (is ability_def subscribed?)" % ability_id)
		return -1
	if is_on_cooldown(ability_id):
		return -1
	var pid: int = _next_id
	_next_id += 1
	var now: int = _now()
	_pending[pid] = {
		"ability_id": ability_id,
		"target_id": target_id,
		"deadline_usec": now + (int(def.get(&"wind_up_ms")) + resolve_timeout_ms) * 1000,
		"ready_before": int(_ready_at_usec.get(ability_id, 0)),
	}
	_set_ready_at(ability_id, now + int(def.get(&"cooldown_ms")) * 1000)
	action_started.emit(ability_id, pid)
	_lunge_after_wind_up(ability_id, pid)
	var req: ReducerRequest = _call(ability_id, target_id, aim, pid)
	if req == null:
		_revoke(pid, "the request could not be sent")
	elif req.is_pending():
		req.settled.connect(func(r: ReducerRequest) -> void: _on_settled(pid, r))
	else:
		_on_settled(pid, req)
	return pid


func is_on_cooldown(ability_id: int) -> bool:
	return _now() < int(_ready_at_usec.get(ability_id, 0))


func cooldown_remaining_sec(ability_id: int) -> float:
	return maxf(0.0, float(int(_ready_at_usec.get(ability_id, 0)) - _now()) / 1_000_000.0)


func pending_count() -> int:
	return _pending.size()


# --- rows ----------------------------------------------------------------------------------

## Uses taken back (refused, no answer), newest last: their lunges do not happen.
var _revoked_pids: Dictionary[int, bool] = {}


func _on_bound() -> void:
	# Guarded: rebind() calls bind() again on reconnect (DECISIONS #48).
	if not EntityRegistry.global_row_event.is_connected(_on_global_row):
		EntityRegistry.global_row_event.connect(_on_global_row)


## The server's word on a cooldown, converted to our clock.
func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table != STATE_TABLE or new == null:
		return
	var ability_id: int = int(new.get(&"ability_id"))
	var remaining_usec: int = int(new.get(&"cooldown_until")) - ClockSync.server_usec()
	if not is_local_authority and remaining_usec > 0 and (old == null or int(old.get(&"cooldown_until")) != int(new.get(&"cooldown_until"))):
		started_elsewhere.emit(ability_id)
	_set_ready_at(ability_id, _now() + maxi(0, remaining_usec))


func _on_global_row(ev: RowEvent) -> void:
	if ev.table != EVENT_TABLE or ev.kind != RowEvent.Kind.INSERTED:
		return
	var row: RefCounted = ev.current()
	if row == null:
		return
	var actor: int = int(row.get(&"actor_id"))
	var target: int = int(row.get(&"target_id"))
	if actor != entity_id and target != entity_id:
		return
	var id: int = int(row.get(&"id"))
	if _seen_events.has(id):
		return
	_seen_events[id] = true
	if _seen_events.size() > MAX_SEEN_EVENTS:
		_seen_events.erase(_seen_events.keys()[0])

	var ability_id: int = int(row.get(&"ability_id"))
	var outcome: int = int(row.get(&"outcome"))
	if actor == entity_id:
		var pid: int = int(row.get(&"predicted_id"))
		if is_local_authority and _pending.has(pid):
			_pending.erase(pid)
			action_resolved.emit(ability_id, pid, outcome, target)
		else:
			action_observed.emit(actor, ability_id, target, outcome)
		SignalBus.entity_action.emit(actor, ability_id, target, outcome)
	else:
		action_observed.emit(actor, ability_id, target, outcome)


func _on_settled(pid: int, req: ReducerRequest) -> void:
	if req.is_ok():
		return   # the action_event row is the confirmation; it may arrive before or after this
	_revoke(pid, req.error_message if not req.error_message.is_empty() else ReducerRequest.Outcome.keys()[req.outcome])


func _revoke(pid: int, reason: String) -> void:
	if not _pending.has(pid):
		return
	var p: Dictionary = _pending[pid]
	_pending.erase(pid)
	_revoked_pids[pid] = true   # a lunge still to come does not (`_lunge_after_wind_up`)
	if _revoked_pids.size() > 32:
		_revoked_pids.erase(_revoked_pids.keys()[0])
	var ability_id: int = int(p["ability_id"])
	# Hand the cooldown back: the use never happened.
	_set_ready_at(ability_id, int(p["ready_before"]))
	action_revoked.emit(ability_id, pid, reason)


# --- time ----------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if is_bound():
		tick()


## Deadlines and cooldowns. Public so tests can step it.
func tick() -> void:
	var now: int = _now()
	for pid: int in _pending.keys():
		if now > int(_pending[pid]["deadline_usec"]):
			_revoke(pid, "no answer from the server")
	for ability_id: int in _cooling.keys():
		if now >= int(_ready_at_usec.get(ability_id, 0)):
			_cooling.erase(ability_id)
			ability_ready.emit(ability_id)


func _set_ready_at(ability_id: int, usec: int) -> void:
	_ready_at_usec[ability_id] = usec
	if usec > _now():
		_cooling[ability_id] = true


func _now() -> int:
	return int(_clock_override.call()) if _clock_override.is_valid() else Time.get_ticks_usec()


## THE BODY LUNGES (DECISIONS #232): an ability whose content `lunges` dashes its user as its wind-up
## ends, unless it was taken back before (refused, revoked).
func _lunge_after_wind_up(ability_id: int, pid: int) -> void:
	var wind_up: int = lunge_wind_up_ms(_def(ability_id))
	if wind_up < 0 or not is_inside_tree():
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var input: LocalInputComponent = ent.find_component(LocalInputComponent) as LocalInputComponent if ent != null else null
	if input == null:
		return
	get_tree().create_timer(float(wind_up) / 1000.0, true, true).timeout.connect(func() -> void:
		if is_instance_valid(input) and not _revoked_pids.has(pid):
			input.dash_once())


## How long after its use an ability's user lunges (its wind-up), from its `ability_def` row; -1 when it
## does not lunge.
static func lunge_wind_up_ms(def: RefCounted) -> int:
	if def == null:
		return -1
	var data: Variant = JSON.parse_string(String(def.get(&"data"))) if def.get(&"data") != null else null
	if not (data is Dictionary) or not bool((data as Dictionary).get("lunges", false)):
		return -1
	return int(def.get(&"wind_up_ms"))


func _def(ability_id: int) -> RefCounted:
	if _def_override.is_valid():
		return _def_override.call(ability_id) as RefCounted
	return SpaceTimeSync.get_row(DEF_TABLE, ability_id)


func _call(ability_id: int, target_id: int, aim: Vector3, pid: int) -> ReducerRequest:
	if _reducer_override.is_valid():
		return _reducer_override.call(ability_id, target_id, aim, pid) as ReducerRequest
	# With how far behind the server this client sees everyone (DECISIONS #226): an ability the
	# world's referee judges is judged as the player saw it.
	return SpaceTimeSync.call_reducer(&"use_ability_seen", [ability_id, target_id, aim, pid, view_delay_ms()],
		["u32", "u64", "vector3[f32,f32,f32]", "u32", "u32"])


## HOW FAR BEHIND THE SERVER THIS CLIENT SEES EVERYONE ELSE, in ms: the delay it draws other
## entities at (their interpolation, on average) and the half round trip a row took to reach it. What
## the referee rewinds by when it judges this player's ability (capped by `foundation.rewind_max_ms`).
static func view_delay_ms() -> int:
	var total: float = 0.0
	var n: int = 0
	for node: Node in EntitySpawner.entity_nodes():
		var ent: SpaceTimeEntity = node as SpaceTimeEntity
		if ent == null:
			continue
		var mv: SpaceTimeMovementComponent = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		if mv != null and mv.mode == SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED:
			total += mv.get_interp_delay_sec()
			n += 1
	var interp: float = total / n if n > 0 else 0.1
	return maxi(0, roundi(interp * 1000.0 + float(ClockSync.rtt_usec()) / 2000.0))
