extends "res://tests/suite_base.gd"
## The `entity_registry` suite (tests/test_runner.gd runs it; `-- --only=entity_registry` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_entity_registry_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- EntityRegistry buffering ---------------------------------------------------------

class FakeEntity extends Node:
	var received: Array[RowEvent] = []
	func receive_row_event(ev: RowEvent) -> void:
		received.append(ev)


func _run_entity_registry_tests() -> void:
	print("== EntityRegistry ==")
	# Instantiate the registry script directly; skip _ready (it would look for SpaceTimeSync).
	var reg: Node = load("res://foundation/core/entity_registry.gd").new()

	var early1: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, FakeRow.new(42, 100.0))
	var early2: RowEvent = RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(42, 100.0), FakeRow.new(42, 75.0))
	reg._on_row_event(early1)
	reg._on_row_event(early2)
	_check(reg.peek_buffered(42).size() == 2, "events buffered before register")

	var ent := FakeEntity.new()
	get_tree().root.add_child(ent)
	reg.register(42, ent)
	_check(ent.received.size() == 2, "buffered events replayed on register")
	_check(ent.received[0] == early1 and ent.received[1] == early2, "replay preserves order")
	_check(reg.peek_buffered(42).is_empty(), "buffer cleared after replay")

	var live: RowEvent = RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(42, 75.0), FakeRow.new(42, 50.0))
	reg._on_row_event(live)
	_check(ent.received.size() == 3, "live events routed directly")

	var got_global: Array[RowEvent] = []
	reg.global_row_event.connect(func(ev: RowEvent) -> void: got_global.append(ev))
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"world_config", null, FakeGlobalRow.new()))
	_check(got_global.size() == 1, "non-entity rows go to global_row_event")

	# AN ENTITY STILL BINDING (0.49.0): a row that arrives after its `entity` row goes straight to it,
	# not into the buffer it would only be given once bound (a thrown body waited out its 2 s timeout).
	var waiting := FakeEntity.new()
	get_tree().root.add_child(waiting)
	reg.await_rows(44, waiting)
	var after: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, FakeRow.new(44, 100.0))
	reg._on_row_event(after)
	_check(waiting.received.size() == 1 and waiting.received[0] == after and reg.peek_buffered(44).is_empty(),
		"an entity waiting to bind is handed its rows as they come, not buffered")
	reg.register(44, waiting)
	_check(waiting.received.size() == 1, "and registering it replays nothing twice")
	reg.unregister(44)
	waiting.free()
	var gone := FakeEntity.new()
	get_tree().root.add_child(gone)
	reg.await_rows(4601, gone)
	gone.free()
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, FakeRow.new(4601, 100.0)))
	_check(reg.peek_buffered(4601).size() == 1, "one that went before binding: its rows are buffered again")
	reg.take_buffered(4601)

	var orphan_delete: RowEvent = RowEvent.make(RowEvent.Kind.DELETED, &"health_state", FakeRow.new(99, 0.0), null)
	reg._on_row_event(orphan_delete)
	_check(reg.peek_buffered(99).is_empty(), "delete for unknown entity is not buffered")

	# --- ONE EVENT PER ROW (DECISIONS #176) -------------------------------------------------
	# The cache hands an update the very row it replaced as `old`, so it replaces the held event.
	var first: FakeRow = FakeRow.new(43, 100.0)
	var second: FakeRow = FakeRow.new(43, 80.0)
	var third: FakeRow = FakeRow.new(43, 60.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, first))
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", first, second))
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", second, third))
	var held: Array = reg.peek_buffered(43)
	_check(held.size() == 1 and (held[0] as RowEvent).kind == RowEvent.Kind.INSERTED
		and (held[0] as RowEvent).new == third,
		"an insert and two updates of one row are held as one insert of the latest (%d held)" % held.size())
	reg._on_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"health_state", third, null))
	_check(reg.peek_buffered(43).is_empty(), "a row inserted and deleted before its entity exists is not held")
	# Two rows of one table are two rows, whatever their values.
	reg._on_row_event(_item_ev(RowEvent.Kind.INSERTED, null, FakeItemRow.new(1, 45, 1, 1)))
	reg._on_row_event(_item_ev(RowEvent.Kind.INSERTED, null, FakeItemRow.new(1, 45, 1, 1)))
	_check(reg.peek_buffered(45).size() == 2, "two rows of one table are both held")
	# More rows than the old cap of 256, the entity's own state first: none of it is dropped.
	var pos_row: FakeRow = FakeRow.new(44, 100.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null, pos_row))
	for i: int in 900:
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null,
			FakeCatchRow.new(i, 44, 1, 1, "perch", 0.5)))
	var many := FakeEntity.new()
	get_tree().root.add_child(many)
	reg.register(44, many)
	_check(many.received.size() == 901, "an entity with 900 catches gets all 901 rows (got %d)" % many.received.size())
	_check(many.received.any(func(e: RowEvent) -> bool: return e.new == pos_row),
		"its own state, held first, is not pushed out by its catches")

	many.queue_free()
	ent.queue_free()
	reg.free()
