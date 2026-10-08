@tool
class_name GripFit
## FIT AN ITEM IN THE HAND without dragging it there (DECISIONS #157, #158). Luke: "can we not
## design our rod / scale our other items to fit in the hole that the hand animations use, and
## then take pictures to get the angle right, with minimal user intervening other than checking
## the end goal?"
##
##   1. THE HOLE. A hand closed round nothing still leaves a hole: its curled fingers lie on a
##      circle round it. `hole` finds that circle from the finger bones: its centre, and its line
##      (from the little finger to the index, the way a blade or a rod's tip comes out of a fist),
##      in the HAND's frame. The item's HOLD (`hold_of`: its `Hold` node, else its root) goes on
##      the centre.
##   2. WHERE IT POINTS. An animation that USES the item (a cast, a heave, a swing) was animated
##      round something held: the item goes along the fist's line, and the grip file's
##      `ItemGrip.fit_face` only rolls it round that line (which way a rod's reel hangs). An
##      animation that only CARRIES it (standing, walking, running, jumping: CARRY_FOR) has a
##      relaxed hand whose line points wherever: there the item is held STEADY toward
##      `ItemGrip.carry_point`, the same in every one of them, and the WRIST TURNS (up to
##      `ItemGrip.wrist_turn_deg`, `wrist_turn`) to lay the fist along it, as a person carrying a
##      rod does. With no carry_point, along the fist, and steady only when the clip swings it.
##   3. IN THE FIST AND CLEAR OF THE BODY through the whole clip. The handle may leave the fist's
##      line by no more than `ItemGrip.fit_cone_deg` (what the wrist could not turn: the fingers
##      would show through it), and the item must clear the body by ENOUGH_AIR (`BodyClearance`).
##      If either fails, the turns round it are tried, and the least turn that does both wins
##      (else the one that comes nearest).
##
##   4. THE HAND STAYS SHUT ROUND IT (DECISIONS #160). A clip that opens the hand (a jump flings the
##      fingers wide) would let the item through them: while the item is in the hand, `close_fist`
##      turns the fingers back toward the fist of the grip file's `ItemGrip.fist_animation` (the
##      idle's), as far as the clip opened them. A clip that makes a fist is left alone, so every
##      grip fitted to a fist still fits.
##
## A TOOL script: the preview calls it with what it reads off its posed characters, and the game's
## wrist (`HoldWrist`) calls `wrist_turn` and `close_fist`. Engine types in and out, and no node of
## its own.

## The fingers a closed hand curls round a handle, and the joints along each that lie on the
## circle (the knuckle, `_01`, sets the line instead).
const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]
const JOINTS: Array[String] = ["_02", "_03", "_04_leaf"]
## A hand is a FIST when the circle fits its fingers this closely (metres) and they curl this far.
const FIST_FIT: float = 0.012
const FIST_CURL_DEG: float = 90.0
## A hand curled this much less than a fist is closed all the way round a held item (`close_fist`);
## between, part way.
const FIST_OPEN_SPAN_DEG: float = 45.0
## The bones a hand closes round a handle: the thumb's and every finger's.
const FIST_BONES: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
## Animations that only CARRY the item (by the start of their semantic name): their hands hold
## nothing in particular, and their arms sway, which the item should not follow. Everything else
## uses the item, on purpose.
const CARRY_FOR: Array[String] = ["locomotion.", "jump."]
const STEADY_SWING_DEG: float = 15.0
## The air off the body a fit is happy with (what the preview's labels call green).
const ENOUGH_AIR: float = 0.02
## About half a finger's thickness (metres): a handle in a hole of radius r (to the bones' lines)
## wants a radius of about r less this. Judged by eye on Quaternius' gloved hands: in a hole of
## 1.6 cm the rod's cork looks gripped at 1 cm and shows through the fingers at 2 cm (#158).
const FINGER_HALF: float = 0.006
## The node in an item's scene that says where the fist closes on it.
const HOLD_NODE: String = "Hold"
## The turns tried round a grip that does not fit (degrees): about the item's own X and Z, and
## all the way round its axis (a reel can swing off a leg the hand brushes); then finer round
## the best.
const TILT_DEG: Array[float] = [-30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0]
const ROLL_DEG: Array[float] = [-150.0, -120.0, -90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0]
const FINE_DEG: Array[float] = [-5.0, 0.0, 5.0]


