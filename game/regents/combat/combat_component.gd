class_name CombatComponent extends SpaceTimeComponent
## A PLAYER'S COMBAT (owner, 2026-10-19: hybrid action combat; the weapon is the kit). On the local
## player it reads the keys and asks the server; on everyone it holds what they wield (the `wielded` row)
## and their block. It never decides a hit: swings are the foundation's abilities, which the world's
## referee judges along the way the body faces, and the server says what a hit does (`game/regents.rs`).
##
##   LMB tap    the kit's light combo: each tap the next step, inside its `combo_window_ms`
##   LMB hold   its heavy (fires once held `heavy_hold_ms`)
##   RMB hold   block (raised inside `regents.parry_ms` of a hit: a parry)
##   Ctrl       the dodge roll (the foundation's `dash` action; slow-walk moves to Alt): the dash moves you
##              at once, predicted here; the Dodge roll ability's Rolling status means nothing hits you
##   Q E R F    the kit's skills, unlocked at its mastery ranks (1, 3, 6, 9): IN STANCE only, else E
##              works what is in front of you and Q picks at a station as before
##   Tab        the next target in front of you: a ring under it, its health at the top. For reference,
##              not aim: a swing hits what it sweeps.
##   Esc        drops the target
## STANCE: a target picked, or a swing in the last `stance_s`: the body faces where the camera looks.
##
## A DRAWN KIT (the bow, owner 2026-10-20): LMB held DRAWS (the server's Drawing status: a walk), the arms
## drawing then aiming (an upper-body pose, so the legs keep walking); let go LOOSES an arrow: at the Tab
## target (the server aims it and rolls the hit), else where the camera looks. RMB lets the draw go; a
## roll does too. Every client draws another player's draw from their Drawing status.
##
## THE SWING'S TIMELINE (owner, 2026-10-19), the same here as on the server (`game/regents.rs`): a swing
## lands at its wind-up and holds you for its clip's length (`KitDef.lock_ms`). A press while it holds you
## is QUEUED (the latest wins; it lapses after the combo's window) and fires the moment it may: the combo's
## next light step from just after the hit (`chain_ms`), anything else once the lock is over. From the
## start to just after the hit the swing is COMMITTED: you walk, facing the aim (the server's Swinging
## status bounds the same), and its animation plays on whatever the legs do (the hit lands whatever they
## do); in the recovery you move freely and moving cuts the swing's tail. No swing starts in the air: a
## press there waits for the ground (the queue), as the server refuses one. A ROLL in the
## wind-up cancels the swing (it never lands), in the recovery ends it. THE ROLL plays its Roll whole, facing
## the way it goes, and nothing swings until it is over (`regents.roll_ms`): a press waits for it, as in the air. A heavy hit in a light's wind-up
## FLINCHES you (the server cancels it; the Flinched status shows here and clears the queue).

const TABLE_WIELDED: StringName = &"wielded"
const TABLE_STATE: StringName = &"combat_state"
## A foe this player slew, and what they got (`game/regents.rs`, `foe_kill`).
const TABLE_KILL: StringName = &"foe_kill"
## The roll: the foundation's dash action (the client predicts its movement), on Ctrl.
const ACTION_DODGE: StringName = &"dash"
const ACTION_SLOW: StringName = &"move_slow"
const FACING: StringName = &"regents_combat"
const SKILL_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R, KEY_F]
## The dodge roll (`content/ability/dodge.tres`): everyone's, wielding or not.
const DODGE_ID: int = 40010
## The Flinched, Swinging and Drawing statuses (`content/status/`).
const STATUS_FLINCHED: int = 105
const STATUS_SWINGING: int = 104
const STATUS_DRAWING: int = 107
## A drawn kit's poses and shot (`anim/adventurer.tres`).
const POSE_DRAW: StringName = &"pose.bow_draw"
const POSE_AIM: StringName = &"pose.bow_aim"
## The shortest draw a release looses (shorter: the draw is let go).
const MIN_DRAW_MS: int = 120
## How long after a swing lands it is still committed (the server's `regents.swing_hold_ms`).
const COMMIT_AFTER_HIT_MS: int = 80

## The ability use asked of the server: (ability id, target) -> the predicted id. Tests replace it.
signal swung(ability_id: int)
## The target changed (-1: none).
signal target_changed(target_id: int)
## This player slew foe `foe_id` and got `loot` (`item:qty,...`; "" for nothing).
signal slew(foe_id: int, loot: String)
## A key was refused here, and why (the server's refusals come back as revokes).
signal refused(why: String)

