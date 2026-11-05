extends Node
## COMBAT, PLAYED (game/regents/tests/combat_playtest.sh starts this beside the world's real referee): a
## real client through the latency simulator, at the frontier camp's training dummy, through the real
## keys, clicks and the bag panel. Wields the copper axe (the bag's button), Tabs onto the dummy (the
## ring, the target frame), taps the string (a chop, then the overhead, its finisher, which staggers; each
## judged by the referee; the numbers float up; axemanship XP), waits for the dummy to be whole, rolls (Ctrl:
## further than a run in the same time), blocks (no swing behind it); at the skeleton camp PARRIES a light it
## saw (and fails one pressed too early), ripostes, blocks the rest; ROLES: re-hilts two swords at the workbench
## and plays each handle's last hit (COMBAT_OVERHAUL.md §5); and lets the target go (Esc). Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 680.0
## The camp's guide and the yard's sparring skeleton (the glade's `guide` and `sparring_1` points).
const GUIDE: Vector3 = Vector3(5.0, 0.0, 22.5)
const SPARRING: Vector3 = Vector3(13.5, 0.0, 24.5)
const SPARRING_KIND: int = 105
const DUMMY_1: Vector3 = Vector3(7.0, 0.0, 20.0)
const AXE: int = 40001
const AXEMANSHIP: int = 40007
const DUMMY_KIND: int = 102
const BOW: int = 40020
const ARROWS: int = 40022
const IRON_SWORD: int = 40019
const CROSSGUARD: int = 40040
const BANNER: int = 40041

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

	# --- THE STRING: a chop, then the overhead, the axe's finisher (COMBAT_OVERHAUL.md §3) ---
	var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
	await _click(0.06)
	_check(driver.action_clip() == &"extra/Sword_Regular_A", "a chop plays its own swing, not Interact (%s)" % driver.action_clip())
	await _until(func() -> bool: return dh.get_current() < 500.0, 3.0)
	var hit1: float = 500.0 - dh.get_current()
	_check(is_equal_approx(snappedf(hit1, 0.01), 8.4), "a tap of the left button: a chop the referee judged a hit, 12 at the copper axe's 70 %% (%.2f)" % hit1)
	# ITS POISE ON THE MARKER (Luke, 2026-11-02): the chop wore 10 of the dummy's 50, shown round the ring under it.
	var arc_worn: Callable = func() -> float:
		var m: ShaderMaterial = combat.poise_arc.material_override as ShaderMaterial if combat.poise_arc != null else null
		return float(m.get_shader_parameter(&"worn")) if m != null else -1.0
	await _until(func() -> bool: return float(arc_worn.call()) > 0.0, 2.0)
	_check(combat.poise_arc != null and combat.poise_arc.visible and absf(float(arc_worn.call()) - 0.2) < 0.02,
		"the chop wore a fifth of the dummy's poise, filled round the ring under it (%.2f)" % float(arc_worn.call()))
	await _click(0.06)
	# The overhead's clip steps forward in its source; played in place, the model never leaves the body.
	var skel: Skeleton3D = me.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var root_bone: int = skel.find_bone("root")
	var drift: float = 0.0
	var overhead_clip: StringName = &""
	for i: int in range(40):
		await get_tree().process_frame
		drift = maxf(drift, skel.get_bone_pose_position(root_bone).length())
		var clip_now: String = String(driver.action_clip())
		if driver.action_playing() and overhead_clip == &"" and clip_now != "extra/Sword_Regular_A" and not clip_now.ends_with("_Rec"):
			overhead_clip = driver.action_clip()
	_check(overhead_clip == &"extra/Sword_Heavy_A" and drift < 0.05,
		"a second tap inside the window: the overhead (%s), played in place: its root moved %.3f m, so nothing snaps back" % [overhead_clip, drift])
	var rec0: int = combat.recoveries
	await _until(func() -> bool: return driver.action_playing() and String(driver.action_clip()) == "extra/Sword_Heavy_A_Rec", 2.5)
	_check(combat.recoveries > rec0 and String(driver.action_clip()) == "extra/Sword_Heavy_A_Rec",
		"the overhead blends back through its recovery (%s), not a snap to idle (Luke, 2026-11-01)" % driver.action_clip())
	await _until(func() -> bool: return dh.get_current() < 500.0 - hit1 - 1.0, 3.0)
	var hit2: float = 500.0 - hit1 - dh.get_current()
	_check(is_equal_approx(snappedf(hit2, 0.01), 18.2), "the string's last: the overhead, its finisher, 26 (%.2f)" % hit2)
	await _until(func() -> bool: return feed != null and feed.flashes.has(&"stagger"), 2.0)
	_check(feed != null and feed.flashes.has(&"stagger"), "the finisher STAGGERED the dummy (the old heavy's job, now the string's last)")
	var arc_steady: float = float((combat.poise_arc.material_override as ShaderMaterial).get_shader_parameter(&"steady")) if combat.poise_arc != null else -1.0
	_check(arc_steady > 0.5 and feed.poise_steadied(ClockSync.server_usec()), "its poise broke: the ring's arc is the gray of Steadied")
	_check(feed != null and feed.shown.size() >= 2 and is_equal_approx(snappedf(feed.shown[0], 0.01), 8.4), "the numbers floated up from the dummy: %s" % str(feed.shown if feed != null else []))
	await _until(func() -> bool: return int(skilling.xp.get(AXEMANSHIP, 0)) >= 7, 3.0)
	_check(int(skilling.xp.get(AXEMANSHIP, 0)) >= 7, "axemanship XP for the hits (%d)" % int(skilling.xp.get(AXEMANSHIP, 0)))
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
	var least: int = axe.light[0].wind_up_ms + axe.follow_for(0)
	_check(starts.size() >= 2 and starts.size() <= 4 and gaps.all(func(g: int) -> bool: return g >= least - 20),
		"mashing for 1.5 s swings %d times, never faster than a swing lands and follows through (gaps %s ms, at least %d)" % [starts.size(), str(gaps), least])
	_check(refusals.is_empty(), "and the server took every one: the client's timeline is the server's (%s)" % str(refusals))
	await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)

	# --- A ROLL IN A SWING'S WIND-UP: the swing never lands ---
	var before_roll: float = dh.get_current()
	await _click(0.03)   # a chop (its wind-up 320 ms)
	await _key(KEY_CTRL)
	_check(combat.swing_canceled, "Ctrl in the chop's wind-up cancels it here")
	await _until(func() -> bool: return driver.action_clip() == &"Roll", 1.0)
	_check(driver.action_clip() == &"Roll", "and the roll plays its Roll (%s)" % driver.action_clip())
	await get_tree().create_timer(1.5).timeout
	_check(is_equal_approx(dh.get_current(), before_roll), "the canceled chop never landed on the dummy (%.1f)" % dh.get_current())
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
		await _heal(my_hp)
		await _parrying_the_camp(my_hp)
		await _back_at_camp(my_hp, home)
		await _blocking_the_camp(me, my_hp)
		await _back_at_camp(my_hp, home)
		await _blocked_from_behind(my_hp)
		await _back_at_camp(my_hp, home)
		# A sweep hits the first body in its path: with the camp round you that may be the skeleton beside this one
		# (2026-11-01: two runs running), so what the chop did is read off the camp's skeletons, the most any lost.
		var camp_hp: Dictionary[int, float] = {}
		for id: int in EntityRegistry.all_entity_ids():
			var ce: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if ce != null and ce.definition != null and FoeDef.by_kind(ce.definition.kind) != null:
				var ch: SpaceTimeHealthComponent = ce.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
				if ch != null:
					camp_hp[id] = ch.get_current()
		var chopped: Callable = func() -> float:
			var most: float = 0.0
			for id: int in camp_hp:
				var ce: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
				var ch: SpaceTimeHealthComponent = ce.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent if ce != null else null
				if ch != null:
					most = maxf(most, camp_hp[id] - ch.get_current())
			return most
		# Waiting its turn a foe circles out of reach (COMBAT_OVERHAUL.md §2): hit back when it steps in.
		# Guarded while it does (two skeletons at once kill a player who stands there), then the guard drops.
		var fights_at: float = FoeDef.by_kind(103).reach_m + 0.2
		combat.set_block(true)
		await _until(func() -> bool: return foe_ent.global_position.distance_to(me.global_position) < fights_at, 12.0)
		combat.set_block(false)
		await _until(func() -> bool: return not combat.blocking, 2.0)
		# A skeleton's finisher staggers you (COMBAT_OVERHAUL.md §3), and a press made then waits for it: each try
		# waits until you can act, faces it, chops (2026-11-01: three skeletons kept a single chop waiting past
		# the check, two runs running).
		for attempt: int in 4:
			if float(chopped.call()) > 0.01:
				break
			await _until(func() -> bool: return combat.can_act() and not combat.swinging(Time.get_ticks_msec()), 3.0)
			var to_it: Vector3 = foe_ent.global_position - me.global_position
			input.set_look(atan2(-to_it.x, -to_it.z), 0.0)
			await get_tree().create_timer(0.3).timeout
			await _click(0.06)
			await _until(func() -> bool: return float(chopped.call()) > 0.01, 2.0)
		_check(float(chopped.call()) > 0.01, "your chop hit a skeleton back: %.1f off it" % float(chopped.call()))
		# Run: past its leash (25 m from home) it gives up and walks home.
		await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))
		var hurt_hp: float = my_hp.get_current()
		await _until(func() -> bool: return foe_ent.global_position.distance_to(home) < 2.0, 20.0)
		_check(foe_ent.global_position.distance_to(home) < 2.0, "out of its reach, it walked home (%.1f m from its point)" % foe_ent.global_position.distance_to(home))
		# Out of the fight, health comes back (regents.regen_delay_s, then regen_pct_per_s): measured from
		# leaving it, since the walk home may outlast the delay.
		await _until(func() -> bool: return my_hp.get_current() > hurt_hp + 3.0 or my_hp.get_current() >= my_hp.get_max(), 20.0)
		_check(my_hp.get_current() > hurt_hp, "out of the fight, your health comes back: %.1f -> %.1f" % [hurt_hp, my_hp.get_current()])

	# --- ROLES BY THE HANDLE (COMBAT_OVERHAUL.md §5): the sword's three, re-hilted at the workbench ---
	await _roles(dummy, dh)

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
	_check(not combat.drawing() and inv.count(ARROWS) == arrows1 and st_bow.status() != 107, "RMB lets the draw go (and parries with the stave): no arrow, no Drawing")
	combat.wield(-1)
	await get_tree().create_timer(0.5).timeout

	await _yard()

	# --- LET THE TARGET GO ---
	await _key(KEY_ESCAPE)
	await _until(func() -> bool: return combat.target_id == -1, 1.0)
	_check(combat.target_id == -1 and not hud._target_box.visible and not combat._ring.visible, "Esc: no target, no ring, no frame")
	_finish()


