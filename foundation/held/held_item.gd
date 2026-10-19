class_name HeldItem extends Node3D
## AN ITEM HELD IN A CHARACTER'S HAND: a rod, a sword, a shield, a bow (DECISIONS #153, #158).
##
## The item's scene has this script (or one extending it) at its root, a `Hold` node where the fist
## closes on it (else its root is that point), and an `ItemGrip` saying where the hold sits in the
## hand during each animation, in each body's hand. `HeldItem.attach(skeleton, scene)` puts it in
## the grip's hand. From then on, after every update of the skeleton's pose, it sits where the
## grips say for what the body is playing, each animation's grip weighted by how much of it is
## showing (`AnimationDriverComponent.semantic_weights`, when a driver is given).
##
## The ANIMATION is the whole story (DECISIONS #156): nothing tells an item what "mode" it is in.
## A cast holds the rod the cast's way however it was started, and a run the run's way. While a
## steady grip is showing, the WRIST turns to keep the item in the fist (`HoldWrist`, #158), and
## whatever the clip does with the fingers, the HAND stays shut round it (`close_fist_now`, #160).
##
## PUT AWAY AND DRAWN (#158, #159): an item that FOLLOWS an `EquipComponent` (`follow`) plays the
## set's `item.draw`/`item.stow` on the upper body when one starts there, and moves between the hand
## and its stow bone (`ItemGrip.stow_*`) when the equip state flips; the game decides when, and
## checks the equip state before anything that needs the item in hand. On its own, `stow()` and
## `draw()` time the swap themselves (`stow_swap_at`, `draw_swap_at`).
##
## Presentation only: it is told, it decides nothing (hard rule 11).

## Where it sits in the hand, per animation and body. Edit it in a held-item preview.
@export var grip: ItemGrip
## How quickly the item follows the body's change of animation (per second). The driver's own
## blends are smooth already; this covers the state machine's switches (into the air, a landing).
@export var animation_follow: float = 12.0

## The body's animation, read every frame when set. Null: `set_animation_weights` says instead.
var driver: AnimationDriverComponent = null
## Which BODY holds it (`female`, `male`), for the grips kept for one body (DECISIONS #155): the
## `BODY_META` meta on the skeleton, which the character's look sets. Empty: the shared grips.
var body_type: StringName = &""

## The skeleton meta a character's look sets to say which body it is.
const BODY_META: StringName = &"body"

var _skel: Skeleton3D = null
var _hand_bone: int = -1
## How much of each animation is showing, eased toward what is asked.
var _anims: Dictionary[StringName, float] = {}
var _fixed: Dictionary[StringName, float] = {}
## Where the fist closes on the item (`GripFit.hold_of`), and the way back from it to the root.
var _hold: Transform3D = Transform3D()
var _hold_inv: Transform3D = Transform3D()
## The hand as it was last drawn (the wrist turned), and the fist's line as last seen closed.
var _last_hand: Transform3D = Transform3D()
var _fist_axis: Vector3 = Vector3.ZERO
var _wrist: HoldWrist = null
## Put away (on its stow bone) or in the hand; and, while a draw or a stow plays, which way it is
## going (+1 to the hand, -1 away) and the seconds until the hand takes it or lets go.
var _stowed: bool = false
var _going: int = 0
var _swap_left: float = 0.0
var _stow_bone: int = -1
## The equip state this item follows, if any.
var _equip: EquipComponent = null
## How far it is packed to its stow length (0..1, `ItemGrip.stow_length`): all the way while put
## away, eased in the hand over PACK_SEC as it goes away and as it comes out.
var _packed: float = 0.0
const PACK_SEC: float = 0.3
## The fist it is held in (`GripFit.fist_pose` of the grip's `fist_animation`), read once the
## driver gives the clips; and how far the hand was closed round it in the last update (0..1).
var _fist: Dictionary[int, Quaternion] = {}
var _fist_from: StringName = &""
var _closed: float = 0.0
## THE OTHER HAND (`OffHand`, DECISIONS #172): the IK on that arm, made the first time it is needed,
## and the item's point it holds.
var _off_ik: TwoBoneIK3D = null
var _off_point: Node3D = null


