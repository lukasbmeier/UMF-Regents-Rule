extends "res://tests/suite_base.gd"
## MOVES MADE OF CLIPS AND CODE (`-- --only=regents_motion`; 2026-11-17, the motion lab), with no server and no renderer:
##   - every move in `game/regents/motion/moves/` loads, names only clips that exist, begins and ends with its channels
##     at rest (a spin whole turns), and its clips' seams leave no gap where the pose under them shows through; the
##     spinning advance turns four times; NEGATIVE: a move left tipped over is caught, a clip with no such name is
##     found missing, a move with no curves and no clips never moves
##   - a clip's stretch: time-warped to its part (forward and back), eased in and out, nothing outside it
##   - the figure's turn (the code's): about the hips, a tip toward the facing, a spin to the left, a squash feet down
##   - on a real character (`ShowcaseActor`, stepped by hand; the bent bones read where they are drawn,
##     `MotionBones.seen`): the back flip's clip puts the head under the hips and the body lands 2.5 m back; the sky
##     blade's clip raises the sword hand over the head; the leap slam's clips lift the hips over 1.5 m; the spinning
##     dash's clip root carries it its 7 m; the dragged foe is hauled forward; the hook's reach (code) points the arm at
##     its target; NEGATIVES: the same moves with their clips taken out stay on their feet, hand low, hips low, carried
##     only as far as the code says, and with the layer off the arm points elsewhere
##   - the trail keeps a blade while it draws and is empty once it stops and its life runs out; it is sampled AS DRAWN
##     (the sky blade's raised blade starts at the bent hand, over the head), and `clear` forgets it
##   - the wrist (code) rolls the hand about the fore arm: what the hand carries turns, the arm does not
##   - IN THE GAME (PROGRESS 110): every row of `AbilityMoves` names an ability some kit has and a move; every motion lab
##     placeholder has a row; a fighter's `MotionPlayer` plays an ability's move as it begins and the victim move on what
##     it hits, its own height left out (the server lifts the body); NEGATIVES: an ability with no row plays nothing, a
##     hit from one with no victim move, or long after, plays nothing
##   - MIXAMO (PROGRESS 111): the retargeted libraries key only our bones; on a character a clip stands, a two-handed
##     hold keeps the hands together, the sword arm is the right one, a walk walks in place (and their negatives)
##   - THE BOWSTRING (PROGRESS 112): straight at rest, a V to the fingers with an arrow at full draw, straight when let
##     go, measured from the model (a 1.4x bow's is 1.4x); NEGATIVES: a hand reaching for an arrow, a spell's pose
##   - the lab shows every move, its shoulder charge plays to its end (the charger carried, the foe thrown back and on
##     its feet again), and its SCRUBBER lands on the moment asked, held, and back to the same moment shows the same
##     frame (forward and backward)
## How it LOOKS: `"$GODOT" --path . res://game/regents/motion/motion_lab.tscn -- <out dir> [name] [compare] [dense]`.

const MOVES: String = "res://game/regents/motion/moves/"
const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const SWORD: ItemDef = preload("res://game/regents/content/item/steel_sword.tres")
const LAB: String = "res://game/regents/motion/motion_lab.tscn"


func run() -> void:
	_run_moves()
	_run_clip_stretch()
	_run_figure_turn()
	await _run_on_a_character()
	await _run_trail()
	await _run_wrist()
	_run_ability_table()
	await _run_mixamo()
	await _run_bow_string()
	await _run_in_game()
	await _run_lab()


# ---------------------------------------------------------------- the moves

static func _move_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in DirAccess.get_files_at(MOVES):
		if f.ends_with(".tres"):
			out.append(f.get_basename())
	out.sort()
	return out


static func _move(n: String) -> MotionMove:
	return load(MOVES + n + ".tres") as MotionMove


## How far a pose's channels are from standing (a spin or a tip of whole turns counts as standing): the worst, in
## degrees or centimeters.
static func _off_rest(p: MotionMove.Pose) -> float:
	var worst: float = 0.0
	for turn: float in [p.spin, p.tip]:
		worst = maxf(worst, rad_to_deg(absf(wrapf(turn, -PI, PI))))
	for a: float in [p.bank, p.bend, p.twist, p.raise, p.spread]:
		worst = maxf(worst, rad_to_deg(absf(a)))
	worst = maxf(worst, absf(p.lift_m) * 100.0)
	worst = maxf(worst, absf(p.squash) * 100.0)
	worst = maxf(worst, p.reach * 100.0)
	return worst


## How much the clips together cover the pose under them where they cover it least (1: fully, all through).
static func _thinnest_seam(m: MotionMove) -> float:
	if m.clips.is_empty():
		return 1.0
	var first: float = 1.0
	var last: float = 0.0
	for c: MotionClip in m.clips:
		first = minf(first, c.at)
		last = maxf(last, c.until)
	var worst: float = 1.0
	var steps: int = 200
	for k: int in range(1, steps):
		var u: float = lerpf(first, last, float(k) / float(steps))
		var t: float = u * m.length_s
		# Not at its very ends (a move eases in from and out to the pose under it).
		if t < 0.2 or t > m.length_s * last - 0.3:
			continue
		# Each clip goes on over what is under it by its weight: the pose under them all shows through by what is left.
		var under: float = 1.0
		for c: MotionClip in m.clips:
			under *= 1.0 - c.weight(t, m.length_s)
		worst = minf(worst, 1.0 - under)
	return worst