## THE HOLE a hand's curled fingers make, in the HAND's frame: {"centre": Vector3, "axis": Vector3,
## "radius": float, "fist": bool, "error": float, "curl_deg": float}. Empty when the skeleton has
## no such hand or fingers.
##
## Its LINE runs across the knuckles, from the little finger's to the index's. Its CENTRE is the
## middle of the biggest circle that fits inside the fist, seen down that line: walled by the palm
## (the wrist to each knuckle), the curled fingers (knuckle, joints, tip) and the gap from the
## fingertips back to the wrist. A circle through the finger joints alone sat down among them,
## and a handle on it showed through the fingers (#158). `radius` is that circle's, to the bones'
## lines: a handle wants about a finger's half-thickness (FINGER_HALF) less. `error` and
## `curl_deg` say whether the hand is closed at all (`fist`): how far its finger joints are off one
## circle, and how far its fingers curl. `with_centre` false skips the circle (the game's wrist
## needs only the line, every frame).
static func hole(skeleton: Skeleton3D, hand: StringName, with_centre: bool = true) -> Dictionary:
	var side: String = String(hand).trim_prefix("hand")
	var hand_i: int = skeleton.find_bone(String(hand))
	var index_i: int = skeleton.find_bone("index_01" + side)
	var pinky_i: int = skeleton.find_bone("pinky_01" + side)
	if hand_i < 0 or index_i < 0 or pinky_i < 0:
		return {}
	var into_hand: Transform3D = skeleton.get_bone_global_pose(hand_i).affine_inverse()
	var axis: Vector3 = (into_hand * skeleton.get_bone_global_pose(index_i).origin
		- into_hand * skeleton.get_bone_global_pose(pinky_i).origin).normalized()
	var u: Vector3 = axis.cross(Vector3.UP)
	if u.length() < 0.3:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var points: PackedVector2Array = PackedVector2Array()
	var chains: Array[PackedVector2Array] = []
	var curl: float = 0.0
	for f: String in FINGERS:
		var bones: Array[Vector3] = []
		for j: String in ["_01", "_02", "_03", "_04_leaf"]:
			var b: int = skeleton.find_bone(f + j + side)
			if b < 0:
				return {}
			bones.append(into_hand * skeleton.get_bone_global_pose(b).origin)
		for k: int in range(1, 4):
			points.append(Vector2(bones[k].dot(u), bones[k].dot(v)))
		# The wrist, the knuckle, the joints, the tip, and back to the wrist: round the inside.
		var ring: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		for q: Vector3 in bones:
			ring.append(Vector2(q.dot(u), q.dot(v)))
		chains.append(ring)
		curl += rad_to_deg(bones[0].angle_to(bones[3] - bones[2]))
	curl /= float(FINGERS.size())
	var circle: Array = _circle(points)
	var out: Dictionary = {"axis": axis, "error": float(circle[2]), "curl_deg": curl,
		"fist": float(circle[2]) <= FIST_FIT and curl >= FIST_CURL_DEG}
	if not with_centre:
		return out
	var inside: Array = _inscribed(chains, circle[0] as Vector2)
	var flat: Vector2 = inside[0]
	var centre: Vector3 = u * flat.x + v * flat.y
	# Along the line, level with the middle finger's knuckle: the middle of the grip.
	var middle_i: int = skeleton.find_bone("middle_01" + side)
	var middle: Vector3 = into_hand * skeleton.get_bone_global_pose(middle_i).origin
	centre += axis * (middle.dot(axis) - centre.dot(axis))
	out["centre"] = centre
	out["radius"] = float(inside[1])
	return out


