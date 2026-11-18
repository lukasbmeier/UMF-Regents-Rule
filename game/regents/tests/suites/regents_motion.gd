extends "res://tests/suite_base.gd"
## MOVES MADE OF CLIPS AND CODE (`-- --only=regents_motion`; 2026-11-17, the motion lab), with no server and no renderer:
##   - every move in `game/regents/motion/moves/` loads, names only clips that exist, begins and ends with its channels
##     at rest (a spin whole turns), and its clips' seams leave no gap where the pose under them shows through; the
##     spinning advance turns seven times; NEGATIVE: a move left tipped over is caught, a clip with no such name is
##     found missing, a move with no curves and no clips never moves
##   - a clip's stretch: time-warped to its part (forward and back), eased in and out, nothing outside it
##   - the figure's turn (the code's): about the hips, a tip toward the facing, a spin to the left, a squash feet down
##   - on a real character (`ShowcaseActor`, stepped by hand; the bent bones read where they are drawn,
##     `MotionBones.seen`): the back flip's clip puts the head under the hips and the body lands 2.5 m back; the sky
##     blade's clip raises the sword hand over the head; the leap slam's clips lift the hips over 1.5 m; the spinning
##     dash's clip root carries it its 7 m; the dragged foe is hauled forward; the hook's reach (code) points the arm at
##     its target; NEGATIVES: the same moves with their clips taken out stay on their feet, hand low, hips low, carried
##     only as far as the code says, and with the layer off the arm points elsewhere
##   - the trail keeps a blade while it draws and is empty once it stops and its life runs out
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
	_check(names.size() >= 11, "the lab's moves are there (%d)" % names.size())
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
	_check(absf(spin.at(spin.length_s).spin - 7.0 * TAU) < 0.01, "the spinning advance turns seven times")
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
			_check(went > 1.5, "the dragged foe is hauled forward (%.2f m)" % went)
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


# ---------------------------------------------------------------- the trail

func _run_trail() -> void:
	var a: ShowcaseActor = _actor()
	var trail := MotionTrail.new()
	add_child(trail)
	trail.set_process(false)
	trail.follow(a.held)
	trail.emitting = true
	for i: int in 10:
		trail.step(1.0 / 60.0)
	_check(trail.sample_count() >= 9, "the trail keeps the blade while it draws (%d)" % trail.sample_count())
	trail.emitting = false
	for i: int in 30:
		trail.step(1.0 / 60.0)
	_check(trail.sample_count() == 0, "and is empty once it stops and its life runs out")
	trail.queue_free()
	a.queue_free()
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
	lab.queue_free()
	Engine.time_scale = 1.0
	await get_tree().process_frame
