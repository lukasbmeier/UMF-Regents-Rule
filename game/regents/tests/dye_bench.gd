extends Node3D
## THE DYE'S COST AT 300 (W4; WARDROBE.md §6 step 4): what a WATCHING CLIENT pays to draw 50 to 300 players in view,
## each a `RegentsFigure` as the game spawns it, idling. Windowed, no server:
##   "$GODOT" --path . res://game/regents/tests/dye_bench.tscn -- [counts] [frames]      (default 50,100,200,300 and 180)
## Three cases at each count, each measured over `frames` frames after it settles:
##   old     the old look: every body the plain Peasant as painted (no colors, no armor): the baseline
##   likely  a handful of players' color sets (6) and armor of mixed families and tiers (a third bare)
##   worst   every body its own colors and armor of a random family and tier
##   colors6, colors_all   the dye alone: 6 color sets, or every body its own, and no armor (as many surfaces as old)
## Printed: draw calls, GPU ms and the whole frame's ms (vsync off; mean and p95), dye materials made (`Wardrobe.shared_count`),
## surfaces drawn, video memory, and how long the crowd took to build and dress. Then it quits.
## This machine's numbers: compare the cases with each other, not with another machine.

const MALE: String = "res://game/regents/looks/peasant_m.tscn"
const FEMALE: String = "res://game/regents/looks/peasant_f.tscn"
const SETS: Array[Array] = [
	[], ["copper_armet", "copper_cuirass", "copper_legplates"], ["iron_cuirass", "iron_legplates"],
	["steel_armet", "steel_cuirass", "steel_legplates"], ["soft_leather_hood", "soft_leather_jerkin", "soft_leather_trousers"],
	["supple_leather_jerkin", "supple_leather_trousers"], ["linen_robe", "linen_trousers"]]

var _crowd: Array[Node] = []
var _def: EntityDefinition = null


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var counts: Array[int] = [50, 100, 200, 300]
	if args.size() > 0 and not args[0].begins_with("--"):
		counts.clear()
		for c: String in args[0].split(","):
			counts.append(int(c))
	var frames: int = int(args[1]) if args.size() > 1 else 180
	_def = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	_stage()
	_run.call_deferred(counts, frames)


func _stage() -> void:
	get_window().size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # a frame takes what it costs
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 14, 26)
	cam.fov = 55.0
	add_child(cam)
	cam.look_at(Vector3(0, 0, -4))


func _run(counts: Array[int], frames: int) -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i: int in 30:
		await get_tree().process_frame
	# Once through unmeasured: the shaders compiled, the pieces loaded.
	await _build(10, "worst", 1)
	await _settle(30)
	_clear()
	print("DYE case | players | draw calls | surfaces | GPU ms mean/p95 | frame ms mean/p95 | dye materials | video MB | build ms")
	for n: int in counts:
		for kind: String in ["old", "colors6", "colors_all", "likely", "worst"]:
			var before: int = Wardrobe.shared_count()
			var t0: int = Time.get_ticks_usec()
			await _build(n, kind, 7 + n)
			var build_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			var made: int = Wardrobe.shared_count() - before
			await _settle(30)
			var m: Dictionary = await _measure(frames, vp)
			print("DYE %s | %d | %d | %d | %.2f / %.2f | %.2f / %.2f | %d (%d in all) | %.0f | %.0f" % [kind, n, roundi(m["draws"]), roundi(m["objects"]),
				m["gpu"], m["gpu95"], m["cpu"], m["cpu95"], made, Wardrobe.shared_count(), m["vram"], build_ms])
			_clear()
			await _settle(10)
	# After every crowd has gone: what the dye still keeps (a session where players come and go).
	await _settle(30)
	print("DYE after every crowd left: %d dye materials still kept, %d resources, %.1f MB static" % [
		Wardrobe.shared_count(), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	AppExit.quit(get_tree(), 0)


## `n` players in a crowd in view: `kind` as above.
func _build(n: int, kind: String, seed_n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var cols: int = int(ceil(sqrt(float(n) * 1.6)))
	var looks: ArmorLooks = ArmorLooks.current()
	var palettes: Array[Dictionary] = []
	for p: int in 6:
		palettes.append(_colors(rng))
	for i: int in n:
		var female: bool = i % 2 == 1
		var f: RegentsFigure = (load(FEMALE if female else MALE) as PackedScene).instantiate() as RegentsFigure
		var text: String = "peasant_f" if female else "peasant_m"
		var items: Array[int] = []
		if kind == "likely":
			text = RegentsColors.with_colors(text, palettes[i % palettes.size()])
			items = _items(SETS[(i / 2) % SETS.size()] if i % 3 != 0 else [])
		elif kind == "colors6":
			text = RegentsColors.with_colors(text, palettes[i % palettes.size()])
		elif kind == "colors_all":
			text = RegentsColors.with_colors(text, _colors(rng))
		elif kind == "worst":
			text = RegentsColors.with_colors(text, _colors(rng))
			items = _items(SETS[rng.randi_range(1, SETS.size() - 1)])
		f.apply_appearance(text)
		f.position = Vector3((float(i % cols) - float(cols - 1) * 0.5) * 1.3, 0, -float(i / cols) * 1.4)
		add_child(f)
		if not items.is_empty():
			var got: Array = looks.dress_for(items, f.body)
			var pieces: Dictionary[StringName, PackedScene] = got[0]
			var pals: Dictionary[String, DyePalette] = got[1]
			f.wear_armor(pieces, pals)
		CharacterPicker.play_idle(f, _def)
		_crowd.append(f)
	await get_tree().process_frame


func _items(files: Array) -> Array[int]:
	var out: Array[int] = []
	for file: Variant in files:
		out.append((load("res://game/regents/content/item/%s.tres" % String(file)) as ItemDef).id)
	return out


func _colors(rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in RegentsColors.KEYS:
		out[k] = Color8(rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255))
	return out


func _clear() -> void:
	for n: Node in _crowd:
		n.queue_free()
	_crowd.clear()


func _settle(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _measure(frames: int, vp: RID) -> Dictionary:
	var draws: float = 0.0
	var objects: float = 0.0
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	await RenderingServer.frame_post_draw
	var last: int = Time.get_ticks_usec()
	for i: int in frames:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(float(now - last) / 1000.0)   # the whole frame, start to drawn
		last = now
	gpu.sort()
	cpu.sort()
	return {"draws": draws / frames, "objects": objects / frames, "gpu": _mean(gpu), "gpu95": gpu[int(frames * 0.95)],
		"cpu": _mean(cpu), "cpu95": cpu[int(frames * 0.95)],
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}


func _mean(a: Array[float]) -> float:
	var s: float = 0.0
	for v: float in a:
		s += v
	return s / maxf(float(a.size()), 1.0)
