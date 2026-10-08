class_name SessionComponent extends SpaceTimeComponent
## The client half of the server's phase machine (ARCHITECTURE §7, module `advance_phases`).
##
## `session_member` is entity-scoped so it arrives through the normal component route. The
## `session` row is NOT — it has no `entity_id`, so it reaches `EntityRegistry.global_row_event`
## instead, and this component filters that stream for the one session it belongs to. That
## split is the general pattern for "my row plus a world row it points at".
##
## Genre-agnostic on purpose: the foundation exposes phase NUMBER, when it ends, and the
## member's score. What a phase MEANS — fishing's rounds, a party game's lobby — is the genre's
## business (GENRE_ADAPTERS §6). Nothing here knows what kind 0 is.

## Entity-local signals.
signal joined_session(session_id: int)
signal left_session()
signal phase_changed(old_phase: int, new_phase: int, ends_at_usec: int)
signal score_changed(score: int, coins: int)
## THE LOBBY (DECISIONS #174): this member said ready, or not, or changed team.
signal lobby_changed(ready: bool, team: int)
## THE MATCH (DECISIONS #182): a new match began, or its first round started.
signal match_changed(started: bool, number: int)

const MEMBER_TABLE: StringName = &"session_member"
const SESSION_TABLE: StringName = &"session"
## Ready and team, for a session kind with a lobby (`shared/rules.json`).
const LOBBY_TABLE: StringName = &"lobby_member"
## The session's match: where its rounds count from, and whether its first round has started. Per
## session, like `session`, so it arrives on the global stream too.
const MATCH_TABLE: StringName = &"session_match"

## Matches the module's kind-0 phase machine. A genre with its own `session.kind` numbers its
## phases from 100, exactly like `move_state` and `challenge.kind`.
## Mirrors `PHASE_*` in `server/src/module.rs`. SHOP is the between-rounds phase: the scores are
## in, nothing is being played, and a genre may let players spend what they earned.
enum Phase { LOBBY = 0, PLAYING = 1, RESULTS = 2, SHOP = 3 }
## A phase further off than this is held (the module holds one for a year), not timed.
const WAITING_SEC: float = 24.0 * 3600.0

var _session_id: int = -1
var _score: int = 0
var _coins: int = 0
var _phase: int = -1
var _phase_ends_at_usec: int = 0
var _session_kind: int = -1
var _seed: int = 0
var _round: int = 0
var _is_ready: bool = false
var _team: int = 0
## The session round the match began on; -1 while no match row is known (a server from before them).
var _match_first_round: int = -1
var _match_started: bool = false
var _match_number: int = 0


func required_tables() -> Array[StringName]:
	return [MEMBER_TABLE, LOBBY_TABLE]


## A kind with no lobby has no lobby row.
func optional_tables() -> Array[StringName]:
	return [LOBBY_TABLE]


# --- read API ------------------------------------------------------------------------

func get_session_id() -> int:
	return _session_id


func get_phase() -> int:
	return _phase


func get_session_kind() -> int:
	return _session_kind


## Server-rolled per round. Genre validators derive their randomness from it.
func get_seed() -> int:
	return _seed


## Which round this is, counting from 1. `advance_phases` bumps it on entering LOBBY, so during
## RESULTS and SHOP it is still the round whose scores are on the board — which is what lets a
## genre say "round 3 results" and pick out that round's records.
func get_round() -> int:
	return _round


## THE ROUND A PLAYER SEES (DECISIONS #182): counted from 1 in this match. `get_round()` is the
## session's own count, which catches and standings are filed under; show this one.
func get_match_round() -> int:
	if _match_first_round < 0:
		return _round
	return maxi(_round - _match_first_round + 1, 1)


## Whether the match's first round has begun. False while its lobby waits for players. True when
## no match row is known, so a client against an older server never waits in a lobby for ever.
func is_match_started() -> bool:
	return _match_first_round < 0 or _match_started


## Which match of the session this is: 1, 2, ... (0 while unknown).
func match_number() -> int:
	return _match_number


func get_score() -> int:
	return _score


func get_coins() -> int:
	return _coins


## Said ready in the lobby (DECISIONS #174).
func is_ready() -> bool:
	return _is_ready


## The team picked in the lobby: a number into the rules' teams (0 when there are none).
func team() -> int:
	return _team


func is_in_session() -> bool:
	return _session_id >= 0


