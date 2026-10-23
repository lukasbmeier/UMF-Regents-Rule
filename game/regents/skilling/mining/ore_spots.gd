class_name RegentsOreSpots extends RefCounted
## WHERE THE ORE SITS ON A ROCK (owner, 2026-10-21: "fix the copper bits on the rocks (position) in a
## workbench if possible as right now they are floating"). Two ways, the first that has them:
##
##   its LAYOUT   `ore/<rock model's file name>_ore.tscn` beside this script: the rock model and its
##                nuggets, real nugget models, placed by hand. Open it, move, turn or size a nugget (any
##                child whose name starts with "Ore"), save: every rock of that model shows them so, in
##                any colour of ore. A new rock model gets one from `make_ore_layouts.gd`.
##   ON SURFACE   none made yet: nuggets around its upper half, each dropped onto the rock's own surface
##                (a ray against its triangles) and turned to lie flat on it, so none floats.
##
## Spots are in the MODEL's own space (unscaled): the nuggets are its children.

const LAYOUT_DIR: String = "res://game/regents/skilling/mining/ore/"
## How far a nugget sinks into the surface it lies on (metres, model space): it sits in, not on.
const SINK_M: float = 0.03
## A snapped nugget's size (the pebble model's, times this).
const NUGGET_SCALE: float = 0.9


## The layout file for rock model `model_scene` (whether or not it exists yet).
static func layout_path(model_scene: PackedScene) -> String:
	return LAYOUT_DIR + model_scene.resource_path.get_file().get_basename() + "_ore.tscn"


## The nuggets' places in a layout scene: each child whose name starts with "Ore", in order.
static func from_layout(layout: PackedScene) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var root: Node = layout.instantiate()
	for c: Node in root.get_children():
		var n: Node3D = c as Node3D
		if n != null and String(n.name).begins_with("Ore"):
			out.append(n.transform)
	root.free()
	return out


## The spots for rock model `model_scene` (instantiated as `model`): its layout's, else `count` snapped.
static func spots_for(model_scene: PackedScene, model: Node3D, count: int, salt: int) -> Array[Transform3D]:
	var path: String = layout_path(model_scene) if model_scene != null else ""
	if not path.is_empty() and ResourceLoader.exists(path):
		var layout: PackedScene = load(path) as PackedScene
		if layout != null:
			var got: Array[Transform3D] = from_layout(layout)
			if not got.is_empty():
				return got
	return on_surface(model, count, salt)


## The rock's triangles in its own space, as a surface to cast rays at (null for none).
static func surface_of(model: Node3D) -> TriangleMesh:
	var faces: PackedVector3Array = faces_of(model)
	var tm := TriangleMesh.new()
	return tm if not faces.is_empty() and tm.create_from_faces(faces) else null


## The rock's triangles in its own space (every mesh but its nuggets), three points each.
static func faces_of(model: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for n: Node in meshes:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or mi.is_in_group(&"not_solid"):
			continue
		var t: Transform3D = RegentsSolid.relative(model, mi)
		for p: Vector3 in mi.mesh.get_faces():
			faces.append(t * p)
	return faces


## `count` spots round the rock's upper half, each on its surface and lying flat on it (up along the
## surface's normal), sunk `SINK_M` in. `salt` turns the ring (each rock its own).
static func on_surface(model: Node3D, count: int, salt: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var faces: PackedVector3Array = faces_of(model)
	var tm := TriangleMesh.new()
	if faces.is_empty() or not tm.create_from_faces(faces):
		return out
	var box := AABB(faces[0], Vector3.ZERO)
	for f: Vector3 in faces:
		box = box.expand(f)
	var mid: Vector3 = box.get_center()
	var reach: float = box.size.length() + 1.0
	for i: int in count:
		var a: float = TAU * float(i) / float(count) + float(salt % 7)
		var h: float = box.position.y + box.size.y * (0.45 + 0.12 * float(i % 3))
		var aim := Vector3(mid.x, h, mid.z)
		var out_dir := Vector3(cos(a), 0.35, sin(a)).normalized()
		var hit: Dictionary = tm.intersect_ray(aim + out_dir * reach, -out_dir)
		if hit.is_empty():
			hit = tm.intersect_ray(Vector3(aim.x + cos(a) * box.size.x * 0.25, box.end.y + 1.0, aim.z + sin(a) * box.size.z * 0.25), Vector3.DOWN)
		if hit.is_empty():
			continue
		var normal: Vector3 = (hit["normal"] as Vector3).normalized()
		if normal.dot(out_dir) < 0.0:
			normal = -normal   # a face wound the other way: the outside is the way the ray came
		out.append(Transform3D(lying_on(normal, a).scaled(Vector3.ONE * NUGGET_SCALE), (hit["position"] as Vector3) - normal * SINK_M))
	return out


## A basis whose up is `normal`, turned `turn` about it.
static func lying_on(normal: Vector3, turn: float) -> Basis:
	var side: Vector3 = Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = side.cross(normal).normalized()
	var z: Vector3 = x.cross(normal).normalized()
	return Basis(x, normal, z).rotated(normal, turn)
