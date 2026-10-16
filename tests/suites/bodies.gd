extends "res://tests/suite_base.gd"
## BODIES THE REFEREE MOVES (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246), with no server:
##   - a `BodyDef`: what it bakes, its shapes, its problems; the foundation's ball is content
##   - a `FlyingBody` in real physics: it falls, bounces (a hit, fast), rolls and comes to rest (and stops),
##     its frames and what it remembers; its def's forces push it; `shift` moves it and its memory;
##     `place` puts it somewhere, at rest or moving
##   - the referee's `BodyReferee`: one write a tick for a body in flight with its frames, one more when it
##     comes to rest and then none; a hit on a person's stand-in reported with whom; a server teleport
##     adopted, its own echo not
##   - the thrower's correction (`BodyComponent`): a gap a share at a time, a big one at once
##   - `BodyLaunch`: a throw's own flight, taken once; forgotten; numbers that do not repeat
##   - the turn between two rows (`BodyComponent._turn_at`), the movement component's render seq

const BALL_ID: int = 1


class FakeMoveRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var pos: Vector3
	var vel: Vector3
	var last_processed_seq: int
	var teleport_flag: bool = false
	func _init(eid: int, p: Vector3, v: Vector3, seq: int, tp: bool = false) -> void:
		entity_id = eid
		pos = p
		vel = v
		last_processed_seq = seq
		teleport_flag = tp


func run() -> void:
	_run_def()
	# Real time: `Engine.time_scale` would make each physics frame longer, not add frames.
	await _run_flight()
	await _run_forces_and_moves()
	await _run_referee()
	_run_correction()
	_run_launch()
	_run_turns()
	await _run_bench()


func _floor() -> StaticBody3D:
	var f := StaticBody3D.new()
	f.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	f.add_child(shape)
	f.collision_layer = 1
	get_tree().root.add_child(f)
	return f


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _run_def() -> void:
	print("== bodies: the content ==")
	var ball: BodyDef = BodyDef.by_id(BALL_ID)
	_check(ball != null and ball.display_name == "Ball" and HoldDef.kinds_of(ball.launched_by) == [0], "the foundation's ball is content, thrown by players (kind 0)")
	var bake: Dictionary = ball.to_bake()
	_check(bake.keys() == ["id", "name", "launchers", "max_speed_mps", "max_spin_rps", "reach_m", "max_per_owner", "lifetime_s"],
		"it bakes what the server checks, no more (%s)" % [bake.keys()])
	var d := BodyDef.new()
	d.display_name = "Thing"
	d.shape = BodyDef.Shape.BOX
	d.box_size = Vector3(0.2, 0.0, 0.2)
	_check(d.validate().any(func(m: String) -> bool: return m.contains("box with no size")), "a box with no size says so")
	d.box_size = Vector3.ONE
	d.launched_by = [load("res://foundation/content/character/player.tres") as EntityDefinition]
	d.max_speed_mps = 0.0
	_check(d.validate().any(func(m: String) -> bool: return m.contains("no speed")), "thrown by players at no speed says so")
	d.shape = BodyDef.Shape.CYLINDER
	d.radius_m = 0.1
	d.height_m = 0.02
	_check(d.make_shape() is CylinderShape3D and is_equal_approx((d.make_shape() as CylinderShape3D).radius, 0.1), "a disc's shape: a short cylinder")
	var look: Node3D = d.make_visual()
	_check(look is MeshInstance3D, "with no model: a plain shape of its size")
	look.free()
	var body_kind: EntityDefinition = load("res://foundation/content/character/body.tres") as EntityDefinition
	_check(body_kind != null and body_kind.kind == 3 and body_kind.scene != null, "every body is drawn by kind 3's definition")
	var defs: Array[EntityDefinition] = []
	EntityDefinition.add_foundation_kinds(defs)
	_check(defs.size() == 1 and defs[0].kind == 3, "Boot registers it in every game")
	EntityDefinition.add_foundation_kinds(defs)
	_check(defs.size() == 1, "once")


