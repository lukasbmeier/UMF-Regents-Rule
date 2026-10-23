class_name RegentsSolid extends RefCounted
## EVERYTHING YOU SEE STOPS YOU (owner, 2026-10-21: "Every 3d object should have collisions"): a model
## wrapped in its own shape, one convex hull per mesh, so a rock, a station's anvil or a bush blocks the way
## where it is drawn, whatever its size or however it was placed. One StaticBody3D (named "Solid") under the
## node given, on the world's layer (1), colliding with nothing itself. A hull is worked out once per mesh
## and kept (`_hulls`), so a glade of the same rocks costs one each.
##
## Walking through is for what lies low and soft (grass, flowers, ferns, pebbles): `RegentsSolidProps` says
## which of a level's props are solid. Presentation only: the server bounds movement by the level's bake.

## Each mesh's hull, in its own space.
static var _hulls: Dictionary = {}


## A body under `holder` wrapping every mesh under `model` (and `model` itself, when it is one), except
## those in `skip` and those in the "not_solid" group. The body sits at `holder`'s origin; each hull is
## moved into `holder`'s space (scale included: no scaled shape). Null when there was no mesh.
static func wrap(holder: Node3D, model: Node3D, skip: Array[Node] = []) -> StaticBody3D:
	var meshes: Array[MeshInstance3D] = []
	if model is MeshInstance3D:
		meshes.append(model as MeshInstance3D)
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as MeshInstance3D)
	var body: StaticBody3D = null
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null or skip.has(mi) or mi.is_in_group(&"not_solid"):
			continue
		var hull: ConvexPolygonShape3D = hull_of(mi.mesh)
		if hull == null:
			continue
		if body == null:
			body = StaticBody3D.new()
			body.name = "Solid"
			body.collision_layer = 1
			body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = moved(hull, relative(holder, mi))
		body.add_child(shape)
	if body != null:
		holder.add_child(body)
	return body


## `mesh`'s convex hull (simplified), worked out once.
static func hull_of(mesh: Mesh) -> ConvexPolygonShape3D:
	if _hulls.has(mesh):
		return _hulls[mesh] as ConvexPolygonShape3D
	var hull: ConvexPolygonShape3D = mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
	_hulls[mesh] = hull
	return hull


## `hull` with every point moved by `t` (a new shape: the kept one is shared).
static func moved(hull: ConvexPolygonShape3D, t: Transform3D) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	for p: Vector3 in hull.points:
		pts.append(t * p)
	var out := ConvexPolygonShape3D.new()
	out.points = pts
	return out


## Where `node` is in `holder`'s space, from their local transforms (works before either is in the tree).
static func relative(holder: Node3D, node: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != holder:
		var n3: Node3D = n as Node3D
		if n3 != null:
			t = n3.transform * t
		n = n.get_parent()
	return t
