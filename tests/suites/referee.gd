extends "res://tests/suite_base.gd"
## The `referee` suite (tests/test_runner.gd runs it; `-- --only=referee` runs it alone).
## THE REFEREE (DECISIONS #226, FOUNDATION_SYSTEMS milestone 5): where an entity was (its history,
## rewound); what a sweep hits (reach, width, height, the first in its path, never through a wall);
## the milestone's proof (a pounce whose user saw the hen before she was through a gap hits her, one
## that saw her after misses, and the rewind is what decides); who may be hit; the rows it judges by;
## and the client's part (how far behind it sees, the key, the launcher's rules). The module's side:
## tests/integration_test.sh; a real referee against a real server: tests/sidecar_test.sh.

const BASE: int = 10_000_000


func run() -> void:
	_run_history()
	_run_sweep()
	await _run_walls_and_rewind()
	await _run_walls_put_up()
	_run_who()
	_run_two_sides()
	_run_rows()
	_run_feed()
	_run_regions()
	await _run_client_side()
	await _run_stale()


## A REFEREE STOPS WHEN THE PROJECT IS NEWER THAN IT (DECISIONS #272): a folder's newest code or content
## file is its stamp; a file written after the sidecar started makes it stale. (A referee from yesterday
## ran yesterday's code after a publish: the skeletons never attacked.)
func _run_stale() -> void:
	var dir: String = "user://stamp_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir.path_join("deep")))
	for f: String in ["a.gd", "deep/b.tres", "c.png"]:
		var fa: FileAccess = FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_string("x")
		fa.close()
	var before: int = ProjectStamp._newest_in(dir)
	_check(before > 0, "a folder's stamp: its newest code or content file (%d)" % before)
	_check(ProjectStamp.now() >= before - 86400 * 365 and ProjectStamp.now() > 0, "the project has one (its scripts, its bake, its bindings)")
	_check(not ProjectStamp.newer_than(ProjectStamp.now()), "a sidecar just started: not stale")
	_check(ProjectStamp.newer_than(ProjectStamp.now() - 5), "the project newer than it: stale, so it stops and a fresh one starts")
	# The referee looks off its main thread (template 1.6.2: 0.4 s a look on a big project, every 10 s).
	var asked_ms: int = Time.get_ticks_msec()
	var task: int = ProjectStamp.look_async()
	asked_ms = Time.get_ticks_msec() - asked_ms
	var found: int = ProjectStamp.finish_look(task)
	_check(task >= 0 and found == ProjectStamp.now() and asked_ms < 50,
		"a referee's look at the project runs on a worker thread and finds the same stamp (%d; starting it took the caller %d ms)"
			% [found, asked_ms])
	# A picture is not code: writing one does not make a sidecar stale; a script does.
	await get_tree().create_timer(1.1).timeout
	var png: FileAccess = FileAccess.open(dir.path_join("c.png"), FileAccess.WRITE)
	png.store_string("y")
	png.close()
	_check(ProjectStamp._newest_in(dir) == before, "a picture written later: the stamp stays")
	var gd: FileAccess = FileAccess.open(dir.path_join("deep/b.tres"), FileAccess.WRITE)
	gd.store_string("y")
	gd.close()
	_check(ProjectStamp._newest_in(dir) > before, "a resource deep in it written later: the stamp moves on")
	for f: String in ["a.gd", "deep/b.tres", "c.png"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("deep")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


class _MoveRow extends RefCounted:
	var entity_id: int = 0
	var world_id: int = 0
	var pos: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var server_ts: int = 0
	func _init(eid: int, p: Vector3, ts: int, w: int = 0) -> void:
		entity_id = eid
		pos = p
		server_ts = ts
		world_id = w


class _ReqRow extends RefCounted:
	var id: int = 0
	var world_id: int = 0
	var actor_id: int = 0
	var ability_id: int = 0
	var target_id: int = 0
	var rewind_ms: int = 0
	var due_at: int = 0
	func _init(rid: int, actor: int, due: int, w: int = 0) -> void:
		id = rid
		actor_id = actor
		due_at = due
		world_id = w


class _AbilityRow extends RefCounted:
	var ability_id: int = 0
	var cooldown_ms: int = 800
	var range: float = 0.0
	var wind_up_ms: int = 450
	var damage: float = 0.0
	var data: String = "{}"
	func _init(id: int) -> void:
		ability_id = id


class _EntityRow extends RefCounted:
	var entity_id: int = 0
	var world_id: int = 0
	var kind: int = 0
	var owner: PackedByteArray = PackedByteArray()
	func _init(eid: int, k: int) -> void:
		entity_id = eid
		kind = k


func _run_history() -> void:
	print("== referee: where an entity was ==")
	var h := TransformHistory.new()
	_check(h.at(5).is_empty(), "nothing known: nothing said")
	h.push(1000, Vector3.ZERO, 0.0)
	h.push(2000, Vector3(1, 0, 0), 1.0)
	_check((h.at(1500)["pos"] as Vector3).is_equal_approx(Vector3(0.5, 0, 0)) and is_equal_approx(float(h.at(1500)["yaw"]), 0.5),
		"between two rows: the line between them (%s)" % str(h.at(1500)["pos"]))
	_check((h.at(500)["pos"] as Vector3) == Vector3.ZERO and (h.at(9000)["pos"] as Vector3) == Vector3(1, 0, 0),
		"before the first, the first; after the last, the last: never a guess past what the server said")
	h.push(1200, Vector3(0, 0, 7), 0.0)
	_check((h.at(1200)["pos"] as Vector3) == Vector3(0, 0, 7) and h.size() == 3, "a late row goes in its place")
	h.push(1200, Vector3(0, 0, 8), 0.0)
	_check((h.at(1200)["pos"] as Vector3) == Vector3(0, 0, 8) and h.size() == 3, "one at the same time replaces it")
	var long := TransformHistory.new()
	long.keep_usec = 1_000_000
	for i: int in 100:
		long.push(i * 50_000, Vector3(i, 0, 0), 0.0)
	_check(long.size() <= 22 and long.size() >= 20 and long.newest_usec() == 99 * 50_000,
		"it keeps a second of rows, not all of them (%d)" % long.size())


func _run_sweep() -> void:
	print("== referee: what a sweep hits ==")
	var at := func(id: int, p: Vector3) -> Dictionary: return {"id": id, "pos": p, "radius": 0.4, "height": 1.8, "center_y": 0.9}
	var j := func(targets: Array, yaw: float = 0.0) -> Dictionary:
		return LungeJudge.judge(null, Vector3.ZERO, yaw, 1.4, 0.35, 0.6, targets)
	_check(int(j.call([at.call(7, Vector3(0, 0, -1.0))])["hit_id"]) == 7, "one a metre ahead: hit")
	_check(int(j.call([at.call(7, Vector3(0, 0, -2.3))])["hit_id"]) == 0, "2.3 m ahead, past the reach and both widths (2.15 m): missed")
	_check(int(j.call([at.call(7, Vector3(0, 0, -2.0))])["hit_id"]) == 7, "2 m ahead: the ball's edge reaches its body")
	_check(int(j.call([at.call(7, Vector3(0.9, 0, -1.0))])["hit_id"]) == 0, "0.9 m to the side of the path: missed")
	_check(int(j.call([at.call(7, Vector3(0, 0, 1.0))])["hit_id"]) == 0, "behind: missed")
	_check(int(j.call([at.call(7, Vector3(0, 0, -1.8)), at.call(8, Vector3(0.1, 0, -0.9))])["hit_id"]) == 8,
		"two in its path: the nearer")
	_check(int(j.call([at.call(7, Vector3(-1.0, 0, 0)), at.call(8, Vector3(0, 0, -1.0))], PI / 2.0)["hit_id"]) == 7,
		"it sweeps the way its user faces (a quarter turn: -X)")
	_check(int(j.call([at.call(7, Vector3(0, 2.5, -1.0))])["hit_id"]) == 0, "one standing up on a bale above it: missed")


## A fence across the path (z = -1, 0.2 m thick, 1.5 m high) with a gap 0.5 m wide at x = 0: a hen
## fits it, the ball (0.7 m across) does not.
func _fence(root: Node3D, gap: bool) -> void:
	var boards: Array = [[-3.0, -0.25], [0.25, 3.0]] if gap else [[-3.0, 3.0]]
	for b: Array in boards:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(b[1]) - float(b[0]), 1.5, 0.2)
		shape.shape = box
		body.add_child(shape)
		root.add_child(body)
		body.global_position = Vector3((float(b[0]) + float(b[1])) * 0.5, 0.75, -1.0)


