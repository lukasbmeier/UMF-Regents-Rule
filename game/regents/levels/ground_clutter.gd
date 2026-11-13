@tool
class_name RegentsGroundClutter extends Node3D
## A MEADOW, NOT SEVENTY TUFTS (PROGRESS step 59). Put one in a level and list what grows (`kinds`): as the level
## loads it scatters each kind over a square of flat ground round this node, as MultiMeshes (one draw for every tuft
## of a kind in a 24 m cell, no node for each). Soft things only: nothing here is solid, a foe sees through it, the
## server knows none of it.
##
##   WHERE   seeded, so it is the same for everyone and every time. In patches (`patch_m`), thinner where a kind
##           is `patchy`. With a `RegentsGroundPaint` (`paint`) it keeps off trodden dirt and bare soil, and gathers
##           at the rim of the soil: the foot of every rock and tree.
##   FAR     a tuft shrinks into its foot between `draw_distance_m - fade_m` and `draw_distance_m` from the camera
##           (the foliage shader does it: no blending, no pop); a cell past that is not drawn.
##   WEAK MACHINES   every MultiMesh is in the `detail_density` group: Settings' Detail draws half of them on
##           Medium, a quarter on Low (GraphicsQuality). None of them casts a shadow.
##
## In the editor press SCATTER AGAIN after changing anything (it is made as the scene opens, never saved in it). A
## headless process (the referee, a suite) scatters nothing unless asked.
## FLAT GROUND ONLY: everything is put at this node's height. A level with hills needs each one's ground height.

## The level's RegentsGroundPaint, if it has one.
@export var paint: NodePath = ^"../GroundPaint"
## What grows.
@export var kinds: Array[RegentsClutterKind] = []
## The side of the square it covers, centered on this node, and of the cells it is cut into, meters.
@export_range(8.0, 1024.0, 1.0) var extent_m: float = 120.0
@export_range(4.0, 128.0, 1.0) var cell_m: float = 24.0
## How far from the camera clutter is drawn, and over how many meters before that it shrinks away.
@export_range(10.0, 400.0, 1.0) var draw_distance_m: float = 52.0
@export_range(0.0, 100.0, 1.0) var fade_m: float = 14.0
## How wide a patch is, about, meters.
@export_range(2.0, 200.0, 0.5) var patch_m: float = 16.0
@export var scatter_seed: int = 4059
@export_tool_button("Scatter again", "Reload") var scatter_button: Callable = scatter

## More trodden than this and no plant grows; barer soil than this and nothing does (a trunk, a rock's own foot).
const DIRT_MAX: float = 0.3
const SOIL_MAX: float = 0.45
## The rim of a patch of soil or dirt: anything over this.
const RIM_MIN: float = 0.03
## The foot of a rock or a tree: this far out from its soil, meters. And how many more are tried there than on open
## ground (so things gather at a foot, not only survive there).
const FOOT_M: float = 0.9
const FOOT_EXTRA: int = 2

## The MultiMeshInstance3Ds made by the last scatter.
var made: Array[MultiMeshInstance3D] = []
## Where each of them put its own, as this node sees it (one list for each of `made`). Kept here because a
## MultiMesh's transforms cannot be read back in a headless process (its renderer keeps none).
var _where: Array[PackedVector3Array] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	scatter()


## How many are scattered, all kinds together (before Detail thins what is drawn).
func count() -> int:
	var n: int = 0
	for mmi: MultiMeshInstance3D in made:
		n += mmi.multimesh.instance_count
	return n