func _run_moves() -> void:
	var names: PackedStringArray = _move_names()
	_check(names.size() >= 14, "the lab's moves are there (%d)" % names.size())
	for n: String in names:
		var m: MotionMove = _move(n)
		_check(m != null and m.length_s > 0.0, "%s loads, with a length" % n)
		if m == null:
			continue
		var missing: PackedStringArray = PackedStringArray()
		for c: MotionClip in m.clips:
			if c.clip() == null:
				missing.append(String(c.animation))
		_check(missing.is_empty(), "%s names only clips that exist (not found: %s)" % [n, missing])
		_check(_off_rest(m.at(0.0)) < 1.0, "%s begins with its channels at rest (%.1f off)" % [n, _off_rest(m.at(0.0))])
		_check(_off_rest(m.at(m.length_s)) < 1.0, "%s ends with its channels at rest (%.1f off)" % [n, _off_rest(m.at(m.length_s))])
		_check(_thinnest_seam(m) > 0.7, "%s's clips leave no gap at a seam (the thinnest %.2f)" % [n, _thinnest_seam(m)])
	var spin: MotionMove = _move("spinning_advance")
	_check(absf(spin.at(spin.length_s).spin - 4.0 * TAU) < 0.01, "the spinning advance turns four times")
	# NEGATIVES: the checks are not blind.
	var bad := MotionMove.new()
	bad.tip_deg = 90.0
	bad.tip = Curve.new()
	bad.tip.add_point(Vector2(0.0, 0.0))
	bad.tip.add_point(Vector2(1.0, 1.0))
	_check(_off_rest(bad.at(bad.length_s)) > 80.0, "NEGATIVE: a move that ends tipped over is caught (%.0f off)" % _off_rest(bad.at(bad.length_s)))
	var nowhere := MotionClip.new()
	nowhere.animation = &"extra/No_Such_Clip"
	_check(nowhere.clip() == null, "NEGATIVE: a clip with no such name is found missing")
	var gap := MotionMove.new()
	gap.length_s = 2.0
	var c1 := MotionClip.new()
	c1.animation = &"core/Sprint"
	c1.until = 0.4
	var c2 := MotionClip.new()
	c2.animation = &"core/Sprint"
	c2.at = 0.6
	gap.clips = [c1, c2]
	_check(_thinnest_seam(gap) < 0.1, "NEGATIVE: two clips with a gap between are caught (%.2f)" % _thinnest_seam(gap))
	var empty := MotionMove.new()
	_check(empty.at(0.3).is_rest() and empty.root_at(0.3) == Vector3.ZERO, "NEGATIVE: a move with no curves and no clips never moves")


func _run_clip_stretch() -> void:
	var c := MotionClip.new()
	c.animation = &"core/BackFlip"   # 1.93 s
	c.at = 0.25
	c.until = 0.75
	c.from_s = 0.2
	c.to_s = 1.2
	c.blend_in_s = 0.1
	c.blend_out_s = 0.1
	# A move of 2 s: the stretch is 0.5 s to 1.5 s.
	_check(absf(c.clip_time(1.0, 2.0) - 0.7) < 0.001, "a clip is time-warped to its part (half way: 0.7 s)")
	_check(absf(c.clip_time(0.0, 2.0) - 0.2) < 0.001 and absf(c.clip_time(2.0, 2.0) - 1.2) < 0.001, "and held at its ends outside it")
	_check(c.weight(0.4, 2.0) == 0.0 and c.weight(1.6, 2.0) == 0.0, "nothing outside its stretch")
	_check(c.weight(1.0, 2.0) == 1.0 and c.weight(0.55, 2.0) > 0.0 and c.weight(0.55, 2.0) < 1.0, "full in the middle, easing in at its start")
	c.from_s = 1.2
	c.to_s = 0.2
	_check(absf(c.clip_time(0.75, 2.0) - 0.95) < 0.001, "a part with its end before its start plays backward")


func _run_figure_turn() -> void:
	var fwd := Vector3(0.0, 0.0, -1.0)
	var p := MotionMove.Pose.new()
	p.tip = PI
	var t: Transform3D = MotionLayer.figure_transform(p, fwd, 1.0)
	_check((t * Vector3(0.0, 1.0, 0.0)).distance_to(Vector3(0.0, 1.0, 0.0)) < 0.001, "a code flip turns about the hips (they stay)")
	_check((t * Vector3.ZERO).distance_to(Vector3(0.0, 2.0, 0.0)) < 0.001, "the feet go over the top")
	p.tip = deg_to_rad(30.0)
	var head: Vector3 = MotionLayer.figure_transform(p, fwd, 1.0) * Vector3(0.0, 1.7, 0.0)
	_check(head.z < -0.2, "a tip leans the head toward the facing (z %.2f)" % head.z)
	p.tip = 0.0
	p.spin = PI * 0.5
	var nose: Vector3 = MotionLayer.figure_transform(p, fwd, 1.0).basis * fwd
	_check(nose.distance_to(Vector3(-1.0, 0.0, 0.0)) < 0.001, "a quarter spin turns to the left")
	p.spin = 0.0
	p.squash = 0.2
	var sq: Transform3D = MotionLayer.figure_transform(p, fwd, 1.0)
	_check((sq * Vector3.ZERO).length() < 0.001 and (sq * Vector3(0.0, 1.0, 0.0)).y < 0.85, "a squash presses down with the feet on the ground")


