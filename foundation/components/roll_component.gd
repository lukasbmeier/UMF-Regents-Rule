class_name RollComponent extends SpaceTimeComponent
## THE DODGE ROLL (DECISIONS #309), on every entity (`SpaceTimeEntity` gives one to a scene without). A character
## whose definition names a `dodge_roll` (an `AbilityDef` that `rolls`) rolls on that ability's key (its `key`;
## empty: the dash key, `LocalInputComponent.ACTION_DASH`): the way the keys push, else the way the body faces.
##
## A ROLL, taken (the action component asked the server, predicted): its body DASHES at once (its movement
## profile's dash, predicted here and bounded by the server as any) and is held to the way it began for its
## length (`force_move`: a set roll, whatever keys are pressed after); the server puts its status on them (the
## foundation's Rolling: nothing hits them), judges a hit against when it was pressed, and tells the genre
## (`Genre::on_roll`). Its animation plays whole (`ability.<id>`, committed), the model facing the way it goes,
## here and on every other client. `rolled` tells the genre's client to let go of what a roll cancels (a swing, a
## block, a cast, a queue).
##
## NO ROLL IN THE AIR (unless the ability may): a press there, or while the player cannot act, waits for the
## ground and rolls as they land, within `foundation.roll_hold_ms`; later it lapses. A genre may call `roll()`
## itself (a key of its own); it never dashes on the key alone (the dash key rolls instead).

## A roll began on this entity (here, predicted: `direction` the way it goes; elsewhere: Vector2.ZERO).
signal rolled(ability_id: int, direction: Vector2)

## Its roll: the definition's `dodge_roll` unless a genre set one before bind. Null: it does not roll.
var ability: AbilityDef = null
## Until when (msec) this client's roll holds it: what a genre waits for before its next action.
var roll_until_ms: int = -100000
## When a press it could not take yet was made (msec), waiting for the ground; -1: none.
var asked_ms: int = -1

var _action: SpaceTimeActionComponent = null
var _input: LocalInputComponent = null
var _driver: AnimationDriverComponent = null
var _movement: SpaceTimeMovementComponent = null
var _status: StatusComponent = null

## Test seams. Empty in production.
var _clock_override: Callable = Callable()      # () -> msec
var _grounded_override: Callable = Callable()   # () -> bool
var _keys_override: Callable = Callable()       # () -> Vector2 (x right, y back)


## No tables: the roll is an ability (the action component's rows) and a status (the status component's).
func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ability == null and ent != null and ent.definition != null:
		ability = ent.definition.dodge_roll
	if ability != null and not ability.rolls:
		push_warning("RollComponent: '%s' is not a roll (tick its rolls): entity %d does not roll" % [ability.display_name, entity_id])
		ability = null
	set_process(false)
	set_process_unhandled_input(false)
	if ability == null or ent == null:
		return
	_action = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	_input = ent.find_component(LocalInputComponent) as LocalInputComponent
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_movement = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_status = ent.find_component(StatusComponent) as StatusComponent
	if _action != null:
		# Everyone's roll plays whole, here (predicted) and on every other client (its cooldown row).
		if not _action.started_elsewhere.is_connected(_on_started_elsewhere):
			_action.started_elsewhere.connect(_on_started_elsewhere)
		if is_local_authority and not _action.action_revoked.is_connected(_on_revoked):
			_action.action_revoked.connect(_on_revoked)
	if is_local_authority:
		set_process(true)
		set_process_unhandled_input(true)


# --- intent ----------------------------------------------------------------------------------

## ROLL NOW, the way the keys push: the predicted id, or -1 (it has no roll, it is cooling down, or it is in the
## air or cannot act: then the press waits for the ground, `asked_ms`).
func roll() -> int:
	if ability == null or _action == null:
		return -1
	var now: int = _now()
	if (not ability.roll_in_air and not grounded()) or not can_act():
		asked_ms = now
		return -1
	asked_ms = -1
	var dir: Vector2 = direction()
	var pid: int = _action.request_use(ability.id, 0, Vector3(dir.x, 0.0, dir.y))
	if pid < 0:
		return -1
	var ms: int = length_ms()
	if _input != null:
		_input.dash_once()
		# A SET ROLL (Regent's Rule, 2026-11-11: a roll forward then S went a short way): the way it began is the
		# way it goes for its whole length, whatever keys are pressed.
		_input.force_move(dir, float(ms) / 1000.0)
	roll_until_ms = now + ms
	_show(ability.id)
	rolled.emit(ability.id, dir)
	return pid