## Put an item from `scene` into `skeleton`'s hand (the scene's grip says which). Returns it, or
## null when the scene is not a held item or the skeleton has no such hand.
static func attach(skeleton: Skeleton3D, scene: PackedScene) -> HeldItem:
	if skeleton == null or scene == null:
		return null
	var made: Node = scene.instantiate()
	var item: HeldItem = made as HeldItem
	if item == null:
		push_warning("HeldItem: %s is not a held item (its root needs held_item.gd)" % scene.resource_path)
		if made != null:
			made.free()
		return null
	var hand_name: StringName = item.grip.hand if item.grip != null else &"hand_r"
	if skeleton.find_bone(String(hand_name)) < 0:
		push_warning("HeldItem: the skeleton has no %s bone to hold %s" % [hand_name, scene.resource_path])
		item.free()
		return null
	var hand: BoneAttachment3D = hand_node(skeleton, hand_name)
	if hand == null:
		hand = BoneAttachment3D.new()
		hand.name = "Hold_%s" % hand_name
		hand.bone_name = String(hand_name)
		skeleton.add_child(hand)
	hand.add_child(item)
	item._skel = skeleton
	item._hand_bone = skeleton.find_bone(String(hand_name))
	item.body_type = StringName(skeleton.get_meta(BODY_META, &""))
	item._stow_bone = skeleton.find_bone(String(item.grip.stow_bone)) if item.grip != null else -1
	item._hold = GripFit.hold_of(item)
	item._hold_inv = item._hold.affine_inverse()
	item._wrist = HoldWrist.new()
	item._wrist.name = "Wrist_%s" % hand_name
	item._wrist.item = item
	skeleton.add_child(item._wrist)
	skeleton.skeleton_updated.connect(item._on_skeleton_updated)
	item._on_skeleton_updated()
	return item


## The attachment holding items in `hand_name`, if there is one.
static func hand_node(skeleton: Skeleton3D, hand_name: StringName) -> BoneAttachment3D:
	return skeleton.get_node_or_null(NodePath("Hold_%s" % hand_name)) as BoneAttachment3D


## Without a driver: the animations to hold the item for, by semantic name and weight
## (`{&"locomotion.idle": 1.0}`). Empty: the idle's grip.
func set_animation_weights(weights: Dictionary[StringName, float]) -> void:
	_fixed = weights.duplicate()
	if driver == null:
		_anims = _fixed.duplicate()


## How much of each animation the item is held for, as shown.
func animation_weights() -> Dictionary[StringName, float]:
	return _anims


## Where the item's HOLD sits in the hand right now, in the hand's frame, as last drawn: what the
## grips say. The item's own `transform` is this, less its hold (`hold_offset`).
func held_in_hand() -> Transform3D:
	if grip == null or _skel == null or _hand_bone < 0 or not _skel.is_inside_tree():
		return transform * _hold
	return grip.blend(_anims, _last_hand, _skel.global_basis, body_type)


## The hand (world) the item was last drawn in: the wrist turned, as the skeleton drew it.
func hand_now() -> Transform3D:
	return _last_hand


## Where the fist closes on the item, in its own frame (its `Hold` node).
func hold_offset() -> Transform3D:
	return _hold


func hand_bone() -> int:
	return _hand_bone


## Whether it is put away right now (on its stow bone, not in the hand).
func is_stowed() -> bool:
	return _stowed


## Whether it is put away or on its way there.
func wants_stowed() -> bool:
	return _going < 0 or (_stowed and _going == 0)


## Whether it can be put away at all: the grip has a stow place and the skeleton its bone.
func can_stow() -> bool:
	return grip != null and grip.stows() and _stow_bone >= 0


## FOLLOW AN EQUIP STATE (#159): from now on the draw and the put-away play when `equip` starts
## them, and the item moves when `equip` says it reached the hand or its place. Gives `equip` this
## item's own timings (from its clips: how far into the draw the hand takes it), and keeps an item
## with nowhere to go in the hand.
func follow(equip: EquipComponent) -> void:
	if equip == null or equip == _equip:
		return
	_equip = equip
	equip.draw_sec = draw_seconds()
	equip.stow_sec = stow_seconds()
	equip.equip_started.connect(_on_equip_started)
	equip.equip_cancelled.connect(_on_equip_cancelled)
	equip.equipped_changed.connect(_on_equipped_changed)
	if not can_stow():
		equip.away_when_idle = false
		equip.set_equipped_now(true)
	set_stowed_now(not equip.is_equipped())


