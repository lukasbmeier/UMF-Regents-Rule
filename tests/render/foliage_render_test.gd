extends Node3D
## THE LOOK, RENDERED (DECISIONS #141). A headless run has no pixels, so this one opens a window:
##
##   godot --path . --resolution 320x240 res://tests/render/foliage_render_test.tscn
##   (or tests/render_test.sh)
##
## One grass blade the way the Nature kit authors it — a double-sided quad whose normals point
## straight UP — under a sun, seen from the front and from behind. A blade must look the same
## from both sides. Under a plain double-sided StandardMaterial3D it does not: the engine turns a
## back face's normal round, so an up-facing blade seen from behind is lit as if it faced the
## ground. That is checked too, as the control — it is the bug this guards, and a test that
## could not see it would pass whatever the shader did. Then the shipped grass material, as the
## import made it, under the same light.
##
## Prints `RENDER PASS`/`RENDER FAIL` per check and exits 1 on any failure.

const PATCH: int = 24
const SETTLE_FRAMES: int = 12

var _failures: int = 0
var _blade: MeshInstance3D = null
var _cam: Camera3D = null


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.1, 0.1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	# Straight overhead, so the front and back views are mirror images of each other. From a
	# slant, Burley diffuse (the kit's) lights an edge-on blade up to twice as bright with the sun
	# behind the viewer — a real look, but not the one this test is about.
	sun.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	sun.light_energy = 0.5
	sun.shadow_enabled = false
	add_child(sun)
	_blade = MeshInstance3D.new()
	_blade.mesh = _up_normal_quad()
	add_child(_blade)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _run() -> void:
	var std := StandardMaterial3D.new()
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.roughness = 1.0
	std.metallic_specular = 0.0
	var std_front: float = await _luminance(std, true)
	var std_back: float = await _luminance(std, false)
	print("   StandardMaterial3D: front %.3f, back %.3f" % [std_front, std_back])
	_expect(std_back < 0.4 * std_front,
		"CONTROL: a plain double-sided material draws an up-facing blade dark from behind (%.3f vs %.3f) — the bug"
			% [std_back, std_front])

	var fol: ShaderMaterial = FoliageMaterial.from_standard(std)
	var fol_front: float = await _luminance(fol, true)
	var fol_back: float = await _luminance(fol, false)
	print("   foliage shader:     front %.3f, back %.3f" % [fol_front, fol_back])
	_expect(absf(fol_back - fol_front) < 0.05 * fol_front,
		"the foliage shader lights a blade the same from behind as from the front (%.3f vs %.3f)" % [fol_back, fol_front])
	_expect(absf(fol_front - std_front) < 0.05 * std_front,
		"and its front is the kit material's front (%.3f vs %.3f)" % [fol_front, std_front])

	# The shipped grass, as imported: its own material and texture on the same blade.
	var grass: Material = _kit_material("res://game/world/kits/nature/Grass_Common_Short.gltf", "Grass")
	_expect(grass is ShaderMaterial, "the shipped grass is drawn by the foliage shader")
	if grass != null:
		var g_front: float = await _luminance(grass, true)
		var g_back: float = await _luminance(grass, false)
		print("   shipped grass:      front %.3f, back %.3f" % [g_front, g_back])
		_expect(g_front > 0.02 and absf(g_back - g_front) < 0.05 * g_front,
			"the shipped grass is lit the same from both sides (%.3f vs %.3f)" % [g_back, g_front])

	await _run_distance()
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


## THE GRASS KEEPS ITS COLOUR AT A DISTANCE (Luke: "the grass changes colors based on how far away
## we are"). The kit colours its grass from a palette of thin stripes (`Grass.png`: yellow, green,
## orange, light green, then white), and a mipmap averages a stripe into its neighbours: seen at
## a third-person distance, the light-green grass sampled a mip where it had turned whitish. The
## shipped tuft, as imported, is drawn close up and small (the size it is on screen from a
## third-person camera), and its colour compared. A plain mipmapped material on the same tuft is
## the control that shows the bug.
const NEAR_PX: float = 110.0
const FAR_PX: float = 9.0
const AVERAGE_FRAMES: int = 6


