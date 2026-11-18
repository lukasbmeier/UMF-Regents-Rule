class_name MotionLayer extends Node
## PLAYS A MOVE MADE IN CODE (`MotionMove`) on a character, over the clip it is playing: the whole figure turned about
## its hips (its `model` node: lifted, spun, tipped, banked, squashed), its bones bent (`MotionBones`, put first among
## its skeleton's modifiers), and, if asked, its body carried along its facing (`carry`).
##
## AFTER THE DRIVER, EACH FRAME: the game's `AnimationDriverComponent` sets the model's GLOBAL rotation every frame (its
## facing, eased round), which would undo a turn put on any node above it. So this runs after it (`process_priority`)
## and puts its turn on the model's own transform, from where the driver left it: the model's place and size are put
## back first (the driver sets only its rotation), so nothing builds up from frame to frame.
##
##   var layer := MotionLayer.attach(actor, actor.model, actor.skeleton)
##   layer.play(load("res://game/regents/motion/moves/leaping_strike.tres"), actor.facing(), foe.position)
##
## `enabled` false shows the clip alone (the lab's comparison): nothing is turned or bent (the body is still carried,
## so the two go as far).
## Presentation only (hard rule 11): it shows what happened and decides nothing. In the game the body's travel is the
## server's (a lunge, a push): leave `carry` off there.

## A move started and a move ended (by itself or `stop`).
signal started(move: MotionMove)
signal ended(move: MotionMove)

## On: moves show whole. Off: the clips alone (no channel: nothing turned, bent or lifted by code), as far.
var enabled: bool = true:
	set(v):
		enabled = v
		if not v:
			_apply_rest()
## Carry the body along the move's travel (a lab, a showcase; never in the game, where the server moves bodies).
var carry: bool = true
## How fast its clock runs (1: real time).
var speed: float = 1.0

var body: Node3D = null
var model: Node3D = null
var skeleton: Skeleton3D = null
var bones: MotionBones = null

var move: MotionMove = null
## Seconds into the move; the way the body faced as it began (world, flat); where it reaches (world; INF: nowhere).
var t: float = 0.0
var facing: Vector3 = Vector3.FORWARD
var target: Vector3 = Vector3.INF
## The pose now (the last frame's), and the travel already carried.
var pose: MotionMove.Pose = null
var _carried: float = 0.0
var _carried_root: Vector3 = Vector3.ZERO
## The skeleton's size in the world (a clip's root moves in its units).
var _skel_scale: Vector3 = Vector3.ONE
## The model's own place and size as it was given (the driver never changes them; this puts them back each frame).
var _model_pos: Vector3 = Vector3.ZERO
var _model_scale: Vector3 = Vector3.ONE
## Set by the suite: it steps the layer by hand.
var manual: bool = false


## A layer on `body`, turning its `the_model` and bending `skel` (null: the whole body only).
static func attach(on_body: Node3D, the_model: Node3D, skel: Skeleton3D) -> MotionLayer:
	var l := MotionLayer.new()
	l.name = "MotionLayer"
	# After the animation driver (it turns the model each frame) and anything else at the default.
	l.process_priority = 1000
	l.body = on_body
	l.model = the_model
	if the_model != null:
		l._model_pos = the_model.position
		l._model_scale = the_model.scale
	l.skeleton = skel
	if skel != null:
		if skel.is_inside_tree():
			l._skel_scale = skel.global_transform.basis.get_scale()
		l.bones = MotionBones.new()
		l.bones.name = "MotionBones"
		skel.add_child(l.bones)
		skel.move_child(l.bones, 0)
	on_body.add_child(l)
	return l


## Play `m` from its start: the body faces `toward` (world, flat), the arm reaches for `at`.
func play(m: MotionMove, toward: Vector3, at: Vector3 = Vector3.INF) -> void:
	if move != null:
		ended.emit(move)
	move = m
	t = 0.0
	_carried = 0.0
	_carried_root = Vector3.ZERO
	var flat := Vector3(toward.x, 0.0, toward.z)
	facing = flat.normalized() if flat.length_squared() > 0.000001 else Vector3.FORWARD
	target = at
	started.emit(m)
	_apply(0.0)


