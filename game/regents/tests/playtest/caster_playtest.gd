extends Node
## THE IMP CASTER, PLAYED (Luke's F1, 2026-11-12; `caster_playtest.sh`): a real client at a simulated round trip
## against the world's real referee and the imp by the glade's skeleton camp. It stands in the imp's range and takes
## whatever is cast next, each of six ways once: a bolt taken, a bolt stepped out of after the aim locks, a bolt
## walked into (a steady walk through the lock is LED, Luke 2026-11-13: it hits), a bolt turned from after the lock
## (the walk reversed: it misses), a ring stood in, a ring walked out of. Then it stands on the imp and swings: a staggered imp's cast is lost (the server's
## word, read by `caster_playtest.sh`).

const OVERALL_TIMEOUT_SEC: float = 250.0
const IMP_KIND: int = 109
const AXE: int = 40001
const STATUS_STAGGERED: int = 103
## Which way from the imp we stand (flat): away from the melee camp and the archer beside it.
const SIDE: Vector3 = Vector3(0.6, 0.0, -0.8)

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var me: SpaceTimeEntity
var combat: CombatComponent
var input: LocalInputComponent
var my_hp: SpaceTimeHealthComponent
var imp: SpaceTimeEntity
var foe: FoeDef
## Each cast the imp was seen to begin: [ability id, msec].
var casts: Array[Vector2i] = []


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
	foe = FoeDef.by_kind(IMP_KIND)
	var bolt: AbilityDef = foe.shot() if foe != null else null
	var ring: AbilityDef = foe.ring() if foe != null else null
	_check(bolt != null and ring != null, "the imp is content, with a bolt and a ring")
	if bolt == null or ring == null:
		_finish()
		return
	await _until(func() -> bool: return inv.count(AXE) == 1, 5.0)
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == AXE:
			combat.wield(s.id)
	await _until(func() -> bool: return combat.kit != null, 5.0)
	await _until(func() -> bool: return _find_imp() != null, 10.0)
	imp = _find_imp()
	_check(imp != null, "an imp stands in the glade")
	if imp == null:
		_finish()
		return
	var home: Vector3 = imp.global_position
	var act: SpaceTimeActionComponent = imp.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	act.started_elsewhere.connect(func(ability_id: int) -> void:
		if ability_id == bolt.id or ability_id == ring.id:
			casts.append(Vector2i(ability_id, Time.get_ticks_msec())))
	var look: FoeLook = imp.find_component(FoeLook) as FoeLook
	await _until(func() -> bool: return look != null and look.dressed, 5.0)
	var skel: Skeleton3D = SkillingLook.skeleton_of(imp)
	var mace: Node3D = skel.get_node_or_null(^"Imp_Mace") as Node3D if skel != null else null
	_check(mace != null and not mace.visible, "as drawn here: its mace is hidden (it casts)")
	var far: Vector3 = home + SIDE.normalized() * (foe.notice_m + 3.0) + Vector3(0, 0.05, 0)
	await _stand_at(far, home)
	await get_tree().create_timer(3.0).timeout
	_check(casts.is_empty() and is_equal_approx(my_hp.get_current(), my_hp.get_max()), "NEGATIVE: past its notice for 3 s: it casts nothing")

	# --- IN ITS RANGE: whatever it casts next, each of the six ways once ---
	var spot: Vector3 = home + SIDE.normalized() * 9.0 + Vector3(0, 0.05, 0)
	var bolt_whole: float = bolt.damage * float(foe.damage_pct) / 100.0
	var ring_whole: float = ring.damage * float(foe.damage_pct) / 100.0
	var ring_spell: SpellDef = SpellDef.by_ability(ring.id)
	var feed: HitFeedbackComponent = imp.find_component(HitFeedbackComponent) as HitFeedbackComponent
	var looks: SpellLooks = get_tree().root.find_child("SpellLooks", true, false) as SpellLooks
	var status: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	var done: Dictionary[String, String] = {}
	var order: Array[int] = []
	var staggered: bool = false
	# IT SEES ONLY IN FRONT, AND HEARS ALL ROUND (Luke's F9, 2026-11-13): 3.5 m off its side it knows we are here,
	# whichever way it faces; then it keeps us while it sees us. Where it stands NOW: at rest it wanders (F10).
	# The camp's archer is kept down meanwhile (the shell): wandering, it can come within sight of our spot.
	print("ARCHER_DOWN")
	await get_tree().create_timer(1.5).timeout
	var heard_at: Vector3 = imp.global_position
	await _stand_at(heard_at + SIDE.normalized() * 3.0 + Vector3(0, 0.05, 0), heard_at)
	await get_tree().create_timer(0.8).timeout
	await _heal()
	var n: int = casts.size()
	await _stand_at(spot, home)
	var deadline: int = Time.get_ticks_msec() + 130_000
	var lock_ms: int = int(HotRules.number(&"regents.foe_shot_lock_ms"))
	while done.size() < 6 and Time.get_ticks_msec() < deadline:
		await _until(func() -> bool: return casts.size() > n, 10.0)
		if casts.size() <= n:
			break
		var cast: Vector2i = casts[n]
		n = casts.size()
		order.append(cast.x)
		var hp: float = my_hp.get_current()
		var is_ring: bool = cast.x == ring.id
		var tell: int = ring.wind_up_ms if is_ring else bolt.wind_up_ms
		var ways: Array[String] = ["ring_stood", "ring_left"]
		if not is_ring:
			ways = ["bolt_stood", "bolt_left", "bolt_walked", "bolt_turned"]
		var key: String = ways[-1]
		for w: String in ways:
			if not done.has(w):
				key = w
				break
		if key == "bolt_walked" or key == "bolt_turned":
			# A steady walk across its line from well before the aim locks (the server reads it at the lock) ...
			var walk_ms: int = (tell - lock_ms - 500) - (Time.get_ticks_msec() - cast.y)
			await get_tree().create_timer(maxf(float(walk_ms) / 1000.0, 0.0)).timeout
			Input.action_press(&"move_left")
			if key == "bolt_turned":
				# ... turned back once the aim has locked: the led bolt flies to where that walk was going.
				var turn_ms: int = (tell - 100) - (Time.get_ticks_msec() - cast.y)
				await get_tree().create_timer(maxf(float(turn_ms) / 1000.0, 0.0)).timeout
				Input.action_release(&"move_left")
				Input.action_press(&"move_right")
		elif key.ends_with("left"):
			# Out of it: a bolt after its aim has locked; a ring once it lies on the ground.
			var go_ms: int = (tell + 150 if is_ring else tell - 150) - (Time.get_ticks_msec() - cast.y)
			await get_tree().create_timer(maxf(float(go_ms) / 1000.0, 0.0)).timeout
			Input.action_press(&"move_left")
			await get_tree().create_timer(1.1).timeout
			Input.action_release(&"move_left")
		var until_ms: int = cast.y + tell + (ring_spell.delay_ms if is_ring else 1500) + 500
		while Time.get_ticks_msec() < until_ms:
			await get_tree().physics_frame
			staggered = staggered or status.status() == STATUS_STAGGERED
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")
		var took: float = hp - my_hp.get_current()
		var areas: int = looks._areas.size() if looks != null else -1
		var again: bool = done.has(key)
		done[key] = "%.2f" % took
		match key if not again else "":
			"bolt_stood":
				_check(is_equal_approx(snappedf(took, 0.01), snappedf(bolt_whole, 0.01)), "its bolt, stood for: %.2f taken (its %.0f at %d %%: %.2f)" % [took, bolt.damage, foe.damage_pct, bolt_whole])
			"bolt_left":
				_check(took < 0.01, "its bolt, stepped out of after the aim locked: nothing taken (%.2f)" % took)
			"bolt_walked":
				_check(is_equal_approx(snappedf(took, 0.01), snappedf(bolt_whole, 0.01)), "its bolt, walked into: a steady walk through the lock is led and hit, %.2f taken" % took)
			"bolt_turned":
				_check(took < 0.01, "its bolt, the walk turned back after the aim locked: it flew to where the walk was going, nothing taken (%.2f)" % took)
			"ring_stood":
				_check(is_equal_approx(snappedf(took, 0.01), snappedf(ring_whole, 0.01)), "its ring, stood in: %.2f taken as it filled (its %.0f at %d %%: %.2f)" % [took, ring.damage, foe.damage_pct, ring_whole])
				_check(areas >= 0, "and the ring was drawn on the ground")
			"ring_left":
				_check(took < 0.01, "its ring, walked out of: nothing taken (%.2f)" % took)
		await _heal()
		await _stand_at(spot, home)
		n = casts.size()
	_check(done.size() == 6, "a bolt taken, stepped out of, walked into, turned from; a ring stood in, a ring left: %s" % str(done))
	# Every cast seen, in order (those cast while we healed and walked back too).
	order.clear()
	for c: Vector2i in casts:
		order.append(c.x)
	var pattern_ok: bool = order.size() >= 3
	for i: int in order.size():
		pattern_ok = pattern_ok and order[i] == (ring.id if i % 3 == 2 else bolt.id)
	_check(pattern_ok, "seen to cast bolt, bolt, ring, and again (%s)" % str(order))
	_check(feed != null and feed.flashes.count(&"shot") >= 2 and not feed.flashes.has(&"glint"), "each cast glinted pale before it flew, never red")
	_check(not staggered, "nothing it cast staggered us")

	# --- ON IT: swung at, its cast is lost (the server says so) ---
	print("SLAY_CAMP")
	await _stand_at(far, home)
	await _heal()
	await get_tree().create_timer(2.0).timeout
	var at_it: Vector3 = imp.global_position
	await _stand_at(at_it + SIDE.normalized() * 1.3 + Vector3(0, 0.05, 0), at_it)
	combat.set_target(imp.entity_id)
	var imp_status: StatusComponent = imp.find_component(StatusComponent) as StatusComponent
	var imp_hp: SpaceTimeHealthComponent = imp.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	var imp_staggered: bool = false
	var swing_until: int = Time.get_ticks_msec() + 9000
	while Time.get_ticks_msec() < swing_until and imp_hp.get_current() > 12.0:
		var to_it: Vector3 = imp.global_position - me.global_position
		input.set_look(atan2(-to_it.x, -to_it.z), 0.0)
		combat.light()
		for i: int in 24:
			await get_tree().physics_frame
			imp_staggered = imp_staggered or (imp_status != null and imp_status.status() == STATUS_STAGGERED)
	_check(imp_hp.get_current() < imp_hp.get_max() and imp_staggered, "swung at up close: it is hurt (%.0f of %.0f) and staggers (its poise is low)" % [imp_hp.get_current(), imp_hp.get_max()])
	_check(imp.global_position.distance_to(at_it) < 2.5, "and it never stepped back from us (moved %.1f m)" % imp.global_position.distance_to(at_it))
	_finish()


func _find_imp() -> SpaceTimeEntity:
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind == IMP_KIND:
			return e
	return null


func _heal() -> void:
	print("HEAL %d" % me.entity_id)
	await _until(func() -> bool: return my_hp.get_current() >= my_hp.get_max() - 0.01, 6.0)


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
	printerr("  FAIL: caster playtest exceeded %.0fs" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\ncaster (fighter): %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