func _run_flight() -> void:
	print("== bodies: a ball in flight, real physics ==")
	var floor_node: StaticBody3D = _floor()
	var ball: BodyDef = BodyDef.by_id(BALL_ID)
	var b: FlyingBody = FlyingBody.make(ball)
	get_tree().root.add_child(b)
	var hits: Array[float] = []
	b.hit.connect(func(_o: Object, _p: Vector3, _n: Vector3, speed: float) -> void: hits.append(speed))
	var rested: Array[bool] = [false]
	b.came_to_rest.connect(func() -> void: rested[0] = true)
	b.launch(Vector3(0, 2.0, 0), Vector3(3, 0, 0), Vector3.ZERO, Vector3.ZERO)
	_check(b.frames == 0 and b.state_at(0)[0] == Vector3(0, 2.0, 0), "launched: frame 0 is where it left")
	await _frames(20)
	_check(b.frames >= 18 and b.global_position.y < 2.0 and b.global_position.x > 0.5, "it flies: forward and falling (%s at frame %d)" % [b.global_position, b.frames])
	var at10: Array = b.state_at(10)
	_check(not at10.is_empty() and (at10[0] as Vector3).x > 0.0, "it remembers where it was, frame by frame")
	var waited: int = 0
	while not rested[0] and waited < 900:
		await get_tree().physics_frame
		waited += 1
	_check(not hits.is_empty() and hits[0] > 3.0, "it hit the floor fast (%.1f m/s), once on landing" % (hits[0] if not hits.is_empty() else 0.0))
	_check(rested[0] and b.at_rest, "it rolled and came to rest (after %d frames)" % waited)
	await _frames(3)
	var x: float = b.global_position.x
	_check(b.freeze and b.global_position.y < 0.2 and b.global_position.y > 0.0, "at rest: stopped, on the floor (y %.3f)" % b.global_position.y)
	await _frames(10)
	_check(is_equal_approx(b.global_position.x, x), "and it stays put")
	b.queue_free()
	floor_node.queue_free()
	await get_tree().physics_frame