## THE YARD (the tutorial, Luke 2026-11-01): begun at the guide (E twice, as the HUD answers it); a sword taken in
## hand; then against the sparring skeleton, reading each swing as this client sees it start: the parry and the
## strike back, the held guard, a roll through a light and through the glinting overhead, and three in a row. Each
## lesson is the SERVER's tick, seen in the tutorial's row; the ring closes on each of its swings, over its wind-up.
func _yard() -> void:
	var tut: TutorialComponent = me.find_component(TutorialComponent) as TutorialComponent
	var my_hp: SpaceTimeHealthComponent = me.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	_check(tut != null and tut.state == TutorialComponent.OFFERED, "the yard: the tutorial is offered (state %d)" % (tut.state if tut != null else -9))
	if tut == null:
		return
	await _heal(my_hp)
	await _stand_at(GUIDE + Vector3(0, 0.05, 1.5), GUIDE)
	hud.talk_to_guide()
	_check(hud.tutorial_card.offering(), "E on the guide: their offer")
	hud.talk_to_guide()
	await _until(func() -> bool: return tut.state == TutorialComponent.ON, 4.0)
	_check(tut.state == TutorialComponent.ON, "E again: the lessons begun")
	var ticked: Array[String] = []
	tut.lesson_ticked.connect(func(l: LessonDef) -> void: ticked.append(l.display_name))
	var sword_row: int = -1
	for st: SpaceTimeInventoryComponent.Stack in inv.items():
		if st.item_def_id == IRON_SWORD:
			sword_row = st.id
	combat.wield(sword_row)
	await _until(func() -> bool: return ticked.has("Take it in hand"), 4.0)
	_check(ticked.has("Take it in hand"), "a sword taken in hand: ticked (%s)" % str(ticked))
	var partner: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind == SPARRING_KIND:
			partner = e
	_check(partner != null, "the sparring skeleton stands in the yard")
	if partner == null:
		return
	var feed: HitFeedbackComponent = partner.find_component(HitFeedbackComponent) as HitFeedbackComponent
	var seen: Array[Dictionary] = []
	(partner.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent).started_elsewhere.connect(func(ability_id: int) -> void:
		seen.append({"ability": ability_id, "at": Time.get_ticks_msec()}))
	var parried_by: Array[int] = []
	combat.parried.connect(func(by: int) -> void: parried_by.append(by))
	var swings: Array[int] = []
	combat.swung.connect(func(_ab: int) -> void: swings.append(Time.get_ticks_msec()))
	await _stand_at(SPARRING + Vector3(0, 0.05, 2.2), SPARRING)
	_face(partner)
	var want: Array[String] = ["Parry", "Strike back", "Hold your guard", "Roll through", "The red glint", "Three in a row"]
	var until_ms: int = Time.get_ticks_msec() + 75_000
	while Time.get_ticks_msec() < until_ms and not want.all(func(w: String) -> bool: return ticked.has(w)):
		if my_hp.get_current() < 40.0:
			await _heal(my_hp)
		if partner.global_position.distance_to(me.global_position) > 3.0:
			await _stand_at(partner.global_position + Vector3(0, 0.05, 2.2), partner.global_position)
		_face(partner)
		var n: int = seen.size()
		await _until(func() -> bool: return seen.size() > n, 6.0)
		if seen.size() <= n:
			# Its rest (or it waits): three in a row on it, if that is still to do.
			if not ticked.has("Three in a row"):
				for i: int in 3:
					var n1: int = swings.size()
					await _click(0.06)
					await _until(func() -> bool: return swings.size() > n1, 1.0)
					await get_tree().create_timer(0.45).timeout
			continue
		var swing: Dictionary = seen[seen.size() - 1]
		var a: AbilityDef = null
		for x: AbilityDef in FoeDef.by_kind(SPARRING_KIND).kit.light:
			if x.id == int(swing["ability"]):
				a = x
		if a == null:
			continue
		var lands: int = int(swing["at"]) + a.wind_up_ms
		if KitDef.is_unblockable(a.id) or not ticked.has("Roll through"):
			# ROLL through it: begun 200 ms before it lands as seen.
			await _until(func() -> bool: return Time.get_ticks_msec() >= lands - 200, 2.0)
			await _key(KEY_CTRL)
		elif not ticked.has("Parry") or not ticked.has("Strike back"):
			# PARRY, as the ring shuts (60 ms before it lands as seen), then strike at once.
			await _until(func() -> bool: return Time.get_ticks_msec() >= lands - 60, 2.0)
			var p0: int = parried_by.size()
			combat.set_block(true)
			await get_tree().create_timer(0.05).timeout
			combat.set_block(false)
			await _until(func() -> bool: return parried_by.size() > p0, 1.5)
			if parried_by.size() > p0:
				_face(partner)
				await _click(0.03)
		elif not ticked.has("Hold your guard"):
			# THE HELD GUARD through it, facing it.
			await _until(func() -> bool: return Time.get_ticks_msec() >= lands - 400, 2.0)
			combat.set_block(true)
			await get_tree().create_timer(0.8).timeout
			combat.set_block(false)
		# Its combo over (the glinting overhead is its last), it rests: three in a row on it, while that is to do.
		if KitDef.is_unblockable(a.id) and not ticked.has("Three in a row"):
			await _until(func() -> bool: return Time.get_ticks_msec() >= lands + 150 and combat.can_act(), 2.0)
			_face(partner)
			# Each tap once the swing before it has begun, a beat after (as the dummy's string is played above).
			for i: int in 3:
				var n0: int = swings.size()
				await _click(0.06)
				await _until(func() -> bool: return swings.size() > n0, 1.0)
				await get_tree().create_timer(0.45).timeout
			continue
		await get_tree().create_timer(0.5).timeout
	print("   the yard's lessons ticked: %s; the rings: %s" % [str(ticked), str(feed.rings if feed != null else [])])
	for w: String in want:
		_check(ticked.has(w), "the yard: \"%s\" ticked by the server" % w)
	var winds: Array[int] = []
	for a: AbilityDef in FoeDef.by_kind(SPARRING_KIND).kit.light:
		winds.append(a.wind_up_ms)
	_check(feed != null and not feed.rings.is_empty() and feed.rings.all(func(w: int) -> bool: return winds.has(w)),
		"a ring closed on each of its swings, over its wind-up (%s)" % str(feed.rings if feed != null else []))
	_check(hud.tutorial_card.visible and not hud.tutorial_card._title.text.is_empty(), "the card shows the lesson now: \"%s\"" % hud.tutorial_card._title.text)
	combat.set_target(-1)
	await _stand_at(GUIDE + Vector3(0, 0.05, 1.5), GUIDE)
	combat.wield(-1)
	await get_tree().create_timer(0.5).timeout


