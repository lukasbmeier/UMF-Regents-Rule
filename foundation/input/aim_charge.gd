class_name AimCharge extends Node
## AIM AND CHARGE (DECISIONS #249): hold a key to charge a throw where you look, let go to throw it.
## A genre adds one to its game scene (a disc golfer's backhand and forehand, a hen's egg): each of
## `actions` is a STYLE (its index: LMB a backhand, RMB a forehand). While one is held:
##   - its meter fills (`ChargeMeter`: `charge_s`, overcharged past `over_from`)
##   - the player's body faces where they look (`hold_facing`), so a throw behind them is thrown by
##     someone who turned round
##   - the mouse's up and down sets the RELEASE ANGLE instead of tilting the view (`angle_from_mouse_y`:
##     -1 to 1, up positive; a disc's hyzer and anyzer), the view's pitch held where it was
## Let go: `released(style, power, over, aim, angle)`; another style, or `cancel()` (hit while
## charging), puts it down. `ChargeBar` draws it. Input only: what the genre throws is its claim,
## bounded by the server (rule 13).

signal started(style: int)
signal changed(style: int, value: float, angle: float)
signal released(style: int, power: float, over: bool, aim: Vector3, angle: float)
signal cancelled(style: int)

## The keys, one a style (their index is the style the signals say).
@export var actions: Array[StringName] = [&"attack"]
## Seconds from empty to full, and the share past which it is overcharged.
@export_range(0.05, 10.0, 0.05, "suffix:s") var charge_s: float = 1.2
@export_range(0.0, 1.0, 0.01) var over_from: float = 0.95
@export var over_mode: ChargeMeter.Over = ChargeMeter.Over.HOLD
## The body faces the aim while charging.
@export var face_aim: bool = true
## The mouse's up and down sets the release angle while charging (the view's pitch held).
@export var angle_from_mouse_y: bool = true
## How much angle a radian of mouse movement gives (the view would have tilted that much).
@export_range(0.0, 10.0, 0.05) var angle_per_radian: float = 1.5
## Off: nothing starts a charge (a genre's phase in which you cannot throw).
@export var enabled: bool = true

var meter: ChargeMeter = null
## The style held now (-1: none), and its release angle (-1 to 1).
var style: int = -1
var angle: float = 0.0

var _input: LocalInputComponent = null
## The charge was started by its key (so letting the key go, or the mouse, ends it), not by `press`.
var _by_key: bool = false

const REASON: StringName = &"aim_charge"


func _ready() -> void:
	meter = ChargeMeter.new(charge_s, over_from, over_mode)


## Use this player's input (tests; by default the local player's, found when needed).
func use_input(input: LocalInputComponent) -> void:
	_input = input


func is_charging() -> bool:
	return style >= 0


## Where a throw now would go: the view's heading and pitch, as a direction.
func aim() -> Vector3:
	var input: LocalInputComponent = _local_input()
	if input == null:
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		return -cam.global_basis.z if cam != null else Vector3.FORWARD
	return Basis.from_euler(Vector3(input.get_look_pitch(), input.get_look_yaw(), 0.0)) * Vector3.FORWARD


## Start charging style `s` (its key went down). Another already held is put down.
func press(s: int) -> void:
	if not enabled or s < 0 or s >= actions.size():
		return
	if style >= 0:
		cancel()
	_by_key = false
	style = s
	angle = 0.0
	meter.begin()
	var input: LocalInputComponent = _local_input()
	if input != null:
		if face_aim:
			input.hold_facing(REASON, true)
		if angle_from_mouse_y:
			input.borrow_mouse_y(REASON, true)
			input.take_borrowed_y()
	started.emit(s)


## Let go of what is charging: thrown.
func release() -> void:
	if style < 0:
		return
	var s: int = style
	var r: Dictionary = meter.release()
	var a: float = angle
	var dir: Vector3 = aim()
	_let_go()
	released.emit(s, float(r["power"]), bool(r["over"]), dir, a)


## Put it down without throwing.
func cancel() -> void:
	if style < 0:
		return
	var s: int = style
	meter.cancel()
	_let_go()
	cancelled.emit(s)


func _let_go() -> void:
	style = -1
	_by_key = false
	var input: LocalInputComponent = _local_input()
	if input != null:
		input.hold_facing(REASON, false)
		input.borrow_mouse_y(REASON, false)


func _process(delta: float) -> void:
	_read_keys()
	if style < 0:
		return
	meter.step(delta)
	var input: LocalInputComponent = _local_input()
	if input != null and angle_from_mouse_y:
		angle = clampf(angle + input.take_borrowed_y() * angle_per_radian, -1.0, 1.0)
	changed.emit(style, meter.value, angle)


func _read_keys() -> void:
	if not MouseCapture.is_captured():
		if style >= 0 and _by_key:
			cancel()   # the mouse was let go (Escape): a throw is not let fly behind a menu
		return
	if style >= 0:
		if _by_key and InputMap.has_action(actions[style]) and not Input.is_action_pressed(actions[style]):
			release()
		return
	for i: int in actions.size():
		if InputMap.has_action(actions[i]) and Input.is_action_just_pressed(actions[i]):
			press(i)
			_by_key = true
			return


func _local_input() -> LocalInputComponent:
	if _input == null or not is_instance_valid(_input):
		var me: SpaceTimeEntity = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id) as SpaceTimeEntity
		_input = me.find_component(LocalInputComponent) as LocalInputComponent if me != null else null
	return _input


func _exit_tree() -> void:
	if style >= 0:
		cancel()
