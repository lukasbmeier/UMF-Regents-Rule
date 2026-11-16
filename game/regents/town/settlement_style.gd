@tool
class_name SettlementStyle extends Resource
## A SETTLEMENT'S LOOK (2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md` §3): the colors every building of a village
## wears, how weathered it is, and how far each building strays from it. The same kit models, a different `.tres`,
## a different place. Edit one in the Inspector; the town lab (`town_lab.tscn`, F6) shows them side by side.
##
## Each color is what the AVERAGE texel of its slot becomes; the painting's light and dark stay (the town dye,
## `town_surface.gdshader`). ALPHA IS HOW MUCH: 1 dyes it, 0 keeps the kit's own painting. `styles/*.tres` are the
## presets; copy one before changing it.

@export var title: String = ""
## What this look is for (the lab shows it).
@export_multiline var note: String = ""

@export_group("Colors")
## Walls' plaster (between the timbers).
@export var plaster: Color = Color(1, 1, 1, 0)
## Cut stone: the stone under the plaster, footings, corners, gable ends, the trim's stone strip, castle tops.
@export var stone: Color = Color(1, 1, 1, 0)
## Rough stone walls (the kit's "uneven brick"; the castle's walls and towers).
@export var masonry: Color = Color(1, 1, 1, 0)
## Fired brick.
@export var brick: Color = Color(1, 1, 1, 0)
## Cobbles and paving.
@export var paving: Color = Color(1, 1, 1, 0)
## Roof tiles, round and flat.
@export var roof: Color = Color(1, 1, 1, 0)
## Dark wood: beams, frames, doors.
@export var timber: Color = Color(1, 1, 1, 0)
## Light wood: boards, planks, balconies.
@export var planks: Color = Color(1, 1, 1, 0)
## Ironwork: fences, brackets, hinges.
@export var metal: Color = Color(1, 1, 1, 0)
## Window glass by day (alpha 0 keeps a dark blue-gray).
@export var glass: Color = Color(1, 1, 1, 0)
## Vines on the walls.
@export var foliage: Color = Color(1, 1, 1, 0)
## Cloth: the props' banners, awnings and stall covers (the town's own color on its market).
@export var cloth: Color = Color(1, 1, 1, 0)

@export_group("Weather")
## How far the plaster has worn through to the stone, and how weathered roofs and old wood are.
@export_range(0.0, 1.5) var wear: float = 0.5
## The color old roofs and boards weather to (lichen, rust, rot).
@export var wear_color: Color = Color(0.42, 0.3, 0.12)
## Moss on what faces up and low on walls.
@export_range(0.0, 1.0) var moss: float = 0.0
@export var moss_color: Color = Color(0.2, 0.3, 0.08)
## Dirt splashed up the foot of every wall: how much, and how high (m).
@export_range(0.0, 1.0) var grime: float = 0.2
@export_range(0.2, 4.0) var grime_height: float = 1.2
@export var grime_color: Color = Color(0.45, 0.38, 0.3)
## Snow lying on roofs, sills and anything that faces up.
@export_range(0.0, 1.0) var snow: float = 0.0
## Bleached by the sun: grayer and lighter.
@export_range(0.0, 1.0) var fade: float = 0.0

@export_group("Each building")
## How far each building's colors stray from the style: hue, then light and saturation, then wear.
@export_range(0.0, 0.15) var jitter_hue: float = 0.02
@export_range(0.0, 0.5) var jitter_value: float = 0.1
@export_range(0.0, 1.0) var jitter_wear: float = 0.3

@export_group("Streets")
## The streets' stones (Luke, 2026-11-15: streets must never read as the walls): code-made, never a texture a wall
## wears; their color is `paving` (kept well apart from `stone` and `masonry`: the suite checks every preset), a
## second color for some of the stones, and the laying.
## A second stone color; alpha is the share of stones that take it (0, none).
@export var paving_mix: Color = Color(0, 0, 0, 0)
## Round cobbles, or setts (cut blocks in rows).
@export_enum("Cobbles", "Setts") var paving_pattern: int = 0

@export_group("Night")
## Lamplight in the windows after dark.
@export var window_light: Color = Color(1.0, 0.8, 0.45)
## How many windows are lit.
@export_range(0.0, 1.0) var lit_share: float = 0.7

## The dye slots, in the shaders' order (`slot_ids`; each building's nudge moves each one its own way).
const SLOTS: Array[StringName] = [&"plaster", &"stone", &"masonry", &"brick", &"paving", &"roof", &"timber", &"planks",
	&"metal", &"glass", &"foliage", &"cloth"]
## The weather and night numbers, by the shaders' uniform names (the same as the fields').
const NUMBERS: Array[StringName] = [&"wear", &"moss", &"grime", &"grime_height", &"snow", &"fade", &"jitter_hue",
	&"jitter_value", &"jitter_wear", &"lit_share"]
const COLORS: Array[StringName] = [&"wear_color", &"moss_color", &"grime_color", &"window_light"]


## The streets' color when `paving` keeps the painting (alpha 0): a dark worn gray-brown, unlike the kit's walls.
const PAVING_PAINTED: Color = Color(0.4, 0.37, 0.33)


## A slot's color (`SLOTS`).
func color_of(slot: StringName) -> Color:
	return get(slot) as Color


## The streets' stone color: `paving` over `PAVING_PAINTED` by its alpha.
func paving_color() -> Color:
	var c: Color = PAVING_PAINTED.lerp(paving, paving.a)
	c.a = 1.0
	return c


## A copy to change freely (the lab's own; never the file's).
func copy() -> SettlementStyle:
	return duplicate() as SettlementStyle
