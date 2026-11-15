@tool
class_name MetalFinish extends Resource
## A METAL'S LOOK on any outfit (the wardrobe, 2026-11-14): what the metal parts of a piece become. One mesh for every
## tier: copper, iron and steel plate are the same Knight pieces in three finishes (`metals/*.tres`). Edit one in the
## Inspector, run the wardrobe lab (F6) and look; a new metal is a new `.tres` here.
##
## The color is what the AVERAGE metal texel becomes: the outfit's own painting (dents, edges, grime) stays, as
## lighter and darker shades of it (`outfit_dye.gdshader`). Presentation only: a finish never says what a piece does.

## Shown in the lab's lists.
@export var title: String = ""
## The metal's color. Alpha is how much of it: 1 replaces the painted metal, 0 keeps the outfit's own.
@export var color: Color = Color(0.75, 0.75, 0.78, 1.0)
## 1 a bare metal; lower reads as painted, lacquered or blackened.
@export_range(0.0, 1.0) var metallic: float = 1.0
## 0 a mirror, 1 dull. The painting's own roughness varies around it.
@export_range(0.0, 1.0) var roughness: float = 0.4
## How much of the darker hollows takes the wear color: verdigris on copper, rust on iron, soot on steel.
@export_range(0.0, 1.0) var wear: float = 0.0
## The wear's color (dull, never metallic).
@export var wear_color: Color = Color(0.3, 0.45, 0.35, 1.0)


## This finish onto a dye material (`outfit_dye.gdshader`).
func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter(&"metal_color", color)
	mat.set_shader_parameter(&"metal_metallic", metallic)
	mat.set_shader_parameter(&"metal_roughness", roughness)
	mat.set_shader_parameter(&"metal_wear", wear)
	mat.set_shader_parameter(&"metal_wear_color", wear_color)
