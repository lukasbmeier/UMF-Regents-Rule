extends "res://tests/suite_base.gd"
## The `aim` suite (tests/test_runner.gd runs it; `-- --only=aim` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_aim_tests()



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
