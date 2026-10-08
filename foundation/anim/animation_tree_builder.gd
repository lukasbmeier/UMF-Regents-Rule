class_name AnimationTreeBuilder
## Generates the `AnimationTree` for an `AnimationSet`. NOBODY HAND-AUTHORS THE GRAPH
## (hard rule 11, `docs/ANIMATION_SPEC.md` §4).
##
## A hand-built graph is a second place where "what the character can do" is written down, and
## it drifts from the first one the moment a clip is renamed. Here the set is the only source:
## the same six semantic names produce the same graph for a knight, a chicken or a fishing rod,
## and a character that is missing a clip gets the fallback chain rather than a T-pose.
##
## THE GRAPH
##   output <- action(OneShot) <- hit(OneShot) <- upper(OneShot) <- pose(Blend2) <- body(StateMachine)
##     body: Grounded  BlendSpace1D over normalised speed [idle, walk, run]
##           JumpStart -> Air -> Land -> Grounded, and anything -> Dead
##     pose:   a clip HELD over the body — looping, or frozen at a point of its length that a
##             value drives (how far a rod is heaved, a bow drawn) — blended in by weight
##             (pose_clip -> pose_scale(TimeScale) -> pose_seek(TimeSeek) -> pose input 1)
##     upper:  a one-shot on the UPPER BODY only (`upper_body`): drawing or stowing an item while
##             the legs keep walking (DECISIONS #158)
##     hit:    a reaction fired over whatever the body is doing
##     action: interact / an ability, same idea, layered last so it wins
##
## The driver writes `parameters/body/Grounded/blend_position`, travels the state machine
## through `parameters/body/playback`, fires the two one-shots and holds the pose (its blend, its
## scale, its seek). Those parameter paths are the whole interface, and
## `AnimationDriverComponent` is the only thing that touches them.

const STATE_GROUNDED: StringName = &"Grounded"
const STATE_JUMP_START: StringName = &"JumpStart"
const STATE_AIR: StringName = &"Air"
const STATE_LAND: StringName = &"Land"
const STATE_DEAD: StringName = &"Dead"
## The state machine's implicit entry node.
const STATE_START: StringName = &"Start"

## Every travel the driver can ask for, and therefore every transition the graph must carry
## DIRECTLY. `travel()` routes through whatever is shortest, and with no direct route it picks
## any two-hop one: a grounded character whose take-off was aborted once reached the ground by
## way of the DEATH state, because "JumpStart -> Dead -> Grounded" was as short as the intended
## route. A complete table is cheaper than reasoning about which detours are acceptable.
const TRAVELS: Dictionary[StringName, Array] = {
	STATE_GROUNDED: [STATE_JUMP_START, STATE_AIR, STATE_LAND, STATE_DEAD],
	STATE_JUMP_START: [STATE_GROUNDED, STATE_AIR, STATE_LAND, STATE_DEAD],
	STATE_AIR: [STATE_GROUNDED, STATE_JUMP_START, STATE_LAND, STATE_DEAD],
	STATE_LAND: [STATE_GROUNDED, STATE_JUMP_START, STATE_AIR, STATE_DEAD],
	STATE_DEAD: [STATE_GROUNDED],
}

const NODE_BODY: StringName = &"body"
const NODE_HIT: StringName = &"hit"
const NODE_HIT_CLIP: StringName = &"hit_clip"
const NODE_ACTION: StringName = &"action"
const NODE_ACTION_CLIP: StringName = &"action_clip"
const NODE_POSE: StringName = &"pose"
const NODE_POSE_CLIP: StringName = &"pose_clip"
const NODE_POSE_SCALE: StringName = &"pose_scale"
const NODE_POSE_SEEK: StringName = &"pose_seek"
const NODE_UPPER: StringName = &"upper"
const NODE_UPPER_CLIP: StringName = &"upper_clip"
const NODE_OUTPUT: StringName = &"output"

const P_PLAYBACK: String = "parameters/body/playback"
const P_BLEND: String = "parameters/body/Grounded/blend_position"
const P_HIT_REQUEST: String = "parameters/hit/request"
const P_HIT_ACTIVE: String = "parameters/hit/active"
const P_ACTION_REQUEST: String = "parameters/action/request"
const P_ACTION_ACTIVE: String = "parameters/action/active"
const P_POSE_BLEND: String = "parameters/pose/blend_amount"
const P_POSE_SCALE: String = "parameters/pose_scale/scale"
const P_POSE_SEEK: String = "parameters/pose_seek/seek_request"
const P_UPPER_REQUEST: String = "parameters/upper/request"
const P_UPPER_ACTIVE: String = "parameters/upper/active"

