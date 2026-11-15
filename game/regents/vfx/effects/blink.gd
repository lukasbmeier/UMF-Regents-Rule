class_name VfxBlink extends VfxEffect
## BLINK (the staff's R: 8 m the way you look, at once): where you were, a column of violet light snaps shut round
## you as you fade, motes rush in, a small circle flashes; where you land, the column bursts open, a ring and a
## ripple spread, motes scatter, and you fade back in. Put it where the caster stands, facing the way they blink;
## `target` is where they land. With a `caster` it fades that body out and in (and the lab moves it); in the game
## the server moves the player and this only shows it.

@export_group("Look")
@export_range(0.2, 3.0, 0.05, "suffix:m") var column_height_m: float = 2.4
@export_range(0.1, 2.0, 0.05, "suffix:m") var column_radius_m: float = 0.55
@export var color: Color = Color(0.6, 0.45, 1.0)
## When the body is gone and when it is back (s).
@export_range(0.0, 1.0, 0.01, "suffix:s") var gone_at_s: float = 0.12
@export_range(0.0, 1.0, 0.01, "suffix:s") var back_at_s: float = 0.2
## Move `caster` to `target` at `gone_at_s` (the lab; the game's server moves it).
@export var moves_caster: bool = true

## [column, circle, motes] at each end.
var _out: Array[GeometryInstance3D] = []
var _in: Array[GeometryInstance3D] = []
var _ripple: MeshInstance3D = null
var _streak: MeshInstance3D = null
var _origin: Vector3 = Vector3.ZERO
var _moved: bool = false
var _meshes: Array = []
var _light: OmniLight3D = null


func _build() -> void:
	duration_s = maxf(duration_s, 1.1)
	_out = _end_parts("Out", true)
	_in = _end_parts("In", false)
	_ripple = clocked(VfxKit.shape_node(VfxKit.disc(1.0), VfxKit.distort({"radial": true, "strength": 0.05, "band_width": 0.25})), null) as MeshInstance3D
	_ripple.rotation.x = 0.0
	# A thin streak of light along the jump, gone at once.
	_streak = clocked(VfxKit.shape_node(VfxKit.tube(0.06, 0.06, 1.0, 12), VfxKit.energy(true, VfxKit.arcane_heat(), {
		"tile_a": Vector2(1, 4), "scroll_a": Vector2(0, -6), "heat_bias": 0.2, "intensity": 2.0,
		"uv_fade": Vector4(0, 0, 0.3, 0.3)}), "Streak"), null) as MeshInstance3D
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 4.0
	add_child(_light)


## One end's parts: the column of light, a small circle on the ground, motes (rushing in to the column, or out).
func _end_parts(prefix: String, inward: bool) -> Array[GeometryInstance3D]:
	var holder := Node3D.new()
	holder.name = prefix
	add_child(holder)
	var heat: GradientTexture1D = VfxKit.arcane_heat()
	var col: MeshInstance3D = clocked(VfxKit.shape_node(VfxKit.tube(column_radius_m, column_radius_m * 0.7, column_height_m, 32),
		VfxKit.energy(true, heat, {"tile_a": Vector2(3, 1), "scroll_a": Vector2(0, -1.5), "tile_b": Vector2(5, 2), "scroll_b": Vector2(0.3, -2.5),
		"bands": 4.0, "heat_bias": -0.12, "fresnel_heat": 0.45, "intensity": 1.5, "alpha_scale": 0.8, "uv_fade": Vector4(0, 0, 0.45, 0.15)}), "Column"), holder) as MeshInstance3D
	col.position.y = column_height_m * 0.5
	var circ: MeshInstance3D = clocked(VfxKit.shape_node(VfxKit.disc(column_radius_m * 3.4), VfxKit.circle({
		"ring_color": color, "rune_color": color.lightened(0.4), "ring_radius": 0.92, "ring_width": 0.05, "inner_radius": 0.55,
		"rune_inner": 0.6, "rune_outer": 0.85, "rune_count": 8.0, "rune_stroke": 0.12, "rune_spin": -1.5, "rune_seed": 11.0,
		"glow": 3.0, "wisp": 0.2}), "Circle"), holder) as MeshInstance3D
	circ.position.y = 0.03
	var move: ParticleProcessMaterial = VfxKit.motion(Vector3.UP, 180.0 if not inward else 0.0, Vector2(2.0, 5.0) if not inward else Vector2.ZERO,
		Vector3.ZERO, VfxKit.ramp(PackedColorArray([Color(color, 0.0), color.lightened(0.3), Color(color, 0.0)])), 1.0, 0.2)
	if inward:
		VfxKit.from_ball(move, 1.4, true)
		move.radial_accel_min = -16.0
		move.radial_accel_max = -12.0
	else:
		VfxKit.from_ball(move, 0.3)
		move.damping_min = 3.0
		move.damping_max = 5.0
	move.emission_shape_offset = Vector3(0, 1.0, 0)
	var motes: GPUParticles3D = clocked(VfxKit.particles(40, 0.45, VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 4.0),
		Vector2(0.08, 0.08), move, true, 0.85), holder) as GPUParticles3D
	return [col, circ, motes]


