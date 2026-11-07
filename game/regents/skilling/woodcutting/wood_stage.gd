class_name WoodStage extends SubViewportContainer
## WOODCUTTING'S 3D STAGE (`MINIGAMES_PREP.md` §5; Luke's M7, 2026-11-05: gathering as a 3D stage too, a test): the
## round's trunk standing in a glade, cut into pieces with their branches, and the copper axe swinging on its own on
## the side you chop from (`FloatingTool`; Luke's play, 2026-11-06: no character on a stage, the player's own is the
## one working, as the anvil's hammer). `ChopMinigame` puts it behind its 2D readouts and tells it what `ChopModel`
## landed: PRESENTATION ONLY, it decides nothing. Its own world (`own_world_3d`).
##
## Designers: open `wood_stage.tscn` to move the camera, the sun or the glade's plants, and the axe's two poses on the
## left side: drag `AxeRest` and `AxeHit` (each shows the axe, a preview only the editor sees; the right side mirrors
## them).
## The numbers below size the trunk. The sounds are `game/regents/art/sound/woodcutting/` (`make_skill_sounds.py`).

## The stump's height, a piece's height, the trunk's radius; a branch's length (a whole one, and the stub left on
## the bottom piece).
@export var stump_h: float = 0.62
@export var piece_h: float = 0.55
@export var trunk_r: float = 0.24
@export var branch_len: float = 0.62
@export var stub_len: float = 0.12
## The axe, and its blade's edge in its own space (the point that bites: the head is `Head`, the edge out along -X).
@export var axe: PackedScene = preload("res://game/regents/skilling/woodcutting/axe.tscn")
@export var axe_edge: Vector3 = Vector3(-0.19, 0.6, 0.0)

const BARKS: Dictionary[String, String] = {
	"yew": "res://game/regents/art/nature/Bark_TwistedTree.png",
	"oak": "res://game/regents/art/nature/Bark_PineTree.png",
}
const BARK: String = "res://game/regents/art/nature/Bark_NormalTree.png"
const LEAVES: PackedScene = preload("res://game/regents/art/nature/Bush_Large.gltf")

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _trunk: Node3D = $Viewport/Stage/Trunk
@onready var _chips: CPUParticles3D = $Viewport/Stage/Chips
@onready var _leaves: CPUParticles3D = $Viewport/Stage/Leaves
@onready var _chop: AudioStreamPlayer = $Chop
@onready var _branch: AudioStreamPlayer = $Branch
@onready var _fall: AudioStreamPlayer = $Fall

var tool: FloatingTool = null
var _bark: StandardMaterial3D = null
var _pieces: Array[Node3D] = []
var _shown_cut: int = -1
var _drop: float = 0.0
var _flying: Array[Dictionary] = []
var _side: int = ChopModel.SIDE_LEFT
var _shake: float = 0.0
var _camera_home: Transform3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the clicks
	stretch = true
	_camera_home = camera.transform
	tool = FloatingTool.make(axe)
	tool.head_local = axe_edge
	$Viewport/Stage.add_child(tool)
	_place_tool(ChopModel.SIDE_LEFT)


## The round's tree: its bark (by its name: the yew twisted, the oak pine-barked, else a common tree).
func set_tree(display_name: String) -> void:
	var path: String = BARK
	for k: String in BARKS:
		if display_name.to_lower().contains(k):
			path = BARKS[k]
	_bark = StandardMaterial3D.new()
	_bark.albedo_texture = load(path) as Texture2D
	_bark.uv1_scale = Vector3(2.0, 1.0, 1.0)
	_bark.roughness = 0.9
	($Viewport/Stage/Stump as MeshInstance3D).material_override = _bark   # the stump is the same tree
	_shown_cut = -1


## The trunk as the model has it now: its pieces from `cut` up (`segments`: each piece's branch side), and which side
## the axe chops from.
func show_trunk(segments: PackedInt32Array, cut: int, side: int) -> void:
	if side != _side:
		_place_tool(side)
	if cut == _shown_cut:
		return
	if _shown_cut >= 0 and cut == _shown_cut + 1 and not _pieces.is_empty():
		_throw(_pieces[0])   # the bottom piece flies; the rest drop one piece
		_pieces.remove_at(0)
		_drop = piece_h
	_shown_cut = cut
	for p: Node3D in _pieces:
		p.queue_free()
	_pieces.clear()
	for j: int in ChopModel.VIEW_SEGMENTS:
		if cut + j >= segments.size():
			break
		_pieces.append(_piece(segments[cut + j], j == 0))
	_lay_pieces()