func _run_walls_and_rewind() -> void:
	print("== referee: walls, and the rewind (the milestone's proof) ==")
	var root := Node3D.new()
	add_child(root)
	_fence(root, true)
	var ref := ActionReferee.new()
	ref.send = false
	root.add_child(ref)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = ref.get_world_3d().direct_space_state
	var hen := func(z: float, x: float = 0.0) -> Array: return [{"id": 2, "pos": Vector3(x, 0, z), "radius": 0.4, "height": 1.8, "center_y": 0.9}]
	var through: Dictionary = LungeJudge.judge(space, Vector3.ZERO, 0.0, 1.4, 0.35, 0.6, hen.call(-1.0))
	_check(float(through["reach"]) < 0.9 and float(through["reach"]) > 0.5,
		"the ball stops at the gap's posts, met head on: it does not fit (%.2f m of 1.4)" % float(through["reach"]))
	_check(int(through["hit_id"]) == 2, "a hen IN the gap, within reach of where it stopped: hit")
	_check(int(LungeJudge.judge(space, Vector3.ZERO, 0.0, 1.4, 0.35, 0.6, hen.call(-1.6))["hit_id"]) == 0,
		"a hen through it: missed, though the open-ground reach is 2.15 m")
	_check(int(LungeJudge.judge(null, Vector3.ZERO, 0.0, 1.4, 0.35, 0.6, hen.call(-1.6))["hit_id"]) == 2,
		"(with no fence the same hen is hit: the fence is what saved her)")
	var behind: Dictionary = LungeJudge.judge(space, Vector3(1.5, 0, 0), 0.0, 1.4, 0.35, 0.6, hen.call(-1.25, 1.5))
	_check(int(behind["hit_id"]) == 0,
		"a hen pressed to the far side of a solid board, within a ball's reach of where it stopped: not hit through it")

	# A WALL IT GRAZES IT SLIDES ALONG (Luke, 0.40.1): beside a bale and angled a little into it, the
	# ball caught its corner and stopped 0.1 m out; a hen just ahead was missed.
	var bale := StaticBody3D.new()
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(1.0, 1.0, 2.0)
	bshape.shape = bbox
	bale.add_child(bshape)
	root.add_child(bale)
	bale.global_position = Vector3(-6.0, 0.5, -0.5)   # its face at x = -5.5, the wolf at x = -5.1
	await get_tree().physics_frame
	await get_tree().physics_frame
	var by_bale: Dictionary = LungeJudge.judge(space, Vector3(-5.1, 0, 0), 0.25, 1.4, 0.35, 0.6,
		[{"id": 3, "pos": Vector3(-5.1, 0, -1.3), "radius": 0.28, "height": 0.7, "center_y": 0.35}])
	_check(float(by_bale["reach"]) > 1.2, "angled into the bale it grazes, the lunge slides along it (%.2f m of 1.4)" % float(by_bale["reach"]))
	_check(int(by_bale["hit_id"]) == 3, "and the hen just ahead by the bale is hit")
	_check(LungeJudge.path(space, Vector3(-5.1, 0.6, 0), Vector3(-1.4, 0, 0), 0.35).size() == 2
		and (LungeJudge.path(space, Vector3(-5.1, 0.6, 0), Vector3(-1.4, 0, 0), 0.35)[1] as Vector3).x > -5.2,
		"(straight into its side it stops: nothing to slide along)")
	# WITH ITS BACK TO A WALL (Luke's playtest of Fowl Play's step 7: an egg thrown by a hen backed onto a
	# hay stack went 2.3 m of 9 and missed the wolf): a ball cast from touching a wall it moves away from
	# was stopped where it stood. (The farm's own stack, a mesh's faces: Fowl Play's `walk` suite.)
	var back_to_bale: Dictionary = LungeJudge.judge(space, Vector3(-5.5 + 0.35, 0, -0.5), -PI / 2.0, 9.0, 0.35, 0.6, [])
	_check(float(back_to_bale["reach"]) > 8.9, "its back to the bale, a throw goes its whole way ahead (%.2f m of 9)" % float(back_to_bale["reach"]))

	# THE PROOF. A hen runs -Z through the gap at 4 m/s, and is out of reach (through it) at T. The
	# wolf stands facing her; its view of others is 150 ms behind the server. (Two sides off, as in Fowl
	# Play: a game that turns them on, a bot wolf and a bot hen are one side.)
	var sides_off: RefCounted = _two_sides(0.0)
	var t_safe: int = BASE + 2_000_000
	ref.set_entity(1, 0)
	ref.set_entity(2, 0)
	ref.set_sweep(500, 1.4, 0.35, 0.6)
	ref.record(1, BASE, Vector3.ZERO, 0.0)
	for i: int in 61:
		var ts: int = BASE + i * 50_000
		ref.record(2, ts, Vector3(0, 0, -1.45 - 4.0 * float(ts - t_safe) / 1_000_000.0), 0.0)
	_check((ref.history(2).at(t_safe)["pos"] as Vector3).is_equal_approx(Vector3(0, 0, -1.45)), "(the hen is at -1.45 m at T)")
	var due: int = t_safe + 50_000
	ref.add_request(1, 1, 500, 150, due)    # the wolf saw her at T - 100 ms
	ref.add_request(2, 1, 500, 0, due)      # it saw her as she was when it landed, T + 50 ms
	ref.add_request(3, 1, 500, 0, t_safe - 100_000)   # it LANDED at T - 100 ms, seen as it was
	var out: Array[Dictionary] = ref.settle(due + ActionReferee.SETTLE_USEC)
	var by_id: Dictionary = {}
	for v: Dictionary in out:
		by_id[int(v["request_id"])] = v
	_check(by_id.size() == 3, "all three judged once they had landed")
	_check(int(by_id.get(1, {}).get("hit_id", -1)) == 2,
		"a pounce whose wolf saw her 100 ms before she was through hits her, though by then she was through (rewound 150 ms)")
	_check(int(by_id.get(2, {}).get("hit_id", -1)) == 0, "one whose wolf saw her 50 ms after: missed")
	_check(int(by_id.get(3, {}).get("hit_id", -1)) == 2, "and one that landed 100 ms before: hit")
	_check(ref.pending_count() == 0, "none left waiting")
	ref.add_request(4, 1, 500, 0, due + 1_000_000)
	var early: Array[Dictionary] = ref.settle(due + ActionReferee.SETTLE_USEC)
	_check(early.is_empty() and ref.pending_count() == 1, "one that lands a second later waits (%d judged)" % early.size())
	_check(ref.settle(due + 1_000_000 + ActionReferee.SETTLE_USEC - 1).is_empty(), "until it has landed and settled")
	_check(ref.settle(due + 1_000_000 + ActionReferee.SETTLE_USEC).size() == 1, "then it is judged")
	_two_sides_back(sides_off)
	root.queue_free()
	await get_tree().process_frame


