extends Node
## COMBAT, PLAYED (game/regents/tests/combat_playtest.sh starts this beside the world's real referee): a
## real client through the latency simulator, at the frontier camp's training dummy, through the real
## keys, clicks and the bag panel. Wields the copper axe (the bag's button), Tabs onto the dummy (the
## ring, the target frame), taps the light combo and holds a heavy (each judged by the referee; the
## numbers float up; axemanship XP), waits for the dummy to be whole, rolls (Ctrl: further than a run in
## the same time), blocks (no swing behind it), and lets the target go (Esc). Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 220.0
const DUMMY_1: Vector3 = Vector3(7.0, 0.0, 20.0)
const AXE: int = 40001
const AXEMANSHIP: int = 40007
const DUMMY_KIND: int = 102
const BOW: int = 40020
const ARROWS: int = 40022

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var me: SpaceTimeEntity
var combat: CombatComponent
var skilling: SkillingComponent
var inv: SpaceTimeInventoryComponent
var hud: RegentsHud
var input: LocalInputComponent


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	combat = me.find_component(CombatComponent) as CombatComponent
	skilling = me.find_component(SkillingComponent) as SkillingComponent
	inv = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	input = me.find_component(LocalInputComponent) as LocalInputComponent
	hud = get_tree().current_scene.find_child("HUD", true, false) as RegentsHud
	_check(combat != null and hud != null and input != null, "the adventurer has its combat; the genre's HUD is up")
	if combat == null or hud == null or input == null:
		_finish()
		return
	input.capture_mouse = false   # a display-less run has no cursor to capture
	await _until(func() -> bool: return inv.count(AXE) == 1, 5.0)
	await _until(func() -> bool: return hud._skillbar.text != "", 3.0)
	_check(combat.kit == null and hud._skillbar.text.contains("No weapon"), "nothing wielded: the bar says so (\"%s\")" % hud._skillbar.text)

	# --- WIELD: the bag panel's button ---
	hud.toggle_bag()
	await get_tree().process_frame
	var row: int = -1
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == AXE:
			row = s.id
	hud.bag_window.picked_row = row
	hud.bag_window.refresh()
	var button: Button = hud.bag_window.find_child("Wield_%d" % row, true, false) as Button if hud.bag_window.is_open() else null
	_check(button != null and button.text == "Wield", "the bag panel has a Wield button on the copper axe")
	if button != null:
		button.pressed.emit()
	await _until(func() -> bool: return combat.kit != null, 5.0)
	_check(combat.kit != null and combat.kit.key == &"axe" and combat.weapon.id == AXE, "wielded: it fights with the axe kit")
	await _until(func() -> bool: return _bag_button(row) == "Put away", 2.0)
	_check(_bag_button(row) == "Put away", "its button now puts it away")
	hud.toggle_bag()
	await _until(func() -> bool: return combat.weapon != null and hud._skillbar.text.contains("LMB Chop"), 2.0)
	_check(hud._skillbar.text.contains("Copper axe") and hud._skillbar.text.contains("LMB Chop") and hud._skillbar.text.contains("Q Cleave"),
		"the bar: \"%s\"" % hud._skillbar.text)

	# --- TARGET: Tab onto the dummy ---
	var dummy: int = await _dummy_at(DUMMY_1)
	_check(dummy > 0, "a training dummy at camp")
	if dummy <= 0:
		_finish()
		return
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 1.4), DUMMY_1)
	await _key(KEY_TAB)
	await _until(func() -> bool: return combat.target_id == dummy and hud._target_box.visible, 2.0)
	_check(combat.target_id == dummy and combat.in_stance(), "Tab: the dummy is the target, and we are in stance")
	_check(hud._target_box.visible and hud._target_label.text.contains("Training dummy") and hud._target_label.text.contains("500 / 500"),
		"the target frame: \"%s\"" % hud._target_label.text)
	_check(combat._ring != null and combat._ring.visible and combat._ring.global_position.distance_to((EntityRegistry.get_entity(dummy) as Node3D).global_position) < 0.2,
		"the ring is under it")
	var dh: SpaceTimeHealthComponent = (EntityRegistry.get_entity(dummy) as SpaceTimeEntity).find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	var feed: HitFeedbackComponent = (EntityRegistry.get_entity(dummy) as SpaceTimeEntity).find_component(HitFeedbackComponent) as HitFeedbackComponent

	# --- THE LIGHT COMBO, AND A HEAVY ---
	var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
	await _click(0.06)
	_check(driver.action_clip() == &"extra/Sword_Regular_A", "a chop plays its own swing, not Interact (%s)" % driver.action_clip())
	await _until(func() -> bool: return dh.get_current() < 500.0, 3.0)
	var hit1: float = 500.0 - dh.get_current()
	_check(is_equal_approx(snappedf(hit1, 0.01), 7.7), "a tap of the left button: a chop the referee judged a hit, 11 at the copper axe's 70 %% (%.2f)" % hit1)
	await _click(0.06)
	await _until(func() -> bool: return dh.get_current() < 500.0 - hit1 - 1.0, 3.0)
	var hit2: float = 500.0 - hit1 - dh.get_current()
	_check(is_equal_approx(snappedf(hit2, 0.01), 10.5), "a second tap inside the window: the combo's second chop, 15 (%.2f)" % hit2)
	await get_tree().create_timer(1.0).timeout
	var before_heavy: float = dh.get_current()
	await _click(0.6)
	# The overhead's clip steps 0.85 m forward in its source; played in place, the model never leaves the body.
	var skel: Skeleton3D = me.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var root_bone: int = skel.find_bone("root")
	var drift: float = 0.0
	for i: int in range(40):
		await get_tree().process_frame
		drift = maxf(drift, skel.get_bone_pose_position(root_bone).length())
	_check(driver.action_clip() == &"extra/Sword_Heavy_B" and drift < 0.05,
		"the overhead plays in place: its root moved %.3f m (its clip steps 0.85 m), so nothing snaps back" % drift)
	await _until(func() -> bool: return dh.get_current() < before_heavy - 1.0, 3.0)
	_check(is_equal_approx(snappedf(before_heavy - dh.get_current(), 0.01), 22.4), "held: the overhead, 32 (%.2f)" % (before_heavy - dh.get_current()))
	_check(feed != null and feed.shown.size() >= 3 and is_equal_approx(snappedf(feed.shown[0], 0.01), 7.7), "the numbers floated up from the dummy: %s" % str(feed.shown if feed != null else []))
	await _until(func() -> bool: return int(skilling.xp.get(AXEMANSHIP, 0)) >= 9, 3.0)
	_check(int(skilling.xp.get(AXEMANSHIP, 0)) >= 9, "axemanship XP for the hits (%d)" % int(skilling.xp.get(AXEMANSHIP, 0)))
	await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)
	_check(is_equal_approx(dh.get_current(), 500.0), "the dummy is whole again a few seconds on")

	# --- SPAM: held to the animation, every press kept ---
	var starts: Array[int] = []
	var on_swing: Callable = func(_a: int) -> void: starts.append(Time.get_ticks_msec())
	combat.swung.connect(on_swing)
	var refusals: Array[String] = []
	var on_refused: Callable = func(why: String) -> void: refusals.append(why)
	combat.refused.connect(on_refused)
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await _click(0.03)
		await get_tree().create_timer(0.03).timeout
	await get_tree().create_timer(1.2).timeout
	combat.swung.disconnect(on_swing)
	combat.refused.disconnect(on_refused)
	var gaps: Array[int] = []
	for i: int in range(1, starts.size()):
		gaps.append(starts[i] - starts[i - 1])
	var axe: KitDef = combat.kit
	var least: int = axe.light[0].wind_up_ms + axe.chain_ms
	_check(starts.size() >= 3 and starts.size() <= 5 and gaps.all(func(g: int) -> bool: return g >= least - 20),
		"mashing for 1.5 s swings %d times, never faster than a swing lands and chains (gaps %s ms, at least %d)" % [starts.size(), str(gaps), least])
	_check(refusals.is_empty(), "and the server took every one: the client's timeline is the server's (%s)" % str(refusals))
	await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)

	# --- A ROLL IN A HEAVY'S WIND-UP: the swing never lands ---
	var before_roll: float = dh.get_current()
	await _click(0.45)   # held: the overhead (its wind-up 600 ms)
	await _key(KEY_CTRL)
	_check(combat.swing_cancelled, "Ctrl in the overhead's wind-up cancels it here")
	await _until(func() -> bool: return driver.action_clip() == &"Roll", 1.0)
	_check(driver.action_clip() == &"Roll", "and the roll plays its Roll (%s)" % driver.action_clip())
	await get_tree().create_timer(1.5).timeout
	_check(is_equal_approx(dh.get_current(), before_roll), "the cancelled overhead never landed on the dummy (%.1f)" % dh.get_current())
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 1.4), DUMMY_1)

	# --- A COMMITTED SWING: you walk until it lands ---
	await get_tree().create_timer(1.0).timeout
	await _stand_at(DUMMY_1 + Vector3(-4.0, 0.05, 3.0), DUMMY_1 + Vector3(-4.0, 0.0, -6.0))
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.5).timeout
	await _click(0.03)
	await get_tree().create_timer(0.08).timeout   # slowing from a run to a walk
	var p0: Vector3 = me.global_position
	await get_tree().create_timer(0.15).timeout
	var walked: float = Vector2(me.global_position.x - p0.x, me.global_position.z - p0.z).length() / 0.15
	# Still running at the click; the swing plays to its hit all the same, as the server lands it.
	await _until(func() -> bool: return Time.get_ticks_msec() >= combat.swing_hit_ms, 1.0)
	_check(driver.action_playing() and driver.action_clip() == &"extra/Sword_Regular_A",
		"run into a swing: its animation plays through to the hit (%s)" % driver.action_clip())
	await get_tree().create_timer(0.8).timeout
	var p1: Vector3 = me.global_position
	await get_tree().create_timer(0.3).timeout
	var ran_after: float = Vector2(me.global_position.x - p1.x, me.global_position.z - p1.z).length() / 0.3
	Input.action_release(&"move_forward")
	_check(walked < 2.0 and ran_after > 3.5, "running into a swing: %.1f m/s until it lands, then %.1f m/s again" % [walked, ran_after])

	# --- NO SWING IN THE AIR: a click there waits for the ground ---
	await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))
	await get_tree().create_timer(1.0).timeout
	var air: Array[bool] = []
	var on_air: Callable = func(_a: int) -> void: air.append(combat.grounded())
	combat.swung.connect(on_air)
	Input.action_press(&"jump")
	await _until(func() -> bool: return not combat.grounded(), 1.0)
	Input.action_release(&"jump")
	await get_tree().create_timer(0.15).timeout
	var aloft: bool = not combat.grounded()
	await _click(0.03)
	var swung_aloft: int = air.size()
	await _until(func() -> bool: return air.size() > 0, 2.0)
	combat.swung.disconnect(on_air)
	_check(aloft and swung_aloft == 0 and air.size() == 1 and air[0],
		"a click in a jump swings nothing in the air; it swings on landing (%s)" % str(air))
	await get_tree().create_timer(1.2).timeout
	# And the server's own say: a client that asks in the air anyway (past its own check) is refused.
	var why_refused: Array[String] = []
	var on_no: Callable = func(why: String) -> void: why_refused.append(why)
	combat.refused.connect(on_no)
	Input.action_press(&"jump")
	await _until(func() -> bool: return not combat.grounded(), 1.0)
	Input.action_release(&"jump")
	await get_tree().create_timer(0.2).timeout
	var act: SpaceTimeActionComponent = me.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	act.request_use(combat.kit.light[0].id, 0, Vector3(0, 0, -1))
	await _until(func() -> bool: return not why_refused.is_empty(), 3.0)
	combat.refused.disconnect(on_no)
	_check(why_refused.any(func(w: String) -> bool: return w.contains("not in the air")),
		"a swing asked for in the air anyway: the server refuses it (%s)" % str(why_refused))
	await get_tree().create_timer(1.2).timeout
	# NO ROLL IN THE AIR (Luke's playtest, 2026-10-24): Ctrl in a jump is held, and rolls as it lands.
	await get_tree().create_timer(1.0).timeout
	var rolled_before: int = combat.roll_until_ms
	Input.action_press(&"jump")
	await _until(func() -> bool: return not combat.grounded(), 1.0)
	Input.action_release(&"jump")
	await get_tree().create_timer(0.15).timeout
	var up_there: bool = not combat.grounded()
	await _key(KEY_CTRL)
	var held_aloft: bool = combat.roll_until_ms == rolled_before and combat.roll_on_landing_ms >= 0
	await _until(func() -> bool: return combat.roll_until_ms != rolled_before, 2.0)
	var landed_first: bool = combat.grounded()
	_check(up_there and held_aloft and combat.roll_until_ms != rolled_before and landed_first,
		"Ctrl in a jump rolls nothing in the air (held: %s); it rolls as it lands (%s)" % [str(held_aloft), str(landed_first)])
	await get_tree().create_timer(2.0).timeout

	# --- THE ROLL: further than a run in the same time ---
	# Open ground by the spawn, running north: nothing in the way for 6 m (the camp's stall stopped it).
	await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))
	# The roll is the dash, moved by this client at once; the server only bounds it.
	var ran: float = await _run_for(0.7, false)
	var mv0: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var before_roll_fixes: int = int(mv0.get_reconcile_stats()["reconciles"])
	var rolled: float = await _run_for(0.7, true)
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var fixed: int = before_roll_fixes
	_check(rolled > ran + 1.2 and int(mv.get_reconcile_stats()["reconciles"]) == fixed,
		"Ctrl while running: the predicted dash carries %.2f m against a run's %.2f, and the server corrected none of it" % [rolled, ran])

	# --- THE ROLL PLAYS WHOLE; NOTHING SWINGS IN IT; NOT AGAIN TOO SOON ---
	await get_tree().create_timer(1.6).timeout   # the roll above is off its cooldown
	var roll_s: float = driver.shot_seconds(&"ability.40010")
	var rolls: Array[int] = []
	var on_roll: Callable = func(_a: int) -> void: rolls.append(Time.get_ticks_msec())
	combat.swung.connect(on_roll)
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.3).timeout
	var rolled_at: int = Time.get_ticks_msec()
	await _key(KEY_CTRL)
	await _click(0.03)   # mid-roll: waits for the roll
	# Watched until the queued swing takes over at the roll's end: the dash's speed used to cut it at once.
	var rolling_ms: int = 0
	while Time.get_ticks_msec() - rolled_at < int(roll_s * 1000.0) and rolls.is_empty():
		if driver.action_playing() and driver.action_clip() == &"Roll":
			rolling_ms = Time.get_ticks_msec() - rolled_at
		await get_tree().process_frame
	_check(rolling_ms >= int(HotRules.number(&"regents.roll_ms")) - 60,
		"running, the Roll plays on (%d ms of its %.2f s, until the queued swing takes over): the dash's speed no longer cuts it" % [rolling_ms, roll_s])
	# Ctrl again inside the roll's cooldown: no roll, and NO DASH, even with the dash's own cooldown lost (as a
	# correction lost it before DECISIONS #264): the dash is the roll's, not the key's.
	var mvp: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var dodges_before: int = int(mvp.get_reconcile_stats()["reconciles"])
	mvp._predicted.dash_cooldown = 0
	var act2: SpaceTimeActionComponent = me.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	var second_rolls: Array[int] = []
	var on_started: Callable = func(id: int, _pid: int) -> void: second_rolls.append(id)
	act2.action_started.connect(on_started)
	await _key(KEY_CTRL)
	var dashed_again: bool = false
	for i: int in range(12):
		await get_tree().process_frame
		dashed_again = dashed_again or mvp.get_predicted_state().dash_left > 0
	act2.action_started.disconnect(on_started)
	_check(not dashed_again and not second_rolls.has(40010),
		"Ctrl again inside the roll's 1.5 s cooldown: no roll and no dash, even with the dash's own cooldown gone (%d corrections meanwhile)"
		% (int(mvp.get_reconcile_stats()["reconciles"]) - dodges_before))
	await _until(func() -> bool: return not rolls.is_empty(), 2.0)
	Input.action_release(&"move_forward")
	combat.swung.disconnect(on_roll)
	var roll_ms: int = int(HotRules.number(&"regents.roll_ms"))
	_check(rolls.size() == 1 and rolls[0] - rolled_at >= roll_ms - 20,
		"a click mid-roll swings only once the roll is over (%d ms after Ctrl, the roll %d ms)" % [(rolls[0] - rolled_at) if not rolls.is_empty() else -1, roll_ms])
	await get_tree().create_timer(1.2).timeout

	# --- THE BLOCK ---
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 1.4), DUMMY_1)
	var st: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _until(func() -> bool: return combat.blocking and st != null and st.status() == 102, 3.0)
	_check(combat.blocking and st != null and st.status() == 102, "the right button held: blocking")
	var guarded: float = dh.get_current()
	await _click(0.06)
	await get_tree().create_timer(1.2).timeout
	_check(is_equal_approx(dh.get_current(), guarded), "no swing behind a block")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	combat.set_block(false)
	await _until(func() -> bool: return not combat.blocking and st.status() == 0, 3.0)
	_check(not combat.blocking and st.status() == 0, "let go: the block comes down")

	# --- A SKELETON (owner, 2026-10-19): it notices you, comes for you and swings; you hit it back; past its
	# leash it gives up and walks home. Its brain runs in the referee, as in play.
	await _key(KEY_ESCAPE)
	var my_hp: SpaceTimeHealthComponent = me.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	await _stand_at(Vector3(33.0, 0.05, 8.0), Vector3(33.0, 0.0, -1.0))   # 9 m from skeleton_1 (it notices at 10)
	var foe_ent: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind == 103 \
				and (foe_ent == null or e.global_position.distance_to(me.global_position) < foe_ent.global_position.distance_to(me.global_position)):
			foe_ent = e
	_check(foe_ent != null, "a skeleton warrior at the camp")
	if foe_ent != null:
		var home: Vector3 = foe_ent.global_position
		var hp0: float = my_hp.get_current()
		# Its swings are watched from now: one may start the moment it arrives.
		var sdrv: AnimationDriverComponent = foe_ent.find_component(AnimationDriverComponent) as AnimationDriverComponent
		var swung_clip: Array[StringName] = []
		var watch: Callable = func() -> void:
			if sdrv != null and sdrv.action_playing() and String(sdrv.action_clip()).contains("Sword"):
				swung_clip.append(sdrv.action_clip())
		await _until(func() -> bool:
			watch.call()
			return foe_ent.global_position.distance_to(me.global_position) < 2.6, 10.0)
		_check(foe_ent.global_position.distance_to(me.global_position) < 2.6, "it noticed you and came (%.1f m away now)" % foe_ent.global_position.distance_to(me.global_position))
		await _until(func() -> bool:
			watch.call()
			return my_hp.get_current() < hp0 and not swung_clip.is_empty(), 8.0)
		_check(my_hp.get_current() < hp0 and not swung_clip.is_empty(),
			"it swung its sword (%s) and hit you: %.1f -> %.1f" % [swung_clip[0] if not swung_clip.is_empty() else &"no swing seen", hp0, my_hp.get_current()])
		var shp: SpaceTimeHealthComponent = foe_ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
		var s0: float = shp.get_current()
		var to_it: Vector3 = foe_ent.global_position - me.global_position
		input.set_look(atan2(-to_it.x, -to_it.z), 0.0)
		await get_tree().create_timer(0.4).timeout
		await _click(0.06)
		await _until(func() -> bool: return shp.get_current() < s0, 3.0)
		_check(shp.get_current() < s0, "your chop hit it back: %.1f -> %.1f" % [s0, shp.get_current()])
		# Run: past its leash (25 m from home) it gives up and walks home.
		await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))
		await _until(func() -> bool: return foe_ent.global_position.distance_to(home) < 2.0, 20.0)
		_check(foe_ent.global_position.distance_to(home) < 2.0, "out of its reach, it walked home (%.1f m from its point)" % foe_ent.global_position.distance_to(home))
		# Out of the fight, health comes back (regents.regen_delay_s, then regen_pct_per_s).
		var hurt_hp: float = my_hp.get_current()
		await _until(func() -> bool: return my_hp.get_current() > hurt_hp + 3.0 or my_hp.get_current() >= my_hp.get_max(), 20.0)
		_check(my_hp.get_current() > hurt_hp, "out of the fight, your health comes back: %.1f -> %.1f" % [hurt_hp, my_hp.get_current()])

	# --- THE YEW BOW (owner, 2026-10-20): drawn on the move, loosed at the Tab target; the arrow flies in
	# the referee's world and what it hits is the server's; free aim; RMB lets the draw go ---
	print("GRANT_BOW %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(BOW) == 1 and inv.count(ARROWS) >= 6, 20.0)
	_check(inv.count(BOW) == 1 and inv.count(ARROWS) >= 6, "the shell gave a yew bow and arrows")
	var bow_row: int = -1
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == BOW:
			bow_row = s.id
	combat.wield(bow_row)
	await _until(func() -> bool: return combat.kit != null and combat.kit.draws, 5.0)
	_check(combat.kit != null and combat.kit.key == &"bow" and hud._skillbar.text.contains("hold LMB draw"), "wielded: the bar says draw and loose (\"%s\")" % hud._skillbar.text)
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 10.0), DUMMY_1)
	combat.set_target(dummy)
	await get_tree().create_timer(0.3).timeout
	_check(hud._skillbar.text.contains("to hit"), "with the dummy targeted it says the chance to hit (\"%s\")" % hud._skillbar.text)
	var arrows0: int = inv.count(ARROWS)
	var before_shot: float = dh.get_current()
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.45).timeout
	var pdrv: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_check(combat.drawing() and hud._draw_bar.visible and pdrv.upper_pose_weight() > 0.5,
		"LMB held: drawing, the bar fills, the arms draw (%.2f)" % pdrv.upper_pose_weight())
	# Drawn, you walk.
	Input.action_press(&"move_left")
	await get_tree().create_timer(0.15).timeout
	var wp0: Vector3 = me.global_position
	await get_tree().create_timer(0.4).timeout
	var walk_speed: float = Vector2(me.global_position.x - wp0.x, me.global_position.z - wp0.z).length() / 0.4
	Input.action_release(&"move_left")
	_check(walk_speed < 2.0 and pdrv.upper_pose_weight() > 0.5, "drawn, you walk (%.1f m/s), the bow still drawn" % walk_speed)
	await get_tree().create_timer(0.4).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _until(func() -> bool: return dh.get_current() < before_shot, 4.0)
	_check(dh.get_current() < before_shot and inv.count(ARROWS) == arrows0 - 1,
		"let go: an arrow flew and hit the dummy (%.1f -> %.1f), one arrow used" % [before_shot, dh.get_current()])
	# Free aim: no target, at the dummy along the view.
	combat.set_target(-1)
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 10.0), DUMMY_1)
	var before_free: float = dh.get_current()
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.9).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _until(func() -> bool: return dh.get_current() < before_free, 4.0)
	_check(dh.get_current() < before_free, "no target: aimed along the view, it still hits what it flies into (%.1f -> %.1f)" % [before_free, dh.get_current()])
	# WHAT YOU HIT BECOMES YOUR TARGET (owner, 2026-10-20: "auto highlight that enemy"), on the hit, so free
	# aim stays free.
	await _until(func() -> bool: return combat.target_id == dummy, 1.0)
	_check(combat.target_id == dummy and hud._target_box.visible, "and the dummy it hit is the target now (picked on the hit, not the press)")
	# RMB lets the draw go: nothing loosed.
	var arrows1: int = inv.count(ARROWS)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.4).timeout
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.8).timeout
	var st_bow: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	_check(not combat.drawing() and inv.count(ARROWS) == arrows1 and st_bow.status() != 107, "RMB lets the draw go: no arrow, no Drawing")
	combat.wield(-1)
	await get_tree().create_timer(0.5).timeout

	# --- LET THE TARGET GO ---
	await _key(KEY_ESCAPE)
	await _until(func() -> bool: return combat.target_id == -1, 1.0)
	_check(combat.target_id == -1 and not hud._target_box.visible and not combat._ring.visible, "Esc: no target, no ring, no frame")
	_finish()