## The bones the UPPER one-shot moves on the humanoid skeleton, when a set does not name its own
## (`AnimationSet.upper_body_filter`): the chest up, both arms and every finger. The hips and legs
## keep whatever the body is doing.
const UPPER_SPINE: Array[StringName] = [&"spine_02", &"spine_03", &"neck_01", &"Head"]
const UPPER_ARM: Array[String] = ["clavicle", "upperarm", "lowerarm", "hand"]
const UPPER_FINGERS: Array[String] = ["index", "middle", "ring", "pinky", "thumb"]

## The locomotion blend's points, by semantic name, in the order `_build_ground` adds them: the
## line (a set that does not strafe) and the plane (one that does). What
## `AnimationDriverComponent.semantic_weights` reads the blend back by.
const LINE_POINTS: Array[StringName] = [AnimationSet.IDLE, AnimationSet.WALK, AnimationSet.RUN,
	AnimationSet.SPRINT]
const PLANE_POINTS: Array[StringName] = [AnimationSet.IDLE, AnimationSet.WALK,
	AnimationSet.WALK_BACK, AnimationSet.WALK_LEFT, AnimationSet.WALK_RIGHT, AnimationSet.RUN,
	AnimationSet.RUN_BACK, AnimationSet.RUN_LEFT, AnimationSet.RUN_RIGHT, AnimationSet.SPRINT]
## Where "walking" sits on the 0..1 speed axis when the config is unavailable.
const DEFAULT_WALK_RATIO: float = 0.15
const DEFAULT_RUN_RATIO: float = 0.625


## Build a tree for `set`. Returns null (and pushes an error) if the set cannot drive one —
## a caller that ignores the return value would otherwise ship a character stuck in a T-pose.
## `cfg` is only read for the walk/run speed ratio; tests pass their own.
static func build(set: AnimationSet, cfg: MovementConfig = null) -> AnimationTree:
	if set == null:
		push_error("AnimationTreeBuilder: no AnimationSet")
		return null
	var missing: Array[StringName] = set.missing_required()
	if not missing.is_empty():
		push_error("AnimationTreeBuilder: AnimationSet is missing %s" % str(missing))
		return null

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	for lib_name: StringName in set.libraries:
		var lib: AnimationLibrary = set.libraries[lib_name]
		if lib != null:
			tree.add_animation_library(lib_name, lib)

	var root := AnimationNodeBlendTree.new()
	root.add_node(NODE_BODY, _build_body(set, cfg if cfg != null else MovementConfig.shared()),
		Vector2(-360.0, 0.0))
	# THE POSE, held over the body. Starts on the idle clip at weight 0 — nothing — until the driver
	# is asked to hold one; a scale of 0 and a seek every frame is how a value scrubs a clip.
	root.add_node(NODE_POSE_CLIP, _clip_node(set, AnimationSet.IDLE, true), Vector2(-540.0, 260.0))
	root.add_node(NODE_POSE_SCALE, AnimationNodeTimeScale.new(), Vector2(-400.0, 260.0))
	root.add_node(NODE_POSE_SEEK, AnimationNodeTimeSeek.new(), Vector2(-280.0, 260.0))
	root.add_node(NODE_POSE, AnimationNodeBlend2.new(), Vector2(-200.0, 0.0))
	# THE UPPER BODY: a one-shot over the pose that moves only `upper_body(set)`. Starts on the
	# interact clip, like the action, until the driver points it at one.
	root.add_node(NODE_UPPER_CLIP, _clip_node(set, AnimationSet.INTERACT), Vector2(-200.0, 140.0))
	root.add_node(NODE_UPPER, _upper_shot(set), Vector2(-120.0, 0.0))
	root.add_node(NODE_HIT_CLIP, _clip_node(set, AnimationSet.HIT), Vector2(-180.0, 140.0))
	root.add_node(NODE_HIT, _one_shot(set, AnimationSet.HIT), Vector2(-40.0, 0.0))
	root.add_node(NODE_ACTION_CLIP, _clip_node(set, AnimationSet.INTERACT), Vector2(140.0, 140.0))
	root.add_node(NODE_ACTION, _one_shot(set, AnimationSet.INTERACT), Vector2(300.0, 0.0))
	root.connect_node(NODE_POSE_SCALE, 0, NODE_POSE_CLIP)
	root.connect_node(NODE_POSE_SEEK, 0, NODE_POSE_SCALE)
	# Blend2 input 0 is the body, input 1 the pose; OneShot input 0 is the pass-through, input 1
	# is the clip it fires.
	root.connect_node(NODE_POSE, 0, NODE_BODY)
	root.connect_node(NODE_POSE, 1, NODE_POSE_SEEK)
	root.connect_node(NODE_UPPER, 0, NODE_POSE)
	root.connect_node(NODE_UPPER, 1, NODE_UPPER_CLIP)
	root.connect_node(NODE_HIT, 0, NODE_UPPER)
	root.connect_node(NODE_HIT, 1, NODE_HIT_CLIP)
	root.connect_node(NODE_ACTION, 0, NODE_HIT)
	root.connect_node(NODE_ACTION, 1, NODE_ACTION_CLIP)
	root.connect_node(NODE_OUTPUT, 0, NODE_ACTION)

	tree.tree_root = root
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	return tree


