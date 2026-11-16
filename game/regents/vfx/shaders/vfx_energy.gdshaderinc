// THE ENERGY LOOK (the VFX lab, 2026-11-14): fire, frost, wind, arcane light on a mesh (a sphere, a shell, a cone,
// a slash's arc) or on a particle's mesh. Two noises scroll through it, one bending the other; the sum is the HEAT,
// read through a color RAMP (cold, dark on the left; hot, white on the right). A rim (fresnel) or a core can add heat.
// It EATS AWAY by the noise (`fx_erosion`, or a particle's color alpha), with a hot edge where it is eaten.
// Everything is made in code: the noises are NoiseTexture2D and the ramp a GradientTexture1D, no image files
// (Luke's "No AI disclosure", 2026-11-14: procedural first).
//
// Included by `vfx_energy_add.gdshader` (glows over what is behind) and `vfx_energy_mix.gdshader` (covers it:
// ice, smoke). The effect's script (`VfxEffect`) drives the `fx_` instance values each frame, so its slow motion and
// its shots are exact; a material's own values are the look, set in the Inspector.

uniform sampler2D noise_a : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_b : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D ramp : source_color, hint_default_white, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
// How many times each noise repeats over the mesh's UV, and how fast it moves (UV a second).
uniform vec2 tile_a = vec2(1.0, 1.0);
uniform vec2 scroll_a = vec2(0.0, -0.4);
uniform vec2 tile_b = vec2(2.0, 2.0);
uniform vec2 scroll_b = vec2(0.13, -0.8);
// How far noise A bends noise B (a curling, licking look past ~0.2).
uniform float warp : hint_range(0.0, 1.0) = 0.25;
// The heat: the noise's share, a constant added, and the rim's (> 0) or the core's (< 0) share.
uniform float noise_heat : hint_range(0.0, 2.0) = 1.0;
uniform float heat_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float fresnel_heat : hint_range(-2.0, 2.0) = 0.0;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.0;
// Heat added across V (a slash: its outer edge, V 1, hotter; < 0 its inner).
uniform float v_heat : hint_range(-2.0, 2.0) = 0.0;
// 0: smooth; 2 or more: the heat in that many flat bands (a painted, toon look).
uniform float bands : hint_range(0.0, 12.0, 1.0) = 0.0;
// Brightness: past 1 it glows (the level's glow).
uniform float intensity : hint_range(0.0, 16.0) = 3.0;
uniform float alpha_scale : hint_range(0.0, 2.0) = 1.0;
// The rim (fresnel) also fades it out where it faces away (a soft ball, not a disc): 0 off.
uniform float rim_fade : hint_range(0.0, 1.0) = 0.0;
// Eaten away: how soft the eaten edge is, how wide its hot line, and how hot.
uniform float erode_softness : hint_range(0.001, 0.5) = 0.06;
uniform float edge_width : hint_range(0.0, 0.5) = 0.08;
uniform float edge_heat : hint_range(0.0, 2.0) = 0.6;
// Faded at the ends of the mesh's UV: x the start (U), y the end (U), z the bottom (V 0), w the top (V 1).
uniform vec4 uv_fade = vec4(0.0);
// Faded toward the edge of a flat disc (a PlaneMesh, from its middle): the share of its radius that fades; 0 off.
uniform float radial_fade : hint_range(0.0, 1.0) = 0.0;
// Pushed out along its normal by noise A (m): a flame's lick, a boiling shell.
uniform float displace : hint_range(0.0, 1.0) = 0.0;
// Soft where it meets the ground or a body (m): 0 off.
uniform float depth_fade : hint_range(0.0, 2.0) = 0.0;
// A SWEEP along U (a slash): only the stretch behind its head shows, `sweep_tail` long, its head `sweep_heat` hotter.
uniform float sweep_tail : hint_range(0.01, 1.0) = 0.6;
uniform float sweep_heat : hint_range(0.0, 2.0) = 0.8;

// Set by the effect each frame (`VfxEffect`): its own clock (s), how eaten it is (0 whole, 1 gone), its fade, and
// its sweep's head along U (< 0: no sweep, all shows).
instance uniform float fx_time = 0.0;
instance uniform float fx_erosion = 0.0;
instance uniform float fx_alpha = 1.0;
instance uniform float fx_sweep = -1.0;
// Added to its heat (a blast cooling: from hot, > 0, to cold, < 0).
instance uniform float fx_heat = 0.0;

