class_name MovementModel extends RefCounted
## The movement simulation, shared by client prediction (LOCAL_PREDICTED) and the sidecar
## (SERVER_AUTHORITY). Same script, same engine on both sides — that is what makes reconciliation
## agree. server/src/sim.rs is a FROZEN gravity-only twin used only by MODULE-authority worlds.
##
## Phase 2: gravity + jump + flat ground. Phase 4 adds horizontal movement, slopes, and the
## config-gated branches (flap, dash, swim, mount). Collision is injected via `resolve_collision`
## (CharacterBody3D.move_and_slide on both client and sidecar).
##
## RULES
##  1. All math on pos/vel goes through Vector3 (f32). No scalar float intermediates — keeps the
##     model deterministic across client/sidecar builds and platforms.
##  2. Every change regenerates shared/golden/*.json (GDScript regression vectors).
##  3. New branches are config-driven inside this one model; never fork it per genre.

## `resolve_collision`: Callable(prev: MovementState, next: MovementState) -> MovementState.
## Client and sidecar pass a CharacterBody3D-backed resolver; tests pass an empty Callable.
static func simulate(state: MovementState, input: InputFrame, cfg: MovementConfig, dt: float,
		resolve_collision: Callable = Callable()) -> MovementState:
	var s: MovementState = state.duplicate()

	# 0. Horizontal movement. `move_dir` is already camera-relative and magnitude-clamped by
	#    LocalInputComponent, so this only turns a direction into velocity.
	#
	#    This step runs BEFORE jump so the existing gravity-only golden vectors are unchanged:
	#    with no input and no horizontal velocity, accelerating toward zero is a no-op. That is
	#    deliberate — a new branch must not silently rewrite the regression baseline.
	#
	#    Tier A note: the module's frozen twin does NOT replicate this. The module takes the
	#    client's `client_pos` within a per-frame speed envelope (DECISIONS #70), so motion is the
	#    client's and the server only bounds how fast it may claim to have gone.
	#    GAITS. A plain key press RUNS; sprint and slow are modifiers on top of it. `run_speed`
	#    is what `walk_speed` used to be, so every vector generated before gaits existed is
	#    unchanged — the new branches are only reachable with an input nothing used to send.
	var wish_speed: float = cfg.run_speed
	if input.sprint:
		wish_speed = cfg.sprint_speed
	elif input.slow:
		wish_speed = cfg.walk_speed
	#    Sideways and backwards are slower (both 1.0 unless a game says otherwise). `move_dir`
	#    arrives in WORLD space — `LocalInputComponent` has already turned the stick by the look
	#    direction — so it is turned BACK into the character's own frame to decide which gear
	#    this is, and out again to move. Skipping that made sprinting north a backwards sprint:
	#    the playtest measured 5.2 m/s, which is 8 x 0.65 exactly.
	var stick: Vector2 = input.move_dir.rotated(input.look_yaw)
	var lateral: float = stick.x * cfg.strafe_speed_mult
	var along: float = stick.y
	if along > 0.0:
		along = along * cfg.back_speed_mult
	var geared: Vector2 = Vector2(lateral, along).rotated(-input.look_yaw)
	var wish: Vector3 = Vector3(geared.x, 0.0, geared.y) * wish_speed
	var horizontal: Vector3 = Vector3(s.vel.x, 0.0, s.vel.z)
	# Airborne steering is deliberately weak; you commit to a jump.
	var control: float = 1.0 if s.grounded else cfg.air_control
	if wish.length_squared() > 0.0 and cfg.turn_rate_full > 0.0 and s.grounded 			and horizontal.length_squared() > TURN_FROM_SPEED_SQ:
		# A LIMITED TURN (OPEN_ITEMS A2): a heavy body at speed swings its velocity round at
		# `turn_rate_full` degrees a second, and slows while it points away from where it is told to
		# go. The look is never clamped (a clamped camera is nauseating): the overshoot is the body's.
		horizontal = turn_toward(horizontal, wish, cfg, dt)
	elif wish.length_squared() > 0.0:
		# Pushing AGAINST your own momentum brakes as hard as letting go and pushing the other
		# way together. Without this a reversal takes (2 x speed) / acceleration — 0.4 s from a
		# sprint at the old tuning — which is what "glidy" felt like. A quarter turn (dot = 0)
		# is unaffected. turning.json pins this branch (DECISIONS #81).
		var rate: Vector3 = Vector3(cfg.acceleration, 0.0, 0.0)
		if horizontal.dot(wish) < 0.0:
			rate = rate + Vector3(cfg.friction, 0.0, 0.0)
		horizontal = horizontal.move_toward(wish, rate.x * control * dt)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, Vector3(cfg.friction, 0.0, 0.0).x * control * dt)
	s.vel = Vector3(horizontal.x, s.vel.y, horizontal.z)

	# 0b. Dash (config-gated, §2.4). A fresh press adds a burst of horizontal speed along the
	#     wish direction (facing, when there is none), after this tick's acceleration so the
	#     whole burst lands; acceleration and friction then bring it back to normal speed.
	if s.dash_cooldown > 0:
		s.dash_cooldown -= 1
	if s.dash_left > 0:
		s.dash_left -= 1
	if cfg.dash_impulse > 0.0 and input.dash and not s.dash_held and s.dash_cooldown == 0:
		var dir: Vector3 = Vector3(input.move_dir.x, 0.0, input.move_dir.y)
		if dir.length_squared() == 0.0:
			dir = Vector3(-sin(input.look_yaw), 0.0, -cos(input.look_yaw))
		s.vel = s.vel + dir.normalized() * Vector3(cfg.dash_impulse, 0.0, 0.0).x
		s.dash_cooldown = cfg.dash_cooldown_ticks
		s.dash_left = cfg.dash_ticks
	s.dash_held = input.dash

	# 1. HOVER (config-gated, DECISIONS #236): a body on the wing holds itself at `hover_height`, rising or
	#    falling to it at `hover_climb` at most, steering as on the ground: no jump, no gravity.
	if cfg.hover_height > 0.0:
		var to: Vector3 = Vector3(0.0, cfg.hover_height, 0.0) - Vector3(0.0, s.pos.y, 0.0)
		var climb: Vector3 = (to * Vector3(4.0, 4.0, 4.0)).clamp(Vector3(0.0, -cfg.hover_climb, 0.0), Vector3(0.0, cfg.hover_climb, 0.0))
		s.vel = Vector3(s.vel.x, climb.y, s.vel.z)
		s.grounded = false
		s.jump_held = input.jump
		s.pos = s.pos + s.vel * dt
		if resolve_collision.is_valid():
			s = resolve_collision.call(state, s)
			s.grounded = false
		s.move_state = classify(s, input)
		return s

	# 1b. Jump from the ground; FLAP in the air (config-gated, §2.4, one per fresh press).
	#    A HELD key hops again only once the body has stopped rising: brushing an object's edge on
	#    the way up stands it "on the floor" for a tick, and a held Space jumped again from there
	#    (a playtest's "jumping near an object makes you double jump", 2026-10-20). A fresh press
	#    always jumps.
	if s.grounded:
		s.flaps_used = 0
		if input.jump and (not s.jump_held or s.vel.y <= 0.0):
			s.vel = Vector3(s.vel.x, Vector3(0.0, cfg.jump_velocity, 0.0).y, s.vel.z)
			s.grounded = false
	elif input.jump and not s.jump_held and s.flaps_used < cfg.flap_charges:
		s.vel = Vector3(s.vel.x, Vector3(0.0, cfg.flap_velocity, 0.0).y, s.vel.z)
		s.flaps_used += 1
	s.jump_held = input.jump

	# 2. Gravity (airborne only)
	if not s.grounded:
		s.vel = s.vel - Vector3(0.0, cfg.gravity, 0.0) * dt
	# 2b. GLIDE (config-gated, DECISIONS #236): holding jump after a flap, it falls no faster than
	#     `glide_fall_speed`; its way forward is its own.
	if cfg.glide_fall_speed > 0.0 and not s.grounded and input.jump and s.flaps_used > 0 \
			and s.vel.y < Vector3(0.0, -cfg.glide_fall_speed, 0.0).y:
		s.vel = Vector3(s.vel.x, Vector3(0.0, -cfg.glide_fall_speed, 0.0).y, s.vel.z)

	# 3. Integrate
	s.pos = s.pos + s.vel * dt

	# 4. Ground. With a collision resolver the WORLD is the ground: move_and_slide decides when
	#    we touch down, on whatever surface is there. The flat `ground_y` plane is only the
	#    stand-in for simulating without a world — the golden vectors and the module's gravity
	#    twin. Applying it on top of a real floor was a bug: on the landing frame it zeroed the
	#    fall velocity before the resolver moved the body, so the body could stop a few mm above
	#    the floor, never touch it, never be grounded, and never jump again (DECISIONS #80). It
	#    was also an invisible floor at y = ground_y over every pit and valley.
	if resolve_collision.is_valid():
		s = resolve_collision.call(state, s)
	else:
		var ground: Vector3 = Vector3(0.0, cfg.ground_y, 0.0)
		if s.pos.y <= ground.y and s.vel.y <= 0.0:
			s.pos = Vector3(s.pos.x, ground.y, s.pos.z)
			s.vel = Vector3(s.vel.x, 0.0, s.vel.z)
			s.grounded = true

	# 5. What the entity is doing, for animation and for everyone watching it (§2.5). Decided
	#    AFTER collision, so "grounded" is the world's answer, not the prediction's.
	s.move_state = classify(s, input)
	return s


