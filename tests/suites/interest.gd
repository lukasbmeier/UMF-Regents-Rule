extends "res://tests/suite_base.gd"
## The `interest` suite (tests/test_runner.gd runs it; `-- --only=interest` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_interest_tests()
	_run_ring_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## The SDK's subscription handle, which is all SpaceTimeSync touches for a subscription.
class FakeSubHandle extends RefCounted:
	signal applied()
	signal end()
	var error: int = OK
	var error_message: String = ""
	var unsubscribed: bool = false

	func unsubscribe() -> void:
		unsubscribed = true


## Stands in for the generated module client. Driving the REAL SpaceTimeSync.subscribe path with
## it is the point: the overlap this suite is about happens inside that path, so a test that
## called InterestManager's internals directly would prove nothing about it.
class FakeSubSdk extends Node:
	var handles: Array[FakeSubHandle] = []
	var queries: Array[PackedStringArray] = []
	var next_error: int = OK

	func subscribe(q: PackedStringArray) -> RefCounted:
		var h := FakeSubHandle.new()
		h.error = next_error
		next_error = OK
		handles.append(h)
		queries.append(q)
		return h

## THE ONE PLACE SUBSCRIPTION SQL IS BUILT (PHASE3_SPEC Task 11). Two things go wrong here and
## neither of them errors: asking for the wrong rows, which brings the game up empty with every
## entity stalled on its bind timeout and a clean log; and dropping the old subscription before
## the new one has arrived, which deletes every row in the cache and makes the spawner despawn
## and respawn the whole world mid-play.
func _run_interest_tests() -> void:
	print("== InterestManager: one place the SQL is built ==")
	var im: Node = _autoload("InterestManager")
	var sync: Node = _autoload("SpaceTimeSync")
	if im == null or sync == null:
		_check(false, "InterestManager and SpaceTimeSync autoloads are registered")
		return
	var prev_config: NetConfig = sync.config
	var prev_sdk: Variant = sync._sdk
	var prev_ready: bool = sync.is_world_ready
	var prev_state: int = sync.state
	var prev_world: int = im.world_id
	var prev_extra: Array[StringName] = im.extra_tables.duplicate()
	var cfg := NetConfig.new()
	sync.config = cfg

	# --- every table a game's entities need is in that game's set (DECISIONS #160) ------------
	# A game names its tables in its NetConfig (a .tres). The foundation's new `equip_state` was
	# missing from the fishing game's: nobody's rod came out on anyone else's screen, and nothing
	# said why. So each game scene's set is checked against what its entities' components require.
	# (Not the sidecar's: it leaves out what only a screen shows, on purpose.)
	# The foundation's scenes and the game's main scene (a genre's suites check its other scenes).
	var game_scenes: PackedStringArray = ["res://foundation/boot.tscn", "res://tests/levels/greybox_demo.tscn"]
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not main_scene.is_empty() and not game_scenes.has(main_scene):
		game_scenes.append(main_scene)
	for game_path: String in game_scenes:
		var st: SceneState = (load(game_path) as PackedScene).get_state()
		var game_cfg: NetConfig = null
		var defs: Array = []
		var with_genres: bool = false
		for n: int in range(st.get_node_count()):
			for p: int in range(st.get_node_property_count(n)):
				match st.get_node_property_name(n, p):
					&"net_config":
						game_cfg = st.get_node_property_value(n, p) as NetConfig
					&"entity_definitions":
						defs = st.get_node_property_value(n, p) as Array
					&"load_genres":
						with_genres = bool(st.get_node_property_value(n, p))
		game_cfg = (game_cfg if game_cfg != null else NetConfig.new()).duplicate() as NetConfig
		# A game scene boots shared/game.json's genres (DECISIONS #173): their definitions and tables
		# join the scene's, exactly as Boot joins them.
		if with_genres:
			var mods: Array[GenreModule] = Genres.modules()
			Genres.merge_tables(game_cfg, mods)
			defs = defs.duplicate()
			defs.append_array(Genres.definitions(mods))
		var missing: Array[String] = []
		for d: Variant in defs:
			var def: EntityDefinition = d as EntityDefinition
			if def == null or def.scene == null:
				continue
			var inst: Node = def.scene.instantiate()
			for c: Node in inst.find_children("*", "", true, false):
				var comp: SpaceTimeComponent = c as SpaceTimeComponent
				if comp == null:
					continue
				for t: StringName in comp.required_tables():
					if not game_cfg.core_tables.has(t):
						missing.append("%s's %s needs %s" % [def.resource_path.get_file(), comp.name, t])
			inst.free()
		_check(not defs.is_empty() and missing.is_empty(),
			"%s subscribes every table its entities' components need%s" % [game_path.get_file(),
				"" if missing.is_empty() else " (MISSING: %s)" % ", ".join(missing)])

	# --- (a) the question being asked ------------------------------------------------------
	var sidecar_table: Array[StringName] = [&"input_queue"]
	im.extra_tables = sidecar_table
	var qs: Array[String] = im.build_queries(3)
	_check(qs.has("SELECT * FROM entity WHERE world_id = 3 AND chunk != 4294967295"),
		"a per-world table is filtered to the world we are in (and a placed thing's, never a parked one)")
	_check(qs.has("SELECT * FROM item_def"),
		"a static catalogue is not: every world shares one")
	_check(qs.has("SELECT * FROM input_queue WHERE world_id = 3"),
		"and a table the sidecar adds goes through the same rule")
	var always: int = InterestManager.ALWAYS_TABLES.filter(func(t: StringName) -> bool: return not cfg.core_tables.has(t)).size()
	_check(qs.size() == cfg.core_tables.size() + 1 + always,
		"one query per table, %d for %d" % [qs.size(), cfg.core_tables.size() + 1 + always])
	_check(im.build_queries(0).has("SELECT * FROM entity WHERE world_id = 0 AND chunk != 4294967295"),
		"and world 0 is spelled out rather than left unfiltered")
	var dupe: Array[StringName] = [&"entity"]
	im.extra_tables = dupe
	_check(im.build_queries(0).size() == cfg.core_tables.size() + always,
		"an extra table already in the core set is not asked for twice")
	# What the foundation needs everywhere is asked for whatever a config lists (DECISIONS #201):
	# the hot rules and the authority list, whole (neither is per world).
	_check(qs.has("SELECT * FROM hot_rule") and qs.has("SELECT * FROM authority")
		and im.subscribed_tables().has(&"hot_rule"),
		"the hot rules and the authority list are always asked for, unfiltered")
	var none: Array[StringName] = []
	im.extra_tables = none

	# EVERY TABLE THE SHIPPED GAME SUBSCRIBES TO HAS BEEN DECIDED, one way or the other. Adding a
	# table to the config and forgetting this file is silent both ways: an unfiltered `entity`
	# subscribes the client to every world at once, and a filtered table with no `world_id` column
	# is a subscription the server refuses.
	# A GAME'S per-world tables are decided in its own NetConfig (`world_tables`), never by editing
	# the foundation's list (DECISIONS #154); a genre's suites check its own. These are the foundation's.
	var expect_filtered: Array[StringName] = [&"entity", &"movement_state", &"health_state",
		&"session", &"action_event", &"equip_state", &"appearance", &"lobby_member", &"world_level", &"session_match", &"status_state", &"hold_progress", &"hold_member", &"attachment", &"noise",
		&"body_state", &"body_contact", &"push", &"ground_item", &"resource_state", &"chat_message"]
	var expect_whole: Array[StringName] = [&"world_config", &"player", &"session_member",
		&"item_def", &"inventory_item", &"challenge", &"timed_press", &"ability_def", &"ability_state"]
	var shipped := NetConfig.new()
	_check(shipped != null, "the foundation's NetConfig is made")
	var undecided: Array[StringName] = []
	if shipped != null:
		for t: StringName in shipped.core_tables:
			if not expect_filtered.has(t) and not expect_whole.has(t):
				undecided.append(t)
	_check(undecided.is_empty(),
		"no table is subscribed without deciding whether it is per-world (%s)" % str(undecided))
	var wrong: Array[String] = []
	for t: StringName in expect_filtered:
		var q: String = im.query_for(t, 5, shipped)
		var cell: bool = InterestManager.CELL_TABLES.has(t)
		if not q.ends_with("WHERE world_id = 5" + (" AND chunk != 4294967295" if cell else "")):
			wrong.append("%s should be filtered (%s)" % [t, q])
	for t: StringName in expect_whole:
		if im.query_for(t, 5, shipped).contains("world_id"):
			wrong.append("%s should not be" % t)
	_check(wrong.is_empty(), "and each one is asked for the way it was decided (%s)" % str(wrong))

	# --- (b) the lifecycle, through the real subscribe path --------------------------------
	var fake := FakeSubSdk.new()
	add_child(fake)
	sync._sdk = fake
	sync._sets.clear()
	im._active = null
	im._incoming = null
	im.world_id = 0
	var readies: Array[int] = [0]
	var ready_cb: Callable = func() -> void: readies[0] += 1
	sync.world_ready.connect(ready_cb)
	var switched: Array[int] = []
	var switched_cb: Callable = func(w: int) -> void: switched.append(w)
	im.world_changed.connect(switched_cb)

	sync.state = SpaceTimeSync.ConnectionState.CONNECTED
	_check(fake.handles.size() == 1 and not im.has_world(),
		"connecting asks for the default world and waits for the server to confirm")
	_check(readies[0] == 0, "world_ready has not fired yet (%d)" % readies[0])
	fake.handles[0].applied.emit()
	_check(im.has_world() and readies[0] == 1 and sync._sets.size() == 1,
		"once it applies: one active set, world_ready once (%d sets, %d ready)"
			% [sync._sets.size(), readies[0]])

	# THE OVERLAP, which is the whole reason this is its own object.
	im.set_world(1)
	_check(fake.handles.size() == 2 and not fake.handles[0].unsubscribed,
		"switching world subscribes the new set while the old one is STILL LIVE")
	_check(sync._sets.size() == 2 and readies[0] == 1,
		"both are active for the moment (%d sets), and world_ready waits" % sync._sets.size())
	fake.handles[1].applied.emit()
	_check(fake.handles[0].unsubscribed,
		"the old set is dropped only once the new one has applied")
	_check(sync._sets.size() == 1 and switched == [0, 1] and readies[0] == 2,
		"leaving exactly one active set (%d), world_changed %s, world_ready twice (%d)"
			% [sync._sets.size(), str(switched), readies[0]])

	im.set_world(2)
	fake.handles[2].applied.emit()
	_check(sync._sets.size() == 1 and switched == [0, 1, 2] and readies[0] == 3,
		"switching a SECOND time still leaves exactly one active set (%d sets, %s)"
			% [sync._sets.size(), str(switched)])
	im.set_world(2)
	_check(fake.handles.size() == 3, "asking for the world we are already in does nothing")

	# A switch overtaken before the server answers must not apply into a world we have left.
	im.set_world(3)
	im.set_world(4)
	_check(fake.handles[3].unsubscribed,
		"a pending set is cancelled when another switch overtakes it")
	fake.handles[3].applied.emit()   # the server answers the cancelled one anyway
	_check(im.world_id == 4 and sync._sets.size() == 2 and switched.size() == 3,
		"and its late confirmation is ignored (world %d, %s)" % [im.world_id, str(switched)])
	fake.handles[4].applied.emit()
	_check(sync._sets.size() == 1 and switched == [0, 1, 2, 4],
		"the world asked for LAST is the one left active (%s)" % str(switched))

	# A reconnect re-applies the handle we already hold (they survive it), so no new set — but
	# world_ready must fire again, because everything downstream has always waited on it.
	var before_reconnect: int = fake.handles.size()
	fake.handles[4].applied.emit()
	_check(fake.handles.size() == before_reconnect and sync._sets.size() == 1,
		"a re-applied handle does not build a second set")
	_check(readies[0] == 5, "but world_ready fires again for it (%d)" % readies[0])

	# A refused subscription has to be loud: silently it is a game that comes up empty.
	fake.next_error = ERR_CANT_CONNECT
	im.set_world(7)
	_check(im._incoming == null, "a refused subscription is not left pending forever")
	_check(sync._sets.size() == 1 and im.has_world(),
		"and the world we already had is still subscribed (%d sets)" % sync._sets.size())

	# Leaving a set subscribed would leak it and its handle, which is exactly what the cycle
	# fixed in SpaceTimeSync.unsubscribe() was; tear down the way a real disconnect does.
	if im._active != null:
		var dropped: SubscriptionSet = im._active
		sync.unsubscribe(dropped)
		# An unsubscribed set lets go of the SDK's handle. That is what tells a late `end` "we
		# asked for this" from "the server refused it", and it releases the SDK's own
		# subscription object instead of holding it for the life of the process.
		_check(dropped._handle == null, "an unsubscribed set lets go of its SDK handle")
	_check(sync._sets.is_empty(), "the suite leaves no subscription behind (%d)" % sync._sets.size())
	sync.world_ready.disconnect(ready_cb)
	im.world_changed.disconnect(switched_cb)
	sync.state = prev_state
	sync._sets.clear()
	sync._sdk = prev_sdk
	sync.config = prev_config
	sync.is_world_ready = prev_ready
	im.world_id = prev_world
	im.extra_tables = prev_extra
	im._active = null
	im._incoming = null
	fake.free()


