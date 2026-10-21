class_name SpaceTimeInventoryComponent extends SpaceTimeComponent
## Inventory, per ARCHITECTURE §7. Cache-only: the client never adds or removes anything, it
## mirrors `inventory_item` and asks the server to change it.
##
## This is the first component backed by MANY rows per entity, which the base `bind()` contract
## does not cover — `initial_rows` holds one row per table. So it keeps its own map keyed by
## ROW ID and bulk-loads whatever is already in the cache on bind. Keying by row id also makes
## the load idempotent: the one row `bind()` happened to pass through is simply seen twice and
## the second sighting is a no-op.
##
## Values are copied out of rows, never retained (hard rule 6: SDK rows are the cache's own
## instances). A `_Stack` is a plain snapshot, not a live reference.

signal item_added(item_def_id: int, qty: int)
signal item_removed(item_def_id: int, qty: int)
signal slot_changed(slot: int)
## Any change at all. UI that just needs to re-draw listens here instead of the three above.
signal inventory_changed()

const TABLE: StringName = &"inventory_item"
## Not in any slot yet — in the bag, unplaced.
const SLOT_NONE: int = -1


## One stack, copied out of a row.
class Stack extends RefCounted:
	var id: int
	var item_def_id: int
	var qty: int
	var slot: int
	var instance_data: String

	func _init(p_id: int, p_def: int, p_qty: int, p_slot: int, p_data: String = "") -> void:
		id = p_id
		item_def_id = p_def
		qty = p_qty
		slot = p_slot
		instance_data = p_data


var _stacks: Dictionary[int, Stack] = {}


func required_tables() -> Array[StringName]:
	return [TABLE]


## A fresh player owns nothing, so there may never be a row to wait for.
func optional_tables() -> Array[StringName]:
	return [TABLE]


# --- read API ------------------------------------------------------------------------

## Total quantity of an item across every stack.
func count(item_def_id: int) -> int:
	var total: int = 0
	for s: Stack in _stacks.values():
		if s.item_def_id == item_def_id:
			total += s.qty
	return total


func has_item(item_def_id: int, qty: int = 1) -> bool:
	return count(item_def_id) >= qty


## Every stack, newest row id last. Copies, so a caller cannot corrupt the mirror.
func items() -> Array[Stack]:
	var ids: Array = _stacks.keys()
	ids.sort()
	var out: Array[Stack] = []
	for id: int in ids:
		var s: Stack = _stacks[id]
		out.append(Stack.new(s.id, s.item_def_id, s.qty, s.slot, s.instance_data))
	return out


func stack_count() -> int:
	return _stacks.size()


func get_stack(item_id: int) -> Stack:
	var s: Stack = _stacks.get(item_id, null)
	return Stack.new(s.id, s.item_def_id, s.qty, s.slot, s.instance_data) if s != null else null


func item_in_slot(slot: int) -> Stack:
	for s: Stack in _stacks.values():
		if s.slot == slot:
			return Stack.new(s.id, s.item_def_id, s.qty, s.slot, s.instance_data)
	return null


# --- intent --------------------------------------------------------------------------

## Ask the server to spend part of a stack. The inventory does NOT change here; it changes when
## the resulting row update arrives. Callers watch the returned request for rejection.
func request_consume(item_id: int, qty: int) -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"consume_item", [item_id, qty], ["u64", "u32"])


## Drop `qty` of stack `item_id` at your feet (DECISIONS #269): yours a while, then anyone's.
func request_drop(item_id: int, qty: int) -> ReducerRequest:
	GroundItems.own_drop_msec = Time.get_ticks_msec()   # not walked straight back into
	return SpaceTimeSync.call_reducer(&"drop_item", [item_id, qty], ["u64", "u32"])


func request_set_slot(item_id: int, slot: int) -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"set_item_slot", [item_id, slot], ["u64", "i16"])


# --- row handling --------------------------------------------------------------------

func _on_bound() -> void:
	_load_existing()


## Pull whatever is already in the cache. `bind()` hands over every stack the entity was sent
## (DECISIONS #180); this also reads any the cache holds that never reached it as an event, and
## applying a stack twice is applying it once.
func _load_existing() -> void:
	var tbl: Object = SpaceTimeSync.get_table(TABLE)
	if tbl == null:
		return   # no SDK (unit tests, or codegen has not run) — rows still arrive by event
	if not tbl.has_method(&"find_by_owner_entity_id"):
		return
	var rows: Variant = tbl.call(&"find_by_owner_entity_id", entity_id)
	if not (rows is Array):
		return
	for row: RefCounted in rows:
		_apply_row(row)


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	if new == null:
		_remove_row(old)
		return
	_apply_row(new)


func _apply_row(row: RefCounted) -> void:
	var id: int = int(row.get(&"id"))
	var def_id: int = int(row.get(&"item_def_id"))
	var qty: int = int(row.get(&"qty"))
	var slot: int = int(row.get(&"slot"))
	var data: Variant = row.get(&"instance_data")
	var prev: Stack = _stacks.get(id, null)

	_stacks[id] = Stack.new(id, def_id, qty, slot, str(data) if data != null else "")

	if prev == null:
		item_added.emit(def_id, qty)
	else:
		# A stack changing size is an add or a remove of the DIFFERENCE, not of the whole
		# stack — otherwise consuming 1 of 20 would look like losing 19.
		var delta: int = qty - prev.qty
		if delta > 0:
			item_added.emit(def_id, delta)
		elif delta < 0:
			item_removed.emit(def_id, -delta)
		if slot != prev.slot:
			slot_changed.emit(slot)
		if delta == 0 and slot == prev.slot:
			return   # nothing observable changed; do not wake the UI
	_announce()


func _remove_row(old: RefCounted) -> void:
	if old == null:
		return
	var id: int = int(old.get(&"id"))
	var prev: Stack = _stacks.get(id, null)
	if prev == null:
		return
	_stacks.erase(id)
	item_removed.emit(prev.item_def_id, prev.qty)
	_announce()


func _announce() -> void:
	inventory_changed.emit()
	SignalBus.entity_inventory_changed.emit(entity_id)