## Below this horizontal speed an entity is standing still. 0.1 m/s, squared.
const IDLE_SPEED_SQ: float = 0.01
## Below this horizontal speed a turn-limited body turns freely (it starts off any way it is told).
## 0.5 m/s, squared.
const TURN_FROM_SPEED_SQ: float = 0.25


## THE LIMITED TURN (OPEN_ITEMS A2; FOWL_PLAY_CHASE 1.2: "sharp chicken turns make them overshoot").
## `h` is the body's horizontal velocity, `wish` where the input asks it to go (and how fast). The
## heading swings toward the wish by at most `turn_rate_at` degrees a second; the speed heads for
## the wish's speed times the cosine of the angle still to turn (none once it is a quarter turn or
## more away), so a body asked to go back the way it came brakes as it comes round, by `friction`,
## and gathers speed again by `acceleration`. Slower, it turns sharper (`turn_rate_slow`).
## The scalars are GDScript's (f64) and the vectors Godot's (f32): shared/golden/movement/
## turn_rate.json mirrors them op for op.
static func turn_toward(h: Vector3, wish: Vector3, cfg: MovementConfig, dt: float) -> Vector3:
	var heading: Vector2 = Vector2(h.x, h.z)
	var want: Vector2 = Vector2(wish.x, wish.z)
	var speed: float = heading.length()
	var off: float = heading.angle_to(want)
	var max_step: float = deg_to_rad(turn_rate_at(cfg, speed)) * dt
	var turn: float = clampf(off, -max_step, max_step)
	var dir: Vector2 = heading.normalized().rotated(turn)
	var aim: float = want.length() * maxf(cos(absf(off - turn)), 0.0)
	speed = move_toward(speed, aim, (cfg.acceleration if aim > speed else cfg.friction) * dt)
	return Vector3(dir.x, 0.0, dir.y) * speed


