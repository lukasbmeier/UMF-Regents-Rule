shader_type spatial;
// GENRE CODE. A small pond's surface: two scrolling normal maps for the wind, darker in the
// middle where it is deep, a pale band at the edge, and up to four expanding RIPPLES that
// `PondVisual.ripple()` starts — a bobber landing, a nibble, a fish leaving the water.
//
// Opaque on purpose. A transparent surface needs a bed under it, sorts badly against the rim and
// the other ponds, and reads worse at the size these are; depth is suggested by colour instead.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.035, 0.14, 0.25, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.13, 0.42, 0.50, 1.0);
uniform vec4 edge_color : source_color = vec4(0.55, 0.75, 0.72, 1.0);
/// The surface's radius in the mesh's own units. Colour and the edge band are measured from it.
uniform float radius = 1.2;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.55;
uniform float wave_speed = 0.035;
uniform float wave_strength = 0.4;
/// xy: ripple centre in the surface's local XZ. z: `now` when it started. w: strength (0 = none).
uniform vec4 ripples[4];
/// The pond's own clock, advanced by PondVisual. Not TIME: a script cannot read the shader's
/// clock, so a ripple's start could never be stamped in it.
uniform float now = 0.0;
uniform float ripple_speed = 0.55;
uniform float ripple_life = 2.4;

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

// A ring travelling outward from `r.xy`: its height, and how steep it is (for the normal).
vec2 ripple_wave(vec4 r, vec2 p) {
	if (r.w <= 0.0) {
		return vec2(0.0);
	}
	float age = now - r.z;
	if (age < 0.0 || age > ripple_life) {
		return vec2(0.0);
	}
	float d = distance(p, r.xy);
	float front = age * ripple_speed;
	float band = exp(-pow((d - front) * 7.0, 2.0));
	float fade = (1.0 - age / ripple_life) * r.w;
	float phase = (d - front) * 38.0;
	return vec2(sin(phase), cos(phase)) * band * fade;
}

void fragment() {
	float dist = length(local_xz);
	float t = clamp(dist / radius, 0.0, 1.0);

	vec2 uv = local_xz * wave_scale;
	vec3 na = texture(wave_a, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.6)).rgb;
	vec3 nb = texture(wave_b, uv * 1.7 - vec2(TIME * wave_speed * 0.7, -TIME * wave_speed)).rgb;
	vec3 n = normalize(mix(na, nb, 0.5) * 2.0 - 1.0);

	// Ripples bend the normal radially; the colour brightens a touch on each crest.
	float crest = 0.0;
	vec2 bend = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 w = ripple_wave(ripples[i], local_xz);
		vec2 dir = normalize(local_xz - ripples[i].xy + vec2(0.0001));
		bend += dir * w.y;
		crest += max(w.x, 0.0);
	}
	n.xy += bend * 0.9;
	NORMAL_MAP = normalize(vec3(n.xy * wave_strength, 1.0)) * 0.5 + 0.5;

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.0, 1.0, t));
	water = mix(water, edge_color.rgb, smoothstep(0.82, 1.0, t) * 0.55);
	water += vec3(0.12, 0.16, 0.16) * crest;
	ALBEDO = water;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	// A little light of its own, so a pond in shadow still reads as water and not as a hole.
	EMISSION = water * 0.12;
	// Fresnel: grazing views catch more sky.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(ALBEDO, vec3(0.6, 0.75, 0.85), fres * 0.5);
}
