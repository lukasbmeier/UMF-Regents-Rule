extends "res://tests/suite_base.gd"
## AIM, CHARGE AND THE FLIGHT CAM (FOUNDATION_SYSTEMS milestone 14, DECISIONS #248, #249), no server:
##   - `ChargeMeter`: fills in its time, holds at the top or bounces, overcharged past its mark, let go
##     or put down
##   - the mouse's up and down lent to a genre (`borrow_mouse_y`): the view holds its pitch, turns still
##   - `AimCharge`: a style charged, the body facing the aim, the release angle from the mouse, thrown
##     with its power and aim; another style or a cancel puts it down
##   - `CameraRig.watch`: behind what it watches along where it goes, looking at it; back to the
##     player's own view, gliding
##   - `FlightCam`: follows a throw's own flight, comes back when it is gone; off with the setting
##   - `ChargeBar`: where it draws, shown only while charging


func run() -> void:
	_run_meter()
	_run_borrow()
	_run_charge()
	await _run_watch()
	await _run_flight_cam()
	_run_bar()


func _run_meter() -> void:
	print("== aim: the charge meter ==")
	var m := ChargeMeter.new(1.0, 0.95)
	m.begin()
	m.step(0.5)
	_check(is_equal_approx(m.value, 0.5) and not m.is_over(), "half its time held: half full")
	m.step(0.47)
	_check(m.is_over(), "past its mark (0.95): overcharged")
	m.step(5.0)
	_check(is_equal_approx(m.value, 1.0), "held on: it stays full (HOLD)")
	var r: Dictionary = m.release()
	_check(is_equal_approx(float(r["power"]), 1.0) and bool(r["over"]) and not m.held, "let go: full power, overcharged, no longer held")
	m.step(1.0)
	_check(is_equal_approx(m.value, 1.0), "let go, it no longer fills")
	var b := ChargeMeter.new(1.0, 0.95, ChargeMeter.Over.BOUNCE)
	b.begin()
	b.step(1.25)
	_check(is_equal_approx(b.value, 0.75), "a bouncing meter past the top comes back down (0.75)")
	b.step(1.0)
	_check(is_equal_approx(b.value, 0.25), "and goes back up from the bottom (0.25)")
	b.cancel()
	_check(b.value == 0.0 and not b.held, "put down: empty")


func _motion(dy: float, dx: float = 0.0) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, dy)
	return e


func _run_borrow() -> void:
	print("== aim: the mouse's up and down, lent ==")
	var c: LocalInputComponent = _make_input_component(true)
	c.capture_mouse = false
	var p0: float = c.get_look_pitch()
	c.borrow_mouse_y(&"test", true)
	c._unhandled_input(_motion(-100.0, 50.0))
	_check(is_equal_approx(c.get_look_pitch(), p0), "lent, moving the mouse up does not tilt the view")
	_check(not is_equal_approx(c.get_look_yaw(), 0.0), "side to side still turns it")
	var y: float = c.take_borrowed_y()
	_check(y > 0.0, "and the borrower is given the up (%.3f rad)" % y)
	_check(c.take_borrowed_y() == 0.0, "once")
	c.borrow_mouse_y(&"test", false)
	c._unhandled_input(_motion(-100.0))
	_check(c.get_look_pitch() > p0, "given back, it tilts the view again")
	c.queue_free()


func _run_charge() -> void:
	print("== aim: aim and charge ==")
	var c: LocalInputComponent = _make_input_component(true)
	c.capture_mouse = false
	var ac := AimCharge.new()
	ac.actions = [&"test_backhand", &"test_forehand"]
	ac.charge_s = 1.0
	get_tree().root.add_child(ac)
	ac.use_input(c)
	var got: Array = []
	ac.released.connect(func(s: int, power: float, over: bool, aim: Vector3, angle: float) -> void: got.append([s, power, over, aim, angle]))
	var put_down: Array[int] = []
	ac.cancelled.connect(func(s: int) -> void: put_down.append(s))
	ac.press(1)
	_check(ac.is_charging() and ac.style == 1 and c.is_facing_held(), "a forehand charging: the body faces the aim")
	c._unhandled_input(_motion(-120.0))
	ac._process(0.6)
	_check(ac.angle > 0.0 and is_equal_approx(ac.meter.value, 0.6), "up with the mouse: a release angle (%.2f), the meter at 0.6" % ac.angle)
	ac.release()
	_check(got.size() == 1 and int(got[0][0]) == 1 and is_equal_approx(float(got[0][1]), 0.6) and not bool(got[0][2]) and float(got[0][4]) > 0.0,
		"let go: thrown, style 1, 0.6 of its power, not overcharged, at its angle")
	_check((got[0][3] as Vector3).is_normalized(), "along where the view looks")
	_check(not ac.is_charging() and not c.is_facing_held(), "and the body and the mouse are the player's again")
	ac.press(0)
	ac.press(1)
	_check(put_down == [0] and ac.style == 1, "another style while one charges: the first is put down")
	ac.cancel()
	_check(put_down == [0, 1] and got.size() == 1, "a cancel: put down, nothing thrown")
	ac.enabled = false
	ac.press(0)
	_check(not ac.is_charging(), "off: nothing starts")
	ac.queue_free()
	c.queue_free()


