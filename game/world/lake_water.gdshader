shader_type spatial;
// GENRE CODE. The lake's surface.
//
// It reads what is BEHIND it: the depth buffer says how much water lies between the surface and
// the lakebed at each pixel, and the screen texture is the lakebed itself. Shallow water shows
// the bed through a tint, deep water goes dark, and where the terrain is about to break the
// surface there is foam — so the shoreline draws itself wherever the terrain puts it, with no
// mesh cut to fit.
//
// Ripples are the pond's system scaled up: eight rings, started by `LakeWater.ripple()` from
// things that happened (a float landing, a fish breaking the surface) and aged on the lake's own
// clock, `now`, because a script cannot read the shader's TIME.
//
// THE WATER'S COLOUR IS ITS DEPTH (DECISIONS #150): how far DOWN the bed is — turquoise shallows,
// teal-blue by ~2.5 m, navy by ~8.5 m, darker still in the Deep Hole — blended stop to stop. It
// was the length of the LINE OF SIGHT through the water, and from a player's camera, looking
// across the lake, that is long everywhere past the first few metres: the whole lake read as one
// flat blue, and the shallows and the drop-offs, where the fish are, could not be told apart. The
// line of sight still decides how much of the bed shows through.
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.24, 0.66, 0.60, 1.0);
uniform vec4 mid_color : source_color = vec4(0.08, 0.40, 0.49, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.17, 0.30, 1.0);
uniform vec4 abyss_color : source_color = vec4(0.015, 0.08, 0.17, 1.0);
/// Metres of water where each colour has fully taken over. The lake bake's own spread: a tenth of
/// it is under 0.7 m, half under 3.1 m, a tenth past 8.3 m, and the Deep Hole goes to 14 m.
uniform float mid_depth = 2.5;
uniform float deep_depth = 8.5;
uniform float abyss_depth = 13.0;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.95, 1.0);
/// Per metre of water: how fast it goes from clear to deep.
uniform float murk = 0.32;
uniform float foam_width = 0.55;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 0.07;
uniform float wave_speed = 0.018;
uniform float wave_strength = 0.45;
uniform float refraction = 0.035;
/// xy: world XZ of the ring's centre. z: `now` when it started. w: strength (0 = none).
uniform vec4 ripples[8];
uniform float now = 0.0;
uniform float ripple_speed = 0.9;
uniform float ripple_life = 3.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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
	float band = exp(-pow((d - front) * 4.0, 2.0));
	float fade = (1.0 - age / ripple_life) * r.w;
	float phase = (d - front) * 22.0;
	return vec2(sin(phase), cos(phase)) * band * fade;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	vec3 na = texture(wave_a, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.7)).rgb;
	vec3 nb = texture(wave_b, uv * 1.9 - vec2(TIME * wave_speed * 0.8, -TIME * wave_speed)).rgb;
	vec3 n = normalize(mix(na, nb, 0.5) * 2.0 - 1.0);

	float crest = 0.0;
	vec2 bend = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec2 w = ripple_wave(ripples[i], world_pos.xz);
		bend += normalize(world_pos.xz - ripples[i].xy + vec2(0.0001)) * w.y;
		crest += max(w.x, 0.0);
	}
	n.xy += bend * 0.8;
	NORMAL_MAP = normalize(vec3(n.xy * wave_strength, 1.0)) * 0.5 + 0.5;

	// How much water is between this pixel of surface and whatever is behind it.
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 behind_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	behind_view.xyz /= behind_view.w;
	float thickness = max(-behind_view.z + VERTEX.z, 0.0);
	float deep = 1.0 - exp(-thickness * murk);
	// How far DOWN the bed is: the colour. (Past the far plane there is no bed: that is deep.)
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(behind_view.xyz, 1.0)).xyz;
	float depth_m = max(world_pos.y - bed_world.y, 0.0);

	vec2 ruv = SCREEN_UV + n.xy * refraction * clamp(thickness, 0.0, 1.0);
	vec3 bed = texture(screen_tex, ruv).rgb;
	vec3 water = mix(shallow_color.rgb, mid_color.rgb, smoothstep(mid_depth * 0.15, mid_depth, depth_m));
	water = mix(water, deep_color.rgb, smoothstep(mid_depth, deep_depth, depth_m));
	water = mix(water, abyss_color.rgb, smoothstep(deep_depth, abyss_depth, depth_m));
	vec3 col = mix(bed * mix(vec3(1.0), shallow_color.rgb * 1.6, 0.6), water, clamp(deep * 1.15, 0.0, 1.0));
	float foam = 1.0 - smoothstep(0.0, foam_width, thickness);
	col = mix(col, foam_color.rgb, foam * 0.55);
	col += vec3(0.10, 0.13, 0.13) * crest;

	ALBEDO = col;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
