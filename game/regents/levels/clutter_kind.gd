@tool
class_name RegentsClutterKind extends Resource
## ONE KIND OF GROUND CLUTTER (PROGRESS step 59): a model `RegentsGroundClutter` scatters over open ground (a grass
## tuft, a flower, a pebble). Walked through and never solid; add one in the clutter node's `kinds` in the Inspector.

## What is scattered: a model with no collision of its own.
@export var model: PackedScene = null
## How many on a 10 m x 10 m square of open ground, before the patches thin it.
@export_range(0.0, 400.0, 0.5) var per_100_m2: float = 10.0
## Its size, picked between these for each one.
@export_range(0.05, 4.0, 0.05) var min_scale: float = 0.7
@export_range(0.05, 4.0, 0.05) var max_scale: float = 1.2
## Height multiplier relative to width (< 1 makes short plush turf that stays below enemies and loot).
@export_range(0.15, 2.0, 0.05) var height_scale: float = 1.0
## Its color, multiplied into the model's own (white: as the model is; only leaves, petals and blades take it).
@export var tint: Color = Color.WHITE
## 0: spread evenly. 1: only in patches, with bare ground between.
@export_range(0.0, 1.0, 0.05) var patchy: float = 0.7
## How likely one grows at the foot of a rock or a tree (the rim of its soil), whatever the patches say.
@export_range(0.0, 1.0, 0.05) var at_edges: float = 0.6
## Lies on trodden ground too (a pebble); a plant does not.
@export var on_dirt: bool = false
## How far its top sways, meters for each meter of height (0: still; only leaves, petals and blades sway).
@export_range(0.0, 0.3, 0.005) var sway_m: float = 0.03
