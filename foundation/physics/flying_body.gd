class_name FlyingBody extends RigidBody3D
## A BODY IN FLIGHT (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246): a `RigidBody3D` built from a
## `BodyDef`, its forces (`BodyForces`) applied every physics frame. THE ONE IMPLEMENTATION: the
## world's referee flies the real one (`BodyReferee`), the thrower's game flies its own from the
## moment it throws (`BodyLaunch`, `BodyComponent`), and the body's bench throws one with no server.
## The same script and the same numbers on both sides is what keeps the thrower's view and the
## referee's together (as `MovementModel` keeps a player's).
##
## Its clock is `frames`: physics frames since it was launched. The referee writes it with every row,
## so the thrower compares the referee's frame N with its own (`state_at`).
##
## It comes to rest by its own rule (slower than its def's rest speed while touching something, for its
## rest time): it then stops (frozen) until something moves it (`place`, `wake`). Godot's own sleeping
## is off: what "at rest" means is the def's, the same on both sides.

## It hit something (`other`: the collider, a level's body or another's; `speed` m/s into it).
signal hit(other: Object, pos: Vector3, normal: Vector3, speed: float)
## It came to rest.
signal came_to_rest()

## Layer 20: bodies (each other's). Layer 21: the people as bodies meet them (the referee's stand-ins).
const BODY_LAYER: int = 1 << 19
const PROXY_LAYER: int = 1 << 20
## What a body meets: the level (and walls things put up), other bodies, people.
const MASK: int = 1 | BODY_LAYER | PROXY_LAYER
## How many frames back it remembers where it was (4 s at 60 Hz: more than any round trip).
const HISTORY: int = 240
## Spinning slower than this (rad/s) counts as still, for rest.
const REST_SPIN: float = TAU
## The same thing hit again within this many frames is the same hit (a ball bouncing on its spot, a disc
## sliding down a trunk): left out of the next casts, so the next new thing it meets is found.
const REHIT_FRAMES: int = 8

var def: BodyDef = null
## Physics frames since it was launched.
var frames: int = 0
var at_rest: bool = false

## frame -> [pos, vel], the newest `HISTORY`.
var _history: Dictionary[int, Array] = {}
var _settling_s: float = 0.0
## collider RID -> the frame it was last hit (REHIT_FRAMES).
var _hit_at: Dictionary[RID, int] = {}
## Its velocity going into the step just run (what it had at the end of the last `_integrate_forces`):
## how fast it went INTO what the step's contacts say it met (DECISIONS #317).
var _prev_vel: Vector3 = Vector3.ZERO
var _query: PhysicsShapeQueryParameters3D = null
## Set from outside, applied at the next integration (the physics server's own state is only safe there).
var _pending_place: Dictionary = {}
var _pending_shift: Dictionary = {}


## A body for `def`: its shape, mass, bounce, friction, damping, gravity. Add it to the tree, then `launch`.
static func make(p_def: BodyDef) -> FlyingBody:
	var b := FlyingBody.new()
	b.def = p_def
	b.name = "FlyingBody"
	var shape := CollisionShape3D.new()
	shape.shape = p_def.make_shape()
	b.add_child(shape)
	var mat := PhysicsMaterial.new()
	mat.bounce = p_def.bounce
	mat.friction = p_def.friction
	b.physics_material_override = mat
	b.mass = p_def.mass_kg
	b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	b.linear_damp = p_def.linear_damp
	b.angular_damp = p_def.angular_damp
	b.gravity_scale = p_def.gravity_scale
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 6
	b.can_sleep = false
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	# Its def's `hits_bodies` off: off the bodies' layer and not looking for it, so no pair of bodies with
	# either one off ever meets (DECISIONS #317). `_contacts` casts with this mask, so its casts follow.
	b.collision_layer = BODY_LAYER if p_def.hits_bodies else 0
	b.collision_mask = MASK if p_def.hits_bodies else (1 | PROXY_LAYER)
	return b


