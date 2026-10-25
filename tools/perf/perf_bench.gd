extends Node3D
## WHAT COSTS FRAMES, MEASURED (DECISIONS #282). A typical UMF scene with no server: a sun with
## shadows, the Environment effects the games' levels turn on (SSAO, SSIL, glow, volumetric fog,
## SSR), a few hundred props and a crowd of reference humanoids walking on the real animation tree
## (`AnimationTreeBuilder`). The camera flies the same path for every configuration, so each one
## draws the same frames; each is timed on the GPU and the CPU (the renderer's own measurements) and
## as whole frames.
##
##   tools\run.cmd tools/perf/perf_bench.sh                       every lever, then the quality presets
##   godot --path . res://tools/perf/perf_bench.tscn -- --only=presets --resolution...
##
## Arguments (after `--`): `--only=levers|presets|<name>,<name>`, `--frames=N` (timed per config,
## 240), `--warmup=N` (60), `--chars=N` (30), `--level=res://...tscn` (a game's own level instead
## of the made-up one), `--out=<path>` (a JSON of the results). It prints a table and quits.
##
## A lever is ONE thing turned down from the full look (`LEVERS`); a preset is Settings' own
## Low / Medium / High (`Settings.QUALITY_PRESETS`), applied the way a player's choice is.

const HUMANOID: String = "res://foundation/content/character/humanoid.tres"

## [name, what it changes from the full look]. `_apply_lever` reads the keys.
const LEVERS: Array[Array] = [
	["full", {}],
	["no_ssao", {"ssao": false}],
	["no_ssil", {"ssil": false}],
	["no_glow", {"glow": false}],
	["no_volumetric_fog", {"volumetric_fog": false}],
	["no_ssr", {"ssr": false}],
	["no_screen_effects", {"ssao": false, "ssil": false, "glow": false, "volumetric_fog": false, "ssr": false}],
	["shadows_off", {"shadows": false}],
	["shadows_hard_2048", {"shadow_quality": 0, "shadow_atlas": 2048}],
	["shadow_distance_40", {"shadow_distance": 40.0}],
	["fxaa_not_taa", {"aa": 1}],
	["aa_off", {"aa": 0}],
	["scale_75", {"scale": 0.75}],
	["scale_50", {"scale": 0.5}],
	["lod_aggressive", {"lod": 4.0}],
	["no_characters", {"characters": false}],
	["characters_culled", {"char_range": 0.01}],
	["animation_quarter_rate", {"anim_every": 4}],
	["animation_frozen", {"anim_every": 0}],
]

var _frames: int = 240
var _warmup: int = 60
var _chars: int = 30
var _out: String = ""
var _only: PackedStringArray = PackedStringArray()
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _camera: Camera3D = null
var _crowd: Node3D = null
## The look as built, put back before each lever.
var _full: Dictionary = {}
var _t: float = 0.0
var _results: Array[Dictionary] = []
var _trees: Array[AnimationTree] = []
## Each tree's pacing, as the game's AnimationDriverComponent paces it (AnimationRate, by Detail).
var _pacers: Array[AnimationRate.Pacer] = []
## Advance the crowd's trees every Nth frame (1 every frame, 0 never): `animation_*` levers.
var _anim_every: int = 1
var _frame_no: int = 0


