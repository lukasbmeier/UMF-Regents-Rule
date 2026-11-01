extends "res://tests/suite_base.gd"
## The `sdk_patches` suite (tests/test_runner.gd runs it; `-- --only=sdk_patches` runs it alone).
## THE UMF PATCHES TO THE VENDORED SDK (`addons/SpacetimeDB`, DECISIONS #10): what this project changed
## in it, held here so an SDK upgrade that loses a patch fails a test. The one suite allowed to name SDK
## types (AGENTS.md hard rule 3), because what it tests is the SDK.

const ROWS: int = 4000


func run() -> void:
	_run_btree_slots()


## A BTREE INDEX SWAPS AN UPDATED ROW IN PLACE WITHOUT SEARCHING ITS BUCKET (DECISIONS #300). Every
## movement row of a world shares its `world_id`, so that index is one bucket of the whole table: on
## Regent's Rule's expanse 4,000 rows, searched for every player's step (~60 us each, a fifth of a strip
## referee's frame time). The bucket's rows and their order are as they were; only the search is gone.
func _run_btree_slots() -> void:
	print("== sdk patches: a btree index finds a row by its slot ==")
	var idx := _ModuleTableBTreeIndex.new()
	idx._table_name = &"movement_state"
	idx._field_name = &"world_id"
	var cache: Dictionary = {}
	idx._cache_ref = cache
	var rows: Array = []
	for i: int in ROWS:
		var r := _row(i + 1, 0)
		rows.append(r)
		idx._on_insert(r)
	_check((cache[0] as Array).size() == ROWS and idx._sorted_keys == [0], "%d rows of one world: one bucket" % ROWS)
	var t0: int = Time.get_ticks_usec()
	for i: int in range(ROWS - 300, ROWS):   # the players: the last rows in, updated again and again
		for step: int in 5:
			var next := _row(i + 1, 0)
			idx._on_update(rows[i], next)
			rows[i] = next
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	_check(idx.searches == 0, "1,500 updates at the bucket's end: none searched the bucket (%d searches, %.1f ms)" % [idx.searches, ms])
	_check(_same(cache[0] as Array, rows), "and the bucket holds the new rows, in their places")
	# A row out from the front: every row behind it moves up one, and is still found by its slot.
	idx._on_delete(rows[0])
	rows.remove_at(0)
	_check(_same(cache[0] as Array, rows), "a row deleted from the front: the rest in order")
	for i: int in rows.size():
		var next := _row((rows[i] as UmfMovementStateRow).entity_id, 0)
		idx._on_update(rows[i], next)
		rows[i] = next
	_check(idx.searches == 0, "then every row updated once: still no search (the rows behind it renumbered; %d)" % idx.searches)
	_check(_same(cache[0] as Array, rows), "and every one in its place")
	# A row to another world: out of one bucket, onto the end of the other.
	var mover: UmfMovementStateRow = rows[10]
	var moved := _row(mover.entity_id, 1)
	idx._on_update(mover, moved)
	rows.remove_at(10)
	_check(_same(cache[0] as Array, rows) and _same(cache[1] as Array, [moved]) and idx._sorted_keys == [0, 1],
		"a row to world 1: out of world 0's bucket, the only one in world 1's")
	var back := _row(moved.entity_id, 1)
	idx._on_update(moved, back)
	_check(_same(cache[1] as Array, [back]) and idx.searches == 0, "and updated there, in place (%d searches)" % idx.searches)
	idx._on_delete(back)
	_check(not cache.has(1) and idx._sorted_keys == [0], "deleted: world 1's bucket and key gone")
	idx._on_delete(_row(999_999, 0))
	_check((cache[0] as Array).size() == rows.size(), "a row it never had, deleted: nothing changes")
	# The SDK's own way in: an update for a row whose slot it never noted (a desync) appends it, as before.
	var stray := _row(888_888, 0)
	idx._on_update(_row(888_888, 0), stray)
	_check((cache[0] as Array).back() == stray, "an update of a row it never had: added at the end (as before)")
	idx._clear_cache()
	_check(cache.is_empty() and idx._slots.is_empty() and idx._sorted_keys.is_empty(), "cleared: buckets, keys and slots")


func _row(entity_id: int, world_id: int) -> UmfMovementStateRow:
	var r := UmfMovementStateRow.new()
	r.entity_id = entity_id
	r.world_id = world_id
	return r


## The same row objects in the same order.
func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true