## Run forward for `secs` (rolling with Ctrl at the start when `roll`): how far the body went.
## FOES YOU CAN READ (COMBAT_OVERHAUL.md §2, 2026-10-31): held up against the camp for 16 s, a block stops
## the skeletons' lights (a quarter through) but not their finisher: it glints red as it winds up (the
## client saw it start) and lands in full. And their hits on you come in turns, never two together.
func _blocking_the_camp(me: SpaceTimeEntity, my_hp: SpaceTimeHealthComponent, through_pct: float = -1.0) -> void:
	var feeds: Array[HitFeedbackComponent] = []
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and FoeDef.by_kind(e.definition.kind) != null:
			var f: HitFeedbackComponent = e.find_component(HitFeedbackComponent) as HitFeedbackComponent
			if f != null:
				feeds.append(f)
	# What each foe's hits do through a block (the server's rule: the ability's damage at the foe's %, through
	# the wielded weapon's guard: the light one, unless `through_pct` says the full one's).
	var block: float = (through_pct if through_pct >= 0.0 else HotRules.number(&"regents.weak_block_pct")) / 100.0
	var whole: Array[float] = []
	var blocked: Array[float] = []
	for f: FoeDef in FoeDef.all():
		for a: AbilityDef in f.kit.light:
			var d: float = snappedf(a.damage * float(f.damage_pct) / 100.0, 0.01)
			if f.kit.unblockable.has(a):
				whole.append(d)
			else:
				blocked.append(snappedf(d * block, 0.01))
	combat.set_block(true)
	await _until(func() -> bool: return combat.blocking, 3.0)
	var drops: Array[float] = []
	var at_ms: Array[int] = []
	var last: float = my_hp.get_current()
	var until: int = Time.get_ticks_msec() + 16000
	var heals_asked: int = 0
	var raised_ms: int = 0
	# The camp's three take ~60 health in 5 s: worn low, the shell's HEAL (a rise, never counted) keeps the 16 s
	# going (2026-11-01: stopping at 45 health left one run 5 s and no light from in front).
	while Time.get_ticks_msec() < until and my_hp.get_current() > 0.0:
		await get_tree().process_frame
		_face_nearest_foe()   # the guard stops only what is in front
		if not combat.blocking and Time.get_ticks_msec() - raised_ms > 300:
			raised_ms = Time.get_ticks_msec()
			combat.set_block(true)   # a stagger or a hit may drop it: hold it up again (not every frame: the rate limit)
		var now_hp: float = my_hp.get_current()
		if now_hp < last - 0.01:
			drops.append(snappedf(last - now_hp, 0.01))
			at_ms.append(Time.get_ticks_msec())
		last = now_hp
		if now_hp < 50.0 and heals_asked < 6:
			heals_asked += 1
			print("HEAL %d" % me.entity_id)
			await _until(func() -> bool: return my_hp.get_current() > 60.0, 4.0)
			last = my_hp.get_current()
	combat.set_block(false)
	var glinted: bool = feeds.any(func(f: HitFeedbackComponent) -> bool: return f.flashes.has(&"glint"))
	_check(glinted, "a skeleton's finisher glinted red as it wound up (%d foes watched)" % feeds.size())
	_check(drops.any(func(d: float) -> bool: return whole.any(func(w: float) -> bool: return is_equal_approx(d, w))),
		"the finisher came through the block in full (one of %s): hits taken %s" % [str(whole), str(drops)])
	_check(drops.any(func(d: float) -> bool: return blocked.any(func(b: float) -> bool: return is_equal_approx(d, b))),
		"a light was still blocked (the guard: %d%% through, one of %s): hits taken %s" % [roundi(block * 100.0), str(blocked), str(drops)])
	# Hits are seen on this client: the referee's settle and the round trip's jitter move each by up to
	# ~50 ms, so two hits the server spaced by the gap show at least the gap less 100 ms apart.
	var gap: int = int(HotRules.number(&"regents.token_gap_ms"))
	var least: int = 1 << 30
	for i: int in range(1, at_ms.size()):
		least = mini(least, at_ms[i] - at_ms[i - 1])
	_check(at_ms.size() >= 2 and least >= gap - 100, "%d hits held up against them, never two together: the least gap %d ms (the rule %d)" % [at_ms.size(), least, gap])


