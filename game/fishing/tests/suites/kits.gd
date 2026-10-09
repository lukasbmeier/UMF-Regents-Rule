extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `kits` suite (`-- --only=kits` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	_run_kit_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine

const LAKESIDE_ASSETS: String = "res://game/world/terrain/lakeside_assets.tres"
const NATURE_KIT: String = "res://game/world/kits/nature/"


## THE NATURE KIT, AS THE LAKESIDE DRAWS IT (DECISIONS #137, #141). Every model the terrain's
## instancer places, as imported: each leaf, petal and blade is FoliageMaterial's shader â€” cut-out
## exactly where the kit's own material was, opaque where it was not â€” and nothing else is. The
## import script does this, and editing the script reimports nothing, so this is what says a
## reimport happened. That the shader LIGHTS a back face is `tests/render_test.sh`: a headless
## run has no pixels.
func _run_kit_tests() -> void:
	print("== nature kit ==")
	var assets: Terrain3DAssets = load(LAKESIDE_ASSETS) as Terrain3DAssets
	_check(assets != null and assets.get_mesh_count() > 0, "the lakeside's instancer has its meshes")
	if assets == null:
		return
	var foliage: int = 0
	var solid: int = 0
	var wrong: PackedStringArray = PackedStringArray()
	for id: int in range(assets.get_mesh_count()):
		var ma: Terrain3DMeshAsset = assets.get_mesh_asset(id)
		var scene: PackedScene = ma.scene_file if ma != null else null
		if scene == null:
			wrong.append("mesh asset %d has no scene" % id)
			continue
		var source: String = scene.resource_path
		var gltf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source)) as Dictionary
		var modes: Dictionary[String, String] = {}
		for m: Variant in gltf.get("materials", []):
			var md: Dictionary = m as Dictionary
			modes[str(md.get("name", ""))] = str(md.get("alphaMode", "OPAQUE"))
		var root: Node = scene.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for i: int in range(mesh.get_surface_count()):
				var mat: Material = mesh.surface_get_material(i)
				var what: String = "%s: %s" % [source.get_file(), mat.resource_name if mat != null else "<none>"]
				if not FoliageMaterial.is_foliage(mat):
					solid += 1
					if not mat is StandardMaterial3D:
						wrong.append(what + " is not foliage, and not the kit's own material")
					continue
				foliage += 1
				var sm: ShaderMaterial = mat as ShaderMaterial
				var cut: bool = modes.get(mat.resource_name, "OPAQUE") != "OPAQUE"
				var want: Shader = FoliageMaterial.SHADER_CUTOUT if cut else FoliageMaterial.SHADER_OPAQUE
				if sm == null or sm.shader != want:
					wrong.append(what + " is %s, not the foliage shader (%s)" % [mat.get_class(), "cut-out" if cut else "opaque"])
				elif sm.get_shader_parameter(&"texture_albedo") == null:
					wrong.append(what + " lost its texture")
		root.free()
	print("   %d leaf and blade surfaces, %d solid ones" % [foliage, solid])
	_check(foliage > 50 and solid > 20, "the kit's models have both foliage and solid surfaces (%d, %d)" % [foliage, solid])
	_check(wrong.is_empty(), "every leaf, petal and blade the lakeside draws is the two-sided foliage shader, "
		+ "and nothing else is (reimport the Nature kit if not):
      " + "
      ".join(wrong))

	# The blended cherry blossom leaf is a cut-out (#137), at the kit's threshold for it.
	var cherry: PackedScene = load(NATURE_KIT + "CherryBlossom_1.gltf") as PackedScene
	var leaf: ShaderMaterial = null
	if cherry != null:
		var root: Node = cherry.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (n as MeshInstance3D).mesh
			for i: int in range(mesh.get_surface_count()):
				if mesh.surface_get_material(i) != null and mesh.surface_get_material(i).resource_name == "Leaves_CherryBlossom":
					leaf = mesh.surface_get_material(i) as ShaderMaterial
		root.free()
	_check(leaf != null and leaf.shader == FoliageMaterial.SHADER_CUTOUT
		and is_equal_approx(float(leaf.get_shader_parameter(&"alpha_scissor_threshold")), 0.5),
		"the cherry blossom's blended leaves are imported as a cut-out at 0.5")

	# The conversion carries every value the kit's foliage uses across, and refuses what it cannot.
	var std := StandardMaterial3D.new()
	std.resource_name = "Leaves_Test"
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	std.alpha_scissor_threshold = 0.2
	std.albedo_color = Color(0.9, 0.8, 0.7, 1.0)
	std.albedo_texture = PlaceholderTexture2D.new()
	std.vertex_color_use_as_albedo = true
	std.vertex_color_is_srgb = true
	std.roughness = 0.8
	std.metallic_specular = 0.3
	var conv: ShaderMaterial = FoliageMaterial.from_standard(std)
	_check(conv.shader == FoliageMaterial.SHADER_CUTOUT and conv.resource_name == "Leaves_Test"
		and conv.get_shader_parameter(&"albedo") == Color(0.9, 0.8, 0.7, 1.0)
		and conv.get_shader_parameter(&"texture_albedo") == std.albedo_texture
		and is_equal_approx(float(conv.get_shader_parameter(&"alpha_scissor_threshold")), 0.2)
		and bool(conv.get_shader_parameter(&"use_vertex_color")) and bool(conv.get_shader_parameter(&"vertex_color_is_srgb"))
		and is_equal_approx(float(conv.get_shader_parameter(&"roughness")), 0.8)
		and is_equal_approx(float(conv.get_shader_parameter(&"specular")), 0.3),
		"FoliageMaterial.from_standard carries the kit material's values across")
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(FoliageMaterial.from_standard(std).shader == FoliageMaterial.SHADER_OPAQUE, "an opaque blade stays opaque")
	std.normal_enabled = true
	_check(not FoliageMaterial.unsupported(std).is_empty(), "a leaf with a normal map is left as the kit made it")
	std.normal_enabled = false
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_check(not FoliageMaterial.unsupported(std).is_empty(), "and so is one still blended")
	var bark := StandardMaterial3D.new()
	bark.resource_name = "Bark_NormalTree"
	_check(not FoliageMaterial.is_foliage(bark) and FoliageMaterial.is_foliage(std),
		"bark is not foliage, and a leaf is")
