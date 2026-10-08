extends "res://tests/suite_base.gd"
## The `grip` suite (tests/test_runner.gd runs it; `-- --only=grip` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_rod_grip_tests()



## THE LINE, DRAWN. Reported: "the line looks strange as it arcs into the water on long casts" —
## it sagged by its length whatever was under it, so a 40 m line dived under the lake halfway
## out and came back up at the float. Slack line droops from the rod tip until it meets the water
## and lies on it from there; it never runs under the surface.
## THE ROD IN THE HAND (DECISIONS #147): the grip file the game reads, the steady carry's
## geometry, and the editor preview that writes the file — driven the way the gizmo drives it.
func _run_rod_grip_tests() -> void:
	print("== held items: the grip ==")
	# --- ONE GRIP: the gizmo's place in, the same place out ------------------------------------
	var hand := Transform3D(Basis.from_euler(Vector3(0.4, 1.1, -0.3), EULER_ORDER_YXZ), Vector3(0.5, 1.2, -0.3))
	var body := Basis(Vector3.UP, 0.7)
	var want := Transform3D(Basis.from_euler(Vector3(0.3, -1.2, 0.5), EULER_ORDER_YXZ), Vector3(0.6, 1.25, -0.2))
	var e := GripEntry.new()
	_check(e.set_held(want, hand, body) and (hand * e.in_hand(hand, body)).is_equal_approx(want),
		"a grip taken from the gizmo puts the item back exactly where the gizmo was")
	_check(not e.set_held(want, hand, body), "setting the same place again changes nothing")
	var d: Vector3 = e.rotation_degrees
	e.rotation_degrees = Vector3(180.0 - d.x, d.y + 180.0, d.z + 180.0)
	_check(not e.set_held(want, hand, body) and e.rotation_degrees == Vector3(180.0 - d.x, d.y + 180.0, d.z + 180.0),
		"nor does the same turn spelled another way — and the spelling typed is kept")
	# STEADY: the direction kept to the BODY, the grip still in the hand.
	var s := GripEntry.new()
	s.position = Vector3(0.0, 0.1, 0.0)
	s.rotation_degrees = Vector3(20.0, 40.0, 0.0)
	var turned := Transform3D(hand.basis.rotated(Vector3.RIGHT, 0.8), hand.origin + Vector3(0.0, 0.1, 0.05))
	var held_before: Transform3D = hand * s.in_hand(hand, body)
	_check(not (turned * s.in_hand(turned, body)).basis.is_equal_approx(held_before.basis),
		"CONTROL: following the hand, the item turns when the hand turns")
	s.set_steady(true, hand, body)
	_check(s.steady and (hand * s.in_hand(hand, body)).is_equal_approx(held_before),
		"made steady, the item does not move in the frame it was made steady in")
	var held_turned: Transform3D = turned * s.in_hand(turned, body)
	_check(held_turned.basis.is_equal_approx(held_before.basis) and held_turned.origin.is_equal_approx(turned * s.position),
		"steady, it keeps its direction when the hand turns, with its grip still in the hand")
	var body2 := Basis(Vector3.UP, 1.9)
	_check((hand * s.in_hand(hand, body2)).basis.is_equal_approx(body2 * body.inverse() * held_before.basis),
		"and it turns with the body")

	# --- WHICH GRIP AN ANIMATION USES (DECISIONS #156) -----------------------------------------
	# Luke: "each item should have two variables, body tweaks and animation tweaks. The mode feels
	# redundant ... I should be able to tie ANY animation to either body exactly as it looks best,
	# and anytime that animation is called (from modes or other means) the item should match."
	var g := ItemGrip.new()
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.1, 0.0), Vector3.ZERO, false))
	g.entries.append(_grip_entry(AnimationSet.RUN, Vector3(0.0, 0.2, 0.0), Vector3(0.0, 90.0, 0.0), false))
	g.entries.append(_grip_entry(&"fishing.heave", Vector3(0.0, 0.3, 0.0), Vector3.ZERO, false))
	_check(is_equal_approx(g.resolve(AnimationSet.RUN).position.y, 0.2)
			and g.resolve(AnimationSet.RUN_LEFT).animation == AnimationSet.RUN
			and g.resolve(AnimationSet.SPRINT).animation == AnimationSet.RUN
			and is_equal_approx(g.resolve(&"fishing.heave").position.y, 0.3),
		"an animation uses its own grip, and one whose clip falls back to it borrows it (run_left, sprint)")
	_check(g.resolve(AnimationSet.WALK).animation == AnimationSet.IDLE and g.resolve(&"fishing.wait").animation == AnimationSet.IDLE
			and g.resolve(AnimationSet.INTERACT).animation == AnimationSet.IDLE and g.resolve(&"").animation == AnimationSet.IDLE,
		"and every animation with no grip anywhere along its fallbacks borrows the idle's, a genre's own included")
	_check(ItemGrip.steps(AnimationSet.SPRINT) == ([AnimationSet.SPRINT, AnimationSet.RUN, AnimationSet.WALK, AnimationSet.IDLE] as Array[StringName])
			and ItemGrip.steps(&"fishing.heave") == ([&"fishing.heave", AnimationSet.IDLE] as Array[StringName]),
		"the steps a sprint looks at: sprint, run, walk, idle; a genre's heave: itself, then the idle")
	_check(ItemGrip.new().resolve(AnimationSet.RUN) == null and g.animations() == ([AnimationSet.IDLE, AnimationSet.RUN, &"fishing.heave"] as Array[StringName]),
		"a grip file with no grips has none to give, and a file lists the animations it has grips for")
	var walk: GripEntry = g.ensure(AnimationSet.WALK)
	_check(is_equal_approx(walk.position.y, 0.1) and g.entries.size() == 4 and g.ensure(AnimationSet.WALK) == walk
			and g.resolve(AnimationSet.RUN).animation == AnimationSet.RUN,
		"giving the walk its own grip starts it where the walk had the item (the idle's), once; the run keeps its own")
	_check(g.remove(AnimationSet.WALK) and g.resolve(AnimationSet.WALK).animation == AnimationSet.IDLE
			and not g.remove(AnimationSet.IDLE) and g.find(AnimationSet.IDLE) != null,
		"taking it away makes it borrow again; the idle's shared grip, which everything borrows, is not taken away")
	# BLENDED AS THE ANIMATIONS BLEND.
	var half: Transform3D = g.blend({AnimationSet.IDLE: 0.5, AnimationSet.RUN: 0.5}, Transform3D(), Basis())
	_check(half.origin.is_equal_approx(Vector3(0.0, 0.15, 0.0))
			and absf(rad_to_deg(Quaternion(half.basis).get_angle()) - 45.0) < 0.01,
		"half idle and half run: half way between their grips, in place and in turn (%s)" % half.origin)
	_check(g.blend({AnimationSet.IDLE: 0.5, &"fishing.heave": 0.5}, Transform3D(), Basis()).origin.is_equal_approx(Vector3(0.0, 0.2, 0.0)),
		"half way through blending into the heave: half way to the heave's grip")
	_check(g.blend({}, Transform3D(), Basis()).origin.is_equal_approx(Vector3(0.0, 0.1, 0.0)),
		"told no animation, the idle's grip")
	# PER BODY (DECISIONS #155): Luke, "can I not just change the position of the female body?"
	# Her own grip wins over the shared one at the same step — and only there: the run's own grip,
	# shared, still beats her idle grip while she runs.
	g.entries.append(_grip_entry(AnimationSet.IDLE, Vector3(0.0, 0.15, 0.0), Vector3.ZERO, false))
	g.entries[g.entries.size() - 1].body = &"female"
	_check(is_equal_approx(g.resolve(AnimationSet.IDLE, &"female").position.y, 0.15)
			and is_equal_approx(g.resolve(AnimationSet.IDLE, &"male").position.y, 0.1)
			and is_equal_approx(g.resolve(AnimationSet.IDLE).position.y, 0.1),
		"an idle grip kept for the female body is hers alone: the male body and an unknown one keep the shared")
	_check(is_equal_approx(g.resolve(AnimationSet.WALK, &"female").position.y, 0.15)
			and is_equal_approx(g.resolve(AnimationSet.RUN, &"female").position.y, 0.2),
		"her walk borrows her idle grip, and the run's own grip, shared, still beats it while she runs")
	var her_run: GripEntry = g.ensure(AnimationSet.RUN, &"female")
	_check(is_equal_approx(her_run.position.y, 0.2) and her_run.body == &"female"
			and g.resolve(AnimationSet.SPRINT, &"female") == her_run
			and is_equal_approx(g.resolve(AnimationSet.SPRINT, &"male").position.y, 0.2),
		"her own run grip starts where her run was, and her sprint borrows it; his sprint the shared run's")
	_check(g.bodies() == ([&"female"] as Array[StringName])
			and g.blend({AnimationSet.IDLE: 1.0}, Transform3D(), Basis(), &"female").origin.is_equal_approx(Vector3(0.0, 0.15, 0.0)),
		"the game blends with her grips when it knows she is the one holding it")
	_check(g.remove(AnimationSet.IDLE, &"female") and is_equal_approx(g.resolve(AnimationSet.IDLE, &"female").position.y, 0.1),
		"taking her idle grip away gives her the shared one")

	# --- THE BODY: capsules round its bones, built to measure ------------------------------------
	var sk := Skeleton3D.new()
	for spec: Array in [["thigh_r", -1, Vector3(0.1, 1.0, 0.0)], ["calf_r", 0, Vector3(0.0, -0.5, 0.0)],
			["foot_r", 1, Vector3(0.0, -0.4, 0.0)], ["thigh_l", -1, Vector3(-0.1, 1.0, 0.0)],
			["calf_l", 3, Vector3(0.0, -0.5, 0.0)], ["foot_l", 4, Vector3(0.0, -0.4, 0.0)],
			["spine_01", -1, Vector3(0.0, 1.05, 0.0)], ["neck_01", 6, Vector3(0.0, 0.5, 0.0)],
			["Head", 7, Vector3(0.0, 0.1, 0.0)]]:
		var i: int = sk.add_bone(String(spec[0]))
		sk.set_bone_parent(i, int(spec[1]))
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, spec[2]))
		sk.set_bone_pose_position(i, spec[2])
	add_child(sk)
	var by_thigh: Dictionary = BodyClearance.measure(sk, Vector3(0.4, 0.75, 0.0), 0.03)
	_check(is_equal_approx(float(by_thigh["air"]), 0.3 - 0.10 - 0.03) and by_thigh["part"] == "right thigh",
		"a ball 30 cm off the right thigh has that, less the thigh and itself, of air (%.3f m, %s)"
			% [by_thigh["air"], by_thigh["part"]])
	_check(float(BodyClearance.measure(sk, Vector3(0.0, 1.3, 0.1), 0.0)["air"]) < 0.0
			and BodyClearance.measure(sk, Vector3(0.0, 1.3, 0.1), 0.0)["part"] == "torso",
		"and one at the chest is inside the torso")
	var thing := Node3D.new()
	var marked := Node3D.new()
	marked.name = "Pommel"
	marked.set_meta(BodyClearance.META, 0.02)
	thing.add_child(marked)
	thing.add_child(Node3D.new())
	_check(BodyClearance.points_of(thing) == ([marked] as Array[Node3D]),
		"an item is measured at the nodes it marks with a clearance_radius, and only those")
	thing.free()
	# A LINE (#156): a rod's blank swept through the head while both its ends stayed clear, and the
	# preview, measuring only the reel, called the run green.
	var head_at: Vector3 = Vector3(0.0, 1.65 + BodyClearance.HEAD_UP, 0.0)
	var left_end: Vector3 = head_at + Vector3(-0.5, 0.0, 0.0)
	var right_end: Vector3 = head_at + Vector3(0.5, 0.0, 0.0)
	_check(float(BodyClearance.measure(sk, left_end, 0.01)["air"]) > 0.3 and float(BodyClearance.measure(sk, right_end, 0.01)["air"]) > 0.3,
		"CONTROL: two points half a metre either side of the head are well clear of it")
	var through: Dictionary = BodyClearance.measure_line(sk, left_end, right_end, 0.01)
	_check(is_equal_approx(float(through["air"]), -0.12 - 0.01) and through["part"] == "head",
		"and the line between them goes through it: %.3f m of air, against the %s" % [through["air"], through["part"]])
	_check(is_equal_approx(BodyClearance.between_segments(Vector3(0.3, 0.8, -1.0), Vector3(0.3, 0.8, 1.0), Vector3(0.1, 1.0, 0.0), Vector3(0.1, 0.5, 0.0)), 0.2),
		"a line crossing in front of a bone is as far from it as the gap between them (0.2 m)")
	var blade := Node3D.new()
	var base := Node3D.new()
	base.name = "Base"
	base.set_meta(BodyClearance.META, 0.01)
	base.set_meta(BodyClearance.LINE_TO, NodePath("../Point"))
	var point := Node3D.new()
	point.name = "Point"
	blade.add_child(base)
	blade.add_child(point)
	add_child(blade)
	base.global_position = left_end
	point.global_position = right_end
	var blade_air: Dictionary = BodyClearance.item_air(sk, blade)
	_check(float(blade_air["air"]) < 0.0 and blade_air["part"] == "head" and blade_air["point"] == "Base",
		"an item's node with a clearance_to meta is measured as a line to that node (%s against the %s)"
			% [blade_air["point"], blade_air["part"]])
	blade.queue_free()
	var rod_marks: Array[String] = []
	var rod_inst: Node = (load("res://game/fishing/fishing_rod.tscn") as PackedScene).instantiate()
	for n: Node3D in BodyClearance.points_of(rod_inst):
		rod_marks.append("%s%s" % [n.name, " -> %s" % n.get_meta(BodyClearance.LINE_TO) if n.has_meta(BodyClearance.LINE_TO) else ""])
	rod_inst.free()
	_check(rod_marks == (["Reel", "Shaft -> ../Tip"] as Array[String]),
		"the rod is measured at its reel, and along its blank to the tip (%s)" % ", ".join(rod_marks))
	sk.queue_free()

	# --- THE HOLE A HAND MAKES (DECISIONS #157) -----------------------------------------------------
	# Four fingers curled round a circle 2.5 cm in radius whose line runs along the hand's z, centred
	# at (0.03, 0.09): the fit finds the circle, its line, and that it is a fist. The same fingers
	# held straight are not one.
	var hand_sk := Skeleton3D.new()
	var hand_bone: int = hand_sk.add_bone("hand_r")
	var finger_z: Dictionary[String, float] = {"index": 0.03, "middle": 0.01, "ring": -0.01, "pinky": -0.03}
	var round_deg: Array[float] = [180.0, 90.0, 0.0, -60.0]
	var joint_names: Array[String] = ["_01", "_02", "_03", "_04_leaf"]
	for f: String in finger_z:
		for j: int in range(4):
			var b: int = hand_sk.add_bone(f + joint_names[j] + "_r")
			hand_sk.set_bone_parent(b, hand_bone)
			var a: float = deg_to_rad(round_deg[j])
			var at: Vector3 = Vector3(0.03 + 0.025 * cos(a), 0.09 + 0.025 * sin(a), finger_z[f])
			hand_sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, at))
			hand_sk.set_bone_pose_position(b, at)
	add_child(hand_sk)
	var curled: Dictionary = GripFit.hole(hand_sk, &"hand_r")
	# THE HOLE IS INSIDE THE FIST (DECISIONS #158): the biggest circle walled by the palm (the wrist
	# to the knuckle), the curled finger and the gap from the fingertip back to the wrist. A circle
	# through the finger joints alone (centre (0.03, 0.09), 2.5 cm) crosses that gap 2.2 cm from its
	# centre: a handle there showed through the fingers.
	var ring: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for j: int in range(4):
		var aj: float = deg_to_rad(round_deg[j])
		ring.append(Vector2(0.03 + 0.025 * cos(aj), 0.09 + 0.025 * sin(aj)))
	var c2: Vector2 = Vector2((curled.get("centre", Vector3.INF) as Vector3).x, (curled.get("centre", Vector3.INF) as Vector3).y)
	var r2: float = float(curled.get("radius", 0.0))
	var nearest_wall: float = INF
	for k: int in range(ring.size()):
		nearest_wall = minf(nearest_wall, c2.distance_to(Geometry2D.get_closest_point_to_segment(c2, ring[k], ring[(k + 1) % ring.size()])))
	_check(not curled.is_empty() and (curled["axis"] as Vector3).angle_to(Vector3(0.0, 0.0, 1.0)) < 0.01
			and is_equal_approx((curled["centre"] as Vector3).z, 0.01) and bool(curled["fist"]),
		"fingers curled round a handle: its line runs across the knuckles, and the hand is a fist")
	_check(Geometry2D.is_point_in_polygon(c2, ring) and nearest_wall >= r2 - 0.0005 and r2 >= 0.019,
		"and the hole is the biggest circle inside the fist: centre %s, %.1f cm across the bones, touching no wall (nearest %.1f cm)"
			% [c2, r2 * 100.0, nearest_wall * 100.0])
	var old_centre: Vector2 = Vector2(0.03, 0.09)
	var old_wall: float = INF
	for k: int in range(ring.size()):
		old_wall = minf(old_wall, old_centre.distance_to(Geometry2D.get_closest_point_to_segment(old_centre, ring[k], ring[(k + 1) % ring.size()])))
	_check(old_wall < 0.025, "CONTROL: the circle through the finger joints (2.5 cm) reaches through the fist's mouth, %.1f cm from its centre" % (old_wall * 100.0))
	for f: String in finger_z:
		for j: int in range(4):
			hand_sk.set_bone_pose_position(hand_sk.find_bone(f + joint_names[j] + "_r"),
				Vector3(0.03, 0.09 + 0.02 * float(j), finger_z[f]))
	var straight: Dictionary = GripFit.hole(hand_sk, &"hand_r")
	_check(not bool(straight["fist"]) and float(straight["curl_deg"]) < 45.0,
		"and the same fingers held straight are no fist (curled %.0f deg)" % float(straight["curl_deg"]))
	hand_sk.queue_free()

	# IN THE EDITOR ONLY TOOL SCRIPTS RUN. The first grip preview stood empty there while this suite
	# passed: the looks' assembly did not run, and the preview called a method on the animation
	# set, a data class there. A headless run cannot see either, so check the source.
	var preview_src: String = FileAccess.get_file_as_string("res://foundation/held/held_item_preview.gd")
	var editor_calls: Array[String] = []
	for m: String in ["anim_name(", "has_exact(", "visual_for(", "missing_required(", "can_strafe(", ".clip(",
			"HeldItem.", "FishingRod.", "held_in_hand(", "set_mode("]:
		if preview_src.contains(m):
			editor_calls.append(m)
	_check(editor_calls.is_empty(), "the preview calls no method of a class that is data in the editor (%s)"
		% ", ".join(editor_calls))
	var tools: Array[String] = []
	for f: String in ["res://game/characters/modular_character.gd", "res://foundation/held/grip_entry.gd",
			"res://foundation/held/item_grip.gd", "res://foundation/held/body_clearance.gd",
			"res://foundation/held/off_hand.gd", "res://foundation/held/held_item_preview.gd"]:
		if not FileAccess.get_file_as_string(f).begins_with("@tool"):
			tools.append(f.get_file())
	_check(tools.is_empty(), "and what it does call runs in the editor: the looks, the grip, the body (%s)" % ", ".join(tools))

	# --- THE PREVIEW, driven as the gizmo drives it. It runs at runtime too; only the editor writes
	# the file. It edits a COPY here, and its pose and looks are set here: the scene saves whatever
	# the last person to edit it left.
	var scene: PackedScene = load("res://game/fishing/rod_grip_preview.tscn") as PackedScene
	var prev: Node3D = scene.instantiate() as Node3D if scene != null else null
	_check(prev != null, "the grip preview scene loads")
	if prev == null:
		return
	var file_grip: ItemGrip = prev.get("grip") as ItemGrip
	_check(file_grip != null and file_grip.resource_path == "res://game/fishing/rod_grip.tres",
		"it edits the grip file the game reads")
	var rod_scene: PackedScene = load("res://game/fishing/fishing_rod.tscn") as PackedScene
	var in_game: FishingRod = rod_scene.instantiate() as FishingRod
	_check(in_game.grip == file_grip, "and the game's rod reads that same file")
	in_game.free()
	var file_before: String = _grip_text(file_grip)
	var fixture: ItemGrip = _item_grip_from(GRIP_147)
	prev.set("grip", fixture)
	prev.set("look", 5)
	prev.set("beside", 0)
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "both")
	prev.set("pose_at", 0.0)
	prev.set("play", false)
	add_child(prev)
	for i: int in range(4):
		await get_tree().process_frame
	var bodies: int = prev.call("body_count")
	_check(bodies == 2 and str(prev.call("look_name", 0)).ends_with("_f") and str(prev.call("look_name", 1)).ends_with("_m"),
		"it shows the grip on a woman and a man: every look is one of those two bodies")
	if bodies != 2:
		prev.queue_free()
		return
	_check(prev.call("body_type_of", 0) == &"female" and prev.call("body_type_of", 1) == &"male",
		"and it knows which body each is, from its look (%s, %s)" % [prev.call("body_type_of", 0), prev.call("body_type_of", 1)])
	var grip_node: Node3D = prev.get_node(^"Grip") as Node3D
	var idle_grip: GripEntry = fixture.find(AnimationSet.IDLE)
	var h0: Transform3D = prev.call("hand_of", 0)
	var shown: Node3D = prev.call("item_of", 0)
	var his: Node3D = prev.call("item_of", 1)
	var label: Label3D = prev.call("label_of", 0)
	_check(_hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0)))
			and grip_node.global_transform.is_equal_approx(_hold_at(shown))
			and _hold_at(his).is_equal_approx(
				(prev.call("hand_of", 1) as Transform3D) * idle_grip.in_hand(prev.call("hand_of", 1), prev.call("body_of", 1))),
		"standing, the Grip node sits in her hand in the idle's grip, and each rod in its own hand")
	_check(prev.call("editing") == idle_grip and prev.call("holder") == 0
			and label.text.contains("SETTING locomotion.idle · both") and label.text.contains("uses locomotion.idle · both")
			and float(prev.call("worst_air", 0)) >= 0.02 and float(prev.call("worst_air", 1)) >= 0.02
			and label.modulate.r < label.modulate.g,
		"the label says which grip a drag sets and which one she uses, and a grip that clears both bodies through the idle is green (%.1f, %.1f cm)"
			% [float(prev.call("worst_air", 0)) * 100.0, float(prev.call("worst_air", 1)) * 100.0])
	# Where the fixture's grips start: its numbers placed the rod's root, its grips place the hold.
	var idle_from: Vector3 = idle_grip.position
	var heave_from: Vector3 = fixture.find(&"fishing.heave").position
	grip_node.global_position += h0.basis * Vector3(0.0, 0.02, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var heave_grip: GripEntry = fixture.find(&"fishing.heave")
	_check(idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0)) and heave_grip.position == heave_from,
		"moving the Grip node 2 cm along her fingers moves the idle's grip 2 cm along them, and no other animation's (%s)" % idle_grip.position)
	_check(_hold_at(shown).is_equal_approx(grip_node.global_transform), "and the rod goes with it")

	# THE RUN: nobody has set it, so it borrows the idle's. The first drag SETS the run's grip,
	# starting where the rod was; from then on the run's alone moves.
	prev.set("animation", String(AnimationSet.RUN))
	for i: int in range(3):
		await get_tree().process_frame
	var before: Transform3D = _hold_at(shown)
	h0 = prev.call("hand_of", 0)
	_check(prev.call("editing") == null and grip_node.global_transform.is_equal_approx(before)
			and before.is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0)))
			and label.text.contains("not set") and label.text.contains("uses locomotion.idle · both"),
		"in the run, with no grip of its own, the rod is in the idle's grip, and the label says the run's is not set yet")
	grip_node.global_position += h0.basis * Vector3(0.0, 0.03, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var run_own: GripEntry = fixture.find(AnimationSet.RUN)
	_check(run_own != null and prev.call("editing") == run_own
			and run_own.position.is_equal_approx(idle_grip.position + Vector3(0.0, 0.03, 0.0))
			and GripEntry.same_turn(run_own.rotation_degrees, idle_grip.rotation_degrees)
			and idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0))
			and _hold_at(shown).is_equal_approx(grip_node.global_transform),
		"a drag in the run makes the run's own grip where the rod was, moved by the drag; the idle's stays put")
	_check(label.text.contains("uses locomotion.run · both") and not label.text.contains("not set"),
		"and the label says she uses it")
	var held_run: Transform3D = _hold_at(shown)
	prev.set("steady", true)
	for i: int in range(2):
		await get_tree().process_frame
	_check(run_own.steady and _hold_at(shown).basis.is_equal_approx(held_run.basis) and label.text.contains("steady"),
		"ticking Steady makes the run's grip steady without turning the rod (the wrist turns to hold it)")
	prev.call("clear_this_grip")
	for i: int in range(2):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(fixture.find(AnimationSet.RUN) == null and prev.call("editing") == null
			and _hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0))),
		"Clear This Grip takes it away: the run borrows the idle's again")
	# Steady on an animation nobody has set sets it too, where the rod already is.
	prev.set("animation", String(AnimationSet.WALK))
	for i: int in range(3):
		await get_tree().process_frame
	var held_walk: Transform3D = _hold_at(shown)
	prev.set("steady", true)
	for i: int in range(2):
		await get_tree().process_frame
	_check(fixture.find(AnimationSet.WALK) != null and fixture.find(AnimationSet.WALK).steady
			and _hold_at(shown).basis.is_equal_approx(held_walk.basis) and not idle_grip.steady,
		"ticking Steady in the walk, which borrowed, gives the walk a steady grip of its own where the rod was")
	prev.call("clear_this_grip")

	# ONE BODY: her grip alone. The man beside her keeps the shared one.
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "female")
	for i: int in range(3):
		await get_tree().process_frame
	var his_before: Transform3D = _hold_at(his)
	var hers_before: Transform3D = _hold_at(shown)
	_check(prev.call("holder") == 0 and prev.call("editing") == null and grip_node.global_transform.is_equal_approx(hers_before)
			and label.text.contains("SETTING locomotion.idle · female"),
		"choosing the female body puts the Grip node on her rod; her own idle grip is not set yet")
	grip_node.global_position += (prev.call("hand_of", 0) as Transform3D).basis * Vector3(0.04, 0.0, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	var her_grip: GripEntry = fixture.find(AnimationSet.IDLE, &"female")
	_check(her_grip != null and her_grip.position.is_equal_approx(idle_grip.position + Vector3(0.04, 0.0, 0.0))
			and _hold_at(his).is_equal_approx(his_before) and not _hold_at(shown).is_equal_approx(hers_before)
			and label.text.contains("uses locomotion.idle · female"),
		"a drag sets her body's own idle grip: the rod moves in HER hand only; his stays where it was")
	prev.set("animation", String(AnimationSet.WALK))
	for i: int in range(3):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(_hold_at(shown).is_equal_approx(h0 * her_grip.in_hand(h0, prev.call("body_of", 0)))
			and (prev.call("label_of", 1) as Label3D).text.contains("uses locomotion.idle · both"),
		"her walk borrows her own idle grip; his, the shared one")
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("body", "both")
	for i: int in range(3):
		await get_tree().process_frame
	_check(prev.call("holder") == 1 and grip_node.global_transform.is_equal_approx(_hold_at(his))
			and (prev.call("label_of", 1) as Label3D).text.contains("SETTING locomotion.idle · both"),
		"setting the shared grip again, the Grip node moves to him: her own grip would not move with it")
	prev.set("body", "male")
	for i: int in range(3):
		await get_tree().process_frame
	_check(prev.call("holder") == 1 and prev.call("editing") == null,
		"choosing the male body puts it on him, for a grip of his own")
	prev.set("body", "female")
	prev.call("clear_this_grip")
	for i: int in range(3):
		await get_tree().process_frame
	_check(fixture.find(AnimationSet.IDLE, &"female") == null and _hold_at(shown).is_equal_approx(hers_before),
		"Clear This Grip gives her the shared grip back")
	prev.set("body", "both")

	# ANY ANIMATION, AS IT IS SET. Luke: "if I'm in carry mode but change the fishing animation, it
	# doesn't take". The heave's grip is the heave's, and no other animation's.
	prev.set("animation", "fishing.heave")
	for i: int in range(3):
		await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(prev.call("editing") == heave_grip
			and grip_node.global_transform.is_equal_approx(h0 * heave_grip.in_hand(h0, prev.call("body_of", 0)))
			and _hold_at(shown).is_equal_approx(grip_node.global_transform),
		"picking the heave puts the rod and the Grip node in the heave's grip, which is what a drag then sets")
	grip_node.global_position += h0.basis * Vector3(0.0, 0.01, 0.0)
	for i: int in range(2):
		await get_tree().process_frame
	_check(heave_grip.position.is_equal_approx(heave_from + Vector3(0.0, 0.01, 0.0))
			and fixture.find(&"fishing.wait").position == heave_from
			and idle_grip.position.is_equal_approx(idle_from + Vector3(0.0, 0.02, 0.0)),
		"and a drag there moves the heave's grip alone: the waiting pose's and the idle's stay put")

	# LUKE'S CASE (DECISIONS #152): his carry grip clears the man's leg in the idle's first frame and
	# sits inside the woman's further in. The preview must say so.
	var leg: ItemGrip = _item_grip_from(GRIP_LEG)
	prev.set("grip", leg)
	prev.set("animation", String(AnimationSet.IDLE))
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var his_here: float = prev.call("air_here", 1)
	var hers_worst: float = prev.call("worst_air", 0)
	var his_worst: float = prev.call("worst_air", 1)
	var his_label: Label3D = prev.call("label_of", 1)
	print("   his grip: the man %.1f cm clear in the frame shown, %.1f cm at worst; the woman %.1f cm at worst"
		% [his_here * 100.0, his_worst * 100.0, hers_worst * 100.0])
	_check(his_here >= 0.02, "CONTROL: in the frame shown that grip clears the man (%.1f cm) — all the old preview measured"
		% (his_here * 100.0))
	_check(hers_worst < 0.0 and label.text.contains("INSIDE") and label.modulate.r > label.modulate.g,
		"and the preview shows it inside HER through the idle, in red (%.1f cm): what the game shows" % (hers_worst * 100.0))
	_check(his_worst < 0.02 and his_label.modulate.r > his_label.modulate.g,
		"and red on him too: clear in the frame shown, but %.1f cm at worst further into the clip" % (his_worst * 100.0))

	# Played, the clip goes round and the rods stay in the hands.
	prev.set("grip", fixture)
	prev.set("play", true)
	for i: int in range(2):
		await get_tree().process_frame
	var played_from: Transform3D = prev.call("hand_of", 0)
	await get_tree().create_timer(0.4).timeout
	await get_tree().process_frame
	h0 = prev.call("hand_of", 0)
	_check(not h0.is_equal_approx(played_from)
			and _hold_at(shown).is_equal_approx(h0 * idle_grip.in_hand(h0, prev.call("body_of", 0))),
		"ticking play plays the clip, the rod in the moving hand (the hand moved %.1f cm)"
			% (h0.origin.distance_to(played_from.origin) * 100.0))

	# --- FIT (DECISIONS #157) ---------------------------------------------------------------------
	# Luke: "can we not design our rod to fit in the hole that the hand animations use, and then take
	# pictures to get the angle right, with minimal user intervening other than checking the end
	# goal?" The hole, on the real rig: the idle closes the hand round one, the jump opens it.
	prev.set("play", false)
	var her_hole: Dictionary = prev.call("hole_of", 0, AnimationSet.IDLE, 0.0)
	var his_hole: Dictionary = prev.call("hole_of", 1, AnimationSet.IDLE, 0.0)
	var jump_hole: Dictionary = prev.call("hole_of", 0, AnimationSet.JUMP_LOOP, 0.5)
	var jump_open: Dictionary = prev.call("hole_of", 0, AnimationSet.JUMP_LOOP, 0.5, false)
	print("   the fist's hole: hers %.1f cm across the bones (%.1f cm off a circle), his %.1f cm; jumping, the clip curls her fingers %.0f deg, holding the rod %.0f deg"
		% [float(her_hole["radius"]) * 100.0, float(her_hole["error"]) * 100.0, float(his_hole["radius"]) * 100.0,
			float(jump_open["curl_deg"]), float(jump_hole["curl_deg"])])
	_check(bool(her_hole["fist"]) and bool(his_hole["fist"]) and float(her_hole["radius"]) > 0.015
			and float(her_hole["radius"]) < 0.03,
		"standing, both hands close round a hole the fit can find (hers %.1f cm in radius)" % (float(her_hole["radius"]) * 100.0))
	_check(not bool(jump_open["fist"]), "CONTROL: jumping, the clip opens her hand: no fist to fit to")
	# THE HAND STAYS SHUT ROUND IT (DECISIONS #160). Luke: the hand opens while jumping. Holding the
	# rod, the jump's fingers are shut to the idle's fist, so the idle's grip, which the jumps borrow,
	# sits in the same hole.
	_check(bool(jump_hole["fist"]) and (jump_hole["centre"] as Vector3).distance_to(her_hole["centre"] as Vector3) < 0.002,
		"holding the rod, her jumping hand is shut round it: the idle's fist (its hole %.1f mm from the idle's)"
			% ((jump_hole["centre"] as Vector3).distance_to(her_hole["centre"] as Vector3) * 1000.0))
	# CONTROL: Luke's carry grip (#152) is off the fist and inside her leg. FIT THIS GRIP puts the
	# handle in the fist, carried steady toward where the grip file says (tip up and forward), and
	# clear of both bodies through the whole idle — measured by the preview's own labels, not the fit.
	var fitme: ItemGrip = _item_grip_from(GRIP_LEG)
	fitme.carry_point = Vector3(0.0, 1.0, 1.0)
	fitme.fit_face = Vector3(0.0, 1.0, 0.0)
	prev.set("grip", fitme)
	prev.set("body", "both")
	prev.set("animation", String(AnimationSet.IDLE))
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var red_before: float = minf(float(prev.call("worst_air", 0)), float(prev.call("worst_air", 1)))
	_check(red_before < 0.0, "CONTROL: that grip is inside a body through the idle (%.1f cm)" % (red_before * 100.0))
	prev.call("fit_this_grip")
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	var idle_fit: GripEntry = fitme.find(AnimationSet.IDLE)
	var mid_fist: Vector3 = ((her_hole["centre"] as Vector3) + (his_hole["centre"] as Vector3)) * 0.5
	_check(idle_fit.position.distance_to(mid_fist) < 0.003,
		"Fit This Grip puts the handle in the fist: %.1f mm from the middle of both hands' holes"
			% (idle_fit.position.distance_to(mid_fist) * 1000.0))
	var carried_dir: Vector3 = (idle_fit.basis() * Vector3.UP).normalized()
	var asked_dir: Vector3 = GripFit.body_dir(fitme.carry_point).normalized()
	print("   fitted idle: %s; carried %.0f deg from tip-up-and-forward" % [prev.call("fit_said"), rad_to_deg(carried_dir.angle_to(asked_dir))])
	_check(idle_fit.steady and rad_to_deg(carried_dir.angle_to(asked_dir)) <= 30.5
			and float(prev.call("out_of_fist", 0)) <= fitme.fit_cone_deg + 1.0
			and float(prev.call("out_of_fist", 1)) <= fitme.fit_cone_deg + 1.0,
		"the idle only carries the rod: held steady near where the grip file asks, the wrist keeping the handle in both fists (%.0f, %.0f deg out)"
			% [float(prev.call("out_of_fist", 0)), float(prev.call("out_of_fist", 1))])
	_check(float(prev.call("worst_air", 0)) >= GripFit.ENOUGH_AIR and float(prev.call("worst_air", 1)) >= GripFit.ENOUGH_AIR
			and label.modulate.g > label.modulate.r,
		"and both labels go green: %.1f cm and %.1f cm clear at worst through the idle"
			% [float(prev.call("worst_air", 0)) * 100.0, float(prev.call("worst_air", 1)) * 100.0])
	# A RUN carries it the same way, steady: the swinging arm no longer sweeps it.
	prev.set("animation", String(AnimationSet.RUN))
	for i: int in range(2):
		await get_tree().process_frame
	var idle_kept: String = "%s|%s" % [idle_fit.position, idle_fit.rotation_degrees]
	prev.call("fit_this_grip")
	var run_fit: GripEntry = fitme.find(AnimationSet.RUN)
	_check(run_fit != null and run_fit.steady
			and rad_to_deg((run_fit.basis() * Vector3.UP).normalized().angle_to(asked_dir)) <= 30.5
			and "%s|%s" % [idle_fit.position, idle_fit.rotation_degrees] == idle_kept,
		"fitting the run carries the rod steady the same way; the idle's grip is left alone")
	# The HEAVE uses the rod: it was animated round one, so the rod goes along the fist, not steady.
	prev.set("animation", "fishing.heave")
	for i: int in range(2):
		await get_tree().process_frame
	prev.call("fit_this_grip")
	var heave_fit: GripEntry = fitme.find(&"fishing.heave")
	var heave_hole: Dictionary = prev.call("hole_of", 0, &"fishing.heave", 0.0)
	var heave_off: float = rad_to_deg((heave_fit.basis() * Vector3.UP).angle_to(heave_hole["axis"] as Vector3))
	_check(not heave_fit.steady and heave_off < 3.0,
		"fitting the heave, which uses the rod, holds it along the fist (%.1f deg off its line), in the hand's frame" % heave_off)
	# EVERY ANIMATION, and what could not be cleared said in words.
	prev.call("fit_every_animation")
	var said: String = prev.call("fit_said")
	var fitted: Array[StringName] = fitme.animations()
	var clips: int = (prev.get("definition") as EntityDefinition).animation_set.clips.size()
	print("   %s" % said)
	_check(fitted.size() == clips and said.begins_with("fitted %d animations" % clips)
			and (said.contains("all clear") or said.contains("the hand itself")),
		"Fit Every Animation gives every animation in the set a grip (%d), and names any it could not clear and why" % fitted.size())
	# THE WRIST (DECISIONS #158): the preview turns it as the game does. CONTROL: with the wrist
	# held as the clip has it, the steady idle's handle leaves the fist.
	prev.set("animation", String(AnimationSet.IDLE))
	for i: int in range(3):
		await get_tree().process_frame
	var in_fist: float = prev.call("out_of_fist", 0)
	fitme.wrist_turn_deg = 0.0
	for i: int in range(2):
		await get_tree().process_frame
	var stiff: float = prev.call("out_of_fist", 0)
	fitme.wrist_turn_deg = 60.0
	for i: int in range(2):
		await get_tree().process_frame
	_check(stiff > 20.0 and in_fist < 5.0 and (prev.call("label_of", 0) as Label3D).text.contains("in the fist"),
		"the wrist turns to keep the carried handle in her fist (%.0f deg out) where the clip's own wrist leaves it %.0f deg out"
			% [in_fist, stiff])
	# THE CARRY POINT is a node ON HER HAND (DECISIONS #159; Luke: "why is the carry point so far
	# out and not on the hand?"): turn it, and the grip file's carry_point follows its +Y (in the
	# body's terms), and the carried animation shown is fitted to it a moment later.
	var carry_node: Node3D = prev.get_node_or_null(^"CarryPoint") as Node3D
	_check(carry_node != null, "the preview has a Carry Point node")
	if carry_node != null:
		var body0: Basis = (prev.call("body_of", 0) as Basis).orthonormalized()
		var her_hold: Vector3 = _hold_at(prev.call("item_of", 0) as Node3D).origin
		_check(carry_node.global_position.distance_to(her_hold) < 0.005,
			"it sits on her hand, where her fist closes (%.1f mm off)" % (carry_node.global_position.distance_to(her_hold) * 1000.0))
		var idle_before: Basis = fitme.find(AnimationSet.IDLE).basis()
		var y_want: Vector3 = (body0 * GripFit.body_dir(Vector3(0.6, 1.0, 0.0))).normalized()
		var z_want: Vector3 = (body0 * GripFit.body_dir(fitme.fit_face))
		z_want = (z_want - y_want * z_want.dot(y_want)).normalized()
		carry_node.global_basis = Basis(y_want.cross(z_want).normalized(), y_want, z_want)
		carry_node.global_position += Vector3(0.5, 0.0, 0.0)
		for i: int in range(3):
			await get_tree().process_frame
		_check(fitme.carry_point.normalized().distance_to(Vector3(0.6, 1.0, 0.0).normalized()) < 0.01
				and carry_node.global_position.distance_to(_hold_at(prev.call("item_of", 0) as Node3D).origin) < 0.05,
			"turning it up and to her right sets carry_point there (%s); moving it puts it back on her hand" % fitme.carry_point)
		# The preview fits it a moment (REFIT_DELAY_MSEC) after the turn: waited for, not timed (a
		# fixed 0.6 s missed it on a slow frame), up to 3 s.
		var refit_until: int = Time.get_ticks_msec() + 3000
		while fitme.find(AnimationSet.IDLE).basis().is_equal_approx(idle_before) and Time.get_ticks_msec() < refit_until:
			await get_tree().process_frame
		# Fitted toward the new way: nearer it than the old (tip up and forward), and within the fit's
		# turns round it (to keep the handle in the fist and clear). The reel side is left as it was.
		var refit_dir: Vector3 = (fitme.find(AnimationSet.IDLE).basis() * Vector3.UP).normalized()
		var to_new: float = rad_to_deg(refit_dir.angle_to(GripFit.body_dir(fitme.carry_point).normalized()))
		var to_old: float = rad_to_deg(refit_dir.angle_to(GripFit.body_dir(Vector3(0.0, 1.0, 1.0)).normalized()))
		_check(to_new < to_old and to_new <= 30.5,
			"and the idle is fitted again toward it (%.0f deg off it, %.0f deg off the old way)" % [to_new, to_old])
	# PUT AWAY (DECISIONS #158): Fit Stow slings it where the draw's hand reaches, hanging the way
	# the grip file asks, and sets the draw's and the stow's grips to meet it there: no jump.
	fitme.stow_point = Vector3(-0.6, -0.8, 0.0)
	fitme.stow_face = Vector3(0.0, 0.0, 1.0)
	prev.call("fit_stow_now")
	for i: int in range(2):
		await get_tree().process_frame
	_check(fitme.stows() and fitme.draw_swap_at > 0.0 and fitme.stow_swap_at > 0.0
			and String(prev.call("fit_said")).begins_with("fit stow"),
		"Fit Stow gives the rod a place on her back, and when the draw takes it (%d%%) and the stow lets go (%d%%)"
			% [roundi(fitme.draw_swap_at * 100.0), roundi(fitme.stow_swap_at * 100.0)])
	var jumps: Array[float] = []
	for pair: Array in [[ItemGrip.DRAW, fitme.draw_swap_at], [ItemGrip.STOW, fitme.stow_swap_at]]:
		prev.set("animation", String(pair[0]))
		prev.set("pose_at", float(pair[1]))
		for i: int in range(3):
			await get_tree().process_frame
		var in_hand_hold: Transform3D = _hold_at(prev.call("item_of", 0) as Node3D)
		prev.set("show_stowed", true)
		for i: int in range(2):
			await get_tree().process_frame
		var slung_hold: Transform3D = _hold_at(prev.call("item_of", 0) as Node3D)
		prev.set("show_stowed", false)
		jumps.append(in_hand_hold.origin.distance_to(slung_hold.origin))
		jumps.append(rad_to_deg(Quaternion(in_hand_hold.basis.orthonormalized()).angle_to(Quaternion(slung_hold.basis.orthonormalized()))))
	_check(jumps[0] < 0.01 and jumps[1] < 5.0 and jumps[2] < 0.01 and jumps[3] < 5.0,
		"at those moments the rod in her hand is where it is slung: the draw takes it %.1f cm and %.0f deg off, the stow lets it go %.1f cm and %.0f deg off"
			% [jumps[0] * 100.0, jumps[1], jumps[2] * 100.0, jumps[3]])
	prev.set("animation", String(AnimationSet.IDLE))
	prev.set("pose_at", 0.0)
	prev.set("show_stowed", true)
	for i: int in range(3):
		await get_tree().process_frame
	var slung_dir: Vector3 = ((prev.call("body_of", 0) as Basis).orthonormalized().inverse()
		* _hold_at(prev.call("item_of", 0) as Node3D).basis.y).normalized()
	_check(GripFit.body_dir(slung_dir).distance_to(Vector3(-0.6, -0.8, 0.0).normalized()) < 0.05
			and (prev.call("label_of", 0) as Label3D).text.contains("put away"),
		"Show Stowed hangs it down across her back to the left, as the grip file asks (%s)" % GripFit.body_dir(slung_dir))
	prev.set("show_stowed", false)
	# THE OTHER HAND (DECISIONS #172): the grip file says the rod is held in both hands waiting, and
	# the preview puts her left hand on the reel there as the game does; standing, it is her own.
	prev.set("grip", file_grip.duplicate(true))
	prev.set("animation", "fishing.wait")
	for i: int in range(4):
		await get_tree().process_frame
	var skel0: Skeleton3D = prev.get("_skels")[0] as Skeleton3D
	var off_ik: TwoBoneIK3D = skel0.get_node_or_null(OffHand.IK_NAME) as TwoBoneIK3D
	var off_target: Node3D = skel0.get_node_or_null(OffHand.TARGET_NAME) as Node3D
	var off_point: Node3D = OffHand.point_of(prev.call("item_of", 0) as Node3D, file_grip)
	_check(off_ik != null and off_ik.active and is_equal_approx(off_ik.influence, 1.0) and off_point != null,
		"waiting, the preview holds the reel with her left hand (the grip file's off hand)")
	if off_target != null and off_point != null:
		var want_wrist: Vector3 = OffHand.wrist_target(skel0, file_grip, off_point.global_position,
			(prev.call("item_of", 0) as Node3D).global_basis)
		_check(off_target.global_position.distance_to(want_wrist) < 0.001,
			"its wrist goes where the game puts it (OffHand, the same code)")
	prev.set("animation", String(AnimationSet.IDLE))
	for i: int in range(3):
		await get_tree().process_frame
	_check(off_ik == null or not off_ik.active, "standing, the hand is the clip's own")
	_check(_grip_text(file_grip) == file_before, "and none of it touched the grip file")
	prev.queue_free()
	await get_tree().process_frame
const GRIP_LEG: Array[Vector3] = [Vector3(-0.03, 0.11, -0.04), Vector3(95.0, 0.0, 0.0),
	Vector3(-0.025, 0.09, -0.09), Vector3(88.13, -90.567, -91.564)]
## The animations a rod is FISHED with (the cast, the waiting pose, the heave, a snap's), which
## hold it the fishing way; every other animation borrows the idle's, the carrying way.
const FISHED_WITH: Array[StringName] = [&"interact", &"fishing.wait", &"fishing.heave", &"fishing.fail"]


## A rod's grip from those four numbers: the idle's (carrying), and the fishing animations'. The
## numbers place the rod's ROOT, as they were tuned; a grip places its HOLD (DECISIONS #158).
func _item_grip_from(v: Array[Vector3]) -> ItemGrip:
	var g := ItemGrip.new()
	g.entries.append(_root_entry(AnimationSet.IDLE, v[2], v[3], false))
	for a: StringName in FISHED_WITH:
		g.entries.append(_root_entry(a, v[0], v[1], false))
	return g


## Where a held item's HOLD is in the world (its `Hold` node).
static func _hold_at(item: Node3D) -> Transform3D:
	return item.global_transform * GripFit.hold_of(item)


## Every grip in a file, as text: to show a test left it alone.
static func _grip_text(g: ItemGrip) -> String:
	var parts: PackedStringArray = []
	for e: GripEntry in g.entries:
		parts.append("%s|%s|%s|%s|%s" % [e.animation, e.body, e.position, e.rotation_degrees, e.steady])
	return ";".join(parts)
