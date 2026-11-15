// THE TOWN'S WEATHER AND EACH BUILDING'S NUDGE (2026-11-15), shared by `town_surface.gdshader` and
// `town_leaves.gdshader`. Every uniform here comes from a `SettlementStyle` (`TownKit.apply_style`); the two
// instance uniforms come from each building (`TownKit.dress`: a seed from where it stands, the height of its foot).
// Code-made: no texture is generated here, only math on the kit's own.

group_uniforms weather;
uniform float wear : hint_range(0.0, 1.5) = 0.5;
uniform vec4 wear_color : source_color = vec4(0.42, 0.3, 0.12, 1.0);
uniform float moss : hint_range(0.0, 1.0) = 0.0;
uniform vec4 moss_color : source_color = vec4(0.2, 0.3, 0.08, 1.0);
uniform float grime : hint_range(0.0, 1.0) = 0.2;
uniform float grime_height : hint_range(0.2, 4.0) = 1.2;
uniform vec4 grime_color : source_color = vec4(0.45, 0.38, 0.3, 1.0);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
group_uniforms each_building;
uniform float jitter_hue : hint_range(0.0, 0.15) = 0.02;
uniform float jitter_value : hint_range(0.0, 0.5) = 0.1;
uniform float jitter_wear : hint_range(0.0, 1.0) = 0.3;
group_uniforms night;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec4 window_light : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float lit_share : hint_range(0.0, 1.0) = 0.7;
group_uniforms;

// Each building's: a number from where it stands (the same building always gets the same), and where its foot is.
instance uniform float building_seed = 0.0;
instance uniform float building_base = 0.0;

varying vec3 v_world;
varying vec3 v_wnormal;

float town_hash(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float town_hash3(vec3 p) {
	return town_hash(dot(p, vec3(1.0, 57.0, 113.0)));
}

float town_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = town_hash3(i);
	float n100 = town_hash3(i + vec3(1, 0, 0));
	float n010 = town_hash3(i + vec3(0, 1, 0));
	float n110 = town_hash3(i + vec3(1, 1, 0));
	float n001 = town_hash3(i + vec3(0, 0, 1));
	float n101 = town_hash3(i + vec3(1, 0, 1));
	float n011 = town_hash3(i + vec3(0, 1, 1));
	float n111 = town_hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float town_fbm(vec3 p) {
	return town_noise(p) * 0.6 + town_noise(p * 2.13 + 7.1) * 0.3 + town_noise(p * 4.7 + 3.3) * 0.1;
}

float town_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 town_rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 town_hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// This building's nudge to one slot's color: a little hue, a little light. Slot is `SettlementStyle.SLOTS`' index,
// so a building's plaster and its timber move independently.
vec3 town_jitter(vec3 col, int slot) {
	float h = town_hash(building_seed * 17.31 + float(slot) * 3.17 + 0.5);
	float v = town_hash(building_seed * 29.77 + float(slot) * 7.73 + 1.5);
	float s = town_hash(building_seed * 11.13 + float(slot) * 5.31 + 2.5);
	vec3 hsv = town_rgb2hsv(max(col, vec3(0.0)));
	hsv.x = fract(hsv.x + (h - 0.5) * 2.0 * jitter_hue);
	hsv.y = clamp(hsv.y * (1.0 + (s - 0.5) * jitter_value), 0.0, 1.0);
	hsv.z = max(hsv.z * (1.0 + (v - 0.5) * 2.0 * jitter_value), 0.0);
	return town_hsv2rgb(hsv);
}

// How worn this building is: the style's wear, nudged per building.
float town_wear() {
	return clamp(wear + (town_hash(building_seed * 3.91 + 9.5) - 0.5) * jitter_wear, 0.0, 1.5);
}

// Grime at the foot, moss on what faces up and low on the walls, the sun's fading, snow on what faces up.
// `rough` comes back changed too (wet moss, dry snow).
vec3 town_weather(vec3 col, inout float rough) {
	float up = v_wnormal.y;
	float h = v_world.y - building_base;
	float n = town_fbm(v_world * 0.55);
	float n2 = town_fbm(v_world * 1.9 + 11.0);
	float g = grime * (1.0 - smoothstep(0.0, grime_height, h)) * (0.55 + 0.45 * n2);
	col = mix(col, col * grime_color.rgb, clamp(g, 0.0, 1.0));
	float m_up = clamp(up, 0.0, 1.0) * smoothstep(0.35, 0.7, n + moss * 0.35);
	float m_low = (1.0 - smoothstep(0.0, 1.0 + moss, h)) * smoothstep(0.45, 0.75, n2 + moss * 0.25);
	float m = moss * clamp(m_up + m_low * 0.7, 0.0, 1.0);
	col = mix(col, moss_color.rgb * (0.6 + 0.6 * n2), m);
	rough = mix(rough, 0.95, m);
	float l = town_luma(col);
	col = mix(col, mix(vec3(l), col, 0.4) * 1.18 + 0.02, fade * 0.8);
	float s = snow * smoothstep(0.3, 0.7, up) * smoothstep(0.35, 0.55, n * 0.6 + snow * 0.6);
	col = mix(col, vec3(0.9, 0.93, 0.97), clamp(s, 0.0, 1.0));
	rough = mix(rough, 0.55, s);
	return col;
}