# ---------------------------------------------------------------- on a character

func _actor() -> ShowcaseActor:
	var a: ShowcaseActor = ShowcaseActor.make(ADVENTURER, 4, SWORD.held_scene, null)
	add_child(a)
	a.set_process(false)
	a.driver.set_process(false)
	a.step(0.0)
	return a


func _layer(a: ShowcaseActor) -> MotionLayer:
	var l: MotionLayer = MotionLayer.attach(a, a.model, a.skeleton)
	l.manual = true
	l.bones.watch = [&"hand_r", &"Head", &"pelvis", &"upperarm_r"]
	return l


## Where bone `b` is as last drawn, the clips and the bend in it (`MotionBones.seen`).
func _seen(l: MotionLayer, b: StringName) -> Vector3:
	return l.bones.seen.get(b, Vector3.INF) as Vector3


## Play `m` facing -Z (reaching for `at`) and step it through, calling `look` at each frame drawn (after the skeleton
## has drawn it); the actor's place is where the move left it.
func _through(a: ShowcaseActor, l: MotionLayer, m: MotionMove, look: Callable, at: Vector3 = Vector3.INF) -> void:
	l.play(m, Vector3(0.0, 0.0, -1.0), at)
	while l.playing():
		a.step(1.0 / 30.0)
		l.step(1.0 / 30.0)
		await get_tree().process_frame   # the skeleton's modifiers run as it updates
		if l.playing():
			look.call(l.t / m.length_s)


## A copy of `m` with its clips taken out (the code alone).
static func _without_clips(m: MotionMove) -> MotionMove:
	var d: MotionMove = m.duplicate() as MotionMove
	d.clips = []
	return d


func _run_on_a_character() -> void:
	var a: ShowcaseActor = _actor()
	var l: MotionLayer = _layer(a)
	for clipped: bool in [true, false]:
		var tag: String = "" if clipped else "NEGATIVE, the clips taken out: "
		# The back flip: the head under the hips at its height; the body 2.5 m back.
		var flip: MotionMove = _move("backflip") if clipped else _without_clips(_move("backflip"))
		var low: Array[float] = [9.0]
		var start: Vector3 = a.position
		await _through(a, l, flip, func(_u: float) -> void:
			low[0] = minf(low[0], _seen(l, &"Head").y - _seen(l, &"pelvis").y))
		if clipped:
			_check(low[0] < -0.2, "the back flip's clip puts the head under the hips (%.2f m)" % low[0])
		else:
			_check(low[0] > 0.3, tag + "the head stays over the hips (%.2f m)" % low[0])
		_check(absf((a.position - start).z - 2.5) < 0.1, "%sthe flip lands 2.5 m back (%.2f)" % [tag, (a.position - start).z])
		# The sky blade: the sword hand over the head as it is raised.
		var sky: MotionMove = _move("sky_blade") if clipped else _without_clips(_move("sky_blade"))
		var high: Array[float] = [-9.0]
		await _through(a, l, sky, func(_u: float) -> void:
			high[0] = maxf(high[0], _seen(l, &"hand_r").y - _seen(l, &"Head").y))
		if clipped:
			_check(high[0] > 0.1, "the sky blade's clip raises the sword hand over the head (%.2f m)" % high[0])
		else:
			_check(high[0] < 0.0, tag + "the hand stays below it (%.2f m)" % high[0])
		# The leap slam: the hips over 1.5 m up at the top of the rising cut.
		var slam: MotionMove = _move("leap_slam") if clipped else _without_clips(_move("leap_slam"))
		var hips: Array[float] = [0.0]
		var ground_y: float = a.position.y
		await _through(a, l, slam, func(_u: float) -> void:
			hips[0] = maxf(hips[0], _seen(l, &"pelvis").y - ground_y))
		if clipped:
			_check(hips[0] > 1.5, "the leap slam's clips lift the hips over 1.5 m (%.2f m)" % hips[0])
		else:
			_check(hips[0] < 1.3, tag + "the hips stay low (%.2f m)" % hips[0])
		# The spinning dash: carried by its clip's root, stretched to 7 m (none without it: it has no travel curve).
		var dash: MotionMove = _move("spinning_dash") if clipped else _without_clips(_move("spinning_dash"))
		start = a.position
		await _through(a, l, dash, func(_u: float) -> void: pass)
		var went: float = start.z - a.position.z
		if clipped:
			_check(absf(went - 7.0) < 0.4, "the spinning dash's clip carries it its 7 m (%.2f)" % went)
		else:
			_check(absf(went) < 0.05, tag + "it goes nowhere (%.2f)" % went)
		# Dragged: the knockback's root turned round hauls the body forward.
		var drag: MotionMove = _move("dragged") if clipped else _without_clips(_move("dragged"))
		start = a.position
		await _through(a, l, drag, func(_u: float) -> void: pass)
		went = start.z - a.position.z
		if clipped:
			_check(went > 1.2 and went < 2.4, "the dragged foe is hauled forward, from 3 m to near its hauler (%.2f m)" % went)
		else:
			_check(absf(went) < 0.05, tag + "it stays where it was (%.2f)" % went)
	# The hook's reach is the code's: with the layer off, the arm is wherever the throw's clip has it.
	var aims: Array[float] = []
	for on: bool in [true, false]:
		l.enabled = on
		var hook: MotionMove = _move("hook_pull")
		var target: Vector3 = a.position + Vector3(4.0, 1.4, -1.0)
		var best: Array[float] = [180.0]
		await _through(a, l, hook, func(u: float) -> void:
			if absf(u - hook.impact_at) < 0.03:
				var shoulder: Vector3 = _seen(l, &"upperarm_r")
				best[0] = minf(best[0], rad_to_deg((_seen(l, &"hand_r") - shoulder).angle_to(target - shoulder))), target)
		aims.append(best[0])
	l.enabled = true
	_check(aims[0] < 25.0, "the hook's reach points the arm at its target (%.0f deg off)" % aims[0])
	_check(aims[1] > 40.0, "NEGATIVE: with the layer off the arm points elsewhere (%.0f deg off)" % aims[1])
	a.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- Mixamo, retargeted

