class_name CarveStage extends SubViewportContainer
## WOODWORKING'S 3D STAGE: THE CARVE (Luke, 2026-11-07: "vertical and have wood you can take off from either side").
## A yew stave stands upright on the game's own workbench (Quaternius's), in rows from the top; each row is a block whose
## LEFT and RIGHT edges move apart from its middle line, so the two sides can differ (a bow's back and belly). A carving
## knife floats beside it (no character on a stage) and comes in from the side cut, throwing chips. `CarveMinigame` draws
## the profiles over it and tells it what `CarveModel` says: PRESENTATION ONLY. Built in code round the bench model,
## placed by the model's own size (its top is where the stave stands), in its own world.

## The stave's height above the bench, its thickness (toward the camera), and one unit of an edge in meters.
@export var stave_height: float = 0.78
@export var stave_depth: float = 0.05
@export var unit_width: float = 0.016
## How far from its edge the knife rests, and how long its stroke in takes.
@export var knife_rest: float = 0.07
@export var knife_in_s: float = 0.07

const BENCH: PackedScene = preload("res://game/regents/art/props/Workbench.gltf")
const CUT_SOUND: AudioStream = preload("res://game/regents/art/sound/woodcutting/chop.wav")
const WOOD: Color = Color(0.58, 0.27, 0.15)        # yew: a deep red-brown, against the bench's pale top
const WOOD_HOVER: Color = Color(0.78, 0.42, 0.24)
const STEEL: Color = Color(0.72, 0.74, 0.78)
const HANDLE: Color = Color(0.32, 0.20, 0.12)

var viewport: SubViewport
var camera: Camera3D
## The stave's bottom middle (on the bench's top).
var base: Vector3 = Vector3.ZERO
var _stage: Node3D
var _rows: Array[MeshInstance3D] = []
var _wood: StandardMaterial3D
var _hover_wood: StandardMaterial3D
var _n: int = 0
var _left: PackedInt32Array = PackedInt32Array()
var _right: PackedInt32Array = PackedInt32Array()
var _knife: Node3D
var _chips: CPUParticles3D
var _sound: AudioStreamPlayer
var _stroke_age: float = 10.0
var _aim: Vector3 = Vector3.ZERO
var _aim_side: int = 0   # 0 the left, 1 the right


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the clicks
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	_stage = Node3D.new()
	viewport.add_child(_stage)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.08, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.48)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_stage.add_child(sun)
	var bench: Node3D = BENCH.instantiate() as Node3D
	_stage.add_child(bench)
	var box: AABB = _bounds(bench)
	base = Vector3(box.get_center().x, box.end.y, box.get_center().z + box.size.z * 0.15)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.2
	lamp.omni_range = 4.0
	lamp.position = base + Vector3(-0.6, 0.9, 0.9)
	_stage.add_child(lamp)
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.30, 0.25, 0.20)
	floor_mesh.material = floor_mat
	var floor_inst: MeshInstance3D = MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.position.y = box.position.y
	_stage.add_child(floor_inst)
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = WOOD
	_wood.roughness = 0.85
	_hover_wood = StandardMaterial3D.new()
	_hover_wood.albedo_color = WOOD_HOVER
	_hover_wood.roughness = 0.85
	_knife = _make_knife()
	_stage.add_child(_knife)
	_chips = CPUParticles3D.new()
	_chips.emitting = false
	_chips.one_shot = true
	_chips.explosiveness = 1.0
	_chips.amount = 14
	_chips.lifetime = 0.7
	var chip_mesh: BoxMesh = BoxMesh.new()
	chip_mesh.size = Vector3(0.012, 0.004, 0.008)
	var chip_mat: StandardMaterial3D = StandardMaterial3D.new()
	chip_mat.albedo_color = WOOD_HOVER
	chip_mesh.material = chip_mat
	_chips.mesh = chip_mesh
	_chips.spread = 50.0
	_chips.initial_velocity_min = 0.5
	_chips.initial_velocity_max = 1.3
	_chips.gravity = Vector3(0.0, -6.0, 0.0)
	_stage.add_child(_chips)
	camera = Camera3D.new()
	camera.fov = 40.0
	_stage.add_child(camera)
	var mid: Vector3 = base + Vector3(0.0, stave_height * 0.5, 0.0)
	camera.position = mid + Vector3(0.0, 0.1, 1.75)
	camera.look_at(mid + Vector3(0.0, 0.07, 0.0))   # a little above the middle: the round's title is over the top
	camera.current = true
	_sound = AudioStreamPlayer.new()
	_sound.stream = CUT_SOUND
	add_child(_sound)
	_aim = mid + Vector3(-0.2, 0.0, stave_depth)


## The bench model's bounds (every mesh in it).
static func _bounds(root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = node as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0.0, -0.3), Vector3(1.0, 0.9, 0.6))


