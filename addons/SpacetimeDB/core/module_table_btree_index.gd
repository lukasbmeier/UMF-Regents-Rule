## Base class for codegen'd btree (non-unique) index accessors.
##
## Each generated btree index (e.g. [code]BlackholioCirclePlayerIdBTreeIndex[/code])
## extends this and exposes a typed [code]filter(col_val) -> Array[Row][/code]
## returning every row whose indexed column equals the given value. Backed by a
## multimap cache (one bucket of rows per distinct column value) kept in sync with
## [LocalDatabase] via insert/update/delete listeners, so a lookup is O(1) on the
## value plus O(k) over the k matching rows, not a linear scan of the whole table.
class_name _ModuleTableBTreeIndex
extends Resource

## Normalized table name this index belongs to.
var _table_name: StringName
## The field name used as the (non-unique) index key.
var _field_name: StringName
## Ascending list of the distinct keys currently in the cache — a mirror of the
## multimap's keys kept sorted so range queries binary-search instead of scanning.
## Maintained only at bucket create/empty edges (distinct-key churn), not per row,
## and only for keys [method Array.bsearch] can order (see [method _is_orderable_key]).
var _sorted_keys: Array = []
## Reference to the subclass-owned multimap, captured in [method _connect_cache_to_db]
## so base-class range queries can read it (the typed [code]_cache[/code] lives on the
## generated subclass).
var _cache_ref: Dictionary = { }
## UMF PATCH (DECISIONS #300; keep it on an SDK upgrade): where each cached row sits in
## its bucket, by the row's instance id, so an update that keeps its key swaps the row in
## place instead of searching the bucket for it. One bucket can hold a whole table (every
## movement row of a world shares its [code]world_id[/code]): Regent's Rule's referees
## searched 4,000 rows for every player's step, ~60 us each. Exact at all times: a
## removal renumbers the rows behind it. Order in a bucket is unchanged.
var _slots: Dictionary[int, int] = { }
## TESTING (UMF): how many times a bucket was searched for a row (a slot was wrong).
var searches: int = 0


## Whether [param k] is a value [method Array.bsearch] can order. Bytes-backed keys
## (Identity / ConnectionId / u128 / u256 all map to [PackedByteArray]), row objects
## and dictionaries have no [code]<[/code]: bsearch lands on an arbitrary index for
## them, so [method _key_removed] would fail to find the key it was handed and the
## mirror would keep every key the client ever saw. Deliberately a superset of
## codegen's ORDERABLE_INDEX_TYPES (int / float / String): no generated accessor can
## be starved of a mirror, at the cost of maintaining one for a StringName or bool
## column that has no range accessor to read it.
func _is_orderable_key(k: Variant) -> bool:
	var t: int = typeof(k)
	return (
		t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_STRING
		or t == TYPE_STRING_NAME or t == TYPE_BOOL
	)


## Inserts [param k] into [member _sorted_keys] at its sorted position.
func _key_added(k: Variant) -> void:
	if not _is_orderable_key(k):
		return
	var i: int = _sorted_keys.bsearch(k, true)
	_sorted_keys.insert(i, k)


## Removes [param k] from [member _sorted_keys] if present.
func _key_removed(k: Variant) -> void:
	if not _is_orderable_key(k):
		return
	var i: int = _sorted_keys.bsearch(k, true)
	if i < _sorted_keys.size() and _sorted_keys[i] == k:
		_sorted_keys.remove_at(i)


## Gathers every cached row in the sorted-key window [code][lo, hi)[/code] (indices
## into [member _sorted_keys]). Shared by all of the range/bound queries below.
func _gather(lo: int, hi: int) -> Array:
	var out: Array = []
	for i: int in range(lo, hi):
		out.append_array(_cache_ref[_sorted_keys[i]])
	return out


## Every cached row whose key lies in [code][from_val, to_val][/code] inclusive.
## Returns an untyped [Array]; the codegen'd subclass assigns it into a typed
## [code]Array[Row][/code]. O(log d) to locate the window over d distinct keys,
## plus O(k) to gather the k matching rows. The one-sided variants below share the
## same cost profile.
func _range_rows(from_val: Variant, to_val: Variant) -> Array:
	# [first key >= from_val, first key > to_val)
	return _gather(_sorted_keys.bsearch(from_val, true), _sorted_keys.bsearch(to_val, false))


## Rows whose key is [code]>= v[/code].
func _gte_rows(v: Variant) -> Array:
	return _gather(_sorted_keys.bsearch(v, true), _sorted_keys.size())


## Rows whose key is [code]> v[/code].
func _gt_rows(v: Variant) -> Array:
	return _gather(_sorted_keys.bsearch(v, false), _sorted_keys.size())


## Rows whose key is [code]<= v[/code].
func _lte_rows(v: Variant) -> Array:
	return _gather(0, _sorted_keys.bsearch(v, false))


## Rows whose key is [code]< v[/code].
func _lt_rows(v: Variant) -> Array:
	return _gather(0, _sorted_keys.bsearch(v, true))