## The retargeted libraries (`game/regents/tools/retarget_mixamo.gd`, 2026-11-18) and their least clip count.
const MIXAMO: Dictionary[String, int] = {"mx_great_sword": 51, "mx_sword_shield": 51, "mx_magic": 56, "mx_locomotion": 12}


## A move that is one clip, all of it.
static func _clip_move(clip_name: StringName) -> MotionMove:
	var clip: Animation = MotionClip.find(clip_name)
	var m := MotionMove.new()
	m.length_s = clip.length if clip != null else 1.0
	var mc := MotionClip.new()
	mc.animation = clip_name
	mc.blend_in_s = 0.0
	mc.blend_out_s = 0.0
	m.clips = [mc]
	return m


## The tracks of `lib` that name anything but a bone of `skel` on the skeleton node.
static func _strays(lib: AnimationLibrary, skel: Skeleton3D) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: StringName in lib.get_animation_list():
		var anim: Animation = lib.get_animation(n)
		for i: int in anim.get_track_count():
			var p: NodePath = anim.track_get_path(i)
			if String(p.get_concatenated_names()) != "Skeleton3D" or skel.find_bone(p.get_concatenated_subnames()) < 0:
				out.append("%s: %s" % [n, p])
	return out


## Mixamo's clips on our skeleton: every library loads and keys only our bones; on a real character a clip stands,
## a two-handed hold keeps the hands together, a chop goes over the head, the sword arm is the right one, a walk walks
## in place. NEGATIVES: a Mixamo bone name left in is caught; Quaternius's idle holds the hands apart; the shield
## hand swings less than the sword hand.
func _run_mixamo() -> void:
	var a: ShowcaseActor = _actor()
	var l: MotionLayer = _layer(a)
	l.bones.watch = [&"hand_r", &"hand_l", &"Head", &"pelvis"]
	for key: String in MIXAMO:
		var lib: AnimationLibrary = load(MotionClip.LIBRARIES.get(key, "")) as AnimationLibrary
		_check(lib != null and lib.get_animation_list().size() >= MIXAMO[key],
			"%s loads with its %d clips" % [key, MIXAMO[key]])
		if lib == null:
			continue
		var strays: PackedStringArray = _strays(lib, a.skeleton)
		_check(strays.is_empty(), "%s keys only our skeleton's bones %s" % [key, str(strays.slice(0, 3))])
	# NEGATIVE: a track still on Mixamo's rig is found.
	var probe := AnimationLibrary.new()
	var bad: Animation = MotionClip.find(&"mx_locomotion/idle").duplicate() as Animation
	bad.track_set_path(0, NodePath("Skeleton3D:mixamorig_Hips"))
	probe.add_animation(&"bad", bad)
	_check(_strays(probe, a.skeleton).size() == 1, "NEGATIVE: a Mixamo bone left in a track is caught")

	# Standing: Mixamo's idle keeps the hips at our height and the head over them, all through.
	var rest_hips: float = a.skeleton.get_bone_global_rest(a.skeleton.find_bone(&"pelvis")).origin.y
	var hips_off: Array[float] = [0.0]
	var head_over: Array[float] = [9.0]
	var ground_y: float = a.position.y
	await _through(a, l, _clip_move(&"mx_locomotion/idle"), func(_u: float) -> void:
		hips_off[0] = maxf(hips_off[0], absf(_seen(l, &"pelvis").y - ground_y - rest_hips))
		head_over[0] = minf(head_over[0], _seen(l, &"Head").y - _seen(l, &"pelvis").y))
	_check(hips_off[0] < 0.06, "Mixamo's idle stands at our hip height (%.1f cm off at most)" % (hips_off[0] * 100.0))
	_check(head_over[0] > 0.5, "and keeps the head over the hips (%.2f m at least)" % head_over[0])

	# Two hands on the hilt: the great sword's idle holds them together; Quaternius's idle does not.
	var gaps: Array[float] = []
	for clip: StringName in [&"mx_great_sword/great_sword_idle", &"core/Idle"]:
		var gap: Array[float] = [0.0]
		await _through(a, l, _clip_move(clip), func(_u: float) -> void:
			gap[0] = maxf(gap[0], _seen(l, &"hand_r").distance_to(_seen(l, &"hand_l"))))
		gaps.append(gap[0])
	_check(gaps[0] < 0.25, "the great sword's idle holds both hands on the hilt (%.2f m apart at most)" % gaps[0])
	_check(gaps[1] > 0.5, "NEGATIVE: Quaternius's idle holds them apart (%.2f m)" % gaps[1])

	# The chop: both hands over the head.
	var over: Array[float] = [-9.0]
	await _through(a, l, _clip_move(&"mx_great_sword/great_sword_slash"), func(_u: float) -> void:
		over[0] = maxf(over[0], minf(_seen(l, &"hand_r").y, _seen(l, &"hand_l").y) - _seen(l, &"Head").y))
	_check(over[0] > 0.1, "the great sword's slash raises both hands over the head (%.2f m)" % over[0])

	# The sword arm is the right one (Mixamo's RightHand onto our hand_r): in the shield slash it sweeps much farther.
	var sweep: Dictionary[StringName, Array] = {&"hand_r": [], &"hand_l": []}
	await _through(a, l, _clip_move(&"mx_sword_shield/sword_and_shield_slash"), func(_u: float) -> void:
		for h: StringName in sweep:
			sweep[h].append(_seen(l, h) - _seen(l, &"pelvis")))
	var reach: Dictionary[StringName, float] = {}
	for h: StringName in sweep:
		var box := AABB(sweep[h][0] as Vector3, Vector3.ZERO)
		for p: Variant in sweep[h]:
			box = box.expand(p as Vector3)
		reach[h] = box.size.length()
	_check(reach[&"hand_r"] > reach[&"hand_l"] * 1.3,
		"the shield slash swings the right hand (%.2f m) more than the shield hand (%.2f m)" % [reach[&"hand_r"], reach[&"hand_l"]])

	# A walk walks in place (the server moves the body): the hips end where they began.
	var path: Array[Vector3] = []
	await _through(a, l, _clip_move(&"mx_locomotion/walking"), func(_u: float) -> void:
		path.append(_seen(l, &"pelvis") - a.position))
	var drift: Vector3 = path[path.size() - 1] - path[0]
	drift.y = 0.0
	_check(drift.length() < 0.1, "Mixamo's walk walks in place (the hips drift %.2f m)" % drift.length())
	a.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the bowstring

