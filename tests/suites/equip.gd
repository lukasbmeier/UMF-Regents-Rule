extends "res://tests/suite_base.gd"
## The `equip` suite (tests/test_runner.gd runs it; `-- --only=equip` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_equip_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## AN ITEM IN HAND OR PUT AWAY (DECISIONS #159): the equip state, on its own clock. Stepped by hand
## here; the real rig and the cast are in the animation-scene and aim suites.
func _run_equip_tests() -> void:
	print("== equip: in hand, or put away ==")
	var e := EquipComponent.new()
	add_child(e)
	e.set_process(false)
	e.draw_sec = 0.4
	e.stow_sec = 0.6
	e.away_after_sec = 1.0
	var log: Array[String] = []
	e.equip_started.connect(func(d: bool) -> void: log.append("start %s" % ("draw" if d else "stow")))
	e.equip_cancelled.connect(func(d: bool) -> void: log.append("back %s" % ("draw" if d else "stow")))
	e.equipped_changed.connect(func(on: bool) -> void: log.append("in hand" if on else "away"))
	_check(e.state() == EquipComponent.State.AWAY and not e.is_equipped(), "it starts put away")
	e.needed()
	_check(e.state() == EquipComponent.State.DRAWING and not e.is_equipped() and log == (["start draw"] as Array[String]),
		"needed, it starts drawing; not in hand yet (%s)" % str(log))
	e._process(0.3)
	_check(not e.is_equipped(), "not in hand 0.3 s into a 0.4 s draw")
	e._process(0.15)
	_check(e.is_equipped() and log.back() == "in hand", "in hand when the draw's time is up")
	for i: int in range(9):
		e._process(0.1)
		if i == 4:
			e.needed()
	_check(e.state() == EquipComponent.State.READY, "used part way, it stays in hand past the idle time from when it was drawn")
	e._process(0.6)
	_check(e.state() == EquipComponent.State.STOWING and log.back() == "start stow",
		"a full second unused, it starts going away (%s)" % str(log))
	e.needed()
	_check(e.is_equipped() and log.back() == "back stow", "needed again while going, it is turned back: in hand at once")
	e.put_away()
	e._process(0.7)
	_check(e.state() == EquipComponent.State.AWAY and log.back() == "away", "put away, it is away when the put-away's time is up")
	e.draw()
	e.put_away()
	_check(e.state() == EquipComponent.State.AWAY and log.back() == "back draw", "a draw turned back half way leaves it away")
	e.away_when_idle = false
	e.set_equipped_now(true)
	e._process(5.0)
	_check(e.is_equipped() and log.back() == "in hand", "carried (not away when idle), it stays in hand however long it is unused")
	e.free()
