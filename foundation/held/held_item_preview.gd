@tool
extends Node3D
## LINE UP A HELD ITEM IN THE HAND, by eye, in the editor (DECISIONS #153, #156). Any item, any
## character: give it a character `definition`, an `item` scene and its `grip` file. The game's
## rod uses it as `game/fishing/rod_grip_preview.tscn`.
##
## THE QUICK WAY (DECISIONS #259): pick a BODY ("both" for everyone) and an ANIMATION, type the item's
## HOLD (position and rotation in the hand) or drag the Grip node, press USE THIS GRIP FOR ALL, then step
## through the other animations and fix only the ones that look wrong: each fix is a nudge on the one grip,
## and follows it if it moves again. The grip FILE sits at the bottom of the Inspector; there is no need
## to open its list.
##
## A woman and a man stand in the Inspector's ANIMATION holding the item exactly as the game will
## (every look is one of those two bodies). Pick the ANIMATION and the BODY whose grip you are
## setting ("both", "female", "male"), select the GRIP node and move it (W) or turn it (E): the
## item follows, and the grip file is written when you SAVE THE SCENE (Ctrl+S; its tab shows * until then). A drag sets the grip for exactly that
## animation and that body. The first drag MAKES it, starting where the item already sits, so
## nothing jumps; from then on, whenever that body plays that animation in the game, the item sits
## there, whatever started the animation.
##
## An animation nobody has set BORROWS a grip (`ItemGrip`): the one its clip falls back to, else
## the idle's; and a body's own grip beats the shared one. Each character's label says which grip
## it is using. CLEAR THIS GRIP takes the one you are editing away, so it borrows again.
##
## FIT (DECISIONS #157): instead of dragging, FIT THIS GRIP puts the item's handle in the hole the
## hand's fingers make, pointing along the fist (or, while only carried, toward the grip file's
## carry_point, steady), clear of the body through the whole clip (`GripFit`). FIT EVERY ANIMATION does that for each animation in the set,
## for the body chosen. SAVE PICTURES then photographs every animation (its first frame, and the
## frame where the item comes closest to the body) into `res://grip_pictures/<grip>.png`: check
## that, and drag any grip that still looks wrong.
##
## STEADY (per grip): the item keeps its direction to the BODY instead of turning with the hand,
## while its grip stays in the hand. For a long item in an animation that swings the arm. The WRIST
## turns to keep it in the fist (`ItemGrip.wrist_turn_deg`, DECISIONS #158), here as in the game,
## and each label says how far the handle still leaves the fist.
##
## PUT AWAY (DECISIONS #158): tick SHOW STOWED to see the item slung on its stow bone, and move the
## STOW node to place it. FIT STOW puts it where the hand reaches in the draw (`item.draw`), so the
## hand takes it there without a jump, and measures when the draw takes it and the stow lets go.
##
## THE HOLD: the Grip node marks where the fist closes on the item, which is the item's `Hold`
## node (in the item's own scene: move it there to hold the item higher or lower), else its root.
## THE CARRY POINT node sits on the first character's hand and is how a carried item is held
## (`ItemGrip.carry_point`, `fit_face`): TURN it, and the animation shown, if it only carries the
## item, is fitted again to hold it so.
##
## THE OTHER HAND (DECISIONS #172): in an animation the grip file holds the item in both hands in
## (`ItemGrip`, "Off hand"), the other hand is put on the item's off-hand point by the same IK the
## game runs (`OffHand`), so the preview shows it where the game will.
##
## THE GAME PLAYS THE CLIP; this shows one frame of it. Each label gives the item's air off the
## body in the frame shown and at its worst through the whole clip, for every point the item
## marks with a `clearance_radius` meta (BodyClearance). Green is 2 cm clear all the way. Tick
## `play` to watch the clip go round (untick it to edit).
##
## The characters, the pose and the items are built here and never saved, and nothing here runs
## in the game. The editor reloads this script under an open scene: its variables hold only
## engine types (DECISIONS #152).

## How long the grip must sit still after a change before the labels' worst air is measured again and
## the Inspector's Hold is redrawn: neither runs on every frame of a drag (both cost a frame each).
const SETTLE_MSEC: int = 250
## Where the second character stands: to the first one's left, clear of a right-hand item.
const BESIDE_AT: Vector3 = Vector3(-1.8, 0.0, 0.0)
## Between an animation's semantic name and what it is, in the Animation list.
const LABEL_SEP: String = " · "
## Frames of the clip read for its worst.
const CLIP_SAMPLES: int = 24
## The air off the body the label calls enough.
const ENOUGH_AIR: float = 0.02
## What `body` says for the grip every body shares.
const BOTH: String = "both"
## How long after the Carry Point node is turned the grip shown is fitted to it.
const REFIT_DELAY_MSEC: int = 400
## How far off the body Fit Stow rests the item it slings on the back.
const STOW_AIR: float = 0.01

## The characters (its looks) and their animations.
@export var definition: EntityDefinition:
	set(value):
		definition = value
		_built = false
		notify_property_list_changed()
## The item's scene: a `HeldItem`, its root at its grip point.
@export var item: PackedScene:
	set(value):
		item = value
		_built = false
## The animation to line it up in, by semantic name. Pick one, or type one.
@export var animation: String = "locomotion.idle":
	set(value):
		animation = value
		_posed = false
		notify_property_list_changed()   # the Hold shown is this animation's, this body's
## Whose grip a drag sets: "both" (the one every body shares) or one body's own ("female",
## "male": what the characters' looks say they are).
@export var body: String = BOTH:
	set(value):
		body = value
		_posed = false
		notify_property_list_changed()   # the Hold shown is this animation's, this body's
@export_group("Hold")
## WHERE THE ITEM SITS IN THE HAND in this animation, for this body: metres in the hand bone's frame
## (+Y along the fingers, +Z the thumb). Typing here does what dragging the Grip node does. Not saved
## in this scene: it is the grip file's.
@export var hold_position: Vector3:
	get:
		return _hold_now().origin
	set(value):
		_set_hold(Transform3D(_hold_now().basis, value))
## Its turn in the hand, in degrees (YXZ, as a node's), as it is shown now.
@export var hold_rotation: Vector3:
	get:
		var e: Vector3 = _hold_now().basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	set(value):
		var r: Vector3 = Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))
		_set_hold(Transform3D(Basis.from_euler(r, EULER_ORDER_YXZ), _hold_now().origin))