func _ready() -> void:
	var level: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--warmup="):
			_warmup = int(arg.get_slice("=", 1))
		elif arg.begins_with("--chars="):
			_chars = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--only="):
			_only = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--level="):
			level = arg.get_slice("=", 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if level.is_empty():
		_build_scene()
	else:
		_load_level(level)
	_build_crowd()
	_camera = Camera3D.new()
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()
	_full = _snapshot()
	_run.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	_fly(_t)
	_frame_no += 1
	if _anim_every > 1 and _frame_no % _anim_every == 0:
		for tree: AnimationTree in _trees:
			tree.advance(delta * float(_anim_every))
	elif _anim_every == 1 and _camera != null:
		for i: int in range(_trees.size()):
			var at: Vector3 = (_trees[i].get_parent() as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
			_pacers[i].step(_trees[i], AnimationRate.hz(GraphicsQuality.detail, _camera.global_position.distance_to(at),
				AnimationRate.on_screen(_camera, at), false), delta, AnimationRate.phase(i))


## The same path every time: a slow circle 2 m up, looking across the middle, the way a
## third-person camera sees a level.
func _fly(t: float) -> void:
	if _camera == null:
		return
	var a: float = t * 0.25
	_camera.position = Vector3(cos(a) * 30.0, 2.2, sin(a) * 30.0)
	_camera.look_at(Vector3(cos(a + 0.6) * 10.0, 1.4, sin(a + 0.6) * 10.0))


func _run() -> void:
	print("[bench] %s | %s | %dx%d | %d characters | %d frames per config" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y,
		_chars, _frames])
	var want_levers: bool = _only.is_empty() or _only.has("levers")
	var want_presets: bool = _only.is_empty() or _only.has("presets")
	for lever: Array in LEVERS:
		if want_levers or _only.has(String(lever[0])):
			_restore()
			_apply_lever(lever[1] as Dictionary)
			await _measure(String(lever[0]))
	for i: int in range(Settings.QUALITY_PRESETS.size()):
		var name: String = "preset_" + String(Settings.entry(&"quality")["choices"][i]).to_lower()
		if want_presets or _only.has(name):
			_restore()
			Settings.set_value(&"quality", i)
			for model: Node in _crowd.get_children():
				AnimationRate.apply_range(model as Node3D, GraphicsQuality.detail)
			await _measure(name)
	_report()
	Settings.use_defaults()
	AppExit.quit(get_tree())


## Draw `_warmup` frames, then time `_frames`: the GPU's and the CPU's render time (the renderer's
## own measurement of this viewport) and the whole frame.
func _measure(name: String) -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	# Uncapped, whatever the preset says (Low caps at 60): the frames say what the machine can do.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_t = 0.0
	for i: int in range(_warmup):
		await get_tree().process_frame
	_t = 0.0
	var gpu: PackedFloat32Array = PackedFloat32Array()
	var cpu: PackedFloat32Array = PackedFloat32Array()
	var frame: PackedFloat32Array = PackedFloat32Array()
	var last: int = Time.get_ticks_usec()
	for i: int in range(_frames):
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		frame.append(float(now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	var row: Dictionary = {"name": name, "gpu_ms": _median(gpu), "cpu_ms": _median(cpu),
		"frame_ms": _median(frame), "frame_p95_ms": _quantile(frame, 0.95),
		"fps": 1000.0 / maxf(_median(frame), 0.001)}
	_results.append(row)
	print("[bench] %-22s gpu %7.2f ms   render cpu %6.2f ms   frame %7.2f ms (p95 %7.2f)   %6.1f fps" % [
		name, row["gpu_ms"], row["cpu_ms"], row["frame_ms"], row["frame_p95_ms"], row["fps"]])


func _report() -> void:
	var base: float = 0.0
	for r: Dictionary in _results:
		if r["name"] == "full":
			base = float(r["gpu_ms"])
	if base > 0.0:
		print("[bench] saved from the full look's %.2f ms of GPU:" % base)
		for r: Dictionary in _results:
			print("[bench]   %-22s %+7.2f ms  (%+5.1f%%)" % [r["name"], float(r["gpu_ms"]) - base,
				(float(r["gpu_ms"]) - base) / base * 100.0])
	if not _out.is_empty():
		var f: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(),
				"method": RenderingServer.get_current_rendering_method(),
				"size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"characters": _chars, "frames": _frames, "results": _results}, "  "))
			f.close()


# --- the levers ----------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var root: Window = get_tree().root
	return {"ssao": _env.ssao_enabled, "ssil": _env.ssil_enabled, "glow": _env.glow_enabled,
		"volumetric_fog": _env.volumetric_fog_enabled, "ssr": _env.ssr_enabled,
		"shadows": _sun.shadow_enabled, "shadow_distance": _sun.directional_shadow_max_distance,
		"shadow_quality": 3, "shadow_atlas": 4096, "aa": 2, "scale": 1.0, "lod": root.mesh_lod_threshold,
		"characters": true, "char_range": 0.0, "anim_every": 1}


func _restore() -> void:
	Settings.use_defaults()
	# The full look whatever this machine's own default is (Low on Compatibility).
	Settings.set_value(&"quality", Settings.QUALITY_HIGH)
	_apply_lever(_full)


func _apply_lever(c: Dictionary) -> void:
	var root: Window = get_tree().root
	# Only Forward+ draws these (the others warn and draw nothing): as GraphicsQuality does.
	var forward: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	if c.has("ssao"): _env.ssao_enabled = bool(c["ssao"]) and forward
	if c.has("ssil"): _env.ssil_enabled = bool(c["ssil"]) and forward
	if c.has("glow"): _env.glow_enabled = bool(c["glow"])
	if c.has("volumetric_fog"): _env.volumetric_fog_enabled = bool(c["volumetric_fog"]) and forward
	if c.has("ssr"): _env.ssr_enabled = bool(c["ssr"]) and forward
	if c.has("shadows"): _sun.shadow_enabled = bool(c["shadows"])
	if c.has("shadow_distance"): _sun.directional_shadow_max_distance = float(c["shadow_distance"])
	if c.has("shadow_quality"):
		RenderingServer.directional_soft_shadow_filter_set_quality(int(c["shadow_quality"]) as RenderingServer.ShadowQuality)
	if c.has("shadow_atlas"): RenderingServer.directional_shadow_atlas_set_size(int(c["shadow_atlas"]), true)
	var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if c.has("aa") and not compat:
		root.use_taa = int(c["aa"]) == 2
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(c["aa"]) == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if c.has("scale"):
		root.scaling_3d_scale = float(c["scale"])
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(c["scale"]) < 1.0 and not compat 			else Viewport.SCALING_3D_MODE_BILINEAR
	if c.has("lod"): root.mesh_lod_threshold = float(c["lod"])
	if c.has("characters"): _crowd.visible = bool(c["characters"])
	if c.has("char_range"):
		for n: Node in _crowd.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).visibility_range_end = float(c["char_range"])
	if c.has("anim_every"):
		_anim_every = int(c["anim_every"])


# --- the scene -----------------------------------------------------------------------------

## The look the games' levels have: Fishing's lakeside turns on SSAO, SSIL, glow, volumetric fog
## and SSR; Regent's frontier SSAO, glow and fog; the sun's shadows reach 80 m.
func _build_scene() -> void:
	_env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var forward: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.ssao_enabled = forward
	_env.ssil_enabled = forward
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.fog_enabled = true
	_env.fog_density = 0.006
	_env.volumetric_fog_enabled = forward
	_env.volumetric_fog_density = 0.01
	_env.ssr_enabled = forward
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.35, 0.5, 0.3), 0.9)
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 282
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.25
	trunk.height = 3.0
	var crown := SphereMesh.new()
	crown.radius = 1.6
	crown.height = 2.8
	var rock := BoxMesh.new()
	var bark: StandardMaterial3D = _mat(Color(0.4, 0.3, 0.2), 0.9)
	var leaves: StandardMaterial3D = _mat(Color(0.2, 0.45, 0.2), 0.8)
	var stone: StandardMaterial3D = _mat(Color(0.5, 0.5, 0.52), 0.7)
	for i: int in range(300):
		var at := Vector3(rng.randf_range(-110.0, 110.0), 0.0, rng.randf_range(-110.0, 110.0))
		var t := MeshInstance3D.new()
		t.mesh = trunk
		t.material_override = bark
		t.position = at + Vector3(0.0, 1.5, 0.0)
		add_child(t)
		var c := MeshInstance3D.new()
		c.mesh = crown
		c.material_override = leaves
		c.position = at + Vector3(0.0, 3.8, 0.0)
		add_child(c)
	for i: int in range(200):
		var r := MeshInstance3D.new()
		r.mesh = rock
		r.material_override = stone
		r.scale = Vector3(rng.randf_range(0.5, 2.5), rng.randf_range(0.3, 1.5), rng.randf_range(0.5, 2.5))
		r.position = Vector3(rng.randf_range(-110.0, 110.0), r.scale.y * 0.5, rng.randf_range(-110.0, 110.0))
		r.rotation.y = rng.randf_range(0.0, TAU)
		add_child(r)


