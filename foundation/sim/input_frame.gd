class_name InputFrame extends RefCounted
## One client tick of input. Runtime struct — NOT a Resource (allocation churn at 60 Hz).
## Wire shape must match server/src/sim.rs::InputFrame field-for-field (submit_input argument).

var seq: int = 0            # u32, monotonic per entity
var client_tick: int = 0    # u32
var move_dir: Vector2 = Vector2.ZERO   # normalised, f32 components
var look_yaw: float = 0.0   # f32
## Phase 3 Task 1. Aim pitch in radians. The movement model ignores it; the sidecar and the
## action layer use it for raycasts. Kept on the wire so aim is authoritative, not client-drawn.
var look_pitch: float = 0.0 # f32
var jump: bool = false
var sprint: bool = false
## Config-gated (§2.4): does nothing unless MovementConfig.dash_impulse > 0.
var dash: bool = false
## The slow-walk modifier (Ctrl). A plain key press runs; this is what makes it a walk.
var slow: bool = false
## Face `look_yaw` even standing still: something is being AIMED. Without it the body turns to
## the camera only while moving (DECISIONS #100). Set by `LocalInputComponent.hold_facing`.
var face: bool = false
## MODULE-authority (Tier A) worlds: where the client thinks it is after applying this frame; the
## module takes it within a per-frame speed envelope. The sidecar ignores it (it simulates the
## same model itself).
var client_pos: Vector3 = Vector3.ZERO
## The server's `correction_epoch` this client had applied when it produced the frame. The module
## consumes frames from an older epoch without moving (DECISIONS #71). Stamped by the movement
## component, never by hand.
var epoch: int = 0                # u32
## What the model says this frame's movement IS (MovementState.Move). Tier A has no simulation
## of its own, so the module mirrors this onto the row and everyone else animates from it.
## Stamped by the movement component, never by hand.
var move_state: int = 0           # u8

func to_dict() -> Dictionary:
	return {
		"seq": seq, "client_tick": client_tick,
		"move_x": move_dir.x, "move_y": move_dir.y,
		"look_yaw": look_yaw, "look_pitch": look_pitch,
		"jump": jump, "sprint": sprint,
		"client_pos": [client_pos.x, client_pos.y, client_pos.z],
		"epoch": epoch,
		"move_state": move_state,
		"dash": dash,
		"slow": slow,
		"face": face,
	}

## Read one off an `input_queue` row's nested `frame`. The sidecar's only way in: it replays
## what the client sent rather than sampling a keyboard it does not have.
##
## `client_pos` is deliberately NOT read. It is the Tier A claim, and a world with an authority
## does not take claims — it simulates the frame itself and writes what it gets.
static func from_row(row: RefCounted) -> InputFrame:
	var f := InputFrame.new()
	if row == null:
		return f
	# THE WIRE SPELLS THE DIRECTION AS TWO FLOATS. `sim.rs` has `move_x`/`move_y`, and so does the
	# generated struct and the adapter that builds it; `move_dir` is this class's own convenience.
	# Reading the convenience name off a real row yields null -> (0, 0), and the entity simply
	# never moves, with nothing logged.
	f.seq = int(row.get(&"seq"))
	f.client_tick = int(row.get(&"client_tick"))
	f.move_dir = Vector2(float(row.get(&"move_x")), float(row.get(&"move_y")))
	f.look_yaw = float(row.get(&"look_yaw"))
	f.look_pitch = float(row.get(&"look_pitch"))
	f.jump = bool(row.get(&"jump"))
	f.sprint = bool(row.get(&"sprint"))
	f.dash = bool(row.get(&"dash"))
	f.slow = bool(row.get(&"slow"))
	f.face = bool(row.get(&"face"))
	f.epoch = int(row.get(&"epoch"))
	f.move_state = int(row.get(&"move_state"))
	return f


static func from_dict(d: Dictionary) -> InputFrame:
	var f := InputFrame.new()
	f.seq = int(d.get("seq", 0))
	f.client_tick = int(d.get("client_tick", 0))
	f.move_dir = Vector2(float(d.get("move_x", 0.0)), float(d.get("move_y", 0.0)))
	f.look_yaw = float(d.get("look_yaw", 0.0))
	f.look_pitch = float(d.get("look_pitch", 0.0))
	f.jump = bool(d.get("jump", false))
	f.sprint = bool(d.get("sprint", false))
	var cp: Variant = d.get("client_pos")
	if cp is Array and cp.size() == 3:
		f.client_pos = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	f.epoch = int(d.get("epoch", 0))
	f.move_state = int(d.get("move_state", 0))
	f.dash = bool(d.get("dash", false))
	f.slow = bool(d.get("slow", false))
	f.face = bool(d.get("face", false))
	return f

## Argument array in the order the `submit_input` reducer expects one frame.
func to_reducer_args() -> Array:
	return [seq, client_tick, move_dir.x, move_dir.y, look_yaw, look_pitch, jump, sprint, client_pos, epoch, move_state, dash, slow, face]
