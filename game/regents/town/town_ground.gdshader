// THE TOWN WORLD'S GROUND (2026-11-15, `town_world.gd`): grass in two greens with dry patches, dirt roads, cobbled
// squares, all code-made but the cobbles (the kit's `T_RoundRocks`). The roads and squares come from the world's
// layout: each road a segment (a.x, a.y, b.x, b.y), each square a box (center x, z, half x, z), in world meters.
shader_type spatial;

uniform vec4 grass_a : source_color = vec4(0.27, 0.42, 0.16, 1.0);
uniform vec4 grass_b : source_color = vec4(0.39, 0.5, 0.2, 1.0);
uniform vec4 dry : source_color = vec4(0.55, 0.5, 0.3, 1.0);
uniform vec4 dirt : source_color = vec4(0.45, 0.36, 0.25, 1.0);
uniform vec4 cobble_tint : source_color = vec4(0.75, 0.72, 0.68, 1.0);
uniform sampler2D cobble_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roads[48];
uniform int road_count = 0;
uniform float road_width = 4.0;
uniform vec4 squares[8];
uniform int square_count = 0;

varying vec3 v_world;

float g_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash(i), g_hash(i + vec2(1, 0)), f.x), mix(g_hash(i + vec2(0, 1)), g_hash(i + vec2(1, 1)), f.x), f.y);
}

float g_fbm(vec2 p) {
	return g_noise(p) * 0.55 + g_noise(p * 2.1 + 5.3) * 0.28 + g_noise(p * 4.3 + 1.7) * 0.17;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float n = g_fbm(p * 0.04);
	float n2 = g_fbm(p * 0.35 + 9.0);
	vec3 col = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.3, 0.7, n));
	col = mix(col, dry.rgb, smoothstep(0.62, 0.8, g_fbm(p * 0.015 + 3.0)) * 0.6);
	col *= 0.85 + 0.3 * n2;
	float rough = 0.95;
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	float road = 0.0;
	for (int i = 0; i < road_count; i++) {
		float d = seg_dist(p, roads[i].xy, roads[i].zw);
		road = max(road, 1.0 - smoothstep(road_width * 0.5 - 0.6 + n2 * 1.2, road_width * 0.5 + 1.2, d));
	}
	col = mix(col, dirt.rgb * (0.8 + 0.35 * n2), road);
	float paved = 0.0;
	for (int i = 0; i < square_count; i++) {
		vec2 q = abs(p - squares[i].xy) - squares[i].zw;
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		paved = max(paved, 1.0 - smoothstep(-0.5, 0.8 + n2, d));
	}
	if (paved > 0.0) {
		vec2 uv = p * 0.5;
		vec3 c = texture(cobble_tex, uv).rgb;
		float detail = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)) / 0.0753, 0.0, 3.0);
		col = mix(col, cobble_tint.rgb * detail * 0.35, paved);
		nrm = mix(nrm, texture(cobble_normal, uv).rgb, paved);
		rough = mix(rough, 0.85, paved);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = nrm;
}