## Where each gait falls on the normalised speed axis. The driver divides the body's speed by
## `sprint_speed`, so a blend point at `walk_speed / sprint_speed` is reached exactly when the
## player is walking — which is what stops the feet from skating.
static func walk_ratio(cfg: MovementConfig) -> float:
	var c: MovementConfig = cfg if cfg != null else MovementConfig.shared()
	if c == null or c.sprint_speed <= 0.0:
		return DEFAULT_WALK_RATIO
	return clampf(c.walk_speed / c.sprint_speed, 0.02, 0.95)


static func run_ratio(cfg: MovementConfig) -> float:
	var c: MovementConfig = cfg if cfg != null else MovementConfig.shared()
	if c == null or c.sprint_speed <= 0.0:
		return DEFAULT_RUN_RATIO
	return clampf(c.run_speed / c.sprint_speed, 0.05, 0.99)


## True when the tree built for this set takes a Vector2 blend position rather than a float.
static func is_strafing(set: AnimationSet) -> bool:
	return set != null and set.can_strafe()


## The locomotion blend. One forward axis when the set has no strafe clips; a plane of gait rings
## when it has — the character then keeps facing the camera and moves its feet sideways, which is
## the difference between strafing and sliding like a chess piece.
static func _build_ground(set: AnimationSet, cfg: MovementConfig) -> AnimationRootNode:
	var w: float = walk_ratio(cfg)
	var r: float = run_ratio(cfg)
	if not is_strafing(set):
		var line := AnimationNodeBlendSpace1D.new()
		line.min_space = 0.0
		line.max_space = 1.0
		line.snap = 0.02
		# Named points: Godot 4.7 warns on unnamed ones, and a name is what the editor shows
		# when somebody opens the generated tree to see what it did.
		line.add_blend_point(_clip_node(set, AnimationSet.IDLE, true), 0.0, -1, "idle")
		line.add_blend_point(_clip_node(set, AnimationSet.WALK, true), w, -1, "walk")
		line.add_blend_point(_clip_node(set, AnimationSet.RUN, true), r, -1, "run")
		line.add_blend_point(_clip_node(set, AnimationSet.SPRINT, true), 1.0, -1, "sprint")
		return line

	# x is sideways, y is forwards, both in units of sprint speed. The rings sit at the speeds
	# the model actually produces, sideways and backwards included (DECISIONS #100), so the
	# blend position lands ON a clip rather than between two that mean different things.
	var strafe_m: float = cfg.strafe_speed_mult if cfg != null else 1.0
	var back_m: float = cfg.back_speed_mult if cfg != null else 1.0
	var plane := AnimationNodeBlendSpace2D.new()
	plane.min_space = Vector2(-1.0, -1.0)
	plane.max_space = Vector2(1.0, 1.0)
	plane.snap = Vector2(0.02, 0.02)
	plane.add_blend_point(_clip_node(set, AnimationSet.IDLE, true), Vector2.ZERO, -1, "idle")
	plane.add_blend_point(_clip_node(set, AnimationSet.WALK, true), Vector2(0.0, w), -1, "walk")
	plane.add_blend_point(_clip_node(set, AnimationSet.WALK_BACK, true), Vector2(0.0, -w * back_m), -1, "walk_back")
	plane.add_blend_point(_clip_node(set, AnimationSet.WALK_LEFT, true), Vector2(-w * strafe_m, 0.0), -1, "walk_left")
	plane.add_blend_point(_clip_node(set, AnimationSet.WALK_RIGHT, true), Vector2(w * strafe_m, 0.0), -1, "walk_right")
	plane.add_blend_point(_clip_node(set, AnimationSet.RUN, true), Vector2(0.0, r), -1, "run")
	plane.add_blend_point(_clip_node(set, AnimationSet.RUN_BACK, true), Vector2(0.0, -r * back_m), -1, "run_back")
	plane.add_blend_point(_clip_node(set, AnimationSet.RUN_LEFT, true), Vector2(-r * strafe_m, 0.0), -1, "run_left")
	plane.add_blend_point(_clip_node(set, AnimationSet.RUN_RIGHT, true), Vector2(r * strafe_m, 0.0), -1, "run_right")
	plane.add_blend_point(_clip_node(set, AnimationSet.SPRINT, true), Vector2(0.0, 1.0), -1, "sprint")
	return plane


