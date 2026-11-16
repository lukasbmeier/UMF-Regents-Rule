extends Node
## COMBAT, PLAYED (game/regents/tests/combat_playtest.sh starts this beside the world's real referee): a
## real client through the latency simulator, at the frontier camp's training dummy, through the real
## keys, clicks and the bag panel. Wields the copper axe (the bag's button), Tabs onto the dummy (the
## ring, the target frame), taps the string (a chop, then the overhead, its finisher, which staggers; each
## judged by the referee; the numbers float up; axemanship XP), waits for the dummy to be whole, rolls (Ctrl:
## further than a run in the same time), blocks (no swing behind it); at the skeleton camp PARRIES a light it
## saw (and fails one pressed too early), ripostes, blocks the rest; ROLES: re-hilts two swords at the workbench
## and plays each handle's last hit (COMBAT_OVERHAUL.md §5); THE LAB'S LOOKS (PROGRESS 82): the swings wore the
## crescent, the parries flashed, a staff's Fireball and Blink show theirs; and lets the target go (Esc). Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 840.0
## A hit dealt at once shows this soon after its blow lands as seen: the referee's settle (80 ms), its frame, ours.
const AT_ONCE_MS: int = 220
## The camp's guide and the yard's sparring skeleton (the glade's `guide` and `sparring_1` points).
const GUIDE: Vector3 = Vector3(5.0, 0.0, 22.5)
const SPARRING: Vector3 = Vector3(13.5, 0.0, 24.5)
const SPARRING_KIND: int = 105
const DUMMY_1: Vector3 = Vector3(7.0, 0.0, 20.0)
## The camp's second dummy (`continent.json` dummy_2), 2.7 m from the first: one Cleave can reach both.
const DUMMY_2: Vector3 = Vector3(9.5, 0.0, 21.0)
const AXE: int = 40001
const AXEMANSHIP: int = 40007
const DUMMY_KIND: int = 102
const BOW: int = 40020
const ARROWS: int = 40022
const IRON_SWORD: int = 40019
const CROSSGUARD: int = 40040
const BANNER: int = 40041
const STAFF: int = 40023

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
	await _until(func() -> bool: return _bar_text() != "", 3.0)
	_check(combat.kit == null and hud.ability_bar.visible and _bar_text().contains("No weapon"), "nothing wielded: the ability bar's weapon says so (\"%s\")" % _bar_text())

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
	await _until(func() -> bool: return combat.weapon != null and _bar_text().contains("Left click: Chop"), 2.0)
	_check(_bar_text().contains("Copper axe") and _bar_text().contains("Left click: Chop") and _bar_text().contains("Q Cleave"),
		"the ability bar: \"%s\"" % _bar_text())

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
	await _cleave_both(dummy, dh)

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
	var held_aloft: bool = combat.roll_until_ms == rolled_before and combat._roll != null and combat._roll.asked_ms >= 0   # the foundation's air hold
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

	# --- A SET ROLL (Luke, 2026-11-11: "if I roll forward but then press s it goes a short distance") ---
	# Running north, Ctrl, then at once S for the rest of it: as far as the same roll with W held, and the server
	# corrects none of it (the frames are a player's own).
	await get_tree().create_timer(1.6).timeout
	var roll_w: Vector2 = await _roll_for(false)
	await get_tree().create_timer(1.7).timeout
	var roll_s_key: Vector2 = await _roll_for(true)
	_check(roll_w.x > 3.0 and absf(roll_w.x - roll_s_key.x) < 0.5 and roll_w.y + roll_s_key.y == 0.0,
		"a roll goes a set length: %.2f m with W held, %.2f m with S pressed as it begins; the server corrected none of it (%d)" % [roll_w.x, roll_s_key.x, int(roll_w.y + roll_s_key.y)])

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
	var camp: Vector3 = Vector3(33.0, 0.0, -1.0)
	var foe_ent: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind == 103 \
				and (foe_ent == null or e.global_position.distance_to(camp) < foe_ent.global_position.distance_to(camp)):
			foe_ent = e
	# IT SEES IN FRONT (Luke's F9, 2026-11-13): 7 m off where it faces NOW (it notices at 10), never behind it. A rock
	# or a tree may stand in that line, or it may turn on its next wander step as we arrive: then where it stood and
	# faced is printed, and we stand in front of it again (a try is a fresh reading of where it faces).
	var stood_at: Vector3 = foe_ent.global_position if foe_ent != null else camp
	if foe_ent != null:
		for attempt: int in 4:
			var yaw: float = foe_ent.body.rotation.y if foe_ent.body != null else 0.0
			var at_it: Vector3 = foe_ent.global_position
			stood_at = at_it
			var front: Vector3 = at_it + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 7.0
			await _stand_at(Vector3(front.x, at_it.y + 0.05, front.z), at_it)
			await _until(func() -> bool: return foe_ent.global_position.distance_to(me.global_position) < 4.5, 4.0)
			if foe_ent.global_position.distance_to(me.global_position) < 4.5:
				break
			print("   (in front of it, unnoticed: it at %s facing %.2f, we at %s, %.1f m; again)" % [str(at_it), yaw, str(me.global_position), foe_ent.global_position.distance_to(me.global_position)])
	else:
		await _stand_at(Vector3(33.0, 0.05, 8.0), camp)
	_check(foe_ent != null, "a skeleton warrior at the camp")
	if foe_ent != null:
		var home: Vector3 = stood_at   # where it stood as we came, before it moved (its point is within its wander)
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
		await _armor_in_the_camp(my_hp, home)
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
		# Home is its point; where it stood when we came is within its wander of that (F10, 2026-11-13).
		var home_m: float = FoeDef.by_kind(103).wander_m + 2.0
		await _until(func() -> bool: return foe_ent.global_position.distance_to(home) < home_m, 20.0)
		_check(foe_ent.global_position.distance_to(home) < home_m, "out of its reach, it walked home (%.1f m from where it stood as we came; its point is within its %.0f m wander of there)" % [foe_ent.global_position.distance_to(home), FoeDef.by_kind(103).wander_m])
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
	_check(combat.kit != null and combat.kit.key == &"bow" and _bar_text().contains("Hold left click: draw"), "wielded: the bar says draw and loose (\"%s\")" % _bar_text())
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 10.0), DUMMY_1)
	combat.set_target(dummy)
	await get_tree().create_timer(0.3).timeout
	_check(_bar_text().contains("to hit"), "with the dummy targeted it says the chance to hit, beside the arrows (\"%s\")" % _bar_text())
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
	# Free aim: no target, the crosshair put on the dummy (Luke, 2026-11-11: a free shot goes TO THE CROSSHAIR; the
	# camera is over the right shoulder, so looking straight at the dummy leaves the crosshair beside it).
	combat.set_target(-1)
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 10.0), DUMMY_1)
	var straight: Vector3 = combat.crosshair_point()
	var beside: bool = not combat.crosshair_on_body
	var on_it: bool = await _crosshair_onto(dummy)
	_check(on_it, "the look turned a little puts the crosshair on the dummy (looking straight at it, it was %s: %s)" % ["beside it" if beside else "on it", straight])
	var before_free: float = dh.get_current()
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.9).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _until(func() -> bool: return dh.get_current() < before_free, 4.0)
	_check(dh.get_current() < before_free, "no target: the arrow flew to the crosshair and hit the dummy it was on (%.1f -> %.1f)" % [before_free, dh.get_current()])
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
	await _lab_looks(dummy)

	# --- LET THE TARGET GO ---
	await _key(KEY_ESCAPE)
	await _until(func() -> bool: return combat.target_id == -1, 1.0)
	_check(combat.target_id == -1 and not hud._target_box.visible and not combat._ring.visible, "Esc: no target, no ring, no frame")
	_finish()


