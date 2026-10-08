@tool
class_name GripEntry extends Resource
## One way of holding an item: during `animation`, in `body`'s hand, the item sits HERE (DECISIONS
## #153, #156). An `ItemGrip` is a list of these. Edited by eye in a held-item preview, or typed
## in the Inspector.
##
## The defaults below are NEUTRAL on purpose: Godot leaves a property out of a saved file when it
## equals its default, so a value that matched a default here would live only in this script.

## The animation, by semantic name (`locomotion.idle`, `locomotion.run`, `interact`,
## `fishing.heave`): whenever the body plays it, the item sits here. Every grip names one; the
## IDLE's grip is the one every animation without a grip of its own ends up borrowing.
@export var animation: StringName = &"":
	set(value):
		animation = value
		emit_changed()
## The BODY this grip is for (`female`, `male`: what the character's look says it is, DECISIONS
## #155). Empty: every body. One body's own grip wins over the shared one for the same animation.
@export var body: StringName = &"":
	set(value):
		body = value
		emit_changed()
## Where the item's grip point sits, in the hand bone's frame (metres): on this skeleton +Y runs
## along the fingers and +Z the way the thumb points. The item's own origin is its grip point.
@export var position: Vector3 = Vector3.ZERO:
	set(value):
		position = value
		emit_changed()
## The item's turn, in degrees (Euler YXZ, what the Inspector shows for a node). From the HAND,
## or from the BODY when `steady`.
@export var rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		rotation_degrees = value
		emit_changed()
## CARRIED STEADY: the item keeps its direction to the BODY, not to the hand, while its grip point
## stays in the hand. For a long item in an animation that swings the arm (a rod or a spear while
## running): following the hand, its tip sweeps through the head every stride.
@export var steady: bool = false:
	set(value):
		steady = value
		emit_changed()


## The grip's turn as a basis: from the hand, or from the body when steady.
func basis() -> Basis:
	var r: Vector3 = Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z))
	return Basis.from_euler(r, EULER_ORDER_YXZ)


## The item in the HAND'S frame, for a hand and a body (the skeleton's) as they are right now.
## Scale is the hand's own business: the item is parented to it.
func in_hand(hand: Transform3D, body: Basis) -> Transform3D:
	if not steady:
		return Transform3D(basis(), position)
	var turn: Basis = hand.basis.orthonormalized().inverse() * body.orthonormalized() * basis()
	return Transform3D(turn.orthonormalized(), position)


## Take where the item is held in the WORLD (a gizmo's transform) as this grip, for a hand and a
## body as they are right now. Writes only what moved or turned, so a grip slid along the fingers
## keeps its rotation exactly as it was typed. Returns whether anything changed.
func set_held(held: Transform3D, hand: Transform3D, body: Basis) -> bool:
	var local: Vector3 = hand.affine_inverse() * held.origin
	var turn: Basis = held.basis.orthonormalized()
	turn = (body.orthonormalized().inverse() * turn) if steady \
		else (hand.basis.orthonormalized().inverse() * turn)
	var e: Vector3 = turn.orthonormalized().get_euler(EULER_ORDER_YXZ)
	var deg: Vector3 = Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	var moved: bool = not local.is_equal_approx(position)
	var turned: bool = not same_turn(deg, rotation_degrees)
	if moved:
		position = local
	if turned:
		rotation_degrees = deg
	return moved or turned


## Make this grip steady or not WITHOUT moving the item: its turn is restated in the other frame,
## for a hand and a body as they are now (the preview's frame on screen).
func set_steady(on: bool, hand: Transform3D, body: Basis) -> void:
	if on == steady:
		return
	var held: Transform3D = hand * in_hand(hand, body)
	steady = on
	set_held(Transform3D(held.basis.orthonormalized(), held.origin), hand, body)


func copy_from(other: GripEntry) -> void:
	position = other.position
	rotation_degrees = other.rotation_degrees
	steady = other.steady


## Two Euler triples that turn the same way (a gizmo can hand back either of two spellings).
static func same_turn(a: Vector3, b: Vector3) -> bool:
	var ra: Basis = Basis.from_euler(Vector3(deg_to_rad(a.x), deg_to_rad(a.y), deg_to_rad(a.z)), EULER_ORDER_YXZ)
	var rb: Basis = Basis.from_euler(Vector3(deg_to_rad(b.x), deg_to_rad(b.y), deg_to_rad(b.z)), EULER_ORDER_YXZ)
	return ra.is_equal_approx(rb)