## Run forward for `secs` (rolling with Ctrl at the start when `roll`): how far the body went.
func _run_for(secs: float, roll: bool) -> float:
	await get_tree().create_timer(0.6).timeout
	var from: Vector3 = me.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.25).timeout   # up to speed
	from = me.global_position
	if roll:
		await _key(KEY_CTRL)
	await get_tree().create_timer(secs).timeout
	var d: float = Vector2(me.global_position.x - from.x, me.global_position.z - from.z).length()
	Input.action_release(&"move_forward")
	await get_tree().create_timer(0.4).timeout
	return d


## The bag panel's button on row `row`: its words, or "" when there is none.
func _bag_button(row: int) -> String:
	var b: Button = hud.bag_window.find_child("Wield_%d" % row, true, false) as Button if hud.bag_window.is_open() else null
	return b.text if b != null else ""


func _click(hold_s: float) -> void:
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(hold_s).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await get_tree().physics_frame


func _mouse(button: MouseButton, down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


func _dummy_at(at: Vector3) -> int:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		for id: int in EntityRegistry.all_entity_ids():
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.definition != null and e.definition.kind == DUMMY_KIND and Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() < 0.6:
				return id
		await get_tree().process_frame
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		print("   (entity %d: kind %s at %s)" % [id, str(e.definition.kind) if e != null and e.definition != null else "?", str(e.global_position) if e != null else "?"])
	return -1


func _stand_at(at: Vector3, face: Vector3) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
	var to: Vector3 = face - at
	input.set_look(atan2(-to.x, -to.z) if to.length() > 0.01 else 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().physics_frame


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
	printerr("  FAIL: combat playtest exceeded %.0fs" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\ncombat (fighter): %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