const BOW_SCENE: String = "res://game/regents/combat/weapons/yew_bow.tscn"


## Hold the bow's draw pose at `t` (or none: let it go) for `frames` frames, the actor stepped by hand.
func _bow_frames(a: ShowcaseActor, frames: int, pose: StringName, t: float = -1.0) -> void:
	for i: int in frames:
		if pose.is_empty():
			a.driver.release_upper_pose()
		else:
			a.driver.hold_upper_pose(pose, 1.0, t)
		a.step(1.0 / 30.0)
		await get_tree().process_frame


## The bowstring (Luke, 2026-11-18, PROGRESS 112): straight at rest, drawn back into a V to the fingers with an arrow on
## it at full draw, straight again when let go. NEGATIVES: a hand reaching over the shoulder for an arrow (early in the
## draw) does not take it; a pose that is not a draw (a spell's cast) does not; the model's own string is gone.
func _run_bow_string() -> void:
	var a: ShowcaseActor = ShowcaseActor.make(ADVENTURER, 4, load(BOW_SCENE) as PackedScene, null)
	add_child(a)
	a.set_process(false)
	a.driver.set_process(false)
	await _bow_frames(a, 10, &"")
	var s: BowString = a.held.get_node_or_null("String") as BowString if a.held != null else null
	_check(s != null, "the yew bow carries a BowString")
	if s == null:
		a.queue_free()
		return
	var mi: MeshInstance3D = BowString._first_mesh(a.held.get_node("Model"))
	_check(mi != null and mi.mesh.get_surface_count() == 2, "the model's own string is taken out (%d surfaces left)" % (mi.mesh.get_surface_count() if mi != null else -1))
	var span: float = s.tip_a.distance_to(s.tip_b)
	_check(span > 1.1 and span < 1.7, "the string runs tip to tip (%.2f m)" % span)
	var straight: Callable = func() -> bool: return not s.held and s.nock.is_equal_approx(s.rest_nock) and not s._arrow.visible
	_check(straight.call(), "at rest it is straight, with no arrow")
	# Full draw: the V to the fingers, the arrow from the nock over the riser.
	await _bow_frames(a, 30, &"pose.bow_aim")
	var back: float = (s.nock - s.rest_nock).dot((s.rest_nock - s.riser).normalized())
	_check(s.held and s.nock.distance_to(s.hand_point()) < 0.02, "at full draw the string goes to the fingers")
	_check(back > 0.2, "drawn back into a V (%.2f m behind its rest)" % back)
	var arrow_dir: Vector3 = -s._arrow.transform.basis.z.normalized()
	_check(s._arrow.visible and arrow_dir.dot((s.riser - s.nock).normalized()) > 0.99, "an arrow lies from the nock over the riser")
	# Let go: straight again.
	await _bow_frames(a, 30, &"")
	_check(straight.call(), "let go, it snaps straight and the arrow is gone")
	# NEGATIVE: early in the draw the hand is over the shoulder, reaching for an arrow.
	await _bow_frames(a, 30, &"pose.bow_draw", 0.125)
	_check(s.drawing() and not s.takes(s.hand_point()) and straight.call(),
		"NEGATIVE: a hand reaching over the shoulder for an arrow leaves it straight")
	await _bow_frames(a, 30, &"pose.bow_draw", 0.75)
	_check(s.held, "later in the same draw it is taken")
	# NEGATIVE: a pose that is not a draw.
	await _bow_frames(a, 30, &"pose.spell_cast")
	_check(not s.drawing() and straight.call(), "NEGATIVE: a spell's cast pose is not a draw")
	a.queue_free()
	await get_tree().process_frame
	# A bigger bow (the tank's, 1.4x) has a longer string: it is measured from the model.
	var big: Node3D = (load(BOW_SCENE) as PackedScene).instantiate() as Node3D
	(big.get_node("Model") as Node3D).scale *= 1.4
	add_child(big)
	var bs: BowString = big.get_node("String") as BowString
	_check(absf(bs.tip_a.distance_to(bs.tip_b) / span - 1.4) < 0.01, "a 1.4x bow's string is 1.4x as long")
	big.queue_free()
	await get_tree().process_frame
	# Made at one size and grown after (the lab's size bar): the string is fitted to it again.
	var grown: Node3D = (load(BOW_SCENE) as PackedScene).instantiate() as Node3D
	add_child(grown)
	var gs: BowString = grown.get_node("String") as BowString
	var before: float = gs.tip_a.distance_to(gs.tip_b)
	(grown.get_node("Model") as Node3D).scale *= 1.4
	gs._update()
	_check(absf(gs.tip_a.distance_to(gs.tip_b) / before - 1.4) < 0.01 and gs.nock.is_equal_approx(gs.rest_nock),
		"a bow grown after it was made has its string fitted again (%.2f m to %.2f m)" % [before, gs.tip_a.distance_to(gs.tip_b)])
	grown.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the trail

