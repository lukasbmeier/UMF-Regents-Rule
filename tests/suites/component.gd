extends "res://tests/suite_base.gd"
## The `component` suite (tests/test_runner.gd runs it; `-- --only=component` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_component_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


## Concrete subclass that records the shape of every dispatch it receives.
class ProbeComponent extends SpaceTimeComponent:
	var seen: Array[String] = []
	var bound_count: int = 0

	func required_tables() -> Array[StringName]:
		return [&"health_state"]

	func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
		seen.append("%s %s->%s" % [
			table,
			"null" if old == null else "row",
			"null" if new == null else "row",
		])

	func _on_bound() -> void:
		bound_count += 1

func _run_component_tests() -> void:
	print("== SpaceTimeComponent ==")
	var owner_entity := FakeOwnerEntity.new()
	get_tree().root.add_child(owner_entity)

	# bind() with no initial rows: fields set, _on_bound once, nothing dispatched.
	var bare := ProbeComponent.new()
	get_tree().root.add_child(bare)
	var empty_rows: Dictionary[StringName, RefCounted] = {}
	bare.bind(owner_entity, empty_rows)
	_check(bare.entity == owner_entity, "bind sets entity")
	_check(bare.entity_id == 99, "bind copies entity_id")
	_check(bare.is_local_authority, "bind copies is_local_authority")
	_check(bare.bound_count == 1, "_on_bound called exactly once")
	_check(bare.is_bound(), "is_bound() true after bind")
	_check(bare.seen.is_empty(), "no dispatch without initial rows")

	# bind() replays an initial row as an insert.
	var c := ProbeComponent.new()
	get_tree().root.add_child(c)
	var initial: Dictionary[StringName, RefCounted] = {&"health_state": FakeRow.new(99, 100.0)}
	c.bind(owner_entity, initial)
	_check(c.seen == ["health_state null->row"], "initial row replayed as insert")

	# receive_row_event dispatches by kind.
	c.seen.clear()
	c.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, FakeRow.new(99, 100.0)))
	_check(c.seen == ["health_state null->row"], "INSERTED -> (table, null, row)")

	c.seen.clear()
	c.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"health_state", FakeRow.new(99, 0.0), null))
	_check(c.seen == ["health_state row->null"], "DELETED -> (table, row, null)")

	c.seen.clear()
	c.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(99, 100.0), FakeRow.new(99, 75.0)))
	_check(c.seen == ["health_state row->row"], "UPDATED -> (table, old, new)")

	# rebind re-applies a fresh initial set (reconnect path, DECISIONS #17).
	c.seen.clear()
	c.rebind(initial)
	_check(c.seen == ["health_state null->row"], "rebind replays initial rows")
	_check(c.bound_count == 2, "rebind calls _on_bound again")

	_check(c.required_tables() == [&"health_state"], "required_tables passthrough")

	bare.queue_free()
	c.queue_free()
	owner_entity.queue_free()
