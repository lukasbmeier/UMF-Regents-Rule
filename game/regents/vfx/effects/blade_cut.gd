class_name VfxBladeCut extends VfxEffect
## A WEAPON'S CUT (Luke, 2026-11-14: the overhead's crescent looked right but was drawn overhead on a sideways
## swing; "replacing the sword/melee swings with the vfx from the overhead is nice if cheap"): the sheet the blade
## REALLY sweeps, read from the weapon each frame (as `SwingTrail` finds a blade), worn as a crescent: hot at the tip,
## fading to nothing toward the hilt, eaten away by noise as it ages, a thin bright line along the tip; at the hit a
## flare and sparks off the tip and, a blow that ends at the ground, dust, chips and a ring. So it matches any swing:
## sideways, overhead, a thrust. Two ribbons (one draw each) while it cuts; the hit's parts only at the hit.
##
## Set `weapon` (the `HeldItem` in the fighter's hand) before it enters the tree; it draws in the world. In the game
## `SwingTrail` would take this look (`look()`), timed from the swing's start as it is now.

@export_group("The cut")
## Its color (the hottest part, at the tip, goes past it to white).
@export var color: Color = Color(1.0, 0.9, 0.72)
## How long a stretch of the sheet shows behind the blade, and of the bright line along its tip.
@export_range(0.05, 1.0, 0.01, "suffix:s") var life_s: float = 0.2
@export_range(0.02, 1.0, 0.01, "suffix:s") var edge_life_s: float = 0.11
## How far along the weapon from the hand the sheet begins (the hilt draws nothing), and the bright line.
@export_range(0.0, 0.9, 0.05) var blade_from: float = 0.25
@export_range(0.5, 0.98, 0.01) var edge_from: float = 0.85
## When it starts drawing, when the blow lands, and how long it draws after (s from its start: a swing's wind-up).
@export_range(0.0, 3.0, 0.01, "suffix:s") var cut_from_s: float = 0.12
@export_range(0.0, 3.0, 0.01, "suffix:s") var hit_at_s: float = 0.22
@export_range(0.0, 1.0, 0.01, "suffix:s") var after_hit_s: float = 0.12
@export_group("The hit")
@export_range(0, 120) var sparks: int = 30
## Dust, chips and a ring where the tip lands, when it is this near the ground (m); 0: never.
@export_range(0.0, 2.0, 0.05, "suffix:m") var ground_m: float = 0.55
@export_range(0.0, 1.0, 0.05) var shake: float = 0.2

## The weapon in the hand (a `HeldItem`); null draws no sheet.
var weapon: Node3D = null
var _blade: Array = []
var _sheet: RibbonTrail = null
var _edge: RibbonTrail = null
var _hit_at: Node3D = null
var _flare: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _sparks: GPUParticles3D = null
var _ground: Array[GPUParticles3D] = []
var _struck: bool = false
var _grounded: bool = false
var _light: OmniLight3D = null


## The crescent's look on a blade's sheet: `tint` at its body, white-hot at the tip, nothing at the hilt.
static func look(tint: Color, bright: bool = false) -> ShaderMaterial:
	var heat: GradientTexture1D = VfxKit.ramp(PackedColorArray([Color(tint.darkened(0.6), 0.0), Color(tint.darkened(0.2), 0.5), Color(tint, 0.9), Color(1.6, 1.6, 1.5, 1.0)]),
		PackedFloat32Array([0.0, 0.4, 0.75, 1.0]))
	if bright:
		return VfxKit.energy(true, heat, {"noise_heat": 0.15, "heat_bias": 0.7, "intensity": 2.0, "uv_fade": Vector4(0.0, 0.3, 0.35, 0.2)})
	return VfxKit.energy(true, heat, {"tile_a": Vector2(2, 3), "scroll_a": Vector2(1.5, 0), "tile_b": Vector2(3, 7), "scroll_b": Vector2(2.5, 0),
		"bands": 4.0, "heat_bias": -0.42, "noise_heat": 0.45, "v_heat": 0.85, "intensity": 1.1, "alpha_scale": 0.8,
		"erode_softness": 0.1, "uv_fade": Vector4(0.0, 0.35, 0.8, 0.03)})


