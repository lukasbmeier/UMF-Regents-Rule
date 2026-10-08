extends "res://tests/suite_base.gd"
## The `spawner` suite (tests/test_runner.gd runs it; `-- --only=spawner` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_spawner_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


func _run_spawner_tests() -> void:
	print("== EntitySpawner ==")
	var reg: Node = _autoload("EntityRegistry")
	var bus: Node = _autoload("SignalBus")
	var spawner: Node = _autoload("EntitySpawner")
	_check(spawner != null, "EntitySpawner autoload registered")
	if spawner == null or reg == null or bus == null:
		return

	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.display_name = "Player"
	defn.scene = load(PLAYER_SCENE) as PackedScene
	spawner.register_definition(defn)

	var holder := Node.new()
	holder.name = "SpawnerWorldRoot"
	get_tree().root.add_child(holder)
	spawner.world_root_path = spawner.get_path_to(holder)
	spawner._world_ready = true

	var despawned: Array[int] = []
	var dcb := func(eid: int) -> void: despawned.append(eid)
	bus.entity_despawned.connect(dcb)

	# --- insert spawns and binds ----------------------------------------------------
	# player.tscn carries a Health component, so its health_state row must already be buffered
	# or the entity would correctly sit waiting for its bind timeout.
	_buffer_player_rows(reg, 101)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(101, 0)))
	_check(spawner.spawned_count() == 1, "insert spawns one node")
	var node: Node = spawner.get_entity_node(101)
	_check(node != null and node.get_parent() == holder, "spawned under the world root")
	_check(node != null and node.is_bound(), "spawned entity is bound")
	_check(reg.has_entity(101), "spawned entity registered")

	# --- unknown kind is refused, not guessed ---------------------------------------
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(102, 77)))
	_check(spawner.spawned_count() == 1, "unknown kind does not spawn")

	# --- duplicate insert is a no-op ------------------------------------------------
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(101, 0)))
	_check(spawner.spawned_count() == 1, "duplicate insert does not double-spawn")

	# --- RECONNECT: delete then re-insert in the SAME frame is a rebind -------------
	# This is the case that would otherwise despawn and respawn the local player.
	var before: Node = spawner.get_entity_node(101)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(101, 0), null))
	_check(spawner.spawned_count() == 1, "delete alone does not free immediately")
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(101, 0)))
	spawner._flush_despawns()
	_check(spawner.spawned_count() == 1, "reconnect yields exactly one node")
	_check(spawner.get_entity_node(101) == before, "reconnect kept the SAME node (rebind)")
	_check(despawned.is_empty(), "reconnect emits no entity_despawned")

	# --- a real delete does despawn -------------------------------------------------
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(101, 0), null))
	spawner._flush_despawns()
	_check(spawner.spawned_count() == 0, "delete with no re-insert frees the node")
	_check(despawned == [101], "entity_despawned emitted once for a real delete")
	_check(not reg.has_entity(101), "unregistered from EntityRegistry")

	# --- A SESSION ENDING tears the world down -------------------------------------------
	# The SDK keeps its rows after `disconnected` so a game can read last-known state. The
	# spawner used to keep the SCENES too: a player who left was still standing in the world,
	# still sampling input and still holding the mouse cursor behind the connect screen.
	despawned.clear()
	_buffer_player_rows(reg, 111)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(111, 0)))
	_buffer_player_rows(reg, 112)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(112, 0)))
	_check(spawner.spawned_count() == 2, "two entities in the world before the session ends")
	spawner._on_connection_state(SpaceTimeSync.ConnectionState.RECONNECTING)
	_check(spawner.spawned_count() == 2,
		"a TRANSIENT drop keeps the world: it reconnects in place (DECISIONS #17)")
	spawner._on_connection_state(SpaceTimeSync.ConnectionState.DISCONNECTED)
	despawned.sort()
	_check(spawner.spawned_count() == 0 and despawned == [111, 112],
		"a terminal disconnect despawns every entity (%s)" % str(despawned))
	_check(not reg.has_entity(111) and not reg.has_entity(112), "and unregisters them")
	# The next session's rows arrive before its world_ready does, as on a first connect.
	_buffer_player_rows(reg, 113)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(113, 0)))
	_check(spawner.spawned_count() == 0,
		"the next session's entities wait for its world, like the first session's did")
	spawner._on_world_ready()
	_check(spawner.spawned_count() == 1 and spawner.get_entity_node(113) != null,
		"and spawn when it is ready")
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(113, 0), null))
	spawner._flush_despawns()

	bus.entity_despawned.disconnect(dcb)
	holder.queue_free()