## Whether the current phase has no end: held until something moves it (a match's lobby waiting
## for its players to be ready, DECISIONS #182). Show "waiting", never the seconds.
func is_waiting() -> bool:
	return seconds_remaining() > WAITING_SEC


## Seconds until the current phase ends, by the server clock. Negative once it is overdue and
## `advance_phases` has not caught up yet — clamp in UI rather than here.
func seconds_remaining() -> float:
	if _phase_ends_at_usec <= 0:
		return 0.0
	return float(_phase_ends_at_usec - ClockSync.server_usec()) / 1_000_000.0


# --- row handling --------------------------------------------------------------------

func _on_bound() -> void:
	# Guarded because `rebind()` runs `bind()` again on reconnect (DECISIONS #17). Connecting
	# unconditionally left this component subscribed twice after every reconnect, so every
	# phase change would have been reported twice to the UI.
	if not EntityRegistry.global_row_event.is_connected(_on_global_row):
		EntityRegistry.global_row_event.connect(_on_global_row)
	# The session row is usually already in the cache by the time we bind; only if it is not
	# do we wait for it to arrive on the global stream.
	_resolve_session_row()


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table == LOBBY_TABLE:
		var r: bool = bool(new.get(&"ready")) if new != null else false
		var t: int = int(new.get(&"team")) if new != null else 0
		if r != _is_ready or t != _team:
			_is_ready = r
			_team = t
			lobby_changed.emit(_is_ready, _team)
		return
	if table != MEMBER_TABLE:
		return
	if new == null:
		var had: bool = _session_id >= 0
		_session_id = -1
		_phase = -1
		_phase_ends_at_usec = 0
		if had:
			left_session.emit()
		return

	var sid: int = int(new.get(&"session_id"))
	var score: int = int(new.get(&"score"))
	var coins: int = int(new.get(&"coins"))

	if sid != _session_id:
		_session_id = sid
		joined_session.emit(sid)
		_resolve_session_row()

	if score != _score or coins != _coins:
		_score = score
		_coins = coins
		score_changed.emit(_score, _coins)
		SignalBus.session_score_changed.emit(entity_id, _score, _coins)


## `session` carries no entity_id, so it never reaches a component through the entity. It
## arrives here instead, for every session in scope — hence the id filter.
func _on_global_row(ev: RowEvent) -> void:
	if _session_id < 0:
		return
	var row: RefCounted = ev.current()
	if ev.table == MATCH_TABLE:
		if row != null and int(row.get(&"session_id")) == _session_id:
			_apply_match_row(row if ev.kind != RowEvent.Kind.DELETED else null)
		return
	if ev.table != SESSION_TABLE:
		return
	if row == null or int(row.get(&"id")) != _session_id:
		return
	_apply_session_row(row)


func _resolve_session_row() -> void:
	if _session_id < 0:
		return
	var row: RefCounted = SpaceTimeSync.get_row(SESSION_TABLE, _session_id)
	if row != null:
		_apply_session_row(row)
	var m: RefCounted = SpaceTimeSync.get_row(MATCH_TABLE, _session_id)
	if m != null:
		_apply_match_row(m)


func _apply_match_row(row: RefCounted) -> void:
	var first: int = int(row.get(&"first_round")) if row != null else -1
	var started: bool = bool(row.get(&"started")) if row != null else false
	var number: int = int(row.get(&"number")) if row != null else 0
	if first == _match_first_round and started == _match_started and number == _match_number:
		return
	_match_first_round = first
	_match_started = started
	_match_number = number
	match_changed.emit(is_match_started(), _match_number)


func _apply_session_row(row: RefCounted) -> void:
	_session_kind = int(row.get(&"kind"))
	_seed = int(row.get(&"seed"))
	_round = int(row.get(&"round"))
	var ends_at: int = int(row.get(&"phase_ends_at"))
	var new_phase: int = int(row.get(&"phase"))
	var old_phase: int = _phase
	_phase_ends_at_usec = ends_at

	if new_phase == old_phase:
		return
	_phase = new_phase
	phase_changed.emit(old_phase, new_phase, ends_at)
	# ONCE PER CLIENT, NOT ONCE PER PLAYER. Every member in view carries a SessionComponent that
	# tracks the same session row, and all of them used to announce it — so one transition
	# reached the bus once for each player on screen. Found when the end-of-round bell rang three
	# times with three players in the world. The phase is the match's, and the bus is the local
	# UI's, so the local player's component is the one that announces it.
	if is_local_authority:
		SignalBus.session_phase_changed.emit(_session_id, old_phase, new_phase, ends_at)