## THE FIST an item is held in: each of `hand`'s finger and thumb bones' poses (its rotation from
## its parent) in `animation`, `at` seconds in, by bone index. Empty when the clip keys none.
static func fist_pose(skeleton: Skeleton3D, hand: StringName, animation: Animation, at: float = 0.0) -> Dictionary[int, Quaternion]:
	var out: Dictionary[int, Quaternion] = {}
	if skeleton == null or animation == null:
		return out
	var side: String = String(hand).trim_prefix("hand")
	for t: int in range(animation.get_track_count()):
		if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name: String = animation.track_get_path(t).get_concatenated_subnames()
		if not bone_name.ends_with(side) or not FIST_BONES.any(func(f: String) -> bool: return bone_name.begins_with(f + "_")):
			continue
		var b: int = skeleton.find_bone(bone_name)
		if b >= 0:
			out[b] = animation.rotation_track_interpolate(t, at)
	return out


## CLOSE THE HAND round a held item: each finger and thumb bone turned toward `fist` (`fist_pose`)
## as far as the clip has opened the hand, none for a fist (FIST_CURL_DEG or more) and all the way
## at FIST_OPEN_SPAN_DEG less. Call it on the clip's own pose. Returns how far it closed it, 0..1.
static func close_fist(skeleton: Skeleton3D, hand: StringName, fist: Dictionary) -> float:
	if skeleton == null or fist.is_empty():
		return 0.0
	var h: Dictionary = hole(skeleton, hand, false)
	if h.is_empty():
		return 0.0
	var w: float = clampf((FIST_CURL_DEG - float(h["curl_deg"])) / FIST_OPEN_SPAN_DEG, 0.0, 1.0)
	if w <= 0.0:
		return 0.0
	for b: int in fist:
		skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(fist[b] as Quaternion, w))
	return w


