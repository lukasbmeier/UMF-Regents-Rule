class_name MovementConfig extends Resource
## Movement tunables. The single source of truth is `shared/movement_config.json`: the Rust
## module bakes it in at build time (server/build.rs) and the client reads it through `shared()`.
##
## It used to be that only Rust read the JSON. The client used `MovementConfig.new()`, i.e. the
## defaults hardcoded below, and the codegen'd .tres was referenced by nothing — so editing the
## JSON changed the server's speed envelope and not the client's movement. The defaults below
## are kept equal to the JSON, and a unit test fails the moment they drift (DECISIONS #81).

const SHARED_JSON: String = "res://shared/movement_config.json"
static var _shared: MovementConfig = null


## The project's movement config, parsed once from the shared JSON. What every movement
## component uses unless its scene assigns a specific one.
static func shared() -> MovementConfig:
	if _shared == null:
		_shared = from_json_file(SHARED_JSON)
	return _shared

@export_group("Ground")
## THREE GAITS. Running is what a key press does; the other two are modifiers. The numbers are
## not taste — they are what the animation clips are authored to travel at, measured off the
## planted foot (`Walk_Fwd` 0.96 m/s, `Jog_Fwd` 5.14, `Sprint` 7.84). A character moving at a
## speed its clip was not authored for skates, and skating is what reads as floaty.
@export var walk_speed: float = 1.2
@export var run_speed: float = 5.0
@export var sprint_speed: float = 8.0
## Sideways and backwards are slower than forwards — every locomotion set is authored that way
## (this one strafes at 2.0 m/s against a 5.1 m/s jog), and a character sliding sideways at full
## running speed skates however good the animation is. The golden files that predate these carry
## 1.0 for both in their own embedded config, which is what keeps their vectors describing this
## model exactly.
@export var strafe_speed_mult: float = 0.7
@export var back_speed_mult: float = 0.65
@export var acceleration: float = 70.0
@export var friction: float = 60.0
@export var max_slope_deg: float = 45.0
@export var ground_y: float = 0.0

@export_group("Air")
@export var air_control: float = 0.3
@export var jump_velocity: float = 8.0
@export var gravity: float = 20.0
@export var coyote_time_sec: float = 0.0

@export_group("Flap and dash (PHASE4_SPEC §2.4, off by default)")
## Mid-air jumps allowed before landing. 0 disables flapping.
@export var flap_charges: int = 0
@export var flap_velocity: float = 6.0
## Horizontal speed added by a dash. 0 disables dashing.
@export var dash_impulse: float = 0.0
@export var dash_cooldown_ticks: int = 45
## How many ticks move_state reads DASH after one.
@export var dash_ticks: int = 10

@export_group("Reconciliation")
@export var reconcile_accept_epsilon: float = 0.02
@export var reconcile_snap_threshold: float = 1.0
@export var reconcile_smooth_time: float = 0.1
@export var remote_interp_delay: float = 0.1

const FIELDS: Array[StringName] = [
	&"walk_speed", &"run_speed", &"sprint_speed", &"strafe_speed_mult", &"back_speed_mult", &"acceleration", &"friction", &"max_slope_deg", &"ground_y",
	&"air_control", &"jump_velocity", &"gravity", &"coyote_time_sec",
	&"reconcile_accept_epsilon", &"reconcile_snap_threshold", &"reconcile_smooth_time", &"remote_interp_delay",
	&"flap_charges", &"flap_velocity", &"dash_impulse", &"dash_cooldown_ticks", &"dash_ticks",
]

static func from_dict(d: Dictionary) -> MovementConfig:
	var c := MovementConfig.new()
	for f in FIELDS:
		if d.has(String(f)):
			# JSON numbers are all floats; `set` converts to an int property's type.
			c.set(f, d[String(f)])
	return c

static func from_json_file(path: String) -> MovementConfig:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("MovementConfig: cannot read %s" % path)
		return MovementConfig.new()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("MovementConfig: %s is not a JSON object" % path)
		return MovementConfig.new()
	return from_dict(parsed)