## Whether this client's roll holds it now.
func rolling() -> bool:
	return _now() < roll_until_ms


## The roll's length now (ms): its hot rule's value when it names one this game has, else its `roll_ms`.
func length_ms() -> int:
	return length_of(ability)


## `a`'s length now (ms). The client's twin of the server's `module::roll_ms`.
static func length_of(a: AbilityDef) -> int:
	if a == null:
		return 0
	if not a.roll_ms_rule.is_empty() and HotRules.has_rule(a.roll_ms_rule):
		return maxi(0, roundi(HotRules.number(a.roll_ms_rule)))
	return a.roll_ms


## How long until it rolls again and its whole cooldown, in seconds: (0, total) when ready.
func cooldown() -> Vector2:
	if ability == null:
		return Vector2.ZERO
	var left: float = _action.cooldown_remaining_sec(ability.id) if _action != null else 0.0
	return Vector2(left, float(ability.cooldown_ms) / 1000.0)


## The way a roll begun now goes (a world direction, as `InputFrame.move_dir`).
func direction() -> Vector2:
	var keys: Vector2 = _keys_override.call() if _keys_override.is_valid() else Vector2(
		Input.get_action_strength(LocalInputComponent.ACTION_RIGHT) - Input.get_action_strength(LocalInputComponent.ACTION_LEFT),
		Input.get_action_strength(LocalInputComponent.ACTION_BACK) - Input.get_action_strength(LocalInputComponent.ACTION_FORWARD))
	return direction_for(keys, _input.get_body_yaw() if _input != null else 0.0)


## `keys` (x right, y back, as pressed) turned to the world by the body's `yaw`; with none pressed, the way it
## faces (-Z at yaw 0). The server's twin: `roll::direction`.
static func direction_for(keys: Vector2, yaw: float) -> Vector2:
	if keys.length_squared() < 0.0001:
		return Vector2(-sin(yaw), -cos(yaw))
	return keys.normalized().rotated(-yaw)


## The input action that rolls: the ability's `key`, else the dash key.
func key_action() -> StringName:
	if ability == null:
		return &""
	return ability.key if not ability.key.is_empty() else LocalInputComponent.ACTION_DASH


## Whether the body is on the ground, as this client moves it.
func grounded() -> bool:
	if _grounded_override.is_valid():
		return bool(_grounded_override.call())
	if _movement == null:
		return true
	var s: MovementState = _movement.get_predicted_state() if is_local_authority else _movement.get_render_state()
	return s == null or s.grounded


## Whether its state and every effect let it act.
func can_act() -> bool:
	return _status == null or _status.can_act()


# --- time and keys --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if ability == null or not is_local_authority or event.is_echo():
		return
	var key: StringName = key_action()
	if not InputMap.has_action(key) or not event.is_action_pressed(key):
		return
	if _input != null and (_input.is_held_still() or (_input.capture_mouse and not MouseCapture.is_captured())):
		return
	roll()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_bound():
		tick()


## A press waiting for the ground: rolled as it lands, or let lapse. Public so tests can step it.
func tick() -> void:
	if asked_ms < 0:
		return
	if _now() - asked_ms > int(HotRules.number(&"foundation.roll_hold_ms")):
		asked_ms = -1
	elif (ability.roll_in_air or grounded()) and can_act():
		asked_ms = -1
		roll()   # refused now (cooling down): the press is spent, not kept


## Someone else's roll began (their cooldown row): it plays whole, facing the way it goes.
func _on_started_elsewhere(ability_id: int) -> void:
	if ability != null and ability_id == ability.id:
		_show(ability_id)
		rolled.emit(ability_id, Vector2.ZERO)


## The server refused this client's roll: it is not rolling (the dash it made is movement, bounded as any).
func _on_revoked(ability_id: int, _pid: int, _reason: String) -> void:
	if ability == null or ability_id != ability.id:
		return
	roll_until_ms = -100000
	if _input != null:
		_input.force_move(Vector2.ZERO, 0.0)


## Its animation whole (the driver fires `ability.<id>` itself as the use starts): committed, the model facing
## the way it moves.
func _show(ability_id: int) -> void:
	if _driver == null:
		return
	var s: float = _driver.shot_seconds(StringName("ability.%d" % ability_id))
	if s <= 0.0:
		s = float(length_ms()) / 1000.0
	_driver.commit_action(s)
	_driver.face_motion(s)


func _now() -> int:
	return int(_clock_override.call()) if _clock_override.is_valid() else Time.get_ticks_msec()