## The middle of the biggest circle inside the middle finger's ring (`chains[1]`: wrist, knuckle,
## joints, tip, closed back to the wrist) that clears every finger's ring: [centre, radius].
## Searched on a grid round `near`, coarse then fine.
static func _inscribed(chains: Array[PackedVector2Array], near: Vector2) -> Array:
	var ring: PackedVector2Array = chains[mini(1, chains.size() - 1)]
	var best: Vector2 = near
	var best_r: float = -INF
	for pass_step: Array in [[0.003, 14], [0.0005, 8]]:
		var step: float = pass_step[0]
		var reach: int = pass_step[1]
		var around: Vector2 = best if best_r > -INF else near
		for i: int in range(-reach, reach + 1):
			for j: int in range(-reach, reach + 1):
				var p: Vector2 = around + Vector2(float(i), float(j)) * step
				if not Geometry2D.is_point_in_polygon(p, ring):
					continue
				var r: float = INF
				for c: PackedVector2Array in chains:
					for k: int in range(c.size()):
						var a: Vector2 = c[k]
						var b: Vector2 = c[(k + 1) % c.size()]
						r = minf(r, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
				if r > best_r:
					best_r = r
					best = p
	if best_r == -INF:
		return [near, 0.0]
	return [best, best_r]


## What a fit needs of one posed frame: the hand (world, as the clip has it: the wrist not turned),
## the body's basis, the body's parts (`BodyClearance.posed`) and the hand's hole.
static func frame_of(skeleton: Skeleton3D, hand: StringName) -> Dictionary:
	var hand_i: int = skeleton.find_bone(String(hand))
	return {"hand": skeleton.global_transform * skeleton.get_bone_global_pose(hand_i),
		"body": skeleton.global_basis, "parts": BodyClearance.posed(skeleton),
		"hole": hole(skeleton, hand)}


# --- the item ---------------------------------------------------------------------------------

## WHERE THE FIST CLOSES ON AN ITEM, in the item's frame: its `Hold` node (placed in the item's
## scene; its +Y along the handle out past the thumb, its +Z back toward the wrist), else its
## root. A grip says where the HOLD sits in the hand; the item hangs from it.
static func hold_of(item: Node3D) -> Transform3D:
	var hold: Node3D = item.get_node_or_null(NodePath(HOLD_NODE)) as Node3D if item != null else null
	return in_item(item, hold) if hold != null else Transform3D()


## An item's measured points and lines (`BodyClearance`), in its HOLD's frame: [name, from, to,
## radius] each. Read through the nodes' own transforms, not the world, so the same item gives
## the same numbers wherever it happens to be held (a fit that cannot clear picks between turns a
## hair apart).
static func marks_of(item: Node3D) -> Array[Array]:
	var out: Array[Array] = []
	var into_hold: Transform3D = hold_of(item).affine_inverse()
	for n: Node3D in BodyClearance.points_of(item):
		var to: Node3D = n.get_node_or_null(n.get_meta(BodyClearance.LINE_TO) as NodePath) as Node3D \
			if n.has_meta(BodyClearance.LINE_TO) else null
		var from: Vector3 = into_hold * in_item(item, n).origin
		out.append([String(n.name), from, into_hold * in_item(item, to).origin if to != null else from,
			float(n.get_meta(BodyClearance.META))])
	return out


## Where `node` is in `item`'s frame, through the transforms between them.
static func in_item(item: Node3D, node: Node3D) -> Transform3D:
	var at: Transform3D = Transform3D()
	var n: Node = node
	while n != null and n != item:
		var n3: Node3D = n as Node3D
		if n3 != null:
			at = n3.transform * at
		n = n.get_parent()
	return at


## A direction given in the BODY's terms (x to the character's right, y up, z forward) in the
## skeleton's own frame (whose +X is the character's left). Its own inverse.
static func body_dir(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Whether an animation only carries the item (CARRY_FOR).
static func carries(animation: StringName) -> bool:
	for prefix: String in CARRY_FOR:
		if String(animation).begins_with(prefix):
			return true
	return false


# --- the wrist ----------------------------------------------------------------------------------

## THE WRIST TURN (DECISIONS #158): the turn of the hand about the wrist, in the frame
## `hand_basis` is in, that lays the fist's line (`fist_axis`, in the hand's frame) along `want`,
## by the shortest way and no more than `limit_deg`. A person carrying a rod steady bends the
## wrist to keep it in the fist; what the wrist cannot reach shows as the handle leaving the fist.
static func wrist_turn(hand_basis: Basis, fist_axis: Vector3, want: Vector3, limit_deg: float) -> Basis:
	var a: Vector3 = (hand_basis.orthonormalized() * fist_axis).normalized()
	var w: Vector3 = want.normalized()
	var angle: float = a.angle_to(w)
	if angle < 0.00001 or limit_deg <= 0.0 or a.is_zero_approx() or w.is_zero_approx():
		return Basis.IDENTITY
	var about: Vector3 = a.cross(w)
	if about.length() < 0.000001:
		about = a.cross(Vector3.UP) if absf(a.dot(Vector3.UP)) < 0.9 else a.cross(Vector3.RIGHT)
	return Basis(about.normalized(), minf(angle, deg_to_rad(limit_deg)))


## The fist's line for a frame: this frame's, when its hand is a fist, else `fallback`'s.
static func axis_of(f: Dictionary, fallback: Vector3) -> Vector3:
	var h: Dictionary = f["hole"]
	return h["axis"] as Vector3 if not h.is_empty() and bool(h["fist"]) else fallback


## Where the item's HOLD is in the world for one frame: held `turn` (in the hand's frame, or the
## body's when steady) with the hold at `centre` in the hand. A steady hold turns the wrist first
## (`wrist_turn`, up to `wrist_deg`), and `centre` is in the turned hand.
static func placed(f: Dictionary, centre: Vector3, turn: Basis, steady: bool, wrist_deg: float,
		fist_axis: Vector3) -> Transform3D:
	var hand: Transform3D = f["hand"]
	if not steady:
		return Transform3D(hand.basis.orthonormalized() * turn, hand * centre)
	var rot: Basis = (f["body"] as Basis).orthonormalized() * turn
	var w: Basis = wrist_turn(hand.basis, axis_of(f, fist_axis), rot.y, wrist_deg)
	return Transform3D(rot, Transform3D(w * hand.basis, hand.origin) * centre)


## How far the item's line is out of the fist's in one frame, after the wrist has turned (degrees).
static func out_of_fist(f: Dictionary, turn: Basis, steady: bool, wrist_deg: float,
		fist_axis: Vector3) -> float:
	var hand: Transform3D = f["hand"]
	var axis: Vector3 = axis_of(f, fist_axis)
	if not steady:
		return rad_to_deg(turn.y.angle_to(axis))
	var want: Vector3 = (f["body"] as Basis).orthonormalized() * turn.y
	var w: Basis = wrist_turn(hand.basis, axis, want, wrist_deg)
	return rad_to_deg(((w * hand.basis.orthonormalized()) * axis).angle_to(want))


# --- the fit --------------------------------------------------------------------------------------

## FIT the grip for one animation. `frames`: `frame_of` through its clip, for every body it is
## for; `marks`: `marks_of` the item; `carry`, `face`, `cone_deg`, `wrist_deg`: the grip file's
## (`ItemGrip`); `fallback`: a hole to use when this animation's hand never closes (the idle's).
## Returns {"position", "rotation_degrees", "steady", "air", "part", "point", "hand_air",
## "hand_part", "out_of_fist_deg", "swing_deg", "fist"}, or {} when the hand has no fingers to
## fit. `hand_air` is the hold's own least air: small, and the animation itself puts the hand
## against the body. `out_of_fist_deg` is the most the handle leaves the fist's line.
static func fit(frames: Array[Dictionary], marks: Array[Array], animation: StringName,
		carry: Vector3, face: Vector3, cone_deg: float, wrist_deg: float,
		fallback: Dictionary) -> Dictionary:
	var hl: Dictionary = mean_hole(frames, fallback)
	if hl.is_empty() or frames.is_empty():
		return {}
	var centre: Vector3 = hl["centre"]
	var axis: Vector3 = hl["axis"]
	var fist: Basis = faced(frames, fist_basis(hl), face)
	var turn: Basis = fist
	var steady: bool = false
	if carries(animation) and not carry.is_zero_approx():
		turn = steady_turn(frames, fist, carry, face)
		steady = true
	elif carries(animation) and swing_of(frames, fist, false) > STEADY_SWING_DEG:
		turn = steady_turn(frames, fist, Vector3.ZERO, face)
		steady = true
	if _score(frames, marks, centre, turn, turn, steady, wrist_deg, axis, cone_deg, 1) < 1000.0 - 0.001:
		turn = search(frames, marks, centre, turn, steady, wrist_deg, axis, cone_deg)
	var worst: Dictionary = worst_of(frames, marks, centre, turn, steady, wrist_deg, axis)
	var hand_air: Dictionary = worst_of(frames, [["hand", Vector3.ZERO, Vector3.ZERO, 0.0]] as Array[Array],
		centre, turn, steady, wrist_deg, axis)
	var e: Vector3 = turn.get_euler(EULER_ORDER_YXZ)
	return {"position": centre, "rotation_degrees": Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)),
		"steady": steady, "air": worst["air"], "part": worst["part"], "point": worst["point"],
		"hand_air": hand_air["air"], "hand_part": hand_air["part"],
		"out_of_fist_deg": most_out_of_fist(frames, turn, steady, wrist_deg, axis),
		"swing_deg": swing_of(frames, turn, steady), "fist": bool(hl["fist"])}


