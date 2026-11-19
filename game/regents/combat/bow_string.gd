class_name BowString extends Node3D
## THE BOWSTRING, DRAWN BACK INTO A V, AND THE ARROW ON IT (Luke, 2026-11-18: "is there a way to get the string to pull
## back into a V while drawing and show an arrow nocked?"). A child of a bow's held-item scene (`yew_bow.tscn`).
##
## The model's own string (one surface of its mesh, `string_surface`) is hidden and drawn here instead, as two thin
## pieces from the limbs' tips to a NOCK POINT: at rest the middle of the string (a straight line, as the model had it);
## while the body holds a draw pose (`pose.bow_draw` / `pose.bow_aim` on the upper body, which every client shows, for
## another player's draw too), the drawing hand's fingers, and an arrow lies from the nock over the riser. Only while
## the hand is behind the string, within `max_draw_m` of it and on the bow's plane (`plane_m`) does it take the string (a
## hand still reaching over the shoulder for an arrow does not stretch it). Let go (the pose blends out), it snaps back.
##
## Presentation only (hard rule 11): it reads the pose the driver shows and where the bones are, and decides nothing.
## Made in code from the model's own parts: no image, no new mesh file.

## The bow's model (its first MeshInstance3D is the bow).
@export var model_path: NodePath = ^"../Model"
## Which surface of the bow's mesh is its string (the model's white cord).
@export var string_surface: int = 2
## The fingers that hold the string: the nock is between them.
@export var draw_bones: Array[StringName] = [&"index_02_r", &"middle_02_r"]
## Farthest the string is taken from its rest (m): a hand farther off has not got hold of it.
@export_range(0.1, 2.0, 0.01, "suffix:m") var max_draw_m: float = 0.85
## Farthest a hand may be off the bow's plane (the plane of its string and riser) and still hold the string (m): a hand
## reaching over the shoulder for an arrow is well off it.
@export_range(0.01, 0.5, 0.01, "suffix:m") var plane_m: float = 0.12
## How much of the draw pose must show before the string goes to the hand.
@export_range(0.0, 1.0, 0.01) var pose_from: float = 0.35
## The string's thickness (m).
@export_range(0.001, 0.02, 0.0005, "suffix:m") var radius_m: float = 0.0035
## The arrow shown on the string while drawn (none: no arrow), and its length (m).
@export var arrow_scene: PackedScene = preload("res://game/regents/art/weapons/Arrow.fbx")
@export_range(0.2, 2.0, 0.01, "suffix:m") var arrow_length_m: float = 0.78

const DRAW_POSES: Array[StringName] = [&"pose.bow_draw", &"pose.bow_aim"]

## Where the string is, in this node's space: its tips, its middle at rest, the riser the arrow lies over.
var tip_a: Vector3 = Vector3.ZERO
var tip_b: Vector3 = Vector3.ZERO
var rest_nock: Vector3 = Vector3.ZERO
var riser: Vector3 = Vector3.ZERO
## Where the string is taken to now (this node's space), and whether a hand holds it.
var nock: Vector3 = Vector3.ZERO
var held: bool = false

var _ready_ok: bool = false
## The bow's mesh, and the string's tips and the riser in ITS space; how that space sits in this node's as last fitted
## (the bow's size or place changed since: fitted again, `_fit_to_model`).
var _mesh_node: MeshInstance3D = null
var _m_tip_a: Vector3 = Vector3.ZERO
var _m_tip_b: Vector3 = Vector3.ZERO
var _m_riser: Vector3 = Vector3.ZERO
var _fit: Transform3D = Transform3D()
var _fitted: bool = false
var _skeleton: Skeleton3D = null
var _driver: AnimationDriverComponent = null
var _bones: PackedInt32Array = PackedInt32Array()
var _piece_a: MeshInstance3D = null
var _piece_b: MeshInstance3D = null
var _arrow: Node3D = null
var _drawn_poses: Array[StringName] = []

## The mesh with its string taken out, one per bow mesh (shared by every bow of that model).
static var _stripped: Dictionary[RID, ArrayMesh] = {}


func _ready() -> void:
	var model: Node = get_node_or_null(model_path)
	var mi: MeshInstance3D = _first_mesh(model) if model != null else null
	if mi == null or mi.mesh == null or string_surface < 0 or string_surface >= mi.mesh.get_surface_count():
		push_warning("BowString: no bow mesh with a string surface %d under %s" % [string_surface, model_path])
		return
	_mesh_node = mi
	_measure(mi.mesh)
	_fit_to_model()
	var string_mat: Material = mi.get_active_material(string_surface)
	mi.mesh = _without_string(mi.mesh, string_surface)
	_piece_a = _piece(string_mat)
	_piece_b = _piece(string_mat)
	if arrow_scene != null:
		_arrow = _arrow_node(arrow_scene)
		_arrow.visible = false
	nock = rest_nock
	_place()
	_ready_ok = true
	_connect.call_deferred()   # after the held item's own (it moves the bow on the same signal first)


