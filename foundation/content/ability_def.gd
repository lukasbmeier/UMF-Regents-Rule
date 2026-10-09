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
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if wind_up_ms < MIN_WIND_UP_MS:
		out.append("its wind-up (%d ms) is under the %d ms a round trip needs: players would see it land before it starts" % [wind_up_ms, MIN_WIND_UP_MS])
	return out
