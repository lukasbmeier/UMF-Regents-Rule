shader_type spatial;
// THE ROD'S BLANK, BENDING toward what the line is pulling on (FishingRod.set_bend, DECISIONS #144).
// The mesh is the blank in its own frame: +Y along the rod, -half_length at the butt, +half_length
// at the tip. Each point is pushed along `bend_dir` by `bend` times the square of how far up the rod
// it is — the butt stays in the hand, the tip goes furthest — and drawn in a little so the rod does
// not grow as it curves. FishingRod moves the tip (and the line with it) by the same formula.

uniform vec4 albedo : source_color = vec4(0.1, 0.16, 0.28, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
// Metres the tip moves, and which way (a unit vector across the rod, in the blank's frame).
uniform float bend = 0.0;
uniform vec3 bend_dir = vec3(0.0, 0.0, 1.0);
uniform float half_length = 0.75;

void vertex() {
	float s = clamp((VERTEX.y + half_length) / (2.0 * half_length), 0.0, 1.0);
	float d = bend * s * s;
	VERTEX += bend_dir * d;
	VERTEX.y -= 0.5 * d * d / (2.0 * half_length);
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
