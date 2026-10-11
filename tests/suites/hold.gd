extends "res://tests/suite_base.gd"
## The `hold` suite (tests/test_runner.gd runs it; `-- --only=hold` runs it alone).
## HOLD TO INTERACT (DECISIONS #209): the foundation's Help up as content; which press starts which
## hold (a genre's over the foundation's, presses told apart by doer and status, the clashes refused);
## the component that follows holds on an entity and the one it does (the bar moving between rows,
## done heard once, the doer's pose); the interact key held and let go; the prompt and its bar; every
## entity given a HoldComponent and every client subscribed. The server's side: tests/integration_test.sh.


func run() -> void:
	HoldDef.clear_cache()
	_run_content()
	await _run_genre()
	await _run_component()
	await _run_key_and_prompt()
	await _run_nearby()
	_run_every_entity_has_one()
	HoldDef.clear_cache()


class _HoldRow extends RefCounted:
	var hold_id: int = 0
	var entity_id: int = 0
	var world_id: int = 0
	var hold: int = 0
	var progress: float = 0.0
	var rate: float = 0.0
	var at: int = 0
	var doers: int = 1
	var state: int = 0
	func _init(p_id: int, eid: int, p_hold: int, p_progress: float, p_rate: float, ago_s: float = 0.0, p_doers: int = 1, p_state: int = 0) -> void:
		hold_id = p_id
		entity_id = eid
		hold = p_hold
		progress = p_progress
		rate = p_rate
		at = ClockSync.server_usec() - int(ago_s * 1_000_000.0)
		doers = p_doers
		state = p_state


class _MemberRow extends RefCounted:
	var entity_id: int = 0
	var world_id: int = 0
	var hold_id: int = 0
	var target_id: int = 0
	var hold: int = 0
	var since: int = 0
	var from: Vector3 = Vector3.ZERO
	func _init(eid: int, p_hold_id: int, target: int, p_hold: int) -> void:
		entity_id = eid
		hold_id = p_hold_id
		target_id = target
		hold = p_hold


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
	func _init(eid: int, st: int, p_serial: int = 1) -> void:
		entity_id = eid
		status = st
		serial = p_serial
		since = ClockSync.server_usec()


## An interaction component whose crosshair is on whatever the test says (no camera needed).
class _Aimed extends InteractionComponent:
	var aimed: int = -1
	func _raycast_target() -> int:
		return aimed


## Records the poses asked of it instead of playing them.
class _PoseRecorder extends AnimationDriverComponent:
	var held: StringName = &""
	var released: int = 0
	func hold_pose(semantic: StringName, _weight: float = 1.0, _at: float = -1.0, _while_moving: bool = false) -> void:
		held = semantic
	func release_pose() -> void:
		held = &""
		released += 1
	func _process(_delta: float) -> void:
		pass


func _help_up() -> HoldDef:
	return HoldDef.find(0, 0, StatusDef.DOWNED, 0)


func _run_content() -> void:
	print("== hold: the foundation's Help up, as content ==")
	var h: HoldDef = _help_up()
	_check(h != null and h.display_name == "Help up" and h.prompt == "Help up", "a press on a downed player starts Help up")
	_check(HoldDef.find(1, 0, StatusDef.DOWNED, 0) == h, "a downed NPC too")
	_check(HoldDef.find(0, 0, StatusDef.NORMAL, 0) == null, "nothing to hold on someone standing")
	_check(HoldDef.find(0, 1, StatusDef.DOWNED, 0) == null, "nor with another verb")
	_check(HoldDef.by_id(h.id) == h, "found by its id, as hold_progress names it")
	_check(is_equal_approx(h.rate(1), 0.25) and is_equal_approx(h.rate(2), 0.4) and is_equal_approx(h.rate(3), 0.5)
		and is_equal_approx(h.rate(6), 0.5) and h.rate(0) == 0.0,
		"4 s alone, 2.5 with two, 2 with three or more; nobody, nothing")
	_check(h.summary() == "Takes 4.0 s alone, 2.5 s with 2, 2.0 s with 3+", "its line in the Content panel: %s" % h.summary())
	var baked: Dictionary = h.to_bake()
	_check(baked["targets"] == [0, 1] and baked["doers"] == [] and baked["when"] == StatusDef.find(StatusDef.DOWNED).id
		and baked["then"] == StatusDef.find(StatusDef.NORMAL).id and baked["seconds_with"] == [4.0, 2.5, 2.0],
		"baked: the kinds it is done to, anyone may, while downed, back to normal: %s" % str(baked))
	_check(h.validate().is_empty(), "and nothing wrong with it: %s" % str(h.validate()))
	var bad := HoldDef.new()
	bad.display_name = "Bad"
	bad.seconds_with = PackedFloat32Array([0.0])
	var why: Array[String] = bad.validate()
	_check(why.any(func(s: String) -> bool: return s.contains("done to nothing"))
		and why.any(func(s: String) -> bool: return s.contains("more than 0 s"))
		and why.any(func(s: String) -> bool: return s.contains("no prompt")),
		"refused: done to nothing, a time of 0 s, no prompt (%d reasons)" % why.size())
	_check(h.why_no_workbench() != "" , "no bench for a hold, and it says why")