## SPIN IT ON ITS OWN LENGTH, about the fist (DECISIONS #261): a blade's edges, an axe's head, turned
## without moving the handle. The gizmo's rings turn about the WORLD's axes unless its Local space is on
## (T in the 3D view); these always turn about the item's own +Y.
@export_tool_button("Spin 15°", "RotateRight") var spin_cw: Callable = func() -> void: spin(15.0)
@export_tool_button("Spin -15°", "RotateLeft") var spin_ccw: Callable = func() -> void: spin(-15.0)
@export_tool_button("Spin 90°", "RotateRight") var spin_quarter: Callable = func() -> void: spin(90.0)
## STEADY: the item keeps its direction to the body, not the hand (a long item in a swinging arm). The grip
## being edited's, read from the grip file, not stored in this scene.
@export var steady: bool:
	get:
		var e: GripEntry = _shown_for_edit() if grip != null and not _skels.is_empty() else null
		return e != null and e.is_steady()
	set(value):
		# Steady is part of THIS grip: made first if it is missing, where the item already sits.
		if grip != null and not _skels.is_empty() and _holder >= 0 and _holder < _skels.size():
			var e: GripEntry = grip.ensure(_anim(), _body_key())
			e.set_steady(value, _hand(_holder), _skels[_holder].global_basis)
		_posed = false
## USE THIS GRIP FOR ALL (DECISIONS #259, #263): the item as it sits now becomes the one grip every animation
## uses FOR THE BODY CHOSEN ("male": his grips only, hers untouched; "both": everyone's), and that body's
## other grips go. Then fix only the animations that need it. Undo: git.
@export_tool_button("Use This Grip For All", "Reload") var one_grip: Callable = use_this_for_all
## Take this animation's own grip away: it goes back to the one grip (or borrows, without one).
@export_tool_button("Clear This Grip", "Remove") var clear_grip: Callable = clear_this_grip
@export_group("Automatic fit")
## Fit the grip being edited into the hand, automatically (`GripFit`). A fit is a grip of its own.
@export_tool_button("Fit This Grip", "Edit") var fit_grip: Callable = fit_this_grip
## Fit a grip for every animation in the set, for the body chosen (each its own, not one for all).
@export_tool_button("Fit Every Animation", "Edit") var fit_all: Callable = fit_every_animation
@export_group("")
## Photograph every animation into res://grip_pictures/, to check the fits by eye.
@export_tool_button("Save Pictures", "Image") var save_pictures: Callable = save_pictures_now
## Show the item put away, on its stow bone (move the Stow node to place it).
@export var show_stowed: bool = false:
	set(value):
		show_stowed = value
		_posed = false
## Put the stow place where the hand reaches in the draw, and measure when it takes and lets go.
@export_tool_button("Fit Stow", "Edit") var fit_stow: Callable = fit_stow_now
## How far through the animation's clip (0 its first frame, 1 its last).
@export_range(0.0, 1.0, 0.01) var pose_at: float = 0.0:
	set(value):
		pose_at = value
		_posed = false
## Play the clip round, as the game does.
@export var play: bool = false:
	set(value):
		play = value
		_posed = false
## The two characters: the first, and another beside it (-1: nobody). The Quaternius looks
## alternate: even numbers are men, odd numbers women.
@export_range(0, 15) var look: int = 5:
	set(value):
		look = value
		_built = false
@export_range(-1, 15) var beside: int = 0:
	set(value):
		beside = value
		_built = false
@export_group("File")
## The grip being edited — the file the game reads. Its list is what the buttons above write; there is
## no need to open it.
@export var grip: ItemGrip:
	set(value):
		grip = value
		_posed = false
		notify_property_list_changed()

var _built: bool = false
var _posed: bool = false
## The characters, one entry each in every array below.
var _names: Array[String] = []
var _skels: Array[Skeleton3D] = []
var _players: Array[AnimationPlayer] = []
var _items: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _hands: Array[int] = []
## Which body each character is (its skeleton's `body` meta, which its look sets).
var _body_types: Array[StringName] = []
## The item's least air off each body through the clip, and how far through it that was.
var _worst: Array[float] = []
var _worst_at: Array[float] = []
var _worst_part: Array[String] = []
var _at: float = 0.0
## The character holding the Grip node: one whose hand shows the grip being edited.
var _holder: int = 0
var _grip_set: Transform3D = Transform3D()
var _grip_known: bool = false
var _worst_due: int = -1
## Abilities' names by id, for the Animation list (read once).
var _ability_names: Dictionary = {}
var _abilities_read: bool = false
var _refresh_due: int = -1
## The grip changed since the grip file was last written: it is written when the scene is saved (Ctrl+S),
## not on every move (DECISIONS #260).
var _dirty: bool = false
## The grip file's contents as last seen: a change from anywhere (gizmo, Inspector, undo) is saved.
var _seen: String = ""
## What the last fit did, in words, for the label; and whether pictures are being taken (the pose
## is theirs meanwhile).
var _fit_said: String = ""
var _picturing: bool = false
## The item's hold (its `Hold` node) undone: where its root is from the hold.
var _hold_inv: Transform3D = Transform3D()
## Each character's hand as the clip posed it (before the wrist turns), and its fist's line as last
## seen closed.
var _raw_hand: Array[Quaternion] = []
var _fist_axis: Array[Vector3] = []
## Each character's fingers as the clip posed them (bone index to its rotation), the fist the grip
## file closes them toward (`GripFit.fist_pose`), and the animation that fist was read from.
var _raw_fingers: Array[Dictionary] = []
var _fists: Array[Dictionary] = []
var _fist_from: Array[StringName] = []
## The Carry Point node's turn as last set, and when the grip being edited is due to be fitted
## again after it was turned.
var _carry_turn: Basis = Basis.IDENTITY
var _carry_known: bool = false
var _refit_at: int = -1
## The Stow node as last placed.
var _stow_set: Transform3D = Transform3D()
var _stow_known: bool = false


# --- the Inspector ---------------------------------------------------------------------------

## The animations and bodies offered as suggestions (any may be typed).
func _validate_property(property: Dictionary) -> void:
	if property["name"] in ["hold_position", "hold_rotation", "steady"]:
		property["usage"] = PROPERTY_USAGE_EDITOR
	elif property["name"] == "animation" and definition != null and definition.animation_set != null:
		var keys: Array[String] = []
		for k: StringName in definition.animation_set.clips:
			keys.append(String(k))
		keys.sort()
		var names: Array[String] = []
		for k: String in keys:
			names.append(animation_label(k))
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(names)
	elif property["name"] == "body":
		var names: Array[String] = [BOTH]
		for b: StringName in _body_types:
			if not b.is_empty() and not names.has(String(b)):
				names.append(String(b))
		if grip != null:
			for b: StringName in grip.bodies():
				if not names.has(String(b)):
					names.append(String(b))
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(names)


## CLEAR THIS GRIP: the animation, in that body's hand, borrows again. The idle's shared grip, the
## one everything ends up borrowing, stays.
func clear_this_grip() -> void:
	if grip != null:
		grip.remove(_anim(), _body_key())
	_posed = false


## USE THIS GRIP FOR ALL (`ItemGrip.use_for_all`): where the item sits now, in the hand shown, is the one grip.
func use_this_for_all() -> void:
	if grip == null or _skels.is_empty() or _holder < 0:
		return
	var shown: GripEntry = _shown_for_edit()
	var steady_now: bool = shown != null and shown.is_steady()
	var hand: Transform3D = _hand(_holder)
	var held: Transform3D = hand * _hold_now()
	var e := GripEntry.new()
	e.steady = steady_now
	e.set_held(held, hand, _skels[_holder].global_basis)
	var key: StringName = _body_key()
	var gone: int = grip.use_for_all(e.position, e.rotation_degrees, e.steady, key)
	_fit_said = "One grip for all %s (%d grip(s) replaced). Step through the animations; a drag or a typed Hold on one is a fix on this grip." 		% ["bodies" if key.is_empty() else "%s grips (the others untouched)" % key, gone]
	_posed = false
	notify_property_list_changed()