## A GATE (DECISIONS #229): a character whose wall, 2 m wide across the path, is up only while it is
## shut (a status of its own, 150 here).
func _gate_def() -> EntityDefinition:
	var shut := StatusDef.new()
	shut.status = 150
	var gate := EntityDefinition.new()
	gate.kind = 50
	gate.blocker_size = Vector3(2.0, 1.5, 0.2)
	gate.blocker_offset = Vector3(0.0, 0.75, 0.0)
	gate.blocks_in = [shut]
	return gate


func _run_walls_put_up() -> void:
	print("== referee: walls entities put up (a shut gate) ==")
	var gate: EntityDefinition = _gate_def()
	_check(gate.has_blocker() and gate.blocks_when(150) and not gate.blocks_when(0), "a gate's wall is up only while it is shut")
	var always := EntityDefinition.new()
	always.blocker_size = Vector3.ONE
	_check(always.blocks_when(0) and always.blocks_when(7), "one with no statuses named: always")
	_check(not EntityDefinition.new().has_blocker() and EntityBlocker.make(EntityDefinition.new(), 1) == null, "a character with no size: no wall")
	var flat := EntityDefinition.new()
	flat.blocker_size = Vector3(2.0, 0.0, 0.2)
	_check(", ".join(flat.validate()).contains("give it a size in all three"), "a wall with no height is refused by validate")
	var b: EntityBlocker = EntityBlocker.make(gate, 9)
	b.follow_status(0)
	_check(b.collision_layer == 0 and not b.is_blocking(), "open: on no layer")
	b.follow_status(150)
	_check(b.collision_layer == SpaceTimeEntity.WORLD_MASK and b.is_blocking(), "shut: on the level's layer, as a fence")
	_check(LungeJudge.LEVEL_MASK & b.collision_layer != 0, "(which a pounce's sweep is stopped by)")
	var ic := InteractionComponent.new()
	_check(ic._target_id_of(b) == 9, "aimed at, the wall is its gate")
	ic.free()
	b.free()

	var root := Node3D.new()
	add_child(root)
	var ref := ActionReferee.new()
	ref.send = false
	root.add_child(ref)
	ref.know(gate)
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = ref.get_world_3d().direct_space_state
	var hen: Array = [{"id": 2, "pos": Vector3(0, 0, -1.6), "radius": 0.28, "height": 0.7, "center_y": 0.35}]
	var pounce := func() -> Dictionary: return LungeJudge.judge(space, Vector3.ZERO, 0.0, 1.4, 0.35, 0.6, hen)
	# The gate, a metre ahead across the wolf's path, open.
	ref.set_entity(9, 50, 0)
	ref.record(9, BASE, Vector3(0, 0, -1.0), 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(ref.wall_of(9) != null and not ref.wall_of(9).is_blocking(), "the referee builds the gate's wall where it stands, down while it is open")
	_check(int(pounce.call()["hit_id"]) == 2, "open, a hen through it is pounced")
	var st := _StatusRow.new(9, 150)
	ref.on_row(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, st))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shut: Dictionary = pounce.call()
	_check(ref.wall_of(9).is_blocking() and int(shut["hit_id"]) == 0 and float(shut["reach"]) < 0.9,
		"shut (its status row), the pounce stops at it and she is safe (%.2f m of 1.4)" % float(shut["reach"]))
	ref.record(9, BASE + 50_000, Vector3(0, 0, -1.0), PI / 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(int(pounce.call()["hit_id"]) == 2, "turned along the path (its heading), it no longer stands across it")
	ref.on_row(RowEvent.make(RowEvent.Kind.DELETED, &"entity", _EntityRow.new(9, 50), null))
	_check(ref.wall_of(9) == null, "the gate gone, its wall goes with it")
	root.queue_free()
	await get_tree().process_frame


class _StatusRow extends RefCounted:
	var entity_id: int = 0
	var status: int = 0
	func _init(eid: int, s: int) -> void:
		entity_id = eid
		status = s


func _run_who() -> void:
	print("== referee: who may be hit ==")
	var ref := ActionReferee.new()
	ref.set_entity(10, 0)
	_check(ref.may_be_hit(10), "a person standing")
	ref.set_entity(11, 0, StatusDef.DOWNED)
	_check(not ref.may_be_hit(11), "not one downed: a pounce passes over them (downed.tres: not hittable)")
	_check(StatusDef.find(StatusDef.DOWNED).targetable and not StatusDef.find(StatusDef.DOWNED).hittable,
		"(though they can still be helped up: targetable)")
	ref.set_entity(12, 0, StatusDef.OUT)
	_check(not ref.may_be_hit(12), "nor one out")
	ref.set_entity(13, 110)
	_check(not ref.may_be_hit(13), "nor a thing (a nest: not a person)")
	ref.set_entity(14, 0, 0, true, false)
	_check(not ref.may_be_hit(14), "nor a player who is not connected")
	var hen := EntityDefinition.new()
	hen.kind = 120
	hen.playable = true
	ref.know(hen)
	ref.set_entity(15, 120)
	_check(ref.may_be_hit(15), "a playable character of a genre's kind is a person")
	ref.set_entity(16, 1)
	_check(ref.may_be_hit(16), "and an NPC person (kind 1)")
	ref.set_entity(17, 117)
	_check(not ref.may_be_hit(17), "a genre's NPC of no playable kind, with no brain: a thing")
	ref.set_entity(18, 117, 0, false, true, true)
	_check(ref.may_be_hit(18), "the same with a brain driving it (Fowl Play's decoy hen): a person, as the module says (is_person)")
	var brain_row := ActionReferee.TABLES.has(&"npc_brain")
	_check(brain_row, "(it hears who has a brain: npc_brain is one of its tables)")
	ref.know(load("res://foundation/content/character/player.tres") as EntityDefinition)
	var box: Dictionary = ref.hitbox(0)
	_check(is_equal_approx(float(box["radius"]), 0.4) and is_equal_approx(float(box["height"]), 1.8) and is_equal_approx(float(box["center_y"]), 0.9),
		"a character's hitbox is its body's capsule, standing on the ground (%s)" % str(box))
	var small := EntityDefinition.new()
	small.kind = 121
	small.scene = load("res://foundation/entities/player.tscn") as PackedScene
	small.collision_radius = 0.28
	small.collision_height = 0.7
	ref.know(small)
	var b2: Dictionary = ref.hitbox(121)
	_check(is_equal_approx(float(b2["radius"]), 0.28) and is_equal_approx(float(b2["height"]), 0.7) and is_equal_approx(float(b2["center_y"]), 0.35),
		"a character's own size (a hen: 0.28 m by 0.7) is its hitbox (%s)" % str(b2))
	ref.free()


## TWO SIDES (DECISIONS #283, Regent's Rule: two skeletons side by side hit each other, never the player
## behind). Off, a sweep's first person is hit, whoever it is; on, a player's passes through players and
## anyone else's through everyone but players.
func _run_two_sides() -> void:
	print("== referee: two sides ==")
	var ref := ActionReferee.new()
	ref.set_sweep(501, 1.6, 0.35, 0.6)
	ref.set_entity(30, 1, 0, false, true, true)    # a skeleton swinging -Z
	ref.set_entity(31, 1, 0, false, true, true)    # the skeleton just ahead of it
	ref.set_entity(32, 0, 0, true)                 # the player behind that one
	ref.set_entity(33, 0, 0, true)                 # a player swinging +Z at the skeleton, through 32
	ref.set_entity(34, 1)                          # an NPC with no brain (a training dummy), off to the side
	ref.set_entity(35, 0, 0, true)                 # a player swinging -Z at it
	ref.record(30, BASE, Vector3.ZERO, 0.0)
	ref.record(31, BASE, Vector3(0, 0, -0.6), 0.0)
	ref.record(32, BASE, Vector3(0, 0, -1.3), 0.0)
	ref.record(33, BASE, Vector3(0, 0, -2.0), PI)
	ref.record(34, BASE, Vector3(5, 0, -0.8), 0.0)
	ref.record(35, BASE, Vector3(5, 0, 0.8), 0.0)
	_check(ref.is_player(32) and not ref.is_player(30), "(a player is on the players' side; a brain with no player is not)")
	ref.add_request(1, 30, 501, 0, BASE)
	ref.add_request(2, 33, 501, 0, BASE)
	var off_row: RefCounted = _two_sides(0.0)    # set either way: a game's own override is the default
	var off: Dictionary = _by_request(ref.settle(BASE + ActionReferee.SETTLE_USEC))
	_two_sides_back(off_row)
	_check(int(off.get(1, -1)) == 31, "the rule off: the skeleton's swing hits the skeleton beside it (%d)" % int(off.get(1, -1)))
	_check(int(off.get(2, -1)) == 32, "and the player's hits the player in front (%d)" % int(off.get(2, -1)))
	var on: RefCounted = _two_sides(1.0)
	ref.add_request(3, 30, 501, 0, BASE)
	ref.add_request(4, 33, 501, 0, BASE)
	ref.add_request(5, 35, 501, 0, BASE)
	var two: Dictionary = _by_request(ref.settle(BASE + ActionReferee.SETTLE_USEC))
	_two_sides_back(on)
	_check(int(two.get(3, -1)) == 32, "on: the skeleton's swing passes its friend and hits the player (%d)" % int(two.get(3, -1)))
	_check(int(two.get(4, -1)) == 31, "and the player's passes the other player and hits the skeleton (%d)" % int(two.get(4, -1)))
	_check(int(two.get(5, -1)) == 34, "and a player still hits an NPC with no brain (a training dummy) (%d)" % int(two.get(5, -1)))
	ref.free()


func _by_request(verdicts: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for v: Dictionary in verdicts:
		out[int(v["request_id"])] = int(v["hit_id"])
	return out


## The two-sides rule as the server's row says (`_two_sides_back` takes the row away again).
func _two_sides(value: float) -> RefCounted:
	var row := _HotRow.new()
	row.number = value
	(HotRules as Node).call(&"_on_row", RowEvent.make(RowEvent.Kind.INSERTED, &"hot_rule", null, row))
	return row


func _two_sides_back(row: RefCounted) -> void:
	(HotRules as Node).call(&"_on_row", RowEvent.make(RowEvent.Kind.DELETED, &"hot_rule", row, null))


class _HotRow extends RefCounted:
	var key: String = String(ActionReferee.TWO_SIDES)
	var number: float = 1.0
	var text: String = ""
	var overridden: bool = true


func _run_rows() -> void:
	print("== referee: the rows it judges by ==")
	var ref := ActionReferee.new()
	ref.world_id = 3
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"movement_state", null, _MoveRow.new(5, Vector3(1, 2, 3), 777, 3)))
	_check(ref.history(5) != null and (ref.history(5).at(777)["pos"] as Vector3) == Vector3(1, 2, 3), "a movement row: where it was")
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"movement_state", null, _MoveRow.new(6, Vector3.ONE, 777, 4)))
	_check(ref.history(6) == null, "another world's: not its business")
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"action_request", null, _ReqRow.new(41, 5, 900, 3)))
	_check(ref.pending_count() == 1, "a request: waiting to land")
	ref.on_row(RowEvent.make(RowEvent.Kind.DELETED, &"action_request", _ReqRow.new(41, 5, 900, 3), null))
	_check(ref.pending_count() == 0, "answered (or run out): forgotten")
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, _EntityRow.new(5, 0)))
	_check(ref.may_be_hit(5), "an entity row: what kind it is")
	ref.on_row(RowEvent.make(RowEvent.Kind.DELETED, &"entity", _EntityRow.new(5, 0), null))
	_check(not ref.may_be_hit(5) and ref.history(5) == null, "gone: forgotten, and where it was")
	ref.free()


