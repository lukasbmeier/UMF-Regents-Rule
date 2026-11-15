// A PARTICLE'S SHAPE (the VFX lab, 2026-11-14), drawn on a QuadMesh in a GPUParticles3D: a soft dot, a streak, a
// star, a puff of smoke or a shard, all made from math (and a noise for the puff), never an image. Its color and its
// fade come from the particle (the process material's color ramp): as its alpha falls a puff is EATEN AWAY by the
// noise rather than going faint. It faces the camera (`facing` 0), turns only round its own up (1: a streak along
// its flight, with "Align Y" on the process material), or keeps the particle's own turn (2: flat on the ground).
//
// Included by `vfx_sprite_add.gdshader` (glows) and `vfx_sprite_mix.gdshader` (covers: smoke, dust, snow).

uniform sampler2D noise : hint_default_white, repeat_enable, filter_linear_mipmap;
// 0 a soft dot, 1 a streak (bright at its head, the quad's top), 2 a star, 3 a puff, 4 a shard, 5 a ring.
uniform int shape : hint_range(0, 5) = 0;
uniform int facing : hint_range(0, 2) = 0;
// How bright: past 1 it glows. How soft a dot's falloff is (higher: a harder core).
uniform float intensity : hint_range(0.0, 16.0) = 3.0;
uniform float falloff : hint_range(0.5, 8.0) = 2.0;
// A puff: how lumpy, and how soft its eaten edge.
uniform float lumps : hint_range(0.0, 1.5) = 0.6;
uniform float erode_softness : hint_range(0.01, 0.5) = 0.15;
// The ring's thickness (a share of its radius).
uniform float ring_width : hint_range(0.01, 1.0) = 0.15;
// Multiplies its color (a mesh, not a particle, has no color of its own).
uniform vec4 tint : source_color = vec4(1.0);

instance uniform float fx_time = 0.0;
instance uniform float fx_alpha = 1.0;

varying float v_seed;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 scale_m = mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0), vec4(0.0, 0.0, s.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	if (facing == 0) {
		mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		float spin = INSTANCE_CUSTOM.x;
		w = w * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0), vec4(sin(spin), cos(spin), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * w * scale_m;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	} else if (facing == 1) {
		vec3 up = normalize(MODEL_MATRIX[1].xyz);
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 side = cross(up, to_cam);
		side = length(side) > 0.0001 ? normalize(side) : normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 back = cross(side, up);
		mat4 w = mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(back, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * w * scale_m;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float a = 0.0;
	float lit = 1.0;
	if (shape == 0) {
		a = pow(clamp(1.0 - d, 0.0, 1.0), falloff);
	} else if (shape == 1) {
		float across = pow(clamp(1.0 - abs(q.x), 0.0, 1.0), falloff);
		// The head (the quad's top, its flight's way with "Align Y") bright, the tail thinning out.
		float along = smoothstep(-1.0, -0.8, q.y) * (1.0 - smoothstep(-0.8, 1.0, q.y) * 0.85) * (1.0 - smoothstep(0.7, 1.0, q.y));
		a = across * along;
	} else if (shape == 2) {
		float core = pow(clamp(1.0 - d, 0.0, 1.0), falloff + 1.0);
		float rays = max(clamp(1.0 - abs(q.x) * 10.0, 0.0, 1.0) * (1.0 - abs(q.y)),
			clamp(1.0 - abs(q.y) * 10.0, 0.0, 1.0) * (1.0 - abs(q.x)));
		a = clamp(core + rays * rays, 0.0, 1.0);
	} else if (shape == 3) {
		// A puff: a soft ball made lumpy by one noise, its inside broken by another; as its alpha falls it is eaten
		// from its thin parts in; lit from above (lighter on top).
		float n = texture(noise, UV * 0.8 + vec2(v_seed * 5.3, v_seed * 2.9) + vec2(0.0, 0.03) * fx_time).r;
		float n2 = texture(noise, UV * 1.7 + vec2(v_seed * 3.1, v_seed * 7.7)).r;
		float body = clamp(1.0 - d * (1.0 + lumps * (n - 0.5)), 0.0, 1.0);
		float v = body * (0.6 + 0.8 * n2);
		float er = 1.0 - COLOR.a;
		a = smoothstep(er, er + erode_softness * 2.0, v) * smoothstep(0.0, 0.55, body) * 0.8;
		lit = mix(1.15, 0.7, UV.y);
	} else if (shape == 4) {
		a = 1.0 - smoothstep(0.85, 1.0, abs(q.x) * 2.6 + abs(q.y));
		a *= mix(0.6, 1.0, 1.0 - abs(q.x) * 2.0);
	} else {
		float w = ring_width;
		a = 1.0 - smoothstep(w * 0.5, w * 0.5 + fwidth(d) * 1.5, abs(d - (1.0 - w * 0.6)));
	}
	float fade = (shape == 3) ? 1.0 : COLOR.a;
	ALBEDO = COLOR.rgb * tint.rgb * intensity * lit;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a * fade * tint.a * fx_alpha, 0.0, 1.0);
}
