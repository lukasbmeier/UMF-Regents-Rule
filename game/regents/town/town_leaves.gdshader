// THE TOWN'S VINES (2026-11-15): the kit's leaf cards (`MI_Vine`) in the settlement's foliage color, two shades
// broken by noise, each building's nudge, fading and snow as `town_surface.gdshader`. Cut out, both sides drawn.
shader_type spatial;
render_mode cull_disabled;

#include "res://game/regents/town/town_weather.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// a: the leaves' color (alpha how much; 0 keeps the kit's greens). b is unused, kept for `TownKit`'s one way of setting.
uniform vec4 dye_a : source_color = vec4(0.3, 0.4, 0.05, 0.0);
uniform vec4 dye_b : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 dye_c : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform ivec3 slot_ids = ivec3(10, 10, 10);

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 leaf = texture(albedo_tex, UV);
	vec3 kit_a = vec3(0.256, 0.398, 0.0);
	vec3 kit_b = vec3(0.423, 0.467, 0.006);
	vec3 a = mix(kit_a, dye_a.rgb, dye_a.a);
	vec3 b = mix(kit_b, dye_a.rgb * vec3(1.45, 1.2, 1.1), dye_a.a);
	float n = town_fbm(v_world * 1.3);
	vec3 col = town_jitter(mix(a, b, n) * (0.55 + 0.6 * leaf.r), slot_ids.x);
	float rough = 0.8;
	col = town_weather(col, rough);
	ALBEDO = col;
	ROUGHNESS = rough;
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
