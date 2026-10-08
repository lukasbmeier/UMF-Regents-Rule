extends "res://tests/suite_base.gd"
## The `health` suite (tests/test_runner.gd runs it; `-- --only=health` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_health_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


func _run_health_tests() -> void:
	print("== SpaceTimeHealthComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus autoload present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 55
	get_tree().root.add_child(owner_entity)

	var h := SpaceTimeHealthComponent.new()
	get_tree().root.add_child(h)

	var local: Array[String] = []
	h.health_changed.connect(func(c: float, m: float, d: float) -> void:
		local.append("changed %.0f/%.0f d=%.0f" % [c, m, d]))
	h.damaged.connect(func(a: float, s: int) -> void: local.append("damaged %.0f from %d" % [a, s]))
	h.healed.connect(func(a: float) -> void: local.append("healed %.0f" % a))
	h.died.connect(func(k: int) -> void: local.append("died by %d" % k))
	h.revived.connect(func() -> void: local.append("revived"))

	var bus_events: Array[String] = []
	var hcb := func(eid: int, c: float, m: float) -> void:
		bus_events.append("health %d %.0f/%.0f" % [eid, c, m])
	var dcb := func(eid: int, killer: int) -> void: bus_events.append("died %d by %d" % [eid, killer])
	var rcb := func(eid: int) -> void: bus_events.append("revived %d" % eid)
	bus.entity_health_changed.connect(hcb)
	bus.entity_died.connect(dcb)
	bus.entity_revived.connect(rcb)

	# First bind: initial state, not a change.
	var initial: Dictionary[StringName, RefCounted] = {&"health_state": FakeHealthRow.new(55, 100.0, 100.0)}
	h.bind(owner_entity, initial)
	_check(local == ["changed 100/100 d=0"], "first bind reports delta 0 and no damage")
	_check(h.get_current() == 100.0 and h.get_max() == 100.0, "read API reflects the row")
	_check(is_equal_approx(h.get_ratio(), 1.0), "ratio 1.0 at full health")

	# 100 -> 75 is damage of 25, attributed to the source on the row.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 100.0, 100.0), FakeHealthRow.new(55, 75.0, 100.0, false, 9)))
	_check(local == ["changed 75/100 d=-25", "damaged 25 from 9"], "100->75 emits damaged(25, 9)")
	_check(is_equal_approx(h.get_ratio(), 0.75), "ratio tracks current/max")

	# 75 -> 100 is healing, not damage.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 75.0, 100.0), FakeHealthRow.new(55, 100.0, 100.0)))
	_check(local == ["changed 100/100 d=25", "healed 25"], "75->100 emits healed(25)")

	# Death transition.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 100.0, 100.0), FakeHealthRow.new(55, 0.0, 100.0, true, 42)))
	_check(local.has("died by 42"), "is_dead false->true emits died(last_damage_source)")
	_check(h.is_dead(), "is_dead read API")

	# Still dead on a later update: died must not repeat.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 0.0, 100.0, true, 42), FakeHealthRow.new(55, 0.0, 120.0, true, 42)))
	_check(not local.has("died by 42"), "died does not re-fire while still dead")

	# Revival.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"health_state",
		FakeHealthRow.new(55, 0.0, 120.0, true, 42), FakeHealthRow.new(55, 60.0, 120.0, false, 42)))
	_check(local.has("revived"), "is_dead true->false emits revived")
	_check(not h.is_dead(), "is_dead cleared")

	# Bus mirrors, entity_id first.
	_check(bus_events.has("health 55 100/100"), "bus entity_health_changed carries entity_id first")
	_check(bus_events.has("died 55 by 42"), "bus entity_died mirrors")
	_check(bus_events.has("revived 55"), "bus entity_revived mirrors")

	# A vanished row must not be reported as a death.
	local.clear()
	h.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"health_state",
		FakeHealthRow.new(55, 60.0, 120.0), null))
	_check(local.is_empty(), "row delete emits nothing (despawn, not death)")

	bus.entity_health_changed.disconnect(hcb)
	bus.entity_died.disconnect(dcb)
	bus.entity_revived.disconnect(rcb)
	h.queue_free()
	owner_entity.queue_free()