## A carving knife lying flat, its blade pointing +x from its handle (its tip at the node's origin).
func _make_knife() -> Node3D:
	var root: Node3D = Node3D.new()
	var blade: BoxMesh = BoxMesh.new()
	blade.size = Vector3(0.07, 0.022, 0.006)
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = STEEL
	steel.metallic = 0.8
	steel.roughness = 0.3
	blade.material = steel
	var blade_inst: MeshInstance3D = MeshInstance3D.new()
	blade_inst.mesh = blade
	blade_inst.position = Vector3(-0.035, 0.0, 0.0)
	root.add_child(blade_inst)
	var grip: CylinderMesh = CylinderMesh.new()
	grip.top_radius = 0.012
	grip.bottom_radius = 0.014
	grip.height = 0.10
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = HANDLE
	grip.material = wood
	var grip_inst: MeshInstance3D = MeshInstance3D.new()
	grip_inst.mesh = grip
	grip_inst.rotation.z = PI * 0.5
	grip_inst.position = Vector3(-0.12, 0.0, 0.0)
	root.add_child(grip_inst)
	return root


## A stave of `n` rows.
func build(n: int) -> void:
	for r: MeshInstance3D in _rows:
		r.queue_free()
	_rows.clear()
	_n = n
	for i: int in n:
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(1.0, row_height() * 0.985, stave_depth)
		var inst: MeshInstance3D = MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _wood
		_stage.add_child(inst)
		_rows.append(inst)


func row_height() -> float:
	return stave_height / float(maxi(1, _n))


## The middle of row `i` (row 0 at the top), world y.
func row_y(i: int) -> float:
	return base.y + stave_height - (float(i) + 0.5) * row_height()


## The stave now: each row's left and right edge, and the row and side under the mouse (-1: none).
func show_stave(left: PackedInt32Array, right: PackedInt32Array, hover_row: int, hover_side: int) -> void:
	_left = left
	_right = right
	for i: int in mini(left.size(), _rows.size()):
		var w: float = maxf(0.002, float(left[i] + right[i]) * unit_width)
		_rows[i].scale = Vector3(w, 1.0, 1.0)
		_rows[i].position = Vector3(base.x + float(right[i] - left[i]) * 0.5 * unit_width, row_y(i), base.z)
		_rows[i].material_override = _hover_wood if i == hover_row else _wood
	if hover_row >= 0 and hover_row < left.size() and _stroke_age > knife_in_s + 0.25:
		_aim_side = hover_side
		_aim = _edge(hover_row, hover_side)


## Row `i`'s edge on `side` (0 left, 1 right), on its front face.
func _edge(i: int, side: int) -> Vector3:
	if i < 0 or i >= mini(_left.size(), _right.size()):
		return Vector3(base.x, base.y + stave_height * 0.5, base.z + stave_depth * 0.5)   # not shown yet
	var units: float = -float(_left[i]) if side == 0 else float(_right[i])
	return Vector3(base.x + units * unit_width, row_y(i), base.z + stave_depth * 0.5)


## Row `i` cut from `side` (0 left, 1 right), `deep` or a fine shave: the knife comes in, chips, the knock.
func cut(i: int, side: int, deep: bool) -> void:
	_aim_side = side
	_aim = _edge(i, side)
	_stroke_age = 0.0
	_chips.amount = 16 if deep else 6
	_chips.position = _aim
	_chips.direction = Vector3(-1.0 if side == 0 else 1.0, 0.5, 0.6)
	_chips.restart()
	_sound.pitch_scale = randf_range(1.05, 1.2) if deep else randf_range(1.55, 1.75)
	_sound.volume_db = -3.0 if deep else -9.0
	_sound.play()


func _process(delta: float) -> void:
	# The knife: lies beside the edge it cuts, its tip toward the stave; comes in fast, backs off slower.
	_stroke_age += delta
	var off: float = knife_rest
	if _stroke_age < knife_in_s:
		off = lerpf(knife_rest, 0.0, _stroke_age / knife_in_s)
	elif _stroke_age < knife_in_s + 0.2:
		off = lerpf(0.0, knife_rest, (_stroke_age - knife_in_s) / 0.2)
	var outward: float = -1.0 if _aim_side == 0 else 1.0
	var at: Vector3 = _aim + Vector3(outward * off, 0.0, 0.02)
	_knife.position = _knife.position.lerp(at, 1.0 if _stroke_age < knife_in_s else minf(1.0, delta * 14.0))
	_knife.rotation = Vector3(0.0, PI if _aim_side == 1 else 0.0, 0.0)   # the blade points at the stave (+x from the left)


## A point on the stave's front face, on screen: `row_edge` down the stave in rows (0 its top, n its bottom), `units`
## out from the middle line (negative: to the left).
func screen_point(row_edge: float, units: float) -> Vector2:
	var p: Vector3 = Vector3(base.x + units * unit_width, base.y + stave_height - row_edge * row_height(), base.z + stave_depth * 0.5)
	return camera.unproject_position(p) * (size / Vector2(maxi(1, viewport.size.x), maxi(1, viewport.size.y)))
