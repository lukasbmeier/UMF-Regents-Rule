shader_type spatial;
// THE GLADE'S GROUND (PROGRESS step 59): one flat floor that reads as grass, trodden dirt and dark soil.
//
// The grass is two greens in big soft patches with a fine grain over them. Where the level is USED the grass gives
// way: `mask` is a picture of the level from above, painted as it loads by `RegentsGroundPaint` from the level's own
// markers (red: trodden dirt under stations, yards and trails; green: bare soil under trees and rocks). The edges of
// both are broken up by the grain, so a painted disc never reads as a circle.
//
// Costs three texture reads a pixel and nothing else. The colors and sizes are the material's, in the Inspector.

render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_color : source_color = vec3(0.21, 0.33, 0.13);
uniform vec3 grass_color_2 : source_color = vec3(0.30, 0.40, 0.15);
uniform vec3 dirt_color : source_color = vec3(0.38, 0.31, 0.22);
uniform vec3 soil_color : source_color = vec3(0.19, 0.16, 0.10);
// A tileable gray noise: the patches and the grain are both read from it, at two sizes.
uniform sampler2D grain : filter_linear_mipmap, repeat_enable, hint_default_white;
// Meters one tile of the grain covers, for the big patches and for the fine grain.
uniform float patch_m = 46.0;
uniform float grain_m = 5.0;
// How far the grain pushes an edge of dirt or soil in and out (0: clean circles).
uniform float ragged : hint_range(0.0, 1.0) = 0.55;
// Set by RegentsGroundPaint, never by hand: the picture, where its middle is (x, z) and how wide it is, m.
uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;
uniform vec2 mask_center = vec2(0.0, 0.0);
uniform float mask_extent_m = 128.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = texture(grain, p / patch_m).r;
	float fine = texture(grain, p / grain_m).r;
	vec3 c = mix(grass_color, grass_color_2, smoothstep(0.38, 0.66, big));
	c *= 0.9 + 0.2 * fine;
	vec2 m = texture(mask, (p - mask_center) / mask_extent_m + vec2(0.5)).rg;
	float edge = ((fine - 0.5) * 0.7 + (big - 0.5) * 0.3) * ragged;
	float soil = smoothstep(0.32, 0.5, m.g + edge * step(0.02, m.g));
	float dirt = smoothstep(0.32, 0.5, m.r + edge * step(0.02, m.r));
	c = mix(c, soil_color * (0.85 + 0.3 * fine), soil);
	c = mix(c, dirt_color * (0.88 + 0.24 * fine), dirt);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