func _run_trail() -> void:
	var a: ShowcaseActor = _actor()
	var l: MotionLayer = _layer(a)
	var trail := MotionTrail.new()
	add_child(trail)
	trail.set_process(false)
	trail.life_s = 5.0
	trail.follow(a.held)
	trail.emitting = true
	# Sampled as the skeleton draws (`skeleton_updated`): through the sky blade, where its clip raises the blade over
	# the head, the newest blade starts by the hand AS DRAWN, never down where the pose under the move holds it.
	var off: Array[float] = [0.0]
	var counted: Array[int] = [0]
	await _through(a, l, _move("sky_blade"), func(u: float) -> void:
		trail.step(1.0 / 30.0)
		if u > 0.3 and u < 0.45 and trail.sample_count() > 0:
			var base: Vector3 = trail._samples[trail._samples.size() - 1][0] as Vector3
			off[0] = maxf(off[0], base.distance_to(_seen(l, &"hand_r")))
			counted[0] += 1)
	_check(trail.sample_count() >= 20, "the trail keeps the blade while it draws (%d)" % trail.sample_count())
	_check(counted[0] > 0 and off[0] < 0.5, "the trail is on the blade as drawn: it starts by the bent hand (%.2f m off, %d frames)" % [off[0], counted[0]])
	trail.emitting = false
	trail.life_s = 0.2
	for i: int in 30:
		trail.step(1.0 / 60.0)
	_check(trail.sample_count() == 0, "and is empty once it stops and its life runs out")
	trail.emitting = true
	for i: int in 3:
		await get_tree().process_frame
	trail.clear()
	_check(trail.sample_count() == 0, "clear forgets it (a blink: no ribbon across the gap)")
	trail.queue_free()
	a.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the wrist

func _run_wrist() -> void:
	var a: ShowcaseActor = _actor()
	var l: MotionLayer = _layer(a)
	var skel: Skeleton3D = a.skeleton
	var hand: int = skel.find_bone("hand_r")
	var kids: PackedInt32Array = skel.get_bone_children(hand)
	_check(not kids.is_empty(), "the hand carries bones (fingers)")
	if kids.is_empty():
		a.queue_free()
		return
	var finger: StringName = StringName(skel.get_bone_name(kids[0]))
	l.bones.watch = [&"hand_r", &"lowerarm_r", finger]
	var roll := MotionMove.new()
	roll.length_s = 1.0
	roll.wrist_deg = 90.0
	roll.wrist = Curve.new()
	roll.wrist.add_point(Vector2(0.0, 1.0))
	roll.wrist.add_point(Vector2(1.0, 1.0))
	var none: MotionMove = roll.duplicate() as MotionMove
	none.wrist_deg = 0.0
	# The same frame with no roll and with it: the finger from the hand, and the hand.
	var fingers: Array[Vector3] = []
	var hands: Array[Vector3] = []
	for m: MotionMove in [none, roll]:
		var got: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
		await _through(a, l, m, func(u: float) -> void:
			if u > 0.4 and u < 0.6:
				got[0] = _seen(l, finger) - _seen(l, &"hand_r")
				got[1] = _seen(l, &"hand_r"))
		fingers.append(got[0])
		hands.append(got[1])
	var f0: Vector3 = fingers[0]
	var f1: Vector3 = fingers[1]
	var angle: float = rad_to_deg(f0.angle_to(f1)) if f0.length() > 0.001 and f1.length() > 0.001 else 0.0
	_check(angle > 20.0, "the wrist rolls the hand: what it carries turns (%.0f deg)" % angle)
	_check(hands[0].distance_to(hands[1]) < 0.02, "and the arm does not move (the hand %.3f m away)" % hands[0].distance_to(hands[1]))
	a.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- in the game (PROGRESS 110)

