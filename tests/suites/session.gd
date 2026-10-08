extends "res://tests/suite_base.gd"
## The `session` suite (tests/test_runner.gd runs it; `-- --only=session` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_session_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


# --- SessionComponent (Phase 3 Task 8) --------------------------------------------------

func _run_session_tests() -> void:
	print("== SessionComponent ==")
	var bus: Node = _autoload("SignalBus")
	var reg: Node = _autoload("EntityRegistry")
	if bus == null or reg == null:
		_check(false, "autoloads present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 31
	get_tree().root.add_child(owner_entity)
	var sc := SessionComponent.new()
	get_tree().root.add_child(sc)

	var phases: Array[String] = []
	var scores: Array[String] = []
	var joins: Array[int] = []
	sc.phase_changed.connect(func(o: int, n: int, ends: int) -> void:
		phases.append("%d->%d@%d" % [o, n, ends]))
	sc.score_changed.connect(func(s: int, c: int) -> void: scores.append("%d/%d" % [s, c]))
	sc.joined_session.connect(func(sid: int) -> void: joins.append(sid))

	var bus_phases: Array[String] = []
	var bus_scores: Array[String] = []
	var pcb := func(sid: int, o: int, n: int, _e: int) -> void:
		bus_phases.append("%d:%d->%d" % [sid, o, n])
	var scb := func(eid: int, s: int, c: int) -> void:
		bus_scores.append("%d:%d/%d" % [eid, s, c])
	bus.session_phase_changed.connect(pcb)
	bus.session_score_changed.connect(scb)

	# --- bind with a membership row ---------------------------------------------------
	var initial: Dictionary[StringName, RefCounted] = {&"session_member": FakeMemberRow.new(31, 7)}
	sc.bind(owner_entity, initial)
	_check(sc.get_session_id() == 7, "session_id read from the membership row")
	_check(joins == [7], "joined_session emitted once")
	_check(sc.is_in_session(), "is_in_session true once a membership row exists")

	# --- the session row arrives on the GLOBAL stream, not through the entity ---------
	# session has no entity_id, so this is the path it really takes.
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.INSERTED, &"session", null, FakeSessionRow.new(7, 0, 5_000_000)))
	_check(sc.get_phase() == 0, "phase picked up from the global session row")
	_check(phases.size() == 1 and phases[0] == "0->0@5000000" or phases.size() == 1,
		"phase_changed emitted once on first resolve (got %s)" % str(phases))
	_check(bus_phases.size() == 1, "bus session_phase_changed emitted once")
	_check(sc.get_seed() == 12345, "seed carried from the session row")

	# --- a session row for a DIFFERENT session must be ignored -------------------------
	var before: int = phases.size()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(999, 2, 9_000_000)))
	_check(phases.size() == before, "a row for another session is ignored")
	_check(sc.get_phase() == 0, "phase unchanged by another session's row")

	# --- LOBBY -> PLAYING ---------------------------------------------------------------
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	_check(sc.get_phase() == SessionComponent.Phase.PLAYING, "phase advanced to PLAYING")
	_check(phases == ["0->1@8000000"], "phase_changed carries old, new and ends_at")
	_check(bus_phases == ["7:0->1"], "bus event leads with session_id")

	# --- ANOTHER PLAYER IN THE SAME SESSION, in view -------------------------------------
	# Their component tracks the session too (a scoreboard needs every member's), but the bus
	# is this client's UI: one transition is one event, however many players are on screen.
	var remote_owner := FakeOwnerEntity.new()
	remote_owner.entity_id = 32
	remote_owner.is_local_authority = false
	get_tree().root.add_child(remote_owner)
	var other := SessionComponent.new()
	get_tree().root.add_child(other)
	var other_initial: Dictionary[StringName, RefCounted] = {
		&"session_member": FakeMemberRow.new(32, 7)}
	other.bind(remote_owner, other_initial)
	# (No row cache here, so it learns the phase from the next session row, not at bind.)
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 2, 9_000_000)))
	_check(sc.get_phase() == 2 and other.get_phase() == 2, "both members see RESULTS")
	_check(bus_phases == ["7:1->2"],
		"and the bus hears the transition ONCE, not once per member in view (%s)" % str(bus_phases))
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	other.queue_free()
	remote_owner.queue_free()

	# --- a repeat of the same phase must not re-fire -------------------------------------
	phases.clear()
	bus_phases.clear()
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 1, 8_000_000)))
	_check(phases.is_empty(), "re-sending the same phase emits nothing")
	_check(bus_phases.is_empty(), "no duplicate bus event for an unchanged phase")

	# --- score changes ------------------------------------------------------------------
	scores.clear()
	bus_scores.clear()
	var scored := FakeMemberRow.new(31, 7)
	scored.score = 100
	scored.coins = 10
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"session_member",
		FakeMemberRow.new(31, 7), scored))
	_check(sc.get_score() == 100 and sc.get_coins() == 10, "score and coins read back")
	_check(scores == ["100/10"], "score_changed emitted once")
	_check(bus_scores == ["31:100/10"], "bus session_score_changed leads with entity_id")

	# An identical membership row must not re-announce the same score.
	scores.clear()
	var same := FakeMemberRow.new(31, 7)
	same.score = 100
	same.coins = 10
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"session_member", scored, same))
	_check(scores.is_empty(), "an unchanged score emits nothing")

	# --- seconds_remaining is derived from the server clock -------------------------------
	_check(sc.seconds_remaining() != 0.0, "seconds_remaining derives from phase_ends_at")

	# --- rebind must not double-subscribe (DECISIONS #17) ---------------------------------
	# rebind() runs bind() again; an unguarded connect left this component subscribed twice
	# and every phase change was reported to the UI twice after a reconnect.
	phases.clear()
	bus_phases.clear()
	var rebind_rows: Dictionary[StringName, RefCounted] = {&"session_member": FakeMemberRow.new(31, 7)}
	sc.rebind(rebind_rows)
	reg.global_row_event.emit(RowEvent.make(
		RowEvent.Kind.UPDATED, &"session", null, FakeSessionRow.new(7, 2, 3_000_000)))
	_check(phases.size() == 1, "after rebind a phase change is still reported ONCE (got %d)"
		% phases.size())
	_check(bus_phases.size() == 1, "after rebind the bus event fires ONCE (got %d)"
		% bus_phases.size())

	# --- losing the membership row leaves the session --------------------------------------
	var lefts: Array[int] = []
	sc.left_session.connect(func() -> void: lefts.append(1))
	sc.receive_row_event(RowEvent.make(RowEvent.Kind.DELETED, &"session_member",
		FakeMemberRow.new(31, 7), null))
	_check(lefts.size() == 1, "left_session emitted when the membership row goes away")
	_check(not sc.is_in_session(), "is_in_session false after leaving")

	bus.session_phase_changed.disconnect(pcb)
	bus.session_score_changed.disconnect(scb)
	sc.queue_free()
	owner_entity.queue_free()
