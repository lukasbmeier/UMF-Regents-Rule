extends Node
## REMOTE SMOOTHNESS PLAYTEST: how one real client draws ANOTHER real client moving.
##
## Two processes, one scene, told apart by `--role=`:
##   walker    walks a square (hold forward, turn 90 degrees every 1.5 s), then teleports
##   observer  finds the walker's entity and records where it DRAWS it every physics frame
##
## The observer asserts what a player watching someone else would notice:
##   visible     the walker is seen to cover ground
##   continuous  no frame-to-frame change in motion bigger than walking can produce: no
##               lurches between packets, no stop-start where the buffer ran dry
##   no stalls   the drawn walker never freezes mid-walk while it is really moving
##   teleport    a teleport is ONE snap, announced with entity_teleported, not a glide across
##   jumps       up a ramp and three jumps on the platform: exactly three `jumped` and no more,
##               none on the ramp (the friends' test saw jump/land restart on every bump)
##   help up     the walker downs itself; the observer walks up, looks at it and HOLDS the interact
##               key (DECISIONS #209): let go early, the help is lost; held, it is back on its feet
##
## Driven by tests/remote_playtest.sh, which runs both at a chosen simulated latency. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 190.0
const STEP_TIMEOUT_SEC: float = 30.0
## Seconds the walker walks, and the length of each side of its square.
const WALK_SEC: float = 9.0
const SIDE_SEC: float = 1.5
## The walker's model accelerates at most 40 m/s^2: 0.011 m change in per-frame displacement.
## Interpolation between 20 Hz snapshots adds a kink at each sample; a stall or lurch between
## packets is several times larger. 0.05 m sits well above the first and well below the second.
const LURCH_EPS: float = 0.05
## The walker's jumps on the platform, after it walks up the ramp.
const JUMPS: int = 3

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "observer"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr("--role=".length())
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	if _role == "walker":
		await _walk(me)
	else:
		await _observe(me)
	_finish()


# --- walker ------------------------------------------------------------------------------

func _walk(me: SpaceTimeEntity) -> void:
	print("== remote playtest: WALKER (entity %d) ==" % me.entity_id)
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	# Start from open floor. Walking into a wall is a genuine instant stop, which the observer
	# rightly draws as a lurch: the first version turned on wall-clock timers from wherever it
	# spawned, drifted, and sometimes walked into the north wall — the netcode was blamed for a
	# collision it drew correctly. The square below (-Z, -X, +Z, +X from here, ~7.5 m a side)
	# stays inside x -8..-0.5, z 0.5..8: clear of every wall, ramp, step and the platform.
	var tp_seen: Array[bool] = [false]
	var tcb := func(eid: int) -> void:
		if eid == me.entity_id:
			tp_seen[0] = true
	SignalBus.entity_teleported.connect(tcb)
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(-0.5, 0.0, 8.0)], ["vector3[f32,f32,f32]"])
	var deadline: int = Time.get_ticks_msec() + 10_000
	while not tp_seen[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	SignalBus.entity_teleported.disconnect(tcb)
	# Give the observer time to connect and settle before there is anything to watch.
	await get_tree().create_timer(4.0).timeout
	# Sides counted in PHYSICS frames, so the route is the same every run.
	var side_frames: int = int(SIDE_SEC * 60.0)
	var yaw: float = 0.0
	input.set_look(yaw, 0.0)
	Input.action_press(&"move_forward")
	for side: int in range(int(WALK_SEC / SIDE_SEC)):
		for f: int in range(side_frames):
			await get_tree().physics_frame
		yaw = wrapf(yaw + PI * 0.5, -PI, PI)
		input.set_look(yaw, 0.0)
	Input.action_release(&"move_forward")
	await get_tree().create_timer(1.0).timeout
	# The observer's last check: a teleport arrives as one snap.
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(-6.0, 0.5, 6.0)], ["vector3[f32,f32,f32]"])
	await get_tree().create_timer(4.0).timeout
	# UP THE RAMP AND JUMP. Ramp30 climbs +Z at x 5 onto the platform (top 1.75 m). Walked, not
	# teleported: the walk up a slope is what must NOT read as a jump to anyone watching.
	SpaceTimeSync.call_reducer(&"teleport", [Vector3(5.0, 0.0, -5.0)], ["vector3[f32,f32,f32]"])
	await get_tree().create_timer(2.0).timeout
	input.set_look(PI, 0.0)
	Input.action_press(&"move_forward")
	for f: int in range(int(2.2 * 60.0)):
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	await get_tree().create_timer(1.0).timeout
	print("   walker on the platform at %s" % me.global_position)
	for k: int in range(JUMPS):
		Input.action_press(&"jump")
		for f: int in range(6):
			await get_tree().physics_frame
		Input.action_release(&"jump")
		await get_tree().create_timer(1.4).timeout
	await get_tree().create_timer(2.0).timeout
	_check(true, "walker finished its route")
	await _see_the_observer_go_out(me)
	await _be_helped_up(me)


