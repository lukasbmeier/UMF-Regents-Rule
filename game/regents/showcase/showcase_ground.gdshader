shader_type spatial;
// THE SHOWCASE'S LAND (2026-11-15): one sculpted valley painted by its own shape, no image. Grass in two greens on
// the flat, dry gold grass up the hills, earth on the slopes, rock where it is steep, snow on the high peaks, a sandy
// shore round the lake, and trodden dirt round the camp. A tileable noise breaks every edge. The colors are the
// material's, in the Inspector (ShowcaseWorld makes it).

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_color : source_color = vec3(0.20, 0.33, 0.12);
uniform vec3 grass_color_2 : source_color = vec3(0.32, 0.42, 0.15);
uniform vec3 dry_color : source_color = vec3(0.52, 0.48, 0.24);
uniform vec3 earth_color : source_color = vec3(0.36, 0.28, 0.19);
uniform vec3 rock_color : source_color = vec3(0.42, 0.41, 0.40);
uniform vec3 snow_color : source_color = vec3(0.92, 0.94, 0.98);
uniform vec3 shore_color : source_color = vec3(0.55, 0.5, 0.38);
uniform vec3 dirt_color : source_color = vec3(0.36, 0.29, 0.2);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable, hint_default_white;
// Heights (m): where grass dries, where snow begins, the water's line.
uniform float dry_from_m = 14.0;
uniform float snow_from_m = 62.0;
uniform float water_y = -1.4;
// The camp's trodden ground: its middle (x, z) and radius (m).
uniform vec3 camp = vec3(0.0, 0.0, 9.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(grain, p / 70.0).r;
	float mid = texture(grain, p / 13.0).r;
	float fine = texture(grain, p / 3.1).r;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float y = world_pos.y + (big - 0.5) * 8.0;
	vec3 c = mix(grass_color, grass_color_2, smoothstep(0.35, 0.68, big));
	c = mix(c, dry_color, smoothstep(dry_from_m - 4.0, dry_from_m + 10.0, y) * 0.85);
	c *= 0.86 + 0.28 * fine;
	float earth = smoothstep(0.16, 0.3, slope + (mid - 0.5) * 0.18);
	c = mix(c, earth_color * (0.8 + 0.4 * mid), earth);
	float rock = smoothstep(0.32, 0.46, slope + (mid - 0.5) * 0.2);
	vec3 stone = rock_color * (0.7 + 0.5 * mid) * (0.85 + 0.3 * fine);
	c = mix(c, stone, rock);
	float snow = smoothstep(snow_from_m, snow_from_m + 8.0, y + (fine - 0.5) * 6.0) * (1.0 - smoothstep(0.55, 0.7, slope));
	c = mix(c, snow_color * (0.92 + 0.08 * fine), snow);
	float shore = 1.0 - smoothstep(water_y + 0.2, water_y + 1.6 + mid * 0.8, world_pos.y);
	c = mix(c, shore_color * (0.85 + 0.3 * fine), shore);
	float r = length(p - camp.xz) + (mid - 0.5) * 3.0 + (fine - 0.5) * 1.2;
	c = mix(c, dirt_color * (0.85 + 0.3 * fine), (1.0 - smoothstep(camp.y * 0.55, camp.y, r)) * 0.9);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.6, snow);
	SPECULAR = mix(0.15, 0.4, snow);
}