## Turn the item `deg` about its own length (its +Y, through the fist), for the animation and body shown.
func spin(deg: float) -> void:
	var t: Transform3D = _hold_now()
	# Its length in the hold's frame: the item's +Y, as the item's own Hold node is turned on it.
	var axis: Vector3 = (_hold_inv.basis * Vector3.UP).normalized()
	if axis.is_zero_approx():
		axis = Vector3.UP
	_set_hold(Transform3D(t.basis * Basis(axis, deg_to_rad(deg)), t.origin))


## Where the item sits in the hand shown, for the grip being edited (identity before the characters stand).
func _hold_now() -> Transform3D:
	if grip == null or _skels.is_empty() or _holder < 0 or _holder >= _skels.size():
		return Transform3D()
	var e: GripEntry = _shown_for_edit()
	if e == null:
		return Transform3D()
	return e.in_hand(_hand(_holder), _skels[_holder].global_basis)


## A typed Hold: as a drag of the Grip node there (this animation's grip, made if it is missing).
func _set_hold(in_hand: Transform3D) -> void:
	if grip == null or _skels.is_empty() or _holder < 0 or _holder >= _skels.size():
		return
	var e: GripEntry = grip.ensure(_anim(), _body_key())
	var hand: Transform3D = _hand(_holder)
	e.set_held(hand * in_hand, hand, _skels[_holder].global_basis)


# --- per frame -------------------------------------------------------------------------------

func _ready() -> void:
	_built = false


func _process(delta: float) -> void:
	# Built again when a reload kept `_built` but not the characters a previous version made.
	if not _built or (_skels.is_empty() and get_child_count(true) > get_child_count()):
		_build()
	if _skels.is_empty() or grip == null or _picturing:
		return
	if grip.find(AnimationSet.IDLE) == null:
		grip.ensure(AnimationSet.IDLE)
	if not _posed:
		_posed = true
		_at = pose_at
		for i: int in range(_skels.size()):
			_seek(i, _anim(), _at)
		_grip_known = false
		_worst_due = 0
	elif play:
		_at = fmod(_at + delta / maxf(_clip_length(), 0.01), 1.0)
		for i: int in range(_skels.size()):
			_seek(i, _anim(), _at)
	for i: int in range(_skels.size()):
		_turn_wrist(i, _anim())
	_holder = _pick_holder()
	_sync_carry_point()
	_sync_stow()
	if _refit_at >= 0 and Time.get_ticks_msec() >= _refit_at:
		_refit_at = -1
		if GripFit.carries(_anim()):
			fit_this_grip()
			_fit_said += "\n(Fit Every Animation carries it so in every animation)"
	var grip_node: Node3D = get_node_or_null(^"Grip") as Node3D
	if grip_node != null and _holder >= 0:
		var want: Transform3D = _hand(_holder) * _shown_for_edit().in_hand(_hand(_holder), _skels[_holder].global_basis)
		if _grip_known and not grip_node.global_transform.is_equal_approx(_grip_set):
			# The gizmo moved it (or undo did): that sets the grip for this animation and body,
			# made where the item sat if it was borrowing.
			var e: GripEntry = grip.ensure(_anim(), _body_key())
			e.set_held(grip_node.global_transform, _hand(_holder), _skels[_holder].global_basis)
			_grip_set = grip_node.global_transform
		elif not _grip_known or not want.is_equal_approx(_grip_set):
			grip_node.global_transform = want
			_grip_set = grip_node.global_transform
			_grip_known = true
	var now: String = _signature()
	if now != _seen:
		if not _seen.is_empty():
			# Measured and redrawn once it settles, not every frame of a drag; written on the scene's save.
			_worst_due = Time.get_ticks_msec() + SETTLE_MSEC
			_refresh_due = Time.get_ticks_msec() + SETTLE_MSEC
			if not _dirty:
				_dirty = true
				_mark_unsaved()
		_seen = now
	if _worst_due >= 0 and Time.get_ticks_msec() >= _worst_due:
		_worst_due = -1
		for i: int in range(_skels.size()):
			_measure_worst(i)
	for i: int in range(_skels.size()):
		_items[i].global_transform = _place(i, _anim())
		_hold_off_hand(i)
		_show(i)
	if _refresh_due >= 0 and Time.get_ticks_msec() >= _refresh_due:
		_refresh_due = -1
		notify_property_list_changed()


## SAVED WITH THE SCENE (DECISIONS #260): the grip file is written when the preview scene is saved (Ctrl+S),
## not on every move: a write per change had the editor rescan the file under every drag.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		save_grip()


## Write the grip file now if it changed. True when it was written.
func save_grip() -> bool:
	if not _dirty or grip == null or grip.resource_path.is_empty():
		return false
	_dirty = false
	return ResourceSaver.save(grip) == OK


## Whether the grip has changes the file does not have yet.
func grip_unsaved() -> bool:
	return _dirty


## The scene tab shows it unsaved (*), so Ctrl+S, or the editor asking on close, writes the grip.
func _mark_unsaved() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").call(&"mark_scene_as_unsaved")


## The other hand on the item, as the game puts it (`OffHand`), in the animations the grip holds it
## in both hands in; its own clip's hand in every other.
func _hold_off_hand(i: int) -> void:
	if not OffHand.used(grip) or i >= _items.size():
		return
	var on: float = 1.0 if grip.off_hand_animations.has(_anim()) and not show_stowed else 0.0
	var ik: TwoBoneIK3D = OffHand.make_ik(_skels[i], grip) if on > 0.0 		else _skels[i].get_node_or_null(OffHand.IK_NAME) as TwoBoneIK3D
	if ik == null:
		return
	OffHand.place(_skels[i], grip, ik, OffHand.point_of(_items[i], grip), _items[i].global_basis, on)


# --- fitting (GripFit, DECISIONS #157) --------------------------------------------------------

## FIT THIS GRIP: the chosen animation, for the chosen body.
func fit_this_grip() -> void:
	if grip == null or _skels.is_empty():
		return
	var r: Dictionary = _fit(_anim())
	_fit_said = _fit_words(_anim(), r)
	_posed = false


