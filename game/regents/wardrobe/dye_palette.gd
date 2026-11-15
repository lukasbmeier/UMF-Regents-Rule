@tool
class_name DyePalette extends Resource
## A WHOLE OUTFIT'S COLORS (the wardrobe, 2026-11-14): one color per dye slot, worn by every piece at once, whatever
## outfit each piece came from. Every outfit is split into the same six slots (`zones.json`, baked by
## `game/regents/tools/wardrobe_assets.py zones`): METAL, MAIN cloth, ACCENT cloth, TRIM, LEATHER and UNDER (the
## dark undercloth). A Noble torso and Knight legs worn together take the same main and the same metal.
##
## Each color is what the AVERAGE texel of its slot becomes; the painting's light and dark stay. ALPHA IS HOW MUCH:
## 1 dyes it, 0 keeps the outfit's own painting. `palettes/<outfit>_<n>.tres` are the pack's own colourways, made
## by the bake (copy one before changing it: the bake rewrites them).

@export var title: String = ""
## What this palette is for (the lab shows it).
@export_multiline var note: String = ""
## The metal parts. Null keeps every outfit's own metal.
@export var metal: MetalFinish
@export var main: Color = Color(1, 1, 1, 0)
@export var accent: Color = Color(1, 1, 1, 0)
@export var trim: Color = Color(1, 1, 1, 0)
@export var leather: Color = Color(1, 1, 1, 0)
@export var under: Color = Color(1, 1, 1, 0)
## The trim's own light (runes, a later tier's mark). 0 for none.
@export_range(0.0, 4.0) var trim_glow: float = 0.0

## The cloth slots, in the shader's order (each `<slot>_color`).
const CLOTH: Array[StringName] = [&"main", &"accent", &"trim", &"leather", &"under"]


## This palette onto a dye material (`outfit_dye.gdshader`).
func apply_to(mat: ShaderMaterial) -> void:
	for slot: StringName in CLOTH:
		mat.set_shader_parameter(StringName("%s_color" % slot), get(slot) as Color)
	mat.set_shader_parameter(&"trim_glow", trim_glow)
	if metal != null:
		metal.apply_to(mat)
	else:
		mat.set_shader_parameter(&"metal_color", Color(1, 1, 1, 0))
		mat.set_shader_parameter(&"metal_wear", 0.0)


## A copy to change freely (the lab's own; never the file's).
func copy() -> DyePalette:
	var p: DyePalette = duplicate() as DyePalette
	if metal != null:
		p.metal = metal.duplicate() as MetalFinish
	return p