func _run_distance() -> void:
	_blade.visible = false
	var scene: PackedScene = load("res://game/world/kits/nature/Grass_Common_Short.gltf") as PackedScene
	var tuft: Node3D = scene.instantiate() as Node3D if scene != null else null
	_expect(tuft != null, "the shipped grass tuft loads")
	if tuft == null:
		return
	add_child(tuft)
	var meshes: Array[MeshInstance3D] = []
	for n: Node in tuft.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as MeshInstance3D)
	var box: AABB = AABB()
	for i: int in range(meshes.size()):
		var b: AABB = meshes[i].global_transform * meshes[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	var shipped: Material = _kit_material("res://game/world/kits/nature/Grass_Common_Short.gltf", "Grass")
	var tex: Texture2D = (shipped as ShaderMaterial).get_shader_parameter(&"texture_albedo") as Texture2D \
		if shipped is ShaderMaterial else null

	# The control: the kit's own texture, sampled the way a StandardMaterial3D samples it.
	var mip := StandardMaterial3D.new()
	mip.albedo_texture = tex
	mip.cull_mode = BaseMaterial3D.CULL_DISABLED
	mip.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for m: MeshInstance3D in meshes:
		m.material_override = mip
	var mip_near: Color = await _tuft_colour(box, NEAR_PX)
	var mip_far: Color = await _tuft_colour(box, FAR_PX)
	print("   mipmapped palette:  near %s, far %s" % [_rgb(mip_near), _rgb(mip_far)])
	# Half way between the fixed grass (0.03) and the bug (0.12-0.14 measured): a margin both ways.
	_expect(_drift(mip_near, mip_far) > 0.08,
		"CONTROL: sampled through its mipmaps, the grass fades to another colour at a distance (%.2f) — the bug"
			% _drift(mip_near, mip_far))

	for m: MeshInstance3D in meshes:
		m.material_override = null
	var near: Color = await _tuft_colour(box, NEAR_PX)
	var far: Color = await _tuft_colour(box, FAR_PX)
	print("   shipped grass:      near %s, far %s" % [_rgb(near), _rgb(far)])
	_expect(near.g > near.r and near.g > near.b and _drift(near, far) < 0.05,
		"the shipped grass is the same green close up and %d px tall (%.2f apart)" % [int(FAR_PX), _drift(near, far)])
	tuft.queue_free()


## The tuft's mean colour (sRGB, as shown) when it stands `px` pixels tall on screen, seen level
## from the front at the game camera's field of view. Background pixels (black) are left out.
func _tuft_colour(box: AABB, px: float) -> Color:
	var screen_h: float = get_viewport().get_visible_rect().size.y
	_cam.fov = 70.0
	var dist: float = box.size.y * screen_h / (2.0 * px * tan(deg_to_rad(_cam.fov) * 0.5))
	var centre: Vector3 = box.get_center()
	_cam.look_at_from_position(centre + Vector3(0.0, 0.0, dist), centre)
	for i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	# Several frames, averaged: a tuft a few pixels tall moves with the anti-aliasing's jitter, and
	# one frame read the control 0.14, 0.13 and 0.12 apart on three runs. Only the tuft's own
	# rectangle on screen is read: every pixel of the window, six times, took minutes.
	var rect: Rect2i = _screen_rect(box, 3)
	var sum: Color = Color(0, 0, 0, 0)
	var n: int = 0
	for f: int in range(AVERAGE_FRAMES):
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var r: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var p: Color = img.get_pixel(x, y)
				if p.r + p.g + p.b > 0.12:
					sum += p
					n += 1
	_cam.fov = 40.0
	return Color(sum.r / n, sum.g / n, sum.b / n) if n > 0 else Color.BLACK


## Where `box` falls on screen through the current camera, grown by `margin` pixels.
func _screen_rect(box: AABB, margin: int) -> Rect2i:
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for i: int in range(8):
		var s: Vector2 = _cam.unproject_position(box.get_endpoint(i))
		lo = lo.min(s)
		hi = hi.max(s)
	var p: Vector2i = Vector2i(floori(lo.x) - margin, floori(lo.y) - margin)
	return Rect2i(p, Vector2i(ceili(hi.x) + margin, ceili(hi.y) + margin) - p)


## How far apart two colours are in HUE, brightness aside: the distance between their shares of
## red, green and blue. A tuft that is merely smaller loses brightness at its edges, not its hue.
static func _drift(a: Color, b: Color) -> float:
	var sa: float = maxf(a.r + a.g + a.b, 0.001)
	var sb: float = maxf(b.r + b.g + b.b, 0.001)
	return Vector3(a.r / sa - b.r / sb, a.g / sa - b.g / sb, a.b / sa - b.b / sb).length()


static func _rgb(c: Color) -> String:
	return "(%d, %d, %d)" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("RENDER PASS ", msg)
	else:
		_failures += 1
		printerr("RENDER FAIL ", msg)


## Mean LINEAR luminance of the middle of the screen, where the blade is, looking at its front
## (from +Z) or its back (from -Z).
func _luminance(mat: Material, front: bool) -> float:
	_blade.material_override = mat
	var z: float = 3.0 if front else -3.0
	_cam.look_at_from_position(Vector3(0.0, 0.0, z), Vector3.ZERO)
	for i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var c: Vector2i = img.get_size() / 2
	var sum: float = 0.0
	for y: int in range(c.y - PATCH / 2, c.y + PATCH / 2):
		for x: int in range(c.x - PATCH / 2, c.x + PATCH / 2):
			var p: Color = img.get_pixel(x, y).srgb_to_linear()
			sum += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
	return sum / float(PATCH * PATCH)


## A 2 x 2 m blade in the XY plane, facing +Z, every normal pointing up — how the kit's grass is
## authored. UVs sample the middle of a texture, where the kit's grass is solid.
static func _up_normal_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]
	# Clockwise seen from +Z: Godot's front face.
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(corners[i])
	return st.commit()


static func _kit_material(path: String, material_name: String) -> Material:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var found: Material = null
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i: int in range(mesh.get_surface_count()):
			var m: Material = mesh.surface_get_material(i)
			if m != null and m.resource_name == material_name:
				found = m
	root.free()
	return found
