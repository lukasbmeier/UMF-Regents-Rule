class_name CombatComponent extends SpaceTimeComponent
## A PLAYER'S COMBAT (owner, 2026-10-19: hybrid action combat; the weapon is the kit). On the local
## player it reads the keys and asks the server; on everyone it holds what they wield (the `wielded` row)
## and their block. It never decides a hit: swings are the foundation's abilities, which the world's
## referee judges along the way the body faces, and the server says what a hit does (`game/regents.rs`).
##
##   LMB tap    the kit's STRING: each tap the next step, inside `regents.combo_window_ms`; its last is the
##              FINISHER (COMBAT_OVERHAUL.md §3: the heavy merged in: armour, it flinches a light, it staggers),
##              the one the wielded weapon's HANDLE gives (its role, §5: `role()`, `KitDef.light_at`). The server
##              resolves the same from the bag row; this client predicts it, its clip and its lock.
##   RMB        THE GUARD (§4): the press PARRIES a hit in front landing within `regents.parry_ms` of it, as
##              you saw it (the server judges it, `guard`); held, it blocks a hit in front. A parry opens the
##              RIPOSTE: the next tap, inside `regents.riposte_ms`, is the string's first step, harder.
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
## is QUEUED (the latest wins; it lapses after the string's window) and fires the moment it may: the string's
## next step once the last one's FOLLOW-THROUGH is over (`KitDef.follow_ms`), anything else once the lock is over. From the
## start to just after the hit the swing is COMMITTED: you walk, facing the aim (the server's Swinging
## status bounds the same), and its animation plays on whatever the legs do (the hit lands whatever they
## do); in the recovery you move freely and moving cuts the swing's tail. No swing starts in the air: a
## press there waits for the ground (the queue), as the server refuses one. A ROLL in the
## wind-up cancels the swing (it never lands), in the recovery ends it. THE ROLL plays its Roll whole, facing
## the way it goes, and nothing swings until it is over (`regents.roll_ms`): a press waits for it, as in the air.
## No roll starts in the air either: Ctrl there is held and rolls on landing (within `ROLL_HOLD_MS`). A finisher in a light's wind-up
## FLINCHES you, and one that lands STAGGERS you (the server cancels the swing; the status shows here and clears the queue).
##
## A CASTING KIT (the Staff, owner 2026-10-20): its abilities are SPELLS (`SpellDef`), cast through the same
## press, queue and lock as a swing: LMB taps a Bolt, Q-F (in stance) its spells, each on its OWN cooldown
## (no global one) and paid in mana (`ResourceComponent`; the server spends it, `cast_spell`). A spell with
## a cast time shows a bar and the casting pose; a press meanwhile is held and fires when it ends. A long
## cast (0.8 s or more) roots: moving off it, or rolling, lets it go (`cancel_cast`). An area spell lands
## where the crosshair meets the ground, within its range.

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
## The Flinched, Staggered, Swinging and Drawing statuses (`content/status/`).
const STATUS_FLINCHED: int = 105
const STATUS_STAGGERED: int = 103
const STATUS_SWINGING: int = 104
const STATUS_DRAWING: int = 107
## A drawn kit's poses and shot (`anim/adventurer.tres`).
const POSE_DRAW: StringName = &"pose.bow_draw"
const POSE_AIM: StringName = &"pose.bow_aim"
## A casting kit's poses while a spell is cast (`anim/adventurer.tres`): a short cast, a long one.
const POSE_CAST: StringName = &"pose.spell_cast"
const POSE_CHANNEL: StringName = &"pose.spell_channel"
## A rooted cast is let go by moving this far off where it began (the server's `ROOTED_SLACK_M`).
const ROOTED_SLACK_M: float = 0.5
## Who is casting what (`game/regents.rs`): everyone's, for their casting pose.
const TABLE_CASTING: StringName = &"casting"
## The shortest draw a release looses (shorter: the draw is let go).
const MIN_DRAW_MS: int = 120
## How long after a swing lands it is still committed (the server's `regents.swing_hold_ms`).
const COMMIT_AFTER_HIT_MS: int = 80
## The recovery comes in this long before its strike's clip ends: the action slots' cross-fade (their 0.15 s).
const RECOVER_LEAD_S: float = 0.15