## Set it going from `origin` at `vel`, turned by `rot` (a rotation vector), spinning `spin`, at frame
## `from_frame` (0: just thrown; a referee picking up one already flying: its row's frames). In the tree.
func launch(origin: Vector3, vel: Vector3, rot: Vector3, spin: Vector3, from_frame: int = 0) -> void:
	frames = from_frame
	at_rest = false
	freeze = false
	_settling_s = 0.0
	_history.clear()
	global_transform = Transform3D(basis_of(rot), origin)
	linear_velocity = vel
	angular_velocity = spin
	_prev_vel = vel
	_hit_at.clear()   # frames start again: what it hit before belongs to another flight
	_history[frames] = [origin, vel]
	reset_physics_interpolation()


## Put it somewhere else at once (the server moved it: a disc back at its lie), still or moving.
func place(pos: Vector3, vel: Vector3, rot: Vector3, spin: Vector3, rest: bool = false) -> void:
	_pending_place = {"pos": pos, "vel": vel, "rot": rot, "spin": spin, "rest": rest}
	if freeze and not rest:
		freeze = false


## Move its flight by `dpos` and `dvel` (the thrower's game nearing the referee's): applied at the next
## frame, and to what it remembers, so the next comparison is not counted twice.
func shift(dpos: Vector3, dvel: Vector3) -> void:
	var cur: Vector3 = _pending_shift.get("pos", Vector3.ZERO)
	var curv: Vector3 = _pending_shift.get("vel", Vector3.ZERO)
	_pending_shift = {"pos": cur + dpos, "vel": curv + dvel}
	for f: int in _history.keys():
		var e: Array = _history[f]
		_history[f] = [(e[0] as Vector3) + dpos, (e[1] as Vector3) + dvel]


## Start it moving again after a rest (something pushed it).
func wake() -> void:
	at_rest = false
	_settling_s = 0.0
	freeze = false


## Where it was at frame `f`, as [pos, vel], or [] when that is not remembered.
func state_at(f: int) -> Array:
	return _history.get(f, [])


## Its turn now, as a rotation vector (what `body_state.rot` holds).
func rot_vector() -> Vector3:
	var q: Quaternion = global_transform.basis.get_rotation_quaternion()
	return rotvec_of(q)


static func rotvec_of(q: Quaternion) -> Vector3:
	var angle: float = q.get_angle()
	if absf(angle) < 1e-6:
		return Vector3.ZERO
	return q.get_axis() * angle


static func basis_of(rot: Vector3) -> Basis:
	var angle: float = rot.length()
	if angle < 1e-6:
		return Basis.IDENTITY
	return Basis(rot / angle, angle)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _pending_place.is_empty():
		var p: Dictionary = _pending_place
		_pending_place = {}
		state.transform = Transform3D(basis_of(p["rot"] as Vector3), p["pos"] as Vector3)
		state.linear_velocity = p["vel"]
		state.angular_velocity = p["spin"]
		_prev_vel = p["vel"]
		_settling_s = 0.0
		at_rest = bool(p["rest"])
		if at_rest:
			set_deferred(&"freeze", true)
		return
	if not _pending_shift.is_empty():
		var t: Transform3D = state.transform
		t.origin += _pending_shift["pos"] as Vector3
		state.transform = t
		state.linear_velocity += _pending_shift["vel"] as Vector3
		_prev_vel += _pending_shift["vel"] as Vector3
		_pending_shift = {}
	if def != null and def.forces != null:
		def.forces.apply(state, def, state.step)
	if def != null and def.ground_drag > 0.0 and state.get_contact_count() > 0:
		var keep: float = maxf(0.0, 1.0 - def.ground_drag * state.step)
		state.linear_velocity *= keep
		state.angular_velocity *= keep
	# AFTER its forces and drag (DECISIONS #317): the cast ahead looks along the velocity the next step will
	# really run, so a shot its forces stopped on the floor never "hits" a target past it. What the step
	# met is read from its contacts and `_prev_vel`, which the forces do not touch, so stopping a body on
	# touch hides nothing.
	_contacts(state)
	frames += 1
	_history[frames] = [state.transform.origin, state.linear_velocity]
	_history.erase(frames - HISTORY)
	_rest(state)
	_prev_vel = state.linear_velocity


