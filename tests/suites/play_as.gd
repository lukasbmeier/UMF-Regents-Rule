extends "res://tests/suite_base.gd"
## The `play_as` suite (tests/test_runner.gd runs it; `-- --only=play_as` runs it alone).
## CHOOSING A CHARACTER (DECISIONS #217): a character a player may choose is content (`playable`,
## baked for the server); the lobby offers the game's (Play as, C) and asks the server
## (`choose_character`); when an entity's kind changes, every client builds it again as the new
## character. The server's side: tests/integration_test.sh (refusals) and a game with two playable
## characters (Fowl Play's integration suite: a hen made a wolf and back).

const HEN_KIND: int = 120
const WOLF_KIND: int = 121


func run() -> void:
	_run_content()
	await _run_rebuilt()


func _def(kind: int, name: String, playable: bool) -> EntityDefinition:
	var d := EntityDefinition.new()
	d.kind = kind
	d.display_name = name
	d.playable = playable
	d.scene = load(PLAYER_SCENE) as PackedScene
	return d


func _run_content() -> void:
	print("== play as: the characters a player may choose ==")
	var d: EntityDefinition = _def(HEN_KIND, "Hen", true)
	_check(bool(d.to_bake().get("playable", false)) and not bool(_def(1, "NPC", false).to_bake().get("playable", true)),
		"playable is baked for the server (its PLAYABLE_KINDS)")
	var bot: EntityDefinition = _def(HEN_KIND, "Hen bot", true)
	bot.brain = &"wander"
	_check(bot.validate().any(func(w: String) -> bool: return w.contains("playable and has a brain")),
		"a playable character with a brain is flagged: a player plays it")
	var baked: String = FileAccess.get_file_as_string("res://shared/content/foundation/character.json")
	_check(baked.contains("\"playable\": false"), "the foundation's own characters are not offered (a game marks its own)")

	var spawner: Node = _autoload("EntitySpawner")
	var saved_defs: Array[EntityDefinition] = spawner.definitions.duplicate()
	var saved_kinds: Dictionary = spawner._by_kind.duplicate()
	spawner.register_definition(_def(WOLF_KIND, "Wolf", true))
	spawner.register_definition(_def(HEN_KIND, "Hen", true))
	spawner.register_definition(_def(1, "NPC", false))
	var kinds: Array = spawner.playable_characters().map(func(e: EntityDefinition) -> int: return e.kind)
	_check(kinds == [HEN_KIND, WOLF_KIND], "the playable ones, one per kind, by kind: %s" % str(kinds))

	var reg: Node = _autoload("EntityRegistry")
	var prev_local: int = reg.local_entity_id
	var me := SpaceTimeEntity.new()
	me.definition = spawner._by_kind[HEN_KIND]
	get_tree().root.add_child(me)
	reg.register(7101, me)
	reg.local_entity_id = 7101
	_check(LobbyPanel.next_character() == WOLF_KIND, "a hen's next character is the wolf")
	me.definition = spawner._by_kind[WOLF_KIND]
	_check(LobbyPanel.next_character() == HEN_KIND, "and the wolf's, round again, the hen")
	spawner._by_kind.erase(WOLF_KIND)
	spawner.definitions.assign(spawner.definitions.filter(func(e: EntityDefinition) -> bool: return e.kind != WOLF_KIND))
	me.definition = spawner._by_kind[HEN_KIND]
	_check(LobbyPanel.next_character() == -1, "only one to choose from: nothing to change to (no Play as)")
	reg.unregister(7101)
	reg.local_entity_id = prev_local
	me.queue_free()
	spawner.definitions = saved_defs
	spawner._by_kind = saved_kinds


## The SDK's cache, as far as a respawn reads it.
class FakeCache extends RefCounted:
	var tables: Dictionary = {}
	func put(table: StringName, pk: Variant, row: RefCounted) -> void:
		if not tables.has(table):
			tables[table] = {}
		tables[table][pk] = row
	func get_row_by_pk(table: StringName, pk: Variant) -> RefCounted:
		return (tables.get(table, {}) as Dictionary).get(pk)
	func find_where(table: StringName, pred: Callable) -> Array:
		var out: Array = []
		for r: Variant in (tables.get(table, {}) as Dictionary).values():
			if pred.call(r):
				out.append(r)
		return out


class FakeSdk extends Node:
	var cache: FakeCache = FakeCache.new()
	func get_local_database() -> Object:
		return cache


func _run_rebuilt() -> void:
	print("== play as: an entity whose kind changes is built again as the new character ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var saved_defs: Array[EntityDefinition] = spawner.definitions.duplicate()
	var saved_kinds: Dictionary = spawner._by_kind.duplicate()
	var hen: EntityDefinition = _def(HEN_KIND, "Hen", true)
	var wolf: EntityDefinition = _def(WOLF_KIND, "Wolf", true)
	spawner.register_definition(hen)
	spawner.register_definition(wolf)
	var holder := Node3D.new()
	get_tree().root.add_child(holder)
	var prev_root: NodePath = spawner.world_root_path
	var prev_ready: bool = spawner._world_ready
	var prev_sdk: Node = SpaceTimeSync._sdk
	var prev_cfg: NetConfig = SpaceTimeSync.config
	spawner.world_root_path = spawner.get_path_to(holder)
	spawner._world_ready = true
	var fake := FakeSdk.new()
	add_child(fake)
	SpaceTimeSync._sdk = fake
	SpaceTimeSync.config = NetConfig.new()
	Genres.merge_tables(SpaceTimeSync.config, Genres.modules())
	var eid: int = 7201
	var as_hen := FakeEntityRow.new(eid, HEN_KIND)
	fake.cache.put(&"entity", eid, as_hen)
	for ev: RowEvent in _player_rows(eid):
		fake.cache.put(ev.table, int(ev.current().get(&"entity_id") if ev.current().get(&"entity_id") != null else ev.current().get(&"id")), ev.current())
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, as_hen))
	await get_tree().process_frame
	var first: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(first != null and first.definition == hen and first.is_bound(), "spawned a hen")
	# The same kind again (its row rewritten for another reason): left as it is.
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"entity", as_hen, FakeEntityRow.new(eid, HEN_KIND)))
	_check(spawner.get_entity_node(eid) == first, "an update that keeps the kind keeps the entity")
	var as_wolf := FakeEntityRow.new(eid, WOLF_KIND)
	fake.cache.put(&"entity", eid, as_wolf)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"entity", as_hen, as_wolf))
	await get_tree().process_frame
	var again: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(again != null and again != first and again.definition == wolf and again.is_bound(),
		"made a wolf: built again from the wolf's definition, bound (%s)" % (again.definition.display_name if again != null and again.definition != null else "none"))
	var mv: SpaceTimeMovementComponent = again.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if again != null else null
	_check(mv != null and mv.is_bound(), "its components bound again, from the cache's rows")
	_check(not is_instance_valid(first) or first.is_queued_for_deletion() or not first.is_inside_tree(), "and the hen's node is gone")
	spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", as_wolf, null))
	spawner._flush_despawns()
	await get_tree().process_frame
	SpaceTimeSync._sdk = prev_sdk
	SpaceTimeSync.config = prev_cfg
	fake.queue_free()
	spawner.world_root_path = prev_root
	spawner._world_ready = prev_ready
	spawner.definitions = saved_defs
	spawner._by_kind = saved_kinds
	holder.queue_free()
