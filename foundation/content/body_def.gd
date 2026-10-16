@tool
class_name BodyDef extends ContentDef
## A BODY (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246): something thrown, kicked or launched that
## the world's referee then flies with real physics: a disc, a ball, an egg, a thrown item. In the world
## it is an entity (kind 3) whose place every client takes from its `movement_state` row, and whose turn,
## spin and rest come in a `body_state` row; what it IS (its shape, how it bounces, what pushes it in the
## air, who may throw it and how hard) is here. Tried in its bench (`tools/workbench/body_workbench.tscn`)
## with no server.
##
## "Launching" is the server's (baked: who may, how fast, from how far, how many, how long it lasts);
## "In flight" and "At rest" are the physics both the referee and the thrower's game run (not baked: they
## read this resource). "How it shows" is presentation only.

enum Shape { SPHERE, CYLINDER, BOX }

@export_group("Its body")
## Its collision shape. A disc is a short cylinder (it flies on its flat side), a ball a sphere.
@export var shape: Shape = Shape.SPHERE
## A sphere's or cylinder's radius.
@export_range(0.01, 5.0, 0.005, "suffix:m") var radius_m: float = 0.11
## A cylinder's height (a disc: 2 cm).
@export_range(0.005, 5.0, 0.005, "suffix:m") var height_m: float = 0.02
## A box's size.
@export var box_size: Vector3 = Vector3(0.3, 0.3, 0.3)
## Its mass: what a collision with another body shares out.
@export_range(0.01, 100.0, 0.01, "suffix:kg") var mass_kg: float = 0.2

@export_group("In flight")
## How much of its speed a bounce keeps (0: it stops dead, 1: it bounces as high as it fell).
@export_range(0.0, 1.0, 0.01) var bounce: float = 0.3
## How much it grips what it touches (0: ice; 1: rubber on rubber). Rolling and skidding come from this.
@export_range(0.0, 1.0, 0.01) var friction: float = 0.6
## Air drag on its speed, a share a second (a disc's real drag belongs in its forces).
@export_range(0.0, 10.0, 0.01) var linear_damp: float = 0.05
## Drag on its spin, a share a second.
@export_range(0.0, 10.0, 0.01) var angular_damp: float = 0.1
## Drag while it touches something (the ground, a wall it slides along), a share of its speed and spin a
## second: what stops a ball rolling and a disc skidding across the grass. Godot's physics has no rolling
## resistance of its own, so without this a ball rolls on and on.
@export_range(0.0, 20.0, 0.05) var ground_drag: float = 1.5
## How much gravity pulls it (1: as anything falls).
@export_range(-2.0, 4.0, 0.05) var gravity_scale: float = 1.0
## What else pushes it in the air (a genre's: a disc's flight). None: gravity, bounce and drag only.
@export var forces: BodyForces

@export_group("Launching")
## The characters that may throw it themselves (`launch_body`). None: only a genre's own rules launch
## it (`launch_body_internal`: a disc thrown from the lie).
@export var launched_by: Array[EntityDefinition] = []
## The fastest it may leave a hand. The server refuses a throw faster than this.
@export_range(0.0, 200.0, 0.1, "suffix:m/s") var max_speed_mps: float = 25.0
## The fastest it may spin as it leaves (radians a second; a disc thrown hard spins ~60).
@export_range(0.0, 400.0, 0.5, "suffix:rad/s") var max_spin_rps: float = 30.0
## How far from its thrower it may start (where the server last had them, plus their own speed for the
## time a row takes): a hand's reach.
@export_range(0.0, 10.0, 0.05, "suffix:m") var reach_m: float = 2.0
## How many of these one thrower may have in the world at once; a further throw takes away their oldest.
## 0: any number.
@export_range(0, 64) var max_per_owner: int = 3
## How long one lasts once thrown (0: until a genre takes it away).
@export_range(0.0, 3600.0, 1.0, "suffix:s") var lifetime_s: float = 60.0

