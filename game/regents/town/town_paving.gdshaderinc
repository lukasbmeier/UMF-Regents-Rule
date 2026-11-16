// THE STREETS' STONES (2026-11-15; Luke: streets must never read as the walls): code-made paving, never a texture any
// wall wears. Round COBBLES (pattern 0, a jittered cell per stone) or SETTS (pattern 1, cut blocks in running bond),
// a dark joint between them, each stone a little lighter or darker and a share of them a second color (`mix`).
// Used by the town world's ground (`town_ground.gdshader`) and the lab's streets (`town_street.gdshader`).

float pv_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 pv_hash2(vec2 p) {
	return vec2(pv_hash(p), pv_hash(p + vec2(17.31, 5.17)));
}

// At world point p (meters): how much of a stone it is (0 in a joint), the stone's own number (0-1), and how the
// stone's face tilts there (for the normal).
void town_pave(vec2 p, int pattern, out float stone, out float id, out vec2 tilt) {
	if (pattern == 1) {
		vec2 size = vec2(0.44, 0.24);
		float row = floor(p.y / size.y);
		float x = p.x / size.x + 0.5 * mod(row, 2.0);
		vec2 cell = vec2(floor(x), row);
		vec2 f = vec2(fract(x), fract(p.y / size.y));
		vec2 e = min(f, 1.0 - f) * size;
		float edge = min(e.x, e.y);
		stone = smoothstep(0.008, 0.028, edge);
		id = pv_hash(cell);
		vec2 c = f - 0.5;
		tilt = c * 0.25 + sign(c) * (1.0 - smoothstep(0.01, 0.05, e)) * 0.45;
		return;
	}
	float cell_m = 0.24;
	vec2 g = p / cell_m;
	vec2 ip = floor(g);
	vec2 fp = fract(g);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best = vec2(0.0);
	vec2 best_cell = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 r = o + 0.2 + 0.6 * pv_hash2(ip + o) - fp;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = r;
				best_cell = ip + o;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = (sqrt(d2) - sqrt(d1)) * cell_m * 0.5;
	stone = smoothstep(0.006, 0.026, edge);
	id = pv_hash(best_cell);
	tilt = -best * 0.8 * (0.4 + 0.6 * stone);
}

// Far off, where a stone is a few pixels (`blur` 0-1, from `fwidth` of the world point), the stones fade to their
// average so they never shimmer.
void town_pave_far(float blur, inout float stone, inout float id, inout vec2 tilt) {
	stone = mix(stone, 0.88, blur);
	id = mix(id, 0.5, blur);
	tilt *= 1.0 - blur;
}

// The paving's color: each stone `base` a little lighter or darker (a share of them `mix`), the joints dark with dirt.
vec3 town_paving_color(vec3 base, vec4 mix_col, vec3 joint, float stone, float id) {
	vec3 s = base * (0.8 + 0.4 * id);
	float second = step(fract(id * 7.13), mix_col.a);
	s = mix(s, mix_col.rgb * (0.8 + 0.4 * fract(id * 3.7)), second);
	return mix(joint, s, stone);
}
