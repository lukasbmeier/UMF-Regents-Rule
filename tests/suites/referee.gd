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
	_run_who()
	_run_rows()
	await _run_client_side()


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

	# THE PROOF. A hen runs -Z through the gap at 4 m/s, and is out of reach (through it) at T. The
	# wolf stands facing her; its view of others is 150 ms behind the server.
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
	root.queue_free()
	await get_tree().process_frame


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
