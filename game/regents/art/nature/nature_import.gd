@tool
extends EditorScenePostImport
## THE NATURE MODELS' LEAVES AND BLADES, LIT ON BOTH SIDES (PROGRESS step 59; ported from Fishing's
## `quaternius_import.gd`, the foundation's DECISIONS #137, #141, #146). Set as a nature model's import script (its
## `.import`, `import_script/path`; every model in this folder has it), this swaps each leaf, petal and grass-blade
## material for `FoliageMaterial`'s shader, which lights a back face by the normal the kit authored. A plain
## double-sided StandardMaterial3D flips that normal: grass turned black from behind and bushes and crowns had dark
## blotches. A BLENDED leaf is made a cut-out first (it sorts wrongly against its own tree, and casts its shadow as a
## solid card). Bark, rocks, mushrooms and pebbles are left as the kit made them.
##
## Runs only when a model is imported (the editor, `--import`); nothing of it runs in the game. Editing this script
## reimports NOTHING: select the models and Reimport. A NEW nature model needs this script set on it, or the regents
## suite's "no leaf is a plain material" fails and names it.

## Where a blended leaf is cut, once it is a cut-out.
const CUTOUT_THRESHOLD: float = 0.5


func _post_import(scene: Node) -> Object:
	_foliage(scene, get_source_file())
	return scene


static func _foliage(node: Node, source: String) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i: int in range(mi.mesh.get_surface_count()):
			var mat: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null or not FoliageMaterial.is_foliage(mat):
				continue
			cut_out(mat)
			var why: String = FoliageMaterial.unsupported(mat)
			if not why.is_empty():
				push_warning("nature_import: %s: %s is left as it was: %s" % [source, mat.resource_name, why])
				continue
			mi.mesh.surface_set_material(i, FoliageMaterial.from_standard(mat))
	for child: Node in node.get_children():
		_foliage(child, source)


## A blended material becomes a cut-out; anything else is left as the kit made it.
static func cut_out(mat: StandardMaterial3D) -> void:
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = CUTOUT_THRESHOLD
