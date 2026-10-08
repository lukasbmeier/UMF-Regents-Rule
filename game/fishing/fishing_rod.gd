class_name FishingRod extends HeldItem
## GENRE CODE. A fishing rod, held in a character's hand.
##
## The rod's own axis is +Y, grip at the origin, and `Tip` marks the end the line leaves from.
## Any scene with that shape can replace `fishing_rod.tscn`; nothing else knows what the rod is
## made of.
##
## HOW IT SITS IN THE HAND is the foundation's held-item system (DECISIONS #153, #156): this is a
## `HeldItem`, and `rod_grip.tres` says where it sits during each ANIMATION (the idle and the
## walk carry it; the cast, the waiting pose and the heave fish with it), in each BODY's hand.
## Edit it in `rod_grip_preview.tscn`.
##
## IN THE FIGHT it shows what the fight is doing (DECISIONS #144): the blank BENDS toward whatever
## the line is pulling on (`set_bend`) and the reel's handle TURNS as the player winds
## (`set_reel_turn`). Presentation only: it is told, it decides nothing.
##
## HELD IN BOTH HANDS (DECISIONS #163, #172) is the grip's data, not this script's: `rod_grip.tres`
## says which animations the left hand holds the reel in (the cast, the wait, the heave), and its
## point is `OffHand`, the reel's knob, which goes round with the handle. The foundation's
## `HeldItem` puts the hand there, and the grip preview shows it. The clips' own left hand is not on
## this rod: left to them it hung in the air waiting, floated off the reel heaving, and went
## through her chest and belly casting (the arms suite).

## Metres the tip moves at a bend of 1.
const BEND_M: float = 0.42
## The reel handle's reach from the axle, and how far its knob stands off the reel's face.
const HANDLE_RADIUS: float = 0.04
const KNOB_OUT: float = 0.045
const BLANK_SHADER: Shader = preload("res://game/fishing/rod_blank.gdshader")

var _blank_mat: ShaderMaterial = null
var _blank_half: float = 0.75
var _blank_y: float = 1.0
var _tip_rest: Vector3 = Vector3.ZERO
var _bead_rest: Vector3 = Vector3.ZERO
var _bend: float = 0.0
var _bend_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var _handle: Node3D = null
var _knob: Marker3D = null


func _ready() -> void:
	var tip: Node3D = get_node_or_null(^"Tip") as Node3D
	var bead: Node3D = get_node_or_null(^"TipBead") as Node3D
	_tip_rest = tip.position if tip != null else Vector3(0.0, 1.76, 0.0)
	_bead_rest = bead.position if bead != null else _tip_rest
	_make_blank_bendable()
	_make_handle()


## Where the line leaves the rod, in world space — at the tip as it is bent right now.
func tip_position() -> Vector3:
	var tip: Node3D = get_node_or_null(^"Tip") as Node3D
	return tip.global_position if tip != null else global_position


## BEND THE ROD: `amount` 0 (straight) .. ~1.2 (as far as it goes), toward `toward` in world space —
## where the line runs. Only the part of that direction ACROSS the rod bends it.
func set_bend(amount: float, toward: Vector3) -> void:
	_bend = maxf(amount, 0.0)
	var local: Vector3 = global_transform.affine_inverse() * toward - _tip_rest
	local.y = 0.0
	if local.length_squared() > 0.000001:
		_bend_dir = local.normalized()
	var metres: float = _bend * BEND_M
	if _blank_mat != null:
		_blank_mat.set_shader_parameter(&"bend", metres)
		_blank_mat.set_shader_parameter(&"bend_dir", _bend_dir)
	# The tip and its bead go where the blank's end went (rod_blank.gdshader, at s = 1).
	var shift: Vector3 = _bend_dir * metres - Vector3(0.0, 0.5 * metres * metres / (2.0 * _blank_half), 0.0)
	var tip: Node3D = get_node_or_null(^"Tip") as Node3D
	var bead: Node3D = get_node_or_null(^"TipBead") as Node3D
	if tip != null:
		tip.position = _tip_rest + shift
	if bead != null:
		bead.position = _bead_rest + shift


func bend() -> float:
	return _bend


## The reel's handle, turned to `radians` about its axle.
func set_reel_turn(radians: float) -> void:
	if _handle != null:
		_handle.rotation = Vector3(0.0, radians, 0.0)


