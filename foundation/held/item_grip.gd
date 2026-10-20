@tool
class_name ItemGrip extends Resource
## HOW AN ITEM IS HELD: in which hand, and where it sits in it during each ANIMATION, in each
## BODY's hand (DECISIONS #153, #156). One `.tres` per item (a rod, a sword, a shield, a bow),
## read by its `HeldItem` scene and edited by eye in a held-item preview (`held_item_preview.gd`).
##
## A list of `GripEntry`: "during this animation, in this body's hand, it sits here". Whatever
## starts an animation (walking about, a cast, a pose a genre holds), while the body plays it the
## item sits where that animation's grip says. An animation with no grip of its own BORROWS one:
##
##   1. its own grip, if it has one
##   2. else the grip of the animation its CLIP would fall back to (`AnimationSet.FALLBACKS`:
##      `locomotion.sprint` borrows `run`'s, `run` borrows `walk`'s, `walk` the idle's)
##   3. else the IDLE's grip (`locomotion.idle`): every item's starting point
##
## and at every one of those steps, a grip for this BODY (`female`, `male`: what the character's
## look says it is, DECISIONS #155) wins over the grip for every body. So her own idle grip moves
## the item in her hand alone, and a run's own grip, shared, still beats her idle grip while she
## runs (it is there because the run poses the hand differently).
##
## So an item needs one grip, the idle's, and each animation or body that holds it differently
## gets its own. In the game the grips BLEND with the same weights the animations do
## (`AnimationDriverComponent.semantic_weights`), so walking into a run, or a cast into a waiting
## pose, moves the item as smoothly as the arm.
##
## A TOOL resource: the editor previews call its methods. It may read `AnimationSet`'s constants
## (a class's constants are there in the editor) but call no method of a non-tool class.

## The semantic names of drawing an item and putting it away (DECISIONS #158): the animation set
## maps them to clips, `HeldItem.draw`/`stow` play them.
const DRAW: StringName = &"item.draw"
const STOW: StringName = &"item.stow"

## The bone the item is held in. `hand_r` and `hand_l` on the humanoid (Quaternius) skeleton.
@export var hand: StringName = &"hand_r"
## Every grip. Edit them in the preview; typing here works too.
@export var entries: Array[GripEntry] = []
## ONE GRIP FOR EVERY ANIMATION, AND SPOT FIXES (DECISIONS #257): the idle's grip is the UNIVERSAL
## one, which every animation uses, and a grip made for an animation (a drag in the preview) is a
## spot fix on it (`GripEntry.relative`): a nudge from the universal grip, so moving the universal
## grip moves the fixes with it. The preview's Use One Grip For All turns it on. Off: every grip is
## its own (an item fitted per animation, like the rod).
@export var universal: bool = false
## How far the WRIST may turn to keep an item carried steady in the fist, in degrees (DECISIONS
## #158, `HoldWrist`): the arm swings, the item keeps its direction, and the hand bends to stay
## round its handle. 0: the hand never turns, and the handle turns in the fist instead.
@export_range(0.0, 120.0, 1.0) var wrist_turn_deg: float = 60.0
## THE FIST it is held in (DECISIONS #160, `GripFit.close_fist`): the animation whose first frame's
## hand closes round it. A clip that opens the hand while the item is in it (a jump) has its fingers
## closed back toward this one's. Empty: the hand does whatever the clip does.
@export var fist_animation: StringName = &"locomotion.idle"

@export_group("Stow")
## WHERE IT IS PUT AWAY (DECISIONS #158, `HeldItem.stow`): the bone it rides on while slung, and
## where its HOLD sits on that bone, in the bone's frame. Move the preview's Stow node, or press its
## Fit Stow: that puts it where the hand reaches in the draw, so the hand takes it without a jump.
## All zero: the item is never put away.
@export var stow_bone: StringName = &"spine_03"
@export var stow_position: Vector3 = Vector3.ZERO
@export var stow_rotation_degrees: Vector3 = Vector3.ZERO
## How far through the draw (`item.draw`) the hand takes it, and through the stow (`item.stow`)
## lets go of it (0..1). 0: not measured; half way. Fit Stow measures them.
@export_range(0.0, 1.0, 0.01) var draw_swap_at: float = 0.0
@export_range(0.0, 1.0, 0.01) var stow_swap_at: float = 0.0
## For FIT STOW: which way the item hangs while slung, in the BODY's terms (x right, y up,
## z forward): a rod down across the back to the left hip is (-0.6, -0.8, 0). Zero: as the hand
## holds it when it takes it. And which way its own +Z faces (0, 0, 1): toward the body, so a rod's
## reel, on its -Z, faces out.
@export var stow_point: Vector3 = Vector3.ZERO
@export var stow_face: Vector3 = Vector3.ZERO
## How LONG it is while put away, as a share of its length (DECISIONS #161): a telescopic rod packs
## to 0.45, so 1.85 m of rod slung from the shoulder stops dragging its tip on the ground. Squeezed
## along its own length about its Hold: it packs in the hand before the stow lets go of it, and
## stretches out again once the draw has it. 1: as it is.
@export_range(0.2, 1.0, 0.01) var stow_length: float = 1.0

