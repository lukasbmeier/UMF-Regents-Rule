extends Node
## EntityRegistry — routes RowEvents to entity nodes and buffers the ones that arrive early.
##
## Phase 2 scope: routing + buffering + the two hooks the Phase 3 spawner will consume
## (entity_row_inserted / entity_row_deleted). SpaceTimeEntity itself lands in Phase 3; until
## then anything registered here only needs a `receive_row_event(ev: RowEvent)` method.
##
## Why buffering exists (Blindspot #3): rows for one entity span several tables and arrive in
## arbitrary order. `health_state` can show up before the spawner has even seen the `entity`
## row. We hold those events per entity_id and replay them on register().
##
## ONE EVENT PER ROW (DECISIONS #176). An update or a delete names the row it follows (`ev.old` is
## the cache's own instance, the one a held event left as its `new`), so it REPLACES the held event
## rather than queueing beside it: an insert then three updates is held as one insert of the latest
## row, and an insert then a delete as nothing. The buffer therefore never holds more than the cache
## does, and nothing is ever dropped to make room. It used to keep the newest 256 events: the rival
## arrived with 900 catches, they pushed his position out, and he was drawn at the origin, in the lake.

## Fired for rows in the `entity` table specifically — the spawner's trigger.
signal entity_row_inserted(ev: RowEvent)
signal entity_row_deleted(ev: RowEvent)
## An entity's own row changed (its kind: the character its player now plays, DECISIONS #217).
signal entity_row_updated(ev: RowEvent)
## Rows with no entity_id (world_config, session, item_def, …). World systems listen here.
signal global_row_event(ev: RowEvent)

const ENTITY_TABLE: StringName = &"entity"
const PLAYER_TABLE: StringName = &"player"
const BUFFER_TTL_USEC: int = 30_000_000     # drop orphaned buffers after 30 s
const SWEEP_INTERVAL_SEC: float = 5.0

var local_entity_id: int = -1

var _entities: Dictionary[int, Node] = {}
## entity_id -> {row: RowEvent}, in arrival order, keyed by the row the event leaves current.
var _buffers: Dictionary[int, Dictionary] = {}
var _buffer_touched_usec: Dictionary[int, int] = {}
var _sweep_accum: float = 0.0


func _ready() -> void:
	SpaceTimeSync.row_event.connect(_on_row_event)
	SpaceTimeSync.connection_state_changed.connect(_on_connection_state)
	SpaceTimeSync.world_ready.connect(_on_world_ready)


func _process(delta: float) -> void:
	_sweep_accum += delta
	if _sweep_accum >= SWEEP_INTERVAL_SEC:
		_sweep_accum = 0.0
		_sweep_buffers()


# --- Public --------------------------------------------------------------------

## Register a bound entity node. Buffered events are replayed synchronously, in arrival order.
func register(entity_id: int, node: Node) -> void:
	assert(node.has_method(&"receive_row_event"), "Entity node must implement receive_row_event(ev)")
	assert(not _entities.has(entity_id), "entity %d already registered" % entity_id)
	_entities[entity_id] = node
	node.tree_exiting.connect(unregister.bind(entity_id), CONNECT_ONE_SHOT)
	for ev: RowEvent in take_buffered(entity_id):
		node.call(&"receive_row_event", ev)


func unregister(entity_id: int) -> void:
	_entities.erase(entity_id)


func get_entity(entity_id: int) -> Node:
	return _entities.get(entity_id)


## Every registered entity id, for debug views and tests. A copy, so it is safe to iterate
## while entities spawn and despawn.
func all_entity_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_entities.keys())
	return ids


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


func is_local(entity_id: int) -> bool:
	return entity_id == local_entity_id and entity_id >= 0


## Events currently held for an entity that has not registered yet. Spawner uses this to
## hand initial rows to bind() without waiting for another update.
func peek_buffered(entity_id: int) -> Array:
	var held: Dictionary = _buffers.get(entity_id, {})
	return held.values()


## Hold `events` for entity `eid` as if they had just arrived before its scene existed: a respawn
## rebuilds an entity from the cache this way (`EntitySpawner.respawn`).
func rebuffer(eid: int, events: Array[RowEvent]) -> void:
	for ev: RowEvent in events:
		if ev.entity_id == eid:
			_buffer(ev)


