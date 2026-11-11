@tool
extends EditorScenePostImport
## SMOOTH SHADING FOR A LOW-POLY ANIMAL (Luke, 2026-11-10: the deer "smooth shading instead of low poly").
## Quaternius's animals are made flat-shaded: every face has its own corners, each with the face's normal. Set as
## an imported model's import script (its `.import`, `import_script/path`), this gives every corner the average of
## the faces round its point, so the body reads as one rounded surface; the shape, its colors, its skin and its
## clips are untouched. Corners of DIFFERENT surfaces (a material's edge: the nose, the hooves) stay apart, so those
## edges stay crisp. Runs only when the model is imported (the editor, `--import`); nothing of it runs in the game.


func _post_import(scene: Node) -> Object:
	_smooth_all(scene)
	return scene


func _smooth_all(node: Node) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh is ArrayMesh:
		mi.mesh = smoothed(mi.mesh as ArrayMesh)
	for child: Node in node.get_children():
		_smooth_all(child)


## `mesh` with every triangle surface's normals averaged over the corners that share a point (SurfaceTool's
## generate_normals joins corners by position within one smoothing group), tangents remade to match.
static func smoothed(mesh: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.blend_shape_mode = mesh.blend_shape_mode
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		var name: String = mesh.surface_get_name(i)
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES or mesh.get_blend_shape_count() > 0:
			# ASSUMPTION: Quaternius's animals have no blend shapes; one that has keeps its own normals.
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), mesh.surface_get_arrays(i))
		else:
			var st := SurfaceTool.new()
			st.create_from(mesh, i)
			st.deindex()
			st.set_smooth_group(0)
			st.generate_normals()
			if mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV:
				st.generate_tangents()
			st.index()
			st.commit(out)
		var at: int = out.get_surface_count() - 1
		out.surface_set_material(at, mat)
		out.surface_set_name(at, name)
	return out
