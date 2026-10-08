class_name EquipComponent extends SpaceTimeComponent
## AN ITEM IN HAND, OR PUT AWAY (DECISIONS #159): game state, so the game can ask "is it in hand?"
## before it lets anything happen that needs it there: a cast, an attack, an ability. Luke: "when
## the rod is stowed and I do a very fast cast, the cast animation plays, then the draw animation
## plays ... there needs to be an equipped condition that stops casting until equipped (this will
## become more important later with attacks and abilities)".
##
##   AWAY --draw()--> DRAWING --draw_sec--> READY --put_away()--> STOWING --stow_sec--> AWAY
##
## Its clock is its own: nothing waits on an animation (hard rule 11). The held item FOLLOWS it
## (`HeldItem.follow`): it plays the draw or the put-away when one starts, moves the item between
## the hand and its stow place when the state flips, and sets `draw_sec`/`stow_sec` from its own
## clips (how far into the draw the hand takes it).
##
## A genre says when it is USING the item: `needed()`, every frame it is. That draws it when it is
## away (or turns a put-away back: it never left the hand), and, with `away_when_idle`, the item is
## put away `away_after_sec` after the last use, or sooner once the body moves faster than
## `away_when_faster_than` (put away to run). A verb that needs the item in hand checks
## `is_equipped()` and waits until it is (the fisher's cast goes the moment it is).
##
## OVER THE NETWORK (DECISIONS #160): the owner's client decides, and reports each change
## (`set_equip_state`, the public `equip_state` row); everyone else's copy FOLLOWS that row, so a
## draw plays on every screen as it starts there, timed on each client's own clock from then on.
## An entity nobody reports for (an NPC, before its first row) is decided where it is seen, from
## what the game shows of it (the genre's `needed()`).

## A draw (true) or a put-away (false) began; one in progress was turned back before it finished;
## the item reached the hand (true) or its stow place (false).
signal equip_started(drawing: bool)
signal equip_cancelled(drawing: bool)
signal equipped_changed(equipped: bool)

enum State { AWAY, DRAWING, READY, STOWING }
## How fast the body moves, by gait (`shared/movement_config.json`): faster than a walk is running.
enum Gait { NEVER, WALK, RUN }

## Put the item away when it has not been used (`needed()`) for `away_after_sec`. False: once in
## hand, it stays there (carried), however it moves.
@export var away_when_idle: bool = true
@export var away_after_sec: float = 10.0
## And put it away sooner, once the body has moved faster than this gait for
## `away_moving_after_sec` without using it: WALK puts it away to run, RUN to sprint. NEVER: only
## the idle time puts it away.
@export var away_when_faster_than: Gait = Gait.WALK
@export var away_moving_after_sec: float = 0.3
## Seconds from asking until it is in hand, and until it is away. The held item sets these from its
## own clips when it follows this; set them by hand for an item with none.
@export var draw_sec: float = 0.5
@export var stow_sec: float = 0.75
## In hand when the entity arrives.
@export var starts_equipped: bool = false

const TABLE: StringName = &"equip_state"

var _state: State = State.AWAY
var _left: float = 0.0
var _idle: float = 0.0
## Seconds the body has been moving faster than `away_when_faster_than`, and where its speed is read.
var _fast: float = 0.0
var _movement: SpaceTimeMovementComponent = null

## How much faster than a gait's own speed counts as faster than it (a walk measured at 1.25 m/s
## is still a walk).
const GAIT_MARGIN: float = 1.25

## The state last reported to the server (ours), and whether a row has said anyone's (theirs).
var _told: int = -1
var _reported: bool = false


func required_tables() -> Array[StringName]:
	return [TABLE]


## No row until the owner first reports one.
func optional_tables() -> Array[StringName]:
	return [TABLE]


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE or new == null or is_local_authority:
		return
	_reported = true
	_follow_row(int(new.get(&"state")))


## Ours is reported again on every (re)connect: the row may be from before.
func _on_bound() -> void:
	_told = -1
	_tell()


## Whether this client decides the state (ours, or one nobody reports), or follows a row (theirs).
func deciding() -> bool:
	return is_local_authority or entity == null or not _reported


## Whether the owner has reported a state for this entity (always false for our own).
func reported() -> bool:
	return _reported


