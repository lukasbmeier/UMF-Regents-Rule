extends "res://tests/suite_base.gd"
## The `inventory` suite (tests/test_runner.gd runs it; `-- --only=inventory` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_inventory_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


func _run_inventory_tests() -> void:
	print("== SpaceTimeInventoryComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus present")
		return

	# --- routing: an owned row must reach the entity, not the global stream -----------
	var owned: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"inventory_item", null,
		FakeItemRow.new(1, 55, 10, 5))
	_check(owned.entity_id == 55,
		"a row with owner_entity_id is scoped to that entity (got %d)" % owned.entity_id)
	var worldish: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"item_def", null,
		FakeGlobalRow.new())
	_check(worldish.entity_id == -1, "a row with neither id stays a world row")

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 55
	get_tree().root.add_child(owner_entity)
	var inv := SpaceTimeInventoryComponent.new()
	get_tree().root.add_child(inv)

	var added: Array[String] = []
	var removed: Array[String] = []
	var slots: Array[int] = []
	var changes: Array[int] = []
	inv.item_added.connect(func(d: int, q: int) -> void: added.append("%d x%d" % [d, q]))
	inv.item_removed.connect(func(d: int, q: int) -> void: removed.append("%d x%d" % [d, q]))
	inv.slot_changed.connect(func(s: int) -> void: slots.append(s))
	inv.inventory_changed.connect(func() -> void: changes.append(1))
	var bus_changes: Array[int] = []
	var icb := func(eid: int) -> void: bus_changes.append(eid)
	bus.entity_inventory_changed.connect(icb)

	var empty: Dictionary[StringName, RefCounted] = {}
	inv.bind(owner_entity, empty)
	_check(inv.stack_count() == 0, "starts empty with no rows")
	_check(inv.count(10) == 0, "count of an absent item is 0")

	# --- first stack -------------------------------------------------------------------
	inv.receive_row_event(_item_ev(RowEvent.Kind.INSERTED, null, FakeItemRow.new(1, 55, 10, 5)))
	_check(inv.count(10) == 5, "insert records the quantity")
	_check(added == ["10 x5"], "item_added carries def and qty")
	_check(bus_changes == [55], "bus entity_inventory_changed leads with entity_id")

	# --- a SECOND stack of the same item accumulates ------------------------------------
	added.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.INSERTED, null, FakeItemRow.new(2, 55, 10, 20)))
	_check(inv.count(10) == 25, "count sums across stacks (got %d)" % inv.count(10))
	_check(inv.stack_count() == 2, "two distinct stacks tracked")
	_check(added == ["10 x20"], "the second stack reports only its own quantity")

	# --- a partial consume reports the DIFFERENCE, not the whole stack -------------------
	added.clear()
	removed.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.UPDATED,
		FakeItemRow.new(2, 55, 10, 20), FakeItemRow.new(2, 55, 10, 14)))
	_check(removed == ["10 x6"], "shrinking 20->14 reports a removal of 6 (got %s)" % str(removed))
	_check(inv.count(10) == 19, "count reflects the shrink (got %d)" % inv.count(10))
	_check(added.is_empty(), "a shrink is not also an add")

	# --- growing an existing stack --------------------------------------------------------
	added.clear()
	removed.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.UPDATED,
		FakeItemRow.new(2, 55, 10, 14), FakeItemRow.new(2, 55, 10, 18)))
	_check(added == ["10 x4"], "growing 14->18 reports an add of 4")
	_check(removed.is_empty(), "a grow is not also a removal")

	# --- slot moves ------------------------------------------------------------------------
	slots.clear()
	added.clear()
	removed.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.UPDATED,
		FakeItemRow.new(2, 55, 10, 18), FakeItemRow.new(2, 55, 10, 18, 3)))
	_check(slots == [3], "moving a stack reports slot_changed")
	_check(added.is_empty() and removed.is_empty(), "a slot move is not a quantity change")
	var in_slot: SpaceTimeInventoryComponent.Stack = inv.item_in_slot(3)
	_check(in_slot != null and in_slot.id == 2, "item_in_slot finds the stack")

	# --- an identical row must not wake the UI ---------------------------------------------
	changes.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.UPDATED,
		FakeItemRow.new(2, 55, 10, 18, 3), FakeItemRow.new(2, 55, 10, 18, 3)))
	_check(changes.is_empty(), "a row with no observable change emits nothing")

	# --- deleting a stack removes its whole quantity ----------------------------------------
	removed.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.DELETED, FakeItemRow.new(2, 55, 10, 18, 3), null))
	_check(removed == ["10 x18"], "deleting a stack removes its full quantity")
	_check(inv.count(10) == 5, "only the remaining stack is counted")
	_check(inv.stack_count() == 1, "the deleted stack is gone")

	# Deleting something already gone must be silent, not a phantom removal.
	removed.clear()
	inv.receive_row_event(_item_ev(RowEvent.Kind.DELETED, FakeItemRow.new(99, 55, 10, 1), null))
	_check(removed.is_empty(), "deleting an unknown stack emits nothing")

	# --- read helpers -------------------------------------------------------------------------
	_check(inv.has_item(10, 5) and not inv.has_item(10, 6), "has_item respects the threshold")
	var listed: Array = inv.items()
	_check(listed.size() == 1 and listed[0].item_def_id == 10, "items() lists the stacks")
	listed[0].qty = 9999
	_check(inv.count(10) == 5, "items() returns copies, so callers cannot corrupt the mirror")

	# --- idempotent re-application (what the bulk load on bind relies on) ----------------------
	changes.clear()
	added.clear()
	var same_row := FakeItemRow.new(1, 55, 10, 5)
	inv._apply_row(same_row)
	_check(added.is_empty() and changes.is_empty(),
		"re-applying an identical row is a no-op, so the bind-time bulk load cannot double-count")
	_check(inv.count(10) == 5, "count unchanged after re-application")

	bus.entity_inventory_changed.disconnect(icb)
	inv.queue_free()
	owner_entity.queue_free()
