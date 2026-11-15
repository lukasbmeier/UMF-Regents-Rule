class_name VfxFireMissile extends VfxEffect
## A FIREBALL IN FLIGHT: a white-hot core in a licking, banded flame drawn out behind it, flame puffs and dark smoke
## left in the air, embers falling away, a flickering light. It flies from where it is put to `target` at
## `speed_mps` (fireball's: 20), says `arrived` there, and its trail lingers a moment before it is done.
##
## In the game the referee flies the shot and this RIDES on it (`rides`: a body's look, `fireball_look.tscn`,
## `bolt_look.tscn`: it stays on its parent, faces the way it goes, lasts as long as the body); the lab flies it
## itself. `element` Arcane makes it the staff's violet bolt.

signal arrived(at: Vector3)

@export_group("Flight")
## Rides on a flying body (the game's), never flying itself; off: it flies to `target` (the lab).
@export var rides: bool = false
@export_range(1.0, 80.0, 0.5, "suffix:m/s") var speed_mps: float = 20.0
## How long its trail hangs on after it arrives.
@export_range(0.0, 3.0, 0.05, "suffix:s") var linger_s: float = 1.0
@export_group("Look")
@export_enum("Fire", "Arcane") var element: int = 0
@export_range(0.05, 1.0, 0.01, "suffix:m") var core_m: float = 0.3
@export_range(0, 300) var flames_per_s: int = 160
@export_range(0, 100) var smoke_per_s: int = 22
@export_range(0, 100) var embers_per_s: int = 40
@export var light_color: Color = Color(1.0, 0.5, 0.15)
## The ribbon of flame left behind (`RibbonTrail`): how long a stretch shows, how wide at the ball (0: none).
@export_range(0.0, 1.0, 0.01, "suffix:s") var trail_life_s: float = 0.22
@export_range(0.0, 1.0, 0.01, "suffix:m") var trail_width_m: float = 0.42
@export var trail_color: Color = Color(1.0, 0.42, 0.08, 0.75)

var _from: Vector3 = Vector3.ZERO
var _flight_s: float = 1.0
var _arrived: bool = false
var _body: Node3D = null
var _core: MeshInstance3D = null
var _shell: MeshInstance3D = null
var _flames: GPUParticles3D = null
var _smoke: GPUParticles3D = null
var _embers: GPUParticles3D = null
var _light: OmniLight3D = null
var _trail: RibbonTrail = null
var _prev: Vector3 = Vector3.ZERO


## The flame's colors over a puff's life, hottest first.
func _flame_colors() -> PackedColorArray:
	if element == 1:
		return PackedColorArray([Color(0.92, 0.9, 1, 1), Color(0.62, 0.45, 1, 1), Color(0.35, 0.15, 0.85, 0.8), Color(0.12, 0.0, 0.35, 0.0)])
	return PackedColorArray([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.12, 1), Color(0.8, 0.15, 0.03, 0.8), Color(0.3, 0.05, 0.0, 0.0)])


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var heat: GradientTexture1D = VfxKit.fire_heat() if element == 0 else VfxKit.arcane_heat()
	_core = clocked(VfxKit.shape_node(VfxKit.sphere(0.5), VfxKit.energy(true, heat, {
		"tile_a": Vector2(2, 1), "scroll_a": Vector2(0.0, 2.5), "tile_b": Vector2(3, 2), "scroll_b": Vector2(0.4, 3.5),
		"heat_bias": 0.5, "fresnel_heat": -0.5, "rim_fade": 0.8, "intensity": 2.6}), "Core"), _body) as MeshInstance3D
	# The flame: a ball drawn out behind (its +Z), scrolling back over it, licking out by noise.
	_shell = clocked(VfxKit.shape_node(VfxKit.sphere(0.5), VfxKit.energy(true, heat, {
		"tile_a": Vector2(3, 1), "scroll_a": Vector2(0.0, 1.8), "tile_b": Vector2(4, 2), "scroll_b": Vector2(0.3, 2.8),
		"warp": 0.5, "bands": 4.0, "displace": 0.18, "heat_bias": -0.15, "fresnel_heat": 0.15, "rim_fade": 0.35,
		"intensity": 1.6}), "Flame"), _body) as MeshInstance3D
	_shell.rotation.x = PI / 2.0   # the sphere's poles along the flight, so its V scrolls back along it
	var flame_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 180.0, Vector2(0.2, 0.9),
		Vector3(0, 1.5 if element == 0 else 0.0, 0), VfxKit.ramp(_flame_colors()), 1.0, 0.15), 0.12)
	_flames = clocked(VfxKit.particles(roundi(float(flames_per_s) * 0.35), 0.35,
		VfxKit.sprite(true, VfxKit.Shape.DOT, VfxKit.Facing.CAMERA, 1.3, {"falloff": 1.6}), Vector2(0.5, 0.5), flame_move, false, 0.0, true)) as GPUParticles3D
	var smoke_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 60.0, Vector2(0.1, 0.5),
		Vector3(0, 0.7, 0), VfxKit.ramp(PackedColorArray([Color(0.35, 0.2, 0.12, 0.0), Color(0.22, 0.18, 0.16, 0.8), Color(0.32, 0.3, 0.3, 0.0)]), PackedFloat32Array([0.0, 0.15, 1.0])), 0.6, 1.8), 0.15)
	smoke_move.damping_min = 0.5
	smoke_move.damping_max = 1.0
	_smoke = clocked(VfxKit.particles(maxi(roundi(float(smoke_per_s) * 0.9), 1), 0.9,
		VfxKit.sprite(false, VfxKit.Shape.PUFF, VfxKit.Facing.CAMERA, 1.0), Vector2(0.6, 0.6), smoke_move, false, 0.0, true)) as GPUParticles3D
	var ember_move: ParticleProcessMaterial = VfxKit.from_ball(VfxKit.motion(Vector3.UP, 180.0, Vector2(1.0, 3.0),
		Vector3(0, -5 if element == 0 else -1, 0), VfxKit.fade(Color(1.0, 0.6, 0.2) if element == 0 else Color(0.75, 0.62, 1.0), 0.5), 1.0, 0.3), 0.15)
	ember_move.particle_flag_align_y = true
	_embers = clocked(VfxKit.particles(maxi(roundi(float(embers_per_s) * 0.6), 1), 0.6,
		VfxKit.sprite(true, VfxKit.Shape.STREAK, VfxKit.Facing.AXIAL, 4.0), Vector2(0.03, 0.16), ember_move, false, 0.0, true)) as GPUParticles3D
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = 4.0
	_body.add_child(_light)