## A REFEREE ASKS FOR WHAT IT READS (DECISIONS #286): its own tables, what its entities' components declare,
## a genre's `referee_tables` (`*`: all of its tables), the recorder's while it records; never `input_queue`
## (80 % of what a referee was sent at 300 players). Reading a table it does not ask for is loud.
func _run_feed() -> void:
	print("== referee: what it subscribes ==")
	var defs: Array[EntityDefinition] = []
	EntityDefinition.add_foundation_kinds(defs)
	var bare: Array[StringName] = []
	bare.assign(SidecarMain.referee_feed(defs, [] as Array[GenreModule], false))
	_check(not bare.has(&"input_queue"), "no input_queue: only a sidecar that moves the players replays it")
	var own: Array[StringName] = SidecarMain.REFEREE_TABLES
	_check(own.all(func(t: StringName) -> bool: return bare.has(t)), "what it reads itself: %s" % ", ".join(own))
	var player_scene: Array[StringName] = []
	player_scene.assign(SidecarMain.scene_tables(defs[0].scene))
	_check(player_scene.has(&"movement_state") and player_scene.has(&"status_state") and player_scene.has(&"hold_progress"),
		"an entity scene's tables: its components' and the ones every entity is given (%s)" % ", ".join(player_scene))
	_check(player_scene.has(&"lobby_member"), "and what they read themselves (`also_reads`: a status reads the lobby)")
	_check(player_scene.all(func(t: StringName) -> bool: return t == &"input_queue" or bare.has(t)),
		"every one its entities wait for is in its feed (or a bot would wait out its bind)")
	_check(not bare.has(&"noise") and not bare.has(&"session"), "not recording: no noise, no session")
	var rec: Array[StringName] = []
	rec.assign(SidecarMain.referee_feed(defs, [] as Array[GenreModule], true))
	_check(rec.has(&"noise") and rec.has(&"session") and rec.has(&"action_event") and not rec.has(&"input_queue"),
		"recording: the recorder's tables too, and still no input_queue")
	var all_of := GenreModule.new()
	all_of.tables = [&"nest", &"hen"] as Array[StringName]
	var listed := GenreModule.new()
	listed.tables = [&"nest", &"hen"] as Array[StringName]
	listed.referee_tables = [&"hen", &"session"] as Array[StringName]
	var none := GenreModule.new()
	none.tables = [&"nest", &"hen"] as Array[StringName]
	none.referee_tables = [] as Array[StringName]
	var f_all: Array[StringName] = []
	f_all.assign(SidecarMain.referee_feed(defs, [all_of] as Array[GenreModule], false))
	var f_listed: Array[StringName] = []
	f_listed.assign(SidecarMain.referee_feed(defs, [listed] as Array[GenreModule], false))
	var f_none: Array[StringName] = []
	f_none.assign(SidecarMain.referee_feed(defs, [none] as Array[GenreModule], false))
	_check(f_all.has(&"nest") and f_all.has(&"hen"), "a genre's `*` (the default): every one of its tables")
	_check(f_listed.has(&"hen") and f_listed.has(&"session") and not f_listed.has(&"nest"), "a genre's list: those, and not the rest")
	_check(not f_none.has(&"nest") and not f_none.has(&"hen"), "empty: none of them")
	# Reading what it does not ask for: an error, once a table.
	var was: Dictionary[StringName, bool] = SpaceTimeSync.read_only
	SpaceTimeSync.read_only = {&"entity": true}
	SpaceTimeSync.get_row(&"entity", 1)
	_check(not SpaceTimeSync._unasked.has(&"entity"), "a table it asks for: read quietly")
	SpaceTimeSync.get_row(&"referee_test_unasked", 1)
	SpaceTimeSync.find_rows(&"referee_test_unasked", func(_r: RefCounted) -> bool: return true)
	_check(SpaceTimeSync._unasked.has(&"referee_test_unasked"), "one it does not: an error naming it (once)")
	SpaceTimeSync._unasked.erase(&"referee_test_unasked")
	SpaceTimeSync.read_only = was
	SpaceTimeSync.get_row(&"referee_test_unasked", 1)
	_check(not SpaceTimeSync._unasked.has(&"referee_test_unasked"), "a player's client (no list): reads anything")