## FIT EVERY ANIMATION in the set, for the chosen body.
func fit_every_animation() -> void:
	if grip == null or _skels.is_empty():
		return
	var short: PackedStringArray = []
	var count: int = 0
	for a: StringName in _set_animations():
		var r: Dictionary = _fit(a)
		if r.is_empty():
			continue
		count += 1
		if float(r["air"]) < GripFit.ENOUGH_AIR:
			short.append("%s (%s %.1f cm %s the %s; the hand itself %.1f cm from it)" % [a, r["point"],
				absf(float(r["air"])) * 100.0, "off" if float(r["air"]) >= 0.0 else "into", r["part"],
				float(r["hand_air"]) * 100.0])
		elif float(r["out_of_fist_deg"]) > grip.fit_cone_deg + 0.01:
			short.append("%s (the handle %.0f deg out of the fist)" % [a, float(r["out_of_fist_deg"])])
	if _players[0].has_animation(_clip_of(ItemGrip.DRAW)):
		_fit_stow(not grip.stows())
	_fit_said = "fitted %d animations%s%s" % [count, ": all clear and in the fist" if short.is_empty()
		else "; NOT right: " + ", ".join(short), _handle_words()]
	_posed = false


## Fit `anim` for the chosen body's characters and write the grip. Returns what `GripFit.fit` said.
func _fit(anim: StringName) -> Dictionary:
	var who: Array[int] = _fitted()
	if who.is_empty() or not _players[who[0]].has_animation(_clip_of(anim)):
		return {}
	var marks: Array[Array] = GripFit.marks_of(_items[who[0]])
	var idle: Array[Dictionary] = _frames_of(who, AnimationSet.IDLE, 1)
	var fallback: Dictionary = GripFit.mean_hole(idle, {})
	var frames: Array[Dictionary] = _frames_of(who, anim, CLIP_SAMPLES)
	var r: Dictionary = GripFit.fit(frames, marks, anim, grip.carry_point, grip.fit_face,
		grip.fit_cone_deg, grip.wrist_turn_deg, fallback)
	if r.is_empty():
		return r
	var e: GripEntry = grip.ensure(anim, _body_key())
	# A fit is a grip of its own, not a spot fix (it says where the item sits, not a nudge).
	e.relative = false
	e.steady = bool(r["steady"])
	e.position = r["position"]
	e.rotation_degrees = r["rotation_degrees"]
	return r


## The characters a fit is for: the chosen body's, or everyone for "both".
func _fitted() -> Array[int]:
	var out: Array[int] = []
	for i: int in range(_skels.size()):
		if _body_key().is_empty() or _body_types[i] == _body_key():
			out.append(i)
	return out


## `GripFit.frame_of` each of `who` at `samples` + 1 points through `anim`, then the pose put back.
func _frames_of(who: Array[int], anim: StringName, samples: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in who:
		for k: int in range(samples + 1):
			# The clip's own hand: the fit turns the wrist itself, for every turn it tries.
			_seek(i, anim, float(k) / float(maxi(samples, 1)) if samples > 0 else 0.0, false)
			out.append(GripFit.frame_of(_skels[i], grip.hand))
		_seek(i, _anim(), _at)
	return out


static func _fit_words(anim: StringName, r: Dictionary) -> String:
	if r.is_empty():
		return "fit: no fingers to fit %s to" % anim
	return "fitted: %s%s, the handle %.0f deg out of the fist at most, %.1f cm %s at worst" % [
		"in the fist" if bool(r["fist"]) else "where the idle's fist is (this hand opens)",
		", steady" if bool(r["steady"]) else "", float(r["out_of_fist_deg"]),
		absf(float(r["air"])) * 100.0, "clear" if float(r["air"]) >= 0.0 else "INSIDE"]


## How thick a handle the first character's fist holds, in words (for sizing an item to it).
func _handle_words() -> String:
	var h: Dictionary = hole_of(0, AnimationSet.IDLE, 0.0)
	if h.is_empty() or not h.has("radius"):
		return ""
	return " (the fist holds a handle about %.1f cm across)" % (maxf(float(h["radius"]) - GripFit.FINGER_HALF, 0.0) * 200.0)


## Every animation the set has a clip for, by name.
func _set_animations() -> Array[StringName]:
	var out: Array[StringName] = []
	if definition == null or definition.animation_set == null:
		return out
	for k: StringName in definition.animation_set.clips:
		out.append(k)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


# --- put away (DECISIONS #158) -----------------------------------------------------------------

## FIT STOW: the stow place where the hand reaches in the draw, and when the draw and the stow swap.
func fit_stow_now() -> void:
	if grip == null or _skels.is_empty():
		return
	_fit_said = _fit_stow(true)
	_posed = false


## Measure the swaps and, when `place`, choose the stow place: where the draw's hand reaches
## HIGHEST (over the shoulder, where a slung hilt is), hanging the way the grip file's stow_point
## says. The draw's and the stow's own
## grips are then set to hold it exactly so at their swap moments, so the hand takes it, and lets
## it go, without a jump. Returns it in words.
func _fit_stow(place: bool) -> String:
	var i: int = _fitted()[0] if not _fitted().is_empty() else 0
	var sk: Skeleton3D = _skels[i]
	var bone: int = sk.find_bone(String(grip.stow_bone))
	if bone < 0 or not _players[i].has_animation(_clip_of(ItemGrip.DRAW)):
		return "fit stow: no %s bone or no draw clip" % grip.stow_bone
	if grip.find(ItemGrip.DRAW, _body_key()) == null:
		_fit(ItemGrip.DRAW)
	var body: Basis = sk.global_basis.orthonormalized()
	if place:
		# Where the hand reaches highest: over the shoulder, to the back.
		var highest: float = -INF
		for k: int in range(CLIP_SAMPLES + 1):
			var at: float = float(k) / float(CLIP_SAMPLES)
			_seek(i, ItemGrip.DRAW, at)
			var up: float = (body.inverse() * (_held_in(i, ItemGrip.DRAW).origin - sk.global_position)).y
			if up > highest:
				highest = up
				grip.draw_swap_at = at
		# WHERE: the hand at that moment, on the stow bone as it is then. WHICH WAY: as the grip file
		# asks, on the bone as it is standing (the draw twists the chest; the rod is slung while she
		# stands and walks), else as the hand holds it then.
		_seek(i, ItemGrip.DRAW, grip.draw_swap_at)
		var hold: Transform3D = _held_in(i, ItemGrip.DRAW)
		var at_swap: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone)
		var on_bone: Transform3D = at_swap.affine_inverse() * hold
		if not grip.stow_point.is_zero_approx():
			var y: Vector3 = (body * GripFit.body_dir(grip.stow_point)).normalized()
			var face: Vector3 = body * GripFit.body_dir(grip.stow_face if not grip.stow_face.is_zero_approx()
				else Vector3(0.0, 0.0, 1.0))
			var z: Vector3 = (face - y * face.dot(y)).normalized()
			_seek(i, AnimationSet.IDLE, 0.0)
			var standing: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone)
			on_bone.basis = standing.basis.orthonormalized().inverse() * Basis(y.cross(z).normalized(), y, z)
		grip.set_stow_transform(on_bone)
		# Resting ON the back, not in it: moved back (standing) until it clears the body by STOW_AIR.
		_seek(i, AnimationSet.IDLE, 0.0)
		_items[i].global_transform = _stowed_hold(i) * _packed_inv()
		var air: float = float(BodyClearance.item_air(sk, _items[i])["air"])
		if air < STOW_AIR:
			var standing_now: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone)
			on_bone.origin -= standing_now.basis.orthonormalized().inverse() * body.z * (STOW_AIR - air)
			grip.set_stow_transform(on_bone)
	else:
		grip.draw_swap_at = _nearest_at(i, ItemGrip.DRAW, bone)
	_meet_stow(i, ItemGrip.DRAW, grip.draw_swap_at, bone)
	if _players[i].has_animation(_clip_of(ItemGrip.STOW)):
		grip.stow_swap_at = _nearest_at(i, ItemGrip.STOW, bone)
		_meet_stow(i, ItemGrip.STOW, grip.stow_swap_at, bone)
	_seek(i, _anim(), _at)
	return "fit stow: on %s; the draw takes it %d%% in, the stow lets go %d%% in" % [grip.stow_bone,
		roundi(grip.draw_swap_at * 100.0), roundi(grip.stow_swap_at * 100.0)]


