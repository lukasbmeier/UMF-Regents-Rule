extends Node
## THE SKELETON ARCHER, PLAYED (Luke's F1-F6, 2026-11-12; `archer_playtest.sh`): a real client at a simulated round
## trip against the world's real referee and the archer by the glade's skeleton camp. It stands in the archer's range and is shot
## (the tell, the glint, the arrow's damage), holds its guard (blocked), rolls as the arrow comes (nothing dealt),
## taps its guard as it lands (knocked away: nothing dealt, the archer NOT staggered), then walks up to it (it steps
## back once, then is caught and shoves). The server's own word on each is in its log (`archer_playtest.sh` reads it).

const OVERALL_TIMEOUT_SEC: float = 170.0
const ARCHER_KIND: int = 108
const AXE: int = 40001
const STATUS_STAGGERED: int = 103
## Which way from the archer we stand (flat): away from the melee camp beside it, clear of its bushes.
const SIDE: Vector3 = Vector3(0.45, 0.0, 0.89)

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var me: SpaceTimeEntity
var combat: CombatComponent
var input: LocalInputComponent
var my_hp: SpaceTimeHealthComponent
var archer: SpaceTimeEntity
var foe: FoeDef
var shot: AbilityDef
## When the archer was seen to begin each draw, and each shove (msec).
var draws: Array[int] = []
var shoves: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	combat = me.find_component(CombatComponent) as CombatComponent
	input = me.find_component(LocalInputComponent) as LocalInputComponent
	my_hp = me.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	var inv: SpaceTimeInventoryComponent = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	input.capture_mouse = false
	foe = FoeDef.by_kind(ARCHER_KIND)
	shot = foe.shot() if foe != null else null
	_check(foe != null and shot != null, "the archer is content, with a shot")
	if shot == null:
		_finish()
		return
	await _until(func() -> bool: return inv.count(AXE) == 1, 5.0)
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == AXE:
			combat.wield(s.id)
	await _until(func() -> bool: return combat.kit != null, 5.0)
	_check(combat.kit != null, "an axe in hand (a guard needs a weapon)")

	# --- FIND IT: stand outside its notice, north of it, and look ---
	await _until(func() -> bool: return _find_archer() != null, 10.0)
	archer = _find_archer()
	_check(archer != null, "a skeleton archer stands in the glade")
	if archer == null:
		_finish()
		return
	var home: Vector3 = archer.global_position
	var act: SpaceTimeActionComponent = archer.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	act.started_elsewhere.connect(func(ability_id: int) -> void:
		if ability_id == shot.id:
			draws.append(Time.get_ticks_msec())
		elif ability_id == foe.kit.light[0].id:
			shoves.append(Time.get_ticks_msec()))
	var look: FoeLook = archer.find_component(FoeLook) as FoeLook
	await _until(func() -> bool: return look != null and look.dressed, 5.0)
	var skel: Skeleton3D = SkillingLook.skeleton_of(archer)
	var sword: Node3D = skel.get_node_or_null(^"Skeleton_Sword") as Node3D if skel != null else null
	_check(look != null and look.dressed and look.held != null and sword != null and not sword.visible,
		"as drawn here: a bow in its hand, its sword hidden")
	var far: Vector3 = home + SIDE.normalized() * (foe.notice_m + 2.0) + Vector3(0, 0.05, 0)
	await _stand_at(far, home)
	await get_tree().create_timer(3.0).timeout
	_check(draws.is_empty() and is_equal_approx(my_hp.get_current(), my_hp.get_max()),
		"NEGATIVE: %.0f m off, past its notice, for 3 s: it draws nothing" % (foe.notice_m + 2.0))

	# IT SEES ONLY IN FRONT, AND HEARS ALL ROUND (Luke's F9, 2026-11-13): 3.5 m off its side it knows we are here,
	# whichever way it faces; then it keeps us while it sees us. Where it stands NOW: at rest it wanders (F10).
	# The camp's skeletons and the imp are kept down meanwhile (the shell): wandering, they can come within sight.
	print("CAMP_DOWN")
	await get_tree().create_timer(1.5).timeout
	var heard_at: Vector3 = archer.global_position
	await _stand_at(heard_at + SIDE.normalized() * 3.0 + Vector3(0, 0.05, 0), heard_at)
	await get_tree().create_timer(0.8).timeout

	# --- SHOT: in its range and sight, an arrow lands ---
	var spot: Vector3 = home + SIDE.normalized() * 11.0 + Vector3(0, 0.05, 0)
	var feed: HitFeedbackComponent = archer.find_component(HitFeedbackComponent) as HitFeedbackComponent
	var n: int = draws.size()
	var hp: float = my_hp.get_current()
	var flashes_before: int = feed.flashes.count(&"shot") if feed != null else 0
	await _stand_at(spot, home)
	await _until(func() -> bool: return draws.size() > n, 8.0)
	_check(draws.size() > n, "11 m off and in sight: it is seen to draw")
	await _until(func() -> bool: return my_hp.get_current() < hp - 0.01, 4.0)
	var took: float = hp - my_hp.get_current()
	var flight_seen_ms: int = Time.get_ticks_msec() - draws[n] if draws.size() > n else -1
	var whole: float = shot.damage * float(foe.damage_pct) / 100.0
	_check(is_equal_approx(snappedf(took, 0.01), snappedf(whole, 0.01)), "its arrow lands: %.2f taken (its %.0f at %d %%: %.2f)" % [took, shot.damage, foe.damage_pct, whole])
	_check(flight_seen_ms > shot.wind_up_ms and flight_seen_ms < shot.wind_up_ms + 1300,
		"it lands %d ms after the draw was seen to begin: the %d ms tell, then the arrow's flight" % [flight_seen_ms, shot.wind_up_ms])
	_check(feed != null and feed.flashes.count(&"shot") > flashes_before and not feed.flashes.has(&"glint"),
		"it glinted pale before it loosed, never the red of an unblockable swing")
	var status: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	_check(status != null and status.status() != STATUS_STAGGERED, "the arrow does not stagger us")
	if flight_seen_ms <= shot.wind_up_ms:
		flight_seen_ms = shot.wind_up_ms + 500

	# --- GUARD: held, facing it, the next arrow is taken through the block ---
	await _heal()
	_face(archer)
	combat.set_block(true)
	n = draws.size()
	await _until(func() -> bool: return draws.size() > n, 8.0)
	hp = my_hp.get_current()
	await _until(func() -> bool: return my_hp.get_current() < hp - 0.01, 4.0)
	var through: float = hp - my_hp.get_current()
	combat.set_block(false)
	var my_feed: HitFeedbackComponent = me.find_component(HitFeedbackComponent) as HitFeedbackComponent
	_check(through > 0.0 and through < whole - 0.5, "a held guard facing it: the arrow is blocked, %.2f through of %.2f" % [through, whole])
	_check(my_feed != null and my_feed.flashes.has(&"block"), "and it shows as blocked")

	# --- ROLL: begun as the arrow comes, it passes ---
	await _heal()
	var rolled_ok: bool = false
	var tries: int = 0
	while not rolled_ok and tries < 3:
		tries += 1
		n = draws.size()
		await _until(func() -> bool: return draws.size() > n, 8.0)
		if draws.size() <= n:
			break
		hp = my_hp.get_current()
		var wait_ms: int = flight_seen_ms - 250 - (Time.get_ticks_msec() - draws[draws.size() - 1])
		await get_tree().create_timer(maxf(float(wait_ms) / 1000.0, 0.0)).timeout
		Input.action_press(&"move_left")
		await get_tree().physics_frame
		combat.dodge()
		await get_tree().create_timer(1.3).timeout
		Input.action_release(&"move_left")
		rolled_ok = my_hp.get_current() >= hp - 0.01
		await _stand_at(spot, home)
	_check(rolled_ok, "a roll begun as the arrow comes: nothing taken (%d tries)" % tries)

	# --- PARRY: a tap as it lands knocks it away; the archer is not staggered ---
	await _heal()
	var knocked_ok: bool = false
	var archer_status: StatusComponent = archer.find_component(StatusComponent) as StatusComponent
	var staggered: bool = false
	tries = 0
	while not knocked_ok and tries < 4:
		tries += 1
		_face(archer)
		n = draws.size()
		await _until(func() -> bool: return draws.size() > n, 8.0)
		if draws.size() <= n:
			break
		hp = my_hp.get_current()
		var wait_ms: int = flight_seen_ms - 90 - (Time.get_ticks_msec() - draws[draws.size() - 1])
		await get_tree().create_timer(maxf(float(wait_ms) / 1000.0, 0.0)).timeout
		combat.set_block(true)
		await get_tree().create_timer(0.05).timeout
		combat.set_block(false)
		for i: int in 60:
			await get_tree().physics_frame
			staggered = staggered or (archer_status != null and archer_status.status() == STATUS_STAGGERED)
		knocked_ok = my_hp.get_current() >= hp - 0.01
		if not knocked_ok:
			await _heal()
	_check(knocked_ok, "a guard tapped as the arrow lands knocks it away: nothing taken (%d tries)" % tries)
	_check(not staggered, "and its shooter, far off, is NOT staggered by it")
	print("PARRIED_SHOTS %d" % (1 if knocked_ok else 0))

	# --- UP CLOSE: it steps back once, then is caught and shoves ---
	# (The melee camp beside it is slain for this leg: it backs toward them, and their hits are not this suite's.)
	print("SLAY_CAMP")
	await _stand_at(far, home)
	await _heal()
	await get_tree().create_timer(2.0).timeout
	var was: Vector3 = archer.global_position
	var close: Vector3 = was + SIDE.normalized() * (foe.back_within_m - 1.0) + Vector3(0, 0.05, 0)
	await _stand_at(close, was)
	await _until(func() -> bool: return archer.global_position.distance_to(was) > foe.back_m - 1.5, 7.0)
	# ... and until its step is over (it stands again).
	var still: Array[int] = [0]
	var last_at: Array[Vector3] = [archer.global_position]
	await _until(func() -> bool:
		still[0] = still[0] + 1 if archer.global_position.distance_to(last_at[0]) < 0.005 else 0
		last_at[0] = archer.global_position
		return still[0] > 30, 5.0)
	var backed: float = Vector2(archer.global_position.x - was.x, archer.global_position.z - was.z).length()
	var gained: float = archer.global_position.distance_to(me.global_position)
	_check(backed > foe.back_m - 1.0 and backed < foe.back_m + 1.0 and gained > foe.back_within_m,
		"we come within %.0f m: it steps back %.1f m (its %.0f), away from us" % [foe.back_within_m, backed, foe.back_m])
	# Followed at once into its reach: no second step, a shove.
	var at_it: Vector3 = archer.global_position
	n = shoves.size()
	hp = my_hp.get_current()
	await _stand_at(at_it + SIDE.normalized() * 1.4 + Vector3(0, 0.05, 0), at_it)
	await _until(func() -> bool: return shoves.size() > n, 8.0)
	hp = my_hp.get_current()   # (an arrow it had already drawn may land first: the shove's own damage is from here)
	var held_ground: float = archer.global_position.distance_to(at_it)
	_check(shoves.size() > n and held_ground < 1.5, "followed into its reach inside %d ms: it does not step back again (moved %.1f m); it shoves" % [foe.back_every_ms, held_ground])
	var before_push: Vector3 = me.global_position
	await _until(func() -> bool: return my_hp.get_current() < hp - 0.01, 3.0)
	await get_tree().create_timer(0.6).timeout
	var shove_took: float = hp - my_hp.get_current()
	var pushed: float = Vector2(me.global_position.x - before_push.x, me.global_position.z - before_push.z).length()
	_check(shove_took > 0.0 and shove_took < whole and status.status() != STATUS_STAGGERED,
		"the shove lands for little (%.2f) and does not stagger us" % shove_took)
	_check(pushed > 0.8, "and pushes us off it (%.1f m)" % pushed)
	_finish()


func _find_archer() -> SpaceTimeEntity:
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind == ARCHER_KIND:
			return e
	return null


func _heal() -> void:
	print("HEAL %d" % me.entity_id)
	await _until(func() -> bool: return my_hp.get_current() >= my_hp.get_max() - 0.01, 6.0)


func _face(at: SpaceTimeEntity) -> void:
	combat.set_target(at.entity_id)
	var to_it: Vector3 = at.global_position - me.global_position
	input.set_look(atan2(-to_it.x, -to_it.z), 0.0)


func _stand_at(at: Vector3, face: Vector3) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
	var to: Vector3 = face - at
	input.set_look(atan2(-to.x, -to.z) if to.length() > 0.01 else 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


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
		print("   ok: ", msg)
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: archer playtest exceeded %.0fs" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\narcher (fighter): %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
