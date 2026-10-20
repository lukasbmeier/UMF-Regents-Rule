extends "res://tests/suite_base.gd"
## The `animation` suite (tests/test_runner.gd runs it; `-- --only=animation` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_animation_tests()
	_run_universal_grip_tests()
	await _run_grip_preview_tests()



func _run_animation_tests() -> void:
	print("== animation: sets and the generated tree ==")
	var set: AnimationSet = load(HUMANOID_SET) as AnimationSet
	_check(set != null, "the fisher's AnimationSet loads")
	if set == null:
		return
	_check_upper_body_filter(set)

	# (a) the SHIPPED set is complete. Regenerating it against a different library is a one-line
	# tool run, and this is what says whether the result can still drive a character.
	_check(set.missing_required().is_empty(),
		"it names every clip the driver needs (missing %s)" % str(set.missing_required()))
	_check(set.dangling_clips().is_empty(),
		"and every clip it names is really in its libraries (dangling %s)" % str(set.dangling_clips()))
	_check(set.libraries.size() == 2 and set.libraries.has(&"") and set.libraries.has(&"extra"),
		"it carries both libraries (%s)" % str(set.libraries.keys()))
	_check(set.anim_name(AnimationSet.IDLE) == &"Idle"
		and set.anim_name(AnimationSet.RUN) == &"Jog_Fwd"
		and set.anim_name(AnimationSet.SPRINT) == &"Sprint",
		"one clip per gait: %s / %s / %s / %s" % [set.anim_name(AnimationSet.IDLE),
			set.anim_name(AnimationSet.WALK), set.anim_name(AnimationSet.RUN),
			set.anim_name(AnimationSet.SPRINT)])

	# EACH CLIP IS PLAYED AT THE SPEED THE GAME MOVES AT. The generator measures what a clip was
	# authored to travel at (off its planted foot) and scales it to this game's gait; a character
	# at 5 m/s playing a clip authored for 1 m/s is the skating that reads as floaty.
	var unscaled: Array[String] = []
	for semantic: StringName in [AnimationSet.WALK, AnimationSet.RUN, AnimationSet.SPRINT,
			AnimationSet.WALK_BACK, AnimationSet.WALK_LEFT, AnimationSet.RUN_BACK,
			AnimationSet.RUN_LEFT]:
		var ref: AnimationClipRef = set.clip(semantic)
		if ref == null or is_equal_approx(ref.speed_scale, 1.0):
			unscaled.append(String(semantic))
		_check(ref != null and ref.speed_scale > 0.25 and ref.speed_scale < 3.0,
			"%s plays at a sane rate (x%.2f)" % [semantic, ref.speed_scale if ref != null else 0.0])
	_check(unscaled.is_empty(),
		"every locomotion clip was fitted to a gait, none left at its authored speed (%s)"
			% str(unscaled))

	# AND EVERY LOOPING CLIP STILL LOOPS. Speed-scaling a clip means playing it through a custom
	# timeline — the only thing a state-machine state understands — and turning that on hands the
	# clip's loop over to the NODE's own `loop_mode`, which defaults to "no loop". Every locomotion
	# clip is scaled, so every one of them played a single cycle and froze on a last frame that is
	# indistinguishable from its first, while the character kept sliding (DECISIONS #103).
	var built: AnimationTree = AnimationTreeBuilder.build(set)
	_check(built != null, "the fisher's set builds a tree")
	if built != null:
		var faults: Array[String] = _loop_faults(built)
		_check(faults.is_empty(), "a strafing tree loops what must loop and ends what must end: %s"
			% str(faults))
		# The forward-only graph is a different node with the same trap in it.
		var line_set: AnimationSet = set.duplicate() as AnimationSet
		line_set.strafe = false
		var line_tree: AnimationTree = AnimationTreeBuilder.build(line_set)
		var line_faults: Array[String] = _loop_faults(line_tree)
		_check(line_tree != null and not AnimationTreeBuilder.is_strafing(line_set)
			and line_faults.is_empty(),
			"and so does a forward-only one, which is a different node: %s" % str(line_faults))
		# An AnimationTree is a Node. These two were never parented, so nothing else will free them
		# and the run would end holding every clip they reference.
		built.free()
		if line_tree != null:
			line_tree.free()

	# A NODE RE-POINTED AT RUNTIME TAKES THE NEW CLIP'S TIMING. The driver swaps clips in two
	# places (a heavy landing, an ability's own animation); a node that kept the previous clip's
	# timeline would stretch the new one to fit a length it never had.
	var swap := AnimationNodeAnimation.new()
	AnimationTreeBuilder.apply_clip(swap, set, AnimationSet.JUMP_START)
	var swapped_len: float = swap.timeline_length
	_check(swap.use_custom_timeline and swapped_len > 0.0,
		"a scaled clip arrives with a timeline (%.2f s)" % swapped_len)
	AnimationTreeBuilder.apply_clip(swap, set, AnimationSet.JUMP_LOOP, true)
	_check(not swap.use_custom_timeline,
		"and swapping an UNSCALED clip in clears it rather than inheriting %.2f s" % swapped_len)

	# (b) The interact verb resolves to a clip (a genre's set may override it with its own, from a
	# second library: fishing's cast, checked in its own suite).
	_check(set.clip(AnimationSet.INTERACT) != null and set.anim_name(AnimationSet.INTERACT) != &"",
		"the set's `interact` resolves to a clip (%s)" % set.anim_name(AnimationSet.INTERACT))

	# (c) FALLBACKS. The libraries have no heavy landing; the set must still land.
	_check(not set.has_exact(AnimationSet.JUMP_LAND_HEAVY),
		"the library really has no heavy landing (otherwise this fallback is untested)")
	_check(set.anim_name(AnimationSet.JUMP_LAND_HEAVY) == set.anim_name(AnimationSet.JUMP_LAND),
		"so a heavy landing falls back to the ordinary one")

	# (d) a set with almost nothing in it: the chain has to bottom out at idle, and the missing
	# list has to be honest about what is not there.
	var tiny := AnimationSet.new()
	var only_idle: Dictionary[StringName, AnimationClipRef] = {
		AnimationSet.IDLE: AnimationClipRef.make(&"Idle", true),
	}
	tiny.clips = only_idle
	_check(tiny.anim_name(AnimationSet.RUN) == &"Idle",
		"run falls back through walk to idle (%s)" % tiny.anim_name(AnimationSet.RUN))
	_check(tiny.anim_name(AnimationSet.DEATH) == &"Idle", "so does a missing death")
	_check(tiny.missing_required().size() == 3,
		"but the three jump clips have nothing to fall back to, and it says so (%s)"
			% str(tiny.missing_required()))

	# (e) a typo is caught by the set, not by the player. `dangling_clips` needs real libraries.
	var typo := AnimationSet.new()
	typo.libraries = set.libraries
	var bad: Dictionary[StringName, AnimationClipRef] = {
		AnimationSet.IDLE: AnimationClipRef.make(&"Idle", true),
		AnimationSet.HIT: AnimationClipRef.make(&"Hit_Chestt"),
		AnimationSet.WALK: AnimationClipRef.make(&"extra/Walk_Fwd", true),
	}
	typo.clips = bad
	var dangling: Array[StringName] = typo.dangling_clips()
	_check(dangling.size() == 1 and dangling[0] == AnimationSet.HIT,
		"a misspelled clip is reported, and a correctly spelled one in the second library is not (%s)"
			% str(dangling))

	# --- the generated tree ---------------------------------------------------------------
	var tree: AnimationTree = AnimationTreeBuilder.build(set)
	_check(tree != null, "the builder produces a tree for a complete set")
	if tree == null:
		return
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	_check(root != null and root.get_node_list().size() == 12,
		"the graph is the twelve documented nodes: body, pose (+ its clip, scale, seek), upper, hit, action (%s)"
			% str(root.get_node_list()))
	# THE UPPER BODY (DECISIONS #158): a one-shot that moves the chest, arms and hands and leaves
	# the hips and legs to the body under it.
	var upper: AnimationNodeOneShot = root.get_node(AnimationTreeBuilder.NODE_UPPER) as AnimationNodeOneShot
	_check(upper != null and upper.filter_enabled and upper.is_path_filtered(^"Skeleton3D:hand_r")
			and upper.is_path_filtered(^"Skeleton3D:spine_03") and upper.is_path_filtered(^"Skeleton3D:index_02_l")
			and not upper.is_path_filtered(^"Skeleton3D:thigh_r") and not upper.is_path_filtered(^"Skeleton3D:pelvis")
			and typeof(tree.get(AnimationTreeBuilder.P_UPPER_REQUEST)) == TYPE_INT,
		"the upper-body one-shot plays the chest, the arms and the fingers, and passes the hips and legs through")
	# THE POSE sits between the body and the one-shots: body -> pose -> hit -> action -> output.
	_check(typeof(tree.get(AnimationTreeBuilder.P_POSE_BLEND)) == TYPE_FLOAT
		and typeof(tree.get(AnimationTreeBuilder.P_POSE_SCALE)) == TYPE_FLOAT
		and typeof(tree.get(AnimationTreeBuilder.P_POSE_SEEK)) == TYPE_FLOAT,
		"the held pose takes a blend, a scale and a seek")
	_check(is_zero_approx(float(tree.get(AnimationTreeBuilder.P_POSE_BLEND))),
		"and starts at nothing: a character holds no pose until asked")
	_check(tree.get_animation_library_list().size() == 2,
		"both libraries came with it, so `extra/Fish_Cast` resolves at runtime")

	# The four parameter paths ARE the interface between the driver and the graph. If a rename
	# breaks one, the driver writes into nothing and the character quietly stops reacting.
	_check(tree.get(AnimationTreeBuilder.P_PLAYBACK) is AnimationNodeStateMachinePlayback,
		"the state machine's playback is at %s" % AnimationTreeBuilder.P_PLAYBACK)
	_check(typeof(tree.get(AnimationTreeBuilder.P_BLEND)) == TYPE_VECTOR2,
		"a strafing set blends on a PLANE: %s takes a Vector2" % AnimationTreeBuilder.P_BLEND)
	_check(typeof(tree.get(AnimationTreeBuilder.P_HIT_REQUEST)) == TYPE_INT
		and typeof(tree.get(AnimationTreeBuilder.P_ACTION_REQUEST)) == TYPE_INT,
		"both one-shots take a request")

	var sm: AnimationNodeStateMachine = root.get_node(AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	for state: StringName in [AnimationTreeBuilder.STATE_GROUNDED, AnimationTreeBuilder.STATE_JUMP_START,
			AnimationTreeBuilder.STATE_AIR, AnimationTreeBuilder.STATE_LAND, AnimationTreeBuilder.STATE_DEAD]:
		_check(sm.has_node(state), "the state machine has '%s'" % state)
	_check(sm.has_transition(AnimationTreeBuilder.STATE_START, AnimationTreeBuilder.STATE_GROUNDED),
		"and enters on Grounded by itself, so a character animates from frame one")

	# EVERY travel the driver can make is a DIRECT transition. `travel()` takes the shortest
	# route it can find, and when the only route was two hops it once reached the ground by way
	# of the death state — a live character playing a death animation, with nothing in any log.
	var indirect: Array[String] = []
	for from: StringName in AnimationTreeBuilder.TRAVELS:
		for to: StringName in AnimationTreeBuilder.TRAVELS[from]:
			if not sm.has_transition(from, to):
				indirect.append("%s->%s" % [from, to])
	_check(indirect.is_empty(),
		"no travel the driver can make has to be routed through another state (%s)" % str(indirect))

	# THE BLEND POINTS ARE THE GAME'S OWN SPEEDS. The driver divides the body's velocity by
	# sprint_speed, so a point at walk_speed/sprint_speed is reached exactly when the player
	# walks — including the sideways and backwards gears, which are slower on purpose.
	var cfg: MovementConfig = MovementConfig.shared()
	_check(set.can_strafe() and AnimationTreeBuilder.is_strafing(set),
		"the shipped set strafes: it has the whole directional ring")
	var plane: AnimationNodeBlendSpace2D = sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) as AnimationNodeBlendSpace2D
	_check(plane != null and plane.get_blend_point_count() == 10,
		"the strafing blend is idle, two rings of four and a sprint (%d points)"
			% (plane.get_blend_point_count() if plane != null else -1))
	var w: float = cfg.walk_speed / cfg.sprint_speed
	var r: float = cfg.run_speed / cfg.sprint_speed
	var want: Dictionary[String, Vector2] = {
		"idle": Vector2.ZERO,
		"walk": Vector2(0.0, w),
		"walk_back": Vector2(0.0, -w * cfg.back_speed_mult),
		"walk_left": Vector2(-w * cfg.strafe_speed_mult, 0.0),
		"run": Vector2(0.0, r),
		"run_left": Vector2(-r * cfg.strafe_speed_mult, 0.0),
		"sprint": Vector2(0.0, 1.0),
	}
	var found: Array[Vector2] = []
	for i: int in range(plane.get_blend_point_count()):
		found.append(plane.get_blend_point_position(i))
	var missing_points: Array[String] = []
	for label: String in want:
		var hit: bool = false
		for pos: Vector2 in found:
			if pos.distance_to(want[label]) < 1e-5:
				hit = true
		if not hit:
			missing_points.append("%s@%s" % [label, want[label]])
	_check(missing_points.is_empty(),
		"every gait sits at the speed the model produces for it (%s missing from %s)"
			% [str(missing_points), str(found)])

	# The same set, without the strafe wish: one forward axis, four gaits on it.
	var line_set: AnimationSet = set.duplicate() as AnimationSet
	line_set.strafe = false
	var line_tree: AnimationTree = AnimationTreeBuilder.build(line_set)
	var line_sm: AnimationNodeStateMachine = (line_tree.tree_root as AnimationNodeBlendTree).get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	var line: AnimationNodeBlendSpace1D = line_sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) as AnimationNodeBlendSpace1D
	_check(line != null and line.get_blend_point_count() == 4,
		"turning strafing off gives one axis with idle, walk, run and sprint on it (%d)"
			% (line.get_blend_point_count() if line != null else -1))
	_check(line != null and absf(line.get_blend_point_position(1) - w) < 1e-5
		and absf(line.get_blend_point_position(2) - r) < 1e-5,
		"at walk_speed/sprint_speed and run_speed/sprint_speed, not guesses")
	_check(typeof(line_tree.get(AnimationTreeBuilder.P_BLEND)) == TYPE_FLOAT,
		"and it blends on a float")
	line_tree.free()

	# THE TAKE-OFF FITS THE JUMP. Quaternius' clip is 1.33 s and this game's jump is 0.8 s, so
	# without the generated speed-up the character is still crouching to jump as it lands, and
	# the airborne loop is never reached at all.
	var airtime: float = 2.0 * cfg.jump_velocity / cfg.gravity
	var start_ref: AnimationClipRef = set.clip(AnimationSet.JUMP_START)
	var start_len: float = set.libraries[&""].get_animation(
		StringName(String(start_ref.anim_name))).length
	_check(start_ref.speed_scale > 1.0 and start_len / start_ref.speed_scale < airtime * 0.5,
		"the take-off plays in %.2f s, inside the %.2f s the player is airborne (clip is %.2f s)"
			% [start_len / start_ref.speed_scale, airtime, start_len])

	# LOOPING. A locomotion blend of one-shot clips freezes a second after the player moves, and
	# nothing about that failure says "loop flag".
	for semantic: StringName in [AnimationSet.IDLE, AnimationSet.WALK, AnimationSet.RUN,
			AnimationSet.SPRINT, AnimationSet.RUN_LEFT, AnimationSet.WALK_BACK]:
		var anim: Animation = _clip_in(set, set.anim_name(semantic))
		_check(anim != null and anim.loop_mode != Animation.LOOP_NONE,
			"%s loops" % set.anim_name(semantic))

	# The speed-up is applied through a custom timeline, because a state-machine state has
	# nowhere to put a TimeScale node. Assert the node really carries it: getting this wrong
	# leaves the clip at its authored length and nothing says so.
	var sm2: AnimationNodeStateMachine = root.get_node(AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	var takeoff: AnimationNodeAnimation = sm2.get_node(AnimationTreeBuilder.STATE_JUMP_START) as AnimationNodeAnimation
	_check(takeoff.use_custom_timeline and takeoff.stretch_time_scale
		and absf(takeoff.timeline_length - start_len / start_ref.speed_scale) < 1e-3,
		"the take-off state plays its clip in %.2f s (timeline %.2f s)"
			% [start_len / start_ref.speed_scale, takeoff.timeline_length])

	# A library exported without `_Loop` suffixes has no loop flags, and a locomotion blend of
	# one-shots freezes a second after the player starts walking. The builder fixes that; here
	# it is given a clip that really does not loop, on a private copy of the library.
	var copy: AnimationLibrary = set.libraries[&""].duplicate(true) as AnimationLibrary
	_check(copy.get_animation(&"Interact").loop_mode == Animation.LOOP_NONE,
		"`Interact` is a one-shot clip in the library (otherwise this test proves nothing)")
	var loopy := AnimationSet.new()
	var loopy_libs: Dictionary[StringName, AnimationLibrary] = {&"": copy}
	loopy.libraries = loopy_libs
	var loopy_clips: Dictionary[StringName, AnimationClipRef] = {}
	for semantic: StringName in AnimationSet.REQUIRED:
		loopy_clips[semantic] = AnimationClipRef.make(&"Interact", true)
	loopy.clips = loopy_clips
	var loopy_tree: AnimationTree = AnimationTreeBuilder.build(loopy)
	_check(loopy_tree != null and copy.get_animation(&"Interact").loop_mode != Animation.LOOP_NONE,
		"building a tree makes the clips its locomotion needs loop")
	if loopy_tree != null:
		loopy_tree.free()

	# (f) NEGATIVE: an unusable set is refused outright rather than producing a tree that plays
	# nothing. The push_error this raises is listed in run_tests.sh.
	_check(AnimationTreeBuilder.build(tiny) == null,
		"a set without the required clips is refused, loudly")
	tree.free()


## A REAL RIG, DRIVEN BY REAL INPUT. Everything above is about resources; this spawns the actual
## fisher with the actual Quaternius skeleton in the actual level, pushes input frames through
## the same prediction the player drives, and asks the skeleton whether it moved.
##
## That last question is the one that matters: every link in the chain — library extraction,
## track re-addressing, the generated graph, the parameter paths, the driver — is invisible
## until a bone rotates, and each of them fails silently on its own.
## Clips in a generated tree whose loop contradicts the job they do: a locomotion clip that
## would freeze after one cycle, or a one-shot that would never hand over. Returns the offenders,
## named, so a failure says which clip rather than that something somewhere is wrong.
func _loop_faults(tree: AnimationTree) -> Array[String]:
	var out: Array[String] = []
	if tree == null:
		return ["no tree"]
	var one_shots: Array[String] = [String(AnimationTreeBuilder.STATE_JUMP_START),
		String(AnimationTreeBuilder.STATE_LAND), String(AnimationTreeBuilder.STATE_DEAD),
		String(AnimationTreeBuilder.NODE_HIT_CLIP), String(AnimationTreeBuilder.NODE_ACTION_CLIP)]
	var nodes: Dictionary[String, AnimationNodeAnimation] = _clip_nodes(tree)
	for label: String in nodes:
		var node: AnimationNodeAnimation = nodes[label]
		# Without a custom timeline the clip keeps its own loop, which the extractor set.
		if node == null or not node.use_custom_timeline:
			continue
		if one_shots.has(label):
			if node.loop_mode != Animation.LOOP_NONE:
				out.append("%s (%s) would never end" % [label, node.animation])
		elif node.loop_mode != Animation.LOOP_LINEAR:
			out.append("%s (%s) would freeze after one cycle" % [label, node.animation])
	return out


## Every AnimationNodeAnimation in a generated tree, by where it sits.
func _clip_nodes(tree: AnimationTree) -> Dictionary[String, AnimationNodeAnimation]:
	var out: Dictionary[String, AnimationNodeAnimation] = {}
	var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return out
	for n: StringName in [AnimationTreeBuilder.NODE_HIT_CLIP, AnimationTreeBuilder.NODE_ACTION_CLIP]:
		out[String(n)] = root.get_node(n) as AnimationNodeAnimation
	var sm: AnimationNodeStateMachine = root.get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	if sm == null:
		return out
	for state: StringName in [AnimationTreeBuilder.STATE_JUMP_START, AnimationTreeBuilder.STATE_AIR,
			AnimationTreeBuilder.STATE_LAND, AnimationTreeBuilder.STATE_DEAD]:
		out[String(state)] = sm.get_node(state) as AnimationNodeAnimation
	var ground: AnimationNode = sm.get_node(AnimationTreeBuilder.STATE_GROUNDED)
	var plane: AnimationNodeBlendSpace2D = ground as AnimationNodeBlendSpace2D
	if plane != null:
		for i: int in range(plane.get_blend_point_count()):
			out["Grounded/%d" % i] = plane.get_blend_point_node(i) as AnimationNodeAnimation
	var line: AnimationNodeBlendSpace1D = ground as AnimationNodeBlendSpace1D
	if line != null:
		for i: int in range(line.get_blend_point_count()):
			out["Grounded/%d" % i] = line.get_blend_point_node(i) as AnimationNodeAnimation
	return out


## THE UPPER BODY LEAVES THE LEGS ALONE (DECISIONS #158). Two of the same character, their
## generated trees advanced in step, one firing the stow on its upper body: its legs must match
## the other's exactly while its arm does not. Watching one character walk could not tell: the
## sword clip moves the legs too, and a thigh swung as far with the filter off.
func _check_upper_body_filter(set: AnimationSet) -> void:
	var scene: PackedScene = load("res://game/characters/mannequin_f.glb") as PackedScene
	var skels: Array[Skeleton3D] = []
	var trees: Array[AnimationTree] = []
	var models: Array[Node3D] = []
	for k: int in range(2):
		var model: Node3D = scene.instantiate() as Node3D
		get_tree().root.add_child(model)
		var skel: Skeleton3D = null
		for n: Node in _walk_nodes(model):
			if n is Skeleton3D:
				skel = n
		skel.name = "Skeleton3D"
		var tree: AnimationTree = AnimationTreeBuilder.build(set)
		model.add_child(tree)
		tree.root_node = tree.get_path_to(skel.get_parent())
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		tree.active = true
		models.append(model)
		skels.append(skel)
		trees.append(tree)
	var upper_clip: AnimationNodeAnimation = (trees[0].tree_root as AnimationNodeBlendTree).get_node(
		AnimationTreeBuilder.NODE_UPPER_CLIP) as AnimationNodeAnimation
	AnimationTreeBuilder.apply_clip(upper_clip, set, ItemGrip.STOW)
	for t: AnimationTree in trees:
		t.advance(0.0)
	trees[0].set(AnimationTreeBuilder.P_UPPER_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var legs: float = 0.0
	var arm: float = 0.0
	for step: int in range(48):
		for t: AnimationTree in trees:
			t.advance(1.0 / 60.0)
		for bone: String in ["pelvis", "thigh_r", "calf_r", "thigh_l", "calf_l"]:
			var b: int = skels[0].find_bone(bone)
			legs = maxf(legs, rad_to_deg(skels[0].get_bone_pose_rotation(b).angle_to(skels[1].get_bone_pose_rotation(b))))
		var u: int = skels[0].find_bone("upperarm_r")
		arm = maxf(arm, rad_to_deg(skels[0].get_bone_pose_rotation(u).angle_to(skels[1].get_bone_pose_rotation(u))))
	_check(legs < 0.5 and arm > 20.0,
		"the stow on the UPPER BODY moves her arm (%.0f deg from the same body not stowing) and leaves her hips and legs as they were (%.2f deg)"
			% [arm, legs])
	for m: Node3D in models:
		m.free()


## ONE GRIP FOR ALL, AND SPOT FIXES (DECISIONS #257): an item placed once, the animations that need it
## nudged, and the nudges follow the universal grip when it moves.
func _run_universal_grip_tests() -> void:
	print("== animation: one grip for all, and spot fixes ==")
	var hand := Transform3D(Basis.from_euler(Vector3(0.3, -0.7, 0.2)), Vector3(0.4, 1.1, 0.1))
	var body := Basis.from_euler(Vector3(0.0, 0.5, 0.0))
	var g := ItemGrip.new()
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.08, 0.01), Vector3(60, 40, 30), false))
	g.entries.append(_grip_entry(AnimationSet.RUN, Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 0), true))
	_check(g.make_universal() == 1 and g.universal and g.entries.size() == 1, "Use One Grip For All: the run's own grip goes, the idle's stays")
	var idle: GripEntry = g.find(AnimationSet.IDLE)
	_check(g.resolve(AnimationSet.RUN) == idle, "and the run uses the universal grip")
	var fix: GripEntry = g.ensure(AnimationSet.RUN)
	_check(fix.relative and fix.in_hand(hand, body).is_equal_approx(idle.in_hand(hand, body)),
		"a grip made for the run is a spot fix, starting on the universal grip (nothing moves)")
	var nudged: Transform3D = hand * Transform3D(idle.in_hand(hand, body).basis.rotated(Vector3.UP, 0.4), idle.position + Vector3(0.0, 0.03, 0.0))
	fix.set_held(nudged, hand, body)
	_check((hand * fix.in_hand(hand, body)).is_equal_approx(nudged) and fix.position.is_equal_approx(Vector3(0.0, 0.03, 0.0)),
		"a drag on it keeps where it was put, stored as a nudge (%s)" % fix.position)
	idle.position += Vector3(0.02, 0.0, 0.0)
	var moved: Transform3D = g.resolve(AnimationSet.RUN).in_hand(hand, body)
	_check(moved.origin.is_equal_approx(idle.position + Vector3(0.0, 0.03, 0.0)),
		"move the universal grip and the spot fix moves with it (%s)" % moved.origin)
	idle.rotation_degrees += Vector3(0.0, 10.0, 0.0)
	_check(g.resolve(AnimationSet.RUN).in_hand(hand, body).basis.is_equal_approx((idle.in_hand(hand, body).basis * fix._own_basis()).orthonormalized()),
		"and turns with it")
	var walk: GripEntry = g.ensure(AnimationSet.WALK)
	_check(walk.relative and walk.position.is_zero_approx(), "every grip made after is a spot fix too")
	var plain := ItemGrip.new()
	plain.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.08, 0.01), Vector3(60, 40, 30), false))
	var own: GripEntry = plain.ensure(AnimationSet.RUN)
	_check(not own.relative and own.position.is_equal_approx(Vector3(0.0, 0.08, 0.01)),
		"without it, a new grip is its own, copied from the idle's (as before)")
	idle.position -= Vector3(0.02, 0.0, 0.0)