## The ability use asked of the server: (ability id, target) -> the predicted id. Tests replace it.
signal swung(ability_id: int)
## The target changed (-1: none).
signal target_changed(target_id: int)
## This player slew foe `foe_id` and got `loot` (`item:qty,...`; "" for nothing).
signal slew(foe_id: int, loot: String)
## A key was refused here, and why (the server's refusals come back as revokes).
signal refused(why: String)
## This player's guard PARRIED `attacker_id`'s swing (seen here as the attacker's stagger by us, just after a
## guard press): the riposte window is open.
signal parried(attacker_id: int)

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
## The press waiting for the swing to let go: {"kind": light/skill, "slot", "at"}; {} for none.
var queued: Dictionary = {}
var _slowing: bool = false
var _last_swing_ms: int = -100000
## Until when (msec) this client's roll holds it: no swing before.
var roll_until_ms: int = -100000
## A roll asked for in the air (Luke's playtest, 2026-10-24: "I can roll in the air, shouldn't be doable,
## queue it for when I land"): when it was asked (msec), taken on landing; -1 for none.
var roll_on_landing_ms: int = -1
## How long a roll asked for in the air waits for the ground before it lapses.
const ROLL_HOLD_MS: int = 1500
var _rmb: bool = false
## When this client last pressed its guard, and when it last saw a parry of its own land (msec; -100000: never).
var guard_pressed_ms: int = -100000
var parried_ms: int = -100000
## How long after a guard press a stagger by us is taken for its parry (the server's word arriving).
const PARRY_SEEN_MS: int = 1200
var _local_input: LocalInputComponent = null
var _action: SpaceTimeActionComponent = null
var _driver: AnimationDriverComponent = null
var _movement: SpaceTimeMovementComponent = null
var _status: StatusComponent = null
var _ring: MeshInstance3D = null
## THE TARGET'S POISE ON ITS MARKER (Luke, 2026-11-02: "lets do target marker", not a bar under its health): an arc
## just outside the ring fills round as its poise wears, hotter near the break; it bursts when it breaks, and is a
## grey ring while it is Steadied. Its material's `worn` and `steady` are what it shows (tests read them).
var poise_arc: MeshInstance3D = null
var _arc_feed: HitFeedbackComponent = null
## This client's draw: when it began (msec), or -1.
var draw_started_ms: int = -1
## The arrows loosed by this client (tests).
signal loosed(target_id: int, draw_ms: int)
## A spell this client asked the server to cast (tests).
signal cast_sent(ability_id: int, target_id: int, aim: Vector3, at: Vector3)
## This client's cast in progress: its spell, when it lands (msec), where it began; null / -1 for none.
var cast_spell: SpellDef = null
var cast_until_ms: int = -1
var cast_from: Vector3 = Vector3.ZERO
## When each spell is ready again here (ability id -> msec): its own cooldown, as the server keeps it.
var spell_ready_ms: Dictionary[int, int] = {}
## Another player's cast, from their `casting` row: its ability, or -1.
var remote_cast_ability: int = -1
## The swing's recovery to come (`_plan_recovery`): its clip in the set, the strike it follows, when (msec; -1: none).
var _recover_semantic: StringName = &""
var _recover_strike: StringName = &""
var _recover_at_ms: int = -1
## How many recoveries have played (tests).
var recoveries: int = 0


func required_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE, TABLE_KILL, TABLE_CASTING]


func optional_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE, TABLE_KILL, TABLE_CASTING]


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
		SignalBus.entity_status_changed.connect(_on_any_status)



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
		TABLE_CASTING:
			remote_cast_ability = int(new.get(&"ability")) if new != null else -1


## Whether this player is FIGHTING: a weapon wielded and a target picked. Then Q E R F are always its
## skills; otherwise E works what is in front of you first (owner, 2026-10-20: E at the workbench cast
## a skill).
func fighting() -> bool:
	return kit != null and target_id >= 0


## WHAT YOU HIT BECOMES YOUR TARGET (owner, 2026-10-20: "if I don't have an enemy highlighted but am
## attacking something, auto highlight that enemy"): an enemy your swing, arrow or spell just hurt, when
## you have no target. On the hit, not the press, so a bow or a staff with no target still aims where you
## look (free aim) and only what it lands on is picked. The target, or -1.
func target_what_you_hit(hit_id: int, source_id: int) -> int:
	if not is_local_authority or target_id >= 0 or source_id != entity_id or hit_id == entity_id or not _target_ok(hit_id):
		return target_id
	set_target(hit_id)
	return hit_id


