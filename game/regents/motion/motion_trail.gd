class_name MotionTrail extends MeshInstance3D
## A RIBBON BEHIND A BLADE while a move made in code plays (the motion lab): the held item's blade, base to tip
## (`SwingTrail.blade_of_item`), sampled every frame and kept `life_s`, drawn as one strip that fades along its age.
## Made in code (an `ImmediateMesh`, vertex colors, no image). Presentation only.

@export var color: Color = Color(1.0, 0.92, 0.7, 0.55)
@export_range(0.05, 2.0, 0.01, "suffix:s") var life_s: float = 0.22
## The blade's first share left out (the part by the hand draws nothing).
@export_range(0.0, 0.9, 0.05) var blade_from: float = 0.35

var item: HeldItem = null
## Drawing now (a stopped trail fades out what it has).
var emitting: bool = false

## [base (world), tip (world), age (s)], oldest first.
var _samples: Array[Array] = []
var _blade: Array = []
var _mesh: ImmediateMesh = null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material_override = m


## Follow `held`'s blade.
func follow(held: HeldItem) -> void:
	item = held
	_blade = SwingTrail.blade_of_item(held, blade_from) if held != null else []


func _process(delta: float) -> void:
	step(delta)


## One frame: age what is there, add the blade where it is now (while emitting), redraw.
func step(delta: float) -> void:
	for s: Array in _samples:
		s[2] = float(s[2]) + delta
	while not _samples.is_empty() and float(_samples[0][2]) > life_s:
		_samples.pop_front()
	if emitting and is_instance_valid(item) and item.is_inside_tree() and _blade.size() == 2:
		var to_world: Transform3D = item.global_transform
		_samples.append([to_world * (_blade[0] as Vector3), to_world * (_blade[1] as Vector3), 0.0])
	_draw()


## How many samples it holds now (a suite reads it).
func sample_count() -> int:
	return _samples.size()


func _draw() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s: Array in _samples:
		var fade: float = 1.0 - clampf(float(s[2]) / life_s, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * fade * fade)
		_mesh.surface_set_color(Color(c.r, c.g, c.b, 0.0))
		_mesh.surface_add_vertex(s[0] as Vector3)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(s[1] as Vector3)
	_mesh.surface_end()
