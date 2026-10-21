extends "res://tests/suite_base.gd"
## The `movement` suite (tests/test_runner.gd runs it; `-- --only=movement` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_movement_tests()
	_run_held_jump()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


## Movement component wired to a fake owner, with a controllable clock.
func _make_movement(now_usec_ref: Array) -> SpaceTimeMovementComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 77
	get_tree().root.add_child(owner_entity)
	var m := SpaceTimeMovementComponent.new()
	m._clock_override = func() -> int: return int(now_usec_ref[0])
	var cfg := MovementConfig.new()
	cfg.remote_interp_delay = 0.1
	m.config = cfg
	m.mode = SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED
	get_tree().root.add_child(m)
	var empty: Dictionary[StringName, RefCounted] = {}
	m.bind(owner_entity, empty)
	return m

func _run_movement_tests() -> void:
	print("== SpaceTimeMovementComponent ==")
	var bus: Node = _autoload("SignalBus")
	if bus == null:
		_check(false, "SignalBus present")
		return

	# Three snapshots 50 ms apart along +X, at server times 1.000s / 1.050s / 1.100s. 1 m per
	# 50 ms is 20 m/s, and the rows SAY so: the module derives velocity from the motion, and
	# interpolation uses it (Hermite). This fixture used to claim zero velocity while moving —
	# no real row can — and the curve through it eased, which is the fixture's fault.
	var now: Array = [0]
	var m: SpaceTimeMovementComponent = _make_movement(now)
	var t0: int = 1_000_000
	for i: int in range(3):
		var r := FakeMoveRow.new(77, Vector3(float(i), 0.0, 0.0), t0 + i * 50_000)
		r.vel = Vector3(20.0, 0.0, 0.0)
		m.receive_row_event(_move_ev(r))
	_check(m.snapshot_count() == 3, "three snapshots buffered")

	# --- exact midpoint between snapshot 0 and 1 ------------------------------------
	# render_t = now - 100ms delay. Want render_t = 1.025s -> now = 1.125s.
	now[0] = t0 + 25_000 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0.5, 0, 0)),
		"midpoint interpolates to the midpoint (got %s)" % m.get_render_state().pos)

	# --- a TURN is drawn without corners (Hermite, DECISIONS #76) -----------------------
	# Five snapshots 100 ms apart (a sparse stretch: a tick that processed no frames leaves a
	# gap like this) on an arc of radius 2 m at 5 m/s, each carrying the tangent velocity the
	# module would report. Straight lines between them change direction
	# only at the samples: a kink per sample. Measure the worst frame-to-frame change in
	# displacement across the whole turn, stepping at 60 Hz.
	var tnow: Array = [0]
	var mt: SpaceTimeMovementComponent = _make_movement(tnow)
	var radius: float = 2.0
	var speed: float = 5.0
	var omega: float = speed / radius
	for i: int in range(5):
		var ang: float = omega * float(i) * 0.1
		var row := FakeMoveRow.new(77, Vector3(radius * sin(ang), 0.0, radius * (1.0 - cos(ang))), t0 + i * 100_000)
		row.vel = Vector3(speed * cos(ang), 0.0, speed * sin(ang))
		mt.receive_row_event(_move_ev(row))
	# Strictly INSIDE the buffered span, using the delay the component is ACTUALLY applying. At
	# the span's first instant the view holds the oldest sample, and measuring from there records
	# "starting to move", not the turn. The first versions of this test assumed a 100 ms delay;
	# the five rows arrive in one frame, the estimator rightly reads that as jitter and adapts to
	# ~118 ms, and the "kink" it reported was the hold ending.
	var delay_us: int = int(mt.get_interp_delay_sec() * 1_000_000.0)
	var drawn: Array[Vector3] = []
	var step_us: int = 16_667
	var ts: int = t0 + delay_us + 5_000
	while ts < t0 + 400_000 + delay_us - 5_000:
		tnow[0] = ts
		mt.update_view()
		drawn.append(mt.get_render_state().pos)
		ts += step_us
	var worst_turn: float = 0.0
	for i: int in range(2, drawn.size()):
		worst_turn = maxf(worst_turn, ((drawn[i] - drawn[i - 1]) - (drawn[i - 1] - drawn[i - 2])).length())
	# The true path changes displacement by v^2/r * dt^2 = 12.5 * 0.000278 = 0.0035 m per frame.
	_check(worst_turn < 0.006,
		"a turn is drawn as a curve, not a polygon: worst change %.4f m/frame (the path itself: 0.0035)" % worst_turn)
	mt.entity.queue_free()
	mt.queue_free()

	# --- a DRY SPELL during a turn rejoins without a lurch -----------------------------
	# The rare live lurch, made deterministic: the walker's rows stop arriving, the view projects
	# it on along +X, and meanwhile it has turned to +Z. When the rows resume, the drawn path must
	# get from "projected the wrong way" back onto the real one without any frame-to-frame change
	# in motion a walker cannot make. 0.05 m/frame is the bound the live playtest asserts.
	#
	# The walker's rows come from the REAL MovementModel, one every 3 frames (50 ms), so the turn
	# is one a player can actually make (40 m/s^2). An earlier version turned 90 degrees in zero
	# time — 140 m/s^2 no walker can produce — and most of what it measured was that.
	var dnow: Array = [0]
	var md: SpaceTimeMovementComponent = _make_movement(dnow)
	var cfg_w := MovementConfig.new()
	var walker := MovementState.new()
	walker.grounded = true
	var rows_before: Array[FakeMoveRow] = []
	var rows_after: Array[FakeMoveRow] = []
	for fr: int in range(1, 25):
		var inp := InputFrame.new()
		inp.move_dir = Vector2(1.0, 0.0) if fr <= 12 else Vector2(0.0, 1.0)   # +X, then turn to +Z
		walker = MovementModel.simulate(walker, inp, cfg_w, 1.0 / 60.0)
		if fr % 3 == 0:
			var row := FakeMoveRow.new(77, walker.pos, t0 + fr * 16_667)
			row.vel = walker.vel
			(rows_before if fr <= 12 else rows_after).append(row)
	for row: FakeMoveRow in rows_before:
		md.receive_row_event(_move_ev(row))
	var d_delay: int = int(md.get_interp_delay_sec() * 1_000_000.0)
	var newest_t: int = rows_before[-1].server_ts
	var dpath: Array[Vector3] = []
	var dts: int = rows_before[1].server_ts + d_delay   # start mid-buffer
	# Run 3 frames past the newest sample: the buffer is dry and the view extrapolates.
	while dts - d_delay <= newest_t + 50_000:
		dnow[0] = dts
		md.update_view()
		dpath.append(md.get_render_state().pos)
		dts += 16_667
	_check(md.get_interp_stats()["dry_events"] >= 1, "setup: the buffer ran dry")
	for row: FakeMoveRow in rows_after:   # the rows resume: the walker has been turning
		md.receive_row_event(_move_ev(row))
	for i: int in range(18):
		dnow[0] = dts
		md.update_view()
		dpath.append(md.get_render_state().pos)
		dts += 16_667
	var worst_rejoin: float = 0.0
	for i: int in range(2, dpath.size()):
		worst_rejoin = maxf(worst_rejoin, ((dpath[i] - dpath[i - 1]) - (dpath[i - 1] - dpath[i - 2])).length())
	_check(worst_rejoin < 0.05,
		"rejoining the real path after a dry spell at a turn is smooth: worst change %.3f m/frame" % worst_rejoin)
	_check(md.get_remote_offset().length() < 0.001, "and the rejoin blend has finished (%.3f m left)" % md.get_remote_offset().length())
	md.entity.queue_free()
	md.queue_free()

	# --- quarter point ---------------------------------------------------------------
	now[0] = t0 + 12_500 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0.25, 0, 0)),
		"quarter point interpolates to 0.25 (got %s)" % m.get_render_state().pos)

	# --- exactly on a snapshot -------------------------------------------------------
	now[0] = t0 + 50_000 + 100_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(1.0, 0, 0)),
		"landing exactly on a snapshot uses that snapshot")

	# --- render time older than the whole buffer: hold the oldest --------------------
	now[0] = t0 - 500_000
	m.update_view()
	_check(m.get_render_state().pos.is_equal_approx(Vector3(0, 0, 0)),
		"render time before the buffer holds the oldest snapshot")

	# --- the body actually moved -----------------------------------------------------
	now[0] = t0 + 25_000 + 100_000
	m.update_view()
	var bdy: CharacterBody3D = m.entity.body
	_check(bdy != null and bdy.position.is_equal_approx(Vector3(0.5, 0, 0)),
		"render state is applied to the body transform")
	m.entity.queue_free()
	m.queue_free()

	# --- extrapolation ---------------------------------------------------------------
	var now2: Array = [0]
	var m2: SpaceTimeMovementComponent = _make_movement(now2)
	var moving := FakeMoveRow.new(77, Vector3(10.0, 0.0, 0.0), t0)
	moving.vel = Vector3(4.0, 0.0, 0.0)
	m2.receive_row_event(_move_ev(moving))

	# 50 ms past the newest snapshot -> 10 + 4*0.05 = 10.2
	now2[0] = t0 + 50_000 + 100_000
	m2.update_view()
	_check(m2.get_render_state().pos.is_equal_approx(Vector3(10.2, 0, 0)),
		"extrapolates with velocity past the newest snapshot (got %s)" % m2.get_render_state().pos)

	# 5 s past -> clamped to 100 ms of extrapolation: 10 + 4*0.1 = 10.4, and no further
	now2[0] = t0 + 5_000_000 + 100_000
	m2.update_view()
	_check(m2.get_render_state().pos.is_equal_approx(Vector3(10.4, 0, 0)),
		"extrapolation is clamped to 100 ms, then holds (got %s)" % m2.get_render_state().pos)
	m2.entity.queue_free()
	m2.queue_free()

	# --- jumped / landed fire exactly once across a grounded flip and back -----------
	var now3: Array = [0]
	var m3: SpaceTimeMovementComponent = _make_movement(now3)
	var jumps: Array[int] = []
	var lands: Array[float] = []
	m3.jumped.connect(func() -> void: jumps.append(1))
	m3.landed.connect(func(speed: float) -> void: lands.append(speed))
	var bus_jumps: Array[int] = []
	var jcb := func(eid: int) -> void: bus_jumps.append(eid)
	bus.entity_jumped.connect(jcb)

	var g0 := FakeMoveRow.new(77, Vector3.ZERO, t0)
	m3.receive_row_event(_move_ev(g0))
	var air := FakeMoveRow.new(77, Vector3(0, 1, 0), t0 + 50_000)
	air.grounded = false
	air.vel = Vector3(0, 8.0, 0)
	m3.receive_row_event(_move_ev(air))
	var falling := FakeMoveRow.new(77, Vector3(0, 2, 0), t0 + 100_000)
	falling.grounded = false
	falling.vel = Vector3(0, -6.0, 0)
	m3.receive_row_event(_move_ev(falling))
	var back := FakeMoveRow.new(77, Vector3.ZERO, t0 + 150_000)
	back.grounded = true
	back.vel = Vector3.ZERO
	m3.receive_row_event(_move_ev(back))

	_check(jumps.size() == 1, "jumped fired exactly once (got %d)" % jumps.size())
	_check(lands.size() == 1, "landed fired exactly once (got %d)" % lands.size())
	_check(lands.size() == 1 and is_equal_approx(lands[0], 6.0),
		"landed reports the pre-touchdown fall speed")
	_check(bus_jumps == [77], "entity_jumped mirrored to the bus with entity_id")
	bus.entity_jumped.disconnect(jcb)

	# Walking off a ledge is not a jump.
	var jumps_before: int = jumps.size()
	var ledge := FakeMoveRow.new(77, Vector3(0, -0.1, 0), t0 + 200_000)
	ledge.grounded = false
	ledge.vel = Vector3(0, -1.0, 0)
	m3.receive_row_event(_move_ev(ledge))
	_check(jumps.size() == jumps_before, "leaving the ground downward is not a jump")
	m3.entity.queue_free()
	m3.queue_free()

	# --- move_state_changed -----------------------------------------------------------
	var now8: Array = [0]
	var m8: SpaceTimeMovementComponent = _make_movement(now8)
	var transitions: Array[String] = []
	m8.move_state_changed.connect(func(o: int, n: int) -> void:
		transitions.append("%d->%d" % [o, n]))
	m8.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3.ZERO, t0)))
	var walking := FakeMoveRow.new(77, Vector3.ZERO, t0 + 50_000)
	walking.move_state = 1
	m8.receive_row_event(_move_ev(walking))
	var walking2 := FakeMoveRow.new(77, Vector3.ZERO, t0 + 100_000)
	walking2.move_state = 1
	m8.receive_row_event(_move_ev(walking2))
	_check(transitions == ["0->1"], "move_state_changed fires once per actual change")
	m8.entity.queue_free()
	m8.queue_free()

	# --- teleport clears the buffer and snaps ----------------------------------------
	var now4: Array = [0]
	var m4: SpaceTimeMovementComponent = _make_movement(now4)
	var teleports: Array[int] = []
	var tcb := func(eid: int) -> void: teleports.append(eid)
	bus.entity_teleported.connect(tcb)
	for i: int in range(3):
		m4.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(float(i), 0, 0), t0 + i * 50_000)))
	var tp := FakeMoveRow.new(77, Vector3(500.0, 0, 0), t0 + 150_000)
	tp.teleport_flag = true
	m4.receive_row_event(_move_ev(tp))
	_check(m4.snapshot_count() == 1, "teleport clears the snapshot buffer")
	# The snap is drawn on the next physics tick (update_view), never between ticks: with
	# physics interpolation on, a transform moved between ticks is rendered as a smear.
	m4.update_view()
	_check(m4.get_render_state().pos.is_equal_approx(Vector3(500, 0, 0)),
		"teleport snaps the render state instead of gliding")
	_check(teleports == [77], "entity_teleported mirrored to the bus")
	bus.entity_teleported.disconnect(tcb)
	m4.entity.queue_free()
	m4.queue_free()

	# --- ordering / dedupe / ring cap -------------------------------------------------
	var now5: Array = [0]
	var m5: SpaceTimeMovementComponent = _make_movement(now5)
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(2, 0, 0), t0 + 100_000)))
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(0, 0, 0), t0)))
	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(1, 0, 0), t0 + 50_000)))
	_check(m5.snapshot_count() == 3, "out-of-order snapshots are all kept")
	now5[0] = t0 + 25_000 + 100_000
	m5.update_view()
	_check(m5.get_render_state().pos.is_equal_approx(Vector3(0.5, 0, 0)),
		"out-of-order snapshots are sorted, so interpolation is still correct")

	m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(9, 9, 9), t0 + 50_000)))
	_check(m5.snapshot_count() == 3, "a repeated timestamp replaces rather than duplicates")

	for i: int in range(60):
		m5.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(float(i), 0, 0),
			t0 + 1_000_000 + i * 50_000)))
	_check(m5.snapshot_count() == SpaceTimeMovementComponent.RING_SIZE,
		"ring is capped at RING_SIZE (got %d)" % m5.snapshot_count())
	m5.entity.queue_free()
	m5.queue_free()

	# --- SERVER_DRIVEN applies the newest row with no smoothing ----------------------
	var now6: Array = [0]
	var m6: SpaceTimeMovementComponent = _make_movement(now6)
	m6.mode = SpaceTimeMovementComponent.Mode.SERVER_DRIVEN
	m6.receive_row_event(_move_ev(FakeMoveRow.new(77, Vector3(3, 0, 0), t0)))
	now6[0] = t0
	m6.update_view()
	_check(m6.get_render_state().pos.is_equal_approx(Vector3(3, 0, 0)),
		"SERVER_DRIVEN renders the authoritative state directly")
	_check(m6.get_authoritative_state().pos.is_equal_approx(Vector3(3, 0, 0)),
		"authoritative read API returns the newest row")
	var acked := FakeMoveRow.new(77, Vector3(3, 0, 0), t0 + 10_000)
	acked.last_processed_seq = 42
	m6.receive_row_event(_move_ev(acked))
	_check(m6.get_last_processed_seq() == 42, "last_processed_seq is read off the row")
	m6.entity.queue_free()
	m6.queue_free()

	# --- empty buffer must not crash --------------------------------------------------
	var now7: Array = [0]
	var m7: SpaceTimeMovementComponent = _make_movement(now7)
	m7.update_view()
	_check(m7.snapshot_count() == 0, "update_view on an empty buffer is a no-op")
	m7.entity.queue_free()
	m7.queue_free()