## ANOTHER PLAYER'S ROW: a draw or a put-away plays as it starts there; an end state is taken at
## once unless ours is already on its way to it.
func _follow_row(s: int) -> void:
	match s:
		State.DRAWING:
			draw()
		State.STOWING:
			put_away()
		State.READY:
			if _state != State.READY and _state != State.DRAWING:
				set_equipped_now(true)
		State.AWAY:
			if _state != State.AWAY and _state != State.STOWING:
				set_equipped_now(false)


## Report ours to the server when it changed (bound, ours, connected or not: a request that cannot
## be sent settles at once).
func _tell() -> void:
	if not is_local_authority or entity == null or int(_state) == _told:
		return
	_told = int(_state)
	SpaceTimeSync.call_reducer(&"set_equip_state", [_told], ["u8"])


func _ready() -> void:
	super()
	_state = State.READY if starts_equipped else State.AWAY


func state() -> State:
	return _state


## In hand and ready to use. A put-away in progress is not: `needed()` turns it back first.
func is_equipped() -> bool:
	return _state == State.READY


## THE GAME IS USING THE ITEM (call it every frame it is): drawn if it is away, a put-away turned
## back, and the idle clock restarted. Another player's, which follows their row, ignores it.
func needed() -> void:
	if not deciding():
		return
	_idle = 0.0
	draw()


## THE ITEM IS BEING USED WHERE IT IS (a verb's animation still playing after the verb): in hand,
## the idle clock restarts, and a put-away is turned back. Unlike `needed()`, it never draws.
func in_use() -> void:
	if not deciding():
		return
	match _state:
		State.READY:
			_idle = 0.0
		State.STOWING:
			_turn_back()


## Draw it: away, it starts drawing; going away, it is turned back, in hand at once.
func draw() -> void:
	match _state:
		State.AWAY:
			_begin(State.DRAWING)
		State.STOWING:
			_turn_back()


## Put it away: in hand, it starts going; being drawn, it is turned back, away at once.
func put_away() -> void:
	match _state:
		State.READY:
			_begin(State.STOWING)
		State.DRAWING:
			_turn_back()


## In hand or away at once, with no draw or put-away between (arriving, or another player's cast
## that is already playing).
func set_equipped_now(on: bool) -> void:
	_state = State.READY if on else State.AWAY
	_left = 0.0
	_idle = 0.0
	_tell()
	equipped_changed.emit(on)


func _begin(to: State) -> void:
	_state = to
	_left = draw_sec if to == State.DRAWING else stow_sec
	_tell()
	equip_started.emit(to == State.DRAWING)
	if _left <= 0.0:
		_arrive()


func _arrive() -> void:
	_state = State.READY if _state == State.DRAWING else State.AWAY
	_left = 0.0
	_idle = 0.0
	_tell()
	equipped_changed.emit(_state == State.READY)


func _turn_back() -> void:
	var was_drawing: bool = _state == State.DRAWING
	_state = State.AWAY if was_drawing else State.READY
	_left = 0.0
	_idle = 0.0
	_tell()
	equip_cancelled.emit(was_drawing)


## The body's speed across the ground (m/s), as drawn: 0 when the entity does not move.
func moving_speed() -> float:
	if _movement == null and entity is SpaceTimeEntity:
		_movement = (entity as SpaceTimeEntity).find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var s: MovementState = _movement.get_render_state() if _movement != null else null
	return Vector2(s.vel.x, s.vel.z).length() if s != null else 0.0


## The speed above which the body is moving faster than `away_when_faster_than` (INF for NEVER).
func faster_than_speed() -> float:
	var cfg: MovementConfig = MovementConfig.shared()
	match away_when_faster_than:
		Gait.WALK:
			return cfg.walk_speed * GAIT_MARGIN
		Gait.RUN:
			return cfg.run_speed * GAIT_MARGIN
	return INF


func _process(delta: float) -> void:
	_fast = _fast + delta if moving_speed() > faster_than_speed() else 0.0
	match _state:
		State.DRAWING, State.STOWING:
			_left -= delta
			if _left <= 0.0:
				_arrive()
		State.READY:
			# Theirs goes away when their row says so.
			if away_when_idle and deciding():
				_idle += delta
				# Used this moment (`needed()`), it stays out however fast the body goes.
				if _idle >= away_after_sec or (_fast >= away_moving_after_sec and _idle >= away_moving_after_sec):
					put_away()
