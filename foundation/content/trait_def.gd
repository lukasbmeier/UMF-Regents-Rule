@tool
class_name TraitDef extends ContentDef
## A TRAIT (DECISIONS #275; the owner's design, `docs/regents_rule/LOOT_AND_STYLES.md` §2 and §6): a
## qualitative change to how an item plays, never to its Power. "Balanced: basics recover 15 % faster,
## abilities do 10 % less." EVERY TRAIT TRADES OR IS SITUATIONAL, NEVER A PURE GAIN: a trait with only
## gains becomes the one everyone must have within a week, so the bake refuses one with no cost atom and
## no condition.
##
## What it does is its ATOMS (`TraitAtom`): numbers the game reads where they act. An item carries its
## traits' ids in its row's `instance_data` (`"t":[40001]`): what it was built with (a handle) or what it
## rolled as it dropped. `Traits` (and the server's `crate::traits`) reads them and multiplies them up;
## the live dial `foundation.trait_strength_pct` scales every trait at once (0: all off).

## Its name in code ("balanced").
@export var key: StringName = &""
## The items it may be on, by the game's item tags ("weapon", "melee", "bow", "tool", "axe"): one in
## common is enough.
@export var applies_to: Array[StringName] = []
## Whether a dropped item may roll it (a handle's own trait may be only the handle's).
@export var rollable: bool = true
## What it gives, in words, as the item's card shows it ("basics recover 15% faster").
@export var gives: String = ""
## What it costs, in words ("abilities do 10% less damage"); a situational trait may leave it empty.
@export var costs: String = ""
## What it does.
@export var atoms: Array[TraitAtom] = []


func content_type() -> StringName:
	return &"trait"


func why_no_workbench() -> String:
	return "a few numbers and two lines of words: the item it is on is where it is tried (its bench, a fight)"


func summary() -> String:
	return "%s: %s%s" % [", ".join(applies_to.map(func(t: StringName) -> String: return String(t))), gives,
		(" / " + costs) if not costs.is_empty() else ""]


func to_bake() -> Dictionary:
	return {"id": id, "key": String(key), "name": display_name, "applies_to": applies_to.map(func(t: StringName) -> String: return String(t)),
		"rollable": rollable, "atoms": atoms.map(func(a: TraitAtom) -> Dictionary: return a.to_bake() if a != null else {})}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (\"balanced\")")
	if applies_to.is_empty():
		out.append("it applies to nothing: name an item tag (\"weapon\", \"tool\")")
	if gives.strip_edges().is_empty():
		out.append("it does not say what it gives")
	if atoms.is_empty():
		out.append("it has no atoms: it does nothing")
	var has_cost: bool = false
	var situational: bool = false
	for a: TraitAtom in atoms:
		if a == null:
			out.append("one of its atoms is empty")
			continue
		var p: String = a.problem()
		if not p.is_empty():
			out.append(p)
		has_cost = has_cost or a.cost
		situational = situational or a.conditional()
	if not atoms.is_empty() and not has_cost and not situational:
		out.append("it is a pure gain: every trait trades (an atom marked `cost`) or works only sometimes (a `condition`)")
	if has_cost and costs.strip_edges().is_empty():
		out.append("it has a cost, but does not say it (`costs`)")
	return out


## Whether it may be on an item with these tags.
func fits(item_tags: Array) -> bool:
	for t: StringName in applies_to:
		if item_tags.has(t) or item_tags.has(String(t)):
			return true
	return false
