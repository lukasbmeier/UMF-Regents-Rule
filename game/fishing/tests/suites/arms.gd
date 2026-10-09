extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `arms` suite (`-- --only=arms` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	await _run_arm_clip_tests()




## ARMS OUT OF THE BODY, IN EVERY ANIMATION (DECISIONS #163). Luke: "all animations should go
## through clipping checks to see if arms clip in the body or other clipping". The real fisher (its
## driver, its rod and the rod's two-handed hand, the grip's `off_hand_animations`), in each body the game
## dresses people in, held in every animation of its set through its clip, and its arms measured
## against its own skin as drawn (`SkinClearance`, during the skeleton's update). Two things fail:
##
##   OFF THE ROD   in an animation the rod is held in both hands in (the grip's `off_hand_animations`), the
##                 left wrist leaves its hold on the reel by more than OFF_HAND_SLACK. This is what
##                 Luke saw: the clips' own left hand is not on this rod, and it hung in the air,
##                 crossed her belly and pressed into her chest (the wait, the cast).
##   INTO THE BODY a forearm or a hand goes FOREARM_SLACK deeper into the body than standing does,
##                 or an upper arm UPPER_ARM_SLACK deeper. Calibrated on what Luke judged: the heave
##                 and the wait he called right put an upper arm 2.0-3.6 cm against her chest (it
##                 rests there when the arms come forward); a forearm or hand through the body is
##                 the fault, and the old elbow put one 6-12 cm in.
const FOREARM_SLACK: float = 0.03
const UPPER_ARM_SLACK: float = 0.045
const OFF_HAND_SLACK: float = 0.03
const ARM_SAMPLES: int = 8
## By path: a class registered after the last import is not known by name until the next one.
const SKIN: GDScript = preload("res://foundation/held/skin_clearance.gd")


func _run_arm_clip_tests() -> void:
	print("== arms out of the body, in every animation ==")
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var defn: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(defn)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	var seen: Array[StringName] = []
	var eid: int = 5301
	while seen.size() < 2 and eid < 5321:
		reg.local_entity_id = eid
		_buffer_player_rows(reg, eid)
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
		var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
		for i: int in range(3):
			await get_tree().process_frame
		var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent if me != null else null
		var feedback: FishingFeedback = me.find_component(FishingFeedback) as FishingFeedback if me != null else null
		var skel: Skeleton3D = driver._find_skeleton(me.get_node(^"Visual/Model")) if driver != null else null
		var body: StringName = StringName(skel.get_meta(HeldItem.BODY_META, &"")) if skel != null else &""
		if skel != null and feedback != null and feedback.fx() != null and not seen.has(body):
			seen.append(body)
			await _arms_in_every_animation(me, driver, feedback, skel, body)
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
		spawner._flush_despawns()
		await get_tree().process_frame
		eid += 1
	_check(seen.size() == 2, "both of the game's bodies were measured (%s)" % str(seen))
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame


func _arms_in_every_animation(me: SpaceTimeEntity, driver: AnimationDriverComponent, feedback: FishingFeedback,
		skel: Skeleton3D, body: StringName) -> void:
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	if input != null:
		input.set_physics_process(false)
		input.send_to_server = false
	# The body is held in each animation here, so the genre's own pose-keeping stands aside; the rod
	# reads the animation itself, in hand.
	feedback.set_process(false)
	var rod: FishingRod = feedback.fx().rod()
	rod.driver = driver
	var equip: EquipComponent = me.find_component(EquipComponent) as EquipComponent
	if equip != null:
		equip.away_when_idle = false
		equip.set_equipped_now(true)
	rod.set_stowed_now(false)
	var skin: Dictionary = SKIN.gather(skel)
	var depth: Array[float] = [0.0]
	var where: Array[String] = [""]
	var by_piece: Dictionary[String, float] = {}
	var measure := func() -> void:
		var hit: Dictionary = SKIN.arms_into_body(skel, skin)
		var pieces: Dictionary = hit["pieces"]
		for piece: String in pieces:
			by_piece[piece] = maxf(float(by_piece.get(piece, 0.0)), float(pieces[piece]))
		if float(hit["depth"]) > depth[0]:
			depth[0] = float(hit["depth"])
			where[0] = "%s into the %s" % [hit["arm"], hit["part"]]
	# The left wrist against where it holds the reel (the grip's off_hand_wrist), as drawn.
	var off_hand: Array[float] = [0.0]
	var measure_hand := func() -> void:
		var want: Vector3 = rod.knob_position() + rod.global_transform.basis * rod.grip.off_hand_wrist
		off_hand[0] = maxf(off_hand[0], BodyClearance.bone_at(skel, &"hand_l").distance_to(want))
	var hand_off: Dictionary[StringName, float] = {}
	var worst: Dictionary[StringName, Array] = {}
	var names: Array[StringName] = []
	for k: StringName in driver.animation_set.clips:
		if driver.animation_set.has_exact(k):
			names.append(k)
	names.sort()
	var piece_worst: Dictionary[StringName, Dictionary] = {}
	for semantic: StringName in names:
		depth[0] = 0.0
		where[0] = ""
		by_piece.clear()
		var deepest_at: float = 0.0
		off_hand[0] = 0.0
		var two: bool = rod.grip.off_hand_animations.has(semantic)
		driver.hold_pose(semantic, 1.0, 0.0)
		await _tick_frames(30)   # the pose blends in, and the rod's grip and hand follow it
		for k: int in range(ARM_SAMPLES + 1):
			var at: float = float(k) / float(ARM_SAMPLES)
			driver.hold_pose(semantic, 1.0, at)
			await _tick_frames(3)
			var before: float = depth[0]
			skel.skeleton_updated.connect(measure)
			if two:
				skel.skeleton_updated.connect(measure_hand)
			await _tick_frames(1)
			skel.skeleton_updated.disconnect(measure)
			if two:
				skel.skeleton_updated.disconnect(measure_hand)
			if depth[0] > before:
				deepest_at = at
		if two:
			hand_off[semantic] = off_hand[0]
		worst[semantic] = [depth[0], where[0], deepest_at, rod.off_hand_weight()]
		piece_worst[semantic] = by_piece.duplicate()
		var line: PackedStringArray = []
		for piece: String in by_piece:
			if by_piece[piece] > 0.0:
				line.append("%s %.1f" % [piece, by_piece[piece] * 100.0])
	# PICTURES (`--arm-pictures=<dir>`, in a window): each animation that put an arm in the body, at
	# its deepest moment, from in front and from the side of that arm, for a person to judge.
	var pictures: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--arm-pictures="):
			pictures = arg.substr("--arm-pictures=".length())
	if not pictures.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(pictures)
		var cam := Camera3D.new()
		cam.fov = 35.0
		me.get_parent().add_child(cam)
		cam.make_current()
		for semantic: StringName in names:
			var w: Array = worst[semantic]
			if float(w[0]) <= 0.005:
				continue
			driver.hold_pose(semantic, 1.0, float(w[2]))
			await _tick_frames(20)
			var chest: Vector3 = BodyClearance.bone_at(skel, &"spine_03")
			var fwd: Vector3 = skel.global_basis.z.normalized()
			var side: Vector3 = skel.global_basis.x.normalized() * (1.0 if String(w[1]).begins_with("left") else -1.0)
			var shots: Array[Image] = []
			for dir: Vector3 in [fwd, (fwd + side).normalized(), side]:
				cam.global_position = chest + dir * 1.1
				cam.look_at(chest, Vector3.UP)
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(360, 400)
				img.convert(Image.FORMAT_RGBA8)
				shots.append(img)
			var sheet := Image.create(360 * shots.size(), 400, false, Image.FORMAT_RGBA8)
			for k: int in range(shots.size()):
				sheet.blit_rect(shots[k], Rect2i(0, 0, 360, 400), Vector2i(k * 360, 0))
			sheet.save_png("%s/%s_%s.png" % [pictures, body, String(semantic).replace(".", "_")])
		# And the cast through its clip, in front and from her left: a strip of moments.
		var strip: Array[Image] = []
		for at: float in [0.1, 0.25, 0.4, 0.55, 0.7, 0.85]:
			driver.hold_pose(AnimationSet.INTERACT, 1.0, at)
			await _tick_frames(20)
			var chest_now: Vector3 = BodyClearance.bone_at(skel, &"spine_03")
			for dir: Vector3 in [skel.global_basis.z.normalized(),
					(skel.global_basis.z - skel.global_basis.x).normalized()]:
				cam.global_position = chest_now + dir * 1.3
				cam.look_at(chest_now, Vector3.UP)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(300, 340)
				img.convert(Image.FORMAT_RGBA8)
				strip.append(img)
		var strip_sheet := Image.create(300 * 6, 340 * 2, false, Image.FORMAT_RGBA8)
		for k: int in range(strip.size()):
			strip_sheet.blit_rect(strip[k], Rect2i(0, 0, 300, 340), Vector2i((k / 2) * 300, (k % 2) * 340))
		strip_sheet.save_png("%s/%s_cast_strip.png" % [pictures, body])
		cam.queue_free()
	driver.release_pose()
	feedback.set_process(true)
	var rest: Dictionary = piece_worst.get(AnimationSet.IDLE, {})
	var over: Array[String] = []
	for semantic: StringName in names:
		var w: Array = worst[semantic]
		print("   %s %-22s %4.1f cm%s%s" % [body, semantic, float(w[0]) * 100.0,
			"" if float(w[0]) <= 0.0 else "  %s at %d%%" % [w[1], roundi(float(w[2]) * 100.0)],
			"" if not hand_off.has(semantic) else ", the left wrist at most %.1f cm off the reel" % (hand_off[semantic] * 100.0)])
		var pieces: Dictionary = piece_worst[semantic]
		for piece: String in pieces:
			var slack: float = UPPER_ARM_SLACK if piece.ends_with("upper arm") else FOREARM_SLACK
			if float(pieces[piece]) > float(rest.get(piece, 0.0)) + slack:
				over.append("%s: the %s %.1f cm in" % [semantic, piece, float(pieces[piece]) * 100.0])
	_check(over.is_empty(),
		"%s: in every animation, no forearm or hand goes over %.0f cm, and no upper arm over %.1f cm, deeper into the body than standing%s"
			% [body, FOREARM_SLACK * 100.0, UPPER_ARM_SLACK * 100.0, "" if over.is_empty() else ": " + "; ".join(over)])
	var strays: Array[String] = []
	for semantic: StringName in hand_off:
		if hand_off[semantic] > OFF_HAND_SLACK:
			strays.append("%s %.1f cm" % [semantic, hand_off[semantic] * 100.0])
	_check(hand_off.size() == rod.grip.off_hand_animations.size() and strays.is_empty(),
		"%s: in every animation the rod is held in both hands in (%s), the left hand stays on it, at the reel%s"
			% [body, ", ".join(rod.grip.off_hand_animations), "" if strays.is_empty() else ": off by " + ", ".join(strays)])
