class_name ShowcaseMovement extends SpaceTimeMovementComponent
## A SHOWCASE BODY'S MOVEMENT (2026-11-15, Luke: "instead of using the movement we have in game you manually are
## setting position"): the game's own `MovementModel`, the one the player's prediction and the referee step, with
## the character's own movement config (its walk, run and sprint, how fast it gets going and stops, how it turns, a
## roll's dash), stepped at the game's tick from the inputs the showcase gives it, standing on the showcase's land
## (`ground`) where the game stands on a level's collision. It is drawn between its last two ticks, as the game draws a
## body, and the animation driver reads it as it reads any body (`get_render_state`): so a showcase character starts,
## stops, turns and rolls as the game's do, its feet matched to its speed by the game's own blend.
##
## No rows and no server: it is never bound to a table. The actor (`ShowcaseActor`) steps it on the render clock.

## Where the ground is under (x, z) -> y; unset: the config's flat `ground_y`.
var ground: Callable = Callable()
## The next tick's input: () -> InputFrame (the actor's).
var steer: Callable = Callable()

var _prev: MovementState = MovementState.new()
var _cur: MovementState = MovementState.new()
var _owed: float = 0.0


## No tables: nothing here comes from the database.
func required_tables() -> Array[StringName]:
	return []


func optional_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	_render = _cur.duplicate()


## Stepped by its actor on the render clock (`advance`), never by the physics tick.
func _physics_process(_delta: float) -> void:
	pass


## The game's tick (s).
func tick_s() -> float:
	return 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))


## Stand it at `pos` (on the ground), still, facing `yaw`: a cut, not a move.
func place(pos: Vector3, yaw: float) -> void:
	var s := MovementState.new()
	s.pos = _on_ground(pos)
	s.yaw = yaw
	s.grounded = true
	_cur = s
	_prev = s.duplicate()
	_owed = 0.0
	_render = s.duplicate()


## Where it is now (its newest tick), and the way it faces.
func now_state() -> MovementState:
	return _cur


## Run the ticks `delta` owes (each with the input `steer` gives), and draw it between the last two.
func advance(delta: float) -> void:
	var dt: float = tick_s()
	_owed += maxf(delta, 0.0)
	while _owed >= dt:
		_owed -= dt
		var f: InputFrame = steer.call() as InputFrame if steer.is_valid() else InputFrame.new()
		var next: MovementState = MovementModel.simulate(_cur, f, _config(), dt, _resolve_on_land)
		# The facing rule `_step` keeps: the body turns to the look only while it moves, or when it is told to face.
		if f.face or f.move_dir.length_squared() > 0.0:
			next.yaw = f.look_yaw
		_prev = _cur
		_cur = next
	var u: float = clampf(_owed / dt, 0.0, 1.0)
	var r: MovementState = _cur.duplicate()
	r.pos = _prev.pos.lerp(_cur.pos, u)
	r.vel = _prev.vel.lerp(_cur.vel, u)
	r.yaw = lerp_angle(_prev.yaw, _cur.yaw, u)
	_render = r


## The model's collision step, on the showcase's land: it stands on the ground wherever it is (it never jumps here).
func _resolve_on_land(_prev_state: MovementState, next: MovementState) -> MovementState:
	var out: MovementState = next.duplicate()
	var y: float = _ground_y(out.pos)
	if out.pos.y <= y + 0.3 or out.grounded:
		out.pos = Vector3(out.pos.x, y, out.pos.z)
		out.vel = Vector3(out.vel.x, 0.0, out.vel.z)
		out.grounded = true
	return out


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground_y(p), p.z)


func _ground_y(p: Vector3) -> float:
	if ground.is_valid():
		return float(ground.call(p.x, p.z))
	return _config().ground_y
