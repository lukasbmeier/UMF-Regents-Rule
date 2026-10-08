extends "res://tests/suite_base.gd"
## The `row_event` suite (tests/test_runner.gd runs it; `-- --only=row_event` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_row_event_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


func _run_row_event_tests() -> void:
	print("== RowEvent ==")
	var ev: RowEvent = RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(7, 90.0), FakeRow.new(7, 80.0))
	_check(ev.entity_id == 7, "entity_id extracted from row")
	_check(ev.current() == ev.new, "current() is new for UPDATED")
	var del: RowEvent = RowEvent.make(RowEvent.Kind.DELETED, &"health_state", FakeRow.new(3, 0.0), null)
	_check(del.entity_id == 3 and del.current() == del.old, "DELETED uses old row")
	var glob: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"world_config", null, FakeGlobalRow.new())
	_check(glob.entity_id == -1, "non-entity table yields entity_id -1")