## How fast a turn-limited body turns at `speed` (degrees a second): `turn_rate_slow` at or below
## `turn_slow_speed`, `turn_rate_full` at its run speed and over, in a straight line between.
static func turn_rate_at(cfg: MovementConfig, speed: float) -> float:
	var slow: float = cfg.turn_rate_slow if cfg.turn_rate_slow > 0.0 else cfg.turn_rate_full
	if speed <= cfg.turn_slow_speed or cfg.run_speed <= cfg.turn_slow_speed:
		return slow
	return lerpf(slow, cfg.turn_rate_full, clampf((speed - cfg.turn_slow_speed) / (cfg.run_speed - cfg.turn_slow_speed), 0.0, 1.0))

## The foundation's movement states, from the post-step state and the input that produced it.
static func classify(s: MovementState, input: InputFrame) -> int:
	if s.dash_left > 0:
		return MovementState.Move.DASH
	if not s.grounded:
		return MovementState.Move.AIR
	var h: Vector3 = Vector3(s.vel.x, 0.0, s.vel.z)
	if h.length_squared() < IDLE_SPEED_SQ:
		return MovementState.Move.IDLE
	if input.sprint:
		return MovementState.Move.SPRINT
	return MovementState.Move.WALK if input.slow else MovementState.Move.RUN


## Convenience for tests and the reconciliation re-simulation loop.
static func simulate_sequence(initial: MovementState, inputs: Array[InputFrame], cfg: MovementConfig,
		dt: float, resolve_collision: Callable = Callable()) -> MovementState:
	var s: MovementState = initial
	for f in inputs:
		s = simulate(s, f, cfg, dt, resolve_collision)
	return s
