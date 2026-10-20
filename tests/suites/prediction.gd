extends "res://tests/suite_base.gd"
## The `prediction` suite (tests/test_runner.gd runs it; `-- --only=prediction` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_prediction_tests()
	_run_push_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


## THE SERVER PUSHES THE PLAYER (DECISIONS #251): the push goes into their next predicted frame, by its
## number, so a correction's replay pushes them again exactly as the first time.
func _run_push_tests() -> void:
	print("== a push from the server ==")
	var m := _make_predicted()
	var still: Array[InputFrame] = _walk_frames(m, 1, 20, Vector2.ZERO)
	var before: MovementState = m.get_predicted_state().duplicate()
	m.push(Vector3(0.0, 8.0, -6.0))
	_check(m.get_predicted_state().vel == before.vel, "a push waits for the next frame (nothing moves between frames)")
	var pushed: Array[InputFrame] = _walk_frames(m, 21, 1, Vector2.ZERO)
	var after: MovementState = m.get_predicted_state()
	_check(after.vel.y > 7.0 and after.vel.z < -5.0 and not after.grounded,
		"the next frame is pushed: up and along, off the ground (vel %s)" % after.vel)
	var flown: Array[InputFrame] = _walk_frames(m, 22, 15, Vector2.ZERO)
	var now: Vector3 = m.get_predicted_state().pos
	_check(now.y > before.pos.y + 1.0 and now.z < before.pos.z - 1.0, "and flies with it (%s from %s)" % [now, before.pos])
	# A correction at seq 20 (a new epoch: the server overrode us there, at the place we predicted):
	# everything since is replayed, the push with it.
	_ack(m, 20, still[19].client_pos, 1)
	var replayed: Vector3 = m.get_predicted_state().pos
	_check(replayed.distance_to(now) < 0.001, "a correction's replay pushes again: the same flight (%.4f m apart)" % replayed.distance_to(now))
	_free_predicted(m)
	_check(pushed.size() == 1 and flown.size() == 15, "setup: the frames were predicted")



## Push `n` frames walking in `dir` (camera-relative move_dir), starting at `from_seq`.
func _walk_frames(m: SpaceTimeMovementComponent, from_seq: int, n: int, dir: Vector2) -> Array[InputFrame]:
	var frames: Array[InputFrame] = []
	for i: int in range(n):
		var f := InputFrame.new()
		f.seq = from_seq + i
		f.move_dir = dir
		m.push_input(f)
		frames.append(f)
	return frames


## The server acknowledges input `lps` with the entity at `pos`, and the tick applies it.
##
## The velocity is the one the module would report — what the client's own motion implied at
## that seq — taken from the prediction history when there is one. A fake row with zero
## velocity made every replay re-accelerate from a standstill and drift 27 cm: the first run of
## this suite "found" that, and it was the fixture lying, not the algorithm.
func _ack(m: SpaceTimeMovementComponent, lps: int, pos: Vector3, epoch: int = 0,
		teleport: bool = false) -> void:
	var r := FakeMoveRow.new(m.entity_id, pos, 2_000_000 + lps * 16_667)
	r.last_processed_seq = lps
	r.correction_epoch = epoch
	r.teleport_flag = teleport
	var h: MovementState = m._history.get(lps, null)
	if h != null and not teleport:
		r.vel = h.vel
	m.receive_row_event(_move_ev(r))
	m.apply_pending_rows()


func _free_predicted(m: SpaceTimeMovementComponent) -> void:
	var e: Node = m.entity
	m.queue_free()
	if e != null:
		e.free()