## Where the winding hand holds on, in world space: the grip's off-hand point, the reel's knob.
func knob_position() -> Vector3:
	return _knob.global_position if _knob != null else global_position


## How much the left hand is on the reel now, 0..1 (`HeldItem.off_hand_on`).
func hand_on_reel() -> float:
	return off_hand_on()


## The rod already in one of `skeleton`'s hands, if there is one: holding a rod twice is a mistake
## a caller can make (a rebind), and this is how it is not made.
static func in_hand(skeleton: Skeleton3D) -> FishingRod:
	if skeleton == null:
		return null
	for hand: Node in skeleton.get_children():
		if hand is BoneAttachment3D:
			for c: Node in hand.get_children():
				if c is FishingRod:
					return c as FishingRod
	return null


# --- pieces --------------------------------------------------------------------------------

## The blank as a mesh that can curve: enough rings along it to bend, and the bending shader
## carrying the look it had.
func _make_blank_bendable() -> void:
	var blank: MeshInstance3D = get_node_or_null(^"Blank") as MeshInstance3D
	if blank == null or not blank.mesh is CylinderMesh:
		return
	var mesh: CylinderMesh = (blank.mesh as CylinderMesh).duplicate() as CylinderMesh
	mesh.rings = 16
	blank.mesh = mesh
	_blank_half = mesh.height * 0.5
	_blank_y = blank.position.y
	var look: StandardMaterial3D = blank.get_surface_override_material(0) as StandardMaterial3D
	_blank_mat = ShaderMaterial.new()
	_blank_mat.shader = BLANK_SHADER
	_blank_mat.set_shader_parameter(&"half_length", _blank_half)
	if look != null:
		_blank_mat.set_shader_parameter(&"albedo", look.albedo_color)
		_blank_mat.set_shader_parameter(&"metallic", look.metallic)
		_blank_mat.set_shader_parameter(&"roughness", look.roughness)
	blank.set_surface_override_material(0, _blank_mat)
	# The shader moves vertices, and the renderer culls by the mesh's own box: widen it by the
	# furthest the tip can go, or a bent rod blinks out at the edge of the screen.
	blank.extra_cull_margin = BEND_M * 1.3


## A handle on the reel: an arm from the axle and a knob standing off the reel's face. The reel
## is a disc turned on its side, so its own Y is the axle and the handle turns about it — on the
## reel's +Y face, which is the rod's -X: the side the left hand holds the rod from in the fishing
## clips (measured, DECISIONS #144), so the winding hand has the handle under it.
func _make_handle() -> void:
	var reel: MeshInstance3D = get_node_or_null(^"Reel") as MeshInstance3D
	if reel == null:
		return
	var metal: Material = reel.get_surface_override_material(0)
	_handle = Node3D.new()
	_handle.name = "Handle"
	reel.add_child(_handle)
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.008, 0.006, HANDLE_RADIUS)
	arm.mesh = arm_mesh
	arm.material_override = metal
	arm.position = Vector3(0.0, 0.021, HANDLE_RADIUS * 0.5)
	_handle.add_child(arm)
	var knob := MeshInstance3D.new()
	knob.name = "Knob"
	var knob_mesh := CylinderMesh.new()
	knob_mesh.top_radius = 0.008
	knob_mesh.bottom_radius = 0.008
	knob_mesh.height = 0.03
	knob_mesh.radial_segments = 8
	knob.mesh = knob_mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.4, 0.27)
	wood.roughness = 0.8
	knob.material_override = wood
	knob.position = Vector3(0.0, 0.021 + 0.015, HANDLE_RADIUS)
	_handle.add_child(knob)
	# The point the left hand holds (`rod_grip.tres` names it): in the scene at the handle's rest, so
	# the editor's preview has it too, and moved onto the handle here so it goes round when wound.
	_knob = reel.get_node_or_null(^"OffHand") as Marker3D
	if _knob == null:
		_knob = Marker3D.new()
		_knob.name = "OffHand"
	else:
		reel.remove_child(_knob)
	_knob.position = Vector3(0.0, KNOB_OUT, HANDLE_RADIUS)
	_handle.add_child(_knob)


## How much of the animations it is held in both hands in is showing, 0..1 (`HeldItem`).
func two_handed_weight() -> float:
	return off_hand_weight()