## THE LAB'S LOOKS IN THE FIGHT (PROGRESS 82; Luke, 2026-11-14: "lets use the vfx in all the current abilites"): the
## swings this run made wore the crescent, the parries flashed at the hand; a staff's Fireball shows its charge in the
## hand, flies as the lab's fireball (riding on its body) and bursts in its blast where it ends; Blink's jump, made by
## the server, shows its columns at both ends.
func _lab_looks(dummy: int) -> void:
	print("LAB_LOOKS")
	var trail: SwingTrail = me.find_component(SwingTrail) as SwingTrail
	_check(trail != null and trail.crescent and is_instance_valid(trail.trail) and trail.trail.look is ShaderMaterial and is_instance_valid(trail.edge_trail),
		"the swings wore the crescent: the cut's look on the sheet, a bright line along the tip")
	var vfx: AbilityVfx = me.find_component(AbilityVfx) as AbilityVfx
	_check(vfx != null and vfx.played.has("parry_flash:-1"), "our parries flashed at the hand (%s)" % (str(vfx.played) if vfx != null else "no AbilityVfx"))
	if vfx == null:
		return
	print("GRANT_STAFF %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(STAFF) == 1, 20.0)
	var row: int = -1
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == STAFF:
			row = s.id
	combat.wield(row)
	await _until(func() -> bool: return combat.kit != null and combat.kit.casts(), 5.0)
	_check(combat.kit != null and combat.kit.casts(), "the shell gave a staff, and it is wielded")
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 8.0), DUMMY_1)
	combat.set_target(dummy)
	await get_tree().create_timer(0.4).timeout
	var fireball: AbilityDef = combat.on_slot(0)
	var before: float = ((EntityRegistry.get_entity(dummy) as SpaceTimeEntity).find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent).get_current()
	combat.cast(fireball)
	await _until(func() -> bool: return is_instance_valid(vfx.charge), 1.0)
	_check(fireball != null and is_instance_valid(vfx.charge) and vfx.charge is VfxFireCharge and vfx.played.has("fire_charge:%d" % fireball.id),
		"Fireball: its charge in the hand as it is cast")
	var rode: bool = false
	var blast: bool = false
	var until_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until_ms and not blast:
		await get_tree().process_frame
		for n: Node in get_tree().root.find_children("*", "VfxFireMissile", true, false):
			rode = rode or (n as VfxFireMissile).rides
		blast = not get_tree().root.find_children("*", "VfxFireBlast", true, false).is_empty()
	var after: float = ((EntityRegistry.get_entity(dummy) as SpaceTimeEntity).find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent).get_current()
	_check(rode and blast and after < before, "it flew as the lab's fireball and burst in its blast where it hit the dummy (%.0f -> %.0f)" % [before, after])
	_check(not is_instance_valid(vfx.charge) or (vfx.charge as Node).is_queued_for_deletion(), "the charge went as the cast ended")
	# Blink, turned away from the dummy: the server moves us, this client sees the jump and shows it.
	await get_tree().create_timer(1.2).timeout
	combat.set_target(-1)
	input.set_look(PI, 0.0)
	await get_tree().create_timer(0.3).timeout
	var blink: AbilityDef = ContentLibrary.find(&"ability", (ContentLibrary.find(&"spell", 40004) as SpellDef).ability.id) as AbilityDef
	var from: Vector3 = me.global_position
	var shown: int = vfx.played.size()
	combat.cast(blink)
	await _until(func() -> bool: return vfx.played.size() > shown and vfx.played[-1] == "blink:%d" % blink.id, 3.0)
	var moved: float = Vector2(me.global_position.x - from.x, me.global_position.z - from.z).length()
	_check(vfx.played.size() > shown and vfx.played[-1] == "blink:%d" % blink.id and moved > 3.0,
		"Blink: the server moved us %.1f m, and its columns showed at both ends (after the cast)" % moved)
	if moved <= 3.0:
		var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		var auth: Variant = mv.get(&"_auth")
		print("BLINK_DEBUG from=%s now=%s row=%s epoch=%s kit=%s casting=%s status=%d played=%s" % [from, me.global_position,
			(auth as MovementState).pos if auth != null else "-", mv.get(&"_epoch"), combat.kit.key if combat.kit != null else &"none",
			combat.casting(), (me.find_component(StatusComponent) as StatusComponent).status(), vfx.played])
	combat.wield(-1)
	await get_tree().create_timer(0.5).timeout


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
		if f.kit == null:
			continue   # a creature that never fights (the deer) swings nothing
		for a: AbilityDef in f.kit.light:
			var d: float = snappedf(a.damage * float(f.damage_pct) / 100.0, 0.01)
			if f.kit.unblockable.has(a):
				whole.append(d)
			else:
				blocked.append(snappedf(d * block, 0.01))
	combat.set_block(true)
	await _until(func() -> bool: return combat.blocking, 3.0)
	# WHEN EACH FOE'S BLOW LANDS, AS THIS CLIENT SHOWS IT (its swing seen starting, plus its wind-up): how long
	# after it the health drops is the lag Luke felt ("I think I dodged ... .5 or .8 seconds later to get hit").
	var lands_ms: Array[int] = []
	var watching: Array = []
	for f: HitFeedbackComponent in feeds:
		var foe_act: SpaceTimeActionComponent = (f.entity as SpaceTimeEntity).find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
		if foe_act == null:
			continue
		var on_swing: Callable = func(ability_id: int) -> void:
			var swung: AbilityDef = ContentLibrary.find(&"ability", ability_id) as AbilityDef
			if swung != null and swung.judged:
				lands_ms.append(Time.get_ticks_msec() + swung.wind_up_ms)
		foe_act.started_elsewhere.connect(on_swing)
		watching.append([foe_act, on_swing])
	var lags: Array[int] = []
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
			var landed: int = -1
			for l: int in lands_ms:
				if l <= Time.get_ticks_msec() + 30 and l > landed:
					landed = l   # the latest blow that had landed by now, as seen
			if landed >= 0:
				lags.append(Time.get_ticks_msec() - landed)
		last = now_hp
		if now_hp < 50.0 and heals_asked < 6:
			heals_asked += 1
			print("HEAL %d" % me.entity_id)
			await _until(func() -> bool: return my_hp.get_current() > 60.0, 4.0)
			last = my_hp.get_current()
	combat.set_block(false)
	for w: Array in watching:
		if is_instance_valid(w[0]):
			(w[0] as SpaceTimeActionComponent).started_elsewhere.disconnect(w[1] as Callable)
	# A HIT SHOWS AS SOON AS THIS LINE ALLOWS (2026-11-11): it waits for a parry press still on its way only as long
	# as THIS client's delay needs (told to the server, `report_seen_delay`), not the most any line may (320 ms).
	lags.sort()
	var seen: int = CombatComponent.seen_delay_ms()
	var wait_ms: int = int(HotRules.number(&"regents.parry_late_ms")) + 2 * maxi(combat.seen_delay_told, 0) + int(HotRules.number(&"regents.hit_hold_slack_ms"))
	var old_wait: int = int(HotRules.number(&"regents.parry_late_ms")) + int(HotRules.number(&"foundation.rewind_max_ms")) + int(HotRules.number(&"foundation.press_credit_cap_ms"))
	var median: int = lags[lags.size() / 2] if not lags.is_empty() else -1
	print("HIT LAG: %d hits, shown %s ms after their blow landed as seen (median %d); this line's wait %d ms (swings shown %d ms late), the old wait %d ms"
		% [lags.size(), str(lags), median, wait_ms, seen, old_wait])
	_check(combat.seen_delay_told >= 0 and absi(combat.seen_delay_told - seen) <= 25, "the server was told how late this client shows a swing (%d ms; now %d)" % [combat.seen_delay_told, seen])
	_check(lags.size() >= 2 and median >= 0 and median <= wait_ms + 80,
		"a hit shows %d ms after its blow lands (median of %d), inside this line's wait of %d ms and a frame or two" % [median, lags.size(), wait_ms])
	if wait_ms + 60 < old_wait:
		_check(median < old_wait, "sooner than the %d ms every hit waited before" % old_wait)
	# DEALT AT ONCE (Luke, 2026-11-12): a hit that does not stagger or kill is dealt as the referee judges it, whatever
	# the ping (a parry or a roll arriving after takes it back); only the finishers still wait. So most hits show
	# within the referee's own 80 ms and a frame or two of the blow landing, far inside this line's wait.
	var at_once: int = lags.filter(func(l: int) -> bool: return l <= AT_ONCE_MS).size()
	_check(at_once >= 2 and at_once * 2 >= lags.size(),
		"dealt at once: %d of %d hits showed within %d ms of their blow landing (this line's wait is %d ms); the rest are the finishers, which wait" % [at_once, lags.size(), AT_ONCE_MS, wait_ms])
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
	# Since hits are dealt at once (2026-11-12) a finisher still WAITS (this line's wait) while the light after it
	# does not: the two can show closer together than they landed by that wait, never closer.
	_check(at_ms.size() >= 2 and least >= gap - 100 - wait_ms, "%d hits held up against them, never two together: the least gap %d ms (the rule %d; a waiting finisher and a light dealt at once show up to %d ms closer)" % [at_ms.size(), least, gap, wait_ms])


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
	# A TRY IS ONE LIGHT ALONE (2026-11-13): with the camp's three taking turns, another's hit already on its way (a
	# finisher, 14.00, measured as the light's) is not this light's; such a try is not made, and worn low you are
	# healed rather than the leg given up, as the parry's below.
	var early_skipped: int = 0
	while not early_ok and tries < 4 and early_skipped < 8:
		if my_hp.get_current() < 60.0:
			await _heal(my_hp)
		tries += 1
		var n: int = seen.size()
		await _until(func() -> bool: return seen.size() > n and light_of.call(int(seen[seen.size() - 1]["ability"])) != null, 10.0)
		if seen.size() <= n:
			break
		var swing: Dictionary = seen[seen.size() - 1]
		var a: AbilityDef = light_of.call(int(swing["ability"]))
		var foe: SpaceTimeEntity = foes[int(swing["foe"])]
		if _other_hit_due(seen, int(swing["foe"]), int(swing["at"]) + a.wind_up_ms + 300):
			tries -= 1
			early_skipped += 1
			print("   (another foe's hit lands before or with this light: not this try)")
			await get_tree().create_timer(0.8).timeout
			continue
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
	var my_feed: HitFeedbackComponent = me.find_component(HitFeedbackComponent) as HitFeedbackComponent
	var took_back_before: int = my_feed.taken_back if my_feed != null else 0
	var took_back_after: int = took_back_before
	var riposte_dealt: float = -1.0
	var riposte_want: float = 0.0
	tries = 0
	# A TRY IS A PRESS THE SERVER COULD JUDGE (2026-11-13): with two skeletons on you, the other's finisher often has you
	# Staggered as the press is due, and a staggered player cannot guard ("you cannot while staggered"): the game's
	# rule, not a missed parry. Such a press is not made and the try is not spent; and worn low you are healed rather
	# than the leg given up (a quiet run lost both its tries to staggers and stopped at 22 health).
	var my_status: StatusComponent = me.find_component(StatusComponent) as StatusComponent
	var skipped: int = 0
	while not parried_ok and tries < 6 and skipped < 8:
		if my_hp.get_current() < 60.0:
			await _heal(my_hp)
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
		if my_status != null and not my_status.can_act():
			tries -= 1
			skipped += 1
			print("   (a press due while we could not act (status %d): not made, not counted)" % my_status.status())
			await get_tree().create_timer(0.8).timeout
			continue
		var hp: float = my_hp.get_current()
		var p0: int = parried_by.size()
		combat.set_block(true)
		await get_tree().create_timer(0.05).timeout
		combat.set_block(false)
		await _until(func() -> bool: return parried_by.size() > p0, 1.5)
		if parried_by.size() > p0 and parried_by[parried_by.size() - 1] == foe.entity_id:
			parried_ok = is_equal_approx(my_hp.get_current(), hp) or my_hp.get_current() >= hp
			took_back_after = (me.find_component(HitFeedbackComponent) as HitFeedbackComponent).taken_back
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
			# Mastery counts (1-33, PROGRESS 73: the axe reaches rank 2 at 15 XP, inside this test).
			var axe_bonus: float = 1.0 + float(SkillDef.mastery_bp(skilling.rank_in(combat.kit.skill))) / 10000.0
			riposte_want = snappedf(chop.damage * float(combat.weapon.weapon_damage_pct) / 100.0 * HotRules.number(&"regents.riposte_damage_pct") / 100.0 * axe_bonus, 0.01)
			_face(foe)
			var step: int = combat.next_light_step(Time.get_ticks_msec())
			await _click(0.03)
			# Another foe's hit may flinch or stagger us mid-riposte (2026-11-13: three take turns on us): the game's
			# rule, not a lost riposte. Such a riposte is not counted, and the parry is tried again.
			var cut: Array[bool] = [false]
			await _until(func() -> bool:
				cut[0] = cut[0] or (my_status != null and (my_status.status() == 105 or my_status.status() == 103))
				return float(drop.call()) > 0.01, 2.0)
			riposte_dealt = snappedf(float(drop.call()), 0.01)
			_check(step == 0, "after the parry the tap is the riposte: the string's first step (%d)" % step)
			if riposte_dealt < 0.01 and cut[0]:
				print("   (our riposte was flinched by another foe's hit: not counted, the parry tried again)")
				parried_ok = false
				tries -= 1
				skipped += 1
		await get_tree().create_timer(0.8).timeout
	_check(parried_ok, "a guard pressed 60 ms before a light lands as seen PARRIES it: no damage, the skeleton staggered by us (%d tries, %d skipped while staggered)" % [tries, skipped])
	# At this round trip that press ARRIVES after the hit was judged and dealt: the hit was taken back (the health
	# straight back, no heal's number). On a quick line the press arrives first and nothing is ever dealt.
	print("TAKEN BACK: %d hit(s) dealt at once and taken back by the parry (swings shown %d ms late)" % [took_back_after - took_back_before, CombatComponent.seen_delay_ms()])
	if CombatComponent.seen_delay_ms() >= 60:
		_check(took_back_after > took_back_before, "the parried hit had been dealt at once and was TAKEN BACK (%d): the press arrived after it, and still counted" % (took_back_after - took_back_before))
	_check(is_equal_approx(riposte_dealt, riposte_want), "the riposte at once: the chop at %d%%: %.2f (%.2f)" % [int(HotRules.number(&"regents.riposte_damage_pct")), riposte_want, riposte_dealt])


