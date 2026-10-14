extends Node
## EntitySpawner — turns `entity` rows into scenes and back (ARCHITECTURE §2, autoload 6).
##
## The server's `entity` table is the spawn list. This autoload watches it, instantiates the
## `EntityDefinition` matching `entity.kind`, hands the new node whatever rows `EntityRegistry`
## buffered while the scene did not exist, and frees it again when the row goes away.
##
## Nothing here decides *what* an entity is — that is the definition's job, and definitions are
## supplied by the game layer. The foundation only knows "kind N maps to some scene".

## Populated by the game layer before `world_ready`, either by assigning this array or through
## `register_definition()`. Autoloads cannot carry inspector exports, which is why this is a
## plain array with a registration call rather than `@export`.
var definitions: Array[EntityDefinition] = []

## Where spawned entities are parented. Falls back to the current scene, then the tree root, so
## the spawner is usable in a bare test scene with no world.
var world_root_path: NodePath = NodePath()

var _by_kind: Dictionary[int, EntityDefinition] = {}
var _nodes: Dictionary[int, Node] = {}
## Rows that arrived before the world was ready; replayed on `world_ready`.
var _deferred_inserts: Array[RowEvent] = []
## Deletes seen this frame, not yet acted on — see `_flush_despawns`.
var _pending_despawn: Dictionary[int, Node] = {}
var _world_ready: bool = false
## Whether entity rows become nodes. A sidecar that only REFEREES a world (DECISIONS #226: players
## move themselves, it judges abilities) reads the rows and builds nothing.
var spawning: bool = true
## WHICH rows become nodes, when not all of them: Callable(entity_id: int, kind: int) -> bool. A referee
## builds only the bots it drives (DECISIONS #230). An entity it turns away is built later by
## `spawn_now`, once the filter lets it in.
var spawn_filter: Callable = Callable()


func _ready() -> void:
	EntityRegistry.entity_row_inserted.connect(_on_entity_inserted)
	EntityRegistry.entity_row_deleted.connect(_on_entity_deleted)
	EntityRegistry.entity_row_updated.connect(_on_entity_updated)
	SpaceTimeSync.world_ready.connect(_on_world_ready)
	SpaceTimeSync.connection_state_changed.connect(_on_connection_state)
	get_tree().process_frame.connect(_flush_despawns)


func register_definition(defn: EntityDefinition) -> void:
	if defn == null or defn.scene == null:
		push_error("EntitySpawner: definition with no scene")
		return
	if not definitions.has(defn):
		definitions.append(defn)
	_by_kind[defn.kind] = defn


func get_entity_node(entity_id: int) -> Node:
	return _nodes.get(entity_id, null)


## Every entity node currently spawned. The sidecar walks these once per server tick to collect
## what each one owes the database; nothing else needs the whole list.
func entity_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for n: Node in _nodes.values():
		if is_instance_valid(n):
			out.append(n)
	return out


func spawned_count() -> int:
	return _nodes.size()


## Tear the whole world down. Called when a session ENDS — `disconnected` is terminal
## (DECISIONS #17) — never on a transient drop, which reconnects in place.
##
## The SDK deliberately keeps its row cache after a disconnect so a game can read last-known
## state, and until this existed the spawner kept the SCENES too: a player who left a game was
## still standing in it, still sampling input, still holding the mouse cursor and still sending
## reducer calls that failed with "not connected". The rows can stay; the world cannot. The next
## connect re-inserts everything and the spawner builds it afresh.
func despawn_all() -> void:
	_pending_despawn.clear()
	_deferred_inserts.clear()
	_world_ready = false
	var ids: Array[int] = []
	ids.assign(_nodes.keys())
	for eid: int in ids:
		var node: Node = _nodes[eid]
		_nodes.erase(eid)
		EntityRegistry.unregister(eid)
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
		SignalBus.entity_despawned.emit(eid)


# --- row handling -------------------------------------------------------------------

