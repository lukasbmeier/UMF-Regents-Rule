// A CIRCLE ON THE GROUND (the VFX lab, 2026-11-14): a spell's magic circle or a foe's warning, drawn on a flat
// PlaneMesh lying on the ground. An outer ring, an inner ring, a band of RUNES (each one made from a hash of its
// place: strokes between the points of a 3 x 3 grid, never an image), ticks, and a FILL that grows from the middle
// out (a warning filling as its blow comes: `fx_fill`). Its lines can be broken by a moving noise (wisps).
// Radii are a share of the plane's half width (1: its edge). Nothing here is an image file.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 ring_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 rune_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.25, 0.55, 1.0, 0.25);
// How bright the lines are: past 1 they glow (the level's glow).
uniform float glow : hint_range(0.0, 16.0) = 3.0;
// A dark ground beneath the whole circle, so it reads on bright grass (its opacity).
uniform float shade : hint_range(0.0, 1.0) = 0.0;
uniform float ring_radius : hint_range(0.0, 1.0) = 0.95;
uniform float ring_width : hint_range(0.0, 0.3) = 0.035;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.62;
uniform float inner_width : hint_range(0.0, 0.3) = 0.015;
// The rune band, between two radii; how many runes round it, how thick their strokes, which set (any number), how
// fast it turns (radians a second; < 0 the other way).
uniform float rune_inner : hint_range(0.0, 1.0) = 0.68;
uniform float rune_outer : hint_range(0.0, 1.0) = 0.88;
uniform float rune_count : hint_range(0.0, 64.0, 1.0) = 14.0;
uniform float rune_stroke : hint_range(0.01, 0.4) = 0.1;
uniform float rune_seed = 3.0;
uniform float rune_spin = 0.35;
// Ticks inside the outer ring: how many (0: none) and how long.
uniform float ticks : hint_range(0.0, 128.0, 1.0) = 0.0;
uniform float tick_length : hint_range(0.0, 0.3) = 0.05;
// The fill's bright front line, and how far its brightness falls inward.
uniform float fill_front : hint_range(0.0, 0.3) = 0.05;
// Wisps: how much the noise breaks the lines (0: clean), its size, and its drift.
uniform float wisp : hint_range(0.0, 1.0) = 0.3;
uniform float wisp_tile = 2.0;
uniform vec2 wisp_scroll = vec2(0.04, 0.09);

// Set by the effect each frame (`VfxEffect`): its clock (s), its fade, how far round the circle is drawn (0..1, it
// draws itself), the fill's radius (< 0: no fill), and how eaten away by the noise it is.
instance uniform float fx_time = 0.0;
instance uniform float fx_alpha = 1.0;
instance uniform float fx_draw = 1.0;
instance uniform float fx_fill = -1.0;
instance uniform float fx_erosion = 0.0;

const float TAU_ = 6.28318530718;

float line_band(float r, float radius, float width, float aa) {
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + aa, abs(r - radius));
}

float hash11(float x) {
	return fract(sin(x * 127.1 + rune_seed * 311.7) * 43758.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// One rune: strokes between the points of a 3 x 3 grid, each kept or not by a hash of the rune's number. A stem
// always; at least two more.
float rune(vec2 p, float id) {
	vec2 g[9] = vec2[](vec2(-0.22, -0.34), vec2(0.0, -0.34), vec2(0.22, -0.34),
		vec2(-0.22, 0.0), vec2(0.0, 0.0), vec2(0.22, 0.0),
		vec2(-0.22, 0.34), vec2(0.0, 0.34), vec2(0.22, 0.34));
	float d = seg(p, g[1], g[7]);
	int picked = 0;
	for (int i = 0; i < 10; i++) {
		float h = hash11(id * 13.0 + float(i) * 1.37);
		if (h > 0.62 || (i >= 8 && picked < 2)) {
			int a = int(floor(hash11(id * 7.0 + float(i) * 3.1) * 8.99));
			int b = int(floor(hash11(id * 5.0 + float(i) * 9.7) * 8.99));
			if (a != b && !((a == 1 && b == 7) || (a == 7 && b == 1))) {
				d = min(d, seg(p, g[a], g[b]));
				picked++;
			}
		}
	}
	return d;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x) / TAU_ + 0.5;
	float aa = fwidth(r) * 1.5;
	float n = texture(noise, UV * wisp_tile + wisp_scroll * fx_time).r;
	float broken = mix(1.0, smoothstep(0.25, 0.75, n) * 1.5, wisp);
	float drawn = step(ang, fx_draw);
	float disc = 1.0 - smoothstep(1.0 - aa * 2.0, 1.0, r);

	float lines = max(line_band(r, ring_radius, ring_width, aa), line_band(r, inner_radius, inner_width, aa));
	if (ticks > 0.0) {
		float k = abs(fract(ang * ticks + 0.5) - 0.5) / ticks * TAU_ * r;
		float top = ring_radius - ring_width * 0.5;
		float in_band = step(top - tick_length, r) * step(r, top);
		lines = max(lines, in_band * (1.0 - smoothstep(0.006, 0.006 + aa, k)));
	}
	lines *= drawn * broken;

	float runes = 0.0;
	if (rune_count > 0.0 && rune_outer > rune_inner) {
		float ra = fract(ang + rune_spin * fx_time / TAU_);
		float cell = floor(ra * rune_count);
		float h = rune_outer - rune_inner;
		float mid = (rune_outer + rune_inner) * 0.5;
		float aspect = TAU_ * mid / rune_count / h;
		vec2 local = vec2((fract(ra * rune_count) - 0.5) * aspect, (r - rune_inner) / h - 0.5);
		float d = rune(local, cell);
		float aa2 = fwidth(local.y) * 1.5;
		float in_band = step(abs(local.y), 0.5);
		runes = in_band * (1.0 - smoothstep(rune_stroke * 0.5, rune_stroke * 0.5 + aa2, d)) * drawn * broken;
	}

	// The fill grows from the middle out to `fx_fill`, its front line bright.
	float fill = 0.0;
	float front = 0.0;
	if (fx_fill >= 0.0) {
		float inside = 1.0 - smoothstep(fx_fill - aa, fx_fill, r);
		fill = inside * fill_color.a * mix(0.55, 1.0, smoothstep(0.0, max(fx_fill, 0.001), r));
		front = line_band(r, fx_fill, fill_front, aa) * step(0.001, fx_fill);
	}

	// Laid down in order, each over the last: the shade, the fill, the lines and the runes.
	vec3 c = vec3(0.0);
	float a = shade * disc;
	c = mix(c, fill_color.rgb * glow * 0.6, fill);
	a = a + fill * (1.0 - a);
	float lc = clamp(max(lines, front), 0.0, 1.0);
	c = mix(c, ring_color.rgb * glow, lc);
	a = a + lc * (1.0 - a);
	float rc = clamp(runes, 0.0, 1.0);
	c = mix(c, rune_color.rgb * glow, rc);
	a = a + rc * (1.0 - a);

	float th = fx_erosion * 1.1 - 0.1;
	float keep = smoothstep(th, th + 0.1, n);
	ALBEDO = c;
	ALPHA = clamp(a * disc * keep * fx_alpha, 0.0, 1.0);
}
