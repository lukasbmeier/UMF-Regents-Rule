class_name TreeNodeComponent extends SpaceTimeComponent
## A TREE, DRAWN (presentation only: the server decides everything). Which tree it is comes from its
## `tree_node` row (a `TreeDef`: its look, picked by the entity's id so every client draws the same
## one); whether it stands, from its status: Felled (status 100) is a stump until the server lifts it.
## It falls over when felled and grows back up when it stands again. Its trunk blocks the way while it
## stands (a StaticBody under Visual); a stump does not.

const TABLE_TREE: StringName = &"tree_node"
const TABLE_STATUS: StringName = &"status_state"
const STATUS_FELLED: int = 100

## It fell (true) or stood again (false). For every client.
signal felled_changed(felled: bool)

var def: TreeDef = null
var felled: bool = false
var _model: Node3D = null
var _stump: MeshInstance3D = null
var _blocker: StaticBody3D = null
var _trunk: CollisionShape3D = null
var _tween: Tween = null


func required_tables() -> Array[StringName]:
	return [TABLE_TREE, TABLE_STATUS]


func optional_tables() -> Array[StringName]:
	return [TABLE_STATUS]


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_TREE:
			if new != null:
				_set_def(TreeDef.by_id(int(new.get(&"def_id"))))
		TABLE_STATUS:
			_set_felled(new != null and int(new.get(&"status")) == STATUS_FELLED)


func _visual() -> Node3D:
	return get_node_or_null(^"../../Visual") as Node3D


func _set_def(d: TreeDef) -> void:
	if d == def or d == null:
		return
	def = d
	var v: Node3D = _visual()
	if v == null:
		return
	if _model != null:
		_model.queue_free()
	if not d.models.is_empty():
		_model = d.models[absi(entity_id) % d.models.size()].instantiate() as Node3D
		_model.scale = Vector3.ONE * d.model_scale
		v.add_child(_model)
	if _stump == null:
		_stump = MeshInstance3D.new()
		var m: CylinderMesh = CylinderMesh.new()
		m.top_radius = 0.38
		m.bottom_radius = 0.48
		m.height = 0.45
		_stump.mesh = m
		_stump.position = Vector3(0, 0.22, 0)
		v.add_child(_stump)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = d.stump_color
	mat.roughness = 0.9
	_stump.material_override = mat
	if _blocker == null:
		_blocker = StaticBody3D.new()
		_blocker.collision_mask = 0
		_trunk = CollisionShape3D.new()
		var c: CylinderShape3D = CylinderShape3D.new()
		c.radius = 0.45
		c.height = 3.0
		_trunk.shape = c
		_trunk.position = Vector3(0, 1.5, 0)
		_blocker.add_child(_trunk)
		v.add_child(_blocker)
	_show(felled, false)


func _set_felled(f: bool) -> void:
	if f == felled:
		return
	felled = f
	_show(f, is_bound())
	felled_changed.emit(f)


## Standing or a stump; `animate` tips it over (or grows it back) instead of switching at once.
func _show(f: bool, animate: bool) -> void:
	if _trunk != null:
		_trunk.set_deferred(&"disabled", f)
	if _stump != null:
		_stump.visible = f
	if _model == null:
		return
	if _tween != null:
		_tween.kill()
	var full: Vector3 = Vector3.ONE * (def.model_scale if def != null else 1.0)
	if not animate:
		_model.visible = not f
		_model.rotation = Vector3.ZERO
		_model.scale = full
		return
	_tween = create_tween()
	if f:
		# Timber: it tips over, away from the axe's side we cannot know, so along its own facing.
		_model.visible = true
		_model.rotation = Vector3.ZERO
		_tween.tween_property(_model, ^"rotation:x", deg_to_rad(88.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_model, ^"scale", full * 0.01, 0.35)
		_tween.tween_callback(func() -> void: _model.visible = false)
	else:
		_model.visible = true
		_model.rotation = Vector3.ZERO
		_model.scale = full * 0.15
		_tween.tween_property(_model, ^"scale", full, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