## Whether key slot `slot` (0 Q .. 3 F) is a skill now: the kit has one there, you are in stance, and, for
## the key that also works what is in front of you (E), you are fighting or nothing is in front of you.
func skill_key_is_skill(slot: int, is_interact_key: bool) -> bool:
	if kit == null or slot < 0 or slot >= kit.skills.size() or not in_stance():
		return false
	if not is_interact_key or fighting():
		return true
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var sk: SkillingComponent = ent.find_component(SkillingComponent) as SkillingComponent if ent != null else null
	return sk == null or sk.target_now() < 0


## Whether Q E R F are skills now: a weapon wielded, and a target picked or a swing just now.
func in_stance() -> bool:
	if kit == null:
		return false
	return target_id >= 0 or Time.get_ticks_msec() - _last_swing_ms < int(stance_s * 1000.0)


## The step a tap now swings: the RIPOSTE (the first step) just after a parry; else the next after the last,
## until the window after its lock; else the first.
func next_light_step(now_ms: int) -> int:
	if kit == null or kit.light.is_empty():
		return -1
	if riposte_open(now_ms):
		return 0
	if combo_step >= 0 and combo_step + 1 < kit.light.size() and now_ms - combo_ms <= combo_window_ms():
		return combo_step + 1
	return 0


## The string's window (`regents.combo_window_ms`): a tap this long after a step's lock is still the next.
static func combo_window_ms() -> int:
	return int(HotRules.number(&"regents.combo_window_ms"))


## Whether a tap now is a RIPOSTE: a parry of ours seen within `regents.riposte_ms`, and no swing since.
func riposte_open(now_ms: int) -> bool:
	return now_ms - parried_ms <= int(HotRules.number(&"regents.riposte_ms")) and swing_at_ms < parried_ms


## Whether a swing holds us at `now_ms` (between its start and its lock, not cancelled).
func swinging(now_ms: int) -> bool:
	return swing_ability != null and not swing_cancelled and now_ms < swing_lock_ms


## Whether ability `a` (a light step `step`, -1 for anything else) may start at `now_ms`: on the ground, able
## to act (not staggered, flinched or slain: the press waits in the queue, as the server would refuse it), the
## swing before it lets go (the string's next step after its follow-through), and its cooldown is over.
func may_start(a: AbilityDef, step: int, now_ms: int) -> bool:
	if a == null or kit == null or not grounded() or not can_act() or now_ms < roll_until_ms:
		return false
	if swinging(now_ms):
		var chain: bool = step > 0 and step == combo_step + 1
		var from: int = mini(swing_hit_ms + kit.follow_for(combo_step), swing_lock_ms) if chain else swing_lock_ms
		if now_ms < from:
			return false
	return _action == null or _action.cooldown_remaining_sec(a.id) <= 0.0


## Whether this player's status lets them act (the server's `require_can_act`): a Stagger, a Flinch or
## Slain does not, and a press then waits rather than being sent to be refused (Luke's feedback 4097).
func can_act() -> bool:
	return _status == null or _status.can_act()   # its state and every effect (template #302)


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
	swing_lock_ms = now + lock_for(a)
	swing_cancelled = false
	combo_step = step
	combo_ms = swing_lock_ms
	swung.emit(a.id)
	return pid


## A press: `kind` "light" or "skill" (`slot` 0 Q .. 3 F). It swings now when it may, else it is queued (the
## latest press wins) and swings the moment it may. True when it swung now.
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
	if kit.casts():
		var a: AbilityDef = kit.light[0] if kind == "light" else (kit.skills[slot] if kind == "skill" and slot < kit.skills.size() else null)
		return a != null and may_cast(now) and cast(a)
	match kind:
		"light":
			var step: int = next_light_step(now)
			var a: AbilityDef = kit.light_at(step, role())
			return step >= 0 and may_start(a, step, now) and swing(a, step) >= 0
		"skill":
			return slot < kit.skills.size() and may_start(kit.skills[slot], -1, now) and swing(kit.skills[slot]) >= 0
	return false


