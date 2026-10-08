@tool
extends EditorScenePostImport
## Post-import for the Quaternius kits.
##
## VILLAGE AND PROPS: swap each imported surface's material for the kit's own `.tres` of the same
## name. The kits' glTFs carry placeholder materials; the real ones are shaders with trim sheets
## that live in `<kit>/materials/`. Quaternius ship a script that does this (by Cat Prisbrey,
## CC0), one copy per kit, each hard-wired to `res://addons/quaternius/materials/`. Two kits in
## one project need two folders — both have an `MI_Brick.tres`, and they are different
## materials — so this one script works out WHICH kit a model belongs to from the file being
## imported:
##
##   res://game/world/kits/village/medievalvillagemegakit/Wall/X.gltf -> kits/village/materials/
##
## NATURE: the glTF's own materials are the real ones, with two changes. A BLENDED leaf (the
## cherry blossom's) sorts wrongly against its own tree, and casts its shadow as a solid card, so
## it is imported as a cut-out like every other leaf in the kit (DECISIONS #137). And every
## leaf, petal and grass blade is drawn by `FoliageMaterial`'s shader, which lights BOTH sides by
## the normal the kit authored: a double-sided StandardMaterial3D flips it on a back face, and a
## grass blade whose normal points up turns black from behind (DECISIONS #141).
##
## Editing this script does not reimport anything: Godot only reimports when a source file or its
## `.import` settings change. After an edit, select the kit's files and Reimport.
##
## A model outside a kit folder is left untouched.

const KITS_ROOT: String = "res://game/world/kits/"
## Where a blended leaf is cut, once it is a cut-out.
const CUTOUT_THRESHOLD: float = 0.5


func _post_import(scene: Node) -> Object:
	var source: String = get_source_file()
	var folder: String = _materials_folder(source)
	if not folder.is_empty():
		_swap(scene, folder)
	if _kit_of(source) == "nature":
		_cut_out_blends(scene)
		_two_sided_foliage(scene, source)
	return scene


static func _kit_of(source: String) -> String:
	if not source.begins_with(KITS_ROOT):
		return ""
	return source.substr(KITS_ROOT.length()).get_slice("/", 0)


static func _materials_folder(source: String) -> String:
	var kit: String = _kit_of(source)
	if kit.is_empty():
		return ""
	return KITS_ROOT + kit + "/materials/"


static func _swap(node: Node, folder: String) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat == null:
				continue
			var path: String = folder + mat.resource_name + ".tres"
			if ResourceLoader.exists(path):
				mi.mesh.surface_set_material(i, load(path) as Material)
	for child: Node in node.get_children():
		_swap(child, folder)


static func _cut_out_blends(node: Node) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i: int in range(mi.mesh.get_surface_count()):
			var mat: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				cut_out(mat)
	for child: Node in node.get_children():
		_cut_out_blends(child)


static func _two_sided_foliage(node: Node, source: String) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i: int in range(mi.mesh.get_surface_count()):
			var mat: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null or not FoliageMaterial.is_foliage(mat):
				continue
			var why: String = FoliageMaterial.unsupported(mat)
			if not why.is_empty():
				push_warning("quaternius_import: %s: %s is left as it was — %s" % [source, mat.resource_name, why])
				continue
			mi.mesh.surface_set_material(i, FoliageMaterial.from_standard(mat))
	for child: Node in node.get_children():
		_two_sided_foliage(child, source)


## A blended surface becomes a cut-out; anything else is left as the kit made it. Public so a
## test can hold it to the header.
static func cut_out(mat: StandardMaterial3D) -> void:
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = CUTOUT_THRESHOLD
