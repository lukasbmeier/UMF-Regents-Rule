@tool
class_name RuleEntry extends Resource
## ONE HOT RULE, as a rule set declares it (`RuleSetDef`, DECISIONS #201): a number the game is tuned
## by while it runs (a round's length, a range, a price), with its bounds and what it means. Its
## key is `<owner>.<name>`; the server serves its value in the `hot_rule` table, and an admin may
## change it live (`set_rule`) within `minimum`..`maximum`.
##
## NOT for anything a client predicts exactly (movement: `shared/movement_config.json`, the goldens):
## a hot value there would make clients and server disagree. The bake refuses those names.

enum Kind {
	## A real number (a length in seconds, a range in metres, a rate).
	NUMBER,
	## A whole number (a count, a price).
	INTEGER,
	## On or off.
	FLAG,
	## Words (a message, a name).
	TEXT,
}

## Its name within the set: lower case, words joined by underscores. The key is `<owner>.<name>`.
@export var name: StringName = &""
@export var kind: Kind = Kind.NUMBER
## The value it has unless this game or an admin says otherwise (NUMBER, INTEGER; FLAG: 0 or 1).
@export var number: float = 0.0
## The value it has, for TEXT.
@export var text: String = ""
## The smallest value an admin may set, and the largest (NUMBER, INTEGER).
@export var minimum: float = 0.0
@export var maximum: float = 1.0
## What the number is measured in, shown beside it ("s", "m", "coins").
@export var unit: String = ""
## What it does, for the person tuning it: the tweak panel and the dock show this.
@export_multiline var description: String = ""


## What is wrong with it, one sentence each.
func problems() -> Array[String]:
	var out: Array[String] = []
	var n: String = String(name)
	if n.is_empty() or n != n.to_lower() or n.contains(".") or n.contains(" ") or not n.is_valid_ascii_identifier():
		out.append("rule '%s': a name is lower case words joined by underscores" % n)
	match kind:
		Kind.NUMBER, Kind.INTEGER:
			if minimum > maximum:
				out.append("rule '%s': its minimum (%s) is above its maximum (%s)" % [n, minimum, maximum])
			elif number < minimum or number > maximum:
				out.append("rule '%s': its value %s is outside %s..%s" % [n, number, minimum, maximum])
			if kind == Kind.INTEGER and (number != floorf(number) or minimum != floorf(minimum) or maximum != floorf(maximum)):
				out.append("rule '%s': a whole-number rule has a fraction in it" % n)
		Kind.FLAG:
			if number != 0.0 and number != 1.0:
				out.append("rule '%s': a flag is 0 (off) or 1 (on)" % n)
	if description.strip_edges().is_empty():
		out.append("rule '%s': say what it does (its description is what the tuner reads)" % n)
	return out


## As the bake writes it.
func to_bake(owner: String) -> Dictionary:
	return {"key": "%s.%s" % [owner, name], "kind": Kind.keys()[kind].to_lower(), "number": number,
		"text": text, "min": minimum if kind != Kind.FLAG else 0.0, "max": maximum if kind != Kind.FLAG else 1.0,
		"unit": unit}
