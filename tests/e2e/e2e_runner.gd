extends Node
## END-TO-END: a real Godot client against a real published module. No fakes anywhere.
##
## The unit suites construct rows by hand and the server suite drives reducers from the CLI.
## Neither proves the two halves agree. This one runs the whole chain —
##   reducer call -> BSATN encode -> module -> row write -> subscription -> BSATN decode ->
##   SpaceTimeSync -> EntityRegistry -> SpaceTimeEntity -> component -> SignalBus
## — and asserts on what the client ends up believing.
##
## It is the only layer that would have caught the `Vec3`/`Vector3` binding break (DECISIONS
## #40): every unit test passed while no client could read or send a position, because the
## fakes were hand-written Godot types and the real generated rows were not.
##
## Driven by tests/e2e_test.sh, which publishes a fresh module first. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 90.0
const STEP_TIMEOUT_SEC: float = 25.0

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false


func _ready() -> void:
	# Boot (a sibling in this scene) connects during its own _ready; start after the tree settles.
	_run.call_deferred()


func _run() -> void:
	var watchdog: SceneTreeTimer = get_tree().create_timer(OVERALL_TIMEOUT_SEC)
	watchdog.timeout.connect(_on_watchdog)

	await _step_connect()
	var eid: int = await _step_local_entity()
	if eid < 0:
		_finish()
		return
	var entity: Node = await _step_spawned(eid)
	if entity == null:
		_finish()
		return
	if "--restart-check" in OS.get_cmdline_user_args():
		await _step_restarted_inputs(entity)
		_finish()
		return
	_step_components_from_real_rows(entity)
	await _step_teleport_round_trip(entity, eid)
	await _step_input_round_trip(entity)
	await _step_action_round_trip(entity)
	_finish()


# --- steps ---------------------------------------------------------------------------

func _step_connect() -> void:
	print("== connect ==")
	var ok: bool = await _until(func() -> bool:
		return SpaceTimeSync.is_connected_to_server(), "CONNECTED")
	_check(ok, "client reaches CONNECTED against the live server")
	var ready_ok: bool = await _until(func() -> bool:
		return SpaceTimeSync.is_world_ready, "world_ready")
	_check(ready_ok, "initial subscription applies (world_ready)")


func _step_local_entity() -> int:
	print("== identity ==")
	var ok: bool = await _until(func() -> bool:
		return EntityRegistry.local_entity_id >= 0, "local entity assignment")
	_check(ok, "server assigned this client an entity")
	if not ok:
		return -1
	var eid: int = EntityRegistry.local_entity_id
	# The id must agree with the adapter's own lookup through the SDK cache.
	_check(SpaceTimeSync.get_local_entity_id() == eid,
		"EntityRegistry and the SDK cache agree on the local entity (%d vs %d)"
			% [eid, SpaceTimeSync.get_local_entity_id()])
	print("   local entity: ", eid)
	return eid


func _step_spawned(eid: int) -> Node:
	print("== spawn ==")
	var ok: bool = await _until(func() -> bool:
		return EntitySpawner.get_entity_node(eid) != null, "spawner to instantiate our entity")
	_check(ok, "EntitySpawner spawned the local entity from a real `entity` row")
	if not ok:
		return null
	var entity: Node = EntitySpawner.get_entity_node(eid)
	# Binding waits for every required table, so give the rows time to arrive rather than
	# racing them. If a table is genuinely missing this still fails, just via the timeout.
	var bound: bool = await _until(func() -> bool: return entity.is_bound(), "entity bind")
	_check(bound, "the spawned entity bound from real rows")
	_check(entity.is_local_authority, "the local entity is flagged as local authority")
	_check(not entity.has_node(^"Nameplate"), "the local entity dropped its nameplate")
	_check(entity.has_node(^"CameraRig"), "the local entity kept its camera rig")
	return entity


