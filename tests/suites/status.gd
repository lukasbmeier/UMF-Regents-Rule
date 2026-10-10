extends "res://tests/suite_base.gd"
## The `status` suite (tests/test_runner.gd runs it; `-- --only=status` runs it alone).
## STATUSES (DECISIONS #206): the foundation's seven as content; a genre replacing one; what a status
## does to movement (the config and the presses it takes away), measured through the movement
## component the way prediction and the sidecar step; the body hidden for two reasons at once; the
## tag over the head; a player who is out watching a teammate; every entity given a StatusComponent.


func run() -> void:
	StatusDef.clear_cache()
	_run_content()
	await _run_genre_replaces()
	await _run_movement()
	await _run_presentation()
	await _run_spectate()
	_run_every_entity_has_one()
	StatusDef.clear_cache()


class _StatusRow extends RefCounted:
	var entity_id: int = 0
	var world_id: int = 0
	var status: int = 0
	var prev_status: int = 0
	var since: int = 0
	var lasts_ms: int = 0
	var by_entity: int = 0
	var data: String = ""
	var serial: int = 1
	func _init(eid: int, st: int, p_serial: int = 1, p_lasts_ms: int = 0) -> void:
		entity_id = eid
		status = st
		serial = p_serial
		lasts_ms = p_lasts_ms
		since = ClockSync.server_usec()


class _PlayerRow extends RefCounted:
	var entity_id: int = 0
	var name: String = ""
	var online: bool = true
	func _init(eid: int, on: bool = true) -> void:
		entity_id = eid
		name = "P%d" % eid
		online = on


func _run_content() -> void:
	print("== status: the foundation's, as content ==")
	var names: PackedStringArray = PackedStringArray()
	for n: int in 7:
		var s: StatusDef = StatusDef.find(n)
		names.append(s.display_name if s != null else "?")
	_check(names == PackedStringArray(["Normal", "Injured", "Downed", "Carried", "Out", "Hidden", "Escaped"]),
		"the foundation has its seven, numbered 0-6: %s" % ", ".join(names))
	_check(StatusDef.normal().moves_as_usual() and StatusDef.find(StatusDef.NORMAL).apply_to(MovementConfig.shared()) == MovementConfig.shared(),
		"normal changes nothing (the same config, not a copy)")
	var downed: StatusDef = StatusDef.find(StatusDef.DOWNED)
	var base: MovementConfig = MovementConfig.shared()
	var c: MovementConfig = downed.apply_to(base)
	_check(is_equal_approx(c.run_speed, base.run_speed * 0.25) and is_equal_approx(c.sprint_speed, c.run_speed)
		and c.flap_charges == 0 and c.dash_impulse == 0.0,
		"downed crawls at a quarter of the character's run, with no sprint, flaps or dash (run %.2f)" % c.run_speed)
	_check(downed.then_status == StatusDef.find(StatusDef.OUT) and is_equal_approx(downed.lasts_s, 60.0),
		"and after 60 s it is out")
	var f := InputFrame.new()
	f.jump = true
	f.sprint = true
	f.dash = true
	f.move_dir = Vector2(0, -1)
	var g: InputFrame = downed.filter_input(f)
	_check(not g.jump and not g.sprint and not g.dash and g.move_dir == f.move_dir and f.jump,
		"its presses are taken out (jump, sprint, dash), the move kept, the frame sent left alone")
	_check(StatusDef.normal().filter_input(f) == f, "normal leaves the frame as it is")
	var injured: StatusDef = StatusDef.find(StatusDef.INJURED)
	_check(injured.bursting_at(0.5) and not injured.bursting_at(1.6)
		and is_equal_approx(injured.apply_to(base, true).sprint_speed, base.sprint_speed * 1.5),
		"injured bursts half as fast again for 1.5 s, then not")
	var out: StatusDef = StatusDef.find(StatusDef.OUT)
	_check(out.spectate and out.hide_body and not out.targetable and not out.can_act, "out: watches a teammate, hidden, out of reach")
	var bad := StatusDef.new()
	bad.display_name = "Loop"
	bad.then_status = bad
	_check(bad.validate().any(func(s: String) -> bool: return s.contains("becomes itself")), "a status that becomes itself is refused")
	bad.then_status = null   # a resource holding itself is never freed