class _RowStub extends RefCounted:
	var _v: Dictionary = {}
	func _init(v: Dictionary) -> void:
		_v = v
	func _get(key: StringName) -> Variant:
		return _v.get(key, null)


## Whether `ranges` hold every cell of the level (`r.clip`) that `r` watches, and no other cell of it.
func _ranges_hold_watched(r: RefereeRegion, ranges: Array[Vector2i]) -> bool:
	for x: int in range(r.clip.position.x, r.clip.end.x):
		for z: int in range(r.clip.position.y, r.clip.end.y):
			var c: int = Cells.at(x, z)
			var held: bool = ranges.any(func(g: Vector2i) -> bool: return c >= g.x and c <= g.y)
			if held != r.watches(x, z):
				return false
	return true


## REGION REFEREES (DECISIONS #288): a referee for some cells of a world runs what stands in them and
## watches a border round them; an NPC it drives is handed on only past its edge; what it subscribes is a
## query per column; it judges only its own people's swings; the module's rows say what it drives.
func _run_regions() -> void:
	print("== referee: regions ==")
	_check(RefereeRegion.parse("1,2") == null and RefereeRegion.parse("a,b,c,d") == null, "a region that is not four numbers: none")
	var r: RefereeRegion = RefereeRegion.parse("2,-1,0,1")
	_check(r.x0 == 0 and r.x1 == 2 and r.z0 == -1 and r.z1 == 1, "its corners in either order (%s)" % r.describe())
	r.side_m = 10.0
	r.hand_on_m = 2.0
	_check(r.runs(Vector3(0.0, 0.0, -10.0)) and r.runs(Vector3(29.9, 0.0, 19.9)), "it runs what stands in its cells, edge to edge")
	_check(not r.runs(Vector3(30.5, 0.0, 0.0)) and not r.runs(Vector3(-0.5, 0.0, 0.0)), "not what stands just past them")
	_check(r.runs(Vector3(31.5, 0.0, 0.0), true) and not r.runs(Vector3(32.5, 0.0, 0.0), true),
		"its own NPC: still its own up to 2 m past the edge, not further")
	_check(r.watches(-1, -2) and r.watches(3, 2) and not r.watches(4, 0) and not r.watches(0, -3), "it watches one cell round them")
	var cols: Array[Vector2i] = r.columns()
	_check(cols.size() == 5 and cols[0] == Vector2i(Cells.at(-1, -2), Cells.at(-1, 2)) and cols[4] == Vector2i(Cells.at(3, -2), Cells.at(3, 2)),
		"what it asks for: one range of chunks a column, its cells and the border (%d columns)" % cols.size())
	_check(cols[0].y - cols[0].x == 4, "a column's chunks are consecutive (5 cells)")
	var wide: RefereeRegion = RefereeRegion.parse("-512,-512,-1,511")
	_check(wide.columns().size() == 513, "a region to the grid's edge watches 513 columns")
	wide.clip_to(AABB(Vector3(-100.0, -10.0, -50.0), Vector3(300.0, 20.0, 100.0)))
	var clipped: Array[Vector2i] = wide.columns()
	_check(clipped.size() == 4 and clipped[0] == Vector2i(Cells.at(-3, -2), Cells.at(-3, 1)) and clipped[3].x == Cells.at(0, -2),
		"clipped to the level (a cell round it): its own columns and its border's, the level's rows only (%d columns)" % clipped.size())
	var away: RefereeRegion = RefereeRegion.parse("100,100,110,110")
	away.clip_to(AABB(Vector3(-100.0, -10.0, -50.0), Vector3(300.0, 20.0, 100.0)))
	_check(away.columns().is_empty(), "a region the level does not reach asks for nothing")
	# What it subscribes (template 1.6.3): a strip as tall as the level is one range; a region cut across
	# the level's height a range a column. Either way exactly the level's cells it watches, no other's.
	var strip: Array[Vector2i] = wide.ranges()
	_check(strip.size() == 1 and strip[0] == Vector2i(Cells.at(-3, -2), Cells.at(0, 1)),
		"a strip as tall as the level: its columns as one range (%d)" % strip.size())
	var cut: RefereeRegion = RefereeRegion.parse("-512,-512,-1,-1")
	cut.clip_to(AABB(Vector3(-100.0, -10.0, -50.0), Vector3(300.0, 20.0, 100.0)))
	var cut_ranges: Array[Vector2i] = cut.ranges()
	_check(cut_ranges == cut.columns() and cut_ranges.size() == 4, "a region cut across the level's height: a range a column (%d)" % cut_ranges.size())
	_check(_ranges_hold_watched(wide, strip) and _ranges_hold_watched(cut, cut_ranges),
		"each holds the level's cells it watches and no other of the level's (the strip's gaps are outside it)")
	_check(not _ranges_hold_watched(cut, [Vector2i(cut_ranges[0].x, cut_ranges[3].y)]),
		"(the check's negative: one range over the cut region's columns takes in the region above it)")
	_check(r.ranges() == r.columns(), "a region with no clip and not to the grid's edge: a range a column")
	var whole: RefereeRegion = RefereeRegion.parse("-4,-512,3,511")
	var whole_ranges: Array[Vector2i] = whole.ranges()
	_check(whole_ranges.size() == 1 and whole_ranges[0] == Vector2i(Cells.at(-5, -512), Cells.at(4, 511)), "no clip, to the grid's edges: one range")
	wide.clip_to(AABB())
	_check(wide.columns().size() == 513, "no bounds: no clip")
	var im: Node = get_node(^"/root/InterestManager")
	var prev_cols: Array[Vector2i] = im.region_columns
	var prev_cfg: NetConfig = SpaceTimeSync.config
	SpaceTimeSync.config = NetConfig.new()
	im.region_columns = cols
	var q: Array[String] = []
	q.assign(im.build_ring_queries(4))
	_check(im.is_ring() and not q.is_empty() and q.all(func(x: String) -> bool: return x.contains("world_id = 4 AND chunk >= ")),
		"subscribed: the cell tables by column (%d queries)" % q.size())
	var by_column: int = q.size()
	im.region_columns = strip
	q.assign(im.build_ring_queries(4))
	_check(q.size() * cols.size() == by_column and q.has("SELECT * FROM movement_state WHERE world_id = 4 AND chunk >= %d AND chunk <= %d" % [strip[0].x, strip[0].y]),
		"a strip: one query a cell table (%d, against %d by column)" % [q.size(), by_column])
	im.region_columns = cols
	_check(q.any(func(x: String) -> bool: return x.begins_with("SELECT * FROM movement_state")), "movement among them")
	var no_cols: Array[Vector2i] = []
	im.region_on = true
	im.region_columns = no_cols
	q.assign(im.build_ring_queries(4))
	_check(im.is_ring() and q.is_empty() and not im.build_queries(4).any(func(x: String) -> bool: return x.begins_with("SELECT * FROM movement_state")),
		"a region with no columns asks for no cell of any table, never the whole world's")
	im.region_on = false
	_check(not im.is_ring(), "and a referee for the whole world: no cells of its own (it is sent the world)")
	im.region_columns = prev_cols
	SpaceTimeSync.config = prev_cfg

	# What it asks the module for.
	var seen: Array[Dictionary] = [
		{"id": 1, "pos": Vector3(5.0, 0.0, 5.0), "mine": false},     # in its cells, not its own: take
		{"id": 2, "pos": Vector3(31.0, 0.0, 5.0), "mine": true},     # its own, 1 m past the edge: keep
		{"id": 3, "pos": Vector3(33.0, 0.0, 5.0), "mine": true},     # its own, 3 m past: let go
		{"id": 4, "pos": Vector3(31.0, 0.0, 5.0), "mine": false},    # someone else's, past the edge: leave
		{"id": 5, "pos": Vector3(5.0, 0.0, 5.0), "mine": true},      # its own, at home: keep
	]
	var ask: Dictionary = RegionKeeper.decide(seen, r)
	_check(ask["take"] == [1] and ask["release"] == [3], "take what has come in, let go of what has gone 2 m out (take %s, let go %s)" % [ask["take"], ask["release"]])

	# The keeper: the module's rows decide what it runs.
	var me := PackedByteArray([1, 2, 3])
	var other := PackedByteArray([9, 9, 9])
	var rows: Dictionary = {
		&"npc_driver": [_RowStub.new({&"entity_id": 11, &"world_id": 4, &"driver": me}),
			_RowStub.new({&"entity_id": 12, &"world_id": 4, &"driver": other})],
		&"player": [_RowStub.new({&"entity_id": 20})],
		&"npc_brain": [_RowStub.new({&"entity_id": 11}), _RowStub.new({&"entity_id": 12}), _RowStub.new({&"entity_id": 13})],
		&"body_state": [],
		&"movement_state": [
			_RowStub.new({&"entity_id": 11, &"world_id": 4, &"pos": Vector3(35.0, 0.0, 0.0)}),
			_RowStub.new({&"entity_id": 12, &"world_id": 4, &"pos": Vector3(5.0, 0.0, 0.0)}),
			_RowStub.new({&"entity_id": 13, &"world_id": 4, &"pos": Vector3(6.0, 0.0, 0.0)}),
			_RowStub.new({&"entity_id": 20, &"world_id": 4, &"pos": Vector3(7.0, 0.0, 0.0)})],
	}
	var k := RegionKeeper.new()
	k.region = r
	k.world_id = 4
	k.send = false
	k.identity = me
	k.rows_of = func(t: StringName) -> Array: return rows.get(t, [])
	var started: Array[int] = []
	var stopped: Array[int] = []
	k.on_mine = func(eid: int) -> void: started.append(eid)
	k.on_not_mine = func(eid: int) -> void: stopped.append(eid)
	var asked: Dictionary = k.poll()
	_check(started == [11] and stopped == [11], "the module says 11 is ours: run it; it stands 5 m out: let go (%s, %s)" % [started, stopped])
	_check(asked["take"] == [12, 13] and asked["release"] == [11],
		"ask for 12 and 13 in its cells (the module refuses 12 while another drives it), never the player")
	k.poll()
	_check(started == [11] and not k.drives(11), "let go, the row not yet changed: not run again")
	(rows[&"movement_state"][0] as _RowStub)._v[&"pos"] = Vector3(10.0, 0.0, 0.0)
	k.poll()
	_check(k.drives(11) and started == [11, 11], "back in before the module heard: run again")
	rows[&"npc_driver"] = [_RowStub.new({&"entity_id": 12, &"world_id": 4, &"driver": me})]
	k.poll()
	_check(k.drives(12) and not k.drives(11) and stopped.count(11) == 2, "the module gave it 12 and took 11 away: so it runs 12, not 11")
	k.free()

	# Judging: only its own people's swings.
	var ref := ActionReferee.new()
	ref.send = false
	ref.world_id = 4
	ref.may_judge = func(actor: int) -> bool: return actor == 5
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"action_request", null, _ReqRow.new(41, 5, 900, 4)))
	ref.on_row(RowEvent.make(RowEvent.Kind.INSERTED, &"action_request", null, _ReqRow.new(42, 6, 900, 4)))
	var verdicts: Array[Dictionary] = ref.settle(10_000_000_000)
	_check(verdicts.size() == 1 and int(verdicts[0]["request_id"]) == 41 and ref.pending_count() == 0,
		"a swing of its own region's: judged; another region's: left for that referee (%d judged)" % verdicts.size())
	ref.free()