## The real point of this suite: components fed by GENERATED rows, not hand-written fakes.
func _step_components_from_real_rows(entity: Node) -> void:
	print("== components from real rows ==")
	var health: SpaceTimeHealthComponent = null
	var movement: SpaceTimeMovementComponent = null
	var session: SessionComponent = null
	for c: SpaceTimeComponent in entity.get_components():
		_check(c.is_bound(), "%s bound" % c.get_class())
		if c is SpaceTimeHealthComponent:
			health = c
		elif c is SpaceTimeMovementComponent:
			movement = c
		elif c is SessionComponent:
			session = c

	_check(health != null and health.has_state(), "health component has real server state")
	if health != null:
		_check(health.get_max() == 100.0,
			"health max came from the server row (got %s)" % health.get_max())

	# MovementState.from_row over a generated row — the exact call that was broken when the
	# module's wire struct was named Vec3 instead of Vector3.
	_check(movement != null and movement.get_authoritative_state() != null,
		"movement decoded a real movement_state row into a MovementState")
	if movement != null and movement.get_authoritative_state() != null:
		var pos: Vector3 = movement.get_authoritative_state().pos
		_check(pos is Vector3, "decoded position is a native Godot Vector3")
		print("   server position: ", pos)

	# THE VIEW. A client with no current camera renders nothing at all, and because the HUD is a
	# CanvasLayer it keeps drawing over the void — so the failure looks like a grey screen with a
	# working UI and reports no error. Asserted here, against a real entity spawned by the real
	# spawner from a real server row, because that is the path that decides it.
	var cam: Camera3D = get_viewport().get_camera_3d()
	_check(cam != null, "a camera is current, so the client is actually rendering the world")
	_check(cam != null and entity.is_ancestor_of(cam),
		"the current camera belongs to OUR entity, not to somebody else's")
	if cam != null:
		print("   looking through ", entity.get_path_to(cam))

	_check(session != null and session.is_in_session(),
		"session component resolved a real session_member row")
	if session != null:
		_check(session.get_phase() >= 0,
			"session phase resolved from the global `session` row (got %d)" % session.get_phase())
		print("   session ", session.get_session_id(), " phase ", session.get_phase())


## Client calls a reducer; the server writes a row; the client must SEE it.
func _step_teleport_round_trip(entity: Node, eid: int) -> void:
	print("== reducer round trip (teleport) ==")
	var movement: SpaceTimeMovementComponent = _find_movement(entity)
	if movement == null:
		_check(false, "movement component present for the teleport step")
		return

	var teleported: Array[int] = []
	var cb := func(e: int) -> void: teleported.append(e)
	SignalBus.entity_teleported.connect(cb)

	# Pick a target the entity is NOT already standing on. `e2e_test.sh` always republishes, but
	# running this scene straight from the editor does not, and against a reused identity a fixed
	# destination is a no-op the second time: the row never changes, no update is delivered, and
	# the assertion fails for a reason that has nothing to do with the code under test.
	var here: MovementState = movement.get_authoritative_state()
	var away_from: float = here.pos.x if here != null else 0.0
	var target := Vector3(7.0 if absf(away_from - 7.0) > 0.5 else -7.0, 1.0, -3.0)
	var req: ReducerRequest = SpaceTimeSync.call_reducer(
		&"teleport", [target], ["vector3[f32,f32,f32]"])
	_check(req != null, "teleport reducer call was dispatched")

	# Assert on X/Z only. `teleport` clears `grounded`, so the module's gravity starts pulling
	# Y down on the very next tick — asserting the exact point raced that and flaked. The
	# horizontal position is what proves the value round-tripped; Y settling to the ground is
	# the server behaving correctly, not a failure.
	var ok: bool = await _until(func() -> bool:
		var s: MovementState = movement.get_authoritative_state()
		if s == null:
			return false
		return absf(s.pos.x - target.x) < 0.01 and absf(s.pos.z - target.z) < 0.01,
		"the teleported position")
	_check(ok, "the position this client SENT came back as authoritative state")
	var settled: MovementState = movement.get_authoritative_state()
	_check(settled != null and settled.pos.y <= target.y + 0.01,
		"gravity acts on the teleported entity (y %s did not rise above the drop point)"
			% (settled.pos.y if settled != null else "n/a"))
	_check(teleported.has(eid),
		"entity_teleported reached SignalBus for our entity (got %s)" % str(teleported))
	SignalBus.entity_teleported.disconnect(cb)


## The input path, which is where BSATN encoding of a struct array lives. A silent failure
## here is what a client would experience as "my character does not move".
func _step_input_round_trip(entity: Node) -> void:
	print("== input round trip (submit_input) ==")
	var movement: SpaceTimeMovementComponent = _find_movement(entity)
	if movement == null:
		_check(false, "movement component present for the input step")
		return

	var before: int = movement.get_last_processed_seq()
	var frames: Array[InputFrame] = []
	for i: int in range(3):
		var f := InputFrame.new()
		f.seq = before + 1 + i
		f.client_tick = i
		f.move_dir = Vector2(0.0, -1.0)
		f.look_yaw = 0.25
		f.look_pitch = -0.125     # the field added in Task 1; proves the struct layout matches
		f.jump = false
		f.sprint = false
		var auth: MovementState = movement.get_authoritative_state()
		f.client_pos = auth.pos if auth != null else Vector3.ZERO
		frames.append(f)

	var req: ReducerRequest = SpaceTimeSync.submit_input(frames)
	_check(req != null, "submit_input was dispatched through the generated wrapper")

	var target_seq: int = before + 3
	var ok: bool = await _until(func() -> bool:
		return movement.get_last_processed_seq() >= target_seq, "the server to ack our inputs")
	_check(ok, "server processed our inputs: last_processed_seq reached %d (was %d, now %d)"
		% [target_seq, before, movement.get_last_processed_seq()])