## A tap of the string; a skill key (each queued when it may not swing yet).
func light() -> bool:
	return press("light")


func skill(slot: int) -> bool:
	return press("skill", slot)


## Ctrl: the dodge roll, the way you are moving. In a swing's wind-up it cancels the swing (it never
## lands); in its recovery it ends it; the queue and the combo are over. The body DASHES only when the roll
## is taken (owner, 2026-10-19: "it dashes forward instead of rolling"): Ctrl itself presses no dash.
func dodge() -> int:
	if _action == null:
		return -1
	if not grounded() or not can_act():
		roll_on_landing_ms = Time.get_ticks_msec()   # no roll in the air, nor staggered: taken once it may
		return -1
	roll_on_landing_ms = -1
	var pid: int = _action.request_use(DODGE_ID, 0, Vector3.ZERO)
	if pid < 0:
		return -1
	if _local_input != null:
		_local_input.dash_once()
	draw_started_ms = -1   # the server's Rolling ends the Drawing too
	_cast_over()   # and lets a cast go (the server ends it too)
	var now: int = Time.get_ticks_msec()
	if swinging(now):
		swing_cancelled = now < swing_hit_ms
		swing_lock_ms = now
	roll_until_ms = now + int(HotRules.number(&"regents.roll_ms"))
	queued = {}
	combo_step = -1
	return pid


## THE ROLL'S COOLDOWN (owner, 2026-10-21: "roll cooldown UI"): how long until Ctrl rolls again, and its
## whole cooldown, in seconds (the server's word as the action component holds it). (0, total) when ready.
func roll_cooldown() -> Vector2:
	if _roll_total_s < 0.0:
		var def: AbilityDef = ContentLibrary.find(&"ability", DODGE_ID) as AbilityDef
		_roll_total_s = float(def.cooldown_ms) / 1000.0 if def != null else 0.0
	return Vector2(_action.cooldown_remaining_sec(DODGE_ID) if _action != null else 0.0, _roll_total_s)


## The roll's whole cooldown (s), looked up once (-1: not yet).
var _roll_total_s: float = -1.0


## How long a swing's animation is held whatever the body does: to just after its hit; a LUNGE (it moves the
## body itself) its whole clip, or its own dash let go of it halfway (Luke's playtest, 2026-10-24: "q lunge is
## also cut off half way through"). `clip_s`: its clip's length.
static func commit_seconds(a: AbilityDef, clip_s: float) -> float:
	var to_hit: float = float(a.wind_up_ms + COMMIT_AFTER_HIT_MS) / 1000.0
	return maxf(clip_s, to_hit) if a.lunges else to_hit


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
				var strike_s: float = _driver.shot_seconds(StringName("ability.%d" % a.id))
				_driver.commit_action(commit_seconds(a, strike_s))
				_plan_recovery(a.id, strike_s)
				return


## THE SWING'S RECOVERY (Luke's feedback, 2026-11-01: "the end of the swing ... transition back to the idle/locomotion
## animation is instant ... swing -> snap back"): a swing's clip is the strike alone, and the set's `recover.<id>` (its
## clip's `_Rec`, the arm brought back) follows it, cross-faded in through the second action slot as the strike ends.
## Presentation only: the lock is still the strike's (the server's), so the pace is unchanged, and moving or the next
## swing cuts the recovery as it cut the old tail. Every body's swings (`_began`), on every client.
func _plan_recovery(ability_id: int, strike_s: float) -> void:
	_recover_semantic = StringName("recover.%d" % ability_id)
	_recover_at_ms = -1
	if _driver == null or _driver.animation_set == null or not _driver.animation_set.has_exact(_recover_semantic):
		return
	var strike: AnimationClipRef = _driver.animation_set.clip(StringName("ability.%d" % ability_id))
	_recover_strike = strike.anim_name if strike != null else &""
	_recover_at_ms = Time.get_ticks_msec() + int(maxf(strike_s - RECOVER_LEAD_S, 0.0) * 1000.0)


## The recovery, when its strike is ending: only if that strike still plays (no roll, no flinch, no next swing,
## no death took its place); a hit-stop holding the body puts it off.
func _tick_recovery(now: int) -> void:
	if _recover_at_ms < 0 or now < _recover_at_ms or _driver == null:
		return
	if _driver.held_still():
		return
	_recover_at_ms = -1
	if _driver.action_playing() and _driver.action_clip() == _recover_strike:
		_driver.play_action(_recover_semantic)
		recoveries += 1


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


