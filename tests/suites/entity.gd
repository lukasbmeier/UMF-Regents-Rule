extends "res://tests/suite_base.gd"
## The `entity` suite (tests/test_runner.gd runs it; `-- --only=entity` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_entity_tests()
	_run_kin_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


## Stands in for the Health/Movement components until Tasks 5-6 land, so the entity's routing
## and bind gating can be tested on the real player.tscn today.
class TableProbe extends SpaceTimeComponent:
	var tables: Array[StringName] = []
	var bound_rows: int = 0
	var events: Array[StringName] = []

	func required_tables() -> Array[StringName]:
		return tables

	func _on_row_updated(table: StringName, _old: RefCounted, _new: RefCounted) -> void:
		events.append(table)

	func _on_bound() -> void:
		bound_rows = events.size()

static func _probe(table_names: Array[StringName], node_name: String) -> TableProbe:
	var p := TableProbe.new()
	p.tables = table_names
	p.name = node_name
	return p


func _run_entity_tests() -> void:
	print("== SpaceTimeEntity ==")
	var bus: Node = _autoload("SignalBus")
	var reg: Node = _autoload("EntityRegistry")
	_check(bus != null and reg != null, "SignalBus and EntityRegistry autoloads present")
	if bus == null or reg == null:
		return
	var scene: PackedScene = load(PLAYER_SCENE) as PackedScene
	_check(scene != null, "player.tscn loads")
	if scene == null:
		return

	# --- happy path: every required table present at bind ---------------------------
	var ent: SpaceTimeEntity = scene.instantiate() as SpaceTimeEntity
	_check(ent != null, "player.tscn root is a SpaceTimeEntity")
	if ent == null:
		return
	var health_probe: TableProbe = _probe([&"health_state"], "Health")
	var move_probe: TableProbe = _probe([&"movement_state"], "Movement")
	ent.get_node(^"Components").add_child(health_probe)
	ent.get_node(^"Components").add_child(move_probe)

	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.display_name = "Test Player"
	ent.definition = defn
	get_tree().root.add_child(ent)

	var spawned: Array[int] = []
	var cb := func(eid: int, _kind: int) -> void: spawned.append(eid)
	bus.entity_spawned.connect(cb)

	ent.bind(7, 0, PackedByteArray(), _player_rows(7))

	_check(ent.is_bound(), "binds immediately when all required tables are present")
	_check(ent.entity_id == 7 and ent.world_id == 0, "bind sets entity_id and world_id")
	_check(health_probe.is_bound() and move_probe.is_bound(), "all components bound")
	_check(health_probe.bound_rows == 1, "component received its initial row before _on_bound")
	_check(spawned.size() == 1 and spawned[0] == 7, "entity_spawned emitted exactly once")
	_check(reg.has_entity(7), "registered with EntityRegistry")
	_check(ent.body == ent, "body property is the entity itself")

	# --- routing: an event goes only to the component that asked for the table -------
	health_probe.events.clear()
	move_probe.events.clear()
	ent.receive_row_event(RowEvent.make(
		RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(7, 100.0), FakeRow.new(7, 60.0)))
	_check(health_probe.events == [&"health_state"], "row routed to the component that wants it")
	_check(move_probe.events.is_empty(), "row NOT routed to components that did not ask")

	# An unrouted table must not crash or fan out.
	ent.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"world_config", null, FakeGlobalRow.new()))
	_check(move_probe.events.is_empty(), "unrouted table is ignored")

	# --- remote entity drops the camera rig, keeps the nameplate --------------------
	_check(not ent.is_local_authority, "entity 7 is not the local player in this test")
	_check(not ent.has_node(^"CameraRig"), "remote entity freed CameraRig")
	_check(ent.has_node(^"Nameplate"), "remote entity kept Nameplate")

	bus.entity_spawned.disconnect(cb)
	reg.unregister(7)
	ent.queue_free()

	# --- missing-table path: binds anyway after the timeout, with a warning ----------
	var slow: SpaceTimeEntity = scene.instantiate() as SpaceTimeEntity
	var slow_probe: TableProbe = _probe([&"health_state", &"movement_state"], "Both")
	slow.get_node(^"Components").add_child(slow_probe)
	slow.definition = defn
	slow.bind_timeout_sec = 0.05
	get_tree().root.add_child(slow)
	# Hold back a row from a REQUIRED table. It used to hold back whichever row came last, which
	# became `inventory_item` — a collection a fresh player legitimately has none of, and now
	# declared optional (DECISIONS #69). The converse is asserted just below.
	var slow_rows: Array = _player_rows(8)
	var straggler: RowEvent = null
	for ev: RowEvent in slow_rows:
		if ev.table == &"movement_state":
			straggler = ev
	slow_rows.erase(straggler)
	slow.bind(8, 0, PackedByteArray(), slow_rows)
	_check(not slow.is_bound(), "waits while a required table is still missing")

	# The straggler arriving before the timeout binds immediately, no warning.
	slow.receive_row_event(straggler)
	_check(slow.is_bound(), "binds as soon as the last required table arrives")
	_check(slow_probe.bound_rows == 2, "late rows still delivered as initial state")
	reg.unregister(8)
	slow.queue_free()

	# The converse, and the fix for every player standing frozen for two seconds at spawn: a
	# table a component declares OPTIONAL — a collection that may be empty, like a new player's
	# inventory — never delays bind. Before `optional_tables()` this waited out the timeout.
	var quick: SpaceTimeEntity = scene.instantiate() as SpaceTimeEntity
	quick.definition = defn
	quick.bind_timeout_sec = 5.0
	get_tree().root.add_child(quick)
	var quick_rows: Array = []
	for ev: RowEvent in _player_rows(9):
		if ev.table != &"inventory_item":
			quick_rows.append(ev)
	quick.bind(9, 0, PackedByteArray(), quick_rows)
	_check(quick.is_bound(), "an empty OPTIONAL table (no inventory rows) does not delay bind")
	reg.unregister(9)
	quick.queue_free()


