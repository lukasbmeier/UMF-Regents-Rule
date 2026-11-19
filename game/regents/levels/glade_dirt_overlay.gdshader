shader_type spatial;
// CAMP DIRT & SOIL OVERLAY FOR TERRAIN3D LEVELS (Step 115b): paints ragged trodden trails, station pads and bare
// tree/rock soil rings from `RegentsGroundPaint` onto the flat camp floor without modifying Terrain3D data.
// Transparent everywhere the mask is empty so Terrain3D grass shows straight through with zero seam.

render_mode diffuse_burley, specular_schlick_ggx, depth_draw_never;

uniform vec3 dirt_color : source_color = vec3(0.36, 0.29, 0.20);
uniform vec3 soil_color : source_color = vec3(0.19, 0.16, 0.10);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float patch_m = 46.0;
uniform float grain_m = 5.0;
uniform float ragged : hint_range(0.0, 1.0) = 0.55;
uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec2 mask_center = vec2(0.0, 0.0);
uniform float mask_extent_m = 128.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = (p - mask_center) / mask_extent_m + vec2(0.5);
	if (uv.x < 0.01 || uv.x > 0.99 || uv.y < 0.01 || uv.y > 0.99) {
		discard;
	}
	vec2 m = texture(mask, uv).rg;
	float big = texture(grain, p / patch_m).r;
	float fine = texture(grain, p / grain_m).r;
	float edge = ((fine - 0.5) * 0.7 + (big - 0.5) * 0.3) * ragged;
	float soil = smoothstep(0.30, 0.52, m.g + edge * step(0.02, m.g));
	float dirt = smoothstep(0.30, 0.52, m.r + edge * step(0.02, m.r));
	float alpha = clamp(max(soil, dirt), 0.0, 1.0);
	if (alpha < 0.01) {
		discard;
	}
	vec3 soil_c = soil_color * (0.85 + 0.3 * fine);
	vec3 dirt_c = dirt_color * (0.88 + 0.24 * fine);
	ALBEDO = mix(soil_c, dirt_c, clamp(dirt / max(alpha, 0.001), 0.0, 1.0));
	ALPHA = alpha;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