## THE GUARD, pressed (`on`) or let go (the server's say: its row comes back). A press is a parry the server
## judges against the hit as this client saw it (`seen_delay_ms` sent along); held, the block.
func set_block(on: bool) -> ReducerRequest:
	_rmb = on
	if on:
		guard_pressed_ms = Time.get_ticks_msec()
		if not swinging(guard_pressed_ms):
			combo_ms = guard_pressed_ms   # a guard pauses the string's decay, as the server does
	return SpaceTimeSync.call_reducer(&"guard", [on, seen_delay_ms()], ["bool", "u32"])


## HOW LATE THIS CLIENT SHOWS ANOTHER'S SWING, in ms: its animation starts as the use arrives, half a round
## trip after the server began it (not the interpolation of their body). The server judges a parry by it.
static func seen_delay_ms() -> int:
	return maxi(0, roundi(float(ClockSync.rtt_usec()) / 2000.0))


## THE GUARD FACES FORWARD (`regents.guard_arc_deg`): whether a guard facing `yaw` (forward (-sin, -cos))
## stops a hit from an attacker at (`dx`, `dz`) from it. Twin: the server's `rules::in_guard_arc`.
static func guard_stops(yaw: float, dx: float, dz: float) -> bool:
	var length: float = sqrt(dx * dx + dz * dz)
	if length < 0.001:
		return true
	var c: float = (-sin(yaw) * dx - cos(yaw) * dz) / length
	return c >= cos(deg_to_rad(clampf(HotRules.number(&"regents.guard_arc_deg"), 0.0, 360.0) * 0.5)) - 0.000001


## Another entity's status changed: one Staggered BY US just after our guard press is our parry landing (the
## riposte window opens; the string starts over at the riposte).
func _on_any_status(id: int, _from: int, to: int) -> void:
	if to != STATUS_STAGGERED or id == entity_id:
		return
	var now: int = Time.get_ticks_msec()
	if now - guard_pressed_ms > PARRY_SEEN_MS:
		return
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	var st: StatusComponent = ent.find_component(StatusComponent) as StatusComponent if ent != null else null
	if st == null or st.by_entity() != entity_id:
		return
	parried_ms = now
	combo_step = -1
	parried.emit(id)


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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed != _rmb:
			if mb.pressed:
				let_draw_go()   # the stave parries: the draw goes in the same press (COMBAT_OVERHAUL.md §4)
			set_block(mb.pressed)
		return
	if mb != null and _can_fight():
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			light()
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
	elif _can_fight():
		var slot: int = SKILL_KEYS.find(k.physical_keycode)
		if slot >= 0 and skill_key_is_skill(slot, InputMap.has_action(&"interact") and k.is_action(&"interact")):
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
	_tick_recovery(Time.get_ticks_msec())
	if not is_local_authority:
		return
	var now: int = Time.get_ticks_msec()
	_tick_cast(now)
	# Flinched or staggered by the server: the swing is over, and so is what was queued.
	var st: StatusComponent = _status
	if st != null and (st.status() == STATUS_FLINCHED or st.status() == STATUS_STAGGERED) and swinging(now):
		swing_cancelled = true
		swing_lock_ms = now
		queued = {}
		combo_step = -1
		_let_go()
	# A roll asked for in the air: on landing, or let it lapse.
	if roll_on_landing_ms >= 0 and grounded() and can_act():
		var asked: int = roll_on_landing_ms
		roll_on_landing_ms = -1
		if now - asked <= ROLL_HOLD_MS:
			dodge()
	# The queue: fire when it may, or let it lapse.
	if not queued.is_empty() and kit != null:
		if now - int(queued["at"]) > combo_window_ms():
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
	return clampf(float(Time.get_ticks_msec() - draw_started_ms) / float(draw_full_ms()), 0.0, 1.0)


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


## THE WIELDED WEAPON'S TRAITS (template DECISIONS #275): its bag row's, for the client's twins of the
## server's numbers (a swing's recovery, the bow's draw). None for nothing wielded.
func weapon_traits() -> Array[int]:
	var data: String = weapon_data()
	return ItemDef.trait_ids(data) if weapon_row >= 0 else []