## Seconds from starting the draw until the hand has it, and from starting the put-away until it
## is in its place: its clips' lengths, as far as the grip's swap moments (half way unmeasured).
## 0 with no driver or no clip.
func draw_seconds() -> float:
	return _until_swap(ItemGrip.DRAW, grip.draw_swap_at if grip != null else 0.0)


func stow_seconds() -> float:
	return _until_swap(ItemGrip.STOW, grip.stow_swap_at if grip != null else 0.0)


func _until_swap(semantic: StringName, at: float) -> float:
	if driver == null:
		return 0.0
	return driver.shot_seconds(semantic) * (at if at > 0.0 else 0.5)


func _on_equip_started(drawing: bool) -> void:
	if driver != null and can_stow():
		driver.play_upper(ItemGrip.DRAW if drawing else ItemGrip.STOW)


func _on_equip_cancelled(_drawing: bool) -> void:
	if driver != null:
		driver.stop_upper()


func _on_equipped_changed(equipped: bool) -> void:
	set_stowed_now(not equipped)


## PUT IT AWAY: the stow plays on the upper body, and the hand lets go of it on the stow bone. At
## once when there is no driver or no clip. (Following an equip state: ask it instead.)
func stow() -> void:
	if can_stow() and not wants_stowed():
		_start(-1)


## DRAW IT: the draw plays, and the hand takes it from the stow bone.
func draw() -> void:
	if wants_stowed():
		_start(1)


## Put away or in the hand at once, with no animation (a character arriving with it slung, or a
## cast that cannot wait for the hand).
func set_stowed_now(on: bool) -> void:
	_stowed = on and can_stow()
	_going = 0
	_swap_left = 0.0
	_packed = 1.0 if _stowed else 0.0


func _start(way: int) -> void:
	var semantic: StringName = ItemGrip.STOW if way < 0 else ItemGrip.DRAW
	var at: float = grip.stow_swap_at if way < 0 else grip.draw_swap_at
	if at <= 0.0:
		at = 0.5
	if driver != null and driver.play_upper(semantic):
		_going = way
		_swap_left = driver.shot_seconds(semantic) * at
	else:
		set_stowed_now(way < 0)


## CLOSE THE HAND ROUND IT this frame (`HoldWrist` asks, during the skeleton's update, before the
## wrist turns): the clip's fingers turned toward the grip's fist as far as the clip opened them
## (a jump flings them wide). Not while it is put away: the hand is free then.
func close_fist_now(skeleton: Skeleton3D) -> void:
	_closed = 0.0
	if grip == null or grip.fist_animation.is_empty() or _stowed or driver == null:
		return
	if _fist_from != grip.fist_animation:
		_fist_from = grip.fist_animation
		_fist = GripFit.fist_pose(skeleton, grip.hand,
			AnimationTreeBuilder.clip_animation(driver.animation_set, grip.fist_animation))
	_closed = GripFit.close_fist(skeleton, grip.hand, _fist)


## How far the hand was closed round it in the skeleton's last update: 0 is the clip's own hand.
func fist_closed() -> float:
	return _closed


## HOW FAR TO TURN THE WRIST this frame, in the skeleton's frame (`HoldWrist` asks, during the
## skeleton's update, before this item is placed): the turn that lays the fist along the item's
## steady direction, as far as its steady grips are showing. None for grips held in the hand.
func wrist_turn_now(skeleton: Skeleton3D) -> Basis:
	if grip == null or grip.wrist_turn_deg <= 0.0 or _hand_bone < 0 or _stowed:
		return Basis.IDENTITY
	var h: Dictionary = GripFit.hole(skeleton, grip.hand, false)
	if not h.is_empty() and bool(h["fist"]):
		_fist_axis = h["axis"]
	if _fist_axis == Vector3.ZERO:
		return Basis.IDENTITY
	var weights: Dictionary = _anims if not _anims.is_empty() else {AnimationSet.IDLE: 1.0}
	var want: Vector3 = Vector3.ZERO
	var steady: float = 0.0
	var total: float = 0.0
	for a: StringName in weights:
		var w: float = float(weights[a])
		var e: GripEntry = grip.resolve(a, body_type) if w > 0.0 else null
		if e == null:
			continue
		total += w
		if e.is_steady():
			steady += w
			# A steady grip's turn is in the body's frame, which is the skeleton's own.
			want += (e.basis() * Vector3.UP) * w
	if steady <= 0.0 or total <= 0.0 or want.is_zero_approx():
		return Basis.IDENTITY
	var full: Basis = GripFit.wrist_turn(skeleton.get_bone_global_pose(_hand_bone).basis, _fist_axis,
		want, grip.wrist_turn_deg)
	return Basis.IDENTITY.slerp(full, clampf(steady / total, 0.0, 1.0))