## Whether a swing seen from a foe other than `foe_id` lands (as seen: its start plus its wind-up) between now and
## `by_ms`: a hit that would be measured in place of the one a leg watches.
func _other_hit_due(seen: Array[Dictionary], foe_id: int, by_ms: int) -> bool:
	var now: int = Time.get_ticks_msec()
	for s: Dictionary in seen:
		if int(s["foe"]) == foe_id:
			continue
		var a: AbilityDef = ContentLibrary.find(&"ability", int(s["ability"])) as AbilityDef
		var lands: int = int(s["at"]) + (a.wind_up_ms if a != null else 0)
		if lands >= now - 50 and lands <= by_ms:
			return true
	return false


## THE GUARD FACES FORWARD: the block held, turned away from the nearest skeleton, a light comes through in
## full (COMBAT_OVERHAUL.md §4: a hit from behind takes full damage).
## ARMOR (S2 the core, S3 the pieces; ARMOR_PREP.md A1, A6, A7): the shell gives two real pieces of the material table,
## an iron cuirass (Defense 5 x 2 = 10) and a copper armet of quality 1000 (2 x 1, a fifth more: 2.4); they are put on out
## of the fight, the server's `worn` row comes back to this client (others draw it from the same row), and every hit the
## camp lands is its foe's hit x K / (K + 12.4), never the whole of it. Then they come off again.
func _armor_in_the_camp(my_hp: SpaceTimeHealthComponent, home: Vector3) -> void:
	var cuirass: ItemDef = ItemDef.by_id(40075)
	var armet: ItemDef = ItemDef.by_id(40070)
	_check(cuirass != null and cuirass.armor_slot == &"chest" and cuirass.defense == 10 and armet != null and armet.armor_slot == &"head" and armet.defense == 2,
		"the pieces are the table's: an iron cuirass (chest, 10) and a copper armet (head, 2)")
	print("GRANT_ARMOR %d %d %d" % [me.entity_id, 40075, 40070])
	var row_of := func(item: int) -> int:
		for st: SpaceTimeInventoryComponent.Stack in inv.items():
			if st.item_def_id == item:
				return st.id
		return -1
	await _until(func() -> bool: return int(row_of.call(40075)) > 0 and int(row_of.call(40070)) > 0, 8.0)
	_check(int(row_of.call(40075)) > 0 and int(row_of.call(40070)) > 0, "the shell gave an iron cuirass and a copper armet")
	# Away from the camp, then out of the fight (`regents.regen_delay_s` after the last hurt): wearing waits for that.
	await _stand_at(home + Vector3(0, 0.05, 40.0), home)
	var worn_on := func(slot: String) -> int:
		var r: RefCounted = SpaceTimeSync.get_row(&"worn", me.entity_id)
		return int(r.get(StringName(slot + "_item"))) if r != null else 0
	var refusals: Array[String] = []
	for piece: int in [40075, 40070]:
		var until_ms: int = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < until_ms:
			var req: ReducerRequest = SpaceTimeSync.call_reducer(&"wear", [int(row_of.call(piece))], ["u64"])
			await _until(func() -> bool: return not req.is_pending(), 3.0)
			if req.is_ok():
				break
			refusals.append(req.error_message)
			await get_tree().create_timer(1.0).timeout
	await _until(func() -> bool: return int(worn_on.call("chest")) == 40075 and int(worn_on.call("head")) == 40070, 3.0)
	_check(int(worn_on.call("chest")) == 40075 and int(worn_on.call("head")) == 40070,
		"worn out of the fight, and the server's worn row came back: the cuirass on the chest, the armet on the head%s"
			% ((" (refused first while in the fight: %s)" % refusals[0]) if not refusals.is_empty() else ""))
	_check(refusals.all(func(w: String) -> bool: return w.contains("not in a fight")), "refused only while in the fight (%s)" % str(refusals))
	# The camp's hits, unblocked: each its foe's hit x K / (K + 10 + 2 x 1.2).
	var k: float = HotRules.number(&"regents.defense_k")
	var keep: float = k / (k + 10.0 + 2.0 * 1.2)
	var whole: Array[float] = []
	var kept: Array[float] = []
	for f: FoeDef in FoeDef.all():
		if f.kit == null:
			continue
		for a: AbilityDef in f.kit.light:
			whole.append(snappedf(a.damage * float(f.damage_pct) / 100.0, 0.01))
			kept.append(snappedf(a.damage * float(f.damage_pct) / 100.0 * keep, 0.01))
	await _heal(my_hp)
	await _stand_at(home + Vector3(0, 0.05, 2.4), home)
	var drops: Array[float] = []
	var last: float = my_hp.get_current()
	var until: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until and my_hp.get_current() > 25.0 and drops.size() < 2:
		await get_tree().process_frame
		_face_nearest_foe()
		var now_hp: float = my_hp.get_current()
		if now_hp < last - 0.01:
			drops.append(snappedf(last - now_hp, 0.01))
		last = now_hp
	var near := func(d: float, among: Array[float]) -> bool: return among.any(func(x: float) -> bool: return absf(x - d) <= 0.02)
	_check(not drops.is_empty() and drops.all(func(d: float) -> bool: return near.call(d, kept)),
		"in the armor every hit lands at its foe's hit x %.0f / (%.0f + 12.4) (one of %s): hits taken %s" % [k, k, str(kept), str(drops)])
	_check(not drops.is_empty() and not drops.any(func(d: float) -> bool: return near.call(d, whole)),
		"NEGATIVE: none lands whole (%s): hits taken %s" % [str(whole), str(drops)])
	# Off again, out of the fight.
	await _stand_at(home + Vector3(0, 0.05, 40.0), home)
	for slot: String in ["chest", "head"]:
		var until_ms: int = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < until_ms:
			var req: ReducerRequest = SpaceTimeSync.call_reducer(&"take_off", [slot], ["string"])
			await _until(func() -> bool: return not req.is_pending(), 3.0)
			if req.is_ok():
				break
			await get_tree().create_timer(1.0).timeout
	await _until(func() -> bool: return int(worn_on.call("chest")) == 0 and int(worn_on.call("head")) == 0, 3.0)
	_check(int(worn_on.call("chest")) == 0 and int(worn_on.call("head")) == 0, "taken off: nothing worn")
	await _stand_at(home + Vector3(0, 0.05, 2.4), home)   # back where the camp's phases stand, for what follows