## WHAT IT HIT, AND HOW FAST, two ways (DECISIONS #246, #317):
## 1. What the step just run met (Jolt's own contacts). A body met within its first step (or launched
##    overlapping something), another body closing on it inside a step (head-on or from behind), a graze
##    the cast below missed: Jolt has already stopped or turned it, and nothing is left ahead to find.
##    Its speed into it is the larger of how fast it went in (its velocity going into the step against the
##    contact's normal) and the push it took (the contact's impulse over its mass, over 1 + its bounce: a
##    body hit from behind went away from what hit it). Slower than its def's `contact_speed_mps` is a touch, not a hit (a
##    ball rolling on the floor touches it every frame); 0 reports every contact.
## 2. What it is about to hit. Godot reports only the contacts of the step, and a fast hit bounces clear
##    within it (a ball into a person at 6 m/s showed as a 1 m/s touch after), so the hit is found ahead:
##    its own shape cast along this frame's motion, at the speed it goes into it.
## The same thing is said once: what either way reported is left out of both for `REHIT_FRAMES` (a cast's
## hit is not said again when its contact comes a frame later). The same on the referee and the
## thrower's game.
func _contacts(state: PhysicsDirectBodyState3D) -> void:
	if def == null:
		return
	for rid: RID in _hit_at.keys():
		if frames - int(_hit_at[rid]) > REHIT_FRAMES:
			_hit_at.erase(rid)
	var exclude: Array[RID] = [get_rid()]
	for n: PhysicsBody3D in get_collision_exceptions():
		if is_instance_valid(n):   # one freed since (a referee's stand-in for someone who left, or turned untouchable)
			exclude.append(n.get_rid())   # what it passes through (its thrower, as it leaves the hand)
	for i: int in state.get_contact_count():
		var rid: RID = state.get_contact_collider(i)
		if _hit_at.has(rid) or exclude.has(rid):
			continue
		var normal: Vector3 = state.get_contact_local_normal(i)   # out of what it met, toward this body
		var into: float = maxf(0.0, -_prev_vel.dot(normal))
		# The push, less what its bounce added: a bounce sends it back at `bounce` times what it came in at, so
		# the push is (1 + bounce) times the closing speed. Divided out, it reads as the cast ahead would.
		var dv: float = state.get_contact_impulse(i).length() / maxf(mass, 0.001) / (1.0 + def.bounce)
		var speed: float = maxf(into, dv)
		if def.contact_speed_mps > 0.0 and speed < def.contact_speed_mps:
			continue
		_hit_at[rid] = frames
		hit.emit(state.get_contact_collider_object(i), state.get_contact_collider_position(i), normal, speed)
	var motion: Vector3 = state.linear_velocity * state.step
	if motion.length_squared() < 1e-8:
		return
	if _query == null:
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = def.make_shape()
		_query.collision_mask = collision_mask
	exclude.append_array(_hit_at.keys())
	_query.exclude = exclude
	_query.transform = state.transform
	_query.motion = motion
	var space: PhysicsDirectSpaceState3D = state.get_space_state()
	var fractions: PackedFloat32Array = space.cast_motion(_query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return
	var at: Transform3D = state.transform
	at.origin += motion * fractions[1]
	_query.transform = at
	_query.motion = Vector3.ZERO
	var info: Dictionary = space.get_rest_info(_query)
	if info.is_empty():
		return
	_hit_at[info["rid"] as RID] = frames
	var normal: Vector3 = info["normal"]
	var speed: float = maxf(0.0, -state.linear_velocity.dot(normal))
	hit.emit(instance_from_id(int(info["collider_id"])), info["point"] as Vector3, normal, speed)


func _rest(state: PhysicsDirectBodyState3D) -> void:
	if def == null or at_rest:
		return
	var still: bool = state.linear_velocity.length() < def.rest_speed_mps \
		and state.angular_velocity.length() < REST_SPIN and state.get_contact_count() > 0
	_settling_s = (_settling_s + state.step) if still else 0.0
	if still and _settling_s >= def.rest_s:
		at_rest = true
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		set_deferred(&"freeze", true)
		came_to_rest.emit()
