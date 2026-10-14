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
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if judged and reach_m <= 0.0:
		out.append("it is judged by the referee but reaches nowhere: give it a reach")
	if wind_up_ms < MIN_WIND_UP_MS:
		out.append("its wind-up (%d ms) is under the %d ms a round trip needs: players would see it land before it starts" % [wind_up_ms, MIN_WIND_UP_MS])
	return out
