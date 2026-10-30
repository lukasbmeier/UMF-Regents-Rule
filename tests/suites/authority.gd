extends "res://tests/suite_base.gd"
## The `authority` suite (tests/test_runner.gd runs it; `-- --only=authority` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_authority_tests()



# --- RowEvent -----------------------------------------------------------------------

## AuthoritySync with its flushes counted, so the server-tick cadence can be driven by hand
## rather than measured against however fast this machine happens to run.
class CountingSync extends AuthoritySync:
	var calls: int = 0

	func flush() -> Array[Dictionary]:
		calls += 1
		return super()


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
	# A brain's still frames for a body at rest (template 1.5.3): nothing stepped, nothing written.
	for i: int in range(40):
		await get_tree().physics_frame
	mv.take_authority_write()
	var rest: Vector3 = mv.get_authority_state().pos
	for i: int in range(10):
		mv.push_authority_input(_frame(0, Vector2.ZERO))
		await get_tree().physics_frame
	_check(mv.take_authority_write().is_empty() and mv.get_authority_state().pos == rest,
		"a body at rest given still frames (a skeleton idle in camp) is not stepped and owes no write")
	for i: int in range(10):
		mv.push_authority_input(_frame(0, Vector2(0.0, -1.0)))
		await get_tree().physics_frame
	_check(not mv.take_authority_write().is_empty() and mv.get_authority_state().pos.z < rest.z - 0.1,
		"and a frame that walks still moves it")

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
