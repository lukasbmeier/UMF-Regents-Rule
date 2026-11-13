class_name ImpactBurst extends Node3D
## WHERE A SPELL'S MISSILE ENDS (Luke, 2026-11-11: "better magic vfx"): a flash that swells and fades, a pulse of
## light, and sparks thrown out, gone in `LIFE_S`. Made by `ShotLook` as its shot is taken away; it lives in the
## world and frees itself.
##
## Presentation only (hard rule 11).

## How long the flash and the light last, and the whole burst (its sparks die out).
const FLASH_S: float = 0.22
const LIFE_S: float = 0.7

var size_m: float = 1.0
var color: Color = Color.WHITE
var _age: float = 0.0
var _flash: MeshInstance3D = null
var _light: OmniLight3D = null


## A burst of `color`, `size` m wide, at `pos`: added to `tree`'s root. Null with no tree.
static func at(tree: SceneTree, pos: Vector3, tint: Color, size: float) -> ImpactBurst:
	if tree == null or tree.root == null:
		return null
	var b := ImpactBurst.new()
	b.name = "ImpactBurst"
	b.size_m = size
	b.color = tint
	b.position = pos
	tree.root.add_child.call_deferred(b)
	return b


func _ready() -> void:
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 16
	ball.rings = 8
	_flash.mesh = ball
	_flash.material_override = glow_material(color, false)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.scale = Vector3.ONE * size_m * 0.25
	add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 3.0
	_light.omni_range = maxf(size_m * 3.0, 2.0)
	add_child(_light)
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = clampi(roundi(10.0 + size_m * 10.0), 8, 48)
	p.lifetime = LIFE_S * 0.8
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.initial_velocity_min = size_m * 1.5
	p.initial_velocity_max = size_m * 4.0
	p.damping_min = 2.0
	p.damping_max = 4.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * clampf(size_m * 0.08, 0.03, 0.2)
	quad.material = glow_material(color, true)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true


func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / FLASH_S, 0.0, 1.0)
	_flash.scale = Vector3.ONE * size_m * lerpf(0.25, 1.0, 1.0 - (1.0 - t) * (1.0 - t))
	(_flash.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.45 * (1.0 - t))
	_flash.visible = t < 1.0
	_light.light_energy = 3.0 * (1.0 - t)
	if _age >= LIFE_S:
		queue_free()


## A glowing, unshaded material of `tint`, added over what is behind it; `billboard`: a quad that faces the camera.
static func glow_material(tint: Color, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = tint
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	return m