## How far Tab looks, and how wide in front (degrees, the whole arc).
@export var target_range_m: float = 25.0
@export var target_arc_deg: float = 120.0
## How long after the last swing the stance holds with no target.
@export var stance_s: float = 5.0

## What this player wields: the item, its kit, its bag row (0 / null / -1: nothing).
var weapon: ItemDef = null
var kit: KitDef = null
var weapon_row: int = -1
## Their block, from the server's row.
var blocking: bool = false
## The local player's target (an entity id), or -1.
var target_id: int = -1
## The light combo as this client swung it: the step last swung, and when its lock ended (msec).
var combo_step: int = -1
var combo_ms: int = -100000
## The swing now (or last): its ability, when it began, lands and lets go (msec), and whether it was
## cancelled (a roll, a flinch).
var swing_ability: AbilityDef = null
var swing_at_ms: int = -100000
var swing_hit_ms: int = -100000
var swing_lock_ms: int = -100000
var swing_cancelled: bool = false
## The press waiting for the swing to let go: {"kind": light/heavy/skill, "slot", "at"}; {} for none.
var queued: Dictionary = {}
var _slowing: bool = false
var _last_swing_ms: int = -100000
## Until when (msec) this client's roll holds it: no swing before.
var roll_until_ms: int = -100000
var _lmb_down_ms: int = -1
var _heavy_fired: bool = false
var _rmb: bool = false
var _local_input: LocalInputComponent = null
var _action: SpaceTimeActionComponent = null
var _driver: AnimationDriverComponent = null
var _movement: SpaceTimeMovementComponent = null
var _status: StatusComponent = null
var _ring: MeshInstance3D = null
## This client's draw: when it began (msec), or -1.
var draw_started_ms: int = -1
## The arrows loosed by this client (tests).
signal loosed(target_id: int, draw_ms: int)


func required_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE, TABLE_KILL]


func optional_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE, TABLE_KILL]


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_local_input = ent.find_component(LocalInputComponent) as LocalInputComponent if ent != null else null
	_action = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent if ent != null else null
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent if ent != null else null
	_movement = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if ent != null else null
	_status = ent.find_component(StatusComponent) as StatusComponent if ent != null else null
	set_process(true)   # everyone's draw is drawn here; the keys only for our own
	# Everyone's swings and rolls play whole, here and on every other client (their starts arrive later).
	if _action != null:
		_action.action_started.connect(func(id: int, _pid: int) -> void: _began(id))
		_action.started_elsewhere.connect(_began)
	if is_local_authority:
		bind_keys()
		if _action != null:
			_action.action_revoked.connect(_on_revoked)


## The roll on Ctrl (owner, 2026-10-19: "Ctrl to roll is fine for now"): the foundation's dash action
## (it binds Q when a game has not: Q is a skill here), and slow-walk moved to Alt.
static func bind_keys() -> void:
	if not InputMap.has_action(ACTION_DODGE):
		InputMap.add_action(ACTION_DODGE)
	InputMap.action_erase_events(ACTION_DODGE)
	var ctrl: InputEventKey = InputEventKey.new()
	ctrl.physical_keycode = KEY_CTRL
	InputMap.action_add_event(ACTION_DODGE, ctrl)
	if InputMap.has_action(ACTION_SLOW):
		for e: InputEvent in InputMap.action_get_events(ACTION_SLOW):
			var k: InputEventKey = e as InputEventKey
			if k != null and (k.physical_keycode == KEY_CTRL or k.keycode == KEY_CTRL):
				InputMap.action_erase_event(ACTION_SLOW, e)
		var alt: InputEventKey = InputEventKey.new()
		alt.physical_keycode = KEY_ALT
		if not InputMap.action_has_event(ACTION_SLOW, alt):
			InputMap.action_add_event(ACTION_SLOW, alt)


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_WIELDED:
			weapon = ItemDef.by_id(int(new.get(&"item_id"))) if new != null else null
			kit = KitDef.by_key(StringName(String(new.get(&"kit")))) if new != null else null
			weapon_row = int(new.get(&"item_row")) if new != null else -1
		TABLE_STATE:
			blocking = new != null and bool(new.get(&"blocking"))
		TABLE_KILL:
			if new != null and old == null and is_local_authority:
				slew.emit(int(new.get(&"foe_id")), String(new.get(&"loot")))


