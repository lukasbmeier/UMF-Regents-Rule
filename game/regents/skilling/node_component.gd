class_name NodeComponent extends SpaceTimeComponent
## A GATHERING NODE, DRAWN (presentation only: the server decides everything). Which node it is comes from
## its `gather_node` row (a `NodeDef`: its look, picked by the entity's id so every client draws the same);
## whether it can be worked, from its status: Depleted (100) until the server lifts it. A tree tips over
## and leaves a stump; a rock crumbles to rubble; it grows (or rises) back when it comes back. Ore shows on
## a rock as coloured nuggets (where its model's ore layout puts them, else snapped onto its surface:
## `RegentsOreSpots`). A tree's trunk, or a rock's whole shape (`RegentsSolid`: owner, 2026-10-21, a rock
## three metres wide stopped you at three quarters of one), blocks the way while it stands; what is left
## does not.

const TABLE_NODE: StringName = &"gather_node"
const TABLE_STATUS: StringName = &"status_state"
const STATUS_DEPLETED: int = 100
const NUGGET: String = "res://game/regents/art/nature/Pebble_Round_1.gltf"
## How many nuggets a rock shows when its model has no layout.
const NUGGETS: int = 5

## It was worked out (true) or came back (false). For every client.
signal depleted_changed(depleted: bool)

var def: NodeDef = null
var depleted: bool = false
var _model: Node3D = null
var _left: MeshInstance3D = null
## What blocks the way while it stands: a tree's trunk, a rock's hulls. Off while worked out.
var solid: StaticBody3D = null
## The nuggets on it, in its model's space (tests read them).
var nuggets: Array[Node3D] = []
var _tween: Tween = null


func required_tables() -> Array[StringName]:
	return [TABLE_NODE, TABLE_STATUS]


func optional_tables() -> Array[StringName]:
	return [TABLE_STATUS]


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_NODE:
			if new != null:
				_set_def(NodeDef.by_id(int(new.get(&"def_id"))))
		TABLE_STATUS:
			_set_depleted(new != null and int(new.get(&"status")) == STATUS_DEPLETED)


func _visual() -> Node3D:
	return get_node_or_null(^"../../Visual") as Node3D


func is_rock() -> bool:
	return def != null and def.depleted == NodeDef.Depleted.RUBBLE


func _set_def(d: NodeDef) -> void:
	if d == def or d == null:
		return
	def = d
	var v: Node3D = _visual()
	if v == null:
		return
	if _model != null:
		_model.queue_free()
	var scene: PackedScene = null
	if not d.models.is_empty():
		scene = d.models[absi(entity_id) % d.models.size()]
		_model = scene.instantiate() as Node3D
		_model.scale = Vector3.ONE * d.model_scale
		v.add_child(_model)
	if _left == null:
		_left = MeshInstance3D.new()
		v.add_child(_left)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = d.depleted_color
	mat.roughness = 0.95
	if is_rock():
		var m: SphereMesh = SphereMesh.new()
		m.radius = 0.55
		m.height = 0.45
		_left.mesh = m
		_left.position = Vector3(0, 0.12, 0)
	else:
		var m: CylinderMesh = CylinderMesh.new()
		m.top_radius = 0.38
		m.bottom_radius = 0.48
		m.height = 0.45
		_left.mesh = m
		_left.position = Vector3(0, 0.22, 0)
	_left.material_override = mat
	if solid != null:
		solid.queue_free()
		solid = null
	if is_rock() and _model != null:
		solid = RegentsSolid.wrap(v, _model)
	else:
		# A tree: its trunk only (walking under the canopy is fine).
		solid = StaticBody3D.new()
		solid.name = "Solid"
		solid.collision_mask = 0
		var trunk := CollisionShape3D.new()
		var c: CylinderShape3D = CylinderShape3D.new()
		c.radius = 0.45 * d.model_scale
		c.height = 3.0
		trunk.shape = c
		trunk.position = Vector3(0, c.height * 0.5, 0)
		solid.add_child(trunk)
		v.add_child(solid)
	if _model != null and d.ore_color.a > 0.0:
		_add_ore(d.ore_color, scene)
	_show(depleted, false)


## Ore on the rock: nuggets of its colour where its model's layout puts them, else snapped onto its surface.
func _add_ore(color: Color, scene: PackedScene) -> void:
	var nugget: PackedScene = load(NUGGET) as PackedScene
	if nugget == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.35
	nuggets.clear()
	for spot: Transform3D in RegentsOreSpots.spots_for(scene, _model, NUGGETS, absi(entity_id)):
		var n: Node3D = nugget.instantiate() as Node3D
		n.name = "Ore%d" % (nuggets.size() + 1)
		n.transform = spot
		n.add_to_group(&"not_solid")
		for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
			mi.add_to_group(&"not_solid")
		_model.add_child(n)
		nuggets.append(n)


static func _aabb_of(n: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var box: AABB = n.global_transform.affine_inverse() * m.global_transform * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _set_depleted(d: bool) -> void:
	if d == depleted:
		return
	depleted = d
	_show(d, is_bound())
	depleted_changed.emit(d)


## Standing or worked out; `animate` plays the fall (or the crumble) and the return.
func _show(d: bool, animate: bool) -> void:
	if solid != null:
		solid.set_deferred(&"collision_layer", 0 if d else 1)
	if _left != null:
		_left.visible = d
	if _model == null:
		return
	if _tween != null:
		_tween.kill()
	var full: Vector3 = Vector3.ONE * (def.model_scale if def != null else 1.0)
	if not animate:
		_model.visible = not d
		_model.rotation = Vector3.ZERO
		_model.scale = full
		_model.position = Vector3.ZERO
		return
	_tween = create_tween()
	_model.visible = true
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	if d and not is_rock():
		# Timber: it tips over along its own facing.
		_tween.tween_property(_model, ^"rotation:x", deg_to_rad(88.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_model, ^"scale", full * 0.01, 0.35)
		_tween.tween_callback(func() -> void: _model.visible = false)
	elif d:
		# The rock crumbles into the ground.
		_tween.tween_property(_model, ^"scale", Vector3(full.x * 1.15, full.y * 0.2, full.z * 1.15), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(func() -> void: _model.visible = false)
	else:
		_model.scale = full * 0.15
		_tween.tween_property(_model, ^"scale", full, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