## OUT, AS SOMEONE ELSE SEES IT (DECISIONS #206): the observer puts itself out at the end; here its
## body leaves the world (hidden, no collision) and comes back when it is in again. The walker stays
## connected meanwhile, so the observer has someone to watch.
func _see_the_observer_go_out(me: SpaceTimeEntity) -> void:
	var other: SpaceTimeEntity = null
	var deadline: int = Time.get_ticks_msec() + 30_000
	var went_out: bool = false
	var hidden_while_out: bool = false
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if other == null:
			for id: int in EntityRegistry.all_entity_ids():
				var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
				if id != me.entity_id and e != null and e.is_bound() and e.definition != null and e.definition.kind == 0:
					var st0: StatusComponent = e.find_component(StatusComponent) as StatusComponent
					if st0 != null and st0.status() == StatusDef.OUT:
						other = e
			continue
		var st: StatusComponent = other.find_component(StatusComponent) as StatusComponent
		if st.status() == StatusDef.OUT:
			went_out = true
			hidden_while_out = not other.visible and other.collision_layer == 0
		elif went_out:
			break
	_check(went_out, "the walker sees the observer go out")
	_check(hidden_while_out, "and its body leave the world (hidden, nothing collides with it)")
	_check(other != null and other.visible and other.collision_layer != 0, "and come back when it is in again")


# --- observer ----------------------------------------------------------------------------

