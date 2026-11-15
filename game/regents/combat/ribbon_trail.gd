class_name RibbonTrail extends MeshInstance3D
## A TRAIL (Luke, 2026-11-11: "trails for weapon swings (enemy and yours)", "trails for arrow projectile to show
## where its flying"): a fading ribbon drawn where something has just been.
##   - behind a POINT (an arrow, a spell's missile): `follow(node)`; the ribbon faces the camera, `width_m` wide
##     at its head, thinning to nothing at its tail;
##   - behind a BLADE (a swing): `add_blade(base, tip)` each frame of the cut; the ribbon is the sheet the blade
##     swept.
## Samples older than `lifetime_s` fall off its tail. It lives in the world (top level), so it stays where it was
## drawn while what it follows moves on; when that is gone it fades and frees itself (`free_when_done`).
##
## Presentation only (hard rule 11): it reads positions, and nothing reads it.

## How long a stretch of it shows (s).
@export_range(0.02, 3.0, 0.01, "suffix:s") var lifetime_s: float = 0.3
## A point's ribbon, at its head (m).
@export_range(0.005, 2.0, 0.005, "suffix:m") var width_m: float = 0.08
## Its color at its head; its tail fades to clear.
@export var color: Color = Color(1.0, 1.0, 1.0, 0.6)
## Whether it glows over what is behind it (a spell) or covers it (a blade's pale sheet in daylight).
@export var additive: bool = false
## Frees itself once what it follows is gone and its last stretch has faded.
@export var free_when_done: bool = false
## A LOOK of its own instead of the plain one (the VFX lab, PROGRESS 78-79: a cut's crescent, `VfxBladeCut`). Its
## UV: U along the trail (0 the newest edge, 1 the tail), V across it (0 the base, 1 the tip); its vertex alpha is
## how much life is left (the energy shader eats the trail away by it). Null: the plain ribbon, as before.
@export var look: Material = null
## Samples nearer than this to the last are not kept (m).
const MIN_STEP_M: float = 0.01
## A step longer than this in one frame is a jump, not a flight: the trail starts over (m).
const MAX_JUMP_M: float = 6.0
## The most samples kept (a long-lived trail on something fast).
const MAX_SAMPLES: int = 96

## What a point trail follows (its global position, each frame); `offset` from it in its own frame.
var _target: Variant = null
var _offset: Vector3 = Vector3.ZERO
## [time (s), a, b]: a point's sample holds its place in `a` (`b` unused); a blade's holds its base and tip.
var _samples: Array[Array] = []
var _blade: bool = false
var _clock: float = 0.0
var _mesh: ImmediateMesh = null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	material_override = look if look != null else ribbon_material(additive)


## Draw behind `node` from now on (`at`: a point in its own frame).
func follow(node: Node3D, at: Vector3 = Vector3.ZERO) -> void:
	_target = node
	_offset = at
	_blade = false


## A blade was here now, from `base` to `tip` (world): the next edge of the sheet it sweeps.
func add_blade(base: Vector3, tip: Vector3) -> void:
	_blade = true
	if not _samples.is_empty():
		var last: Array = _samples[-1]
		if (last[1] as Vector3).distance_to(base) < MIN_STEP_M and (last[2] as Vector3).distance_to(tip) < MIN_STEP_M:
			return
	_samples.append([_clock, base, tip])
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


## How many samples it holds now (tests read it).
func sample_count() -> int:
	return _samples.size()


## Whether anything of it shows now.
func showing() -> bool:
	return _samples.size() >= 2


func _process(delta: float) -> void:
	step(delta)


## One frame: what it follows is sampled, the old falls off, the ribbon is drawn. Public so tests can step it.
func step(delta: float) -> void:
	_clock += delta
	var following: bool = _target != null and is_instance_valid(_target) and (_target as Node3D).is_inside_tree()
	if following and not _blade:
		var t: Node3D = _target as Node3D
		var p: Vector3 = t.global_transform * _offset
		# Put somewhere else at once (its entity placed, a teleport): never a streak across the world.
		if not _samples.is_empty() and (_samples[-1][1] as Vector3).distance_to(p) > MAX_JUMP_M:
			_samples.clear()
		if _samples.is_empty() or (_samples[-1][1] as Vector3).distance_to(p) >= MIN_STEP_M:
			_samples.append([_clock, p, p])
			if _samples.size() > MAX_SAMPLES:
				_samples.pop_front()
	while not _samples.is_empty() and _clock - float(_samples[0][0]) > lifetime_s:
		_samples.pop_front()
	_draw()
	if free_when_done and not following and _samples.size() < 2 and (_target != null or _blade):
		queue_free()


func _draw() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_at: Vector3 = cam.global_position if cam != null else Vector3(0.0, 100.0, 0.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n: int = _samples.size()
	for i: int in range(n):
		var s: Array = _samples[i]
		var life: float = clampf(1.0 - (_clock - float(s[0])) / lifetime_s, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * life)
		var a: Vector3 = s[1]
		var b: Vector3 = s[2]
		if not _blade:
			# A point's ribbon: across the way it goes, facing the camera, thinner toward its tail.
			var along: Vector3 = ((_samples[mini(i + 1, n - 1)][1] as Vector3) - (_samples[maxi(i - 1, 0)][1] as Vector3))
			var side: Vector3 = along.cross(cam_at - a)
			side = side.normalized() * (width_m * 0.5 * life) if side.length_squared() > 0.0000001 else Vector3.ZERO
			b = a + side
			a = a - side
		_mesh.surface_set_color(c)
		_mesh.surface_set_uv(Vector2(1.0 - life, 0.0))
		_mesh.surface_add_vertex(a)
		# A plain blade's sheet is faint at one edge; a look of its own shades its edges itself.
		_mesh.surface_set_color(Color(c.r, c.g, c.b, c.a * (0.25 if _blade and look == null else 1.0)))
		_mesh.surface_set_uv(Vector2(1.0 - life, 1.0))
		_mesh.surface_add_vertex(b)
	_mesh.surface_end()


## The ribbon's material: unshaded, its color the vertices', seen from both sides, never hiding what is behind.
static func ribbon_material(glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if glow else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## A trail behind `node`, living in the world beside it (so it stays as `node` goes): added to `node`'s scene
## root now, freed once `node` is gone and it has faded. Null where there is no tree to draw in.
static func behind(node: Node3D, life_s: float, width: float, tint: Color, glow: bool) -> RibbonTrail:
	if node == null or not node.is_inside_tree():
		return null
	var t := RibbonTrail.new()
	t.name = "Trail"
	t.lifetime_s = life_s
	t.width_m = width
	t.color = tint
	t.additive = glow
	t.free_when_done = true
	node.get_tree().root.add_child.call_deferred(t)
	t.follow(node)
	return t
