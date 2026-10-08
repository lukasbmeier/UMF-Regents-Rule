extends "res://tests/suite_base.gd"
## The `input` suite (tests/test_runner.gd runs it; `-- --only=input` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_input_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


func _run_input_tests() -> void:
	print("== LocalInputComponent ==")

	# The component is useless without its actions; assert the project actually defines them
	# rather than silently sampling zeros forever.
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right",
			&"jump", &"sprint", &"interact"]:
		_check(InputMap.has_action(a), "input action '%s' is defined in project.godot" % a)

	var c: LocalInputComponent = _make_input_component(true)
	var frames: Array[InputFrame] = []
	c.input_sampled.connect(func(f: InputFrame) -> void: frames.append(f))
	_release_all_actions()

	# --- seq is monotonic ------------------------------------------------------------
	var f1: InputFrame = c.sample()
	var f2: InputFrame = c.sample()
	var f3: InputFrame = c.sample()
	_check(f1.seq == 1 and f2.seq == 2 and f3.seq == 3,
		"seq increments monotonically from 1 (got %d,%d,%d)" % [f1.seq, f2.seq, f3.seq])
	_check(f1.client_tick == 0 and f3.client_tick == 2, "client_tick advances with seq")
	_check(frames.size() == 3, "input_sampled emitted once per sample")
	_check(c.last_seq() == 3, "last_seq reports the newest frame")
	# A RESTARTED client (DECISIONS #149): its entity's row says the server has taken inputs up to
	# 570 already, from the run before. It carries on from there instead of counting from 1 into
	# the server's drop — and a server behind it (the normal case) changes nothing.
	var back: LocalInputComponent = _make_input_component(true)
	var row_held := SpaceTimeMovementComponent.new()
	row_held._last_processed_seq = 570
	back._movement = row_held
	var resumed: InputFrame = back.sample()
	row_held._last_processed_seq = 12
	var next: InputFrame = back.sample()
	_check(resumed.seq == 571 and back.first_seq() == 571 and next.seq == 572,
		"a restarted client carries on from the count its entity's row holds (%d, then %d)" % [resumed.seq, next.seq])
	back._movement = null
	row_held.free()
	back.queue_free()

	# --- idle input is exactly zero ---------------------------------------------------
	_check(f1.move_dir == Vector2.ZERO, "no keys held yields a zero move_dir")
	_check(not f1.jump and not f1.sprint, "no keys held yields no jump/sprint")

	# --- a single direction -----------------------------------------------------------
	Input.action_press(&"move_forward")
	var fwd: InputFrame = c.sample()
	_check(fwd.move_dir.is_equal_approx(Vector2(0, -1)),
		"forward is -Y in move_dir (got %s)" % fwd.move_dir)
	_check(is_equal_approx(fwd.move_dir.length(), 1.0), "single direction has magnitude 1")

	# --- diagonals are normalised, not 1.41x faster ------------------------------------
	Input.action_press(&"move_right")
	var diag: InputFrame = c.sample()
	_check(is_equal_approx(diag.move_dir.length(), 1.0),
		"diagonal input is normalised to magnitude 1 (got %f)" % diag.move_dir.length())
	_check(diag.move_dir.is_equal_approx(Vector2(1, -1).normalized()),
		"diagonal points between the two axes")

	# --- opposing keys cancel -----------------------------------------------------------
	Input.action_press(&"move_left")
	var cancel: InputFrame = c.sample()
	_check(is_equal_approx(cancel.move_dir.x, 0.0), "left+right cancel on the X axis")
	_release_all_actions()

	# --- buttons ------------------------------------------------------------------------
	Input.action_press(&"jump")
	Input.action_press(&"sprint")
	var btn: InputFrame = c.sample()
	_check(btn.jump and btn.sprint, "jump and sprint are sampled")
	_release_all_actions()
	var released: InputFrame = c.sample()
	_check(not released.jump and not released.sprint, "buttons clear when released")

	# --- movement is relative to where the body is being told to face ----------------------
	# Look 90 degrees; "forward" must now point along world -X.
	c.set_look(PI / 2.0, 0.0)
	Input.action_press(&"move_forward")
	var turned: InputFrame = c.sample()
	_check(turned.move_dir.is_equal_approx(Vector2(-1, 0)),
		"move_dir follows the look direction: forward at 90 deg points -X (got %s)"
			% turned.move_dir)

	# FREE LOOK. The camera keeps turning; the body does not, so a held direction keeps going
	# where the character is pointed instead of curving after the camera.
	_check(InputMap.has_action(LocalInputComponent.ACTION_FREELOOK),
		"the project defines a free-look action")
	Input.action_press(LocalInputComponent.ACTION_FREELOOK)
	var swing := InputEventMouseMotion.new()
	swing.relative = Vector2(300.0, 0.0)
	MouseCapture.want_capture(true)
	c._unhandled_input(swing)
	var held: InputFrame = c.sample()
	_check(absf(c.get_look_yaw() - PI / 2.0) > 0.5,
		"the camera turned (%.2f rad)" % c.get_look_yaw())
	_check(absf(held.look_yaw - PI / 2.0) < 1e-5 and held.move_dir.is_equal_approx(Vector2(-1, 0)),
		"but the body's heading and the movement direction did not (%s, %s)"
			% [held.look_yaw, held.move_dir])
	Input.action_release(LocalInputComponent.ACTION_FREELOOK)
	var after_free: InputFrame = c.sample()
	_check(absf(after_free.look_yaw - c.get_look_yaw()) < 1e-5,
		"and letting go hands the body the camera's heading, without a jump in between")
	MouseCapture.want_capture(false)
	c.set_look(0.0, 0.0)
	_release_all_actions()

	# --- look angles ---------------------------------------------------------------------
	c.set_look(1.0, 0.5)
	var looked: InputFrame = c.sample()
	_check(is_equal_approx(looked.look_yaw, 1.0) and is_equal_approx(looked.look_pitch, 0.5),
		"look angles are carried on the frame")
	c.set_look(0.0, 99.0)
	_check(c.get_look_pitch() < deg_to_rad(90.0),
		"pitch is clamped below vertical (got %f rad)" % c.get_look_pitch())

	# --- facing follows the camera only while moving ----------------------------------------
	# Standing still and looking around must not spin the body. The module applies the same rule
	# to the same frame (DECISIONS #100); a client that applied a different one would show every
	# other player facing somewhere they are not.
	var yaw_m: SpaceTimeMovementComponent = _make_predicted(91)
	var yaw_seq: Array[int] = [0]
	var still := InputFrame.new()
	yaw_seq[0] += 1
	still.seq = yaw_seq[0]
	still.look_yaw = 1.2
	yaw_m.push_input(still)
	_check(absf(yaw_m.get_predicted_state().yaw) < 1e-6,
		"looking around while standing still does not turn the body (%.3f rad)"
			% yaw_m.get_predicted_state().yaw)
	var going := InputFrame.new()
	yaw_seq[0] += 1
	going.seq = yaw_seq[0]
	going.look_yaw = 1.2
	going.move_dir = Vector2(0.0, -1.0)
	yaw_m.push_input(going)
	_check(absf(yaw_m.get_predicted_state().yaw - 1.2) < 1e-6,
		"and moving turns it to face the camera (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	# AIMING turns it standing still (#136): a cast thrown behind you is thrown by someone facing
	# that way. Same rule, same frame, in module.rs.
	var aimed := InputFrame.new()
	yaw_seq[0] += 1
	aimed.seq = yaw_seq[0]
	aimed.look_yaw = -2.5
	aimed.face = true
	yaw_m.push_input(aimed)
	_check(absf(yaw_m.get_predicted_state().yaw + 2.5) < 1e-6,
		"a frame that is aiming turns the body standing still (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	var after := InputFrame.new()
	yaw_seq[0] += 1
	after.seq = yaw_seq[0]
	after.look_yaw = 0.4
	yaw_m.push_input(after)
	_check(absf(yaw_m.get_predicted_state().yaw + 2.5) < 1e-6,
		"and once it stops aiming, the heading it aimed on stays (%.3f rad)" % yaw_m.get_predicted_state().yaw)
	yaw_m.entity.queue_free()
	yaw_m.queue_free()

	# --- hold_facing: who asks, and what goes on the wire ----------------------------------
	c.set_look(0.0, 0.0)
	_check(not c.sample().face, "nobody aiming: the frame does not ask to face")
	c.hold_facing(&"bow", true)
	c.hold_facing(&"cast", true)
	c.set_look(1.9, 0.0)
	var aiming_frame: InputFrame = c.sample()
	_check(aiming_frame.face and absf(aiming_frame.look_yaw - 1.9) < 1e-6,
		"while something aims, the frame asks to face the camera (face=%s, yaw %.2f)" % [aiming_frame.face, aiming_frame.look_yaw])
	c.hold_facing(&"cast", false)
	_check(c.sample().face, "one reason letting go does not cancel another's")
	c.hold_facing(&"bow", false)
	_check(not c.sample().face and not c.is_facing_held(), "and the last one letting go ends it")
	c.set_look(0.0, 0.0)

	# --- mouse look only while the cursor is ours -------------------------------------------
	# Without this gate the view swings whenever the pointer moves — across a menu, or on its
	# way out of the window. That is the other half of "the mouse is not captured": not only
	# did the cursor escape the window, it went on steering the camera from outside it.
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 0.0)
	c.set_look(0.0, 0.0)
	MouseCapture.want_capture(false)
	c._unhandled_input(motion)
	_check(is_equal_approx(c.get_look_yaw(), 0.0),
		"a free cursor does not steer the camera (yaw %f)" % c.get_look_yaw())
	MouseCapture.want_capture(true)
	c._unhandled_input(motion)
	_check(absf(c.get_look_yaw() + 100.0 * c.mouse_sensitivity) < 1e-5,
		"a captured one does, by relative x sensitivity (yaw %f)" % c.get_look_yaw())
	MouseCapture.want_capture(false)
	c.set_look(0.0, 0.0)

	# --- client_pos comes from the body ---------------------------------------------------
	c.entity.position = Vector3(3.0, 1.0, -2.0)
	var posed: InputFrame = c.sample()
	_check(posed.client_pos.is_equal_approx(Vector3(3.0, 1.0, -2.0)),
		"client_pos is the body position (got %s)" % posed.client_pos)

	# --- wire order matches the Rust struct -----------------------------------------------
	# to_reducer_args feeds BSATN positionally; a field out of order silently corrupts input.
	var args: Array = posed.to_reducer_args()
	_check(args.size() == 14, "to_reducer_args has 14 fields (got %d)" % args.size())
	_check(args[12] is bool and args[13] is bool,
		"the slow-walk modifier and then the aim close the frame, matching sim.rs")
	_check(args[9] is int and args[10] is int and args[11] is bool,
		"epoch, move_state, dash close the frame, matching sim.rs")
	_check(args[0] == posed.seq and args[1] == posed.client_tick,
		"args start with seq, client_tick")
	_check(args[4] == posed.look_yaw and args[5] == posed.look_pitch,
		"look_yaw precedes look_pitch, matching sim.rs")
	_check(args[8] is Vector3, "client_pos is the ninth arg and a Vector3")

	c.entity.queue_free()
	c.queue_free()

	# --- a REMOTE entity must not sample ---------------------------------------------------
	var remote: LocalInputComponent = _make_input_component(false)
	_check(not remote.is_physics_processing(),
		"a remote entity's input component does not run physics processing")
	remote.entity.queue_free()
	remote.queue_free()
