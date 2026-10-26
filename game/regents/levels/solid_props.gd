class_name RegentsSolidProps extends Node
## A LEVEL'S PROPS STOP YOU (owner, 2026-10-21: "Every 3d object should have collisions"): put one in a
## level, point it at the props, and say which models are solid. Each of them is wrapped in its own shape
## as the level loads (`RegentsSolid`: a convex hull per mesh), in players' games and the referee's alike,
## so a rock blocks you, and a foe, where it is drawn. What is soft (bushes: Luke's playtest, 2026-10-24, "the
## bushes have 3d collisions when I don't think they should"; grass, flowers, ferns, pebbles, mushrooms) is
## walked through, and seen through by a foe: leave it off the list.
##
## A STREAMED level (the continent, PROGRESS step 23): its props arrive a cell at a time, after the level
## loaded (`LevelStreamer` adds each cell's scene under the props node). Each cell's are wrapped as it
## arrives, under that cell, so its shapes go when it is freed. A referee never streams: it keeps the
## whole level, wrapped as it loads.

## The props: every model under this node is looked at (not only its children).
@export var props: NodePath = ^"../Decor"
## Which models are solid: a prop whose model file's name starts with one of these.
@export var solid_models: PackedStringArray = PackedStringArray(["Rock_"])

## The props it made solid this run (tests read it).
var made_solid: Array[Node3D] = []


func _ready() -> void:
	var root: Node3D = get_node_or_null(props) as Node3D
	if root == null:
		push_warning("RegentsSolidProps: no props at %s" % props)
		return
	_wrap_all(root, root)
	# Connected after: the bodies just made are children of `root` too.
	root.child_entered_tree.connect(_on_arrived)


## A streamed cell (or anything added later) arrived under the props: its own props, wrapped under it.
func _on_arrived(n: Node) -> void:
	var node: Node3D = n as Node3D
	if node == null or node is StaticBody3D:
		return   # one of the bodies made here
	if is_solid(node.scene_file_path):
		_wrap_one.call_deferred(node)   # a single prop, added on its own
	else:
		_wrap_all.call_deferred(node, node)   # a streamed cell: its props, under it


func _wrap_all(holder: Node3D, under: Node3D) -> void:
	if not is_instance_valid(holder) or not holder.is_inside_tree():
		return
	for n: Node in under.find_children("*", "Node3D", true, false):
		var prop: Node3D = n as Node3D
		if prop.scene_file_path.is_empty() or not is_solid(prop.scene_file_path):
			continue
		if RegentsSolid.wrap(holder, prop) != null:
			made_solid.append(prop)


func _wrap_one(prop: Node3D) -> void:
	if is_instance_valid(prop) and prop.is_inside_tree() and RegentsSolid.wrap(prop, prop) != null:
		made_solid.append(prop)


## Whether a prop of model `path` is solid here.
func is_solid(path: String) -> bool:
	var file: String = path.get_file()
	for prefix: String in solid_models:
		if file.begins_with(prefix):
			return true
	return false