func _run_prediction_tests() -> void:
	print("== prediction & reconciliation ==")
	var bus: Node = _autoload("SignalBus")
	var forward := Vector2(0.0, -1.0)

	# --- the Phase 3 bug, pinned ------------------------------------------------------
	# Walking, the server's echo is always ~100 ms behind where we are NOW. Phase 3 compared
	# the echo with "now", saw most of a metre of error at a sprint, and snapped on nearly every
	# row — the rubber-banding players reported. The echo must be compared with what we
	# predicted AT THE SEQ IT ACKNOWLEDGES.
	var m := _make_predicted()
	var counts: Array[float] = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	var frames: Array[InputFrame] = _walk_frames(m, 1, 40, forward)
	var at10: Vector3 = frames[9].client_pos
	var now: Vector3 = m.get_predicted_state().pos
	_check(now.distance_to(at10) > 1.0,
		"setup: the prediction is over a metre past seq 10 (%.2f m)" % now.distance_to(at10))
	_ack(m, 10, at10)
	_check(counts.is_empty(), "an echo that matches what we predicted AT ITS SEQ is not a correction, however far behind 'now' it is")
	_check(m.get_predicted_state().pos == now, "and the prediction is left exactly where it was")

	# --- (a) matching rows: zero reconciles, pending drains -----------------------------
	_check(m.pending_count() == 30, "acknowledging seq 10 of 40 leaves 30 pending (got %d)" % m.pending_count())
	_ack(m, 25, frames[24].client_pos)
	_ack(m, 40, frames[39].client_pos)
	_check(counts.is_empty() and m.pending_count() == 0, "exact acks: no corrections, nothing left pending")
	_check(frames[39].client_pos == m.get_predicted_state().pos,
		"the Tier A claim sent with a frame is exactly the predicted position for it")
	_check(frames[20].epoch == 0, "frames carry the epoch they were predicted under")
	_free_predicted(m)

	# --- (b) small error: one smooth correction, replayed, glided ------------------------
	m = _make_predicted()
	counts = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	frames = _walk_frames(m, 1, 30, forward)
	var before: Vector3 = m.get_predicted_state().pos
	_ack(m, 20, frames[19].client_pos + Vector3(0.1, 0.0, 0.0))
	_check(counts.size() == 1 and absf(counts[0] - 0.1) < 1e-4, "a 10 cm disagreement is one correction of 10 cm (%s)" % str(counts))
	var shift: Vector3 = m.get_predicted_state().pos - before
	_check(shift.is_equal_approx(Vector3(0.1, 0.0, 0.0)),
		"the correction is replayed: the present moves by the error, not back to the old seq (%s)" % shift)
	_check(m.get_visual_offset().is_equal_approx(Vector3(-0.1, 0.0, 0.0)),
		"the VISUAL stays where it was drawn and glides from there (%s)" % m.get_visual_offset())
	_check(m.get_reconcile_stats()["snaps"] == 0, "10 cm glides, it does not snap")
	for i: int in range(ceili(m.config.reconcile_smooth_time * 60.0)):
		m._decay_visual_offset(1.0 / 60.0)
	_check(m.get_visual_offset().length() < 0.001,
		"the glide completes within reconcile_smooth_time (%.5f m left)" % m.get_visual_offset().length())
	_free_predicted(m)

	# --- (b2) a correction keeps the dash's cooldown (DECISIONS #264) ----------------------
	# Reported from play: roll, Ctrl again at once, and the body dashed though the roll was cooling down.
	# The rewind took the server's row, which has no cooldown, so the next press dashed.
	m = _make_predicted()
	m.config.dash_impulse = 16.0
	m.config.dash_cooldown_ticks = 90
	var dash_frames: Array[InputFrame] = _walk_frames(m, 1, 5, forward)
	var press := InputFrame.new()
	press.seq = 6
	press.move_dir = forward
	press.dash = true
	m.push_input(press)
	dash_frames = _walk_frames(m, 7, 20, forward)
	_check(m.get_predicted_state().dash_cooldown > 0, "setup: a dash, cooling down (%d ticks left)" % m.get_predicted_state().dash_cooldown)
	_ack(m, 15, m._history[15].pos + Vector3(0.1, 0.0, 0.0))
	_check(m.get_reconcile_stats()["reconciles"] == 1 and m.get_predicted_state().dash_cooldown > 0,
		"a correction after it keeps the cooldown (%d ticks left)" % m.get_predicted_state().dash_cooldown)
	var again := InputFrame.new()
	again.seq = 27
	again.move_dir = forward
	again.dash = true
	m.push_input(again)
	_check(m.get_predicted_state().dash_left == 0, "so Ctrl again inside it does not dash")
	_free_predicted(m)

	# --- (c) large error: snap ---------------------------------------------------------
	m = _make_predicted()
	frames = _walk_frames(m, 1, 30, forward)
	_ack(m, 20, frames[19].client_pos + Vector3(2.0, 0.0, 0.0))
	_check(m.get_reconcile_stats()["snaps"] == 1, "a 2 m disagreement snaps")
	_check(m.get_visual_offset() == Vector3.ZERO, "a snap leaves no glide behind")
	_check(m.pending_count() == 0, "a snap discards the inputs it can no longer trust")
	_free_predicted(m)

	# --- (d) a failed batch is forgotten ------------------------------------------------
	m = _make_predicted()
	_walk_frames(m, 1, 10, forward)
	m.on_input_batch_failed(5, 7)
	_check(m.pending_count() == 7, "seqs 5-7 of a failed batch are dropped from pending (%d left)" % m.pending_count())
	_check(not m._history.has(5) and not m._history.has(7) and m._history.has(8),
		"and from history, so nothing is ever compared against them")
	_free_predicted(m)

	# --- (e) determinism ----------------------------------------------------------------
	var a := _make_predicted(56)
	var b := _make_predicted(57)
	_walk_frames(a, 1, 30, Vector2(0.6, -0.8))
	_walk_frames(b, 1, 30, Vector2(0.6, -0.8))
	var off := Vector3(0.05, 0.0, -0.03)
	_ack(a, 12, a._history[12].pos + off)
	_ack(b, 12, b._history[12].pos + off)
	_check(a.get_predicted_state().pos == b.get_predicted_state().pos,
		"replaying the same pending inputs from the same server state is bit-identical")
	_free_predicted(a)
	_free_predicted(b)

	# --- (f) an OVERRIDE (new epoch, no teleport): replay, glide, and it settles -------
	m = _make_predicted()
	counts = []
	m.reconciled.connect(func(e: float) -> void: counts.append(e))
	frames = _walk_frames(m, 1, 20, forward)
	var pred_before: Vector3 = m.get_predicted_state().pos
	_ack(m, 10, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_check(counts.size() == 1 and absf(counts[0] - 0.4) < 1e-3,
		"an override is one correction the size of the server's change (%s)" % str(counts))
	_check(m.get_epoch() == 1, "we adopt the server's new correction epoch")
	_check((m.get_predicted_state().pos - pred_before).is_equal_approx(Vector3(0.4, 0.0, 0.0)),
		"our unacknowledged inputs are REPLAYED from the corrected state, so the correction costs no movement")
	var next: Array[InputFrame] = _walk_frames(m, 21, 5, forward)
	_check(next[0].epoch == 1, "frames predicted after the override carry the new epoch")
	# The server consumed seqs 11..20 (old epoch) without moving: those rows must not be read as errors.
	_ack(m, 18, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_ack(m, 20, frames[9].client_pos + Vector3(0.4, 0.0, 0.0), 1)
	_check(counts.size() == 1, "rows acknowledging old-epoch frames are not corrections (%d)" % counts.size())
	_ack(m, 25, next[4].client_pos, 1)
	_check(counts.size() == 1, "the first new-epoch ack matches exactly: ONE correction settled it")
	_free_predicted(m)

	# --- (g) a TELEPORT override: snap, announce, drop the old inputs -------------------
	m = _make_predicted()
	var tps: Array[int] = []
	var tcb := func(eid: int) -> void: tps.append(eid)
	bus.entity_teleported.connect(tcb)
	_walk_frames(m, 1, 20, forward)
	_ack(m, 10, Vector3(50.0, 0.0, 50.0), 1, true)
	_check(m.get_predicted_state().pos == Vector3(50.0, 0.0, 50.0), "a teleport puts us exactly at the target")
	_check(m.get_reconcile_stats()["snaps"] == 1 and m.get_visual_offset() == Vector3.ZERO,
		"a teleport snaps; it never glides across the map")
	_check(tps == [55], "the teleport is announced once on the bus (%s)" % str(tps))
	_check(m.pending_count() == 0, "inputs from the old place are not replayed at the new one")
	bus.entity_teleported.disconnect(tcb)
	_free_predicted(m)

	# --- (h) the LOCAL entity's events come from the prediction, at once -----------------
	# Detected from rows, a jump sound played a round trip after the jump: 200 ms at 200 ms.
	m = _make_predicted()
	var evs: Array[String] = []
	m.event_predicted.connect(func(k: StringName, id: int) -> void: evs.append("%s@%d" % [k, id]))
	var jump_count: Array[int] = [0]
	m.jumped.connect(func() -> void: jump_count[0] += 1)
	_walk_frames(m, 1, 5, Vector2.ZERO)
	var jf := InputFrame.new()
	jf.seq = 6
	jf.jump = true
	m.push_input(jf)
	_check(evs == ["jumped@6"] and jump_count[0] == 1,
		"a jump is announced on the very frame it is predicted, identified by its seq (%s)" % str(evs))
	_check(jf.move_state == MovementState.Move.AIR, "and the frame reports AIR to the server")
	var sq: int = 7
	while not m.get_predicted_state().grounded and sq < 300:
		var idle := InputFrame.new()
		idle.seq = sq
		m.push_input(idle)
		sq += 1
	_check(evs.size() == 2 and evs[1].begins_with("landed@"), "the landing is announced when the prediction lands (%s)" % str(evs))
	_ack(m, sq - 1, m._history[sq - 1].pos)
	_check(jump_count[0] == 1 and evs.size() == 2, "acknowledging rows do not fire the events a second time")
	_free_predicted(m)

	# --- (i) a TELEPORT revokes what was predicted on the old path ------------------------
	m = _make_predicted()
	var revoked: Array[String] = []
	m.event_revoked.connect(func(k: StringName, id: int) -> void: revoked.append("%s@%d" % [k, id]))
	_walk_frames(m, 1, 3, Vector2.ZERO)
	var j2 := InputFrame.new()
	j2.seq = 4
	j2.jump = true
	m.push_input(j2)
	_walk_frames(m, 5, 6, Vector2.ZERO)
	_ack(m, 2, Vector3(20.0, 0.0, 20.0), 1, true)
	_check(revoked == ["jumped@4"], "a teleport revokes the jump predicted after the seq it acknowledges (%s)" % str(revoked))
	_free_predicted(m)

	# --- (j) a correction whose replay no longer jumps revokes the jump -------------------
	# The server puts us 2 m up at seq 3. Replaying from there, the jump at seq 6 is pressed in
	# mid-air, so it never happens: revoke it rather than leave an animation mid-jump.
	m = _make_predicted()
	revoked = []
	m.event_revoked.connect(func(k: StringName, id: int) -> void: revoked.append("%s@%d" % [k, id]))
	_walk_frames(m, 1, 5, Vector2.ZERO)
	var j3 := InputFrame.new()
	j3.seq = 6
	j3.jump = true
	m.push_input(j3)
	_walk_frames(m, 7, 6, Vector2.ZERO)
	var up := FakeMoveRow.new(m.entity_id, Vector3(0.0, 2.0, 0.0), 3_000_000)
	up.last_processed_seq = 3
	up.correction_epoch = 1
	up.grounded = false
	m.receive_row_event(_move_ev(up))
	m.apply_pending_rows()
	_check(revoked == ["jumped@6"], "a correction whose replay has no jump revokes the predicted one (%s)" % str(revoked))
	_check(not m.get_predicted_state().grounded, "and the replayed present is airborne, falling from the corrected height")
	_free_predicted(m)

	# --- (k) move_state through push_input ------------------------------------------------
	m = _make_predicted()
	var states: Array[int] = []
	m.move_state_changed.connect(func(_o: int, n: int) -> void: states.append(n))
	_walk_frames(m, 1, 3, Vector2.ZERO)
	var walk_f: Array[InputFrame] = _walk_frames(m, 4, 10, forward)
	var sprint_f := InputFrame.new()
	sprint_f.seq = 14
	sprint_f.move_dir = forward
	sprint_f.sprint = true
	m.push_input(sprint_f)
	# A plain key press RUNS; WALK is the slow modifier now (DECISIONS #100).
	_check(walk_f[-1].move_state == MovementState.Move.RUN and sprint_f.move_state == MovementState.Move.SPRINT,
		"frames report RUN then SPRINT to the server")
	_check(states == [MovementState.Move.RUN, MovementState.Move.SPRINT],
		"move_state_changed fires from the prediction, once per change (%s)" % str(states))
	_free_predicted(m)