# --- pieces ------------------------------------------------------------------------------

static func _build_body(set: AnimationSet, cfg: MovementConfig) -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	sm.add_node(STATE_GROUNDED, _build_ground(set, cfg), Vector2(300.0, 100.0))
	sm.add_node(STATE_JUMP_START, _clip_node(set, AnimationSet.JUMP_START), Vector2(500.0, 20.0))
	# (the ground node above is the locomotion blend, 1D or 2D depending on the set)
	sm.add_node(STATE_AIR, _clip_node(set, AnimationSet.JUMP_LOOP, true), Vector2(680.0, 20.0))
	sm.add_node(STATE_LAND, _clip_node(set, AnimationSet.JUMP_LAND), Vector2(680.0, 180.0))
	sm.add_node(STATE_DEAD, _clip_node(set, AnimationSet.DEATH), Vector2(300.0, 280.0))

	# A state machine with no transition out of its implicit Start node plays nothing until
	# something calls travel(); entering on Grounded means a character animates from frame one.
	_link(sm, STATE_START, STATE_GROUNDED, 0.0, true)

	# The two that run themselves: the take-off hands over at its own end, and the landing hands
	# back. These are added first so the table below does not overwrite them.
	_link(sm, STATE_JUMP_START, STATE_AIR, 0.1, true)
	_link(sm, STATE_LAND, STATE_GROUNDED, 0.12, true)

	# Everything the driver can ask for, directly. See TRAVELS.
	for from: StringName in TRAVELS:
		for to: StringName in TRAVELS[from]:
			if not sm.has_transition(from, to):
				_link(sm, from, to, 0.12)
	return sm


## `auto` transitions fire themselves when the clip ends; the rest wait for `travel()`.
static func _link(sm: AnimationNodeStateMachine, from: StringName, to: StringName,
		xfade: float, auto: bool = false) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	if auto:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	sm.add_transition(from, to, t)


## Point `node` at the set's `semantic` clip, CARRYING THAT CLIP'S OWN TIMING WITH IT. Returns
## false when the set cannot name a clip, so a caller can leave the node alone.
##
## The timing is not only the speed. Turning on `use_custom_timeline` also makes the node override
## the animation's own loop with its `loop_mode`, and that defaults to LOOP_NONE: a speed-scaled
## walk cycle then plays exactly once and freezes on its last frame, which for a locomotion loop
## is indistinguishable from its first (DECISIONS #103). Every locomotion clip is speed-scaled, so
## every one of them froze after a second while idle — the one clip left at x1.0 — kept going.
##
## Swapping a node's animation therefore goes THROUGH HERE rather than assigning `animation`
## directly, or the node keeps the timeline of the clip it used to hold.
static func apply_clip(node: AnimationNodeAnimation, set: AnimationSet, semantic: StringName,
		looping: bool = false) -> bool:
	if node == null or set == null:
		return false
	var ref: AnimationClipRef = set.clip(semantic)
	if ref == null:
		return false
	node.animation = ref.anim_name
	var loops: bool = looping or ref.loop
	if loops:
		_ensure_loop(set, ref.anim_name)
	# A clip authored for a different character rarely fits this game's timings — Quaternius'
	# take-off runs 1.33 s against a 0.8 s jump, so the character would still be crouching as it
	# landed. `speed_scale` is played through a custom timeline, which is how a state-machine
	# state can be sped up at all (nothing in a state machine takes a TimeScale node).
	var length: float = _length_of(set, ref.anim_name)
	if not is_equal_approx(ref.speed_scale, 1.0) and ref.speed_scale > 0.0 and length > 0.0:
		node.use_custom_timeline = true
		node.stretch_time_scale = true
		node.timeline_length = length / ref.speed_scale
		# The override above, restated. A one-shot (a landing, a death) must still NOT loop, or
		# the `at end` transition it hands over on never fires.
		node.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	else:
		# An unscaled clip plays on its own terms; a node being re-pointed must not keep the
		# previous clip's length, which would stretch this one to fit it.
		node.use_custom_timeline = false
	return true


