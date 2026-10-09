extends Node3D
## THE WATER SHOWS ITS DEPTH from where the player stands (DECISIONS #150). The lake's shader,
## over a bed 2 m down (about the lake's median) beside one 8 m down (its deepest tenth), seen
## low across the surface the way a third-person camera sees a lake. The two halves must come out
## plainly different colours at the same distance. The shader used to colour by the length of the
## line of sight through the water, which at this angle is many metres over both: past the first
## couple of metres the whole lake read as one flat blue.
##
## Needs pixels, so it is part of tests/render_test.sh. Prints RENDER PASS/FAIL, exits 1 on a failure.

const SETTLE_FRAMES: int = 16
const PATCH: int = 16

var _failures: int = 0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 20.0, 0.0)
	add_child(sun)
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.78, 0.7, 0.5)
	# Left of x = 0 a bed 2 m under the surface, right of it one 8 m down.
	for spec: Array in [[-15.0, -2.0], [15.0, -8.0]]:
		var bed := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(30.0, 1.0, 80.0)
		bed.mesh = box
		bed.material_override = sand
		bed.position = Vector3(float(spec[0]), float(spec[1]) - 0.5, 0.0)
		add_child(bed)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/world/lake_water.gdshader") as Shader
	water.material_override = mat
	add_child(water)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	# Low across the water, as the game's camera stands behind an angler on the shore.
	cam.look_at_from_position(Vector3(0.0, 3.0, 22.0), Vector3(0.0, 0.0, 0.0))
	cam.make_current()
	_run.call_deferred()


func _run() -> void:
	for i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var size: Vector2i = img.get_size()
	# The same row, a quarter in from each side: equally far from the camera, one over each bed.
	var row: int = int(size.y * 0.62)
	var shallow: Color = _mean(img, Vector2i(int(size.x * 0.25), row))
	var deep: Color = _mean(img, Vector2i(int(size.x * 0.75), row))
	var apart: float = Vector3(shallow.r - deep.r, shallow.g - deep.g, shallow.b - deep.b).length()
	print("   over 2 m %s, over 8 m %s: %.3f apart" % [_rgb(shallow), _rgb(deep), apart])
	# Coloured by the line of sight, these came out 0.165 apart, both blue, the 2 m one only paler.
	_expect(apart > 0.28 and shallow.g > deep.g + 0.2,
		"seen low across the lake, 2 m and 8 m of water are plainly different colours (%.3f apart)" % apart)
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


func _mean(img: Image, c: Vector2i) -> Color:
	var sum: Color = Color(0, 0, 0, 0)
	for y: int in range(c.y - PATCH / 2, c.y + PATCH / 2):
		for x: int in range(c.x - PATCH / 2, c.x + PATCH / 2):
			sum += img.get_pixel(x, y)
	var n: float = float(PATCH * PATCH)
	return Color(sum.r / n, sum.g / n, sum.b / n)


static func _rgb(c: Color) -> String:
	return "(%d, %d, %d)" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("RENDER PASS ", msg)
	else:
		_failures += 1
		printerr("RENDER FAIL ", msg)