## THE WIELDED WEAPON'S ROLE (COMBAT_OVERHAUL.md §5): its handle's shape, from its bag row (`ItemDef.role_of`,
## the server's `role_of`). Null for nothing wielded, or a kit with no roles.
func role() -> RoleDef:
	return ItemDef.role_of(weapon, weapon_data()) if weapon != null else null


## The wielded weapon's bag row's `instance_data` ("" for none).
func weapon_data() -> String:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var inv: SpaceTimeInventoryComponent = ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent if ent != null else null
	if inv == null or weapon_row < 0:
		return ""
	for st: SpaceTimeInventoryComponent.Stack in inv.items():
		if st.id == weapon_row:
			return st.instance_data
	return ""


## WHAT AN ACTION IS, for traits: a step of the string "basic" (and "combo_last" for its last, the finisher),
## anything else "skill". Twin: the server's `action_tags`.
static func action_tags(k: KitDef, a: AbilityDef) -> Array:
	if k != null and k.is_finisher(a):
		return [&"basic", &"combo_last"]   # any role's last hit
	return [&"basic"] if k != null and k.light.has(a) else [&"skill"]


## A swing's lock with its recovery (the part after the wind-up) scaled by `recovery`. Twin: `lock_with`.
static func lock_with(lock_ms: int, wind_up_ms: int, recovery: float) -> int:
	return wind_up_ms + roundi(float(maxi(lock_ms - wind_up_ms, 0)) * maxf(recovery, 0.0))


## How long swinging `a` holds this player: the kit's lock, its recovery through the weapon's traits
## (Balanced faster, Heavy slower), as the server works it out.
func lock_for(a: AbilityDef) -> int:
	if kit == null:
		return a.wind_up_ms
	var traits: Array[int] = weapon_traits()
	var recovery: float = Traits.mult(traits, &"recovery", action_tags(kit, a)) if not traits.is_empty() else 1.0
	return lock_with(maxi(kit.lock_ms(a), a.wind_up_ms), a.wind_up_ms, recovery)


## The bow's full draw with its traits (Swift Draw: sooner), as the server works it out (`draw_full_with`); a
## draw begun in the riposte window fills in `regents.riposte_draw_pct` of that (the bow's riposte).
func draw_full_ms() -> int:
	if kit == null:
		return 1
	var traits: Array[int] = weapon_traits()
	var m: float = Traits.mult(traits, &"draw_time") if not traits.is_empty() else 1.0
	var full: int = maxi(roundi(float(kit.draw_full_ms) * maxf(m, 0.05)), 1)
	if drawing() and draw_started_ms >= parried_ms and draw_started_ms - parried_ms <= int(HotRules.number(&"regents.riposte_ms")):
		full = maxi(roundi(float(full) * clampf(HotRules.number(&"regents.riposte_draw_pct"), 1.0, 100.0) / 100.0), 1)
	return full


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
	# A spell being cast: the casting pose (a long cast its own), the legs free.
	var spell: SpellDef = cast_spell if is_local_authority and casting() else (SpellDef.by_ability(remote_cast_ability) if not is_local_authority and remote_cast_ability >= 0 else null)
	if spell != null:
		_driver.hold_upper_pose(POSE_CHANNEL if spell.cast_ms >= 800 else POSE_CAST, 1.0)
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


# --- a casting kit: the Staff (owner, 2026-10-20) ----------------------------------------------------

## Whether this client is casting a spell with a cast time.
func casting() -> bool:
	return cast_spell != null and cast_until_ms >= 0


## How far this client's cast is, 0..1.
func cast_progress() -> float:
	if not casting():
		return 0.0
	var cast_ms: float = float(cast_spell.cast_ms) * HotRules.number(&"regents.cast_time_pct") / 100.0
	return clampf(1.0 - float(cast_until_ms - Time.get_ticks_msec()) / maxf(cast_ms, 1.0), 0.0, 1.0)


## Whether a spell may begin now: on the ground, not rolling, no cast going and the last one's clip over.
func may_cast(now_ms: int) -> bool:
	return kit != null and grounded() and now_ms >= roll_until_ms and not casting() and not swinging(now_ms)