## THE PARRY, PLAYED (COMBAT_OVERHAUL.md §4): against the camp, a guard press made a whole wind-up before a
## light SEEN starting (too early: no parry, it lands in full), then one made just before a light lands as
## this client shows it (parried: no damage, the skeleton staggered by us), then a tap at once: the riposte.
func _parrying_the_camp(my_hp: SpaceTimeHealthComponent) -> void:
	var seen: Array[Dictionary] = []
	var foes: Dictionary[int, SpaceTimeEntity] = {}
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and FoeDef.by_kind(e.definition.kind) != null:
			foes[id] = e
			var act: SpaceTimeActionComponent = e.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
			if act != null:
				act.started_elsewhere.connect(func(ability_id: int) -> void:
					seen.append({"foe": id, "ability": ability_id, "at": Time.get_ticks_msec()}))
	var parried_by: Array[int] = []
	combat.parried.connect(func(by: int) -> void: parried_by.append(by))
	var light_of: Callable = func(ability_id: int) -> AbilityDef:
		if KitDef.is_unblockable(ability_id):
			return null   # a finisher: no parry stops it
		for f: FoeDef in FoeDef.all():
			for a: AbilityDef in f.kit.light:
				if a.id == ability_id:
					return a
		return null
	# TOO EARLY: pressed (a tap) as a light is seen starting, a whole wind-up before it lands.
	var early_ok: bool = false
	var early_taken: float = -1.0
	var tries: int = 0
	while not early_ok and tries < 4 and my_hp.get_current() > 60.0:
		tries += 1
		var n: int = seen.size()
		await _until(func() -> bool: return seen.size() > n and light_of.call(int(seen[seen.size() - 1]["ability"])) != null, 10.0)
		if seen.size() <= n:
			break
		var swing: Dictionary = seen[seen.size() - 1]
		var a: AbilityDef = light_of.call(int(swing["ability"]))
		var foe: SpaceTimeEntity = foes[int(swing["foe"])]
		_face(foe)
		var hp: float = my_hp.get_current()
		combat.set_block(true)
		await get_tree().create_timer(0.05).timeout
		combat.set_block(false)
		var whole: float = snappedf(a.damage * float(FoeDef.by_kind(foe.definition.kind).damage_pct) / 100.0, 0.01)
		await _until(func() -> bool: return my_hp.get_current() < hp - 0.01, float(a.wind_up_ms) / 1000.0 + 1.0)
		early_taken = snappedf(hp - my_hp.get_current(), 0.01)
		early_ok = is_equal_approx(early_taken, whole) and not parried_by.has(foe.entity_id)
		await get_tree().create_timer(0.8).timeout
	_check(early_ok, "a guard pressed as a light is seen starting (a whole wind-up early) parries nothing: it lands in full (%.2f)" % early_taken)
	await _heal(my_hp)
	# IN TIME: pressed 60 ms before the light lands as this client shows it (its clip's hit). Judged with no
	# credit for the trips (the press's and the swing's), it would count 90 ms late: past the window.
	var parried_ok: bool = false
	var riposte_dealt: float = -1.0
	var riposte_want: float = 0.0
	tries = 0
	while not parried_ok and tries < 6 and my_hp.get_current() > 40.0:
		tries += 1
		var n: int = seen.size()
		await _until(func() -> bool: return seen.size() > n and light_of.call(int(seen[seen.size() - 1]["ability"])) != null, 10.0)
		if seen.size() <= n:
			break
		var swing: Dictionary = seen[seen.size() - 1]
		var a: AbilityDef = light_of.call(int(swing["ability"]))
		var foe: SpaceTimeEntity = foes[int(swing["foe"])]
		_face(foe)
		var press_at: int = int(swing["at"]) + a.wind_up_ms - 60
		await _until(func() -> bool: return Time.get_ticks_msec() >= press_at, 2.0)
		var hp: float = my_hp.get_current()
		var p0: int = parried_by.size()
		combat.set_block(true)
		await get_tree().create_timer(0.05).timeout
		combat.set_block(false)
		await _until(func() -> bool: return parried_by.size() > p0, 1.5)
		if parried_by.size() > p0 and parried_by[parried_by.size() - 1] == foe.entity_id:
			parried_ok = is_equal_approx(my_hp.get_current(), hp) or my_hp.get_current() >= hp
			# STAGGERED, IT STANDS DAZED (Luke, 2026-11-01: "keep them in one spot and dazed animation for the
			# length"): it does not move, and holds the dazed sway.
			var fst: StatusComponent = foe.find_component(StatusComponent) as StatusComponent
			var fdrv: AnimationDriverComponent = foe.find_component(AnimationDriverComponent) as AnimationDriverComponent
			var at0: Vector3 = foe.global_position
			var dazed: bool = false
			for i: int in 12:
				await get_tree().physics_frame
				dazed = dazed or (fdrv != null and String(fdrv.pose_clip()) == "extra/Zombie_Idle" and fdrv.pose_weight() > 0.3)
			var moved: float = Vector2(foe.global_position.x - at0.x, foe.global_position.z - at0.z).length()
			if fst != null and fst.status() == 103:
				_check(moved < 0.1 and dazed, "the parried skeleton stands rooted (moved %.2f m) and dazed (%s)" % [moved, fdrv.pose_clip() if fdrv != null else &"?"])
			# THE RIPOSTE: a tap at once, at the staggered skeleton. A sweep hits the first body in its path, so
			# it is read off whichever skeleton it landed on (2026-11-01: once the one beside the parried one).
			var before: Dictionary[int, float] = {}
			for id: int in foes:
				var h: SpaceTimeHealthComponent = foes[id].find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
				before[id] = h.get_current() if h != null else 0.0
			var drop: Callable = func() -> float:
				var most: float = 0.0
				for id: int in foes:
					var h: SpaceTimeHealthComponent = foes[id].find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
					if h != null:
						most = maxf(most, float(before[id]) - h.get_current())
				return most
			var chop: AbilityDef = combat.kit.light[0]
			riposte_want = snappedf(chop.damage * float(combat.weapon.weapon_damage_pct) / 100.0 * HotRules.number(&"regents.riposte_damage_pct") / 100.0, 0.01)
			_face(foe)
			var step: int = combat.next_light_step(Time.get_ticks_msec())
			await _click(0.03)
			await _until(func() -> bool: return float(drop.call()) > 0.01, 2.0)
			riposte_dealt = snappedf(float(drop.call()), 0.01)
			_check(step == 0, "after the parry the tap is the riposte: the string's first step (%d)" % step)
		await get_tree().create_timer(0.8).timeout
	_check(parried_ok, "a guard pressed 60 ms before a light lands as seen PARRIES it: no damage, the skeleton staggered by us (%d tries)" % tries)
	_check(is_equal_approx(riposte_dealt, riposte_want), "the riposte at once: the chop at %d%%: %.2f (%.2f)" % [int(HotRules.number(&"regents.riposte_damage_pct")), riposte_want, riposte_dealt])