## A HELD jump hops again only once the body has stopped rising (a playtest, 2026-10-20: "jumping near
## an object makes you double jump"): a resolver that stands the body on an edge for one tick on the
## way up, as move_and_slide does brushing one.
func _run_held_jump() -> void:
	print("== movement: a held jump near an object ==")
	var cfg := MovementConfig.new()
	var dt: float = 1.0 / 60.0
	var edge_at: Array = [3]   # the tick the body brushes the edge
	var tick: Array = [0]
	var brush := func(_prev: MovementState, next: MovementState) -> MovementState:
		var out: MovementState = next.duplicate()
		out.grounded = tick[0] == edge_at[0]
		if out.pos.y <= 0.0 and out.vel.y <= 0.0:
			out.pos.y = 0.0
			out.vel.y = 0.0
			out.grounded = true
		return out
	var s := MovementState.new()
	s.grounded = true
	var held := InputFrame.new()
	held.jump = true
	var top: float = 0.0
	var rises: int = 0
	var was_rising: bool = false
	for i: int in range(40):
		tick[0] = i
		s = MovementModel.simulate(s, held, cfg, dt, brush)
		top = maxf(top, s.pos.y)
		if s.vel.y > 0.0 and not was_rising:
			rises += 1
		was_rising = s.vel.y > 0.0
		if i == edge_at[0]:
			_check(s.vel.y > 0.0 and s.vel.y < cfg.jump_velocity - 0.01, "on the edge, rising: still the first jump (vel %.2f)" % s.vel.y)
	var one_jump: float = cfg.jump_velocity * cfg.jump_velocity / (2.0 * cfg.gravity)
	_check(rises == 1 and top <= one_jump + 0.05, "Space held past an edge on the way up: one jump's height (%.2f m, one is %.2f)" % [top, one_jump])
	# Held through the landing: it hops again (holding Space keeps hopping).
	for i: int in range(60):
		tick[0] = 100 + i
		s = MovementModel.simulate(s, held, cfg, dt, brush)
		if s.vel.y > 0.0 and not was_rising:
			rises += 1
		was_rising = s.vel.y > 0.0
	_check(rises >= 2, "held through the landing: it hops again")
	# A fresh press on the edge does jump: the player asked.
	var s2 := MovementState.new()
	s2.grounded = true
	s2.vel = Vector3(0.0, 2.0, 0.0)
	s2.jump_held = false
	s2 = MovementModel.simulate(s2, held, cfg, dt)
	_check(s2.vel.y > cfg.jump_velocity - 1.0, "a fresh press stood on an edge, even rising: it jumps")
