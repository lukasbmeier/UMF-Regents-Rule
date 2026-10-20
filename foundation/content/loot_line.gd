@tool
class_name LootLine extends Resource
## ONE LINE OF A LOOT TABLE (`LootTableDef`, DECISIONS #268): an item (or another table) and its
## chance. In an EACH table every line rolls its own chance (several can drop; a line at 100 % always
## does); in a ONE-OF table exactly one line wins, by its share, and what is left over is nothing.

## What drops: an item (content of the type "item"). Leave empty when the line is a table.
@export var item: ContentDef
## Or another table, rolled when this line hits (a shared one: "undead common", "a few marks").
@export var table: LootTableDef
## Its chance: in an EACH table, the chance it drops at all; in a ONE-OF table, its share of the one
## roll (the shares add up to 100 at most; the rest is nothing). 0.0001 % to 100 %.
@export_range(0.0001, 100.0, 0.0001, "suffix:%") var chance_pct: float = 100.0
## How many, from..to (an even chance of each). A table line rolls its table once.
@export_range(1, 100000) var qty_min: int = 1
@export_range(1, 100000) var qty_max: int = 1
## Straight into the bag (currency, a quest item), never on the ground.
@export var to_bag: bool = false
## BAD-LUCK PROTECTION (EACH tables only): each roll that misses raises this line's chance for that
## player, and a long enough run of misses guarantees it; a hit resets it. How fast is two hot rules,
## in units of the line's own odds (`foundation.loot_pity_ramp_x`, `foundation.loot_pity_cap_x`).
@export var pity: bool = false


func to_bake() -> Dictionary:
	return {"item": ContentDef.ref(item), "table": ContentDef.ref(table), "chance_pm": roundi(chance_pct * 10000.0),
		"qty_min": qty_min, "qty_max": qty_max, "to_bag": to_bag, "pity": pity}


## What it is, in a few words: "Copper ore 1-2 (60 %)".
func describe() -> String:
	var what: String = item.display_name if item != null else ("[%s]" % table.display_name if table != null else "?")
	var qty: String = "" if table != null else (" %d" % qty_min if qty_min == qty_max else " %d-%d" % [qty_min, qty_max])
	return "%s%s (%s %%)%s" % [what, qty, LootTableDef.pretty(chance_pct), " pity" if pity else ""]