func _start() -> void:
	_from = global_position
	_prev = global_position
	if rides:
		duration_s = 3600.0   # as long as the body it rides on
		_arrived = false
		_body.visible = true
		_body.position = Vector3.ZERO
		if _trail == null and trail_width_m > 0.0:
			_trail = RibbonTrail.behind(_body, trail_life_s, trail_width_m, trail_color, true)
		for p: GPUParticles3D in [_flames, _smoke, _embers]:
			p.restart()
			p.emitting = p != _smoke or smoke_per_s > 0
		return
	var dist: float = _from.distance_to(target)
	_flight_s = maxf(dist / maxf(speed_mps, 0.1), 0.05)
	duration_s = _flight_s + linger_s
	_arrived = false
	_body.visible = true
	_body.position = Vector3.ZERO
	if dist > 0.01:
		_body.look_at(target, Vector3.UP)
	if _trail == null and trail_width_m > 0.0:
		_trail = RibbonTrail.behind(_body, trail_life_s, trail_width_m, trail_color, true)
	for p: GPUParticles3D in [_flames, _smoke, _embers]:
		p.restart()
		p.emitting = true


func _animate(a: float, _t: float) -> void:
	if rides:
		_ride(a)
		return
	var f: float = span(a, 0.0, _flight_s)
	var spot: Vector3 = _from.lerp(target, f)
	_body.global_position = spot
	for p: GPUParticles3D in [_flames, _smoke, _embers]:
		p.global_position = spot
	var flick: float = 1.0 + 0.1 * sin(a * 37.0) + 0.06 * sin(a * 91.0)
	_core.scale = Vector3.ONE * core_m * 0.6 * flick
	_shell.scale = Vector3(core_m, core_m * 2.4, core_m) * (2.0 - flick)
	_shell.position = Vector3(0, 0, core_m * 0.55)
	_light.light_energy = 3.0 * flick
	if f >= 1.0 and not _arrived:
		_arrived = true
		_body.visible = false
		for p: GPUParticles3D in [_flames, _smoke, _embers]:
			p.emitting = false
		arrived.emit(target)


## On a flying body: it stays where the body is, its flame drawn back the way it came.
func _ride(a: float) -> void:
	var here: Vector3 = global_position
	var way: Vector3 = here - _prev
	if way.length() > 0.002 and absf(way.normalized().y) < 0.98:
		_body.look_at(here + way, Vector3.UP)
	_prev = here
	var flick: float = 1.0 + 0.1 * sin(a * 37.0) + 0.06 * sin(a * 91.0)
	_core.scale = Vector3.ONE * core_m * 0.6 * flick
	_shell.scale = Vector3(core_m, core_m * 2.4, core_m) * (2.0 - flick)
	_shell.position = Vector3(0, 0, core_m * 0.55)
	_light.light_energy = 3.0 * flick


func _end() -> void:
	for p: GPUParticles3D in [_flames, _smoke, _embers]:
		p.emitting = false
