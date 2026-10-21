@tool
class_name TraitAtom extends Resource
## ONE THING A TRAIT DOES (`TraitDef`, DECISIONS #275): one number the game reads at one place. A trait is
## a few of these, at least one of them its COST (or a condition: it only works sometimes).
##
## The words are the GAME's: `what` names a number its code looks up (Regent's Rule: "damage",
## "recovery", "draw_time", "work_time", "depletion"...), `on` the kind of action it touches ("basic",
## "heavy"; empty: every one). The foundation only carries them, multiplies them up and says whether a
## condition holds; each game lists the words it reads (`docs/HANDBOOK.md`, Traits).
##
## Either it MULTIPLIES (`mult`: 0.85 is 15 % less, 1.25 a quarter more) or it ADDS (`value`: a chance
## in percent, an amount in percent of something), as its `what` says.

## The number it changes, in the game's words ("damage", "recovery", "work_time", "stagger").
@export var what: StringName = &""
## The action it touches ("basic", "heavy", "skill"); empty: all of them.
@export var on: StringName = &""
## A multiplier (1: no change). 0.85: 15 % less; 1.3: 30 % more.
@export_range(0.05, 5.0, 0.01) var mult: float = 1.0
## Or an amount added, in percent (a chance: 10 = one in ten; an amount: 5 = 5 % of the damage).
@export_range(-100.0, 100.0, 0.1, "suffix:%") var value: float = 0.0
## Only WHEN (its condition): "always"; "target_below" / "target_above" its target's health in percent of
## its most (`threshold_pct`); "against" a target of a family (`against`: "beast", "humanoid").
@export_enum("always", "target_below", "target_above", "against") var condition: String = "always"
## For target_below / target_above: the target's health, in percent of its most.
@export_range(0.0, 100.0, 1.0, "suffix:%") var threshold_pct: float = 30.0
## For against: the family ("beast", "humanoid", "undead": a game's foes say theirs).
@export var against: StringName = &""
## This is what the trait COSTS (shown in the cost colour; every trait needs one, or a condition).
@export var cost: bool = false


func to_bake() -> Dictionary:
	return {"what": String(what), "on": String(on), "mult": mult, "value": value, "condition": condition,
		"threshold_pct": threshold_pct, "against": String(against), "cost": cost}


## What is wrong with it ("" for nothing), for its trait's `validate`.
func problem() -> String:
	if what == &"":
		return "an atom with no `what` (the number it changes)"
	if is_equal_approx(mult, 1.0) and is_zero_approx(value):
		return "the %s atom changes nothing (mult 1, value 0)" % what
	if condition == "against" and against == &"":
		return "the %s atom works against a family, but names none" % what
	return ""


## Whether it works only sometimes.
func conditional() -> bool:
	return not condition.is_empty() and condition != "always"
