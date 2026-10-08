class_name SimWorld extends Node3D
## One world this process simulates: the collision geometry entities are resolved against, and
## the node the spawner parents them under.
##
## THE LEVEL IS THE SAME SCENE THE CLIENTS LOAD, and that is not a convenience. The authority
## resolves movement with `move_and_slide` against this geometry while each client predicts
## against its own copy; if the two differ by so much as a step, every player is corrected the
## moment they touch it (`docs/ARCHITECTURE.md` §6). A sidecar-specific "collision only" level
## would be a second thing to keep in sync, and nothing would report it drifting.
##
## The visual half of the scene comes along for the ride. A dedicated-server export strips it
## (`docs/SIDECAR_SPEC.md` §1) and a headless run draws nothing regardless, so the cost is some
## mesh memory rather than any work per frame.
##
## SERVER-ONLY (hard rule 7b).

## Where entities are parented. The level scene may nominate one; otherwise this node.
@export var entity_root_name: StringName = &"WorldRoot"

var world_id: int = 0
var sync: AuthoritySync = null

var _level: Node3D = null


## Build the world. Call before the connection is opened, so the geometry exists by the time the
## first entity row arrives.
func setup(p_world_id: int, level: PackedScene, tick_hz: float = 20.0) -> void:
	world_id = p_world_id
	name = "World%d" % world_id
	if level != null:
		_level = level.instantiate() as Node3D
		if _level != null:
			add_child(_level)
	else:
		push_warning("SimWorld %d: no level scene — movement will resolve against nothing and "
			% world_id + "every entity will walk through every wall.")
	sync = AuthoritySync.new()
	sync.name = "AuthoritySync"
	sync.world_id = world_id
	sync.tick_hz = tick_hz
	add_child(sync)


## The node entities are spawned under. A level that names a `WorldRoot` gets to keep its own
## layout; anything else parents to the world itself.
func entity_root() -> Node3D:
	if _level != null:
		var named: Node = _level.get_node_or_null(NodePath(String(entity_root_name)))
		var as_3d: Node3D = named as Node3D
		if as_3d != null:
			return as_3d
	return self
