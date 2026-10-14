extends "res://tests/suite_base.gd"
## The `action` suite (tests/test_runner.gd runs it; `-- --only=action` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_action_tests()
	_run_lunge_tests()
	_run_key_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


class FakeLungeDef extends RefCounted:
	var ability_id: int = 3
	var wind_up_ms: int = 450
	var data: String = ""


## A LUNGE (DECISIONS #232): an ability whose content `lunges` throws its user's body forward by its
## movement profile's dash as the wind-up ends: the client presses dash for one frame, and a character
## that lunges so does not dash by its key.
func _run_lunge_tests() -> void:
	print("== action: a lunge (DECISIONS #232) ==")
	var row := FakeLungeDef.new()
	row.data = JSON.stringify({"name": "Pounce", "judged": true, "lunges": true})
	_check(SpaceTimeActionComponent.lunge_wind_up_ms(row) == 450, "an ability whose row says it lunges: its user lunges 450 ms in (its wind-up)")
	row.data = JSON.stringify({"name": "Swipe", "judged": true})
	_check(SpaceTimeActionComponent.lunge_wind_up_ms(row) == -1 and SpaceTimeActionComponent.lunge_wind_up_ms(null) == -1,
		"one that does not (or no row): no lunge")
	var pounce := AbilityDef.new()
	pounce.lunges = true
	_check(bool(pounce.to_bake().get("lunges", false)), "the bake says it lunges (the server puts it in the row's data)")
	var defn := EntityDefinition.new()
	_check(not LocalInputComponent.lunges_by_ability(defn) and not LocalInputComponent.lunges_by_ability(null), "a character with no lunging ability dashes by its key")
	defn.abilities = [pounce]
	_check(LocalInputComponent.lunges_by_ability(defn), "one with one dashes only by it")
	var c: LocalInputComponent = _make_input_component(true)
	if not InputMap.has_action(&"dash"):
		InputMap.add_action(&"dash")
	c.dash_key = false
	Input.action_press(&"dash")
	var held: InputFrame = c.sample()
	c.dash_once()
	var lunge: InputFrame = c.sample()
	var after: InputFrame = c.sample()
	_check(not held.dash, "its dash key held: no dash (it lunges only by its ability)")
	_check(lunge.dash and not after.dash, "the lunge: dash pressed on one frame, and only one")
	c.dash_key = true
	_check(c.sample().dash, "a character that dashes by its key: the key dashes")
	Input.action_release(&"dash")
	c.queue_free()
	# The model: one dash press on a profile with a dash throws the body forward.
	var cfg := MovementConfig.new()
	cfg.dash_impulse = 4.5
	var s := MovementState.new()
	s.grounded = true
	var f := InputFrame.new()
	f.look_yaw = 0.0
	f.dash = true
	var thrown: MovementState = MovementModel.simulate(s, f, cfg, 1.0 / 60.0, Callable())
	_check(thrown.vel.z < -4.0, "a dash press: the body is thrown forward (%.2f m/s along its facing)" % -thrown.vel.z)



# --- SpaceTimeActionComponent (PHASE3_SPEC Task 12, PHASE4_SPEC §3) --------------------

class FakeAbilityDef extends RefCounted:
	var ability_id: int
	var cooldown_ms: int = 800
	var wind_up_ms: int = 150
	var range: float = 2.0
	var damage: float = 10.0
	func _init(id: int) -> void:
		ability_id = id

class FakeActionEvent extends RefCounted:
	var id: int
	var world_id: int = 0
	var actor_id: int
	var ability_id: int
	var target_id: int = 0
	var aim: Vector3 = Vector3.ZERO
	var outcome: int = 1
	var predicted_id: int = 0
	var server_ts: int = 0
	func _init(p_id: int, p_actor: int, p_ability: int, p_pid: int) -> void:
		id = p_id
		actor_id = p_actor
		ability_id = p_ability
		predicted_id = p_pid

class FakeAbilityState extends RefCounted:
	var id: int = 1
	var entity_id: int
	var ability_id: int
	var cooldown_until: int
	var charges: int = 0
	func _init(eid: int, ab: int, until: int) -> void:
		entity_id = eid
		ability_id = ab
		cooldown_until = until


