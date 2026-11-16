@tool
extends ModularCharacter
## A GENRE'S LOOK, AS A GENRE WRITES ONE (DECISIONS #316): a scene of its own whose root script
## extends `ModularCharacter`, adding a free colour option (`"color": true`) to the foundation's
## options, with nothing in `foundation/` or `game/characters/` edited. The `looks` suite opens the
## picker on it, and it tints the outfit with the chosen colour.

const MAIN_KEY: String = "main"
const SWATCHES: Array[Color] = [Color(0.55, 0.12, 0.12), Color(0.15, 0.3, 0.6), Color(0.2, 0.45, 0.2),
	Color(0.85, 0.7, 0.25), Color(0.1, 0.1, 0.1), Color(0.92, 0.92, 0.9)]
## The look's own: what the button shows while nothing is chosen.
const OWN: Color = Color(0.6, 0.5, 0.4)

## The colour chosen, or OWN.
var main_color: Color = OWN
var main_chosen: bool = false


func appearance_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = super()
	out.insert(0, {"key": MAIN_KEY, "label": "Main colour", "color": true, "swatches": SWATCHES, "own": OWN})
	return out


func apply_appearance(appearance: String) -> void:
	super(appearance)
	var v: int = int(Appearance.choices(appearance).get(MAIN_KEY, 0))
	main_chosen = Appearance.is_color(v)
	main_color = Appearance.color_of(v, OWN)
	if not main_chosen or skeleton() == null:
		return
	for n: Node in skeleton().find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or String(mi.get_meta(PIECE_META, "")).get_file().begins_with("Hair"):
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or not OUTFIT_MATERIALS.has(src.resource_name):
				continue
			var mat: StandardMaterial3D = src.duplicate() as StandardMaterial3D
			mat.albedo_color = main_color
			mi.set_surface_override_material(i, mat)