## Whether Q E R F are skills now: a weapon wielded, and a target picked or a swing just now.
func in_stance() -> bool:
	if kit == null:
		return false
	return target_id >= 0 or Time.get_ticks_msec() - _last_swing_ms < int(stance_s * 1000.0)


## The light step a tap now swings: the next after the last, until the window after its lock, else the first.
func next_light_step(now_ms: int) -> int:
	if kit == null or kit.light.is_empty():
		return -1
	if combo_step >= 0 and combo_step + 1 < kit.light.size() and now_ms - combo_ms <= kit.combo_window_ms:
		return combo_step + 1
	return 0


## Whether a swing holds us at `now_ms` (between its start and its lock, not cancelled).
func swinging(now_ms: int) -> bool:
	return swing_ability != null and not swing_cancelled and now_ms < swing_lock_ms


## Whether ability `a` (a light step `step`, -1 for anything else) may start at `now_ms`: on the ground,
## the swing before it lets go (the combo's next step from just after its hit), and its cooldown is over.
func may_start(a: AbilityDef, step: int, now_ms: int) -> bool:
	if a == null or kit == null or not grounded() or now_ms < roll_until_ms:
		return false
	if swinging(now_ms):
		var chain: bool = step > 0 and step == combo_step + 1
		var from: int = mini(swing_hit_ms + kit.chain_ms, swing_lock_ms) if chain else swing_lock_ms
		if now_ms < from:
			return false
	return _action == null or _action.cooldown_remaining_sec(a.id) <= 0.0


## Whether the body is on the ground (as this client moves it): no swing starts in the air.
func grounded() -> bool:
	if _movement == null:
		return true
	var s: MovementState = _movement.get_predicted_state() if is_local_authority else _movement.get_render_state()
	return s == null or s.grounded


## Swing ability `a` now, aimed where the camera looks, its timeline begun: the predicted id, or -1.
func swing(a: AbilityDef, step: int = -1) -> int:
	if a == null or _action == null:
		return -1
	var now: int = Time.get_ticks_msec()
	_last_swing_ms = now
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var pid: int = _action.request_use(a.id, 0, Vector3(-sin(yaw), 0.0, -cos(yaw)))
	if pid < 0:
		return -1
	swing_ability = a
	swing_at_ms = now
	swing_hit_ms = now + a.wind_up_ms
	swing_lock_ms = now + (kit.lock_ms(a) if kit != null else a.wind_up_ms)
	swing_cancelled = false
	combo_step = step
	combo_ms = swing_lock_ms
	swung.emit(a.id)
	return pid


## A press: `kind` "light", "heavy" or "skill" (`slot` 0 Q .. 3 F). It swings now when it may, else it is
## queued (the latest press wins) and swings the moment it may. True when it swung now.
func press(kind: String, slot: int = 0) -> bool:
	if kit == null:
		return false
	if kind == "skill":
		if slot >= kit.skills.size():
			refused.emit("No skill on that key yet")
			return false
		var sk: SkillingComponent = (entity as SpaceTimeEntity).find_component(SkillingComponent) as SkillingComponent
		if (sk.rank_in(kit.skill) if sk != null else 1) < kit.rank_for(slot):
			refused.emit("%s needs %s rank %d" % [kit.skills[slot].display_name, kit.skill.display_name, kit.rank_for(slot)])
			return false
	if _try(kind, slot):
		queued = {}
		return true
	queued = {"kind": kind, "slot": slot, "at": Time.get_ticks_msec()}
	return false


func _try(kind: String, slot: int) -> bool:
	var now: int = Time.get_ticks_msec()
	match kind:
		"light":
			var step: int = next_light_step(now)
			return step >= 0 and may_start(kit.light[step], step, now) and swing(kit.light[step], step) >= 0
		"heavy":
			return kit.heavy != null and may_start(kit.heavy, -1, now) and swing(kit.heavy) >= 0
		"skill":
			return slot < kit.skills.size() and may_start(kit.skills[slot], -1, now) and swing(kit.skills[slot]) >= 0
	return false


## A light tap; the heavy; a skill key (each queued when it may not swing yet).
func light() -> bool:
	return press("light")


func heavy() -> bool:
	return press("heavy")


func skill(slot: int) -> bool:
	return press("skill", slot)


