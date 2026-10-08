class_name SkyDirector extends Node3D
## GENRE CODE. THE SKY FOLLOWS THE ROUND (DECISIONS #168): the time of day and the weather the
## server rolled (`FishingConditions`) shown on the level's sun, sky and fog, and as rain. Each time
## of day has a `SkyLook` (where the sun goes through the round, the light's colour, the sky) and
## each weather a `WeatherLook` (clouds, grey, fog, rain) on top; the scene blends to a new round's
## over `blend_sec`, and the sun moves through the round's PLAYING phase.
##
## It finds the level's first DirectionalLight3D and WorldEnvironment itself (the lakeside is
## generated; nothing in it is edited for this), and works on its own copy of the environment.
## It decides nothing: rain does not slow anyone, and the rolls that use the conditions are the
## server's. Presentation only, like the rest of `game/world/`.

## Per time-of-day id (`shared/fishing/fishing.json` conditions.times).
@export var times: Dictionary[String, SkyLook] = {}
## Per weather id (conditions.weather). A weather with no entry changes nothing.
@export var weathers: Dictionary[String, WeatherLook] = {}
## Seconds to blend into a new round's look.
@export var blend_sec: float = 6.0
## How many raindrops a downpour has in the air around the camera.
@export var rain_drops: int = 2400

var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _rain: GPUParticles3D = null
var _conditions: FishingConditions = null
## The look on screen now, as a flat set of numbers blended toward the target every frame.
var _now: Dictionary = {}
var _phase: int = -1
var _phase_ends_usec: int = 0


func _ready() -> void:
	SignalBus.session_phase_changed.connect(func(_s: int, _o: int, phase: int, ends: int) -> void:
		_phase = phase
		_phase_ends_usec = ends)
	_find_level.call_deferred()


func _find_level() -> void:
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	for n: Node in root.find_children("*", "DirectionalLight3D", true, false):
		_sun = n as DirectionalLight3D
		break
	for n: Node in root.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we.environment != null:
			# Our own copy: the level's environment is a resource of a generated scene.
			_env = we.environment.duplicate(true) as Environment
			we.environment = _env
			if _env.sky != null:
				_sky = _env.sky.sky_material as ProceduralSkyMaterial
		break
	_conditions = FishingConditions.find(get_tree())
	_rain = _make_rain()
	add_child(_rain)


## The look the scene is blending toward now (tests read it), as numbers.
func target() -> Dictionary:
	var time_id: String = _conditions.time_id() if _conditions != null and _conditions.known else ""
	var weather_id: String = _conditions.weather_id() if _conditions != null and _conditions.known else ""
	var t: SkyLook = times.get(time_id, null)
	if t == null:
		t = SkyLook.new()
	var w: WeatherLook = weathers.get(weather_id, null)
	if w == null:
		w = WeatherLook.new()
	var progress: float = round_progress()
	var grey := Color(0.55, 0.58, 0.62)
	var dark: float = 1.0 - w.darken
	return {
		"elevation": lerpf(t.sun_elevation_deg, t.sun_elevation_end_deg, progress),
		"azimuth": t.sun_azimuth_deg,
		"sun_color": t.sun_color,
		"sun_energy": t.sun_energy * w.sun_energy_mult,
		"sky_top": t.sky_top.lerp(grey, w.grey) * dark,
		"sky_horizon": t.sky_horizon.lerp(grey, w.grey) * dark,
		"ground_horizon": t.ground_horizon.lerp(grey, w.grey) * dark,
		"ambient": t.ambient_energy * lerpf(1.0, 0.75, w.darken),
		"fog_color": t.fog_color.lerp(grey, w.grey) * dark,
		"fog_density": t.fog_density + w.fog_density_add,
		"rain": w.rain,
	}


## How far through the round's PLAYING phase it is, 0..1 (0 before it, 1 after).
func round_progress() -> float:
	if _phase != SessionComponent.Phase.PLAYING:
		return 0.0 if _phase <= SessionComponent.Phase.LOBBY else 1.0
	var total: float = Rules.phase_seconds(0, SessionComponent.Phase.PLAYING)
	if total <= 0.0 or _phase_ends_usec <= 0:
		return 0.0
	var left: float = float(_phase_ends_usec - ClockSync.server_usec()) / 1_000_000.0
	return clampf(1.0 - left / total, 0.0, 1.0)


## The look on screen (tests read it).
func shown() -> Dictionary:
	return _now


## Jump straight to the target, without blending (tests, and the first frame).
func snap() -> void:
	_now = target()
	_apply()


func _process(delta: float) -> void:
	if _sun == null and _env == null:
		return
	var want: Dictionary = target()
	if _now.is_empty():
		_now = want
	else:
		var k: float = 1.0 - exp(-delta * 3.0 / maxf(blend_sec, 0.01))
		for key: String in want:
			var a: Variant = _now[key]
			var b: Variant = want[key]
			if a is Color:
				_now[key] = (a as Color).lerp(b as Color, k)
			else:
				_now[key] = lerpf(float(a), float(b), k)
	_apply()


func _apply() -> void:
	if _sun != null:
		var el: float = deg_to_rad(float(_now["elevation"]))
		var az: float = deg_to_rad(float(_now["azimuth"]))
		# The light shines along its -Z: from the sun's direction toward the ground.
		var from: Vector3 = Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		if from.y < 0.0:
			from.y = -from.y * 0.35 + 0.15   # below the horizon: the moon, low and dim
		_sun.global_basis = Basis.looking_at(-from.normalized(), Vector3.UP)
		_sun.light_color = _now["sun_color"]
		_sun.light_energy = float(_now["sun_energy"])
	if _sky != null:
		_sky.sky_top_color = _now["sky_top"]
		_sky.sky_horizon_color = _now["sky_horizon"]
		_sky.ground_horizon_color = _now["ground_horizon"]
	if _env != null:
		_env.ambient_light_energy = float(_now["ambient"])
		_env.fog_light_color = _now["fog_color"]
		_env.fog_density = float(_now["fog_density"])
	if _rain != null:
		var amount: float = float(_now["rain"])
		_rain.emitting = amount > 0.02
		_rain.amount_ratio = clampf(amount, 0.0, 1.0)
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			_rain.global_position = cam.global_position + Vector3(0.0, 10.0, 0.0)


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = maxi(rain_drops, 1)
	p.lifetime = 1.1
	# Started full: turned on, the air is already raining rather than filling from the top.
	p.preprocess = 1.0
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -25, -20), Vector3(40, 30, 40))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(18.0, 1.0, 18.0)
	mat.direction = Vector3(0.05, -1.0, 0.0)
	mat.spread = 2.0
	mat.initial_velocity_min = 18.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	p.process_material = mat
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.55)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.8, 0.86, 0.92, 0.5)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = look
	p.draw_pass_1 = drop
	return p
