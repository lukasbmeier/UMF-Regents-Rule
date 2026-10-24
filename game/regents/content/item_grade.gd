@tool
class_name RegentsGrade
## AN ITEM'S GRADE AND POWER (owner, 2026-10-20, `docs/regents_rule/LOOT_AND_STYLES.md`).
##
##   QUALITY   a made item's 0-1000 (thousandths, its row's `instance_data` `{"q":734}`): the round that
##             made it sets it, and it adds a little per point (a weapon's damage, a tool's speed).
##   GRADE     a BAND of quality, for the colour, the name and (later) the trait count: Common, Fine
##             from `regents.grade_fine_q` (400), Masterwork from `regents.grade_masterwork_q` (800).
##             A material (no quality) has none. The colours are the style's (`UiStyle.grade_colors`).
##   TIER      the item itself (copper, iron): its `weapon_damage_pct`. Tier DOMINATES: the best of a
##             tier never reaches the worst of the next (`tier_overlaps`; an item's `validate` says so).
##   POWER     the one number to compare: the weapon's damage in percent of its kit's, its quality
##             included (an iron weapon 100 to 120, a copper one 70 to 84); ammo its own percent.
##             Tools show their tier and speed instead (a tier is what a node asks for).

const NAMES: PackedStringArray = ["Common", "Fine", "Masterwork"]
## Quality adds up to a fifth to a weapon's hits: the server's `hit_damage` (genre/regents/mod.rs).
const QUALITY_DAMAGE_DIV: float = 5000.0


## A row's quality (thousandths), or -1 for an item with none.
static func quality_of(instance_data: String) -> int:
	return int(data_of(instance_data).get("q", -1))


## A row's `instance_data` as a Dictionary (`{"q":734,"h":40016}`); empty for none or not JSON. (Not
## `String.to_int` from "q": it keeps every digit after it, the handle's too.)
static func data_of(instance_data: String) -> Dictionary:
	if instance_data.is_empty():
		return {}
	var v: Variant = JSON.parse_string(instance_data)
	return v as Dictionary if v is Dictionary else {}


## The grade of quality `q`: 0 Common, 1 Fine, 2 Masterwork; -1 for none (q < 0).
static func of_quality(q: int) -> int:
	if q < 0:
		return -1
	var fine: float = HotRules.number(&"regents.grade_fine_q")
	var masterwork: float = maxf(HotRules.number(&"regents.grade_masterwork_q"), fine)
	if float(q) >= masterwork:
		return 2
	if float(q) >= fine:
		return 1
	return 0


static func grade_name(grade: int) -> String:
	return NAMES[grade] if grade >= 0 and grade < NAMES.size() else ""


## What quality does to a weapon's hits: 1.0 to 1.2.
static func quality_mult(q: int) -> float:
	return 1.0 + float(clampi(q, 0, 1000)) / QUALITY_DAMAGE_DIV


## Its POWER at quality `q` (-1 for none: a material, a tool that is no weapon).
static func power(it: ItemDef, q: int) -> int:
	if it == null:
		return -1
	if it.weapon_kit != &"":
		return roundi(float(it.weapon_damage_pct) * quality_mult(q))
	if it.ammo_for != &"":
		return it.ammo_damage_pct
	return -1


## Its name with its grade: "Fine iron axe", "Masterwork iron sword"; a Common or ungraded one as it is.
static func item_name(it: ItemDef, q: int) -> String:
	if it == null:
		return "?"
	var g: int = of_quality(q)
	if g < 1:
		return it.display_name
	return "%s %s" % [grade_name(g), it.display_name.left(1).to_lower() + it.display_name.substr(1)]


## Where tier fails to dominate among `items`: for each pair of weapons of one kit, a better tier (more
## damage) whose worst (quality 0) does not beat the lesser's best (quality 1000). One line each.
static func tier_overlaps(items: Array[ItemDef]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for a: ItemDef in items:
		for b: ItemDef in items:
			if a.weapon_kit == &"" or a.weapon_kit != b.weapon_kit or b.weapon_damage_pct <= a.weapon_damage_pct:
				continue
			if power(a, 1000) >= power(b, 0):
				out.append("%s at its best (Power %d) reaches %s at its worst (Power %d): tier must dominate" % [
					a.display_name, power(a, 1000), b.display_name, power(b, 0)])
	return out
