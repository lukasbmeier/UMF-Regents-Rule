class_name StationComponent extends SpaceTimeComponent
## A STATION, DRAWN (presentation only): which one it is comes from its `station` row (a `StationDef`'s
## key); its look is that def's pieces, a greybox body, and a glow (a furnace's fire). Its bulk blocks the
## way. What is made at it is its recipes' (`RecipeDef.at(key)`).

const TABLE_STATION: StringName = &"station"

var def: StationDef = null
var key: StringName = &""


func required_tables() -> Array[StringName]:
	return [TABLE_STATION]


func _on_row_updated(_table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if new == null:
		return
	var k: StringName = StringName(String(new.get(&"key")))
	if k == key:
		return
	key = k
	def = StationDef.by_key(k)
	_build()


## The recipes made here, in order.
func recipes() -> Array[RecipeDef]:
	return RecipeDef.at(key)


func _build() -> void:
	var v: Node3D = get_node_or_null(^"../../Visual") as Node3D
	if v == null or def == null:
		return
	for c: Node in v.get_children():
		c.queue_free()
	var extent: AABB = AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 1.0, 1.2))
	if def.body_size != Vector3.ZERO:
		var body: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = def.body_size
		body.mesh = box
		body.position = Vector3(0, def.body_size.y * 0.5, 0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = def.body_color
		mat.roughness = 0.95
		body.material_override = mat
		v.add_child(body)
		extent = AABB(Vector3(-def.body_size.x * 0.5, 0, -def.body_size.z * 0.5), def.body_size)
	for i: int in def.pieces.size():
		if def.pieces[i] == null:
			continue
		var piece: Node3D = def.pieces[i].instantiate() as Node3D
		piece.transform = def.piece_transforms[i] if i < def.piece_transforms.size() else Transform3D.IDENTITY
		v.add_child(piece)
	if def.glow_color.a > 0.0:
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = def.glow_color
		light.light_energy = 2.2
		light.omni_range = 4.0
		light.position = Vector3(0, def.body_size.y * 0.45, def.body_size.z * 0.5 + 0.15)
		v.add_child(light)
		var mouth: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(def.body_size.x * 0.5, def.body_size.y * 0.35)
		mouth.mesh = quad
		mouth.position = Vector3(0, def.body_size.y * 0.4, def.body_size.z * 0.5 + 0.01)
		var glow: StandardMaterial3D = StandardMaterial3D.new()
		glow.albedo_color = def.glow_color
		glow.emission_enabled = true
		glow.emission = def.glow_color
		glow.emission_energy_multiplier = 3.0
		mouth.material_override = glow
		v.add_child(mouth)
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var b: BoxShape3D = BoxShape3D.new()
	b.size = Vector3(maxf(extent.size.x, 0.8), 1.2, maxf(extent.size.z, 0.8))
	shape.shape = b
	shape.position = Vector3(0, 0.6, 0)
	blocker.add_child(shape)
	v.add_child(blocker)
