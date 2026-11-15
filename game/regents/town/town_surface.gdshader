// THE TOWN DYE (2026-11-15; the wardrobe's dye, for buildings): any kit surface in any color, its painting kept.
//
// The Medieval Village kit draws every building with about ten tiling textures whose color is nearly flat (the shape
// is in the normal maps). Here a texel becomes its SLOT's color times how much lighter or darker the painting is than
// the texture's mean (`mean_luma`, measured from the texture), so the grain, the cracks and the mortar stay. A color's
// alpha is how much (0 keeps the painting). `TownKit.SURFACES` says which kit material is which MODE and which slots:
//   0 one slot          (stone, masonry, brick, paving)
//   1 plaster           plaster over stone, the stone showing through where the kit's wear masks say (`wear`)
//   2 wood trim         the trim sheet's bands: light planks (a), dark timber (b), end grain, a stone strip (c);
//                       `uv2_wear` also weathers it by the kit's second UVs (MI_WoodTrim_Wear)
//   3 roof tiles        one slot, weathered by the kit's second UVs
//   4 glass             dark by day; lit at night, some windows and not others (`lit_share`)
//   5 metal             one slot, metallic
// Then each building's nudge and the weather (`town_weather.gdshaderinc`). Set by `TownKit` from a `SettlementStyle`.
shader_type spatial;
render_mode cull_back;

#include "res://game/regents/town/town_weather.gdshaderinc"

uniform int mode = 0;
uniform bool uv2_wear = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float mean_luma = 0.25;
uniform float metallic_value = 0.0;
group_uniforms under;
uniform sampler2D under_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float under_mean = 0.25;
uniform sampler2D top_wear_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D bottom_wear_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
group_uniforms dyes;
// a: the one slot, the plaster, the light planks, the roof, the glass, the metal. b: the stone under the plaster, the
// dark timber. c: the trim sheet's stone strip.
uniform vec4 dye_a : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 dye_b : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 dye_c : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// Which `SettlementStyle.SLOTS` a, b and c are (so each building's nudge moves a slot the same way everywhere).
uniform ivec3 slot_ids = ivec3(0, 1, 2);
// The trim sheet's band means: light planks, dark timber, end grain, the stone strip.
uniform vec4 band_means = vec4(0.16, 0.07, 0.28, 0.31);
group_uniforms;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 dyed(vec3 base, vec4 dye, float mean) {
	float detail = clamp(town_luma(base) / max(mean, 0.0005), 0.0, 3.0);
	return mix(base, dye.rgb * detail, dye.a);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 nrm = texture(normal_tex, UV).rgb;
	float rough = texture(rough_tex, UV).g;
	float metallic = metallic_value;
	vec3 col = base;
	vec3 glow = vec3(0.0);
	float w = town_wear();
	if (mode == 1) {
		vec3 plaster = town_jitter(dyed(base, dye_a, mean_luma), slot_ids.x);
		vec3 under_base = texture(under_tex, UV).rgb;
		vec3 under = town_jitter(dyed(under_base, dye_b, under_mean), slot_ids.y);
		float mask = clamp(texture(top_wear_tex, UV).r + texture(bottom_wear_tex, UV).r, 0.0, 1.0);
		// More wear lets the stone show further from the eaves and the foot; a little noise breaks the edge.
		float ragged = mask + (texture(noise_tex, UV * 1.7).r - 0.5) * 0.25;
		float shown = clamp((ragged - (1.0 - w * 0.75)) * 5.0, 0.0, 1.0);
		col = mix(plaster, under, shown);
		nrm = mix(nrm, texture(under_normal, UV).rgb, shown);
		rough = mix(rough, texture(under_rough, UV).g, shown);
	} else if (mode == 2) {
		float v = fract(UV.y);
		vec4 dye = vec4(0.0);
		float mean = 0.5;
		int slot = slot_ids.x;
		if (v < 0.312) {
			dye = dye_a; mean = band_means.x;
		} else if (v < 0.62) {
			dye = dye_b; mean = band_means.y; slot = slot_ids.y;
		} else if (v < 0.785) {
			bool light = fract(UV.x) < 0.5;
			dye = light ? dye_a : dye_b; mean = band_means.z; slot = light ? slot_ids.x : slot_ids.y;
		} else if (v < 0.955) {
			dye = dye_c; mean = band_means.w; slot = slot_ids.z;
		}
		col = town_jitter(dyed(base, dye, mean), slot);
		if (uv2_wear) {
			float m = texture(top_wear_tex, UV2).r;
			vec3 wc = wear_color.rgb * (0.75 + 0.5 * texture(noise_tex, UV).r);
			col = mix(col, wc * clamp(town_luma(base) / max(mean, 0.0005), 0.3, 2.0), clamp(m * w, 0.0, 1.0) * 0.85);
		}
	} else if (mode == 3) {
		col = town_jitter(dyed(base, dye_a, mean_luma), slot_ids.x);
		float m = texture(top_wear_tex, UV2).r;
		vec3 wc = wear_color.rgb * (0.7 + 0.6 * texture(noise_tex, UV).r);
		col = mix(col, wc * clamp(town_luma(base) / max(mean_luma, 0.0005), 0.3, 2.0), clamp(m * w, 0.0, 1.0) * 0.8);
	} else if (mode == 4) {
		float g = texture(albedo_tex, UV).r;
		col = mix(vec3(0.03, 0.04, 0.05), dye_a.a > 0.0 ? dye_a.rgb * 0.25 : vec3(0.14, 0.17, 0.2), g);
		rough = 0.08;
		metallic = 0.0;
		nrm = vec3(0.5, 0.5, 1.0);
		// One window lit and the next not: a cell of the building's front, by floor.
		vec3 cell = floor(v_world / vec3(2.0, 3.0, 2.0));
		float lit = step(town_hash(dot(cell, vec3(3.1, 17.3, 7.7)) + building_seed * 0.37), lit_share);
		glow = window_light.rgb * mix(0.25, 1.0, g) * 2.2 * night * lit;
	} else {
		col = town_jitter(dyed(base, dye_a, mean_luma), slot_ids.x);
	}
	if (mode != 4) {
		col = town_weather(col, rough);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	NORMAL_MAP = nrm;
	EMISSION = glow;
}