func _run_watch() -> void:
	print("== aim: the camera watches something else ==")
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	rig.add_child(cam)
	get_tree().root.add_child(rig)
	var target := Node3D.new()
	get_tree().root.add_child(target)
	target.global_position = Vector3(0, 1, 0)
	var cfg := FollowCamConfig.new()
	cfg.distance = 4.0
	cfg.height = 1.5
	cfg.follow_rate = 1000.0   # no trail, to measure where it sits
	cfg.return_s = 0.5
	rig.watch(target, cfg)
	_check(rig.watching() == target, "it watches what it was given")
	for i: int in 10:
		target.global_position += Vector3(0.5, 0, 0)   # 30 m/s along x
		rig._apply(1.0 / 60.0)
	var behind: Vector3 = target.global_position - Vector3(4.0, -1.5, 0.0)
	_check(cam.global_position.distance_to(behind) < 0.2, "behind it along where it goes, above it (%s, wanted %s)" % [cam.global_position, behind])
	var look: Vector3 = -cam.global_basis.z
	_check(look.dot((target.global_position - cam.global_position).normalized()) > 0.99, "looking at it")
	rig.stop_watching()
	_check(rig.watching() == null and rig.returning(), "stopped: gliding back")
	var from: Vector3 = cam.global_position
	rig._apply(0.25)
	var mid: Vector3 = cam.global_position
	rig._apply(0.3)
	_check(not rig.returning(), "back in its return time")
	_check(mid.distance_to(from) > 0.1 and mid.distance_to(cam.global_position) > 0.1, "on its way, between where it was and the player's view")
	rig.watch(target, cfg)
	target.free()
	rig._apply(1.0 / 60.0)
	_check(rig.watching() == null, "what it watched went: it comes back on its own")
	rig.queue_free()
	await get_tree().process_frame


func _run_flight_cam() -> void:
	print("== aim: the flight cam ==")
	var rig := CameraRig.new()
	rig.add_child(Camera3D.new())
	get_tree().root.add_child(rig)
	var fc := FlightCam.new()
	fc.obey_setting = false
	get_tree().root.add_child(fc)
	fc.use_rig(rig)
	var flight := Node3D.new()
	get_tree().root.add_child(flight)
	_check(fc.follow_throw(4242, flight) and rig.watching() == flight and fc.is_following(), "a throw: the camera follows its own flight at once")
	fc._process(0.1)
	_check(rig.watching() == flight, "while its body has not arrived")
	flight.free()
	fc._process(0.1)
	_check(not fc.is_following() and rig.watching() == null, "the flight gone with no body to follow: back to the player")
	fc.obey_setting = true
	var was: Variant = Settings.get_value(&"flight_cam")
	Settings.set_value(&"flight_cam", false)
	var other := Node3D.new()
	get_tree().root.add_child(other)
	_check(not fc.follow_throw(4243, other) and rig.watching() == null, "the player turned it off: it stays with them")
	Settings.set_value(&"flight_cam", was)
	other.free()
	fc.queue_free()
	rig.queue_free()
	await get_tree().process_frame


func _run_bar() -> void:
	print("== aim: the charge bar ==")
	var ac := AimCharge.new()
	get_tree().root.add_child(ac)
	var bar := ChargeBar.new()
	bar.source = ac
	get_tree().root.add_child(bar)
	bar._process(0.0)
	_check(not bar.visible, "not charging: not shown")
	ac.press(0)
	bar._process(0.0)
	_check(bar.visible, "charging: shown")
	var r: Rect2 = bar.bar_rect()
	var vp: Vector2 = bar.get_viewport_rect().size
	_check(is_equal_approx(r.size.x, bar.size_px.x) and is_equal_approx(r.position.x + r.size.x * 0.5, vp.x * 0.5), "a bar of its size, centred on the screen (%s in %s)" % [r, vp])
	ac.cancel()
	bar.queue_free()
	ac.queue_free()