func _on_world_ready() -> void:
	_world_ready = true
	for defn: EntityDefinition in definitions:
		if defn != null and defn.scene != null:
			_by_kind[defn.kind] = defn
	var queued: Array[RowEvent] = _deferred_inserts.duplicate()
	_deferred_inserts.clear()
	for ev: RowEvent in queued:
		_spawn_from(ev)


func _on_connection_state(state: SpaceTimeSync.ConnectionState) -> void:
	if state == SpaceTimeSync.ConnectionState.DISCONNECTED:
		despawn_all()


func _on_entity_inserted(ev: RowEvent) -> void:
	# Before the subscription applies, the definitions may not be registered yet and the world
	# root may not exist. Hold them rather than spawning into nothing.
	if not _world_ready:
		_deferred_inserts.append(ev)
		return
	_spawn_from(ev)


func _on_entity_deleted(ev: RowEvent) -> void:
	var eid: int = ev.entity_id
	if not _nodes.has(eid):
		return
	# Do NOT free yet. A reconnect tears every row down and re-inserts it in the same drain
	# (DECISIONS #17); freeing here would despawn and respawn the local player, losing its
	# camera and any component state. `_flush_despawns` commits the delete a frame later, by
	# which point a matching re-insert has had its chance to cancel it.
	_pending_despawn[eid] = _nodes[eid]


## AN ENTITY BECAME ANOTHER KIND (DECISIONS #217): its player chose another character (a hen made a
## wolf in the lobby). Its node is built again from the new kind's definition: model, body, movement,
## camera, components, all the new character's, exactly as if it had just arrived.
func _on_entity_updated(ev: RowEvent) -> void:
	var row: RefCounted = ev.current()
	var node: SpaceTimeEntity = _nodes.get(ev.entity_id) as SpaceTimeEntity
	if row == null or node == null or node.definition == null or row.get(&"kind") == null:
		return
	var kind: int = int(row.get(&"kind"))
	if kind == node.definition.kind:
		return
	print("[EntitySpawner] entity %d is now a kind %d (was %d)" % [ev.entity_id, kind, node.definition.kind])
	respawn(ev.entity_id)


## The characters a player may choose to play (DECISIONS #217): one definition per playable kind, the
## one this game registered for it, by kind.
func playable_characters() -> Array[EntityDefinition]:
	var kinds: Array[int] = []
	for k: int in _by_kind.keys():
		if _by_kind[k] != null and _by_kind[k].playable:
			kinds.append(k)
	for d: EntityDefinition in definitions:
		if d != null and d.playable and not kinds.has(d.kind) and not _by_kind.has(d.kind):
			kinds.append(d.kind)
	kinds.sort()
	var out: Array[EntityDefinition] = []
	for k: int in kinds:
		var d: EntityDefinition = _by_kind.get(k, null)
		if d == null:
			for each: EntityDefinition in definitions:
				if each != null and each.kind == k:
					d = each
		out.append(d)
	return out


## Runs once per frame. Anything still pending was a real delete, not a reconnect.
func _flush_despawns() -> void:
	if _pending_despawn.is_empty():
		return
	var ids: Array = _pending_despawn.keys()
	_pending_despawn.clear()
	for eid: int in ids:
		var node: Node = _nodes.get(eid, null)
		if node == null:
			continue
		_nodes.erase(eid)
		EntityRegistry.unregister(eid)
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
		SignalBus.entity_despawned.emit(eid)


