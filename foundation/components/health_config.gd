class_name HealthConfig extends Resource
## Design-time presentation settings for `SpaceTimeHealthComponent`.
##
## Deliberately contains NO gameplay values. Max health, damage and death all live on the
## server (`health_state`, `apply_damage`); anything here that the server also knows would be a
## second source of truth waiting to disagree with it.

## Used for `get_ratio()` only until the first row arrives, so a bar drawn on the first frame
## is not dividing by zero.
@export var assumed_max: float = 100.0

## Ratio below which UI may show a "low health" treatment. A threshold for presentation, not a
## gameplay rule — nothing in the foundation reads it.
@export var low_ratio: float = 0.25
