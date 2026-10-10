extends Node
## TIMED PRESS PLAYTEST (DECISIONS #210): a real client, through the latency simulator, plays a
## server-timed press the way a player does. It uses the resource node beside it (`interact`), and the
## server issues a timed press. For each of the three presses it watches its OWN bar (the marker drawn
## from the server's clock) and presses the interact key the frame the marker reaches the target's
## centre. What the server judges is the proof:
##   --expect=credited    (the rule's credit for the trip on): judged where the player saw it, so
##                        three presses on the centre score well (mean quality at least 0.7), and the
##                        bar needed next to no calibration
##   --expect=uncredited  (`foundation.press_credit_cap_ms` 0, set by tests/press_playtest.sh): the
##                        first press judged on arrival, a one-way trip late, clearly worse; the bar
##                        then calibrates by about that from the judgement (DECISIONS #213) and the
##                        next presses are judged well again
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 60.0

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _expect: String = "credited"
## The resource node beside the spawn (`--node=`): the template has no character for one, so it is
## not drawn, but it is used as any is.
var _node: int = -1


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--expect="):
			_expect = arg.substr("--expect=".length())
		elif arg.begins_with("--node="):
			_node = int(arg.substr("--node=".length()))
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	await get_tree().create_timer(2.0).timeout   # the clock settles
	_check(_node >= 0, "a resource node to use (%d, placed by the script)" % _node)
	var node: int = _node
	var tp: TimedPressComponent = me.find_component(TimedPressComponent) as TimedPressComponent
	SpaceTimeSync.call_reducer(&"interact", [node, 0], ["u64", "u8"])
	var deadline: int = Time.get_ticks_msec() + 10_000
	while tp.current() < 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var id: int = tp.current()
	_check(id >= 0, "using it starts a timed press")
	if id < 0:
		_finish()
		return
	var judged: Array = []
	tp.judged.connect(func(_c: int, round: int, q: float, pos: float, predicted: float) -> void: judged.append([round, q, pos, predicted]))
	for round: int in 3:
		var centre: float = tp.target(id, round)
		var was: float = tp.marker(id)
		deadline = Time.get_ticks_msec() + 8_000
		# The frame BEFORE the marker, as drawn, reaches the centre (from either side): the key is read
		# a physics frame after it goes down, as a player anticipates the marker by a moment.
		var period: float = float((tp._sweeps[id] as Dictionary)["period_s"])
		var frame_s: float = 1.0 / float(Engine.physics_ticks_per_second)
		while Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
			var now: float = ChallengeModel.sweep_position(tp.elapsed(id) + frame_s, period)
			if tp.elapsed(id) > 0.05 and ((was < centre and now >= centre) or (was > centre and now <= centre)):
				break
			was = now
		Input.action_press(&"interact")
		await get_tree().physics_frame
		Input.action_release(&"interact")
		await get_tree().create_timer(0.25).timeout
	deadline = Time.get_ticks_msec() + 5_000
	while judged.size() < 3 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var mean: float = 0.0
	for j: Array in judged:
		mean += float(j[1]) / 3.0
		print("   press %d: predicted %.2f, judged %.2f (marker %.3f)" % [int(j[0]) + 1, float(j[3]), float(j[1]), float(j[2])])
	print("   MEAN %.3f (%s)" % [mean, _expect])
	_check(judged.size() == 3, "the server judged all three presses (%d)" % judged.size())
	_check(judged.all(func(j: Array) -> bool: return float(j[3]) > 0.7), "each was pressed on the centre as the player saw it (predicted)")
	print("   bar calibrated %+d ms" % roundi(tp.calibration_s * 1000.0))
	judged.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	if _expect == "credited":
		_check(mean >= 0.7, "credited for the trip, the server judges them where they were seen: %.2f" % mean)
		_check(absf(tp.calibration_s) <= 0.04, "and the bar, drawn by the server's clock, needed next to no calibration (%+d ms)" % roundi(tp.calibration_s * 1000.0))
	elif judged.size() == 3:
		# Judged on arrival: the first press, made on the centre as drawn, is judged a one-way trip late;
		# the bar calibrates by about that from the server's judgement (DECISIONS #213), and the presses
		# after it, made on the centre as now drawn, are judged well again.
		_check(float(judged[0][1]) <= 0.5, "judged on arrival, the first press is a one-way trip late: clearly worse (%.2f)" % float(judged[0][1]))
		_check(tp.calibration_s >= 0.05, "the bar calibrates from that judgement by about a one-way trip (%+d ms)" % roundi(tp.calibration_s * 1000.0))
		_check(float(judged[1][1]) >= 0.6 and float(judged[2][1]) >= 0.6,
			"and the presses after it are judged where they were seen again (%.2f, %.2f)" % [float(judged[1][1]), float(judged[2][1])])
	_finish()


func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + 30_000
	while Time.get_ticks_msec() < deadline:
		var id: int = EntityRegistry.local_entity_id
		if id >= 0:
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.is_bound():
				return e
		await get_tree().process_frame
	_check(false, "local player spawned and bound")
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: press playtest exceeded %.0fs" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release(&"interact")
	print("\npress (%s): %d passed, %d failed" % [_expect, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
