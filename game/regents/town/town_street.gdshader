// A STRETCH OF PAVED STREET (the town lab's streets): a style's paving (`town_paving.gdshaderinc`) on a flat strip,
// its edges worn into the grass. The strip's UV runs 0-1 across it.
shader_type spatial;

#include "res://game/regents/town/town_paving.gdshaderinc"

uniform vec4 paving : source_color = vec4(0.4, 0.37, 0.33, 1.0);
uniform vec4 paving_mix : source_color = vec4(0.0);
uniform int paving_pattern = 0;
uniform vec4 grass : source_color = vec4(0.32, 0.43, 0.2, 1.0);
uniform vec4 dirt : source_color = vec4(0.45, 0.36, 0.25, 1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float stone;
	float id;
	vec2 tilt;
	town_pave(v_world.xz, paving_pattern, stone, id, tilt);
	town_pave_far(smoothstep(0.08, 0.3, length(fwidth(v_world.xz))), stone, id, tilt);
	vec3 joint = mix(dirt.rgb * 0.4, paving.rgb * 0.3, 0.4);
	vec3 c = town_paving_color(paving.rgb, paving_mix, joint, stone, id);
	float across = abs(UV.y - 0.5) * 2.0;
	float ragged = pv_hash(floor(v_world.xz * 1.5)) * 0.08;
	float edge = smoothstep(0.82, 1.0, across + ragged);
	ALBEDO = mix(c, mix(dirt.rgb, grass.rgb, 0.4), edge);
	ROUGHNESS = mix(1.0, 0.9, stone * (1.0 - edge));
	SPECULAR = 0.25;
	NORMAL_MAP = vec3(0.5 + tilt * 0.25 * (1.0 - edge), 1.0);
}
