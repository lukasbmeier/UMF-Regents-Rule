shader_type spatial;
// THE SHOWCASE'S LAKE (2026-11-15): a still lake in code. Small moving ripples from noise, the sky caught at a low
// angle (the engine's reflections), deeper and darker where the land falls away under it.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 shallow_color : source_color = vec3(0.16, 0.3, 0.32);
uniform vec3 deep_color : source_color = vec3(0.03, 0.08, 0.12);
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable, hint_normal;
uniform float ripple_speed = 0.02;
uniform float depth_fade_m = 4.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 n1 = texture(ripples, p / 9.0 + vec2(TIME * ripple_speed, 0.0)).xyz;
	vec3 n2 = texture(ripples, p / 5.3 - vec2(0.0, TIME * ripple_speed * 1.3)).xyz;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.35;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float under = clamp((VERTEX.z - world.z) / depth_fade_m, 0.0, 1.0);
	ALBEDO = mix(shallow_color, deep_color, under);
	ALPHA = mix(0.55, 0.96, under);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
