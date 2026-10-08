// THE NATURE KIT'S LEAVES AND BLADES, lit by the normals the kit gave them on BOTH sides.
//
// Quaternius author foliage normals on purpose: every grass blade's normal points straight up (so
// a tuft is lit like the ground it grows from), and the leaves' are bent outward over the crown
// (so a canopy shades as one soft mass). The materials are double-sided, and a double-sided
// StandardMaterial3D FLIPS the normal on a back face — a blade seen from behind is lit as if it
// faced the ground, a leaf as if it faced into the trunk. Those were the black blades in the grass
// and the dark blotches in bushes and crowns (DECISIONS #141). This shader un-flips it.
//
// Everything else is what the kit's StandardMaterial3D did, so FoliageMaterial.from_standard can
// carry its values across: albedo colour x texture (x vertex colour where the kit uses it), the
// cut-out threshold, roughness, specular. Included by nature_foliage.gdshader (cut-out leaves and
// petals) and nature_foliage_opaque.gdshader (the grass, which has no alpha to test).

render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
#ifdef FOLIAGE_PALETTE
// The kit colours its grass from a PALETTE of thin stripes (Grass.png: yellow, green, orange, light
// green, then white), each blade's UVs inside one stripe. A mipmap averages a stripe into its
// neighbours: from a third-person camera the light-green grass read a mip where it had turned
// whitish, and "the grass changes colour with distance" (DECISIONS #146). A palette has no detail
// to shimmer, so it is read at full size at any distance.
uniform sampler2D texture_albedo : source_color, filter_linear, repeat_enable;
#else
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
#endif
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_vertex_color = false;
uniform bool vertex_color_is_srgb = false;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = albedo * texture(texture_albedo, UV);
	if (use_vertex_color) {
		vec4 v = COLOR;
		if (vertex_color_is_srgb) {
			v.rgb = mix(pow((v.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), v.rgb * (1.0 / 12.92),
				lessThan(v.rgb, vec3(0.04045)));
		}
		c *= v;
	}
	ALBEDO = c.rgb;
#ifdef FOLIAGE_CUTOUT
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
	// The engine has already turned NORMAL round on a back face (cull_disabled). Turn it back: both
	// sides of a blade or a leaf are lit by the normal the kit authored.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
