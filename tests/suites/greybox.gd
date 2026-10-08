extends "res://tests/suite_base.gd"
## The `greybox` suite (tests/test_runner.gd runs it; `-- --only=greybox` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_greybox_tests()



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
