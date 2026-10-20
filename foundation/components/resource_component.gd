class_name ResourceComponent extends SpaceTimeComponent
## AN ENTITY'S POOLS, MIRRORED (DECISIONS #270): mana, stamina; whatever `resource_state` rows the server
## gives it. Each holds what it had after its last spend and when; what it holds NOW is worked out here
## by the server's own rule (`ResourceDef.level`, by the server's clock), so a bar fills smoothly with no
## row a second. Cache-only: the server spends (a genre's reducer), never this.

signal changed(resource_id: int)

const TABLE: StringName = &"resource_state"

## resource id -> {"stored": float, "at_usec": int}
var _pools: Dictionary[int, Dictionary] = {}


func required_tables() -> Array[StringName]:
	return [TABLE]


## An entity has no pools until its game gives it one.
func optional_tables() -> Array[StringName]:
	return [TABLE]


## Whether it has pool `resource_id`.
func has_pool(resource_id: int) -> bool:
	return _pools.has(resource_id)


## What pool `resource_id` holds now (0 when it has none).
func level(resource_id: int) -> float:
	var p: Dictionary = _pools.get(resource_id, {})
	var def: ResourceDef = ResourceDef.by_id(resource_id)
	if p.is_empty() or def == null:
		return 0.0
	return def.level_after(float(p["stored"]), float(ClockSync.server_usec() - int(p["at_usec"])) / 1_000_000.0)


## The most pool `resource_id` holds.
func max_of(resource_id: int) -> float:
	var def: ResourceDef = ResourceDef.by_id(resource_id)
	return def.max_amount if def != null else 0.0


## Whether pool `resource_id` holds `amount` now (what the server will check).
func can_pay(resource_id: int, amount: float) -> bool:
	return level(resource_id) + 1e-4 >= amount


func _on_bound() -> void:
	var tbl: Object = SpaceTimeSync.get_table(TABLE)
	if tbl == null or not tbl.has_method(&"find_by_entity_id"):
		return   # no SDK (unit tests): rows still arrive by event
	var rows: Variant = tbl.call(&"find_by_entity_id", entity_id)
	if rows is Array:
		for row: RefCounted in rows:
			_apply(row)


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	if new == null:
		if old != null:
			_pools.erase(int(old.get(&"resource_id")))
			changed.emit(int(old.get(&"resource_id")))
		return
	_apply(new)


func _apply(row: RefCounted) -> void:
	var id: int = int(row.get(&"resource_id"))
	_pools[id] = {"stored": float(row.get(&"stored")), "at_usec": int(row.get(&"at"))}
	changed.emit(id)