## A RESTARTED CLIENT (DECISIONS #149), run second by e2e_test.sh with the SAME identity: the
## server still holds the first run's input count for this entity, and this process's own input
## component — the real sampling path, nothing sent by hand — has to be heard at once. Before the
## fix its frames counted from 1 and were dropped until the count passed the first run's: the
## player stood still on the server for as long as the first run had lasted, then snapped.
const RESTART_HEARD_WITHIN_SEC: float = 2.0

func _step_restarted_inputs(entity: Node) -> void:
	print("== a restarted client's own inputs ==")
	var movement: SpaceTimeMovementComponent = _find_movement(entity)
	var input: LocalInputComponent = null
	for c: SpaceTimeComponent in (entity as SpaceTimeEntity).get_components():
		if c is LocalInputComponent:
			input = c
	if movement == null or input == null:
		_check(false, "movement and input components present for the restart step")
		return
	while input.first_seq() == 0:
		await get_tree().process_frame
	# A process counting for itself starts at 1. This one is the first run's player back again, and
	# the server holds that run's count, so its first frame has to come after it.
	_check(input.first_seq() > 1,
		"this run's first frame carries on from the first run's count (seq %d), not from 1 into a drop"
			% input.first_seq())
	var until: int = Time.get_ticks_msec() + int(RESTART_HEARD_WITHIN_SEC * 1000.0)
	while movement.get_last_processed_seq() < input.first_seq() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_check(movement.get_last_processed_seq() >= input.first_seq(),
		"and the server hears it within %.0f s: acked up to %d" % [RESTART_HEARD_WITHIN_SEC, movement.get_last_processed_seq()])


# --- helpers -------------------------------------------------------------------------


## PHASE3_SPEC Task 12 / PHASE4_SPEC §3 through the real wire: a predicted start, then the
## module's action_event (BSATN-decoded, predicted id echoed) confirms it; a refusal revokes it.
func _step_action_round_trip(entity: Node) -> void:
	print("== action round trip (use_ability) ==")
	var action: SpaceTimeActionComponent = null
	for c: SpaceTimeComponent in entity.get_components():
		if c is SpaceTimeActionComponent:
			action = c
	_check(action != null, "the player scene carries an action component")
	if action == null:
		return
	var started: Array[int] = []
	var resolved: Array[Array] = []
	var revoked: Array[String] = []
	action.action_started.connect(func(_ab: int, pid: int) -> void: started.append(pid))
	action.action_resolved.connect(func(ab: int, pid: int, o: int, t: int) -> void: resolved.append([ab, pid, o, t]))
	action.action_revoked.connect(func(_ab: int, _pid: int, why: String) -> void: revoked.append(why))

	var ok_def: bool = await _until(func() -> bool: return SpaceTimeSync.get_row(&"ability_def", 0) != null,
		"ability_def row 0 in the cache")
	_check(ok_def, "the built-in ability 0 reached the client (ability_def is subscribed)")
	var pid: int = action.request_use(0)
	_check(pid > 0 and started == [pid], "the action is announced at once, before any server answer")
	var answered: bool = await _until(func() -> bool: return not resolved.is_empty() or not revoked.is_empty(),
		"the module's action_event")
	_check(answered and resolved.size() == 1 and int(resolved[0][1]) == pid,
		"the module's event resolves it, matched by the echoed predicted id (%s %s)" % [str(resolved), str(revoked)])
	if not resolved.is_empty():
		_check(int(resolved[0][2]) == SpaceTimeActionComponent.Outcome.MISS,
			"an untargeted use resolves as a MISS (outcome %d)" % int(resolved[0][2]))
	_check(action.request_use(0) == -1, "a second use inside the cooldown is refused locally")

	await get_tree().create_timer(1.0).timeout
	var pid2: int = action.request_use(0, 987654321)
	var refused: bool = await _until(func() -> bool: return not revoked.is_empty(), "the refusal")
	_check(refused and revoked[0].contains("no such target"),
		"a server refusal revokes the predicted action with the module's reason (%s)" % str(revoked))
	_check(not action.is_on_cooldown(0), "and hands the cooldown back")

func _find_movement(entity: Node) -> SpaceTimeMovementComponent:
	for c: SpaceTimeComponent in entity.get_components():
		if c is SpaceTimeMovementComponent:
			return c
	return null


## Poll a predicate each frame until it holds or the step times out. Everything here is
## asynchronous over a real network, so nothing may block and nothing may wait forever.
func _until(pred: Callable, what: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	printerr("  TIMEOUT after %.0fs waiting for %s" % [STEP_TIMEOUT_SEC, what])
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: e2e exceeded %.0fs overall" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n%d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
