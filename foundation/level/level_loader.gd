class_name LevelLoader extends Node
## THE LEVEL ON SCREEN FOLLOWS THE WORLD'S (DECISIONS #175): when the server's `world_level` row for
## our world names another level, its scene replaces the one showing, and every spawned entity moves
## into the new level's `WorldRoot`. A level's scene is the one its bake names
## (`shared/world/<level>.json` `scene`), or `level_scenes` for a level with no bake (the greybox, 0).
##
## Put one in the game scene, pointed at the level the scene starts with (`current`, `current_id`):
## a scene that is always the same level never swaps. Nothing decides here: the server chose the
## level (`set_world_level`, a genre's set-up) and this only shows it.
##
## Moving an entity leaves the tree and enters it again: what leaving does (`EntityRegistry` forgets
## it, its input gives the cursor back) is put right as it arrives, so a level changed with players
## in it keeps every one of them receiving its rows (a disc golf course's next hole).

signal level_changed(level_id: int)

const TABLE: StringName = &"world_level"

## The level node the scene starts with (a child of the game scene), and its number.
@export var current: NodePath
@export var current_id: int = 0
## Scenes for levels the bakes do not name (the greybox: 0).
@export var level_scenes: Dictionary[int, PackedScene] = {}

var _level: Node3D = null
var _level_id: int = 0


func _ready() -> void:
	_level = get_node_or_null(current) as Node3D
	_level_id = current_id
	EntityRegistry.global_row_event.connect(_on_row)


## The level showing now, and its number.
func level() -> Node3D:
	return _level


func level_id() -> int:
	return _level_id


## The scene for a level: its bake's, else `level_scenes`'. Null when nothing says.
func scene_for(level_id: int) -> PackedScene:
	var bake: LevelBake = LevelBake.by_id(level_id)
	if bake != null and not bake.scene.is_empty() and ResourceLoader.exists(bake.scene):
		return load(bake.scene) as PackedScene
	return level_scenes.get(level_id, null)


## Show level `level_id`: its scene in place of the current one, the entities moved into it. False
## when there is no scene for it (said, and the current level stays).
func show_level(level_id: int) -> bool:
	if level_id == _level_id and _level != null:
		return true
	var scene: PackedScene = scene_for(level_id)
	if scene == null:
		push_warning("LevelLoader: the world runs level %d, and nothing says which scene shows it" % level_id)
		return false
	var parent: Node = _level.get_parent() if _level != null else get_parent()
	var fresh: Node3D = scene.instantiate() as Node3D
	parent.add_child(fresh)
	var world_root: Node = fresh.get_node_or_null(^"WorldRoot")
	if world_root == null:
		world_root = fresh
	# Everyone moves into it, where they stood, still hearing their rows (#250).
	EntitySpawner.move_entities_to(world_root)
	if _level != null:
		parent.remove_child(_level)
		_level.queue_free()
	_level = fresh
	_level_id = level_id
	print("[LevelLoader] level %d: %s" % [level_id, scene.resource_path])
	level_changed.emit(level_id)
	return true


func _on_row(ev: RowEvent) -> void:
	if ev.table != TABLE or ev.kind == RowEvent.Kind.DELETED:
		return
	var row: RefCounted = ev.current()
	if row == null:
		return
	if InterestManager.has_world() and int(row.get(&"world_id")) != InterestManager.world_id:
		return
	show_level(int(row.get(&"level_id")))
