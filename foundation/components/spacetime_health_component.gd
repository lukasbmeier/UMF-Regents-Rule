class_name SpaceTimeHealthComponent extends SpaceTimeComponent
## Health, per ARCHITECTURE §7. Fully authoritative: there is no prediction and no client damage
## API at all. The only path that changes health is the server's `apply_damage`, which is
## authority-gated — so this component's entire job is to turn row updates into signals.
##
## It holds a private copy of the last row's values rather than the row itself (hard rule 6: SDK
## rows are the cache's own instances and must never be retained or mutated).

## Entity-local signals, for siblings in this scene (AnimationTree, VFX).
signal health_changed(current: float, max: float, delta: float)
signal damaged(amount: float, source_id: int)
signal healed(amount: float)
signal died(killer_id: int)
signal revived()

const TABLE: StringName = &"health_state"

@export var config: HealthConfig

var _current: float = 0.0
var _max: float = 0.0
var _is_dead: bool = false
var _last_damage_source: int = 0
## False until the first row lands. Distinguishes "no data yet" from "genuinely at 0 health",
## and is what keeps the first update from being reported as damage.
var _has_row: bool = false


func required_tables() -> Array[StringName]:
	return [TABLE]


# --- read API ------------------------------------------------------------------------

func get_current() -> float:
	return _current


func get_max() -> float:
	return _max


func get_ratio() -> float:
	var m: float = _max if _has_row and _max > 0.0 else _assumed_max()
	return 0.0 if m <= 0.0 else clampf(_current / m, 0.0, 1.0)


func is_dead() -> bool:
	return _is_dead


func get_last_damage_source() -> int:
	return _last_damage_source


func has_state() -> bool:
	return _has_row


# --- row handling --------------------------------------------------------------------

func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	if new == null:
		# The row went away (entity despawning, or scope loss). Report nothing: the spawner
		# is about to free this whole subtree and a death signal here would be a lie.
		_has_row = false
		return

	var was_known: bool = _has_row
	var prev_current: float = _current
	var was_dead: bool = _is_dead

	_current = float(new.get(&"current"))
	_max = float(new.get(&"max"))
	_is_dead = bool(new.get(&"is_dead"))
	_last_damage_source = int(new.get(&"last_damage_source"))
	_has_row = true

	# The first row is initial state, not a change: delta 0, and no damaged/healed. Otherwise a
	# client joining mid-fight would fire a damage reaction for every entity already hurt.
	var delta: float = (_current - prev_current) if was_known else 0.0

	health_changed.emit(_current, _max, delta)
	SignalBus.entity_health_changed.emit(entity_id, _current, _max)

	if was_known:
		if delta < 0.0:
			damaged.emit(-delta, _last_damage_source)
		elif delta > 0.0:
			healed.emit(delta)

	if _is_dead and not was_dead:
		died.emit(_last_damage_source)
		SignalBus.entity_died.emit(entity_id, _last_damage_source)
	elif was_dead and not _is_dead:
		revived.emit()
		SignalBus.entity_revived.emit(entity_id)


func _assumed_max() -> float:
	return config.assumed_max if config != null else 100.0