func _exit_tree() -> void:
	if _skeleton != null and is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_update):
		_skeleton.skeleton_updated.disconnect(_update)


# ---------------------------------------------------------------- following the hand

func _connect() -> void:
	var n: Node = get_parent()
	while n != null and not (n is Skeleton3D):
		n = n.get_parent()
	_skeleton = n as Skeleton3D
	if _skeleton == null:
		return   # a bow on a rack, in a hand-less preview: the string stays straight
	_bones.clear()
	for b: StringName in draw_bones:
		var i: int = _skeleton.find_bone(String(b))
		if i >= 0:
			_bones.append(i)
	_skeleton.skeleton_updated.connect(_update)


## The body's animation driver: the held item's, else the nearest one up the tree (a showcase's actor).
func _find_driver() -> AnimationDriverComponent:
	var item: HeldItem = get_parent() as HeldItem
	if item != null and item.driver != null:
		return item.driver
	var n: Node = _skeleton
	while n != null:
		for c: Node in n.get_children():
			if c is AnimationDriverComponent:
				return c as AnimationDriverComponent
			for cc: Node in c.get_children():
				if cc is AnimationDriverComponent:
					return cc as AnimationDriverComponent
		n = n.get_parent()
	return null


## Whether the body shows a draw: the upper-body pose is one of the bow's, enough of it.
func drawing() -> bool:
	if _driver == null or not is_instance_valid(_driver):
		_driver = _find_driver()
		if _driver == null:
			return false
		_drawn_poses.clear()
	if _drawn_poses.is_empty() and _driver.animation_set != null:
		for p: StringName in DRAW_POSES:
			var n: StringName = _driver.animation_set.anim_name(p)
			if not n.is_empty():
				_drawn_poses.append(n)
	return _driver.upper_pose_weight() >= pose_from and _drawn_poses.has(_driver.upper_pose_clip())


## Where the drawing fingers are, in this node's space (INF without them).
func hand_point() -> Vector3:
	if _skeleton == null or _bones.is_empty():
		return Vector3.INF
	var sum: Vector3 = Vector3.ZERO
	for b: int in _bones:
		sum += _skeleton.global_transform * _skeleton.get_bone_global_pose(b).origin
	return global_transform.affine_inverse() * (sum / float(_bones.size()))


## Whether a hand at `p` (this node's space) has hold of the string: behind it (away from the riser), near enough, and
## on the bow's plane.
func takes(p: Vector3) -> bool:
	if p == Vector3.INF:
		return false
	var back: Vector3 = (rest_nock - riser).normalized()
	var side: Vector3 = (tip_a - tip_b).cross(back).normalized()
	var behind: bool = (p - rest_nock).dot(back) > -0.02
	var near: bool = p.distance_to(rest_nock) <= max_draw_m
	var on_plane: bool = absf((p - rest_nock).dot(side)) <= plane_m
	return behind and near and on_plane


func _update() -> void:
	if not _ready_ok or not is_inside_tree():
		return
	var refitted: bool = _fit_to_model()
	var was: bool = held
	var p: Vector3 = hand_point() if drawing() else Vector3.INF
	held = takes(p)
	if not held and not was and not refitted:
		return   # at rest and still at rest: nothing moves
	nock = p if held else rest_nock
	_place()


## Put the two pieces and the arrow where the nock is now.
func _place() -> void:
	_span(_piece_a, tip_a, nock)
	_span(_piece_b, tip_b, nock)
	if _arrow != null:
		_arrow.visible = held
		if held:
			var ahead: Vector3 = riser - nock
			if ahead.length() < 0.01:
				ahead = riser - rest_nock
			var fwd: Vector3 = ahead.normalized()
			var up: Vector3 = (tip_a - tip_b).normalized()
			if absf(up.dot(fwd)) > 0.95:
				up = Vector3.UP
			var b := Basis.looking_at(fwd, up)
			_arrow.transform = Transform3D(b.scaled_local(Vector3.ONE * arrow_length_m), nock)