## Seconds until spell `a` is ready again here (0: ready).
func spell_cooldown_sec(a: AbilityDef) -> float:
	return maxf(0.0, float(int(spell_ready_ms.get(a.id, 0)) - Time.get_ticks_msec()) / 1000.0)


## A pool to use instead of the entity's (tests, with no entity).
var pool_for_tests: ResourceComponent = null


## This player's pool for the kit wielded (the Staff's mana), or null.
func pool() -> ResourceComponent:
	if pool_for_tests != null:
		return pool_for_tests
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	return ent.find_component(ResourceComponent) as ResourceComponent if ent != null else null


## CAST spell `a` now: at the Tab target, where the camera looks, an area where the crosshair meets the
## ground. Its cooldown or too little mana: refused here (consumed, not queued). True when it was cast.
func cast(a: AbilityDef) -> bool:
	var spell: SpellDef = SpellDef.by_ability(a.id)
	if spell == null or kit == null or not kit.casts():
		return false
	var now: int = Time.get_ticks_msec()
	if spell_cooldown_sec(a) > 0.0:
		refused.emit("%s: ready in %.1f s" % [a.display_name, spell_cooldown_sec(a)])
		return true
	var p: ResourceComponent = pool()
	var cost: float = spell.cost * HotRules.number(&"regents.mana_cost_pct") / 100.0
	if cost > 0.0 and (p == null or not p.can_pay(kit.resource.id, cost)):
		refused.emit("Not enough %s for %s" % [kit.resource.display_name.to_lower(), a.display_name])
		return true
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var pitch: float = _local_input.get_look_pitch() if _local_input != null else 0.0
	var aim := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var at: Vector3 = area_point(a.range_m) if spell.kind == SpellDef.Kind.AREA else Vector3.ZERO
	var at_target: int = target_id if target_id >= 0 and _target_ok(target_id) else 0
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"cast_spell", [a.id, at_target, aim, at],
		["u32", "u64", "vector3[f32,f32,f32]", "vector3[f32,f32,f32]"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.outcome == ReducerRequest.Outcome.REJECTED or r.outcome == ReducerRequest.Outcome.FAILED:
			spell_ready_ms.erase(a.id)
			if cast_spell == spell:
				_cast_over()
			refused.emit(r.error_message.trim_prefix("cast_spell: ")))
	var cast_ms: int = roundi(float(spell.cast_ms) * HotRules.number(&"regents.cast_time_pct") / 100.0)
	spell_ready_ms[a.id] = now + cast_ms + a.cooldown_ms
	_last_swing_ms = now
	swing_ability = a
	swing_at_ms = now
	swing_hit_ms = now + cast_ms
	swing_cancelled = false
	if cast_ms > 0:
		cast_spell = spell
		cast_until_ms = now + cast_ms
		var me: Node3D = entity as Node3D
		cast_from = me.global_position if me != null else Vector3.ZERO
		swing_lock_ms = cast_until_ms + (kit.lock_ms(a) if kit != null else 0)
	else:
		swing_lock_ms = now + (kit.lock_ms(a) if kit != null else a.wind_up_ms)
		if _driver != null:
			_driver.play_upper(StringName("ability.%d" % a.id))
	cast_sent.emit(a.id, at_target, aim, at)
	swung.emit(a.id)
	return true


## Where an area spell would land: where the crosshair meets the ground within `range_m` of this player,
## else that far along the look on their level.
func area_point(range_m: float) -> Vector3:
	var me: Node3D = entity as Node3D
	var from_me: Vector3 = me.global_position if me != null else Vector3.ZERO
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var flat := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and me != null:
		var origin: Vector3 = cam.global_position
		var dir: Vector3 = -cam.global_basis.z
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * (range_m + 30.0), 1)
		var hit: Dictionary = me.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			var off := Vector3(p.x - from_me.x, 0.0, p.z - from_me.z)
			if off.length() > range_m:
				off = off.normalized() * range_m
				return Vector3(from_me.x + off.x, p.y, from_me.z + off.z)
			return p
	return from_me + flat * range_m


