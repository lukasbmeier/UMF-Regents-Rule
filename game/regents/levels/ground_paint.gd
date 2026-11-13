@tool
class_name RegentsGroundPaint extends Node3D
## THE GROUND WEARS WHERE THE LEVEL IS USED (PROGRESS step 59). Put one in a level whose ground is drawn by
## `glade_ground.gdshader` and give it that material: as the level loads it paints a picture of the level from above
## and hands it to the shader. Nothing is painted by hand; move a marker and its patch moves with it.
##
##   TRODDEN DIRT (red)   under every LevelPoint whose kind is in `worn_kinds` (a station, a training dummy);
##                        along every Path3D that is a CHILD of this node (a trail: draw its curve in the editor);
##                        round every plain Marker3D that is a child of this node (a worn patch as wide as its
##                        gizmo: Gizmo Extents is its radius in meters).
##   BARE SOIL (green)    under every gathering node's point (a tree, a rock) except the ones in `grass_tags`
##                        (a plant that grows in the grass), and under every decor model named in `rock_models`.
##
## `RegentsGroundClutter` reads the same picture (`dirt_at`, `soil_at`), so grass keeps off the trails and gathers
## at the foot of rocks and trees. In the editor press REPAINT after moving things (the picture is made as the scene
## opens; it is never saved in the scene). A headless process (the referee, a suite) paints nothing unless asked.

## The ground's material: a ShaderMaterial of `glade_ground.gdshader` (the same one the ground itself has).
@export var material: ShaderMaterial = null
## Where to look for the level's points and decor.
@export var level: NodePath = ^".."
## The side of the square it paints, centered on this node, meters; and its picture's side, pixels.
@export_range(16.0, 1024.0, 1.0) var extent_m: float = 128.0
@export_range(64, 2048, 1) var resolution: int = 512

@export_group("Trodden dirt")
## LevelPoint kinds that wear the ground, and how far round each.
@export var worn_kinds: PackedStringArray = PackedStringArray(["station", "dummy", "guide"])
@export_range(0.5, 10.0, 0.1) var worn_radius_m: float = 2.3
## How wide a trail (a child Path3D) is worn, and how far it wanders off its line, meters.
@export_range(0.4, 8.0, 0.1) var trail_width_m: float = 1.7
@export_range(0.0, 3.0, 0.05) var trail_wander_m: float = 0.45

@export_group("Bare soil")
## Soil reaches this far past a gathering node's own radius, and past a rock's widest side.
@export_range(0.0, 6.0, 0.1) var soil_margin_m: float = 1.5
## Gathering nodes that grow in the grass: no soil under them (a point's first tag).
@export var grass_tags: PackedStringArray = PackedStringArray(["Flax"])
## Decor that sits in soil: a model whose file's name starts with one of these.
@export var rock_models: PackedStringArray = PackedStringArray(["Rock_"])

@export_group("")
@export_tool_button("Repaint", "Reload") var repaint_button: Callable = repaint

## How far in from a patch's edge it starts to thin (a share of its radius).
const SOFT_FROM: float = 0.6
const KIND_NODE: String = "node"
## Which byte of a pixel: trodden dirt, bare soil.
const RED: int = 0
const GREEN: int = 1

var _image: Image = null
var _texture: ImageTexture = null
## The picture's bytes, three a pixel (red, green, unused blue), row by row.
var _bytes: PackedByteArray = PackedByteArray()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	repaint()


## Has it painted (a headless process has not, until `repaint` is called).
func painted() -> bool:
	return _image != null


## Paint the picture from the level as it is now and hand it to the material.
func repaint() -> void:
	_bytes.resize(resolution * resolution * 3)
	_bytes.fill(0)
	var root: Node = get_node_or_null(level)
	if root != null:
		for found: Node in root.find_children("*", "Marker3D", true, false):
			var point: LevelPoint = found as LevelPoint
			if point == null:
				continue
			var at: Vector3 = _local(point)
			if worn_kinds.has(point.kind):
				_stamp(RED, at.x, at.z, worn_radius_m)
			elif point.kind == KIND_NODE and not (point.tags.size() > 0 and grass_tags.has(point.tags[0])):
				_stamp(GREEN, at.x, at.z, point.radius + soil_margin_m)
		for found: Node in root.find_children("*", "MeshInstance3D", true, false):
			var owner_scene: Node3D = _model_root(found, root)
			if owner_scene == null or not _is_rock(owner_scene.scene_file_path):
				continue
			var mi: MeshInstance3D = found as MeshInstance3D
			var box: AABB = mi.get_aabb()
			var s: Vector3 = mi.global_transform.basis.get_scale()
			var at: Vector3 = _local(mi)
			_stamp(GREEN, at.x, at.z, maxf(box.size.x * s.x, box.size.z * s.z) * 0.5 + soil_margin_m * 0.6)
	for child: Node in get_children():
		var trail: Path3D = child as Path3D
		if trail != null and trail.curve != null:
			_stamp_trail(trail)
		elif child is Marker3D and not (child is LevelPoint):
			var patch: Marker3D = child as Marker3D
			_stamp(RED, patch.position.x, patch.position.z, patch.gizmo_extents)
	_image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGB8, _bytes)
	_texture = ImageTexture.create_from_image(_image)
	if material != null:
		# Straight to the renderer: set on the material itself, the editor would save the picture in the scene.
		RenderingServer.material_set_param(material.get_rid(), &"mask", _texture.get_rid())
		RenderingServer.material_set_param(material.get_rid(), &"mask_center", Vector2(global_position.x, global_position.z))
		RenderingServer.material_set_param(material.get_rid(), &"mask_extent_m", extent_m)


