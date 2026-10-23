class_name RegentsSolidProps extends Node
## A LEVEL'S PROPS STOP YOU (owner, 2026-10-21: "Every 3d object should have collisions"): put one in a
## level, point it at the props, and say which models are solid. Each of them is wrapped in its own shape
## as the level loads (`RegentsSolid`: a convex hull per mesh), in players' games and the referee's alike,
## so a rock or a bush blocks you, and a foe, where it is drawn. What lies low and soft (grass, flowers,
## ferns, pebbles, mushrooms) is walked through: leave it off the list.

## The props: every model under this node is looked at (not only its children).
@export var props: NodePath = ^"../Decor"
## Which models are solid: a prop whose model file's name starts with one of these.
@export var solid_models: PackedStringArray = PackedStringArray(["Rock_", "Bush_"])

## The props it made solid this run (tests read it).
var made_solid: Array[Node3D] = []


func _ready() -> void:
	var root: Node3D = get_node_or_null(props) as Node3D
	if root == null:
		push_warning("RegentsSolidProps: no props at %s" % props)
		return
	for n: Node in root.find_children("*", "Node3D", true, false):
		var prop: Node3D = n as Node3D
		if prop.scene_file_path.is_empty() or not is_solid(prop.scene_file_path):
			continue
		if RegentsSolid.wrap(root, prop) != null:
			made_solid.append(prop)


## Whether a prop of model `path` is solid here.
func is_solid(path: String) -> bool:
	var file: String = path.get_file()
	for prefix: String in solid_models:
		if file.begins_with(prefix):
			return true
	return false