## THE GUARD FACES FORWARD: the block held, turned away from the nearest skeleton, a light comes through in
## full (COMBAT_OVERHAUL.md §4: a hit from behind takes full damage).
func _blocked_from_behind(my_hp: SpaceTimeHealthComponent) -> void:
	var whole: Array[float] = []
	for f: FoeDef in FoeDef.all():
		for a: AbilityDef in f.kit.light:
			if not f.kit.unblockable.has(a):
				whole.append(snappedf(a.damage * float(f.damage_pct) / 100.0, 0.01))
	var drops: Array[float] = []
	var last: float = my_hp.get_current()
	var until: int = Time.get_ticks_msec() + 12000
	combat.set_block(true)
	while Time.get_ticks_msec() < until and my_hp.get_current() > 25.0 and not drops.any(func(d: float) -> bool: return whole.has(d)):
		await get_tree().process_frame
		_face_nearest_foe()
		input.set_look(input.get_look_yaw() + PI, 0.0)   # the back to it
		if not combat.blocking:
			combat.set_block(true)
		var now_hp: float = my_hp.get_current()
		if now_hp < last - 0.01:
			drops.append(snappedf(last - now_hp, 0.01))
		last = now_hp
	combat.set_block(false)
	_check(drops.any(func(d: float) -> bool: return whole.has(d)),
		"blocking with the back to them: a light comes through in full (one of %s): hits taken %s" % [str(whole), str(drops)])