func _build() -> void:
	duration_s = maxf(duration_s, hit_at_s + after_hit_s + life_s + 0.8)
	_sheet = RibbonTrail.new()
	_sheet.name = "Sheet"
	_sheet.lifetime_s = life_s
	_sheet.color = Color.WHITE
	_sheet.look = look(color)
	clocked(_sheet)
	_edge = RibbonTrail.new()
	_edge.name = "Edge"
	_edge.lifetime_s = edge_life_s
	_edge.color = Color.WHITE
	_edge.look = look(color, true)
	clocked(_edge)
	_hit_at = Node3D.new()
	_hit_at.name = "HitAt"
	_hit_at.top_level = true
	add_child(_hit_at)
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	_flare = clocked(VfxKit.shape_node(q, VfxKit.sprite(true, VfxKit.Shape.STAR, VfxKit.Facing.CAMERA, 3.0, {"falloff": 3.0, "tint": color.lightened(0.4)}), "Flare"), _hit_at) as MeshInstance3D
	var spark: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 80.0, Vector2(3.0, 8.0), Vector3(0, -9.8, 0),
		VfxKit.ramp(PackedColorArray([Color(1, 1, 0.9, 1), Color(1, 0.7, 0.3, 1), Color(1, 0.4, 0.1, 0)])), 1.0, 0.3), 0.08)
	spark.particle_flag_align_y = true
	spark.damping_min = 1.0
	spark.damping_max = 2.0
	_sparks = clocked(VfxKit.particles(sparks, 0.5, VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 5.0), Vector2(0.03, 0.26), spark, true, 1.0), _hit_at) as GPUParticles3D
	if ground_m > 0.0:
		_ring = clocked(VfxKit.shape_node(VfxKit.disc(1.0), VfxKit.circle({
			"ring_color": Color(0.9, 0.8, 0.6), "ring_radius": 0.9, "ring_width": 0.08, "inner_width": 0.0, "rune_count": 0.0,
			"wisp": 0.8, "wisp_tile": 4.0, "glow": 1.4}), "Ring"), _hit_at) as MeshInstance3D
		var dust: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3(0, 0.25, 0), 180.0, Vector2(2.0, 4.5), Vector3(0, 0.4, 0),
			VfxKit.ramp(PackedColorArray([Color(0.42, 0.36, 0.28, 0.75), Color(0.48, 0.43, 0.36, 0.5), Color(0.52, 0.48, 0.42, 0.0)]), PackedFloat32Array([0.0, 0.3, 1.0])), 0.6, 2.0), 0.25)
		dust.flatness = 0.8
		dust.damping_min = 3.0
		dust.damping_max = 5.0
		_ground.append(clocked(VfxKit.particles(12, 1.2, VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0), Vector2(0.9, 0.9), dust, true, 0.9), _hit_at) as GPUParticles3D)
		var chips: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 40.0, Vector2(3.0, 6.0), Vector3(0, -14, 0),
			VfxKit.ramp(PackedColorArray([Color(0.2, 0.16, 0.12, 1), Color(0.2, 0.16, 0.12, 1), Color(0.2, 0.16, 0.12, 0)]), PackedFloat32Array([0.0, 0.85, 1.0])), 1.0, 0.6), 0.15)
		chips.angle_max = 360.0
		chips.angular_velocity_min = -600.0
		chips.angular_velocity_max = 600.0
		_ground.append(clocked(VfxKit.particles(14, 0.9, VfxKit.sprite(false, VfxKit.Shape.SHARD, VfxKit.Facing.CAMERA, 1.0), Vector2(0.1, 0.1), chips, true, 1.0), _hit_at) as GPUParticles3D)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 2.5
	_hit_at.add_child(_light)


func _start() -> void:
	_struck = false
	_grounded = false
	_blade.clear()
	_flare.visible = false
	if _ring != null:
		_ring.visible = false


## Where the blade is now, [base, tip] in the world; [] with no weapon.
func blade_now() -> Array:
	var held: HeldItem = weapon as HeldItem if weapon != null and is_instance_valid(weapon) else null
	if held == null or not held.is_inside_tree():
		return []
	if _blade.is_empty():
		_blade = SwingTrail.blade_of_item(held, blade_from)
		if _blade.size() != 2:
			return []
	return [held.global_transform * (_blade[0] as Vector3), held.global_transform * (_blade[1] as Vector3)]


func _animate(a: float, _t: float) -> void:
	if a >= cut_from_s and a <= hit_at_s + after_hit_s:
		var edge: Array = blade_now()
		if edge.size() == 2:
			var base: Vector3 = edge[0]
			var tip: Vector3 = edge[1]
			_sheet.add_blade(base, tip)
			_edge.add_blade(base.lerp(tip, edge_from), tip)
	if a >= hit_at_s and not _struck:
		_struck = true
		var edge: Array = blade_now()
		var tip: Vector3 = (edge[1] as Vector3) if edge.size() == 2 else global_position + Vector3(0, 1, 0)
		_hit_at.global_position = tip
		burst(_sparks)
		_grounded = ground_m > 0.0 and tip.y - global_position.y <= ground_m
		if _grounded:
			_hit_at.global_position = Vector3(tip.x, global_position.y + 0.04, tip.z)
			for p: GPUParticles3D in _ground:
				burst(p)
		if shake > 0.0:
			shook.emit(shake * (1.0 if _grounded else 0.6), 0.2)
	var h: float = span(a, hit_at_s, hit_at_s + 0.2)
	_flare.visible = _struck and h < 1.0
	_flare.position.y = 0.0 if not _grounded else 0.3
	_flare.scale = Vector3.ONE * lerpf(0.4, 1.1, ease_out(h))
	fx(_flare, &"fx_alpha", 1.0 - h)
	_light.light_energy = 3.0 * (1.0 - h) * float(_struck)
	if _ring != null:
		var rr: float = span(a, hit_at_s, hit_at_s + 0.4)
		_ring.visible = _grounded and rr < 1.0
		_ring.scale = Vector3.ONE * lerpf(0.4, 2.6, ease_out(rr))
		fx(_ring, &"fx_alpha", 1.0 - rr)