## Set `anim`'s own grip to hold the item exactly where it is put away, `at` (0..1) through it:
## the moment the hand takes it or lets it go.
func _meet_stow(i: int, anim: StringName, at: float, bone: int) -> void:
	var sk: Skeleton3D = _skels[i]
	_seek(i, anim, at)
	var slung: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone) * grip.stow_transform()
	var e: GripEntry = grip.ensure(anim, _body_key())
	e.steady = false
	e.set_held(slung, _hand(i), sk.global_basis)


## Where through `anim` the item in character `i`'s hand comes nearest its stow place (0..1).
func _nearest_at(i: int, anim: StringName, bone: int) -> float:
	var sk: Skeleton3D = _skels[i]
	var nearest: float = INF
	var at_nearest: float = 0.5
	for k: int in range(CLIP_SAMPLES + 1):
		var at: float = float(k) / float(CLIP_SAMPLES)
		_seek(i, anim, at)
		var slung: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone) * grip.stow_transform()
		var d: float = _held_in(i, anim).origin.distance_to(slung.origin)
		if d < nearest:
			nearest = d
			at_nearest = at
	return at_nearest


## Where character `i`'s item is put away (its HOLD, world).
func _stowed_hold(i: int) -> Transform3D:
	var sk: Skeleton3D = _skels[i]
	var bone: int = sk.find_bone(String(grip.stow_bone))
	return sk.global_transform * sk.get_bone_global_pose(bone) * grip.stow_transform() if bone >= 0 \
		else _held_in(i, _anim())


## From the item's hold to its root while put away: packed to the grip file's stow length
## (DECISIONS #161), as the game packs it.
func _packed_inv() -> Transform3D:
	return _hold_inv * grip.packing(_hold_inv.affine_inverse(), 1.0)


## Where character `i`'s item is drawn: put away when Show Stowed is ticked, else in the hand.
func _place(i: int, anim: StringName) -> Transform3D:
	if show_stowed and grip.stows():
		return _stowed_hold(i) * _packed_inv()
	return _item_at(i, anim)


## THE STOW node: placed where the grip file puts the item away on the first character; moved, it
## sets that place (in the stow bone's frame).
func _sync_stow() -> void:
	var node: Node3D = get_node_or_null(^"Stow") as Node3D
	if node == null or _skels.is_empty():
		return
	var sk: Skeleton3D = _skels[0]
	var bone: int = sk.find_bone(String(grip.stow_bone))
	if bone < 0:
		return
	var on_bone: Transform3D = sk.global_transform * sk.get_bone_global_pose(bone)
	var want: Transform3D = on_bone * grip.stow_transform()
	if _stow_known and not node.global_transform.is_equal_approx(_stow_set):
		grip.set_stow_transform(on_bone.affine_inverse() * node.global_transform)
		_stow_set = node.global_transform
	elif not _stow_known or not want.is_equal_approx(_stow_set):
		node.global_transform = want
		_stow_set = node.global_transform
		_stow_known = true


# --- pictures -----------------------------------------------------------------------------

const PICTURE_SIZE: Vector2i = Vector2i(480, 360)
const PICTURE_COLUMNS: int = 4
const PICTURES_DIR: String = "res://grip_pictures"


## SAVE PICTURES: every animation, at its first frame and at the frame where the item comes
## closest to the first character's body, through this scene's camera, into one sheet
## (`res://grip_pictures/<grip>.png`, or `to`). Needs a renderer (the editor, or a windowed run).
## Returns the file written, or "".
func save_pictures_now(to: String = "") -> String:
	var cam: Camera3D = get_node_or_null(^"Camera3D") as Camera3D
	if grip == null or _skels.is_empty() or cam == null or _picturing:
		return ""
	_picturing = true
	var vp: SubViewport = SubViewport.new()
	vp.size = PICTURE_SIZE
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp, false, Node.INTERNAL_MODE_BACK)
	var eye: Camera3D = Camera3D.new()
	vp.add_child(eye)
	eye.global_transform = cam.global_transform
	eye.fov = cam.fov
	eye.current = true
	var caption: Label = Label.new()
	caption.position = Vector2(8.0, 6.0)
	caption.add_theme_font_size_override(&"font_size", 15)
	caption.add_theme_constant_override(&"outline_size", 5)
	caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	vp.add_child(caption)
	for l: Label3D in _labels:
		l.visible = false
	var shots: Array[Array] = []
	for a: StringName in _set_animations():
		if not _players[0].has_animation(_clip_of(a)):
			continue
		shots.append([a, 0.0, false])
		shots.append([a, _closest_at(a), false])
	if grip.stows():
		shots.append([AnimationSet.IDLE, 0.0, true])
		shots.append([AnimationSet.RUN, 0.3, true])
	var rows: int = ceili(float(shots.size()) / float(PICTURE_COLUMNS))
	var sheet: Image = Image.create_empty(PICTURE_SIZE.x * PICTURE_COLUMNS, PICTURE_SIZE.y * rows,
		false, Image.FORMAT_RGBA8)
	var ok: bool = true
	for n: int in range(shots.size()):
		var a: StringName = shots[n][0]
		var at: float = shots[n][1]
		var away: bool = shots[n][2]
		var words: PackedStringArray = ["%s%s  %d%%" % ["put away · " if away else "", a, roundi(at * 100.0)]]
		var keep_stowed: bool = show_stowed
		show_stowed = away
		for i: int in range(_skels.size()):
			_seek(i, a, at)
			_items[i].global_transform = _place(i, a)
			var air: float = float(BodyClearance.item_air(_skels[i], _items[i])["air"])
			words.append("%s: %s, %.1f cm %s" % [_body_types[i] if not _body_types[i].is_empty() else _names[i],
				_grip_name(grip.resolve(a, _body_types[i])), absf(air) * 100.0, "clear" if air >= 0.0 else "INSIDE"])
		show_stowed = keep_stowed
		caption.text = "\n".join(words)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		if img == null or img.is_empty():
			ok = false
			break
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, PICTURE_SIZE),
			Vector2i((n % PICTURE_COLUMNS) * PICTURE_SIZE.x, int(float(n) / float(PICTURE_COLUMNS)) * PICTURE_SIZE.y))
	vp.queue_free()
	for l: Label3D in _labels:
		l.visible = true
	_picturing = false
	_posed = false
	if not ok:
		push_warning("Save Pictures: nothing was drawn (a headless run has no renderer)")
		return ""
	var file_name: String = grip.resource_path.get_file().get_basename() if not grip.resource_path.is_empty() else "grip"
	var path: String = ProjectSettings.globalize_path(to)
	if to.is_empty():
		var dir: String = ProjectSettings.globalize_path(PICTURES_DIR)
		DirAccess.make_dir_recursive_absolute(dir)
		if not FileAccess.file_exists(dir.path_join(".gdignore")):
			FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
		path = dir.path_join(file_name + ".png")
	sheet.save_png(path)
	print("Save Pictures: ", path)
	_fit_said = "pictures: grip_pictures/%s.png" % file_name
	return path


