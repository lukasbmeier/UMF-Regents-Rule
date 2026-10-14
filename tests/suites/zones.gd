extends "res://tests/suite_base.gd"
## The `zones` suite (DECISIONS #231): a slow place in a level (`LevelSpeedZone`: a hedge's hole a hen
## crawls through, mud).
##   - where a body's feet are, the slowest zone there says its pace; nowhere, its own
##   - a config at a pace: walk, run, sprint and dash scaled
##   - a body stepped through one goes at that pace, as its owner predicts it and as anyone driving it
##     would (the same step), and at its own again out of it


func run() -> void:
	await _run_speed_at()
	_run_scaled()
	await _run_stepped()


func _level() -> Node3D:
	var level := Node3D.new()
	add_child(level)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	level.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	return level


func _zone(level: Node3D, at: Vector3, size: Vector3, speed: float) -> LevelSpeedZone:
	var z := LevelSpeedZone.new()
	z.size = size
	z.speed = speed
	level.add_child(z)
	z.position = at
	return z


func _run_speed_at() -> void:
	print("== zones: the pace where a body stands ==")
	var level: Node3D = _level()
	_zone(level, Vector3(0, 0.4, 0), Vector3(1, 0.8, 2), 0.4)
	_zone(level, Vector3(0, 0.4, 0.8), Vector3(1, 0.8, 1), 0.25)
	for i: int in 3:
		await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	_check(is_equal_approx(LevelSpeedZone.speed_at(space, Vector3(0, 0, -0.5)), 0.4), "in a zone: its pace (0.4)")
	_check(is_equal_approx(LevelSpeedZone.speed_at(space, Vector3(0, 0, 0.8)), 0.25), "where two overlap: the slower (0.25)")
	_check(is_equal_approx(LevelSpeedZone.speed_at(space, Vector3(0, 0, -3)), 1.0), "out of them: its own pace")
	_check(is_equal_approx(LevelSpeedZone.speed_at(space, Vector3(0, 1.5, -0.5)), 1.0), "above one (its box is 0.8 m high): its own")
	_check(is_equal_approx(LevelSpeedZone.speed_at(null, Vector3.ZERO), 1.0), "no space: its own")
	var z: LevelSpeedZone = LevelSpeedZone.new()
	_check(z.collision_layer == LevelSpeedZone.LAYER and z.collision_mask == 0 and not z.monitoring,
		"a zone is on the zones layer and collides with nothing (nothing is pushed by it)")
	z.free()
	level.queue_free()


func _run_scaled() -> void:
	print("== zones: a config at a pace ==")
	var cfg := MovementConfig.new()
	cfg.dash_impulse = 5.0
	var half: MovementConfig = LevelSpeedZone.scaled(cfg, 0.5)
	_check(half != cfg and is_equal_approx(half.run_speed, cfg.run_speed * 0.5) and is_equal_approx(half.walk_speed, cfg.walk_speed * 0.5)
		and is_equal_approx(half.sprint_speed, cfg.sprint_speed * 0.5) and is_equal_approx(half.dash_impulse, 2.5),
		"half pace: walk, run, sprint and dash halved, on a copy")
	_check(is_equal_approx(half.acceleration, cfg.acceleration) and is_equal_approx(half.jump_velocity, cfg.jump_velocity),
		"how it gets up to speed and jumps: unchanged")
	_check(LevelSpeedZone.scaled(cfg, 1.0) == cfg, "its own pace: the config itself")


## A body run forward `frames` physics frames from `from`: how far it got.
func _run_from(m: SpaceTimeMovementComponent, body: CharacterBody3D, from: Vector3, frames: int, seq_ref: Array[int]) -> float:
	await _place_predicted(m, from, seq_ref, 4)
	var start: Vector3 = body.global_position
	for i: int in frames:
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		f.move_dir = Vector2(0, -1)
		m.push_input(f)
	return Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()


func _run_stepped() -> void:
	print("== zones: a body stepped through one ==")
	var level: Node3D = _level()
	# A long crawl from z = -2 to z = -22, 0.8 m high.
	_zone(level, Vector3(0, 0.4, -12), Vector3(2, 0.8, 20), 0.4)
	var body := FakeOwnerEntity.new()
	body.entity_id = 7301
	var cap := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 0.7
	cap.shape = capsule
	cap.position = Vector3(0, 0.35, 0)
	body.add_child(cap)
	body.collision_mask = 1
	level.add_child(body)
	var m := SpaceTimeMovementComponent.new()
	m.config = MovementConfig.new()
	m.mode = SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED
	get_tree().root.add_child(m)
	m.bind(body, {&"movement_state": FakeMoveRow.new(body.entity_id, Vector3(20, 0, 10), 1_000)})
	for i: int in 3:
		await get_tree().physics_frame
	var seq: Array[int] = [10]
	# Each run long enough to get up to speed and keep going: 40 frames.
	var outside: float = await _run_from(m, body, Vector3(20, 0, 10), 40, seq)
	var inside: float = await _run_from(m, body, Vector3(0, 0, -3), 40, seq)
	print("   40 frames: %.2f m in the open, %.2f m in the crawl" % [outside, inside])
	_check(outside > 1.0, "it runs in the open (%.2f m)" % outside)
	_check(absf(inside / outside - 0.4) < 0.05, "in the zone it goes at its 0.4 pace (%.2f of the open's)" % (inside / outside))
	var out_again: float = await _run_from(m, body, Vector3(-20, 0, 10), 40, seq)
	_check(absf(out_again - outside) < 0.05, "out of it again, its own pace (%.2f m)" % out_again)
	m.queue_free()
	level.queue_free()
	await get_tree().process_frame
