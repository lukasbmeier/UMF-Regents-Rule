extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fishing_animation_scene` suite (`-- --only=fishing_animation_scene` runs it alone), run because shared/game.json
## lists fishing. The fishing half of tests/suites/animation_scene.gd (the original, run on the angler and the lakeside). Shared helpers: game/fishing/tests/fishing_suite_base.gd.


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


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.001 \
		and Quaternion(a.basis.orthonormalized()).angle_to(Quaternion(b.basis.orthonormalized())) < deg_to_rad(0.3)


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
