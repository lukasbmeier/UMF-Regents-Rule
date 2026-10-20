@tool
class_name LootTableDef extends ContentDef
## A LOOT TABLE (DECISIONS #268): what a kill (or a chest, a node) drops, as lines of items and other
## tables. The server rolls it ONCE FOR EACH PLAYER who did enough of the damage (a PERSONAL ROLL:
## `foundation.loot_share_min_pct`), so your odds are the same alone or in a group and nobody's drop is
## anyone else's.
##
##   EACH     every line rolls its own chance. Several can drop; 100 % always does; adding a line
##            changes no other line's odds.
##   ONE-OF   exactly one line wins: type each line's share as a plain percentage (10, 20, 30, 40);
##            what the shares leave of 100 is nothing. A table that adds up past 100 is refused.
##
## A line may be another table ("undead common"), so foes share their common drops and keep their own
## rare ones. A line marked `pity` (EACH only) grows likelier for a player each time it misses them.

enum Mode {
	## Every line rolls its own chance.
	EACH,
	## One line wins, by its share; the rest is nothing.
	ONE_OF,
}

@export var mode: Mode = Mode.EACH
@export var lines: Array[LootLine] = []

## Deepest nesting a table may have (the server's `loot::MAX_DEPTH`).
const MAX_DEPTH: int = 8


func content_type() -> StringName:
	return &"loot_table"


func why_no_workbench() -> String:
	return "a table is lines of chances: its summary says what one roll gives on average, and the bench of what drops it (a foe's) shows it per kill"


func summary() -> String:
	var e: Dictionary = expected()
	var parts: PackedStringArray = PackedStringArray()
	for item_id: int in e:
		parts.append("%s %s" % [pretty(float((e[item_id] as Dictionary)["n"])), (e[item_id] as Dictionary)["name"]])
	return "%s, %d lines: %s a roll" % ["one of" if mode == Mode.ONE_OF else "each", lines.size(), ", ".join(parts)]


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "one_of": mode == Mode.ONE_OF,
		"lines": lines.map(func(l: LootLine) -> Dictionary: return l.to_bake() if l != null else {})}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if lines.is_empty():
		out.append("it has no lines")
	var shares: float = 0.0
	for i: int in lines.size():
		var l: LootLine = lines[i]
		if l == null:
			out.append("line %d is empty" % (i + 1))
			continue
		if (l.item == null) == (l.table == null):
			out.append("line %d needs an item or a table (one, not both)" % (i + 1))
		if l.item != null and l.item.content_type() != &"item":
			out.append("line %d drops a %s, not an item" % [i + 1, l.item.content_type()])
		if l.qty_min > l.qty_max:
			out.append("line %d drops %d to %d: the least is more than the most" % [i + 1, l.qty_min, l.qty_max])
		if l.pity and mode == Mode.ONE_OF:
			out.append("line %d has pity, but a one-of table's lines share one roll: put it in an each table" % (i + 1))
		shares += l.chance_pct
	if mode == Mode.ONE_OF and shares > 100.0 + 1e-6:
		out.append("its shares add up to %s %%: a one-of table's must be 100 at most (the rest is nothing)" % pretty(shares))
	var loop: String = _loop([self], 0)
	if not loop.is_empty():
		out.append(loop)
	return out


## A number as a person writes it: 6.6, 1, 0.04 (at most four places, no trailing zeros).
static func pretty(v: float) -> String:
	var s: String = "%.4f" % v
	s = s.rstrip("0")
	return s.trim_suffix(".")


## WHAT ONE ROLL GIVES ON AVERAGE: {item id: {"name", "n"}} (pity left out: it only moves a line's odds
## for one unlucky player).
func expected() -> Dictionary:
	var out: Dictionary = {}
	_expect(1.0, out, 0)
	return out


func _expect(weight: float, out: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	for l: LootLine in lines:
		if l == null:
			continue
		var p: float = weight * clampf(l.chance_pct, 0.0, 100.0) / 100.0
		if l.table != null:
			l.table._expect(p, out, depth + 1)
		elif l.item != null:
			var key: int = l.item.id
			if not out.has(key):
				out[key] = {"name": l.item.display_name, "n": 0.0}
			(out[key] as Dictionary)["n"] = float((out[key] as Dictionary)["n"]) + p * float(l.qty_min + l.qty_max) / 2.0


## A table that contains itself, or nests deeper than the server rolls: what is wrong, or "".
func _loop(path: Array, depth: int) -> String:
	if depth >= MAX_DEPTH:
		return "it nests tables deeper than %d" % MAX_DEPTH
	for l: LootLine in lines:
		if l == null or l.table == null:
			continue
		if path.has(l.table):
			return "it contains itself (%s)" % " > ".join(path.map(func(t: LootTableDef) -> String: return t.display_name) + [l.table.display_name])
		var deeper: String = l.table._loop(path + [l.table], depth + 1)
		if not deeper.is_empty():
			return deeper
	return ""