## Where the `index`th of `made` put its own, in the world.
func places_in(index: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var here: Vector3 = global_position if is_inside_tree() else position
	for at: Vector3 in _where[index]:
		out.append(here + at)
	return out


## Every one's place in the world (one per mesh of a model, so a model of two meshes is there twice).
func places() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in range(made.size()):
		out.append_array(places_in(i))
	return out


func scatter() -> void:
	for old: MultiMeshInstance3D in made:
		if is_instance_valid(old):
			remove_child(old)
			old.queue_free()
	made.clear()
	_where.clear()
	var mask: RegentsGroundPaint = get_node_or_null(paint) as RegentsGroundPaint
	if mask != null and not mask.painted():
		mask.repaint()
	var patches := FastNoiseLite.new()
	patches.seed = scatter_seed
	patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patches.frequency = 1.0 / maxf(patch_m * 2.0, 0.01)
	var cells: int = maxi(1, ceili(extent_m / cell_m))
	for k: int in range(kinds.size()):
		var kind: RegentsClutterKind = kinds[k]
		if kind == null or kind.model == null or kind.per_100_m2 <= 0.0:
			continue
		var parts: Array[Array] = _parts(kind)
		if parts.is_empty():
			push_warning("RegentsGroundClutter: %s has no mesh" % kind.model.resource_path)
			continue
		for cz: int in range(cells):
			for cx: int in range(cells):
				_scatter_cell(k, kind, parts, cx, cz, mask, patches)


func _scatter_cell(k: int, kind: RegentsClutterKind, parts: Array[Array], cx: int, cz: int,
		mask: RegentsGroundPaint, patches: FastNoiseLite) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([scatter_seed, k, cx, cz])
	var corner: Vector2 = Vector2(float(cx) * cell_m - extent_m * 0.5, float(cz) * cell_m - extent_m * 0.5)
	var middle: Vector3 = Vector3(corner.x + cell_m * 0.5, 0.0, corner.y + cell_m * 0.5)
	var here: Vector3 = global_position if is_inside_tree() else position
	var tries: int = roundi(kind.per_100_m2 * cell_m * cell_m / 100.0)
	var placed: Array[Transform3D] = []
	# The first `tries` may grow anywhere; the rest only at a foot (there is none without a painter).
	for i: int in range(tries * (1 + FOOT_EXTRA) if mask != null and kind.at_edges > 0.0 else tries):
		var x: float = corner.x + rng.randf() * cell_m
		var z: float = corner.y + rng.randf() * cell_m
		var s: float = rng.randf_range(kind.min_scale, kind.max_scale)
		var yaw: float = rng.randf() * TAU
		var roll: float = rng.randf()
		if roll >= _chance(kind, here.x + x, here.z + z, mask, patches, i >= tries):
			continue
		placed.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x - middle.x, 0.0, z - middle.z)))
	if placed.is_empty():
		return
	var where := PackedVector3Array()
	for t: Transform3D in placed:
		where.append(middle + t.origin)
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var local: Transform3D = part[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = placed.size()
		for i: int in range(placed.size()):
			mm.set_instance_transform(i, placed[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d_%d" % [kind.model.resource_path.get_file().get_basename(), cx, cz, made.size()]
		mmi.multimesh = mm
		mmi.position = middle
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 0.5
		# A cell goes once its nearest tuft has shrunk to nothing: its corner is cell_m x 0.71 from its middle.
		mmi.visibility_range_end = draw_distance_m + cell_m * 0.75
		mmi.add_to_group(GraphicsQuality.GROUP_DENSITY)
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		made.append(mmi)
		_where.append(where)


## How likely a `kind` grows at a place in the world, 0 to 1 (`foot_only`: nowhere but at a foot).
func _chance(kind: RegentsClutterKind, wx: float, wz: float, mask: RegentsGroundPaint, patches: FastNoiseLite,
		foot_only: bool = false) -> float:
	var dirt: float = mask.dirt_at(wx, wz) if mask != null else 0.0
	var soil: float = mask.soil_at(wx, wz) if mask != null else 0.0
	if soil > SOIL_MAX or (dirt > DIRT_MAX and not kind.on_dirt):
		return 0.0
	var foot: bool = mask != null and at_foot(mask, wx, wz)
	if foot_only and not foot:
		return 0.0
	var patch: float = smoothstep(-0.15, 0.3, patches.get_noise_2d(wx, wz))
	var p: float = lerpf(1.0, patch, kind.patchy)
	if foot:
		p = kind.at_edges if foot_only else maxf(p, kind.at_edges)
	if dirt > RIM_MIN and not kind.on_dirt:
		p *= 0.5
	return p


## Is a place at the foot of a rock or a tree: on the rim of its soil, or within `FOOT_M` of it.
static func at_foot(mask: RegentsGroundPaint, wx: float, wz: float) -> bool:
	return mask.soil_at(wx, wz) > RIM_MIN or mask.soil_at(wx + FOOT_M, wz) > RIM_MIN or mask.soil_at(wx - FOOT_M, wz) > RIM_MIN 		or mask.soil_at(wx, wz + FOOT_M) > RIM_MIN or mask.soil_at(wx, wz - FOOT_M) > RIM_MIN


## A kind's meshes, each with where it sits in its model: [Mesh, Transform3D]. The meshes are copies whose foliage
## materials shrink with distance and sway (the model's own materials, and every other use of it, are untouched).
func _parts(kind: RegentsClutterKind) -> Array[Array]:
	var out: Array[Array] = []
	var root: Node = kind.model.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		found.append(root)
	for n: Node in found:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var mesh: Mesh = mi.mesh.duplicate() as Mesh
		for i: int in range(mesh.get_surface_count()):
			var mat: ShaderMaterial = mesh.surface_get_material(i) as ShaderMaterial
			if mat == null or not (mat.shader == FoliageMaterial.SHADER_CUTOUT or mat.shader == FoliageMaterial.SHADER_OPAQUE):
				continue
			var own: ShaderMaterial = mat.duplicate() as ShaderMaterial
			own.set_shader_parameter(&"shrink_from_m", maxf(draw_distance_m - fade_m, 0.01))
			own.set_shader_parameter(&"shrink_to_m", draw_distance_m)
			own.set_shader_parameter(&"sway_m", kind.sway_m)
			var base: Variant = mat.get_shader_parameter(&"albedo")
			own.set_shader_parameter(&"albedo", (base as Color if base is Color else Color.WHITE) * kind.tint)
			mesh.surface_set_material(i, own)
		out.append([mesh, _under(mi, root)])
	root.free()
	return out


## `n`'s transform as its model's root sees it (the model is not in the tree).
static func _under(n: Node3D, root: Node) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		var n3: Node3D = at as Node3D
		if n3 != null:
			t = n3.transform * t
		at = at.get_parent()
	var top: Node3D = root as Node3D
	return top.transform * t if top != null and n != root else t
