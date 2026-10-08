class_name FoliageMaterial extends RefCounted
## The Nature kit's leaves and blades as `nature_foliage.gdshader`: the kit's own material values,
## lit on both sides by the kit's own normals (DECISIONS #141).
##
## Called by `quaternius_import.gd` as each Nature model is imported. Runtime-safe (no editor
## classes), so a test or a render tool can convert a material exactly as the import did.

const SHADER_CUTOUT: Shader = preload("res://game/world/kits/nature_foliage.gdshader")
const SHADER_OPAQUE: Shader = preload("res://game/world/kits/nature_foliage_opaque.gdshader")


## A foliage material, by the kit's names: the grass blades, the petals and every leaf. Bark,
## rocks, mushrooms and path stones are solid, and a double-sided solid is lit correctly already.
static func is_foliage(mat: Material) -> bool:
	if mat == null:
		return false
	var n: String = mat.resource_name
	return n == "Grass" or n == "Flowers" or n == "Leaves" or n.begins_with("Leaves_")


## Why `from_standard` cannot carry this material across, or "" when it can. The shader does
## only what the kit's foliage uses; anything more is left as the kit made it rather than drawn
## wrong.
static func unsupported(mat: StandardMaterial3D) -> String:
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			and mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return "blended (cut it out first)"
	if mat.normal_enabled or mat.emission_enabled or mat.rim_enabled or mat.clearcoat_enabled \
			or mat.backlight_enabled or mat.subsurf_scatter_enabled or mat.ao_enabled:
		return "uses a feature the foliage shader does not"
	if mat.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return "not per-pixel shaded"
	if mat.uv1_scale != Vector3.ONE or mat.uv1_offset != Vector3.ZERO or mat.uv1_triplanar:
		return "moves its UVs"
	if mat.metallic_texture != null or mat.roughness_texture != null:
		return "has metallic/roughness maps"
	return ""


## The foliage shader with `mat`'s values. The cut-out variant for a cut-out material, the opaque
## one otherwise.
static func from_standard(mat: StandardMaterial3D) -> ShaderMaterial:
	var cutout: bool = mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var out := ShaderMaterial.new()
	out.resource_name = mat.resource_name
	out.shader = SHADER_CUTOUT if cutout else SHADER_OPAQUE
	out.set_shader_parameter(&"albedo", mat.albedo_color)
	out.set_shader_parameter(&"texture_albedo", mat.albedo_texture)
	out.set_shader_parameter(&"alpha_scissor_threshold", mat.alpha_scissor_threshold)
	out.set_shader_parameter(&"use_vertex_color", mat.vertex_color_use_as_albedo)
	out.set_shader_parameter(&"vertex_color_is_srgb", mat.vertex_color_is_srgb)
	out.set_shader_parameter(&"roughness", mat.roughness)
	out.set_shader_parameter(&"specular", mat.metallic_specular)
	out.set_shader_parameter(&"metallic", mat.metallic)
	out.render_priority = mat.render_priority
	return out
