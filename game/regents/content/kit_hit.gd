class_name KitHit extends Resource
## WHAT ONE OF A KIT'S ABILITIES DOES ON HIT (`HERBALISM_HUNTING_PREP.md` §7 step 5): a knockback push away from the
## attacker (`push_mps`, m/s, through the foundation's `push_entity`) and/or a status effect (`status` for `status_ms`,
## through `add_effect_internal`) when an unblocked hit lands on a living target.
##
## Kept on `KitDef.hits` beside `KitRole` so a foe kit's hamstring bite (Slowed) or wolf lunge (knockback) is authored in
## the Inspector and baked into `shared/content/regents/kit.json`.

## Which ability of this kit carries the on-hit effect.
@export var ability: AbilityDef = null
## Knockback push away from the attacker on an unblocked hit (m/s; 0: none).
@export_range(0.0, 30.0, 0.5, "suffix:m/s") var push_mps: float = 0.0
## PULLED IN instead (PROGRESS 110, the hook): drawn toward the attacker to stop this far from it (m; 0: no pull). The
## server picks the speed that carries it there (`rules::hit_push`). Never with `push_mps`.
@export_range(0.0, 5.0, 0.1, "suffix:m") var pull_to_m: float = 0.0
## THROWN UP (PROGRESS 110, a knock-up): its upward speed (m/s; 0: the push's usual small hop, 2 m/s).
@export_range(0.0, 15.0, 0.5, "suffix:m/s") var lift_mps: float = 0.0
## Status effect applied on an unblocked hit (null: none).
@export var status: StatusDef = null
## How long `status` lasts on the target (ms; 0 when `status` is null).
@export_range(0, 30000, 100, "suffix:ms") var status_ms: int = 0


func to_bake() -> Dictionary:
	return {
		"ability": ability.id if ability != null else 0,
		"push_mps": push_mps,
		"status": status.status if status != null else 0,
		"status_ms": status_ms,
		"pull_to_m": pull_to_m,
		"lift_mps": lift_mps,
	}
