@tool
class_name RuleOverride extends Resource
## THIS GAME'S VALUE FOR ANOTHER OWNER'S RULE (DECISIONS #201): a genre's rule set saying "in this
## game, `foundation.interact_range_m` is 4". The foundation's file is the same in every game, so a
## game sets its own values here, in its genre's set, never by editing the foundation's. One
## override per key in a game (the bake refuses two), within the rule's bounds.

## The rule's full key: `<owner>.<name>`, like `foundation.interact_range_m`.
@export var key: String = ""
## The value (NUMBER, INTEGER, FLAG).
@export var number: float = 0.0
## The value, for a TEXT rule.
@export var text: String = ""
## Why this game wants it different (for the people tuning it).
@export_multiline var reason: String = ""
