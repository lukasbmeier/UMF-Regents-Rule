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
## The level the world runs (`world_level`), once the server has said: its scene replaces the one
## `setup` was given, as `LevelLoader` does for a client (DECISIONS #175, #226).
var level_id: int = -1

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


## Follow the server's `world_level` for this world: the level its bake names. Called once connected
## rows flow (`SpaceTimeSync.row_event`).
func follow_level() -> void:
	if not SpaceTimeSync.row_event.is_connected(_on_row):
		SpaceTimeSync.row_event.connect(_on_row)


func _on_row(ev: RowEvent) -> void:
	if ev.table != &"world_level" or ev.kind == RowEvent.Kind.DELETED:
		return
	var row: RefCounted = ev.current()
	if row == null or int(row.get(&"world_id")) != world_id:
		return
	show_level(int(row.get(&"level_id")))


## The level `id` in place of the one loaded: its bake's scene. False (and the current one kept)
## when no bake names a scene for it.
func show_level(id: int) -> bool:
	if id == level_id and _level != null:
		return true
	var bake: LevelBake = LevelBake.by_id(id)
	if bake == null or bake.scene.is_empty() or not ResourceLoader.exists(bake.scene):
		push_warning("SimWorld %d: the world runs level %d and no bake names its scene; keeping the one loaded" % [world_id, id])
		return false
	var fresh: Node3D = (load(bake.scene) as PackedScene).instantiate() as Node3D
	var old: Node3D = _level
	_level = fresh
	add_child(_level)
	move_child(_level, 0)
	# Everyone it simulates moves into the new level's root, where they stood, still hearing their rows
	# (DECISIONS #253: as the client's LevelLoader; before, a bot the server put on the next hole's tee
	# never heard of it, and walked back from the last basket, or fell where the new level has no ground).
	EntitySpawner.move_entities_to(entity_root())
	if old != null:
		remove_child(old)
		old.queue_free()
	level_id = id
	print("[Sidecar] world %d runs level %d: %s" % [world_id, id, bake.scene])
	return true


## The level loaded now.
func level() -> Node3D:
	return _level


## The node entities are spawned under. A level that names a `WorldRoot` gets to keep its own
## layout; anything else parents to the world itself.
func entity_root() -> Node3D:
	if _level != null:
		var named: Node = _level.get_node_or_null(NodePath(String(entity_root_name)))
		var as_3d: Node3D = named as Node3D
		if as_3d != null:
			return as_3d
	return self
