// THE TOWN WORLD'S GROUND (2026-11-15, `town_world.gd`): grass in two greens with dry patches, dirt roads between the
// places, and inside them PAVED streets and squares in each place's own paving (`town_paving.gdshaderinc`: code-made
// stones, never a wall's texture; the color, mix and laying from that place's `SettlementStyle`). The roads, streets
// and squares come from the world's layout: a road or street a segment (a.x, a.y, b.x, b.y), a square a box (center
// x, z, half x, z), in world meters; a street or square names its place (0-3) in `street_place` / `square_place`.
shader_type spatial;

#include "res://game/regents/town/town_paving.gdshaderinc"

uniform vec4 grass_a : source_color = vec4(0.27, 0.42, 0.16, 1.0);
uniform vec4 grass_b : source_color = vec4(0.39, 0.5, 0.2, 1.0);
uniform vec4 dry : source_color = vec4(0.55, 0.5, 0.3, 1.0);
uniform vec4 dirt : source_color = vec4(0.45, 0.36, 0.25, 1.0);
uniform vec4 roads[48];
uniform int road_count = 0;
uniform float road_width = 4.0;
uniform vec4 streets[32];
uniform int street_place[32];
uniform int street_count = 0;
uniform float street_width = 7.0;
uniform vec4 squares[8];
uniform int square_place[8];
uniform int square_count = 0;
// Each place's paving: its stones' color, the second color (alpha its share), the laying (0 cobbles, 1 setts).
// Linear colors (`town_world.gd` converts the styles' sRGB).
uniform vec4 paving[4];
uniform vec4 paving_mix[4];
uniform int paving_pattern[4];

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
	float spec = 0.5;
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	float road = 0.0;
	for (int i = 0; i < road_count; i++) {
		float d = seg_dist(p, roads[i].xy, roads[i].zw);
		road = max(road, 1.0 - smoothstep(road_width * 0.5 - 0.6 + n2 * 1.2, road_width * 0.5 + 1.2, d));
	}
	vec3 dirt_col = dirt.rgb * (0.8 + 0.35 * n2);
	col = mix(col, dirt_col, road);
	// The paving: the strongest street or square here, and whose it is.
	float paved = 0.0;
	int place = 0;
	for (int i = 0; i < street_count; i++) {
		float d = seg_dist(p, streets[i].xy, streets[i].zw);
		float a = 1.0 - smoothstep(street_width * 0.5 - 0.3, street_width * 0.5 + 0.4 + n2 * 0.8, d);
		if (a > paved) {
			paved = a;
			place = street_place[i];
		}
	}
	for (int i = 0; i < square_count; i++) {
		vec2 q = abs(p - squares[i].xy) - squares[i].zw;
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		float a = 1.0 - smoothstep(-0.5, 0.8 + n2, d);
		if (a > paved) {
			paved = a;
			place = square_place[i];
		}
	}
	if (paved > 0.0) {
		float stone;
		float id;
		vec2 tilt;
		town_pave(p, paving_pattern[place], stone, id, tilt);
		town_pave_far(smoothstep(0.08, 0.3, length(fwidth(p))), stone, id, tilt);
		vec3 joint = mix(dirt_col * 0.45, paving[place].rgb * 0.3, 0.4);
		vec3 c = town_paving_color(paving[place].rgb, paving_mix[place], joint, stone, id);
		// Worn: a little dirt washed over the stones toward the paving's edges.
		c = mix(c, dirt_col * 0.8, (1.0 - paved) * 0.6 + n2 * 0.12);
		col = mix(col, c, paved);
		nrm = mix(nrm, vec3(0.5 + tilt * 0.25, 1.0), paved);
		rough = mix(rough, mix(1.0, 0.9, stone), paved);
		spec = mix(spec, 0.25, paved);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL_MAP = nrm;
}