func _run_client_side() -> void:
	print("== referee: the client's part ==")
	var d: int = SpaceTimeActionComponent.view_delay_ms()
	_check(d >= 100 and d < 1000, "a client says how far behind it sees others: its interpolation and half a round trip (%d ms)" % d)
	_check(RefereeLauncher.is_local_host("http://127.0.0.1:3000") and RefereeLauncher.is_local_host("localhost:3000")
		and not RefereeLauncher.is_local_host("http://friend.example:3000"),
		"a referee is started only for a server on this machine")
	# THE GAME IS STILL HERE (not a process id: on Windows Godot sees only processes it started).
	var alive: String = ProjectSettings.globalize_path("user://referee_suite.alive")
	DirAccess.remove_absolute(alive)
	_check(not RefereeLauncher.is_alive(alive), "no file: the game that started it is gone")
	RefereeLauncher.touch_alive(alive)
	_check(RefereeLauncher.is_alive(alive), "touched just now: still here")
	_check(not RefereeLauncher.is_alive(alive, -1.0), "touched longer ago than it waits: gone")
	DirAccess.remove_absolute(alive)
	var launcher := RefereeLauncher.new()
	_check(not launcher.why_not().is_empty(), "and not by a client that is not the admin of a connected game (\"%s\")" % launcher.why_not())
	launcher.free()
	# THE CHRONICLE (DECISIONS #276): started beside an editor run unless its lock is fresh.
	var lock: String = ChronicleLauncher.lock_path("suite-db")
	_check(lock.ends_with("build/telemetry/suite-db.sqlite.lock"), "the chronicle's lock is where chronicle.py keeps it (%s)" % lock)
	var lock_file: String = ProjectSettings.globalize_path("user://chronicle_suite.lock")
	DirAccess.remove_absolute(lock_file)
	_check(not ChronicleLauncher.lock_fresh(lock_file), "no lock: nothing records, so an editor run starts one")
	RefereeLauncher.touch_alive(lock_file)
	_check(ChronicleLauncher.lock_fresh(lock_file), "a lock touched just now: a chronicle records, so it starts none")
	_check(not ChronicleLauncher.lock_fresh(lock_file, -1.0), "a lock older than it waits: its chronicle is gone")
	DirAccess.remove_absolute(lock_file)
	var chron := ChronicleLauncher.new()
	_check(not chron.why_not().is_empty(), "nor by a client that is not the admin of a connected game (\"%s\")" % chron.why_not())
	chron.free()
	# A referee builds nothing from the rows: the spawner can be told not to spawn.
	EntitySpawner.register_definition(load("res://foundation/content/character/player.tres") as EntityDefinition)
	var before: int = EntitySpawner.spawned_count()
	EntitySpawner.spawning = false
	EntitySpawner._spawn_from(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, _EntityRow.new(99901, 0)))
	var none: bool = EntitySpawner.get_entity_node(99901) == null and EntitySpawner.spawned_count() == before
	EntitySpawner.spawning = true
	_check(none, "told not to spawn, an entity row builds nothing")

	# THE KEY: the left mouse button uses the character's first ability, ahead the way it faces.
	var ent := SpaceTimeEntity.new()
	var defn := EntityDefinition.new()
	var ab := AbilityDef.new()
	ab.id = 7
	defn.abilities = [ab]
	ent.definition = defn
	get_tree().root.add_child(ent)
	ent.entity_id = 9701
	ent.is_local_authority = true
	var act := SpaceTimeActionComponent.new()
	var sent: Array = []
	act._def_override = func(id: int) -> RefCounted: return _AbilityRow.new(id)
	act._reducer_override = func(a: int, _t: int, aim: Vector3, _pid: int) -> ReducerRequest:
		sent.append([a, aim])
		return ReducerRequest.new()
	ent.add_runtime_component(act)
	act.bind(ent, {})
	var input := LocalInputComponent.new()
	input.capture_mouse = false
	input.send_to_server = false
	ent.add_runtime_component(input)
	input.bind(ent, {})
	input.set_physics_process(false)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	input._unhandled_input(lmb)
	_check(sent.size() == 1 and int(sent[0][0]) == 7 and (sent[0][1] as Vector3).is_equal_approx(Vector3(0, 0, -1)),
		"the left mouse button: the character's first ability, aimed the way it faces (%s)" % str(sent))
	input._unhandled_input(lmb)
	_check(sent.size() == 1, "pressed again inside its cooldown: nothing sent")
	input.hold_still(&"test", true)
	act._ready_at_usec.clear()
	input._unhandled_input(lmb)
	_check(sent.size() == 1, "held still (a page over the game): the button does nothing")
	input.hold_still(&"test", false)
	defn.abilities = []
	_check(input.use_first_ability() == -1, "a character with no ability: nothing to use")
	ent.queue_free()
	await get_tree().process_frame
