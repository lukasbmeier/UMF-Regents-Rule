extends Node
## COMBAT, PLAYED (game/regents/tests/combat_playtest.sh starts this beside the world's real referee): a
## real client through the latency simulator, at the frontier camp's training dummy, through the real
## keys, clicks and the bag panel. Wields the bronze axe (the bag's button), Tabs onto the dummy (the
## ring, the target frame), taps the light combo and holds a heavy (each judged by the referee; the
## numbers float up; axemanship XP), waits for the dummy to be whole, rolls (Ctrl: further than a run in
## the same time), blocks (no swing behind it), and lets the target go (Esc). Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 120.0
const DUMMY_1: Vector3 = Vector3(7.0, 0.0, 20.0)
const AXE: int = 40001
const AXEMANSHIP: int = 40007
const DUMMY_KIND: int = 102

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
	var button: Button = hud.bag_panel.find_child("Wield_%d" % row, true, false) as Button if hud.bag_panel != null else null
	_check(button != null and button.text == "Wield", "the bag panel has a Wield button on the bronze axe")
	if button != null:
		button.pressed.emit()
	await _until(func() -> bool: return combat.kit != null, 5.0)
	_check(combat.kit != null and combat.kit.key == &"axe" and combat.weapon.id == AXE, "wielded: it fights with the axe kit")
	await _until(func() -> bool: return _bag_button(row) == "Put away", 2.0)
	_check(_bag_button(row) == "Put away", "its button now puts it away")
	hud.toggle_bag()
	await _until(func() -> bool: return combat.weapon != null and hud._skillbar.text.contains("LMB Chop"), 2.0)
	_check(hud._skillbar.text.contains("Bronze axe") and hud._skillbar.text.contains("LMB Chop") and hud._skillbar.text.contains("Q Cleave"),
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
	await _click(0.06)
	await _until(func() -> bool: return dh.get_current() < 500.0, 3.0)
	var hit1: float = 500.0 - dh.get_current()
	_check(is_equal_approx(snappedf(hit1, 0.01), 7.7), "a tap of the left button: a chop the referee judged a hit, 11 at the bronze axe's 70 %% (%.2f)" % hit1)
	await _click(0.06)
	await _until(func() -> bool: return dh.get_current() < 500.0 - hit1 - 1.0, 3.0)
	var hit2: float = 500.0 - hit1 - dh.get_current()
	_check(is_equal_approx(snappedf(hit2, 0.01), 10.5), "a second tap inside the window: the combo's second chop, 15 (%.2f)" % hit2)
	await get_tree().create_timer(1.0).timeout
	var before_heavy: float = dh.get_current()
	await _click(0.6)
	await _until(func() -> bool: return dh.get_current() < before_heavy - 1.0, 3.0)
	_check(is_equal_approx(snappedf(before_heavy - dh.get_current(), 0.01), 22.4), "held: the overhead, 32 (%.2f)" % (before_heavy - dh.get_current()))
	_check(feed != null and feed.shown.size() >= 3 and is_equal_approx(snappedf(feed.shown[0], 0.01), 7.7), "the numbers floated up from the dummy: %s" % str(feed.shown if feed != null else []))
	await _until(func() -> bool: return int(skilling.xp.get(AXEMANSHIP, 0)) >= 9, 3.0)
	_check(int(skilling.xp.get(AXEMANSHIP, 0)) >= 9, "axemanship XP for the hits (%d)" % int(skilling.xp.get(AXEMANSHIP, 0)))
	await _until(func() -> bool: return is_equal_approx(dh.get_current(), 500.0), 8.0)
	_check(is_equal_approx(dh.get_current(), 500.0), "the dummy is whole again a few seconds on")

	# --- THE ROLL: further than a run in the same time ---
	await _stand_at(DUMMY_1 + Vector3(-6.0, 0.05, 4.0), DUMMY_1 + Vector3(-6.0, 0.0, -6.0))
	# The Rolling status comes a round trip after Ctrl, and bursts for half a second: measured over 0.7 s.
	var ran: float = await _run_for(0.7, false)
	var rolled: float = await _run_for(0.7, true)
	_check(rolled > ran + 1.0, "Ctrl while running: the roll carries %.2f m against a run's %.2f" % [rolled, ran])

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
	var b: Button = hud.bag_panel.find_child("Wield_%d" % row, true, false) as Button if hud.bag_panel != null else null
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