func _save_status(dir: String, file: String, number: int, speed: float, id: int) -> StatusDef:
	DirAccess.make_dir_recursive_absolute(dir)
	var s := StatusDef.new()
	s.status = number
	s.speed = speed
	s.id = id
	s.display_name = file.capitalize()
	ResourceSaver.save(s, dir.path_join(file + ".tres"))
	return load(dir.path_join(file + ".tres")) as StatusDef


func _run_genre_replaces() -> void:
	print("== status: a genre replaces one of the foundation's ==")
	var root: String = "user://status_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["hens", "foxes"])
	StatusDef.clear_cache()
	var f_dir: String = root.path_join("foundation/content/status")
	_save_status(f_dir, "normal", 0, 1.0, 0)
	_save_status(f_dir, "downed", 2, 0.25, 2)
	var hens: String = root.path_join("game/hens/content/status")
	var foxes: String = root.path_join("game/foxes/content/status")
	var slow: StatusDef = _save_status(hens, "downed_hen", 2, 0.1, 10000)
	_check(StatusDef.find(2) == slow and is_equal_approx(StatusDef.find(2).speed, 0.1),
		"the genre's downed is the game's (it crawls at 0.1), the foundation's file untouched")
	_check(StatusDef.find(0) != null and StatusDef.find(0).display_name == "Normal", "the rest stay the foundation's")
	var all: Array[ContentDef] = ContentLibrary.items(&"status")
	_check(slow.validate_with(all).is_empty(), "replacing the foundation's is allowed")
	var stray: StatusDef = _save_status(hens, "stray", 50, 1.0, 10001)
	all = ContentLibrary.items(&"status")
	_check(stray.validate_with(all).any(func(s: String) -> bool: return s.contains("replaces none")),
		"a genre's status under 100 that replaces nothing is refused")
	var twin: StatusDef = _save_status(foxes, "twin", 2, 0.5, 20000)
	all = ContentLibrary.items(&"status")
	_check(twin.validate_with(all).any(func(s: String) -> bool: return s.contains("are both status 2")),
		"two genres with one number are refused")
	var dup: StatusDef = _save_status(hens, "dup", 2, 0.3, 10002)
	all = ContentLibrary.items(&"status")
	_check(dup.validate_with(all).any(func(s: String) -> bool: return s.contains("of the same owner")),
		"two of one genre with one number are refused")
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	StatusDef.clear_cache()
	_wipe(root)
	await get_tree().process_frame


## An entity (not in the tree: the model steps on its flat ground) with a movement component and a
## status, both bound, as `SpaceTimeEntity` binds them.
func _entity_with_status(eid: int, status: int) -> Array:
	var ent := SpaceTimeEntity.new()
	ent.entity_id = eid
	ent.is_local_authority = true
	var st := StatusComponent.new()
	ent.add_runtime_component(st)
	var m := SpaceTimeMovementComponent.new()
	m.config = MovementConfig.shared()
	m.mode = SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED
	ent.add_runtime_component(m)
	st.bind(ent, {&"status_state": _StatusRow.new(eid, status)})
	m.bind(ent, {&"movement_state": FakeMoveRow.new(eid, Vector3.ZERO, 1_000)})
	return [ent, m, st]


func _drive(m: SpaceTimeMovementComponent, frames: int, sprint: bool, jump: bool) -> void:
	for i: int in frames:
		var f := InputFrame.new()
		f.seq = i + 1
		f.move_dir = Vector2(0, -1)
		f.sprint = sprint
		f.jump = jump and i == frames / 2
		m.push_input(f)