func _observe(me: SpaceTimeEntity) -> void:
	print("== remote playtest: OBSERVER (entity %d, simulated latency %d ms) =="
		% [me.entity_id, SpaceTimeSync.get_simulated_latency().x])

	# The walker is whichever other player starts moving.
	var target: SpaceTimeEntity = null
	var mv: SpaceTimeMovementComponent = null
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	var starts: Dictionary[int, Vector3] = {}
	while target == null and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		for id: int in EntityRegistry.all_entity_ids():
			if id == me.entity_id:
				continue
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e == null or not e.is_bound() or e.definition == null or e.definition.kind != 0:
				continue
			var m: SpaceTimeMovementComponent = e.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
			if m == null:
				continue
			var p: Vector3 = m.get_render_state().pos
			if not starts.has(id):
				starts[id] = p
			elif p.distance_to(starts[id]) > 0.5:
				target = e
				mv = m
	_check(target != null, "the observer sees another player start to move")
	if target == null:
		return
	_check(mv.mode == SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED,
		"someone else's player is interpolated, not predicted")
	print("   watching entity %d" % target.entity_id)
	mv.diagnostics_enabled = true   # explain any lurch measured below
	# Every jump and landing the watcher is told about, with where the walker was (authoritative).
	var jumps_seen: Array[Vector3] = []
	var lands_seen: Array[Vector3] = []
	mv.jumped.connect(func() -> void: jumps_seen.append(mv.get_authoritative_state().pos))
	mv.landed.connect(func(_impact: float) -> void: lands_seen.append(mv.get_authoritative_state().pos))
	# The same entity, animated: a remote character is driven by `move_state` and the mirrored
	# jump/land events alone (DECISIONS #94), which only a second real client can exercise.
	var anim: AnimationDriverComponent = target.find_component(
		AnimationDriverComponent) as AnimationDriverComponent
	var anim_peak: float = 0.0
	_check(anim != null and anim.is_animating(),
		"the other player is a rigged character with a live animation tree")

	var teleports: Array[int] = []
	SignalBus.entity_teleported.connect(func(eid: int) -> void:
		if eid == target.entity_id:
			teleports.append(Engine.get_physics_frames()))

	# Record the drawn position every physics frame until the walker's teleport lands.
	var trace: Array[Vector3] = []
	var frames_at: Array[int] = []
	var glide: Array[float] = []
	var seen_states: Array[int] = []
	var diags: Array[Dictionary] = []
	deadline = Time.get_ticks_msec() + int((WALK_SEC + 12.0) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		trace.append(mv.get_render_state().pos)
		frames_at.append(Engine.get_physics_frames())
		glide.append(mv.get_remote_offset().length())
		seen_states.append(mv.get_authoritative_state().move_state if mv.get_authoritative_state() != null else -1)
		if anim != null:
			anim_peak = maxf(anim_peak, anim.speed_blend())
		var dg2: Dictionary = mv.get_frame_diagnostics().duplicate()
		dg2["ring"] = mv.get_snapshot_dump()
		diags.append(dg2)
		if not teleports.is_empty() and Engine.get_physics_frames() > teleports[0] + 30:
			break

	# Analyse the WALK only: everything before the teleport.
	var walk_end: int = trace.size()
	if not teleports.is_empty():
		walk_end = frames_at.find(teleports[0])
		if walk_end < 0:
			walk_end = trace.size()
	var path: float = 0.0
	var lurches: int = 0
	var worst: float = 0.0
	var stalls: int = 0
	var moving_frames: int = 0
	for i: int in range(2, walk_end):
		var d1: Vector3 = trace[i - 1] - trace[i - 2]
		var d2: Vector3 = trace[i] - trace[i - 1]
		var h1: float = Vector2(d1.x, d1.z).length()
		var h2: float = Vector2(d2.x, d2.z).length()
		path += h2
		if h1 > 0.02:
			moving_frames += 1
			if h2 < 0.002:
				stalls += 1   # was walking last frame, frozen this frame
		var change: float = Vector2(d2.x - d1.x, d2.z - d1.z).length()
		if change > LURCH_EPS:
			lurches += 1
			worst = maxf(worst, change)
			print("   lurch at frame %d: change %.3f, glide offset %.3f -> %.3f, steps %.3f -> %.3f"
				% [i, change, glide[i - 1], glide[i], h1, h2])
			for k: int in range(maxi(0, i - 3), mini(diags.size(), i + 2)):
				var dg: Dictionary = diags[k]
				print("      frame %d: %s  render_t step %s  delay %.1f ms  newest ahead %.1f ms  span %.1f ms"
					% [k, dg.get("branch", "?"),
						str(int(dg.get("render_t", 0)) - int(diags[k - 1].get("render_t", 0))) if k > 0 else "-",
						float(dg.get("delay_ms", 0.0)), float(dg.get("newest_ahead_ms", 0.0)), float(dg.get("span_ms", 0.0))])
			var ring: Array = diags[i].get("ring", [])
			var rt: int = int(diags[i].get("render_t", 0))
			for e: Array in ring:
				var dt_ms: float = float(int(e[0]) - rt) / 1000.0
				if dt_ms > -150.0 and dt_ms < 120.0:
					print("      snapshot %+7.1f ms  pos (%.3f, %.3f)  vel (%.2f, %.2f)" % [dt_ms, (e[1] as Vector3).x, (e[1] as Vector3).z, (e[2] as Vector3).x, (e[2] as Vector3).z])
	print("   drew the walker covering %.2f m over %d frames (%d moving)" % [path, walk_end, moving_frames])
	var istats: Dictionary = mv.get_interp_stats()
	print("   lurches: %d (worst %.3f m/frame change); stalls mid-walk: %d; interp delay %.0f ms"
		% [lurches, worst, stalls, mv.get_interp_delay_sec() * 1000.0])
	print("   buffer ran dry %d times (%d frames extrapolated)"
		% [int(istats["dry_events"]), int(istats["extrapolated_frames"])])
	_check(path > 20.0, "the walker is seen to cover ground (%.2f m)" % path)
	_check(lurches == 0, "the remote walker is drawn continuously: no lurches (%d, worst %.3f)" % [lurches, worst])
	_check(stalls <= 1, "the remote walker never freezes mid-walk (%d stalls)" % stalls)

	# What the walker is DOING, as someone else sees it (PHASE4_SPEC §2.5). Tier A has no
	# simulation to decide it: the walker's model classifies each frame and the module mirrors
	# it. This is what a remote animation will play from.
	var walking: int = 0
	var idle_after: int = 0
	var moving_seen: int = 0
	for i: int in range(2, walk_end):
		var h: float = Vector2(trace[i].x - trace[i - 1].x, trace[i].z - trace[i - 1].z).length()
		if h > 0.05:
			moving_seen += 1
			if seen_states[i] == MovementState.Move.RUN:
				walking += 1
	for i: int in range(maxi(0, walk_end - 40), walk_end):
		if seen_states[i] == MovementState.Move.IDLE:
			idle_after += 1
	print("   remote move_state: RUN on %d of %d moving frames; IDLE in the last 40 before the teleport: %d"
		% [walking, moving_seen, idle_after])
	_check(moving_seen > 0 and walking >= int(0.9 * moving_seen),
		"the observer sees the walker as RUN while it runs (%d/%d)" % [walking, moving_seen])
	_check(idle_after > 0, "and as IDLE once it stops")
	if anim != null:
		print("   remote locomotion blend peaked at %.2f, state %s"
			% [anim_peak, anim.current_state()])
		_check(anim_peak > 0.3,
			"and animates it as walking, from those rows alone (blend %.2f)" % anim_peak)

	# The teleport: exactly one announcement, and one snap rather than a slide across the map.
	_check(teleports.size() == 1, "the walker's teleport is announced once (%d)" % teleports.size())
	if walk_end < trace.size() - 1:
		# The signal fires when the row is processed; the snap is drawn on the next physics
		# tick. Find the one big step in the few frames after the announcement.
		var jump: float = 0.0
		var jump_at: int = walk_end
		for i: int in range(maxi(1, walk_end), mini(trace.size(), walk_end + 6)):
			var step: float = trace[i].distance_to(trace[i - 1])
			if step > jump:
				jump = step
				jump_at = i
		var after: float = 0.0
		for i: int in range(jump_at + 1, trace.size()):
			after = maxf(after, trace[i].distance_to(trace[i - 1]))
		print("   teleport drawn as a %.2f m jump; largest step after it %.3f m" % [jump, after])
		_check(jump > 5.0, "the teleport is drawn as ONE snap (%.2f m in a single frame)" % jump)
		_check(after < 0.2, "after the teleport the walker is not sliding across the map (%.3f m)" % after)

	# THE JUMPS, AS SOMEONE ELSE IS TOLD THEM. Wait out the ramp and the jumps.
	var jumps_before: int = jumps_seen.size()
	deadline = Time.get_ticks_msec() + 16_000
	while Time.get_ticks_msec() < deadline and (jumps_seen.size() - jumps_before < JUMPS
			or Time.get_ticks_msec() < deadline - 4000):
		await get_tree().physics_frame
	# And see the last one come down: the loop ends on the jump it was waiting for.
	await get_tree().create_timer(2.0).timeout
	var on_ramp: int = 0
	for j: Vector3 in jumps_seen:
		if j.z < 1.0:
			on_ramp += 1
	print("   jumps the observer was told of: %d (on the walk and ramp: %d), landings %d" % [jumps_seen.size(), on_ramp, lands_seen.size()])
	for j: Vector3 in jumps_seen:
		print("      jumped at %s" % j)
	for l: Vector3 in lands_seen:
		print("      landed at %s" % l)
	_check(on_ramp == 0, "walking up a ramp is not a jump to anyone watching (%d jumps announced on it)" % on_ramp)
	_check(jumps_seen.size() == JUMPS, "each of the walker's %d jumps is announced exactly once (%d)" % [JUMPS, jumps_seen.size()])
	var lands_up: int = 0
	for l: Vector3 in lands_seen:
		if l.y > 1.5:
			lands_up += 1
	_check(lands_up == JUMPS, "and lands exactly once each, on the platform (%d landings up there)" % lands_up)
	await _spectate(me, target)
	await _help_up(me, target)


## OUT, WATCHING A TEAMMATE (DECISIONS #206): the observer puts itself out (the dev tools are on
## here); its camera then follows the walker, the one other player, and comes home when it is in.
func _spectate(me: SpaceTimeEntity, walker: SpaceTimeEntity) -> void:
	var st: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	var rig: CameraRig = me.get_node_or_null(^"CameraRig") as CameraRig
	_check(st != null and rig != null, "the observer has a status and a camera rig")
	if st == null or rig == null:
		return
	SpaceTimeSync.call_reducer(&"set_status", [me.entity_id, StatusDef.OUT, 4294967295, ""], ["u64", "u8", "u32", "string"])
	var deadline: int = Time.get_ticks_msec() + 10_000
	while st.status() != StatusDef.OUT and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var cam: Camera3D = get_viewport().get_camera_3d()
	var near: float = cam.global_position.distance_to(walker.global_position) if cam != null else INF
	print("   out: watching %s, camera %.2f m from the walker" % [rig.following().entity_id if rig.following() != null else -1, near])
	_check(st.status() == StatusDef.OUT and rig.following() == walker, "out, the observer's camera follows the walker")
	_check(near < 8.0, "and is over the walker, not where the observer stands (%.2f m away)" % near)
	_check(not me.visible, "its own body has left the world")
	await get_tree().create_timer(3.0).timeout   # long enough for the walker to see it
	SpaceTimeSync.call_reducer(&"set_status", [me.entity_id, StatusDef.NORMAL, 4294967295, ""], ["u64", "u8", "u32", "string"])
	deadline = Time.get_ticks_msec() + 10_000
	while st.status() != StatusDef.NORMAL and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(rig.following() == null and me.visible, "in again: its own view and body back")
	await get_tree().create_timer(2.0).timeout


# --- help up (DECISIONS #209) ------------------------------------------------------------------

## Where the walker waits to be helped up, and where the observer stands to help: open floor, a metre
## from the walker, its character facing it, the camera level so the crosshair passes over it: in
## front of the character is enough, the crosshair need not be on it (DECISIONS #211, #213).
const DOWN_AT: Vector3 = Vector3(-4.0, 0.0, 0.8)
const HELP_FROM: Vector3 = Vector3(-3.0, 0.0, 0.8)


## THE WALKER: down on open floor, until someone helps it up.
func _be_helped_up(me: SpaceTimeEntity) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [DOWN_AT], ["vector3[f32,f32,f32]"])
	await get_tree().create_timer(1.0).timeout
	SpaceTimeSync.call_reducer(&"set_status", [me.entity_id, StatusDef.DOWNED, 4294967295, ""], ["u64", "u8", "u32", "string"])
	var st: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	var hc: HoldComponent = me.find_component(HoldComponent) as HoldComponent
	var finished: Array = []
	SignalBus.hold_finished.connect(func(target: int, hold: int) -> void:
		if target == me.entity_id:
			finished.append(hold))
	var deadline: int = Time.get_ticks_msec() + 60_000
	var was_down: bool = false
	var most: float = 0.0
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if st.status() == StatusDef.DOWNED:
			was_down = true
		elif was_down:
			break
		for id: int in hc.holds_on_me():
			most = maxf(most, hc.progress(id))
	print("   walker: downed %s, helped %.0f%% of the way at most before it was done, up again: %s" % [was_down, most * 100.0, st.status() == StatusDef.NORMAL])
	_check(was_down, "the walker is downed")
	_check(most > 0.3, "it sees itself being helped up (its bar reached %.0f%%)" % (most * 100.0))
	_check(st.status() == StatusDef.NORMAL and finished.size() == 1 and st.by_entity() != me.entity_id and st.by_entity() > 0,
		"and is back on its feet, helped up by the other player (%s, by %d)" % [str(finished), st.by_entity()])