@export_group("Off hand")
## HELD IN BOTH HANDS (`OffHand`, DECISIONS #172): the animations in which the hand that is not
## gripping holds the item too. While they show, that arm is put on the item by IK, as much as they
## are showing. Empty: one hand, always.
@export var off_hand_animations: Array[StringName] = []
## That arm, root to hand, as the skeleton names it (`upperarm_l`, `lowerarm_l`, `hand_l`).
@export var off_hand_arm: Array[StringName] = []
## The node in the item's scene the fingers hold, by name: it may move (a reel's turning knob).
@export var off_hand_point: StringName = &""
## Where that hand's WRIST sits from the point, in the item's own frame (measured off a clip whose
## two hands hold the item: the rod's left wrist is 11 cm back from its knuckles).
@export var off_hand_wrist: Vector3 = Vector3.ZERO
## Where its ELBOW is pulled toward, from its shoulder, in the BODY's terms: x out past that
## shoulder, y up the spine, z forward. Never in the item's terms (#162): pointed from the item it
## turned with each refit of the grips, and drove the forearm through her waist.
@export var off_hand_elbow: Vector3 = Vector3.ZERO
## The two spine bones that say which way is up for the elbow, low then high.
@export var off_hand_spine: Array[StringName] = []
## How much of the arm's length the hand may use: a locked elbow pins instead of moving.
@export_range(0.5, 1.0, 0.01) var off_hand_reach: float = 1.0

@export_group("Fit")
## FOR THE PREVIEW'S FIT BUTTONS (`GripFit`, DECISIONS #157). Where the item points while it is
## only CARRIED (standing, walking, running, jumping), held steady, in the BODY's terms: x to the
## character's right, y up, z forward. A rod carried tip-up and forward is (0, 1, 1). Zero: along
## the fist. Animations that USE the item always hold it along the fist.
@export var carry_point: Vector3 = Vector3.ZERO
## Which way the item's own +Z faces, in the same terms, in every animation (a rod's reel hangs on
## its -Z, so (0, 1, 0) hangs it below the rod). Zero: toward the wrist.
@export var fit_face: Vector3 = Vector3.ZERO
## How far a fit lets the handle leave the fist's line, in degrees: whatever the wrist could not
## turn (past about this the fingers show through the handle).
@export_range(0.0, 60.0, 1.0) var fit_cone_deg: float = 15.0


## Whether the item has a place to be put away (`stow_position` or its turn set).
func stows() -> bool:
	return not stow_position.is_zero_approx() or not stow_rotation_degrees.is_zero_approx()


## The HOLD's place on `stow_bone`, in that bone's frame.
func stow_transform() -> Transform3D:
	var r: Vector3 = stow_rotation_degrees
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)),
		EULER_ORDER_YXZ), stow_position)


## THE SQUEEZE while it is `packed` (0: as it is; 1: down to `stow_length`), in the ITEM's frame:
## along its own +Y, about its hold (`hold`, the Hold node in the item's frame), which stays put.
## The item sits at `hold_world * hold.affine_inverse() * packing(hold, packed)`.
func packing(hold: Transform3D, packed: float) -> Transform3D:
	var k: float = lerpf(1.0, stow_length, clampf(packed, 0.0, 1.0))
	if is_equal_approx(k, 1.0):
		return Transform3D.IDENTITY
	var s := Basis.from_scale(Vector3(1.0, k, 1.0))
	return Transform3D(s, hold.origin - s * hold.origin)


## Set the stowed place from a HOLD transform in the bone's frame.
func set_stow_transform(t: Transform3D) -> void:
	var e: Vector3 = t.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	stow_position = t.origin
	stow_rotation_degrees = Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


## The animations some grip is for, in the order they first appear.
func animations() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: GripEntry in entries:
		if e != null and not e.animation.is_empty() and not out.has(e.animation):
			out.append(e.animation)
	return out


## The bodies some grip is kept for, in the order they first appear.
func bodies() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: GripEntry in entries:
		if e != null and not e.body.is_empty() and not out.has(e.body):
			out.append(e.body)
	return out


## The entry for exactly this animation and body (empty: every body), or null. A spot fix comes
## with its base (the idle's grip for its body) set.
func find(animation: StringName, body: StringName = &"") -> GripEntry:
	for e: GripEntry in entries:
		if e != null and e.animation == animation and e.body == body:
			if e.relative:
				e.base = _idle_of(body)
			return e
	return null


## The idle's own grip for a body, else the shared one: what a spot fix for that body sits on.
func _idle_of(body: StringName) -> GripEntry:
	var shared: GripEntry = null
	for e: GripEntry in entries:
		if e != null and e.animation == AnimationSet.IDLE and not e.relative:
			if e.body == body:
				return e
			if e.body.is_empty():
				shared = e
	return shared


