class_name MovementState extends RefCounted
## Simulation state for one entity. Runtime struct. Wire shape mirrors server/src/sim.rs::MovementState.
##
## RULE: all arithmetic on this state happens through Vector3 so it stays in f32 and is
## deterministic across client and sidecar builds. Never `pos.y += some_float * dt` (f64).
## Build a Vector3 and add it.

var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var grounded: bool = true
## u8 on the wire. The foundation's values are `Move`, assigned by MovementModel every step; a
## genre numbers its own from 100 (the same convention as entity kinds and challenge kinds).
var move_state: int = 0

## PHASE4_SPEC §2.5. SWIM and MOUNT are reserved: nothing assigns them yet.
## RUN is appended rather than inserted: these numbers are on the wire and in every golden
## file, so the existing ones keep their meaning. WALK is now the SLOW gait (the modifier), RUN
## is what a plain key press does.
enum Move { IDLE = 0, WALK = 1, SPRINT = 2, AIR = 3, DASH = 4, SWIM = 5, MOUNT = 6, RUN = 7 }
const GENRE_MOVE_STATES_FROM: int = 100

## Model bookkeeping for the config-gated branches (§2.4). GDScript-only: the frozen twin and
## the wire row do not carry them. `*_held` turn a held key into a press, so holding jump in the
## air cannot spend every flap charge on consecutive frames.
var jump_held: bool = false
var dash_held: bool = false
var flaps_used: int = 0
var dash_cooldown: int = 0
var dash_left: int = 0

func duplicate() -> MovementState:
	var s := MovementState.new()
	s.pos = pos
	s.vel = vel
	s.yaw = yaw
	s.grounded = grounded
	s.move_state = move_state
	s.jump_held = jump_held
	s.dash_held = dash_held
	s.flaps_used = flaps_used
	s.dash_cooldown = dash_cooldown
	s.dash_left = dash_left
	return s

## Take `own`'s bookkeeping (held keys, flaps used, the dash's cooldown and length): the client's own,
## which a server row does not carry. A correction rewinds to the row WITH what this client knew at that
## seq; rewound without it, a dash's cooldown was gone after any correction, and the next press dashed
## at once (DECISIONS #264). Returns self.
func take_bookkeeping(own: MovementState) -> MovementState:
	if own != null:
		jump_held = own.jump_held
		dash_held = own.dash_held
		flaps_used = own.flaps_used
		dash_cooldown = own.dash_cooldown
		dash_left = own.dash_left
	return self

## Largest absolute component difference across pos and vel. Used by tests and reconciliation.
func max_error(other: MovementState) -> float:
	var dp: Vector3 = (pos - other.pos).abs()
	var dv: Vector3 = (vel - other.vel).abs()
	return maxf(maxf(dp.x, maxf(dp.y, dp.z)), maxf(dv.x, maxf(dv.y, dv.z)))

func approx_equals(other: MovementState, eps: float) -> bool:
	return max_error(other) <= eps and grounded == other.grounded

func to_dict() -> Dictionary:
	return {"pos": [pos.x, pos.y, pos.z], "vel": [vel.x, vel.y, vel.z],
			"yaw": yaw, "grounded": grounded, "move_state": move_state}

static func from_dict(d: Dictionary) -> MovementState:
	var s := MovementState.new()
	var p: Array = d.get("pos", [0, 0, 0])
	var v: Array = d.get("vel", [0, 0, 0])
	s.pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	s.vel = Vector3(float(v[0]), float(v[1]), float(v[2]))
	s.yaw = float(d.get("yaw", 0.0))
	s.grounded = bool(d.get("grounded", true))
	s.move_state = int(d.get("move_state", 0))
	s.jump_held = bool(d.get("jump_held", false))
	s.dash_held = bool(d.get("dash_held", false))
	s.flaps_used = int(d.get("flaps_used", 0))
	s.dash_cooldown = int(d.get("dash_cooldown", 0))
	s.dash_left = int(d.get("dash_left", 0))
	return s

## Build from a generated `movement_state` row (Phase 3 components use this).
static func from_row(row: RefCounted) -> MovementState:
	var s := MovementState.new()
	s.pos = row.get(&"pos")
	s.vel = row.get(&"vel")
	s.yaw = float(row.get(&"yaw"))
	s.grounded = bool(row.get(&"grounded"))
	s.move_state = int(row.get(&"move_state"))
	return s

func _to_string() -> String:
	return "MovementState(pos=%s vel=%s grounded=%s)" % [pos, vel, grounded]