func _run_movement() -> void:
	print("== status: how it moves (the movement component, as prediction and the sidecar step) ==")
	var cfg: MovementConfig = MovementConfig.shared()
	var normal: Array = _entity_with_status(9101, StatusDef.NORMAL)
	_drive(normal[1], 120, true, false)
	var top: float = Vector2((normal[1] as SpaceTimeMovementComponent).get_predicted_state().vel.x,
		(normal[1] as SpaceTimeMovementComponent).get_predicted_state().vel.z).length()
	_check(is_equal_approx(top, cfg.sprint_speed), "normal: a sprint reaches %.2f m/s (the character's)" % top)

	var down: Array = _entity_with_status(9102, StatusDef.DOWNED)
	var dm: SpaceTimeMovementComponent = down[1]
	var highest: float = 0.0
	for i: int in 120:
		var f := InputFrame.new()
		f.seq = i + 1
		f.move_dir = Vector2(0, -1)
		f.sprint = true
		f.jump = i % 20 == 0
		dm.push_input(f)
		highest = maxf(highest, dm.get_predicted_state().pos.y)
	var s: MovementState = dm.get_predicted_state()
	var crawl: float = Vector2(s.vel.x, s.vel.z).length()
	_check(is_equal_approx(crawl, cfg.run_speed * 0.25), "downed: sprinting and jumping, it crawls at %.2f m/s (a quarter of its run)" % crawl)
	_check(highest == 0.0 and s.move_state != MovementState.Move.SPRINT and s.move_state != MovementState.Move.AIR,
		"and never leaves the ground, nor shows a sprint (state %d)" % s.move_state)

	# The status changes under it: the next steps follow (prediction replays with the new one).
	var st: StatusComponent = down[2]
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", _StatusRow.new(9102, StatusDef.DOWNED),
		_StatusRow.new(9102, StatusDef.NORMAL, 2)))
	for i: int in 120:
		var f := InputFrame.new()
		f.seq = 200 + i
		f.move_dir = Vector2(0, -1)
		f.sprint = true
		dm.push_input(f)
	s = dm.get_predicted_state()
	_check(is_equal_approx(Vector2(s.vel.x, s.vel.z).length(), cfg.sprint_speed), "back to normal, it sprints again")

	var hurt: Array = _entity_with_status(9103, StatusDef.INJURED)
	_drive(hurt[1], 50, true, false)
	var burst: float = Vector2((hurt[1] as SpaceTimeMovementComponent).get_predicted_state().vel.x,
		(hurt[1] as SpaceTimeMovementComponent).get_predicted_state().vel.z).length()
	_check(burst > cfg.sprint_speed * 1.4, "injured, just now: its burst carries it past its sprint (%.2f m/s)" % burst)
	for e: Array in [normal, down, hurt]:
		(e[0] as Node).free()
	await get_tree().process_frame


func _run_presentation() -> void:
	print("== status: the body, the tag ==")
	var ent := SpaceTimeEntity.new()
	get_tree().root.add_child(ent)
	ent.entity_id = 9201
	ent.collision_layer = 3
	ent.collision_mask = 5
	var plate_holder := Node3D.new()
	plate_holder.name = "Nameplate"
	ent.add_child(plate_holder)
	var comps := Node.new()
	comps.name = "Components"
	ent.add_child(comps)
	var plate := NameplateComponent.new()
	comps.add_child(plate)
	var presence := PresenceComponent.new()
	comps.add_child(presence)
	var st := StatusComponent.new()
	comps.add_child(st)
	ent._collect_components()
	plate.bind(ent, {&"player": _PlayerRow.new(9201)})
	presence.bind(ent, {&"player": _PlayerRow.new(9201)})
	st.bind(ent, {&"status_state": _StatusRow.new(9201, StatusDef.DOWNED)})
	await get_tree().process_frame
	_check(plate.shown_tag() == "Downed" and ent.visible, "downed: its tag says so, its body is there")
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9201, StatusDef.OUT, 2)))
	_check(not ent.visible and ent.collision_layer == 0 and plate.shown_tag() == "Out", "out: hidden, nothing collides with it")
	ent.set_hidden_by(&"offline", true)   # what PresenceComponent does when they leave
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9201, StatusDef.NORMAL, 3)))
	_check(not ent.visible and ent.hidden_reasons() == [&"offline"],
		"back to normal while also gone: still hidden (two reasons, neither undoes the other)")
	ent.set_hidden_by(&"offline", false)
	_check(ent.visible and ent.collision_layer == 3 and ent.collision_mask == 5 and plate.shown_tag() == "",
		"both over: shown, colliding as before, no tag")
	var heard: Array = []
	st.status_changed.connect(func(a: int, b: int) -> void: heard.append([a, b]))
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9201, StatusDef.INJURED, 4, 5000)))
	_check(heard == [[0, 1]] and st.seconds_left() > 4.0 and st.seconds_left() <= 5.0,
		"a change is heard once, with its countdown (%.1f s left)" % st.seconds_left())
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9201, StatusDef.INJURED, 4, 5000)))
	_check(heard.size() == 1, "the same row again is no news")
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9201, StatusDef.INJURED, 5)))
	_check(heard.size() == 2 and heard[1] == [1, 1], "the same status set again is (downed twice)")
	ent.queue_free()
	await get_tree().process_frame