float vfx_noise(vec2 uv) {
	vec2 ua = uv * tile_a + scroll_a * fx_time;
	float na = texture(noise_a, ua).r;
	vec2 ub = uv * tile_b + scroll_b * fx_time + (na - 0.5) * warp;
	float nb = texture(noise_b, ub).r;
	return clamp(na * 0.45 + nb * 0.55, 0.0, 1.0);
}

// A MULTIMESH OF PIECES (a ring's shards, one draw for all, `VfxGroundRing`): `instanced` on, the mesh one unit
// piece, each instance's own erosion and heat in its custom data (r, g) and its true size in b (across) and a (tall),
// so it looks exactly as a piece of its own would: its normal and its push made as on a piece that size.
uniform bool instanced = false;
varying float vary_erosion;
varying float vary_heat;

void vertex() {
	vary_erosion = fx_erosion;
	vary_heat = fx_heat;
	vec3 size = vec3(1.0);
	vec3 n_real = NORMAL;
	if (instanced) {
		vary_erosion += INSTANCE_CUSTOM.r;
		vary_heat += INSTANCE_CUSTOM.g;
		size = max(vec3(INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a, INSTANCE_CUSTOM.b), vec3(0.0001));
		n_real = normalize(NORMAL / size);
	}
	if (displace > 0.0) {
		vec2 ua = UV * tile_a + scroll_a * fx_time;
		float n = textureLod(noise_a, ua, 0.0).r;
		VERTEX += n_real * (n - 0.35) * displace / size;
	}
	if (instanced) {
		// The engine turns an instance's normal by its basis as it is (right only for an even scale): undo the stretch.
		mat3 m = mat3(MODEL_MATRIX);
		NORMAL = normalize(inverse(transpose(m) * m) * NORMAL);
	}
}

void fragment() {
	float n = vfx_noise(UV);
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);
	float shape = 1.0;
	if (uv_fade.x > 0.0) { shape *= smoothstep(0.0, uv_fade.x, UV.x); }
	if (uv_fade.y > 0.0) { shape *= smoothstep(1.0, 1.0 - uv_fade.y, UV.x); }
	if (uv_fade.z > 0.0) { shape *= smoothstep(0.0, uv_fade.z, UV.y); }
	if (uv_fade.w > 0.0) { shape *= smoothstep(1.0, 1.0 - uv_fade.w, UV.y); }
	if (radial_fade > 0.0) { shape *= 1.0 - smoothstep(1.0 - radial_fade, 1.0, length(UV * 2.0 - 1.0)); }
	float head = 0.0;
	if (fx_sweep >= 0.0) {
		float behind = fx_sweep - UV.x;
		shape *= step(0.0, behind) * (1.0 - smoothstep(0.0, sweep_tail, behind));
		head = 1.0 - smoothstep(0.0, sweep_tail * 0.25, behind);
	}
	// Eaten away: the noise (thinned toward the shape's edges) under a threshold that climbs with the erosion.
	float er = max(vary_erosion, 1.0 - COLOR.a);
	float value = n * shape;
	float th = er * (1.0 + erode_softness) - erode_softness;
	float mask = smoothstep(th, th + erode_softness, value);
	float edge = (er > 0.001) ? 1.0 - smoothstep(th + erode_softness, th + erode_softness + edge_width, value) : 0.0;
	float heat = n * noise_heat + heat_bias + vary_heat + rim * fresnel_heat + edge * edge_heat + head * sweep_heat + UV.y * v_heat;
	heat = clamp(heat, 0.0, 1.0);
	if (bands >= 2.0) {
		heat = floor(heat * bands + 0.5) / bands;
	}
	vec4 rc = texture(ramp, vec2(heat, 0.5));
	float a = rc.a * mask * min(shape * 2.0, 1.0) * fx_alpha * alpha_scale;
	if (rim_fade > 0.0) {
		a *= mix(1.0, facing, rim_fade);
	}
	if (depth_fade > 0.0) {
		float d = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 behind_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		behind_view.xyz /= behind_view.w;
		a *= clamp((VERTEX.z - behind_view.z) / depth_fade, 0.0, 1.0);
	}
	ALBEDO = rc.rgb * COLOR.rgb * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
