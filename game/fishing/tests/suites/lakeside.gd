extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `lakeside` suite (`-- --only=lakeside` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	await _run_lakeside_tests()


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