## The hole to fit to: the mean of this clip's fists (every body's), else `fallback`, else the
## mean of whatever the hand does.
static func mean_hole(frames: Array[Dictionary], fallback: Dictionary) -> Dictionary:
	var fists: Array[Dictionary] = []
	var any: Array[Dictionary] = []
	for f: Dictionary in frames:
		var h: Dictionary = f["hole"]
		if h.is_empty():
			continue
		any.append(h)
		if bool(h["fist"]):
			fists.append(h)
	var use: Array[Dictionary] = fists
	if use.is_empty() and not fallback.is_empty():
		return fallback
	if use.is_empty():
		use = any
	if use.is_empty():
		return {}
	var centre: Vector3 = Vector3.ZERO
	var axis: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	for h: Dictionary in use:
		centre += h["centre"] as Vector3
		axis += h["axis"] as Vector3
		radius += float(h["radius"])
	var n: float = float(use.size())
	return {"centre": centre / n, "axis": axis.normalized(), "radius": radius / n,
		"fist": not fists.is_empty(), "error": 0.0, "curl_deg": 0.0}


## The item along the hole: +Y out past the index, +Z toward the wrist.
static func fist_basis(hl: Dictionary) -> Basis:
	var y: Vector3 = hl["axis"]
	var to_wrist: Vector3 = -(hl["centre"] as Vector3)
	var z: Vector3 = to_wrist - y * to_wrist.dot(y)
	if z.length() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