## Where through `anim` the item comes closest to the first character's body (0..1).
func _closest_at(anim: StringName) -> float:
	var worst: float = INF
	var at_worst: float = 0.0
	for k: int in range(CLIP_SAMPLES + 1):
		var at: float = float(k) / float(CLIP_SAMPLES)
		_seek(0, anim, at)
		_items[0].global_transform = _item_at(0, anim)
		var air: float = float(BodyClearance.item_air(_skels[0], _items[0])["air"])
		if air < worst:
			worst = air
			at_worst = at
	return at_worst


# --- for tests ------------------------------------------------------------------------------

func body_count() -> int:
	return _skels.size()


func look_name(i: int) -> String:
	return _names[i]


func hand_of(i: int) -> Transform3D:
	return _hand(i)


func body_of(i: int) -> Basis:
	return _skels[i].global_basis


func item_of(i: int) -> Node3D:
	return _items[i]


func label_of(i: int) -> Label3D:
	return _labels[i]


## The item's air off a body in the frame shown, and its least through the whole clip (metres,
## negative: inside).
func air_here(i: int) -> float:
	return float(BodyClearance.item_air(_skels[i], _items[i])["air"])


func worst_air(i: int) -> float:
	return _worst[i]


## The grip being edited, or null while that animation (in that body's hand) still borrows.
func editing() -> GripEntry:
	return grip.find(_anim(), _body_key()) if grip != null else null


## The character holding the Grip node (-1: none of the chosen body is shown).
func holder() -> int:
	return _holder


## What the last fit said.
func fit_said() -> String:
	return _fit_said


## How far the item's handle is out of a character's fist in the frame shown (degrees).
func out_of_fist(i: int) -> float:
	var hold: Transform3D = grip.blend({_anim(): 1.0}, _hand(i), _skels[i].global_basis, _body_types[i])
	var h: Dictionary = GripFit.hole(_skels[i], grip.hand)
	var axis: Vector3 = h["axis"] as Vector3 if not h.is_empty() and bool(h["fist"]) else _fist_axis[i]
	return rad_to_deg(hold.basis.y.angle_to(axis)) if axis != Vector3.ZERO else 0.0



## The hole a character's hand makes `at` (0..1) through `anim` (`GripFit.hole`), its fingers shut
## round the item as the game shuts them (`closed` false: as the clip has them); the pose shown is
## put back.
func hole_of(i: int, anim: StringName, at: float, closed: bool = true) -> Dictionary:
	_seek(i, anim, at)
	if not closed:
		var raw: Dictionary = _raw_fingers[i]
		for b: int in raw:
			_skels[i].set_bone_pose_rotation(b, raw[b])
	var h: Dictionary = GripFit.hole(_skels[i], grip.hand if grip != null else &"hand_r")
	_seek(i, _anim(), _at)
	return h


## Which body a character is (`female`, `male`; "" when its look does not say).
func body_type_of(i: int) -> StringName:
	return _body_types[i]


# --- building -------------------------------------------------------------------------------

func _build() -> void:
	_built = true
	_posed = false
	_grip_known = false
	for list: Array in [_names, _skels, _players, _items, _labels, _hands, _body_types, _worst, _worst_at,
			_worst_part, _raw_hand, _fist_axis, _raw_fingers, _fists, _fist_from]:
		list.clear()
	_carry_known = false
	# Everything built here is an internal child: this frees it all, a previous version's too.
	var own: Array[Node] = get_children()
	for n: Node in get_children(true):
		if not own.has(n):
			n.queue_free()
	if definition == null or item == null:
		return
	var looks: Array[PackedScene] = definition.visual_variants.duplicate()
	if looks.is_empty() and definition.visual_scene != null:
		looks.append(definition.visual_scene)
	if looks.is_empty():
		return
	var picks: Array[int] = [look]
	if beside >= 0 and beside != look:
		picks.append(beside)
	for k: int in range(picks.size()):
		_add_body(looks[clampi(picks[k], 0, looks.size() - 1)], BESIDE_AT * float(k))
	notify_property_list_changed()


func _add_body(scene: PackedScene, at: Vector3) -> void:
	var model: Node3D = scene.instantiate() as Node3D
	add_child(model, false, Node.INTERNAL_MODE_BACK)
	model.position = at
	model.rotation.y = deg_to_rad(definition.visual_yaw_deg)
	# The first skeleton, as the game finds it.
	var skel: Skeleton3D = null
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var hand_name: StringName = grip.hand if grip != null else &"hand_r"
	if skel == null or skel.find_bone(String(hand_name)) < 0:
		model.queue_free()
		return
	var player := AnimationPlayer.new()
	var set: AnimationSet = definition.animation_set
	if set != null:
		for lib_name: StringName in set.libraries:
			if set.libraries[lib_name] != null:
				player.add_animation_library(lib_name, set.libraries[lib_name])
	model.add_child(player, false, Node.INTERNAL_MODE_BACK)
	player.root_node = player.get_path_to(skel.get_parent())
	var held: Node3D = item.instantiate() as Node3D
	add_child(held, false, Node.INTERNAL_MODE_BACK)
	_hold_inv = GripFit.hold_of(held).affine_inverse()
	var label := Label3D.new()
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	# The first one's label leans away from the second, the second's away from the first.
	label.position = at + Vector3(0.45 if at.is_zero_approx() else -0.45, 2.15, 0.0)
	add_child(label, false, Node.INTERNAL_MODE_BACK)
	_names.append(scene.resource_path.get_file().get_basename())
	_skels.append(skel)
	_players.append(player)
	_items.append(held)
	_labels.append(label)
	_hands.append(skel.find_bone(String(hand_name)))
	_body_types.append(StringName(skel.get_meta(&"body", &"")))
	_worst.append(INF)
	_worst_at.append(0.0)
	_worst_part.append("")
	_raw_hand.append(skel.get_bone_pose_rotation(skel.find_bone(String(hand_name))))
	_fist_axis.append(Vector3.ZERO)
	_raw_fingers.append({})
	_fists.append({})
	_fist_from.append(&"")


# --- the grip, the pose, the air ------------------------------------------------------------

