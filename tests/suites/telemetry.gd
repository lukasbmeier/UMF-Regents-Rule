extends "res://tests/suite_base.gd"
## The `telemetry` suite (`-- --only=telemetry`). HOW A GAME RAN, AND WHAT A PLAYER SAID (DECISIONS #244):
## a window's frame times summed up (median, 95th, 99th, worst), its spikes (slow frames, and the rows
## stopping after flowing: a network stall), the report small and nothing personal in it; the window
## starting again after it is sent; the feedback page marking the moment as it is asked for, holding the
## player still while they write, and sending what the server's `send_feedback` takes. The server's side:
## tests/integration_test.sh (who may report, the rate, what the server adds); a real client's reports
## and a real referee's: tests/e2e_test.sh, Fowl Play's host playtest.


func run() -> void:
	_run_window()
	await _run_frozen_frame()
	_run_stalls()
	await _run_feedback_page()


## The engine hands `_process` a `delta` of at most ~8 physics ticks (133 ms at 60 Hz) however long the frame
## was: a frozen main thread must still be reported as long as it froze, by the clock.
func _run_frozen_frame() -> void:
	print("== telemetry: a frozen frame, by the clock ==")
	var t := Telemetry.new()
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	t.set(&"_frames", PackedFloat32Array())
	t.set(&"_spikes", [])
	t.set(&"_spike_count", 0)
	OS.delay_msec(600)   # this frame: 600 ms on the main thread
	await get_tree().process_frame
	var engine_ms: float = get_process_delta_time() * 1000.0
	await get_tree().process_frame
	var s: Dictionary = t.summary()
	_check(float(s["max"]) >= 600.0 and int(s["spikes"]) >= 1 and String((s["spike_list"] as Array)[0][2]) == "frame",
		"a 600 ms frame is reported as %.0f ms, a slow frame (the engine's delta: %.0f ms)" % [float(s["max"]), engine_ms])
	_check(is_equal_approx(Telemetry.frame_ms(0.016, 0), 16.0) and is_equal_approx(Telemetry.frame_ms(0.124, 616000), 616.0)
		and is_equal_approx(Telemetry.frame_ms(0.020, 5000), 20.0),
		"a frame's time: the delta, or the clock when that is longer, never shorter than the delta")
	t.queue_free()


func _run_window() -> void:
	print("== telemetry: a window of frames ==")
	var t := Telemetry.new()
	add_child(t)
	t.set_process(false)
	t.set(&"_frames", PackedFloat32Array())
	for i: int in 99:
		t.note_frame(10.0)   # 10 ms frames
	t.note_frame(120.0)   # one 120 ms hitch
	var s: Dictionary = t.summary()
	_check(int(s["frames"]) == 100 and is_equal_approx(float(s["p50"]), 10.0) and is_equal_approx(float(s["max"]), 120.0),
		"a hundred frames, one of them a hitch: median 10 ms, worst 120 (%s)" % str([s["p50"], s["max"]]))
	_check(is_equal_approx(float(s["p99"]), 10.0) and int(s["spikes"]) == 1 and String((s["spike_list"] as Array)[0][2]) == "frame",
		"the 99th still 10 ms (one in a hundred), and the hitch a spike of its own: when, how long, a slow frame")
	for i: int in 40:
		t.note_frame(200.0)
	s = t.summary()
	_check(int(s["spikes"]) == 41 and (s["spike_list"] as Array).size() == Telemetry.MAX_SPIKES,
		"every spike counted (%d), a dozen described: a report stays small" % int(s["spikes"]))
	var platform: String = Telemetry.platform()
	_check(platform.contains(OS.get_name()) and platform.contains("GB") and not platform.contains(OS.get_environment("USERNAME")) \
		and not platform.contains(OS.get_environment("COMPUTERNAME")),
		"the machine, coarsely, nothing personal (no user or computer name): \"%s\"" % platform)
	var detail: String = JSON.stringify({"spikes": s["spike_list"], "screen": "1920x1080", "physics_hz": 60, "max_fps": 0})
	_check(detail.length() + platform.length() + 200 < 1024, "a whole report is well under a kilobyte (%d bytes of text)" % (detail.length() + platform.length()))
	t.send_window()   # not connected: nothing sent, the window starts again
	s = t.summary()
	_check(int(s["frames"]) == 0 and int(s["spikes"]) == 0 and t.sent == 0 and int((t.moment()["before"] as Dictionary)["frames"]) == 140,
		"a window ended: the next starts empty, the last kept for feedback (not sent: no server here)")
	t.queue_free()


