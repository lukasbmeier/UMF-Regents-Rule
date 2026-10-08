extends Node
## Headless test runner. No framework dependency. Golden vectors here are GDScript regression
## tests for movement_model.gd (the live model shared by client and sidecar).
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 on success, 1 on any failure. Add new suites to _run_all().
##
## This is a SCENE, not a `--script` runner, and that is deliberate. `--script` compiles the
## runner (and every script it names as a type) BEFORE the autoloads are registered, so any
## foundation script that references `SignalBus` or `EntityRegistry` fails with
## "Identifier not found" the moment a test annotates a variable with its class. Running as a
## scene puts the harness in the same startup order as the real game, which also means the
## foundation stays free to use autoloads the idiomatic way.

const GOLDEN_DIR: String = "res://shared/golden/movement/"

var _failures: int = 0
var _passes: int = 0


## GDScript's `%` operator has no `%e` conversion (it raises "unsupported format character"),
## so scientific notation is built by hand. Output matches the Rust harness: `0.000e+00`.
static func _sci(v: float) -> String:
	if v == 0.0:
		return "0.000e+00"
	var exp: int = int(floor(log(absf(v)) / log(10.0)))
	var mantissa: float = v / pow(10.0, float(exp))
	return "%.3f%s%02d" % [mantissa, "e+" if exp >= 0 else "e-", absi(exp)]

## `-- --only=lakeside,characters` runs just those suites, named as `_run_all` names them, for
## iterating on one. Only the full run counts: suites share autoloads, and a later one can
## depend on state an earlier one left.
var _only: PackedStringArray = PackedStringArray()


func _on(suite: String) -> bool:
	return _only.is_empty() or _only.has(suite)


func _ready() -> void:
	# One frame later, not now: during _ready the scene tree root is still "setting up
	# children" and refuses add_child(), which the entity suites need in order to put a
	# CharacterBody3D in the tree. Autoloads are already up by _ready, so this deferral is
	# only about tree state.
	_run_all.call_deferred()


func _run_all() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	if _on("golden"):
		_run_golden_vectors()
	if _on("config"):
		_run_config_tests()
	if _on("rules"):
		_run_rules_tests()
	if _on("row_event"):
		_run_row_event_tests()
	if _on("interest"):
		_run_interest_tests()
	if _on("authority"):
		await _run_authority_tests()
	if _on("npc"):
		await _run_npc_tests()
	if _on("gear"):
		_run_gear_tests()
	if _on("standings"):
		_run_standings_tests()
	if _on("entity_registry"):
		_run_entity_registry_tests()
	if _on("component"):
		_run_component_tests()
	if _on("challenge"):
		_run_challenge_tests()
	if _on("fishing_rules"):
		_run_fishing_rules_tests()
	if _on("fight"):
		_run_fight_tests()
	if _on("level_bake"):
		_run_level_bake_tests()
	if _on("entity"):
		_run_entity_tests()
	if _on("spawner"):
		_run_spawner_tests()
	if _on("health"):
		_run_health_tests()
	if _on("single_delivery"):
		_run_single_delivery_test()
	if _on("movement"):
		_run_movement_tests()
	if _on("prediction"):
		_run_prediction_tests()
	if _on("input"):
		_run_input_tests()
	if _on("session"):
		_run_session_tests()
	if _on("inventory"):
		_run_inventory_tests()
	if _on("interaction"):
		_run_interaction_tests()
	if _on("action"):
		_run_action_tests()
	if _on("mouse_capture"):
		_run_mouse_capture_tests()
	if _on("connect"):
		await _run_connect_tests()
	if _on("version"):
		_run_version_tests()
	if _on("settings"):
		await _run_settings_tests()
	if _on("music"):
		await _run_music_tests()
	if _on("looks"):
		await _run_look_tests()
	if _on("fishing_world"):
		await _run_fishing_world_tests()
	if _on("genres"):
		await _run_genre_tests()
	if _on("match"):
		await _run_match_tests()
	if _on("lobby"):
		await _run_lobby_tests()
	if _on("levels"):
		await _run_level_build_tests()
	if _on("camera"):
		_run_camera_tests()
	if _on("aim"):
		await _run_aim_tests()
	if _on("animation"):
		_run_animation_tests()
	if _on("character"):
		_run_character_tests()
	if _on("pose"):
		await _run_pose_tests()
	if _on("animation_scene"):
		await _run_animation_scene_tests()
	if _on("remote_animation"):
		await _run_remote_animation_tests()
	if _on("greybox"):
		await _run_greybox_tests()
	if _on("lakeside"):
		await _run_lakeside_tests()
	if _on("kits"):
		_run_kit_tests()
	if _on("fishing_fx"):
		await _run_fishing_fx_tests()
		await _run_hud_layout_tests()
	if _on("grip"):
		await _run_rod_grip_tests()
	if _on("equip"):
		_run_equip_tests()
	if _on("arms"):
		await _run_arm_clip_tests()
	print("\n%d passed, %d failed" % [_passes, _failures])
	# Let queued frees actually run before exiting, so the engine's exit-time leak report
	# reflects real leaks rather than nodes that simply had not been collected yet. The
	# harness fails on unexpected engine errors, and that report is one of them.
	await get_tree().process_frame
	await get_tree().process_frame
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


# --- helpers -------------------------------------------------------------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


# --- golden vectors --------------------------------------------------------------

func _run_golden_vectors() -> void:
	print("== golden vectors ==")
	var dir: DirAccess = DirAccess.open(GOLDEN_DIR)
	if dir == null:
		_check(false, "cannot open " + GOLDEN_DIR)
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			_run_golden_file(GOLDEN_DIR + file)


func _run_golden_file(path: String) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		_check(false, "bad JSON: " + path)
		return
	var cfg: MovementConfig = MovementConfig.from_dict(doc["config"])
	var dt: float = float(doc["dt"])
	var tol: float = float(doc.get("tolerance", 1e-5))
	# Files regenerated since the model started classifying movement (PHASE4_SPEC §2.5) assert
	# move_state too. Neither harness used to compare it, so a wrong one could never fail.
	var check_ms: bool = bool(doc.get("asserts_move_state", false))
	print("  %s (model=%s, %d cases)" % [doc["name"], doc["model_version"], doc["cases"].size()])

	for c: Dictionary in doc["cases"]:
		var s: MovementState = MovementState.from_dict(c["initial"])
		var expected_at: Dictionary = c.get("expected_at", {})
		var worst: float = 0.0
		var inputs: Array = c["inputs"]
		for i in inputs.size():
			s = MovementModel.simulate(s, InputFrame.from_dict(inputs[i]), cfg, dt)
			var key: String = str(i)
			if expected_at.has(key):
				var exp_i: MovementState = MovementState.from_dict(expected_at[key])
				worst = maxf(worst, s.max_error(exp_i))
				_check(s.approx_equals(exp_i, tol), "%s @frame %d: got %s expected %s" % [c["name"], i, s, exp_i])
				if check_ms:
					_check(s.move_state == exp_i.move_state, "%s @frame %d: move_state %d, expected %d"
						% [c["name"], i, s.move_state, exp_i.move_state])
		var exp: MovementState = MovementState.from_dict(c["expected_final"])
		worst = maxf(worst, s.max_error(exp))
		var ok: bool = s.approx_equals(exp, tol) and (not check_ms or s.move_state == exp.move_state)
		_check(ok, "%s final: got %s (move_state %d) expected %s (move_state %d)"
			% [c["name"], s, s.move_state, exp, exp.move_state])
		print("    %-28s %s  max_err=%s" % [c["name"], "ok " if ok else "BAD", _sci(worst)])


# --- RowEvent -----------------------------------------------------------------------

## AuthoritySync with its flushes counted, so the server-tick cadence can be driven by hand
## rather than measured against however fast this machine happens to run.
class CountingSync extends AuthoritySync:
	var calls: int = 0

	func flush() -> Array[Dictionary]:
		calls += 1
		return super()


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


class FakeRow extends RefCounted:
	var entity_id: int
	var current: float
	## health_state also needs these; defaults keep the older RowEvent tests unchanged.
	var max: float = 100.0
	var is_dead: bool = false
	var last_damage_source: int = 0
	func _init(eid: int, cur: float) -> void:
		entity_id = eid
		current = cur

class FakeGlobalRow extends RefCounted:
	var sim_authority: int = 0

func _run_row_event_tests() -> void:
	print("== RowEvent ==")
	var ev: RowEvent = RowEvent.make(RowEvent.Kind.UPDATED, &"health_state", FakeRow.new(7, 90.0), FakeRow.new(7, 80.0))
	_check(ev.entity_id == 7, "entity_id extracted from row")
	_check(ev.current() == ev.new, "current() is new for UPDATED")
	var del: RowEvent = RowEvent.make(RowEvent.Kind.DELETED, &"health_state", FakeRow.new(3, 0.0), null)
	_check(del.entity_id == 3 and del.current() == del.old, "DELETED uses old row")
	var glob: RowEvent = RowEvent.make(RowEvent.Kind.INSERTED, &"world_config", null, FakeGlobalRow.new())
	_check(glob.entity_id == -1, "non-entity table yields entity_id -1")


# --- EntityRegistry buffering ---------------------------------------------------------

class FakeEntity extends Node:
	var received: Array[RowEvent] = []
	func receive_row_event(ev: RowEvent) -> void:
		received.append(ev)

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
	for game_path: String in ["res://foundation/boot.tscn", "res://game/fishing/lakeside_game.tscn",
			"res://game/fishing/fishing_game.tscn", "res://tests/levels/greybox_demo.tscn"]:
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
	_check(qs.has("SELECT * FROM entity WHERE world_id = 3"),
		"a per-world table is filtered to the world we are in")
	_check(qs.has("SELECT * FROM item_def"),
		"a static catalogue is not: every world shares one")
	_check(qs.has("SELECT * FROM input_queue WHERE world_id = 3"),
		"and a table the sidecar adds goes through the same rule")
	_check(qs.size() == cfg.core_tables.size() + 1,
		"one query per table, %d for %d" % [qs.size(), cfg.core_tables.size() + 1])
	_check(im.build_queries(0).has("SELECT * FROM entity WHERE world_id = 0"),
		"and world 0 is spelled out rather than left unfiltered")
	var dupe: Array[StringName] = [&"entity"]
	im.extra_tables = dupe
	_check(im.build_queries(0).size() == cfg.core_tables.size(),
		"an extra table already in the core set is not asked for twice")
	var none: Array[StringName] = []
	im.extra_tables = none

	# EVERY TABLE THE SHIPPED GAME SUBSCRIBES TO HAS BEEN DECIDED, one way or the other. Adding a
	# table to the config and forgetting this file is silent both ways: an unfiltered `entity`
	# subscribes the client to every world at once, and a filtered table with no `world_id` column
	# is a subscription the server refuses.
	# A GAME'S per-world tables are decided in its own NetConfig (`world_tables`), never by editing
	# the foundation's list (DECISIONS #154): fishing's line in the water belongs to one world.
	var expect_filtered: Array[StringName] = [&"entity", &"movement_state", &"health_state",
		&"session", &"action_event", &"equip_state", &"appearance", &"lobby_member", &"world_level", &"session_match", &"fishing_line",
		&"fishing_conditions", &"fight_show"]
	var expect_whole: Array[StringName] = [&"world_config", &"player", &"session_member",
		&"item_def", &"inventory_item", &"challenge", &"ability_def", &"ability_state",
		&"catch", &"gear", &"fishing_spot"]
	var shipped: NetConfig = (load(FISHING_NET_CONFIG) as NetConfig).duplicate() as NetConfig
	_check(shipped != null, "the fishing NetConfig loads")
	Genres.merge_tables(shipped, Genres.modules())   # and the genres' tables, as Boot adds them
	var undecided: Array[StringName] = []
	if shipped != null:
		for t: StringName in shipped.core_tables:
			if not expect_filtered.has(t) and not expect_whole.has(t):
				undecided.append(t)
	_check(undecided.is_empty(),
		"no table is subscribed without deciding whether it is per-world (%s)" % str(undecided))
	var wrong: Array[String] = []
	for t: StringName in expect_filtered:
		if not im.query_for(t, 5, shipped).ends_with("WHERE world_id = 5"):
			wrong.append("%s should be filtered" % t)
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


static func _input_ev(row: FakeInputRow) -> RowEvent:
	return RowEvent.make(RowEvent.Kind.INSERTED, &"input_queue", null, row)


## One input frame, the way a client would have produced it.
static func _frame(seq: int, dir: Vector2, jump: bool = false) -> InputFrame:
	var f := InputFrame.new()
	f.seq = seq
	f.move_dir = dir
	f.jump = jump
	return f


## SERVER_AUTHORITY: THIS PROCESS IS THE SERVER (PHASE3_SPEC Task 13, SIDECAR_SPEC §3).
##
## The sidecar does not trust a client's claimed position; it replays the client's own input
## frames through the same model and the same collision resolver and writes what it gets. The
## property that has to hold is therefore agreement: given identical frames from identical
## starting state, the authority must land where the client predicted it would, or every player
## in a sidecar world is corrected constantly.
func _run_authority_tests() -> void:
	print("== SERVER_AUTHORITY: the sidecar's movement mode ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var sync: Node = _autoload("SpaceTimeSync")
	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.display_name = "Player"
	defn.scene = load(PLAYER_SCENE) as PackedScene
	if reg == null or spawner == null or sync == null or packed == null or defn.scene == null:
		_check(false, "autoloads, level and player scene present")
		return

	# Become an authority process exactly as the sidecar does: through its NetConfig.
	var prev_config: NetConfig = sync.config
	var cfg := NetConfig.new()
	cfg.authority_process = true
	sync.config = cfg
	_check(SpaceTimeMovementComponent.is_authority_process(),
		"the process reports itself an authority once its NetConfig says so")

	# THE WIRE SPELLING. `sim.rs` has move_x/move_y; this class calls the pair `move_dir`. Reading
	# the wrong one off a real row gives (0, 0) — the entity is simulated perfectly and stands
	# still, with nothing logged anywhere.
	var wire_row := FakeInputRow.new(1, _frame(5, Vector2(0.25, -0.5), true))
	var decoded: InputFrame = InputFrame.from_row(wire_row.frame)
	_check(decoded.move_dir.is_equal_approx(Vector2(0.25, -0.5)) and decoded.seq == 5
			and decoded.jump,
		"a queued frame survives the wire's move_x/move_y spelling (%s, seq %d, jump %s)"
			% [decoded.move_dir, decoded.seq, decoded.jump])

	var level: Node3D = packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	var world_root: Node3D = level.get_node(^"WorldRoot") as Node3D
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true
	var eid: int = 7701
	# NOT ours: a sidecar owns every entity in its world, including ones a player is driving.
	reg.local_entity_id = 0
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var ent: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	var mv: SpaceTimeMovementComponent = ent.find_component(
		SpaceTimeMovementComponent) as SpaceTimeMovementComponent if ent != null else null
	_check(mv != null, "the entity spawned with a movement component")
	if mv == null:
		sync.config = prev_config
		reg.local_entity_id = prev_local
		spawner._world_ready = prev_ready
		level.queue_free()
		return
	_check(mv.mode == SpaceTimeMovementComponent.Mode.SERVER_AUTHORITY,
		"an entity we do NOT own still binds in SERVER_AUTHORITY here (mode %d)" % mv.mode)
	_check(mv.required_tables().has(&"input_queue")
			and mv.optional_tables().has(&"input_queue"),
		"the component asks for the input queue, and does not stall waiting for one")
	# Its own input component must not also be sampling: in the sidecar there is no keyboard.
	var li: LocalInputComponent = ent.find_component(LocalInputComponent) as LocalInputComponent
	if li != null:
		li.set_physics_process(false)

	# --- it replays what the client sent ---------------------------------------------------
	var start := FakeMoveRow.new(eid, Vector3(0.0, 0.0, 0.0), 1_000)
	start.teleport_flag = true
	mv.receive_row_event(_move_ev(start))
	_check(mv.get_authority_state() != null
			and mv.get_authority_state().pos.is_equal_approx(Vector3.ZERO),
		"it starts from where the database says the entity is")
	_check(mv.take_authority_write().is_empty(),
		"an entity standing still owes the database nothing")

	var seq: int = 0
	for i: int in range(30):
		seq += 1
		mv.receive_row_event(_input_ev(FakeInputRow.new(eid, _frame(seq, Vector2(0.0, -1.0)))))
		await get_tree().physics_frame
	var ran: MovementState = mv.get_authority_state()
	print("   after %d frames of forward input: pos %s, seq %d" % [seq, ran.pos, mv.authority_seq()])
	_check(ran.pos.z < -1.0, "replaying the client's frames moves the entity (%s)" % ran.pos)
	var write: Dictionary = mv.take_authority_write()
	_check(not write.is_empty() and int(write["last_processed_seq"]) == seq,
		"the write reports the last seq it consumed (%s, wanted %d)"
			% [str(write.get("last_processed_seq", "-")), seq])
	_check(write.has("pos") and write.has("vel") and write.has("yaw") and write.has("grounded")
			and write.has("move_state") and write.has("teleport_flag") and write.has("entity_id"),
		"and carries every field MovementWrite declares (%s)" % str(write.keys()))
	_check(mv.take_authority_write().is_empty(),
		"taking a write clears it: the same state is not sent twice")

	# --- THE AGREEMENT. Same frames, same start, client prediction vs authority ------------
	# If these two drift, every player in a sidecar world is corrected constantly. They run the
	# same MovementModel against the same move_and_slide resolver, so they must not.
	var mirror_eid: int = 7702
	reg.local_entity_id = mirror_eid
	sync.config = prev_config   # a PLAYER's process: the mirror binds LOCAL_PREDICTED
	_buffer_player_rows(reg, mirror_eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(mirror_eid, 0)))
	var mirror_ent: SpaceTimeEntity = spawner.get_entity_node(mirror_eid) as SpaceTimeEntity
	var mirror: SpaceTimeMovementComponent = mirror_ent.find_component(
		SpaceTimeMovementComponent) as SpaceTimeMovementComponent if mirror_ent != null else null
	var mirror_input: LocalInputComponent = mirror_ent.find_component(
		LocalInputComponent) as LocalInputComponent if mirror_ent != null else null
	if mirror_input != null:
		mirror_input.set_physics_process(false)
	_check(mirror != null and mirror.mode == SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED,
		"the mirror entity binds as a predicting client")
	if mirror != null:
		sync.config = cfg
		var auth_eid: int = 7703
		reg.local_entity_id = 0
		_buffer_player_rows(reg, auth_eid)
		spawner._on_entity_inserted(RowEvent.make(
			RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(auth_eid, 0)))
		var twin_ent: SpaceTimeEntity = spawner.get_entity_node(auth_eid) as SpaceTimeEntity
		var twin: SpaceTimeMovementComponent = twin_ent.find_component(
			SpaceTimeMovementComponent) as SpaceTimeMovementComponent if twin_ent != null else null
		var twin_input: LocalInputComponent = twin_ent.find_component(
			LocalInputComponent) as LocalInputComponent if twin_ent != null else null
		if twin_input != null:
			twin_input.set_physics_process(false)
		var here := Vector3(-5.0, 0.0, -5.0)
		var mseq: Array[int] = [0]
		await _place_predicted(mirror, here, mseq, 8)
		var b := FakeMoveRow.new(auth_eid, here, 2_000)
		b.teleport_flag = true
		twin.receive_row_event(_move_ev(b))
		await get_tree().physics_frame
		_check(mirror.get_predicted_state().pos.distance_to(here) < 0.2
				and twin.get_authority_state().pos.distance_to(here) < 0.2,
			"both start from the same place (%s vs %s)"
				% [mirror.get_predicted_state().pos, twin.get_authority_state().pos])
		var dirs: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0),
			Vector2(-1.0, -1.0).normalized(), Vector2.ZERO]
		var n: int = mseq[0]
		for d: Vector2 in dirs:
			for i: int in range(12):
				n += 1
				await get_tree().physics_frame
				# The SAME frame object shape to both: one predicts with it, one replays it.
				var jump_now: bool = n == mseq[0] + 7
				mirror.push_input(_frame(n, d, jump_now))
				twin.receive_row_event(_input_ev(FakeInputRow.new(auth_eid, _frame(n, d, jump_now))))
		await get_tree().physics_frame
		await get_tree().physics_frame
		var pred: Vector3 = mirror.get_predicted_state().pos
		var auth: Vector3 = twin.get_authority_state().pos
		print("   client predicted %s, the authority simulated %s (%.4f m apart)"
			% [pred, auth, pred.distance_to(auth)])
		_check(pred.distance_to(auth) < 0.01,
			"the authority lands where the client predicted, to the centimetre (%.4f m)"
				% pred.distance_to(auth))
		# AuthoritySync writes for what we SIMULATE. The predicting entity beside it is a client's
		# own; writing its state back would be this process overruling a player it does not own.
		var probe := AuthoritySync.new()
		probe.send = false
		var collected: Array[int] = []
		for c: SpaceTimeMovementComponent in probe.authorities():
			collected.append(c.entity_id)
		_check(collected.has(auth_eid) and not collected.has(mirror_eid),
			"AuthoritySync collects the entities we simulate and skips the predicting one (%s)"
				% str(collected))
		probe.free()
		_teardown_entity(spawner, mirror_eid)
		_teardown_entity(spawner, auth_eid)

	# --- the wall ---------------------------------------------------------------------------
	# The accept criterion: an authority resolves collision against the real level, so a client
	# that holds a direction into a wall is stopped by the server, not by its own good manners.
	sync.config = cfg
	var wall_start := FakeMoveRow.new(eid, Vector3(4.0, 0.0, -5.0), 3_000)
	wall_start.teleport_flag = true
	mv.receive_row_event(_move_ev(wall_start))
	await get_tree().physics_frame
	for i: int in range(240):
		seq += 1
		mv.receive_row_event(_input_ev(FakeInputRow.new(eid, _frame(seq, Vector2(1.0, 0.0)))))
		await get_tree().physics_frame
	var stopped: Vector3 = mv.get_authority_state().pos
	print("   ran east into the wall for 240 frames, ended at x %.2f" % stopped.x)
	_check(stopped.x > 6.5, "it actually travelled (x %.2f)" % stopped.x)
	_check(stopped.x < 10.0,
		"and the wall stopped it: the authority resolves against the real level (x %.2f)"
			% stopped.x)

	# --- gravity without input ---------------------------------------------------------------
	var air := FakeMoveRow.new(eid, Vector3(0.0, 5.0, 0.0), 4_000)
	air.teleport_flag = true
	air.grounded = false
	mv.receive_row_event(_move_ev(air))
	await get_tree().physics_frame
	var high: float = mv.get_authority_state().pos.y
	for i: int in range(30):
		await get_tree().physics_frame
	_check(mv.get_authority_state().pos.y < high - 0.2,
		"an entity nobody is driving still falls: gravity does not wait for input (%.2f -> %.2f)"
			% [high, mv.get_authority_state().pos.y])
	for i: int in range(200):
		await get_tree().physics_frame
	var landed: MovementState = mv.get_authority_state()
	_check(landed.grounded, "and it lands (y %.2f, grounded %s)" % [landed.pos.y, landed.grounded])
	mv.take_authority_write()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(mv.take_authority_write().is_empty(),
		"once it is still, it stops writing: an idle world costs no reducer calls")

	# A ROW MAY LIE ABOUT BEING GROUNDED. `spawn_npc` writes `grounded: true` at whatever height
	# it is handed, so an entity trusted to be asleep on that claim hangs in the air forever — and
	# nothing reports it, because an asleep entity is exactly what an idle world looks like.
	var liar := FakeMoveRow.new(eid, Vector3(2.0, 6.0, -6.0), 4_500)
	liar.teleport_flag = true
	liar.grounded = true          # the lie
	mv.receive_row_event(_move_ev(liar))
	await get_tree().physics_frame
	for i: int in range(240):
		await get_tree().physics_frame
	var fell_to: MovementState = mv.get_authority_state()
	_check(fell_to.pos.y < 1.0,
		"an entity spawned in the air but flagged grounded still falls (y %.2f)" % fell_to.pos.y)
	mv.take_authority_write()

	# --- the catch-up clamp -------------------------------------------------------------------
	# A client that stalled and reconnected arrives with a backlog. Replaying all of it in one
	# tick would fling it across the level; replaying it slowly would take a minute.
	var before_catchup: int = mv.authority_seq()
	for i: int in range(40):
		seq += 1
		mv.receive_row_event(_input_ev(FakeInputRow.new(eid, _frame(seq, Vector2(0.0, -1.0)))))
	_check(mv.authority_backlog() == 40, "40 frames are queued (%d)" % mv.authority_backlog())
	await get_tree().physics_frame
	var consumed: int = mv.authority_seq() - before_catchup
	print("   backlog of 40: %d frames folded in on the first tick, %d still queued"
		% [consumed, mv.authority_backlog()])
	_check(mv.authority_backlog() == 0,
		"the backlog is not replayed frame by frame over the next second (%d left)"
			% mv.authority_backlog())
	var catchup_write: Dictionary = mv.take_authority_write()
	_check(not catchup_write.is_empty() and bool(catchup_write["teleport_flag"]),
		"and the client is TOLD it was moved rather than being silently desynced")
	_check(int(catchup_write["last_processed_seq"]) == seq,
		"the write acknowledges the whole backlog (%s of %d), so it is not replayed again"
			% [str(catchup_write.get("last_processed_seq", "-")), seq])

	# --- someone else moves it ----------------------------------------------------------------
	# We are authoritative over MOTION, not over where the game decides the entity belongs: an
	# admin teleport or a session move has to win, or the sidecar would drag it straight back.
	var elsewhere := FakeMoveRow.new(eid, Vector3(-7.0, 0.0, -7.0), 5_000)
	elsewhere.teleport_flag = true
	elsewhere.last_processed_seq = seq
	mv.receive_row_event(_move_ev(elsewhere))
	await get_tree().physics_frame
	_check(mv.get_authority_state().pos.distance_to(Vector3(-7.0, 0.0, -7.0)) < 0.6,
		"a teleport from another authority wins (%s)" % mv.get_authority_state().pos)

	# --- AuthoritySync: one reducer call per world per tick ----------------------------------
	var asy := CountingSync.new()
	asy.world_id = 0
	asy.tick_hz = 20.0
	asy.send = false   # no server here; flush() still gathers exactly what would be sent
	for i: int in range(10):
		seq += 1
		mv.receive_row_event(_input_ev(FakeInputRow.new(eid, _frame(seq, Vector2(0.0, -1.0)))))
		await get_tree().physics_frame
	var batch: Array[Dictionary] = asy.flush()
	_check(batch.size() == 1, "a moving entity is in the batch (%d writes)" % batch.size())
	_check(not batch.is_empty() and int(batch[0]["last_processed_seq"]) == seq,
		"the batch acknowledges the last frame consumed (%s of %d)"
			% [str(batch[0]["last_processed_seq"]) if not batch.is_empty() else "-", seq])
	_check(asy.flush().is_empty(),
		"flushing again sends nothing: a world where nobody moved costs no reducer calls")

	# A REFUSED WRITE IS NOT A WRITE. The entity has stopped moving, so it will never become
	# dirty on its own again — without this the database keeps the stale row forever, which is
	# exactly what a sidecar that starts before it is registered as an authority looks like.
	var refused := ReducerRequest.new()
	refused.reducer_name = &"write_movement_batch"
	var owed: Array[int] = [eid]
	asy._on_batch_settled(refused, owed)   # still PENDING, i.e. not OK
	_check(refused.outcome != ReducerRequest.Outcome.OK, "(the probe request is not an OK one)")
	var retried: Array[Dictionary] = asy.flush()
	_check(retried.size() == 1 and int(retried[0]["entity_id"]) == eid,
		"a refused batch is owed again on the next tick rather than lost (%d writes)"
			% retried.size())
	_check(asy.writes_refused == 1, "and it is counted (%d)" % asy.writes_refused)

	# The cadence, stepped by hand: a test that waited on the wall clock would measure the
	# machine rather than the code.
	asy.calls = 0
	for i: int in range(60):
		asy._physics_process(1.0 / 60.0)
	_check(absi(asy.calls - 20) <= 1,
		"one second of physics frames produces one batch per server tick (%d of 20)" % asy.calls)
	asy.tick_hz = 20.0
	asy.calls = 0
	asy._physics_process(3.0)   # a long stall: one catch-up tick, not sixty
	asy._physics_process(1.0 / 60.0)
	_check(asy.calls <= 2,
		"and a stalled frame does not fire a burst of catch-up ticks afterwards (%d)" % asy.calls)
	asy.free()

	_teardown_entity(spawner, eid)
	sync.config = prev_config
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame


## Despawn one entity through the spawner's own teardown path.
func _teardown_entity(spawner: Node, eid: int) -> void:
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()


## NPC BRAINS (PHASE3_SPEC Task 14, SIDECAR_SPEC §3).
##
## A brain answers "which way would this character push the stick", and the ORDINARY movement
## path turns that into motion. The tests are in two halves for that reason: the brains alone,
## given a world made up on the spot, and then a real NPC in the real level whose position is
## only allowed to change because the same model that moves players moved it.
## Mirrors `npc_brain`.
class FakeBrainRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var brain: String
	var state: String
	var target_id: int = 0
	var data: String
	func _init(eid: int, b: StringName, st: StringName, d: String) -> void:
		entity_id = eid
		brain = String(b)
		state = String(st)
		data = d


func _run_npc_tests() -> void:
	print("== NPC brains ==")

	# --- (a) the brains, given a world to look at -----------------------------------------
	NpcWorldView.invalidate()
	var view := NpcWorldView.new()
	var npc_state := MovementState.new()
	npc_state.pos = Vector3.ZERO
	var player_state := MovementState.new()
	player_state.pos = Vector3(5.0, 0.0, 0.0)
	var far_state := MovementState.new()
	far_state.pos = Vector3(60.0, 0.0, 0.0)
	view.states = {10: npc_state, 11: player_state, 12: far_state}
	view.kinds = {10: 1, 11: 0, 12: 0}

	_check(view.nearest_of_kind(Vector3.ZERO, 0, 18.0, 10) == 11,
		"the world view finds the nearest player and ignores the distant one (%d)"
			% view.nearest_of_kind(Vector3.ZERO, 0, 18.0, 10))
	_check(view.nearest_of_kind(Vector3.ZERO, 0, 2.0, 10) == 0,
		"and finds nobody when nobody is in range")
	_check(view.nearest_of_kind(Vector3.ZERO, 99, 50.0, 10) == 0,
		"a kind nothing has matches nothing")

	var chase := ChaseBrain.new(1)
	chase.self_id = 10
	chase.think(npc_state, view)
	_check(chase.target_id == 11 and chase.state == &"chase",
		"the chase brain locks onto the player it can see (target %d, %s)"
			% [chase.target_id, chase.state])
	var cf: InputFrame = chase.frame(npc_state)
	_check(cf.move_dir.x > 0.9 and absf(cf.move_dir.y) < 0.1,
		"and pushes the stick towards it in WORLD space (%s)" % cf.move_dir)
	_check(not cf.slow, "chasing runs rather than ambles")
	# WORLD SPACE, not the character's own. `move_dir` is already a world direction by the time it
	# reaches the model (DECISIONS #100), and at yaw 0 a body-relative bug is invisible — which is
	# exactly how the gait version of this mistake survived a whole suite. Ask it at an angle.
	npc_state.yaw = PI * 0.5
	chase.target_id = 0
	chase.think(npc_state, view)
	var turned: InputFrame = chase.frame(npc_state)
	_check(turned.move_dir.x > 0.9 and absf(turned.move_dir.y) < 0.1,
		"an NPC facing 90 degrees away still pushes towards the player in WORLD space (%s)"
			% turned.move_dir)
	npc_state.yaw = 0.0
	# It must hold on past sight range rather than dropping the target at the boundary and
	# re-acquiring it a tick later, which reads as stuttering on the spot.
	player_state.pos = Vector3(20.0, 0.0, 0.0)
	chase.think(npc_state, view)
	_check(chase.target_id == 11,
		"it keeps a target that stepped just outside sight range (%d)" % chase.target_id)
	player_state.pos = Vector3(40.0, 0.0, 0.0)
	chase.think(npc_state, view)
	_check(chase.target_id == 0 and chase.state == &"idle",
		"and gives up once it is really gone (%d, %s)" % [chase.target_id, chase.state])
	var idle_frame: InputFrame = chase.frame(npc_state)
	_check(idle_frame != null, "a brain with no target still produces a frame, never null")

	var wander := WanderBrain.new(7)
	wander.home = Vector3.ZERO
	wander.think(npc_state, view)
	_check(wander.has_goal(), "the wander brain picks somewhere to go")
	_check(wander.goal().distance_to(Vector3.ZERO) <= wander.roam_radius + 0.01,
		"inside its roam radius (%.2f of %.2f)"
			% [wander.goal().distance_to(Vector3.ZERO), wander.roam_radius])
	_check(wander.frame(npc_state).slow, "and ambles rather than sprinting everywhere")
	# Two NPCs spawned in the same tick must not walk in lockstep.
	var other := WanderBrain.new(8)
	other.home = Vector3.ZERO
	other.think(npc_state, view)
	_check(not wander.goal().is_equal_approx(other.goal()),
		"two NPCs pick different places (%s vs %s)" % [wander.goal(), other.goal()])
	# Walking into a wall has to end the walk, or it leans there for the whole session.
	var stuck := MovementState.new()
	stuck.pos = Vector3.ZERO
	stuck.vel = Vector3.ZERO
	for i: int in range(12):
		wander.think(stuck, view)
	_check(not wander.has_goal() or wander.state == &"rest",
		"a wander that stops making progress gives up rather than leaning on the wall (%s)"
			% wander.state)

	# --- (a2) WHAT A RESTART NEEDS -------------------------------------------------------------
	# Through JSON both ways, because that is the column it lives in (`npc_brain.data`).
	var roamer := WanderBrain.new(3)
	roamer.home = Vector3(3.5, 0.0, -2.25)
	roamer.set_goal(Vector3(6.0, 0.0, 1.0))
	var saved: String = JSON.stringify(roamer.save_state())
	var resumed := WanderBrain.new(99)
	resumed.home = Vector3(-40.0, 0.0, 40.0)   # where a restarted sidecar found it standing
	resumed.load_state(JSON.parse_string(saved) as Dictionary)
	_check(resumed.home.is_equal_approx(roamer.home),
		"a wander brain's HOME survives the round trip (%s), not where it happened to be standing"
			% resumed.home)
	_check(resumed.has_goal() and resumed.goal().is_equal_approx(roamer.goal()),
		"and so does where it was going (%s)" % resumed.goal())
	_check(not saved.contains("rest_left"),
		"the rest countdown is not persisted: it changes every think and decides nothing")
	var older := WanderBrain.new(5)
	older.home = Vector3(1.0, 0.0, 1.0)
	older.load_state({"has_goal": false})
	_check(older.home == Vector3(1.0, 0.0, 1.0),
		"a row from an older brain that lacks a field keeps the default, not an error")

	var hunter := ChaseBrain.new(4)
	hunter.target_id = 11
	hunter._idle.home = Vector3(2.0, 0.0, 2.0)
	var hunted := ChaseBrain.new(4)
	hunted.load_state(JSON.parse_string(JSON.stringify(hunter.save_state())) as Dictionary)
	_check(hunted.target_id == 11 and hunted.target() == 11,
		"a chase brain resumes after the same target (%d)" % hunted.target_id)
	_check(hunted._idle.home.is_equal_approx(Vector3(2.0, 0.0, 2.0)),
		"and roams the same patch when it loses them (%s)" % hunted._idle.home)

	# --- (b) A REAL NPC IN THE REAL LEVEL --------------------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var sync: Node = _autoload("SpaceTimeSync")
	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	var prev_config: NetConfig = sync.config
	var cfg := NetConfig.new()
	cfg.authority_process = true
	sync.config = cfg
	var level: Node3D = packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	var defn := EntityDefinition.new()
	defn.kind = 1
	defn.display_name = "Wildlife"
	defn.scene = load(PLAYER_SCENE) as PackedScene
	defn.brain = &"wander"
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 0
	var npc_id: int = 7801
	_buffer_player_rows(reg, npc_id)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(npc_id, 1)))
	var npc: SpaceTimeEntity = spawner.get_entity_node(npc_id) as SpaceTimeEntity
	_check(npc != null and npc.definition != null and npc.definition.brain == &"wander",
		"the NPC spawned and its definition names a brain")
	if npc != null:
		var li: LocalInputComponent = npc.find_component(LocalInputComponent) as LocalInputComponent
		if li != null:
			li.set_physics_process(false)
		var mv: SpaceTimeMovementComponent = npc.find_component(
			SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		var start := FakeMoveRow.new(npc_id, Vector3(-5.0, 0.0, -2.0), 1_000)
		start.teleport_flag = true
		mv.receive_row_event(_move_ev(start))
		await get_tree().physics_frame

		# The sidecar attaches the brain, because the scene is not allowed to name it.
		var brain_c := NpcBrainComponent.new()
		brain_c.name = "NpcBrain"
		brain_c.brain_name = npc.definition.brain
		npc.add_runtime_component(brain_c)
		_check(npc.find_component(NpcBrainComponent) != null,
			"a component attached after the bind is found like any other")
		_check(brain_c.brain != null and brain_c.brain is WanderBrain,
			"and it resolved the brain its definition named")

		var from: Vector3 = mv.get_authority_state().pos
		var moved: float = 0.0
		for i: int in range(420):
			await get_tree().physics_frame
			moved = maxf(moved, from.distance_to(mv.get_authority_state().pos))
		var here: Vector3 = mv.get_authority_state().pos
		print("   the NPC wandered %.2f m from where it started, now at %s" % [moved, here])
		_check(moved > 1.0,
			"IT WALKS: nobody sent it any input and it moved anyway (%.2f m)" % moved)
		_check(absf(here.y) < 0.5,
			"on the floor rather than through it: the brain goes through the real movement path "
				+ "(y %.2f)" % here.y)
		_check(mv.authority_seq() > 0,
			"and its frames are numbered like a player's, so writes acknowledge them (%d)"
				% mv.authority_seq())
		var owed: Dictionary = mv.take_authority_write()
		_check(not owed.is_empty() and int(owed["last_processed_seq"]) == mv.authority_seq(),
			"an NPC owes the database writes exactly as a player does")

		# PERSISTENCE, WITH NOBODY TO PERSIST TO. There is no server here, so every write comes
		# back refused — which is the case that matters: a refused write must stay OWED (the
		# brain keeps trying) and must not be tried more than once a second.
		var refused: Array[int] = [0]
		brain_c.persisted.connect(func(ok: bool) -> void:
			if not ok:
				refused[0] += 1)
		var watch_from: int = Time.get_ticks_msec()
		for i: int in range(200):
			await get_tree().physics_frame
		var watched_s: float = (Time.get_ticks_msec() - watch_from) / 1000.0
		_check(refused[0] >= 1, "the brain tries to persist what it decided (%d attempts)" % refused[0])
		_check(refused[0] <= int(ceilf(watched_s / NpcBrainComponent.PERSIST_MIN_SEC)) + 1,
			"no more than once a second (%d in %.1f s)" % [refused[0], watched_s])
		_check(brain_c._persisted_key.is_empty() and not brain_c._persist_in_flight,
			"and a refused write is owed again, never counted as written")

		# RESUMING. A row written by a previous run is read back into the brain...
		var wb: WanderBrain = brain_c.brain as WanderBrain
		var row := FakeBrainRow.new(npc_id, &"wander", &"rest",
			JSON.stringify({"home": [3.0, 0.0, 4.0], "has_goal": false}))
		brain_c._restore(row)
		_check(wb.home.is_equal_approx(Vector3(3.0, 0.0, 4.0)) and wb.state == &"rest",
			"a previous run's row is resumed: home %s, state %s" % [wb.home, wb.state])
		_check(brain_c._persisted_key == brain_c._key(),
			"and counted as already written, so resuming does not rewrite the same row")
		# ...but not a row some OTHER brain wrote: its data means something else.
		var foreign := FakeBrainRow.new(npc_id, &"chase", &"chase",
			JSON.stringify({"home": [50.0, 0.0, 50.0]}))
		brain_c._restore(foreign)
		_check(wb.home.is_equal_approx(Vector3(3.0, 0.0, 4.0)),
			"a row another brain wrote is ignored rather than misread (%s)" % wb.home)
		_teardown_entity(spawner, npc_id)

	NpcWorldView.invalidate()
	sync.config = prev_config
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame


## GEAR AND THE SHOP (GENRE_ADAPTERS §1). The server owns the prices, the phase gate and what
## each tier does; this is the client's half — reading the row, and never inventing a tier. Every
## number comes from `shared/fishing/fishing.json`, the file the module charges from, so this
## asks THAT file rather than restating it: a retune must not fail a test that was right.
func _run_gear_tests() -> void:
	print("== gear ==")
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 91
	get_tree().root.add_child(owner_entity)
	var gear := GearComponent.new()
	owner_entity.add_child(gear)
	var no_rows: Dictionary[StringName, RefCounted] = {}
	gear.bind(owner_entity, no_rows)
	var cost := func(track: String, t: int) -> int: return int(FishingData.gear(track, t).get("cost", -2))

	# A NEW ANGLER HAS NO ROW. `gear` is a table an entity legitimately has none in, so it has to
	# be optional as well as required — otherwise every fisher sits out its whole bind timeout
	# before it appears (DECISIONS #69).
	_check(gear.required_tables().has(&"gear") and gear.optional_tables().has(&"gear"),
		"gear is required AND optional: no row is a legitimate state")
	_check(gear.rod_tier() == 0 and gear.reel_tier() == 0 and gear.line_tier() == 0,
		"with no row the angler is on the starting kit")
	_check(gear.next_cost(GearComponent.Kind.ROD) == cost.call("rod", 1) and cost.call("rod", 1) > 0,
		"and the first rod costs what the shared file says (%d)" % gear.next_cost(GearComponent.Kind.ROD))
	_check(gear.item_name(GearComponent.Kind.ROD) == str(FishingData.gear("rod", 0)["name"]),
		"the starting rod has its name from the file (%s)" % gear.item_name(GearComponent.Kind.ROD))

	var changed: Array[int] = []
	# Mutate, never reassign: a lambda captures a local by VALUE, so `changed = [...]` inside one
	# updates a copy and the assertion below would read an empty array however well the code works.
	gear.gear_changed.connect(func(r: int, e: int, l: int) -> void:
		changed.clear()
		changed.append_array([r, e, l]))
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"gear", null, FakeGearRow.new(91, 2, 1, 0)))
	_check(gear.rod_tier() == 2 and gear.reel_tier() == 1 and gear.line_tier() == 0,
		"the row is what the tiers are (%d/%d/%d)"
			% [gear.rod_tier(), gear.reel_tier(), gear.line_tier()])
	_check(changed == [2, 1, 0], "and it announces the change once, as (rod, reel, line) (%s)" % str(changed))
	_check(gear.next_cost(GearComponent.Kind.ROD) == cost.call("rod", 3),
		"prices climb with the tier: the third rod costs %d (%d)"
			% [cost.call("rod", 3), gear.next_cost(GearComponent.Kind.ROD)])
	_check(gear.next_cost(GearComponent.Kind.REEL) == cost.call("reel", 2)
			and gear.next_cost(GearComponent.Kind.LINE) == cost.call("line", 1),
		"and each piece is priced by ITS own tier, not the highest one (reel %d, line %d)"
			% [gear.next_cost(GearComponent.Kind.REEL), gear.next_cost(GearComponent.Kind.LINE)])
	_check(gear.next_name(GearComponent.Kind.REEL) == str(FishingData.gear("reel", 2)["name"]),
		"the shop can name what the next reel is (%s)" % gear.next_name(GearComponent.Kind.REEL))

	# The top tier is a wall, and the HUD has to be able to say so without guessing.
	var top: int = GearComponent.max_tier()
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.UPDATED, &"gear", null, FakeGearRow.new(91, top, 0, 0)))
	_check(gear.next_cost(GearComponent.Kind.ROD) == -1 and gear.next_name(GearComponent.Kind.ROD).is_empty(),
		"a maxed rod has no next price and no next name (%d)" % gear.next_cost(GearComponent.Kind.ROD))

	# A row going away is an angler back on the starting kit, not a stale display.
	gear.receive_row_event(RowEvent.make(
		RowEvent.Kind.DELETED, &"gear", FakeGearRow.new(91, top, 0, 0), null))
	_check(gear.rod_tier() == 0, "a deleted row drops back to the starting kit")

	# THE FILE ITSELF, as the shop needs it: every track has every tier, the kit you start with
	# is free, and each tier costs more than the last — a cheaper upgrade is a typo, not a sale.
	var bad: Array[String] = []
	for track: String in ["rod", "reel", "line"]:
		var tiers: Array = (FishingData.doc()["gear"] as Dictionary)[track] as Array
		if tiers.size() != top + 1:
			bad.append("%s has %d tiers" % [track, tiers.size()])
			continue
		if cost.call(track, 0) != 0:
			bad.append("%s tier 0 is not free" % track)
		for t: int in range(1, top + 1):
			if cost.call(track, t) <= cost.call(track, t - 1):
				bad.append("%s tier %d is not dearer than %d" % [track, t, t - 1])
			if str(FishingData.gear(track, t).get("name", "")).is_empty():
				bad.append("%s tier %d has no name" % [track, t])
	_check(bad.is_empty(), "every track has %d named tiers, the first free and each dearer (%s)" % [top + 1, str(bad)])
	# And each track does the thing it is sold for: reach, forgiveness, load. Flat numbers along a
	# track would be three names for one purchase (DECISIONS #118).
	_check(FishingData.max_cast_m(top) > FishingData.max_cast_m(0), "a better rod reaches further")
	_check(FishingData.hookset_window_mult(top) > FishingData.hookset_window_mult(0),
		"a better reel is more forgiving on the hook-set")
	_check(float(FishingData.gear("line", top)["max_load_kg"]) > float(FishingData.gear("line", 0)["max_load_kg"]),
		"a better line holds more weight")
	owner_entity.queue_free()


## Mirrors fishing's `catch` table.
class FakeCatchRow extends RefCounted:
	var id: int
	var owner_entity_id: int
	var session_id: int
	var catch_key: String
	var kg: float
	var quality: float = 0.75
	var hookset: int = 1
	var spot: String = "dock_end"
	var deadlift: bool = false
	var coins: int = 5
	var round: int
	var caught_at: int = 0
	var best_combo: int = 3
	var fight_s: float = 11.5
	var clean: bool = true
	func _init(cid: int, owner: int, sess: int, rnd: int, key: String, weight: float) -> void:
		id = cid
		owner_entity_id = owner
		session_id = sess
		round = rnd
		catch_key = key
		kg = weight


## Who won, and what is news. The scoreboard is assembled from components, so its rules are the
## components' rules: which catches belong to which round, which one is "best", and — the one a
## player notices — that a fish landed in a previous session is history, not a new catch.
func _run_standings_tests() -> void:
	print("== standings ==")
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 93
	get_tree().root.add_child(owner_entity)
	var fishing := FishingComponent.new()
	owner_entity.add_child(fishing)
	var announced: Array[String] = []
	fishing.catch_landed.connect(func(c: Dictionary) -> void: announced.append(str(c["key"])))

	# A REJOIN replays every catch this angler ever made. Before, the last one was re-announced:
	# a banner — and with feedback, a splash and a jingle — for a fish from a previous session.
	var initial: Dictionary[StringName, RefCounted] = {
		&"catch": FakeCatchRow.new(1, 93, 7, 2, "carp", 8.1)}
	fishing.bind(owner_entity, initial)
	_check(announced.is_empty(), "a catch that was already true on arrival is not announced")
	_check(fishing.catches_in(7, 2).size() == 1, "but it is on the record for the scoreboard")
	# Every catch the entity was sent arrives at bind, and none of them is news (DECISIONS #180).
	var historian := FakeOwnerEntity.new()
	historian.entity_id = 94
	get_tree().root.add_child(historian)
	var past := FishingComponent.new()
	historian.add_child(past)
	var told: Array[String] = []
	past.catch_landed.connect(func(c: Dictionary) -> void: told.append(str(c["key"])))
	var rows: Array = [FakeCatchRow.new(11, 94, 7, 1, "carp", 8.1), FakeCatchRow.new(12, 94, 7, 1, "bluegill", 0.3),
		FakeCatchRow.new(13, 94, 7, 2, "walleye", 3.0)]
	past.bind(historian, {&"catch": rows[2]}, {&"catch": rows})
	_check(past.all_catches().size() == 3 and told.is_empty(),
		"bind hands over every catch the entity was sent (%d), and announces none" % past.all_catches().size())
	historian.queue_free()

	var landed := FakeCatchRow.new(2, 93, 7, 3, "bluegill", 0.31)
	landed.hookset = 0
	landed.coins = 3
	landed.spot = "reed_bay"
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, landed))
	_check(announced == ["bluegill"], "a catch that ARRIVES is announced, once (%s)" % str(announced))
	var rec: Dictionary = fishing.catches_in(7, 3)[0] if fishing.catches_in(7, 3).size() > 0 else {}
	_check(str(rec.get("key", "")) == "bluegill" and absf(float(rec.get("kg", 0.0)) - 0.31) < 1e-6
			and int(rec.get("hookset", -9)) == 0 and str(rec.get("spot", "")) == "reed_bay"
			and int(rec.get("coins", -1)) == 3 and not bool(rec.get("deadlift", true))
			and int(rec.get("best_combo", -1)) == 3 and is_equal_approx(float(rec.get("fight_s", 0.0)), 11.5)
			and bool(rec.get("clean", false)),
		"and the record carries what the row says: key, kg, hook-set, spot, coins, and how the fight went (%s)" % str(rec))
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(2, 93, 7, 3, "bluegill", 0.31)))
	_check(announced == ["bluegill"], "and a replay of the same row is not news either")
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(3, 93, 7, 3, "anvil", 118.0)))
	fishing.receive_row_event(RowEvent.make(
		RowEvent.Kind.INSERTED, &"catch", null, FakeCatchRow.new(4, 93, 8, 3, "golden_koi", 5.5)))
	var r3: Array[Dictionary] = fishing.catches_in(7, 3)
	_check(r3.size() == 2 and int(r3[0]["id"]) == 2 and int(r3[1]["id"]) == 3,
		"a round's catches are that round's, in order, and not another session's (%s)" % str(r3))
	_check(fishing.catches_in(7, 2).size() == 1 and fishing.catches_in(8, 3).size() == 1,
		"each round and session keeps its own")

	# Best catch: rarity first, then weight.
	var rarity: Dictionary[String, int] = {"minnow": 0, "perch": 0, "koi": 3}
	var lookup: Callable = func(key: String) -> int: return rarity.get(key, -1)
	var small_koi: Dictionary = {"key": "koi", "kg": 0.41}
	var big_minnow: Dictionary = {"key": "minnow", "kg": 0.19}
	var bigger_perch: Dictionary = {"key": "perch", "kg": 0.38}
	var smaller_perch: Dictionary = {"key": "perch", "kg": 0.16}
	var mix: Array[Dictionary] = [big_minnow, small_koi, bigger_perch]
	_check(FishingStandings.best_catch(mix, lookup) == small_koi,
		"a small rare catch beats a large common one: rarity decides first")
	var perches: Array[Dictionary] = [smaller_perch, bigger_perch]
	_check(FishingStandings.best_catch(perches, lookup) == bigger_perch,
		"between equals, the heavier")
	_check(FishingStandings.best_catch([] as Array[Dictionary], lookup).is_empty(),
		"no catch, no best")
	# And with the REAL catalogue, the one the board uses when nobody hands it a lookup: an anvil
	# is heavier than everything, and is still not the catch anyone boasts about.
	var real: Array[Dictionary] = [{"key": "anvil", "kg": 118.0}, {"key": "golden_koi", "kg": 5.5},
		{"key": "carp", "kg": 9.0}]
	_check(str(FishingStandings.best_catch(real).get("key", "")) == "golden_koi",
		"with the shipped catalogue a Golden Koi beats an anvil and a carp (%s)"
			% str(FishingStandings.best_catch(real)))
	_check(FishingData.rarity_of("not_a_catch") == -1, "and a key the catalogue lacks ranks below everything")

	var ords: Array[String] = []
	for n: int in [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111, 112]:
		ords.append(FishingStandings.ordinal(n))
	_check(ords == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd",
		"101st", "111th", "112th"], "ranks read as English (%s)" % ", ".join(ords))
	owner_entity.queue_free()


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


# --- SpaceTimeComponent base (Phase 3 Task 2) ----------------------------------------

## Stand-in for SpaceTimeEntity. It is a CharacterBody3D and exposes `body` the same way the
## real one does, so components that write a transform are exercised for real rather than
## silently erroring on a missing property.
class FakeOwnerEntity extends CharacterBody3D:
	var entity_id: int = 99
	var is_local_authority: bool = true
	var body: CharacterBody3D:
		get:
			return self

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


# --- LevelBake parity (server/src/level.rs) -----------------------------------------------

const LEVEL_PROBES: String = "res://shared/golden/level/lakeside_probes.json"

## The client's answer to "is that water, which spot" must be the server's, point for point:
## a float the aim ring shows landing in the lake has to be one the module accepts. The Rust
## twin runs the same file (`cargo test --test level`).
func _run_level_bake_tests() -> void:
	print("== LevelBake ==")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PROBES))
	if not doc is Dictionary:
		_check(false, "cannot read " + LEVEL_PROBES)
		return
	var bake: LevelBake = LevelBake.load_level(str(doc["level"]))
	_check(bake != null, "the %s bake loads, grid and all" % str(doc["level"]))
	if bake == null:
		return
	var probes: Array = doc["probes"] as Array
	var mismatches: int = 0
	var wet: int = 0
	for item: Variant in probes:
		var probe: Dictionary = item as Dictionary
		# Through a Vector3, as the client holds positions: its components are f32, and the probes
		# are f32 values that Godot's JSON parser can hand back one f64 ULP out (see `_f32`).
		var v := Vector3(float(probe["x"]), 0.0, float(probe["z"]))
		var c: Vector2i = bake.cell(v.x, v.z)
		var want_cell: Variant = probe["cell"]
		var cell_ok: bool = c == Vector2i(-1, -1) if want_cell == null \
			else c == Vector2i(int((want_cell as Array)[0]), int((want_cell as Array)[1]))
		var spot: Dictionary = bake.spot_at(v.x, v.z)
		var spot_id: Variant = null if spot.is_empty() else spot["id"]
		var water: bool = bake.is_water(v.x, v.z)
		if water:
			wet += 1
		if not (cell_ok and bake.depth_dm_at(v.x, v.z) == int(probe["depth_dm"])
				and water == bool(probe["is_water"]) and spot_id == probe["spot"]):
			mismatches += 1
			printerr("  level probe %s (%s, %s): cell=%s dm=%d water=%s spot=%s; want %s" % [
				probe["name"], v.x, v.z, c, bake.depth_dm_at(v.x, v.z), water, spot_id, probe])
	print("  %s: %d probes, %d over water" % [doc["level"], probes.size(), wet])
	_check(mismatches == 0, "every level probe matches the Rust twin (%d mismatches)" % mismatches)
	_check(wet > 0 and wet < probes.size(), "the probes cover both water and land")
	# The things the game relies on, whatever the probe file says.
	_check(not bake.is_water(bake.spawn.x, bake.spawn.z), "players arrive on dry land")
	_check(bake.is_water(0.0, 16.0), "the end of the dock is fishable")
	_check(not bake.is_water(0.0, 40.0) and not bake.is_water(3.0, 25.0),
		"but a float cannot land on the dock's planks, though they stand over water")
	_check(bake.spot_at(0.0, 16.0).get("id", "") == "dock_end", "and it is the Dock End spot")
	_check(bake.spot_at(0.0, -24.0).get("id", "") == "deep_hole", "the middle of the lake is the Deep Hole")
	_check(bake.is_water(-60.0, -20.0) and bake.spot_at(-60.0, -20.0).is_empty(),
		"and west of it is open water, no spot")
	# NaN fails every comparison: without its guard it would index a real cell.
	_check(bake.cell(NAN, 0.0) == Vector2i(-1, -1) and bake.cell(0.0, NAN) == Vector2i(-1, -1),
		"a NaN position is off the grid, not cell zero")
	_check(bake.depth_dm_at(INF, 0.0) == 0, "infinity is dry land")


# --- ChallengeModel parity (Phase 3 Task 1) -------------------------------------------

const CHALLENGE_GOLDEN: String = "res://shared/golden/challenge/challenge_timing.json"

## Snap a JSON-parsed number to f32.
##
## Godot's JSON parser does not round-trip f64 exactly: the golden file's half_width for
## mid_bar_easy is the f32 0.24500000476837158, and the parser hands back
## 0.24500000476837161 — one f64 ULP out. The vectors ARE f32 values, so reading them as f32
## is the correct interpretation, not a tolerance fudge; Rust's serde does the same implicitly
## by deserialising straight into f32. Without this the comparison drifts by ~1e-17 and the
## max_err = 0 rule reports a parity failure that does not exist.
static func _f32(v: float) -> float:
	return Vector3(v, 0.0, 0.0).x


## Rebuild the u64 seed from the 32-bit halves the golden file stores. A u64 above 2^53 cannot
## survive JSON -> float -> int, which is why the file does not carry it as one number.
static func _join_seed(hi: int, lo: int) -> int:
	return ((hi & ChallengeModel.M32) << 32) | (lo & ChallengeModel.M32)

## THE HOOK-SET TWIN (DECISIONS #136). The client grades a press the instant it is made, a round
## trip before the module's verdict, so its grade has to BE the module's: the same f32 rounding,
## the same thresholds, from the same file. Both run the NumPy-generated golden cases
## (tools/fishing/gen_goldens.py); `server/tests/fishing.rs` is the other half.
func _run_fishing_rules_tests() -> void:
	print("== fishing rules: the hook-set twin ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/fishing/hookset.json", FileAccess.READ)
	_check(f != null, "the hook-set golden file is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var grades: Dictionary[String, int] = {"none": FishingData.HookSet.NONE,
		"perfect": FishingData.HookSet.PERFECT, "good": FishingData.HookSet.GOOD,
		"late": FishingData.HookSet.LATE}
	var cases: Array = doc.get("cases", []) as Array
	var wrong: Array[String] = []
	var seen: Dictionary[int, bool] = {}
	for c: Variant in cases:
		var d: Dictionary = c as Dictionary
		var want: int = grades[str(d["grade"])]
		var got: int = FishingData.grade_hookset(float(d["reaction"]), float(d["window_mult"]))
		seen[want] = true
		if got != want:
			wrong.append("%s @x%s -> %s, want %s" % [str(d["reaction"]), str(d["window_mult"]), got, want])
	_check(cases.size() >= 100 and wrong.is_empty(),
		"every one of the %d golden reactions is graded exactly as the module grades it (%s)"
			% [cases.size(), str(wrong.slice(0, 4))])
	_check(seen.size() == 4, "and the cases cover all four grades (%d)" % seen.size())
	_check(FishingData.grade_hookset(NAN, 1.0) == FishingData.HookSet.NONE
			and FishingData.grade_hookset(INF, 1.0) == FishingData.HookSet.NONE,
		"a reaction that is not a number sets no hook")
	# The windows the HUD draws are the ones the grades come from.
	var perfect: float = FishingData.timing("hookset_perfect_s")
	var late: float = FishingData.timing("hookset_late_s")
	_check(FishingData.timing("min_reaction_s") < perfect and perfect < late
			and late < FishingData.hookset_window(1.0),
		"too fast < perfect < good < late < the window, in the shared file")
	_check(FishingData.hookset_window(FishingData.hookset_window_mult(FishingData.max_tier()))
			> FishingData.hookset_window(1.0), "and a better reel widens the window")


## THE FIGHT'S TWIN (DECISIONS #140). The client plays the fight for feel; the module replays the
## inputs through `genre::fight` to decide what happened. So `FightSim` must BE that simulation:
## every field, as the bytes of its f64, at every checkpoint of every scripted fight in
## `shared/golden/fishing/fight.json` (written by `server/tests/fight.rs`). Not close — equal. A
## difference of one bit here is a catch the client showed landing and the server says snapped.
func _run_fight_tests() -> void:
	print("== the fight: FightSim against genre::fight ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/fishing/fight.json", FileAccess.READ)
	_check(f != null, "the fight's golden file is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var hex := func(v: float) -> String: return PackedFloat64Array([v]).to_byte_array().hex_encode()
	# THE NUMBERS FIRST: both sides must have read the same file into the same bits.
	var base: FightSim.Params = FightSim.base_params()
	var consts: Dictionary = doc.get("constants", {}) as Dictionary
	var wrong_consts: Array[String] = []
	for k: String in consts:
		var v: float = FightSim.dt() if k == "dt" else float(base.get(k))
		if hex.call(v) != str(consts[k]):
			wrong_consts.append(k)
	_check(consts.size() >= 5 and wrong_consts.is_empty(),
		"fight.json and the fixed step read to the module's exact bits (%s)" % str(wrong_consts))

	var hooksets: Dictionary[String, FishingData.HookSet] = {"perfect": FishingData.HookSet.PERFECT,
		"good": FishingData.HookSet.GOOD, "late": FishingData.HookSet.LATE}
	var cases: Array = doc.get("cases", []) as Array
	var tally: Array[int] = [0]   # values compared; an array so the helper can count into it
	var first_bad: String = ""
	var bad_cases: Array[String] = []
	var outcomes: Dictionary[int, int] = {}
	for c: Variant in cases:
		var d: Dictionary = c as Dictionary
		var params: FightSim.Params = FightSim.params_for(int(d["rod"]), int(d["reel"]), int(d["line"]),
			hooksets[str(d["hookset"])], bool(d["deadlift"]))
		var prof: FightSim.Profile = FightSim.profile_of(str(d["catch"]))
		if prof == null:
			bad_cases.append("%s: no profile for %s" % [d["name"], d["catch"]])
			continue
		var sim := FightSim.new(params, prof, int(d["seed"]), float(d["cast_cm"]) / 100.0, true)
		var checks: Array = d["checks"] as Array
		var k: int = 0
		var mismatch: String = ""
		for r: Variant in d["runs"] as Array:
			var run: Array = r as Array
			for i: int in range(int(run[0])):
				sim.tick(int(run[1]) & 1 != 0, int(run[1]) & 2 != 0, int(run[2]))
				while mismatch.is_empty() and k < checks.size() 						and int((checks[k] as Dictionary)["tick"]) == sim.ticks:
					mismatch = _fight_mismatch(sim, checks[k] as Dictionary, tally)
					k += 1
		# The last checkpoint is the end state, taken after the fight was decided.
		while mismatch.is_empty() and k < checks.size():
			mismatch = _fight_mismatch(sim, checks[k] as Dictionary, tally)
			k += 1
		if not mismatch.is_empty():
			bad_cases.append(str(d["name"]))
			if first_bad.is_empty():
				first_bad = "%s %s" % [d["name"], mismatch]
		outcomes[sim.state] = outcomes.get(sim.state, 0) + 1
		# The static replay the client submits through reaches the same place.
		var again: FightSim = FightSim.replay(params, prof, int(d["seed"]), float(d["cast_cm"]) / 100.0,
			d["runs"] as Array)
		if again.ticks != sim.ticks or again.state != sim.state:
			bad_cases.append("%s: replay() ended at %d/%d, ticking at %d/%d" % [d["name"], again.ticks,
				again.state, sim.ticks, sim.state])
	var compared: int = tally[0]
	print("   %d cases, %d values compared" % [cases.size(), compared])
	_check(cases.size() >= 10 and bad_cases.is_empty(),
		"every scripted fight plays out in GDScript exactly as in the module, max_err = 0 (%s; first: %s)"
			% [str(bad_cases), first_bad])
	_check(compared > 5000, "and that is thousands of values, not a handful (%d)" % compared)
	_check(outcomes.get(FightSim.State.LANDED, 0) >= 5 and outcomes.get(FightSim.State.SNAPPED, 0) >= 2,
		"the cases land catches and snap lines both (%s)" % str(outcomes))

	# Every catch the roll can hand out has a fight.
	var missing: Array[String] = []
	for c: Variant in FishingData.doc().get("catches", []) as Array:
		var id: String = str((c as Dictionary)["id"])
		if FightSim.profile_of(id) == null:
			missing.append(id)
	_check(missing.is_empty(), "every catch in the catalogue has a fight profile (%s)" % str(missing))

	# THE LOG, as it rides in submit_challenge_result.
	var runs: Array[PackedInt32Array] = [PackedInt32Array([12, 0, 0]), PackedInt32Array([90, 1, 0]),
		PackedInt32Array([40, 0, 255])]
	_check(FightSim.encode_log(runs) == [3.0, 12.0, 0.0, 0.0, 90.0, 1.0, 0.0, 40.0, 0.0, 255.0],
		"the log encodes as [n, (ticks, flags, crank) x n] (%s)" % str(FightSim.encode_log(runs)))


## "" when every field of `sim` has the bytes `want` has; otherwise which field, where.
func _fight_mismatch(sim: FightSim, want: Dictionary, tally: Array[int]) -> String:
	for pair: Array in sim.snapshot():
		tally[0] += 1
		var got: String = PackedFloat64Array([float(pair[1])]).to_byte_array().hex_encode()
		if got != str(want.get(pair[0], "")):
			return "at tick %d: %s is %s (%s), the module has %s" % [sim.ticks, pair[0], str(pair[1]), got,
				str(want.get(pair[0], "missing"))]
	return ""


func _run_challenge_tests() -> void:
	print("== ChallengeModel ==")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHALLENGE_GOLDEN))
	if not doc is Dictionary:
		_check(false, "cannot read " + CHALLENGE_GOLDEN)
		return
	var tol: float = float(doc.get("tolerance", 1e-5))
	print("  %s (model=%s, %d cases, %d rejects)" % [
		doc["name"], doc["model_version"], doc["cases"].size(), doc["rejects"].size()])

	for c: Dictionary in doc["cases"]:
		var seed_value: int = _join_seed(int(c["seed_hi"]), int(c["seed_lo"]))
		var difficulty: float = _f32(float(c["difficulty"]))
		var worst: float = 0.0

		var centers: Vector3 = ChallengeModel.timing_centers(seed_value)
		var exp_c: Array = c["expected_centers"]
		worst = maxf(worst, absf(centers.x - _f32(float(exp_c[0]))))
		worst = maxf(worst, absf(centers.y - _f32(float(exp_c[1]))))
		worst = maxf(worst, absf(centers.z - _f32(float(exp_c[2]))))

		var half: float = ChallengeModel.timing_half_width(difficulty)
		worst = maxf(worst, absf(half - _f32(float(c["expected_half_width"]))))

		var result: PackedFloat32Array = PackedFloat32Array()
		for v: float in c["result"]:
			result.append(v)
		var quality: float = ChallengeModel.validate_challenge(
			int(c["kind"]), seed_value, difficulty, result)
		_check(quality >= 0.0, "%s: validator rejected a valid case" % c["name"])
		worst = maxf(worst, absf(quality - _f32(float(c["expected_quality"]))))

		var ok: bool = worst <= tol
		_check(ok, "%s: quality %f expected %f" % [c["name"], quality, _f32(float(c["expected_quality"]))])
		# Parity means bit-equality, not "within tolerance" (AGENTS rule 7).
		_check(worst == 0.0, "%s: drifted from the golden vector by %s" % [c["name"], _sci(worst)])
		print("    %-24s %s  max_err=%s" % [c["name"], "ok " if ok else "BAD", _sci(worst)])

	for r: Dictionary in doc["rejects"]:
		var rresult: PackedFloat32Array = PackedFloat32Array()
		for v: float in r["result"]:
			rresult.append(v)
		var got: float = ChallengeModel.validate_challenge(
			int(r["kind"]),
			_join_seed(int(r["seed_hi"]), int(r["seed_lo"])),
			_f32(float(r["difficulty"])),
			rresult)
		_check(got < 0.0, "%s: malformed submission was accepted (%f)" % [r["name"], got])

	# Sanity: the validator must actually read the player's input.
	var s: int = 4242
	var cen: Vector3 = ChallengeModel.timing_centers(s)
	var perfect_in: PackedFloat32Array = PackedFloat32Array([cen.x, cen.y, cen.z])
	var off_in: PackedFloat32Array = PackedFloat32Array([
		minf(cen.x + 0.05, 1.0), minf(cen.y + 0.05, 1.0), minf(cen.z + 0.05, 1.0)])
	var perfect: float = ChallengeModel.validate_challenge(0, s, 0.5, perfect_in)
	var worse: float = ChallengeModel.validate_challenge(0, s, 0.5, off_in)
	_check(perfect > worse, "accuracy must change quality (%f vs %f)" % [perfect, worse])
	_check(absf(perfect - 1.0) < 1e-6, "hitting every centre scores 1.0, got %f" % perfect)


# --- SpaceTimeEntity (Phase 3 Task 3) --------------------------------------------------

const PLAYER_SCENE: String = "res://foundation/entities/player.tscn"

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

## Autoloads cannot be named at compile time from this script: `-s` compiles it before the
## autoloads are added to the tree, which is a hard "Identifier not found" rather than a
## runtime nil. The suites run deferred, so by here they exist and can be fetched by path.
func _autoload(n: String) -> Node:
	return get_tree().root.get_node_or_null(NodePath("/root/" + n))

## A complete, valid initial row set for player.tscn. Every test that spawns or binds that
## scene goes through here: as the scene gains components (Movement in Task 6, Input in Task 7)
## the required tables grow, and without a single source of truth each spawn test breaks
## separately with a different confusing error.
class FakeMemberRow extends RefCounted:
	var id: int = 1
	var session_id: int
	var entity_id: int
	var score: int = 0
	var coins: int = 0
	func _init(eid: int, sid: int) -> void:
		entity_id = eid
		session_id = sid

class FakeSessionRow extends RefCounted:
	var id: int
	var world_id: int = 0
	var kind: int = 0
	var phase: int = 0
	var phase_ends_at: int = 0
	var seed: int = 12345
	var max_members: int = 0
	var round: int = 1
	func _init(sid: int, p: int, ends: int) -> void:
		id = sid
		phase = p
		phase_ends_at = ends

func _player_rows(eid: int) -> Array:
	return [
		RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null,
			FakeHealthRow.new(eid, 100.0, 100.0)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"movement_state", null,
			FakeMoveRow.new(eid, Vector3.ZERO, 0)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"session_member", null,
			FakeMemberRow.new(eid, 1)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"inventory_item", null,
			FakeItemRow.new(900 + eid, eid, 1, 1)),
	]

## Same set, pushed through the registry so the spawner picks it up as buffered initial state.
func _buffer_player_rows(reg: Node, eid: int) -> void:
	for ev: RowEvent in _player_rows(eid):
		reg._on_row_event(ev)


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


# --- EntitySpawner (Phase 3 Task 4) ----------------------------------------------------

## `entity` row stand-in: the spawner reads kind/world_id/owner off the row by name.
class FakeEntityRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var kind: int = 0
	var owner: PackedByteArray = PackedByteArray()
	func _init(eid: int, k: int = 0) -> void:
		entity_id = eid
		kind = k

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


# --- SpaceTimeHealthComponent (Phase 3 Task 5) -----------------------------------------

## Mirrors `health_state`. Values are read off by name, as the SDK's generated rows are.
class FakeHealthRow extends RefCounted:
	var entity_id: int
	var current: float
	var max: float
	var is_dead: bool
	var last_damage_source: int
	var last_change_server_tick: int = 0
	func _init(eid: int, cur: float, mx: float, dead: bool = false, src: int = 0) -> void:
		entity_id = eid
		current = cur
		max = mx
		is_dead = dead
		last_damage_source = src

func _run_health_tests() -> void:
	print("== SpaceTimeHealthComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus autoload present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 55
	get_tree().root.add_child(owner_entity)

	var h := SpaceTimeHealthComponent.new()
	get_tree().root.add_child(h)

	var local: Array[String] = []
	h.health_changed.connect(func(c: float, m: float, d: float) -> void:
		local.append("changed %.0f/%.0f d=%.0f" % [c, m, d]))
	h.damaged.connect(func(a: float, s: int) -> void: local.append("damaged %.0f from %d" % [a, s]))
	h.healed.connect(func(a: float) -> void: local.append("healed %.0f" % a))
	h.died.connect(func(k: int) -> void: local.append("died by %d" % k))
	h.revived.connect(func() -> void: local.append("revived"))

	var bus_events: Array[String] = []
	var hcb := func(eid: int, c: float, m: float) -> void:
		bus_events.append("health %d %.0f/%.0f" % [eid, c, m])
	var dcb := func(eid: int, killer: int) -> void: bus_events.append("died %d by %d" % [eid, killer])
	var rcb := func(eid: int) -> void: bus_events.append("revived %d" % eid)
	bus.entity_health_changed.connect(hcb)
	bus.entity_died.connect(dcb)
	bus.entity_revived.connect(rcb)

	# First bind: initial state, not a change.
	var initial: Dictionary[StringName, RefCounted] = {&"health_state": FakeHealthRow.new(55, 100.0, 100.0)}
	h.bind(owner_entity, initial)
	_check(local == ["changed 100/100 d=0"], "first bind reports delta 0 and no damage")
	_check(h.get_current() == 100.0 and h.get_max() == 100.0, "read API reflects the row")
	_check(is_equal_approx(h.get_ratio(), 1.0), "ratio 1.0 at full health")

	# 100 -> 75 is damage of 25, attributed to the source on the row.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 100.0, 100.0), FakeHealthRow.new(55, 75.0, 100.0, false, 9)))
	_check(local == ["changed 75/100 d=-25", "damaged 25 from 9"], "100->75 emits damaged(25, 9)")
	_check(is_equal_approx(h.get_ratio(), 0.75), "ratio tracks current/max")

	# 75 -> 100 is healing, not damage.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 75.0, 100.0), FakeHealthRow.new(55, 100.0, 100.0)))
	_check(local == ["changed 100/100 d=25", "healed 25"], "75->100 emits healed(25)")

	# Death transition.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 100.0, 100.0), FakeHealthRow.new(55, 0.0, 100.0, true, 42)))
	_check(local.has("died by 42"), "is_dead false->true emits died(last_damage_source)")
	_check(h.is_dead(), "is_dead read API")

	# Still dead on a later update: died must not repeat.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 0.0, 100.0, true, 42), FakeHealthRow.new(55, 0.0, 120.0, true, 42)))
	_check(not local.has("died by 42"), "died does not re-fire while still dead")

	# Revival.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 0.0, 120.0, true, 42), FakeHealthRow.new(55, 60.0, 120.0, false, 42)))
	_check(local.has("revived"), "is_dead true->false emits revived")
	_check(not h.is_dead(), "is_dead cleared")

	# Bus mirrors, entity_id first.
	_check(bus_events.has("health 55 100/100"), "bus entity_health_changed carries entity_id first")
	_check(bus_events.has("died 55 by 42"), "bus entity_died mirrors")
	_check(bus_events.has("revived 55"), "bus entity_revived mirrors")

	# A vanished row must not be reported as a death.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"health_state",
		FakeHealthRow.new(55, 60.0, 120.0), null))
	_check(local.is_empty(), "row delete emits nothing (despawn, not death)")

	bus.entity_health_changed.disconnect(hcb)
	bus.entity_died.disconnect(dcb)
	bus.entity_revived.disconnect(rcb)
	h.queue_free()
	owner_entity.queue_free()


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


# --- SpaceTimeMovementComponent (Phase 3 Task 6) ---------------------------------------

## Mirrors `movement_state`. pos/vel are real Vector3 because the module's wire struct is
## literally named Vector3, which is what makes the SDK map it natively (DECISIONS #40).
## The nested `frame` on an `input_queue` row, spelled the way the WIRE spells it: `move_x` and
## `move_y`, matching `sim.rs` and the generated struct. Using a real InputFrame here instead
## would hide the one mistake this can make, because that class calls the pair `move_dir`.
class FakeWireFrame extends RefCounted:
	var seq: int = 0
	var client_tick: int = 0
	var move_x: float = 0.0
	var move_y: float = 0.0
	var look_yaw: float = 0.0
	var look_pitch: float = 0.0
	var jump: bool = false
	var sprint: bool = false
	var client_pos: Vector3 = Vector3.ZERO
	var epoch: int = 0
	var move_state: int = 0
	var dash: bool = false
	var slow: bool = false
	var face: bool = false


## An `input_queue` row, as the sidecar receives it.
class FakeInputRow extends RefCounted:
	var id: int = 0
	var entity_id: int = 0
	var world_id: int = 0
	var frame: FakeWireFrame = null

	func _init(eid: int, f: InputFrame) -> void:
		entity_id = eid
		id = f.seq
		frame = FakeWireFrame.new()
		frame.seq = f.seq
		frame.client_tick = f.client_tick
		frame.move_x = f.move_dir.x
		frame.move_y = f.move_dir.y
		frame.look_yaw = f.look_yaw
		frame.look_pitch = f.look_pitch
		frame.jump = f.jump
		frame.sprint = f.sprint
		frame.client_pos = f.client_pos
		frame.epoch = f.epoch
		frame.move_state = f.move_state
		frame.dash = f.dash
		frame.slow = f.slow
		frame.face = f.face


## A `gear` row. Tiers only: the prices and the effects are the server's business.
class FakeGearRow extends RefCounted:
	var entity_id: int = 0
	var rod_tier: int = 0
	var reel_tier: int = 0
	var line_tier: int = 0

	func _init(eid: int, rod: int, reel: int, line: int) -> void:
		entity_id = eid
		rod_tier = rod
		reel_tier = reel
		line_tier = line


class FakeMoveRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var pos: Vector3
	var vel: Vector3
	var yaw: float = 0.0
	var grounded: bool = true
	var move_state: int = 0
	var last_processed_seq: int = 0
	var server_tick: int = 0
	var server_ts: int = 0
	var teleport_flag: bool = false
	var correction_epoch: int = 0
	func _init(eid: int, p: Vector3, ts: int) -> void:
		entity_id = eid
		pos = p
		vel = Vector3.ZERO
		server_ts = ts

static func _move_ev(row: FakeMoveRow) -> RowEvent:
	return RowEvent.make(RowEvent.Kind.UPDATED, &"movement_state", null, row)

## Movement component wired to a fake owner, with a controllable clock.
func _make_movement(now_usec_ref: Array) -> SpaceTimeMovementComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 77
	get_tree().root.add_child(owner_entity)
	var m := SpaceTimeMovementComponent.new()
	m._clock_override = func() -> int: return int(now_usec_ref[0])
	var cfg := MovementConfig.new()
	cfg.remote_interp_delay = 0.1
	m.config = cfg
	m.mode = SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED
	get_tree().root.add_child(m)
	var empty: Dictionary[StringName, RefCounted] = {}
	m.bind(owner_entity, empty)
	return m

func _run_movement_tests() -> void:
	print("== SpaceTimeMovementComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus present")
		return

	# Three snapshots 50 ms apart along +X, at server times 1.000s / 1.050s / 1.100s. 1 m per
	# 50 ms is 20 m/s, and the rows SAY so: the module derives velocity from the motion, and
	# interpolation uses it (Hermite). This fixture used to claim zero velocity while moving —
	# no real row can — and the curve through it eased, which is the fixture's fault.
	var now: Array = [0]
	var m: SpaceTimeMovementComponent = _make_movement(now)
	var t0: int = 1_000_000
	for i: int in range(3):
		var r := FakeMoveRow.new(77, Vector3(float(i), 0.0, 0.0), t0 + i * 50_000)
		r.vel = Vector3(20.0, 0.0, 0.0)
		m.receive_row_event(_move_ev(r))
	_check(m.snapshot_count() == 3, "three snapshots buffered")

	# --- exact midpoint between snapshot 0 and 1 ------------------------------------
	# render_t = now - 100ms delay. Want render_t = 1.025s -> now = 1.125s.
	now[0] = t0 + 25_000 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0.5, 0, 0)),
		"midpoint interpolates to the midpoint (got %s)" % m.get_render_state().pos)

	# --- a TURN is drawn without corners (Hermite, DECISIONS #76) -----------------------
	# Five snapshots 100 ms apart (a sparse stretch: a tick that processed no frames leaves a
	# gap like this) on an arc of radius 2 m at 5 m/s, each carrying the tangent velocity the
	# module would report. Straight lines between them change direction
	# only at the samples: a kink per sample. Measure the worst frame-to-frame change in
	# displacement across the whole turn, stepping at 60 Hz.
	var tnow: Array = [0]
	var mt: SpaceTimeMovementComponent = _make_movement(tnow)
	var radius: float = 2.0
	var speed: float = 5.0
	var omega: float = speed / radius
	for i: int in range(5):
		var ang: float = omega * float(i) * 0.1
		var row := FakeMoveRow.new(77, Vector3(radius * sin(ang), 0.0, radius * (1.0 - cos(ang))), t0 + i * 100_000)
		row.vel = Vector3(speed * cos(ang), 0.0, speed * sin(ang))
		mt.receive_row_event(_move_ev(row))
	# Strictly INSIDE the buffered span, using the delay the component is ACTUALLY applying. At
	# the span's first instant the view holds the oldest sample, and measuring from there records
	# "starting to move", not the turn. The first versions of this test assumed a 100 ms delay;
	# the five rows arrive in one frame, the estimator rightly reads that as jitter and adapts to
	# ~118 ms, and the "kink" it reported was the hold ending.
	var delay_us: int = int(mt.get_interp_delay_sec() * 1_000_000.0)
	var drawn: Array[Vector3] = []
	var step_us: int = 16_667
	var ts: int = t0 + delay_us + 5_000
	while ts < t0 + 400_000 + delay_us - 5_000:
		tnow[0] = ts
		mt.update_view()
		drawn.append(mt.get_render_state().pos)
		ts += step_us
	var worst_turn: float = 0.0
	for i: int in range(2, drawn.size()):
		worst_turn = maxf(worst_turn, ((drawn[i] - drawn[i - 1]) - (drawn[i - 1] - drawn[i - 2])).length())
	# The true path changes displacement by v^2/r * dt^2 = 12.5 * 0.000278 = 0.0035 m per frame.
	_check(worst_turn < 0.006,
		"a turn is drawn as a curve, not a polygon: worst change %.4f m/frame (the path itself: 0.0035)" % worst_turn)
	mt.entity.queue_free()
	mt.queue_free()

	# --- a DRY SPELL during a turn rejoins without a lurch -----------------------------
	# The rare live lurch, made deterministic: the walker's rows stop arriving, the view projects
	# it on along +X, and meanwhile it has turned to +Z. When the rows resume, the drawn path must
	# get from "projected the wrong way" back onto the real one without any frame-to-frame change
	# in motion a walker cannot make. 0.05 m/frame is the bound the live playtest asserts.
	#
	# The walker's rows come from the REAL MovementModel, one every 3 frames (50 ms), so the turn
	# is one a player can actually make (40 m/s^2). An earlier version turned 90 degrees in zero
	# time — 140 m/s^2 no walker can produce — and most of what it measured was that.
	var dnow: Array = [0]
	var md: SpaceTimeMovementComponent = _make_movement(dnow)
	var cfg_w := MovementConfig.new()
	var walker := MovementState.new()
	walker.grounded = true
	var rows_before: Array[FakeMoveRow] = []
	var rows_after: Array[FakeMoveRow] = []
	for fr: int in range(1, 25):
		var inp := InputFrame.new()
		inp.move_dir = Vector2(1.0, 0.0) if fr <= 12 else Vector2(0.0, 1.0)   # +X, then turn to +Z
		walker = MovementModel.simulate(walker, inp, cfg_w, 1.0 / 60.0)
		if fr % 3 == 0:
			var row := FakeMoveRow.new(77, walker.pos, t0 + fr * 16_667)
			row.vel = walker.vel
			(rows_before if fr <= 12 else rows_after).append(row)
	for row: FakeMoveRow in rows_before:
		md.receive_row_event(_move_ev(row))
	var d_delay: int = int(md.get_interp_delay_sec() * 1_000_000.0)
	var newest_t: int = rows_before[-1].server_ts
	var dpath: Array[Vector3] = []
	var dts: int = rows_before[1].server_ts + d_delay   # start mid-buffer
	# Run 3 frames past the newest sample: the buffer is dry and the view extrapolates.
	while dts - d_delay <= newest_t + 50_000:
		dnow[0] = dts
		md.update_view()
		dpath.append(md.get_render_state().pos)
		dts += 16_667
	_check(md.get_interp_stats()["dry_events"] >= 1, "setup: the buffer ran dry")
	for row: FakeMoveRow in rows_after:   # the rows resume: the walker has been turning
		md.receive_row_event(_move_ev(row))
	for i: int in range(18):
		dnow[0] = dts
		md.update_view()
		dpath.append(md.get_render_state().pos)
		dts += 16_667
	var worst_rejoin: float = 0.0
	for i: int in range(2, dpath.size()):
		worst_rejoin = maxf(worst_rejoin, ((dpath[i] - dpath[i - 1]) - (dpath[i - 1] - dpath[i - 2])).length())
	_check(worst_rejoin < 0.05,
		"rejoining the real path after a dry spell at a turn is smooth: worst change %.3f m/frame" % worst_rejoin)
	_check(md.get_remote_offset().length() < 0.001, "and the rejoin blend has finished (%.3f m left)" % md.get_remote_offset().length())
	md.entity.queue_free()
	md.queue_free()

	# --- quarter point ---------------------------------------------------------------
	now[0] = t0 + 12_500 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0.25, 0, 0)),
		"quarter point interpolates to 0.25 (got %s)" % m.get_render_state().pos)

	# --- exactly on a snapshot -------------------------------------------------------
	now[0] = t0 + 50_000 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(1.0, 0, 0)),
		"landing exactly on a snapshot uses that snapshot")

	# --- render time older than the whole buffer: hold the oldest --------------------
	now[0] = t0 - 500_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0, 0, 0)),
		"render time before the buffer holds the oldest snapshot")

	# --- the body actually moved -----------------------------------------------------
	now[0] = t0 + 25_000 + 100_000
	m.update_view()
	var bdy: CharacterBody3D = m.entity.body
	_check(bdy != null and bdy.position.is_equal_approx(Vector3(0.5, 0, 0)),
		"render state is applied to the body transform")
	m.entity.queue_free()
	m.queue_free()

	# --- extrapolation ---------------------------------------------------------------
	var now2: Array = [0]
	var m2: SpaceTimeMovementComponent = _make_movement(now2)
	var moving := FakeMoveRow.new(77, Vector3(10.0, 0.0, 0.0), t0)
	moving.vel = Vector3(4.0, 0.0, 0.0)
	m2.receive_row_event(_move_ev(moving))

	# 50 ms past the newest snapshot -> 10 + 4*0.05 = 10.2
	now2[0] = t0 + 50_000 + 100_000
	m2.update_view()
	_check(m2.get_render_state().pos.is_equal_approx(Vector3(10.2, 0, 0)),
		"extrapolates with velocity past the newest snapshot (got %s)" % m2.get_render_state().pos)

	# 5 s past -> clamped to 100 ms of extrapolation: 10 + 4*0.1 = 10.4, and no further
	now2[0] = t0 + 5_000_000 + 100_000
	m2.update_view()
	_check(m2.get_render_state().pos.is_equal_approx(Vector3(10.4, 0, 0)),
		"extrapolation is clamped to 100 ms, then holds (got %s)" % m2.get_render_state().pos)
	m2.entity.queue_free()
	m2.queue_free()

	# --- jumped / landed fire exactly once across a grounded flip and back -----------
	var now3: Array = [0]
	var m3: SpaceTimeMovementComponent = _make_movement(now3)
	var jumps: Array[int] = []
	var lands: Array[float] = []
	m3.jumped.connect(func() -> void: jumps.append(1))
	m3.landed.connect(func(speed: float) -> void: lands.append(speed))
	var bus_jumps: Array[int] = []
	var jcb := func(eid: int) -> void: bus_jumps.append(eid)
	bus.entity_jumped.connect(jcb)

	var g0 := FakeMoveRow.new(77, Vector3.ZERO, t0)
	m3.receive_row_event(_move_ev(g0))
	var air := FakeMoveRow.new(77, Vector3(0, 1, 0), t0 + 50_000)
	air.grounded = false
	air.vel = Vector3(0, 8.0, 0)
	m3.receive_row_event(_move_ev(air))
	var falling := FakeMoveRow.new(77, Vector3(0, 2, 0), t0 + 100_000)
	falling.grounded = false
	falling.vel = Vector3(0, -6.0, 0)
	m3.receive_row_event(_move_ev(falling))
	var back := FakeMoveRow.new(77, Vector3.ZERO, t0 + 150_000)
	back.grounded = true
	back.vel = Vector3.ZERO
	m3.receive_row_event(_move_ev(back))

	_check(jumps.size() == 1, "jumped fired exactly once (got %d)" % jumps.size())
	_check(lands.size() == 1, "landed fired exactly once (got %d)" % lands.size())
	_check(lands.size() == 1 and is_equal_approx(lands[0], 6.0),
		"landed reports the pre-touchdown fall speed")
	_check(bus_jumps == [77], "entity_jumped mirrored to the bus with entity_id")
	bus.entity_jumped.disconnect(jcb)

	# Walking off a ledge is not a jump.
	var jumps_before: int = jumps.size()
	var ledge := FakeMoveRow.new(77, Vector3(0, -0.1, 0), t0 + 200_000)
	ledge.grounded = false
	ledge.vel = Vector3(0, -1.0, 0)
	m3.receive_row_event(_move_ev(ledge))
	_check(jumps.size() == jumps_before, "leaving the ground downward is not a jump")
	m3.entity.queue_free()
	m3.queue_free()

	# --- move_state_changed -----------------------------------------------------------
	var now8: Array = [0]
	var m8: SpaceTimeMovementComponent = _make_movement(now8)
	var transitions: Array[String] = []
	m8.move_state_changed.connect(func(o: int, n: int) -> void:
		transitions.append("%d->%d" % [o, n]))
	m8.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3.ZERO, t0)))
	var walking := FakeMoveRow.new(77, Vector3.ZERO, t0 + 50_000)
	walking.move_state = 1
	m8.receive_row_event(_move_ev(walking))
	var walking2 := FakeMoveRow.new(77, Vector3.ZERO, t0 + 100_000)
	walking2.move_state = 1
	m8.receive_row_event(_move_ev(walking2))
	_check(transitions == ["0->1"], "move_state_changed fires once per actual change")
	m8.entity.queue_free()
	m8.queue_free()

	# --- teleport clears the buffer and snaps ----------------------------------------
	var now4: Array = [0]
	var m4: SpaceTimeMovementComponent = _make_movement(now4)
	var teleports: Array[int] = []
	var tcb := func(eid: int) -> void: teleports.append(eid)
	bus.entity_teleported.connect(tcb)
	for i: int in range(3):
		m4.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(float(i), 0, 0), t0 + i * 50_000)))
	var tp := FakeMoveRow.new(77, Vector3(500.0, 0, 0), t0 + 150_000)
	tp.teleport_flag = true
	m4.receive_row_event(_move_ev(tp))
	_check(m4.snapshot_count() == 1, "teleport clears the snapshot buffer")
	# The snap is drawn on the next physics tick (update_view), never between ticks: with
	# physics interpolation on, a transform moved between ticks is rendered as a smear.
	m4.update_view()
	_check(m4.get_render_state().pos.is_equal_approx(Vector3(500, 0, 0)),
		"teleport snaps the render state instead of gliding")
	_check(teleports == [77], "entity_teleported mirrored to the bus")
	bus.entity_teleported.disconnect(tcb)
	m4.entity.queue_free()
	m4.queue_free()

	# --- ordering / dedupe / ring cap -------------------------------------------------
	var now5: Array = [0]
	var m5: SpaceTimeMovementComponent = _make_movement(now5)
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(2, 0, 0), t0 + 100_000)))
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(0, 0, 0), t0)))
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(1, 0, 0), t0 + 50_000)))
	_check(m5.snapshot_count() == 3, "out-of-order snapshots are all kept")
	now5[0] = t0 + 25_000 + 100_000
	m5.update_view()
	_check(m5.get_render_state().pos.is_equal_approx(Vector3(0.5, 0, 0)),
		"out-of-order snapshots are sorted, so interpolation is still correct")

	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(9, 9, 9), t0 + 50_000)))
	_check(m5.snapshot_count() == 3, "a repeated timestamp replaces rather than duplicates")

	for i: int in range(60):
		m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(float(i), 0, 0),
			t0 + 1_000_000 + i * 50_000)))
	_check(m5.snapshot_count() == SpaceTimeMovementComponent.RING_SIZE,
		"ring is capped at RING_SIZE (got %d)" % m5.snapshot_count())
	m5.entity.queue_free()
	m5.queue_free()

	# --- SERVER_DRIVEN applies the newest row with no smoothing ----------------------
	var now6: Array = [0]
	var m6: SpaceTimeMovementComponent = _make_movement(now6)
	m6.mode = SpaceTimeMovementComponent.Mode.SERVER_DRIVEN
	m6.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(3, 0, 0), t0)))
	now6[0] = t0
	m6.update_view()
	_check(m6.get_render_state().pos.is_equal_approx(Vector3(3, 0, 0)),
		"SERVER_DRIVEN renders the authoritative state directly")
	_check(m6.get_authoritative_state().pos.is_equal_approx(Vector3(3, 0, 0)),
		"authoritative read API returns the newest row")
	var acked := FakeMoveRow.new(77, Vector3(3, 0, 0), t0 + 10_000)
	acked.last_processed_seq = 42
	m6.receive_row_event(_move_ev(acked))
	_check(m6.get_last_processed_seq() == 42, "last_processed_seq is read off the row")
	m6.entity.queue_free()
	m6.queue_free()

	# --- empty buffer must not crash --------------------------------------------------
	var now7: Array = [0]
	var m7: SpaceTimeMovementComponent = _make_movement(now7)
	m7.update_view()
	_check(m7.snapshot_count() == 0, "update_view on an empty buffer is a no-op")
	m7.entity.queue_free()
	m7.queue_free()


# --- LocalInputComponent (Phase 3 Task 7) ----------------------------------------------

func _make_input_component(is_local: bool) -> LocalInputComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 88
	owner_entity.is_local_authority = is_local
	# The camera rig is what "forward" is relative to.
	var rig := Node3D.new()
	rig.name = "CameraRig"
	owner_entity.add_child(rig)
	get_tree().root.add_child(owner_entity)

	var c := LocalInputComponent.new()
	c.send_to_server = false
	get_tree().root.add_child(c)
	var empty: Dictionary[StringName, RefCounted] = {}
	c.bind(owner_entity, empty)
	return c

func _release_all_actions() -> void:
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right",
			&"jump", &"sprint"]:
		if InputMap.has_action(a):
			Input.action_release(a)

func _run_input_tests() -> void:
	print("== LocalInputComponent ==")

	# The component is useless without its actions; assert the project actually defines them
	# rather than silently sampling zeros forever.
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right",
			&"jump", &"sprint", &"interact"]:
		_check(InputMap.has_action(a), "input action '%s' is defined in project.godot" % a)

	var c: LocalInputComponent = _make_input_component(true)
	var frames: Array[InputFrame] = []
	c.input_sampled.connect(func(f: InputFrame) -> void: frames.append(f))
	_release_all_actions()

	# --- seq is monotonic ------------------------------------------------------------
	var f1: InputFrame = c.sample()
	var f2: InputFrame = c.sample()
	var f3: InputFrame = c.sample()
	_check(f1.seq == 1 and f2.seq == 2 and f3.seq == 3,
		"seq increments monotonically from 1 (got %d,%d,%d)" % [f1.seq, f2.seq, f3.seq])
	_check(f1.client_tick == 0 and f3.client_tick == 2, "client_tick advances with seq")
	_check(frames.size() == 3, "input_sampled emitted once per sample")
	_check(c.last_seq() == 3, "last_seq reports the newest frame")
	# A RESTARTED client (DECISIONS #149): its entity's row says the server has taken inputs up to
	# 570 already, from the run before. It carries on from there instead of counting from 1 into
	# the server's drop — and a server behind it (the normal case) changes nothing.
	var back: LocalInputComponent = _make_input_component(true)
	var row_held := SpaceTimeMovementComponent.new()
	row_held._last_processed_seq = 570
	back._movement = row_held
	var resumed: InputFrame = back.sample()
	row_held._last_processed_seq = 12
	var next: InputFrame = back.sample()
	_check(resumed.seq == 571 and back.first_seq() == 571 and next.seq == 572,
		"a restarted client carries on from the count its entity's row holds (%d, then %d)" % [resumed.seq, next.seq])
	back._movement = null
	row_held.free()
	back.queue_free()

	# --- idle input is exactly zero ---------------------------------------------------
	_check(f1.move_dir == Vector2.ZERO, "no keys held yields a zero move_dir")
	_check(not f1.jump and not f1.sprint, "no keys held yields no jump/sprint")

	# --- a single direction -----------------------------------------------------------
	Input.action_press(&"move_forward")
	var fwd: InputFrame = c.sample()
	_check(fwd.move_dir.is_equal_approx(Vector2(0, -1)),
		"forward is -Y in move_dir (got %s)" % fwd.move_dir)
	_check(is_equal_approx(fwd.move_dir.length(), 1.0), "single direction has magnitude 1")

	# --- diagonals are normalised, not 1.41x faster ------------------------------------
	Input.action_press(&"move_right")
	var diag: InputFrame = c.sample()
	_check(is_equal_approx(diag.move_dir.length(), 1.0),
		"diagonal input is normalised to magnitude 1 (got %f)" % diag.move_dir.length())
	_check(diag.move_dir.is_equal_approx(Vector2(1, -1).normalized()),
		"diagonal points between the two axes")

	# --- opposing keys cancel -----------------------------------------------------------
	Input.action_press(&"move_left")
	var cancel: InputFrame = c.sample()
	_check(is_equal_approx(cancel.move_dir.x, 0.0), "left+right cancel on the X axis")
	_release_all_actions()

	# --- buttons ------------------------------------------------------------------------
	Input.action_press(&"jump")
	Input.action_press(&"sprint")
	var btn: InputFrame = c.sample()
	_check(btn.jump and btn.sprint, "jump and sprint are sampled")
	_release_all_actions()
	var released: InputFrame = c.sample()
	_check(not released.jump and not released.sprint, "buttons clear when released")

	# --- movement is relative to where the body is being told to face ----------------------
	# Look 90 degrees; "forward" must now point along world -X.
	c.set_look(PI / 2.0, 0.0)
	Input.action_press(&"move_forward")
	var turned: InputFrame = c.sample()
	_check(turned.move_dir.is_equal_approx(Vector2(-1, 0)),
		"move_dir follows the look direction: forward at 90 deg points -X (got %s)"
			% turned.move_dir)

	# FREE LOOK. The camera keeps turning; the body does not, so a held direction keeps going
	# where the character is pointed instead of curving after the camera.
	_check(InputMap.has_action(LocalInputComponent.ACTION_FREELOOK),
		"the project defines a free-look action")
	Input.action_press(LocalInputComponent.ACTION_FREELOOK)
	var swing := InputEventMouseMotion.new()
	swing.relative = Vector2(300.0, 0.0)
	MouseCapture.want_capture(true)
	c._unhandled_input(swing)
	var held: InputFrame = c.sample()
	_check(absf(c.get_look_yaw() - PI / 2.0) > 0.5,
		"the camera turned (%.2f rad)" % c.get_look_yaw())
	_check(absf(held.look_yaw - PI / 2.0) < 1e-5 and held.move_dir.is_equal_approx(Vector2(-1, 0)),
		"but the body's heading and the movement direction did not (%s, %s)"
			% [held.look_yaw, held.move_dir])
	Input.action_release(LocalInputComponent.ACTION_FREELOOK)
	var after_free: InputFrame = c.sample()
	_check(absf(after_free.look_yaw - c.get_look_yaw()) < 1e-5,
		"and letting go hands the body the camera's heading, without a jump in between")
	MouseCapture.want_capture(false)
	c.set_look(0.0, 0.0)
	_release_all_actions()

	# --- look angles ---------------------------------------------------------------------
	c.set_look(1.0, 0.5)
	var looked: InputFrame = c.sample()
	_check(is_equal_approx(looked.look_yaw, 1.0) and is_equal_approx(looked.look_pitch, 0.5),
		"look angles are carried on the frame")
	c.set_look(0.0, 99.0)
	_check(c.get_look_pitch() < deg_to_rad(90.0),
		"pitch is clamped below vertical (got %f rad)" % c.get_look_pitch())

	# --- facing follows the camera only while moving ----------------------------------------
	# Standing still and looking around must not spin the body. The module applies the same rule
	# to the same frame (DECISIONS #100); a client that applied a different one would show every
	# other player facing somewhere they are not.
	var yaw_m: SpaceTimeMovementComponent = _make_predicted(91)
	var yaw_seq: Array[int] = [0]
	var still := InputFrame.new()
	yaw_seq[0] += 1
	still.seq = yaw_seq[0]
	still.look_yaw = 1.2
	yaw_m.push_input(still)
	_check(absf(yaw_m.get_predicted_state().yaw) < 1e-6,
		"looking around while standing still does not turn the body (%.3f rad)"
			% yaw_m.get_predicted_state().yaw)
	var going := InputFrame.new()
	yaw_seq[0] += 1
	going.seq = yaw_seq[0]
	going.look_yaw = 1.2
	going.move_dir = Vector2(0.0, -1.0)
	yaw_m.push_input(going)
	_check(absf(yaw_m.get_predicted_state().yaw - 1.2) < 1e-6,
		"and moving turns it to face the camera (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	# AIMING turns it standing still (#136): a cast thrown behind you is thrown by someone facing
	# that way. Same rule, same frame, in module.rs.
	var aimed := InputFrame.new()
	yaw_seq[0] += 1
	aimed.seq = yaw_seq[0]
	aimed.look_yaw = -2.5
	aimed.face = true
	yaw_m.push_input(aimed)
	_check(absf(yaw_m.get_predicted_state().yaw + 2.5) < 1e-6,
		"a frame that is aiming turns the body standing still (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	var after := InputFrame.new()
	yaw_seq[0] += 1
	after.seq = yaw_seq[0]
	after.look_yaw = 0.4
	yaw_m.push_input(after)
	_check(absf(yaw_m.get_predicted_state().yaw + 2.5) < 1e-6,
		"and once it stops aiming, the heading it aimed on stays (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	yaw_m.entity.queue_free()
	yaw_m.queue_free()

	# --- hold_facing: who asks, and what goes on the wire ----------------------------------
	c.set_look(0.0, 0.0)
	_check(not c.sample().face, "nobody aiming: the frame does not ask to face")
	c.hold_facing(&"bow", true)
	c.hold_facing(&"cast", true)
	c.set_look(1.9, 0.0)
	var aiming_frame: InputFrame = c.sample()
	_check(aiming_frame.face and absf(aiming_frame.look_yaw - 1.9) < 1e-6,
		"while something aims, the frame asks to face the camera (face=%s, yaw %.2f)" % [aiming_frame.face, aiming_frame.look_yaw])
	c.hold_facing(&"cast", false)
	_check(c.sample().face, "one reason letting go does not cancel another's")
	c.hold_facing(&"bow", false)
	_check(not c.sample().face and not c.is_facing_held(), "and the last one letting go ends it")
	c.set_look(0.0, 0.0)

	# --- mouse look only while the cursor is ours -------------------------------------------
	# Without this gate the view swings whenever the pointer moves — across a menu, or on its
	# way out of the window. That is the other half of "the mouse is not captured": not only
	# did the cursor escape the window, it went on steering the camera from outside it.
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 0.0)
	c.set_look(0.0, 0.0)
	MouseCapture.want_capture(false)
	c._unhandled_input(motion)
	_check(is_equal_approx(c.get_look_yaw(), 0.0),
		"a free cursor does not steer the camera (yaw %f)" % c.get_look_yaw())
	MouseCapture.want_capture(true)
	c._unhandled_input(motion)
	_check(absf(c.get_look_yaw() + 100.0 * c.mouse_sensitivity) < 1e-5,
		"a captured one does, by relative x sensitivity (yaw %f)" % c.get_look_yaw())
	MouseCapture.want_capture(false)
	c.set_look(0.0, 0.0)

	# --- client_pos comes from the body ---------------------------------------------------
	c.entity.position = Vector3(3.0, 1.0, -2.0)
	var posed: InputFrame = c.sample()
	_check(posed.client_pos.is_equal_approx(Vector3(3.0, 1.0, -2.0)),
		"client_pos is the body position (got %s)" % posed.client_pos)

	# --- wire order matches the Rust struct -----------------------------------------------
	# to_reducer_args feeds BSATN positionally; a field out of order silently corrupts input.
	var args: Array = posed.to_reducer_args()
	_check(args.size() == 14, "to_reducer_args has 14 fields (got %d)" % args.size())
	_check(args[12] is bool and args[13] is bool,
		"the slow-walk modifier and then the aim close the frame, matching sim.rs")
	_check(args[9] is int and args[10] is int and args[11] is bool,
		"epoch, move_state, dash close the frame, matching sim.rs")
	_check(args[0] == posed.seq and args[1] == posed.client_tick,
		"args start with seq, client_tick")
	_check(args[4] == posed.look_yaw and args[5] == posed.look_pitch,
		"look_yaw precedes look_pitch, matching sim.rs")
	_check(args[8] is Vector3, "client_pos is the ninth arg and a Vector3")

	c.entity.queue_free()
	c.queue_free()

	# --- a REMOTE entity must not sample ---------------------------------------------------
	var remote: LocalInputComponent = _make_input_component(false)
	_check(not remote.is_physics_processing(),
		"a remote entity's input component does not run physics processing")
	remote.entity.queue_free()
	remote.queue_free()


# --- Greybox scene integration (real level, real frames) --------------------------------
#
# Everything above this line is a unit test: objects wired by hand, `update_view()` called
# directly. This suite is the other kind — it loads the actual level, spawns the actual
# player.tscn through the actual EntitySpawner, and lets real physics frames elapse. It is
# what catches wiring that unit tests cannot see: a component that never gets processed, a
# body parented into nothing, a scene that will not instantiate at all.
#
# It is also the testbed the collision work will need. Phase 3 entities are passive — remote
# interpolation writes a transform directly, so walls are not exercised yet. Once Phase 4
# prediction or Task 13's sidecar drives a body with move_and_slide, this level already has
# the floor, walls and platform to run it into.

const GREYBOX_SCENE: String = "res://tests/levels/greybox.tscn"

# --- MouseCapture (the cursor policy) --------------------------------------------------

## Reported: "the mouse is not captured and can leave the window". Mouse look needs the cursor
## locked to the window; getting it back has to be possible; and two instances on one machine
## must not fight over it. That is a state machine, so it is tested as one.
##
## The POLICY runs headless. The EFFECT — writing Input.mouse_mode — is skipped when there is
## no display server, and the headless server reports MOUSE_MODE_VISIBLE whatever you set it
## to, so `_last_applied_mode` is what a test can actually check.
func _run_mouse_capture_tests() -> void:
	print("== MouseCapture ==")
	_check(_autoload("MouseCapture") != null, "MouseCapture is registered as an autoload")

	var log: Array[bool] = []
	var cb := func(c: bool) -> void: log.append(c)
	MouseCapture.capture_changed.connect(cb)

	# A known starting point: no player, focused, nothing released.
	MouseCapture.want_capture(false)
	MouseCapture._set_focused(true)
	MouseCapture.recapture()
	log.clear()
	_check(not MouseCapture.is_captured(), "the cursor is free until gameplay asks for it")

	# (a) a local player asking is what captures it.
	MouseCapture.want_capture(true)
	_check(MouseCapture.is_captured() and log == [true],
		"a local player with mouse look captures the cursor")
	MouseCapture.want_capture(true)
	_check(log == [true], "asking twice announces once, so UI does not flicker")

	# (b) Escape gives it back, and it STAYS back.
	MouseCapture.release()
	_check(not MouseCapture.is_captured() and log == [true, false], "Escape frees the cursor")
	_check(MouseCapture.released_by_player(),
		"and the HUD can tell that the player did it deliberately")
	MouseCapture._set_focused(false)
	MouseCapture._set_focused(true)
	_check(not MouseCapture.is_captured(),
		"alt-tabbing away and back does not silently re-grab a cursor the player asked for")

	# (c) a click inside the window takes it back.
	MouseCapture.recapture()
	_check(MouseCapture.is_captured() and log.size() == 3 and log[2],
		"clicking in the window recaptures (%s)" % str(log))

	# (d) TWO INSTANCES ON ONE MACHINE. Losing focus has to release, or the other window can
	# never be clicked into — which is how this project is played and tested.
	MouseCapture._set_focused(false)
	_check(not MouseCapture.is_captured(), "losing focus releases the cursor for the other instance")
	MouseCapture._set_focused(true)
	_check(MouseCapture.is_captured(),
		"coming back takes it again, because the player never pressed Escape")

	# (e) the player going away always hands it back: a disconnect must not strand the cursor.
	MouseCapture.want_capture(false)
	_check(not MouseCapture.is_captured() and not MouseCapture.is_wanted(),
		"a despawned player releases the cursor")
	MouseCapture.release()
	MouseCapture.want_capture(true)
	_check(MouseCapture.is_captured(),
		"and a fresh player starts captured even if the last one ended released")

	# (f) THE GUARD on the effect. Negative-tested: with the guard lifted the same transitions
	# DO write a mode, so that check is the only thing keeping a headless run from taking the
	# developer's cursor.
	MouseCapture.want_capture(false)
	MouseCapture._last_applied_mode = -1
	MouseCapture.want_capture(true)
	MouseCapture.want_capture(false)
	_check(MouseCapture._last_applied_mode == -1,
		"with no display server the cursor mode is never written")
	MouseCapture._touch_display = true
	MouseCapture.want_capture(true)
	_check(MouseCapture._last_applied_mode == Input.MOUSE_MODE_CAPTURED,
		"with one, it is (mode %d)" % MouseCapture._last_applied_mode)
	MouseCapture.want_capture(false)
	_check(MouseCapture._last_applied_mode == Input.MOUSE_MODE_VISIBLE,
		"and released again on the way out")
	MouseCapture._touch_display = false
	MouseCapture._last_applied_mode = -1
	MouseCapture.capture_changed.disconnect(cb)


# --- the connect screen ---------------------------------------------------------------

## THE FRONT DOOR. A friend who types an address wrong, or whose host forgot the firewall, meets
## this code first, and nothing else in the suite would notice it misbehaving: every harness
## connects headless and never sees it. What is checked here is what can be checked without a
## server — the address rules, the per-identity profiles, the greeting rule, the screen's own
## states, and that a menu's buttons can be clicked at all. `tests/connect_playtest.sh` drives the
## same screen against a live module.
func _run_connect_tests() -> void:
	print("== connect screen ==")

	# --- addresses: what a player types, and what is dialled -------------------------------
	var cases: Array = [
		["192.168.1.20", "http://192.168.1.20:3000"],
		["  192.168.1.20  ", "http://192.168.1.20:3000"],
		["192.168.1.20:4000", "http://192.168.1.20:4000"],
		["localhost", "http://localhost:3000"],
		["myhost.example", "http://myhost.example:3000"],
		["http://127.0.0.1:3000", "http://127.0.0.1:3000"],
		["http://127.0.0.1:3000/", "http://127.0.0.1:3000"],
		["https://db.example.com", "https://db.example.com"],
		["HTTP://Host:3000", "http://Host:3000"],
		["ws://host:3000", "http://host:3000"],
		["wss://host", "https://host"],
		["[::1]:3000", "http://[::1]:3000"],
		["[::1]", "http://[::1]:3000"],
		["", ""],
		["   ", ""],
		["ftp://host", ""],
		["host:abc", ""],
		["host:0", ""],
		["host:70000", ""],
		["::1", ""],
		["my host", ""],
		["http://host:3000/v1/database", ""],
		["user@host", ""],
		["[::1", ""],
	]
	var bad: Array[String] = []
	for c: Array in cases:
		var got: String = ConnectSettings.normalize_host(String(c[0]))
		if got != String(c[1]):
			bad.append("\"%s\" -> \"%s\" (want \"%s\")" % [c[0], got, c[1]])
	_check(bad.is_empty(), "every address normalises as documented: %s" % ", ".join(bad))

	# --- profiles: one per identity, and flags never write -----------------------------------
	ConnectSettings.use_profile("")
	_check(ConnectSettings.path() == "user://connect.cfg", "the default identity uses connect.cfg")
	ConnectSettings.use_profile("dev2")
	_check(ConnectSettings.path() == "user://connect_dev2.cfg",
		"editor slot 2 keeps its own file, next to its own identity token")
	# A process under a test suite never reads the player's profile (DECISIONS #179).
	var was_db: String = OS.get_environment("UMF_DB")
	OS.set_environment("UMF_DB", "umf-test")
	ConnectSettings.use_profile("dev1")
	var under_suite: String = ConnectSettings.path()
	ConnectSettings.use_profile("")
	var default_under_suite: String = ConnectSettings.path()
	if was_db.is_empty():
		OS.unset_environment("UMF_DB")
	else:
		OS.set_environment("UMF_DB", was_db)
	_check(under_suite == "user://connect_dev1.umf-test.cfg" and default_under_suite == "user://connect.umf-test.cfg",
		"under a test suite, editor slot 1's profile is the suite database's, not the player's (%s, %s)"
			% [under_suite, default_under_suite])
	for tag: String in ["unit_a", "unit_b"]:
		ConnectSettings.use_profile(tag)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ConnectSettings.path()))
	ConnectSettings.use_profile("unit_a")
	_check(ConnectSettings.host("http://fallback:3000") == "http://fallback:3000"
		and ConnectSettings.player_name() == "" and not ConnectSettings.auto_connect(),
		"a fresh profile falls back to the shipped defaults")
	ConnectSettings.save("http://10.0.0.5:3000", "Ailsa", true)
	ConnectSettings.use_profile("unit_b")
	ConnectSettings.save("http://10.0.0.9:3000", "Bram", false)
	ConnectSettings.use_profile("unit_a")
	_check(ConnectSettings.host("x") == "http://10.0.0.5:3000"
		and ConnectSettings.player_name() == "Ailsa" and ConnectSettings.auto_connect(),
		"a profile reads back what it saved")
	ConnectSettings.save_auto_connect(false)
	_check(ConnectSettings.host("x") == "http://10.0.0.5:3000"
		and ConnectSettings.player_name() == "Ailsa" and not ConnectSettings.auto_connect(),
		"ticking auto-connect off keeps the address and name")
	ConnectSettings.use_profile("unit_b")
	_check(ConnectSettings.player_name() == "Bram",
		"two instances on one machine remember two names (%s)" % ConnectSettings.player_name())
	for tag: String in ["unit_a", "unit_b"]:
		ConnectSettings.use_profile(tag)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ConnectSettings.path()))
	ConnectSettings.use_profile("")

	# --- who gets greeted ---------------------------------------------------------------------
	# (display, forced, --autoconnect, --host, saved auto) -> greet?
	var rules: Array = [
		[[true, false, false, false, false], true, "a player starting the game is asked where to"],
		[[false, false, false, false, false], false, "a headless process has nobody to ask"],
		[[false, true, false, false, false], true, "--connect-screen shows it even headless"],
		[[true, false, true, false, false], false, "--autoconnect skips the greeting"],
		[[true, false, false, true, false], false, "--host= skips the greeting"],
		[[true, false, false, false, true], false, "so does a ticked 'connect automatically'"],
		[[true, true, true, true, true], true, "and --connect-screen beats all of them"],
	]
	for r: Array in rules:
		var a: Array = r[0]
		_check(ConnectScreen.should_greet(a[0], a[1], a[2], a[3], a[4]) == bool(r[1]), String(r[2]))

	# --- the screen on its own ------------------------------------------------------------
	var screen: ConnectScreen = (load("res://foundation/ui/connect_screen.tscn") as PackedScene) \
		.instantiate() as ConnectScreen
	get_tree().root.add_child(screen)
	var asked: Array[Array] = []
	screen.connect_requested.connect(func(h: String, n: String, auto: bool) -> void:
		asked.append([h, n, auto]))
	_check(not screen.is_open() and not screen.visible,
		"the screen stays out of the way until someone opens it")
	screen.open("my host", "Ailsa", false)
	screen.submit()
	_check(asked.is_empty() and screen.is_open() and not screen.is_connecting(),
		"an address that cannot be one is refused on the form, not dialled")
	_check(screen.status_text().contains("not a server address"),
		"and the player is told why: \"%s\"" % screen.status_text())

	screen.open("127.0.0.1", "  Ailsa ", true)
	screen.submit()
	_check(asked.size() == 1 and asked[0] == ["http://127.0.0.1:3000", "Ailsa", true],
		"Connect hands boot the normalised address, the trimmed name and the tick: %s" % str(asked))
	_check(screen.is_connecting() and (screen.get_node("%Host") as LineEdit).text \
		== "http://127.0.0.1:3000",
		"the field shows the address as it was understood")
	_check(not (screen.get_node("%Host") as LineEdit).editable,
		"and cannot be edited while that address is being tried")

	# Cancel. The adapter is not connected here, so its terminal signal changes no state; the
	# screen still has to come back to the form rather than wait for a signal that will not come.
	(screen.get_node("%Connect") as Button).pressed.emit()
	_check(screen.is_open() and not screen.is_connecting() and screen.status_text() == "Cancelled.",
		"Cancel returns to the form and says so (\"%s\")" % screen.status_text())
	_check(SpaceTimeSync.last_disconnect_requested,
		"and the adapter records that this disconnect was asked for")

	# An address that never answers is given up on, with the address in the explanation.
	screen.first_connect_timeout_sec = 0.05
	screen.submit()
	for i: int in range(8):
		await get_tree().process_frame
	_check(screen.is_open() and not screen.is_connecting()
		and screen.status_text().contains("No answer from http://127.0.0.1:3000"),
		"an attempt that never answers is ended and explained: \"%s\"" % screen.status_text())
	_check(screen.status_text().contains("--listen-addr 0.0.0.0:3000"),
		"with the one thing a host most often forgets")

	# The session-ended messages: dropped versus left.
	screen._on_world_ready()
	_check(not screen.is_open(), "the world arriving puts the screen away")
	SpaceTimeSync.last_disconnect_requested = false
	screen._on_state(SpaceTimeSync.ConnectionState.DISCONNECTED)
	_check(screen.is_open() and screen.status_text().begins_with("Lost connection"),
		"a session that DROPPED brings the form back saying so: \"%s\"" % screen.status_text())
	screen._on_world_ready()
	SpaceTimeSync.last_disconnect_requested = true
	screen._on_state(SpaceTimeSync.ConnectionState.DISCONNECTED)
	_check(screen.is_open() and screen.status_text() == "Disconnected.",
		"one the player LEFT does not call it lost: \"%s\"" % screen.status_text())
	screen.queue_free()

	# --- a click on a menu is for the menu ----------------------------------------------------
	# MouseCapture sees every click before the GUI does. Before this, the first click with the
	# cursor free always recaptured it and was swallowed, so no menu button could be pressed.
	var layer := CanvasLayer.new()
	var button := Button.new()
	button.text = "Resume"
	button.position = Vector2(40.0, 40.0)
	button.size = Vector2(160.0, 40.0)
	layer.add_child(button)
	get_tree().root.add_child(layer)
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	MouseCapture.want_capture(true)
	MouseCapture.release()
	await get_tree().process_frame
	var vp: Viewport = get_viewport()
	# Headless never tracks hover (no display server sends mouse-enter), and a Button only takes
	# a MOUSE press while hovered. A window would send this notification as the pointer arrived;
	# everything after it is the real input path.
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_click(vp, Vector2(120.0, 60.0))
	await get_tree().process_frame
	_check(presses[0] == 1, "the click reaches the button (%d presses)" % presses[0])
	_check(not MouseCapture.is_captured(), "and does not take the cursor back")
	_click(vp, Vector2(900.0, 500.0))
	await get_tree().process_frame
	_check(MouseCapture.is_captured(), "a click on the world still does")
	_check(presses[0] == 1, "without pressing anything on the way")
	MouseCapture.want_capture(false)
	layer.queue_free()
	await get_tree().process_frame

	# --- FULLSCREEN: F11, Alt+Enter and the menu's button (the windowed half, where the mode really
	# changes, is tests/render_test.sh). Headless, there is no window to change: the keys are still
	# read, the button is greyed and says why, and nothing is asked of the display.
	var key: Callable = func(code: Key, alt: bool = false, pressed: bool = true, echo: bool = false) -> InputEventKey:
		var e := InputEventKey.new()
		e.keycode = code
		e.alt_pressed = alt
		e.pressed = pressed
		e.echo = echo
		return e
	_check(WindowMode.is_toggle_key(key.call(KEY_F11)) and WindowMode.is_toggle_key(key.call(KEY_ENTER, true))
			and WindowMode.is_toggle_key(key.call(KEY_KP_ENTER, true)),
		"F11 and Alt+Enter toggle fullscreen")
	_check(not WindowMode.is_toggle_key(key.call(KEY_ENTER)) and not WindowMode.is_toggle_key(key.call(KEY_F11, false, false))
			and not WindowMode.is_toggle_key(key.call(KEY_F11, false, true, true)) and not WindowMode.is_toggle_key(key.call(KEY_F10)),
		"and plain Enter, a key coming up, a held key repeating or F10 do not")
	_check(WindowMode.cannot() == WindowMode.NO_WINDOW and WindowMode.toggle() == WindowMode.NO_WINDOW,
		"a headless process says it has no window, and leaves the display alone")
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	await get_tree().process_frame
	var fs_button: Button = menu.get_node(^"%Fullscreen") as Button
	menu.call("_refresh_fullscreen")
	_check(fs_button != null and fs_button.disabled and fs_button.tooltip_text == WindowMode.NO_WINDOW
			and fs_button.text.contains("F11"),
		"the Escape menu offers Fullscreen (F11), greyed here with the reason: %s" % (fs_button.tooltip_text if fs_button != null else "-"))
	menu.queue_free()
	await get_tree().process_frame


## A real click: the pointer moves there first, which is what gives the GUI its hover.
func _click(vp: Viewport, at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	vp.push_input(move)
	for pressed: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = at
		b.global_position = at
		vp.push_input(b)


# --- aiming, and the key that casts ----------------------------------------------------

class FakeChallengeRow extends RefCounted:
	var id: int
	var entity_id: int
	var kind: int = 0
	var difficulty: float = 0.35
	var seed: int = 4242
	var issued_at_usec: int = 0
	var expires_at_usec: int = 0
	var payload: String = '{"kind":"fishing","spot":5102}'
	func _init(cid: int, eid: int) -> void:
		id = cid
		entity_id = eid


## Advance BOTH clocks. The camera rig places itself in `_process`, and a headless run can take
## several physics steps inside a single idle frame — awaiting `physics_frame` alone left the
## rig unplaced and this suite reading a camera still sitting at the player's origin.
func _tick_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame
		await get_tree().process_frame


## THE "I HAVE NEVER BEEN ABLE TO FISH" SUITE.
##
## Every reducer in the fishing loop was already covered — by tests that call `cast` directly.
## Between the player and that reducer sat three things no such test can see:
##
##   1. the cursor was never captured, so there was no looking around   (MouseCapture, above)
##   2. the interaction ray was cast `interaction_range` from the CAMERA, and in third person
##      the camera is on a 4.5 m boom BEHIND the player — the ray ended behind them, so the
##      crosshair could never be on anything
##   3. the interact key sent the foundation's generic `interact`, which issues a node
##      challenge that FishingComponent deliberately ignores; the press did nothing visible
##
## So this suite plays that part of the game: the real fisher scene, the real camera rig, the
## real fishing-spot scene, the real level, and the real key.
func _run_aim_tests() -> void:
	print("== aiming and the cast verb ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	if reg == null or spawner == null:
		_check(false, "autoloads present")
		return

	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	if packed == null:
		_check(false, "the level loads")
		return
	var level: Node3D = packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	var world_root: Node3D = level.get_node(^"WorldRoot") as Node3D

	# The definitions the GAME ships, not test doubles: if the shipped .tres is wrong, this
	# suite is wrong with it, which is the point.
	var fisher_def: EntityDefinition = load("res://game/fishing/fisher_definition.tres") as EntityDefinition
	var spot_def: EntityDefinition = load("res://game/fishing/spot_definition.tres") as EntityDefinition
	_check(fisher_def != null and spot_def != null, "the fishing entity definitions load")
	if fisher_def == null or spot_def == null or fisher_def.scene == null or spot_def.scene == null:
		level.queue_free()
		return
	_check(spot_def.kind == FishingComponent.SPOT_KIND,
		"a pond is entity kind %d — the RESOURCE_NODE the module spawns" % FishingComponent.SPOT_KIND)

	# THE POND, placed by hand: this suite is about where the ray goes, so the target holds
	# still. The spawn path itself is covered by the spawner and greybox suites.
	var spot: SpaceTimeEntity = spot_def.scene.instantiate() as SpaceTimeEntity
	world_root.add_child(spot)
	spot.entity_id = 5102     # after add_child: _ready() asserts the entity is not bound yet
	spot.definition = spot_def
	spot.global_position = Vector3(0.0, 0.0, -2.5)
	reg.register(spot.entity_id, spot)

	# THE PLAYER: the real fisher, through the real spawner, as the local authority.
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(fisher_def)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true
	var eid: int = 5101
	reg.local_entity_id = eid
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(me != null and me.is_local_authority, "the local fisher spawned and is ours")
	if me == null:
		reg.unregister(spot.entity_id)
		reg.local_entity_id = prev_local
		spawner._world_ready = prev_ready
		level.queue_free()
		return
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	var fishing: FishingComponent = me.find_component(FishingComponent) as FishingComponent
	var li: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	var cam: Camera3D = me.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
	_check(ic != null and fishing != null and li != null,
		"the fisher carries interaction, fishing and input components")
	_check(cam != null and cam.current, "the fisher's camera is live and current")
	if ic == null or fishing == null or li == null or cam == null:
		reg.unregister(spot.entity_id)
		reg.local_entity_id = prev_local
		spawner._world_ready = prev_ready
		level.queue_free()
		return

	# Nothing is connected here; keep the reducer log to the presses this suite makes.
	li.send_to_server = false
	li.set_look(0.0, 0.0)     # yaw 0 looks down -Z, straight at the pond
	await _tick_frames(15)    # the boom's follow smoothing needs a moment to settle
	var body: CharacterBody3D = me.body

	# (a) THE REGRESSION, stated as a measurement. The camera is further behind the player than
	# the whole interaction range, so a ray `interaction_range` long from the camera stops
	# BEHIND them — it cannot reach anything, at any distance. That was the shipped behaviour.
	var dir: Vector3 = -cam.global_transform.basis.z
	var setback: float = ic._camera_setback(cam.global_position, dir, body)
	_check(setback > ic.range_m(),
		("the third-person camera sits %.2f m behind the player, further than the %.2f m reach: "
		+ "a ray measured from the camera never even reaches the player")
		% [setback, ic.range_m()])

	# (b) with the boom accounted for, the pond 2.5 m away is the target.
	ic.scan()
	_check(ic.get_target() == spot.entity_id,
		"looking at a pond 2.5 m away targets it (got %d)" % ic.get_target())
	_check(ic.get_target_kind() == FishingComponent.SPOT_KIND,
		"and the client knows it is a pond, not another player")
	_check(absf(ic.target_distance() - 2.5) < 0.2,
		"range is measured from the PLAYER (%.2f m), the way the module measures it"
		% ic.target_distance())

	# (c) in view but out of reach is NOT a target: a prompt must not promise something the
	# module's 3 m check will refuse.
	spot.global_position = Vector3(0.0, 0.0, -3.2)
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET,
		"a pond 3.2 m away is plainly in view but out of reach, so it is not a target")
	spot.global_position = Vector3(0.0, 0.0, -2.9)
	ic.scan()
	_check(ic.get_target() == spot.entity_id, "2.9 m, just inside the server's 3 m, is")

	# (d) FIRST PERSON is a different .tres and nothing else. Same ray, same reach.
	var rig: CameraRig = me.get_node_or_null(^"CameraRig") as CameraRig
	if rig != null:
		var prev_cfg: CameraRigConfig = rig.config
		rig.config = load("res://foundation/camera/first_person.tres") as CameraRigConfig
		await _tick_frames(3)
		var fp_setback: float = ic._camera_setback(
			cam.global_position, -cam.global_transform.basis.z, body)
		_check(fp_setback < 0.5,
			"in first person the camera IS the player, so nothing is added (%.2f m)" % fp_setback)
		ic.scan()
		_check(ic.get_target() == spot.entity_id, "and the same pond is still the target")
		rig.config = prev_cfg
		await _tick_frames(3)

	# (e) THE KEY IS THE FOUNDATION'S AGAIN. Fishing used to claim E on a pond and send `cast`;
	# a cast is now AIMED — the cast button, at a point on the water (the lakeside suite plays
	# it) — so the genre claims no key, and E on anything is the foundation's `interact`.
	var sent: Array[String] = []
	var sent_reqs: Array[ReducerRequest] = []
	var scb := func(req: ReducerRequest) -> void:
		# The equip state's reports are the lakeside suite's (DECISIONS #160).
		if req.reducer_name != &"submit_input" and req.reducer_name != &"set_equip_state":
			sent.append(String(req.reducer_name))
			sent_reqs.append(req)
	SpaceTimeSync.reducer_settled.connect(scb)
	var pressed: Array[int] = []
	var pcb := func(id: int) -> void: pressed.append(id)
	ic.interact_requested.connect(pcb)
	ic.scan()
	ic.press_interact()
	_check(sent == ["interact"],
		"E on a pond is the foundation's verb now, not a cast (sent %s)" % str(sent))
	_check(pressed == [spot.entity_id], "and it is announced for presentation (%s)" % str(pressed))

	# (f) and the same for anything else in reach: another player is a target like any node.
	sent.clear()
	spot.global_position = Vector3(0.0, 0.0, -20.0)
	var mate: SpaceTimeEntity = fisher_def.scene.instantiate() as SpaceTimeEntity
	world_root.add_child(mate)
	mate.entity_id = 5103
	mate.definition = fisher_def
	mate.global_position = Vector3(0.0, 0.0, -2.0)
	reg.register(mate.entity_id, mate)
	await _tick_frames(2)
	ic.scan()
	_check(ic.get_target() == mate.entity_id,
		"another player standing in front of us is a target (got %d)" % ic.get_target())
	_check(ic.get_target_kind() == 0, "of kind PLAYER")
	pressed.clear()
	ic.press_interact()
	_check(sent == ["interact"], "E on a player is the foundation's verb (%s)" % str(sent))
	_check(pressed == [mate.entity_id],
		"and is announced whoever handles it, so the reach animation does not depend on the verb")

	# (g) THE LINE IS OUT when our fishing challenge carries its roll — not before, and not for a
	# challenge of any other kind. The module issues the challenge and writes the payload in one
	# transaction, but the row can be seen between the two on a replay.
	var fish_row := FakeChallengeRow.new(7, eid)
	fish_row.kind = FishingComponent.KIND_FISH
	fish_row.payload = ""
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"challenge", null, fish_row))
	_check(not fishing.has_line_out(), "a fishing challenge with no roll in it yet is not a line")
	var node_row := FakeChallengeRow.new(8, eid)
	node_row.kind = 0
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"challenge", null, node_row))
	_check(not fishing.has_line_out(), "and a challenge of another kind is somebody else's business")
	var rolled := FakeChallengeRow.new(7, eid)
	rolled.kind = FishingComponent.KIND_FISH
	rolled.payload = '{"kind":"fishing","spot":"dock_end","catch":"bluegill","kg":0.3,"bite":3.5,"window_mult":1.0,"deadlift":false,"x":0.0,"z":10.0,"range":14.0}'
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"challenge", fish_row, rolled))
	_check(fishing.has_line_out() and str(fishing.cast_info().get("catch", "")) == "bluegill"
			and int(fishing.cast_info().get("id", -1)) == 7,
		"the roll arriving is the line in the water, with what is on it (%s)" % str(fishing.cast_info()))
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"challenge", rolled, null))
	_check(not fishing.has_line_out(), "and the challenge closing takes it out again")

	# (h) THE HOOK-SET STARTS THE FIGHT, built from exactly what the cast recorded — the range in
	# centimetres, the seed, the gear AT THE CAST — because that is what the module will replay.
	# The bite's timing is the playtest's business; here the rig is put at the strike directly.
	var hooked := FakeChallengeRow.new(11, eid)
	hooked.kind = FishingComponent.KIND_FISH
	hooked.payload = '{"kind":"fishing","spot":"dock_end","catch":"largemouth_bass","kg":2.3,"bite":3.0,"window_mult":1.0,"deadlift":false,"x":0.0,"z":10.0,"range":14.37,"range_cm":1437,"fight_seed":4242,"rod":2,"reel":1,"line":3}'
	fishing.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"challenge", null, hooked))
	fishing._rig = FishingComponent.Rig.STRIKE
	fishing._bite_msec = Time.get_ticks_msec() - 150
	fishing._window_sec = FishingData.hookset_window(1.0)
	var fought_ends: Array[int] = []
	var fcb := func(st: int) -> void: fought_ends.append(st)
	fishing.fight_ended.connect(fcb)
	sent.clear()
	fishing.press_cast()
	var fs: FightSim = fishing.fight()
	_check(fishing.rig() == FishingComponent.Rig.FIGHTING and fs != null,
		"a hook-set that grades starts the fight (%s)" % FishingComponent.Rig.keys()[fishing.rig()])
	if fs != null:
		var bass: FightSim.Profile = FightSim.profile_of("largemouth_bass")
		# THE CAST IS THE FIGHT LENGTH (FfC): 0.9 of the range inside 10..40 m, times the catch's
		# share of it. The HUD says the WORLD's metres, the ones the aim showed.
		_check(fs.cast_range_m == 14.37
				and fs.start_distance == FightSim.fight_length(fs.params, 14.37) * bass.distance_scale
				and is_equal_approx(FightSim.fight_length(fs.params, 14.37), 14.37 * 0.9),
			"hooked 14.37 m out, from the payload's whole centimetres (a %.3f m fight)" % fs.start_distance)
		_check(is_equal_approx(fs.line_out_m(), 14.37),
			"and the line out reads 14.37 m, as the aim did — not the fight's own %.2f" % fs.distance)
		var base_p: FightSim.Params = FightSim.base_params()
		_check(fs.params.pump_metres == base_p.pump_metres * float(FishingData.gear("rod", 2)["reel_power"])
				and fs.params.snap_tension == float(FishingData.gear("line", 3)["tension_ceiling"]) / 100.0
				and fs.params.crank_rate == base_p.crank_rate * float(FishingData.gear("reel", 1)["reel_speed"]),
			"with the gear the CAST recorded: rod 2's lift, reel 1's crank, line 3's ceiling")
		_check(fs.params.perfect_set and not fs.is_armed(),
			"from a PERFECT set, and with the setting click still held, not yet a pump")
		await _tick_frames(2)
		_check(is_equal_approx(li.look_scale, FishingComponent.FIGHT_LOOK_SCALE),
			"the mouse is the reel now: looking around is damped (%.2f)" % li.look_scale)
		# THE ANGLER IN THE FIGHT (DECISIONS #144), read off the real feedback, driver and rod. The
		# fight is held still (its physics tick paused) so a state set here is the state shown.
		var feedback: FishingFeedback = me.find_component(FishingFeedback) as FishingFeedback
		var anim: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
		var rod: FishingRod = feedback.fx().rod() if feedback != null and feedback.fx() != null else null
		fishing.set_physics_process(false)
		# Loaded to the top of the catch's band — "too far" — the rod is all the way up.
		fs.load = fs.band_hi
		fs.tension = fs.params.snap_tension * 0.9
		await _tick_frames(4)
		_check(feedback != null and anim != null and anim.pose_clip() == &"extra/Fish_Reel"
				and absf(feedback.heave_shown() - FishingFeedback.HEAVE_TOP) < 0.01,
			"loading the rod to the top of the catch's band heaves the angler all the way: the heave clip, held %.2f of the way through"
				% (feedback.heave_shown() if feedback != null else -1.0))
		_check(rod != null and rod.bend() >= 0.89,
			"the rod bends with the line (%.2f)" % (rod.bend() if rod != null else -1.0))
		_check(feedback.fx().line_tint() == FishingFx.TELL_OVER,
			"and the line shows it is close to snapping (%s)" % feedback.fx().line_tint())
		# A LIGHT catch shows a pump as plainly. A tankard's sweet spot is under a fifth of the rod's
		# load — the fishing playtest hooked one and the heave barely moved (0.15 of the clip) —
		# so the heave and the bend follow the load against ITS band. Its line, barely strained,
		# stays its own colour: that warning is absolute.
		var bass_band: Vector2 = Vector2(fs.band_lo, fs.band_hi)
		var tankard: FightSim.Profile = FightSim.profile_of("tankard")
		fs.band_lo = maxf(tankard.band_centre - tankard.band_width * 0.5, 0.0)
		fs.band_hi = tankard.band_centre + tankard.band_width * 0.5
		fs.load = (fs.band_lo + fs.band_hi) * 0.5
		fs.tension = fs.params.snap_tension * 0.17
		await _tick_frames(30)
		_check(rod != null and fs.in_perfect() and fs.load < 0.2 * fs.params.overload_limit
				and feedback.heave_shown() > 0.75 * FishingFeedback.HEAVE_TOP and rod.bend() > 0.6,
			"a tankard in its sweet spot (%.2f of the rod's load) heaves the rod %.2f of the way up and bends it %.2f"
				% [fs.load / fs.params.overload_limit, feedback.heave_shown() / FishingFeedback.HEAVE_TOP,
					rod.bend() if rod != null else -1.0])
		_check(feedback.fx().line_tint() == FishingFx.LINE_COLOR, "and its line, barely strained, is its own colour")
		fs.band_lo = bass_band.x
		fs.band_hi = bass_band.y
		# LET GO AND WIND. The rod comes back down at the heave clip's own pace, played backwards
		# (#156). It came down in a fixed 0.35 s once: a release from the sweet spot ran 1.7 s of
		# the clip back at five times its speed. Luke: "after I hit the sweet spot it plays the
		# heave like 3x speed and looks strange". Paced against the real clock, frame by frame.
		var clip_s: float = feedback.heave_clip_seconds()
		var top: float = feedback.heave_shown()
		fs.load = 0.0
		fs.tension = fs.params.snap_tension * 0.3
		fishing._crank = 1.0
		var fastest: float = 0.0
		var t_prev: int = Time.get_ticks_usec()
		var h_prev: float = top
		var dropping_usec: int = 0
		while feedback.heave_shown() > 0.0 and dropping_usec < 4000000:
			await _tick_frames(1)
			var t_now: int = Time.get_ticks_usec()
			var h_now: float = feedback.heave_shown()
			# Clip seconds travelled per real second, over windows of 50 ms or more (headless, several
			# frames can pass between two looks, so one frame's figure jitters): 1 is as animated.
			if t_now - t_prev >= 50000 or h_now <= 0.0:
				if h_now > 0.0:
					fastest = maxf(fastest, (h_prev - h_now) * clip_s / maxf(float(t_now - t_prev) / 1e6, 1e-6))
				dropping_usec += t_now - t_prev
				t_prev = t_now
				h_prev = h_now
		# The whole drop's pace (one frame's own timing jitters by a few per cent), and no one frame
		# far past it.
		var pace: float = top * clip_s / maxf(float(dropping_usec) / 1e6, 1e-6)
		print("   let go from %.2f of the heave clip (%.2f s long): down in %.2f s, %.2f times the clip's pace (%.2f in the fastest frame)"
			% [top, clip_s, float(dropping_usec) / 1e6, pace, fastest])
		_check(clip_s > 1.0 and top > 0.5 and pace > 0.85 * FishingFeedback.HEAVE_DROP_PACE
				and pace <= 1.1 * FishingFeedback.HEAVE_DROP_PACE and fastest < 1.5 * FishingFeedback.HEAVE_DROP_PACE,
			"let go from the sweet spot, the rod comes back down at the clip's own pace, backwards: %.2f times it (the old fixed drop ran it at about five)" % pace)
		_check(feedback.heave_shown() < 0.01 and feedback.hand_on_reel() > 0.99 and rod.hand_on_reel() > 0.99,
			"and winding, it comes all the way down (%.2f) and the left hand takes the reel (%.2f)"
				% [feedback.heave_shown(), feedback.hand_on_reel()])
		_check(feedback.fx().line_tint() == FishingFx.LINE_COLOR, "and the line is its own colour again")
		fishing._crank = 0.0
		fs.load = fs.params.overload_limit * 0.5
		await _tick_frames(30)
		# THE LEFT HAND STAYS ON THE REEL (DECISIONS #161). Luke's picture: the rod loaded ("hold the
		# left button to bend the rod") and the left hand off the reel, where the heave clip has it.
		_check(feedback.heave_shown() > 0.1 and rod.hand_on_reel() > 0.99,
			"not winding, the rod loaded and heaved (%.2f), the left hand stays on the reel (%.2f)"
				% [feedback.heave_shown(), rod.hand_on_reel()])
		# AND THE ARM REACHING IT STAYS OUT OF HER BODY (DECISIONS #162). Luke: "the arm is inside the
		# body when reeling". Measured as drawn (during the skeleton's update, the IK applied): her
		# left elbow and forearm against her torso, heaved and winding.
		var arm_skel: Skeleton3D = rod.get_parent().get_parent() as Skeleton3D
		var arm_air: Array[float] = [INF, INF]
		var arm_where: Array[String] = ["", ""]
		var phase: Array[int] = [0]
		var watch_arm := func() -> void:
			if rod.hand_on_reel() < 0.99:
				return
			var torso: Array[Array] = []
			for part: Array in BodyClearance.posed(arm_skel):
				if String(part[0]) == "torso":
					torso.append(part)
			var elbow: Vector3 = BodyClearance.bone_at(arm_skel, &"lowerarm_l")
			var wrist: Vector3 = BodyClearance.bone_at(arm_skel, &"hand_l")
			var air: float = float(BodyClearance.measure_posed(torso, elbow, wrist, ARM_RADIUS)["air"])
			if air < arm_air[phase[0]]:
				arm_air[phase[0]] = air
				arm_where[phase[0]] = "elbow %s, wrist %s" % [arm_skel.global_transform.affine_inverse() * elbow,
					arm_skel.global_transform.affine_inverse() * wrist]
		arm_skel.skeleton_updated.connect(watch_arm)
		await _tick_frames(30)
		phase[0] = 1
		fs.load = 0.0
		fishing._crank = 1.0
		await _tick_frames(40)
		fishing._crank = 0.0
		arm_skel.skeleton_updated.disconnect(watch_arm)
		print("   her left forearm off her torso: %.1f cm heaved (%s), %.1f cm winding (%s)"
			% [arm_air[0] * 100.0, arm_where[0], arm_air[1] * 100.0, arm_where[1]])
		_check(arm_air[0] >= 0.0 and arm_air[1] >= 0.0,
			"her left arm on the reel stays out of her body: %.1f cm clear heaved, %.1f cm winding"
				% [arm_air[0] * 100.0, arm_air[1] * 100.0])
		fs.load = 0.0
		# THE GAUGE reads the same fight.
		var gauge := ReelGauge.new()
		add_child(gauge)
		fs.load = fs.params.overload_limit * 0.5
		gauge.show_fight(fs, 1.0, 0.016)
		_check(is_equal_approx(gauge.rod_fill(), 0.5) and is_equal_approx(gauge.rim_fill(), 0.3)
				and gauge.fish_word() == "fighting",
			"the reel gauge's rod is the load, its rim the tension, and it says what the fish is doing")
		fs.behavior = FightSim.Behavior.RESTING
		_check(gauge.fish_word() == "resting" and is_equal_approx(fs.reel_pays(), fs.params.rest_reel_fraction),
			"a resting fish: the gauge says so, and winding pays the rest share (%.2f)" % fs.reel_pays())
		fs.behavior = FightSim.Behavior.RUNNING
		_check(gauge.fish_word() == "running" and fs.reel_pays() == 0.0, "a running one: winding pays nothing")
		fs.behavior = FightSim.Behavior.HOLDING
		fs.load = 0.0
		# The line won pops off the reel. Wound in steadily and fast — 3 m/s, more than a resting
		# fish gives — the labels never land on top of each other: a young one counts on instead.
		gauge.reset()
		var saved_distance: float = fs.distance
		var metres_per_frame: float = 3.0 / 60.0
		var closest: float = INF
		var most: int = 0
		var biggest: float = 0.0
		for i: int in range(180):
			fs.distance -= metres_per_frame * fs.start_distance / fs.cast_range_m
			gauge.show_fight(fs, 1.0, 1.0 / 60.0)
			var risen: PackedFloat32Array = gauge.pops_risen()
			most = maxi(most, risen.size())
			for k: int in range(1, risen.size()):
				closest = minf(closest, risen[k - 1] - risen[k])
			for t: String in gauge.pops_text():
				biggest = maxf(biggest, float(t.trim_prefix("+").trim_suffix(" m")))
		_check(most >= 2 and closest >= float(ReelGauge.POP_FONT),
			"winding steadily pops the line won off the reel, never one label over another (%d at once, %.0f px apart at the closest)"
				% [most, closest])
		_check(biggest > ReelGauge.POP_EVERY_M + 0.05,
			"a label still rising counts the next metres up instead (+%.1f m)" % biggest)
		fs.distance = saved_distance
		gauge.queue_free()
		fishing.set_physics_process(true)
		# The line goes: what is submitted is the reaction and the whole log, and the rig is free.
		fs.state = FightSim.State.SNAPPED
		fishing._log.append(PackedInt32Array([30, 1, 0]))
		fishing._finish_fight()
		var submit: ReducerRequest = null
		for r: ReducerRequest in sent_reqs:
			if r.reducer_name == &"submit_challenge_result":
				submit = r
		var args: Array = submit.args[1] as Array if submit != null else []
		_check(submit != null and int(submit.args[0]) == 11 and args.size() == 1 + 1 + fishing._log.size() * 3
				and absf(float(args[0]) - 0.15) < 0.05 and int(args[1]) == fishing._log.size(),
			"a finished fight submits [reaction, n, (ticks, flags, crank) x n] for challenge 11 (%s)"
				% (str(args.slice(0, 5)) if submit != null else "nothing sent"))
		_check(fought_ends == [FightSim.State.SNAPPED] and fishing.rig() == FishingComponent.Rig.READY
				and not fishing.has_line_out(), "and a snapped line frees the rod at once")
		await _tick_frames(30)
		_check(rod.hand_on_reel() < 0.01, "and once the fight is over the left hand lets go of the reel (%.2f)"
			% rod.hand_on_reel())
		# WAITING FOR A BITE, the same arms (DECISIONS #162). Luke: "the heave and winding was fixed
		# but now the fishing waiting is still broken... until I hook a fish". A line out with nothing
		# on it holds the waiting pose: both forearms measured against her torso, as drawn.
		fishing._line_out = true
		# After the snap's own clip (an action has both hands; the wait is the pose under it).
		var clip_wait: int = 0
		while anim.action_playing() and clip_wait < 400:
			await _tick_frames(1)
			clip_wait += 1
		await _tick_frames(40)
		var wait_skel: Skeleton3D = rod.get_parent().get_parent() as Skeleton3D
		# On the rod, not in the air in front of her: the left wrist where it is when the fingers hold
		# the reel's knob (the grip's off_hand_wrist), read as drawn.
		var wrist_off: Array[float] = [INF]
		var watch_wrist := func() -> void:
			var want: Vector3 = rod.knob_position() + rod.global_transform.basis * rod.grip.off_hand_wrist
			wrist_off[0] = minf(wrist_off[0], BodyClearance.bone_at(wait_skel, &"hand_l").distance_to(want))
		wait_skel.skeleton_updated.connect(watch_wrist)
		await _tick_frames(10)
		wait_skel.skeleton_updated.disconnect(watch_wrist)
		print("   waiting, her left wrist is %.1f cm from where it holds the reel" % (wrist_off[0] * 100.0))
		_check(wrist_off[0] < 0.03 and rod.hand_on_reel() > 0.99,
			"waiting for a bite, her left hand holds the rod at the reel (%.1f cm off), not the air in front of her"
				% (wrist_off[0] * 100.0))
		var wait_air: Dictionary = await _forearms_off_torso(wait_skel, 30)
		print("   waiting, her forearms off her torso: left %.1f cm, right %.1f cm (%s)"
			% [float(wait_air["left"]) * 100.0, float(wait_air["right"]) * 100.0, anim.pose_clip()])
		_check(anim.pose_clip() == &"extra/Fish_Cast_Idle" and float(wait_air["left"]) >= 0.0
				and float(wait_air["right"]) >= 0.0,
			"waiting for a bite, her arms stay out of her body: left %.1f cm clear, right %.1f cm"
				% [float(wait_air["left"]) * 100.0, float(wait_air["right"]) * 100.0])
		fishing._line_out = false
		await _tick_frames(10)
	fishing.fight_ended.disconnect(fcb)

	# --- teardown: leave no camera, no entity and no level behind ------------------------
	SpaceTimeSync.reducer_settled.disconnect(scb)
	ic.interact_requested.disconnect(pcb)
	reg.unregister(spot.entity_id)
	reg.unregister(mate.entity_id)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	spot.queue_free()
	mate.queue_free()
	level.queue_free()
	await get_tree().process_frame


# --- animation: the set, the generated tree, and a real rig ------------------------------

const FISHER_SET: String = "res://game/anim/fisher.tres"
const FISHING_NET_CONFIG: String = "res://game/fishing/fishing_net_config.tres"
const FISHER_DEF: String = "res://game/fishing/fisher_definition.tres"


## THE CONTRACT, not the content. A character says "I am running"; this suite proves that turns
## into the right clip, that a character missing a clip still animates, and that a set naming a
## clip its library does not have is caught here rather than on the frame the player dies.
## The wheel zoom. Presentation, but a boom that ignores its limits puts the camera inside the
## character or out in the next room, and nothing else in the suite ever moves it.
func _run_camera_tests() -> void:
	print("== CameraRig zoom ==")
	var cfg := CameraRigConfig.new()
	cfg.first_person = false
	cfg.boom_length = 4.0
	cfg.boom_min = 1.5
	cfg.boom_max = 7.0
	cfg.zoom_step = 0.5
	cfg.zoom_smoothing = 0.0   # snap, so a test does not have to wait out an ease
	var rig := CameraRig.new()
	rig.config = cfg
	get_tree().root.add_child(rig)
	_check(is_equal_approx(rig._zoom(0.016), 4.0), "the boom starts where the preset put it")

	rig._input = LocalInputComponent.new()   # the rig only zooms for the entity that owns it
	var wheel_in := InputEventAction.new()
	wheel_in.action = &"camera_zoom_in"
	wheel_in.pressed = true
	for i: int in range(3):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), 2.5),
		"three notches in pull it to 2.5 m (%.2f)" % rig._zoom(0.016))
	for i: int in range(10):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), cfg.boom_min),
		"and it stops at boom_min rather than ending up inside the character (%.2f)"
			% rig._zoom(0.016))

	var wheel_out := InputEventAction.new()
	wheel_out.action = &"camera_zoom_out"
	wheel_out.pressed = true
	for i: int in range(40):
		rig._unhandled_input(wheel_out)
	_check(is_equal_approx(rig._zoom(0.016), cfg.boom_max),
		"pushing out stops at boom_max (%.2f)" % rig._zoom(0.016))
	# While a genre has the mouse (a reel being wound: look damped), the wheel is not the camera's.
	rig._input.look_scale = 0.1
	var held_at: float = rig._zoom(0.016)
	for i: int in range(3):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), held_at),
		"with the mouse lent to the game (look_scale 0.1) the wheel does not zoom (%.2f)" % rig._zoom(0.016))
	rig._input.look_scale = 1.0
	rig._unhandled_input(wheel_in)
	_check(rig._zoom(0.016) < held_at, "and it zooms again once the mouse is the camera's")
	cfg.first_person = true
	var before: float = rig._zoom(0.016)
	rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), before), "a first-person rig has no boom to zoom")
	rig._input.free()
	rig.queue_free()


func _run_animation_tests() -> void:
	print("== animation: sets and the generated tree ==")
	var set: AnimationSet = load(FISHER_SET) as AnimationSet
	_check(set != null, "the fisher's AnimationSet loads")
	if set == null:
		return
	_check_upper_body_filter(set)

	# (a) the SHIPPED set is complete. Regenerating it against a different library is a one-line
	# tool run, and this is what says whether the result can still drive a character.
	_check(set.missing_required().is_empty(),
		"it names every clip the driver needs (missing %s)" % str(set.missing_required()))
	_check(set.dangling_clips().is_empty(),
		"and every clip it names is really in its libraries (dangling %s)" % str(set.dangling_clips()))
	_check(set.libraries.size() == 2 and set.libraries.has(&"") and set.libraries.has(&"extra"),
		"it carries both libraries (%s)" % str(set.libraries.keys()))
	_check(set.anim_name(AnimationSet.IDLE) == &"Idle"
		and set.anim_name(AnimationSet.RUN) == &"Jog_Fwd"
		and set.anim_name(AnimationSet.SPRINT) == &"Sprint",
		"one clip per gait: %s / %s / %s / %s" % [set.anim_name(AnimationSet.IDLE),
			set.anim_name(AnimationSet.WALK), set.anim_name(AnimationSet.RUN),
			set.anim_name(AnimationSet.SPRINT)])

	# EACH CLIP IS PLAYED AT THE SPEED THE GAME MOVES AT. The generator measures what a clip was
	# authored to travel at (off its planted foot) and scales it to this game's gait; a character
	# at 5 m/s playing a clip authored for 1 m/s is the skating that reads as floaty.
	var unscaled: Array[String] = []
	for semantic: StringName in [AnimationSet.WALK, AnimationSet.RUN, AnimationSet.SPRINT,
			AnimationSet.WALK_BACK, AnimationSet.WALK_LEFT, AnimationSet.RUN_BACK,
			AnimationSet.RUN_LEFT]:
		var ref: AnimationClipRef = set.clip(semantic)
		if ref == null or is_equal_approx(ref.speed_scale, 1.0):
			unscaled.append(String(semantic))
		_check(ref != null and ref.speed_scale > 0.25 and ref.speed_scale < 3.0,
			"%s plays at a sane rate (x%.2f)" % [semantic, ref.speed_scale if ref != null else 0.0])
	_check(unscaled.is_empty(),
		"every locomotion clip was fitted to a gait, none left at its authored speed (%s)"
			% str(unscaled))

	# AND EVERY LOOPING CLIP STILL LOOPS. Speed-scaling a clip means playing it through a custom
	# timeline — the only thing a state-machine state understands — and turning that on hands the
	# clip's loop over to the NODE's own `loop_mode`, which defaults to "no loop". Every locomotion
	# clip is scaled, so every one of them played a single cycle and froze on a last frame that is
	# indistinguishable from its first, while the character kept sliding (DECISIONS #103).
	var built: AnimationTree = AnimationTreeBuilder.build(set)
	_check(built != null, "the fisher's set builds a tree")
	if built != null:
		var faults: Array[String] = _loop_faults(built)
		_check(faults.is_empty(), "a strafing tree loops what must loop and ends what must end: %s"
			% str(faults))
		# The forward-only graph is a different node with the same trap in it.
		var line_set: AnimationSet = set.duplicate() as AnimationSet
		line_set.strafe = false
		var line_tree: AnimationTree = AnimationTreeBuilder.build(line_set)
		var line_faults: Array[String] = _loop_faults(line_tree)
		_check(line_tree != null and not AnimationTreeBuilder.is_strafing(line_set)
			and line_faults.is_empty(),
			"and so does a forward-only one, which is a different node: %s" % str(line_faults))
		# An AnimationTree is a Node. These two were never parented, so nothing else will free them
		# and the run would end holding every clip they reference.
		built.free()
		if line_tree != null:
			line_tree.free()

	# A NODE RE-POINTED AT RUNTIME TAKES THE NEW CLIP'S TIMING. The driver swaps clips in two
	# places (a heavy landing, an ability's own animation); a node that kept the previous clip's
	# timeline would stretch the new one to fit a length it never had.
	var swap := AnimationNodeAnimation.new()
	AnimationTreeBuilder.apply_clip(swap, set, AnimationSet.JUMP_START)
	var swapped_len: float = swap.timeline_length
	_check(swap.use_custom_timeline and swapped_len > 0.0,
		"a scaled clip arrives with a timeline (%.2f s)" % swapped_len)
	AnimationTreeBuilder.apply_clip(swap, set, AnimationSet.JUMP_LOOP, true)
	_check(not swap.use_custom_timeline,
		"and swapping an UNSCALED clip in clears it rather than inheriting %.2f s" % swapped_len)

	# (b) a genre's own verb, from a SECOND library: pressing E at a pond plays the rod cast.
	_check(set.anim_name(AnimationSet.INTERACT) == &"extra/Fish_Cast",
		"the fishing genre overrides `interact` with the rod cast from the other library (%s)"
			% set.anim_name(AnimationSet.INTERACT))
	_check(set.has_exact(StringName("ability.0")),
		"and gives ability 0 its own clip, so the action component's predicted start has one")

	# (c) FALLBACKS. The libraries have no heavy landing; the set must still land.
	_check(not set.has_exact(AnimationSet.JUMP_LAND_HEAVY),
		"the library really has no heavy landing (otherwise this fallback is untested)")
	_check(set.anim_name(AnimationSet.JUMP_LAND_HEAVY) == set.anim_name(AnimationSet.JUMP_LAND),
		"so a heavy landing falls back to the ordinary one")

	# (d) a set with almost nothing in it: the chain has to bottom out at idle, and the missing
	# list has to be honest about what is not there.
	var tiny := AnimationSet.new()
	var only_idle: Dictionary[StringName, AnimationClipRef] = {
		AnimationSet.IDLE: AnimationClipRef.make(&"Idle", true),
	}
	tiny.clips = only_idle
	_check(tiny.anim_name(AnimationSet.RUN) == &"Idle",
		"run falls back through walk to idle (%s)" % tiny.anim_name(AnimationSet.RUN))
	_check(tiny.anim_name(AnimationSet.DEATH) == &"Idle", "so does a missing death")
	_check(tiny.missing_required().size() == 3,
		"but the three jump clips have nothing to fall back to, and it says so (%s)"
			% str(tiny.missing_required()))

	# (e) a typo is caught by the set, not by the player. `dangling_clips` needs real libraries.
	var typo := AnimationSet.new()
	typo.libraries = set.libraries
	var bad: Dictionary[StringName, AnimationClipRef] = {
		AnimationSet.IDLE: AnimationClipRef.make(&"Idle", true),
		AnimationSet.HIT: AnimationClipRef.make(&"Hit_Chestt"),
		AnimationSet.WALK: AnimationClipRef.make(&"extra/Walk_Fwd", true),
	}
	typo.clips = bad
	var dangling: Array[StringName] = typo.dangling_clips()
	_check(dangling.size() == 1 and dangling[0] == AnimationSet.HIT,
		"a misspelled clip is reported, and a correctly spelled one in the second library is not (%s)"
			% str(dangling))

	# --- the generated tree ---------------------------------------------------------------
	var tree: AnimationTree = AnimationTreeBuilder.build(set)
	_check(tree != null, "the builder produces a tree for a complete set")
	if tree == null:
		return
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	_check(root != null and root.get_node_list().size() == 12,
		"the graph is the twelve documented nodes: body, pose (+ its clip, scale, seek), upper, hit, action (%s)"
			% str(root.get_node_list()))
	# THE UPPER BODY (DECISIONS #158): a one-shot that moves the chest, arms and hands and leaves
	# the hips and legs to the body under it.
	var upper: AnimationNodeOneShot = root.get_node(AnimationTreeBuilder.NODE_UPPER) as AnimationNodeOneShot
	_check(upper != null and upper.filter_enabled and upper.is_path_filtered(^"Skeleton3D:hand_r")
			and upper.is_path_filtered(^"Skeleton3D:spine_03") and upper.is_path_filtered(^"Skeleton3D:index_02_l")
			and not upper.is_path_filtered(^"Skeleton3D:thigh_r") and not upper.is_path_filtered(^"Skeleton3D:pelvis")
			and typeof(tree.get(AnimationTreeBuilder.P_UPPER_REQUEST)) == TYPE_INT,
		"the upper-body one-shot plays the chest, the arms and the fingers, and passes the hips and legs through")
	# THE POSE sits between the body and the one-shots: body -> pose -> hit -> action -> output.
	_check(typeof(tree.get(AnimationTreeBuilder.P_POSE_BLEND)) == TYPE_FLOAT
		and typeof(tree.get(AnimationTreeBuilder.P_POSE_SCALE)) == TYPE_FLOAT
		and typeof(tree.get(AnimationTreeBuilder.P_POSE_SEEK)) == TYPE_FLOAT,
		"the held pose takes a blend, a scale and a seek")
	_check(is_zero_approx(float(tree.get(AnimationTreeBuilder.P_POSE_BLEND))),
		"and starts at nothing: a character holds no pose until asked")
	_check(tree.get_animation_library_list().size() == 2,
		"both libraries came with it, so `extra/Fish_Cast` resolves at runtime")

	# The four parameter paths ARE the interface between the driver and the graph. If a rename
	# breaks one, the driver writes into nothing and the character quietly stops reacting.
	_check(tree.get(AnimationTreeBuilder.P_PLAYBACK) is AnimationNodeStateMachinePlayback,
		"the state machine's playback is at %s" % AnimationTreeBuilder.P_PLAYBACK)
	_check(typeof(tree.get(AnimationTreeBuilder.P_BLEND)) == TYPE_VECTOR2,
		"a strafing set blends on a PLANE: %s takes a Vector2" % AnimationTreeBuilder.P_BLEND)
	_check(typeof(tree.get(AnimationTreeBuilder.P_HIT_REQUEST)) == TYPE_INT
		and typeof(tree.get(AnimationTreeBuilder.P_ACTION_REQUEST)) == TYPE_INT,
		"both one-shots take a request")

	var sm: AnimationNodeStateMachine = root.get_node(AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	for state: StringName in [AnimationTreeBuilder.STATE_GROUNDED, AnimationTreeBuilder.STATE_JUMP_START,
			AnimationTreeBuilder.STATE_AIR, AnimationTreeBuilder.STATE_LAND, AnimationTreeBuilder.STATE_DEAD]:
		_check(sm.has_node(state), "the state machine has '%s'" % state)
	_check(sm.has_transition(AnimationTreeBuilder.STATE_START, AnimationTreeBuilder.STATE_GROUNDED),
		"and enters on Grounded by itself, so a character animates from frame one")

	# EVERY travel the driver can make is a DIRECT transition. `travel()` takes the shortest
	# route it can find, and when the only route was two hops it once reached the ground by way
	# of the death state — a live character playing a death animation, with nothing in any log.
	var indirect: Array[String] = []
	for from: StringName in AnimationTreeBuilder.TRAVELS:
		for to: StringName in AnimationTreeBuilder.TRAVELS[from]:
			if not sm.has_transition(from, to):
				indirect.append("%s->%s" % [from, to])
	_check(indirect.is_empty(),
		"no travel the driver can make has to be routed through another state (%s)" % str(indirect))

	# THE BLEND POINTS ARE THE GAME'S OWN SPEEDS. The driver divides the body's velocity by
	# sprint_speed, so a point at walk_speed/sprint_speed is reached exactly when the player
	# walks — including the sideways and backwards gears, which are slower on purpose.
	var cfg: MovementConfig = MovementConfig.shared()
	_check(set.can_strafe() and AnimationTreeBuilder.is_strafing(set),
		"the shipped set strafes: it has the whole directional ring")
	var plane: AnimationNodeBlendSpace2D = sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) as AnimationNodeBlendSpace2D
	_check(plane != null and plane.get_blend_point_count() == 10,
		"the strafing blend is idle, two rings of four and a sprint (%d points)"
			% (plane.get_blend_point_count() if plane != null else -1))
	var w: float = cfg.walk_speed / cfg.sprint_speed
	var r: float = cfg.run_speed / cfg.sprint_speed
	var want: Dictionary[String, Vector2] = {
		"idle": Vector2.ZERO,
		"walk": Vector2(0.0, w),
		"walk_back": Vector2(0.0, -w * cfg.back_speed_mult),
		"walk_left": Vector2(-w * cfg.strafe_speed_mult, 0.0),
		"run": Vector2(0.0, r),
		"run_left": Vector2(-r * cfg.strafe_speed_mult, 0.0),
		"sprint": Vector2(0.0, 1.0),
	}
	var found: Array[Vector2] = []
	for i: int in range(plane.get_blend_point_count()):
		found.append(plane.get_blend_point_position(i))
	var missing_points: Array[String] = []
	for label: String in want:
		var hit: bool = false
		for pos: Vector2 in found:
			if pos.distance_to(want[label]) < 1e-5:
				hit = true
		if not hit:
			missing_points.append("%s@%s" % [label, want[label]])
	_check(missing_points.is_empty(),
		"every gait sits at the speed the model produces for it (%s missing from %s)"
			% [str(missing_points), str(found)])

	# The same set, without the strafe wish: one forward axis, four gaits on it.
	var line_set: AnimationSet = set.duplicate() as AnimationSet
	line_set.strafe = false
	var line_tree: AnimationTree = AnimationTreeBuilder.build(line_set)
	var line_sm: AnimationNodeStateMachine = (line_tree.tree_root as AnimationNodeBlendTree).get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	var line: AnimationNodeBlendSpace1D = line_sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) as AnimationNodeBlendSpace1D
	_check(line != null and line.get_blend_point_count() == 4,
		"turning strafing off gives one axis with idle, walk, run and sprint on it (%d)"
			% (line.get_blend_point_count() if line != null else -1))
	_check(line != null and absf(line.get_blend_point_position(1) - w) < 1e-5
		and absf(line.get_blend_point_position(2) - r) < 1e-5,
		"at walk_speed/sprint_speed and run_speed/sprint_speed, not guesses")
	_check(typeof(line_tree.get(AnimationTreeBuilder.P_BLEND)) == TYPE_FLOAT,
		"and it blends on a float")
	line_tree.free()

	# THE TAKE-OFF FITS THE JUMP. Quaternius' clip is 1.33 s and this game's jump is 0.8 s, so
	# without the generated speed-up the character is still crouching to jump as it lands, and
	# the airborne loop is never reached at all.
	var airtime: float = 2.0 * cfg.jump_velocity / cfg.gravity
	var start_ref: AnimationClipRef = set.clip(AnimationSet.JUMP_START)
	var start_len: float = set.libraries[&""].get_animation(
		StringName(String(start_ref.anim_name))).length
	_check(start_ref.speed_scale > 1.0 and start_len / start_ref.speed_scale < airtime * 0.5,
		"the take-off plays in %.2f s, inside the %.2f s the player is airborne (clip is %.2f s)"
			% [start_len / start_ref.speed_scale, airtime, start_len])

	# LOOPING. A locomotion blend of one-shot clips freezes a second after the player moves, and
	# nothing about that failure says "loop flag".
	for semantic: StringName in [AnimationSet.IDLE, AnimationSet.WALK, AnimationSet.RUN,
			AnimationSet.SPRINT, AnimationSet.RUN_LEFT, AnimationSet.WALK_BACK]:
		var anim: Animation = _clip_in(set, set.anim_name(semantic))
		_check(anim != null and anim.loop_mode != Animation.LOOP_NONE,
			"%s loops" % set.anim_name(semantic))

	# The speed-up is applied through a custom timeline, because a state-machine state has
	# nowhere to put a TimeScale node. Assert the node really carries it: getting this wrong
	# leaves the clip at its authored length and nothing says so.
	var sm2: AnimationNodeStateMachine = root.get_node(AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	var takeoff: AnimationNodeAnimation = sm2.get_node(AnimationTreeBuilder.STATE_JUMP_START) as AnimationNodeAnimation
	_check(takeoff.use_custom_timeline and takeoff.stretch_time_scale
		and absf(takeoff.timeline_length - start_len / start_ref.speed_scale) < 1e-3,
		"the take-off state plays its clip in %.2f s (timeline %.2f s)"
			% [start_len / start_ref.speed_scale, takeoff.timeline_length])

	# A library exported without `_Loop` suffixes has no loop flags, and a locomotion blend of
	# one-shots freezes a second after the player starts walking. The builder fixes that; here
	# it is given a clip that really does not loop, on a private copy of the library.
	var copy: AnimationLibrary = set.libraries[&""].duplicate(true) as AnimationLibrary
	_check(copy.get_animation(&"Interact").loop_mode == Animation.LOOP_NONE,
		"`Interact` is a one-shot clip in the library (otherwise this test proves nothing)")
	var loopy := AnimationSet.new()
	var loopy_libs: Dictionary[StringName, AnimationLibrary] = {&"": copy}
	loopy.libraries = loopy_libs
	var loopy_clips: Dictionary[StringName, AnimationClipRef] = {}
	for semantic: StringName in AnimationSet.REQUIRED:
		loopy_clips[semantic] = AnimationClipRef.make(&"Interact", true)
	loopy.clips = loopy_clips
	var loopy_tree: AnimationTree = AnimationTreeBuilder.build(loopy)
	_check(loopy_tree != null and copy.get_animation(&"Interact").loop_mode != Animation.LOOP_NONE,
		"building a tree makes the clips its locomotion needs loop")
	if loopy_tree != null:
		loopy_tree.free()

	# (f) NEGATIVE: an unusable set is refused outright rather than producing a tree that plays
	# nothing. The push_error this raises is listed in run_tests.sh.
	_check(AnimationTreeBuilder.build(tiny) == null,
		"a set without the required clips is refused, loudly")
	tree.free()


## Resolve a clip by its mixer-qualified name (`Idle`, `extra/Walk_Fwd`).
func _clip_in(set: AnimationSet, full: StringName) -> Animation:
	var s: String = String(full)
	var slash: int = s.find("/")
	var lib: AnimationLibrary = set.libraries.get(
		StringName(s.substr(0, slash)) if slash >= 0 else &"", null)
	var name: StringName = StringName(s.substr(slash + 1) if slash >= 0 else s)
	return lib.get_animation(name) if lib != null and lib.has_animation(name) else null


## A REAL RIG, DRIVEN BY REAL INPUT. Everything above is about resources; this spawns the actual
## fisher with the actual Quaternius skeleton in the actual level, pushes input frames through
## the same prediction the player drives, and asks the skeleton whether it moved.
##
## That last question is the one that matters: every link in the chain — library extraction,
## track re-addressing, the generated graph, the parameter paths, the driver — is invisible
## until a bone rotates, and each of them fails silently on its own.
## Clips in a generated tree whose loop contradicts the job they do: a locomotion clip that
## would freeze after one cycle, or a one-shot that would never hand over. Returns the offenders,
## named, so a failure says which clip rather than that something somewhere is wrong.
func _loop_faults(tree: AnimationTree) -> Array[String]:
	var out: Array[String] = []
	if tree == null:
		return ["no tree"]
	var one_shots: Array[String] = [String(AnimationTreeBuilder.STATE_JUMP_START),
		String(AnimationTreeBuilder.STATE_LAND), String(AnimationTreeBuilder.STATE_DEAD),
		String(AnimationTreeBuilder.NODE_HIT_CLIP), String(AnimationTreeBuilder.NODE_ACTION_CLIP)]
	var nodes: Dictionary[String, AnimationNodeAnimation] = _clip_nodes(tree)
	for label: String in nodes:
		var node: AnimationNodeAnimation = nodes[label]
		# Without a custom timeline the clip keeps its own loop, which the extractor set.
		if node == null or not node.use_custom_timeline:
			continue
		if one_shots.has(label):
			if node.loop_mode != Animation.LOOP_NONE:
				out.append("%s (%s) would never end" % [label, node.animation])
		elif node.loop_mode != Animation.LOOP_LINEAR:
			out.append("%s (%s) would freeze after one cycle" % [label, node.animation])
	return out


## Every AnimationNodeAnimation in a generated tree, by where it sits.
func _clip_nodes(tree: AnimationTree) -> Dictionary[String, AnimationNodeAnimation]:
	var out: Dictionary[String, AnimationNodeAnimation] = {}
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return out
	for n: StringName in [AnimationTreeBuilder.NODE_HIT_CLIP, AnimationTreeBuilder.NODE_ACTION_CLIP]:
		out[String(n)] = root.get_node(n) as AnimationNodeAnimation
	var sm: AnimationNodeStateMachine = root.get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	if sm == null:
		return out
	for state: StringName in [AnimationTreeBuilder.STATE_JUMP_START, AnimationTreeBuilder.STATE_AIR,
			AnimationTreeBuilder.STATE_LAND, AnimationTreeBuilder.STATE_DEAD]:
		out[String(state)] = sm.get_node(state) as AnimationNodeAnimation
	var ground: AnimationNode = sm.get_node(AnimationTreeBuilder.STATE_GROUNDED)
	var plane: AnimationNodeBlendSpace2D = ground as AnimationNodeBlendSpace2D
	if plane != null:
		for i: int in range(plane.get_blend_point_count()):
			out["Grounded/%d" % i] = plane.get_blend_point_node(i) as AnimationNodeAnimation
	var line: AnimationNodeBlendSpace1D = ground as AnimationNodeBlendSpace1D
	if line != null:
		for i: int in range(line.get_blend_point_count()):
			out["Grounded/%d" % i] = line.get_blend_point_node(i) as AnimationNodeAnimation
	return out


## How long one cycle of a set's clip takes at the speed the set asks for it to be played.
func _clip_seconds(set: AnimationSet, semantic: StringName) -> float:
	var ref: AnimationClipRef = set.clip(semantic)
	var anim: Animation = _clip_in(set, set.anim_name(semantic))
	if ref == null or anim == null or ref.speed_scale <= 0.0:
		return 1.0
	return anim.length / ref.speed_scale


func _run_animation_scene_tests() -> void:
	print("== animation: a real rig in the real level ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	var defn: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	if reg == null or spawner == null or packed == null or defn == null:
		_check(false, "autoloads, level and fisher definition present")
		return
	_check(defn.visual_for(0) != null and defn.animation_set != null,
		"the fisher definition carries a rigged model and an animation set")
	var level: Node3D = packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	var world_root: Node3D = level.get_node(^"WorldRoot") as Node3D

	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true
	var eid: int = 5201
	reg.local_entity_id = eid
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(me != null and me.is_local_authority, "the fisher spawned as ours")
	if me == null:
		reg.local_entity_id = prev_local
		spawner._world_ready = prev_ready
		level.queue_free()
		return

	var driver: AnimationDriverComponent = me.find_component(
		AnimationDriverComponent) as AnimationDriverComponent
	var movement: SpaceTimeMovementComponent = me.find_component(
		SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var health: SpaceTimeHealthComponent = me.find_component(
		SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	var interaction: InteractionComponent = me.find_component(
		InteractionComponent) as InteractionComponent
	var action: SpaceTimeActionComponent = me.find_component(
		SpaceTimeActionComponent) as SpaceTimeActionComponent
	_check(driver != null and movement != null, "it carries an animation driver and movement")
	# The fisher is a LOCAL entity, so its own input component samples the keyboard every physics
	# tick. Left running, its "nothing pressed" frames interleave with this suite's and halve
	# every speed — which is exactly what it did, and the gait modifiers came out as noise.
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	if input != null:
		input.set_physics_process(false)
		input.send_to_server = false
	if driver == null or movement == null:
		await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)
		return

	# --- the model and the rig ------------------------------------------------------------
	var model: Node3D = me.get_node_or_null(^"Visual/Model") as Node3D
	_check(model != null, "the definition's rigged model replaced the greybox capsule")
	var skel: Skeleton3D = driver._find_skeleton(model) if model != null else null
	_check(skel != null and skel.get_bone_count() == 65,
		"the model brings a skeleton (%d bones)" % (skel.get_bone_count() if skel != null else -1))
	_check(model != null and absf(absf(model.rotation.y) - PI) < 1e-3,
		"the model is turned to face -Z, the direction this project calls forward (yaw %.1f deg)"
			% rad_to_deg(model.rotation.y if model != null else 0.0))
	_check(driver.is_animating(), "the driver built and activated a tree")
	_check(driver.turn_smoothing > 0.0,
		"the model eases round to the body's facing rather than snapping with it")
	if not driver.is_animating() or skel == null:
		await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)
		return
	var tree: AnimationTree = driver.animation_tree()
	_check(tree.get_node(tree.root_node) == skel.get_parent(),
		"the tree is rooted where the re-addressed `Skeleton3D:<bone>` tracks resolve")

	# --- IT ACTUALLY MOVES THE SKELETON ----------------------------------------------------
	var seq: Array[int] = [0]
	await _place_predicted(movement, Vector3(-3.0, 0.0, 3.0), seq, 6)
	await _anim_frames(movement, seq, 6, Vector2.ZERO)
	var idle_a: Array[Quaternion] = _pose_of(skel)
	await _anim_frames(movement, seq, 20, Vector2.ZERO)
	var idle_b: Array[Quaternion] = _pose_of(skel)
	# The teleport above lands the body, so the machine passes through Land on its way in; the
	# landing clip has to finish before Grounded, which is the auto transition doing its job.
	var settled: bool = await _wait_for_state(driver, movement, seq,
		AnimationTreeBuilder.STATE_GROUNDED, 120)
	_check(settled, "the landing clip ends and hands back to Grounded on its own")
	var idle_motion: float = _pose_delta(idle_a, idle_b)
	print("   idle pose moved %.4f rad over 20 frames" % idle_motion)
	_check(idle_motion > 0.002,
		"standing still, the idle animation is running: the skeleton keeps moving (%.4f rad)"
			% idle_motion)
	_check(driver.current_state() == AnimationTreeBuilder.STATE_GROUNDED,
		"and the state machine is Grounded (%s)" % driver.current_state())

	# --- walking drives the blend, and the blend changes the pose --------------------------
	await _anim_frames(movement, seq, 45, Vector2(0.0, -1.0))
	var walk_pose: Array[Quaternion] = _pose_of(skel)
	print("   walking: speed blend %.2f" % driver.speed_blend())
	_check(driver.speed_blend() > 0.35,
		"walking raises the locomotion blend off idle (%.2f)" % driver.speed_blend())
	_check(_pose_delta(idle_b, walk_pose) > 0.05,
		"and the pose is a different one: the blend reaches the bones (%.3f rad)"
			% _pose_delta(idle_b, walk_pose))

	# --- THE GAITS. A plain key press runs; the modifiers are a gear either side of it, and the
	# blend has to land on the clip that was fitted to that gear or the feet skate.
	var cfg: MovementConfig = MovementConfig.shared()
	await _anim_frames(movement, seq, 45, Vector2(0.0, -1.0), false, false, true)   # slow
	var walk_blend: float = driver.strafe_blend().y
	print("   walking: blend y %.2f (want %.2f)" % [walk_blend, cfg.walk_speed / cfg.sprint_speed])
	_check(absf(walk_blend - cfg.walk_speed / cfg.sprint_speed) < 0.08,
		"holding the slow modifier lands on the walk ring (%.2f)" % walk_blend)
	await _anim_frames(movement, seq, 45, Vector2(0.0, -1.0), false, true)          # sprint
	var sprint_blend: float = driver.strafe_blend().y
	_check(absf(sprint_blend - 1.0) < 0.08,
		"and sprinting reaches the outside of the blend (%.2f)" % sprint_blend)

	# --- STRAFING. The body keeps facing the camera, so sideways movement has to come out as a
	# side-step in the character's OWN frame rather than a forward run pointed sideways.
	_check(driver.is_strafing(), "the fisher's set drives a strafing blend")
	await _anim_frames(movement, seq, 50, Vector2(1.0, 0.0))
	var side: Vector2 = driver.strafe_blend()
	print("   strafing right: blend %s" % side)
	_check(side.x > 0.25 and absf(side.y) < 0.15,
		"moving right blends to the right, not forwards (%s)" % side)
	await _anim_frames(movement, seq, 50, Vector2(0.0, 1.0))
	var back: Vector2 = driver.strafe_blend()
	_check(back.y < -0.2 and absf(back.x) < 0.15,
		"and backwards blends backwards (%s)" % back)

	# TURNED ROUND. `move_dir` is relative to the body, so forward is forward whatever the body
	# faces — but the blend is computed from a WORLD velocity, so it has to be rotated back into
	# the character's frame. With the body at yaw 0 both frames agree and the difference is
	# invisible; this is the case that tells them apart.
	# Facing +90 degrees, "forward" is world -X — `move_dir` is a world direction, which is
	# exactly the distinction that made a sprint north move at 8 x 0.65 until it was fixed.
	await _anim_frames_facing(movement, seq, 60, Vector2(-1.0, 0.0), PI * 0.5)
	var turned_blend: Vector2 = driver.strafe_blend()
	var turned_state: MovementState = movement.get_render_state()
	print("   facing %.2f rad, world velocity %s, blend %s"
		% [turned_state.yaw, turned_state.vel, turned_blend])
	_check(absf(turned_state.yaw - PI * 0.5) < 0.01 and absf(turned_state.vel.x) > 3.0,
		"the body turned and is moving along world -X (%s)" % turned_state.vel)
	_check(turned_blend.y > 0.4 and absf(turned_blend.x) < 0.15,
		"running forwards while turned still blends FORWARDS, not sideways (%s)" % turned_blend)
	await _anim_frames(movement, seq, 40, Vector2.ZERO)

	# --- THE FEET KEEP MOVING, a full cycle later ------------------------------------------
	# The check above — "the walking pose is not the idle pose" — is satisfied by a clip frozen on
	# frame one, and that is exactly what shipped: every locomotion clip is speed-scaled, a scaled
	# clip plays through a custom timeline, and a custom timeline overrides the clip's own loop
	# with a node default of "do not loop" (DECISIONS #103). One cycle, then the character slid
	# along the ground in a fixed pose.
	#
	# Frame counts cannot express the window this needs. The animation advances on the RENDER
	# clock, and a headless run puts several physics steps inside one idle frame (DECISIONS #46),
	# so "past the end of the clip" is only meaningful against a wall clock.
	var loco: AnimationSet = defn.animation_set
	var gaits: Array[StringName] = [AnimationSet.RUN, AnimationSet.RUN_RIGHT,
		AnimationSet.RUN_LEFT, AnimationSet.RUN_BACK, AnimationSet.WALK_BACK]
	var gait_names: Array[String] = ["running forwards", "strafing right", "strafing left",
		"running backwards", "walking backwards"]
	var gait_dirs: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(0.0, 1.0)]
	var gait_slow: Array[bool] = [false, false, false, false, true]
	# Started far enough from the greybox's walls that the window measures a gait, not a stop.
	var gait_from: Array[Vector3] = [Vector3(0.0, 0.0, 8.0), Vector3(-8.0, 0.0, -5.0),
		Vector3(8.0, 0.0, -5.0), Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -5.0)]
	for i: int in range(gaits.size()):
		var cycle: float = _clip_seconds(loco, gaits[i])
		await _place_predicted(movement, gait_from[i], seq, 6)
		await _anim_seconds(movement, seq, cycle + 0.4, gait_dirs[i], gait_slow[i])
		var before_pose: Array[Quaternion] = _pose_of(skel)
		await _anim_seconds(movement, seq, 0.5, gait_dirs[i], gait_slow[i])
		var still_moving: float = _pose_delta(before_pose, _pose_of(skel))
		var gait_speed: float = Vector2(movement.get_render_state().vel.x,
			movement.get_render_state().vel.z).length()
		print("   %-18s %-14s cycle %.2f s -> pose moved %.2f rad after it ended, at %.2f m/s"
			% [gait_names[i], loco.anim_name(gaits[i]), cycle, still_moving, gait_speed])
		_check(gait_speed > 0.4,
			"%s: still travelling, so this window measured a gait and not a wall (%.2f m/s)"
				% [gait_names[i], gait_speed])
		_check(still_moving > 0.05,
			"%s: the feet are STILL MOVING a whole cycle in, not stuck on frame one (%.2f rad)"
				% [gait_names[i], still_moving])
	await _place_predicted(movement, Vector3(-3.0, 0.0, 3.0), seq, 6)
	await _anim_frames(movement, seq, 20, Vector2.ZERO)

	# --- AN ACTION DOES NOT OUTLIVE STANDING STILL -----------------------------------------
	# Reported from play: cast, then walk, and the whole cast animation plays over a character
	# sliding away. A one-shot runs to its own end and knows nothing about the body underneath
	# it, so the body has to be the one to take it back.
	await _anim_frames(movement, seq, 20, Vector2.ZERO)
	driver._on_interact_requested(0)
	await _anim_frames(movement, seq, 4, Vector2.ZERO)
	_check(driver.action_playing(), "pressing interact starts the action animation")
	await _anim_frames(movement, seq, 30, Vector2.ZERO)
	_check(driver.action_playing(),
		"and standing still it keeps playing: cancelling always would be a different bug")
	await _anim_frames(movement, seq, 45, Vector2(0.0, -1.0))
	_check(not driver.action_playing(),
		"walking away cancels it instead of sliding through the rest of it")
	await _anim_frames(movement, seq, 20, Vector2.ZERO)

	# --- the jump arc ----------------------------------------------------------------------
	var states: Array[String] = []
	var scb := func(s: StringName) -> void: states.append(String(s))
	driver.state_changed.connect(scb)
	await _anim_frames(movement, seq, 4, Vector2.ZERO, true)     # jump
	_check(driver.current_state() == AnimationTreeBuilder.STATE_JUMP_START
		or driver.current_state() == AnimationTreeBuilder.STATE_AIR,
		"pressing jump takes the character off the ground animation (%s)" % driver.current_state())
	await _anim_frames(movement, seq, 75, Vector2.ZERO)           # rise, fall, land
	_check(driver.current_state() == AnimationTreeBuilder.STATE_GROUNDED
		or driver.current_state() == AnimationTreeBuilder.STATE_LAND,
		"and landing brings it back down (%s after %s)" % [driver.current_state(), str(states)])
	_check(states.has("JumpStart") and states.has("Air"),
		"the whole arc was travelled: %s" % str(states))

	# And again from a height, which is the other way to leave the ground.
	states.clear()
	var high := FakeMoveRow.new(eid, Vector3(-3.0, 5.0, 3.0), 9_500_000)
	high.last_processed_seq = seq[0]
	high.correction_epoch = movement.get_epoch() + 1
	high.teleport_flag = true
	high.grounded = false
	movement.receive_row_event(_move_ev(high))
	var reached_air: bool = await _wait_for_state(driver, movement, seq,
		AnimationTreeBuilder.STATE_AIR, 60)
	_check(reached_air, "falling reaches the airborne loop (%s, arc %s)"
		% [driver.current_state(), str(states)])
	var back_down: bool = await _wait_for_state(driver, movement, seq,
		AnimationTreeBuilder.STATE_GROUNDED, 200)
	_check(back_down, "and landing from it comes all the way back to Grounded (%s, arc %s)"
		% [driver.current_state(), str(states)])

	# A LANDING MUST NOT OUTLIVE THE LANDING. The recovery clip is a stop: watching it finish
	# while the character is already running is the slide the player reported. Landing on the
	# spot must still play it, though — cancelling it always would just be a different bug.
	var running_recovery: int = await _fall_and_time_landing(driver, movement, seq, Vector2(0.0, -1.0))
	var standing_recovery: int = await _fall_and_time_landing(driver, movement, seq, Vector2.ZERO)
	print("   landing recovery: %d frames when running, %d when stopped"
		% [running_recovery, standing_recovery])
	_check(standing_recovery > 10,
		"landing on the spot plays the recovery (%d frames)" % standing_recovery)
	_check(running_recovery * 2 < standing_recovery,
		"landing at a run cuts it short instead of sliding through it (%d vs %d frames)"
			% [running_recovery, standing_recovery])
	await _anim_frames(movement, seq, 30, Vector2.ZERO)
	driver.state_changed.disconnect(scb)

	# --- reactions and verbs ----------------------------------------------------------------
	if health != null:
		health.damaged.emit(7.0, 0)
		await _anim_frames(movement, seq, 3, Vector2.ZERO)
		_check(driver.hit_playing(), "taking damage fires the hit reaction over whatever is playing")
	if interaction != null:
		interaction.interact_requested.emit(99)
		await _anim_frames(movement, seq, 2, Vector2.ZERO)
		_check(driver.action_clip() == &"extra/Fish_Cast" and driver.action_playing(),
			"the interact key plays the genre's cast animation (%s)" % driver.action_clip())
	if action != null:
		action.action_started.emit(0, 1)
		await _anim_frames(movement, seq, 2, Vector2.ZERO)
		_check(driver.action_clip() == &"extra/Melee_Hook",
			"and an ability plays its own clip (%s)" % driver.action_clip())

	# --- a HELD POSE: the fight's heave (DECISIONS #144) ------------------------------------
	# A clip frozen at a point a value picks, blended over the body. Measured on the skeleton: the
	# rod hand has to RISE as the heave goes on, or the pose layer is wired to nothing. The fisher's
	# FishingFeedback owns this pose in the game (it lets it go every frame no line is out), so it
	# is paused while the driver is asked directly.
	var feedback: FishingFeedback = me.find_component(FishingFeedback) as FishingFeedback
	if feedback != null:
		feedback.set_process(false)
	await _anim_frames(movement, seq, 40, Vector2.ZERO)
	var rest_hand: float = _bone_y(skel, "hand_r")
	driver.hold_pose(&"fishing.heave", 1.0, 0.0)
	await _anim_frames(movement, seq, 20, Vector2.ZERO)
	var low_hand: float = _bone_y(skel, "hand_r")
	_check(driver.pose_clip() == &"extra/Fish_Reel" and is_equal_approx(driver.pose_weight(), 1.0),
		"holding the heave blends the set's heave clip in fully (%s, %.2f)" % [driver.pose_clip(), driver.pose_weight()])
	driver.hold_pose(&"fishing.heave", 1.0, 0.75)
	await _anim_frames(movement, seq, 6, Vector2.ZERO)
	var high_hand: float = _bone_y(skel, "hand_r")
	print("   rod hand: %.2f m standing, %.2f m braced, %.2f m heaved" % [rest_hand, low_hand, high_hand])
	_check(high_hand > low_hand + 0.15,
		"and heaving it three-quarters through lifts the rod hand (%.2f -> %.2f m)" % [low_hand, high_hand])
	_check(is_equal_approx(float(tree.get(AnimationTreeBuilder.P_POSE_SCALE)), 0.0),
		"a held point is frozen there, not played on")
	driver.hold_pose(&"fishing.wait", 1.0)
	await _anim_frames(movement, seq, 3, Vector2.ZERO)
	_check(driver.pose_clip() == &"extra/Fish_Cast_Idle"
			and is_equal_approx(float(tree.get(AnimationTreeBuilder.P_POSE_SCALE)), 1.0),
		"waiting with a line out plays the waiting clip, looping (%s)" % driver.pose_clip())
	driver.hold_pose(&"no.such.pose", 1.0)
	_check(driver.pose_clip() == &"extra/Fish_Cast_Idle", "a pose the set does not have changes nothing")
	driver.release_pose()
	await _anim_frames(movement, seq, 20, Vector2.ZERO)
	_check(is_zero_approx(driver.pose_weight())
			and absf(_bone_y(skel, "hand_r") - rest_hand) < 0.05,
		"letting go blends it out, and the body is its own again (%.2f m)" % _bone_y(skel, "hand_r"))
	driver.play_action(&"fishing.fail")
	await _anim_frames(movement, seq, 2, Vector2.ZERO)
	_check(driver.action_clip() == &"extra/Fish_Reel_Failed" and driver.action_playing(),
		"a genre's own reaction plays through the action slot (%s)" % driver.action_clip())
	var waited: int = 0
	while driver.action_playing() and waited < 400:
		await _anim_frames(movement, seq, 1, Vector2.ZERO)
		waited += 1
	print("   the fail clip played out in %d frames" % waited)
	if feedback != null:
		feedback.set_process(true)

	# --- THE ROD, HELD (DECISIONS #147, #153) ----------------------------------------------------
	# Luke: "the reel clips into her leg", and "the run animation feels strange" — the rod rode the
	# running arm, its tip swept through her head every stride. Then: "I get it aligned for one
	# animation, but a separate animation (run) needs a different value" — so a grip is per
	# animation (and per body, #155), blended as the animations blend (#156: no modes). Measured on
	# the real rig, driven by the real FishingFeedback and the real driver. The control first: the
	# rod left to the hand in #147's fishing grip for every animation, pinned here (the grip file is
	# tuned by hand).
	var rod: FishingRod = feedback.fx().rod() if feedback != null and feedback.fx() != null else null
	_check(rod != null, "the fisher holds a rod")
	if rod != null and feedback != null:
		# Carried in the hand for these; put away is checked after (DECISIONS #158, #159).
		var equip: EquipComponent = me.find_component(EquipComponent) as EquipComponent
		_check(equip != null, "the fisher has an equip state")
		equip.away_when_idle = false
		equip.set_equipped_now(true)
		var file_grip: ItemGrip = rod.grip
		var as_it_was := ItemGrip.new()
		as_it_was.entries.append(_root_entry(AnimationSet.IDLE, GRIP_147[0], GRIP_147[1], false))
		rod.grip = as_it_was
		feedback.set_process(false)
		await _place_predicted(movement, Vector3(-3.0, 0.0, 3.0), seq, 6)
		await _anim_frames(movement, seq, 40, Vector2.ZERO)
		var loose_idle: Dictionary = await _measure_rod(movement, seq, skel, rod, Vector2.ZERO, 40)
		await _anim_frames(movement, seq, 20, Vector2(0.0, -1.0))
		var loose_run: Dictionary = await _measure_rod(movement, seq, skel, rod, Vector2(0.0, -1.0), 60)
		print("   rod left to the hand: reel %.1f cm off the leg standing; running, it swings %.0f deg, %.1f cm from the head"
			% [loose_idle["air"] * 100.0, loose_run["swing"], loose_run["head"] * 100.0])
		_check(loose_idle["air"] < 0.01 and loose_run["swing"] > 35.0 and loose_run["head"] < 0.0,
			"CONTROL: held the fishing way and left to the hand, the reel sits on the leg (%.1f cm) and running swings the rod %.0f deg through the head (%.1f cm) — the bug"
				% [loose_idle["air"] * 100.0, loose_run["swing"], loose_run["head"] * 100.0])
		rod.grip = file_grip
		feedback.set_process(true)
		await _place_predicted(movement, Vector3(-3.0, 0.0, 3.0), seq, 6)
		await _anim_frames(movement, seq, 40, Vector2.ZERO)
		var stood: Dictionary = await _measure_rod(movement, seq, skel, rod, Vector2.ZERO, 40)
		_check(rod.driver == driver and rod.body_type == &"female",
			"the rod reads the body's animation from its driver, and knows it is in a woman's hand")
		_check(stood["air"] >= 0.02,
			"and standing, the reel is 2 cm or more off her body: %.1f cm %s (%s; if not, retune the idle grip in rod_grip_preview.tscn until her label is green)"
				% [absf(stood["air"]) * 100.0, "clear" if stood["air"] >= 0.0 else "INSIDE",
					defn.visual_for(eid).resource_path.get_file().get_basename()])
		# THE WRIST (DECISIONS #158): carried steady, the hand turns to keep the handle in the fist.
		# The clip's own hand is what the skeleton gives back after the frame; the hand the rod was
		# drawn in is the turned one.
		var raw_hand: Transform3D = _hand_of(skel, file_grip)
		var turned_by: float = rad_to_deg(Quaternion(raw_hand.basis.orthonormalized()).angle_to(
			Quaternion(rod.hand_now().basis.orthonormalized())))
		var fist_line: Vector3 = GripFit.hole(skel, file_grip.hand)["axis"]
		var off_line: float = rad_to_deg(rod.held_in_hand().basis.y.angle_to(fist_line))
		var raw_off: float = rad_to_deg((raw_hand.basis.orthonormalized().inverse()
			* (rod.hand_now().basis.orthonormalized() * rod.held_in_hand().basis.y)).angle_to(fist_line))
		print("   standing, the wrist turns %.0f deg: the handle %.0f deg off the fist's line (%.0f deg with the wrist as the clip has it)"
			% [turned_by, off_line, raw_off])
		_check(turned_by > 10.0 and off_line < 5.0 and raw_off > 20.0,
			"carried steady, her wrist turns %.0f deg to keep the handle in the fist (%.0f deg off its line; %.0f deg without the turn)"
				% [turned_by, off_line, raw_off])
		# THE ANIMATION'S WEIGHTS, as the tree blends them. The locomotion points are read back by
		# position in the order the builder adds them: a reordering there must show up here.
		var body_sm: AnimationNodeStateMachine = (tree.tree_root as AnimationNodeBlendTree).get_node(
			AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
		var plane: AnimationNodeBlendSpace2D = body_sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) as AnimationNodeBlendSpace2D
		var order_ok: bool = plane != null and plane.get_blend_point_count() == AnimationTreeBuilder.PLANE_POINTS.size()
		if order_ok:
			for i: int in range(plane.get_blend_point_count()):
				var clip: StringName = (plane.get_blend_point_node(i) as AnimationNodeAnimation).animation
				order_ok = order_ok and clip == defn.animation_set.anim_name(AnimationTreeBuilder.PLANE_POINTS[i])
		_check(order_ok, "the locomotion plane's points are the builder's PLANE_POINTS, in order")
		var standing_w: Dictionary[StringName, float] = driver.semantic_weights()
		_check(absf(float(standing_w.get(AnimationSet.IDLE, 0.0)) - 1.0) < 0.02,
			"standing, the driver says the body shows its idle (%s)" % standing_w)
		# WHAT THE GRIP FILE SAYS IS WHAT THE GAME DRAWS (DECISIONS #152): the rod as drawn
		# (interpolated, as rendered), in the frame of the hand it is drawn in.
		var carried: Dictionary = _rod_in_hand(skel, rod)
		var want_carry: Transform3D = file_grip.resolve(AnimationSet.IDLE, rod.body_type).in_hand(
			rod.hand_now(), skel.global_basis)
		_check(_near(carried["drawn"] as Transform3D, want_carry) and _near(carried["in_hand"] as Transform3D, want_carry),
			"and it is drawn in the hand where the grip file's idle grip for her puts it (%s, want %s)"
				% [(carried["drawn"] as Transform3D).origin, want_carry.origin])
		await _anim_frames(movement, seq, 20, Vector2(0.0, -1.0))
		var running_w: Dictionary[StringName, float] = driver.semantic_weights()
		var run_share: float = float(running_w.get(AnimationSet.RUN, 0.0)) + float(running_w.get(AnimationSet.SPRINT, 0.0))
		var total_w: float = 0.0
		for k: StringName in running_w:
			total_w += running_w[k]
		_check(run_share > 0.8 and absf(total_w - 1.0) < 0.001,
			"running, the body shows its run (%.2f of it), and the weights sum to 1 (%.3f)" % [run_share, total_w])
		var ran: Dictionary = await _measure_rod(movement, seq, skel, rod, Vector2(0.0, -1.0), 60)
		print("   rod carried: reel %.1f cm off the body standing; running, it swings %.1f deg, %.1f cm from the head, reel %.1f cm off the body"
			% [stood["air"] * 100.0, ran["swing"], ran["head"] * 100.0, ran["air"] * 100.0])
		_check(ran["swing"] < 8.0 and ran["head"] > 0.05 and ran["air"] >= 0.02,
			"running, the rod is carried STEADY: it turns %.1f deg over the strides, stays %.1f cm from the head and %.1f cm off the body (if not: give the run a steady grip in rod_grip_preview.tscn)"
				% [ran["swing"], ran["head"] * 100.0, ran["air"] * 100.0])
		# A GRIP OF ITS OWN FOR ONE ANIMATION. A copy of the file, so the file is never touched: her
		# run's grip moved 6 cm along her fingers. Running, the rod sits there; standing, it is back
		# in the idle's.
		var copy: ItemGrip = file_grip.duplicate(true) as ItemGrip
		var run_own: GripEntry = copy.ensure(AnimationSet.RUN, rod.body_type)
		run_own.position += Vector3(0.0, 0.06, 0.0)
		rod.grip = copy
		await _anim_frames(movement, seq, 30, Vector2(0.0, -1.0))
		var moved_by: float = rod.held_in_hand().origin.distance_to(file_grip.blend(rod.animation_weights(),
			rod.hand_now(), skel.global_basis, rod.body_type).origin)
		_check(moved_by > 0.045 and moved_by < 0.065,
			"given its own grip 6 cm along the fingers, the RUN holds the rod %.1f cm from where the file had it" % (moved_by * 100.0))
		await _anim_frames(movement, seq, 50, Vector2.ZERO)
		_check(_near(rod.held_in_hand(), copy.resolve(AnimationSet.IDLE, rod.body_type).in_hand(
				rod.hand_now(), skel.global_basis)),
			"and standing again it is back in the idle's grip: the run's own grip is the run's alone")
		# HER OWN GRIP (DECISIONS #155): the fisher here wears a woman's look, and the rod knows it
		# from the look. An idle grip kept for the male body changes nothing for her; one kept for
		# hers is the one drawn. Her own, if the file has one, is taken away first: she starts on
		# the shared grip.
		var me_body: StringName = rod.body_type
		copy.remove(AnimationSet.IDLE, me_body)
		var his_only: GripEntry = copy.ensure(AnimationSet.IDLE, &"male")
		his_only.position += Vector3(0.05, 0.0, 0.0)
		await _anim_frames(movement, seq, 4, Vector2.ZERO)
		var shared_idle: Transform3D = copy.find(AnimationSet.IDLE).in_hand(rod.hand_now(), skel.global_basis)
		var unmoved: bool = _near(rod.held_in_hand(), shared_idle)
		var hers_only: GripEntry = copy.ensure(AnimationSet.IDLE, &"female")
		hers_only.position += Vector3(0.0, 0.0, 0.03)
		await _anim_frames(movement, seq, 4, Vector2.ZERO)
		_check(me_body == &"female" and unmoved
				and _near(rod.held_in_hand(), hers_only.in_hand(rod.hand_now(), skel.global_basis)),
			"a %s look holds the rod in her body's own grip, and a grip kept for the male body does not touch it" % me_body)
		rod.grip = file_grip
		await _anim_frames(movement, seq, 10, Vector2.ZERO)
		if interaction != null:
			# THE CAST HOLDS IT THE CAST'S WAY (DECISIONS #156): nothing tells the rod it is fishing;
			# the body plays the cast, and the rod reads that.
			interaction.interact_requested.emit(99)
			await _anim_frames(movement, seq, 40, Vector2.ZERO)
			var cast_w: Dictionary[StringName, float] = driver.semantic_weights()
			_check(driver.action_playing() and float(cast_w.get(AnimationSet.INTERACT, 0.0)) > 0.99,
				"a cast: the driver says the body is showing the cast (%s)" % cast_w)
			var fishing: Dictionary = _rod_in_hand(skel, rod)
			var want_cast: Transform3D = file_grip.resolve(AnimationSet.INTERACT, rod.body_type).in_hand(
				rod.hand_now(), skel.global_basis)
			_check(_near(fishing["drawn"] as Transform3D, want_cast) and _near(fishing["in_hand"] as Transform3D, want_cast)
					and not _near(want_cast, want_carry),
				"and the rod is drawn where the grip file's grip for the cast puts it (%s), not the idle's"
					% (fishing["drawn"] as Transform3D).origin)
			var cast_wait: int = 0
			while driver.action_playing() and cast_wait < 400:
				await _anim_frames(movement, seq, 1, Vector2.ZERO)
				cast_wait += 1
			await _anim_frames(movement, seq, 40, Vector2.ZERO)
			_check(_near(rod.held_in_hand(), file_grip.resolve(AnimationSet.IDLE, rod.body_type).in_hand(
					rod.hand_now(), skel.global_basis)),
				"and once the cast is over it is back in the idle's grip")
			# PUT AWAY (DECISIONS #158): slung on the back while she is not fishing, drawn to fish.
			# The stow plays on the UPPER BODY: she walks on through it.
			_check(rod.can_stow(), "the grip file has a place to put the rod away (Fit Stow)")
			# The idle clock, short here (the fisher's own is longer); speed is checked after.
			var idle_was: float = equip.away_after_sec
			var faster_was: EquipComponent.Gait = equip.away_when_faster_than
			equip.away_after_sec = 1.5
			equip.away_when_faster_than = EquipComponent.Gait.NEVER
			equip.away_when_idle = true
			var stow_bone: int = skel.find_bone(String(file_grip.stow_bone))
			var thigh: int = skel.find_bone("thigh_r")
			var thigh_first: Quaternion = Quaternion.IDENTITY
			var thigh_most: float = 0.0
			var upper_seen: bool = false
			var waited_back: int = 0
			while not rod.is_stowed() and waited_back < 400:
				await _anim_frames(movement, seq, 1, Vector2(0.0, -0.4))
				waited_back += 1
				if driver.upper_playing():
					var q: Quaternion = skel.get_bone_pose_rotation(thigh)
					if not upper_seen:
						thigh_first = q
					upper_seen = true
					thigh_most = maxf(thigh_most, rad_to_deg(thigh_first.angle_to(q)))
			var packed_when_slung: float = rod.packed()
			print("   put away after %d frames walking; her right thigh swung %.0f deg while the stow played" % [waited_back, thigh_most])
			_check(rod.is_stowed() and upper_seen and driver.upper_clip() == &"Sword_Exit"
					and driver.current_state() == AnimationTreeBuilder.STATE_GROUNDED,
				"not fishing, she puts the rod away: the stow plays on her upper body while she walks on, grounded (that it leaves her legs to the walk: the animation suite)")
			await _anim_frames(movement, seq, 2, Vector2.ZERO)
			var slung: Transform3D = skel.global_transform * skel.get_bone_global_pose(stow_bone) * file_grip.stow_transform()
			var rod_hold: Transform3D = rod.global_transform * rod.hold_offset()
			_check(_near(rod_hold, slung) and rod.wrist_turn_now(skel).is_equal_approx(Basis.IDENTITY),
				"and it rides on her %s where the grip file slings it (%.1f mm off), her wrist left alone"
					% [file_grip.stow_bone, rod_hold.origin.distance_to(slung.origin) * 1000.0])
			# PACKED SHORT (DECISIONS #161, Luke's choice). Slung from the shoulder at its full 1.85 m,
			# the rod's tip dragged on the ground behind her. On her back it is the grip file's stow
			# length, packed in her hand before the stow let go of it.
			var full_reach: float = (rod.get_node(^"Tip") as Node3D).position.distance_to(rod.hold_offset().origin)
			var slung_reach: float = rod.tip_position().distance_to(rod_hold.origin)
			var tip_up: float = rod.tip_position().y - skel.global_position.y
			print("   slung: the tip %.2f m from the hold (%.2f m drawn), %.2f m off the ground" % [slung_reach, full_reach, tip_up])
			_check(file_grip.stow_length < 0.6 and absf(slung_reach - full_reach * file_grip.stow_length) < 0.01
					and tip_up > 0.5 and packed_when_slung > 0.99,
				"and it is packed to %.0f%% of its length on her back (its tip %.2f m off the ground), all the way before it landed there (%.2f)"
					% [file_grip.stow_length * 100.0, tip_up, packed_when_slung])
			# Another player's cast arrives already playing (their public rows): their rod is in their
			# hand at once. (Our own waits for the draw: the aim suite.) She is shown as someone else's
			# angler for this.
			feedback.is_local_authority = false
			interaction.interact_requested.emit(99)
			await _anim_frames(movement, seq, 2, Vector2.ZERO)
			_check(not rod.is_stowed() and driver.action_playing() and equip.is_equipped(),
				"another player's cast, already playing with the rod on their back, puts it in their hand at once")
			feedback.is_local_authority = true
			var back_wait: int = 0
			while not rod.is_stowed() and back_wait < 600:
				await _anim_frames(movement, seq, 1, Vector2.ZERO)
				back_wait += 1
			# DRAWN: asked for again, she draws it on her upper body, and the hand takes it part way
			# through the draw, when the equip state says it is in hand.
			equip.away_when_idle = false
			equip.needed()
			await _anim_frames(movement, seq, 2, Vector2.ZERO)
			_check(rod.is_stowed() and driver.upper_playing() and driver.upper_clip() == &"Sword_Enter",
				"wanted in the hand again, she draws it: the draw plays on her upper body, the rod still slung for now")
			var drawn_wait: int = 0
			while rod.is_stowed() and drawn_wait < 200:
				await _anim_frames(movement, seq, 1, Vector2.ZERO)
				drawn_wait += 1
			_check(not rod.is_stowed() and driver.upper_playing() and equip.is_equipped(),
				"and her hand takes it during the draw (%d frames in), as the equip state says it is in hand" % drawn_wait)
			var stretch_until: int = Time.get_ticks_msec() + int(HeldItem.PACK_SEC * 1000.0) + 200
			while Time.get_ticks_msec() < stretch_until:
				await _anim_frames(movement, seq, 1, Vector2.ZERO)
			var drawn_hold: Vector3 = (rod.global_transform * rod.hold_offset()).origin
			_check(rod.packed() < 0.01 and absf(rod.tip_position().distance_to(drawn_hold) - full_reach) < 0.01,
				"and in her hand it stretches out to its full length again (%.2f m)" % rod.tip_position().distance_to(drawn_hold))
			# PUT AWAY TO RUN. Luke: "tweak the stow rate (from immediately even when standing still
			# like it is now, to 10 seconds of idle or moving past walking speed)". In hand and
			# unused: standing, and walking, keep it out past the old 1.5 s; running puts it away in a
			# moment, the stow playing while she runs. NEVER is the control: she runs on with it. (She
			# goes backwards: the walks above left her at a wall.)
			equip.away_after_sec = idle_was
			equip.away_when_faster_than = EquipComponent.Gait.WALK
			equip.away_when_idle = true
			equip.set_equipped_now(true)
			await _anim_seconds(movement, seq, 2.0, Vector2.ZERO)
			var kept_standing: bool = equip.is_equipped()
			var walked_at: float = 0.0
			var kept_walking: bool = true
			var until_walk: int = Time.get_ticks_msec() + 1500
			while Time.get_ticks_msec() < until_walk:
				await _anim_frames(movement, seq, 1, Vector2(0.0, 1.0), false, false, true)
				walked_at = maxf(walked_at, equip.moving_speed())
				kept_walking = kept_walking and equip.is_equipped()
			_check(idle_was >= 10.0 and kept_standing and kept_walking and walked_at > 0.5 and walked_at < equip.faster_than_speed(),
				"unused, standing 2 s and walking 1.5 s (at %.1f m/s) leave the rod in her hand (the fisher waits %.0f s)" % [walked_at, idle_was])
			equip.away_when_faster_than = EquipComponent.Gait.NEVER
			var ran_at: float = 0.0
			var kept_running: bool = true
			var until_run: int = Time.get_ticks_msec() + 1000
			while Time.get_ticks_msec() < until_run:
				await _anim_frames(movement, seq, 1, Vector2(0.0, 1.0))
				ran_at = maxf(ran_at, equip.moving_speed())
				kept_running = kept_running and equip.is_equipped()
			_check(kept_running and ran_at > MovementConfig.shared().walk_speed * EquipComponent.GAIT_MARGIN,
				"the control: told never to put it away for speed, she runs a second (%.1f m/s) with it in hand" % ran_at)
			equip.away_when_faster_than = EquipComponent.Gait.WALK
			var run_start: int = Time.get_ticks_msec()
			var stow_after: float = -1.0
			var stow_shown_running: bool = false
			while not rod.is_stowed() and Time.get_ticks_msec() - run_start < 3000:
				await _anim_frames(movement, seq, 1, Vector2(0.0, 1.0))
				if stow_after < 0.0 and equip.state() == EquipComponent.State.STOWING:
					stow_after = float(Time.get_ticks_msec() - run_start) / 1000.0
				if driver.upper_playing() and driver.upper_clip() == &"Sword_Exit" and equip.moving_speed() > equip.faster_than_speed():
					stow_shown_running = true
			print("   running, the put-away began %.2f s in" % stow_after)
			_check(stow_after >= equip.away_moving_after_sec - 0.05 and stow_after < equip.away_moving_after_sec + 0.3
					and stow_shown_running and rod.is_stowed(),
				"told to put it away above a walk, running puts it away %.2f s in, the stow playing as she runs" % stow_after)
			# THE HAND STAYS SHUT (DECISIONS #160). The jump's clip flings the fingers wide; holding the
			# rod they stay shut round it, as the skeleton is drawn (read during its update: the
			# fingers are put back after it). Put away, the hand is free: the control.
			var curls: Array[float] = []
			var closed_by: Array[float] = []
			var in_air := func() -> void:
				if driver.current_state() == AnimationTreeBuilder.STATE_AIR:
					var hh: Dictionary = GripFit.hole(skel, file_grip.hand, false)
					if not hh.is_empty():
						curls.append(float(hh["curl_deg"]))
						closed_by.append(rod.fist_closed())
			skel.skeleton_updated.connect(in_air)
			equip.away_when_idle = false
			var jumps: Array[Array] = []
			for held: bool in [false, true]:
				equip.set_equipped_now(held)
				await _anim_frames(movement, seq, 30, Vector2.ZERO)
				curls.clear()
				closed_by.clear()
				await _anim_frames(movement, seq, 1, Vector2.ZERO, true)
				var air_wait: int = 0
				while (curls.size() < 10 or driver.current_state() == AnimationTreeBuilder.STATE_AIR) and air_wait < 120:
					await _anim_frames(movement, seq, 1, Vector2.ZERO)
					air_wait += 1
				jumps.append([curls.duplicate(), closed_by.duplicate(), rod.is_stowed()])
			skel.skeleton_updated.disconnect(in_air)
			var loose: Array = jumps[0][0]
			var shut: Array = jumps[1][0]
			var loose_max: float = loose.max() if not loose.is_empty() else 999.0
			var shut_min: float = shut.min() if not shut.is_empty() else -1.0
			print("   jumping with the rod put away her fingers curl at most %.0f deg; holding it, at least %.0f deg (%d and %d frames in the air)"
				% [loose_max, shut_min, loose.size(), shut.size()])
			_check(bool(jumps[0][2]) and loose.size() >= 10 and loose_max < 60.0 and (jumps[0][1] as Array).max() == 0.0,
				"CONTROL: jumping with the rod put away, her hand opens as the clip has it (at most %.0f deg)" % loose_max)
			_check(not bool(jumps[1][2]) and shut.size() >= 10 and shut_min >= GripFit.FIST_CURL_DEG and (jumps[1][1] as Array).min() > 0.9,
				"jumping with it in her hand, her fingers stay shut round it (at least %.0f deg, a fist)" % shut_min)
			equip.away_after_sec = idle_was
			equip.away_when_faster_than = faster_was
			equip.away_when_idle = true

	# --- death and revival ------------------------------------------------------------------
	if health != null:
		health.died.emit(0)
		var died: bool = await _wait_for_state(driver, movement, seq,
			AnimationTreeBuilder.STATE_DEAD, 40)
		_check(died, "dying travels to the death state (%s)" % driver.current_state())
		health.revived.emit()
		var up: bool = await _wait_for_state(driver, movement, seq,
			AnimationTreeBuilder.STATE_GROUNDED, 60)
		_check(up, "and reviving comes back to Grounded (%s)" % driver.current_state())

	await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)



## DOES THE CHARACTER STAND UP? Every other animation test can pass while the character animates
## flawlessly lying on its back — which is exactly what shipped: the FBX library's conversion
## from Z-up centimetres lived on a node, that node was dropped when the tracks were re-addressed,
## and the result was an upright-looking pose graph driving a body face-down in the floor with
## its pelvis 9 mm off the ground.
##
## So this measures the posed skeleton in metres, for clips out of BOTH libraries: a head above
## a pelvis above a pair of feet, at human height, in this game's units.
func _run_pose_tests() -> void:
	print("== animation: the character stands up ==")
	var set: AnimationSet = load(FISHER_SET) as AnimationSet
	var model_scene: PackedScene = load("res://game/characters/mannequin_f.glb") as PackedScene
	if set == null or model_scene == null:
		_check(false, "the fisher set and the default model load")
		return
	for semantic: StringName in [AnimationSet.IDLE, AnimationSet.WALK, AnimationSet.RUN,
			AnimationSet.JUMP_START, AnimationSet.INTERACT]:
		var clip: StringName = set.anim_name(semantic)
		await _check_pose(model_scene, set, semantic, clip)
	# AND EVERY LOOK THE GAME DRESSES SOMEONE IN. Each is assembled from separate pieces onto one
	# skeleton (ModularCharacter), so a piece bound to the wrong bones, or a head scaled unlike its
	# clothes, is a character that does not stand up — measured the same way.
	for look: PackedScene in _shipped_looks():
		print("   look %s" % look.resource_path.get_file())
		for semantic: StringName in [AnimationSet.IDLE, AnimationSet.RUN, AnimationSet.INTERACT]:
			await _check_pose(look, set, semantic, set.anim_name(semantic))


## THE UPPER BODY LEAVES THE LEGS ALONE (DECISIONS #158). Two of the same character, their
## generated trees advanced in step, one firing the stow on its upper body: its legs must match
## the other's exactly while its arm does not. Watching one character walk could not tell: the
## sword clip moves the legs too, and a thigh swung as far with the filter off.
func _check_upper_body_filter(set: AnimationSet) -> void:
	var scene: PackedScene = load("res://game/characters/mannequin_f.glb") as PackedScene
	var skels: Array[Skeleton3D] = []
	var trees: Array[AnimationTree] = []
	var models: Array[Node3D] = []
	for k: int in range(2):
		var model: Node3D = scene.instantiate() as Node3D
		get_tree().root.add_child(model)
		var skel: Skeleton3D = null
		for n: Node in _walk_nodes(model):
			if n is Skeleton3D:
				skel = n
		skel.name = "Skeleton3D"
		var tree: AnimationTree = AnimationTreeBuilder.build(set)
		model.add_child(tree)
		tree.root_node = tree.get_path_to(skel.get_parent())
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		tree.active = true
		models.append(model)
		skels.append(skel)
		trees.append(tree)
	var upper_clip: AnimationNodeAnimation = (trees[0].tree_root as AnimationNodeBlendTree).get_node(
		AnimationTreeBuilder.NODE_UPPER_CLIP) as AnimationNodeAnimation
	AnimationTreeBuilder.apply_clip(upper_clip, set, ItemGrip.STOW)
	for t: AnimationTree in trees:
		t.advance(0.0)
	trees[0].set(AnimationTreeBuilder.P_UPPER_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var legs: float = 0.0
	var arm: float = 0.0
	for step: int in range(48):
		for t: AnimationTree in trees:
			t.advance(1.0 / 60.0)
		for bone: String in ["pelvis", "thigh_r", "calf_r", "thigh_l", "calf_l"]:
			var b: int = skels[0].find_bone(bone)
			legs = maxf(legs, rad_to_deg(skels[0].get_bone_pose_rotation(b).angle_to(skels[1].get_bone_pose_rotation(b))))
		var u: int = skels[0].find_bone("upperarm_r")
		arm = maxf(arm, rad_to_deg(skels[0].get_bone_pose_rotation(u).angle_to(skels[1].get_bone_pose_rotation(u))))
	_check(legs < 0.5 and arm > 20.0,
		"the stow on the UPPER BODY moves her arm (%.0f deg from the same body not stowing) and leaves her hips and legs as they were (%.2f deg)"
			% [arm, legs])
	for m: Node3D in models:
		m.free()


func _check_pose(model_scene: PackedScene, set: AnimationSet, semantic: StringName,
		clip: StringName) -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
	get_tree().root.add_child(model)
	var skel: Skeleton3D = null
	for n: Node in _walk_nodes(model):
		if n is Skeleton3D:
			skel = n
	if skel == null:
		_check(false, "the model has a skeleton")
		model.queue_free()
		return

	# One clip, nothing else: no blending, no state machine, so what is measured is the clip.
	var tree := AnimationTree.new()
	for lib_name: StringName in set.libraries:
		tree.add_animation_library(lib_name, set.libraries[lib_name])
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	tree.tree_root = node
	model.add_child(tree)
	tree.root_node = tree.get_path_to(skel.get_parent())
	tree.active = true

	# SAMPLE ACROSS THE CLIP, not at one arbitrary instant. "Four frames in" lands at a different
	# point of every clip — `Jump_Start` plays at x4.17 and four frames put it deep in its crouch,
	# where the head genuinely is below human height — so the measurement flickered against its
	# own threshold run to run. What the check means is "this clip is a human standing up", and
	# the honest way to ask that is: upright at EVERY sample, human-sized at its tallest.
	# Three properties, each asked at the moment it means something. A run lifts a foot 0.4 m and
	# a take-off crouches, so neither "feet down always" nor "upright always" is true of a
	# correct clip — asking those of one arbitrary frame is what made this flicker.
	var tallest: float = -INF          # scale: is this a person or a model in centimetres?
	var pelvis_at_tallest: float = 0.0 # uprightness, asked where the character is standing up
	var foot_at_tallest: float = 0.0
	var planted: float = INF           # the PLANTED foot: does it ever reach the ground?
	for i: int in range(12):
		for f: int in range(3):
			await get_tree().process_frame
		var head: float = _bone_y(skel, "Head")
		var foot: float = _bone_y(skel, "foot_l")
		planted = minf(planted, absf(foot))
		if head > tallest:
			tallest = head
			pelvis_at_tallest = _bone_y(skel, "pelvis")
			foot_at_tallest = foot
	print("   %-18s %-16s tallest head %.2f (pelvis %.2f, foot %.2f)  planted foot %.2f"
		% [semantic, clip, tallest, pelvis_at_tallest, foot_at_tallest, planted])
	_check(tallest > pelvis_at_tallest + 0.4 and pelvis_at_tallest > foot_at_tallest + 0.4,
		"%s stands up at its tallest: head %.2f over pelvis %.2f over foot %.2f"
			% [clip, tallest, pelvis_at_tallest, foot_at_tallest])
	_check(tallest > 1.2 and tallest < 2.0,
		"%s is human-sized, in metres: head reaches %.2f m" % [clip, tallest])
	_check(planted < 0.35,
		"%s puts a foot on the ground the entity stands on (closest %.2f m)" % [clip, planted])
	model.queue_free()
	await get_tree().process_frame


## Every model the fishing game dresses an entity in: each angler look and the rival's.
func _shipped_looks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	var rival: EntityDefinition = load("res://game/fishing/rival_definition.tres") as EntityDefinition
	if fisher != null:
		out.append_array(fisher.visual_variants)
	if rival != null and rival.visual_for(0) != null:
		out.append(rival.visual_for(0))
	return out


## CHARACTERS PUT TOGETHER FROM PIECES (ModularCharacter): what a look is made of, and who wears
## which. The pose suite measures them animating; this checks the assembly itself, which can be
## wrong in ways a pose would not show — a piece left on a skeleton of its own renders in its
## rest pose, frozen, next to a character that animates perfectly.
const PIECES_DIR: String = "res://game/characters/quaternius/models/"
const LOD_CONTROL: String = "res://game/world/kits/nature/Birch_1.gltf"

## How many LODs the renderer holds for a mesh's surfaces (the most of any surface).
static func _lod_count(mesh: Mesh) -> int:
	var most: int = 0
	if mesh == null:
		return 0
	for s: int in range(mesh.get_surface_count()):
		var surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		most = maxi(most, (surf.get("lods", []) as Array).size())
	return most


func _run_character_tests() -> void:
	print("== characters: looks ==")
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	_check(fisher != null and fisher.visual_variants.size() >= 2,
		"anglers come in several looks (%d)" % (fisher.visual_variants.size() if fisher != null else 0))
	if fisher == null:
		return
	# WHO WEARS WHAT: by entity id, the same on every client, and neighbours never match.
	var n: int = fisher.visual_variants.size()
	var seen: Dictionary[PackedScene, bool] = {}
	for id: int in range(n):
		seen[fisher.visual_for(id)] = true
	_check(seen.size() == n, "%d consecutive entity ids wear %d different looks" % [n, seen.size()])
	_check(fisher.visual_for(n + 3) == fisher.visual_for(3) and fisher.visual_for(-1) == fisher.visual_for(n - 1),
		"and the choice is a pure function of the id, wrapping (and safe for any id)")
	var plain := EntityDefinition.new()
	plain.visual_scene = fisher.visual_variants[0]
	_check(plain.visual_for(12345) == plain.visual_scene, "a definition with no variants wears its one model")

	for look: PackedScene in _shipped_looks():
		var name: String = look.resource_path.get_file()
		var model: ModularCharacter = look.instantiate() as ModularCharacter
		_check(model != null, "%s is a ModularCharacter" % name)
		if model == null:
			continue
		# Assembled by instantiate() alone, before it is in any tree: the spawner and the
		# animation driver may look for its skeleton before its _ready ever runs.
		var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		var skel: Skeleton3D = model.skeleton()
		_check(skels.size() == 1 and skel != null and skels[0] == skel,
			"%s comes out of instantiate() on ONE skeleton (%d)" % [name, skels.size()])
		# Into the tree the way the spawner puts it: the headless renderer objects to freeing a
		# mesh with material overrides that was never in one.
		get_tree().root.add_child(model)
		if skel == null:
			model.queue_free()
			continue
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		var loose: Array[String] = []
		var unbound: Array[String] = []
		for node: Node in meshes:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.get_parent() != skel or mi.skeleton != NodePath(".."):
				loose.append(String(mi.name))
			if mi.skin != null:
				for b: int in range(mi.skin.get_bind_count()):
					var bone: StringName = mi.skin.get_bind_name(b)
					if bone == &"" or skel.find_bone(bone) < 0:
						unbound.append("%s:%s" % [mi.name, bone])
						break
		_check(meshes.size() > (model as ModularCharacter).parts.size(),
			"%s wears its head and every piece (%d meshes for %d pieces)" % [name, meshes.size(), model.parts.size()])
		_check(loose.is_empty(), "%s: every mesh is on the one skeleton (%s)" % [name, str(loose)])
		_check(unbound.is_empty(), "%s: every skin binds bones the skeleton has, by name (%s)" % [name, str(unbound)])
		_check(skel.get_bone_count() == 65, "%s has the 65-bone skeleton the clips are for (%d)" % [name, skel.get_bone_count()])
		var brows: Array[String] = []
		for node: Node in meshes:
			if is_instance_valid(node) and String(node.name).begins_with("Eyebrows"):
				brows.append(String(node.name))
		_check(brows.size() == 1, "%s has one pair of eyebrows, not the head's and its own (%s)" % [name, str(brows)])
		# EVERY PIECE SITS ON THIS BODY. A skin's bind poses are where its piece expects each bone
		# to be; the head's skeleton is where each bone IS. A piece modelled on another body (or a
		# head from another pack) would pass every check above and float off its wearer.
		var worst: float = 0.0
		var worst_at: String = ""
		for node: Node in meshes:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.skin == null:
				continue
			for i: int in range(mi.skin.get_bind_count()):
				var bone: int = skel.find_bone(mi.skin.get_bind_name(i))
				if bone < 0:
					continue
				var expected: Transform3D = mi.skin.get_bind_pose(i).affine_inverse()
				var off: float = expected.origin.distance_to(skel.get_bone_global_rest(bone).origin)
				if off > worst:
					worst = off
					worst_at = "%s/%s" % [mi.name, mi.skin.get_bind_name(i)]
		_check(worst < 0.005, "%s: every piece is bound where the head's skeleton has its bones (worst %.4f m at %s)"
			% [name, worst, worst_at])
		model.queue_free()

	# NO LODS ON A WORN PIECE (DECISIONS #177). The pieces are worn in layers a millimetre apart, and
	# an LOD simplifies each one on its own: at 8 m the buzzed hair sank into the scalp and the skin
	# showed through it in spots. The renderer's own surface data says what it would draw at a
	# distance; a kit tree, imported with LODs, proves this check can see them.
	var tree: Node = (load(LOD_CONTROL) as PackedScene).instantiate()
	var control_lods: int = 0
	for node: Node in tree.find_children("*", "MeshInstance3D", true, false):
		control_lods = maxi(control_lods, _lod_count((node as MeshInstance3D).mesh))
	tree.free()
	_check(control_lods > 0, "the check sees LODs where an import made them (%d on %s)" % [control_lods, LOD_CONTROL.get_file()])
	var with_lods: Array[String] = []
	var pieces: int = 0
	for f: String in DirAccess.get_files_at(PIECES_DIR):
		if not f.ends_with(".gltf"):
			continue
		pieces += 1
		var piece: Node = (load(PIECES_DIR + f) as PackedScene).instantiate()
		for node: Node in piece.find_children("*", "MeshInstance3D", true, false):
			if _lod_count((node as MeshInstance3D).mesh) > 0:
				with_lods.append("%s/%s" % [f.get_basename(), node.name])
		piece.free()
	_check(pieces >= 50 and with_lods.is_empty(),
		"none of the %d character pieces has an LOD to sink into the one under it (%s)" % [pieces, str(with_lods)])

	# COLOURS ARE PER CHARACTER. The pieces share their imported materials, so a tint written to
	# the shared one would dress every character in the last one's hair colour.
	var a: ModularCharacter = fisher.visual_variants[0].instantiate() as ModularCharacter
	var b: ModularCharacter = fisher.visual_variants[0].instantiate() as ModularCharacter
	var c: ModularCharacter = fisher.visual_variants[2].instantiate() as ModularCharacter
	for m: ModularCharacter in [a, b, c]:
		get_tree().root.add_child(m)
	var hair_of := func(m: ModularCharacter) -> StandardMaterial3D:
		for node: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node as MeshInstance3D
			for i: int in range(mi.mesh.get_surface_count()):
				var src: Material = mi.mesh.surface_get_material(i)
				if src != null and src.resource_name.begins_with(ModularCharacter.HAIR_PREFIX):
					return mi.get_surface_override_material(i) as StandardMaterial3D
		return null
	var ha: StandardMaterial3D = hair_of.call(a)
	var hb: StandardMaterial3D = hair_of.call(b)
	var hc: StandardMaterial3D = hair_of.call(c)
	_check(ha != null and hc != null and ha.albedo_color.is_equal_approx(a.hair_color)
			and hc.albedo_color.is_equal_approx(c.hair_color),
		"each look's hair is its own colour (%s, %s)"
			% [str(ha.albedo_color) if ha != null else "none", str(hc.albedo_color) if hc != null else "none"])
	_check(ha != null and hb != null and ha == hb,
		"two anglers in the same look share that look's copy rather than one each")
	var shared: bool = false
	for node: Node in a.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src != null and src.resource_name.begins_with(ModularCharacter.HAIR_PREFIX) \
					and not src.albedo_color.is_equal_approx(Color.WHITE):
				shared = true
	_check(not shared, "and the imported material itself is left as it came")
	for m: ModularCharacter in [a, b, c]:
		m.queue_free()


## The rod over `frames` frames of `dir`: the least air between its reel and the leg (m), the most
## its axis turned from where it started, in the body's frame (deg), and the least room between
## the rod and the head (m, from a ball of HEAD_RADIUS round the head bone).
const HEAD_RADIUS: float = 0.12

func _measure_rod(m: SpaceTimeMovementComponent, seq_ref: Array[int], skel: Skeleton3D,
		rod: FishingRod, dir: Vector2, frames: int) -> Dictionary:
	var air: float = INF
	var swing: float = 0.0
	var head: float = INF
	var first: Vector3 = Vector3.ZERO
	var reel: Node3D = rod.get_node(^"Reel") as Node3D
	var tip: Node3D = rod.get_node(^"Tip") as Node3D
	var head_bone: int = skel.find_bone("Head")
	for i: int in range(frames):
		await _anim_frames(m, seq_ref, 1, dir)
		air = minf(air, float(BodyClearance.measure(skel, reel.global_position, float(reel.get_meta(BodyClearance.META)))["air"]))
		var axis: Vector3 = (skel.global_basis.inverse() * rod.global_transform.basis.y).normalized()
		if first == Vector3.ZERO:
			first = axis
		swing = maxf(swing, rad_to_deg(first.angle_to(axis)))
		var h: Vector3 = skel.global_transform * skel.get_bone_global_pose(head_bone).origin
		head = minf(head, BodyClearance.to_segment(h, rod.global_position, tip.global_position) - HEAD_RADIUS)
	return {"air": air, "swing": swing, "head": head}


## The rod's HOLD in the frame of the hand holding it (DECISIONS #158): as the rod was last placed
## in the hand the skeleton drew, the wrist turned ("in_hand"), and as both are DRAWN ("drawn":
## physics interpolation is on, and the renderer reads that transform).
func _rod_in_hand(_skel: Skeleton3D, rod: FishingRod) -> Dictionary:
	var attach: Node3D = rod.get_parent() as Node3D
	return {
		"in_hand": rod.hand_now().affine_inverse() * rod.global_transform * rod.hold_offset(),
		"drawn": attach.get_global_transform_interpolated().affine_inverse()
			* rod.get_global_transform_interpolated() * rod.hold_offset(),
	}


func _hand_of(skel: Skeleton3D, grip: ItemGrip) -> Transform3D:
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone(String(grip.hand)))


## Two transforms within a millimetre and a third of a degree: a held item eases its animation
## weights, so a few parts in ten thousand of a neighbouring grip can still be in it.
## About the thickness of a forearm in its sleeve (m), for measuring an arm against the body.
const ARM_RADIUS: float = 0.04


## The least air of each forearm (elbow to wrist) off the torso over `frames` updates of
## `skel`, as drawn (read during the update, the IK and the wrist applied): {"left", "right"}.
func _forearms_off_torso(skel: Skeleton3D, frames: int) -> Dictionary:
	var least: Dictionary = {"left": INF, "right": INF}
	var watch := func() -> void:
		var torso: Array[Array] = []
		for part: Array in BodyClearance.posed(skel):
			if String(part[0]) == "torso":
				torso.append(part)
		for side: String in ["left", "right"]:
			var s: String = "_l" if side == "left" else "_r"
			var air: float = float(BodyClearance.measure_posed(torso, BodyClearance.bone_at(skel, StringName("lowerarm" + s)),
				BodyClearance.bone_at(skel, StringName("hand" + s)), ARM_RADIUS)["air"])
			least[side] = minf(float(least[side]), air)
	skel.skeleton_updated.connect(watch)
	await _tick_frames(frames)
	skel.skeleton_updated.disconnect(watch)
	return least


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.001 \
		and Quaternion(a.basis.orthonormalized()).angle_to(Quaternion(b.basis.orthonormalized())) < deg_to_rad(0.3)


func _grip_entry(anim: StringName, pos: Vector3, rot: Vector3, steady: bool) -> GripEntry:
	var e := GripEntry.new()
	e.animation = anim
	e.position = pos
	e.rotation_degrees = rot
	e.steady = steady
	return e


func _bone_y(skel: Skeleton3D, bone: String) -> float:
	var i: int = skel.find_bone(bone)
	return skel.get_bone_global_pose(i).origin.y if i >= 0 else NAN


func _walk_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c: Node in n.get_children():
		out.append_array(_walk_nodes(c))
	return out


## A REMOTE character animates too — that is most of the point of mirroring `move_state`
## (DECISIONS #82). No input here: rows from the server are the only thing driving it.
func _run_remote_animation_tests() -> void:
	print("== animation: a remote character ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	var defn: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	if reg == null or spawner == null or packed == null or defn == null:
		_check(false, "autoloads, level and fisher definition present")
		return
	var level: Node3D = packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	var world_root: Node3D = level.get_node(^"WorldRoot") as Node3D
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true
	reg.local_entity_id = -1            # nothing here is ours
	var eid: int = 5202
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var other: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(other != null and not other.is_local_authority, "a remote fisher spawned")
	if other == null:
		await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)
		return
	var driver: AnimationDriverComponent = other.find_component(
		AnimationDriverComponent) as AnimationDriverComponent
	var movement: SpaceTimeMovementComponent = other.find_component(
		SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_check(driver != null and driver.is_animating(),
		"and it animates: the driver does not care whose entity it is")

	if driver == null or movement == null:
		await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)
		return

	# Snapshots of somebody walking, exactly as the server sends them.
	var clock: Array = [0]
	movement._clock_override = func() -> int: return int(clock[0])
	var t0: int = 20_000_000
	for i: int in range(4):
		var row := FakeMoveRow.new(eid, Vector3(float(i) * 0.25, 0.0, 0.0), t0 + i * 50_000)
		row.vel = Vector3(5.0, 0.0, 0.0)
		row.move_state = MovementState.Move.WALK
		row.last_processed_seq = i + 1
		movement.receive_row_event(_move_ev(row))
	clock[0] = t0 + 120_000
	for i: int in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
		clock[0] += 16_000
	print("   remote blend %.2f, state %s" % [driver.speed_blend(), driver.current_state()])
	_check(driver.speed_blend() > 0.3,
		"a walking remote player is animated as walking (%.2f)" % driver.speed_blend())

	# And standing still stops it: IDLE is authoritative, so interpolation noise cannot leave a
	# remote character shuffling on the spot for ever.
	for i: int in range(4):
		var row := FakeMoveRow.new(eid, Vector3(1.0, 0.0, 0.0), t0 + 400_000 + i * 50_000)
		row.move_state = MovementState.Move.IDLE
		row.last_processed_seq = 10 + i
		movement.receive_row_event(_move_ev(row))
	clock[0] = t0 + 520_000
	for i: int in range(30):
		await get_tree().physics_frame
		await get_tree().process_frame
		clock[0] += 16_000
	_check(driver.speed_blend() < 0.1,
		"and a stopped one settles back to idle (%.2f)" % driver.speed_blend())

	# A REMOTE take-off is announced from the rows, while the interpolated view still has the
	# character standing on the ground — it is drawn ~100 ms in the past (DECISIONS #75). The
	# driver must not read that as "already landed" and swap the take-off for a landing.
	movement.jumped.emit()
	for i: int in range(12):
		await get_tree().physics_frame
		await get_tree().process_frame
		clock[0] += 16_000
	_check(driver.current_state() == AnimationTreeBuilder.STATE_JUMP_START,
		"a remote take-off survives a view that still shows its feet on the ground (%s)"
			% driver.current_state())
	await _teardown_anim(reg, spawner, eid, prev_local, prev_ready, level)


# --- animation helpers --------------------------------------------------------------------

## Physics frames that also let the render clock run: the body is driven by `push_input` on the
## physics tick, the AnimationTree advances on the idle tick, and this suite needs both.
func _anim_frames(m: SpaceTimeMovementComponent, seq_ref: Array[int], n: int,
		move_dir: Vector2, jump: bool = false, sprint: bool = false, slow: bool = false) -> void:
	for i: int in range(n):
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		f.move_dir = move_dir
		f.jump = jump
		f.sprint = sprint
		f.slow = slow
		m.push_input(f)
		await get_tree().process_frame


## Drive `move_dir` for `secs` of ANIMATION time. Frame counts are the wrong clock for anything
## measured against a clip's length: see the comment at the call site.
func _anim_seconds(m: SpaceTimeMovementComponent, seq_ref: Array[int], secs: float,
		move_dir: Vector2, slow: bool = false) -> void:
	var until: int = Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await _anim_frames(m, seq_ref, 1, move_dir, false, false, slow)


## Like `_anim_frames`, but also telling the body which way to face.
func _anim_frames_facing(m: SpaceTimeMovementComponent, seq_ref: Array[int], n: int,
		move_dir: Vector2, yaw: float) -> void:
	for i: int in range(n):
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		f.move_dir = move_dir
		f.look_yaw = yaw
		m.push_input(f)
		await get_tree().process_frame


## Drop the character from a height holding `dir`, and count the frames it spends in the landing
## recovery. Returns 0 if it never enters one.
func _fall_and_time_landing(driver: AnimationDriverComponent, m: SpaceTimeMovementComponent,
		seq_ref: Array[int], dir: Vector2) -> int:
	var drop := FakeMoveRow.new(m.entity_id, Vector3(-3.0, 3.0, 3.0), 9_600_000 + seq_ref[0])
	drop.last_processed_seq = seq_ref[0]
	drop.correction_epoch = m.get_epoch() + 1
	drop.teleport_flag = true
	drop.grounded = false
	m.receive_row_event(_move_ev(drop))
	var frames: int = 0
	var seen: bool = false
	for i: int in range(240):
		await _anim_frames(m, seq_ref, 1, dir)
		if driver.current_state() == AnimationTreeBuilder.STATE_LAND:
			frames += 1
			seen = true
		elif seen:
			break
	return frames


## Step the character until its state machine reaches `state`. Frame COUNTS are not a clock
## here — a headless run can take several physics steps inside one idle frame — so every wait
## in this suite is for the thing itself.
func _wait_for_state(driver: AnimationDriverComponent, m: SpaceTimeMovementComponent,
		seq_ref: Array[int], state: StringName, max_steps: int) -> bool:
	for i: int in range(max_steps):
		if driver.current_state() == state:
			return true
		await _anim_frames(m, seq_ref, 1, Vector2.ZERO)
	return driver.current_state() == state


func _pose_of(skel: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i: int in range(skel.get_bone_count()):
		out.append(skel.get_bone_pose_rotation(i))
	return out


## Total rotation between two poses, in radians. Zero means the skeleton did not move at all.
func _pose_delta(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var total: float = 0.0
	for i: int in range(mini(a.size(), b.size())):
		total += absf(a[i].angle_to(b[i]))
	return total


func _teardown_anim(reg: Node, spawner: Node, eid: int, prev_local: int, prev_ready: bool,
		level: Node3D) -> void:
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame


func _run_greybox_tests() -> void:
	print("== greybox scene ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var bus: Node = _autoload("SignalBus")
	if reg == null or spawner == null or bus == null:
		_check(false, "autoloads present")
		return

	var packed: PackedScene = load(GREYBOX_SCENE) as PackedScene
	_check(packed != null, "greybox.tscn loads")
	if packed == null:
		return
	var level: Node3D = packed.instantiate() as Node3D
	_check(level != null, "greybox root is a Node3D")
	if level == null:
		return
	get_tree().root.add_child(level)

	# The level ships the geometry a moving body will need.
	_check(level.has_node(^"Floor/Collision"), "level has floor collision")
	_check(level.has_node(^"WallEast/Collision"), "level has wall collision")
	_check(level.has_node(^"SpawnPoint"), "level has a spawn point")
	var world_root: Node3D = level.get_node(^"WorldRoot") as Node3D
	_check(world_root != null, "level exposes a WorldRoot for spawned entities")

	# --- spawn a real player through the real spawner --------------------------------
	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.scene = load(PLAYER_SCENE) as PackedScene
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true

	var eid: int = 4242
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))

	var player: Node = spawner.get_entity_node(eid)
	_check(player != null, "player spawned into the level")
	if player == null:
		level.queue_free()
		return
	_check(player.get_parent() == world_root, "player is parented under WorldRoot")
	_check(player.is_bound(), "player bound inside the level")
	_check(player is CharacterBody3D, "player root is a CharacterBody3D")
	_check(player.has_node(^"CollisionShape3D"), "player carries a collision shape")

	# ORIGIN AT THE FEET. The movement model's `pos.y == ground_y` means standing on the ground,
	# and the module spawns players there. With the origin at the capsule's centre the lower
	# half started inside the floor, and the player could not walk until a jump lifted it out.
	var shape_node: CollisionShape3D = player.get_node(^"CollisionShape3D") as CollisionShape3D
	var capsule: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	_check(capsule != null and absf(shape_node.position.y - capsule.height * 0.5) < 1e-4,
		"the capsule's bottom sits exactly at the body origin (origin at the feet)")
	var placeholder: Node3D = player.get_node_or_null(^"Visual/Model") as Node3D
	_check(placeholder != null and absf(placeholder.position.y - capsule.height * 0.5) < 1e-4,
		"the greybox model is lifted to match, so it stands on the floor too")

	# PHYSICS LAYERS. Entities collide with the world, never with each other: a remote entity
	# is drawn ~100 ms in the past, and every player spawns on the same point.
	var cb: CharacterBody3D = player as CharacterBody3D
	_check(cb.collision_layer == SpaceTimeEntity.ENTITY_MASK,
		"entity bodies live on the entity layer (got %d)" % cb.collision_layer)
	_check(cb.collision_mask == SpaceTimeEntity.WORLD_MASK | SpaceTimeEntity.BARRIER_MASK,
		"entity bodies collide with the world and its barriers, never each other (mask %d)"
		% cb.collision_mask)
	var floor_body: StaticBody3D = level.get_node(^"Floor") as StaticBody3D
	_check(floor_body.collision_layer & SpaceTimeEntity.WORLD_MASK != 0,
		"level geometry is on the world layer the bodies collide with")

	# Every component the scene ships is bound, not just the ones a unit test constructs.
	var comps: Array = player.get_components()
	_check(comps.size() >= 2, "player has its components (got %d)" % comps.size())
	var bound_all: bool = true
	for c: SpaceTimeComponent in comps:
		if not c.is_bound():
			bound_all = false
	_check(bound_all, "every component on the spawned scene is bound")

	var movement: SpaceTimeMovementComponent = null
	for c: SpaceTimeComponent in comps:
		if c is SpaceTimeMovementComponent:
			movement = c
	_check(movement != null, "player scene carries a movement component")

	# --- real frames move the body through the level ---------------------------------
	if movement != null:
		# Drive the clock ourselves so interpolation is deterministic under real frames.
		var clock: Array = [0]
		movement._clock_override = func() -> int: return int(clock[0])
		var t0: int = 10_000_000
		for i: int in range(3):
			var row := FakeMoveRow.new(eid, Vector3(float(i) * 2.0, 1.0, 0.0), t0 + i * 50_000)
			movement.receive_row_event(_move_ev(row))

		# Render time at the first snapshot: the body should sit at the start of the path.
		clock[0] = t0 + 100_000
		await get_tree().physics_frame
		await get_tree().physics_frame
		var start_pos: Vector3 = (player as CharacterBody3D).position
		_check(start_pos.is_equal_approx(Vector3(0, 1, 0)),
			"after real frames the body sits at the first snapshot (got %s)" % start_pos)

		# Advance the clock to the midpoint of the last span and let frames run: the
		# component's own _physics_process must move it, with nothing calling update_view().
		clock[0] = t0 + 75_000 + 100_000
		await get_tree().physics_frame
		await get_tree().physics_frame
		var mid_pos: Vector3 = (player as CharacterBody3D).position
		_check(mid_pos.is_equal_approx(Vector3(3, 1, 0)),
			"_physics_process drives interpolation unaided (got %s)" % mid_pos)
		_check(mid_pos.x > start_pos.x, "the body actually travelled across the level")

	# --- the view: exactly one camera, and it is the local player's -------------------
	# Nothing below this line is visible headless, which is precisely why it is asserted here.
	# `CameraRig._ready()` runs when the spawner adds an entity to the tree, BEFORE `bind()`
	# knows whose entity it is, so the rig cannot decide this for itself. When it tried, no
	# camera was ever made current and the game rendered nothing — while the HUD, a CanvasLayer,
	# kept drawing. The symptom was a grey screen with a working UI, and no error anywhere.
	_check(not player.has_node(^"CameraRig"),
		"a REMOTE entity's camera rig is freed, so it cannot take the view")

	var prev_local: int = reg.local_entity_id
	var local_eid: int = 4243
	reg.local_entity_id = local_eid
	_buffer_player_rows(reg, local_eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(local_eid, 0)))
	var mine: Node = spawner.get_entity_node(local_eid)
	_check(mine != null and mine.is_local_authority, "the local entity bound as local authority")
	if mine != null:
		_check(mine.has_node(^"CameraRig"), "the local entity keeps its camera rig")
		_check(not mine.has_node(^"Nameplate"), "the local entity drops its own nameplate")
		var cam: Camera3D = mine.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
		_check(cam != null and cam.current,
			"the local player's camera is CURRENT (without this the screen is grey)")
		_check(cam != null and get_viewport().get_camera_3d() == cam,
			"the viewport is actually looking through that camera")
		var currents: int = _count_current_cameras(get_tree().root)
		_check(currents == 1,
			"exactly one camera is current in the whole tree (got %d)" % currents)

	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(local_eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local

	# --- JUMPING, through the real resolver on the real floor --------------------------
	# Reported: "jump breaks after a few jumps (or by jumping near a wall) and then I can't jump."
	# No test ever jumped on flat ground. This one does it twenty times, open floor and against a
	# wall, driving push_input exactly as LocalInputComponent does, one frame per physics tick.
	var jumper_eid: int = 4244
	var prev_local_j: int = reg.local_entity_id
	reg.local_entity_id = jumper_eid
	_buffer_player_rows(reg, jumper_eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(jumper_eid, 0)))
	var jumper: SpaceTimeEntity = spawner.get_entity_node(jumper_eid) as SpaceTimeEntity
	_check(jumper != null and jumper.is_local_authority, "a local, predicted jumper spawned in the level")
	if jumper != null:
		var jm: SpaceTimeMovementComponent = jumper.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		var ji: LocalInputComponent = jumper.find_component(LocalInputComponent) as LocalInputComponent
		ji.set_physics_process(false)   # this test drives the frames itself
		var jseq: Array[int] = [1000]
		var landings: Array[String] = []
		var failed_at: int = -1
		for n: int in range(20):
			# Vary the approach so the landings fall at different phases; the last eight run
			# into the east wall (inner face x = 9.5).
			var dir: Vector2 = Vector2(sin(float(n) * 1.7), -cos(float(n) * 1.7)) * (0.3 + 0.07 * float(n % 10))
			if n >= 12:
				dir = Vector2(1.0, 0.0)
				if n == 12:
					await _place_predicted(jm, Vector3(8.5, 0.0, 0.0), jseq)
			var start_y: float = jumper.global_position.y
			var peak: float = start_y
			var landed: bool = false
			for f: int in range(150):
				var frame := InputFrame.new()
				jseq[0] += 1
				frame.seq = jseq[0]
				frame.move_dir = dir
				frame.jump = f == 0
				# Inside the physics frame, exactly where LocalInputComponent calls it.
				await get_tree().physics_frame
				jm.push_input(frame)
				peak = maxf(peak, jumper.global_position.y)
				if f > 5 and jm.get_predicted_state().grounded:
					landed = true
					break
			landings.append("%d:%.2fm%s" % [n, peak - start_y, "" if landed else "(no landing)"])
			if failed_at < 0 and (peak - start_y < 1.0 or not landed):
				failed_at = n
		_check(failed_at < 0,
			"twenty consecutive jumps each leave the ground and land (first failure at jump %d): %s"
				% [failed_at, " ".join(landings)])
		var rest_y: float = jumper.global_position.y
		_check(jm.get_predicted_state().grounded and rest_y < 0.001,
			"after the last landing the body rests ON the floor and is grounded (y=%.4f)" % rest_y)

		# THE DEAD ZONE, constructed directly. Twenty jumps from y = 0 all follow one vertical
		# path, so they all land at the same phase — and that phase misses the band, which is
		# why the loop above passed even against the broken code. In play the phase varies
		# (off a step edge, off a wall, out of a clamp cycle); here it is swept. Each drop starts
		# at rest, not grounded, h above the floor. The old model clamped the fall at y = 0 and
		# zeroed it BEFORE move_and_slide, so any h between the 1 mm tolerance and one frame's
		# first fall step (5.6 mm) hovered there for ever.
		var stuck: Array[String] = []
		for h: float in [0.0015, 0.002, 0.003, 0.004, 0.005, 0.0055, 0.01, 0.05, 0.13, 0.6]:
			await _place_predicted(jm, Vector3(-3.0, h, -3.0), jseq, 0)
			var settled: bool = false
			for f: int in range(40):
				await get_tree().physics_frame
				var idle := InputFrame.new()
				jseq[0] += 1
				idle.seq = jseq[0]
				jm.push_input(idle)
				if jm.get_predicted_state().grounded:
					settled = true
					break
			var y0: float = jumper.global_position.y
			var up: float = 0.0
			for f: int in range(40):
				await get_tree().physics_frame
				var jf := InputFrame.new()
				jseq[0] += 1
				jf.seq = jseq[0]
				jf.jump = f == 0
				jm.push_input(jf)
				up = maxf(up, jumper.global_position.y - y0)
			if not settled or up < 1.0:
				stuck.append("h=%.4f(settled=%s, jump=%.2fm, rest y=%.4f)" % [h, settled, up, y0])
		_check(stuck.is_empty(), "a body dropped from ANY small height lands and can jump again: %s"
			% (" ".join(stuck) if not stuck.is_empty() else "all ten did"))

		# SLOPES (PHASE4_SPEC §2.3). `max_slope_deg` (45) reaches move_and_slide as
		# floor_max_angle. Ramp30 climbs from the floor at z = -2.03 to the platform top
		# (y = 1.75) at z = 1; Ramp55 is steeper than the limit.
		# Probe the geometry THROUGH THE ENGINE first. The ramps were first written with their
		# basis column by column; .tscn stores it row by row, so both sloped the WRONG way and
		# a Python check that decoded them the same wrong way agreed. A downward ray is what
		# Godot actually sees.
		var space: PhysicsDirectSpaceState3D = jumper.get_world_3d().direct_space_state
		for probe: Array in [["Ramp30", Vector3(5.0, 4.0, -1.0), 0.595, 30.0], ["Ramp55", Vector3(-6.5, 4.0, -6.7), 1.0, 55.0]]:
			var q := PhysicsRayQueryParameters3D.create(probe[1], probe[1] + Vector3.DOWN * 8.0, SpaceTimeEntity.WORLD_MASK)
			var hit: Dictionary = space.intersect_ray(q)
			var ok_hit: bool = not hit.is_empty() and (hit["collider"] as Node).name == probe[0]
			var hy: float = (hit["position"] as Vector3).y if ok_hit else -1.0
			var ang: float = rad_to_deg((hit["normal"] as Vector3).angle_to(Vector3.UP)) if ok_hit else -1.0
			_check(ok_hit and absf(hy - float(probe[2])) < 0.02 and absf(ang - float(probe[3])) < 0.5,
				"%s surface is where the level says: hit y=%.3f (want %.3f) at %.1f deg (want %.0f)"
					% [probe[0], hy, probe[2], ang, probe[3]])
		await _place_predicted(jm, Vector3(5.0, 0.0, -4.0), jseq)
		for f: int in range(120):   # walk +Z: two metres of floor, the ramp, onto the platform
			await get_tree().physics_frame
			var wf := InputFrame.new()
			jseq[0] += 1
			wf.seq = jseq[0]
			wf.move_dir = Vector2(0.0, 1.0)
			jm.push_input(wf)
		await _frames_idle(jm, jseq, 20)
		var on_top: Vector3 = jumper.global_position
		_check(absf(on_top.y - 1.75) < 0.05 and on_top.z > 1.0 and jm.get_predicted_state().grounded,
			"walking (no jump) up the 30 degree ramp arrives on the platform top (at %s)" % on_top)

		# Standing still halfway up it: no sliding back down.
		await _place_predicted(jm, Vector3(5.0, 1.0, -0.5), jseq, 45)
		var perch: Vector3 = jumper.global_position
		await _frames_idle(jm, jseq, 90)
		var slid: float = jumper.global_position.distance_to(perch)
		_check(jm.get_predicted_state().grounded and slid < 0.02 and perch.y > 0.7,
			"standing on the 30 degree slope, the body stays put (moved %.3f m at y=%.2f)" % [slid, perch.y])

		# The 55 degree ramp is a wall to walk up, not a floor.
		await _place_predicted(jm, Vector3(-6.5, 0.0, -4.5), jseq)
		var steep_peak: float = 0.0
		for f: int in range(90):
			await get_tree().physics_frame
			var sf := InputFrame.new()
			jseq[0] += 1
			sf.seq = jseq[0]
			sf.move_dir = Vector2(0.0, -1.0)
			jm.push_input(sf)
			steep_peak = maxf(steep_peak, jumper.global_position.y)
		_check(steep_peak < 0.5,
			"walking into the 55 degree ramp does not climb it: steeper than max_slope_deg (peak y=%.2f)" % steep_peak)
		ji.set_physics_process(true)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(jumper_eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local_j

	# --- death signal reaches the bus from inside a real scene -----------------------
	var deaths: Array[int] = []
	var dcb := func(e: int, _k: int) -> void: deaths.append(e)
	bus.entity_died.connect(dcb)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(eid, 100.0, 100.0), FakeHealthRow.new(eid, 0.0, 100.0, true, 7)))
	_check(deaths == [eid], "a health row routed through the live scene reaches entity_died")
	bus.entity_died.disconnect(dcb)

	# --- despawn tears the scene down -------------------------------------------------
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	_check(spawner.get_entity_node(eid) == null, "despawn removed the player from the level")
	_check(not reg.has_entity(eid), "despawn unregistered the entity")

	level.queue_free()
	await get_tree().process_frame


const LAKESIDE_SCENE: String = "res://game/world/lakeside.tscn"
const LAKESIDE_ASSETS: String = "res://game/world/terrain/lakeside_assets.tres"
const NATURE_KIT: String = "res://game/world/kits/nature/"


## THE LINE, DRAWN. Reported: "the line looks strange as it arcs into the water on long casts" —
## it sagged by its length whatever was under it, so a 40 m line dived under the lake halfway
## out and came back up at the float. Slack line droops from the rod tip until it meets the water
## and lies on it from there; it never runs under the surface.
## THE ROD IN THE HAND (DECISIONS #147): the grip file the game reads, the steady carry's
## geometry, and the editor preview that writes the file — driven the way the gizmo drives it.
func _run_rod_grip_tests() -> void:
	print("== held items: the grip ==")
	# --- ONE GRIP: the gizmo's place in, the same place out ------------------------------------
	var hand := Transform3D(Basis.from_euler(Vector3(0.4, 1.1, -0.3), EULER_ORDER_YXZ), Vector3(0.5, 1.2, -0.3))
	var body := Basis(Vector3.UP, 0.7)
	var want := Transform3D(Basis.from_euler(Vector3(0.3, -1.2, 0.5), EULER_ORDER_YXZ), Vector3(0.6, 1.25, -0.2))
	var e := GripEntry.new()
	_check(e.set_held(want, hand, body) and (hand * e.in_hand(hand, body)).is_equal_approx(want),
		"a grip taken from the gizmo puts the item back exactly where the gizmo was")
	_check(not e.set_held(want, hand, body), "setting the same place again changes nothing")
	var d: Vector3 = e.rotation_degrees
	e.rotation_degrees = Vector3(180.0 - d.x, d.y + 180.0, d.z + 180.0)
	_check(not e.set_held(want, hand, body) and e.rotation_degrees == Vector3(180.0 - d.x, d.y + 180.0, d.z + 180.0),
		"nor does the same turn spelled another way — and the spelling typed is kept")
	# STEADY: the direction kept to the BODY, the grip still in the hand.
	var s := GripEntry.new()
	s.position = Vector3(0.0, 0.1, 0.0)
	s.rotation_degrees = Vector3(20.0, 40.0, 0.0)
	var turned := Transform3D(hand.basis.rotated(Vector3.RIGHT, 0.8), hand.origin + Vector3(0.0, 0.1, 0.05))
	var held_before: Transform3D = hand * s.in_hand(hand, body)
	_check(not (turned * s.in_hand(turned, body)).basis.is_equal_approx(held_before.basis),
		"CONTROL: following the hand, the item turns when the hand turns")
	s.set_steady(true, hand, body)
	_check(s.steady and (hand * s.in_hand(hand, body)).is_equal_approx(held_before),
		"made steady, the item does not move in the frame it was made steady in")
	var held_turned: Transform3D = turned * s.in_hand(turned, body)
	_check(held_turned.basis.is_equal_approx(held_before.basis) and held_turned.origin.is_equal_approx(turned * s.position),
		"steady, it keeps its direction when the hand turns, with its grip still in the hand")
	var body2 := Basis(Vector3.UP, 1.9)
	_check((hand * s.in_hand(hand, body2)).basis.is_equal_approx(body2 * body.inverse() * held_before.basis),
		"and it turns with the body")

	# --- WHICH GRIP AN ANIMATION USES (DECISIONS #156) -----------------------------------------
	# Luke: "each item should have two variables, body tweaks and animation tweaks. The mode feels
	# redundant ... I should be able to tie ANY animation to either body exactly as it looks best,
	# and anytime that animation is called (from modes or other means) the item should match."
	var g := ItemGrip.new()
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.1, 0.0), Vector3.ZERO, false))
	g.entries.append(_grip_entry(AnimationSet.RUN, Vector3(0.0, 0.2, 0.0), Vector3(0.0, 90.0, 0.0), false))
	g.entries.append(_grip_entry(&"fishing.heave", Vector3(0.0, 0.3, 0.0), Vector3.ZERO, false))
	_check(is_equal_approx(g.resolve(AnimationSet.RUN).position.y, 0.2)
			and g.resolve(AnimationSet.RUN_LEFT).animation == AnimationSet.RUN
			and g.resolve(AnimationSet.SPRINT).animation == AnimationSet.RUN
			and is_equal_approx(g.resolve(&"fishing.heave").position.y, 0.3),
		"an animation uses its own grip, and one whose clip falls back to it borrows it (run_left, sprint)")
	_check(g.resolve(AnimationSet.WALK).animation == AnimationSet.IDLE and g.resolve(&"fishing.wait").animation == AnimationSet.IDLE
			and g.resolve(AnimationSet.INTERACT).animation == AnimationSet.IDLE and g.resolve(&"").animation == AnimationSet.IDLE,
		"and every animation with no grip anywhere along its fallbacks borrows the idle's, a genre's own included")
	_check(ItemGrip.steps(AnimationSet.SPRINT) == ([AnimationSet.SPRINT, AnimationSet.RUN, AnimationSet.WALK, AnimationSet.IDLE] as Array[StringName])
			and ItemGrip.steps(&"fishing.heave") == ([&"fishing.heave", AnimationSet.IDLE] as Array[StringName]),
		"the steps a sprint looks at: sprint, run, walk, idle; a genre's heave: itself, then the idle")
	_check(ItemGrip.new().resolve(AnimationSet.RUN) == null and g.animations() == ([AnimationSet.IDLE, AnimationSet.RUN, &"fishing.heave"] as Array[StringName]),
		"a grip file with no grips has none to give, and a file lists the animations it has grips for")
	var walk: GripEntry = g.ensure(AnimationSet.WALK)
	_check(is_equal_approx(walk.position.y, 0.1) and g.entries.size() == 4 and g.ensure(AnimationSet.WALK) == walk
			and g.resolve(AnimationSet.RUN).animation == AnimationSet.RUN,
		"giving the walk its own grip starts it where the walk had the item (the idle's), once; the run keeps its own")
	_check(g.remove(AnimationSet.WALK) and g.resolve(AnimationSet.WALK).animation == AnimationSet.IDLE
			and not g.remove(AnimationSet.IDLE) and g.find(AnimationSet.IDLE) != null,
		"taking it away makes it borrow again; the idle's shared grip, which everything borrows, is not taken away")
	# BLENDED AS THE ANIMATIONS BLEND.
	var half: Transform3D = g.blend({AnimationSet.IDLE: 0.5, AnimationSet.RUN: 0.5}, Transform3D(), Basis())
	_check(half.origin.is_equal_approx(Vector3(0.0, 0.15, 0.0))
			and absf(rad_to_deg(Quaternion(half.basis).get_angle()) - 45.0) < 0.01,
		"half idle and half run: half way between their grips, in place and in turn (%s)" % half.origin)
	_check(g.blend({AnimationSet.IDLE: 0.5, &"fishing.heave": 0.5}, Transform3D(), Basis()).origin.is_equal_approx(Vector3(0.0, 0.2, 0.0)),
		"half way through blending into the heave: half way to the heave's grip")
	_check(g.blend({}, Transform3D(), Basis()).origin.is_equal_approx(Vector3(0.0, 0.1, 0.0)),
		"told no animation, the idle's grip")
	# PER BODY (DECISIONS #155): Luke, "can I not just change the position of the female body?"
	# Her own grip wins over the shared one at the same step — and only there: the run's own grip,
	# shared, still beats her idle grip while she runs.
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.15, 0.0), Vector3.ZERO, false))
	g.entries[g.entries.size() - 1].body = &"female"
	_check(is_equal_approx(g.resolve(AnimationSet.IDLE, &"female").position.y, 0.15)
			and is_equal_approx(g.resolve(AnimationSet.IDLE, &"male").position.y, 0.1)
			and is_equal_approx(g.resolve(AnimationSet.IDLE).position.y, 0.1),
		"an idle grip kept for the female body is hers alone: the male body and an unknown one keep the shared")
	_check(is_equal_approx(g.resolve(AnimationSet.WALK, &"female").position.y, 0.15)
			and is_equal_approx(g.resolve(AnimationSet.RUN, &"female").position.y, 0.2),
		"her walk borrows her idle grip, and the run's own grip, shared, still beats it while she runs")
	var her_run: GripEntry = g.ensure(AnimationSet.RUN, &"female")
	_check(is_equal_approx(her_run.position.y, 0.2) and her_run.body == &"female"
			and g.resolve(AnimationSet.SPRINT, &"female") == her_run
			and is_equal_approx(g.resolve(AnimationSet.SPRINT, &"male").position.y, 0.2),
		"her own run grip starts where her run was, and her sprint borrows it; his sprint the shared run's")
	_check(g.bodies() == ([&"female"] as Array[StringName])
			and g.blend({AnimationSet.IDLE: 1.0}, Transform3D(), Basis(), &"female").origin.is_equal_approx(Vector3(0.0, 0.15, 0.0)),
		"the game blends with her grips when it knows she is the one holding it")
	_check(g.remove(AnimationSet.IDLE, &"female") and is_equal_approx(g.resolve(AnimationSet.IDLE, &"female").position.y, 0.1),
		"taking her idle grip away gives her the shared one")

	# --- THE BODY: capsules round its bones, built to measure ------------------------------------
	var sk := Skeleton3D.new()
	for spec: Array in [["thigh_r", -1, Vector3(0.1, 1.0, 0.0)], ["calf_r", 0, Vector3(0.0, -0.5, 0.0)],
			["foot_r", 1, Vector3(0.0, -0.4, 0.0)], ["thigh_l", -1, Vector3(-0.1, 1.0, 0.0)],
			["calf_l", 3, Vector3(0.0, -0.5, 0.0)], ["foot_l", 4, Vector3(0.0, -0.4, 0.0)],
			["spine_01", -1, Vector3(0.0, 1.05, 0.0)], ["neck_01", 6, Vector3(0.0, 0.5, 0.0)],
			["Head", 7, Vector3(0.0, 0.1, 0.0)]]:
		var i: int = sk.add_bone(String(spec[0]))
		sk.set_bone_parent(i, int(spec[1]))
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, spec[2]))
		sk.set_bone_pose_position(i, spec[2])
	add_child(sk)
	var by_thigh: Dictionary = BodyClearance.measure(sk, Vector3(0.4, 0.75, 0.0), 0.03)
	_check(is_equal_approx(float(by_thigh["air"]), 0.3 - 0.10 - 0.03) and by_thigh["part"] == "right thigh",
		"a ball 30 cm off the right thigh has that, less the thigh and itself, of air (%.3f m, %s)"
			% [by_thigh["air"], by_thigh["part"]])
	_check(float(BodyClearance.measure(sk, Vector3(0.0, 1.3, 0.1), 0.0)["air"]) < 0.0
			and BodyClearance.measure(sk, Vector3(0.0, 1.3, 0.1), 0.0)["part"] == "torso",
		"and one at the chest is inside the torso")
	var thing := Node3D.new()
	var marked := Node3D.new()
	marked.name = "Pommel"
	marked.set_meta(BodyClearance.META, 0.02)
	thing.add_child(marked)
	thing.add_child(Node3D.new())
	_check(BodyClearance.points_of(thing) == ([marked] as Array[Node3D]),
		"an item is measured at the nodes it marks with a clearance_radius, and only those")
	thing.free()
	# A LINE (#156): a rod's blank swept through the head while both its ends stayed clear, and the
	# preview, measuring only the reel, called the run green.
	var head_at: Vector3 = Vector3(0.0, 1.65 + BodyClearance.HEAD_UP, 0.0)
	var left_end: Vector3 = head_at + Vector3(-0.5, 0.0, 0.0)
	var right_end: Vector3 = head_at + Vector3(0.5, 0.0, 0.0)
	_check(float(BodyClearance.measure(sk, left_end, 0.01)["air"]) > 0.3 and float(BodyClearance.measure(sk, right_end, 0.01)["air"]) > 0.3,
		"CONTROL: two points half a metre either side of the head are well clear of it")
	var through: Dictionary = BodyClearance.measure_line(sk, left_end, right_end, 0.01)
	_check(is_equal_approx(float(through["air"]), -0.12 - 0.01) and through["part"] == "head",
		"and the line between them goes through it: %.3f m of air, against the %s" % [through["air"], through["part"]])
	_check(is_equal_approx(BodyClearance.between_segments(Vector3(0.3, 0.8, -1.0), Vector3(0.3, 0.8, 1.0), Vector3(0.1, 1.0, 0.0), Vector3(0.1, 0.5, 0.0)), 0.2),
		"a line crossing in front of a bone is as far from it as the gap between them (0.2 m)")
	var blade := Node3D.new()
	var base := Node3D.new()
	base.name = "Base"
	base.set_meta(BodyClearance.META, 0.01)
	base.set_meta(BodyClearance.LINE_TO, NodePath("../Point"))
	var point := Node3D.new()
	point.name = "Point"
	blade.add_child(base)
	blade.add_child(point)
	add_child(blade)
	base.global_position = left_end
	point.global_position = right_end
	var blade_air: Dictionary = BodyClearance.item_air(sk, blade)
	_check(float(blade_air["air"]) < 0.0 and blade_air["part"] == "head" and blade_air["point"] == "Base",
		"an item's node with a clearance_to meta is measured as a line to that node (%s against the %s)"
			% [blade_air["point"], blade_air["part"]])
	blade.queue_free()
	var rod_marks: Array[String] = []
	var rod_inst: Node = (load("res://game/fishing/fishing_rod.tscn") as PackedScene).instantiate()
	for n: Node3D in BodyClearance.points_of(rod_inst):
		rod_marks.append("%s%s" % [n.name, " -> %s" % n.get_meta(BodyClearance.LINE_TO) if n.has_meta(BodyClearance.LINE_TO) else ""])
	rod_inst.free()
	_check(rod_marks == (["Reel", "Shaft -> ../Tip"] as Array[String]),
		"the rod is measured at its reel, and along its blank to the tip (%s)" % ", ".join(rod_marks))
	sk.queue_free()

	# --- THE HOLE A HAND MAKES (DECISIONS #157) -----------------------------------------------------
	# Four fingers curled round a circle 2.5 cm in radius whose line runs along the hand's z, centred
	# at (0.03, 0.09): the fit finds the circle, its line, and that it is a fist. The same fingers
	# held straight are not one.
	var hand_sk := Skeleton3D.new()
	var hand_bone: int = hand_sk.add_bone("hand_r")
	var finger_z: Dictionary[String, float] = {"index": 0.03, "middle": 0.01, "ring": -0.01, "pinky": -0.03}
	var round_deg: Array[float] = [180.0, 90.0, 0.0, -60.0]
	var joint_names: Array[String] = ["_01", "_02", "_03", "_04_leaf"]
	for f: String in finger_z:
		for j: int in range(4):
			var b: int = hand_sk.add_bone(f + joint_names[j] + "_r")
			hand_sk.set_bone_parent(b, hand_bone)
			var a: float = deg_to_rad(round_deg[j])
			var at: Vector3 = Vector3(0.03 + 0.025 * cos(a), 0.09 + 0.025 * sin(a), finger_z[f])
			hand_sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, at))
			hand_sk.set_bone_pose_position(b, at)
	add_child(hand_sk)
	var curled: Dictionary = GripFit.hole(hand_sk, &"hand_r")
	# THE HOLE IS INSIDE THE FIST (DECISIONS #158): the biggest circle walled by the palm (the wrist
	# to the knuckle), the curled finger and the gap from the fingertip back to the wrist. A circle
	# through the finger joints alone (centre (0.03, 0.09), 2.5 cm) crosses that gap 2.2 cm from its
	# centre: a handle there showed through the fingers.
	var ring: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for j: int in range(4):
		var aj: float = deg_to_rad(round_deg[j])
		ring.append(Vector2(0.03 + 0.025 * cos(aj), 0.09 + 0.025 * sin(aj)))
	var c2: Vector2 = Vector2((curled.get("centre", Vector3.INF) as Vector3).x, (curled.get("centre", Vector3.INF) as Vector3).y)
	var r2: float = float(curled.get("radius", 0.0))
	var nearest_wall: float = INF
	for k: int in range(ring.size()):
		nearest_wall = minf(nearest_wall, c2.distance_to(Geometry2D.get_closest_point_to_segment(c2, ring[k], ring[(k + 1) % ring.size()])))
	_check(not curled.is_empty() and (curled["axis"] as Vector3).angle_to(Vector3(0.0, 0.0, 1.0)) < 0.01
			and is_equal_approx((curled["centre"] as Vector3).z, 0.01) and bool(curled["fist"]),
		"fingers curled round a handle: its line runs across the knuckles, and the hand is a fist")
	_check(Geometry2D.is_point_in_polygon(c2, ring) and nearest_wall >= r2 - 0.0005 and r2 >= 0.019,
		"and the hole is the biggest circle inside the fist: centre %s, %.1f cm across the bones, touching no wall (nearest %.1f cm)"
			% [c2, r2 * 100.0, nearest_wall * 100.0])
	var old_centre: Vector2 = Vector2(0.03, 0.09)
	var old_wall: float = INF
	for k: int in range(ring.size()):
		old_wall = minf(old_wall, old_centre.distance_to(Geometry2D.get_closest_point_to_segment(old_centre, ring[k], ring[(k + 1) % ring.size()])))
	_check(old_wall < 0.025, "CONTROL: the circle through the finger joints (2.5 cm) reaches through the fist's mouth, %.1f cm from its centre" % (old_wall * 100.0))
	for f: String in finger_z:
		for j: int in range(4):
			hand_sk.set_bone_pose_position(hand_sk.find_bone(f + joint_names[j] + "_r"),
				Vector3(0.03, 0.09 + 0.02 * float(j), finger_z[f]))
	var straight: Dictionary = GripFit.hole(hand_sk, &"hand_r")
	_check(not bool(straight["fist"]) and float(straight["curl_deg"]) < 45.0,
		"and the same fingers held straight are no fist (curled %.0f deg)" % float(straight["curl_deg"]))
	hand_sk.queue_free()

	# IN THE EDITOR ONLY TOOL SCRIPTS RUN. The first grip preview stood empty there while this suite
	# passed: the looks' assembly did not run, and the preview called a method on the animation
	# set, a data class there. A headless run cannot see either, so check the source.
	var preview_src: String = FileAccess.get_file_as_string("res://foundation/held/held_item_preview.gd")
	var editor_calls: Array[String] = []
	for m: String in ["anim_name(", "has_exact(", "visual_for(", "missing_required(", "can_strafe(", ".clip(",
			"HeldItem.", "FishingRod.", "held_in_hand(", "set_mode("]:
		if preview_src.contains(m):
			editor_calls.append(m)
	_check(editor_calls.is_empty(), "the preview calls no method of a class that is data in the editor (%s)"
		% ", ".join(editor_calls))
	var tools: Array[String] = []
	for f: String in ["res://game/characters/modular_character.gd", "res://foundation/held/grip_entry.gd",
			"res://foundation/held/item_grip.gd", "res://foundation/held/body_clearance.gd",
			"res://foundation/held/off_hand.gd", "res://foundation/held/held_item_preview.gd"]:
		if not FileAccess.get_file_as_string(f).begins_with("@tool"):
			tools.append(f.get_file())
	_check(tools.is_empty(), "and what it does call runs in the editor: the looks, the grip, the body (%s)" % ", ".join(tools))

	# --- THE PREVIEW, driven as the gizmo drives it. It runs at runtime too; only the editor writes
	# the file. It edits a COPY here, and its pose and looks are set here: the scene saves whatever
	# the last person to edit it left.
	var scene: PackedScene = load("res://game/fishing/rod_grip_preview.tscn") as PackedScene
	var prev: Node3D = scene.instantiate() as Node3D if scene != null else null
	_check(prev != null, "the grip preview scene loads")
	if prev == null:
		return
	var file_grip: ItemGrip = prev.get("grip") as ItemGrip
	_check(file_grip != null and file_grip.resource_path == "res://game/fishing/rod_grip.tres",
		"it edits the grip file the game reads")
	var rod_scene: PackedScene = load("res://game/fishing/fishing_rod.tscn") as PackedScene
	var in_game: FishingRod = rod_scene.instantiate() as FishingRod
	_check(in_game.grip == file_grip, "and the game's rod reads that same file")
	in_game.free()
	var file_before: String = _grip_text(file_grip)
	var fixture: ItemGrip = _item_grip_from(GRIP_147)
	prev.set("grip", fixture)
	prev.set("look", 5)
	prev.set("beside", 0)
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "both")
	prev.set("pose_at", 0.0)
	prev.set("play", false)
	add_child(prev)
	for i: int in range(4):
		await get_tree().process_frame
	var bodies: int = prev.call("body_count")
	_check(bodies == 2 and str(prev.call("look_name", 0)).ends_with("_f") and str(prev.call("look_name", 1)).ends_with("_m"),
		"it shows the grip on a woman and a man: every look is one of those two bodies")
	if bodies != 2:
		prev.queue_free()
		return
	_check(prev.call("body_type_of", 0) == &"female" and prev.call("body_type_of", 1) == &"male",
		"and it knows which body each is, from its look (%s, %s)" % [prev.call("body_type_of", 0), prev.call("body_type_of", 1)])
	var grip_node: Node3D = prev.get_node(^"Grip") as Node3D
	var idle_grip: GripEntry = fixture.find(AnimationSet.IDLE)
	var h0: Transform3D = prev.call("hand_of", 0)
	var shown: Node3D = prev.call("item_of", 0)
	var his: Node3D = prev.call("item_of", 1)
	var label: Label3D = prev.call("label_of", 0)
	_check(_hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0)))
			and grip_node.global_transform.is_equal_approx(_hold_at(shown))
			and _hold_at(his).is_equal_approx(
				(prev.call("hand_of", 1) as Transform3D) * idle_grip.in_hand(prev.call("hand_of", 1), prev.call("body_of", 1))),
		"standing, the Grip node sits in her hand in the idle's grip, and each rod in its own hand")
	_check(prev.call("editing") == idle_grip and prev.call("holder") == 0
			and label.text.contains("SETTING locomotion.idle · both") and label.text.contains("uses locomotion.idle · both")
			and float(prev.call("worst_air", 0)) >= 0.02 and float(prev.call("worst_air", 1)) >= 0.02
			and label.modulate.r < label.modulate.g,
		"the label says which grip a drag sets and which one she uses, and a grip that clears both bodies through the idle is green (%.1f, %.1f cm)"
			% [float(prev.call("worst_air", 0)) * 100.0, float(prev.call("worst_air", 1)) * 100.0])
	# Where the fixture's grips start: its numbers placed the rod's root, its grips place the hold.
	var idle_from: Vector3 = idle_grip.position
	var heave_from: Vector3 = fixture.find(&"fishing.heave").position
	grip_node.global_position += h0.basis * Vector3(0.0, 0.02, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var heave_grip: GripEntry = fixture.find(&"fishing.heave")
	_check(idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0)) and heave_grip.position == heave_from,
		"moving the Grip node 2 cm along her fingers moves the idle's grip 2 cm along them, and no other animation's (%s)" % idle_grip.position)
	_check(_hold_at(shown).is_equal_approx(grip_node.global_transform), "and the rod goes with it")

	# THE RUN: nobody has set it, so it borrows the idle's. The first drag SETS the run's grip,
	# starting where the rod was; from then on the run's alone moves.
	prev.set("animation", String(AnimationSet.RUN))
	for i: int in range(3):
		await get_tree().process_frame
	var before: Transform3D = _hold_at(shown)
	h0 = prev.call("hand_of", 0)
	_check(prev.call("editing") == null and grip_node.global_transform.is_equal_approx(before)
			and before.is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0)))
			and label.text.contains("not set") and label.text.contains("uses locomotion.idle · both"),
		"in the run, with no grip of its own, the rod is in the idle's grip, and the label says the run's is not set yet")
	grip_node.global_position += h0.basis * Vector3(0.0, 0.03, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var run_own: GripEntry = fixture.find(AnimationSet.RUN)
	_check(run_own != null and prev.call("editing") == run_own
			and run_own.position.is_equal_approx(idle_grip.position + Vector3(0.0, 0.03, 0.0))
			and GripEntry.same_turn(run_own.rotation_degrees, idle_grip.rotation_degrees)
			and idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0))
			and _hold_at(shown).is_equal_approx(grip_node.global_transform),
		"a drag in the run makes the run's own grip where the rod was, moved by the drag; the idle's stays put")
	_check(label.text.contains("uses locomotion.run · both") and not label.text.contains("not set"),
		"and the label says she uses it")
	var held_run: Transform3D = _hold_at(shown)
	prev.set("steady", true)
	for i: int in range(2):
		await get_tree().process_frame
	_check(run_own.steady and _hold_at(shown).basis.is_equal_approx(held_run.basis) and label.text.contains("steady"),
		"ticking Steady makes the run's grip steady without turning the rod (the wrist turns to hold it)")
	prev.call("clear_this_grip")
	for i: int in range(2):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(fixture.find(AnimationSet.RUN) == null and prev.call("editing") == null
			and _hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0))),
		"Clear This Grip takes it away: the run borrows the idle's again")
	# Steady on an animation nobody has set sets it too, where the rod already is.
	prev.set("animation", String(AnimationSet.WALK))
	for i: int in range(3):
		await get_tree().process_frame
	var held_walk: Transform3D = _hold_at(shown)
	prev.set("steady", true)
	for i: int in range(2):
		await get_tree().process_frame
	_check(fixture.find(AnimationSet.WALK) != null and fixture.find(AnimationSet.WALK).steady
			and _hold_at(shown).basis.is_equal_approx(held_walk.basis) and not idle_grip.steady,
		"ticking Steady in the walk, which borrowed, gives the walk a steady grip of its own where the rod was")
	prev.call("clear_this_grip")

	# ONE BODY: her grip alone. The man beside her keeps the shared one.
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "female")
	for i: int in range(3):
		await get_tree().process_frame
	var his_before: Transform3D = _hold_at(his)
	var hers_before: Transform3D = _hold_at(shown)
	_check(prev.call("holder") == 0 and prev.call("editing") == null and grip_node.global_transform.is_equal_approx(hers_before)
			and label.text.contains("SETTING locomotion.idle · female"),
		"choosing the female body puts the Grip node on her rod; her own idle grip is not set yet")
	grip_node.global_position += (prev.call("hand_of", 0) as Transform3D).basis * Vector3(0.04, 0.0, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var her_grip: GripEntry = fixture.find(AnimationSet.IDLE, &"female")
	_check(her_grip != null and her_grip.position.is_equal_approx(idle_grip.position + Vector3(0.04, 0.0, 0.0))
			and _hold_at(his).is_equal_approx(his_before) and not _hold_at(shown).is_equal_approx(hers_before)
			and label.text.contains("uses locomotion.idle · female"),
		"a drag sets her body's own idle grip: the rod moves in HER hand only; his stays where it was")
	prev.set("animation", String(AnimationSet.WALK))
	for i: int in range(3):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(_hold_at(shown).is_equal_approx(h0 * her_grip.in_hand(h0, prev.call("body_of", 0)))
			and (prev.call("label_of", 1) as Label3D).text.contains("uses locomotion.idle · both"),
		"her walk borrows her own idle grip; his, the shared one")
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "both")
	for i: int in range(3):
		await get_tree().process_frame
	_check(prev.call("holder") == 1 and grip_node.global_transform.is_equal_approx(_hold_at(his))
			and (prev.call("label_of", 1) as Label3D).text.contains("SETTING locomotion.idle · both"),
		"setting the shared grip again, the Grip node moves to him: her own grip would not move with it")
	prev.set("body", "male")
	for i: int in range(3):
		await get_tree().process_frame
	_check(prev.call("holder") == 1 and prev.call("editing") == null,
		"choosing the male body puts it on him, for a grip of his own")
	prev.set("body", "female")
	prev.call("clear_this_grip")
	for i: int in range(3):
		await get_tree().process_frame
	_check(fixture.find(AnimationSet.IDLE, &"female") == null and _hold_at(shown).is_equal_approx(hers_before),
		"Clear This Grip gives her the shared grip back")
	prev.set("body", "both")

	# ANY ANIMATION, AS IT IS SET. Luke: "if I'm in carry mode but change the fishing animation, it
	# doesn't take". The heave's grip is the heave's, and no other animation's.
	prev.set("animation", "fishing.heave")
	for i: int in range(3):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(prev.call("editing") == heave_grip
			and grip_node.global_transform.is_equal_approx(h0 * heave_grip.in_hand(h0, prev.call("body_of", 0)))
			and _hold_at(shown).is_equal_approx(grip_node.global_transform),
		"picking the heave puts the rod and the Grip node in the heave's grip, which is what a drag then sets")
	grip_node.global_position += h0.basis * Vector3(0.0, 0.01, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	_check(heave_grip.position.is_equal_approx(heave_from + Vector3(0.0, 0.01, 0.0))
			and fixture.find(&"fishing.wait").position == heave_from
			and idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0)),
		"and a drag there moves the heave's grip alone: the waiting pose's and the idle's stay put")

	# LUKE'S CASE (DECISIONS #152): his carry grip clears the man's leg in the idle's first frame and
	# sits inside the woman's further in. The preview must say so.
	var leg: ItemGrip = _item_grip_from(GRIP_LEG)
	prev.set("grip", leg)
	prev.set("animation", String(AnimationSet.IDLE))
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var his_here: float = prev.call("air_here", 1)
	var hers_worst: float = prev.call("worst_air", 0)
	var his_worst: float = prev.call("worst_air", 1)
	var his_label: Label3D = prev.call("label_of", 1)
	print("   his grip: the man %.1f cm clear in the frame shown, %.1f cm at worst; the woman %.1f cm at worst"
		% [his_here * 100.0, his_worst * 100.0, hers_worst * 100.0])
	_check(his_here >= 0.02, "CONTROL: in the frame shown that grip clears the man (%.1f cm) — all the old preview measured"
		% (his_here * 100.0))
	_check(hers_worst < 0.0 and label.text.contains("INSIDE") and label.modulate.r > label.modulate.g,
		"and the preview shows it inside HER through the idle, in red (%.1f cm): what the game shows" % (hers_worst * 100.0))
	_check(his_worst < 0.02 and his_label.modulate.r > his_label.modulate.g,
		"and red on him too: clear in the frame shown, but %.1f cm at worst further into the clip" % (his_worst * 100.0))

	# Played, the clip goes round and the rods stay in the hands.
	prev.set("grip", fixture)
	prev.set("play", true)
	for i: int in range(2):
		await get_tree().process_frame
	var played_from: Transform3D = prev.call("hand_of", 0)
	await get_tree().create_timer(0.4).timeout
	await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(not h0.is_equal_approx(played_from)
			and _hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0))),
		"ticking play plays the clip, the rod in the moving hand (the hand moved %.1f cm)"
			% (h0.origin.distance_to(played_from.origin) * 100.0))

	# --- FIT (DECISIONS #157) ---------------------------------------------------------------------
	# Luke: "can we not design our rod to fit in the hole that the hand animations use, and then take
	# pictures to get the angle right, with minimal user intervening other than checking the end
	# goal?" The hole, on the real rig: the idle closes the hand round one, the jump opens it.
	prev.set("play", false)
	var her_hole: Dictionary = prev.call("hole_of", 0, AnimationSet.IDLE, 0.0)
	var his_hole: Dictionary = prev.call("hole_of", 1, AnimationSet.IDLE, 0.0)
	var jump_hole: Dictionary = prev.call("hole_of", 0, AnimationSet.JUMP_LOOP, 0.5)
	var jump_open: Dictionary = prev.call("hole_of", 0, AnimationSet.JUMP_LOOP, 0.5, false)
	print("   the fist's hole: hers %.1f cm across the bones (%.1f cm off a circle), his %.1f cm; jumping, the clip curls her fingers %.0f deg, holding the rod %.0f deg"
		% [float(her_hole["radius"]) * 100.0, float(her_hole["error"]) * 100.0, float(his_hole["radius"]) * 100.0,
			float(jump_open["curl_deg"]), float(jump_hole["curl_deg"])])
	_check(bool(her_hole["fist"]) and bool(his_hole["fist"]) and float(her_hole["radius"]) > 0.015
			and float(her_hole["radius"]) < 0.03,
		"standing, both hands close round a hole the fit can find (hers %.1f cm in radius)" % (float(her_hole["radius"]) * 100.0))
	_check(not bool(jump_open["fist"]), "CONTROL: jumping, the clip opens her hand: no fist to fit to")
	# THE HAND STAYS SHUT ROUND IT (DECISIONS #160). Luke: the hand opens while jumping. Holding the
	# rod, the jump's fingers are shut to the idle's fist, so the idle's grip, which the jumps borrow,
	# sits in the same hole.
	_check(bool(jump_hole["fist"]) and (jump_hole["centre"] as Vector3).distance_to(her_hole["centre"] as Vector3) < 0.002,
		"holding the rod, her jumping hand is shut round it: the idle's fist (its hole %.1f mm from the idle's)"
			% ((jump_hole["centre"] as Vector3).distance_to(her_hole["centre"] as Vector3) * 1000.0))
	# CONTROL: Luke's carry grip (#152) is off the fist and inside her leg. FIT THIS GRIP puts the
	# handle in the fist, carried steady toward where the grip file says (tip up and forward), and
	# clear of both bodies through the whole idle — measured by the preview's own labels, not the fit.
	var fitme: ItemGrip = _item_grip_from(GRIP_LEG)
	fitme.carry_point = Vector3(0.0, 1.0, 1.0)
	fitme.fit_face = Vector3(0.0, 1.0, 0.0)
	prev.set("grip", fitme)
	prev.set("body", "both")
	prev.set("animation", String(AnimationSet.IDLE))
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var red_before: float = minf(float(prev.call("worst_air", 0)), float(prev.call("worst_air", 1)))
	_check(red_before < 0.0, "CONTROL: that grip is inside a body through the idle (%.1f cm)" % (red_before * 100.0))
	prev.call("fit_this_grip")
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var idle_fit: GripEntry = fitme.find(AnimationSet.IDLE)
	var mid_fist: Vector3 = ((her_hole["centre"] as Vector3) + (his_hole["centre"] as Vector3)) * 0.5
	_check(idle_fit.position.distance_to(mid_fist) < 0.003,
		"Fit This Grip puts the handle in the fist: %.1f mm from the middle of both hands' holes"
			% (idle_fit.position.distance_to(mid_fist) * 1000.0))
	var carried_dir: Vector3 = (idle_fit.basis() * Vector3.UP).normalized()
	var asked_dir: Vector3 = GripFit.body_dir(fitme.carry_point).normalized()
	print("   fitted idle: %s; carried %.0f deg from tip-up-and-forward" % [prev.call("fit_said"), rad_to_deg(carried_dir.angle_to(asked_dir))])
	_check(idle_fit.steady and rad_to_deg(carried_dir.angle_to(asked_dir)) <= 30.5
			and float(prev.call("out_of_fist", 0)) <= fitme.fit_cone_deg + 1.0
			and float(prev.call("out_of_fist", 1)) <= fitme.fit_cone_deg + 1.0,
		"the idle only carries the rod: held steady near where the grip file asks, the wrist keeping the handle in both fists (%.0f, %.0f deg out)"
			% [float(prev.call("out_of_fist", 0)), float(prev.call("out_of_fist", 1))])
	_check(float(prev.call("worst_air", 0)) >= GripFit.ENOUGH_AIR and float(prev.call("worst_air", 1)) >= GripFit.ENOUGH_AIR
			and label.modulate.g > label.modulate.r,
		"and both labels go green: %.1f cm and %.1f cm clear at worst through the idle"
			% [float(prev.call("worst_air", 0)) * 100.0, float(prev.call("worst_air", 1)) * 100.0])
	# A RUN carries it the same way, steady: the swinging arm no longer sweeps it.
	prev.set("animation", String(AnimationSet.RUN))
	for i: int in range(2):
		await get_tree().process_frame
	var idle_kept: String = "%s|%s" % [idle_fit.position, idle_fit.rotation_degrees]
	prev.call("fit_this_grip")
	var run_fit: GripEntry = fitme.find(AnimationSet.RUN)
	_check(run_fit != null and run_fit.steady
			and rad_to_deg((run_fit.basis() * Vector3.UP).normalized().angle_to(asked_dir)) <= 30.5
			and "%s|%s" % [idle_fit.position, idle_fit.rotation_degrees] == idle_kept,
		"fitting the run carries the rod steady the same way; the idle's grip is left alone")
	# The HEAVE uses the rod: it was animated round one, so the rod goes along the fist, not steady.
	prev.set("animation", "fishing.heave")
	for i: int in range(2):
		await get_tree().process_frame
	prev.call("fit_this_grip")
	var heave_fit: GripEntry = fitme.find(&"fishing.heave")
	var heave_hole: Dictionary = prev.call("hole_of", 0, &"fishing.heave", 0.0)
	var heave_off: float = rad_to_deg((heave_fit.basis() * Vector3.UP).angle_to(heave_hole["axis"] as Vector3))
	_check(not heave_fit.steady and heave_off < 3.0,
		"fitting the heave, which uses the rod, holds it along the fist (%.1f deg off its line), in the hand's frame" % heave_off)
	# EVERY ANIMATION, and what could not be cleared said in words.
	prev.call("fit_every_animation")
	var said: String = prev.call("fit_said")
	var fitted: Array[StringName] = fitme.animations()
	var clips: int = (prev.get("definition") as EntityDefinition).animation_set.clips.size()
	print("   %s" % said)
	_check(fitted.size() == clips and said.begins_with("fitted %d animations" % clips)
			and (said.contains("all clear") or said.contains("the hand itself")),
		"Fit Every Animation gives every animation in the set a grip (%d), and names any it could not clear and why" % fitted.size())
	# THE WRIST (DECISIONS #158): the preview turns it as the game does. CONTROL: with the wrist
	# held as the clip has it, the steady idle's handle leaves the fist.
	prev.set("animation", String(AnimationSet.IDLE))
	for i: int in range(3):
		await get_tree().process_frame
	var in_fist: float = prev.call("out_of_fist", 0)
	fitme.wrist_turn_deg = 0.0
	for i: int in range(2):
		await get_tree().process_frame
	var stiff: float = prev.call("out_of_fist", 0)
	fitme.wrist_turn_deg = 60.0
	for i: int in range(2):
		await get_tree().process_frame
	_check(stiff > 20.0 and in_fist < 5.0 and (prev.call("label_of", 0) as Label3D).text.contains("in the fist"),
		"the wrist turns to keep the carried handle in her fist (%.0f deg out) where the clip's own wrist leaves it %.0f deg out"
			% [in_fist, stiff])
	# THE CARRY POINT is a node ON HER HAND (DECISIONS #159; Luke: "why is the carry point so far
	# out and not on the hand?"): turn it, and the grip file's carry_point follows its +Y (in the
	# body's terms), and the carried animation shown is fitted to it a moment later.
	var carry_node: Node3D = prev.get_node_or_null(^"CarryPoint") as Node3D
	_check(carry_node != null, "the preview has a Carry Point node")
	if carry_node != null:
		var body0: Basis = (prev.call("body_of", 0) as Basis).orthonormalized()
		var her_hold: Vector3 = _hold_at(prev.call("item_of", 0) as Node3D).origin
		_check(carry_node.global_position.distance_to(her_hold) < 0.005,
			"it sits on her hand, where her fist closes (%.1f mm off)" % (carry_node.global_position.distance_to(her_hold) * 1000.0))
		var idle_before: Basis = fitme.find(AnimationSet.IDLE).basis()
		var y_want: Vector3 = (body0 * GripFit.body_dir(Vector3(0.6, 1.0, 0.0))).normalized()
		var z_want: Vector3 = (body0 * GripFit.body_dir(fitme.fit_face))
		z_want = (z_want - y_want * z_want.dot(y_want)).normalized()
		carry_node.global_basis = Basis(y_want.cross(z_want).normalized(), y_want, z_want)
		carry_node.global_position += Vector3(0.5, 0.0, 0.0)
		for i: int in range(3):
			await get_tree().process_frame
		_check(fitme.carry_point.normalized().distance_to(Vector3(0.6, 1.0, 0.0).normalized()) < 0.01
				and carry_node.global_position.distance_to(_hold_at(prev.call("item_of", 0) as Node3D).origin) < 0.05,
			"turning it up and to her right sets carry_point there (%s); moving it puts it back on her hand" % fitme.carry_point)
		# The preview fits it a moment (REFIT_DELAY_MSEC) after the turn: waited for, not timed (a
		# fixed 0.6 s missed it on a slow frame), up to 3 s.
		var refit_until: int = Time.get_ticks_msec() + 3000
		while fitme.find(AnimationSet.IDLE).basis().is_equal_approx(idle_before) and Time.get_ticks_msec() < refit_until:
			await get_tree().process_frame
		# Fitted toward the new way: nearer it than the old (tip up and forward), and within the fit's
		# turns round it (to keep the handle in the fist and clear). The reel side is left as it was.
		var refit_dir: Vector3 = (fitme.find(AnimationSet.IDLE).basis() * Vector3.UP).normalized()
		var to_new: float = rad_to_deg(refit_dir.angle_to(GripFit.body_dir(fitme.carry_point).normalized()))
		var to_old: float = rad_to_deg(refit_dir.angle_to(GripFit.body_dir(Vector3(0.0, 1.0, 1.0)).normalized()))
		_check(to_new < to_old and to_new <= 30.5,
			"and the idle is fitted again toward it (%.0f deg off it, %.0f deg off the old way)" % [to_new, to_old])
	# PUT AWAY (DECISIONS #158): Fit Stow slings it where the draw's hand reaches, hanging the way
	# the grip file asks, and sets the draw's and the stow's grips to meet it there: no jump.
	fitme.stow_point = Vector3(-0.6, -0.8, 0.0)
	fitme.stow_face = Vector3(0.0, 0.0, 1.0)
	prev.call("fit_stow_now")
	for i: int in range(2):
		await get_tree().process_frame
	_check(fitme.stows() and fitme.draw_swap_at > 0.0 and fitme.stow_swap_at > 0.0
			and String(prev.call("fit_said")).begins_with("fit stow"),
		"Fit Stow gives the rod a place on her back, and when the draw takes it (%d%%) and the stow lets go (%d%%)"
			% [roundi(fitme.draw_swap_at * 100.0), roundi(fitme.stow_swap_at * 100.0)])
	var jumps: Array[float] = []
	for pair: Array in [[ItemGrip.DRAW, fitme.draw_swap_at], [ItemGrip.STOW, fitme.stow_swap_at]]:
		prev.set("animation", String(pair[0]))
		prev.set("pose_at", float(pair[1]))
		for i: int in range(3):
			await get_tree().process_frame
		var in_hand_hold: Transform3D = _hold_at(prev.call("item_of", 0) as Node3D)
		prev.set("show_stowed", true)
		for i: int in range(2):
			await get_tree().process_frame
		var slung_hold: Transform3D = _hold_at(prev.call("item_of", 0) as Node3D)
		prev.set("show_stowed", false)
		jumps.append(in_hand_hold.origin.distance_to(slung_hold.origin))
		jumps.append(rad_to_deg(Quaternion(in_hand_hold.basis.orthonormalized()).angle_to(Quaternion(slung_hold.basis.orthonormalized()))))
	_check(jumps[0] < 0.01 and jumps[1] < 5.0 and jumps[2] < 0.01 and jumps[3] < 5.0,
		"at those moments the rod in her hand is where it is slung: the draw takes it %.1f cm and %.0f deg off, the stow lets it go %.1f cm and %.0f deg off"
			% [jumps[0] * 100.0, jumps[1], jumps[2] * 100.0, jumps[3]])
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("pose_at", 0.0)
	prev.set("show_stowed", true)
	for i: int in range(3):
		await get_tree().process_frame
	var slung_dir: Vector3 = ((prev.call("body_of", 0) as Basis).orthonormalized().inverse()
		* _hold_at(prev.call("item_of", 0) as Node3D).basis.y).normalized()
	_check(GripFit.body_dir(slung_dir).distance_to(Vector3(-0.6, -0.8, 0.0).normalized()) < 0.05
			and (prev.call("label_of", 0) as Label3D).text.contains("put away"),
		"Show Stowed hangs it down across her back to the left, as the grip file asks (%s)" % GripFit.body_dir(slung_dir))
	prev.set("show_stowed", false)
	# THE OTHER HAND (DECISIONS #172): the grip file says the rod is held in both hands waiting, and
	# the preview puts her left hand on the reel there as the game does; standing, it is her own.
	prev.set("grip", file_grip.duplicate(true))
	prev.set("animation", "fishing.wait")
	for i: int in range(4):
		await get_tree().process_frame
	var skel0: Skeleton3D = prev.get("_skels")[0] as Skeleton3D
	var off_ik: TwoBoneIK3D = skel0.get_node_or_null(OffHand.IK_NAME) as TwoBoneIK3D
	var off_target: Node3D = skel0.get_node_or_null(OffHand.TARGET_NAME) as Node3D
	var off_point: Node3D = OffHand.point_of(prev.call("item_of", 0) as Node3D, file_grip)
	_check(off_ik != null and off_ik.active and is_equal_approx(off_ik.influence, 1.0) and off_point != null,
		"waiting, the preview holds the reel with her left hand (the grip file's off hand)")
	if off_target != null and off_point != null:
		var want_wrist: Vector3 = OffHand.wrist_target(skel0, file_grip, off_point.global_position,
			(prev.call("item_of", 0) as Node3D).global_basis)
		_check(off_target.global_position.distance_to(want_wrist) < 0.001,
			"its wrist goes where the game puts it (OffHand, the same code)")
	prev.set("animation", String(AnimationSet.IDLE))
	for i: int in range(3):
		await get_tree().process_frame
	_check(off_ik == null or not off_ik.active, "standing, the hand is the clip's own")
	_check(_grip_text(file_grip) == file_before, "and none of it touched the grip file")
	prev.queue_free()
	await get_tree().process_frame


## The grips of DECISIONS #147 (clear of every leg through the idle), and one that clears a man's
## leg in the idle's first frame and sits inside a woman's further in (Luke's first edit): fishing
## position and turn, carrying position and turn.
const GRIP_147: Array[Vector3] = [Vector3(-0.03, 0.11, -0.04), Vector3(95.0, 0.0, 0.0),
	Vector3(-0.01, 0.11, -0.04), Vector3(0.0, -90.0, -95.0)]
const GRIP_LEG: Array[Vector3] = [Vector3(-0.03, 0.11, -0.04), Vector3(95.0, 0.0, 0.0),
	Vector3(-0.025, 0.09, -0.09), Vector3(88.13, -90.567, -91.564)]
## The animations a rod is FISHED with (the cast, the waiting pose, the heave, a snap's), which
## hold it the fishing way; every other animation borrows the idle's, the carrying way.
const FISHED_WITH: Array[StringName] = [&"interact", &"fishing.wait", &"fishing.heave", &"fishing.fail"]


## A rod's grip from those four numbers: the idle's (carrying), and the fishing animations'. The
## numbers place the rod's ROOT, as they were tuned; a grip places its HOLD (DECISIONS #158).
func _item_grip_from(v: Array[Vector3]) -> ItemGrip:
	var g := ItemGrip.new()
	g.entries.append(_root_entry(AnimationSet.IDLE, v[2], v[3], false))
	for a: StringName in FISHED_WITH:
		g.entries.append(_root_entry(a, v[0], v[1], false))
	return g


## A grip that puts the rod's ROOT at `pos`, turned `rot`, written as where its HOLD goes.
func _root_entry(anim: StringName, pos: Vector3, rot: Vector3, steady: bool) -> GripEntry:
	var rod: Node3D = (load("res://game/fishing/fishing_rod.tscn") as PackedScene).instantiate() as Node3D
	var hold: Transform3D = GripFit.hold_of(rod)
	rod.free()
	var root := Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)),
		EULER_ORDER_YXZ), pos)
	var at: Transform3D = root * hold
	var e: Vector3 = at.basis.get_euler(EULER_ORDER_YXZ)
	return _grip_entry(anim, at.origin, Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)), steady)


## Where a held item's HOLD is in the world (its `Hold` node).
static func _hold_at(item: Node3D) -> Transform3D:
	return item.global_transform * GripFit.hold_of(item)


## Every grip in a file, as text: to show a test left it alone.
static func _grip_text(g: ItemGrip) -> String:
	var parts: PackedStringArray = []
	for e: GripEntry in g.entries:
		parts.append("%s|%s|%s|%s|%s" % [e.animation, e.body, e.position, e.rotation_degrees, e.steady])
	return ";".join(parts)



## ARMS OUT OF THE BODY, IN EVERY ANIMATION (DECISIONS #163). Luke: "all animations should go
## through clipping checks to see if arms clip in the body or other clipping". The real fisher (its
## driver, its rod and the rod's two-handed hand, the grip's `off_hand_animations`), in each body the game
## dresses people in, held in every animation of its set through its clip, and its arms measured
## against its own skin as drawn (`SkinClearance`, during the skeleton's update). Two things fail:
##
##   OFF THE ROD   in an animation the rod is held in both hands in (the grip's `off_hand_animations`), the
##                 left wrist leaves its hold on the reel by more than OFF_HAND_SLACK. This is what
##                 Luke saw: the clips' own left hand is not on this rod, and it hung in the air,
##                 crossed her belly and pressed into her chest (the wait, the cast).
##   INTO THE BODY a forearm or a hand goes FOREARM_SLACK deeper into the body than standing does,
##                 or an upper arm UPPER_ARM_SLACK deeper. Calibrated on what Luke judged: the heave
##                 and the wait he called right put an upper arm 2.0-3.6 cm against her chest (it
##                 rests there when the arms come forward); a forearm or hand through the body is
##                 the fault, and the old elbow put one 6-12 cm in.
const FOREARM_SLACK: float = 0.03
const UPPER_ARM_SLACK: float = 0.045
const OFF_HAND_SLACK: float = 0.03
const ARM_SAMPLES: int = 8
## By path: a class registered after the last import is not known by name until the next one.
const SKIN: GDScript = preload("res://foundation/held/skin_clearance.gd")


func _run_arm_clip_tests() -> void:
	print("== arms out of the body, in every animation ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var defn: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	var seen: Array[StringName] = []
	var eid: int = 5301
	while seen.size() < 2 and eid < 5321:
		reg.local_entity_id = eid
		_buffer_player_rows(reg, eid)
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
		var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
		for i: int in range(3):
			await get_tree().process_frame
		var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent if me != null else null
		var feedback: FishingFeedback = me.find_component(FishingFeedback) as FishingFeedback if me != null else null
		var skel: Skeleton3D = driver._find_skeleton(me.get_node(^"Visual/Model")) if driver != null else null
		var body: StringName = StringName(skel.get_meta(HeldItem.BODY_META, &"")) if skel != null else &""
		if skel != null and feedback != null and feedback.fx() != null and not seen.has(body):
			seen.append(body)
			await _arms_in_every_animation(me, driver, feedback, skel, body)
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
		spawner._flush_despawns()
		await get_tree().process_frame
		eid += 1
	_check(seen.size() == 2, "both of the game's bodies were measured (%s)" % str(seen))
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame


func _arms_in_every_animation(me: SpaceTimeEntity, driver: AnimationDriverComponent, feedback: FishingFeedback,
		skel: Skeleton3D, body: StringName) -> void:
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	if input != null:
		input.set_physics_process(false)
		input.send_to_server = false
	# The body is held in each animation here, so the genre's own pose-keeping stands aside; the rod
	# reads the animation itself, in hand.
	feedback.set_process(false)
	var rod: FishingRod = feedback.fx().rod()
	rod.driver = driver
	var equip: EquipComponent = me.find_component(EquipComponent) as EquipComponent
	if equip != null:
		equip.away_when_idle = false
		equip.set_equipped_now(true)
	rod.set_stowed_now(false)
	var skin: Dictionary = SKIN.gather(skel)
	var depth: Array[float] = [0.0]
	var where: Array[String] = [""]
	var by_piece: Dictionary[String, float] = {}
	var measure := func() -> void:
		var hit: Dictionary = SKIN.arms_into_body(skel, skin)
		var pieces: Dictionary = hit["pieces"]
		for piece: String in pieces:
			by_piece[piece] = maxf(float(by_piece.get(piece, 0.0)), float(pieces[piece]))
		if float(hit["depth"]) > depth[0]:
			depth[0] = float(hit["depth"])
			where[0] = "%s into the %s" % [hit["arm"], hit["part"]]
	# The left wrist against where it holds the reel (the grip's off_hand_wrist), as drawn.
	var off_hand: Array[float] = [0.0]
	var measure_hand := func() -> void:
		var want: Vector3 = rod.knob_position() + rod.global_transform.basis * rod.grip.off_hand_wrist
		off_hand[0] = maxf(off_hand[0], BodyClearance.bone_at(skel, &"hand_l").distance_to(want))
	var hand_off: Dictionary[StringName, float] = {}
	var worst: Dictionary[StringName, Array] = {}
	var names: Array[StringName] = []
	for k: StringName in driver.animation_set.clips:
		if driver.animation_set.has_exact(k):
			names.append(k)
	names.sort()
	var piece_worst: Dictionary[StringName, Dictionary] = {}
	for semantic: StringName in names:
		depth[0] = 0.0
		where[0] = ""
		by_piece.clear()
		var deepest_at: float = 0.0
		off_hand[0] = 0.0
		var two: bool = rod.grip.off_hand_animations.has(semantic)
		driver.hold_pose(semantic, 1.0, 0.0)
		await _tick_frames(30)   # the pose blends in, and the rod's grip and hand follow it
		for k: int in range(ARM_SAMPLES + 1):
			var at: float = float(k) / float(ARM_SAMPLES)
			driver.hold_pose(semantic, 1.0, at)
			await _tick_frames(3)
			var before: float = depth[0]
			skel.skeleton_updated.connect(measure)
			if two:
				skel.skeleton_updated.connect(measure_hand)
			await _tick_frames(1)
			skel.skeleton_updated.disconnect(measure)
			if two:
				skel.skeleton_updated.disconnect(measure_hand)
			if depth[0] > before:
				deepest_at = at
		if two:
			hand_off[semantic] = off_hand[0]
		worst[semantic] = [depth[0], where[0], deepest_at, rod.off_hand_weight()]
		piece_worst[semantic] = by_piece.duplicate()
		var line: PackedStringArray = []
		for piece: String in by_piece:
			if by_piece[piece] > 0.0:
				line.append("%s %.1f" % [piece, by_piece[piece] * 100.0])
	# PICTURES (`--arm-pictures=<dir>`, in a window): each animation that put an arm in the body, at
	# its deepest moment, from in front and from the side of that arm, for a person to judge.
	var pictures: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--arm-pictures="):
			pictures = arg.substr("--arm-pictures=".length())
	if not pictures.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(pictures)
		var cam := Camera3D.new()
		cam.fov = 35.0
		me.get_parent().add_child(cam)
		cam.make_current()
		for semantic: StringName in names:
			var w: Array = worst[semantic]
			if float(w[0]) <= 0.005:
				continue
			driver.hold_pose(semantic, 1.0, float(w[2]))
			await _tick_frames(20)
			var chest: Vector3 = BodyClearance.bone_at(skel, &"spine_03")
			var fwd: Vector3 = skel.global_basis.z.normalized()
			var side: Vector3 = skel.global_basis.x.normalized() * (1.0 if String(w[1]).begins_with("left") else -1.0)
			var shots: Array[Image] = []
			for dir: Vector3 in [fwd, (fwd + side).normalized(), side]:
				cam.global_position = chest + dir * 1.1
				cam.look_at(chest, Vector3.UP)
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(360, 400)
				img.convert(Image.FORMAT_RGBA8)
				shots.append(img)
			var sheet := Image.create(360 * shots.size(), 400, false, Image.FORMAT_RGBA8)
			for k: int in range(shots.size()):
				sheet.blit_rect(shots[k], Rect2i(0, 0, 360, 400), Vector2i(k * 360, 0))
			sheet.save_png("%s/%s_%s.png" % [pictures, body, String(semantic).replace(".", "_")])
		# And the cast through its clip, in front and from her left: a strip of moments.
		var strip: Array[Image] = []
		for at: float in [0.1, 0.25, 0.4, 0.55, 0.7, 0.85]:
			driver.hold_pose(AnimationSet.INTERACT, 1.0, at)
			await _tick_frames(20)
			var chest_now: Vector3 = BodyClearance.bone_at(skel, &"spine_03")
			for dir: Vector3 in [skel.global_basis.z.normalized(),
					(skel.global_basis.z - skel.global_basis.x).normalized()]:
				cam.global_position = chest_now + dir * 1.3
				cam.look_at(chest_now, Vector3.UP)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(300, 340)
				img.convert(Image.FORMAT_RGBA8)
				strip.append(img)
		var strip_sheet := Image.create(300 * 6, 340 * 2, false, Image.FORMAT_RGBA8)
		for k: int in range(strip.size()):
			strip_sheet.blit_rect(strip[k], Rect2i(0, 0, 300, 340), Vector2i((k / 2) * 300, (k % 2) * 340))
		strip_sheet.save_png("%s/%s_cast_strip.png" % [pictures, body])
		cam.queue_free()
	driver.release_pose()
	feedback.set_process(true)
	var rest: Dictionary = piece_worst.get(AnimationSet.IDLE, {})
	var over: Array[String] = []
	for semantic: StringName in names:
		var w: Array = worst[semantic]
		print("   %s %-22s %4.1f cm%s%s" % [body, semantic, float(w[0]) * 100.0,
			"" if float(w[0]) <= 0.0 else "  %s at %d%%" % [w[1], roundi(float(w[2]) * 100.0)],
			"" if not hand_off.has(semantic) else ", the left wrist at most %.1f cm off the reel" % (hand_off[semantic] * 100.0)])
		var pieces: Dictionary = piece_worst[semantic]
		for piece: String in pieces:
			var slack: float = UPPER_ARM_SLACK if piece.ends_with("upper arm") else FOREARM_SLACK
			if float(pieces[piece]) > float(rest.get(piece, 0.0)) + slack:
				over.append("%s: the %s %.1f cm in" % [semantic, piece, float(pieces[piece]) * 100.0])
	_check(over.is_empty(),
		"%s: in every animation, no forearm or hand goes over %.0f cm, and no upper arm over %.1f cm, deeper into the body than standing%s"
			% [body, FOREARM_SLACK * 100.0, UPPER_ARM_SLACK * 100.0, "" if over.is_empty() else ": " + "; ".join(over)])
	var strays: Array[String] = []
	for semantic: StringName in hand_off:
		if hand_off[semantic] > OFF_HAND_SLACK:
			strays.append("%s %.1f cm" % [semantic, hand_off[semantic] * 100.0])
	_check(hand_off.size() == rod.grip.off_hand_animations.size() and strays.is_empty(),
		"%s: in every animation the rod is held in both hands in (%s), the left hand stays on it, at the reel%s"
			% [body, ", ".join(rod.grip.off_hand_animations), "" if strays.is_empty() else ": off by " + ", ".join(strays)])


## SETTINGS (DECISIONS #165). The player's own choices: checked against their definitions,
## applied (buses, mouse look, key bindings), saved and read back, drawn by the panel from the
## definitions (a game's own included), and reachable from the Escape menu, which also shows the
## log. On a file of its own: the player's settings.cfg is never touched by a test.
const SETTINGS_TEST_FILE: String = "user://settings_test.cfg"


func _run_settings_tests() -> void:
	print("== settings ==")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_FILE))
	Settings.use_file(SETTINGS_TEST_FILE)
	_check(Array(Settings.tabs()).slice(0, 3) == [Settings.VIDEO, Settings.AUDIO, Settings.CONTROLS],
		"the foundation's tabs, in order (%s)" % str(Settings.tabs()))
	for bus: StringName in [&"Master", Settings.BUS_MUSIC, Settings.BUS_EFFECTS, Settings.BUS_AMBIENCE, Settings.BUS_VOICE]:
		_check(AudioServer.get_bus_index(bus) >= 0, "the audio bus '%s' exists (default_bus_layout.tres)" % bus)
	_check(float(Settings.get_value(&"master_volume")) == 100.0 and float(Settings.get_value(&"music_volume")) == 70.0
		and Settings.look_sensitivity() == 1.0 and not Settings.invert_look(),
		"a fresh install has the defaults")

	# --- values are checked against their definitions -------------------------------------
	Settings.set_value(&"render_scale", 10.0)
	_check(float(Settings.get_value(&"render_scale")) == 50.0, "a slider is clamped to its range (10 -> %s)" % Settings.get_value(&"render_scale"))
	Settings.set_value(&"mouse_sensitivity", 1.234)
	_check(is_equal_approx(Settings.look_sensitivity(), 1.25), "and snapped to its step (1.234 -> %s)" % Settings.look_sensitivity())
	Settings.set_value(&"max_fps", 99)
	_check(int(Settings.get_value(&"max_fps")) == 0, "a choice out of range is the default")
	Settings.set_value(&"vsync", "yes")
	_check(Settings.get_value(&"vsync") == true, "a value of the wrong kind is the default")
	var heard: Array[StringName] = []
	var on_changed := func(k: StringName, _v: Variant) -> void: heard.append(k)
	Settings.changed.connect(on_changed)
	Settings.set_value(&"master_volume", 40.0)
	Settings.set_value(&"master_volume", 40.0)
	Settings.set_value(&"music_volume", 0.0)
	Settings.changed.disconnect(on_changed)
	_check(heard == [&"master_volume", &"music_volume"], "a change is announced once, a repeat not at all (%s)" % str(heard))
	var master: int = AudioServer.get_bus_index(&"Master")
	var music: int = AudioServer.get_bus_index(Settings.BUS_MUSIC)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(0.4)) and not AudioServer.is_bus_mute(master),
		"the master volume sets the bus (%.1f dB)" % AudioServer.get_bus_volume_db(master))
	_check(AudioServer.is_bus_mute(music), "music at 0 is muted")

	# --- the player's mouse ----------------------------------------------------------------
	var input: LocalInputComponent = _make_input_component(true)
	input.capture_mouse = false
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 10)
	var turned: Array[Vector2] = []
	for setting: Array in [[1.0, false], [2.0, false], [1.0, true]]:
		Settings.set_value(&"mouse_sensitivity", setting[0])
		Settings.set_value(&"invert_y", setting[1])
		input._look_yaw = 0.0
		input._look_pitch = 0.0
		input._unhandled_input(motion)
		turned.append(Vector2(input._look_yaw, input._look_pitch))
	_check(is_equal_approx(turned[1].x, 2.0 * turned[0].x) and is_equal_approx(turned[1].y, 2.0 * turned[0].y),
		"twice the sensitivity turns the view twice as far (%s, %s)" % [turned[0], turned[1]])
	_check(is_equal_approx(turned[2].y, -turned[0].y) and is_equal_approx(turned[2].x, turned[0].x) and turned[0].y != 0.0,
		"inverted, moving the mouse down looks the other way, and left and right are unchanged")
	input.queue_free()

	# --- key bindings ----------------------------------------------------------------------
	var space: String = Settings.event_to_text(_key_event(KEY_SPACE))
	_check(Settings.get_value(&"jump") == space and Settings.binding_label(space) == "Space",
		"jump ships on Space (%s, shown as \"%s\")" % [Settings.get_value(&"jump"), Settings.binding_label(space)])
	Settings.set_value(&"jump", Settings.event_to_text(_key_event(KEY_J)))
	_check(_bound_to(&"jump", KEY_J) and not _bound_to(&"jump", KEY_SPACE),
		"rebinding jump puts J on the action and takes Space off")
	Settings.set_value(&"interact", Settings.event_to_text(_key_event(KEY_W)))
	_check(Settings.clashes(&"interact", String(Settings.get_value(&"interact"))) == PackedStringArray(["Move forward"]),
		"a binding another action has is pointed out (%s)" % str(Settings.clashes(&"interact", String(Settings.get_value(&"interact")))))
	Settings.set_value(&"interact", "mouse:%d" % MOUSE_BUTTON_MIDDLE)
	_check(Settings.binding_label(String(Settings.get_value(&"interact"))) == "Middle mouse"
		and InputMap.action_has_event(&"interact", Settings.text_to_event("mouse:%d" % MOUSE_BUTTON_MIDDLE)),
		"a mouse button can be bound")
	Settings.set_value(&"jump", "nonsense")
	_check(Settings.get_value(&"jump") == space and _bound_to(&"jump", KEY_SPACE),
		"a binding that is not a key or a button is the shipped one")
	Settings.set_value(&"jump", Settings.event_to_text(_key_event(KEY_J)))

	# --- saved, and read back ----------------------------------------------------------------
	Settings.use_file(SETTINGS_TEST_FILE)
	_check(float(Settings.get_value(&"master_volume")) == 40.0 and float(Settings.get_value(&"render_scale")) == 50.0
		and _bound_to(&"jump", KEY_J) and Settings.binding_label(String(Settings.get_value(&"interact"))) == "Middle mouse",
		"everything changed is read back from the file")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_TEST_FILE)
	_check(cfg.has_section_key("audio", "master_volume") and cfg.has_section_key("keys", "jump"),
		"the file is sectioned by tab, bindings under [keys]")
	Settings.reset(Settings.CONTROLS)
	_check(_bound_to(&"jump", KEY_SPACE) and not _bound_to(&"jump", KEY_J) and Settings.look_sensitivity() == 1.0,
		"Reset puts a tab's settings back, bindings included")

	# --- a game's own setting, and the panel ------------------------------------------------
	Settings.define(&"test_gauge", "Testing", "Show the test gauge", Settings.Kind.TOGGLE, true)
	_check(Settings.tabs().has("Testing") and Settings.get_value(&"test_gauge") == true,
		"a game defines its own setting, on its own tab")
	var panel := SettingsPanel.new()
	get_tree().root.add_child(panel)
	panel.open()
	await get_tree().process_frame
	var tabs: TabContainer = panel.find_child("Tabs", true, false) as TabContainer
	_check(tabs != null and tabs.get_tab_count() == Settings.tabs().size(),
		"the panel has a tab per settings tab (%d)" % (tabs.get_tab_count() if tabs != null else -1))
	_check(panel.control_for(&"test_gauge") is CheckButton, "and draws the game's setting without being told about it")
	(panel.control_for(&"test_gauge") as CheckButton).button_pressed = false
	_check(Settings.get_value(&"test_gauge") == false, "clicking a toggle changes the setting")
	var slider: HSlider = panel.control_for(&"effects_volume").get_node(^"Slider") as HSlider
	slider.value = 25.0
	_check(float(Settings.get_value(&"effects_volume")) == 25.0
		and (panel.control_for(&"effects_volume").get_node(^"Value") as Label).text == "25%",
		"dragging a slider changes the setting and its label")
	var bind: Button = panel.control_for(&"sprint").get_node(^"Bind") as Button
	bind.pressed.emit()
	_check(panel.listening() == &"sprint" and bind.text.begins_with("Press a key"), "clicking a binding waits for a key")
	panel._input(_key_event(KEY_ESCAPE))
	_check(panel.listening() == &"" and panel.is_open() and Settings.binding_label(String(Settings.get_value(&"sprint"))) == bind.text,
		"Escape cancels the wait, and leaves the binding and the panel")
	bind.pressed.emit()
	panel._input(_key_event(KEY_K))
	_check(_bound_to(&"sprint", KEY_K) and bind.text == "K", "the next key pressed is the binding (%s)" % bind.text)
	Settings.set_value(&"fullscreen", true)
	_check((panel.control_for(&"fullscreen") as CheckButton).button_pressed, "a change made elsewhere (F11) shows in an open panel")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	var closed: Array[bool] = [false]
	panel.closed.connect(func() -> void: closed[0] = true)
	panel._input(esc)
	_check(not panel.is_open() and closed[0], "Escape closes the panel")
	panel.queue_free()

	# --- the Escape menu ---------------------------------------------------------------------
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	var settings_button: Button = menu.find_child("Settings", true, false) as Button
	var logs_button: Button = menu.find_child("Logs", true, false) as Button
	_check(settings_button != null and logs_button != null, "the Escape menu has Settings and Open log folder")
	settings_button.pressed.emit()
	_check(menu.settings_panel().is_open() and not (menu.get_node(^"Center") as Control).visible and menu.is_page_open(),
		"Settings opens the settings in place of the menu")
	menu.settings_panel()._input(esc)
	_check(not menu.settings_panel().is_open() and (menu.get_node(^"Center") as Control).visible and not menu.is_page_open(),
		"and Escape there goes back to the menu, not out of it")
	var extra: Button = menu.add_button("Journal")
	_check(extra.get_index() == menu.find_child("Disconnect", true, false).get_index() - 1,
		"a genre adds a button of its own, above Disconnect")
	var shown: String = PauseMenu.open_log_folder()
	_check(shown.begins_with(ProjectSettings.globalize_path("user://")),
		"Open log folder shows this game's user folder (%s)" % shown)
	menu.queue_free()

	# Back to the defaults, and no file.
	Settings.reset("Testing")
	for tab: String in [Settings.VIDEO, Settings.AUDIO, Settings.CONTROLS]:
		Settings.reset(tab)
	Settings.use_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_FILE))
	_check(_bound_to(&"jump", KEY_SPACE) and _bound_to(&"sprint", KEY_SHIFT) and _bound_to(&"interact", KEY_E),
		"the bindings are the shipped ones again")


func _key_event(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	return k


func _bound_to(action: StringName, code: Key) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		var k: InputEventKey = ev as InputEventKey
		if k != null and (k.physical_keycode == code or k.keycode == code):
			return true
	return false


## MUSIC BY PHASE (DECISIONS #167): the director plays the phase's track, the default for any
## other phase and out of a game, on the Music bus; and both fishing scenes ship one with a track
## for the round itself, which loops.
func _run_music_tests() -> void:
	print("== music ==")
	var playing: AudioStream = load("res://game/fishing/music/lakeside.wav") as AudioStream
	var between: AudioStream = load("res://game/fishing/music/between_rounds.wav") as AudioStream
	_check(playing != null and between != null, "the generated tracks import")
	_check((playing as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		and (between as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "and loop")
	var d := MusicDirector.new()
	d.tracks = {1: playing}
	d.default_track = between
	d.fade_sec = 0.05
	get_tree().root.add_child(d)
	_check(d.current() == between, "out of a game it plays the default track")
	SignalBus.session_phase_changed.emit(1, 0, 1, 0)
	_check(d.current() == playing, "the round's phase plays its own track")
	await get_tree().create_timer(0.2).timeout
	var sounding: Array[AudioStreamPlayer] = []
	for c: Node in d.get_children():
		var p: AudioStreamPlayer = c as AudioStreamPlayer
		if p != null and p.playing:
			sounding.append(p)
	_check(sounding.size() == 1 and sounding[0].stream == playing and sounding[0].bus == Settings.BUS_MUSIC
		and is_equal_approx(sounding[0].volume_db, d.volume_db),
		"after the fade one track sounds, on the Music bus, at the music's level")
	SignalBus.session_phase_changed.emit(1, 1, 3, 0)
	_check(d.current() == between, "a phase with no track of its own plays the default")
	d.queue_free()
	for scene: String in ["res://game/fishing/fishing_world.tscn"]:
		var state: SceneState = (load(scene) as PackedScene).get_state()
		var found: bool = false
		for i: int in range(state.get_node_count()):
			for k: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, k) == &"tracks":
					var t: Dictionary = state.get_node_property_value(i, k)
					found = t.get(1) == playing
		_check(found, "%s has music for the round" % scene.get_file())
	var fishing_mod: GenreModule = load("res://game/fishing/genre.tres") as GenreModule
	_check(fishing_mod.scenes.has(load("res://game/fishing/fishing_world.tscn")),
		"and the fishing genre puts it in the game")


## A CHOSEN LOOK (DECISIONS #166): the text, the variant it names, the colours a look takes, an
## entity built in it, an entity rebuilt when it changes (not while it is busy), and the picker.
class FakeAppearanceRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var look: String
	func _init(eid: int, text: String) -> void:
		entity_id = eid
		look = text


## The SDK's cache, as far as a respawn reads it: rows by primary key, rows by predicate.
class FakeLookCache extends RefCounted:
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


class FakeLookSdk extends Node:
	var cache: FakeLookCache = FakeLookCache.new()
	func get_local_database() -> Object:
		return cache


class FakeBusyComponent extends SpaceTimeComponent:
	var busy: bool = true
	func required_tables() -> Array[StringName]:
		return []
	func _on_row_updated(_t: StringName, _o: RefCounted, _n: RefCounted) -> void:
		pass
	func blocks_respawn() -> bool:
		return busy


func _run_look_tests() -> void:
	print("== a chosen look ==")
	# --- the text ----------------------------------------------------------------------------
	_check(Appearance.look_name("ranger_f;skin=4;hair=2") == "ranger_f" and Appearance.look_name("") == "",
		"the look's name is the text before the first ;")
	_check(Appearance.choices("ranger_f;skin=4;hair=x;=3;outfit=2") == {"skin": 4, "outfit": 2},
		"the choices are key=number; anything else is skipped")
	_check(Appearance.make("noble_m", {"skin": 2, "hair": 0, "outfit": 1}) == "noble_m;outfit=1;skin=2",
		"made with its keys in order and the look's own choices (0) left out")
	_check(Appearance.is_valid("ranger_f;skin=4") and not Appearance.is_valid("Ranger F")
		and not Appearance.is_valid("x".repeat(Appearance.MAX_LENGTH + 1)),
		"only what the module takes is valid (lowercase, digits, _;=,.-, at most %d)" % Appearance.MAX_LENGTH)

	# --- the variant it names ------------------------------------------------------------------
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	_check(fisher.variant_names().size() == fisher.visual_variants.size() and fisher.variant_names().has("wizard_f"),
		"the angler's looks by name (%s)" % ", ".join(fisher.variant_names()))
	_check(fisher.visual_for(3, "wizard_f;hair=2").resource_path.ends_with("/wizard_f.tscn"),
		"an appearance names the look worn")
	_check(fisher.visual_for(3, "no_such_look") == fisher.visual_for(3) and fisher.visual_for(3, "") == fisher.visual_for(3),
		"a name that is not a look, or none, is the look picked from the id")

	# --- the colours a look takes --------------------------------------------------------------
	var peasant: ModularCharacter = (load("res://game/characters/looks/peasant_f.tscn") as PackedScene).instantiate() as ModularCharacter
	var keys: Array[String] = []
	for o: Dictionary in peasant.appearance_options():
		keys.append(String(o["key"]))
	_check(keys == ["torso", "torso_dye", "arms", "arms_dye", "legs", "legs_dye", "feet", "feet_dye", "head",
		"shoulders", "neck", "hairstyle", "skin", "hair"],
		"a woman's look offers every slot made for her body and its colours, her skin and hair colour (%s)" % str(keys))
	var hair_before: Color = _dressed_color(peasant, "MI_Hair")
	peasant.apply_appearance("peasant_f;hair=10;torso_dye=1;skin=5")
	_check(_dressed_color(peasant, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"])
		and not hair_before.is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"the hair is dressed in the colour chosen (%s, was %s)" % [_dressed_color(peasant, "MI_Hair"), hair_before])
	var skin: StandardMaterial3D = _dressed(peasant, "MI_Regular_")
	_check(skin != null and skin.albedo_texture != null and skin.albedo_texture.resource_path.ends_with("T_Regular_Female_Dark_BaseColor.png")
		and skin.albedo_color.is_equal_approx(CharacterLooks.SKINS[4]["tint"]),
		"the skin is her body's dark texture, in the tone chosen")
	var torso_mat: StandardMaterial3D = _piece_material(peasant, "Female_Peasant_Body", "MI_Peasant")
	var arms_mat: StandardMaterial3D = _piece_material(peasant, "Female_Peasant_Arms", "MI_Peasant")
	_check(torso_mat != null and torso_mat.albedo_texture.resource_path.ends_with("T_Peasant_BaseColor.png"),
		"her torso wears the colourway chosen for it")
	_check(arms_mat != null and arms_mat.albedo_texture.resource_path.ends_with("T_Peasant_2_BaseColor.png"),
		"and her arms, with none chosen, the look's own (%s)" % (arms_mat.albedo_texture.resource_path.get_file() if arms_mat != null else "none"))
	peasant.apply_appearance("peasant_f;hair=99;skin=-2")
	_check(_dressed_color(peasant, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"a choice out of range changes nothing")
	peasant.free()
	await _run_piece_tests()

	# --- an entity built in it, and rebuilt when it changes -------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	var prev_sdk: Node = SpaceTimeSync._sdk
	var prev_cfg: NetConfig = SpaceTimeSync.config
	spawner.register_definition(fisher)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	var eid: int = 5401
	reg.local_entity_id = -1   # someone else: no camera, no input
	var fake := FakeLookSdk.new()
	add_child(fake)
	SpaceTimeSync._sdk = fake
	SpaceTimeSync.config = (load(FISHING_NET_CONFIG) as NetConfig).duplicate() as NetConfig
	Genres.merge_tables(SpaceTimeSync.config, Genres.modules())
	var entity_row := FakeEntityRow.new(eid, 0)
	fake.cache.put(&"entity", eid, entity_row)
	for ev: RowEvent in _player_rows(eid):
		fake.cache.put(ev.table, int(ev.current().get(&"entity_id") if ev.current().get(&"entity_id") != null else ev.current().get(&"id")), ev.current())
	var first := FakeAppearanceRow.new(eid, "wizard_f;hair=10")
	fake.cache.put(&"appearance", eid, first)
	_buffer_player_rows(reg, eid)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"appearance", null, first))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, entity_row))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	var model: Node = me.get_node_or_null(^"Visual/Model") if me != null else null
	_check(model != null and model.scene_file_path.ends_with("/wizard_f.tscn") and me.appearance == "wizard_f;hair=10",
		"an entity whose row names a look is built wearing it (%s)" % (model.scene_file_path if model != null else "no model"))
	_check(model is ModularCharacter and _dressed_color(model as ModularCharacter, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"with the colours it names")
	# A change while a component is busy waits; once it is not, the entity is built again.
	var busy := FakeBusyComponent.new()
	me.add_runtime_component(busy)
	var second := FakeAppearanceRow.new(eid, "noble_m")
	fake.cache.put(&"appearance", eid, second)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"appearance", first, second))
	await get_tree().create_timer(0.8).timeout
	_check(spawner.get_entity_node(eid) == me, "a new look waits while the entity is in the middle of something")
	busy.busy = false
	await get_tree().create_timer(0.8).timeout
	var again: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	var new_model: Node = again.get_node_or_null(^"Visual/Model") if again != null else null
	_check(again != null and again != me and again.is_bound() and new_model != null
		and new_model.scene_file_path.ends_with("/noble_m.tscn") and again.appearance == "noble_m",
		"then it is built again, bound, in the new look (%s)" % (new_model.scene_file_path if new_model != null else "none"))
	_check(not is_instance_valid(me) or me.is_queued_for_deletion() or not me.is_inside_tree(), "and the old node is gone")
	var mv: SpaceTimeMovementComponent = again.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if again != null else null
	_check(mv != null and mv.is_bound(), "its components bound again, from the cache's rows")
	spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", entity_row, null))
	spawner._flush_despawns()
	await get_tree().process_frame
	SpaceTimeSync._sdk = prev_sdk
	SpaceTimeSync.config = prev_cfg
	fake.queue_free()
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the picker ------------------------------------------------------------------------------
	var picker := CharacterPicker.new()
	picker.definition = fisher
	picker.appearance = "ranger_m;hair=3"
	get_tree().root.add_child(picker)
	picker.open()
	await get_tree().process_frame
	var name_label: Label = picker.find_child("LookName", true, false) as Label
	_check(picker.is_open() and picker.preview_model() != null
		and picker.preview_model().scene_file_path.ends_with("/ranger_m.tscn") and name_label.text == "Ranger M",
		"the picker opens on the look already chosen, turning in its preview (%s)" % name_label.text)
	var hair_pick: OptionButton = picker.find_child("hair", true, false) as OptionButton
	_check(hair_pick != null and hair_pick.selected == 3 and hair_pick.item_count == CharacterLooks.HAIRS.size() + 1,
		"its choices are the look's own, starting where they were")
	var before: String = picker.current()
	(picker.find_child("Next", true, false) as Button).pressed.emit()
	_check(picker.current().begins_with(fisher.variant_names()[(fisher.variant_names().find("ranger_m") + 1) % fisher.variant_names().size()])
		and picker.current() != before, "> steps to the next look (%s)" % picker.current())
	hair_pick = picker.find_child("hair", true, false) as OptionButton
	hair_pick.select(5)
	hair_pick.item_selected.emit(5)
	_check(picker.current().contains("hair=5"), "a choice is part of the look (%s)" % picker.current())
	var got: Array[String] = []
	picker.chosen.connect(func(t: String) -> void: got.append(t))
	var want: String = picker.current()
	(picker.find_child("Done", true, false) as Button).pressed.emit()
	_check(got == [want] and not picker.is_open() and Appearance.is_valid(want),
		"Done hands on the look as text the module takes (%s)" % str(got))
	picker.queue_free()


## The material a look's meshes are dressed in for source materials named `prefix`*.
func _dressed(look: ModularCharacter, prefix: String) -> StandardMaterial3D:
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(i)
			if src != null and src.resource_name.begins_with(prefix):
				var worn: Material = mi.get_surface_override_material(i)
				return (worn if worn != null else src) as StandardMaterial3D
	return null


## The material a piece's surface is drawn with (the override, else its own), by the piece's file.
func _piece_material(look: ModularCharacter, piece: String, prefix: String) -> StandardMaterial3D:
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or String(mi.get_meta(ModularCharacter.PIECE_META, "")).get_file().get_basename() != piece:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(i)
			if src != null and src.resource_name.begins_with(prefix):
				var worn: Material = mi.get_surface_override_material(i)
				return (worn if worn != null else src) as StandardMaterial3D
	return null


## The pieces a character is drawn wearing, by file name, sorted.
func _pieces_worn(look: ModularCharacter) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var piece: String = String(n.get_meta(ModularCharacter.PIECE_META, "")).get_file().get_basename()
		if not piece.is_empty() and not out.has(piece):
			out.append(piece)
	out.sort()
	return out


## EVERY PIECE, SLOT BY SLOT (DECISIONS #178): any piece made for a body can be worn on any look of
## that body, alone in its slot, on the one skeleton, bound where it expects the bones; a colourway
## dresses only its own outfit; every choice at once still fits on the row; and the picker shows a
## slot's colours beside it and asks again after each choice.
func _run_piece_tests() -> void:
	print("== a chosen look: every piece ==")
	var looks: Dictionary[String, PackedScene] = {
		"female": load("res://game/characters/looks/peasant_f.tscn") as PackedScene,
		"male": load("res://game/characters/looks/peasant_m.tscn") as PackedScene,
	}
	var tried: int = 0
	var wrong: Array[String] = []
	var longest: Dictionary = {}
	for body: String in looks:
		for slot: Dictionary in CharacterLooks.SLOTS:
			var list: Array = CharacterLooks.slot_list(slot, StringName(body))
			var key: String = String(slot["key"])
			if list.size() >= 2:
				longest[key] = maxi(int(longest.get(key, 0)), list.size())
			for i: int in range(list.size()):
				var look: ModularCharacter = looks[body].instantiate() as ModularCharacter
				look.apply_appearance("x;%s=%d" % [key, i + 1])
				tried += 1
				var want: PackedStringArray = String(list[i][1]).split("+", false)
				var in_slot: PackedStringArray = PackedStringArray()
				for piece: String in _pieces_worn(look):
					if CharacterLooks.slot_of(piece) == key:
						in_slot.append(piece)
				want.sort()
				var skel: Skeleton3D = look.skeleton()
				var skels: int = look.find_children("*", "Skeleton3D", true, false).size()
				var bad: String = ""
				if in_slot != want:
					bad = "wears %s" % str(in_slot)
				elif skel == null or skels != 1:
					bad = "%d skeletons" % skels
				else:
					for n: Node in look.find_children("*", "MeshInstance3D", true, false):
						var mi: MeshInstance3D = n as MeshInstance3D
						if mi.get_parent() != skel or mi.skin == null:
							continue
						for b: int in range(mi.skin.get_bind_count()):
							var bone: int = skel.find_bone(mi.skin.get_bind_name(b))
							if bone < 0 or mi.skin.get_bind_pose(b).affine_inverse().origin.distance_to(
									skel.get_bone_global_rest(bone).origin) > 0.005:
								bad = "%s is not bound to this body at %s" % [mi.name, mi.skin.get_bind_name(b)]
								break
				if not bad.is_empty():
					wrong.append("%s %s=%s: %s" % [body, key, list[i][0], bad])
				get_tree().root.add_child(look)
				look.queue_free()
	_check(tried >= 60 and wrong.is_empty(),
		"each of %d pieces, worn on its body's look, is alone in its slot on the one skeleton, bound to that body (%s)"
			% [tried, str(wrong)])
	await get_tree().process_frame

	# Swapped, the piece's own colours, and a colourway that is not its outfit's never reaches it.
	var p: ModularCharacter = looks["female"].instantiate() as ModularCharacter
	get_tree().root.add_child(p)
	var skel_before: Skeleton3D = p.skeleton()
	p.apply_appearance("peasant_f;torso=3")
	_check(_pieces_worn(p).has("Female_Noble_Body") and not _pieces_worn(p).has("Female_Peasant_Body")
		and _pieces_worn(p).has("Female_Peasant_Arms"),
		"a noble torso on a peasant: the torso swapped, the rest hers (%s)" % ", ".join(_pieces_worn(p)))
	_check(p.skeleton() != null and p.skeleton() != skel_before and p.find_children("*", "Skeleton3D", true, false).size() == 1,
		"put together again on one new skeleton")
	var noble: StandardMaterial3D = _piece_material(p, "Female_Noble_Body", "MI_Noble")
	_check(noble != null and noble.albedo_texture.resource_path.ends_with("T_Noble_BaseColor.png"),
		"the noble torso keeps the noble colours, not the look's peasant colourway (%s)"
			% (noble.albedo_texture.resource_path.get_file() if noble != null else "none"))
	var dye_choices: int = 0
	for o: Dictionary in p.appearance_options():
		if String(o["key"]) == "torso_dye":
			dye_choices = (o["choices"] as PackedStringArray).size()
	_check(dye_choices == CharacterLooks.colourways("Noble").size() + 1,
		"its colours are the noble torso's (%d choices)" % dye_choices)
	p.apply_appearance("peasant_f;torso=3;torso_dye=2")
	noble = _piece_material(p, "Female_Noble_Body", "MI_Noble")
	_check(noble != null and noble.albedo_texture.resource_path.ends_with("T_Noble_2_BaseColor.png"),
		"and dyed, it wears the noble colourway chosen")
	p.apply_appearance("peasant_f")
	_check(_pieces_worn(p).has("Female_Peasant_Body") and not _pieces_worn(p).has("Female_Noble_Body"),
		"with the choice gone, she wears her own torso again")
	p.queue_free()
	var r: ModularCharacter = (load("res://game/characters/looks/rival.tscn") as PackedScene).instantiate() as ModularCharacter
	get_tree().root.add_child(r)
	r.apply_appearance("rival;beard=1;brows=1")
	var brows: Array[String] = []
	for n: Node in r.find_children("Eyebrows*", "MeshInstance3D", true, false):
		brows.append(String(n.name))
	_check(not _pieces_worn(r).has("Hair_Moustache") and not _pieces_worn(r).has("Hair_MuttonChops"),
		"no beard takes off every beard piece a look wears (his moustache and his chops)")
	_check(brows == ["Eyebrows_Regular"], "one pair of eyebrows, the ones chosen (%s)" % str(brows))
	r.queue_free()

	# Every choice at once is text the module takes.
	var all: Dictionary = {"skin": CharacterLooks.SKINS.size(), "hair": CharacterLooks.HAIRS.size()}
	for k: Variant in longest:
		all[k] = longest[k]
		all[String(k) + CharacterLooks.DYE] = 3
	var everything: String = Appearance.make("wizard_f", all)
	_check(Appearance.is_valid(everything),
		"every choice at once fits what the module takes (%d of %d characters)" % [everything.length(), Appearance.MAX_LENGTH])

	# The picker: a slot's colours beside it, asked again after a choice, a stale one dropped.
	var picker := CharacterPicker.new()
	picker.definition = load(FISHER_DEF) as EntityDefinition
	picker.appearance = "peasant_f;torso_dye=3"
	add_child(picker)
	picker.open()
	var torso_row: Node = picker.find_child("Row_torso", true, false)
	_check(torso_row != null and torso_row.get_node_or_null(^"torso") != null and torso_row.get_node_or_null(^"torso_dye") != null,
		"the torso's colours sit in the torso's row")
	var dye: OptionButton = picker.find_child("torso_dye", true, false) as OptionButton
	_check(dye != null and dye.item_count == CharacterLooks.colourways("Peasant").size() + 1 and dye.selected == 3,
		"a peasant torso offers the peasant's colourways, the third chosen")
	(picker.find_child("torso", true, false) as OptionButton).item_selected.emit(3)
	dye = picker.find_child("torso_dye", true, false) as OptionButton
	_check(dye != null and dye.item_count == CharacterLooks.colourways("Noble").size() + 1,
		"a noble torso picked, its colours are asked for again (%d)" % (dye.item_count if dye != null else 0))
	_check(picker.current().contains("torso=3") and not picker.current().contains("torso_dye"),
		"and the third colourway, which the noble torso lacks, is dropped (%s)" % picker.current())
	var shown: ModularCharacter = picker.preview_model() as ModularCharacter
	_check(shown != null and _pieces_worn(shown).has("Female_Noble_Body"), "the preview wears it")
	picker.close()
	picker.queue_free()
	await get_tree().process_frame


func _dressed_color(look: ModularCharacter, prefix: String) -> Color:
	var m: StandardMaterial3D = _dressed(look, prefix)
	return m.albedo_color if m != null else Color(0, 0, 0, 0)


## THE LAKE AROUND THE FISHING (DECISIONS #168-#171): the round's time of day and weather (named,
## favouring what they favour, drawn on the sky), other players' fights shown, the journal and the
## records, the rival's name, and the HUD's journal and keys.
class FakeConditionsRow extends RefCounted:
	var world_id: int = 0
	var round: int
	var time_of_day: int
	var weather: int
	func _init(r: int, t: int, w: int) -> void:
		round = r
		time_of_day = t
		weather = w


class FakeFishLineRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var spot: String = "dock_end"
	var x: float
	var z: float
	var challenge_id: int = 0
	func _init(eid: int, px: float, pz: float) -> void:
		entity_id = eid
		x = px
		z = pz


class FakeShowRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var state: int
	var load: float
	var line_m: float
	func _init(eid: int, s: int, l: float, m: float) -> void:
		entity_id = eid
		state = s
		load = l
		line_m = m


func _run_fishing_world_tests() -> void:
	print("== the lake around the fishing ==")
	# --- the conditions, as data ------------------------------------------------------------
	_check(str(FishingData.time_of_day(0).get("id")) == "dawn" and FishingData.times_count() == 4
		and str(FishingData.weather(2).get("id")) == "rain" and FishingData.time_of_day(9).is_empty(),
		"the times of day and the weathers come from fishing.json, in order")
	_check(is_equal_approx(FishingData.likes("fish_whoa", PackedStringArray(["night", "fog"])), 3.6)
		and FishingData.likes("fish_trash", PackedStringArray(["night"])) == 1.0,
		"a like multiplies, and nothing liked is 1 (the server's rule, for showing)")
	var fav: PackedStringArray = FishingData.favoured_by(PackedStringArray(["night", "fog"]), 3)
	_check(fav == PackedStringArray(["strange fish", "Channel Catfish", "things that should not be here"]),
		"what a foggy night favours, most first, in words (%s)" % ", ".join(fav))
	var cond := FishingConditions.new()
	add_child(cond)
	var heard: Array[int] = [0]
	cond.changed.connect(func() -> void: heard[0] += 1)
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, FishingConditions.TABLE, null,
		FakeConditionsRow.new(3, 2, 2)))
	_check(cond.known and cond.round_number == 3 and cond.words() == "Dusk, rain" and heard[0] == 1,
		"the server's row is read and named (%s)" % cond.words())
	_check(cond.describe().begins_with("Dusk, rain: ") and cond.describe().contains("biting")
		and cond.tags() == PackedStringArray(["dusk", "rain"]),
		"and said with what it favours (%s)" % cond.describe())
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, FishingConditions.TABLE, null,
		FakeConditionsRow.new(3, 2, 2)))
	_check(heard[0] == 1, "the same conditions again are not news")

	# --- the sky shows them -----------------------------------------------------------------
	var stage := Node3D.new()
	add_child(stage)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.sky = Sky.new()
	we.environment.sky.sky_material = ProceduralSkyMaterial.new()
	we.environment.fog_density = 0.0016   # the lakeside's own
	var original_env: Environment = we.environment
	stage.add_child(we)
	var sky: SkyDirector = (load("res://game/world/sky_director.tscn") as PackedScene).instantiate() as SkyDirector
	stage.add_child(sky)
	sky._find_level()
	var looks_missing: Array[String] = []
	for i: int in range(FishingData.times_count()):
		var id: String = str(FishingData.time_of_day(i).get("id"))
		if not sky.times.has(id):
			looks_missing.append(id)
	for i: int in range(8):
		var w: Dictionary = FishingData.weather(i)
		if not w.is_empty() and not sky.weathers.has(str(w.get("id"))):
			looks_missing.append(str(w.get("id")))
	_check(looks_missing.is_empty(), "every time of day and weather in fishing.json has a look in sky_director.tscn %s" % str(looks_missing))
	cond.set_conditions(4, 3, 2)   # night, rain
	sky.snap()
	var night: SkyLook = sky.times["night"]
	var rain: WeatherLook = sky.weathers["rain"]
	_check(is_equal_approx(sun.light_energy, night.sun_energy * rain.sun_energy_mult) and sky._rain.emitting
		and is_equal_approx(we.environment.fog_density, night.fog_density + rain.fog_density_add),
		"a rainy night: the moon's light under cloud, the rain falling, the fog thicker")
	_check(we.environment != original_env and original_env.fog_density != we.environment.fog_density,
		"on the director's own copy of the environment, not the level's")
	cond.set_conditions(2, 1, 0)   # day, clear
	sky.snap()
	var day: SkyLook = sky.times["day"]
	_check(not sky._rain.emitting and is_equal_approx(sun.light_energy, day.sun_energy) and sun.global_basis.z.y > 0.3,
		"a clear day: no rain, the full sun, high in the sky")
	sky._phase = SessionComponent.Phase.PLAYING
	sky._phase_ends_usec = ClockSync.server_usec() + int(Rules.phase_seconds(0, SessionComponent.Phase.PLAYING) * 0.25 * 1e6)
	_check(is_equal_approx(snappedf(sky.round_progress(), 0.01), 0.75) and
		is_equal_approx(float(sky.target()["elevation"]), lerpf(day.sun_elevation_deg, day.sun_elevation_end_deg, sky.round_progress())),
		"the sun moves through the round (%.2f of the way, at %.1f degrees)" % [sky.round_progress(), float(sky.target()["elevation"])])
	stage.queue_free()
	cond.queue_free()

	# --- another player's fight, shown -------------------------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(LAKESIDE_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(FISHER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5501
	var them: int = 5502
	for eid: int in [5501, them]:
		_buffer_player_rows(reg, eid)
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	for i: int in range(4):
		await get_tree().process_frame
	var other: SpaceTimeEntity = spawner.get_entity_node(them) as SpaceTimeEntity
	var fishing: FishingComponent = other.find_component(FishingComponent) as FishingComponent
	var feedback: FishingFeedback = other.find_component(FishingFeedback) as FishingFeedback
	other.global_position = Vector3(0.0, 0.9, 30.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, FishingComponent.LINE_TABLE, null, FakeFishLineRow.new(them, 0.0, 10.0)))
	for i: int in range(20):
		await get_tree().process_frame
	_check(fishing.line_out() and fishing.shown_fight().is_empty() and feedback.heave_shown() == 0.0,
		"their line is out with nothing on it: they wait")
	var show := FakeShowRow.new(them, FishingComponent.Shown.SWEET, 0.8, 8.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, FishingComponent.SHOW_TABLE, null, show))
	# A report is reached over the time between reports (#181): longer than that, then look.
	await get_tree().create_timer(FishingFeedback.SHOWN_SPAN_SEC + 0.15).timeout
	var fx: FishingFx = feedback.fx()
	var float_at: Vector3 = fx.float_position()
	var shore := Vector3(other.global_position.x, float_at.y, other.global_position.z)
	_check(fishing.shown_fight().get("state") == FishingComponent.Shown.SWEET and fx.state() == FishingFx.State.FIGHTING,
		"their fight arrives, and is drawn as a fight")
	_check(feedback.heave_shown() > 0.5 * FishingFeedback.HEAVE_TOP,
		"they heave with the load they show (%.2f of %.2f)" % [feedback.heave_shown(), FishingFeedback.HEAVE_TOP])
	_check(absf(float_at.distance_to(shore) - 8.0) < 1.5,
		"their float is dragged in to the metres they show (%.1f m out)" % float_at.distance_to(shore))
	_check(fx.tell_visible() and FishingFeedback.tell_shown(FishingComponent.Shown.SWEET) == FishingFx.TELL_PERFECT
		and FishingFeedback.tell_shown(FishingComponent.Shown.RUNNING) == FishingFx.TELL_RUN,
		"with the tell ring in the colour of what they show")
	# THEIR HEAVE MOVES EVERY FRAME (DECISIONS #181). Reports half a second apart, as the rival's
	# are: between two, the pose is on its way from one to the next, never holding still and never
	# jumping when a row lands (Luke: "the rival animations look like a slideshow").
	var last_show: FakeShowRow = show
	var frames_between: Array = []
	for load: float in [0.3, 0.9, 0.4]:
		var next_show := FakeShowRow.new(them, FishingComponent.Shown.BAND, load, 8.0)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, FishingComponent.SHOW_TABLE, last_show, next_show))
		last_show = next_show
		var seen: Array[float] = []
		var until: int = Time.get_ticks_msec() + 500
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			seen.append(feedback.heave_shown())
		frames_between.append(seen)
	# From 0.3's heave to 0.9's, starting at the last frame before the report landed.
	var rise: Array = [(frames_between[0] as Array).back()] + (frames_between[1] as Array)
	var low: float = FishingFeedback.HEAVE_TOP * (1.0 - pow(1.0 - 0.3, 2.0))
	var high: float = FishingFeedback.HEAVE_TOP * (1.0 - pow(1.0 - 0.9, 2.0))
	var moving: int = 0
	var biggest_step: float = 0.0
	var reached_at: int = -1
	for i: int in range(1, rise.size()):
		var step: float = absf(float(rise[i]) - float(rise[i - 1]))
		biggest_step = maxf(biggest_step, step)
		if reached_at < 0 and absf(float(rise[i]) - high) < 0.01:
			reached_at = i
		elif reached_at < 0 and step > 1e-6:
			moving += 1
	var climbing: int = reached_at if reached_at > 0 else rise.size()
	_check(rise.size() > 10 and climbing > 5 and moving >= int(0.9 * float(climbing - 1)),
		"between two of their reports the heave moves on every frame until it gets there (%d of %d frames)"
			% [moving, climbing - 1])
	_check(biggest_step < 0.5 * (high - low),
		"and never jumps when a report lands (largest step %.3f of a %.3f climb)" % [biggest_step, high - low])
	_check(reached_at > 0, "and reaches what they reported before the next report (%.3f, want %.3f)"
		% [float(rise[rise.size() - 1]), high])
	# A run reports the same load again and again: the rod strains rather than standing still.
	for i: int in range(2):
		var run_show := FakeShowRow.new(them, FishingComponent.Shown.RUNNING, 0.4, 8.0)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, FishingComponent.SHOW_TABLE, last_show, run_show))
		last_show = run_show
		await get_tree().create_timer(0.4).timeout
	var still: int = 0
	var run_frames: int = 0
	var before: float = feedback.heave_shown()
	var run_until: int = Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < run_until:
		await get_tree().process_frame
		run_frames += 1
		if absf(feedback.heave_shown() - before) < 1e-6:
			still += 1
		before = feedback.heave_shown()
	_check(run_frames > 10 and still <= run_frames / 10,
		"while their catch runs at a steady load, the rod strains: still on %d of %d frames" % [still, run_frames])
	reg._on_row_event(RowEvent.make(RowEvent.Kind.DELETED, FishingComponent.SHOW_TABLE, last_show, null))
	for i: int in range(90):
		await get_tree().process_frame
	_check(fishing.shown_fight().is_empty() and feedback.heave_shown() < 0.05,
		"when they stop showing a fight, the heave comes back down (%.2f)" % feedback.heave_shown())

	# OUR fight is reported, a few times a second and at once on a change.
	var mine: FishingComponent = (spawner.get_entity_node(5501) as SpaceTimeEntity).find_component(FishingComponent) as FishingComponent
	mine._fight = FightSim.new(FightSim.params_for(0, 0, 0, FishingData.HookSet.GOOD, false),
		FightSim.profile_of("bluegill"), 7, 14.0, true)
	mine._report_fight()
	var first: int = mine._show_sent_msec
	mine._report_fight()
	_check(first >= 0 and mine._show_sent_msec == first and mine._show_sent_state == FishingComponent.shown_of(mine._fight),
		"our fight is reported, and not again within %.1f s while it shows the same" % FishingComponent.SHOW_INTERVAL_SEC)
	mine._show_sent_state = -9
	mine._report_fight()
	_check(mine._show_sent_state == FishingComponent.shown_of(mine._fight), "a change is reported at once")
	mine._fight = null

	# --- the journal and the records ----------------------------------------------------------
	var catches: Array = [[1, 5501, "bluegill", 0.31], [2, 5501, "bluegill", 0.42], [3, 5501, "golden_koi", 6.2],
		[4, them, "bluegill", 0.9], [5, them, "carp", 8.0]]
	for c: Array in catches:
		var row := FakeCatchRow.new(int(c[0]), int(c[1]), 1, 1, str(c[2]), float(c[3]))
		row.coins = 10 * int(c[0])
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, row))
	await get_tree().process_frame
	var journal: Array[Dictionary] = FishingRecords.journal(mine)
	var by_key: Dictionary = {}
	for r: Dictionary in journal:
		by_key[r["key"]] = r
	_check(journal.size() == (FishingData.doc()["catches"] as Array).size() and FishingRecords.kinds_caught(journal) == 2,
		"the journal lists every kind in the catalogue, and we have caught 2 of them")
	_check(int(by_key["bluegill"]["count"]) == 2 and is_equal_approx(float(by_key["bluegill"]["best_kg"]), 0.42)
		and int(by_key["bluegill"]["best_coins"]) == 20 and int(by_key["carp"]["count"]) == 0,
		"each kind: how many, the biggest, the best paid; another's catch is not ours")
	var missing: PackedStringArray = FishingRecords.missing(journal)
	_check(missing.size() > 0 and missing[0] == "things that should not be here" and not missing.has("strange fish")
		and not missing.has("small fish"), "the rarities still to find, rarest first (%s)" % ", ".join(missing))
	var biggest: Array[Dictionary] = FishingRecords.biggest()
	var big: Dictionary = {}
	for b: Dictionary in biggest:
		big[b["key"]] = b
	_check(is_equal_approx(float(big["bluegill"]["kg"]), 0.9) and not bool(big["bluegill"]["is_local"])
		and str(biggest[0]["key"]) == "golden_koi", "the records: the biggest bluegill is theirs, the rarest catch first")
	var anglers: Array[Dictionary] = FishingRecords.anglers()
	_check(anglers.size() == 2 and int(anglers[0]["coins"]) == 90 and int(anglers[1]["coins"]) == 60
		and str(anglers[1]["best_key"]) == "golden_koi" and bool(anglers[1]["is_local"]),
		"anglers by what their catches paid, with their best catch")
	var page := CatchJournal.new()
	add_child(page)
	page.open()
	await get_tree().process_frame
	var summary: Label = page.find_child("Summary", true, false) as Label
	var tabs: TabContainer = page.find_child("Tabs", true, false) as TabContainer
	_check(tabs.get_tab_count() == 2 and summary.text.begins_with("2 of %d kinds caught" % journal.size()),
		"the journal page: our catches and the records (%s)" % summary.text)
	var unknowns: int = 0
	for l: Node in page.find_child("Grid", true, false).get_children():
		if (l as Label).text == CatchJournal.UNKNOWN:
			unknowns += 1
	_check(unknowns == journal.size() - 2, "a kind not caught yet is ??? (%d)" % unknowns)
	page.queue_free()

	# AN ANGLER ARRIVES WITH THEIR HISTORY (DECISIONS #180): 25 catches already on the server when
	# they spawn, all of them on the record. The entity used to hand its components only the newest
	# row of each table, and Luke's journal showed one catch where the server had dozens.
	var veteran: int = 5503
	_buffer_player_rows(reg, veteran)
	for i: int in range(25):
		var old := FakeCatchRow.new(700 + i, veteran, 1, 1, "muskellunge" if i == 0 else "bluegill", 15.2 if i == 0 else 0.2)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, old))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(veteran, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var vet: SpaceTimeEntity = spawner.get_entity_node(veteran) as SpaceTimeEntity
	var vet_fishing: FishingComponent = vet.find_component(FishingComponent) as FishingComponent if vet != null else null
	_check(vet_fishing != null and vet_fishing.all_catches().size() == 25,
		"an angler who arrives with 25 catches has all 25 on the record (got %d)"
			% (vet_fishing.all_catches().size() if vet_fishing != null else -1))
	var vet_row: Dictionary = {}
	for a: Dictionary in FishingRecords.anglers():
		if int(a["catches"]) == 25:
			vet_row = a
	_check(not vet_row.is_empty() and str(vet_row["best_key"]) == "muskellunge",
		"and the records count them all, their muskellunge the best (%s)" % str(vet_row))
	for eid: int in [5501, them, veteran]:
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the rival's name, the HUD's journal and keys ------------------------------------------
	var rival_def: EntityDefinition = load("res://game/fishing/rival_definition.tres") as EntityDefinition
	_check(rival_def.display_name == str(FishingData.rival().get("name")),
		"the rival's nameplate is the name fishing.json gives him (%s)" % rival_def.display_name)
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	var hud: Control = (load("res://game/fishing/fishing_hud.tscn") as PackedScene).instantiate() as Control
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var journal_button: Button = menu.find_child("Journal", true, false) as Button
	_check(journal_button != null, "the HUD adds Journal to the Escape menu")
	if journal_button != null:
		journal_button.pressed.emit()
		_check((hud.call("journal") as CatchJournal).is_open() and menu.is_page_open(), "and it opens the journal there")
	_check(Settings.entries("Fishing").size() >= 3 and Settings.entry(&"fish_cast").get("tab") == "Fishing"
		and Settings.entry(&"open_journal").get("kind") == Settings.Kind.KEY,
		"fishing's keys are in the settings, to rebind")
	hud.queue_free()
	menu.queue_free()
	await get_tree().process_frame


## A GAME IS A LIST OF GENRES (DECISIONS #173): shared/game.json names them, each has its client
## file (genre.tres) and its server file (server/src/game/<id>.rs); Boot takes the genres'
## definitions, tables and scenes; a genre that is not listed is not loaded at all; one with no
## file is said, not swallowed.
func _run_genre_tests() -> void:
	print("== genres ==")
	_check(Genres.listed() == PackedStringArray(["fishing"]) and not Genres.title().is_empty(),
		"shared/game.json makes the game of fishing (%s, \"%s\")" % [str(Genres.listed()), Genres.title()])
	var mods: Array[GenreModule] = Genres.modules()
	_check(mods.size() == 1 and mods[0].id == &"fishing" and mods[0].entity_definitions.size() == 3
		and mods[0].tables.has(&"catch") and mods[0].scenes.size() == 2,
		"each genre's client half loads: fishing's definitions, tables and scenes")
	var server_missing: Array[String] = []
	for id: String in Genres.listed():
		if not FileAccess.file_exists(ProjectSettings.globalize_path("res://server/src/game/%s.rs" % id)):
			server_missing.append(id)
	_check(server_missing.is_empty(), "and its server half exists (server/src/game/<id>.rs) %s" % str(server_missing))
	# Every table a genre names is per world or not, decided like the foundation's.
	for m: GenreModule in mods:
		var stray: Array[StringName] = []
		for t: StringName in m.world_tables:
			if not m.tables.has(t):
				stray.append(t)
		_check(stray.is_empty(), "%s's per-world tables are tables it subscribes %s" % [m.id, str(stray)])
	var cfg := NetConfig.new()
	Genres.merge_tables(cfg, mods)
	_check(cfg.core_tables.has(&"fishing_line") and cfg.world_tables.has(&"fishing_line")
		and cfg.core_tables.has(&"entity") and cfg.core_tables.count(&"catch") == 1,
		"a game's subscription is the foundation's tables and its genres', each once")
	Genres.merge_tables(cfg, mods)
	_check(cfg.core_tables.count(&"catch") == 1, "merging twice adds nothing twice")
	# Boot, in a game scene: the genres' definitions are registered, their tables subscribed, their
	# scenes put in the game.
	var game: Node = (load("res://game/fishing/fishing_game.tscn") as PackedScene).instantiate()
	var boot: Node = game.get_node(^"Boot")
	boot.set("connect_screen", null)   # no screen: it would connect at once, and there is no server
	boot.set("pause_menu", null)
	var prev_cfg: NetConfig = SpaceTimeSync.config
	var prev_defs: Array[EntityDefinition] = EntitySpawner.definitions.duplicate()
	var prev_state: int = SpaceTimeSync.state
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var booted: Array = boot.get("genres")
	var cfg_used: NetConfig = boot.get("net_config") as NetConfig
	_check(booted.size() == 1 and cfg_used.core_tables.has(&"fight_show") and cfg_used.world_tables.has(&"fight_show"),
		"Boot loads the genres and subscribes their tables")
	_check(EntitySpawner._by_kind.has(0) and (EntitySpawner._by_kind[0] as EntityDefinition).resource_path.ends_with("fisher_definition.tres"),
		"their entity definitions are what the spawner builds (kind 0 is the angler)")
	_check(game.get_node_or_null(^"HUD") != null and game.get_node_or_null(^"FishingWorld/SkyDirector") != null,
		"and their scenes are in the game: the HUD, the sky")
	SpaceTimeSync.disconnect_from_server("test over")
	game.queue_free()
	await get_tree().process_frame
	SpaceTimeSync.config = prev_cfg
	EntitySpawner.definitions = prev_defs
	# An unknown genre is reported, by name.
	Genres.override_list = PackedStringArray(["no_such_genre"])
	var bad: Array[GenreModule] = Genres.modules()
	Genres.override_list = PackedStringArray()
	_check(bad.is_empty(), "a genre with no genre.tres is skipped (and reported)")


## THE LOBBY (DECISIONS #174): the rules say whether a kind has one (ready-up, players, teams); a
## member's ready and team come from its row; the panel shows only in a lobby, lists who is here,
## and its keys ask the server (offline here: the refusal is said, not swallowed).
class FakeLobbyRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var session_id: int = 1
	var ready: bool
	var team: int
	func _init(eid: int, r: bool, t: int) -> void:
		entity_id = eid
		ready = r
		team = t


func _run_lobby_tests() -> void:
	print("== the lobby ==")
	var lobby: Dictionary = Rules.lobby(0)
	_check(bool(lobby.get("ready_up", false)) and int(lobby.get("min_players", 0)) == 1 and Rules.teams(0).is_empty(),
		"fishing's rounds have a lobby that starts on ready, for one player, with no teams")
	_check(Rules.lobby(77).is_empty() and Rules.teams(77).is_empty(), "a kind with no lobby has none")
	var sess := SessionComponent.new()
	add_child(sess)
	var heard: Array[Array] = []
	sess.lobby_changed.connect(func(r: bool, t: int) -> void: heard.append([r, t]))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(9, true, 2))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(9, true, 2))
	_check(sess.is_ready() and sess.team() == 2 and heard == [[true, 2]],
		"a member's ready and team come from its row, announced once (%s)" % str(heard))
	sess._on_row_updated(SessionComponent.LOBBY_TABLE, FakeLobbyRow.new(9, true, 2), null)
	_check(not sess.is_ready() and sess.team() == 0, "and go with it")
	_check(sess.optional_tables().has(SessionComponent.LOBBY_TABLE), "a kind with no lobby is not waited for")
	sess.queue_free()
	var panel := LobbyPanel.new()
	add_child(panel)
	await get_tree().process_frame
	_check(not panel.should_show() and not panel.visible, "with no local player in a lobby, the panel is not shown")
	var prev_local: int = EntityRegistry.local_entity_id
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(FISHER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5601
	_buffer_player_rows(reg, 5601)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5601, false, 0)))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(5601, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(5601) as SpaceTimeEntity
	var my_sess: SessionComponent = me.find_component(SessionComponent) as SessionComponent
	my_sess._session_kind = 0
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._phase_ends_at_usec = ClockSync.server_usec() + 20_000_000
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Array[Dictionary] = panel.members()
	_check(panel.visible and rows.size() >= 1 and bool(rows[0]["is_local"]) and not bool(rows[0]["ready"]),
		"in a lobby, the panel lists who is here, us not ready yet")
	var hint: Label = panel.find_child("Hint", true, false) as Label
	_check(hint.text.contains("ready"), "and says the key to be ready (%s)" % hint.text.replace("\n", " / "))
	var press := InputEventAction.new()
	press.action = LobbyPanel.ACTION_READY
	press.pressed = true
	panel._unhandled_input(press)
	await get_tree().process_frame
	_check(not panel.said().is_empty(), "the key asks the server, and a refusal is said (offline: \"%s\")" % panel.said())
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5601, true, 0)))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(panel.members()[0]["ready"]), "once the server says ready, the panel does")
	my_sess._phase = SessionComponent.Phase.PLAYING
	await get_tree().process_frame
	_check(not panel.visible, "and it goes when the round starts")
	spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(5601, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	panel.queue_free()


class FakeMatchRow extends RefCounted:
	var session_id: int = 1
	var world_id: int = 0
	var first_round: int
	var started: bool
	var number: int
	func _init(first: int, s: bool, n: int) -> void:
		first_round = first
		started = s
		number = n


class FakeOnlineRow extends RefCounted:
	var identity: PackedByteArray = PackedByteArray([1, 2, 3])
	var entity_id: int
	var name: String
	var online: bool = true
	func _init(eid: int, n: String) -> void:
		entity_id = eid
		name = n


## THE MATCH, THE LOBBY SCREEN, THE SPLASH (DECISIONS #182, #183): the round a player sees counts
## from 1 in the match; the lobby screen stands everyone on its stage, holds the player still, opens
## on a match's lobby and goes when its first round starts (or on Join, arriving mid-match); the
## in-world lobby keeps out of its way; the splash plays, can be skipped, and says the game's name.
func _run_match_tests() -> void:
	print("== the match, the lobby screen, the splash ==")
	# --- the round a player sees ---------------------------------------------------------------
	var sess := SessionComponent.new()
	add_child(sess)
	sess._session_id = 1
	sess._round = 1490
	_check(sess.get_match_round() == 1490 and sess.is_match_started(),
		"with no match row (an older server) the round is the session's own, and nothing waits")
	var heard: Array[Array] = []
	sess.match_changed.connect(func(st: bool, n: int) -> void: heard.append([st, n]))
	sess._on_global_row(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.MATCH_TABLE, null, FakeMatchRow.new(1490, false, 2)))
	_check(sess.get_match_round() == 1 and not sess.is_match_started() and sess.match_number() == 2 and heard == [[false, 2]],
		"a match begun on the session's round 1490 shows it as round 1, its lobby waiting (%s)" % str(heard))
	sess._round = 1493
	_check(sess.get_match_round() == 4, "three rounds on, it is round 4 (%d)" % sess.get_match_round())
	var elsewhere := FakeMatchRow.new(7, true, 9)
	elsewhere.session_id = 2
	sess._on_global_row(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.MATCH_TABLE, null, elsewhere))
	_check(sess.match_number() == 2 and heard.size() == 1, "another session's match is not ours")
	sess.queue_free()
	_check(Rules.doc()["sessions"][0].has("match") and int(Rules.doc()["sessions"][0]["match"]["end_after_empty_s"]) > 0,
		"rules.json says how long a world may be empty before its match ends")

	# --- held still while a page covers the game -------------------------------------------------
	var input: LocalInputComponent = _make_input_component(true)
	_release_all_actions()
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	input.hold_still(&"lobby_screen", true)
	var still: InputFrame = input.sample()
	_check(still.move_dir == Vector2.ZERO and not still.jump and input.is_held_still(),
		"held still, the movement keys and jump are not read")
	var yaw_before: float = input.get_look_yaw()
	var turn := InputEventMouseMotion.new()
	turn.relative = Vector2(300.0, 0.0)
	input._unhandled_input(turn)
	_check(is_equal_approx(input.get_look_yaw(), yaw_before), "nor is the mouse")
	input.hold_still(&"lobby_screen", false)
	var free: InputFrame = input.sample()
	_check(free.move_dir != Vector2.ZERO and free.jump, "let go, they are again")
	_release_all_actions()
	# Freed now, not at the frame's end: its exit hands the cursor back, and the player below asks for it.
	var input_owner: Node = input.entity
	input.free()
	input_owner.queue_free()

	# --- the lobby screen, in a world with two players ---------------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(FISHER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5701
	for eid: int in [5701, 5702]:
		_buffer_player_rows(reg, eid)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(eid, false, 0)))
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"player", null, FakeOnlineRow.new(eid, "Ailsa" if eid == 5701 else "Bram")))
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(5701) as SpaceTimeEntity
	var my_sess: SessionComponent = me.find_component(SessionComponent) as SessionComponent
	var my_input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	my_sess._session_kind = 0
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._phase_ends_at_usec = ClockSync.server_usec() + 365 * 24 * 3_600_000_000
	my_sess._apply_match_row(FakeMatchRow.new(1, false, 1))
	var panel := LobbyPanel.new()
	add_child(panel)
	var screen := LobbyScreen.new()
	add_child(screen)
	for i: int in range(3):
		await get_tree().process_frame
	_check(screen.visible and LobbyScreen.showing(get_tree()) == screen,
		"a match waiting for its players: the lobby screen is open")
	_check(not panel.visible, "and the in-world lobby panel keeps out of its way")
	_check(my_input != null and my_input.is_held_still() and not MouseCapture.is_captured(),
		"the player is held still behind it, and has the cursor")
	_check(MouseCapture.is_held_free() and not MouseCapture.released_by_player(),
		"a page holding the cursor, not the player releasing it: the Escape menu stays shut")
	var escape := InputEventAction.new()
	escape.action = MouseCapture.RELEASE_ACTION
	escape.pressed = true
	MouseCapture._input(escape)
	_check(MouseCapture.released_by_player(), "Escape still opens the menu over it (wanted %s, held %s, captured %s)"
		% [MouseCapture.is_wanted(), MouseCapture.is_held_free(), MouseCapture.is_captured()])
	MouseCapture.recapture()
	_check(not MouseCapture.is_captured() and not MouseCapture.released_by_player(),
		"and Resume comes back to the lobby screen, the cursor still free")
	var models: Dictionary[int, Node3D] = screen.stage_models()
	_check(models.size() == 2 and models.has(5701) and models.has(5702),
		"both players stand on its stage (%s)" % str(models.keys()))
	var ours: Node3D = models.get(5701)
	_check(ours != null and ours.find_children("*", "Skeleton3D", true, false).size() == 1
		and ours.find_children("*", "Label3D", true, false).size() == 1,
		"each in their look, with their name over their head")
	_check(ours != null and models.get(5702) != null and ours.position.x < (models.get(5702) as Node3D).position.x,
		"ourselves first")
	var ready_button: Button = screen.find_child("Ready", true, false) as Button
	var join_button: Button = screen.find_child("Join", true, false) as Button
	var status: Label = screen.find_child("Status", true, false) as Label
	_check(ready_button.visible and not join_button.visible and status.text.contains("0 of 2"),
		"Ready, not Join, and how many are ready: \"%s\"" % status.text)
	ready_button.pressed.emit()
	await get_tree().process_frame
	_check(not screen.said().is_empty(), "Ready asks the server, and a refusal is said (offline: \"%s\")" % screen.said())
	var press := InputEventAction.new()
	press.action = LobbyPanel.ACTION_READY
	press.pressed = true
	screen._unhandled_input(press)
	_check(not screen.said().is_empty(), "R asks too")
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, SessionComponent.LOBBY_TABLE, null, FakeLobbyRow.new(5702, true, 0)))
	for i: int in range(2):
		await get_tree().process_frame
	_check(status.text.contains("1 of 2"), "Bram is ready: \"%s\"" % status.text)
	# The match starts: the screen goes, the game is theirs.
	my_sess._phase = SessionComponent.Phase.PLAYING
	my_sess._apply_match_row(FakeMatchRow.new(1, true, 1))
	for i: int in range(2):
		await get_tree().process_frame
	_check(not screen.visible and not my_input.is_held_still() and screen.stage_models().is_empty(),
		"its first round starts: the screen goes, the player is free, the stage is cleared")
	_check(not MouseCapture.is_held_free(), "and the cursor is the game's again")
	# A new match (after everyone left and came back): its lobby is everyone's again.
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._apply_match_row(FakeMatchRow.new(9, false, 2))
	for i: int in range(2):
		await get_tree().process_frame
	_check(screen.visible, "a new match opens its lobby screen again")
	# Arriving in the middle of a match: Join instead of Ready.
	screen.queue_free()
	my_sess._phase = SessionComponent.Phase.PLAYING
	my_sess._apply_match_row(FakeMatchRow.new(9, true, 2))
	var late := LobbyScreen.new()
	add_child(late)
	for i: int in range(2):
		await get_tree().process_frame
	join_button = late.find_child("Join", true, false) as Button
	ready_button = late.find_child("Ready", true, false) as Button
	_check(late.visible and join_button.visible and not ready_button.visible
		and (late.find_child("Status", true, false) as Label).text.contains("under way"),
		"arriving mid-match, the screen offers Join, not Ready")
	join_button.pressed.emit()
	await get_tree().process_frame
	_check(not late.visible and not my_input.is_held_still(), "and Join takes them into the game")
	late.queue_free()
	var harness := LobbyScreen.new()
	harness.auto_join = true
	add_child(harness)
	for i: int in range(2):
		await get_tree().process_frame
	_check(not harness.visible, "a harness that connects for the player goes straight into a match under way")
	harness.queue_free()
	var off := LobbyScreen.new()
	off.enabled = false
	add_child(off)
	my_sess._phase = SessionComponent.Phase.LOBBY
	my_sess._apply_match_row(FakeMatchRow.new(11, false, 3))
	for i: int in range(2):
		await get_tree().process_frame
	_check(not off.visible and panel.visible, "with no window it never shows, and the in-world lobby is back")
	off.queue_free()
	panel.queue_free()
	for eid: int in [5701, 5702]:
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the splash ----------------------------------------------------------------------------------
	var game_scene: PackedScene = load("res://game/fishing/lakeside_game.tscn") as PackedScene
	var state: SceneState = game_scene.get_state()
	var splash_scene: PackedScene = null
	for i: int in range(state.get_node_count()):
		if state.get_node_name(i) == &"Boot":
			for k: int in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, k) == &"splash_screen":
					splash_scene = state.get_node_property_value(i, k) as PackedScene
	_check(splash_scene != null and splash_scene.resource_path == "res://game/splash_screen.tscn",
		"the game's Boot plays the game's splash")
	var splash: SplashScreen = splash_scene.instantiate() as SplashScreen if splash_scene != null else null
	if splash == null:
		return
	add_child(splash)
	var done: Array[bool] = [false]
	splash.finished.connect(func() -> void: done[0] = true)
	_check((splash.find_child("Title", true, false) as Label).text == Genres.title() and not Genres.title().is_empty(),
		"it says the game's name from shared/game.json (%s)" % Genres.title())
	splash.play()
	splash._process(splash.fade_sec)
	_check(splash.visible and is_equal_approx(splash._root.modulate.a, 1.0) and not done[0], "it fades in and holds")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	splash._input(click)
	splash._process(splash.fade_sec * 0.5)
	_check(not done[0] and splash._root.modulate.a < 1.0, "a click fades it out at once")
	splash._process(splash.fade_sec)
	_check(done[0] and not splash.visible and not splash.is_playing(),
		"well before its time was up (%.1f of %.1f s)" % [splash.fade_sec * 2.5, splash.fade_sec * 2.0 + splash.hold_sec])
	splash.queue_free()
	var whole: SplashScreen = splash_scene.instantiate() as SplashScreen
	add_child(whole)
	var ended: Array[bool] = [false]
	whole.finished.connect(func() -> void: ended[0] = true)
	whole.play()
	var t: float = 0.0
	while not ended[0] and t < 10.0:
		whole._process(0.05)
		t += 0.05
	_check(ended[0] and absf(t - (whole.hold_sec + 2.0 * whole.fade_sec)) < 0.11,
		"left alone, it is done after its fade in, hold and fade out (%.2f s)" % t)
	whole.queue_free()


## LEVELS BUILT IN THE EDITOR (DECISIONS #175): a level scene's markers and collision ARE its
## bake (the meadow, baked again here, is byte for byte what the server compiled in: a stale bake
## fails); the baker agrees with the lakeside's own generator about its lake; the client reads a
## bake's id, scene and points; and the level on screen follows the world's.
class FakeWorldLevelRow extends RefCounted:
	var world_id: int = 0
	var level_id: int
	func _init(id: int) -> void:
		level_id = id


func _run_level_build_tests() -> void:
	print("== levels built in the editor ==")
	var meadow_bake: LevelBake = LevelBake.by_id(2)
	_check(meadow_bake != null and meadow_bake.level == "meadow" and meadow_bake.scene == "res://game/world/levels/meadow.tscn"
		and meadow_bake.points_of("bench").size() == 1 and LevelBake.by_id(1).level == "lakeside" and LevelBake.by_id(0) == null,
		"the client reads a bake's number, scene and points (meadow is 2, the lakeside 1, the greybox none)")
	# --- the meadow, baked again from its scene ----------------------------------------------
	var scene: Node3D = (load("res://game/world/levels/meadow.tscn") as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(scene)
	for i: int in range(8):
		await get_tree().physics_frame
	var out: String = "user://bake_check"
	var r: Dictionary = LevelBaker.bake(scene, out)
	_check(bool(r["ok"]), "the meadow scene bakes (%s)" % r.get("error", ""))
	if bool(r["ok"]):
		var again: PackedByteArray = FileAccess.get_file_as_bytes(r["bin"])
		var shipped: PackedByteArray = FileAccess.get_file_as_bytes("res://shared/world/meadow_depth.bin")
		var json_again: String = FileAccess.get_file_as_string(r["json"])
		var json_shipped: String = FileAccess.get_file_as_string("res://shared/world/meadow.json")
		_check(again == shipped and json_again == json_shipped,
			"and the bake is exactly what the server compiled in (else: move nothing, or bake again with LevelInfo's button)")
	var spot: LevelSpot = scene.get_node(^"PondSpot") as LevelSpot
	spot.position.x += 3.0
	var moved: Dictionary = LevelBaker.bake(scene, out)
	_check(float((moved["doc"]["spots"] as Array)[0]["x"]) == 3.0, "a marker moved in the scene moves in the bake")
	var info: LevelInfo = scene.get_node(^"LevelInfo") as LevelInfo
	info.water_y = 5.0
	var flooded: Dictionary = LevelBaker.bake(scene, out)
	_check(int(flooded["wet"]) > int(r["wet"]) * 2, "and the water is read off the ground: raised, it floods the meadow (%d wet cells, was %d)" % [flooded["wet"], r["wet"]])
	scene.queue_free()
	await get_tree().process_frame
	# --- the lakeside: the baker against its generator ------------------------------------------
	var shipped_lake: LevelBake = LevelBake.load_level("lakeside")
	var lake: Node3D = (load(LAKESIDE_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(lake)
	for i: int in range(8):
		await get_tree().physics_frame
	var settings: Dictionary = {"level_name": "lakeside_check", "level_id": 1, "water_y": shipped_lake.water_y,
		"wade_depth": shipped_lake.wade_depth, "min_cast_depth": shipped_lake.min_cast_dm / 10.0, "grid_spacing": 1.0,
		"bounds": AABB(Vector3(shipped_lake.origin_x, -40, shipped_lake.origin_z),
			Vector3(shipped_lake.width - 1, 80, shipped_lake.height - 1))}
	var lr: Dictionary = LevelBaker.bake(lake, out, settings)
	var differ: int = 0
	var cells: int = 0
	var wet_shipped: int = 0
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(lr.get("bin", "")))
	var w: int = int(lr.get("width", 0))
	var ox: float = float(lr["doc"]["depth_grid"]["origin_x"]) if bool(lr["ok"]) else 0.0
	var oz: float = float(lr["doc"]["depth_grid"]["origin_z"]) if bool(lr["ok"]) else 0.0
	for j: int in range(int(lr.get("height", 0))):
		for i: int in range(w):
			var x: float = ox + i
			var z: float = oz + j
			var mine: int = bytes[j * w + i]
			var theirs: int = shipped_lake.depth_dm_at(x, z)
			cells += 1
			wet_shipped += 1 if theirs > 0 else 0
			if absi(mine - theirs) > 1:
				differ += 1
	_check(bool(lr["ok"]) and cells > 1000 and differ < wet_shipped / 50,
		"baked from its scene, the lakeside's lake matches its generator's to a decimetre in all but %d of %d wet cells" % [differ, wet_shipped])
	_check(bool(lr["ok"]) and (lr["doc"]["spots"] as Array).size() == shipped_lake.spots.size()
		and Vector3(lr["doc"]["spawn"][0], lr["doc"]["spawn"][1], lr["doc"]["spawn"][2]).distance_to(shipped_lake.spawn) < 0.01,
		"and its spots and spawn, read off its markers, are the generator's")
	lake.queue_free()
	await get_tree().process_frame
	# --- the level on screen follows the world's -------------------------------------------------
	var game := Node3D.new()
	game.name = "LevelGame"
	get_tree().root.add_child(game)
	var grey: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	grey.name = "Greybox"
	game.add_child(grey)
	var loader := LevelLoader.new()
	loader.current = ^"../Greybox"
	loader.current_id = 0
	game.add_child(loader)
	var prev_root: NodePath = EntitySpawner.world_root_path
	EntitySpawner.world_root_path = EntitySpawner.get_path_to(grey.get_node(^"WorldRoot"))
	var walker := Node3D.new()
	walker.name = "Walker"
	grey.get_node(^"WorldRoot").add_child(walker)
	walker.global_position = Vector3(2, 0, 3)
	EntitySpawner._nodes[987654] = walker
	await get_tree().process_frame
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(0)))
	_check(loader.level() == grey and loader.level_id() == 0, "the level the world already runs is left as it is")
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, LevelLoader.TABLE, null, FakeWorldLevelRow.new(2)))
	await get_tree().process_frame
	var shown: Node3D = loader.level()
	_check(loader.level_id() == 2 and shown != null and shown.scene_file_path == "res://game/world/levels/meadow.tscn"
		and not is_instance_valid(grey) or (is_instance_valid(grey) and grey.is_queued_for_deletion()),
		"when the world runs the meadow, its scene (the bake's) replaces the greybox")
	_check(walker.get_parent() == shown.get_node(^"WorldRoot") and walker.global_position.is_equal_approx(Vector3(2, 0, 3))
		and EntitySpawner.get_node(EntitySpawner.world_root_path) == shown.get_node(^"WorldRoot"),
		"and the entities move into its WorldRoot, where they were, where new ones will spawn")
	_check(not loader.show_level(77) and loader.level_id() == 2, "a level nothing can show is said, and the current one stays")
	EntitySpawner._nodes.erase(987654)
	EntitySpawner.world_root_path = prev_root
	game.queue_free()
	await get_tree().process_frame


## THE VERSION CHECK (DECISIONS #164). The fingerprint is of what the bindings depend on: the
## same for the same schema in any key order or with other indexes, different for a changed
## reducer, column, table or access. And the bindings' recorded fingerprint is the schema the last
## codegen actually read: a stale one would refuse every server, or none.
func _run_version_tests() -> void:
	print("== the version check ==")
	var text: String = SpaceTimeSync.codegen_schema_text()
	_check(not text.is_empty(), "the last codegen's schema is on disk")
	var fp: String = SchemaFingerprint.of(text)
	_check(fp.length() == SchemaFingerprint.LENGTH, "a schema has a fingerprint (%s)" % fp)
	_check(fp == SpaceTimeSync.bindings_fingerprint(),
		"the bindings' fingerprint (%s) is the schema codegen read (%s): run tools/publish.sh --codegen"
			% [SpaceTimeSync.bindings_fingerprint(), fp])
	_check(SchemaFingerprint.of("") == "" and SchemaFingerprint.of("<html>not found</html>") == ""
		and SchemaFingerprint.of("[1, 2]") == "", "text that is not a schema has none")
	var schema: Dictionary = JSON.parse_string(text) as Dictionary
	# The same schema, every key in reverse order.
	_check(SchemaFingerprint.of(JSON.stringify(_reversed_keys(schema), "", false)) == fp,
		"the same schema with its keys in another order has the same fingerprint")
	# The server lists its tables, reducers and names in another order on every publish (#186).
	var shuffled: Dictionary = schema.duplicate(true)
	for section: String in ["Tables", "Reducers", "Types"]:
		_schema_section(shuffled, section).reverse()
	var named: Variant = _schema_section_dict(shuffled, "ExplicitNames").get("entries")
	if named is Array:
		(named as Array).reverse()
	_check(SchemaFingerprint.of(JSON.stringify(shuffled)) == fp,
		"the same schema with its tables, reducers and names listed in another order has the same fingerprint")
	var tables: Array = _schema_section(schema, "Tables")
	var reducers: Array = _schema_section(schema, "Reducers")
	_check(not tables.is_empty() and not reducers.is_empty(), "the schema lists tables and reducers")
	if tables.is_empty() or reducers.is_empty():
		return
	var same: Dictionary = schema.duplicate(true)
	(_schema_section(same, "Tables")[0] as Dictionary)["indexes"] = []
	_schema_section(same, "RowLevelSecurity").clear()
	_check(SchemaFingerprint.of(JSON.stringify(same)) == fp,
		"another index or another row-level filter does not change it (the client is unaffected)")
	var cases: Dictionary[String, Callable] = {
		"a reducer's argument retyped": func(d: Dictionary) -> void:
			var params: Array = ((_schema_section(d, "Reducers")[0] as Dictionary)["params"] as Dictionary)["elements"]
			(params[0] as Dictionary)["algebraic_type"] = {"String": []},
		"a reducer added": func(d: Dictionary) -> void:
			var r: Dictionary = (_schema_section(d, "Reducers")[0] as Dictionary).duplicate(true)
			r["source_name"] = "brand_new_reducer"
			_schema_section(d, "Reducers").append(r),
		"a table made private": func(d: Dictionary) -> void:
			(_schema_section(d, "Tables")[0] as Dictionary)["table_access"] = {"Private": []},
		"a table renamed": func(d: Dictionary) -> void:
			(_schema_section(d, "Tables")[0] as Dictionary)["source_name"] = "renamed",
		"a column added to a row type": func(d: Dictionary) -> void:
			var types: Array = (_schema_section_dict(d, "Typespace")["types"]) as Array
			var product: Dictionary = (types[0] as Dictionary)["Product"]
			(product["elements"] as Array).append({"name": {"some": "extra"}, "algebraic_type": {"U8": []}}),
	}
	for what: String in cases:
		var changed: Dictionary = schema.duplicate(true)
		cases[what].call(changed)
		var other: String = SchemaFingerprint.of(JSON.stringify(changed))
		_check(not other.is_empty() and other != fp, "%s changes it (%s -> %s)" % [what, fp, other])
	_check(SchemaFingerprint.url("http://127.0.0.1:3000/", "umf-test")
			== "http://127.0.0.1:3000/v1/database/umf-test/schema?version=10"
		and SchemaFingerprint.url("wss://maincloud.spacetimedb.com", "my game").begins_with(
			"https://maincloud.spacetimedb.com/v1/database/my%20game/"),
		"the schema is asked for at the server's address, over http(s)")
	_check(SchemaFingerprint.mismatch_message("aaa", "bbb").contains("different version")
		and SchemaFingerprint.mismatch_message("aaa", "bbb").contains("aaa"),
		"a mismatch is explained, with both fingerprints")


func _schema_section(schema: Dictionary, key: String) -> Array:
	for s: Variant in schema.get("sections", []) as Array:
		if s is Dictionary and (s as Dictionary).has(key) and (s as Dictionary)[key] is Array:
			return (s as Dictionary)[key] as Array
	return []


func _schema_section_dict(schema: Dictionary, key: String) -> Dictionary:
	for s: Variant in schema.get("sections", []) as Array:
		if s is Dictionary and (s as Dictionary).has(key) and (s as Dictionary)[key] is Dictionary:
			return (s as Dictionary)[key] as Dictionary
	return {}


func _reversed_keys(v: Variant) -> Variant:
	if v is Dictionary:
		var out: Dictionary = {}
		var keys: Array = (v as Dictionary).keys()
		keys.reverse()
		for k: Variant in keys:
			out[k] = _reversed_keys((v as Dictionary)[k])
		return out
	if v is Array:
		var out: Array = []
		for e: Variant in v as Array:
			out.append(_reversed_keys(e))
		return out
	return v


## THE HUD FITS THE WINDOW (DECISIONS #161). Luke's 860 x 445 game view had the fight gauge over
## the prompt; at 1280 x 720 they touched. Laid out in a viewport of each size: the gauge never covers
## the prompt or the hook-set bar, and stays on screen.
func _run_hud_layout_tests() -> void:
	print("== the HUD fits the window ==")
	for at: Vector2i in [Vector2i(860, 445), Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var view := SubViewport.new()
		view.size = at
		add_child(view)
		var hud: Control = (load("res://game/fishing/fishing_hud.tscn") as PackedScene).instantiate() as Control
		view.add_child(hud)
		await get_tree().process_frame
		await get_tree().process_frame
		var gauge: Rect2 = (hud.call("reel_gauge") as Control).get_global_rect()
		var prompt: Rect2 = (hud.get_node(^"Prompt") as Control).get_global_rect()
		var bar: Rect2 = (hud.get_node(^"Bar") as Control).get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(at))
		_check(not gauge.intersects(prompt) and not gauge.intersects(bar) and screen.encloses(gauge),
			"at %d x %d the fight gauge (%s) is on screen and clear of the prompt (%s) and the hook-set bar"
				% [at.x, at.y, gauge, prompt])
		view.free()


## AN ITEM IN HAND OR PUT AWAY (DECISIONS #159): the equip state, on its own clock. Stepped by hand
## here; the real rig and the cast are in the animation-scene and aim suites.
func _run_equip_tests() -> void:
	print("== equip: in hand, or put away ==")
	var e := EquipComponent.new()
	add_child(e)
	e.set_process(false)
	e.draw_sec = 0.4
	e.stow_sec = 0.6
	e.away_after_sec = 1.0
	var log: Array[String] = []
	e.equip_started.connect(func(d: bool) -> void: log.append("start %s" % ("draw" if d else "stow")))
	e.equip_cancelled.connect(func(d: bool) -> void: log.append("back %s" % ("draw" if d else "stow")))
	e.equipped_changed.connect(func(on: bool) -> void: log.append("in hand" if on else "away"))
	_check(e.state() == EquipComponent.State.AWAY and not e.is_equipped(), "it starts put away")
	e.needed()
	_check(e.state() == EquipComponent.State.DRAWING and not e.is_equipped() and log == (["start draw"] as Array[String]),
		"needed, it starts drawing; not in hand yet (%s)" % str(log))
	e._process(0.3)
	_check(not e.is_equipped(), "not in hand 0.3 s into a 0.4 s draw")
	e._process(0.15)
	_check(e.is_equipped() and log.back() == "in hand", "in hand when the draw's time is up")
	for i: int in range(9):
		e._process(0.1)
		if i == 4:
			e.needed()
	_check(e.state() == EquipComponent.State.READY, "used part way, it stays in hand past the idle time from when it was drawn")
	e._process(0.6)
	_check(e.state() == EquipComponent.State.STOWING and log.back() == "start stow",
		"a full second unused, it starts going away (%s)" % str(log))
	e.needed()
	_check(e.is_equipped() and log.back() == "back stow", "needed again while going, it is turned back: in hand at once")
	e.put_away()
	e._process(0.7)
	_check(e.state() == EquipComponent.State.AWAY and log.back() == "away", "put away, it is away when the put-away's time is up")
	e.draw()
	e.put_away()
	_check(e.state() == EquipComponent.State.AWAY and log.back() == "back draw", "a draw turned back half way leaves it away")
	e.away_when_idle = false
	e.set_equipped_now(true)
	e._process(5.0)
	_check(e.is_equipped() and log.back() == "in hand", "carried (not away when idle), it stays in hand however long it is unused")
	e.free()


## THE FOUNDATION'S RULES ARE DATA (DECISIONS #154): `shared/rules.json`, read by the client here
## and compiled into the module by build.rs. The integration suite proves the module took the
## same numbers; this proves the client reads them and the build reads the same file.
func _run_rules_tests() -> void:
	print("== rules: shared/rules.json ==")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Rules.PATH)) as Dictionary
	_check(raw != null and raw.has("player") and raw.has("sessions"), "shared/rules.json parses")
	if raw == null:
		return
	_check(is_equal_approx(Rules.max_health(), float((raw["player"] as Dictionary)["max_health"]))
			and is_equal_approx(Rules.interact_range(), float(raw["interact_range_m"])),
		"a new player's health and the interact range are the file's (%s, %s m)" % [Rules.max_health(), Rules.interact_range()])
	var names: Array[String] = []
	var total: float = 0.0
	for p: Variant in Rules.phases(0):
		names.append(Rules.phase_name(0, int((p as Dictionary)["phase"])))
		total += Rules.phase_seconds(0, int((p as Dictionary)["phase"]))
	_check(names == (["lobby", "playing", "results", "shop"] as Array[String]) and total > 0.0,
		"session kind 0 goes round its phases in the file's order: %s (%.0f s a round)" % [", ".join(names), total])
	_check(Rules.phase_name(0, 42).is_empty() and Rules.phases(77).is_empty() and is_zero_approx(Rules.phase_seconds(77, 1)),
		"a phase or a kind the file does not plan has no name and no length")
	_check(FileAccess.get_file_as_string("res://server/build.rs").contains("../shared/rules.json"),
		"and the server's build compiles the same file in")
	# THE DATABASE: the test suites set UMF_DB, people do not.
	var cfg := NetConfig.new()
	var was: String = OS.get_environment("UMF_DB")
	OS.unset_environment("UMF_DB")
	var plain: String = SpaceTimeSync.database_name(cfg)
	OS.set_environment("UMF_DB", "umf_probe")
	var steered: String = SpaceTimeSync.database_name(cfg)
	if was.is_empty():
		OS.unset_environment("UMF_DB")
	else:
		OS.set_environment("UMF_DB", was)
	_check(plain == cfg.module_name and steered == "umf_probe",
		"a client joins its config's database (%s), or the one UMF_DB names (%s)" % [plain, steered])

func _run_fishing_fx_tests() -> void:
	print("== fishing presentation: the line ==")
	var fx := FishingFx.new()
	fx.ripple_override = func(_at: Vector3, _strength: float) -> void: pass
	get_tree().root.add_child(fx)
	# No rod in hand: the line leaves from 1.5 m above the node, 2.5 m above the water here.
	fx.global_position = Vector3(0.0, 1.0, 0.0)
	var water := Vector3(0.0, 0.0, -40.0)
	fx.place_at(water)
	await get_tree().process_frame
	await get_tree().process_frame
	var pts: PackedVector3Array = fx.line_points()
	var under: int = 0
	var lying: int = 0
	for p: Vector3 in pts:
		if p.y < water.y:
			under += 1
		if is_equal_approx(p.y, water.y + FishingFx.LINE_ON_WATER):
			lying += 1
	_check(pts.size() > 40 and pts[0].is_equal_approx(Vector3(0.0, 2.5, 0.0))
			and Vector2(pts[-1].x, pts[-1].z).distance_to(Vector2(water.x, water.z)) < 0.01,
		"a 40 m line runs from the rod tip to the float, finely (%d points)" % pts.size())
	_check(under == 0, "and never under the lake (%d points under)" % under)
	_check(lying > pts.size() / 3 and pts[pts.size() / 10].y > water.y + 0.3,
		"it droops from the tip and lies on the water for much of its length (%d of %d points)" % [lying, pts.size()])
	fx.queue_free()
	await get_tree().process_frame


## THE NATURE KIT, AS THE LAKESIDE DRAWS IT (DECISIONS #137, #141). Every model the terrain's
## instancer places, as imported: each leaf, petal and blade is FoliageMaterial's shader â€” cut-out
## exactly where the kit's own material was, opaque where it was not â€” and nothing else is. The
## import script does this, and editing the script reimports nothing, so this is what says a
## reimport happened. That the shader LIGHTS a back face is `tests/render_test.sh`: a headless
## run has no pixels.
func _run_kit_tests() -> void:
	print("== nature kit ==")
	var assets: Terrain3DAssets = load(LAKESIDE_ASSETS) as Terrain3DAssets
	_check(assets != null and assets.get_mesh_count() > 0, "the lakeside's instancer has its meshes")
	if assets == null:
		return
	var foliage: int = 0
	var solid: int = 0
	var wrong: PackedStringArray = PackedStringArray()
	for id: int in range(assets.get_mesh_count()):
		var ma: Terrain3DMeshAsset = assets.get_mesh_asset(id)
		var scene: PackedScene = ma.scene_file if ma != null else null
		if scene == null:
			wrong.append("mesh asset %d has no scene" % id)
			continue
		var source: String = scene.resource_path
		var gltf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source)) as Dictionary
		var modes: Dictionary[String, String] = {}
		for m: Variant in gltf.get("materials", []):
			var md: Dictionary = m as Dictionary
			modes[str(md.get("name", ""))] = str(md.get("alphaMode", "OPAQUE"))
		var root: Node = scene.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for i: int in range(mesh.get_surface_count()):
				var mat: Material = mesh.surface_get_material(i)
				var what: String = "%s: %s" % [source.get_file(), mat.resource_name if mat != null else "<none>"]
				if not FoliageMaterial.is_foliage(mat):
					solid += 1
					if not mat is StandardMaterial3D:
						wrong.append(what + " is not foliage, and not the kit's own material")
					continue
				foliage += 1
				var sm: ShaderMaterial = mat as ShaderMaterial
				var cut: bool = modes.get(mat.resource_name, "OPAQUE") != "OPAQUE"
				var want: Shader = FoliageMaterial.SHADER_CUTOUT if cut else FoliageMaterial.SHADER_OPAQUE
				if sm == null or sm.shader != want:
					wrong.append(what + " is %s, not the foliage shader (%s)" % [mat.get_class(), "cut-out" if cut else "opaque"])
				elif sm.get_shader_parameter(&"texture_albedo") == null:
					wrong.append(what + " lost its texture")
		root.free()
	print("   %d leaf and blade surfaces, %d solid ones" % [foliage, solid])
	_check(foliage > 50 and solid > 20, "the kit's models have both foliage and solid surfaces (%d, %d)" % [foliage, solid])
	_check(wrong.is_empty(), "every leaf, petal and blade the lakeside draws is the two-sided foliage shader, "
		+ "and nothing else is (reimport the Nature kit if not):
      " + "
      ".join(wrong))

	# The blended cherry blossom leaf is a cut-out (#137), at the kit's threshold for it.
	var cherry: PackedScene = load(NATURE_KIT + "CherryBlossom_1.gltf") as PackedScene
	var leaf: ShaderMaterial = null
	if cherry != null:
		var root: Node = cherry.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for i: int in range(mesh.get_surface_count()):
				if mesh.surface_get_material(i) != null and mesh.surface_get_material(i).resource_name == "Leaves_CherryBlossom":
					leaf = mesh.surface_get_material(i) as ShaderMaterial
		root.free()
	_check(leaf != null and leaf.shader == FoliageMaterial.SHADER_CUTOUT
		and is_equal_approx(float(leaf.get_shader_parameter(&"alpha_scissor_threshold")), 0.5),
		"the cherry blossom's blended leaves are imported as a cut-out at 0.5")

	# The conversion carries every value the kit's foliage uses across, and refuses what it cannot.
	var std := StandardMaterial3D.new()
	std.resource_name = "Leaves_Test"
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	std.alpha_scissor_threshold = 0.2
	std.albedo_color = Color(0.9, 0.8, 0.7, 1.0)
	std.albedo_texture = PlaceholderTexture2D.new()
	std.vertex_color_use_as_albedo = true
	std.vertex_color_is_srgb = true
	std.roughness = 0.8
	std.metallic_specular = 0.3
	var conv: ShaderMaterial = FoliageMaterial.from_standard(std)
	_check(conv.shader == FoliageMaterial.SHADER_CUTOUT and conv.resource_name == "Leaves_Test"
		and conv.get_shader_parameter(&"albedo") == Color(0.9, 0.8, 0.7, 1.0)
		and conv.get_shader_parameter(&"texture_albedo") == std.albedo_texture
		and is_equal_approx(float(conv.get_shader_parameter(&"alpha_scissor_threshold")), 0.2)
		and bool(conv.get_shader_parameter(&"use_vertex_color")) and bool(conv.get_shader_parameter(&"vertex_color_is_srgb"))
		and is_equal_approx(float(conv.get_shader_parameter(&"roughness")), 0.8)
		and is_equal_approx(float(conv.get_shader_parameter(&"specular")), 0.3),
		"FoliageMaterial.from_standard carries the kit material's values across")
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(FoliageMaterial.from_standard(std).shader == FoliageMaterial.SHADER_OPAQUE, "an opaque blade stays opaque")
	std.normal_enabled = true
	_check(not FoliageMaterial.unsupported(std).is_empty(), "a leaf with a normal map is left as the kit made it")
	std.normal_enabled = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_check(not FoliageMaterial.unsupported(std).is_empty(), "and so is one still blended")
	var bark := StandardMaterial3D.new()
	bark.resource_name = "Bark_NormalTree"
	_check(not FoliageMaterial.is_foliage(bark) and FoliageMaterial.is_foliage(std),
		"bark is not foliage, and a leaf is")

## THE GAME'S LEVEL, WALKED. The lakeside is generated (`tools/world/build_lakeside.tscn`), and a
## generated level can be wrong in ways nobody sees until they play it: a spawn inside the
## ground, a ramp too steep to climb, a dock you can walk off, a lake you can walk into. So a
## real predicted player — the real scene, spawner, resolver and terrain collision — takes the
## route a new player takes, from the spawn to the end of the dock, and leans on every barrier.
func _run_lakeside_tests() -> void:
	print("== lakeside scene ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	if reg == null or spawner == null:
		_check(false, "autoloads present")
		return
	var packed: PackedScene = load(LAKESIDE_SCENE) as PackedScene
	_check(packed != null, "lakeside.tscn loads")
	if packed == null:
		return
	var level: LakesideLevel = packed.instantiate() as LakesideLevel
	_check(level != null, "the lakeside's root is a LakesideLevel")
	if level == null:
		return
	get_tree().root.add_child(level)
	for i: int in range(5):
		await get_tree().physics_frame
	var bake: LevelBake = level.bake()
	_check(bake != null and level.terrain() != null and level.water() != null,
		"the level has its terrain, its water and its bake")
	if bake == null:
		level.queue_free()
		return
	var marker: Marker3D = level.get_node_or_null(^"SpawnPoint") as Marker3D
	_check(marker != null and marker.position.is_equal_approx(bake.spawn),
		"the scene's spawn marker is the bake's spawn, which is the one the server uses")
	var world_root: Node3D = level.get_node_or_null(^"WorldRoot") as Node3D
	_check(world_root != null, "the level exposes a WorldRoot for spawned entities")

	# The ground, through the engine: the terrain's collision is where the bake says it is.
	# OFF THE GRID LINES. Godot Physics' heightmap lets a perfectly vertical ray that runs exactly
	# along a cell edge slip between the triangles, in some chunks and not others: (-20, 62) finds
	# nothing at all while (-20.01, 62.01) finds the terrace. Bodies are unaffected; rays are
	# not. The first version of this test fed that miss back as a spawn height of NaN, and a
	# body at NaN takes the whole physics step down with it — the suite hung, not failed.
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x + 0.137, 60.0, z + 0.071),
			Vector3(x + 0.137, -40.0, z + 0.071), SpaceTimeEntity.WORLD_MASK)
		var hit: Dictionary = space.intersect_ray(q)
		return NAN if hit.is_empty() else (hit["position"] as Vector3).y
	var spawn_ground: float = ground_at.call(bake.spawn.x, bake.spawn.z)
	_check(absf(spawn_ground - bake.spawn.y) < 0.1,
		"there is ground under the spawn, where the spawn stands (%.2f vs %.2f)" % [spawn_ground, bake.spawn.y])
	var deck: float = ground_at.call(0.0, 40.0)
	_check(absf(deck - 0.9) < 0.05, "the pier's deck is walkable collision at deck height (%.2f)" % deck)
	var bed: float = ground_at.call(0.0, -24.0)
	_check(bed < -5.0, "mid-lake, the ground is the lakebed, far under the surface (%.2f)" % bed)

	# A real, predicted, local player.
	var eid: int = 4300
	var prev_local: int = reg.local_entity_id
	reg.local_entity_id = eid
	var defn := EntityDefinition.new()
	defn.kind = 0
	defn.scene = load(PLAYER_SCENE) as PackedScene
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(world_root)
	spawner._world_ready = true
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var body: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(body != null and body.is_local_authority, "a local, predicted player spawned into the lakeside")
	if body != null:
		var jm: SpaceTimeMovementComponent = body.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		var ji: LocalInputComponent = body.find_component(LocalInputComponent) as LocalInputComponent
		ji.set_physics_process(false)   # this test drives the frames itself
		var seq: Array[int] = [5000]
		await _place_predicted(jm, bake.spawn, seq, 30)
		_check(jm.get_predicted_state().grounded and absf(body.global_position.y - bake.spawn.y) < 0.1,
			"a player at the spawn stands on the ground (y=%.2f)" % body.global_position.y)

		# Straight ahead from the spawn: down the ramp, out along the pier, to the dock's end.
		await _frames_walk(jm, seq, Vector2(0.0, -1.0), 660)
		var at: Vector3 = body.global_position
		print("   spawn -> dock head: stopped at %s" % at)
		_check(at.z < 29.0 and absf(at.y - 0.9) < 0.1,
			"walking north from the spawn goes down the ramp and out along the pier to the dock head (at %s)" % at)
		_check(at.z > 22.2, "the head's rail stops the walk at its edge, not in the lake (z=%.2f)" % at.z)
		await _frames_walk(jm, seq, Vector2(-1.0, 0.0), 150)
		at = body.global_position
		_check(at.x > -5.1 and absf(at.y - 0.9) < 0.1, "the head's west rail keeps you on the deck (at %s)" % at)
		for side: float in [-1.0, 1.0]:
			await _place_predicted(jm, Vector3(0.0, 0.95, 40.0), seq, 20)
			await _frames_walk(jm, seq, Vector2(side, 0.0), 120)
			at = body.global_position
			_check(absf(at.x) < 2.1 and absf(at.y - 0.9) < 0.1,
				"nobody steps off the %s side of the pier (at %s)" % ["west" if side < 0.0 else "east", at])

		# Wading: from the bank west of the dock, straight out into the lake.
		var bank := Vector3(-20.0, 0.0, 62.0)
		var bank_ground: float = ground_at.call(bank.x, bank.z)
		_check(not is_nan(bank_ground), "there is ground on the bank west of the dock")
		if not is_nan(bank_ground):
			bank.y = bank_ground + 0.05
			await _place_predicted(jm, bank, seq, 30)
			await _frames_walk(jm, seq, Vector2(0.0, -1.0), 300)
			at = body.global_position
			var depth: float = bake.depth_at(at.x, at.z)
			print("   wading from the bank: stopped at %s, %.1f m deep" % [at, depth])
			_check(depth > 0.0 and depth <= bake.wade_depth + 0.25,
				"walking into the lake stops at wading depth: in the water, no deeper than %.1f m (%.2f m at %s)"
					% [bake.wade_depth, depth, at])
			_check(at.y > -bake.wade_depth - 0.3, "with the feet still on the shallow bed (y=%.2f)" % at.y)
		ji.set_physics_process(true)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	await _run_lakeside_cast_tests(reg, spawner, world_root, bake)
	reg.local_entity_id = prev_local
	level.queue_free()
	await get_tree().process_frame


## THE CAST, PLAYED ON THE DOCK (Fishing for Compliments' aimed cast, DECISIONS #136). The real
## fisher scene, as the local player, at the end of the real dock over the real lake: hold the
## cast button and the ring goes out over the water; look back at the village and it is dry
## land; let go and `cast` is sent to where the ring was. And the angler turns to face wherever
## they are aiming, standing still — the bug this was written for: cast behind you and only the
## line and the float went that way.
func _run_lakeside_cast_tests(reg: Node, spawner: Node, world_root: Node3D, bake: LevelBake) -> void:
	print("== lakeside: the aimed cast ==")
	# --- the arc, as a pure function ---------------------------------------------------------
	var feet := Vector3(0.0, 0.9, 24.0)
	var north := Vector3(0.0, 0.45, -1.0)
	var reach: float = FishingData.max_cast_m(0)
	var lob: Dictionary = FishingComponent.solve_cast(feet, north, 0.0, reach, bake.water_y)
	var full: Dictionary = FishingComponent.solve_cast(feet, north, 1.0, reach, bake.water_y)
	_check(float(full["range"]) > float(lob["range"]) + 5.0,
		"holding longer throws further (%.1f m at no charge, %.1f m at full)" % [float(lob["range"]), float(full["range"])])
	_check(float(full["range"]) <= reach + 1e-3, "and never further than the rod reaches (%.1f of %.1f m)" % [float(full["range"]), reach])
	var fp: Vector3 = full["point"]
	_check(is_equal_approx(fp.y, bake.water_y) and fp.z < feet.z and absf(fp.x) < 0.01,
		"it lands on the water, straight out the way it was thrown (%s)" % fp)
	_check(float(full["flight"]) > float(lob["flight"]) and float(lob["flight"]) > 0.2,
		"a longer cast is longer in the air (%.2f s vs %.2f s)" % [float(full["flight"]), float(lob["flight"])])
	var arc: PackedVector3Array = full["arc"]
	_check(arc.size() > 10 and arc[0].y > feet.y + 1.0, "the arc starts up at the rod, not at the feet (%d points)" % arc.size())
	var better: Dictionary = FishingComponent.solve_cast(feet, north, 1.0, FishingData.max_cast_m(FishingData.max_tier()),
		bake.water_y)
	_check(float(better["range"]) > float(full["range"]) + 10.0,
		"the best rod reaches much further (%.1f m)" % float(better["range"]))
	var down: Dictionary = FishingComponent.solve_cast(feet, Vector3(0.0, -1.0, -0.2), 0.5, reach, bake.water_y)
	_check((down["point"] as Vector3).z < feet.z - 2.0, "aiming at your own feet still lobs it out in front")

	# --- FfC's gate, said out loud (DECISIONS #143) ----------------------------------------------
	# A rod decides which spots can be reached at all. From the dock head, thrown straight at the
	# Deep Hole: the starting rod's ring falls short, and the aim says what lies further out and
	# which rod reaches it; the rod that reaches it is not told about it.
	var hole := Vector3.ZERO
	for s: Dictionary in bake.spots:
		if str(s["id"]) == "deep_hole":
			hole = Vector3(float(s["x"]), bake.water_y, float(s["z"]))
	var at_hole: Vector3 = (hole - feet) * Vector3(1.0, 0.0, 1.0)
	var short: Vector3 = feet + at_hole.normalized() * reach
	_check(FishingData.min_rod("deep_hole") == 2 and FishingData.min_rod("north_drop") == 1
			and FishingData.min_rod("dock_end") == 0 and FishingData.min_rod("") == 0,
		"the spots declare the rod that reaches them: the North Drop the Ash Rod's, the Deep Hole the Yew Longrod's")
	_check(str(FishingComponent.spot_beyond(bake, feet, short, 0).get("id", "")) == "deep_hole",
		"with the starting rod, aimed at the Deep Hole, the aim names it as further out")
	_check(FishingComponent.spot_beyond(bake, feet, short, 2).is_empty(),
		"with the Yew Longrod it does not: that rod reaches it")
	_check(FishingComponent.spot_beyond(bake, feet, feet + Vector3(0.0, 0.0, 10.0), 0).is_empty(),
		"and aimed back at the village there is nothing further out to name")
	_check(FishingData.spots_opened_by(1, bake) == PackedStringArray(["The North Drop"])
			and FishingData.spots_opened_by(2, bake) == PackedStringArray(["The Deep Hole"])
			and FishingData.spots_opened_by(3, bake).is_empty(),
		"the shop can say which water a rod opens (1: %s, 2: %s)"
			% [str(FishingData.spots_opened_by(1, bake)), str(FishingData.spots_opened_by(2, bake))])

	# --- the rig, on the dock ------------------------------------------------------------------
	var fisher_def: EntityDefinition = load("res://game/fishing/fisher_definition.tres") as EntityDefinition
	var eid: int = 4310
	reg.local_entity_id = eid
	spawner.register_definition(fisher_def)
	_buffer_player_rows(reg, eid)
	spawner._on_entity_inserted(RowEvent.make(
		RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	_check(me != null and me.is_local_authority, "the real fisher spawned on the lakeside as the local player")
	if me == null:
		return
	var fishing: FishingComponent = me.find_component(FishingComponent) as FishingComponent
	var li: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var session: SessionComponent = me.find_component(SessionComponent) as SessionComponent
	li.send_to_server = false
	li.set_physics_process(false)   # frames are pushed below, so the heading is the rule's alone
	var seq: Array[int] = [7000]
	await _place_predicted(mv, Vector3(0.0, 0.95, 24.5), seq, 30)
	_check(mv.get_predicted_state().grounded and absf(me.global_position.y - 0.9) < 0.1,
		"standing on the dock head (%s)" % me.global_position)
	var sent: Array[ReducerRequest] = []
	# The equip state's reports to the server, kept apart (DECISIONS #160).
	var told: Array[int] = []
	var scb := func(req: ReducerRequest) -> void:
		if req.reducer_name == &"set_equip_state":
			told.append(int(req.args[0]))
		elif req.reducer_name != &"submit_input":
			sent.append(req)
	SpaceTimeSync.reducer_settled.connect(scb)
	var refused: Array[String] = []
	var rcb := func(why: String) -> void: refused.append(why)
	fishing.cast_refused.connect(rcb)
	var released: Array[Vector3] = []
	var relcb := func(t: Vector3, _f: float) -> void: released.append(t)
	fishing.cast_released.connect(relcb)
	var sample_frames := func(n: int) -> void:
		for i: int in range(n):
			await get_tree().physics_frame
			li.sample()

	# LOOKING AROUND IS NOT AIMING: turn the camera to the village behind, standing still, and
	# the angler keeps facing the lake (DECISIONS #100).
	li.set_look(0.0, 0.25)
	await sample_frames.call(4)
	var facing_lake: float = mv.get_predicted_state().yaw
	li.set_look(PI, 0.25)
	await sample_frames.call(10)
	_check(absf(angle_difference(mv.get_predicted_state().yaw, facing_lake)) < 0.01,
		"looking back at the village, standing still, does not turn the angler (yaw %.2f)" % mv.get_predicted_state().yaw)

	# AIMING IS: hold the button with the camera on the village and the angler turns round.
	fishing.press_cast()
	_check(fishing.rig() == FishingComponent.Rig.CHARGING and li.is_facing_held(),
		"holding the cast button charges, and holds the body facing the aim")
	await sample_frames.call(10)
	_check(absf(angle_difference(mv.get_predicted_state().yaw, PI)) < 0.01,
		"THE ANGLER TURNS TO FACE THE CAST, standing still (yaw %.2f, aiming %.2f)" % [mv.get_predicted_state().yaw, PI])
	await get_tree().create_timer(FishingComponent.CHARGE_SEC + 0.2).timeout
	_check(not bool(fishing.aim()["valid"]) and str(fishing.aim()["reason"]).contains("dry land"),
		"and the ring over the village says it is dry land (%s)" % str(fishing.aim()["reason"]))
	fishing.release_cast()
	_check(sent.is_empty() and fishing.rig() == FishingComponent.Rig.READY,
		"letting go over land casts nothing (%d sent)" % sent.size())
	_check(refused.size() == 1 and refused[0].contains("dry land"), "and says why (%s)" % str(refused))
	_check(not li.is_facing_held(), "the rod is down: the body is free again")

	# OVER THE LAKE: a full charge, a valid ring, and `cast` sent to exactly where it was.
	refused.clear()
	li.set_look(0.0, 0.25)
	fishing.press_cast()
	await sample_frames.call(6)
	_check(absf(angle_difference(mv.get_predicted_state().yaw, 0.0)) < 0.01,
		"aiming back out at the lake turns the angler back (yaw %.2f)" % mv.get_predicted_state().yaw)
	await get_tree().create_timer(FishingComponent.CHARGE_SEC + 0.2).timeout
	var aim: Dictionary = fishing.aim()
	var ring: Vector3 = aim["point"]
	_check(is_equal_approx(fishing.charge(), 1.0), "held long enough, the charge is full (%.2f)" % fishing.charge())
	_check(bool(aim["valid"]) and bake.is_water(ring.x, ring.z),
		"the ring is out on the water, somewhere the server will take (%s, %s)" % [ring, str(aim["reason"])])
	_check(float(aim["range"]) > FishingData.cast_setting("min_range_m") and float(aim["range"]) <= reach + 1e-3,
		"between the minimum and the rod's reach (%.1f m)" % float(aim["range"]))
	_check((aim["spot"] as Dictionary) == bake.spot_at(ring.x, ring.z),
		"and names the spot the bake says it is in (%s)" % str((aim["spot"] as Dictionary).get("id", "open water")))
	fishing.release_cast()
	_check(released.size() == 1 and released[0].is_equal_approx(ring),
		"letting go throws the float at the ring (%s)" % str(released))
	_check(sent.size() == 1 and sent[0].reducer_name == &"cast" and (sent[0].args[0] as Vector3).is_equal_approx(ring),
		"and sends `cast` with that point (%s)" % (str(sent[0].args) if not sent.is_empty() else "nothing"))
	_check(refused.size() == 1 and fishing.rig() == FishingComponent.Rig.READY,
		"with no server to accept it the refusal comes back and the rig resets (%s)" % str(refused))
	_check(not li.is_facing_held(), "and the body is free again")
	# THE FLOAT COMES BACK. It was thrown on the button, before the server answered; refused, it
	# floated on with nothing behind it (Luke's picture: the rod put away under a line still
	# running from its tip to the float).
	var fb: FishingFeedback = me.find_component(FishingFeedback) as FishingFeedback
	var thrown_fx: FishingFx = fb.fx() if fb != null else null
	_check(thrown_fx != null, "the fisher shows its cast (FishingFx)")
	if thrown_fx != null:
		var back_by: int = Time.get_ticks_msec() + 4000
		var came_back: bool = false
		while Time.get_ticks_msec() < back_by:
			await get_tree().process_frame
			if thrown_fx.state() == FishingFx.State.IDLE:
				came_back = true
				break
		_check(came_back and not thrown_fx.line_visible(),
			"and the float it threw comes back in: no float left on the water (%s)" % FishingFx.State.keys()[thrown_fx.state()])

	# NOT UNTIL THE ROD IS IN HAND (DECISIONS #159). Luke: "when the rod is stowed and I do a very
	# fast cast, the cast animation plays, then the draw". Put away, a tap aims and draws, and the
	# cast waits for the hand: nothing is thrown or sent until the rod is out, then it goes by itself.
	var equip: EquipComponent = me.find_component(EquipComponent) as EquipComponent
	_check(equip != null, "the fisher has an equip state")
	if equip != null:
		equip.set_equipped_now(false)
		sent.clear()
		refused.clear()
		released.clear()
		told.clear()
		var in_hand_at_cast: Array[bool] = []
		var watch := func(_t: Vector3, _f: float) -> void: in_hand_at_cast.append(equip.is_equipped())
		fishing.cast_released.connect(watch)
		fishing.press_cast()
		fishing.release_cast()
		await get_tree().process_frame
		_check(equip.state() == EquipComponent.State.DRAWING and fishing.waiting_for_rod()
				and fishing.rig() == FishingComponent.Rig.CHARGING and released.is_empty() and sent.is_empty(),
			"a tap with the rod put away draws it, and the cast waits: nothing thrown, nothing sent")
		var waited: float = 0.0
		while released.is_empty() and refused.is_empty() and waited < equip.draw_sec + 1.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		print("   the cast waited %.2f s for the rod (its draw takes %.2f s)" % [waited, equip.draw_sec])
		# Thrown (and, with no server here, refused after), or refused at once for a short aim: either
		# way not before the rod is in hand.
		_check(equip.draw_sec > 0.1 and (released.size() == 1 or refused.size() >= 1) and in_hand_at_cast.all(func(b: bool) -> bool: return b)
				and waited >= equip.draw_sec - 0.05 and not fishing.waiting_for_rod(),
			"and goes by itself the moment the rod is in hand (%.2f s after the tap), never before" % waited)
		# OTHER PLAYERS SEE THE DRAW AS IT STARTS (DECISIONS #160): the client reports each change,
		# the draw and then the hand, before the cast. (A live server and a second client: the
		# fishing playtest's observer.)
		_check(told == ([EquipComponent.State.DRAWING, EquipComponent.State.READY] as Array[int]),
			"and it tells the server the rod is coming out, then that it is in hand (%s)" % str(told))
		fishing.cast_released.disconnect(watch)
		# AND THE DRAW DOES NOT COME BACK. Luke (0.18.1): "If I have the rod stowed, then just click
		# left click to cast as fast as possible, it draws, casts then draws again." The hand takes
		# the rod a third of the way into the draw; the rest of the draw clip was frozen under the
		# cast (a one-shot covering the whole body stops what is under it) and played on after it.
		var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
		_check(driver != null, "the fisher has an animation driver")
		if driver != null:
			var cast_seen: bool = false
			var cast_over: bool = false
			var covered_upper: bool = false
			var away_in_cast: bool = false
			var draw_after: float = 0.0
			var looked: float = 0.0
			while looked < 4.0 and not (cast_over and equip.state() != EquipComponent.State.READY):
				await get_tree().process_frame
				looked += get_process_delta_time()
				var w: Dictionary[StringName, float] = driver.semantic_weights()
				if driver.action_playing():
					if float(w.get(AnimationSet.INTERACT, 0.0)) > 0.99:
						if cast_seen:
							covered_upper = covered_upper or driver.upper_playing()
						cast_seen = true
					away_in_cast = away_in_cast or not equip.is_equipped()
				elif cast_seen:
					cast_over = true
				if cast_over:
					draw_after = maxf(draw_after, float(w.get(ItemGrip.DRAW, 0.0)))
			print("   after the cast: the draw showed at %.2f; under the cast the draw %s, the rod %s" % [draw_after,
				"played on" if covered_upper else "was over", "went away" if away_in_cast else "stayed in hand"])
			_check(cast_seen and cast_over and not covered_upper and draw_after < 0.01,
				"the cast plays over the rest of the draw, and the draw does not play again after it (%.2f)" % draw_after)
			_check(not away_in_cast,
				"and the rod is not put away while the cast still plays, though the rig is done with it (refused here)")
		fishing.press_cast()
		fishing.cancel_charge()
		_check(not fishing.waiting_for_rod(), "a cancelled aim forgets a waiting cast")

	# OUT OF THE ROUND: nothing charges, nothing is sent, and the player is told.
	sent.clear()
	refused.clear()
	session._apply_session_row(FakeSessionRow.new(1, SessionComponent.Phase.SHOP, 0))
	fishing.press_cast()
	_check(fishing.rig() == FishingComponent.Rig.READY and not li.is_facing_held() and sent.is_empty(),
		"in the shop phase the button does not even start a cast")
	_check(refused.size() == 1 and refused[0].contains("PLAYING"), "and says why (%s)" % str(refused))

	SpaceTimeSync.reducer_settled.disconnect(scb)
	fishing.cast_refused.disconnect(rcb)
	fishing.cast_released.disconnect(relcb)
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame


## Walking frames for a predicted entity, pushed inside physics frames as LocalInputComponent
## pushes them. `dir` is a WORLD direction (x, z).
func _frames_walk(m: SpaceTimeMovementComponent, seq_ref: Array[int], dir: Vector2, n: int) -> void:
	for f: int in range(n):
		await get_tree().physics_frame
		var wf := InputFrame.new()
		seq_ref[0] += 1
		wf.seq = seq_ref[0]
		wf.move_dir = dir
		m.push_input(wf)



## Move a LOCAL_PREDICTED entity the way the server would: a teleport row under a new epoch,
## applied on the next tick. Lets a scene test put the body somewhere without reaching into
## private state.
func _place_predicted(m: SpaceTimeMovementComponent, pos: Vector3, seq_ref: Array[int],
		settle_frames: int = 20) -> void:
	var r := FakeMoveRow.new(m.entity_id, pos, 9_000_000 + seq_ref[0])
	r.last_processed_seq = seq_ref[0]
	r.correction_epoch = m.get_epoch() + 1
	r.teleport_flag = true
	r.grounded = false
	m.receive_row_event(_move_ev(r))
	await get_tree().physics_frame   # the row is applied at the top of this tick
	for i: int in range(settle_frames):
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		m.push_input(f)



## Idle frames for a predicted entity, pushed inside physics frames.
func _frames_idle(m: SpaceTimeMovementComponent, seq_ref: Array[int], n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		m.push_input(f)

## Walk the whole tree and count cameras claiming the view. More than one means whichever
## entity bound last wins, which is not a thing a player should be able to notice.
func _count_current_cameras(node: Node) -> int:
	var n: int = 0
	var cam: Camera3D = node as Camera3D
	if cam != null and cam.current:
		n += 1
	for child: Node in node.get_children():
		n += _count_current_cameras(child)
	return n



# --- LOCAL_PREDICTED reconciliation (PHASE4_SPEC §1, DECISIONS #71/#72) -----------------

## A predicted movement component whose fake body is NOT in the tree, so the collision resolver
## falls back to the pure model and every expected position is exact.
func _make_predicted(eid: int = 55) -> SpaceTimeMovementComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = eid
	var m := SpaceTimeMovementComponent.new()
	m.config = MovementConfig.new()
	m.mode = SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED
	get_tree().root.add_child(m)
	var initial: Dictionary[StringName, RefCounted] = {
		&"movement_state": FakeMoveRow.new(eid, Vector3.ZERO, 1_000)}
	m.bind(owner_entity, initial)
	return m


## Push `n` frames walking in `dir` (camera-relative move_dir), starting at `from_seq`.
func _walk_frames(m: SpaceTimeMovementComponent, from_seq: int, n: int, dir: Vector2) -> Array[InputFrame]:
	var frames: Array[InputFrame] = []
	for i: int in range(n):
		var f := InputFrame.new()
		f.seq = from_seq + i
		f.move_dir = dir
		m.push_input(f)
		frames.append(f)
	return frames


## The server acknowledges input `lps` with the entity at `pos`, and the tick applies it.
##
## The velocity is the one the module would report — what the client's own motion implied at
## that seq — taken from the prediction history when there is one. A fake row with zero
## velocity made every replay re-accelerate from a standstill and drift 27 cm: the first run of
## this suite "found" that, and it was the fixture lying, not the algorithm.
func _ack(m: SpaceTimeMovementComponent, lps: int, pos: Vector3, epoch: int = 0,
		teleport: bool = false) -> void:
	var r := FakeMoveRow.new(m.entity_id, pos, 2_000_000 + lps * 16_667)
	r.last_processed_seq = lps
	r.correction_epoch = epoch
	r.teleport_flag = teleport
	var h: MovementState = m._history.get(lps, null)
	if h != null and not teleport:
		r.vel = h.vel
	m.receive_row_event(_move_ev(r))
	m.apply_pending_rows()


func _free_predicted(m: SpaceTimeMovementComponent) -> void:
	var e: Node = m.entity
	m.queue_free()
	if e != null:
		e.free()


func _run_prediction_tests() -> void:
	print("== prediction & reconciliation ==")
	var bus: Node = _autoload("SignalBus")
	var forward := Vector2(0.0, -1.0)

	# --- the Phase 3 bug, pinned ------------------------------------------------------
	# Walking, the server's echo is always ~100 ms behind where we are NOW. Phase 3 compared
	# the echo with "now", saw most of a metre of error at a sprint, and snapped on nearly every
	# row — the rubber-banding players reported. The echo must be compared with what we
	# predicted AT THE SEQ IT ACKNOWLEDGES.
	var m := _make_predicted()
	var counts: Array[float] = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	var frames: Array[InputFrame] = _walk_frames(m, 1, 40, forward)
	var at10: Vector3 = frames[9].client_pos
	var now: Vector3 = m.get_predicted_state().pos
	_check(now.distance_to(at10) > 1.0,
		"setup: the prediction is over a metre past seq 10 (%.2f m)" % now.distance_to(at10))
	_ack(m, 10, at10)
	_check(counts.is_empty(), "an echo that matches what we predicted AT ITS SEQ is not a correction, however far behind 'now' it is")
	_check(m.get_predicted_state().pos == now, "and the prediction is left exactly where it was")

	# --- (a) matching rows: zero reconciles, pending drains -----------------------------
	_check(m.pending_count() == 30, "acknowledging seq 10 of 40 leaves 30 pending (got %d)" % m.pending_count())
	_ack(m, 25, frames[24].client_pos)
	_ack(m, 40, frames[39].client_pos)
	_check(counts.is_empty() and m.pending_count() == 0, "exact acks: no corrections, nothing left pending")
	_check(frames[39].client_pos == m.get_predicted_state().pos,
		"the Tier A claim sent with a frame is exactly the predicted position for it")
	_check(frames[20].epoch == 0, "frames carry the epoch they were predicted under")
	_free_predicted(m)

	# --- (b) small error: one smooth correction, replayed, glided ------------------------
	m = _make_predicted()
	counts = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	frames = _walk_frames(m, 1, 30, forward)
	var before: Vector3 = m.get_predicted_state().pos
	_ack(m, 20, frames[19].client_pos + Vector3(0.1, 0.0, 0.0))
	_check(counts.size() == 1 and absf(counts[0] - 0.1) < 1e-4, "a 10 cm disagreement is one correction of 10 cm (%s)" % str(counts))
	var shift: Vector3 = m.get_predicted_state().pos - before
	_check(shift.is_equal_approx(Vector3(0.1, 0.0, 0.0)),
		"the correction is replayed: the present moves by the error, not back to the old seq (%s)" % shift)
	_check(m.get_visual_offset().is_equal_approx(Vector3(-0.1, 0.0, 0.0)),
		"the VISUAL stays where it was drawn and glides from there (%s)" % m.get_visual_offset())
	_check(m.get_reconcile_stats()["snaps"] == 0, "10 cm glides, it does not snap")
	for i: int in range(ceili(m.config.reconcile_smooth_time * 60.0)):
		m._decay_visual_offset(1.0 / 60.0)
	_check(m.get_visual_offset().length() < 0.001,
		"the glide completes within reconcile_smooth_time (%.5f m left)" % m.get_visual_offset().length())
	_free_predicted(m)

	# --- (c) large error: snap ---------------------------------------------------------
	m = _make_predicted()
	frames = _walk_frames(m, 1, 30, forward)
	_ack(m, 20, frames[19].client_pos + Vector3(2.0, 0.0, 0.0))
	_check(m.get_reconcile_stats()["snaps"] == 1, "a 2 m disagreement snaps")
	_check(m.get_visual_offset() == Vector3.ZERO, "a snap leaves no glide behind")
	_check(m.pending_count() == 0, "a snap discards the inputs it can no longer trust")
	_free_predicted(m)

	# --- (d) a failed batch is forgotten ------------------------------------------------
	m = _make_predicted()
	_walk_frames(m, 1, 10, forward)
	m.on_input_batch_failed(5, 7)
	_check(m.pending_count() == 7, "seqs 5-7 of a failed batch are dropped from pending (%d left)" % m.pending_count())
	_check(not m._history.has(5) and not m._history.has(7) and m._history.has(8),
		"and from history, so nothing is ever compared against them")
	_free_predicted(m)

	# --- (e) determinism ----------------------------------------------------------------
	var a := _make_predicted(56)
	var b := _make_predicted(57)
	_walk_frames(a, 1, 30, Vector2(0.6, -0.8))
	_walk_frames(b, 1, 30, Vector2(0.6, -0.8))
	var off := Vector3(0.05, 0.0, -0.03)
	_ack(a, 12, a._history[12].pos + off)
	_ack(b, 12, b._history[12].pos + off)
	_check(a.get_predicted_state().pos == b.get_predicted_state().pos,
		"replaying the same pending inputs from the same server state is bit-identical")
	_free_predicted(a)
	_free_predicted(b)

	# --- (f) an OVERRIDE (new epoch, no teleport): replay, glide, and it settles -------
	m = _make_predicted()
	counts = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	frames = _walk_frames(m, 1, 20, forward)
	var pred_before: Vector3 = m.get_predicted_state().pos
	_ack(m, 10, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_check(counts.size() == 1 and absf(counts[0] - 0.4) < 1e-3,
		"an override is one correction the size of the server's change (%s)" % str(counts))
	_check(m.get_epoch() == 1, "we adopt the server's new correction epoch")
	_check((m.get_predicted_state().pos - pred_before).is_equal_approx(Vector3(0.4, 0.0, 0.0)),
		"our unacknowledged inputs are REPLAYED from the corrected state, so the correction costs no movement")
	var next: Array[InputFrame] = _walk_frames(m, 21, 5, forward)
	_check(next[0].epoch == 1, "frames predicted after the override carry the new epoch")
	# The server consumed seqs 11..20 (old epoch) without moving: those rows must not be read as errors.
	_ack(m, 18, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_ack(m, 20, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_check(counts.size() == 1, "rows acknowledging old-epoch frames are not corrections (%d)" % counts.size())
	_ack(m, 25, next[4].client_pos, 1)
	_check(counts.size() == 1, "the first new-epoch ack matches exactly: ONE correction settled it")
	_free_predicted(m)

	# --- (g) a TELEPORT override: snap, announce, drop the old inputs -------------------
	m = _make_predicted()
	var tps: Array[int] = []
	var tcb := func(eid: int) -> void: tps.append(eid)
	bus.entity_teleported.connect(tcb)
	_walk_frames(m, 1, 20, forward)
	_ack(m, 10, Vector3(50.0, 0.0, 50.0), 1, true)
	_check(m.get_predicted_state().pos == Vector3(50.0, 0.0, 50.0), "a teleport puts us exactly at the target")
	_check(m.get_reconcile_stats()["snaps"] == 1 and m.get_visual_offset() == Vector3.ZERO,
		"a teleport snaps; it never glides across the map")
	_check(tps == [55], "the teleport is announced once on the bus (%s)" % str(tps))
	_check(m.pending_count() == 0, "inputs from the old place are not replayed at the new one")
	bus.entity_teleported.disconnect(tcb)
	_free_predicted(m)

	# --- (h) the LOCAL entity's events come from the prediction, at once -----------------
	# Detected from rows, a jump sound played a round trip after the jump: 200 ms at 200 ms.
	m = _make_predicted()
	var evs: Array[String] = []
	m.event_predicted.connect(func(k: StringName, id: int) -> void: evs.append("%s@%d" % [k, id]))
	var jump_count: Array[int] = [0]
	m.jumped.connect(func() -> void: jump_count[0] += 1)
	_walk_frames(m, 1, 5, Vector2.ZERO)
	var jf := InputFrame.new()
	jf.seq = 6
	jf.jump = true
	m.push_input(jf)
	_check(evs == ["jumped@6"] and jump_count[0] == 1,
		"a jump is announced on the very frame it is predicted, identified by its seq (%s)" % str(evs))
	_check(jf.move_state == MovementState.Move.AIR, "and the frame reports AIR to the server")
	var sq: int = 7
	while not m.get_predicted_state().grounded and sq < 300:
		var idle := InputFrame.new()
		idle.seq = sq
		m.push_input(idle)
		sq += 1
	_check(evs.size() == 2 and evs[1].begins_with("landed@"), "the landing is announced when the prediction lands (%s)" % str(evs))
	_ack(m, sq - 1, m._history[sq - 1].pos)
	_check(jump_count[0] == 1 and evs.size() == 2, "acknowledging rows do not fire the events a second time")
	_free_predicted(m)

	# --- (i) a TELEPORT revokes what was predicted on the old path ------------------------
	m = _make_predicted()
	var revoked: Array[String] = []
	m.event_revoked.connect(func(k: StringName, id: int) -> void: revoked.append("%s@%d" % [k, id]))
	_walk_frames(m, 1, 3, Vector2.ZERO)
	var j2 := InputFrame.new()
	j2.seq = 4
	j2.jump = true
	m.push_input(j2)
	_walk_frames(m, 5, 6, Vector2.ZERO)
	_ack(m, 2, Vector3(20.0, 0.0, 20.0), 1, true)
	_check(revoked == ["jumped@4"], "a teleport revokes the jump predicted after the seq it acknowledges (%s)" % str(revoked))
	_free_predicted(m)

	# --- (j) a correction whose replay no longer jumps revokes the jump -------------------
	# The server puts us 2 m up at seq 3. Replaying from there, the jump at seq 6 is pressed in
	# mid-air, so it never happens: revoke it rather than leave an animation mid-jump.
	m = _make_predicted()
	revoked = []
	m.event_revoked.connect(func(k: StringName, id: int) -> void: revoked.append("%s@%d" % [k, id]))
	_walk_frames(m, 1, 5, Vector2.ZERO)
	var j3 := InputFrame.new()
	j3.seq = 6
	j3.jump = true
	m.push_input(j3)
	_walk_frames(m, 7, 6, Vector2.ZERO)
	var up := FakeMoveRow.new(m.entity_id, Vector3(0.0, 2.0, 0.0), 3_000_000)
	up.last_processed_seq = 3
	up.correction_epoch = 1
	up.grounded = false
	m.receive_row_event(_move_ev(up))
	m.apply_pending_rows()
	_check(revoked == ["jumped@6"], "a correction whose replay has no jump revokes the predicted one (%s)" % str(revoked))
	_check(not m.get_predicted_state().grounded, "and the replayed present is airborne, falling from the corrected height")
	_free_predicted(m)

	# --- (k) move_state through push_input ------------------------------------------------
	m = _make_predicted()
	var states: Array[int] = []
	m.move_state_changed.connect(func(_o: int, n: int) -> void: states.append(n))
	_walk_frames(m, 1, 3, Vector2.ZERO)
	var walk_f: Array[InputFrame] = _walk_frames(m, 4, 10, forward)
	var sprint_f := InputFrame.new()
	sprint_f.seq = 14
	sprint_f.move_dir = forward
	sprint_f.sprint = true
	m.push_input(sprint_f)
	# A plain key press RUNS; WALK is the slow modifier now (DECISIONS #100).
	_check(walk_f[-1].move_state == MovementState.Move.RUN and sprint_f.move_state == MovementState.Move.SPRINT,
		"frames report RUN then SPRINT to the server")
	_check(states == [MovementState.Move.RUN, MovementState.Move.SPRINT],
		"move_state_changed fires from the prediction, once per change (%s)" % str(states))
	_free_predicted(m)


# --- movement config: one source of truth, and the feel it promises ---------------------

## Frames (60 Hz) until `pred` holds, stepping the pure model from `s` with `input`.
func _frames_until(s: MovementState, input: InputFrame, cfg: MovementConfig, pred: Callable,
		limit: int = 120) -> Array:
	var dist: float = 0.0
	for n: int in range(1, limit + 1):
		var next: MovementState = MovementModel.simulate(s, input, cfg, 1.0 / 60.0)
		dist += Vector2(next.pos.x - s.pos.x, next.pos.z - s.pos.z).length()
		s = next
		if bool(pred.call(s)):
			return [n, dist, s]
	return [-1, dist, s]


func _run_config_tests() -> void:
	print("== movement config ==")
	# The JSON is the single source (DECISIONS #81). The client read the hardcoded defaults and
	# the server read the JSON, so an edit to the JSON changed only the server. Now the client
	# reads the JSON too, and the defaults must still equal it so tests that construct
	# MovementConfig.new() measure the same game.
	var shared: MovementConfig = MovementConfig.shared()
	var defaults := MovementConfig.new()
	var drift: PackedStringArray = []
	for field: StringName in MovementConfig.FIELDS:
		if not is_equal_approx(float(shared.get(field)), float(defaults.get(field))):
			drift.append("%s json=%s default=%s" % [field, shared.get(field), defaults.get(field)])
	_check(drift.is_empty(), "MovementConfig defaults equal shared/movement_config.json (%s)"
		% (", ".join(drift) if not drift.is_empty() else "all fields"))

	# THE FEEL CONTRACT. "Movement is very glidy" is a tuning complaint; these numbers are what
	# fixed it, and a retune that brings the glide back fails here, not in a playtest months later.
	var sprinting := MovementState.new()
	sprinting.grounded = true
	sprinting.vel = Vector3(0.0, 0.0, -shared.sprint_speed)
	var back := InputFrame.new()
	back.move_dir = Vector2(0.0, 1.0)
	back.sprint = true
	var rev: Array = _frames_until(sprinting, back, shared, func(s: MovementState) -> bool:
		return s.vel.z >= 0.9 * shared.sprint_speed * shared.back_speed_mult)
	print("   sprint reversal to 90%% the other way: %d frames (%.0f ms)" % [rev[0], float(rev[0]) * 1000.0 / 60.0])
	_check(rev[0] > 0 and rev[0] <= 15, "reversing a sprint takes at most 0.25 s (%d frames)" % rev[0])

	var let_go := InputFrame.new()
	var stop: Array = _frames_until(sprinting, let_go, shared, func(s: MovementState) -> bool:
		return Vector2(s.vel.x, s.vel.z).length() < 0.05)
	print("   stop from a sprint: %d frames (%.0f ms), sliding %.2f m" % [stop[0], float(stop[0]) * 1000.0 / 60.0, stop[1]])
	_check(stop[0] > 0 and stop[0] <= 12, "letting go of a sprint stops within 0.2 s (%d frames)" % stop[0])
	_check(float(stop[1]) < 0.8, "and slides under 0.8 m (%.2f m)" % float(stop[1]))

	var rest := MovementState.new()
	rest.grounded = true
	var fwd := InputFrame.new()
	fwd.move_dir = Vector2(0.0, -1.0)
	var go: Array = _frames_until(rest, fwd, shared, func(s: MovementState) -> bool:
		return -s.vel.z >= 0.9 * shared.run_speed)
	_check(go[0] > 0 and go[0] <= 6, "reaching running speed takes at most 0.1 s (%d frames)" % go[0])


# --- SpaceTimeActionComponent (PHASE3_SPEC Task 12, PHASE4_SPEC §3) --------------------

class FakeAbilityDef extends RefCounted:
	var ability_id: int
	var cooldown_ms: int = 800
	var wind_up_ms: int = 150
	var range: float = 2.0
	var damage: float = 10.0
	func _init(id: int) -> void:
		ability_id = id

class FakeActionEvent extends RefCounted:
	var id: int
	var world_id: int = 0
	var actor_id: int
	var ability_id: int
	var target_id: int = 0
	var aim: Vector3 = Vector3.ZERO
	var outcome: int = 1
	var predicted_id: int = 0
	var server_ts: int = 0
	func _init(p_id: int, p_actor: int, p_ability: int, p_pid: int) -> void:
		id = p_id
		actor_id = p_actor
		ability_id = p_ability
		predicted_id = p_pid

class FakeAbilityState extends RefCounted:
	var id: int = 1
	var entity_id: int
	var ability_id: int
	var cooldown_until: int
	var charges: int = 0
	func _init(eid: int, ab: int, until: int) -> void:
		entity_id = eid
		ability_id = ab
		cooldown_until = until


## An action component on a fake local entity, with the clock, the catalogue and the reducer
## call all under the test's control. Abilities 0-9 exist; anything else does not.
func _make_action(now_ref: Array, requests: Array[ReducerRequest], local: bool = true) -> SpaceTimeActionComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 70
	owner_entity.is_local_authority = local
	get_tree().root.add_child(owner_entity)
	var a := SpaceTimeActionComponent.new()
	a._clock_override = func() -> int: return int(now_ref[0])
	a._def_override = func(id: int) -> RefCounted: return FakeAbilityDef.new(id) if id < 10 else null
	a._reducer_override = func(_ab: int, _tg: int, _aim: Vector3, _pid: int) -> ReducerRequest:
		var r := ReducerRequest.new()
		r.reducer_name = &"use_ability"
		requests.append(r)
		return r
	get_tree().root.add_child(a)
	var empty: Dictionary[StringName, RefCounted] = {}
	a.bind(owner_entity, empty)
	return a


func _action_ev(row: FakeActionEvent) -> RowEvent:
	return RowEvent.make(RowEvent.Kind.INSERTED, &"action_event", null, row)


func _run_action_tests() -> void:
	print("== SpaceTimeActionComponent ==")
	var reg: Node = _autoload("EntityRegistry")
	var bus: Node = _autoload("SignalBus")
	var now: Array = [1_000_000]
	var reqs: Array[ReducerRequest] = []
	var a: SpaceTimeActionComponent = _make_action(now, reqs)
	var log: Array[String] = []
	a.action_started.connect(func(ab: int, pid: int) -> void: log.append("start %d#%d" % [ab, pid]))
	a.action_resolved.connect(func(ab: int, pid: int, o: int, t: int) -> void: log.append("resolved %d#%d o%d t%d" % [ab, pid, o, t]))
	a.action_revoked.connect(func(ab: int, pid: int, why: String) -> void: log.append("revoked %d#%d %s" % [ab, pid, why]))
	a.action_observed.connect(func(act: int, ab: int, t: int, o: int) -> void: log.append("observed a%d %d t%d o%d" % [act, ab, t, o]))
	a.ability_ready.connect(func(ab: int) -> void: log.append("ready %d" % ab))
	var bus_log: Array[String] = []
	var bcb := func(act: int, ab: int, t: int, o: int) -> void: bus_log.append("%d %d %d %d" % [act, ab, t, o])
	bus.entity_action.connect(bcb)

	# (a) predicted start: announced at once, cooldown running, nothing announced twice.
	var pid: int = a.request_use(0, 9)
	_check(pid == 1 and log == ["start 0#1"], "an action starts THE MOMENT it is requested, with a predicted id (%s)" % str(log))
	_check(reqs.size() == 1 and a.is_on_cooldown(0), "the request is sent and the cooldown starts locally")
	_check(a.request_use(0, 9) == -1 and reqs.size() == 1,
		"a second use inside the cooldown is refused locally: nothing sent, nothing announced")
	_check(a.request_use(50) == -1 and reqs.size() == 1, "an unknown ability is refused locally")

	# (b) the server's event carries the predicted id back: resolved, exactly once.
	var hit := FakeActionEvent.new(500, 70, 0, 1)
	hit.target_id = 9
	hit.outcome = SpaceTimeActionComponent.Outcome.HIT
	reg.global_row_event.emit(_action_ev(hit))
	reg.global_row_event.emit(_action_ev(hit))   # a cache replay on reconnect
	_check(log.slice(1) == ["resolved 0#1 o0 t9"], "the matching action_event resolves it, once (%s)" % str(log))
	_check(bus_log == ["70 0 9 0"], "and the actor's component announces it on the bus, once (%s)" % str(bus_log))
	_check(a.pending_count() == 0, "nothing left waiting")

	# (c) a refusal from the server revokes it and hands the cooldown back.
	now[0] += 900_000
	a.tick()
	log.clear()
	var pid2: int = a.request_use(0, 9)
	reqs[1]._settle(ReducerRequest.Outcome.REJECTED, "use_ability: out of range")
	_check(log == ["start 0#%d" % pid2, "revoked 0#%d use_ability: out of range" % pid2],
		"a server refusal revokes the predicted action, with the server's reason (%s)" % str(log))
	_check(not a.is_on_cooldown(0), "and the cooldown is handed back: the use never happened")

	# (d) no answer at all: revoked once the wind-up plus the timeout has passed.
	log.clear()
	var pid3: int = a.request_use(1)
	now[0] += (150 + 1000) * 1000 - 1
	a.tick()
	# (Cooldowns legitimately end during this wait — ability 1's 800 ms, and ability 0's, handed
	# back by the revoke above — so ability_ready entries are expected here; look past them.)
	var not_ready := func(entries: Array[String]) -> Array[String]:
		var out: Array[String] = []
		for e: String in entries:
			if not e.begins_with("ready "):
				out.append(e)
		return out
	_check(not_ready.call(log) == ["start 1#%d" % pid3], "still waiting just inside the deadline (%s)" % str(log))
	now[0] += 2
	a.tick()
	var rest: Array[String] = not_ready.call(log)
	_check(rest.size() == 2 and rest[1].begins_with("revoked 1#%d" % pid3), "revoked when nothing arrives in time (%s)" % str(log))
	_check(log.has("ready 1") and log.has("ready 0"), "the cooldowns that ran out during the wait each announced ready")

	# (e) someone else's action that hits THIS entity: observed, and not announced by us.
	log.clear()
	bus_log.clear()
	var incoming := FakeActionEvent.new(501, 99, 0, 7)
	incoming.target_id = 70
	incoming.outcome = SpaceTimeActionComponent.Outcome.HIT
	reg.global_row_event.emit(_action_ev(incoming))
	_check(log == ["observed a99 0 t70 o0"], "a hit on this entity is reported for a hit reaction (%s)" % str(log))
	_check(bus_log.is_empty(), "the bus announcement is the ACTOR's component's job, not the target's")
	reg.global_row_event.emit(_action_ev(FakeActionEvent.new(502, 98, 0, 3)))
	_check(log.size() == 1, "an action involving neither actor nor target here is ignored")

	# (f) the server's cooldown is authoritative; (g) ability_ready fires once when it ends.
	log.clear()
	var until: int = ClockSync.server_usec() + 2_000_000
	a.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"ability_state", null, FakeAbilityState.new(70, 3, until)))
	_check(a.is_on_cooldown(3) and absf(a.cooldown_remaining_sec(3) - 2.0) < 0.05,
		"an ability_state row sets the cooldown from the server's clock (%.3f s)" % a.cooldown_remaining_sec(3))
	now[0] += 2_100_000
	a.tick()
	a.tick()
	_check(log.count("ready 3") == 1, "ability_ready fires once when a cooldown runs out (%s)" % str(log))
	bus.entity_action.disconnect(bcb)
	a.entity.queue_free()
	a.queue_free()

	# (h) a REMOTE entity's own actions are observed, never "resolved": its client predicted them,
	# this one did not.
	var rreqs: Array[ReducerRequest] = []
	var remote: SpaceTimeActionComponent = _make_action(now, rreqs, false)
	var rlog: Array[String] = []
	remote.action_resolved.connect(func(_ab: int, _p: int, _o: int, _t: int) -> void: rlog.append("resolved"))
	remote.action_observed.connect(func(_act: int, _ab: int, _t: int, _o: int) -> void: rlog.append("observed"))
	reg.global_row_event.emit(_action_ev(FakeActionEvent.new(600, 70, 0, 1)))
	_check(rlog == ["observed"], "a remote player's action is observed (for its animation), not resolved (%s)" % str(rlog))
	remote.entity.queue_free()
	remote.queue_free()

# --- SessionComponent (Phase 3 Task 8) --------------------------------------------------

func _run_session_tests() -> void:
	print("== SessionComponent ==")
	var bus: Node = _autoload("SignalBus")
	var reg: Node = _autoload("EntityRegistry")
	if bus == null or reg == null:
		_check(false, "autoloads present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 31
	get_tree().root.add_child(owner_entity)
	var sc := SessionComponent.new()
	get_tree().root.add_child(sc)

	var phases: Array[String] = []
	var scores: Array[String] = []
	var joins: Array[int] = []
	sc.phase_changed.connect(func(o: int, n: int, ends: int) -> void:
		phases.append("%d->%d@%d" % [o, n, ends]))
	sc.score_changed.connect(func(s: int, c: int) -> void: scores.append("%d/%d" % [s, c]))
	sc.joined_session.connect(func(sid: int) -> void: joins.append(sid))

	var bus_phases: Array[String] = []
	var bus_scores: Array[String] = []
	var pcb := func(sid: int, o: int, n: int, _e: int) -> void:
		bus_phases.append("%d:%d->%d" % [sid, o, n])
	var scb := func(eid: int, s: int, c: int) -> void:
		bus_scores.append("%d:%d/%d" % [eid, s, c])
	bus.session_phase_changed.connect(pcb)
	bus.session_score_changed.connect(scb)

	# --- bind with a membership row ---------------------------------------------------
	var initial: Dictionary[StringName, RefCounted] = {&"session_member": FakeMemberRow.new(31, 7)}
	sc.bind(owner_entity, initial)
	_check(sc.get_session_id() == 7, "session_id read from the membership row")
	_check(joins == [7], "joined_session emitted once")
	_check(sc.is_in_session(), "is_in_session true once a membership row exists")

	# --- the session row arrives on the GLOBAL stream, not through the entity ---------
	# session has no entity_id, so this is the path it really takes.
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.INSERTED, &"session", null, FakeSessionRow.new(7, 0, 5_000_000)))
	_check(sc.get_phase() == 0, "phase picked up from the global session row")
	_check(phases.size() == 1 and phases[0] == "0->0@5000000" or phases.size() == 1,
		"phase_changed emitted once on first resolve (got %s)" % str(phases))
	_check(bus_phases.size() == 1, "bus session_phase_changed emitted once")
	_check(sc.get_seed() == 12345, "seed carried from the session row")

	# --- a session row for a DIFFERENT session must be ignored -------------------------
	var before: int = phases.size()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(999, 2, 9_000_000)))
	_check(phases.size() == before, "a row for another session is ignored")
	_check(sc.get_phase() == 0, "phase unchanged by another session's row")

	# --- LOBBY -> PLAYING ---------------------------------------------------------------
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	_check(sc.get_phase() == SessionComponent.Phase.PLAYING, "phase advanced to PLAYING")
	_check(phases == ["0->1@8000000"], "phase_changed carries old, new and ends_at")
	_check(bus_phases == ["7:0->1"], "bus event leads with session_id")

	# --- ANOTHER PLAYER IN THE SAME SESSION, in view -------------------------------------
	# Their component tracks the session too (a scoreboard needs every member's), but the bus
	# is this client's UI: one transition is one event, however many players are on screen.
	var remote_owner := FakeOwnerEntity.new()
	remote_owner.entity_id = 32
	remote_owner.is_local_authority = false
	get_tree().root.add_child(remote_owner)
	var other := SessionComponent.new()
	get_tree().root.add_child(other)
	var other_initial: Dictionary[StringName, RefCounted] = {
		&"session_member": FakeMemberRow.new(32, 7)}
	other.bind(remote_owner, other_initial)
	# (No row cache here, so it learns the phase from the next session row, not at bind.)
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 2, 9_000_000)))
	_check(sc.get_phase() == 2 and other.get_phase() == 2, "both members see RESULTS")
	_check(bus_phases == ["7:1->2"],
		"and the bus hears the transition ONCE, not once per member in view (%s)" % str(bus_phases))
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	other.queue_free()
	remote_owner.queue_free()

	# --- a repeat of the same phase must not re-fire -------------------------------------
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	_check(phases.is_empty(), "re-sending the same phase emits nothing")
	_check(bus_phases.is_empty(), "no duplicate bus event for an unchanged phase")

	# --- score changes ------------------------------------------------------------------
	scores.clear()
	bus_scores.clear()
	var scored := FakeMemberRow.new(31, 7)
	scored.score = 100
	scored.coins = 10
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"session_member",
		FakeMemberRow.new(31, 7), scored))
	_check(sc.get_score() == 100 and sc.get_coins() == 10, "score and coins read back")
	_check(scores == ["100/10"], "score_changed emitted once")
	_check(bus_scores == ["31:100/10"], "bus session_score_changed leads with entity_id")

	# An identical membership row must not re-announce the same score.
	scores.clear()
	var same := FakeMemberRow.new(31, 7)
	same.score = 100
	same.coins = 10
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"session_member", scored, same))
	_check(scores.is_empty(), "an unchanged score emits nothing")

	# --- seconds_remaining is derived from the server clock -------------------------------
	_check(sc.seconds_remaining() != 0.0, "seconds_remaining derives from phase_ends_at")

	# --- rebind must not double-subscribe (DECISIONS #17) ---------------------------------
	# rebind() runs bind() again; an unguarded connect left this component subscribed twice
	# and every phase change was reported to the UI twice after a reconnect.
	phases.clear()
	bus_phases.clear()
	var rebind_rows: Dictionary[StringName, RefCounted] = {&"session_member": FakeMemberRow.new(31, 7)}
	sc.rebind(rebind_rows)
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 2, 3_000_000)))
	_check(phases.size() == 1, "after rebind a phase change is still reported ONCE (got %d)"
		% phases.size())
	_check(bus_phases.size() == 1, "after rebind the bus event fires ONCE (got %d)"
		% bus_phases.size())

	# --- losing the membership row leaves the session --------------------------------------
	var lefts: Array[int] = []
	sc.left_session.connect(func() -> void: lefts.append(1))
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"session_member",
		FakeMemberRow.new(31, 7), null))
	_check(lefts.size() == 1, "left_session emitted when the membership row goes away")
	_check(not sc.is_in_session(), "is_in_session false after leaving")

	bus.session_phase_changed.disconnect(pcb)
	bus.session_score_changed.disconnect(scb)
	sc.queue_free()
	owner_entity.queue_free()


# --- SpaceTimeInventoryComponent (Phase 3 Task 9) ---------------------------------------

## Mirrors `inventory_item`. NOTE the column is `owner_entity_id`, not `entity_id` — that is
## precisely what RowEvent's fallback exists for.
class FakeItemRow extends RefCounted:
	var id: int
	var owner_entity_id: int
	var item_def_id: int
	var qty: int
	var slot: int = -1
	var instance_data: String = ""
	func _init(p_id: int, owner: int, def_id: int, p_qty: int, p_slot: int = -1) -> void:
		id = p_id
		owner_entity_id = owner
		item_def_id = def_id
		qty = p_qty
		slot = p_slot

static func _item_ev(kind: RowEvent.Kind, old: FakeItemRow, new: FakeItemRow) -> RowEvent:
	return RowEvent.make(kind, &"inventory_item", old, new)

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


# --- InteractionComponent (Phase 3 Task 10) ---------------------------------------------

func _run_interaction_tests() -> void:
	print("== InteractionComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 61
	owner_entity.is_local_authority = true
	get_tree().root.add_child(owner_entity)
	var ic := InteractionComponent.new()
	get_tree().root.add_child(ic)
	var empty: Dictionary[StringName, RefCounted] = {}
	ic.bind(owner_entity, empty)

	var local_targets: Array[int] = []
	ic.target_changed.connect(func(id: int) -> void: local_targets.append(id))
	var bus_targets: Array[int] = []
	var tcb := func(id: int) -> void: bus_targets.append(id)
	bus.interact_target_changed.connect(tcb)

	_check(ic.get_target() == InteractionComponent.NO_TARGET, "starts with no target")
	_check(not ic.has_target(), "has_target false initially")
	_check(ic.request_interact() == null, "request_interact with no target does nothing")

	# --- the signal fires on CHANGE, not per frame -------------------------------------
	# A crosshair held on one thing for 600 frames must announce once, or the prompt UI
	# rebuilds every frame.
	ic._set_target(77)
	ic._set_target(77)
	ic._set_target(77)
	_check(local_targets == [77], "holding a target announces once (got %s)" % str(local_targets))
	_check(bus_targets == [77], "bus mirrors once")
	_check(ic.has_target() and ic.get_target() == 77, "target readable")

	ic._set_target(88)
	_check(local_targets == [77, 88], "switching targets announces the new one")
	ic._set_target(InteractionComponent.NO_TARGET)
	_check(local_targets == [77, 88, -1], "looking away announces -1 so the prompt clears")
	ic._set_target(InteractionComponent.NO_TARGET)
	_check(local_targets.size() == 3, "looking at nothing twice announces once")

	# --- what counts as a target --------------------------------------------------------
	_check(ic._target_id_of(null) == InteractionComponent.NO_TARGET, "nothing hit is no target")
	var plain := Node3D.new()
	get_tree().root.add_child(plain)
	_check(ic._target_id_of(plain) == InteractionComponent.NO_TARGET,
		"an ordinary node is not interactable")

	# A prop standing in for an entity: in the group AND carrying the meta.
	var prop := StaticBody3D.new()
	prop.add_to_group(InteractionComponent.GROUP_INTERACTABLE)
	prop.set_meta(&"entity_id", 404)
	get_tree().root.add_child(prop)
	_check(ic._target_id_of(prop) == 404, "an interactable prop resolves to its entity_id meta")

	# In the group but no meta: not a target, rather than a crash or a bogus id.
	var half := StaticBody3D.new()
	half.add_to_group(InteractionComponent.GROUP_INTERACTABLE)
	get_tree().root.add_child(half)
	_check(ic._target_id_of(half) == InteractionComponent.NO_TARGET,
		"group membership without the meta is not a target")

	# --- a remote entity does not scan ----------------------------------------------------
	var remote_owner := FakeOwnerEntity.new()
	remote_owner.entity_id = 62
	remote_owner.is_local_authority = false
	get_tree().root.add_child(remote_owner)
	var remote_ic := InteractionComponent.new()
	get_tree().root.add_child(remote_ic)
	remote_ic.bind(remote_owner, empty)
	_check(not remote_ic.is_physics_processing(), "a remote entity does not raycast")

	# --- the client range must not exceed the server's -------------------------------------
	# A larger client range prompts for things the server will refuse, which reads as a bug.
	_check(is_equal_approx(ic.range_m(), Rules.interact_range()) and Rules.interact_range() > 0.0,
		"left unset, the prompt reaches exactly as far as the server's check, from shared/rules.json (%s m)"
			% ic.range_m())
	ic.interaction_range = 1.5
	_check(is_equal_approx(ic.range_m(), 1.5), "and a component given its own range uses that")
	ic.interaction_range = 0.0

	bus.interact_target_changed.disconnect(tcb)
	plain.queue_free()
	prop.queue_free()
	half.queue_free()
	remote_ic.queue_free()
	remote_owner.queue_free()
	ic.queue_free()
	owner_entity.queue_free()