## Let the move go now: the figure stands as its clip has it.
func stop() -> void:
	if move == null:
		return
	var m: MotionMove = move
	move = null
	_apply_rest()
	if bones != null:
		bones.move = null
	ended.emit(m)


## Is a move playing?
func playing() -> bool:
	return move != null


## Its share run, 0 to 1 (1 when none plays).
func progress() -> float:
	return clampf(t / maxf(move.length_s, 0.001), 0.0, 1.0) if move != null else 1.0


func _process(delta: float) -> void:
	if not manual:
		step(delta)


## One frame of it (`delta` real seconds, times `speed`).
func step(delta: float) -> void:
	if move == null:
		return
	t += delta * speed
	if t >= move.length_s:
		_apply(move.length_s)
		stop()
		return
	_apply(t)


func _apply(at_s: float) -> void:
	pose = move.at(at_s)
	# The clips' root: its height lifts the turning point (a flip in the air turns about the hips up there); its travel
	# along the ground is carried below.
	var root: Vector3 = move.root_at(at_s)
	var pivot: float = move.pivot_m + root.y * _skel_scale.y
	if bones != null:
		bones.move = move
		bones.t = at_s
	if not enabled:
		_apply_rest()
	else:
		if model != null and body != null:
			_apply_rest()
			# The turn is in the body's frame (its place, unturned): taken to the world about the body, then put on the
			# model as the driver left it.
			var at_body := Transform3D(Basis.IDENTITY, body.global_position)
			var turn_w: Transform3D = at_body * figure_transform(pose, facing, pivot) * at_body.affine_inverse()
			model.global_transform = turn_w * model.global_transform
		if bones != null:
			bones.pose = pose
			var turn: Basis = figure_transform(pose, facing, move.pivot_m).basis.orthonormalized()
			bones.body_up = turn * Vector3.UP
			bones.body_forward = turn * facing
			bones.target = target
	if carry and body != null:
		# Carried as an outside move (a showcase actor takes it as a teleport): along the facing it began with.
		var d: float = pose.travel_m - _carried
		_carried = pose.travel_m
		# A clip's root travel, from its skeleton's frame (+z the way it faces, +x its left) to the world.
		var flat_root := Vector3(root.x, 0.0, root.z)
		var dr: Vector3 = flat_root - _carried_root
		_carried_root = flat_root
		var left: Vector3 = Vector3.UP.cross(facing)
		body.position += facing * (d + dr.z * _skel_scale.z) + left * (dr.x * _skel_scale.x)


func _apply_rest() -> void:
	if model != null:
		model.position = _model_pos
		model.scale = _model_scale
	if bones != null:
		bones.pose = null


## THE WHOLE FIGURE'S TURN for pose `p` (in the body's frame: its place, unturned), the body facing
## `toward`: spun round its up, tipped forward about its right, banked about its forward, squashed along its up; all
## about the point `pivot` m over the feet, and lifted. A pose at rest is no turn at all.
static func figure_transform(p: MotionMove.Pose, toward: Vector3, pivot: float) -> Transform3D:
	var fwd := Vector3(toward.x, 0.0, toward.z)
	fwd = fwd.normalized() if fwd.length_squared() > 0.000001 else Vector3.FORWARD
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	# Tipped forward: the head toward the facing (about the right, a negative turn); banked right: the head toward
	# the right (about the forward, a positive turn).
	var lean: Basis = Basis(fwd, p.bank) * Basis(right, -p.tip)
	var s: float = clampf(p.squash, -0.5, 0.5)
	var squash := Basis.from_scale(Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5))
	# Turned about the hips; squashed about the feet (a landing presses down, it does not lift the feet).
	var turn: Basis = Basis(Vector3.UP, p.spin) * lean
	var piv := Vector3(0.0, pivot, 0.0)
	return Transform3D(turn * squash, piv + Vector3(0.0, p.lift_m, 0.0) - turn * piv)
