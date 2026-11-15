shader_type sky;
// THE SHOWCASE'S SKY (2026-11-15): made in code, no image. A gradient from the horizon to the zenith, a glow round
// the sun, the sun's and the moon's discs, drifting clouds from noise lit from the sun's side, and stars at night.
// `ShowcaseWorld` sets every value from its `ShowcaseMood`.

uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform vec4 zenith_color : source_color = vec4(0.22, 0.42, 0.78, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.72, 0.8, 0.88, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float glow_spread : hint_range(0.0, 1.0) = 0.25;
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float sun_visible : hint_range(0.0, 1.0) = 1.0;
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float moon_visible : hint_range(0.0, 1.0) = 0.0;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.6, 0.66, 0.76, 1.0);
uniform float cloud_speed = 0.006;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 ground_color : source_color = vec4(0.18, 0.2, 0.17, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float clouds_at(vec2 uv, float t) {
	float a = texture(cloud_noise, uv * 0.35 + vec2(t, t * 0.4)).r;
	float b = texture(cloud_noise, uv * 0.9 - vec2(t * 1.7, t * 0.6)).r;
	float c = texture(cloud_noise, uv * 2.3 + vec2(t * 2.5, -t)).r;
	return a * 0.6 + b * 0.3 + c * 0.1;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, -1.0, 1.0);
	// The gradient: a quick change near the horizon, a slow one up to the zenith.
	float h = pow(clamp(up, 0.0, 1.0), 0.45);
	vec3 col = mix(horizon_color.rgb, zenith_color.rgb, h);
	// The glow round the sun: wide and low, warming the horizon on its side.
	vec3 s = normalize(sun_dir);
	float toward_sun = max(dot(d, s), 0.0);
	float spread = mix(2.0, 18.0, 1.0 - glow_spread);
	float glow = pow(toward_sun, spread) * (1.0 - h * 0.6);
	float horizon_band = exp(-abs(up) * 7.0);
	float side = pow(max(dot(normalize(d.xz + vec2(1e-4)), normalize(s.xz + vec2(1e-4))), 0.0), 3.0);
	col += glow_color.rgb * (glow * 0.9 + horizon_band * side * glow_spread * 0.8);
	// Stars, above the horizon, faded by the glow.
	if (stars > 0.0 && up > 0.0) {
		vec3 p = d * 420.0;
		vec3 cell = floor(p);
		float r = hash13(cell);
		if (r > 0.9965) {
			vec3 center = cell + 0.5 + (vec3(hash13(cell + 7.1), hash13(cell + 3.3), hash13(cell + 5.7)) - 0.5) * 0.6;
			float dist = length(p - center);
			float tw = 0.65 + 0.35 * sin(TIME * (1.5 + r * 40.0) + r * 100.0);
			float star = smoothstep(0.32, 0.0, dist) * tw * (r - 0.9965) / 0.0035;
			col += vec3(0.85, 0.9, 1.0) * star * stars * 2.2 * smoothstep(0.0, 0.25, up) * (1.0 - glow);
		}
	}
	// The sun's and the moon's discs.
	float sun_disc = smoothstep(0.99955, 0.99985, dot(d, s));
	col += sun_color.rgb * sun_disc * 14.0 * sun_visible;
	col += sun_color.rgb * pow(toward_sun, 600.0) * 2.0 * sun_visible;
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	float moon_disc = smoothstep(0.99935, 0.9997, md);
	col = mix(col, moon_color.rgb * 1.6, moon_disc * moon_visible);
	col += moon_color.rgb * pow(max(md, 0.0), 300.0) * 0.5 * moon_visible;
	// Clouds on a far flat ceiling, thinning toward the horizon.
	if (up > 0.0 && cloud_cover > 0.0) {
		vec2 uv = d.xz / (up + 0.12);
		float t = TIME * cloud_speed;
		float n = clouds_at(uv, t);
		float cover = 1.0 - cloud_cover;
		float density = smoothstep(cover - 0.08, cover + 0.22, n);
		// Lit from the sun's side: denser toward the sun is shade.
		float ahead = clouds_at(uv + s.xz * 0.06, t);
		float shade = clamp((ahead - n) * 5.0 + 0.5, 0.0, 1.0);
		vec3 cloud = mix(cloud_lit.rgb, cloud_shade.rgb, shade);
		cloud += glow_color.rgb * pow(toward_sun, 6.0) * 0.8 * (1.0 - density * 0.5);
		float fade = smoothstep(0.0, 0.18, up);
		col = mix(col, cloud, density * fade * 0.92);
	}
	// Below the horizon, the far ground's haze.
	if (up < 0.0) {
		col = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.25, -up));
	}
	COLOR = col;
}