func _start() -> void:
	_origin = global_position
	_moved = false
	(_out[0].get_parent() as Node3D).global_position = _origin
	(_in[0].get_parent() as Node3D).global_position = target
	_ripple.global_position = target + Vector3(0, 0.05, 0)
	burst(_out[2] as GPUParticles3D)
	_meshes.clear()
	if caster != null and is_instance_valid(caster):
		for m: Node in caster.find_children("*", "GeometryInstance3D", true, false):
			if not (m is GPUParticles3D):
				_meshes.append(m)
	var mid: Vector3 = (_origin + target) * 0.5 + Vector3(0, 1.0, 0)
	_streak.global_position = mid
	var along: Vector3 = target - _origin
	if along.length() > 0.01:
		_streak.look_at(mid + along, Vector3.UP)
		_streak.rotate_object_local(Vector3.RIGHT, -PI / 2.0)   # the tube's length (its Y) along the jump
	_streak.scale = Vector3(1.0, along.length(), 1.0)


func _animate(a: float, _t: float) -> void:
	# Out: the column snaps shut round the body (narrows to nothing), its circle flashes and fades.
	var shut: float = span(a, 0.0, gone_at_s + 0.08)
	var col_out: GeometryInstance3D = _out[0]
	col_out.scale = Vector3(lerpf(1.0, 0.0, ease_in(shut)), 1.0 + shut * 0.3, lerpf(1.0, 0.0, ease_in(shut)))
	col_out.visible = shut < 1.0
	fx(_out[1], &"fx_alpha", 1.0 - span(a, 0.05, 0.6))
	fx(_out[1], &"fx_draw", ease_out(span(a, 0.0, 0.1)))
	# The streak: a blink of light along the way.
	var st: float = span(a, gone_at_s - 0.02, gone_at_s + 0.16)
	_streak.visible = a >= gone_at_s - 0.02 and st < 1.0
	fx(_streak, &"fx_alpha", 1.0 - st)
	# In: the column bursts open and fades; its circle and the ripple spread.
	var open: float = span(a, gone_at_s, gone_at_s + 0.4)
	var col_in: GeometryInstance3D = _in[0]
	col_in.visible = a >= gone_at_s and open < 1.0
	col_in.scale = Vector3(lerpf(0.2, 1.6, ease_out(open)), lerpf(1.2, 0.6, open), lerpf(0.2, 1.6, ease_out(open)))
	fx(col_in, &"fx_alpha", 1.0 - ease_in(open))
	_in[1].visible = a >= gone_at_s
	fx(_in[1], &"fx_draw", ease_out(span(a, gone_at_s, gone_at_s + 0.15)))
	fx(_in[1], &"fx_alpha", 1.0 - span(a, gone_at_s + 0.3, duration_s))
	(_in[1] as Node3D).scale = Vector3.ONE * lerpf(0.6, 1.3, ease_out(open))
	var rp: float = span(a, gone_at_s, gone_at_s + 0.45)
	_ripple.visible = a >= gone_at_s and rp < 1.0
	_ripple.scale = Vector3.ONE * 6.0
	fx(_ripple, &"fx_wave", ease_out(rp))
	fx(_ripple, &"fx_alpha", 1.0 - rp)
	_light.global_position = (_origin if a < gone_at_s else target) + Vector3(0, 1.2, 0)
	_light.light_energy = 4.0 * (1.0 - span(a, 0.0, gone_at_s)) if a < gone_at_s else 5.0 * (1.0 - open)
	if a >= gone_at_s and not _moved:
		_moved = true
		burst(_in[2] as GPUParticles3D)
		if moves_caster and caster != null and is_instance_valid(caster):
			caster.global_position = target
	# The body: fades out by `gone_at_s`, back in from `back_at_s`.
	var seen: float = 1.0 - span(a, 0.0, gone_at_s) if a < gone_at_s else span(a, back_at_s, back_at_s + 0.2)
	_fade_body(1.0 - seen)


func _end() -> void:
	_fade_body(0.0)


## The caster's meshes `how` faded (0 seen, 1 gone).
func _fade_body(how: float) -> void:
	for v: Variant in _meshes:
		if is_instance_valid(v):
			(v as GeometryInstance3D).transparency = how
