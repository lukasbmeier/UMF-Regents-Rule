// A RIPPLE IN THE AIR (the VFX lab, 2026-11-14): a shockwave or heat haze that bends what is behind it. Put on a
// ball (its rim bends most: a bubble swelling) or a flat disc (`radial`: a ring at `fx_wave` of its radius),
// softened by a noise. Draws only what is already on screen (the opaque world), bent.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D noise : hint_default_white, repeat_enable, filter_linear_mipmap;
// How far it bends (a share of the screen), how wide its band, and a faint tint (its alpha: how much).
uniform float strength : hint_range(0.0, 0.2) = 0.03;
uniform float band_width : hint_range(0.01, 1.0) = 0.2;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform bool radial = true;
uniform float wobble : hint_range(0.0, 1.0) = 0.3;

instance uniform float fx_time = 0.0;
instance uniform float fx_alpha = 1.0;
// Where a flat disc's ring is (0..1 of its radius).
instance uniform float fx_wave = 0.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// On a flat disc (`radial`) the band is a ring at `fx_wave` of its radius; on a ball it is its rim (a bubble).
	float band = 0.0;
	if (radial) {
		band = (1.0 - smoothstep(0.0, band_width * 0.5, abs(length(p) - fx_wave))) * (1.0 - smoothstep(0.95, 1.0, length(p)));
	} else {
		float rimv = 1.0 - abs(dot(NORMAL, VIEW));
		band = smoothstep(1.0 - band_width * 2.0, 0.85, rimv) * (1.0 - smoothstep(0.9, 1.0, rimv));
	}
	float n = texture(noise, UV * 3.0 + vec2(fx_time * 0.2, fx_time * 0.37)).r;
	vec2 dir = radial ? normalize(p + 0.0001) : vec2(0.0, 1.0);
	vec2 bend = (NORMAL.xy * 0.6 + dir * 0.4) * strength * band * mix(1.0, n * 2.0, wobble) * fx_alpha;
	vec3 behind = textureLod(screen_texture, SCREEN_UV + bend, 0.0).rgb;
	ALBEDO = mix(behind, tint.rgb * 2.0, tint.a * band * fx_alpha);
	ALPHA = clamp(band * fx_alpha * 4.0, 0.0, 1.0);
}
