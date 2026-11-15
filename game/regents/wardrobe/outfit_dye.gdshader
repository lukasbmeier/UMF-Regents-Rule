// THE OUTFIT DYE (the wardrobe, 2026-11-14): any outfit piece in any colors, its painting kept.
//
// Every Quaternius outfit is one painted atlas. The bake (`game/regents/tools/wardrobe_assets.py zones`) sorts its
// texels into six DYE SLOTS and writes `zones/T_<Outfit>_Zones.png`: R the slot (x 40), B the slot's mean brightness.
// Here a texel of a dyed slot becomes the slot's color times how much lighter or darker the painting is than that
// mean, so folds, dents, stitching and grime stay. A color's alpha is how much (0 keeps the painting).
// Metal (the ORM's blue channel) also takes the finish's metallic, roughness and wear (`MetalFinish`).
// The rest is StandardMaterial3D's: the same albedo, ORM and normal textures the piece was imported with.
// Set by `Wardrobe.dress` from a `DyePalette`; `show_zones` paints each slot one flat color (the lab's Z).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D zone_tex : hint_default_black, filter_nearest;
uniform bool show_zones = false;

group_uniforms metal;
uniform vec4 metal_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float metal_metallic : hint_range(0.0, 1.0) = 1.0;
uniform float metal_roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metal_wear : hint_range(0.0, 1.0) = 0.0;
uniform vec4 metal_wear_color : source_color = vec4(0.3, 0.45, 0.35, 1.0);
group_uniforms cloth;
uniform vec4 main_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 accent_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 trim_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 leather_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 under_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float trim_glow : hint_range(0.0, 4.0) = 0.0;
group_uniforms;

const float SLOT_STEP = 40.0 / 255.0;

vec3 zone_flat(int id) {
	if (id == 1) return vec3(0.55, 0.58, 0.68);
	if (id == 2) return vec3(0.8, 0.05, 0.05);
	if (id == 3) return vec3(0.03, 0.15, 0.9);
	if (id == 4) return vec3(1.0, 0.65, 0.0);
	if (id == 5) return vec3(0.3, 0.1, 0.02);
	if (id == 6) return vec3(0.02, 0.55, 0.1);
	return vec3(0.02);
}

void fragment() {
	vec4 z = texture(zone_tex, UV);
	int id = int(round(z.r / SLOT_STEP));
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float ref = max(pow(z.b, 2.2), 0.0005);
	float detail = clamp(dot(base, vec3(0.2126, 0.7152, 0.0722)) / ref, 0.0, 4.0);
	vec4 dye = vec4(0.0);
	if (id == 1) dye = metal_color;
	else if (id == 2) dye = main_color;
	else if (id == 3) dye = accent_color;
	else if (id == 4) dye = trim_color;
	else if (id == 5) dye = leather_color;
	else if (id == 6) dye = under_color;
	vec3 col = mix(base, dye.rgb * detail, dye.a);
	float metallic = orm.b;
	float rough = orm.g;
	if (id == 1) {
		metallic = mix(orm.b, metal_metallic, dye.a);
		rough = mix(orm.g, clamp(metal_roughness + (orm.g - 0.5) * 0.3, 0.03, 1.0), dye.a);
		// Wear gathers where the painting is darker than the metal's mean: the hollows and the grime.
		float w = metal_wear * smoothstep(1.05, 0.35, detail);
		col = mix(col, metal_wear_color.rgb * clamp(detail * 1.4, 0.2, 1.2), w);
		metallic = mix(metallic, 0.0, w);
		rough = mix(rough, 0.95, w);
	}
	vec3 glow = id == 4 ? col * trim_glow : vec3(0.0);
	if (show_zones) {
		col = zone_flat(id) * (0.45 + 0.55 * clamp(detail, 0.0, 1.2));
		metallic = 0.0;
		rough = 1.0;
		glow = vec3(0.0);
	}
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = rough;
	AO = orm.r;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	EMISSION = glow;
}
