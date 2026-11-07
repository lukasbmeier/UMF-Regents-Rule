class_name MineStage extends SubViewportContainer
## MINING'S 3D STAGE (`MINIGAMES_PREP.md` §5; Luke's M7, 2026-11-05: gathering as a 3D stage too, a test): the round's
## rock (its node's own model, its ore nuggets in the ore's color, as the world shows it), and the copper pick swinging
## on its own at it (`FloatingTool`; Luke's play, 2026-11-06: no character on a stage, the player's own is the one
## working, as the anvil's hammer). The pick hovers by the mouse and comes down where a strike landed. `CrackMinigame`
## draws the seam over the rock (a readout, clearer in 2D) and tells it what `CrackModel` landed: PRESENTATION ONLY.
##
## Designers: open `mine_stage.tscn` to move the camera, the light, or the pick's two poses: drag `PickRest` and
## `PickHit` (each shows the pick, a preview only the editor sees); in play both move so the pick's point lands on the
## strike. The pick swings from one to the other, so keep them in the pick's own plane (turned about its local Z) for
## the point to lead. The sounds are `game/regents/art/sound/mining/` (`make_skill_sounds.py`).

## The pick, and its point in its own space (the point that lands: the left end of its head, as the model has it).
@export var pick: PackedScene = preload("res://game/regents/skilling/mining/pickaxe.tscn")
@export var pick_tip: Vector3 = Vector3(-0.31, 0.67, 0.0)
## Every rock stands this tall on the stage (the models differ a lot: the big rock is over 4 m), its front this far
## toward the camera from the middle of the stage.
@export var rock_height: float = 1.9
@export var rock_front_z: float = 1.1

const NUGGET: String = "res://game/regents/art/nature/Pebble_Round_1.gltf"
const ROCK: String = "res://game/regents/art/nature/Rock_Medium_1.gltf"

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _rock_root: Node3D = $Viewport/Stage/Rock
@onready var _dust: CPUParticles3D = $Viewport/Stage/Dust
@onready var _chips: CPUParticles3D = $Viewport/Stage/Chips
@onready var _sparks: CPUParticles3D = $Viewport/Stage/Sparks
@onready var _strike: AudioStreamPlayer = $Strike
@onready var _split: AudioStreamPlayer = $Split
@onready var _miss: AudioStreamPlayer = $Miss

var tool: FloatingTool = null
var _rock: Node3D = null
var _box: AABB = AABB(Vector3(-1.5, 0, -1), Vector3(3, 2, 2))
var _jolt: float = 0.0
var _shake: float = 0.0
var _camera_home: Transform3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the clicks
	stretch = true
	_camera_home = camera.transform
	tool = FloatingTool.make(pick)
	tool.head_local = pick_tip
	$Viewport/Stage.add_child(tool)
	tool.set_poses(FloatingTool.marker(self, ^"Viewport/Stage/PickRest"), FloatingTool.marker(self, ^"Viewport/Stage/PickHit"))
	set_rock(null)


## The round's rock: `node`'s model and its ore (the copper rock's, by default).
func set_rock(node: NodeDef) -> void:
	if _rock != null:
		_rock.queue_free()
	var scene: PackedScene = node.models[0] if node != null and not node.models.is_empty() else load(ROCK) as PackedScene
	_rock = scene.instantiate() as Node3D
	_rock_root.add_child(_rock)
	var color: Color = node.ore_color if node != null else Color(0.85, 0.48, 0.22)
	if color.a > 0.0:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.6
		mat.roughness = 0.35
		var nugget: PackedScene = load(NUGGET) as PackedScene
		for spot: Transform3D in RegentsOreSpots.spots_for(scene, _rock, 5, 7):
			var n: Node3D = nugget.instantiate() as Node3D
			n.transform = spot
			for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
			_rock.add_child(n)
	var raw: AABB = _aabb(_rock)
	var k: float = rock_height / maxf(0.01, raw.size.y)
	_rock.scale = Vector3.ONE * k
	var c: Vector3 = raw.get_center() * k
	_rock.position = Vector3(-c.x, -raw.position.y * k, rock_front_z - raw.end.z * k)
	_box = _rock.transform * raw
	tool.aim(Vector3(0.0, rock_height * 0.5, rock_front_z), true)


## Where the rock is on screen: its box's corners, projected.
func rock_rect() -> Rect2:
	var r: Rect2 = Rect2()
	var first: bool = true
	for i: int in 8:
		var p: Vector2 = _screen(_rock_root.global_transform * _box.get_endpoint(i))
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r


## Where the pick hovers between strikes: over screen point `at` (the mouse, kept on the seam's face).
func hover(at: Vector2) -> void:
	if not tool.is_swinging():
		tool.aim(_world(at))


## A strike that opened the seam at screen point `at` (`split`: the whole seam, the rock splits).
func strike(at: Vector2, split: bool) -> void:
	var spot: Vector3 = _world(at)
	tool.aim(spot)
	tool.swing()
	_chips.position = spot
	_chips.restart()
	_dust.position = spot
	_dust.amount = 40 if split else 12
	_dust.restart()
	if split:
		_jolt = 1.0
		_shake = 1.0
		_play(_split, randf_range(0.95, 1.05))
	else:
		_play(_strike, randf_range(0.93, 1.07))


## A strike off the seam at `at`: the pick jars (it bounces off with a shudder, sparks, the dull knock).
func jar(at: Vector2) -> void:
	tool.aim(_world(at))
	tool.jar()
	_sparks.position = _world(at)
	_sparks.restart()
	_shake = 0.5
	_play(_miss, 1.0)


func _play(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _scale() -> Vector2:
	return size / Vector2(maxi(1, viewport.size.x), maxi(1, viewport.size.y))


func _screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) * _scale()


## The point on the rock's front under screen point `at` (on the plane through the box's front, facing the camera).
func _world(at: Vector2) -> Vector3:
	var front: float = (_rock_root.global_transform * _box.end).z
	var from: Vector3 = camera.project_ray_origin(at / _scale())
	var dir: Vector3 = camera.project_ray_normal(at / _scale())
	var k: float = (front - from.z) / dir.z if absf(dir.z) > 0.0001 else 0.0
	return from + dir * k


static func _aabb(n: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var box: AABB = m.transform * m.get_aabb()
		var p: Node = m.get_parent()
		while p != null and p != n:
			if p is Node3D:
				box = (p as Node3D).transform * box
			p = p.get_parent()
		out = box if first else out.merge(box)
		first = false
	return out if not first else AABB(Vector3(-1.5, 0, -1), Vector3(3, 2, 2))


func _process(delta: float) -> void:
	_jolt = maxf(0.0, _jolt - delta * 4.0)
	_rock_root.position = Vector3(sin(_jolt * 40.0) * 0.04 * _jolt, 0.0, 0.0)
	_shake = maxf(0.0, _shake - delta * 6.0)
	camera.transform = _camera_home
	if _shake > 0.0:
		camera.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.02 * _shake