static func _clip_node(set: AnimationSet, semantic: StringName,
		looping: bool = false) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	apply_clip(node, set, semantic, looping)
	return node


## Length in seconds of the clip `set` names `semantic`, or 0 when it names none.
static func clip_length(set: AnimationSet, semantic: StringName) -> float:
	var ref: AnimationClipRef = set.clip(semantic) if set != null else null
	return _length_of(set, ref.anim_name) if ref != null else 0.0


## The clip `set` names `semantic` (as `AnimationSet.clip` finds it), or null when it names none:
## for a reader of its tracks (a held item's fist, `GripFit.fist_pose`).
static func clip_animation(set: AnimationSet, semantic: StringName) -> Animation:
	var ref: AnimationClipRef = set.clip(semantic) if set != null else null
	return _animation_of(set, ref.anim_name) if ref != null else null


## Length of a clip in its library, or 0 if it is not there.
static func _length_of(set: AnimationSet, full_name: StringName) -> float:
	var anim: Animation = _animation_of(set, full_name)
	return anim.length if anim != null else 0.0


## A clip in its library ("library/clip"), or null if it is not there.
static func _animation_of(set: AnimationSet, full_name: StringName) -> Animation:
	var s: String = String(full_name)
	var slash: int = s.find("/")
	var lib_name: StringName = StringName(s.substr(0, slash)) if slash >= 0 else &""
	var clip_name: StringName = StringName(s.substr(slash + 1)) if slash >= 0 else full_name
	var lib: AnimationLibrary = set.libraries.get(lib_name, null)
	if lib == null or not lib.has_animation(clip_name):
		return null
	return lib.get_animation(clip_name)


## Locomotion clips have to loop. Godot's importers set that from a `_Loop` suffix, which every
## Quaternius clip carries — but a library exported by hand may not, and a locomotion blend of
## non-looping clips freezes on the last frame a second after the character starts walking.
## Fixed here rather than trusted, because the failure is silent and looks like a hang.
static func _ensure_loop(set: AnimationSet, full_name: StringName) -> void:
	var s: String = String(full_name)
	var slash: int = s.find("/")
	var lib_name: StringName = StringName(s.substr(0, slash)) if slash >= 0 else &""
	var clip_name: StringName = StringName(s.substr(slash + 1)) if slash >= 0 else full_name
	var lib: AnimationLibrary = set.libraries.get(lib_name, null)
	if lib == null or not lib.has_animation(clip_name):
		return
	var anim: Animation = lib.get_animation(clip_name)
	if anim.loop_mode == Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_LINEAR


## The bones an upper-body one-shot moves: the set's `upper_body_filter`, else the humanoid's chest,
## arms and fingers (UPPER_SPINE, UPPER_ARM, UPPER_FINGERS).
static func upper_body(set: AnimationSet) -> Array[StringName]:
	if set != null and not set.upper_body_filter.is_empty():
		return set.upper_body_filter.duplicate()
	var out: Array[StringName] = UPPER_SPINE.duplicate()
	for side: String in ["_l", "_r"]:
		for b: String in UPPER_ARM:
			out.append(StringName(b + side))
		for f: String in UPPER_FINGERS:
			for j: String in ["_01", "_02", "_03"]:
				out.append(StringName(f + j + side))
	return out


## The upper-body one-shot: filtered to `upper_body(set)`, so the tracks it plays move those bones
## and everything else passes through from below.
static func _upper_shot(set: AnimationSet) -> AnimationNodeOneShot:
	var one: AnimationNodeOneShot = _one_shot(set, AnimationSet.INTERACT)
	one.filter_enabled = true
	for bone: StringName in upper_body(set):
		one.set_filter_path(NodePath("Skeleton3D:%s" % bone), true)
	return one


static func _one_shot(set: AnimationSet, semantic: StringName) -> AnimationNodeOneShot:
	var one := AnimationNodeOneShot.new()
	var ref: AnimationClipRef = set.clip(semantic)
	var blend: float = ref.blend_time if ref != null else 0.15
	one.fadein_time = blend
	one.fadeout_time = blend
	one.break_loop_at_end = false
	return one
