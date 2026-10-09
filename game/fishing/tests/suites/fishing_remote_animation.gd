extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fishing_remote_animation` suite (`-- --only=fishing_remote_animation` runs it alone), run because shared/game.json
## lists fishing. The fishing half of tests/suites/remote_animation.gd (the original, run on the angler and the lakeside). Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	await _run_remote_animation_tests()



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