## How trodden the ground is at a place in the world, 0 to 1 (0 off the picture, and before it is painted).
func dirt_at(x: float, z: float) -> float:
	return _read(RED, x, z)


## How bare the soil is at a place in the world, 0 to 1.
func soil_at(x: float, z: float) -> float:
	return _read(GREEN, x, z)


func _read(channel: int, x: float, z: float) -> float:
	if _bytes.is_empty():
		return 0.0
	var px: int = _pixel(x - global_position.x)
	var pz: int = _pixel(z - global_position.z)
	if px < 0 or pz < 0 or px >= resolution or pz >= resolution:
		return 0.0
	return float(_bytes[(pz * resolution + px) * 3 + channel]) / 255.0


## `n`'s place as this node sees it (the picture is centered on this node).
func _local(n: Node3D) -> Vector3:
	return n.global_position - global_position


func _pixel(offset_m: float) -> int:
	return floori((offset_m / extent_m + 0.5) * float(resolution))


## A round patch, full in the middle and thinning to nothing at `radius` (the larger of what is there and it).
## The picture's outermost pixels are left empty: the shader reads its edge for everything beyond it.
func _stamp(channel: int, x: float, z: float, radius: float) -> void:
	if radius <= 0.0:
		return
	var per_m: float = float(resolution) / extent_m
	var x0: int = maxi(1, _pixel(x - radius))
	var x1: int = mini(resolution - 2, _pixel(x + radius))
	var z0: int = maxi(1, _pixel(z - radius))
	var z1: int = mini(resolution - 2, _pixel(z + radius))
	for pz: int in range(z0, z1 + 1):
		var dz: float = (float(pz) + 0.5) / per_m - extent_m * 0.5 - z
		for px: int in range(x0, x1 + 1):
			var dx: float = (float(px) + 0.5) / per_m - extent_m * 0.5 - x
			var d: float = sqrt(dx * dx + dz * dz) / radius
			if d >= 1.0:
				continue
			var v: int = roundi(255.0 * (1.0 - smoothstep(SOFT_FROM, 1.0, d)))
			var i: int = (pz * resolution + px) * 3 + channel
			if v > _bytes[i]:
				_bytes[i] = v


## A trail: patches along the curve, wandering a little to either side so it is not a ruled line.
func _stamp_trail(trail: Path3D) -> void:
	var points: PackedVector3Array = trail.curve.get_baked_points()
	if points.size() < 2:
		return
	var wander := FastNoiseLite.new()
	wander.seed = hash(String(trail.name))
	wander.frequency = 0.09
	var walked: float = 0.0
	var last: Vector3 = trail.position + trail.transform.basis * points[0]
	for i: int in range(points.size()):
		var at: Vector3 = trail.position + trail.transform.basis * points[i]
		var next: Vector3 = trail.position + trail.transform.basis * points[mini(i + 1, points.size() - 1)]
		walked += at.distance_to(last)
		last = at
		var along: Vector3 = next - at if i + 1 < points.size() else at - (trail.position + trail.transform.basis * points[i - 1])
		var side: Vector3 = Vector3(-along.z, 0.0, along.x).normalized() * wander.get_noise_1d(walked) * trail_wander_m * 2.0
		_stamp(RED, at.x + side.x, at.z + side.z, trail_width_m * 0.5 * (1.0 + 0.25 * wander.get_noise_1d(walked + 500.0)))


## The instanced model `n` belongs to: the nearest node above it (or itself) that came from a scene file, under
## `root`. Null for a mesh that is the level's own.
static func _model_root(n: Node, root: Node) -> Node3D:
	var at: Node = n
	while at != null and at != root:
		if not at.scene_file_path.is_empty():
			return at as Node3D
		at = at.get_parent()
	return null


func _is_rock(scene_path: String) -> bool:
	var file: String = scene_path.get_file()
	for prefix: String in rock_models:
		if file.begins_with(prefix):
			return true
	return false
