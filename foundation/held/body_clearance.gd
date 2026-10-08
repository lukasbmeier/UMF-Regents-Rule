@tool
class_name BodyClearance
## HOW MUCH AIR A HELD ITEM HAS OFF THE BODY (DECISIONS #153): a reel against the thigh, a sword's
## pommel against the hip, a shield's rim against the chest. Measured in the held-item preview
## through a whole clip, and by tests on the real rig.
##
## The body is capsules round its bones (`HUMANOID`, the Quaternius skeleton; radii measured off
## the trousers' and shirts' vertices). An item says which of its points to measure with a
## `clearance_radius` meta on the node (Inspector ▸ Metadata ▸ Add, a float in metres): the rod's
## `Reel` carries 0.038. A node that also carries `clearance_to` (a NodePath from that node) is
## a LINE from it to that node, as thick as its radius: a blade, a spear, the rod's blank (its
## `Shaft`, to `Tip`), whose middle can pass through a head while both ends stay clear (#156).

## [name, from bone, to bone, radius (m)]. A bone with no `to` is a ball.
const HUMANOID: Array[Array] = [
	["right thigh", &"thigh_r", &"calf_r", 0.10],
	["right shin", &"calf_r", &"foot_r", 0.09],
	["left thigh", &"thigh_l", &"calf_l", 0.10],
	["left shin", &"calf_l", &"foot_l", 0.09],
	["torso", &"spine_01", &"neck_01", 0.12],
	["head", &"Head", &"", 0.12],
]
## The meta an item's node carries to be measured, the one that makes it a line, and how far
## above the head bone the head's centre is.
const META: StringName = &"clearance_radius"
const LINE_TO: StringName = &"clearance_to"
const HEAD_UP: float = 0.09


## The least air between a ball at `point` (world space) of `radius` and any part of the posed
## `skeleton`, in metres (negative: inside), and which part: {"air": float, "part": String}.
static func measure(skeleton: Skeleton3D, point: Vector3, radius: float,
		parts: Array[Array] = HUMANOID) -> Dictionary:
	return measure_line(skeleton, point, point, radius, parts)


## The same for a LINE from `from` to `to` (a rod's blank), `radius` thick.
static func measure_line(skeleton: Skeleton3D, from: Vector3, to: Vector3, radius: float,
		parts: Array[Array] = HUMANOID) -> Dictionary:
	return measure_posed(posed(skeleton, parts), from, to, radius)


## The body's parts as it is posed now, in world space: [name, from, to, radius] each (a ball's
## from and to are its centre). Read once per pose when many placings of an item are tried
## against it (`GripFit`).
static func posed(skeleton: Skeleton3D, parts: Array[Array] = HUMANOID) -> Array[Array]:
	var out: Array[Array] = []
	for p: Array in parts:
		var a: Vector3 = bone_at(skeleton, p[1] as StringName)
		if a == Vector3.INF:
			continue
		if StringName(p[2]).is_empty():
			var i: int = skeleton.find_bone(String(p[1]))
			var up: Vector3 = (skeleton.global_basis * skeleton.get_bone_global_pose(i).basis).y.normalized()
			var centre: Vector3 = a + up * HEAD_UP
			out.append([String(p[0]), centre, centre, float(p[3])])
		else:
			var b: Vector3 = bone_at(skeleton, p[2] as StringName)
			if b == Vector3.INF:
				continue
			out.append([String(p[0]), a, b, float(p[3])])
	return out


## The least air between a line (or a point: `from` == `to`) `radius` thick and a body's `posed`
## parts: {"air": float, "part": String}.
static func measure_posed(parts: Array[Array], from: Vector3, to: Vector3, radius: float) -> Dictionary:
	var best: float = INF
	var name: String = ""
	for p: Array in parts:
		var air: float = between_segments(from, to, p[1] as Vector3, p[2] as Vector3) - float(p[3]) - radius
		if air < best:
			best = air
			name = String(p[0])
	return {"air": best, "part": name}


## The nodes of an item that are measured: those with a `clearance_radius` meta.
static func points_of(item: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if item == null:
		return out
	var n3: Node3D = item as Node3D
	if n3 != null and item.has_meta(META):
		out.append(n3)
	for n: Node in item.find_children("*", "Node3D", true, false):
		if n.has_meta(META):
			out.append(n as Node3D)
	return out


## The least air of every measured point (or line) of `item` as it sits now: {"air", "part",
## "point"}.
static func item_air(skeleton: Skeleton3D, item: Node) -> Dictionary:
	var best: Dictionary = {"air": INF, "part": "", "point": ""}
	for n: Node3D in points_of(item):
		var to: Node3D = n.get_node_or_null(n.get_meta(LINE_TO) as NodePath) as Node3D \
			if n.has_meta(LINE_TO) else null
		var end: Vector3 = to.global_position if to != null else n.global_position
		var r: Dictionary = measure_line(skeleton, n.global_position, end, float(n.get_meta(META)))
		if float(r["air"]) < float(best["air"]):
			best = {"air": r["air"], "part": r["part"], "point": String(n.name)}
	return best


static func bone_at(skeleton: Skeleton3D, bone: StringName) -> Vector3:
	var i: int = skeleton.find_bone(String(bone))
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.INF


static func to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The least distance between the segments p1-p2 and q1-q2 (either may be a single point).
static func between_segments(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	if p1.is_equal_approx(p2):
		return to_segment(p1, q1, q2)
	if q1.is_equal_approx(q2):
		return to_segment(q1, p1, p2)
	var c: PackedVector3Array = Geometry3D.get_closest_points_between_segments(p1, p2, q1, q2)
	return c[0].distance_to(c[1])
