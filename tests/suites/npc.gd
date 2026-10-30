extends "res://tests/suite_base.gd"
## The `npc` suite (tests/test_runner.gd runs it; `-- --only=npc` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_npc_tests()
	_run_tiers()



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


## THE BRAINS' COST (DECISIONS #287): one world view a think period, shared (not one a physics tick: at 300
## players that rebuild was the brains' whole cost), and NPC TIERS: dormant with no player near, awake when
## one comes, between the two as it was, and never with the flag off.
func _run_tiers() -> void:
	print("== NPC brains: one view a think period, and tiers ==")
	NpcWorldView.invalidate()
	var t: Array[int] = [5000]
	NpcWorldView.clock_msec = func() -> int: return t[0]
	var first: NpcWorldView = NpcWorldView.current()
	t[0] += NpcWorldView.SHARED_MS - 1
	_check(NpcWorldView.current() == first, "within a think period: the same view, shared")
	t[0] += 1
	var second: NpcWorldView = NpcWorldView.current()
	_check(second != first, "a think period later: built again")
	t[0] -= 10_000
	_check(NpcWorldView.current() != second, "a clock that went back: built again, never stuck")
	NpcWorldView.clock_msec = Callable()
	NpcWorldView.invalidate()

	var view := NpcWorldView.new()
	var near := MovementState.new()
	near.pos = Vector3(30.0, 0.0, 40.0)
	var npc := MovementState.new()
	view.states = {1: npc, 2: near}
	view.players = {2: true}
	_check(is_equal_approx(view.nearest_player_m(Vector3.ZERO), 50.0), "the nearest player: 50 m")
	view.players = {}
	_check(view.nearest_player_m(Vector3.ZERO) == INF, "no player: none near (INF)")

	var b := NpcBrainComponent.new()
	var changes: Array[bool] = []
	b.tier_changed.connect(func(d: bool) -> void: changes.append(d))
	b.retier(10.0, 500.0, true, 200.0, 400.0, 30.0)
	b.retier(10.0, 500.0, true, 200.0, 400.0, 30.0)
	_check(not b.dormant and is_equal_approx(b.alone_s, 20.0), "alone 20 s of 30: still awake")
	b.retier(10.0, 500.0, true, 200.0, 400.0, 30.0)
	_check(b.dormant and changes == [true], "alone 30 s: dormant")
	b.retier(10.0, 300.0, true, 200.0, 400.0, 30.0)
	_check(b.dormant, "a player at 300 m (between wake and sleep): still dormant")
	b.retier(1.0, 150.0, true, 200.0, 400.0, 30.0)
	_check(not b.dormant and changes == [true, false] and b.alone_s == 0.0, "a player within 200 m: awake")
	b.retier(25.0, 500.0, true, 200.0, 400.0, 30.0)
	b.retier(10.0, 300.0, true, 200.0, 400.0, 30.0)
	b.retier(25.0, 500.0, true, 200.0, 400.0, 30.0)
	_check(not b.dormant, "a player passing within 400 m starts the count again")
	b.retier(10.0, 500.0, true, 200.0, 400.0, 30.0)
	_check(b.dormant, "and 35 s alone after that: dormant")
	b.retier(100.0, INF, false, 200.0, 400.0, 30.0)
	_check(not b.dormant, "the flag off: awake, whoever is near")
	b.retier(100.0, INF, false, 200.0, 400.0, 30.0)
	_check(not b.dormant, "and it stays awake")
	b.free()