## Take the buffered events and clear them, so they are delivered exactly once.
##
## The spawner uses this rather than `peek_buffered` because it feeds the events to `bind()` as
## initial state, and `register()` replays whatever is still buffered straight afterwards —
## peeking delivered every initial row twice. Harmless for a component that just mirrors a
## value, but a counting component (inventory) would double-count. Anything buffered AFTER
## this call still replays on `register()`, which is correct: those are genuinely new.
func take_buffered(entity_id: int) -> Array:
	var out: Array = peek_buffered(entity_id)
	_buffers.erase(entity_id)
	_buffer_touched_usec.erase(entity_id)
	return out


# --- Internal -------------------------------------------------------------------

func _on_row_event(ev: RowEvent) -> void:
	if ev.table == ENTITY_TABLE:
		match ev.kind:
			RowEvent.Kind.INSERTED: entity_row_inserted.emit(ev)
			RowEvent.Kind.DELETED:  entity_row_deleted.emit(ev)
			RowEvent.Kind.UPDATED:  entity_row_updated.emit(ev)
			_: pass
		# entity rows are also routed to the entity (kind changes, owner changes).

	if ev.table == PLAYER_TABLE:
		_maybe_assign_local(ev)

	if ev.entity_id < 0:
		global_row_event.emit(ev)
		return

	var node: Node = _entities.get(ev.entity_id)
	if node != null:
		node.call(&"receive_row_event", ev)
	else:
		_buffer(ev)


func _buffer(ev: RowEvent) -> void:
	if ev.kind == RowEvent.Kind.DELETED and not _buffers.has(ev.entity_id):
		return   # nothing to delete; no point holding a tombstone
	var held: Dictionary = _buffers.get_or_add(ev.entity_id, {})
	_buffer_touched_usec[ev.entity_id] = ev.received_usec
	var before: RowEvent = held.get(ev.old) as RowEvent if ev.old != null else null
	if before != null:
		# This event follows a held one: the entity will only ever need the row as it is now.
		held.erase(ev.old)
		if ev.kind == RowEvent.Kind.DELETED:
			if before.kind == RowEvent.Kind.INSERTED:
				return   # arrived and left before the entity existed: nothing to tell it
			ev = _merged(RowEvent.Kind.DELETED, ev, before.old, null)
		else:
			ev = _merged(before.kind, ev, before.old, ev.new)
	held[ev.current()] = ev


## `ev` restated as one event from `old` to `new`, keeping when it arrived.
static func _merged(kind: RowEvent.Kind, ev: RowEvent, old: RefCounted, new: RefCounted) -> RowEvent:
	var out: RowEvent = RowEvent.make(kind, ev.table, old, new)
	out.received_usec = ev.received_usec
	return out


func _sweep_buffers() -> void:
	var now: int = Time.get_ticks_usec()
	for eid: int in _buffer_touched_usec.keys():
		if now - _buffer_touched_usec[eid] > BUFFER_TTL_USEC:
			push_warning("EntityRegistry: dropping %d orphaned events for entity %d" % [_buffers[eid].size(), eid])
			_buffers.erase(eid)
			_buffer_touched_usec.erase(eid)


func _maybe_assign_local(ev: RowEvent) -> void:
	if ev.kind == RowEvent.Kind.DELETED or SpaceTimeSync.local_identity.is_empty():
		return
	var row: RefCounted = ev.new
	var ident: Variant = row.get(&"identity")
	if ident is PackedByteArray and ident == SpaceTimeSync.local_identity:
		var eid: Variant = row.get(&"entity_id")
		if eid != null:
			_assign_local(int(eid))


## Fallback path: the subscription applied but no `player` row event reached us — the row was
## already in the cache. Also covers reconnect, where every row is re-inserted.
func _on_world_ready() -> void:
	var eid: int = SpaceTimeSync.get_local_entity_id()
	if eid >= 0:
		_assign_local(eid)


## The ONLY emitter of `local_entity_assigned`. Both the row-event path and the world-ready
## fallback funnel through here, so the signal fires once per actual change and never on a
## reconnect that resolves to the same entity. Phase 3's EntitySpawner relies on that: a second
## emission for an id it already spawned would double-spawn the local player.
func _assign_local(eid: int) -> void:
	if eid == local_entity_id:
		return
	local_entity_id = eid
	SignalBus.local_entity_assigned.emit(eid)


func _on_connection_state(s: SpaceTimeSync.ConnectionState) -> void:
	if s == SpaceTimeSync.ConnectionState.DISCONNECTED or s == SpaceTimeSync.ConnectionState.FAILED:
		_buffers.clear()
		_buffer_touched_usec.clear()
		local_entity_id = -1