func _anim() -> StringName:
	var key: String = animation.get_slice(LABEL_SEP, 0).strip_edges()
	return StringName(key) if not key.is_empty() else AnimationSet.IDLE


## AN ANIMATION AS THE LIST NAMES IT (DECISIONS #262): its semantic name, then what it is: an ability's
## name (`ability.40002 · Slash (second)`), and the clip it plays (`· Sword_Light_B`). Only the semantic
## name before the first ` · ` counts; the rest is for reading.
func animation_label(semantic: String) -> String:
	var parts: Array[String] = [semantic]
	if semantic.begins_with("ability.") and semantic.get_slice(".", 1).is_valid_int():
		var named: String = _ability_name(int(semantic.get_slice(".", 1)))
		if not named.is_empty():
			parts.append(named)
	if definition != null and definition.animation_set != null and definition.animation_set.clips.has(StringName(semantic)):
		var ref: Resource = definition.animation_set.clips[StringName(semantic)]
		var clip: String = String(ref.get(&"anim_name")) if ref != null else ""
		if not clip.is_empty():
			parts.append(clip.get_file())
	# A comma would split the Inspector's list.
	return LABEL_SEP.join(parts).replace(",", "")


## An ability's name by id, read once per preview from the game's content (the library loads every file).
func _ability_name(id: int) -> String:
	if not _abilities_read:
		_abilities_read = true
		for def: ContentDef in ContentLibrary.items(&"ability"):
			_ability_names[def.id] = def.display_name
	return String(_ability_names.get(id, ""))


## The body whose grip is edited, as the grip file keys it ("" is every body's).
func _body_key() -> StringName:
	return &"" if body.is_empty() or body == BOTH else StringName(body)


## Who holds the Grip node: the first character of the chosen body; for "both", the first whose
## item shows the shared grip (one with a grip of its own body's would not move with the drag).
func _pick_holder() -> int:
	var key: StringName = _body_key()
	if not key.is_empty():
		return _body_types.find(key)
	var shared: GripEntry = grip.resolve(_anim())
	for i: int in range(_skels.size()):
		if grip.resolve(_anim(), _body_types[i]) == shared:
			return i
	return 0


## The grip being edited if it exists, else the one it would start from (what that body borrows).
func _shown_for_edit() -> GripEntry:
	if grip == null:
		return null
	var own: GripEntry = grip.find(_anim(), _body_key())
	return own if own != null else grip.resolve(_anim(), _body_key())


## Where the item's HOLD is for this character (world): as the game blends it, with `anim` fully
## showing, for this character's body. The item hangs from it (`_item_at`).
func _held_in(i: int, anim: StringName) -> Transform3D:
	var hand: Transform3D = _hand(i)
	return hand * grip.blend({anim: 1.0}, hand, _skels[i].global_basis, _body_types[i])


func _item_at(i: int, anim: StringName) -> Transform3D:
	return _held_in(i, anim) * _hold_inv


## THE WRIST, as the game turns it (`HoldWrist`, and the held item's wrist_turn_now): from the hand the clip
## posed, its fingers shut round the item (`_close_hand`), laid along the item when the grip `anim`
## uses is steady.
func _turn_wrist(i: int, anim: StringName) -> void:
	var sk: Skeleton3D = _skels[i]
	var bone: int = _hands[i]
	sk.set_bone_pose_rotation(bone, _raw_hand[i])
	_close_hand(i)
	if grip == null:
		return
	var h: Dictionary = GripFit.hole(sk, grip.hand)
	if not h.is_empty() and bool(h["fist"]):
		_fist_axis[i] = h["axis"]
	var e: GripEntry = grip.resolve(anim, _body_types[i])
	if e == null or not e.is_steady() or grip.wrist_turn_deg <= 0.0 or _fist_axis[i] == Vector3.ZERO \
			or (show_stowed and grip.stows()):
		return
	var hand: Transform3D = sk.get_bone_global_pose(bone)
	var turn: Basis = GripFit.wrist_turn(hand.basis, _fist_axis[i], e.basis() * Vector3.UP, grip.wrist_turn_deg)
	var parent: int = sk.get_bone_parent(bone)
	var above: Transform3D = sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local: Transform3D = above.affine_inverse() * Transform3D(turn * hand.basis, hand.origin)
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())


## THE FINGERS, as the game closes them round the item (the held item's close_fist_now, DECISIONS #160):
## the clip's own, shut toward the grip file's fist as far as the clip opened them (a jump). Not
## while the item is shown put away: the hand is free.
func _close_hand(i: int) -> void:
	var sk: Skeleton3D = _skels[i]
	var raw: Dictionary = _raw_fingers[i]
	for b: int in raw:
		sk.set_bone_pose_rotation(b, raw[b])
	if grip == null or grip.fist_animation.is_empty() or (show_stowed and grip.stows()):
		return
	GripFit.close_fist(sk, grip.hand, _fist_of(i))


## The fist character `i` closes round the item: the grip file's `fist_animation`, its first frame.
func _fist_of(i: int) -> Dictionary:
	if grip == null or grip.fist_animation.is_empty():
		return {}
	if _fist_from[i] != grip.fist_animation:
		_fist_from[i] = grip.fist_animation
		var clip: StringName = _clip_of(grip.fist_animation)
		var anim: Animation = _players[i].get_animation(clip) if _players[i].has_animation(clip) else null
		_fists[i] = GripFit.fist_pose(_skels[i], grip.hand, anim)
	return _fists[i]


## THE CARRY POINT node (DECISIONS #159): ON the first character's hand, where the fist closes,
## turned the way a carried item is held: its +Y (green) where it points, its +Z (blue) the way the
## item's own +Z faces (a rod's reel is on the other side). TURN it: that sets the grip file's
## carry_point and fit_face, and a moment later the animation shown, if it only carries the item,
## is fitted to it. Moving it does nothing: it lives on the hand. While Play is ticked it rides the
## moving hand and is not read: untick Play to turn it.
func _sync_carry_point() -> void:
	var node: Node3D = get_node_or_null(^"CarryPoint") as Node3D
	if node == null or _skels.is_empty():
		return
	var body: Basis = _skels[0].global_basis.orthonormalized()
	var on_hand: Vector3 = _held_in(0, _anim()).origin
	var want: Basis = _carry_basis(body)
	if play:
		# Playing, it rides on the moving hand, shown from the file: untick Play to turn it.
		node.global_transform = Transform3D(want, on_hand)
		_carry_turn = node.global_basis.orthonormalized()
		_carry_known = true
		return
	if _carry_known and not node.global_basis.orthonormalized().is_equal_approx(_carry_turn):
		var b: Basis = node.global_basis.orthonormalized()
		grip.carry_point = GripFit.body_dir(body.inverse() * b.y).snapped(Vector3.ONE * 0.001)
		grip.fit_face = GripFit.body_dir(body.inverse() * b.z).snapped(Vector3.ONE * 0.001)
		_carry_turn = b
		_refit_at = Time.get_ticks_msec() + REFIT_DELAY_MSEC
		node.global_position = on_hand
	elif not _carry_known or not want.is_equal_approx(_carry_turn) or not node.global_position.is_equal_approx(on_hand):
		node.global_transform = Transform3D(want, on_hand)
		_carry_turn = node.global_basis.orthonormalized()
		_carry_known = true