## First cached row whose key equals [param col_val], or null if the bucket is absent
## or empty. Backs the generated [code]first_by_<field>[/code] without the typed
## bucket-copy that [code]filter()[/code] builds — only row 0 is needed.
func _first_row(col_val: Variant) -> _ModuleTableType:
	var bucket: Variant = _cache_ref.get(col_val)
	if bucket == null or bucket.is_empty():
		return null
	return bucket[0]


## Wires [param cache] (a [code]Dictionary[value, Array[Row]][/code] multimap) to live
## insert/update/delete callbacks on [param db] so each per-value bucket stays current
## without manual polling. Mirrors [_ModuleTableUniqueIndex] but keeps a bucket of rows
## per key instead of a single row, and keeps [member _sorted_keys] aligned at the
## bucket create/empty edges. The callbacks read the multimap via [member _cache_ref]
## (set here), so they're named methods rather than capturing lambdas.
func _connect_cache_to_db(cache: Dictionary, db: LocalDatabase) -> void:
	_cache_ref = cache
	db.subscribe_to_inserts(_table_name, _on_insert)
	db.subscribe_to_updates(_table_name, _on_update)
	db.subscribe_to_deletes(_table_name, _on_delete)
	db.register_index_invalidator(_clear_cache)


## Drops every cached bucket and the sorted-key mirror with it. Registered with
## [method LocalDatabase.register_index_invalidator] because the delete listener above is
## not reached by [method LocalDatabase.clear_all_tables], which empties the mirror in
## silence — these buckets would otherwise keep answering [code]filter()[/code] and every
## range query with rows that are gone.
func _clear_cache() -> void:
	_cache_ref.clear()
	_sorted_keys.clear()
	_slots.clear()


## Insert listener — appends the row to its key's bucket, creating the bucket (and
## registering the key in [member _sorted_keys]) on first sight of the value.
func _on_insert(r: _ModuleTableType) -> void:
	var col_val: Variant = r[_field_name]
	if not _cache_ref.has(col_val):
		_cache_ref[col_val] = []
		_key_added(col_val)
	_append(_cache_ref[col_val], r)


## Update listener — moves the row between buckets when its key changed, else swaps
## the stale instance in place. Empties/creates buckets at the key edges.
func _on_update(p: _ModuleTableType, r: _ModuleTableType) -> void:
	var previous_col_val: Variant = p[_field_name]
	var col_val: Variant = r[_field_name]

	if previous_col_val != col_val:
		if _cache_ref.has(previous_col_val):
			_remove(previous_col_val, p)
		if not _cache_ref.has(col_val):
			_cache_ref[col_val] = []
			_key_added(col_val)
		_append(_cache_ref[col_val], r)
	elif _cache_ref.has(col_val):
		# Same key — swap the stale instance for the new one in place.
		var bucket: Array = _cache_ref[col_val]
		var idx: int = _slot_of(bucket, p)
		if idx != -1:
			bucket[idx] = r
			_slots.erase(p.get_instance_id())
			_slots[r.get_instance_id()] = idx
		else:
			_append(bucket, r)
	else:
		_cache_ref[col_val] = []
		_key_added(col_val)
		_append(_cache_ref[col_val], r)


## Delete listener — drops the row from its bucket, emptying the bucket (and
## unregistering the key) when it was the last row for that value.
func _on_delete(r: _ModuleTableType) -> void:
	var col_val: Variant = r[_field_name]
	if _cache_ref.has(col_val):
		_remove(col_val, r)


## UMF PATCH (#300): [param r] onto the end of [param bucket], its slot noted.
func _append(bucket: Array, r: _ModuleTableType) -> void:
	bucket.append(r)
	_slots[r.get_instance_id()] = bucket.size() - 1


## UMF PATCH (#300): where [param r] is in [param bucket] (-1: not there), by its slot;
## searched for only if the slot is wrong, which the renumbering keeps from happening.
func _slot_of(bucket: Array, r: _ModuleTableType) -> int:
	var idx: int = _slots.get(r.get_instance_id(), -1)
	if idx >= 0 and idx < bucket.size() and bucket[idx] == r:
		return idx
	searches += 1
	idx = bucket.find(r)
	if idx != -1:
		_slots[r.get_instance_id()] = idx
	return idx


## UMF PATCH (#300): [param r] out of its key's bucket (nothing if it is not there, as
## [code]erase[/code] did), the rows behind it renumbered, and the key dropped with its
## last row.
func _remove(col_val: Variant, r: _ModuleTableType) -> void:
	var bucket: Array = _cache_ref[col_val]
	var idx: int = _slot_of(bucket, r)
	if idx != -1:
		bucket.remove_at(idx)
		_slots.erase(r.get_instance_id())
		for i: int in range(idx, bucket.size()):
			_slots[(bucket[i] as Object).get_instance_id()] = i
	if bucket.is_empty():
		_cache_ref.erase(col_val)
		_key_removed(col_val)