func _blocked_from_behind(my_hp: SpaceTimeHealthComponent) -> void:
	var whole: Array[float] = []
	for f: FoeDef in FoeDef.all():
		if f.kit == null:
			continue   # a creature that never fights (the deer) swings nothing
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
		await _until(func() -> bool: return _bar_text().contains(last.display_name), 2.0)
		_check(_bar_text().contains("Slash - Slash (second) - %s" % last.display_name) and _bar_text().contains("hold for " + role.guard_words.get_slice(":", 0))
			and not _bar_text().to_lower().contains("finisher"), "wielded, the weapon's moves: \"%s\"" % _bar_text())
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
				rank = skilling.rank_in(sword_kit.skill)   # the first two hits' XP may have raised it (1-33: finer steps)
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
		var expect: float = snappedf(float(case[3]) * 1.13 * (1.0 + float(SkillDef.mastery_bp(rank)) / 10000.0), 0.01)
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
## Whether entity kind `kind` is one of the camp's MELEE foes. The camp's archer and imp hold their fire in this suite
## (`regents.ranged_tokens` 0) and stand a few meters off: a guard turned to the nearest of ALL foes sometimes had its
## back to the three that were hitting (2026-11-13: two runs died of it).
func _melee_foe(kind: int) -> bool:
	var f: FoeDef = FoeDef.by_kind(kind)
	return f != null and f.behavior == &"melee"