## The carried item's turn, from the grip file's carry_point and fit_face (tip-up-and-forward, the
## reel below, when they are not set).
func _carry_basis(body: Basis) -> Basis:
	var y: Vector3 = (body * GripFit.body_dir(grip.carry_point if not grip.carry_point.is_zero_approx()
		else Vector3(0.0, 1.0, 1.0))).normalized()
	var face: Vector3 = body * GripFit.body_dir(grip.fit_face if not grip.fit_face.is_zero_approx()
		else Vector3(0.0, 1.0, 0.0))
	var z: Vector3 = face - y * face.dot(y)
	if z.length() < 0.001:
		z = y.cross(body.x)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


func _measure_worst(i: int) -> void:
	_worst[i] = INF
	_worst_part[i] = ""
	if BodyClearance.points_of(_items[i]).is_empty():
		return
	var keep: Transform3D = _items[i].global_transform
	for k: int in range(CLIP_SAMPLES + 1):
		var at: float = float(k) / float(CLIP_SAMPLES)
		_seek(i, _anim(), at)
		_items[i].global_transform = _place(i, _anim())
		var r: Dictionary = BodyClearance.item_air(_skels[i], _items[i])
		if float(r["air"]) < _worst[i]:
			_worst[i] = float(r["air"])
			_worst_at[i] = at
			_worst_part[i] = "%s against the %s" % [r["point"], r["part"]]
	_seek(i, _anim(), _at)
	_items[i].global_transform = keep


func _show(i: int) -> void:
	var text: String = ""
	if i == _holder:
		text = "SETTING %s\n" % _editing_text()
		if not _fit_said.is_empty():
			text += _fit_said + "\n"
	elif i == 0 and _holder < 0:
		text = "SETTING %s\n(no %s character here: pick a look)\n" % [_editing_text(), body]
	text += _names[i] + ("  (%s)" % _body_types[i] if not _body_types[i].is_empty() else "")
	if show_stowed and grip.stows():
		text += "\nput away on %s" % grip.stow_bone
	else:
		text += "\nuses %s" % _grip_name(grip.resolve(_anim(), _body_types[i]))
		var out: float = out_of_fist(i)
		text += "\nin the fist" if out < 5.0 else "\nthe handle %d deg out of the fist" % roundi(out)
	if _worst[i] != INF:
		var r: Dictionary = BodyClearance.item_air(_skels[i], _items[i])
		text += "\n%s here\n%s at worst (%d%% in)\n%s" % [_air_text(float(r["air"])),
			_air_text(_worst[i]), roundi(_worst_at[i] * 100.0), _worst_part[i]]
		_labels[i].modulate = Color(0.7, 1.0, 0.7) if _worst[i] >= ENOUGH_AIR \
			and float(r["air"]) >= ENOUGH_AIR else Color(1.0, 0.55, 0.45)
	else:
		_labels[i].modulate = Color(0.85, 0.9, 1.0)
	_labels[i].text = text


## The grip being edited, in words: which, and whether a drag will make it.
func _editing_text() -> String:
	var key: StringName = _body_key()
	var line: String = "%s · %s" % [_anim(), BOTH if key.is_empty() else String(key)]
	var own: GripEntry = grip.find(_anim(), key)
	if own == null:
		return line + ("\n(not set: uses the universal grip; a drag makes a spot fix)" if grip.universal
			else "\n(not set: a drag sets it, from here)")
	if own.relative:
		return line + " · spot fix on the universal grip"
	return line + (" · universal" if grip.universal and own.animation == AnimationSet.IDLE else "") \
		+ (" · steady" if own.steady else "")


## A grip as a label names it: its animation and its body, and steady when it is.
static func _grip_name(e: GripEntry) -> String:
	if e == null:
		return "no grip"
	return "%s · %s%s%s" % [e.animation, BOTH if e.body.is_empty() else String(e.body),
		" · spot fix" if e.relative else "", " · steady" if e.is_steady() else ""]


static func _air_text(air: float) -> String:
	return "%.1f cm %s" % [absf(air) * 100.0, "clear" if air >= 0.0 else "INSIDE"]


## Every grip's numbers (and the file's own settings), so a change from anywhere is seen.
func _signature() -> String:
	var parts: PackedStringArray = ["%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [grip.universal, grip.carry_point, grip.fit_face,
		grip.fit_cone_deg, grip.wrist_turn_deg, grip.stow_bone, grip.stow_position,
		grip.stow_rotation_degrees, grip.draw_swap_at, grip.stow_swap_at, grip.stow_point, grip.stow_face]]
	for e: GripEntry in grip.entries:
		if e != null:
			parts.append("%s|%s|%s|%s|%s|%s" % [e.animation, e.body, e.position, e.rotation_degrees, e.steady, e.relative])
	return ";".join(parts)


func _clip_length() -> float:
	var clip: StringName = _clip_of(_anim())
	return _players[0].get_animation(clip).length if _players[0].has_animation(clip) else 0.0


## Pose a character `at` (0..1) through `semantic`'s clip, its fingers shut round the item as the
## game shuts them, and turn its wrist as the game would (`turn`; a fit wants the clip's own wrist).
func _seek(i: int, semantic: StringName, at: float, turn: bool = true) -> void:
	var clip: StringName = _clip_of(semantic)
	var player: AnimationPlayer = _players[i]
	if not player.has_animation(clip):
		return
	var length: float = player.get_animation(clip).length
	player.play(clip)
	player.seek(clampf(at, 0.0, 1.0) * length, true)
	player.pause()
	_raw_hand[i] = _skels[i].get_bone_pose_rotation(_hands[i])
	var raw: Dictionary = {}
	for b: int in _fist_of(i):
		raw[b] = _skels[i].get_bone_pose_rotation(b)
	_raw_fingers[i] = raw
	if turn:
		_turn_wrist(i, semantic)
	else:
		_close_hand(i)


func _hand(i: int) -> Transform3D:
	return _skels[i].global_transform * _skels[i].get_bone_global_pose(_hands[i])


## The clip a semantic names in the set, read from its DATA, following the set's fallbacks. In
## the editor only TOOL scripts run: `AnimationSet`, `EntityDefinition` and the item's own script
## are data there, their methods absent, so nothing here may call one (DECISIONS #147).
func _clip_of(semantic: StringName) -> StringName:
	var set: AnimationSet = definition.animation_set if definition != null else null
	if set == null:
		return &""
	var seen: Array[StringName] = []
	var name: StringName = semantic
	while not name.is_empty() and not seen.has(name):
		seen.append(name)
		if set.clips.has(name):
			var ref: AnimationClipRef = set.clips[name]
			if ref != null:
				return ref.anim_name
		var alts: Array = AnimationSet.FALLBACKS.get(name, [] as Array)
		name = StringName(alts[0]) if not alts.is_empty() else &""
	return &""
