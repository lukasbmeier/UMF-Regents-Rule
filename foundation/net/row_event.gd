class_name RowEvent extends RefCounted
## Normalised cache event. SpaceTimeSync converts SDK signals into these; nothing downstream
## sees SDK types. `old` / `new` are the generated row objects (opaque to the foundation,
## typed by the component that consumes them).

enum Kind { INSERTED, UPDATED, DELETED }

var kind: Kind
var table: StringName
## -1 when the row is not entity-scoped (e.g. world_config, session, item_def).
var entity_id: int = -1
var old: RefCounted = null
var new: RefCounted = null
## Local receive time, for latency diagnostics.
var received_usec: int = 0

static func make(p_kind: Kind, p_table: StringName, p_old: RefCounted, p_new: RefCounted) -> RowEvent:
	var ev := RowEvent.new()
	ev.kind = p_kind
	ev.table = p_table
	ev.old = p_old
	ev.new = p_new
	ev.received_usec = Time.get_ticks_usec()
	ev.entity_id = _extract_entity_id(p_new if p_new != null else p_old)
	return ev

## Which entity a row belongs to, in lookup order:
##   `entity_id`        — the row IS that entity's state (movement_state, health_state)
##   `owner_entity_id`  — the row is OWNED BY that entity (inventory_item, and genre tables
##                        like a `catch`: the row is not the entity, it belongs to it)
## Anything with neither is a world row (world_config, session, item_def) and goes to
## `EntityRegistry.global_row_event` instead.
##
## The fallback is not cosmetic: without it `inventory_item` scored -1 and every inventory
## row bypassed the entity that owns it, so the component never saw one.
## `Object.get()` returns null for a property that does not exist, which is the probe.
static func _extract_entity_id(row: RefCounted) -> int:
	if row == null:
		return -1
	var v: Variant = row.get(&"entity_id")
	if v != null:
		return int(v)
	v = row.get(&"owner_entity_id")
	return int(v) if v != null else -1

## The row that represents current state (new for insert/update, old for delete).
func current() -> RefCounted:
	return old if kind == Kind.DELETED else new

func _to_string() -> String:
	return "RowEvent(%s %s eid=%d)" % [Kind.keys()[kind], table, entity_id]