func _save_hold(dir: String, file: String, id: int, to: Array[EntityDefinition], by: Array[EntityDefinition], when: StatusDef) -> HoldDef:
	DirAccess.make_dir_recursive_absolute(dir)
	var h := HoldDef.new()
	h.id = id
	h.display_name = file.capitalize()
	h.prompt = h.display_name
	h.done_to = to
	h.done_by = by
	h.only_when = when
	h.seconds_with = PackedFloat32Array([8.0])
	ResourceSaver.save(h, dir.path_join(file + ".tres"))
	HoldDef.clear_cache()   # the game reads its holds once; content changing under it is a test's doing
	return load(dir.path_join(file + ".tres")) as HoldDef


func _run_genre() -> void:
	print("== hold: a genre's over the foundation's; presses told apart ==")
	var root: String = "user://hold_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["hens", "foxes"])
	HoldDef.clear_cache()
	var humanoid: EntityDefinition = load("res://foundation/content/character/humanoid.tres") as EntityDefinition
	var npc: EntityDefinition = load("res://foundation/content/character/npc.tres") as EntityDefinition
	var downed: StatusDef = StatusDef.find(StatusDef.DOWNED)
	var f_dir: String = root.path_join("foundation/content/hold")
	var hens: String = root.path_join("game/hens/content/hold")
	var foxes: String = root.path_join("game/foxes/content/hold")
	var base: HoldDef = _save_hold(f_dir, "help_up", 0, [humanoid, npc], [], downed)
	var hen_help: HoldDef = _save_hold(hens, "hen_help", 10000, [humanoid], [], downed)
	_check(HoldDef.find(0, 0, StatusDef.DOWNED, 0) == hen_help, "a downed player: the genre's hold, before the foundation's")
	_check(HoldDef.find(1, 0, StatusDef.DOWNED, 0) == base, "a downed NPC, which the genre's is not done to: still the foundation's")
	var all: Array[ContentDef] = ContentLibrary.items(&"hold")
	_check(hen_help.validate_with(all).is_empty(), "replacing the foundation's is allowed")
	# The same nest and key: a chicken (kind 0 here) lays, an NPC (kind 1) cracks.
	var lay: HoldDef = _save_hold(hens, "lay", 10001, [npc], [humanoid], null)
	var crack: HoldDef = _save_hold(hens, "crack", 10002, [npc], [npc], null)
	all = ContentLibrary.items(&"hold")
	_check(not lay.overlaps(crack) and lay.validate_with(all).is_empty(), "told apart by who does it")
	_check(HoldDef.find(1, 0, StatusDef.NORMAL, 0) == lay and HoldDef.find(1, 0, StatusDef.NORMAL, 1) == crack,
		"so one press lays and the other cracks")
	var sit: HoldDef = _save_hold(hens, "sit", 10003, [npc], [], null)
	all = ContentLibrary.items(&"hold")
	_check(sit.validate_with(all).any(func(s: String) -> bool: return s.contains("tell them apart")),
		"one genre with two holds one press could start is refused")
	var fox: HoldDef = _save_hold(foxes, "fox_help", 20000, [humanoid], [], null)
	all = ContentLibrary.items(&"hold")
	_check(fox.validate_with(all).any(func(s: String) -> bool: return s.contains("only one genre")),
		"two genres with one press are refused")
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	HoldDef.clear_cache()
	_wipe(root)
	await get_tree().process_frame