func _run_forces_and_moves() -> void:
	print("== bodies: forces, shift, place ==")
	var d: BodyDef = (BodyDef.by_id(BALL_ID) as BodyDef).duplicate() as BodyDef
	d.gravity_scale = 0.0
	d.linear_damp = 0.0
	d.mass_kg = 0.5
	var f: BodyForces = (load("res://tests/fixtures/push_forces.gd") as Script).new() as BodyForces
	d.forces = f   # 2 N along x: 4 m/s/s on 0.5 kg
	var b: FlyingBody = FlyingBody.make(d)
	get_tree().root.add_child(b)
	b.launch(Vector3(0, 50, 0), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	await _frames(30)
	var expect: float = 4.0 * float(b.frames) / 60.0
	_check(absf(b.linear_velocity.x - expect) < 0.15, "its forces push it: %.2f m/s after %d frames (4 m/s/s: %.2f)" % [b.linear_velocity.x, b.frames, expect])
	var before: Vector3 = b.global_position
	var mem: Vector3 = b.state_at(b.frames)[0]
	b.shift(Vector3(0, 0, 1.0), Vector3.ZERO)
	_check((b.state_at(b.frames - 1)[0] as Vector3).z > 0.99 or (b.state_at(b.frames)[0] as Vector3).z - mem.z > 0.99,
		"shift moves what it remembers too (so the next row is not counted twice)")
	await _frames(2)
	_check(b.global_position.z - before.z > 0.99, "and the body itself, at its next frame")
	b.place(Vector3(5, 50, 5), Vector3.ZERO, Vector3(0, PI / 2, 0), Vector3.ZERO, true)
	await _frames(3)
	_check(b.global_position.distance_to(Vector3(5, 50, 5)) < 0.01 and b.at_rest and b.freeze, "placed at rest: there, stopped")
	_check(FlyingBody.rotvec_of(b.global_basis.get_rotation_quaternion()).distance_to(Vector3(0, PI / 2, 0)) < 0.01, "turned as it was put")
	_check(b.rot_vector().distance_to(Vector3(0, PI / 2, 0)) < 0.01, "and says its turn as a rotation vector")
	b.place(Vector3(5, 50, 5), Vector3(1, 0, 0), Vector3.ZERO, Vector3.ZERO, false)
	await _frames(5)
	_check(not b.at_rest and not b.freeze and b.global_position.x > 5.0, "placed moving: it goes again")
	b.queue_free()
	await get_tree().physics_frame


func _run_referee() -> void:
	print("== bodies: the referee flies them ==")
	var floor_node: StaticBody3D = _floor()
	var ref := BodyReferee.new()
	ref.send = false
	ref.world_id = 0
	get_tree().root.add_child(ref)
	ref.set_physics_process(false)   # its own 20 Hz flush would take what the checks flush by hand
	var b: FlyingBody = ref.start_body(901, BALL_ID, Vector3(0, 1.0, 0), Vector3(6, 0, 0), Vector3.ZERO, Vector3.ZERO)
	_check(b != null and ref.body_count() == 1 and ref.body(901) == b, "a body's rows: it flies it")
	_check(ref.start_body(902, 9999, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO) == null, "a body this game has no def for: not flown (said)")
	# A person 2 m ahead, at the height it flies at.
	ref.set_entity(77, 0, true, true)
	ref._place_proxy(77, Vector3(2.0, 0.0, 0))
	_check(ref.proxy(77) != null, "a person: a stand-in where their row puts them")
	ref.set_entity(78, 0, true, false)
	ref._place_proxy(78, Vector3(9, 0, 9))
	_check(ref.proxy(78) == null, "an offline player: none")
	ref.set_entity(79, 120)
	ref._place_proxy(79, Vector3(9, 0, 9))
	_check(ref.proxy(79) == null, "a thing that is not a person (a genre's prop): none")
	await _frames(2)
	var first: Dictionary = ref.flush()
	var w: Array = first["writes"]
	_check(w.size() == 1 and int(w[0]["entity_id"]) == 901 and int(w[0]["frames"]) >= 1 and not bool(w[0]["at_rest"]),
		"a tick: one write, in flight, with its frames since launch")
	var contacts: Array = []
	var on_person: Array = []
	var waited: int = 0
	while on_person.is_empty() and waited < 180:
		await get_tree().physics_frame
		waited += 1
		contacts.append_array(ref.flush()["contacts"])
		on_person = contacts.filter(func(c: Dictionary) -> bool: return int(c["other_id"]) == 77)
	_check(not on_person.is_empty() and float(on_person[0]["speed"]) > 3.0,
		"it hit the person: reported with whom, how fast (%s)" % [contacts])
	waited = 0
	while not b.at_rest and waited < 900:
		await get_tree().physics_frame
		waited += 1
	await _frames(2)
	var after: Dictionary = ref.flush()
	var resting: Array = after["writes"]
	_check((after["contacts"] as Array).any(func(c: Dictionary) -> bool: return int(c["other_id"]) == 0), "and the ground after: the level, 0")
	_check(resting.size() == 1 and bool(resting[0]["at_rest"]) and resting[0]["vel"] == Vector3.ZERO, "at rest: one write saying so")
	await _frames(4)
	_check((ref.flush()["writes"] as Array).is_empty(), "and then none: a body at rest costs nothing")
	ref._body_row(901, FakeMoveRow.new(901, b.global_position, Vector3.ZERO, b.frames, true))
	_check(b.at_rest, "its own write echoed back (where it already is): nothing")
	ref._body_row(901, FakeMoveRow.new(901, Vector3(-3, 2, 0), Vector3.ZERO, b.frames, true))
	await _frames(3)
	_check(b.global_position.distance_to(Vector3(-3, 2, 0)) < 0.2 and not b.at_rest, "the server moved it: there, falling again")
	var moved: Array = ref.flush()["writes"]
	_check(moved.size() == 1 and not bool(moved[0]["at_rest"]), "and written again")
	ref._drop_body(901)
	_check(ref.body_count() == 0, "its rows gone: it goes")
	ref.queue_free()
	floor_node.queue_free()
	await get_tree().physics_frame


func _run_correction() -> void:
	print("== bodies: the thrower's flight, kept near the referee's ==")
	var b: FlyingBody = FlyingBody.make(BodyDef.by_id(BALL_ID))
	# Not in the tree: only its memory is read and shifted here.
	b._history[30] = [Vector3(10, 2, 0), Vector3(10, 0, 0)]
	b._history[31] = [Vector3(10.2, 2, 0), Vector3(10, 0, 0)]
	var c := BodyComponent.new()
	c._flight = b
	var share: float = HotRules.number(&"foundation.body_correct_share")
	c._compare(FakeMoveRow.new(1, Vector3(10.5, 2, 0), Vector3(10, 0, 0), 30))
	_check(c.corrections == 1 and is_equal_approx(c.last_gap, 0.5) and c.snaps == 0, "a row half a metre off: compared at its own frame (gap %.2f)" % c.last_gap)
	_check(((b.state_at(30)[0] as Vector3).x - 10.0) > 0.5 * share - 0.001 and ((b.state_at(30)[0] as Vector3).x - 10.0) < 0.5 * share + 0.001,
		"moved a share of the way (%.0f %%), not all of it" % (share * 100.0))
	c._compare(FakeMoveRow.new(1, Vector3(20, 2, 0), Vector3(0, 0, 0), 31))
	_check(c.snaps == 1 and (b.state_at(31)[0] as Vector3).distance_to(Vector3(20, 2, 0)) < 0.001, "a row past the snap distance: put there at once")
	c._compare(FakeMoveRow.new(1, Vector3(0, 0, 0), Vector3.ZERO, 5))
	_check(c.corrections == 2, "a row for a frame it no longer remembers: passed over")
	c._flight = null
	c.free()
	b.free()


func _run_launch() -> void:
	print("== bodies: a throw's own flight (BodyLaunch) ==")
	var parent := Node3D.new()
	get_tree().root.add_child(parent)
	var ball: BodyDef = BodyDef.by_id(BALL_ID)
	var id1: int = BodyLaunch.next_id()
	var id2: int = BodyLaunch.next_id()
	_check(id1 != id2 and id1 > 0 and id2 > 0, "each throw its own number")
	var fb: FlyingBody = BodyLaunch.fly(parent, ball, id1, Vector3(0, 5, 0), Vector3(1, 0, 0), Vector3.ZERO, Vector3.ZERO)
	_check(fb != null and fb.get_parent() == parent and BodyLaunch.waiting() >= 1 and fb.get_node_or_null(^"Visual") != null,
		"flying at once, under the world, drawn")
	_check(BodyLaunch.take(id1) == fb and BodyLaunch.take(id1) == null, "taken once, by its body")
	BodyLaunch.fly(parent, ball, id2, Vector3(0, 5, 0), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	BodyLaunch.forget(id2)
	_check(BodyLaunch.take(id2) == null, "a refused throw: forgotten")
	fb.queue_free()
	parent.queue_free()


func _run_turns() -> void:
	print("== bodies: its turn between rows ==")
	var c := BodyComponent.new()
	c._turns[10] = Quaternion.IDENTITY
	c._turns[13] = Quaternion(Vector3.UP, PI / 2)
	_check(c._turn_at(11.5).is_equal_approx(Quaternion(Vector3.UP, PI / 4)), "halfway between two rows: halfway turned")
	_check(c._turn_at(99.0).is_equal_approx(Quaternion(Vector3.UP, PI / 2)), "past the newest: the newest")
	_check(c._turn_at(-1.0).is_equal_approx(Quaternion(Vector3.UP, PI / 2)), "not drawn yet: the newest")
	c.free()
	var m := SpaceTimeMovementComponent.new()
	_check(m.get_render_seq() == -1.0, "a movement component not yet drawn: no render seq")
	m.free()


func _run_bench() -> void:
	print("== bodies: the bench ==")
	_check(ContentLibrary.workbench_for(&"body") == "res://tools/workbench/body_workbench.tscn", "a body's bench is found by its name")
	var bench: BodyWorkbench = (load("res://tools/workbench/body_workbench.tscn") as PackedScene).instantiate() as BodyWorkbench
	get_tree().root.add_child(bench)
	await get_tree().process_frame
	var ball: BodyDef = BodyDef.by_id(BALL_ID)
	bench.item = ball
	bench.load_item(ball)
	_check(bench.get_node_or_null(^"Body") != null, "the ball on the bench, at its size")
	var said: String = bench.run_test(&"arc")
	var r: float = float(bench.last_measure.get("range_m", 0.0))
	_check(r > 35.0 and r < 60.0, "its hardest throw goes %.1f m (25 m/s, 30 degrees, a little drag): %s" % [r, said])
	_check(bench.run_test(&"size").begins_with("22 cm across"), "its size: 22 cm across")
	_check(bench.run_test(&"limits").contains("thrown by kinds [0]"), "its limits: thrown by players")
	bench.run_test(&"bounce")
	_check(is_equal_approx(float(bench.last_measure["back_m"]), 2.0 * ball.bounce * ball.bounce), "its bounce from 2 m")
	bench.queue_free()
	await get_tree().process_frame