## ROLES BY THE HANDLE, PLAYED (COMBAT_OVERHAUL.md §5, Luke 2026-11-01): three Fine iron swords from the shell; two
## RE-HILTED at the workbench through its window (a crossguard hilt, a banner hilt: the badge and the line on what
## each does); then each wielded and its string played at the dummy: its last hit the one its handle gives,
## predicted here (clip, lock) and fired by the server; the pommel bash's longer stagger; the crossguard's FULL
## guard against the camp; the rallying cut's heal, landing on a skeleton.
func _roles(dummy: int, dh: SpaceTimeHealthComponent) -> void:
	print("GRANT_SWORDS %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(IRON_SWORD) == 3 and inv.count(CROSSGUARD) == 1 and inv.count(BANNER) == 1, 20.0)
	_check(inv.count(IRON_SWORD) == 3 and inv.count(CROSSGUARD) == 1 and inv.count(BANNER) == 1, "the shell gave three Fine iron swords, a crossguard hilt and a banner hilt")
	var swords: Array[int] = []
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == IRON_SWORD:
			swords.append(s.id)
	swords.sort()
	# RE-HILT at the workbench, through its window: the refit entry, the hilt picked (its badge, its words), REFIT.
	combat.wield(-1)
	combat.set_target(-1)
	var bench: int = -1
	for id: int in EntityRegistry.all_entity_ids():
		var sc: StationComponent = SkillingComponent.station_of(id)
		if sc != null and sc.key == &"workbench":
			bench = id
	_check(bench > 0, "the camp's workbench")
	var bench_at: Vector3 = (EntityRegistry.get_entity(bench) as Node3D).global_position
	await _stand_at(bench_at + Vector3(0, 0.05, 1.5), bench_at)
	for pair: Array in [[swords[1], CROSSGUARD, "pommel bash"], [swords[2], BANNER, "rallying cut"]]:
		var row: int = pair[0]
		hud.station_window.show_station(bench)
		await _until(func() -> bool: return hud.station_window.is_open(), 2.0)
		var w: RegentsStationWindow = hud.station_window
		var idx: int = -1
		for i: int in w.choices.size():
			if int(w.choices[i].get("refit", -1)) == row:
				idx = i
		w.pick(idx)
		await get_tree().process_frame
		w.pick_part(0, int(pair[1]))
		await get_tree().process_frame
		# No traits (the copper rivets offer Thirsting, which heals and takes healing): the numbers below are the role's.
		if idx >= 0:
			var c: Dictionary = w.choices[idx]
			for t: TraitDef in skilling.refit_traits(row, c["made_by"], String(c["data"])):
				w.want_trait(t.id, false)
			await get_tree().process_frame
		var list: OptionButton = w.find_child("Part_0", true, false) as OptionButton
		_check(idx >= 0 and list != null and list.item_count == 9 and list.get_item_icon(0) != null and w.role_line().contains(String(pair[2]))
			and not w.role_line().to_lower().contains("finisher"), "the workbench refits sword %d: its handle list badged, the hilt picked says \"%s\"" % [row, w.role_line()])
		var go: Button = w.find_child("Refit", true, false) as Button
		if go != null and not go.disabled:
			go.pressed.emit()
		await _until(func() -> bool: return _data_of(row).contains("\"p\":[%d" % int(pair[1])) and inv.count(int(pair[1])) == 0, 5.0)
		_check(_data_of(row).contains("\"p\":[%d" % int(pair[1])) and inv.count(int(pair[1])) == 0, "re-hilted: its parts %s; the hilt used up" % _data_of(row))
		w.close()
		await get_tree().create_timer(0.3).timeout
	# EACH HANDLE'S LAST HIT, at the dummy.
	var act: SpaceTimeActionComponent = me.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	var driver: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
	var dst: StatusComponent = (EntityRegistry.get_entity(dummy) as SpaceTimeEntity).find_component(StatusComponent) as StatusComponent
	var sword_kit: KitDef = KitDef.by_key(&"sword")
	for case: Array in [[swords[0], 40003, &"extra/Sword_Light_C", 26.0, 100], [swords[1], 40022, &"extra/Melee_Hook", 14.0, 150],
			[swords[2], 40023, &"cuts/Sword_Light_D_Cut", 14.0, 100]]:
		var row: int = case[0]
		var want: int = case[1]
		combat.wield(row)
		await _until(func() -> bool: return combat.weapon_row == row and combat.kit != null, 5.0)
		var role: RoleDef = combat.role()
		var last: AbilityDef = sword_kit.finisher_for(role)
		await _until(func() -> bool: return hud._skillbar.text.contains(last.display_name), 2.0)
		_check(hud._skillbar.text.contains("Slash - Slash (second) - %s" % last.display_name) and hud._skillbar.text.contains("hold for " + role.guard_words.get_slice(":", 0))
			and not hud._skillbar.text.to_lower().contains("finisher"), "wielded, the key line: \"%s\"" % hud._skillbar.text)
		await _stand_at(DUMMY_1 + Vector3(0, 0.05, 1.4), DUMMY_1)
		combat.set_target(dummy)
		await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)
		var mine: Array[int] = []
		var theirs: Array[int] = []
		var on_swung: Callable = func(id: int) -> void: mine.append(id)
		var on_resolved: Callable = func(id: int, _pid: int, _outcome: int, _target: int) -> void: theirs.append(id)
		combat.swung.connect(on_swung)
		act.action_resolved.connect(on_resolved)
		var rank: int = skilling.rank_in(sword_kit.skill)
		var clip: StringName = &""
		var staggered_ms: int = -1
		var bar_text: String = ""
		var hp_before_last: float = 0.0
		for step: int in 3:
			if step == 2:
				hp_before_last = dh.get_current()
			await _click(0.04)
			var deadline: int = Time.get_ticks_msec() + 1200
			while Time.get_ticks_msec() < deadline:
				await get_tree().physics_frame
				if step == 2 and driver.action_playing() and String(driver.action_clip()) == String(case[2]):
					clip = driver.action_clip()
				if step == 2 and dst != null and dst.status() == 103 and staggered_ms < 0:
					staggered_ms = dst._lasts_ms
					var bar: Label = hud._target_statuses.get_node_or_null(^"Status_0/Text") as Label
					bar_text = bar.text if bar != null else ""
			if step < 2:
				await _until(func() -> bool: return not combat.swinging(Time.get_ticks_msec()) or Time.get_ticks_msec() >= combat.swing_hit_ms + sword_kit.follow_for(step), 1.0)
		await _until(func() -> bool: return theirs.size() >= 3, 3.0)
		await _until(func() -> bool: return dst != null and dst.status() == 103, 1.0)
		if staggered_ms < 0 and dst != null and dst.status() == 103:
			staggered_ms = dst._lasts_ms
		combat.swung.disconnect(on_swung)
		act.action_resolved.disconnect(on_resolved)
		var name: String = last.display_name
		_check(mine.size() == 3 and mine[2] == want and combat.lock_for(last) == sword_kit.lock_ms(last), "%s: this client predicted its last hit (%s), and its lock (%d ms)" % [name, str(mine), sword_kit.lock_ms(last)])
		_check(theirs.size() >= 3 and theirs[theirs.size() - 1] == want, "%s: the server fired the same (%s)" % [name, str(theirs)])
		_check(clip == StringName(case[2]), "%s plays its own clip (%s)" % [name, clip])
		var dealt: float = snappedf(hp_before_last - dh.get_current(), 0.01)
		var expect: float = snappedf(float(case[3]) * 1.13 * (1.0 + float(mini(3 * (rank - 1), 27)) / 100.0), 0.01)
		_check(is_equal_approx(dealt, expect), "%s hit the dummy for %.2f (%.0f at Fine quality 650: %.2f)" % [name, dealt, float(case[3]), expect])
		var stagger_want: int = roundi(HotRules.number(&"regents.stagger_ms") * float(case[4]) / 100.0)
		_check(staggered_ms == stagger_want, "%s staggered the dummy %d ms (want %d)" % [name, staggered_ms, stagger_want])
		_check(bar_text.begins_with("Staggered") and absf(bar_text.get_slice("  ", 1).to_float() - float(stagger_want) / 1000.0) < 0.35,
			"%s: under the dummy's health its stagger shows, draining (\"%s\")" % [name, bar_text])
		await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)
	# THE BAG: each sword wears its handle's badge.
	hud.toggle_bag()
	await get_tree().process_frame
	var badges: int = 0
	for row: int in swords:
		var slot: UiSlot = hud.bag_window.find_child("Slot_%d" % row, true, false) as UiSlot
		badges += 1 if slot != null and slot.find_child("RoleBadge", false, false) != null else 0
	_check(badges == 3, "in the bag, each sword wears its handle's badge (%d of 3)" % badges)
	hud.toggle_bag()
	combat.set_target(-1)
	# THE CROSSGUARD'S FULL GUARD against the camp: a light comes through at `block_damage_pct`.
	var my_hp: SpaceTimeHealthComponent = me.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	await _heal(my_hp)
	combat.wield(swords[1])
	await _until(func() -> bool: return combat.weapon_row == swords[1], 5.0)
	await _stand_at(Vector3(33.0, 0.05, 3.0), Vector3(33.0, 0.0, -1.0))
	await _blocking_the_camp(me, my_hp, HotRules.number(&"regents.block_damage_pct"))
	await _heal(my_hp)
	# THE RALLYING CUT: hurt, it lands on a skeleton and heals you 8 (nobody near: all of it).
	combat.wield(swords[2])
	await _until(func() -> bool: return combat.weapon_row == swords[2], 5.0)
	print("HURT %d" % me.entity_id)
	await _until(func() -> bool: return my_hp.get_current() < my_hp.get_max() - 20.0, 6.0)
	# Each health update as it arrives (a heal and a skeleton's hit in one frame hid the +8 from a per-frame look,
	# 2026-11-01): the rises among them.
	var rises: Array[float] = []
	var on_health: Callable = func(_current: float, _most: float, delta: float) -> void:
		if delta > 0.01:
			rises.append(snappedf(delta, 0.01))
	my_hp.health_changed.connect(on_health)
	var landed: bool = false
	var until: int = Time.get_ticks_msec() + 45000
	var heals_asked: int = 0
	combat.set_block(false)
	# The camp's three keep you hurt (and staggered): the string is mashed whenever you can act; worn low, the
	# shell's HEAL sets you whole (a big rise, never 8), and their hits bring you down again.
	while Time.get_ticks_msec() < until and not landed:
		var foe: SpaceTimeEntity = _nearest_foe()
		if foe == null:
			break
		if my_hp.get_current() < 35.0 and heals_asked < 6:
			heals_asked += 1
			print("HEAL %d" % me.entity_id)
			await _until(func() -> bool: return my_hp.get_current() > 60.0, 4.0)
			continue   # the foe found before the wait may be gone (slain, its body freed): find one again
		_face(foe)
		if combat.can_act() and foe.global_position.distance_to(me.global_position) < FoeDef.by_kind(103).reach_m + 0.4:
			await _click(0.04)
		for i: int in 6:
			await get_tree().physics_frame
		landed = rises.any(func(r: float) -> bool: return is_equal_approx(r, 8.0))
	my_hp.health_changed.disconnect(on_health)
	_check(landed, "the rallying cut landed on a skeleton and healed you 8, all of it with nobody near (rises %s)" % str(rises))
	combat.set_target(-1)
	await _heal(my_hp)
	await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))


