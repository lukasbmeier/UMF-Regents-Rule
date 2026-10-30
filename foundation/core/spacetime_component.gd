@abstract
class_name SpaceTimeComponent
extends Node
## Base for every synced component. Contract: `docs/ARCHITECTURE.md` §7.
##
## A component NEVER owns authoritative state. It receives rows through `_on_row_updated` and
## may hold only `predicted` and presentation state (hard rule 4). It never references UI
## (hard rule 5) — low-frequency, entity_id-first facts go on `SignalBus`; everything else is
## an entity-local signal the sibling nodes connect to.
##
## Two-phase init (hard rule 8): `_ready()` must not touch synced data, because rows have not
## arrived yet and `entity` is still null. Everything that needs the network happens in
## `bind()`, which the spawner calls. `_ready()` asserts that ordering.
##
## Subclasses implement `required_tables()` and `_on_row_updated()`. They override
## `_on_row_inserted` / `_on_row_deleted` only when insert or delete needs to differ from the
## null-on-one-side update the defaults synthesise.

## The owning entity. Typed `Node` until Phase 3 Task 3 lands `SpaceTimeEntity`.
## ASSUMPTION: Task 3 retypes this to `SpaceTimeEntity`; the only members touched here are
## `entity_id` and `is_local_authority`, both of which that class is specified to expose.
var entity: Node = null
var entity_id: int = -1
## True only on the client that owns this entity. Drives prediction and input sampling.
var is_local_authority: bool = false

var _bound: bool = false


## Tables this component needs before it is useful. The entity gates `bind()` on them and
## routes row events by this list.
@abstract func required_tables() -> Array[StringName]


## The subset of `required_tables()` where an entity may legitimately have NO rows at all —
## collections, like an empty inventory or no pending challenge. Rows from these tables are
## still routed here; bind just does not wait for one to exist. Without this the entity cannot
## tell "not arrived yet" from "there is none", waits out `bind_timeout_sec` on every spawn,
## and a player stands frozen for two seconds because their inventory is empty.
func optional_tables() -> Array[StringName]:
	return []


## Tables it reads itself (`SpaceTimeSync.get_row` / `find_rows`) that are not routed to it: a row it looks
## up by another key (a session by its id, a definition). A referee subscribes these too (DECISIONS #286),
## so a component built there finds them; one left off is an error in the referee, naming it.
func also_reads() -> Array[StringName]:
	return []


## True while this component is in the middle of something a rebuild of the entity would lose
## (DECISIONS #166): a look chosen mid-game waits for it. Only state that lives nowhere but here
## counts (the fishing fight, played on this client); anything in a row is rebuilt from the row.
func blocks_respawn() -> bool:
	return false


## Applied for every row event whose table this component declared. `old` is null on insert,
## `new` is null on delete — the defaults below synthesise that shape so a subclass can treat
## all three kinds uniformly.
@abstract func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void


func _ready() -> void:
	assert(entity == null, "hard rule 8: bind() ran before _ready(). Components are added to " \
		+ "the tree first and bound by the spawner afterwards, never the other way round.")


## Called by the owning entity. `initial_rows` holds the latest row per required table that
## arrived before this component existed; each is replayed as an insert so a subclass sees one
## code path whether it was present from the start or spawned late. `history` holds EVERY row per
## table, in arrival order (DECISIONS #180): where a table has it, all of them are replayed, so a
## collection (catches, stacks) arrives whole. All of it lands before `is_bound()` turns true:
## a component that announces news checks that, and nothing that was already true is news.
func bind(p_entity: Node, initial_rows: Dictionary[StringName, RefCounted],
		history: Dictionary[StringName, Array] = {}) -> void:
	assert(not _bound, "component bound twice; use rebind() on reconnect")
	entity = p_entity
	entity_id = p_entity.entity_id
	is_local_authority = p_entity.is_local_authority
	for table: StringName in required_tables():
		var rows: Array = history.get(table, [])
		if rows.is_empty():
			var row: RefCounted = initial_rows.get(table, null)
			if row != null:
				_on_row_inserted(table, row)
			continue
		for r: Variant in rows:
			_on_row_inserted(table, r as RefCounted)
	_bound = true
	_on_bound()


## Reconnect path: the SDK tears every row down and re-inserts it, so the component is fed a
## fresh initial set without being destroyed. See DECISIONS #17.
func rebind(initial_rows: Dictionary[StringName, RefCounted],
		history: Dictionary[StringName, Array] = {}) -> void:
	_bound = false
	bind(entity, initial_rows, history)


func is_bound() -> bool:
	return _bound


## Dispatch by kind. The entity calls this for every event on a table in `required_tables()`.
func receive_row_event(ev: RowEvent) -> void:
	match ev.kind:
		RowEvent.Kind.INSERTED:
			_on_row_inserted(ev.table, ev.new)
		RowEvent.Kind.UPDATED:
			_on_row_updated(ev.table, ev.old, ev.new)
		RowEvent.Kind.DELETED:
			_on_row_deleted(ev.table, ev.old)


func _on_row_inserted(table: StringName, row: RefCounted) -> void:
	_on_row_updated(table, null, row)


func _on_row_deleted(table: StringName, row: RefCounted) -> void:
	_on_row_updated(table, row, null)


## Hook for subclasses: runs once, after `bind()` has applied the initial rows.
func _on_bound() -> void:
	pass
