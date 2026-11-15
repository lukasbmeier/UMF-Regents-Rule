@tool
class_name Settlement extends Node3D
## A VILLAGE, A TOWN, A CASTLE (2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md` §3): every building under this node
## wears its `style`, each a little differently. Put buildings under it (a `KitHouse`, a `CastleWall`, a demo house from
## `houses/`, any kit piece's scene); groups of them may sit in plain Node3Ds.
##
## As the game runs, each building is DRESSED (the style's materials; its own nudge from a seed made of `town_seed` and
## where it stands, so moving a house re-rolls it) and, with `merge` on, MERGED into one mesh, a surface per material.
## In the editor nothing is changed: the buildings show the kit's own colors there.
##
## A building is a `KitHouse`, a `CastleWall` or the root of an instanced scene; anything else is searched inside.

@export var style: SettlementStyle
## Stirred into every building's seed: two villages of one style differ by it.
@export var town_seed: int = 0
## Each building into one mesh as the game runs (far fewer draw calls). Off keeps the pieces (to look at one).
@export var merge: bool = true
## Beyond this (m), a building is not drawn; 0 always draws it.
@export_range(0.0, 3000.0) var draw_distance: float = 900.0

## The buildings found and dressed by the last `dress_all` (the suite and the labs read it).
var buildings: Array[Node3D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	dress_all()


## Every building found under this node (see the class's note).
func find_buildings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect(self, out)
	return out


func _collect(n: Node, out: Array[Node3D]) -> void:
	for c: Node in n.get_children():
		var b: Node3D = c as Node3D
		if b == null:
			continue
		if b is KitHouse or b is CastleWall or not b.scene_file_path.is_empty():
			out.append(b)
		else:
			_collect(b, out)


## A building's seed: `town_seed` and where it stands (to the meter).
func seed_of(b: Node3D) -> int:
	var p: Vector3i = Vector3i(b.global_position.round())
	return hash([town_seed, p.x, p.y, p.z])


## Dresses (and merges, with `merge`) every building. Returns how many.
func dress_all() -> int:
	buildings = find_buildings()
	if style == null:
		return buildings.size()
	for b: Node3D in buildings:
		dress_one(b)
	return buildings.size()


## One building: dressed, merged, dressed again (the merged mesh carries the seed), and its draw distance set.
func dress_one(b: Node3D) -> void:
	var s: int = seed_of(b)
	var foot: float = b.global_position.y
	TownKit.dress(b, style, s, foot)
	if merge:
		var m: MeshInstance3D = TownKit.merge(b)
		if m != null:
			TownKit.dress(m, style, s, foot)
	if draw_distance > 0.0:
		for n: Node in b.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).visibility_range_end = draw_distance


## A new style for every building here (the labs' swap): materials are per style, so this re-dresses them.
func restyle(s: SettlementStyle) -> void:
	style = s
	for b: Node3D in buildings:
		if is_instance_valid(b):
			TownKit.dress(b, style, seed_of(b), b.global_position.y)