const GRIP_TEST_PATH: String = "user://grip_preview_test.tres"


## THE GRIP PREVIEW'S QUICK WAY (DECISIONS #259), driven as the Inspector drives it: type a Hold, Use This
## Grip For All, step to another animation and fix it; move the one grip and the fix follows.
func _run_grip_preview_tests() -> void:
	print("== animation: the grip preview's one grip for all ==")
	var item := HeldItem.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = Vector3(0.03, 0.6, 0.03)
	item.add_child(mesh)
	mesh.owner = item
	var packed := PackedScene.new()
	packed.pack(item)
	item.free()
	var g := ItemGrip.new()
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.08, 0.01), Vector3(60, 40, 30), false))
	g.entries.append(_grip_entry(AnimationSet.RUN, Vector3(0.2, 0.0, 0.0), Vector3(0, 90, 0), true))
	var prev: Node3D = (load("res://foundation/held/held_item_preview.gd") as GDScript).new() as Node3D
	prev.set("definition", load(CHARACTER_DEF))
	prev.set("item", packed)
	if FileAccess.file_exists(GRIP_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GRIP_TEST_PATH))
	g.resource_path = GRIP_TEST_PATH
	prev.set("grip", g)
	prev.set("beside", -1)
	add_child(prev)
	for i: int in range(6):
		await get_tree().process_frame
	prev.set("animation", String(AnimationSet.RUN))
	await get_tree().process_frame
	var want := Vector3(0.01, 0.07, 0.02)
	prev.set("hold_position", want)
	await get_tree().process_frame
	_check((prev.get("hold_position") as Vector3).is_equal_approx(want), "a typed Hold puts the item there in the hand (%s)" % prev.get("hold_position"))
	prev.call("use_this_for_all")
	await get_tree().process_frame
	_check(g.universal and g.entries.size() == 1 and g.entries[0].animation == AnimationSet.IDLE
		and g.entries[0].position.is_equal_approx(want), "Use This Grip For All: it is the one grip now, the others gone")
	prev.set("animation", "interact")
	await get_tree().process_frame
	_check((prev.get("hold_position") as Vector3).is_equal_approx(want), "another animation uses it as it is")
	prev.set("hold_position", want + Vector3(0.0, 0.02, 0.0))
	await get_tree().process_frame
	var fix: GripEntry = g.find(&"interact")
	_check(fix != null and fix.relative and fix.position.is_equal_approx(Vector3(0.0, 0.02, 0.0)), "a Hold typed there is a fix on the one grip (a nudge %s)" % (fix.position if fix != null else Vector3.ZERO))
	prev.set("animation", String(AnimationSet.IDLE))
	await get_tree().process_frame
	prev.set("hold_position", want + Vector3(0.03, 0.0, 0.0))
	prev.set("animation", "interact")
	await get_tree().process_frame
	_check((prev.get("hold_position") as Vector3).is_equal_approx(want + Vector3(0.03, 0.02, 0.0)), "move the one grip and the fix follows (%s)" % prev.get("hold_position"))
	# SAVED WITH THE SCENE (DECISIONS #260): nothing is written while it is moved; the scene's save writes it.
	_check(not FileAccess.file_exists(GRIP_TEST_PATH) and bool(prev.call("grip_unsaved")),
		"every move above wrote nothing: the grip waits for the scene's save")
	prev.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var written: ItemGrip = ResourceLoader.load(GRIP_TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemGrip 		if FileAccess.file_exists(GRIP_TEST_PATH) else null
	_check(written != null and written.universal and written.entries.size() == 2 and not bool(prev.call("grip_unsaved")),
		"saving the scene writes it: one grip and its fix")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GRIP_TEST_PATH))
	prev.queue_free()
	await get_tree().process_frame