func _run_ability_table() -> void:
	var table: AbilityMoves = load(AbilityMoves.PATH) as AbilityMoves
	_check(table != null and table.rows.size() >= 9, "the abilities shown as moves are there (%d)" % (table.rows.size() if table != null else 0))
	if table == null:
		return
	var in_kits: Dictionary[int, bool] = {}
	for k: KitDef in KitDef.all():
		for a: AbilityDef in k.abilities():
			in_kits[a.id] = true
	for r: AbilityMove in table.rows:
		var n: String = r.ability.display_name if r.ability != null else "a row"
		_check(r.ability != null and in_kits.has(r.ability.id), "%s is a kit's ability" % n)
		_check(r.move != null and r.move.length_s > 0.0, "%s has a move" % n)
	# Every motion lab placeholder has its row (its notes say so).
	for k: KitDef in KitDef.all():
		for a: AbilityDef in k.abilities():
			if a.designer_notes.contains("PROGRESS 110"):
				_check(AbilityMoves.of(a.id) != null, "%s (a motion lab placeholder) is shown as its move" % a.display_name)
	var hook: AbilityMove = AbilityMoves.of(40063)
	_check(hook != null and hook.victim != null and hook.victim.resource_path.ends_with("dragged.tres"), "the hook pull hauls its foe (dragged)")
	_check(AbilityMoves.of(40001) == null, "NEGATIVE: the sword's first slash has no move: its clip as before")


func _run_in_game() -> void:
	var a: ShowcaseActor = _actor()
	var foe: ShowcaseActor = _actor()
	foe.walk_to(a.position + Vector3(0.0, 0.0, -3.0), 0.0)
	foe.step(0.0)
	var p: MotionPlayer = MotionPlayer.make(a, a.driver)
	var q: MotionPlayer = MotionPlayer.make(foe, foe.driver)
	_check(p != null and q != null, "a fighter gets a motion player on its model")
	if p == null or q == null:
		a.queue_free()
		foe.queue_free()
		return
	_check(not p.layer.carry and p.layer.lift_scale == 0.0, "in the game it carries nothing and lifts nothing (the server moves the body)")
	_check(not p.began(40001) and not p.layer.playing(), "NEGATIVE: an ability with no row plays nothing")
	_check(p.began(40063) and p.layer.playing() and p.layer.move == AbilityMoves.of(40063).move, "the hook pull plays its move as it begins")
	# A hit from it on the foe: the foe is dragged (EntityRegistry finds who struck).
	EntityRegistry.register(a.entity_id, a)
	q.hit_by(12.0, a.entity_id)
	_check(q.layer.playing() and q.layer.move == AbilityMoves.of(40063).victim, "the foe it hits plays its victim move (dragged)")
	q.layer.stop()
	p.last_ability_ms -= MotionPlayer.HIT_WINDOW_MS + 100
	q.hit_by(12.0, a.entity_id)
	_check(not q.layer.playing(), "NEGATIVE: a hit long after it began plays nothing")
	p.began(40062)
	q.hit_by(12.0, a.entity_id)
	_check(q.layer.move == AbilityMoves.of(40062).victim, "the kick sends its foe flying (kicked)")
	q.layer.stop()
	p.began(40058)
	q.hit_by(12.0, a.entity_id)
	_check(not q.layer.playing(), "NEGATIVE: the leaping strike has no victim move: its foe flinches as before")
	EntityRegistry.unregister(a.entity_id)
	# Its height is the server's: the leap slam's hips stay low here (the lab lifts them over 1.5 m).
	p.layer.stop()
	p.layer.bones.watch = [&"pelvis"]
	p.layer.manual = true
	var slam: MotionMove = _move("leap_slam")
	p.layer.play(slam, Vector3(0.0, 0.0, -1.0))
	var hips: float = 0.0
	while p.layer.playing():
		a.step(1.0 / 30.0)
		p.layer.step(1.0 / 30.0)
		await get_tree().process_frame
		hips = maxf(hips, (p.layer.bones.seen.get(&"pelvis", Vector3.ZERO) as Vector3).y - a.position.y)
	_check(hips < 1.3, "the leap slam's own height is left to the server's lift (hips %.2f m)" % hips)
	a.queue_free()
	foe.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the lab

func _await_lab(lab: Node3D, done: Callable, seconds: float) -> void:
	var waited: float = 0.0
	var last: int = Time.get_ticks_msec()
	while not bool(done.call()) and waited < seconds:
		await get_tree().process_frame
		var now: int = Time.get_ticks_msec()
		waited += float(now - last) / 1000.0
		last = now