## Ctrl: the dodge roll, the way you are moving. In a swing's wind-up it cancels the swing (it never
## lands); in its recovery it ends it; the queue and the combo are over. The body DASHES only when the roll
## is taken (owner, 2026-10-19: "it dashes forward instead of rolling"): Ctrl itself presses no dash.
func dodge() -> int:
	if _action == null:
		return -1
	var pid: int = _action.request_use(DODGE_ID, 0, Vector3.ZERO)
	if pid < 0:
		return -1
	if _local_input != null:
		_local_input.dash_once()
	draw_started_ms = -1   # the server's Rolling ends the Drawing too
	var now: int = Time.get_ticks_msec()
	if swinging(now):
		swing_cancelled = now < swing_hit_ms
		swing_lock_ms = now
	roll_until_ms = now + int(HotRules.number(&"regents.roll_ms"))
	queued = {}
	combo_step = -1
	return pid


## An ability began on this entity (predicted here, or another player's arriving): a swing's animation plays
## on to just after it lands however the body moves (the hit lands regardless); the roll plays its Roll whole,
## the model facing the way the roll goes.
func _began(ability_id: int) -> void:
	if _driver == null:
		return
	if ability_id == DODGE_ID:
		var roll_s: float = _driver.shot_seconds(StringName("ability.%d" % DODGE_ID))
		_driver.commit_action(roll_s)
		_driver.face_motion(roll_s)
		return
	# A foe wields nothing: its swing is whichever kit has it.
	for k: KitDef in ([kit] if kit != null else KitDef.all()):
		for a: AbilityDef in k.abilities():
			if a.id == ability_id:
				_driver.commit_action(float(a.wind_up_ms + COMMIT_AFTER_HIT_MS) / 1000.0)
				return


## The swing is over early (a roll, a flinch, a refusal): its animation is no longer committed.
func _let_go() -> void:
	if _driver != null:
		_driver.commit_action(0.0)


## The server refused a use: a swing it refused never began (its timeline is undone).
func _on_revoked(ability_id: int, _predicted_id: int, why: String) -> void:
	if swing_ability != null and swing_ability.id == ability_id and swinging(Time.get_ticks_msec()):
		swing_lock_ms = Time.get_ticks_msec()
		swing_cancelled = true
		combo_step = -1
		_let_go()
	refused.emit(why)


## Raise or lower the block (the server's say: its row comes back).
func set_block(on: bool) -> ReducerRequest:
	_rmb = on
	return SpaceTimeSync.call_reducer(&"block", [on], ["bool"])


## Wield bag row `row` (a weapon), or put it away (-1).
func wield(row: int) -> ReducerRequest:
	if row < 0:
		return SpaceTimeSync.call_reducer(&"unwield", [], [])
	return SpaceTimeSync.call_reducer(&"wield", [row], ["u64"])


## Whether the mouse is ours (as the foundation's attack key asks: a game that captures it, captured).
func _mouse_ours() -> bool:
	return _local_input == null or not _local_input.capture_mouse or MouseCapture.is_captured()


func _can_fight() -> bool:
	return kit != null and (_local_input == null or not _local_input.is_held_still()) and _mouse_ours()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_authority or not is_bound():
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and _can_fight() and kit.draws:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				begin_draw()
			else:
				loose()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			let_draw_go()
		return
	if mb != null and _can_fight():
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down_ms = Time.get_ticks_msec()
				_heavy_fired = false
			elif _lmb_down_ms >= 0:
				if not _heavy_fired:
					light()
				_lmb_down_ms = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed != _rmb:
			set_block(mb.pressed)
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.is_action_pressed(ACTION_DODGE) and _mouse_ours() and (_local_input == null or not _local_input.is_held_still()):
		dodge()
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_TAB:
		next_target()
		get_viewport().set_input_as_handled()
	elif in_stance() and _can_fight():
		var slot: int = SKILL_KEYS.find(k.physical_keycode)
		if slot >= 0:
			skill(slot)
			get_viewport().set_input_as_handled()


