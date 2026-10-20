extends "res://tests/suite_base.gd"
## The `loot` suite (DECISIONS #268): a loot table as content.
##   - what one roll gives on average (each and one-of, nested), as its summary and a foe's bench say
##   - what it bakes (one-of, each line's chance in parts per million)
##   - what its check refuses: one-of past 100 %, pity in a one-of, a line with no item or both, a
##     line that is not an item, least over most, a table that contains itself
## The roll itself (each, one-of, pity, who earns a roll): server/tests/loot.rs. A kill's loot on a real
## server: a genre's integration hook (Regent's Rule's skeletons).


## An item, as a genre's would be (the foundation has no item content of its own).
class TestItem extends ContentDef:
	func content_type() -> StringName:
		return &"item"

	func to_bake() -> Dictionary:
		return {"id": id}


## Not an item.
class TestOther extends ContentDef:
	func content_type() -> StringName:
		return &"noise"

	func to_bake() -> Dictionary:
		return {}


func run() -> void:
	var bones: TestItem = _item(1, "Bones")
	var marks: TestItem = _item(2, "Marks")
	var dagger: TestItem = _item(3, "Rusted dagger")
	var purse := _table(11, "A few marks", LootTableDef.Mode.ONE_OF, [_line(marks, 50.0, 5, 5), _line(marks, 35.0, 10, 10), _line(marks, 15.0, 15, 15)])
	var common := _table(12, "Undead common", LootTableDef.Mode.EACH, [_line(dagger, 10.0)])
	var warden := _table(10, "Warden", LootTableDef.Mode.EACH, [_line(bones, 100.0, 1, 1, true), _nest(purse, 80.0), _nest(common, 100.0)])
	_check(warden.validate().is_empty() and purse.validate().is_empty(), "the Warden and its tables are sound: %s" % str(warden.validate() + purse.validate()))
	var e: Dictionary = warden.expected()
	_check(is_equal_approx(float((e[1] as Dictionary)["n"]), 1.0) and is_equal_approx(float((e[2] as Dictionary)["n"]), 6.6)
		and is_equal_approx(float((e[3] as Dictionary)["n"]), 0.1),
		"a Warden kill gives on average 1 bones, 6.6 marks (80 %% of 5x50 + 10x35 + 15x15 %%), 0.1 daggers: %s" % str(e))
	_check(warden.summary().begins_with("each, 3 lines: 1 Bones, 6.6 Marks, 0.1 Rusted dagger"), "its summary says so: %s" % warden.summary())
	var baked: Dictionary = purse.to_bake()
	var line0: Dictionary = (baked["lines"] as Array)[0]
	_check(baked["one_of"] == true and int(line0["chance_pm"]) == 500000 and int(line0["item"]) == 2 and int(line0["table"]) == -1,
		"it bakes one-of, 50 %% as 500000 per million, the item's id and no table: %s" % str(line0))
	_check(int(((warden.to_bake()["lines"] as Array)[1] as Dictionary)["table"]) == 11, "a nested line bakes its table's id")
	# What its check refuses.
	var over := _table(20, "Over", LootTableDef.Mode.ONE_OF, [_line(bones, 60.0), _line(marks, 50.0)])
	_check(_says(over, "add up to 110 %"), "a one-of past 100 %%: %s" % str(over.validate()))
	var pity_one := _table(21, "Pity", LootTableDef.Mode.ONE_OF, [_line(bones, 10.0)])
	pity_one.lines[0].pity = true
	_check(_says(pity_one, "has pity, but a one-of"), "pity in a one-of: %s" % str(pity_one.validate()))
	var both := _table(22, "Both", LootTableDef.Mode.EACH, [_nest(common, 10.0)])
	both.lines[0].item = bones
	var neither := _table(23, "Neither", LootTableDef.Mode.EACH, [_line(null, 10.0)])
	_check(_says(both, "an item or a table") and _says(neither, "an item or a table"), "a line with both, or neither")
	var wrong := _table(24, "Wrong", LootTableDef.Mode.EACH, [_line(_other(), 10.0)])
	_check(_says(wrong, "drops a noise, not an item"), "a line that is not an item: %s" % str(wrong.validate()))
	var upside := _table(25, "Upside", LootTableDef.Mode.EACH, [_line(bones, 10.0, 4, 2)])
	_check(_says(upside, "the least is more than the most"), "least over most")
	var a := _table(26, "A", LootTableDef.Mode.EACH, [])
	var b := _table(27, "B", LootTableDef.Mode.EACH, [_nest(a, 50.0)])
	a.lines.append(_nest(b, 50.0))
	_check(_says(a, "contains itself (A > B > A)"), "a table that contains itself: %s" % str(a.validate()))
	a.lines.clear()   # (the loop holds itself otherwise)
	_check(_says(_table(28, "Empty", LootTableDef.Mode.EACH, []), "no lines"), "a table with no lines")


func _item(p_id: int, p_name: String) -> TestItem:
	var it := TestItem.new()
	it.id = p_id
	it.display_name = p_name
	return it


func _other() -> TestOther:
	var o := TestOther.new()
	o.id = 9
	o.display_name = "A noise"
	return o


func _table(p_id: int, p_name: String, mode: LootTableDef.Mode, p_lines: Array) -> LootTableDef:
	var t := LootTableDef.new()
	t.id = p_id
	t.display_name = p_name
	t.mode = mode
	for l: LootLine in p_lines:
		t.lines.append(l)
	return t


func _line(it: ContentDef, pct: float, lo: int = 1, hi: int = 1, to_bag: bool = false) -> LootLine:
	var l := LootLine.new()
	l.item = it
	l.chance_pct = pct
	l.qty_min = lo
	l.qty_max = hi
	l.to_bag = to_bag
	return l


func _nest(t: LootTableDef, pct: float) -> LootLine:
	var l := LootLine.new()
	l.table = t
	l.chance_pct = pct
	return l


func _says(t: LootTableDef, words: String) -> bool:
	return " / ".join(t.validate()).contains(words)