## The bag row `row`'s `instance_data` ("" for none).
func _data_of(row: int) -> String:
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.id == row:
			return s.instance_data
	return ""


## The nearest foe, or null.
func _nearest_foe() -> SpaceTimeEntity:
	var best: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and FoeDef.by_kind(e.definition.kind) != null \
				and (best == null or e.global_position.distance_to(me.global_position) < best.global_position.distance_to(me.global_position)):
			best = e
	return best


## Whole again (the shell's HEAL: an authority's negative damage), between the camp's phases.
## Between the camp's phases: whole again, and, if the camp slew you in the last one (three skeletons can, 2026-11-02),
## up at the spawn and back by `home`, where the phases expect you.
func _back_at_camp(my_hp: SpaceTimeHealthComponent, home: Vector3) -> void:
	if my_hp.is_dead():
		print("   (the camp slew you: up at the spawn, and back)")
		await _until(func() -> bool: return not my_hp.is_dead(), 12.0)
		await _stand_at(home + Vector3(0, 0.05, 2.4), home)
	await _heal(my_hp)


func _heal(my_hp: SpaceTimeHealthComponent) -> void:
	print("HEAL %d" % me.entity_id)
	await _until(func() -> bool: return my_hp.get_current() >= my_hp.get_max() - 0.01, 6.0)


## Look (and so face, in stance) at `foe`, its target.
func _face(foe: SpaceTimeEntity) -> void:
	combat.set_target(foe.entity_id)
	var to_it: Vector3 = foe.global_position - me.global_position
	input.set_look(atan2(-to_it.x, -to_it.z), 0.0)


## Face the nearest foe (the guard stops only a hit in front).
func _face_nearest_foe() -> void:
	var best: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and FoeDef.by_kind(e.definition.kind) != null \
				and (best == null or e.global_position.distance_to(me.global_position) < best.global_position.distance_to(me.global_position)):
			best = e
	if best != null:
		_face(best)


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