@export_group("At rest")
## Slower than this (and spinning slower than a turn a second) it is settling...
@export_range(0.01, 5.0, 0.01, "suffix:m/s") var rest_speed_mps: float = 0.15
## ...and settled this long, it is at rest: it stops, and costs nothing until something moves it.
@export_range(0.0, 10.0, 0.05, "suffix:s") var rest_s: float = 0.5
## A hit faster than this is reported (the genre hears it; a sound plays): a tree kick, a disc to the face.
@export_range(0.0, 100.0, 0.1, "suffix:m/s") var contact_speed_mps: float = 3.0

@export_group("How it shows")
## Its model; none: a plain shape of its own size.
@export var visual_scene: PackedScene
## Where its model sits from the body's centre.
@export var visual_offset: Vector3 = Vector3.ZERO
## A plain shape's colour (when it has no model).
@export var color: Color = Color(0.95, 0.55, 0.15)

## The bodies themselves while the game runs, by id (as `HoldDef._held`, DECISIONS #224).
static var _by_id: Dictionary[int, BodyDef] = {}


func content_type() -> StringName:
	return &"body"


func summary() -> String:
	return "%s, %.2f kg; at most %.0f m/s; %s" % [Shape.keys()[shape].to_lower(), mass_kg, max_speed_mps,
		"thrown by %d kind(s)" % HoldDef.kinds_of(launched_by).size() if not launched_by.is_empty() else "launched by its genre"]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"launchers": HoldDef.kinds_of(launched_by),
		"max_speed_mps": max_speed_mps,
		"max_spin_rps": max_spin_rps,
		"reach_m": reach_m,
		"max_per_owner": max_per_owner,
		"lifetime_s": lifetime_s,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if not launched_by.is_empty() and max_speed_mps <= 0.0:
		out.append("its characters may throw it, at no speed: give it a max speed")
	if shape == Shape.BOX and (box_size.x <= 0.0 or box_size.y <= 0.0 or box_size.z <= 0.0):
		out.append("it is a box with no size")
	if shape == Shape.CYLINDER and height_m > radius_m * 8.0:
		out.append("it is a cylinder %.0f times as tall as it is wide: a box or two bodies?" % (height_m / (radius_m * 2.0)))
	return out


## Its collision shape, sized.
func make_shape() -> Shape3D:
	match shape:
		Shape.CYLINDER:
			var c := CylinderShape3D.new()
			c.radius = radius_m
			c.height = height_m
			return c
		Shape.BOX:
			var b := BoxShape3D.new()
			b.size = box_size
			return b
	var s := SphereShape3D.new()
	s.radius = radius_m
	return s


## What draws it: its model, or a plain shape of its size in its colour.
func make_visual() -> Node3D:
	if visual_scene != null:
		var model: Node3D = visual_scene.instantiate() as Node3D
		if model != null:
			model.position = visual_offset
			return model
	var mi := MeshInstance3D.new()
	match shape:
		Shape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = radius_m
			c.bottom_radius = radius_m
			c.height = height_m
			mi.mesh = c
		Shape.BOX:
			var b := BoxMesh.new()
			b.size = box_size
			mi.mesh = b
		_:
			var s := SphereMesh.new()
			s.radius = radius_m
			s.height = radius_m * 2.0
			mi.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = visual_offset
	return mi


## The body with content id `body_id` (what `body_state.def_id` names), or null.
static func by_id(body_id: int) -> BodyDef:
	if not Engine.is_editor_hint() and not _by_id.is_empty():
		return _by_id.get(body_id, null)
	var all: Dictionary[int, BodyDef] = {}
	for d: ContentDef in ContentLibrary.items(&"body"):
		var b: BodyDef = d as BodyDef
		if b != null:
			all[b.id] = b
	if not Engine.is_editor_hint():
		_by_id = all
	return all.get(body_id, null)


## Put a body in the table by hand (tests, a bench trying one that is not saved yet).
static func remember(def: BodyDef) -> void:
	if def != null:
		if _by_id.is_empty():
			by_id(-1)
		_by_id[def.id] = def


static func clear_cache() -> void:
	_by_id.clear()
