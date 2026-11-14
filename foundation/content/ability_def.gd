@tool
class_name AbilityDef extends ContentDef
## AN ABILITY (PHASE3_SPEC Task 12): what `use_ability` does on the server. Baked to
## `shared/content/<owner>/ability.json`; the module seeds the `ability_def` table from it at
## `init`. Its `id` is the `ability_id` a client asks for.

## How long after a use before it can be used again.
@export_range(0, 60000, 10, "suffix:ms") var cooldown_ms: int = 800
## How far from the user its target may be. 0: untargeted (in a Tier A world it always misses: the
## module has no hit test; a sidecar has).
@export_range(0.0, 50.0, 0.1, "suffix:m") var range_m: float = 2.0
## The time before it lands. At least 100 ms, so the predicted start animation covers a round trip
## before the server's answer arrives.
@export_range(0, 5000, 10, "suffix:ms") var wind_up_ms: int = 150
## Health taken from what it hits.
@export_range(0.0, 1000.0, 0.5) var damage: float = 10.0
## The animation the user plays (a semantic name from the character's AnimationSet: `interact`,
## `ability.3`...). Presentation only: not baked, the server does not know it.
@export var animation: StringName = &"interact"
## THE KEY THAT USES IT (DECISIONS #237): an input action (`power`: the right mouse button). Empty:
## the attack key, for a character's first ability; a genre may use it from its own keys (a hen's
## two picked abilities on 1 and 2).
@export var key: StringName = &""

@export_group("Judged by a referee")
## JUDGED BY THE WORLD'S REFEREE (DECISIONS #226): a sidecar decides what it hits, against the
## level's walls and everyone where its user saw them (rewound by what they saw, at most
## `foundation.rewind_max_ms`), as it lands (`wind_up_ms` after the use). Untargeted: it hits the
## first thing in its path. Off: the module's own coarse test (its target in `range_m`).
@export var judged: bool = false
## How far its sweep goes, along the user's heading (a pounce's lunge).
@export_range(0.0, 20.0, 0.05, "suffix:m") var reach_m: float = 1.4
## How wide the sweep is: a ball of this radius, carried along it.
@export_range(0.05, 3.0, 0.01, "suffix:m") var radius_m: float = 0.35
## How high above the user's feet it sweeps.
@export_range(0.0, 3.0, 0.05, "suffix:m") var height_m: float = 0.6

@export_group("The user's body")
## IT LUNGES (DECISIONS #232): as its wind-up ends the user's body is thrown forward by its movement
## profile's dash (`dash_impulse`, along where it is going or facing), so others see a pounce, not a
## swipe. A character with an ability that lunges dashes only so: its dash key does nothing.
@export var lunges: bool = false

@export_group("A dodge roll")
## A DODGE ROLL (DECISIONS #309): on its key (`key`; empty: the dash key) its user's body is thrown the way their
## keys push (else the way it faces) by its movement profile's DASH, at once, and held to that way for `roll_ms`;
## for as long, `roll_status` holds them (a status that is not `hittable`: nothing a referee judges hits them). A
## press in the air waits for the ground (`foundation.roll_hold_ms`); the server refuses one there, unless
## `roll_in_air`. A character rolls with the one its `dodge_roll` names (`RollComponent`). The animation it plays
## is `animation` (`ability.<id>` in the character's set), whole, the model facing the way it goes.
@export var rolls: bool = false
## The status that holds its user while it lasts, put on as an EFFECT beside their state (the foundation's
## Rolling: not hittable, no sprint, no jump).
@export var roll_status: StatusDef
## How long it lasts: the unhittable window and the time its way is held.
@export_range(0, 3000, 10, "suffix:ms") var roll_ms: int = 550
## A HOT RULE that gives its length live (a game's own: `regents.roll_ms`), over `roll_ms`. Empty: `roll_ms`.
@export var roll_ms_rule: StringName = &""
## May begin in the air. Off: no roll in the air.
@export var roll_in_air: bool = false

## The shortest wind-up the network allows (ARCHITECTURE: the RTT floor).
const MIN_WIND_UP_MS: int = 100


func content_type() -> StringName:
	return &"ability"


func to_bake() -> Dictionary:
	return {
		"ability_id": id,
		"cooldown_ms": cooldown_ms,
		"range": range_m,
		"wind_up_ms": wind_up_ms,
		"damage": damage,
		"name": display_name,
		"judged": judged,
		"reach": reach_m,
		"radius": radius_m,
		"height": height_m,
		"lunges": lunges,
	}.merged(_roll_bake())


## A roll's own keys, only on a roll: every other ability bakes as it did (no game's bake goes stale).
func _roll_bake() -> Dictionary:
	if not rolls:
		return {}
	return {
		"rolls": true,
		"roll_status": roll_status.status if roll_status != null else -1,
		"roll_ms": roll_ms,
		"roll_ms_rule": String(roll_ms_rule),
		"roll_in_air": roll_in_air,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if judged and reach_m <= 0.0:
		out.append("it is judged by the referee but reaches nowhere: give it a reach")
	if rolls:
		if roll_status == null:
			out.append("it rolls but has no status to hold its user while it lasts: pick one (the foundation's Rolling)")
		elif roll_status.hittable:
			out.append("it rolls, but its status '%s' can be hit: a roll that does not dodge (untick its hittable)" % roll_status.display_name)
		if judged:
			out.append("it rolls and is judged: a roll hits nothing, turn judged off")
		if lunges:
			out.append("it rolls and lunges: a roll is its own dash, turn lunges off")
		if roll_ms <= 0 and roll_ms_rule.is_empty():
			out.append("it rolls for no time: give roll_ms a value")
	if wind_up_ms < MIN_WIND_UP_MS:
		out.append("its wind-up (%d ms) is under the %d ms a round trip needs: players would see it land before it starts" % [wind_up_ms, MIN_WIND_UP_MS])
	return out