## An action component on a fake local entity, with the clock, the catalogue and the reducer
## call all under the test's control. Abilities 0-9 exist; anything else does not.
func _make_action(now_ref: Array, requests: Array[ReducerRequest], local: bool = true) -> SpaceTimeActionComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 70
	owner_entity.is_local_authority = local
	get_tree().root.add_child(owner_entity)
	var a := SpaceTimeActionComponent.new()
	a._clock_override = func() -> int: return int(now_ref[0])
	a._def_override = func(id: int) -> RefCounted: return FakeAbilityDef.new(id) if id < 10 else null
	a._reducer_override = func(_ab: int, _tg: int, _aim: Vector3, _pid: int) -> ReducerRequest:
		var r := ReducerRequest.new()
		r.reducer_name = &"use_ability"
		requests.append(r)
		return r
	get_tree().root.add_child(a)
	var empty: Dictionary[StringName, RefCounted] = {}
	a.bind(owner_entity, empty)
	return a


func _action_ev(row: FakeActionEvent) -> RowEvent:
	return RowEvent.make(RowEvent.Kind.INSERTED, &"action_event", null, row)


func _run_action_tests() -> void:
	print("== SpaceTimeActionComponent ==")
	var reg: Node = _autoload("EntityRegistry")
	var bus: Node = _autoload("SignalBus")
	var now: Array = [1_000_000]
	var reqs: Array[ReducerRequest] = []
	var a: SpaceTimeActionComponent = _make_action(now, reqs)
	var log: Array[String] = []
	a.action_started.connect(func(ab: int, pid: int) -> void: log.append("start %d#%d" % [ab, pid]))
	a.action_resolved.connect(func(ab: int, pid: int, o: int, t: int) -> void: log.append("resolved %d#%d o%d t%d" % [ab, pid, o, t]))
	a.action_revoked.connect(func(ab: int, pid: int, why: String) -> void: log.append("revoked %d#%d %s" % [ab, pid, why]))
	a.action_observed.connect(func(act: int, ab: int, t: int, o: int) -> void: log.append("observed a%d %d t%d o%d" % [act, ab, t, o]))
	a.ability_ready.connect(func(ab: int) -> void: log.append("ready %d" % ab))
	var bus_log: Array[String] = []
	var bcb := func(act: int, ab: int, t: int, o: int) -> void: bus_log.append("%d %d %d %d" % [act, ab, t, o])
	bus.entity_action.connect(bcb)

	# (a) predicted start: announced at once, cooldown running, nothing announced twice.
	var pid: int = a.request_use(0, 9)
	_check(pid == 1 and log == ["start 0#1"], "an action starts THE MOMENT it is requested, with a predicted id (%s)" % str(log))
	_check(reqs.size() == 1 and a.is_on_cooldown(0), "the request is sent and the cooldown starts locally")
	_check(a.request_use(0, 9) == -1 and reqs.size() == 1,
		"a second use inside the cooldown is refused locally: nothing sent, nothing announced")
	_check(a.request_use(50) == -1 and reqs.size() == 1, "an unknown ability is refused locally")

	# (b) the server's event carries the predicted id back: resolved, exactly once.
	var hit := FakeActionEvent.new(500, 70, 0, 1)
	hit.target_id = 9
	hit.outcome = SpaceTimeActionComponent.Outcome.HIT
	reg.global_row_event.emit(_action_ev(hit))
	reg.global_row_event.emit(_action_ev(hit))   # a cache replay on reconnect
	_check(log.slice(1) == ["resolved 0#1 o0 t9"], "the matching action_event resolves it, once (%s)" % str(log))
	_check(bus_log == ["70 0 9 0"], "and the actor's component announces it on the bus, once (%s)" % str(bus_log))
	_check(a.pending_count() == 0, "nothing left waiting")

	# (c) a refusal from the server revokes it and hands the cooldown back.
	now[0] += 900_000
	a.tick()
	log.clear()
	var pid2: int = a.request_use(0, 9)
	reqs[1]._settle(ReducerRequest.Outcome.REJECTED, "use_ability: out of range")
	_check(log == ["start 0#%d" % pid2, "revoked 0#%d use_ability: out of range" % pid2],
		"a server refusal revokes the predicted action, with the server's reason (%s)" % str(log))
	_check(not a.is_on_cooldown(0), "and the cooldown is handed back: the use never happened")

	# (d) no answer at all: revoked once the wind-up plus the timeout has passed.
	log.clear()
	var pid3: int = a.request_use(1)
	now[0] += (150 + 1000) * 1000 - 1
	a.tick()
	# (Cooldowns legitimately end during this wait — ability 1's 800 ms, and ability 0's, handed
	# back by the revoke above — so ability_ready entries are expected here; look past them.)
	var not_ready := func(entries: Array[String]) -> Array[String]:
		var out: Array[String] = []
		for e: String in entries:
			if not e.begins_with("ready "):
				out.append(e)
		return out
	_check(not_ready.call(log) == ["start 1#%d" % pid3], "still waiting just inside the deadline (%s)" % str(log))
	now[0] += 2
	a.tick()
	var rest: Array[String] = not_ready.call(log)
	_check(rest.size() == 2 and rest[1].begins_with("revoked 1#%d" % pid3), "revoked when nothing arrives in time (%s)" % str(log))
	_check(log.has("ready 1") and log.has("ready 0"), "the cooldowns that ran out during the wait each announced ready")

	# (e) someone else's action that hits THIS entity: observed, and not announced by us.
	log.clear()
	bus_log.clear()
	var incoming := FakeActionEvent.new(501, 99, 0, 7)
	incoming.target_id = 70
	incoming.outcome = SpaceTimeActionComponent.Outcome.HIT
	reg.global_row_event.emit(_action_ev(incoming))
	_check(log == ["observed a99 0 t70 o0"], "a hit on this entity is reported for a hit reaction (%s)" % str(log))
	_check(bus_log.is_empty(), "the bus announcement is the ACTOR's component's job, not the target's")
	reg.global_row_event.emit(_action_ev(FakeActionEvent.new(502, 98, 0, 3)))
	_check(log.size() == 1, "an action involving neither actor nor target here is ignored")

	# (f) the server's cooldown is authoritative; (g) ability_ready fires once when it ends.
	log.clear()
	var until: int = ClockSync.server_usec() + 2_000_000
	a.receive_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"ability_state", null, FakeAbilityState.new(70, 3, until)))
	_check(a.is_on_cooldown(3) and absf(a.cooldown_remaining_sec(3) - 2.0) < 0.05,
		"an ability_state row sets the cooldown from the server's clock (%.3f s)" % a.cooldown_remaining_sec(3))
	now[0] += 2_100_000
	a.tick()
	a.tick()
	_check(log.count("ready 3") == 1, "ability_ready fires once when a cooldown runs out (%s)" % str(log))
	bus.entity_action.disconnect(bcb)
	a.entity.queue_free()
	a.queue_free()

	# (h) a REMOTE entity's own actions are observed, never "resolved": its client predicted them,
	# this one did not.
	var rreqs: Array[ReducerRequest] = []
	var remote: SpaceTimeActionComponent = _make_action(now, rreqs, false)
	var rlog: Array[String] = []
	remote.action_resolved.connect(func(_ab: int, _p: int, _o: int, _t: int) -> void: rlog.append("resolved"))
	remote.action_observed.connect(func(_act: int, _ab: int, _t: int, _o: int) -> void: rlog.append("observed"))
	reg.global_row_event.emit(_action_ev(FakeActionEvent.new(600, 70, 0, 1)))
	_check(rlog == ["observed"], "a remote player's action is observed (for its animation), not resolved (%s)" % str(rlog))
	remote.entity.queue_free()
	remote.queue_free()


## AN ABILITY ON ITS OWN KEY (DECISIONS #237): the wolf's Howl on the right mouse button; its Pounce on
## the attack key still (its first, keyed nothing).
func _run_key_tests() -> void:
	print("== action: abilities on their own keys ==")
	if not InputMap.has_action(&"power"):
		InputMap.add_action(&"power")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event(&"power", rmb)
	var pounce := AbilityDef.new()
	pounce.id = 7101
	var howl := AbilityDef.new()
	howl.id = 7102
	howl.key = &"power"
	var defn := EntityDefinition.new()
	defn.abilities = [pounce, howl]
	var ent := SpaceTimeEntity.new()
	ent.definition = defn
	var c := LocalInputComponent.new()
	c.entity = ent
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	_check(c.keyed_ability(press) == howl, "the right mouse button: the ability keyed to `power` (the Howl)")
	var other := InputEventKey.new()
	other.physical_keycode = KEY_K
	other.pressed = true
	_check(c.keyed_ability(other) == null, "a key nothing is on: none (the first ability is the attack key's, not a key's)")
	press.pressed = false
	_check(c.keyed_ability(press) == null, "let go: none")
	InputMap.action_erase_event(&"power", rmb)
	c.free()
	ent.free()
