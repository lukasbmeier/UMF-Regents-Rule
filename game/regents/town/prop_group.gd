@tool
class_name PropGroup extends Node3D
## PROPS PLACED TOGETHER (2026-11-15; Luke: "once i okay the test Ill want to see how eveything furnishes"): a market's
## stalls, a yard's barrels and crates, a wall's banners. Props from the Fantasy Props kit (`TownKit.PROPS`) or the
## village kit's own (`Prop_Wagon`, fences). To its `Settlement` a group is ONE building: dressed in the place's style
## (the props' wood in its planks, their metal in its metal, their cloth in its CLOTH), merged to one mesh, its
## collisions one body. So a market of fifty props draws as a handful of surfaces.
##
## Place them in code with `put` (the town world does), or as children in a scene: an instanced prop under a group is
## taken as it stands (its collisions gathered at `_ready`).

## The props placed by `put`, by name (the suite reads it).
var placed: PackedStringArray = []
var _body: StaticBody3D = null


func _ready() -> void:
	# Props placed in a scene (instanced, not by `put`): their collisions into the group's one body.
	for c: Node in get_children():
		var n: Node3D = c as Node3D
		if n != null and n != _body and not n.scene_file_path.is_empty():
			TownKit.gather_collisions(n, body(), n.transform)


## The group's one body (made on first use).
func body() -> StaticBody3D:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Body"
		add_child(_body)
	return _body


## A prop by its file name at `at` (the group's space), turned `yaw` radians, scaled `size`. Null (and a warning) for
## a name neither kit has.
func put(piece_name: String, at: Vector3, yaw: float = 0.0, size: float = 1.0) -> Node3D:
	if not TownKit.has_piece(piece_name):
		push_warning("PropGroup: no prop %s" % piece_name)
		return null
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at)
	var n: Node3D = TownKit.piece(piece_name).instantiate() as Node3D
	TownKit.gather_collisions(n, body(), xf)
	n.transform = xf
	add_child(n)
	placed.append(piece_name)
	return n
