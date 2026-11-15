class_name VfxParryFlash extends VfxEffect
## A PARRY (a blow turned at the last moment): a hard white star where the weapons meet, a ring snapping out from
## it, sparks sprayed back toward the attacker, a flash of light. Short and sharp: it should feel like a reward. Put
## it where the weapons meet, facing the attacker (its -Z toward them).

@export_range(0.2, 3.0, 0.05, "suffix:m") var size_m: float = 1.3
@export var color: Color = Color(1.0, 0.9, 0.6)
@export_range(0, 120) var sparks: int = 48
@export_range(0.0, 1.0, 0.05) var shake: float = 0.15

var _star: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _ring2: MeshInstance3D = null
var _sparks: GPUParticles3D = null
var _light: OmniLight3D = null


func _build() -> void:
	duration_s = maxf(duration_s, 0.7)
	_star = clocked(VfxKit.shape_node(_quad(size_m), VfxKit.sprite(true, VfxKit.Shape.STAR, VfxKit.Facing.CAMERA, 4.0, {"falloff": 3.5, "tint": color.lightened(0.5)}), "Star")) as MeshInstance3D
	_ring = clocked(VfxKit.shape_node(_quad(size_m), VfxKit.sprite(true, VfxKit.Shape.RING, VfxKit.Facing.CAMERA, 2.5, {"ring_width": 0.05, "tint": color}), "Ring")) as MeshInstance3D
	_ring2 = clocked(VfxKit.shape_node(_quad(size_m), VfxKit.sprite(true, VfxKit.Shape.RING, VfxKit.Facing.CAMERA, 1.5, {"ring_width": 0.03, "tint": color}), "Ring2")) as MeshInstance3D
	var spray: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.FORWARD, 55.0, Vector2(5.0, 12.0), Vector3(0, -6.0, 0),
		VfxKit.ramp(PackedColorArray([Color(1, 1, 1, 1), Color(color, 1.0), Color(1.0, 0.5, 0.15, 0.0)])), 1.0, 0.2), 0.05)
	spray.particle_flag_align_y = true
	spray.damping_min = 3.0
	spray.damping_max = 6.0
	_sparks = clocked(VfxKit.particles(sparks, 0.45, VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 6.0), Vector2(0.03, 0.35), spray, true, 1.0)) as GPUParticles3D
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 4.0
	add_child(_light)


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _start() -> void:
	burst(_sparks)
	if shake > 0.0:
		shook.emit(shake, 0.15)


func _animate(a: float, _t: float) -> void:
	var st: float = span(a, 0.0, 0.2)
	_star.visible = st < 1.0
	_star.scale = Vector3.ONE * lerpf(1.3, 0.5, ease_out(st))
	fx(_star, &"fx_alpha", 1.0 - ease_in(st))
	var r1: float = span(a, 0.0, 0.25)
	_ring.visible = r1 < 1.0
	_ring.scale = Vector3.ONE * lerpf(0.2, 1.0, ease_out(r1))
	fx(_ring, &"fx_alpha", 1.0 - r1)
	var r2: float = span(a, 0.04, 0.4)
	_ring2.visible = a >= 0.04 and r2 < 1.0
	_ring2.scale = Vector3.ONE * lerpf(0.3, 1.5, ease_out(r2))
	fx(_ring2, &"fx_alpha", (1.0 - r2) * 0.5)
	_light.light_energy = 3.0 * (1.0 - ease_out(span(a, 0.0, 0.3)))
