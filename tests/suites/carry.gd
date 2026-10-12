extends "res://tests/suite_base.gd"
## The `carry` suite (tests/test_runner.gd runs it; `-- --only=carry` runs it alone).
## ATTACH AND CARRY (DECISIONS #228, FOUNDATION_SYSTEMS milestone 6), the client's half: a carried
## entity is drawn at its carrier's carry point, turned with it, every frame, and back on its own when
## it is put down; every entity can be carried; every client subscribes. The module's half (the rows,
## the carried entity kept at its carrier, put down when its carrier goes): tests/integration_test.sh.



func run() -> void:
	await _run_follow()
	_run_everywhere()


class _AttachRow extends RefCounted:
	var entity_id: int = 0
	var world_id: int = 0
	var carrier_id: int = 0
	var socket: String = ""
	var since: int = 0
	var prev_status: int = 0
	func _init(eid: int, carrier: int) -> void:
		entity_id = eid
		carrier_id = carrier


func _entity(eid: int, defn: EntityDefinition) -> SpaceTimeEntity:
	var e: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	e.definition = defn
	get_tree().root.add_child(e)
	e.entity_id = eid
	for c: Node in e.get_node(^"Components").get_children():
		if c is LocalInputComponent:
			c.set_physics_process(false)   # nobody plays these
	EntityRegistry.register(eid, e)
	return e


func _run_follow() -> void:
	print("== carry: drawn at its carrier's carry point ==")
	var wolf_def := EntityDefinition.new()
	wolf_def.kind = 0
	wolf_def.carry_offset = Vector3(0.0, 0.5, -0.7)
	wolf_def.carry_yaw_deg = 90.0
	var wolf: SpaceTimeEntity = _entity(9901, wolf_def)
	var hen: SpaceTimeEntity = _entity(9902, EntityDefinition.new())
	wolf.global_position = Vector3(10, 0, 5)
	wolf.rotation.y = 0.0
	hen.global_position = Vector3(-3, 0, -3)
	var cc := CarryComponent.new()
	hen.add_runtime_component(cc)
	cc.bind(hen, {})
	_check(not cc.is_carried() and cc.carrier_id() == -1, "nothing carries it: not carried")
	var heard: Array[int] = []
	cc.carrier_changed.connect(func(id: int) -> void: heard.append(id))
	cc.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"attachment", null, _AttachRow.new(9902, 9901)))
	_check(cc.is_carried() and cc.carrier_id() == 9901 and heard == [9901], "picked up: carried by the wolf, and said so")
	cc._follow()
	_check(hen.global_position.is_equal_approx(Vector3(10.0, 0.5, 4.3)),
		"drawn at the wolf's carry point, 0.7 m ahead of it and 0.5 m up (%s)" % str(hen.global_position))
	_check(is_equal_approx(wrapf(hen.global_rotation.y, -PI, PI), PI / 2.0), "turned by the carry's own 90°")
	wolf.rotation.y = PI / 2.0   # the wolf turns to face -X
	cc._follow()
	_check(hen.global_position.is_equal_approx(Vector3(9.3, 0.5, 5.0)),
		"the wolf turns: its carry point turns with it, ahead of it again (%s)" % str(hen.global_position))
	wolf.global_position = Vector3(20, 1, 5)
	await get_tree().process_frame
	_check(hen.global_position.is_equal_approx(Vector3(19.3, 1.5, 5.0)), "it moves: the hen comes along, each frame (%s)" % str(hen.global_position))
	cc.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"attachment", _AttachRow.new(9902, 9901), null))
	_check(not cc.is_carried() and heard == [9901, -1], "put down: carried no more")
	wolf.global_position = Vector3(40, 0, 0)
	await get_tree().process_frame
	_check(hen.global_position.is_equal_approx(Vector3(19.3, 1.5, 5.0)), "and it stays where it was put down when the wolf goes on")
	_check(CarryComponent.carry_point(wolf).origin.is_equal_approx(Vector3(39.3, 0.5, 0.0)), "(the carry point, as anyone may ask for it)")
	for e: SpaceTimeEntity in [wolf, hen]:
		EntityRegistry.unregister(e.entity_id)
		e.queue_free()
	await get_tree().process_frame


func _run_everywhere() -> void:
	print("== carry: every entity can be carried, every client subscribes ==")
	var p: SpaceTimeEntity = (load(PLAYER_SCENE) as PackedScene).instantiate() as SpaceTimeEntity
	p._collect_components()
	var n: int = p.get_components().filter(func(c: SpaceTimeComponent) -> bool: return c is CarryComponent).size()
	_check(n == 1, "an entity whose scene has none is given one (player.tscn: %d)" % n)
	p.free()
	var world: Array = _autoload("InterestManager").get(&"WORLD_TABLES") as Array
	_check(NetConfig.new().core_tables.has(&"attachment") and world.has(&"attachment"), "every client subscribes attachment, by world")
	_check(EntityDefinition.new().carry_offset == Vector3(0.0, 0.8, -0.6), "a character's carry point unless it says: ahead of it, chest high")
