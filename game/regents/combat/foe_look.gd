class_name FoeLook extends SpaceTimeComponent
## A FOE'S OWN LOOK, on every foe (presentation only; Luke's F1, 2026-11-12: the archer is the warrior's model with
## a bow): what its `FoeDef` says of its look, put on its model once it is there. `hidden_meshes` are hidden (the
## archer's sword), `albedo` is laid over every mesh's own colors (the pack's other texture sets), and `held_scene`
## goes in its hand as a player's weapon does (`HeldItem`: the scene's grip says which hand). A foe whose FoeDef
## names none of these is left as its model is.

## What it holds, once it does (tests read it).
var held: HeldItem = null
## Whether its look has been put on.
var dressed: bool = false
var _foe: FoeDef = null


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_foe = FoeDef.by_kind(ent.definition.kind) if ent != null and ent.definition != null else null
	set_process(_foe != null)


func _process(_delta: float) -> void:
	if dressed or _foe == null or not is_bound():
		return
	var skel: Skeleton3D = SkillingLook.skeleton_of(entity)
	if skel == null:
		return   # its model is not there yet
	dress(skel, _foe)
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if held != null and ent != null:
		held.driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent
	dressed = true
	set_process(false)


## Put `foe`'s look on the model whose skeleton is `skel`.
func dress(skel: Skeleton3D, foe: FoeDef) -> void:
	for n: Node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if foe.hidden_meshes.has(StringName(mi.name)):
			mi.visible = false
			continue
		if foe.albedo == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var base: BaseMaterial3D = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat: BaseMaterial3D = base.duplicate() as BaseMaterial3D
			mat.albedo_texture = foe.albedo
			mi.set_surface_override_material(i, mat)
	if foe.held_scene != null and held == null:
		held = HeldItem.attach(skel, foe.held_scene)