func _nearest_foe() -> SpaceTimeEntity:
	var best: SpaceTimeEntity = null
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e != null and e.definition != null and _melee_foe(e.definition.kind) \
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
		# UP FIRST, THEN BACK (2026-11-13): the health comes back a moment before the Slain status goes, and a step
		# sent in between is refused: the fighter stayed at the spawn, and every camp phase after saw nothing (four
		# checks failed of it, none of them the game's). So: wait for the status, step, and see that we arrived.
		var st: StatusComponent = me.find_component(StatusComponent) as StatusComponent
		await _until(func() -> bool: return st == null or st.status() != 106, 6.0)
		var back: Vector3 = home + Vector3(0, 0.05, 2.4)
		for i: int in 4:
			await _stand_at(back, home)
			if me.global_position.distance_to(back) < 1.0:
				break
			await get_tree().create_timer(0.5).timeout
		_check(me.global_position.distance_to(back) < 1.0, "slain by the camp, up again and back at it (%.1f m from where the phases stand)" % me.global_position.distance_to(back))
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
		if e != null and e.definition != null and _melee_foe(e.definition.kind) \
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


## Turn the look, a little at a time, until the crosshair is on entity `id` (a player putting it there). True when
## it is.
func _crosshair_onto(id: int) -> bool:
	var yaw0: float = input.get_look_yaw()
	for step: int in range(0, 41):
		for side: float in [1.0, -1.0]:
			input.set_look(yaw0 + side * deg_to_rad(0.25) * float(step), deg_to_rad(-3.0))
			await get_tree().physics_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var p: Vector3 = combat.crosshair_point()
			var t: Node3D = EntityRegistry.get_entity(id) as Node3D
			if combat.crosshair_on_body and t != null and Vector2(p.x - t.global_position.x, p.z - t.global_position.z).length() < 0.6:
				return true
	return false