## A cast in progress: it lands at its time (the clip plays), or a rooted one moved off is let go.
func _tick_cast(now: int) -> void:
	if not casting():
		return
	var me: Node3D = entity as Node3D
	var long: bool = not cast_spell.cast_while_moving or cast_spell.cast_ms >= 800
	if long and me != null and Vector2(me.global_position.x - cast_from.x, me.global_position.z - cast_from.z).length() > ROOTED_SLACK_M:
		SpaceTimeSync.call_reducer(&"cancel_cast", [], [])
		refused.emit("Moved: %s let go" % cast_spell.ability.display_name)
		spell_ready_ms.erase(cast_spell.ability.id)
		_cast_over()
		swing_lock_ms = now
		return
	if now >= cast_until_ms:
		if _driver != null:
			_driver.play_upper(StringName("ability.%d" % cast_spell.ability.id))
		cast_spell = null
		cast_until_ms = -1


## The cast is over (landed, let go, refused).
func _cast_over() -> void:
	cast_spell = null
	cast_until_ms = -1


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
		if poise_arc != null:
			poise_arc.visible = false
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
	_place_poise_arc(t)


## The target's poise on its marker (see `poise_arc`); none for a target with no poise (a player).
func _place_poise_arc(t: Node3D) -> void:
	var te: SpaceTimeEntity = t as SpaceTimeEntity
	var feed: HitFeedbackComponent = te.find_component(HitFeedbackComponent) as HitFeedbackComponent if te != null else null
	if poise_arc == null:
		poise_arc = MeshInstance3D.new()
		poise_arc.name = "PoiseArc"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		quad.orientation = PlaneMesh.FACE_Y
		poise_arc.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = _arc_shader()
		poise_arc.material_override = mat
		poise_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		poise_arc.top_level = true
		add_child(poise_arc)
	if feed != _arc_feed:
		if _arc_feed != null and is_instance_valid(_arc_feed) and _arc_feed.poise_broke.is_connected(_burst_arc):
			_arc_feed.poise_broke.disconnect(_burst_arc)
		_arc_feed = feed
		if feed != null:
			feed.poise_broke.connect(_burst_arc)
	var now: int = ClockSync.server_usec()
	poise_arc.visible = feed != null and feed.poise_most > 0.0
	poise_arc.global_position = t.global_position + Vector3(0, 0.05, 0)
	var mat: ShaderMaterial = poise_arc.material_override as ShaderMaterial
	mat.set_shader_parameter(&"worn", feed.poise_worn(now) if feed != null else 0.0)
	mat.set_shader_parameter(&"steady", 1.0 if feed != null and feed.poise_steadied(now) else 0.0)


## The arc bursts: the target's poise broke.
func _burst_arc() -> void:
	if poise_arc == null:
		return
	var mat: ShaderMaterial = poise_arc.material_override as ShaderMaterial
	mat.set_shader_parameter(&"burst", 1.0)
	var tw: Tween = poise_arc.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"burst", v), 1.0, 0.0, 0.45)


static var _arc_code: Shader = null


## The arc: a thin band round the marker, the worn share of it filled clockwise from the front, pale (apart from the
## marker's gold) turning red near the break; a grey band while steadied; a bright widening ring as it bursts.
static func _arc_shader() -> Shader:
	if _arc_code == null:
		_arc_code = Shader.new()
		_arc_code.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float worn = 0.0;
uniform float steady = 0.0;
uniform float burst = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float band = smoothstep(0.70, 0.74, d) * (1.0 - smoothstep(0.82, 0.86, d));
	float a = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float filled = step(a, worn) * band;
	vec3 hot = mix(vec3(1.0, 0.96, 0.88), vec3(1.0, 0.3, 0.1), smoothstep(0.25, 1.0, worn));
	vec3 col = mix(vec3(0.0), hot, filled);
	float alpha = max(band * 0.16, filled * 0.95);
	if (steady > 0.5) {
		col = vec3(0.62, 0.66, 0.72);
		alpha = band * 0.55;
	}
	float r = 0.78 + (1.0 - burst) * 0.18;
	float ring = burst * smoothstep(0.05, 0.0, abs(d - r));
	col = mix(col, vec3(1.0, 0.95, 0.7), ring);
	alpha = max(alpha, ring);
	ALBEDO = col;
	ALPHA = alpha;
}
"""
	return _arc_code


func _exit_tree() -> void:
	if _local_input != null and is_instance_valid(_local_input):
		_local_input.hold_facing(FACING, false)
