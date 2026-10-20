extends "res://tests/suite_base.gd"
## The `animation_scene` suite (tests/test_runner.gd runs it; `-- --only=animation_scene` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_animation_scene_tests()



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
	var defn: EntityDefinition = load(CHARACTER_DEF) as EntityDefinition
	if reg == null or spawner == null or packed == null or defn == null:
		_check(false, "autoloads, level and character definition present")
		return
	_check(defn.visual_for(0) != null and defn.animation_set != null,
		"the character definition carries a rigged model and an animation set")
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
	_check(me != null and me.is_local_authority, "the character spawned as ours")
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
	# The character is a LOCAL entity, so its own input component samples the keyboard every physics
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
	_check(driver.is_strafing(), "the character's set drives a strafing blend")
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
	# A COMMITTED action (DECISIONS #256: a swing's wind-up, which lands whatever the legs do) plays on
	# while the body walks; let go, walking cuts it again.
	driver._on_interact_requested(0)
	driver.commit_action(2.0)
	await _anim_frames(movement, seq, 4, Vector2.ZERO)
	await _anim_frames(movement, seq, 20, Vector2(0.0, -1.0))
	_check(driver.action_playing() and driver.action_committed(), "a committed action plays on while the body walks")
	driver.commit_action(0.0)
	await _anim_frames(movement, seq, 15, Vector2(0.0, -1.0))
	_check(not driver.action_playing(), "and once it is let go, walking cuts it as before")
	await _anim_frames(movement, seq, 20, Vector2.ZERO)
	# AN UPPER-BODY POSE (DECISIONS #266: a bow drawn on the move): it holds while the body walks, and it
	# moves only the chest, arms and fingers.
	var up_blend: AnimationNodeBlend2 = (driver.animation_tree().tree_root as AnimationNodeBlendTree).get_node(AnimationTreeBuilder.NODE_UPPER_POSE) as AnimationNodeBlend2
	_check(up_blend != null and up_blend.is_path_filtered(^"Skeleton3D:upperarm_r") and not up_blend.is_path_filtered(^"Skeleton3D:thigh_l"),
		"the upper-body pose moves the arms, not the legs")
	for i: int in range(40):
		driver.hold_upper_pose(AnimationSet.INTERACT, 1.0, 0.5)
		await _anim_frames(movement, seq, 1, Vector2(0.0, -1.0))
	_check(driver.upper_pose_weight() > 0.95 and driver.upper_pose_clip() == defn.animation_set.anim_name(AnimationSet.INTERACT),
		"held while walking, it stays (%.2f)" % driver.upper_pose_weight())
	driver.release_upper_pose()
	await _anim_frames(movement, seq, 30, Vector2.ZERO)
	_check(driver.upper_pose_weight() < 0.05, "let go, it blends out")

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
		_check(driver.action_clip() == defn.animation_set.anim_name(AnimationSet.INTERACT) and driver.action_playing(),
			"the interact key plays the set's interact animation (%s)" % driver.action_clip())
	if action != null:
		action.action_started.emit(0, 1)
		await _anim_frames(movement, seq, 2, Vector2.ZERO)
		# Its own clip when the set has one (fishing's does), else the set's interact fallback.
		var ability_clip: StringName = defn.animation_set.anim_name(&"ability.0")
		if not defn.animation_set.has_exact(&"ability.0"):
			ability_clip = defn.animation_set.anim_name(AnimationSet.INTERACT)
		_check(driver.action_clip() == ability_clip,
			"and an ability plays its clip (%s, want %s)" % [driver.action_clip(), ability_clip])

	# (The fishing half of this suite, the heave pose and the rod in the hand, is fishing's:
	# game/fishing/tests/suites/fishing_animation_scene.gd.)

	# --- death and revival ------------------------------------------------------------------
	# A full-body one-shot holds the state machine under it, so a revival asked for meanwhile lands
	# when it ends: let the ability's action finish first (AGENTS: animation rules).
	for i: int in range(240):
		if not driver.action_playing() and not driver.hit_playing():
			break
		await _anim_frames(movement, seq, 1, Vector2.ZERO)
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
