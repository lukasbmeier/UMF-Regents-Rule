@tool
class_name MovementProfileDef extends ContentDef
## HOW ONE KIND OF CHARACTER MOVES (docs/FOUNDATION_SYSTEMS.md milestone 1, DECISIONS #205): a
## chicken runs 4 m/s and flaps twice; a wolf runs 4.6 and does not. A character links to its
## profile (`EntityDefinition.movement_profile`); the entity it spawns then moves by these numbers,
## predicted on its player's client and simulated on the sidecar by the same model. A character
## with no profile moves by the foundation's default (`shared/movement_config.json`).
##
## A profile holds EVERY per-character movement number (New fills them from the default), so what
## you see is what it moves by. The network's numbers (tick rates, reconciliation) are the game's,
## not a character's, and stay in `shared/movement_config.json`.
##
## These are PARITY numbers: the client predicts with them exactly. Changing one in a build that
## friends have changes how their old build predicts (docs/rules/compatibility.md rule 4): bump
## `compat`, or keep the old profile and add a new one. They are not hot rules on purpose.

## Speeds (m/s): holding slow, a plain move, holding sprint.
@export_range(0.0, 20.0, 0.05, "suffix:m/s") var walk_speed: float = 1.2
@export_range(0.0, 30.0, 0.05, "suffix:m/s") var run_speed: float = 5.0
@export_range(0.0, 40.0, 0.05, "suffix:m/s") var sprint_speed: float = 8.0
## Sideways and backwards, as a share of the gait's speed (1: as fast as forward).
@export_range(0.1, 1.0, 0.01) var strafe_speed_mult: float = 0.7
@export_range(0.1, 1.0, 0.01) var back_speed_mult: float = 0.65
## How fast it gets up to speed, and how fast it stops (m/s per second). Lower is heavier.
@export_range(1.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 70.0
@export_range(1.0, 200.0, 0.5, "suffix:m/s²") var friction: float = 60.0
## How much it can steer in the air (0: not at all, 1: as on the ground).
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.3
## Jump: the upward speed it leaves the ground with, and the pull back down.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var jump_velocity: float = 8.0
@export_range(1.0, 60.0, 0.1, "suffix:m/s²") var gravity: float = 20.0
## The steepest ground it can walk up.
@export_range(0.0, 89.0, 0.5, "suffix:°") var max_slope_deg: float = 45.0
## Time after running off a ledge in which a jump still counts.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time_sec: float = 0.0
## FLAPS: extra jumps in the air (0: none), each this upward speed. Reset on landing.
@export_range(0, 5) var flap_charges: int = 0
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var flap_velocity: float = 6.0
## DASH: a burst of speed on a fresh press (0: no dash), how long it lasts and before it is back.
@export_range(0.0, 40.0, 0.1, "suffix:m/s") var dash_impulse: float = 0.0
@export_range(0, 600) var dash_cooldown_ticks: int = 45
@export_range(0, 120) var dash_ticks: int = 10
## TURNING AT SPEED (OPEN_ITEMS A2): how fast its run swings round, degrees a second, at full speed
## and at `turn_slow_speed` and under (0: the full rate). 0 turns at once. A heavy predator at
## 180 overshoots a chicken's sharp turn; its look is never slowed, only its body.
@export_range(0.0, 1440.0, 1.0, "suffix:°/s") var turn_rate_full: float = 0.0
@export_range(0.0, 1440.0, 1.0, "suffix:°/s") var turn_rate_slow: float = 0.0
@export_range(0.0, 20.0, 0.05, "suffix:m/s") var turn_slow_speed: float = 3.0

## The numbers a profile carries (all of `MovementConfig`'s that belong to a character).
const PROFILE_FIELDS: Array[StringName] = [
	&"walk_speed", &"run_speed", &"sprint_speed", &"strafe_speed_mult", &"back_speed_mult",
	&"acceleration", &"friction", &"air_control", &"jump_velocity", &"gravity", &"max_slope_deg",
	&"coyote_time_sec", &"flap_charges", &"flap_velocity", &"dash_impulse", &"dash_cooldown_ticks", &"dash_ticks",
	&"turn_rate_full", &"turn_rate_slow", &"turn_slow_speed",
]


func content_type() -> StringName:
	return &"movement"


## A new profile starts as the foundation's default movement, number for number.
func on_created() -> void:
	fill_from(MovementConfig.shared())


func to_bake() -> Dictionary:
	var out: Dictionary = {"id": id, "name": display_name}
	for f: StringName in PROFILE_FIELDS:
		out[String(f)] = get(f)
	return out


func validate() -> Array[String]:
	var out: Array[String] = super()
	if walk_speed > run_speed or run_speed > sprint_speed:
		out.append("its gaits are out of order: walk %s, run %s, sprint %s (each at least the one before)" % [walk_speed, run_speed, sprint_speed])
	if flap_charges > 0 and flap_velocity <= 0.0:
		out.append("it has %d flap(s) of no lift: give flap_velocity a value, or no flaps" % flap_charges)
	if turn_rate_slow > 0.0 and turn_rate_full > 0.0 and turn_rate_slow < turn_rate_full:
		out.append("it turns slower slow (%s°/s) than at speed (%s°/s): a body turns sharper when it is slower" % [turn_rate_slow, turn_rate_full])
	if dash_impulse > 0.0 and dash_ticks <= 0:
		out.append("its dash lasts no time: give dash_ticks a value")
	return out


## The full movement config an entity with this profile moves by: the game's (the network's
## numbers) with this profile's numbers in place of the default's.
func apply_to(base: MovementConfig) -> MovementConfig:
	var c: MovementConfig = base.duplicate() as MovementConfig
	for f: StringName in PROFILE_FIELDS:
		c.set(f, get(f))
	return c


## Fill every number from `cfg` (New does this from the foundation's default).
func fill_from(cfg: MovementConfig) -> void:
	for f: StringName in PROFILE_FIELDS:
		set(f, cfg.get(f))
