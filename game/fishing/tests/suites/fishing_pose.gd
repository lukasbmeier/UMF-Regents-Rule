extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fishing_pose` suite (`-- --only=fishing_pose` runs it alone), run because shared/game.json
## lists fishing. The fishing half of tests/suites/pose.gd (the original, run on the angler and the lakeside). Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	await _run_pose_tests()




## DOES THE CHARACTER STAND UP? Every other animation test can pass while the character animates
## flawlessly lying on its back — which is exactly what shipped: the FBX library's conversion
## from Z-up centimetres lived on a node, that node was dropped when the tracks were re-addressed,
## and the result was an upright-looking pose graph driving a body face-down in the floor with
## its pelvis 9 mm off the ground.
##
## So this measures the posed skeleton in metres, for clips out of BOTH libraries: a head above
## a pelvis above a pair of feet, at human height, in this game's units.
func _run_pose_tests() -> void:
	print("== animation: the character stands up ==")
	var set: AnimationSet = load(FISHER_SET) as AnimationSet
	var model_scene: PackedScene = load("res://game/characters/mannequin_f.glb") as PackedScene
	if set == null or model_scene == null:
		_check(false, "the fisher set and the default model load")
		return
	for semantic: StringName in [AnimationSet.IDLE, AnimationSet.WALK, AnimationSet.RUN,
			AnimationSet.JUMP_START, AnimationSet.INTERACT]:
		var clip: StringName = set.anim_name(semantic)
		await _check_pose(model_scene, set, semantic, clip)
	# AND EVERY LOOK THE GAME DRESSES SOMEONE IN. Each is assembled from separate pieces onto one
	# skeleton (ModularCharacter), so a piece bound to the wrong bones, or a head scaled unlike its
	# clothes, is a character that does not stand up — measured the same way.
	for look: PackedScene in _shipped_looks():
		print("   look %s" % look.resource_path.get_file())
		for semantic: StringName in [AnimationSet.IDLE, AnimationSet.RUN, AnimationSet.INTERACT]:
			await _check_pose(look, set, semantic, set.anim_name(semantic))


func _check_pose(model_scene: PackedScene, set: AnimationSet, semantic: StringName,
		clip: StringName) -> void:
	var model: Node3D = model_scene.instantiate() as Node3D
	get_tree().root.add_child(model)
	var skel: Skeleton3D = null
	for n: Node in _walk_nodes(model):
		if n is Skeleton3D:
			skel = n
	if skel == null:
		_check(false, "the model has a skeleton")
		model.queue_free()
		return

	# One clip, nothing else: no blending, no state machine, so what is measured is the clip.
	var tree := AnimationTree.new()
	for lib_name: StringName in set.libraries:
		tree.add_animation_library(lib_name, set.libraries[lib_name])
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	tree.tree_root = node
	model.add_child(tree)
	tree.root_node = tree.get_path_to(skel.get_parent())
	tree.active = true

	# SAMPLE ACROSS THE CLIP, not at one arbitrary instant. "Four frames in" lands at a different
	# point of every clip — `Jump_Start` plays at x4.17 and four frames put it deep in its crouch,
	# where the head genuinely is below human height — so the measurement flickered against its
	# own threshold run to run. What the check means is "this clip is a human standing up", and
	# the honest way to ask that is: upright at EVERY sample, human-sized at its tallest.
	# Three properties, each asked at the moment it means something. A run lifts a foot 0.4 m and
	# a take-off crouches, so neither "feet down always" nor "upright always" is true of a
	# correct clip — asking those of one arbitrary frame is what made this flicker.
	var tallest: float = -INF          # scale: is this a person or a model in centimetres?
	var pelvis_at_tallest: float = 0.0 # uprightness, asked where the character is standing up
	var foot_at_tallest: float = 0.0
	var planted: float = INF           # the PLANTED foot: does it ever reach the ground?
	for i: int in range(12):
		for f: int in range(3):
			await get_tree().process_frame
		var head: float = _bone_y(skel, "Head")
		var foot: float = _bone_y(skel, "foot_l")
		planted = minf(planted, absf(foot))
		if head > tallest:
			tallest = head
			pelvis_at_tallest = _bone_y(skel, "pelvis")
			foot_at_tallest = foot
	print("   %-18s %-16s tallest head %.2f (pelvis %.2f, foot %.2f)  planted foot %.2f"
		% [semantic, clip, tallest, pelvis_at_tallest, foot_at_tallest, planted])
	_check(tallest > pelvis_at_tallest + 0.4 and pelvis_at_tallest > foot_at_tallest + 0.4,
		"%s stands up at its tallest: head %.2f over pelvis %.2f over foot %.2f"
			% [clip, tallest, pelvis_at_tallest, foot_at_tallest])
	_check(tallest > 1.2 and tallest < 2.0,
		"%s is human-sized, in metres: head reaches %.2f m" % [clip, tallest])
	_check(planted < 0.35,
		"%s puts a foot on the ground the entity stands on (closest %.2f m)" % [clip, planted])
	model.queue_free()
	await get_tree().process_frame
