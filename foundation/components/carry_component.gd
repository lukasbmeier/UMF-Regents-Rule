class_name CarryComponent extends SpaceTimeComponent
## CARRIED BY SOMEONE (FOUNDATION_SYSTEMS milestone 6, DECISIONS #228): while this entity's
## `attachment` row names a carrier, it is drawn at the carrier's carry point
## (`EntityDefinition.carry_offset`, turned with the carrier, and `carry_yaw_deg`), every frame,
## after its own movement has run: so it rides smoothly in the wolf's mouth on every screen, its own
## player's included (whose camera follows it there), and a client that joins later sees it so at once.
##
## It only draws. The server decides who carries whom (a genre's holds: pick up, stash) and keeps the
## carried entity's own row at its carrier (the module's tick), so where it IS agrees with where it is
## drawn; put down, the server's teleport row puts it back on its own feet. Every entity has one
## (`SpaceTimeEntity` adds it), as it has a status.

## Picked up, or put down (-1).
signal carrier_changed(carrier_id: int)

const TABLE: StringName = &"attachment"

var _carrier_id: int = -1


func required_tables() -> Array[StringName]:
	return [TABLE]


## Not carried: no row. Nobody waits for one.
func optional_tables() -> Array[StringName]:
	return [TABLE]


## What carries it (-1: nothing).
func carrier_id() -> int:
	return _carrier_id


func is_carried() -> bool:
	return _carrier_id >= 0


func _on_bound() -> void:
	# After its movement (which draws it where its own state says), so the carrier's place wins.
	process_physics_priority = 100
	process_priority = 100


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	var id: int = int(new.get(&"carrier_id")) if new != null and new.get(&"carrier_id") != null else -1
	if id == _carrier_id:
		return
	_carrier_id = id
	_follow()
	carrier_changed.emit(id)


func _physics_process(_delta: float) -> void:
	_follow()


func _process(_delta: float) -> void:
	_follow()


## Put it at its carrier's carry point now. Public for tests.
func _follow() -> void:
	if _carrier_id < 0 or entity == null:
		return
	var carrier: SpaceTimeEntity = EntityRegistry.get_entity(_carrier_id) as SpaceTimeEntity
	var me: SpaceTimeEntity = entity as SpaceTimeEntity
	if carrier == null or not is_instance_valid(carrier) or me == null or not carrier.is_inside_tree():
		return
	var at: Transform3D = carry_point(carrier)
	var body: Node3D = me.body if me.body != null else me
	if body.is_inside_tree():
		body.global_transform = at
	var visual: Node3D = body.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.position = Vector3.ZERO   # no correction glide: it is exactly where it is carried


## Where something `carrier` carries is drawn: its carry point, turned with it.
static func carry_point(carrier: SpaceTimeEntity) -> Transform3D:
	var body: Node3D = carrier.body if carrier.body != null else carrier
	var yaw: float = body.global_rotation.y
	var defn: EntityDefinition = carrier.definition
	var offset: Vector3 = defn.carry_offset if defn != null else Vector3(0, 0.8, -0.6)
	var turn: float = deg_to_rad(defn.carry_yaw_deg) if defn != null else 0.0
	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(Basis(Vector3.UP, yaw + turn), body.global_position + basis * offset)