## Run north, roll (Ctrl), and say how far the body went in the roll's length (x) and how many times the server
## corrected it meanwhile (y); `back`: S instead of W from the moment the roll begins.
func _roll_for(back: bool) -> Vector2:
	await _stand_at(Vector3(0.0, 0.05, 9.0), Vector3(0.0, 0.0, 0.0))
	await get_tree().create_timer(0.5).timeout   # the step there is a correction of its own: let it settle
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.4).timeout   # up to speed
	var fixes: int = int(mv.get_reconcile_stats()["reconciles"])
	var from: Vector3 = me.global_position
	await _key(KEY_CTRL)
	if back:
		Input.action_release(&"move_forward")
		Input.action_press(&"move_back")
	await get_tree().create_timer(HotRules.number(&"regents.roll_ms") / 1000.0 - 0.05).timeout
	var d: float = Vector2(me.global_position.x - from.x, me.global_position.z - from.z).length()
	Input.action_release(&"move_forward")
	Input.action_release(&"move_back")
	await get_tree().create_timer(0.4).timeout
	return Vector2(d, float(int(mv.get_reconcile_stats()["reconciles"]) - fixes))


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


## AREAS THAT HIT ALL (S1, ABILITIES_PREP.md section 7 step 3): Q, Cleave, swept from beside the two dummies along the
## line between them, lands on BOTH (the referee reports every body its sweep met; each is dealt as a single hit is).
## Before, a sweep landed on its first body only. Then back where the string is played, the first dummy targeted.
func _cleave_both(dummy: int, dh: SpaceTimeHealthComponent) -> void:
	var other: int = await _dummy_at(DUMMY_2)
	_check(other > 0, "the camp's second dummy")
	if other <= 0:
		return
	var oh: SpaceTimeHealthComponent = (EntityRegistry.get_entity(other) as SpaceTimeEntity).find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	# Beside the first dummy, 0.9 m off the line to the second, a quarter metre past it: the sweep (2.2 m, 0.9 m wide)
	# passes both, the first at its start and the second at its end.
	var along: Vector3 = (DUMMY_2 - DUMMY_1).normalized()
	var side: Vector3 = Vector3(along.z, 0.0, -along.x)
	var at: Vector3 = DUMMY_1 + along * 0.25 + side * 0.9 + Vector3(0, 0.05, 0)
	combat.set_target(0)
	await _stand_at(at, at + along * 3.0)
	var a0: float = dh.get_current()
	var b0: float = oh.get_current()
	var swung: bool = combat.skill(0)
	_check(swung and combat.on_slot(0) != null and combat.on_slot(0).id == 40009, "Q: Cleave swung")
	await _until(func() -> bool: return dh.get_current() < a0 and oh.get_current() < b0, 3.0)
	_check(is_equal_approx(snappedf(a0 - dh.get_current(), 0.01), 12.6), "Cleave hit the first dummy: 18 at the copper axe's 70 %% (%.2f)" % (a0 - dh.get_current()))
	_check(is_equal_approx(snappedf(b0 - oh.get_current(), 0.01), 12.6), "and the second, in the same sweep: an area hits all in it (%.2f)" % (b0 - oh.get_current()))
	await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0) and is_equal_approx(oh.get_current(), 500.0), 8.0)
	await _stand_at(DUMMY_1 + Vector3(0, 0.05, 1.4), DUMMY_1)
	combat.set_target(dummy)
	await get_tree().create_timer(0.3).timeout


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


## What the ability bar shows, as words: the weapon's tooltip (its moves), each slot's key and name, and what is
## beside it (mana, or the arrows and the chance to hit). "" before it shows anything.
func _bar_text() -> String:
	var m: Dictionary = hud.ability_bar.model if hud != null and hud.ability_bar != null else {}
	if m.is_empty():
		return ""
	var out: String = String((m.get("weapon", {}) as Dictionary).get("tip", ""))
	for d: Dictionary in m.get("slots", []) as Array:
		out += "
%s %s" % [String(d.get("key", "")), String(d.get("name", ""))]
	return out + "
" + String((m.get("pool", {}) as Dictionary).get("text", ""))


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