func _run_stalls() -> void:
	print("== telemetry: the rows stopping ==")
	var t := Telemetry.new()
	add_child(t)
	t.set_process(false)
	var now: int = Time.get_ticks_msec()
	# Rows flowing 50 ms apart, then a 900 ms gap.
	t.set(&"_last_row_msec", now - 950)
	t.set(&"_row_gap_msec", 50)
	t.call(&"_on_row", null)
	var s: Dictionary = t.summary()
	_check(int(s["spikes"]) == 1 and String((s["spike_list"] as Array)[0][2]) == "net" and float((s["spike_list"] as Array)[0][1]) >= 900.0,
		"rows flowing, then none for 950 ms: a network stall, with how long")
	# Quiet rows (a lobby where nothing moves): a long gap after a long gap is no stall.
	t.set(&"_last_row_msec", Time.get_ticks_msec() - 2000)
	t.set(&"_row_gap_msec", 3000)
	t.call(&"_on_row", null)
	_check(int(t.summary()["spikes"]) == 1, "but rows that were never flowing (nothing moving) are no stall")
	t.queue_free()


func _run_feedback_page() -> void:
	print("== telemetry: the feedback page ==")
	FeedbackPage.ensure_action()
	var f8: bool = false
	for e: InputEvent in InputMap.action_get_events(FeedbackPage.ACTION):
		f8 = f8 or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F8)
	_check(f8, "F8 is feedback in every game")
	var spawner: Node = _autoload("EntitySpawner")
	var reg: Node = _autoload("EntityRegistry")
	var prev_local: int = reg.local_entity_id
	var me := SpaceTimeEntity.new()
	var d := EntityDefinition.new()
	d.kind = 0
	me.definition = d
	get_tree().root.add_child(me)
	var input: LocalInputComponent = _make_input_component(true)
	me.add_runtime_component(input)
	reg.register(7801, me)
	reg.local_entity_id = 7801
	var page := FeedbackPage.new()
	get_tree().root.add_child(page)
	var before: int = ClockSync.server_usec()
	page.mark()
	var marked: int = page.marked_usec()
	var after: int = ClockSync.server_usec()
	await get_tree().create_timer(0.3).timeout
	page.open()
	_check(marked >= before and marked <= after and page.marked_usec() == marked,
		"the moment is marked as the key is pressed, and opening the page (writing) does not move it")
	_check(page.context().has("perf") and page.context().has("look"), "with how the game ran then, and where they looked")
	_check(input.is_held_still(), "while they write, they are held still (the keys do not walk them)")
	page.set_message(FeedbackPage.CATEGORIES.find("Lag"), "  a hitch as I jumped  ")
	var req: ReducerRequest = page.send()
	_check(req != null and req.reducer_name == &"send_feedback" and int(req.args[0]) == page.marked_usec() and int(req.args[1]) == 1
		and String(req.args[2]) == "a hitch as I jumped" and String(req.args[5]).contains("perf"),
		"sent: send_feedback(the moment, Lag, their words, the build, the machine, the context)")
	page.close()
	_check(not input.is_held_still(), "closed: they move again")
	page.set_message(0, "   ")
	_check(page.send() == null, "nothing written: nothing sent")
	page.queue_free()
	reg.unregister(7801)
	reg.local_entity_id = prev_local
	me.queue_free()
