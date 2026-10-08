extends "res://tests/suite_base.gd"
## The `interaction` suite (tests/test_runner.gd runs it; `-- --only=interaction` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_interaction_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- InteractionComponent (Phase 3 Task 10) ---------------------------------------------

func _run_interaction_tests() -> void:
	print("== InteractionComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus present")
		return

	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 61
	owner_entity.is_local_authority = true
	get_tree().root.add_child(owner_entity)
	var ic := InteractionComponent.new()
	get_tree().root.add_child(ic)
	var empty: Dictionary[StringName, RefCounted] = {}
	ic.bind(owner_entity, empty)

	var local_targets: Array[int] = []
	ic.target_changed.connect(func(id: int) -> void: local_targets.append(id))
	var bus_targets: Array[int] = []
	var tcb := func(id: int) -> void: bus_targets.append(id)
	bus.interact_target_changed.connect(tcb)

	_check(ic.get_target() == InteractionComponent.NO_TARGET, "starts with no target")
	_check(not ic.has_target(), "has_target false initially")
	_check(ic.request_interact() == null, "request_interact with no target does nothing")

	# --- the signal fires on CHANGE, not per frame -------------------------------------
	# A crosshair held on one thing for 600 frames must announce once, or the prompt UI
	# rebuilds every frame.
	ic._set_target(77)
	ic._set_target(77)
	ic._set_target(77)
	_check(local_targets == [77], "holding a target announces once (got %s)" % str(local_targets))
	_check(bus_targets == [77], "bus mirrors once")
	_check(ic.has_target() and ic.get_target() == 77, "target readable")

	ic._set_target(88)
	_check(local_targets == [77, 88], "switching targets announces the new one")
	ic._set_target(InteractionComponent.NO_TARGET)
	_check(local_targets == [77, 88, -1], "looking away announces -1 so the prompt clears")
	ic._set_target(InteractionComponent.NO_TARGET)
	_check(local_targets.size() == 3, "looking at nothing twice announces once")

	# --- what counts as a target --------------------------------------------------------
	_check(ic._target_id_of(null) == InteractionComponent.NO_TARGET, "nothing hit is no target")
	var plain := Node3D.new()
	get_tree().root.add_child(plain)
	_check(ic._target_id_of(plain) == InteractionComponent.NO_TARGET,
		"an ordinary node is not interactable")

	# A prop standing in for an entity: in the group AND carrying the meta.
	var prop := StaticBody3D.new()
	prop.add_to_group(InteractionComponent.GROUP_INTERACTABLE)
	prop.set_meta(&"entity_id", 404)
	get_tree().root.add_child(prop)
	_check(ic._target_id_of(prop) == 404, "an interactable prop resolves to its entity_id meta")

	# In the group but no meta: not a target, rather than a crash or a bogus id.
	var half := StaticBody3D.new()
	half.add_to_group(InteractionComponent.GROUP_INTERACTABLE)
	get_tree().root.add_child(half)
	_check(ic._target_id_of(half) == InteractionComponent.NO_TARGET,
		"group membership without the meta is not a target")

	# --- a remote entity does not scan ----------------------------------------------------
	var remote_owner := FakeOwnerEntity.new()
	remote_owner.entity_id = 62
	remote_owner.is_local_authority = false
	get_tree().root.add_child(remote_owner)
	var remote_ic := InteractionComponent.new()
	get_tree().root.add_child(remote_ic)
	remote_ic.bind(remote_owner, empty)
	_check(not remote_ic.is_physics_processing(), "a remote entity does not raycast")

	# --- the client range must not exceed the server's -------------------------------------
	# A larger client range prompts for things the server will refuse, which reads as a bug.
	_check(is_equal_approx(ic.range_m(), Rules.interact_range()) and Rules.interact_range() > 0.0,
		"left unset, the prompt reaches exactly as far as the server's check, from shared/rules.json (%s m)"
			% ic.range_m())
	ic.interaction_range = 1.5
	_check(is_equal_approx(ic.range_m(), 1.5), "and a component given its own range uses that")
	ic.interaction_range = 0.0

	bus.interact_target_changed.disconnect(tcb)
	plain.queue_free()
	prop.queue_free()
	half.queue_free()
	remote_ic.queue_free()
	remote_owner.queue_free()
	ic.queue_free()
	owner_entity.queue_free()