func _process(delta: float) -> void:
	_ease_animations(delta)
	if _going != 0:
		_swap_left -= delta
		if _swap_left <= 0.0:
			_stowed = _going < 0
			_going = 0
	var going_away: bool = _stowed or _going < 0 \
		or (_equip != null and _equip.state() == EquipComponent.State.STOWING)
	_packed = move_toward(_packed, 1.0 if going_away else 0.0, delta / PACK_SEC)
	_hold_with_other_hand()


## How much the other hand holds the item now, 0..1: the both-hands animations' share of what is
## showing (`ItemGrip.off_hand_animations`), and none while it is put away.
func off_hand_weight() -> float:
	return 0.0 if is_stowed() else OffHand.weight(grip, _anims)


## How much the other hand IS holding it (the IK's influence), 0..1.
func off_hand_on() -> float:
	return _off_ik.influence if _off_ik != null and _off_ik.active else 0.0


## The node the other hand holds, or null (`ItemGrip.off_hand_point`).
func off_hand_point() -> Node3D:
	if _off_point == null:
		_off_point = OffHand.point_of(self, grip)
	return _off_point


func _hold_with_other_hand() -> void:
	var w: float = off_hand_weight()
	if _off_ik == null:
		if w <= 0.0 or _skel == null:
			return
		_off_ik = OffHand.make_ik(_skel, grip)
		if _off_ik == null:
			return
	OffHand.place(_skel, grip, _off_ik, off_hand_point(), global_transform.basis, w)


## How far it is packed to its stow length (0: as it is, 1: `ItemGrip.stow_length`).
func packed() -> float:
	return _packed


func _exit_tree() -> void:
	if _wrist != null and is_instance_valid(_wrist):
		_wrist.queue_free()
	_wrist = null
	# The other hand's IK lives on the skeleton: it goes with the item.
	if _off_ik != null:
		OffHand.remove_ik(_skel)
	_off_ik = null


func _ease_animations(delta: float) -> void:
	var want: Dictionary[StringName, float] = driver.semantic_weights() if driver != null else _fixed
	var follow: float = 1.0 - exp(-animation_follow * delta) if animation_follow > 0.0 else 1.0
	for a: StringName in want:
		if not _anims.has(a):
			_anims[a] = 0.0
	for a: StringName in _anims.keys():
		_anims[a] = lerpf(_anims[a], float(want.get(a, 0.0)), follow)
		if _anims[a] < 0.001 and not want.has(a):
			_anims.erase(a)


## After the skeleton's final pose (the wrist turned): the item in the hand. Read off the skeleton,
## not the attachment, so it does not matter which of the two the skeleton tells first.
func _on_skeleton_updated() -> void:
	# A skeleton can still be told to update as its character leaves the tree (a despawn): there is
	# no world to hold anything in then.
	if grip == null or _skel == null or _hand_bone < 0 or not _skel.is_inside_tree():
		return
	_last_hand = _skel.global_transform * _skel.get_bone_global_pose(_hand_bone)
	if _stowed and _stow_bone >= 0:
		# On its stow bone: placed from there, still a child of the hand.
		var slung: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(_stow_bone) \
			* grip.stow_transform()
		transform = _last_hand.affine_inverse() * slung * _hold_inv * grip.packing(_hold, _packed)
		return
	transform = held_in_hand() * _hold_inv * grip.packing(_hold, _packed)
