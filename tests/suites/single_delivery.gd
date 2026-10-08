extends "res://tests/suite_base.gd"
## The `single_delivery` suite (tests/test_runner.gd runs it; `-- --only=single_delivery` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_single_delivery_test()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- regression: initial rows must be delivered exactly once ----------------------------

func _run_single_delivery_test() -> void:
	print("== single delivery ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	if reg == null or spawner == null:
		_check(false, "autoloads present")
		return

	var holder := Node.new()
	get_tree().root.add_child(holder)
	spawner.world_root_path = spawner.get_path_to(holder)
	spawner._world_ready = true

	# Buffer the health row first, exactly as the cache would before the entity row lands.
	_buffer_player_rows(reg, 202)
	var emissions: Array[float] = []
	var bus: Node = _autoload("SignalBus")
	var cb := func(eid: int, cur: float, _m: float) -> void:
		if eid == 202:
			emissions.append(cur)
	bus.entity_health_changed.connect(cb)

	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(202, 0)))

	# Previously this fired twice: once from bind()'s initial rows, once from register()
	# replaying the same still-buffered events.
	_check(emissions.size() == 1,
		"initial health row delivered exactly once (got %d)" % emissions.size())
	_check(reg.peek_buffered(202).is_empty(), "buffer drained by the spawner")

	bus.entity_health_changed.disconnect(cb)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(202, 0), null))
	spawner._flush_despawns()

	# THE RIVAL IN THE LAKE (DECISIONS #176): an entity whose rows outnumber the registry's old cap
	# arrives with its position first and 900 owned rows after it, then its entity row. Spawned by
	# the real spawner into the real player scene, it stands where its row says, not at the origin.
	var at := Vector3(-40.0, 1.02, 50.0)
	for ev: RowEvent in _player_rows(203):
		if ev.table == &"movement_state":
			ev = RowEvent.make(RowEvent.Kind.INSERTED, &"movement_state", null, FakeMoveRow.new(203, at, 0))
		reg._on_row_event(ev)
	for i: int in 900:
		reg._on_row_event(_item_ev(RowEvent.Kind.INSERTED, null, FakeItemRow.new(5000 + i, 203, 1, 1)))
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(203, 0)))
	var crowded: SpaceTimeEntity = spawner.get_entity_node(203) as SpaceTimeEntity
	_check(crowded != null and crowded.is_bound(),
		"an entity with 900 owned rows binds at once (no bind timeout waiting for rows it was sent)")
	if crowded != null:
		_check(crowded.global_position.distance_to(at) < 0.01,
			"and stands where its movement row says (%s), not at the origin (got %s)" % [at, crowded.global_position])
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(203, 0), null))
	spawner._flush_despawns()
	holder.queue_free()
