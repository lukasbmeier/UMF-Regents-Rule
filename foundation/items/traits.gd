class_name Traits
## AN ITEM'S TRAITS, READ (DECISIONS #275): which it has (its row's `instance_data`, `"t":[ids]`), and what
## they make of one number at one action, multiplied up. Its twin is the server's `crate::traits`: the
## client predicts with this what the server decides with that (a swing's recovery, a bow's draw).
##
##   Traits.mult(ids, &"recovery", [&"basic"])                 0.85 with Balanced, 1.0 with none
##   Traits.value(ids, &"heal_on_hit", [&"basic"])             5.0 with Thirsting
##   Traits.mult(ids, &"damage", [&"heavy"], 20.0, &"beast")   a target at 20 % health, a beast
##
## The live dial `foundation.trait_strength_pct` scales them all (100: as authored; 0: none at all).

const KEY: String = "t"
const STRENGTH_RULE: StringName = &"foundation.trait_strength_pct"


## The trait ids an item's `instance_data` carries (none for none, or for data that is not JSON).
static func ids_of(instance_data: String) -> Array[int]:
	var out: Array[int] = []
	if instance_data.is_empty() or not instance_data.contains("\"t\""):
		return out
	var v: Variant = JSON.parse_string(instance_data)
	if v is Dictionary and (v as Dictionary).get(KEY) is Array:
		for x: Variant in (v as Dictionary)[KEY] as Array:
			out.append(int(x))
	return out


## Every trait, by content id (filled on first use; a suite may fill it with its own).
static var by_id: Dictionary = {}


## The trait with content id `trait_id`, or null. (Here, not on `TraitDef`: a static lookup there, beside
## a script naming both `TraitDef` and `TraitAtom`, kept the network addon's scripts alive at exit.)
static func def(trait_id: int) -> TraitDef:
	if by_id.is_empty() or Engine.is_editor_hint():
		for f: Dictionary in ContentLibrary.files():
			if not String(f["path"]).begins_with(ContentLibrary.folder_for(&"trait", String(f["owner"])) + "/"):
				continue
			var d: TraitDef = load(String(f["path"])) as TraitDef
			if d != null:
				by_id[d.id] = d
	return by_id.get(trait_id, null) as TraitDef


## The traits themselves (an unknown id is left out).
static func of(instance_data: String) -> Array[TraitDef]:
	var out: Array[TraitDef] = []
	for id: int in ids_of(instance_data):
		var d: TraitDef = Traits.def(id)
		if d != null:
			out.append(d)
	return out


## How strongly traits work now: 1.0 as authored (the hot rule, in percent).
static func strength() -> float:
	return maxf(HotRules.number(STRENGTH_RULE), 0.0) / 100.0


## `what` at an action tagged `ons` ([&"basic", &"combo_last"]), multiplied over every matching atom of
## the traits `ids`. `target_pct`: the target's health in percent of its most (< 0: unknown, and no
## health condition holds); `family`: the target's ("" unknown).
static func mult(ids: Array[int], what: StringName, ons: Array = [], target_pct: float = -1.0, family: StringName = &"") -> float:
	var k: float = strength()
	var m: float = 1.0
	for a: TraitAtom in _atoms(ids, what, ons, target_pct, family):
		m *= 1.0 + (a.mult - 1.0) * k
	return m


## `what` added up over every matching atom (a chance, an amount), in percent.
static func value(ids: Array[int], what: StringName, ons: Array = [], target_pct: float = -1.0, family: StringName = &"") -> float:
	var k: float = strength()
	var v: float = 0.0
	for a: TraitAtom in _atoms(ids, what, ons, target_pct, family):
		v += a.value * k
	return v


static func _atoms(ids: Array[int], what: StringName, ons: Array, target_pct: float, family: StringName) -> Array[TraitAtom]:
	var out: Array[TraitAtom] = []
	for id: int in ids:
		var d: TraitDef = Traits.def(id)
		if d == null:
			continue
		for a: TraitAtom in d.atoms:
			if a != null and a.what == what and (a.on == &"" or ons.has(a.on) or ons.has(String(a.on))) and holds(a, target_pct, family):
				out.append(a)
	return out


## Whether an atom's condition holds against a target at `target_pct` of its health, of `family`.
static func holds(a: TraitAtom, target_pct: float, family: StringName) -> bool:
	match a.condition:
		"", "always":
			return true
		"target_below":
			return target_pct >= 0.0 and target_pct < a.threshold_pct
		"target_above":
			return target_pct >= 0.0 and target_pct >= a.threshold_pct
		"against":
			return family != &"" and family == a.against
	return false


## An item's card: one line per trait, its name, what it gives and what it costs.
static func lines(instance_data: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: TraitDef in of(instance_data):
		out.append({"name": d.display_name, "gives": d.gives, "costs": d.costs})
	return out