## The fist's turn (in the HAND's frame), rolled round its line so its +Z faces `face` (in the
## body's terms) as nearly as it can through the clip. Zero: as it was (toward the wrist).
static func faced(frames: Array[Dictionary], fist: Basis, face: Vector3) -> Basis:
	if face.is_zero_approx():
		return fist
	var zs: Vector3 = Vector3.ZERO
	for f: Dictionary in frames:
		zs += ((f["hand"] as Transform3D).basis.orthonormalized().inverse()
			* (f["body"] as Basis).orthonormalized() * body_dir(face)).normalized()
	var y: Vector3 = fist.y
	var z: Vector3 = zs - y * zs.dot(y)
	if z.length() < 0.001:
		return fist
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


## A steady turn (in the BODY's frame): toward `point` (in the body's terms) when it is given,
## else where the hand-held `turn` points on average through the clip; its +Z toward `face`, else
## as the hand-held turn's is on average.
static func steady_turn(frames: Array[Dictionary], turn: Basis, point: Vector3, face: Vector3) -> Basis:
	var ys: Vector3 = Vector3.ZERO
	var zs: Vector3 = Vector3.ZERO
	for f: Dictionary in frames:
		var b: Basis = (f["body"] as Basis).orthonormalized().inverse() \
			* (f["hand"] as Transform3D).basis.orthonormalized() * turn
		ys += b.y
		zs += b.z
	var y: Vector3 = body_dir(point).normalized() if not point.is_zero_approx() else ys.normalized()
	var z_from: Vector3 = body_dir(face) if not face.is_zero_approx() else zs
	var z: Vector3 = z_from - y * z_from.dot(y)
	if z.length() < 0.001:
		z = zs - y * zs.dot(y)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


## The least air off the body through the frames, and where: {"air", "part", "point"}.
static func worst_of(frames: Array[Dictionary], marks: Array[Array], centre: Vector3, turn: Basis,
		steady: bool, wrist_deg: float, fist_axis: Vector3, step: int = 1) -> Dictionary:
	var best: Dictionary = {"air": INF, "part": "", "point": ""}
	for k: int in range(0, frames.size(), step):
		var f: Dictionary = frames[k]
		var hold: Transform3D = placed(f, centre, turn, steady, wrist_deg, fist_axis)
		for m: Array in marks:
			var r: Dictionary = BodyClearance.measure_posed(f["parts"] as Array[Array], hold * (m[1] as Vector3),
				hold * (m[2] as Vector3), float(m[3]))
			if float(r["air"]) < float(best["air"]):
				best = {"air": r["air"], "part": r["part"], "point": m[0]}
	return best


## The most the handle leaves the fist's line through the frames (degrees).
static func most_out_of_fist(frames: Array[Dictionary], turn: Basis, steady: bool, wrist_deg: float,
		fist_axis: Vector3, step: int = 1) -> float:
	var most: float = 0.0
	for k: int in range(0, frames.size(), step):
		most = maxf(most, out_of_fist(frames[k], turn, steady, wrist_deg, fist_axis))
	return most