## A player entity in the registry, bound, online, in a status.
func _registered(eid: int, status: int) -> SpaceTimeEntity:
	var ent := SpaceTimeEntity.new()
	get_tree().root.add_child(ent)
	ent.entity_id = eid
	var plate := NameplateComponent.new()
	ent.add_runtime_component(plate)
	var st := StatusComponent.new()
	ent.add_runtime_component(st)
	plate.bind(ent, {&"player": _PlayerRow.new(eid)})
	st.bind(ent, {&"status_state": _StatusRow.new(eid, status)})
	ent._is_bound = true
	EntityRegistry.register(eid, ent)
	return ent


func _run_spectate() -> void:
	print("== status: out, watching a teammate ==")
	var me: SpaceTimeEntity = _registered(9301, StatusDef.OUT)
	var a: SpaceTimeEntity = _registered(9302, StatusDef.NORMAL)
	var b: SpaceTimeEntity = _registered(9303, StatusDef.INJURED)
	var gone: SpaceTimeEntity = _registered(9304, StatusDef.ESCAPED)
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	me.add_child(rig)
	var st: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	st.is_local_authority = true
	_check(st.spectate_candidates() == [9302, 9303], "it may watch the two still playing, not the one who escaped, nor itself")
	st._keep_spectating()
	_check(st.spectating() == a and rig.following() == a, "it watches the first")
	st.spectate_next()
	_check(st.spectating() == b and rig.following() == b, "Jump: the next")
	st.spectate_next()
	_check(st.spectating() == a, "and round again")
	(a.find_component(StatusComponent) as StatusComponent).receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED,
		&"status_state", null, _StatusRow.new(9302, StatusDef.OUT, 2)))
	st._keep_spectating()
	_check(st.spectating() == b, "the one it watches goes out: it moves on to one still playing")
	st.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"status_state", null, _StatusRow.new(9301, StatusDef.NORMAL, 2)))
	_check(st.spectating() == null and rig.following() == null, "back in: its own view again")
	for e: SpaceTimeEntity in [me, a, b, gone]:
		EntityRegistry.unregister(e.entity_id)
		e.queue_free()
	await get_tree().process_frame


func _run_every_entity_has_one() -> void:
	print("== status: every entity has one ==")
	var p: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	p._collect_components()
	var n: int = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is StatusComponent).size()
	_check(n == 1, "an entity whose scene has none is given one (player.tscn: %d)" % n)
	p._collect_components()
	n = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is StatusComponent).size()
	_check(n == 1, "and only one, however often its components are gathered")
	p.free()
	_check(NetConfig.new().core_tables.has(&"status_state") and (_autoload("InterestManager").get(&"WORLD_TABLES") as Array).has(&"status_state"),
		"every client subscribes status_state, by world (the sidecar too: tests/sidecar_test.sh)")


func _wipe(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for sub: String in d.get_directories():
		_wipe(dir.path_join(sub))
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