## Turn the body to `yaw` standing still, as a player does by aiming (the camera's way, held a
## moment: `hold_facing`, which the server applies too), then let go.
func _turn_body(input: LocalInputComponent, yaw: float) -> void:
	input.set_look(yaw, 0.0)
	input.hold_facing(&"playtest", true)
	await get_tree().create_timer(0.5).timeout
	input.hold_facing(&"playtest", false)
	await get_tree().create_timer(0.5).timeout


## THE OBSERVER: walk up to the downed walker, look at it, hold the interact key.
func _help_up(me: SpaceTimeEntity, walker: SpaceTimeEntity) -> void:
	var wst: StatusComponent = walker.find_component(StatusComponent) as StatusComponent
	var whc: HoldComponent = walker.find_component(HoldComponent) as HoldComponent
	var mine: HoldComponent = me.find_component(HoldComponent) as HoldComponent
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	var deadline: int = Time.get_ticks_msec() + 20_000
	while (wst.status() != StatusDef.DOWNED or walker.global_position.distance_to(DOWN_AT) > 0.5) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(wst.status() == StatusDef.DOWNED, "the observer sees the walker downed")
	SpaceTimeSync.call_reducer(&"teleport", [HELP_FROM], ["vector3[f32,f32,f32]"])
	await _turn_body(input, PI)   # facing +Z, the walker square to the side: outside the front arc
	_check(ic.get_target() != walker.entity_id, "beside the walker, facing away to the side: not offered (the front arc only)")
	# Standing still, the camera alone turned to look at the walker: the body did not turn, so the
	# walker is still beside it, not in front (DECISIONS #221).
	input.set_look(PI * 0.5, 0.0)
	await get_tree().create_timer(0.6).timeout
	_check(ic.get_target() != walker.entity_id, "the camera alone turned to the walker: still not offered (the body faces where it did)")
	await _turn_body(input, PI * 0.5)   # the body turned to face -X: the walker in front
	var s: Dictionary = HoldPrompt.state_for(me)
	var under_crosshair: int = ic._raycast_target()
	print("   facing the downed walker, the crosshair on %d: \"%s\"" % [under_crosshair, s["text"]])
	_check(under_crosshair != walker.entity_id, "the observer faces the walker, the crosshair not on it")
	_check(ic.get_target() == walker.entity_id and String(s["text"]) == "Hold E: Help up",
		"and is offered: \"%s\"" % s["text"])

	# Let go early: the help is lost.
	Input.action_press(&"interact")
	await get_tree().create_timer(1.5).timeout
	var part: float = whc.progress(whc.hold_id_for(HoldDef.find(walker.definition.kind, 0, StatusDef.DOWNED, me.definition.kind).id))
	_check(mine.is_holding() and part > 0.1 and part < 0.6, "holding the key: helping, the bar part way (%.0f%%)" % (part * 100.0))
	_check(String(HoldPrompt.state_for(me)["text"]) == "Help up", "the prompt says what it is doing")
	Input.action_release(&"interact")
	await get_tree().create_timer(1.0).timeout
	_check(not mine.is_holding() and whc.holds_on_me().is_empty() and wst.status() == StatusDef.DOWNED,
		"let go early: the help is lost, the walker still down")

	# Held: back on its feet in Help up's 4 s (and a round trip).
	var began: int = Time.get_ticks_msec()
	Input.action_press(&"interact")
	deadline = began + 12_000
	while wst.status() != StatusDef.NORMAL and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var took: float = float(Time.get_ticks_msec() - began) / 1000.0
	print("   helped the walker up in %.2f s" % took)
	_check(wst.status() == StatusDef.NORMAL and took > 3.5 and took < 6.5, "held: the walker is back on its feet in about 4 s (%.2f s)" % took)
	await get_tree().create_timer(0.5).timeout
	_check(not mine.is_holding(), "and the observer is no longer holding anything")
	Input.action_release(&"interact")
	await get_tree().create_timer(1.0).timeout


# --- helpers -----------------------------------------------------------------------------

func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
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
	printerr("  FAIL: remote playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release(&"move_forward")
	Input.action_release(&"interact")
	print("\n%s: %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
