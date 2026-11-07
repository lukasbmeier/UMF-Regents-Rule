class_name FloatingTool extends Node3D
## A TOOL SWINGING ON ITS OWN ON A MINIGAME'S 3D STAGE (Luke's play, 2026-11-06: "consistent with hammer floating, pick
## floating, axe floating, etc since we know we as the character are doing the action"). No character on the stage: the
## player's own character is the one working. PRESENTATION ONLY: the stage tells it to swing when the round's model
## says a blow landed.
##
## It rests in its REST pose and swings to its HIT pose: two transforms of the tool's handle end (the tool scenes put
## the hand at the origin and the handle along +Y, their `Head` marker at the head). A stage takes both from two
## markers in its scene, so a designer moves them in the editor; `aim` shifts both so the head lands on a point.

## How long the blow takes to come down, to go back up, and how far back a jarred blow bounces (0-1 of the way).
@export var fall_s: float = 0.08
@export var rise_s: float = 0.28
@export var bounce: float = 0.45

## The head's place in the tool's own space (its scene's `Head` marker).
var head_local: Vector3 = Vector3(0.0, 0.6, 0.0)
var rest_pose: Transform3D = Transform3D.IDENTITY
var hit_pose: Transform3D = Transform3D.IDENTITY
var _model: Node3D = null
var _offset: Vector3 = Vector3.ZERO
var _target_offset: Vector3 = Vector3.ZERO
var _age: float = 10.0
var _jarred: bool = false


## A pose marker's transform in `stage` (a `Marker3D` at `path`), its editor preview of the tool (any children)
## taken away: the preview is for placing it in the editor, the stage's own tool swings in play.
static func marker(stage: Node, path: NodePath) -> Transform3D:
	var m: Node3D = stage.get_node_or_null(path) as Node3D
	if m == null:
		return Transform3D.IDENTITY
	for c: Node in m.get_children():
		m.remove_child(c)
		c.free()
	return m.transform


## A floating tool of `scene` (a held item's scene: its `Model` is shown, its `Head` says where the head is).
static func make(scene: PackedScene) -> FloatingTool:
	var t: FloatingTool = FloatingTool.new()
	t.name = "Tool"
	var src: Node3D = scene.instantiate() as Node3D
	var head: Node3D = src.get_node_or_null(^"Head") as Node3D
	if head != null:
		t.head_local = head.position
	var model: Node3D = src.get_node_or_null(^"Model") as Node3D
	if model != null:
		src.remove_child(model)
		model.owner = null   # it was the tool scene's; now it is ours
		t._model = model
		t.add_child(model)
	src.free()
	return t


## Its two poses: resting, and at the blow (the head where it lands).
func set_poses(rest: Transform3D, hit: Transform3D) -> void:
	rest_pose = rest
	hit_pose = hit
	transform = rest


## Moves both poses so the blow's head lands on `point` (the stage's space); `now` jumps there, else it glides.
func aim(point: Vector3, now: bool = false) -> void:
	_target_offset = point - hit_pose * head_local
	if now:
		_offset = _target_offset


## Where the head is at the blow, as aimed.
func head_at_hit() -> Vector3:
	return hit_pose * head_local + _target_offset


## A blow that lands: down to the hit pose, then back up.
func swing() -> void:
	_offset = _target_offset
	_age = 0.0
	_jarred = false


## A blow that jars (it hits something hard and bounces off): down, then a quick bounce back with a shudder.
func jar() -> void:
	swing()
	_jarred = true


## How far down the swing is now: 0 resting, 1 at the blow.
func down() -> float:
	if _age < fall_s:
		var k: float = _age / fall_s
		return k * k   # it speeds up into the blow
	var up: float = rise_s * (0.5 if _jarred else 1.0)
	if _age < fall_s + up:
		return 1.0 - smoothstep(0.0, 1.0, (_age - fall_s) / up)
	return 0.0


func is_swinging() -> bool:
	return _age < fall_s + rise_s


func _process(delta: float) -> void:
	_age += delta
	if _age >= fall_s:
		_offset = _offset.lerp(_target_offset, minf(1.0, delta * 10.0))
	var d: float = down()
	var pose: Transform3D = rest_pose.interpolate_with(hit_pose, d)
	pose.origin += _offset
	if _jarred and _age >= fall_s and _age < fall_s + rise_s:
		var shudder: float = (1.0 - (_age - fall_s) / rise_s) * bounce
		pose = pose.rotated_local(Vector3.RIGHT, sin(_age * 70.0) * 0.12 * shudder)
	transform = pose
