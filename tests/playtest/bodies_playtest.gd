extends Node
## BODIES PLAYTEST (DECISIONS #246): real clients, through the latency simulator, and the world's real
## referee (tests/bodies_playtest.sh starts it). Two roles:
##   --role=thrower   throws the greybox's ball at the east wall. It must leave the hand on the throw (its
##                    own flight, that frame); the referee's body must take that flight over, compare it
##                    row by row and keep it within a hand's breadth (no snap) through the wall's bounce;
##                    the wall's hit must arrive as a contact; at rest, what it draws must be where the
##                    referee put it
##   --role=watcher   sees the same ball fly from the referee's rows (no flight of its own), smoothly,
##                    and come to rest in the same place
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 50.0
const BALL_ID: int = 1
## Where the throw goes: east, a little up, hard enough to reach the wall (x 9.5) on the fly.
const THROW_VEL: Vector3 = Vector3(14.0, 3.0, 0.0)

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "thrower"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr("--role=".length())
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	await get_tree().create_timer(2.0).timeout   # the clock settles
	if _role == "thrower":
		await get_tree().create_timer(2.0).timeout   # the watcher is in
		await _throw(me)
	else:
		# Out of the thrower's way (both appear at the spawn): a ball leaving a hand inside someone else
		# is a ball that hits them.
		SpaceTimeSync.call_reducer(&"teleport", [Vector3(0.0, 0.0, -6.0)], ["vector3[f32,f32,f32]"])
		await _watch()
	_finish()


func _throw(me: SpaceTimeEntity) -> void:
	var def: BodyDef = BodyDef.by_id(BALL_ID)
	_check(def != null, "the ball is content")
	_check(get_node_or_null(^"../Game/Thrower") is GreyboxThrower, "the greybox game has its thrower (G)")
	var contacts: Array[Dictionary] = []
	SpaceTimeSync.row_event.connect(func(ev: RowEvent) -> void:
		if ev.table == &"body_contact" and ev.kind == RowEvent.Kind.INSERTED:
			contacts.append({"other_id": int(ev.new.get(&"other_id")), "speed": float(ev.new.get(&"speed"))}))
	var origin: Vector3 = me.global_position + Vector3(0.5, 1.4, 0.0)
	var launch_id: int = BodyLaunch.throw_body(me.get_parent(), def, origin, THROW_VEL)
	var mine: FlyingBody = me.get_parent().get_node_or_null(NodePath("Throw%d" % launch_id)) as FlyingBody
	_check(mine != null and BodyLaunch.waiting() == 1, "it leaves the hand on the throw: the thrower's own flight, this frame")
	var thrower: GreyboxThrower = get_node_or_null(^"../Game/Thrower") as GreyboxThrower
	var cam: FlightCam = thrower.flight_cam if thrower != null else null
	if cam != null:
		cam.obey_setting = false
	var rig: CameraRig = me.get_node_or_null(^"CameraRig") as CameraRig
	_check(cam != null and cam.follow_throw(launch_id, mine) and rig != null and rig.watching() == mine,
		"the flight cam follows it from the throw (DECISIONS #248)")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(mine != null and mine.global_position.x > origin.x, "and it is moving already, before the server has heard")
	var body: BodyComponent = await _body(5.0)
	_check(body != null, "the referee's body arrives")
	if body == null:
		return
	_check(body.flight() == mine and BodyLaunch.waiting() == 0, "and takes the thrower's flight over (no second ball)")
	_check(rig != null and rig.watching() == mine and cam.body_id() == body.entity_id, "the flight cam is on its body now, the same flight")
	var max_gap: float = 0.0
	var deadline: int = Time.get_ticks_msec() + 15_000
	while not body.at_rest and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		max_gap = maxf(max_gap, body.last_gap)
	print("   rows compared %d, worst gap %.3f m, snaps %d" % [body.corrections, max_gap, body.snaps])
	_check(body.corrections >= 10, "the referee's rows were compared with the flight as they came (%d)" % body.corrections)
	_check(body.snaps == 0, "never far enough off to snap (%d)" % body.snaps)
	_check(max_gap < 0.3, "at 150 ms the two flights stayed within %.2f m of each other through the wall's bounce" % max_gap)
	_check(body.at_rest, "it came to rest")
	await get_tree().create_timer(0.6).timeout   # the settle glide
	_check(rig.watching() == (body.entity.get_node(^"Visual") as Node3D), "at rest, the flight cam holds on where it lies")
	await get_tree().create_timer(cam.hold_s + 0.2).timeout
	_check(not cam.is_following() and rig.watching() == null, "and then the camera comes back to the thrower")
	var drawn: Vector3 = (body.entity.get_node(^"Visual") as Node3D).global_position
	var server: Vector3 = (body.entity as Node3D).global_position
	print("   at rest: drawn %s, the referee's %s" % [drawn, server])
	_check(drawn.distance_to(server) < 0.05, "and what it draws is where the referee put it (%.3f m)" % drawn.distance_to(server))
	_check(body.flight() == null, "its own flight is gone: the rows draw it now")
	_check(server.x < 9.4 and server.x > -9.4 and server.y < 0.3, "back off the wall, on the floor (%s)" % server)
	_check(contacts.any(func(c: Dictionary) -> bool: return int(c["other_id"]) == 0 and float(c["speed"]) > 5.0),
		"the wall's hit arrived as a contact, fast (%s)" % [contacts])


func _watch() -> void:
	var body: BodyComponent = await _body(20.0)
	_check(body != null, "the watcher sees the ball the other player threw")
	if body == null:
		return
	_check(body.flight() == null and BodyLaunch.waiting() == 0, "drawn from the referee's rows: no flight of its own")
	var vis: Node3D = body.entity.get_node(^"Visual") as Node3D
	var prev: Vector3 = vis.global_position
	var worst_step: float = 0.0
	var worst_at: String = ""
	var moved: float = 0.0
	var frame: int = 0
	var deadline: int = Time.get_ticks_msec() + 15_000
	while not body.at_rest and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		frame += 1
		var now: Vector3 = vis.global_position
		if now.distance_to(prev) > worst_step:
			worst_step = now.distance_to(prev)
			worst_at = "frame %d, %s -> %s" % [frame, prev, now]
		moved += now.distance_to(prev)
		prev = now
	print("   watched it move %.1f m, worst step a frame %.3f m (%s)" % [moved, worst_step, worst_at])
	_check(moved > 5.0, "it flew (%.1f m)" % moved)
	_check(worst_step < 0.6, "smoothly: no frame jumped more than a fast ball travels (%.3f m)" % worst_step)
	_check(body.at_rest, "and came to rest")
	await get_tree().create_timer(0.5).timeout
	var server: Vector3 = (body.entity as Node3D).global_position
	print("   at rest at %s" % server)
	_check(server.x < 9.4 and server.x > -9.4 and server.y < 0.3, "back off the wall, on the floor, where the thrower's came to rest")


## The first body to arrive (a kind-3 entity, bound), or null after `seconds`.
func _body(seconds: float) -> BodyComponent:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for n: Node in EntitySpawner.entity_nodes():
			var e: SpaceTimeEntity = n as SpaceTimeEntity
			if e != null and e.is_bound() and e.definition != null and e.definition.kind == 3:
				return e.find_component(BodyComponent) as BodyComponent
		await get_tree().physics_frame
	return null


func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + 30_000
	while Time.get_ticks_msec() < deadline:
		var id: int = EntityRegistry.local_entity_id
		if id >= 0:
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.is_bound():
				return e
		await get_tree().process_frame
	_check(false, "local player spawned and bound")
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: bodies playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nbodies (%s): %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