## FRIENDLY COLLISION (DECISIONS #238): a character's kin layer; solid to its kin only while the rule is on.
func _run_kin_tests() -> void:
	print("== entity: friendly collision ==")
	var hot: Node = _autoload("HotRules")
	var defn := EntityDefinition.new()
	defn.kin_layer = 6
	var ent := SpaceTimeEntity.new()
	ent.definition = defn
	ent.collision_layer = 2
	ent.collision_mask = 5
	var bit: int = 1 << 5
	ent.apply_kin_collision()
	_check(ent.collision_layer & bit != 0 and ent.collision_mask & bit == 0 and ent.collision_mask & 5 == 5,
		"the rule off (by default): on its kin layer, solid to nothing more")
	var on := _HotRow.new(&"foundation.friendly_collision", 1.0)
	hot.call(&"_on_row", RowEvent.make(RowEvent.Kind.INSERTED, &"hot_rule", null, on))
	ent.apply_kin_collision()
	_check(ent.collision_mask & bit != 0, "the rule on: solid to its kin")
	hot.call(&"_on_row", RowEvent.make(RowEvent.Kind.DELETED, &"hot_rule", on, null))
	ent.apply_kin_collision()
	_check(ent.collision_mask & bit == 0 and ent.collision_layer & 2 != 0, "off again: they pass through each other; its own layer kept")
	var none := SpaceTimeEntity.new()
	none.definition = EntityDefinition.new()
	none.collision_mask = 5
	none.apply_kin_collision()
	_check(none.collision_mask == 5, "a character with no kin layer: untouched")
	ent.free()
	none.free()


class _HotRow extends RefCounted:
	var key: String
	var number: float
	var text: String = ""
	var overridden: bool = true
	func _init(k: StringName, n: float) -> void:
		key = String(k)
		number = n