## How far the item's axis turns in the BODY's frame through the frames (degrees, from the first).
static func swing_of(frames: Array[Dictionary], turn: Basis, steady: bool) -> float:
	var first: Vector3 = Vector3.ZERO
	var most: float = 0.0
	for f: Dictionary in frames:
		var rot: Basis = (f["body"] as Basis).orthonormalized() * turn if steady \
			else (f["hand"] as Transform3D).basis.orthonormalized() * turn
		var axis: Vector3 = ((f["body"] as Basis).orthonormalized().inverse() * rot.y).normalized()
		if first == Vector3.ZERO:
			first = axis
		most = maxf(most, rad_to_deg(first.angle_to(axis)))
	return most


## The turns round `turn` (tilts about its X and Z, a roll about its Y), coarse then fine: the
## least turn that stays in the fist and clears the body, else the one that comes nearest.
static func search(frames: Array[Dictionary], marks: Array[Array], centre: Vector3, turn: Basis,
		steady: bool, wrist_deg: float, fist_axis: Vector3, cone_deg: float) -> Basis:
	var best: Basis = turn
	var best_score: float = _score(frames, marks, centre, turn, turn, steady, wrist_deg, fist_axis, cone_deg, 2)
	for pass_degs: Array in [[TILT_DEG, ROLL_DEG], [FINE_DEG, FINE_DEG]]:
		var around: Basis = best
		for ax: float in pass_degs[0]:
			for az: float in pass_degs[0]:
				for ry: float in pass_degs[1]:
					var b: Basis = around * Basis.from_euler(Vector3(deg_to_rad(ax), deg_to_rad(ry),
						deg_to_rad(az)), EULER_ORDER_YXZ)
					var s: float = _score(frames, marks, centre, b, turn, steady, wrist_deg, fist_axis, cone_deg, 2)
					if s > best_score:
						best_score = s
						best = b
	return best.orthonormalized()


## In the fist and clear of the body comes first (1000, less the turn from `from`); short of that,
## the nearer the better: each centimetre short of clear and each degree out of the fist past
## `cone_deg` count against it.
static func _score(frames: Array[Dictionary], marks: Array[Array], centre: Vector3, b: Basis,
		from: Basis, steady: bool, wrist_deg: float, fist_axis: Vector3, cone_deg: float, step: int) -> float:
	var air: float = float(worst_of(frames, marks, centre, b, steady, wrist_deg, fist_axis, step)["air"])
	var out: float = most_out_of_fist(frames, b, steady, wrist_deg, fist_axis, step)
	if air >= ENOUGH_AIR and out <= cone_deg + 0.01:
		return 1000.0 - rad_to_deg(Quaternion(from.orthonormalized()).angle_to(Quaternion(b.orthonormalized())))
	return minf(air - ENOUGH_AIR, 0.0) * 100.0 + minf(cone_deg - out, 0.0) * 0.5


## The circle through `points` (least squares, Kasa): [centre: Vector2, radius, worst error].
static func _circle(points: PackedVector2Array) -> Array:
	var sxx: float = 0.0
	var syy: float = 0.0
	var sxy: float = 0.0
	var sx: float = 0.0
	var sy: float = 0.0
	var sxz: float = 0.0
	var syz: float = 0.0
	var sz: float = 0.0
	for q: Vector2 in points:
		var z: float = q.length_squared()
		sxx += q.x * q.x
		syy += q.y * q.y
		sxy += q.x * q.y
		sx += q.x
		sy += q.y
		sxz += q.x * z
		syz += q.y * z
		sz += z
	var n: float = float(points.size())
	var m: Basis = Basis(Vector3(sxx, sxy, sx), Vector3(sxy, syy, sy), Vector3(sx, sy, n))
	if absf(m.determinant()) < 1e-18:
		return [Vector2.ZERO, 0.0, INF]
	var sol: Vector3 = m.inverse() * Vector3(-sxz, -syz, -sz)
	var c: Vector2 = Vector2(-sol.x * 0.5, -sol.y * 0.5)
	var r: float = sqrt(maxf(c.length_squared() - sol.z, 0.0))
	var worst: float = 0.0
	for q: Vector2 in points:
		worst = maxf(worst, absf(q.distance_to(c) - r))
	return [c, r, worst]