func _run_component() -> void:
	print("== hold: what is held on an entity, and what it holds ==")
	var h: HoldDef = _help_up()
	var ent := SpaceTimeEntity.new()
	get_tree().root.add_child(ent)
	ent.entity_id = 9601
	var pose := _PoseRecorder.new()
	ent.add_runtime_component(pose)
	var hc := HoldComponent.new()
	ent.add_runtime_component(hc)
	hc.bind(ent, {}, {&"hold_progress": [_HoldRow.new(71, 9601, h.id, 0.25, 0.5, 1.0), _HoldRow.new(72, 9601, 999, 0.1, 0.0)]})
	_check(hc.holds_on_me() == [71, 72], "two things held on it, both arriving at bind")
	_check(absf(hc.progress(71) - 0.75) < 0.02, "the bar moves between rows: a quarter a second ago at half a second each, now three quarters (%.3f)" % hc.progress(71))
	_check(is_equal_approx(hc.progress(72), 0.1) and hc.def_of(72) == null, "one not moving stays put; one this build lacks has no content")
	_check(hc.hold_id_for(h.id) == 71, "found by its hold")
	var changes: Array = []
	var finished: Array = []
	hc.hold_changed.connect(func(id: int) -> void: changes.append(id))
	hc.hold_finished.connect(func(id: int, hold: int) -> void: finished.append([id, hold]))
	hc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"hold_progress", null, _HoldRow.new(71, 9601, h.id, 1.0, 0.0, 0.0, 2, HoldComponent.DONE)))
	_check(finished == [[71, h.id]] and hc.progress(71) == 1.0 and hc.holds_on_me() == [72], "done: heard once, full, no longer being held")
	hc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"hold_progress", null, _HoldRow.new(71, 9601, h.id, 1.0, 0.0, 0.0, 2, HoldComponent.DONE)))
	_check(finished.size() == 1, "the same row again is no news")
	hc.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"hold_progress", _HoldRow.new(71, 9601, h.id, 1.0, 0.0), null))
	_check(hc.progress(71) == 0.0 and changes.count(71) == 3, "and gone (every change heard: %s)" % str(changes))

	# What it holds: its pose while it does, let go of once when it stops.
	hc.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"hold_member", null, _MemberRow.new(9601, 80, 9700, h.id)))
	_check(hc.is_holding() and int(hc.doing()["target_id"]) == 9700, "it holds Help up on 9700")
	await get_tree().process_frame
	_check(pose.held == h.pose and pose.released == 0, "and holds the hold's pose ('%s')" % pose.held)
	hc.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"hold_member", _MemberRow.new(9601, 80, 9700, h.id), null))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not hc.is_holding() and pose.held == &"" and pose.released == 1, "let go: the pose released, once (%d)" % pose.released)
	ent.queue_free()
	await get_tree().process_frame


## A bound entity in the registry: a definition (its kind), a status, holds, and for the local one
## an interaction component.
func _registered(eid: int, def_path: String, status: int, local: bool) -> SpaceTimeEntity:
	var ent := SpaceTimeEntity.new()
	ent.definition = load(def_path) as EntityDefinition
	get_tree().root.add_child(ent)
	ent.entity_id = eid
	ent.is_local_authority = local
	var st := StatusComponent.new()
	ent.add_runtime_component(st)
	st.bind(ent, {&"status_state": _StatusRow.new(eid, status)})
	var hc := HoldComponent.new()
	ent.add_runtime_component(hc)
	hc.bind(ent, {})
	if local:
		var ic := InteractionComponent.new()
		ent.add_runtime_component(ic)
		ic.bind(ent, {})
		ic.set_physics_process(false)
	ent._is_bound = true
	EntityRegistry.register(eid, ent)
	return ent


