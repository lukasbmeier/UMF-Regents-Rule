class_name LoginBackdrop extends Node3D
## THE LOGIN SCREEN'S PICTURE (2026-11-15): the showcase valley at dusk behind the form, alive: the camp's fire, a
## guard looking out to the keep, a smith at the anvil, the wizard and the ranger by the fire, fireflies, the keep's
## lit windows, and the camera drifting slowly to and fro. Built when the screen shows and freed when it hides
## (`RegentsLogin`), so none of it costs anything in play. Its values are the login scene's, in the Inspector.

const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const SWORD: PackedScene = preload("res://game/regents/combat/weapons/iron_sword.tscn")
const STAFF: PackedScene = preload("res://game/regents/combat/weapons/yew_staff.tscn")
const BOW: PackedScene = preload("res://game/regents/combat/weapons/yew_bow.tscn")
const HAMMER: PackedScene = preload("res://game/regents/skilling/smithing/hammer.tscn")

## The mood behind the form.
@export var mood: ShowcaseMood = preload("res://game/regents/showcase/moods/dusk.tres")
## How much of the valley is drawn (the labs draw 1).
@export_range(0.2, 1.0, 0.05) var detail: float = 0.55
## The camera's two ends and what it looks at; it drifts between them and back over `drift_s`.
@export var eye_a: Vector3 = Vector3(7.5, 2.1, 10.5)
@export var eye_b: Vector3 = Vector3(3.0, 2.9, 11.5)
@export var look_at_point: Vector3 = Vector3(-10.0, 6.0, -70.0)
@export_range(5.0, 300.0, 1.0, "suffix:s") var drift_s: float = 70.0
@export_range(10.0, 100.0, 0.5, "suffix:deg") var fov: float = 52.0

var world: ShowcaseWorld = null
var camera: Camera3D = null
var _t: float = 0.0


func _ready() -> void:
	world = ShowcaseWorld.new()
	world.name = "World"
	world.detail = detail
	world.mood = mood
	world.clear_paths = [[eye_a, eye_a + (look_at_point - eye_a).limit_length(60.0), 5.0],
		[eye_b, eye_b + (look_at_point - eye_b).limit_length(60.0), 5.0]]
	world.clearings = [Vector3(0.0, 0.0, 8.0)]
	add_child(world)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 3000.0
	camera.fov = fov
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	_people()
	_place_camera()


func _people() -> void:
	var guard: ShowcaseActor = _put(6, SWORD, Vector3(-3.4, 0.0, -1.6))
	guard.face(Vector3(-62.0, 0.0, -128.0), true)
	var smith: ShowcaseActor = _put(0, HAMMER, Vector3(3.0, 0.0, 3.7))
	smith.face(Vector3(3.6, 0.0, 3.0), true)
	smith.play(&"pose.smith")
	var ranger: ShowcaseActor = _put(1, BOW, Vector3(-1.5, 0.0, 1.4))
	ranger.face(Vector3.ZERO, true)
	var wizard: ShowcaseActor = _put(2, STAFF, Vector3(1.6, 0.0, -1.1))
	wizard.face(Vector3.ZERO, true)


func _put(look: int, weapon: PackedScene, at: Vector3) -> ShowcaseActor:
	var a: ShowcaseActor = ShowcaseActor.make(ADVENTURER, look, weapon)
	a.ground = world.ground_at
	add_child(a)
	a.walk_to(at, 0.0)
	return a


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


func _place_camera() -> void:
	var u: float = 0.5 - 0.5 * cos(_t / drift_s * TAU)
	camera.look_at_from_position(eye_a.lerp(eye_b, u), look_at_point)