## RING INTEREST (template 1.0, DECISIONS #278): a client in a big world is sent only the cells round its
## player. Two sets: the world's (catalogues, rules, sessions: swapped only with the world) and the
## ring's (every row of a placed thing, by cell, and our own rows by id), swapped as the player walks,
## with the same overlap as a world so a neighbour in a cell both rings share never respawns.
func _run_ring_tests() -> void:
	print("== InterestManager: the cells round you (RING) ==")
	var im: Node = _autoload("InterestManager")
	var sync: Node = _autoload("SpaceTimeSync")
	if im == null or sync == null:
		return
	var prev_config: NetConfig = sync.config
	var prev_sdk: Variant = sync._sdk
	var prev_state: int = sync.state
	var prev_world: int = im.world_id
	var cfg := NetConfig.new()
	cfg.interest = NetConfig.Interest.RING
	sync.config = cfg

	# Every cell table is also filtered by world for a WORLD client, and the ones that follow an entity are cell tables.
	var not_world: Array[StringName] = []
	for t: StringName in InterestManager.CELL_TABLES:
		if not InterestManager.WORLD_TABLES.has(t):
			not_world.append(t)
	var not_cell: Array[StringName] = []
	for t: StringName in InterestManager.FOLLOW_TABLES:
		if not InterestManager.CELL_TABLES.has(t):
			not_cell.append(t)
	_check(not_world.is_empty() and not_cell.is_empty(),
		"every cell table is a world table %s, every follow table a cell table %s" % [not_world, not_cell])
	_check(sync.row_event.is_connected(im._on_row_event) and SignalBus.local_entity_assigned.is_connected(im._on_local_entity),
		"the ring hears our player's rows and who our player is")

	var fake := FakeSubSdk.new()
	add_child(fake)
	sync._sdk = fake
	sync._sets.clear()
	im._active = null
	im._incoming = null
	im._ring_active = null
	im._ring_incoming = null
	im._own_active = null
	im._own_incoming = null
	im.centre = -1
	im.own_entity = -1
	im.world_id = 0
	var moves: Array[int] = []
	var moved_cb: Callable = func(c: int) -> void: moves.append(c)
	im.cells_changed.connect(moved_cb)

	sync.state = SpaceTimeSync.ConnectionState.CONNECTED
	_check(fake.handles.size() == 1, "connecting asks for the world's set only: no player, no place yet (%d sets)" % fake.handles.size())
	var base: PackedStringArray = fake.queries[0]
	_check(base.has("SELECT * FROM player") and base.has("SELECT * FROM session WHERE world_id = 0")
		and not ",".join(base).contains("FROM entity ") and not ",".join(base).contains("chunk"),
		"the world's set has what is not placed (players, sessions) and no placed thing")
	fake.handles[0].applied.emit()

	im._on_local_entity(77)
	_check(fake.handles.size() == 2, "our player known: a set of our own rows is asked for")
	var own: PackedStringArray = fake.queries[1]
	_check(own.has("SELECT * FROM movement_state WHERE entity_id = 77") and own.has("SELECT * FROM entity WHERE entity_id = 77")
		and not own.has("SELECT * FROM noise WHERE entity_id = 77") and not ",".join(own).contains("chunk"),
		"our own rows by id, before we know where we are (an event is not ours to follow)")
	fake.handles[1].applied.emit()
	_check(im.own_set() != null and moves.is_empty(), "and it applies (no cells yet)")

	var here := Vector3(32, 0, 32)
	im._on_row_event(_move_ev(FakeMoveRow.new(77, here, 0)))
	var c0: int = Cells.chunk_of(here)
	_check(im.centre == c0 and fake.handles.size() == 3, "our movement row places the ring (centre %d)" % im.centre)
	var r0: PackedStringArray = fake.queries[2]
	var cells0: PackedInt64Array = Cells.ring(c0, 1)
	var missing: Array[String] = []
	for c: int in cells0:
		for t: StringName in [&"entity", &"movement_state", &"noise", &"ground_item"]:
			var q: String = "SELECT * FROM %s WHERE world_id = 0 AND chunk = %d" % [t, c]
			if not r0.has(q):
				missing.append(q)
	_check(missing.is_empty(), "every cell table, for each of the nine cells: %s" % ", ".join(missing.slice(0, 3)))
	_check(not ",".join(r0).contains("entity_id = 77"), "the cells' set asks by cell only: no row is two of its queries'")
	_check(not ",".join(r0).contains("item_def") and not ",".join(r0).contains("hot_rule"), "nothing of the world's set is asked again")
	fake.handles[2].applied.emit()
	_check(not fake.handles[1].unsubscribed and not fake.handles[0].unsubscribed and moves == [c0],
		"the ring arrives; our own set and the world's are never touched (%s)" % str(moves))

	im._on_row_event(_move_ev(FakeMoveRow.new(77, Vector3(65, 0, 32), 0)))
	_check(fake.handles.size() == 3 and im.centre == c0, "a step over the edge moves nothing")
	im._on_row_event(_move_ev(FakeMoveRow.new(77, Vector3(68.5, 0, 32), 0)))
	var c1: int = Cells.chunk_of(Vector3(68.5, 0, 32))
	_check(fake.handles.size() == 4 and im.centre == c1, "well inside the next cell, the ring follows")
	var far_east: int = Cells.at(Cells.squares(c0).x + 2, Cells.squares(c0).y)
	_check(fake.queries[3].has("SELECT * FROM entity WHERE world_id = 0 AND chunk = %d" % far_east)
		and not fake.queries[3].has("SELECT * FROM entity WHERE world_id = 0 AND chunk = %d"
			% Cells.at(Cells.squares(c0).x - 1, Cells.squares(c0).y)),
		"gaining the column ahead, losing the one behind")
	im._on_row_event(_move_ev(FakeMoveRow.new(77, Vector3(300, 0, 32), 0)))
	_check(fake.handles[3].unsubscribed and fake.handles.size() == 5, "moved on before it applied: the pending one is cancelled")
	fake.handles[4].applied.emit()
	_check(fake.handles[2].unsubscribed and moves.back() == Cells.chunk_of(Vector3(300, 0, 32)), "and the last asked is the one kept")
	_check(not fake.handles[1].unsubscribed, "our own set stays through every move")

	im.set_world(1)
	_check(fake.handles.size() == 7 and fake.queries[6].has("SELECT * FROM entity WHERE world_id = 1 AND chunk = %d" % im.centre),
		"another world: a new world set and a new ring, in that world")
	fake.handles[5].applied.emit()
	fake.handles[6].applied.emit()

	var ref := NetConfig.new()
	ref.interest = NetConfig.Interest.RING
	ref.authority_process = true
	_check(not im.is_ring(ref), "a sidecar or referee is never a ring: it runs the whole world")
	var world_cfg := NetConfig.new()
	_check(not im.is_ring(world_cfg), "and WORLD is the default")

	for set: SubscriptionSet in [im._active, im._ring_active, im._own_active]:
		if set != null:
			sync.unsubscribe(set)
	_check(sync._sets.is_empty(), "the suite leaves no subscription behind (%d)" % sync._sets.size())
	im.cells_changed.disconnect(moved_cb)
	sync.state = prev_state
	sync._sets.clear()
	sync._sdk = prev_sdk
	sync.config = prev_config
	im.world_id = prev_world
	im._active = null
	im._incoming = null
	im._ring_active = null
	im._ring_incoming = null
	im._own_active = null
	im._own_incoming = null
	im.centre = -1
	im.own_entity = -1
	fake.free()