func _run_key_and_prompt() -> void:
	print("== hold: the key held and let go; the prompt and its bar ==")
	var h: HoldDef = _help_up()
	var me: SpaceTimeEntity = _registered(9801, "res://foundation/content/character/humanoid.tres", StatusDef.NORMAL, true)
	var down: SpaceTimeEntity = _registered(9802, "res://foundation/content/character/humanoid.tres", StatusDef.DOWNED, false)
	var up: SpaceTimeEntity = _registered(9803, "res://foundation/content/character/npc.tres", StatusDef.NORMAL, false)
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	_check(ic.hold_for(9802) == h and ic.hold_for(9803) == null, "the key holds on a downed player, presses on one standing")
	ic._set_target(9803)
	ic.press_interact()
	_check(not ic.is_holding_key(), "a press on someone standing is a press (interact), not a hold")
	ic._set_target(9802)
	ic.press_interact()
	_check(ic.is_holding_key(), "a press on the downed one begins holding")
	var req: ReducerRequest = ic.begin_hold(9802)
	_check(req != null and req.reducer_name == &"begin_interact" and req.args == [9802, 0], "asking the server: begin_interact(9802, 0)")
	var rel: ReducerRequest = ic.release_interact()
	_check(rel != null and rel.reducer_name == &"end_interact" and not ic.is_holding_key(), "the key let go: end_interact")
	_check(ic.release_interact() == null, "once")

	var s: Dictionary = HoldPrompt.state_for(me)
	_check(bool(s["visible"]) and String(s["text"]) == "Hold E: Help up" and float(s["progress"]) < 0.0,
		"looking at them: \"%s\", no bar yet" % s["text"])
	var on_down: HoldComponent = down.find_component(HoldComponent) as HoldComponent
	on_down.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"hold_progress", null, _HoldRow.new(91, 9802, h.id, 0.5, 0.0, 0.0, 1)))
	s = HoldPrompt.state_for(me)
	_check(is_equal_approx(float(s["progress"]), 0.5), "part done already: the bar shows it (%.2f)" % float(s["progress"]))
	(me.find_component(HoldComponent) as HoldComponent).receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"hold_member", null, _MemberRow.new(9801, 91, 9802, h.id)))
	on_down.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"hold_progress", null, _HoldRow.new(91, 9802, h.id, 0.5, 0.4, 0.0, 2)))
	s = HoldPrompt.state_for(me)
	_check(String(s["text"]) == "Help up  (2 together)" and float(s["progress"]) >= 0.5, "holding it: \"%s\", the bar filling" % s["text"])
	var prompt := HoldPrompt.new()
	get_tree().root.add_child(prompt)
	prompt.show_state(s)
	_check(prompt.visible and prompt.text() == "Help up  (2 together)" and prompt.bar_value() >= 0.5, "and drawn so")
	ic._set_target(9803)
	(me.find_component(HoldComponent) as HoldComponent).receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"hold_member", _MemberRow.new(9801, 91, 9802, h.id), null))
	prompt.show_state(HoldPrompt.state_for(me))
	_check(not prompt.visible, "nothing to hold where it looks: no prompt")
	prompt.queue_free()
	for e: SpaceTimeEntity in [me, down, up]:
		EntityRegistry.unregister(e.entity_id)
		e.queue_free()
	await get_tree().process_frame