## A game's own level: its WorldEnvironment and its sun are the ones the levers turn.
func _load_level(path: String) -> void:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("bench: no level at %s" % path)
		_build_scene()
		return
	var level: Node = scene.instantiate()
	add_child(level)
	for n: Node in level.find_children("*", "WorldEnvironment", true, false):
		_env = (n as WorldEnvironment).environment
	for n: Node in level.find_children("*", "DirectionalLight3D", true, false):
		_sun = n as DirectionalLight3D
	if _env == null or _sun == null:
		push_error("bench: %s has no WorldEnvironment or no sun" % path)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## The reference humanoid on the game's own tree, walking in place round the middle.
func _build_crowd() -> void:
	_crowd = Node3D.new()
	_crowd.name = "Crowd"
	add_child(_crowd)
	var def: EntityDefinition = load(HUMANOID) as EntityDefinition
	if def == null or (def.visual_scene == null and def.visual_variants.is_empty()):
		push_error("bench: no humanoid at %s" % HUMANOID)
		return
	var looks: Array[PackedScene] = []
	looks.assign(def.visual_variants if not def.visual_variants.is_empty() else [def.visual_scene])
	for i: int in range(_chars):
		var model: Node3D = looks[i % looks.size()].instantiate() as Node3D
		_crowd.add_child(model)
		var a: float = float(i) / float(maxi(_chars, 1)) * TAU
		var r: float = 6.0 + float(i % 5) * 3.0
		model.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		model.rotation.y = -a
		var skel: Skeleton3D = null
		for n: Node in model.find_children("*", "Skeleton3D", true, false):
			skel = n as Skeleton3D
		if skel == null or def.animation_set == null:
			continue
		var tree: AnimationTree = AnimationTreeBuilder.build(def.animation_set)
		if tree == null:
			continue
		AnimationRate.Pacer.take(tree)   # as the game's driver does
		model.add_child(tree)
		tree.root_node = tree.get_path_to(skel.get_parent())
		tree.active = true
		tree.set(AnimationTreeBuilder.P_BLEND, 0.35 + 0.1 * float(i % 4))
		_trees.append(tree)
		_pacers.append(AnimationRate.Pacer.new())
		AnimationRate.apply_range(model, GraphicsQuality.detail)


func _median(a: PackedFloat32Array) -> float:
	return _quantile(a, 0.5)


func _quantile(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s: PackedFloat32Array = a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * float(s.size()))) - 1, 0, s.size() - 1)]
