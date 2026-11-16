@tool
class_name VillageDressing extends Resource
## THE VILLAGE KIT'S SMALL PROPS ABOUT A HOUSE (2026-11-16, `docs/regents_rule/SETTLEMENTS_PREP.md` §8, "Left for later"):
## vines up its walls, a fenced yard behind it, crates by a side wall, the kit's wagon beside it. Give a `Settlement` one
## (`dressing`) and every `KitHouse` under it is dressed from its own seed (`Settlement.seed_of`): the same house, the
## same props. No dressing (null), no props: the look before this.
##
## Each share is how many houses get that prop (0 none, 1 every house). The props go in one `PropGroup` under the house
## ("Village"), so they are merged with it and their collisions (the wagon alone has eleven) are one body.
## `dressing/*.tres` are the presets; how much of each is a taste call (Luke's): the presets are marked `placeholder`.

## The vines: the share of a house's back and side wall cells (ground floor) with a vine hanging on them.
@export_range(0.0, 1.0) var vine_share: float = 0.0
## The share of houses with a fenced yard behind them.
@export_range(0.0, 1.0) var fence_share: float = 0.0
## How deep that yard is (m, from the back wall to the fence; whole 2 m panels).
@export_range(2.0, 8.0, 2.0) var yard_depth: float = 4.0
## Of the fences, the share that are the kit's tall metal ones (else wooden).
@export_range(0.0, 1.0) var metal_fence_share: float = 0.0
## The share of houses with crates stacked by a side wall.
@export_range(0.0, 1.0) var crate_share: float = 0.0
## The share of houses with the kit's wagon standing beside them.
@export_range(0.0, 1.0) var wagon_share: float = 0.0
## A value nobody has chosen yet (Luke's to set): the presets say so.
@export var placeholder: bool = false

## The flat vines (they hang from their origin, about 1.5 x 2.6 m, their leaves toward +z).
const VINES: PackedStringArray = ["Prop_Vine1", "Prop_Vine2", "Prop_Vine3", "Prop_Vine4"]
const WOOD_FENCE: PackedStringArray = ["Prop_WoodenFence_Extension1", "Prop_WoodenFence_Extension2"]
const METAL_FENCE: PackedStringArray = ["Prop_MetalFence_Simple", "Prop_MetalFence_Ornament"]
## A wall piece's outside face, out from its origin (the kit's walls are 0.41 m thick, measured).
const WALL_FACE: float = 0.1
## Where a vine hangs from (its top is ~0.5 m above this, its foot ~2.1 m below).
const VINE_Y: float = 2.4
## The group's name under the house.
const GROUP: String = "Village"


## The props about `h`, from `rng`: a `PropGroup` under the house (null when the dice give it none, or it has one).
func place(h: KitHouse, rng: RandomNumberGenerator) -> PropGroup:
	if h.get_node_or_null(GROUP) != null:
		return null
	var g := PropGroup.new()
	g.name = GROUP
	var hw: float = h.effective_width() * KitHouse.CELL * 0.5
	var hd: float = h.depth * KitHouse.CELL * 0.5
	_vines(g, rng, hw, hd)
	# Crates on one side, the wagon on the other.
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	if rng.randf() < fence_share:
		_fence(g, rng, hw, hd)
	if rng.randf() < crate_share:
		var at := Vector3(side * (hw + WALL_FACE + 0.75), 0.0, rng.randf_range(-hd + 1.0, hd - 1.0))
		g.put("Prop_Crate", at, rng.randf_range(-0.3, 0.3))
		if rng.randf() < 0.6:
			g.put("Prop_Crate", at + Vector3(0.0, 0.0, 1.15 * (1.0 if at.z < 0.0 else -1.0)), rng.randf_range(-0.3, 0.3))
		if rng.randf() < 0.4:
			g.put("Prop_Crate", at + Vector3(0.0, 1.06, 0.0), rng.randf_range(-0.4, 0.4), 0.9)
	if rng.randf() < wagon_share:
		# Along the other side wall, its shafts toward the front (the wagon's +z); clear of the wall by a meter.
		g.put("Prop_Wagon", Vector3(-side * (hw + WALL_FACE + 2.0), 0.0, minf(hd - 0.9, 1.0)), rng.randf_range(-0.12, 0.12))
	if g.placed.is_empty():
		g.free()
		return null
	h.add_child(g)
	return g


## Vines on the back (-z) and side walls' ground-floor cells (never the front: the door is there).
func _vines(g: PropGroup, rng: RandomNumberGenerator, hw: float, hd: float) -> void:
	if vine_share <= 0.0:
		return
	var w: int = roundi(hw * 2.0 / KitHouse.CELL)
	var d: int = roundi(hd * 2.0 / KitHouse.CELL)
	# Each wall: its first cell's middle on the face, the step, how many, the way it faces.
	var walls: Array[Array] = [
		[Vector3(hw - 1.0, VINE_Y, -hd - WALL_FACE), Vector3(-KitHouse.CELL, 0, 0), w, PI],
		[Vector3(hw + WALL_FACE, VINE_Y, hd - 1.0), Vector3(0, 0, -KitHouse.CELL), d, PI * 0.5],
		[Vector3(-hw - WALL_FACE, VINE_Y, -hd + 1.0), Vector3(0, 0, KitHouse.CELL), d, -PI * 0.5],
	]
	for wall: Array in walls:
		for i: int in int(wall[2]):
			if rng.randf() < vine_share:
				g.put(VINES[rng.randi_range(0, VINES.size() - 1)], (wall[0] as Vector3) + (wall[1] as Vector3) * i,
					float(wall[3]))


## A yard behind the house: a fence along its back, and its two sides back to the house's corners. The kit's panels are
## 2 m long, so the yard is a whole number of them deep (`yard_depth` rounded).
func _fence(g: PropGroup, rng: RandomNumberGenerator, hw: float, hd: float) -> void:
	var kinds: PackedStringArray = METAL_FENCE if rng.randf() < metal_fence_share else WOOD_FENCE
	var runs: int = maxi(1, roundi(yard_depth / KitHouse.CELL))
	var back: float = -hd - runs * KitHouse.CELL
	var span: int = roundi(hw * 2.0 / KitHouse.CELL)
	for i: int in span:
		g.put(kinds[i % kinds.size()], Vector3(-hw + KitHouse.CELL * (i + 0.5), 0.0, back))
	for sx: float in [-hw, hw]:
		for i: int in runs:
			g.put(kinds[(i + 1) % kinds.size()], Vector3(sx, 0.0, -hd - KitHouse.CELL * (i + 0.5)), PI * 0.5)