func _run_nearby() -> void:
	print("== hold: the target in front, not only under the crosshair (DECISIONS #211, #213) ==")
	var me: SpaceTimeEntity = _registered(9811, "res://foundation/content/character/humanoid.tres", StatusDef.NORMAL, true)
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	me.global_position = Vector3.ZERO   # facing -Z (no camera, no input here: the body's own way)
	var front: SpaceTimeEntity = _registered(9812, "res://foundation/content/character/humanoid.tres", StatusDef.DOWNED, false)
	front.global_position = Vector3(0.3, 0.0, -1.5)
	ic.scan()
	_check(ic.get_target() == 9812, "a downed teammate 1.5 m in front is the target with no crosshair on them (%d)" % ic.get_target())
	_check(String(HoldPrompt.state_for(me)["text"]) == "Hold E: Help up", "and the prompt offers to help them up")
	front.global_position = Vector3(1.0, 0.0, -0.9)
	ic.scan()
	_check(ic.get_target() == 9812, "48 degrees off the front, inside the 120-degree arc: the target")
	front.global_position = Vector3(1.0, 0.0, -0.3)
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET, "73 degrees off, at the shoulder (outside the arc, a metre away): not the target")
	front.global_position = Vector3(0.0, 0.0, 1.0)
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET, "behind: not the target")
	front.global_position = Vector3(0.0, 0.0, -4.0)
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET, "out of reach (4 m, the reach is %.1f): not the target" % ic.range_m())
	var standing: SpaceTimeEntity = _registered(9813, "res://foundation/content/character/npc.tres", StatusDef.NORMAL, false)
	standing.global_position = Vector3(0.0, 0.0, -1.0)
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET, "someone standing in front, with nothing to do with them: not the target")
	ic.nearby_wanted = func(id: int) -> bool: return id == 9813
	ic.scan()
	_check(ic.get_target() == 9813, "unless a genre wants it offered (a nest, a gate)")
	ic.nearby_wanted = Callable()
	front.global_position = Vector3(-0.2, 0.0, -2.2)
	var near: SpaceTimeEntity = _registered(9814, "res://foundation/content/character/humanoid.tres", StatusDef.DOWNED, false)
	near.global_position = Vector3(0.6, 0.0, -1.2)
	ic.scan()
	_check(ic.get_target() == 9814, "two downed in front: the nearer")
	near.visible = false
	ic.scan()
	_check(ic.get_target() == 9812, "one that is hidden (out) is passed over")
	ic.targeting = InteractionComponent.Targeting.CROSSHAIR
	ic.scan()
	_check(ic.get_target() == InteractionComponent.NO_TARGET, "and with the crosshair only, nothing (none is under it)")
	ic.targeting = InteractionComponent.Targeting.AUTO
	# Not a person: a resource node (or a genre's own kind) in front is offered without a hold.
	var node_def := EntityDefinition.new()
	node_def.kind = 2
	var node := SpaceTimeEntity.new()
	node.definition = node_def
	get_tree().root.add_child(node)
	node.entity_id = 9815
	node._is_bound = true
	EntityRegistry.register(9815, node)
	near.visible = true
	near.global_position = Vector3(0.0, 0.0, 2.0)   # behind
	front.global_position = Vector3(0.0, 0.0, 2.5)
	node.global_position = Vector3(0.2, 0.0, -1.2)
	ic.scan()
	_check(ic.get_target() == 9815, "a resource node in front (no hold, not a person): the target, to use")
	EntityRegistry.unregister(9815)
	node.queue_free()
	var prop := StaticBody3D.new()
	prop.add_to_group(InteractionComponent.GROUP_INTERACTABLE)
	prop.set_meta(&"entity_id", 9816)
	get_tree().root.add_child(prop)
	prop.global_position = Vector3(-0.3, 0.0, -1.0)
	ic.scan()
	_check(ic.get_target() == 9816, "and a prop standing in for an entity (`interactable`), in front")
	prop.queue_free()
	await get_tree().process_frame
	for e: SpaceTimeEntity in [me, front, standing, near]:
		EntityRegistry.unregister(e.entity_id)
		e.queue_free()
	await get_tree().process_frame

	# THE CROSSHAIR HAS NO SAY IN THIRD PERSON (DECISIONS #214): on a downed teammate the character is
	# not facing, it offers nothing; in first person it goes first.
	var aimer := SpaceTimeEntity.new()
	aimer.definition = load("res://foundation/content/character/humanoid.tres") as EntityDefinition
	get_tree().root.add_child(aimer)
	aimer.entity_id = 9821
	aimer.is_local_authority = true
	var aim := _Aimed.new()
	aimer.add_runtime_component(aim)
	aim.bind(aimer, {})
	aim.set_physics_process(false)
	aimer._is_bound = true
	EntityRegistry.register(9821, aimer)
	aimer.global_position = Vector3.ZERO
	var behind: SpaceTimeEntity = _registered(9822, "res://foundation/content/character/humanoid.tres", StatusDef.DOWNED, false)
	behind.global_position = Vector3(1.2, 0.0, 0.6)   # beside and behind the character's front
	aim.aimed = 9822
	aim.scan()
	_check(aim.effective_targeting() == InteractionComponent.Targeting.NEARBY and aim.get_target() == InteractionComponent.NO_TARGET,
		"third person: the crosshair on a downed teammate the character is not facing offers nothing")
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	rig.config = CameraRigConfig.new()
	rig.config.first_person = true
	aimer.add_child(rig)
	aim.scan()
	_check(aim.effective_targeting() == InteractionComponent.Targeting.BOTH and aim.get_target() == 9822,
		"first person: the crosshair is where the character looks, and goes first")
	for e: SpaceTimeEntity in [aimer, behind]:
		EntityRegistry.unregister(e.entity_id)
		e.queue_free()
	await get_tree().process_frame


func _run_every_entity_has_one() -> void:
	print("== hold: every entity has one, every client subscribes ==")
	var p: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	p._collect_components()
	var n: int = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is HoldComponent).size()
	_check(n == 1, "an entity whose scene has none is given one (player.tscn: %d)" % n)
	p._collect_components()
	n = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is HoldComponent).size()
	_check(n == 1, "and only one, however often its components are gathered")
	p.free()
	var world: Array = _autoload("InterestManager").get(&"WORLD_TABLES") as Array
	_check(NetConfig.new().core_tables.has(&"hold_progress") and NetConfig.new().core_tables.has(&"hold_member")
		and world.has(&"hold_progress") and world.has(&"hold_member"),
		"every client subscribes hold_progress and hold_member, by world")


func _wipe(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for sub: String in d.get_directories():
		_wipe(dir.path_join(sub))
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