## A chop that landed (`CLEAN`): the axe swings in, chips fly, the knock.
func chop() -> void:
	tool.swing()
	_chips.position = Vector3((-1.0 if _side == ChopModel.SIDE_LEFT else 1.0) * trunk_r, stump_h + piece_h * 0.5, 0.1)
	_chips.direction = Vector3(-1.0 if _side == ChopModel.SIDE_LEFT else 1.0, 0.6, 0.4)
	_chips.restart()
	_play(_chop, randf_range(0.92, 1.08))


## A branch struck you (`HIT`): the axe is knocked back, leaves burst from the branch, the view shakes.
func hit() -> void:
	tool.jar()
	_leaves.position = Vector3((-1.0 if _side == ChopModel.SIDE_LEFT else 1.0) * (trunk_r + branch_len * 0.6), stump_h + piece_h * 1.5, 0.3)
	_leaves.restart()
	_shake = 1.0
	_play(_branch, 1.0)


## The axe on `side`: the scene's two poses are the left side's; the right side is their mirror (left for right).
func _place_tool(side: int) -> void:
	_side = side
	var rest: Transform3D = FloatingTool.marker(self, ^"Viewport/Stage/AxeRest")
	var hit_pose: Transform3D = FloatingTool.marker(self, ^"Viewport/Stage/AxeHit")
	if side == ChopModel.SIDE_RIGHT:
		rest = _mirror(rest)
		hit_pose = _mirror(hit_pose)
	tool.set_poses(rest, hit_pose)
	tool.aim(hit_pose * tool.head_local, true)


## The same pose seen in a mirror across the trunk (x to -x), still a proper turn (not a flipped model).
static func _mirror(t: Transform3D) -> Transform3D:
	var m: Basis = Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	var b: Basis = m * t.basis * m
	# Mirrored on both sides keeps the handle's line; the blade's edge must still face the trunk: turn it half round
	# the handle.
	b = b * Basis(Vector3.UP, PI)
	return Transform3D(b, Vector3(-t.origin.x, t.origin.y, t.origin.z))


func _piece(branch: int, bottom: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	var log_mesh: CylinderMesh = CylinderMesh.new()
	log_mesh.top_radius = trunk_r
	log_mesh.bottom_radius = trunk_r
	log_mesh.height = piece_h * 0.985
	log_mesh.material = _bark
	var log_inst: MeshInstance3D = MeshInstance3D.new()
	log_inst.mesh = log_mesh
	root.add_child(log_inst)
	if branch != ChopModel.BRANCH_NONE:
		var s: float = -1.0 if branch == ChopModel.BRANCH_LEFT else 1.0
		var length: float = stub_len if bottom else branch_len
		var arm: CylinderMesh = CylinderMesh.new()
		arm.top_radius = 0.045
		arm.bottom_radius = 0.07
		arm.height = length
		arm.material = _bark
		var arm_inst: MeshInstance3D = MeshInstance3D.new()
		arm_inst.mesh = arm
		arm_inst.rotation.z = -s * (PI * 0.5 - 0.25)   # out to the side, a little up
		arm_inst.position = Vector3(s * (trunk_r + length * 0.45), length * 0.12, 0.0)
		root.add_child(arm_inst)
		if not bottom:
			var leaves: Node3D = LEAVES.instantiate() as Node3D
			leaves.scale = Vector3.ONE * 0.32
			leaves.position = Vector3(s * (trunk_r + length * 0.95), length * 0.22 - 0.12, 0.0)
			root.add_child(leaves)
	_trunk.add_child(root)
	return root


func _lay_pieces() -> void:
	for j: int in _pieces.size():
		_pieces[j].position = Vector3(0.0, stump_h + piece_h * (0.5 + j) + _drop, 0.0)


func _throw(piece: Node3D) -> void:
	var away: float = 1.0 if _side == ChopModel.SIDE_LEFT else -1.0   # knocked away from the axe
	_trunk.remove_child(piece)
	$Viewport/Stage.add_child(piece)
	piece.position = Vector3(0.0, stump_h + piece_h * 0.5, 0.0)
	_flying.append({"node": piece, "vel": Vector3(away * 2.6, 2.2, 0.6), "spin": away * -7.0, "landed": false})


func _play(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _process(delta: float) -> void:
	if _drop > 0.0:
		_drop = maxf(0.0, _drop - delta * piece_h / 0.12)
		_lay_pieces()
	for i: int in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[i]
		var n: Node3D = f["node"]
		var v: Vector3 = f["vel"]
		v.y -= 9.8 * delta
		f["vel"] = v
		n.position += v * delta
		n.rotation.z += float(f["spin"]) * delta
		if not bool(f["landed"]) and n.position.y < trunk_r:
			f["landed"] = true
			_play(_fall, randf_range(0.9, 1.1))
		if n.position.y < -1.5:
			n.queue_free()
			_flying.remove_at(i)
	_shake = maxf(0.0, _shake - delta * 6.0)
	camera.transform = _camera_home
	if _shake > 0.0:
		camera.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.02 * _shake