## THE CLIP BROWSER (PROGRESS 114): a Mixamo clip on the browser's adventurer holding the yew bow at 1.4x, played to its
## length; then the staff, then nothing. NEGATIVES: a clip no library has is refused and changes nothing; the sword's
## showcase hides the browser's panel.
func _run_browser(lab: Node3D) -> void:
	var index: int = int(lab.get(&"BROWSER"))
	_check(String((lab.get(&"showcases") as Array[Array])[index][2]) == "_browse", "the lab's list ends with the clip browser")
	var bow: String = "res://game/regents/combat/weapons/yew_bow.tscn"
	lab.call(&"_set_paused", false)
	lab.call(&"browse_hold", bow, 1.4)
	_check(bool(lab.call(&"browse", "mx_great_sword", &"great_sword_slash_4")), "it takes a Mixamo clip")
	lab.call(&"_select", index)
	var coded: RefCounted = lab.get(&"coded") as RefCounted
	var a: ShowcaseActor = coded.get(&"browser") as ShowcaseActor
	var l: MotionLayer = (coded.get(&"layers") as Dictionary).get(a) as MotionLayer
	await _await_lab(lab, func() -> bool: return bool(lab.get(&"started")) and l.playing(), 4.0)
	var clip: Animation = MotionClip.find(&"mx_great_sword/great_sword_slash_4")
	_check(l.playing() and l.move != null and l.move.clips[0].animation == &"mx_great_sword/great_sword_slash_4",
		"the browser's adventurer plays it")
	_check(is_equal_approx(float(lab.call(&"_length_of", index)), clip.length), "the time bar is the clip's length (%.2f s)" % clip.length)
	var model: Node3D = a.held.get_node_or_null("Model") as Node3D if a.held != null else null
	_check(a.held != null and a.held.scene_file_path == bow and model != null and is_equal_approx(model.scale.x, 0.75 * 1.4),
		"holding the yew bow at 1.4x (its model %.2f)" % (model.scale.x if model != null else 0.0))
	var panel: Control = lab.get(&"_br_panel") as Control
	_check(panel.visible, "its panel shows")
	# NEGATIVE: no such clip.
	_check(not bool(lab.call(&"browse", "mx_magic", &"no_such_clip")) and lab.get(&"browse_clip") == &"great_sword_slash_4",
		"NEGATIVE: a clip no library has is refused, and the choice stays")
	lab.call(&"browse_hold", "res://game/regents/combat/weapons/yew_staff.tscn", 1.0)
	_check(a.held != null and a.held.scene_file_path.ends_with("yew_staff.tscn"), "then the staff")
	lab.call(&"browse_hold", "", 1.0)
	_check(a.held == null, "then nothing")
	lab.call(&"_select", 0)
	_check(not panel.visible, "NEGATIVE: another showcase hides the browser's panel")


func _run_lab() -> void:
	var lab: Node3D = (load(LAB) as PackedScene).instantiate() as Node3D
	var shows: Array[Array] = lab.get(&"showcases") as Array[Array]
	var named: String = ""
	for s: Array in shows:
		named += String(s[1]) + " "
	var missing: PackedStringArray = PackedStringArray()
	for n: String in _move_names():
		if not named.contains(n + ".tres"):
			missing.append(n)
	_check(missing.is_empty(), "the lab shows every move (not shown: %s)" % [missing])
	add_child(lab)
	await get_tree().process_frame
	var index: int = -1
	for i: int in shows.size():
		if String(shows[i][0]) == "Shoulder charge":
			index = i
	lab.call(&"_select", index)
	var coded: RefCounted = lab.get(&"coded") as RefCounted
	var charger: ShowcaseActor = coded.get(&"sword") as ShowcaseActor
	var dummies: Array[ShowcaseActor] = coded.get(&"dummies") as Array[ShowcaseActor]
	var foe: ShowcaseActor = dummies[0]
	var foe_layer: MotionLayer = (coded.get(&"layers") as Dictionary).get(foe) as MotionLayer
	foe_layer.bones.watch = [&"Head", &"pelvis"]
	await _await_lab(lab, func() -> bool: return bool(lab.get(&"started")), 3.0)
	var from: Vector3 = charger.position
	var foe_from: Vector3 = foe.position
	await _await_lab(lab, func() -> bool: return not bool(lab.get(&"_running")), 8.0)
	_check(not bool(lab.get(&"_running")), "the shoulder charge plays to its end")
	var charged: float = from.z - charger.position.z
	_check(charged > 5.0 and charged < 6.3, "the charger is carried by the sprint and the dash (%.2f m)" % charged)
	_check(foe_from.z - foe.position.z > 3.5, "the foe is thrown back (%.2f m)" % (foe_from.z - foe.position.z))
	var head_up: float = (foe_layer.bones.seen.get(&"Head", Vector3.ZERO) as Vector3).y - (foe_layer.bones.seen.get(&"pelvis", Vector3.ZERO) as Vector3).y
	_check(head_up > 0.4, "and on its feet again at the end (head %.2f m over the hips)" % head_up)
	# THE SCRUBBER: to a moment ahead, held there; back to an earlier one (played again); the same frame each time.
	var seek: Callable = func(t: float) -> void: lab.call(&"seek", t)
	var settled: Callable = func() -> bool: return float(lab.get(&"_seek_to")) < 0.0
	seek.call(0.3)
	await _await_lab(lab, settled, 6.0)
	var at_03: Vector3 = charger.position
	_check(absf(float(lab.get(&"clock")) - 0.3) < 0.02 and bool(lab.get(&"paused")), "the scrubber lands on 0.30 s and holds (%.3f)" % float(lab.get(&"clock")))
	var held: Vector3 = charger.position
	for i: int in 10:
		await get_tree().process_frame
	_check(charger.position.distance_to(held) < 0.001, "held: nothing moves")
	seek.call(0.9)
	await _await_lab(lab, settled, 6.0)
	_check(absf(float(lab.get(&"clock")) - 0.9) < 0.02, "on to 0.90 s (%.3f)" % float(lab.get(&"clock")))
	_check(charger.position.distance_to(at_03) > 1.0, "where the charger has got to by then")
	seek.call(0.3)
	await _await_lab(lab, settled, 6.0)
	_check(absf(float(lab.get(&"clock")) - 0.3) < 0.02, "back to 0.30 s (played again from the start: %.3f)" % float(lab.get(&"clock")))
	_check(charger.position.distance_to(at_03) < 0.08, "the same frame as before (%.3f m apart)" % charger.position.distance_to(at_03))
	await _run_browser(lab)
	lab.queue_free()
	Engine.time_scale = 1.0
	await get_tree().process_frame
