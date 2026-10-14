@tool
class_name LevelSpeedZone extends Area3D
## A PLACE THAT SLOWS WHOEVER IS IN IT (DECISIONS #231): a hen crawling through a hedge's hole, mud, a
## ladder. A box (`size`, centred on the node) on the zones layer; a body whose feet are in it moves at
## `speed` of its pace (its walk, run, sprint and dash, on top of whatever its status does to them).
## Read where a body is stepped, so its owner's prediction and a referee or sidecar driving it agree:
## both step in the same level. It draws nothing in the game; its box shows in the editor.
##
## THE SERVER DOES NOT KNOW IT. A MODULE world's server bounds a body by its kind and its status, so a
## zone is the client's word: a client that ignored one would cross it at full speed. Right for a
## slowdown that is a game's feel; a genre that needs one held checks it on the server from its own bake.

## Layer 4, "zones" (project.godot's layer names): nothing collides with it; only `speed_at` finds it.
const LAYER: int = 1 << 3

## Metres: the box, centred on the node.
@export var size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(v):
		size = v
		_shape()
## How fast a body in it goes, as a share of its usual pace.
@export_range(0.05, 1.0, 0.01) var speed: float = 0.5


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false


func _ready() -> void:
	_shape()


func _shape() -> void:
	var cs: CollisionShape3D = get_node_or_null(^"Box") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "Box"
		add_child(cs)
	var box: BoxShape3D = cs.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		cs.shape = box
	box.size = size


## The pace at `feet` in `space`: the slowest zone there, 1.0 in none.
static func speed_at(space: PhysicsDirectSpaceState3D, feet: Vector3) -> float:
	if space == null:
		return 1.0
	var q := PhysicsPointQueryParameters3D.new()
	q.position = feet + Vector3(0.0, 0.1, 0.0)
	q.collision_mask = LAYER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var k: float = 1.0
	for hit: Dictionary in space.intersect_point(q, 8):
		var zone: LevelSpeedZone = hit.get("collider") as LevelSpeedZone
		if zone != null:
			k = minf(k, zone.speed)
	return k


## `cfg` at `k` of its pace: walk, run, sprint and dash scaled (a copy; `cfg` itself at 1.0).
static func scaled(cfg: MovementConfig, k: float) -> MovementConfig:
	if is_equal_approx(k, 1.0):
		return cfg
	var c: MovementConfig = cfg.duplicate() as MovementConfig
	c.walk_speed = cfg.walk_speed * k
	c.run_speed = cfg.run_speed * k
	c.sprint_speed = cfg.sprint_speed * k
	c.dash_impulse = cfg.dash_impulse * k
	return c