static func _span(piece: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d: Vector3 = to - from
	var length: float = maxf(d.length(), 0.0001)
	var y: Vector3 = d / length
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	piece.transform = Transform3D(Basis(x, y * length, z), (from + to) * 0.5)


# ---------------------------------------------------------------- built once

## Where the model's mesh sits in this node's space now; when that changed (a bigger bow, a bow turned), the string's
## tips, its middle and the riser are put there again. Whether it changed.
func _fit_to_model() -> bool:
	if _mesh_node == null or not is_instance_valid(_mesh_node):
		return false
	var fit: Transform3D = transform.affine_inverse() * _up_to_parent(_mesh_node)
	if _fitted and fit.is_equal_approx(_fit):
		return false
	_fit = fit
	_fitted = true
	tip_a = fit * _m_tip_a
	tip_b = fit * _m_tip_b
	rest_nock = (tip_a + tip_b) * 0.5
	riser = fit * _m_riser
	if not held:
		nock = rest_nock
	return true


## `n`'s transform in this node's parent's space (`n` is under that parent).
func _up_to_parent(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != get_parent():
		var c3: Node3D = c as Node3D
		if c3 != null:
			t = c3.transform * t
		c = c.get_parent()
	return t


## The string's tips (its ends along its length) and the riser (the wood at mid height), in the mesh's own space.
func _measure(mesh: Mesh) -> void:
	var cord: PackedVector3Array = mesh.surface_get_arrays(string_surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var box := AABB(cord[0], Vector3.ZERO)
	for v: Vector3 in cord:
		box = box.expand(v)
	var axis: int = box.get_longest_axis_index()
	var lo: float = box.position[axis]
	var hi: float = box.end[axis]
	var near: float = (hi - lo) * 0.02
	var sum_lo := Vector3.ZERO
	var sum_hi := Vector3.ZERO
	var n_lo: int = 0
	var n_hi: int = 0
	for v: Vector3 in cord:
		if v[axis] <= lo + near:
			sum_lo += v
			n_lo += 1
		elif v[axis] >= hi - near:
			sum_hi += v
			n_hi += 1
	_m_tip_a = sum_hi / float(maxi(n_hi, 1))
	_m_tip_b = sum_lo / float(maxi(n_lo, 1))
	# The riser: the bow's wood within a few percent of the string's middle, along the string.
	var mid: float = (lo + hi) * 0.5
	var band: float = (hi - lo) * 0.05
	var sum := Vector3.ZERO
	var count: int = 0
	for s: int in mesh.get_surface_count():
		if s == string_surface:
			continue
		for v: Vector3 in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v[axis] - mid) <= band:
				sum += v
				count += 1
	_m_riser = sum / float(count) if count > 0 else (_m_tip_a + _m_tip_b) * 0.5 + Vector3.FORWARD * 0.15


static func _without_string(mesh: Mesh, surface: int) -> ArrayMesh:
	var key: RID = mesh.get_rid()
	if _stripped.has(key):
		return _stripped[key]
	var out := ArrayMesh.new()
	for s: int in mesh.get_surface_count():
		if s == surface:
			continue
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	_stripped[key] = out
	return out


func _piece(mat: Material) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius_m
	cyl.bottom_radius = radius_m
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi, false, Node.INTERNAL_MODE_BACK)
	return mi


## The arrow, wrapped so its nock end is at the wrapper's origin, pointing down -Z, one meter long.
func _arrow_node(scene: PackedScene) -> Node3D:
	var wrap := Node3D.new()
	add_child(wrap, false, Node.INTERNAL_MODE_BACK)
	var arrow: Node3D = scene.instantiate() as Node3D
	wrap.add_child(arrow)
	var mi: MeshInstance3D = _first_mesh(arrow)
	if mi == null or mi.mesh == null:
		return wrap
	var to_root: Transform3D = _relative(mi, arrow)
	var box := AABB()
	var first: bool = true
	var steel := Vector3.ZERO
	var n_steel: int = 0
	for s: int in mi.mesh.get_surface_count():
		var steel_part: bool = mi.mesh.surface_get_material(s) != null and mi.mesh.surface_get_material(s).resource_name.contains("Steel")
		for v: Vector3 in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var p: Vector3 = to_root * v
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
			if steel_part:
				steel += p
				n_steel += 1
	var axis: int = box.get_longest_axis_index()
	var length: float = maxf(box.size[axis], 0.0001)
	var head_hi: bool = n_steel == 0 or (steel / float(n_steel))[axis] > box.get_center()[axis]
	var along := Vector3.ZERO
	along[axis] = 1.0 if head_hi else -1.0
	# Its long axis onto -Z, its tail (the end away from the head) at the origin, one meter long.
	var tail: Vector3 = box.get_center() - along * length * 0.5
	var turn: Basis = Basis(Vector3.UP, PI) if along.dot(Vector3.FORWARD) < -0.99 else Basis(Quaternion(along, Vector3.FORWARD))
	arrow.transform = Transform3D(turn.scaled(Vector3.ONE / length), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -tail)
	return wrap


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c: Node in n.get_children():
		var f: MeshInstance3D = _first_mesh(c)
		if f != null:
			return f
	return null


## `from`'s transform in `to`'s space (an ancestor or a sibling's subtree through their common parent), by their local
## transforms: right at `_ready`, before global transforms are worked out.
static func _relative(from: Node3D, to: Node3D) -> Transform3D:
	return _to_root(to).affine_inverse() * _to_root(from)


static func _to_root(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null:
		var c3: Node3D = c as Node3D
		if c3 != null:
			t = c3.transform * t
		c = c.get_parent()
	return t