## Esc with a target drops the target first (the menu opens on the next), before the menu hears it.
func _input(event: InputEvent) -> void:
	if not is_local_authority or target_id < 0:
		return
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		set_target(-1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_bound():
		return
	_draw_pose()
	if not is_local_authority:
		return
	var now: int = Time.get_ticks_msec()
	if _lmb_down_ms >= 0 and not _heavy_fired and kit != null and now - _lmb_down_ms >= kit.heavy_hold_ms:
		_heavy_fired = true
		heavy()
	# Flinched by the server: the swing is over, and so is what was queued.
	var st: StatusComponent = _status
	if st != null and st.status() == STATUS_FLINCHED and swinging(now):
		swing_cancelled = true
		swing_lock_ms = now
		queued = {}
		combo_step = -1
		_let_go()
	# The queue: fire when it may, or let it lapse.
	if not queued.is_empty() and kit != null:
		if now - int(queued["at"]) > kit.combo_window_ms:
			queued = {}
		elif _try(String(queued["kind"]), int(queued["slot"])):
			queued = {}
	# THE COMMITTED SWING: walk from its start until just after it lands. Slow-walk until the server's
	# Swinging status arrives, which then bounds the run to the same walk (both at once would crawl).
	var commit: bool = (swing_ability != null and not swing_cancelled and now < swing_hit_ms + COMMIT_AFTER_HIT_MS \
		and (st == null or st.status() != STATUS_SWINGING)) or (drawing() and (st == null or st.status() != STATUS_DRAWING))
	if commit != _slowing:
		_slowing = commit
		if commit:
			Input.action_press(ACTION_SLOW)
		else:
			Input.action_release(ACTION_SLOW)
	if _rmb and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and DisplayServer.get_name() != "headless":
		set_block(false)
	if target_id >= 0 and not _target_ok(target_id):
		set_target(-1)
	if _local_input != null:
		_local_input.hold_facing(FACING, in_stance() or drawing())
		# Ctrl is the roll's, which dashes when it is taken (`dodge`): the key never dashes on its own.
		_local_input.dash_key = false
	_place_ring()


# --- a drawn kit: the bow (owner, 2026-10-20) ---------------------------------------------------------

## Whether this client is drawing.
func drawing() -> bool:
	return draw_started_ms >= 0


## How far this client's draw is, 0..1 (full at the kit's `draw_full_ms`).
func draw_progress() -> float:
	if not drawing() or kit == null:
		return 0.0
	return clampf(float(Time.get_ticks_msec() - draw_started_ms) / float(maxi(kit.draw_full_ms, 1)), 0.0, 1.0)


## LMB down with a bow: the draw begins (the server's Drawing: you walk). Not in the air, mid-roll or with
## no arrows (the server says so).
func begin_draw() -> bool:
	if kit == null or not kit.draws or drawing() or not grounded() or Time.get_ticks_msec() < roll_until_ms:
		return false
	if ammo_count() <= 0:
		refused.emit("No arrows")
		return false
	draw_started_ms = Time.get_ticks_msec()
	_last_swing_ms = draw_started_ms
	SpaceTimeSync.call_reducer(&"draw_bow", [true], ["bool"])
	return true


## LMB up: loose at the Tab target (the server aims and rolls the hit), else where the camera looks. Too
## quick a release lets the draw go instead.
func loose() -> bool:
	if not drawing():
		return false
	var held: int = Time.get_ticks_msec() - draw_started_ms
	draw_started_ms = -1
	if held < MIN_DRAW_MS:
		SpaceTimeSync.call_reducer(&"draw_bow", [false], ["bool"])
		return false
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var pitch: float = _local_input.get_look_pitch() if _local_input != null else 0.0
	var aim := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var at: int = target_id if target_id >= 0 and _target_ok(target_id) else 0
	SpaceTimeSync.call_reducer(&"loose_arrow", [at, aim], ["u64", "vector3[f32,f32,f32]"])
	if _driver != null and kit != null and not kit.light.is_empty():
		_driver.play_upper(StringName("ability.%d" % kit.light[0].id))
	_last_swing_ms = Time.get_ticks_msec()
	loosed.emit(at, held)
	return true


## RMB (or a roll): the draw is let go, nothing loosed.
func let_draw_go() -> void:
	if not drawing():
		return
	draw_started_ms = -1
	SpaceTimeSync.call_reducer(&"draw_bow", [false], ["bool"])


## The chance an arrow loosed now at the Tab target hits (%), as the server rolls it (its hot rules); -1
## with no target in the bow's range (it flies where you aim).
func hit_chance_now() -> float:
	if target_id < 0 or not _target_ok(target_id):
		return -1.0
	var me: Node3D = entity as Node3D
	var t: Node3D = EntityRegistry.get_entity(target_id) as Node3D
	var d: float = Vector2(t.global_position.x - me.global_position.x, t.global_position.z - me.global_position.z).length()
	if d > HotRules.number(&"regents.bow_range_m"):
		return -1.0
	var near_m: float = HotRules.number(&"regents.hit_near_m")
	var far_m: float = HotRules.number(&"regents.hit_far_m")
	var k: float = clampf((d - near_m) / maxf(far_m - near_m, 0.01), 0.0, 1.0)
	var near_pct: float = HotRules.number(&"regents.hit_near_pct")
	var chance: float = near_pct + (HotRules.number(&"regents.hit_far_pct") - near_pct) * k
	var mv: SpaceTimeMovementComponent = (t as SpaceTimeEntity).find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if t is SpaceTimeEntity else null
	var st: MovementState = mv.get_render_state() if mv != null else null
	if st != null and Vector2(st.vel.x, st.vel.z).length() > 1.5:
		chance -= HotRules.number(&"regents.hit_moving_pct")
	return clampf(chance, 0.0, 100.0)


## Arrows in the bag for the kit wielded.
func ammo_count() -> int:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var inv: SpaceTimeInventoryComponent = ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent if ent != null else null
	if inv == null or kit == null:
		return 0
	var n: int = 0
	for st: SpaceTimeInventoryComponent.Stack in inv.items():
		var it: ItemDef = ItemDef.by_id(st.item_def_id)
		if it != null and it.ammo_for == kit.key:
			n += st.qty
	return n


## THE DRAW, SHOWN on this player's arms (an upper-body pose: the legs keep walking): drawing back over the
## draw, then held aimed. Ours from our own press; another player's from their Drawing status.
func _draw_pose() -> void:
	if _driver == null:
		return
	var t: float = -1.0
	if is_local_authority and drawing():
		t = draw_progress()
	elif not is_local_authority and _status != null and _status.status() == STATUS_DRAWING and kit != null:
		t = clampf(_status.elapsed_sec() * 1000.0 / float(maxi(kit.draw_full_ms, 1)), 0.0, 1.0)
	if t < 0.0:
		_driver.release_upper_pose()
	elif t < 1.0:
		_driver.hold_upper_pose(POSE_DRAW, 1.0, t)
	else:
		_driver.hold_upper_pose(POSE_AIM, 1.0)


## Pick `id` as the target (-1: none).
func set_target(id: int) -> void:
	if id == target_id:
		return
	target_id = id
	target_changed.emit(id)


## The candidates Tab steps through: alive, with health, not us, within range in front of the camera,
## nearest the crosshair first.
func targets() -> Array[int]:
	var me: Node3D = entity as Node3D
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var scored: Array[Vector2] = []
	for id: int in EntityRegistry.all_entity_ids():
		if id == entity_id or not _target_ok(id):
			continue
		var n: Node3D = EntityRegistry.get_entity(id) as Node3D
		var to: Vector3 = n.global_position - me.global_position
		to.y = 0.0
		var d: float = to.length()
		if d > target_range_m or d < 0.01:
			continue
		var ang: float = rad_to_deg(fwd.angle_to(to / d))
		if ang > target_arc_deg * 0.5:
			continue
		scored.append(Vector2(ang + d, float(id)))
	scored.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[int] = []
	for v: Vector2 in scored:
		out.append(int(v.y))
	return out


## Tab: the next target after the one we have (the best first).
func next_target() -> int:
	var list: Array[int] = targets()
	if list.is_empty():
		set_target(-1)
		refused.emit("Nothing to target in front of you")
		return -1
	var at: int = list.find(target_id)
	set_target(list[(at + 1) % list.size()] if at >= 0 else list[0])
	return target_id


## Someone we may target: an entity with health, alive, not a player (no duels yet).
func _target_ok(id: int) -> bool:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	if ent == null or not is_instance_valid(ent) or ent.find_component(SkillingComponent) != null:
		return false
	var h: SpaceTimeHealthComponent = ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	return h != null and not h.is_dead()


func _place_ring() -> void:
	if target_id < 0 or not is_local_authority:
		if _ring != null:
			_ring.visible = false
		return
	var t: Node3D = EntityRegistry.get_entity(target_id) as Node3D
	if t == null:
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.68
		torus.rings = 48
		_ring.mesh = torus
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.78, 0.25, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.top_level = true
		add_child(_ring)
	_ring.visible = true
	_ring.global_position = t.global_position + Vector3(0, 0.04, 0)
	_ring.scale = Vector3(1.0, 0.15, 1.0)


func _exit_tree() -> void:
	if _local_input != null and is_instance_valid(_local_input):
		_local_input.hold_facing(FACING, false)