func _spawn_from(ev: RowEvent) -> void:
	var row: RefCounted = ev.current()
	if row == null:
		return
	var eid: int = ev.entity_id

	# Reconnect: this id was queued for despawn in the same frame. Keep the node, refresh state.
	if _pending_despawn.has(eid):
		var existing: Node = _pending_despawn[eid]
		_pending_despawn.erase(eid)
		if existing.has_method(&"rebind"):
			existing.call(&"rebind", EntityRegistry.take_buffered(eid))
		return

	if _nodes.has(eid):
		return   # duplicate insert; the row cache is the truth and it has not changed identity
	if not spawning:
		return

	var kind: int = int(row.get(&"kind") if row.get(&"kind") != null else -1)
	if spawn_filter.is_valid() and not bool(spawn_filter.call(eid, kind)):
		return
	var defn: EntityDefinition = _by_kind.get(kind, null)
	if defn == null:
		push_error("EntitySpawner: no EntityDefinition registered for entity.kind %d (entity %d)"
			% [kind, eid])
		return

	var node: Node = defn.scene.instantiate()
	var entity: SpaceTimeEntity = node as SpaceTimeEntity
	if entity == null:
		push_error("EntitySpawner: %s root is not a SpaceTimeEntity" % [defn.scene.resource_path])
		node.free()
		return

	entity.definition = defn
	_world_root().add_child(entity)
	_nodes[eid] = entity

	var world_id: int = int(row.get(&"world_id") if row.get(&"world_id") != null else 0)
	var owner_id: Variant = row.get(&"owner")
	var owner_bytes: PackedByteArray = owner_id if owner_id is PackedByteArray else PackedByteArray()
	# Everything buffered for this entity becomes its initial state. TAKE, not peek: `bind()`
	# ends by calling `EntityRegistry.register()`, which replays anything still buffered, and
	# peeking made every component receive its first row twice.
	entity.bind(eid, world_id, owner_bytes, EntityRegistry.take_buffered(eid))


## BUILD AN ENTITY THE FILTER TURNED AWAY, now that it lets it in (a bot's brain row arrived after its
## entity), from the rows the cache holds. True when it has a node.
func spawn_now(eid: int) -> bool:
	if _nodes.has(eid):
		return true
	var row: RefCounted = SpaceTimeSync.get_row(&"entity", eid)
	if row == null:
		return false
	EntityRegistry.take_buffered(eid)
	EntityRegistry.rebuffer(eid, SpaceTimeSync.entity_rows_as_events(eid, InterestManager.subscribed_tables()))
	_spawn_from(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, row))
	return _nodes.has(eid)


## LET GO OF AN ENTITY'S NODE, its rows still there (a bot no longer this process's to drive).
func release(eid: int) -> void:
	var node: Node = _nodes.get(eid, null)
	if node == null:
		return
	_nodes.erase(eid)
	_pending_despawn.erase(eid)
	EntityRegistry.unregister(eid)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	SignalBus.entity_despawned.emit(eid)


## BUILD AN ENTITY AGAIN from the rows the cache holds now (DECISIONS #166). Its node is freed and
## a new one spawned and bound from scratch, so every component starts over with the new model: a
## look chosen mid-game changes the skeleton the animation, the held item and the camera were
## built on, and rebuilding is the one way none of them is left holding the old one. False when
## there is no such entity, or no row for it in the cache.
func respawn(eid: int) -> bool:
	var node: Node = _nodes.get(eid)
	var row: RefCounted = SpaceTimeSync.get_row(&"entity", eid)
	if node == null or row == null:
		return false
	_nodes.erase(eid)
	_pending_despawn.erase(eid)
	EntityRegistry.unregister(eid)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	EntityRegistry.take_buffered(eid)   # anything held is in the cache too, and is taken again below
	EntityRegistry.rebuffer(eid, SpaceTimeSync.entity_rows_as_events(eid, InterestManager.subscribed_tables()))
	# A new player asks for the cursor as if it had just arrived; a player who had it free (in a
	# menu, where a look is chosen) keeps it free.
	var released: bool = MouseCapture.released_by_player()
	_spawn_from(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, row))
	var rebuilt: SpaceTimeEntity = _nodes.get(eid) as SpaceTimeEntity
	if released and rebuilt != null:
		if rebuilt.is_bound():
			MouseCapture.release()
		else:
			rebuilt.bound.connect(MouseCapture.release, CONNECT_ONE_SHOT)
	print("[EntitySpawner] entity %d rebuilt" % eid)
	return _nodes.has(eid)


func _world_root() -> Node:
	if not world_root_path.is_empty():
		var n: Node = get_node_or_null(world_root_path)
		if n != null:
			return n
	var scene: Node = get_tree().current_scene
	return scene if scene != null else get_tree().root
