class_name IconRender
## AN ICON FROM A 3D MODEL (DECISIONS #271): a piece of content that has a model (an item's held scene)
## gets its bag picture drawn from it, so no icon is ever painted by hand unless a designer wants one. The
## model is laid along the picture's diagonal (its longest side), turned a little for depth, lit from the
## front-left with a fill, and framed to fit a square with a transparent background.
##
## `tools/render_icons.tscn` draws one for every piece whose `icon_scene()` gives a model, into
## `rendered_icon_path()`; `ContentDef.icon()` finds it there. Needs a renderer (a window): headless
## draws nothing, and `render` returns null.

## The picture's side, in pixels.
const SIZE: int = 128
## How much of the picture the model fills (the rest is margin).
const FILL: float = 0.86


## Draw `scene` into a `size` square (transparent where it is not), in a hidden viewport under `host`.
## Null with no renderer, or a scene with nothing to see.
static func render(scene: PackedScene, host: Node, size: int = SIZE) -> Image:
	if scene == null or DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var stage := Node3D.new()
	vp.add_child(stage)
	var turn := Node3D.new()
	stage.add_child(turn)
	var model: Node = scene.instantiate()
	turn.add_child(model)
	host.add_child(vp)
	var box: AABB = _bounds(model, turn)
	if box.size == Vector3.ZERO:
		vp.queue_free()
		return null
	# Its longest side up the picture, then along the diagonal, a little turned for depth.
	var basis := Basis.IDENTITY
	var longest: int = box.get_longest_axis_index()
	if longest == Vector3.AXIS_X:
		basis = Basis(Vector3.BACK, PI / 2.0)
	elif longest == Vector3.AXIS_Z:
		basis = Basis(Vector3.RIGHT, PI / 2.0)
	basis = Basis(Vector3.BACK, -PI / 4.0) * Basis(Vector3.UP, deg_to_rad(25.0)) * basis
	turn.transform = Transform3D(basis, -(basis * box.get_center()))
	box = _bounds(model, stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key.light_energy = 1.3
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	fill.light_energy = 0.45
	stage.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.y) / FILL
	cam.near = 0.01
	cam.far = 100.0
	cam.position = Vector3(box.get_center().x, box.get_center().y, box.end.z + 5.0)
	stage.add_child(cam)
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## Every visible mesh's box under `n`, in `space`'s frame.
static func _bounds(n: Node, space: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for v: Node in n.find_children("*", "VisualInstance3D", true, false) + ([n] if n is VisualInstance3D else []):
		var vi: VisualInstance3D = v as VisualInstance3D
		if vi is Light3D or not vi.visible:
			continue
		var b: AABB = space.global_transform.affine_inverse() * vi.global_transform * vi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