## USE THIS GRIP FOR ALL (the preview's button): every grip goes, for every animation and body, and the
## one left is the universal grip, the item held as given (`position` in the hand; `rotation_degrees`
## from the hand, or from the body when `steady`). Returns how many grips went.
func use_for_all(position: Vector3, rotation_degrees: Vector3, steady: bool) -> int:
	var gone: int = entries.size()
	var e := GripEntry.new()
	e.animation = AnimationSet.IDLE
	e.position = position
	e.rotation_degrees = rotation_degrees
	e.steady = steady
	entries = [e]
	universal = true
	emit_changed()
	return gone


## USE ONE GRIP FOR ALL: every animation's own grip goes, the idle's stay (for every body), and a
## grip made from now on is a spot fix on them. Returns how many grips went.
func make_universal() -> int:
	var kept: Array[GripEntry] = []
	for e: GripEntry in entries:
		if e != null and e.animation == AnimationSet.IDLE and not e.relative:
			kept.append(e)
	var gone: int = entries.size() - kept.size()
	entries = kept
	universal = true
	emit_changed()
	return gone


## The entry an animation USES, for a body (empty: one with no grips of its own): see the header.
## Null only when not even the idle has a grip.
func resolve(animation: StringName, body: StringName = &"") -> GripEntry:
	for step: StringName in steps(animation):
		if not body.is_empty():
			var own: GripEntry = find(step, body)
			if own != null:
				return own
		var shared: GripEntry = find(step)
		if shared != null:
			return shared
	return null


## The animations an animation's grip is looked for at, in order: itself, the animations its clip
## falls back to (depth first, as `AnimationSet.clip` follows them), then the idle. Empty is the
## idle.
static func steps(animation: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	_walk(animation, out)
	if not out.has(AnimationSet.IDLE):
		out.append(AnimationSet.IDLE)
	return out


static func _walk(animation: StringName, out: Array[StringName]) -> void:
	if animation.is_empty() or out.has(animation):
		return
	out.append(animation)
	for alt: StringName in AnimationSet.FALLBACKS.get(animation, [] as Array):
		_walk(alt, out)


## The entry for this animation and body, made if it is missing, starting where the item sits now
## for that body (the grip it was borrowing), so making a grip of its own moves nothing.
func ensure(animation: StringName, body: StringName = &"") -> GripEntry:
	var e: GripEntry = find(animation, body)
	if e != null:
		return e
	e = GripEntry.new()
	e.animation = animation
	e.body = body
	var was: GripEntry = resolve(animation, body)
	if universal and animation != AnimationSet.IDLE and (was == null or not was.relative):
		# A new spot fix, starting on the universal grip: no nudge yet, so nothing moves.
		e.relative = true
	elif was != null:
		e.copy_from(was)
	if e.relative:
		e.base = _idle_of(body)
	entries.append(e)
	emit_changed()
	return e


## Take a grip away: that animation (in that body's hand) borrows again. The idle's shared grip,
## the one everything ends up borrowing, is never removed here.
func remove(animation: StringName, body: StringName = &"") -> bool:
	if animation == AnimationSet.IDLE and body.is_empty():
		return false
	var e: GripEntry = find(animation, body)
	if e == null:
		return false
	entries.erase(e)
	emit_changed()
	return true


## WHERE THE ITEM SITS IN THE HAND right now, in the hand's frame: each animation's grip weighted
## by how much of that animation the body is showing (`animations`, by semantic name). Steady
## grips are worked out against `body` (the skeleton's basis) and the hand as they are;
## `body_type` picks a body's own grips. Weights need not sum to 1. With none, the idle's grip.
func blend(animations: Dictionary, hand: Transform3D, body: Basis,
		body_type: StringName = &"") -> Transform3D:
	var parts: Array[Transform3D] = []
	var weights: Array[float] = []
	for a: StringName in animations:
		var w: float = float(animations[a])
		var e: GripEntry = resolve(a, body_type) if w > 0.0 else null
		if e != null:
			parts.append(e.in_hand(hand, body))
			weights.append(w)
	if parts.is_empty():
		var idle: GripEntry = resolve(AnimationSet.IDLE, body_type)
		if idle != null:
			parts.append(idle.in_hand(hand, body))
			weights.append(1.0)
	return average(parts, weights)


## A weighted average of transforms: positions summed, turns slerped in one at a time (always
## the short way round). Identity when there is nothing to average.
static func average(parts: Array[Transform3D], weights: Array[float]) -> Transform3D:
	var pos: Vector3 = Vector3.ZERO
	var rot: Quaternion = Quaternion.IDENTITY
	var total: float = 0.0
	for i: int in range(parts.size()):
		var w: float = weights[i]
		if w <= 0.0:
			continue
		var q: Quaternion = Quaternion(parts[i].basis.orthonormalized())
		if total <= 0.0:
			rot = q
		else:
			if rot.dot(q) < 0.0:
				q = -q
			rot = rot.slerp(q, w / (total + w))
		pos += parts[i].origin * w
		total += w
	if total <= 0.0:
		return Transform3D()
	return Transform3D(Basis(rot.normalized()), pos / total)
