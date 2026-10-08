class_name FishingComponent extends SpaceTimeComponent
## GENRE CODE. The client half of fishing (GENRE_ADAPTERS §1).
##
## It is an ordinary `SpaceTimeComponent`: the foundation does not know fishing exists, and this
## does not modify the foundation. A genre adds components to its own entity scene — here
## `game/fishing/fisher.tscn`, which instances `player.tscn` and adds this node under
## `Components/`. That is the whole extension mechanism.
##
## THE CAST, as Fishing for Compliments plays it (`server/src/game/fishing.rs` has the whole loop):
##
##   READY     hold the cast button to start charging
##   CHARGING  the longer you hold, the further it flies; the arc and a ring show where it lands,
##             green over water the server will accept, red over land or out of reach
##   FLYING    released: the rod swings, the float flies, and `cast(target)` is on its way
##   WAITING   the server's answer says when it bites; the float twitches for the tell. A press
##             now reels in — nothing on it, no penalty
##   STRIKE    it has gone under: press within the window to set the hook
##   FIGHTING  THE PUMP (`FightSim`): hold to load the rod, let go in the sweet band, crank the
##             slack down (wheel, or circle the mouse), give line (right button) when it runs
##   RESOLVING the reaction and the fight's inputs are submitted; the server replays them and says
##             what came out
##
## THE CLIENT DECIDES NOTHING. The ring asks the same bake the server asks (`LevelBake`), so it
## shows what will be accepted, but the server is the one that accepts it. What is on the line is
## rolled server-side at the cast; the client reads its own private copy so the bite and the
## fight can be played honestly — the fight runs HERE, for feel, tick by tick — and submits its
## reaction and every tick's input, which the module replays through the same simulation
## (`server/src/genre/fight.rs`, held to `FightSim` bit for bit).

## A line went into the water at `target`, or came out (`out` false). For EVERY angler, local or
## not: it comes from the public `fishing_line` row, which is what lets a client draw other
## players fishing. `is_news` is false for a line that was already out when this entity arrived.
signal line_changed(out: bool, target: Vector3, spot: String, is_news: bool)
## The server resolved a cast into a catch. `catch` carries: key, kg, quality, hookset, spot,
## deadlift, coins. For every angler.
signal catch_landed(catch: Dictionary)
## The server refused the cast (or it could not be sent), with its reason. UI shows it: a press
## that silently does nothing is the single most confusing thing a networked game can do.
signal cast_refused(reason: String)
## LOCAL ANGLER ONLY. The rig moved to another phase (`Rig`).
signal rig_changed(phase: Rig)
## LOCAL ANGLER ONLY. The cast button came up with the float leaving: where it will land, and how
## long it spends in the air after the rod lets go of it.
signal cast_released(target: Vector3, flight_sec: float)
## LOCAL ANGLER ONLY. It bit: the window to set the hook is open.
signal bite_started()
## LOCAL ANGLER ONLY. The press was graded, as the server will grade it (`FishingData.HookSet`).
signal hookset_graded(grade: int, reaction: float)
## LOCAL ANGLER ONLY. The line came back with nothing: reeled in, or it spat the hook.
signal line_lost(reason: String)
## LOCAL ANGLER ONLY. The hook is set and the fight is on (`fight()` is the simulation).
signal fight_started(catch_key: String)
## LOCAL ANGLER ONLY. A pump was released: its grade (`FightSim.Grade`) and the slack it made.
signal pumped(grade: int, metres: float)
## LOCAL ANGLER ONLY. The fight is decided here (`FightSim.State`); the server's replay follows.
signal fight_ended(state: int)

enum Rig { READY, CHARGING, FLYING, WAITING, STRIKE, FIGHTING, RESOLVING }

const CHALLENGE_TABLE: StringName = &"challenge"
const CATCH_TABLE: StringName = &"catch"
## Public: where each angler's float is. The roll behind it stays private.
const LINE_TABLE: StringName = &"fishing_line"
## Public: what each angler's fight looks like, as its owner reports it (DECISIONS #170).
const SHOW_TABLE: StringName = &"fight_show"
## `FIGHT_*` in server/src/game/fishing.rs: what the tell ring shows.
enum Shown { CALM, BAND, SWEET, FAR, RUNNING }
## How often our fight is reported for the others to watch, at most (and at once on a change).
const SHOW_INTERVAL_SEC: float = 0.2
## `KIND_FISH` in server/src/game/fishing.rs.
const KIND_FISH: int = 100
## `entity_kind::RESOURCE_NODE` — what the greybox's ponds are. Fishing no longer casts at them;
## kept so presentation can still recognise one.
const SPOT_KIND: int = 2

const ACTION_CAST: StringName = &"fish_cast"
const ACTION_GIVE: StringName = &"fish_give"
## Seconds of holding to reach full power.
const CHARGE_SEC: float = 1.1
## The float's gravity. Presentation only: the server checks where it LANDS, not how it flew.
const CAST_GRAVITY: float = 9.8
## When the rod lets go of the float, into the cast clip. `FishingFx.RELEASE_SEC`.
const RELEASE_SEC: float = 0.68
## How long a resolved cast waits for the server's catch before the rig is ready again anyway.
const RESOLVE_TIMEOUT_SEC: float = 4.0
## How long a cast waits for the server to confirm it before giving up on it.
const CONFIRM_TIMEOUT_SEC: float = 4.0
## Our reason for holding the body facing the camera (`LocalInputComponent.hold_facing`).
const FACING_REASON: StringName = &"fishing_cast"
## THE CRANK, from FfC's rig: the mouse wheel (each notch a burst, decaying) or CIRCLING the
## mouse — measured as how far the direction of travel TURNS, so a straight drag winds nothing.
const CRANK_TURN_REF: float = 11.0        # radians of turning per second that is a full crank
const CRANK_WHEEL_NOTCH: float = 0.34
const CRANK_WHEEL_DECAY: float = 2.4
## The mouse is the reel handle during a fight: looking around is damped to this, and comes back
## over LOOK_RESTORE_SEC after, so the winding hand does not fling the camera on the landing.
const FIGHT_LOOK_SCALE: float = 0.10
const LOOK_RESTORE_SEC: float = 0.8

var _rig: Rig = Rig.READY
## The rod's equip state (#159), and a cast let go before the rod was in hand.
var _equip: EquipComponent = null
var _release_waiting: bool = false
var _charge: float = 0.0
## The current aim, while charging: where it lands, whether that is castable, which spot.
var _aim_point: Vector3 = Vector3.ZERO
var _aim_valid: bool = false
var _aim_reason: String = ""
var _aim_spot: Dictionary = {}
## The first spot further along this throw than this rod reaches (FfC's gate, said out loud), or {}.
var _aim_beyond: Dictionary = {}
var _aim_range: float = 0.0
var _aim_flight: float = 0.0
var _aim_arc: PackedVector3Array = PackedVector3Array()

## The cast in the water, from our own challenge row: {id, spot, catch, kg, bite, window_mult,
## deadlift, x, z}. Empty when there is none.
var _cast: Dictionary = {}
var _release_msec: int = -1
var _splash_msec: int = -1
var _bite_msec: int = -1
var _window_sec: float = 0.0
var _resolve_msec: int = -1

## The fight in progress (FIGHTING), the reaction that started it, and its input log so far:
## runs of identical input, [ticks, flags, crank] (`FightSim.encode_log`).
var _fight: FightSim = null
var _reaction: float = 0.0
var _log: Array[PackedInt32Array] = []
var _crank: float = 0.0
var _wheel_crank: float = 0.0
var _turn_accum: float = 0.0
var _last_dir: Vector2 = Vector2.ZERO
var _look_restore: float = 0.0

## Where this angler's line is, from the public row. Known for OTHER players too.
var _line_out: bool = false
var _line_target: Vector3 = Vector3.ZERO
var _line_spot: String = ""
## Every catch row this entity owns, by id: {id, key, kg, quality, hookset, spot, deadlift,
## coins, session, round}. Kept for the scoreboard, which asks about OTHER players too — their
## catches route to their own entity's component exactly as ours do (`owner_entity_id`,
## DECISIONS #52).
var _catches: Dictionary[int, Dictionary] = {}
var _interaction: InteractionComponent = null
## This angler's fight as its owner reports it, from the public row: {state, load, line_m}, or {}.
## Read for OTHER players (ours is the FightSim itself).
var _shown_fight: Dictionary = {}
## How many reports of another angler's fight have arrived: each row is one, even with the same values.
var _shown_serial: int = 0
## When our fight was last reported, and what it said.
var _show_sent_msec: int = -1
var _show_sent_state: int = -1


func required_tables() -> Array[StringName]:
	return [CHALLENGE_TABLE, CATCH_TABLE, LINE_TABLE, SHOW_TABLE]


## No line out and nothing caught yet are the normal state for a new player.
func optional_tables() -> Array[StringName]:
	return [CHALLENGE_TABLE, CATCH_TABLE, LINE_TABLE, SHOW_TABLE]


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null:
		_interaction = ent.find_component(InteractionComponent) as InteractionComponent
		_equip = ent.find_component(EquipComponent) as EquipComponent
	set_process(is_local_authority)


## Whether a cast was let go before the rod was in hand, and goes the moment it is (#159).
func waiting_for_rod() -> bool:
	return _release_waiting


# --- queries ------------------------------------------------------------------------------

func rig() -> Rig:
	return _rig


func has_line_out() -> bool:
	return not _cast.is_empty() or _rig == Rig.FLYING


## A line out is ours alone until it is resolved: its aim, its bite clock, its fight. A new look
## waits for it to come in (DECISIONS #166).
func blocks_respawn() -> bool:
	return is_local_authority and (has_line_out() or _rig != Rig.READY)


## The fight in progress, or null.
func fight() -> FightSim:
	return _fight if _rig == Rig.FIGHTING else null


## How hard the reel is being worked right now, 0..1.
func crank() -> float:
	return _crank


func charge() -> float:
	return _charge


## The aim while charging: {point, valid, reason, spot (Dictionary), range, flight, arc}.
func aim() -> Dictionary:
	return {"point": _aim_point, "valid": _aim_valid, "reason": _aim_reason, "spot": _aim_spot,
		"range": _aim_range, "flight": _aim_flight, "arc": _aim_arc, "beyond": _aim_beyond}


## What our own cast rolled, as far as this client knows: {} before the server confirms.
func cast_info() -> Dictionary:
	return _cast


## 0..1: how close the bite is, over the tell's lead. The float twitches by this.
func bite_tell() -> float:
	if _rig != Rig.WAITING or _bite_msec < 0:
		return 0.0
	var lead: float = FishingData.timing("tell_lead_s")
	var until: float = (_bite_msec - Time.get_ticks_msec()) / 1000.0
	return clampf(1.0 - until / maxf(lead, 0.01), 0.0, 1.0)


## 1 just after the bite, falling to 0 as the window closes.
func strike_left() -> float:
	if _rig != Rig.STRIKE or _bite_msec < 0:
		return 0.0
	var gone: float = (Time.get_ticks_msec() - _bite_msec) / 1000.0
	return clampf(1.0 - gone / maxf(_window_sec, 0.01), 0.0, 1.0)


## ANOTHER angler's fight as its owner shows it (DECISIONS #170): {state (`Shown`), load (0..1 of a
## pump), line_m (metres out)}, or {} when they are not fighting.
func shown_fight() -> Dictionary:
	return _shown_fight


## Counts the reports of `shown_fight()` as they arrive, so a presentation can tell a new one.
func shown_serial() -> int:
	return _shown_serial


## What a fight's tell ring shows, as `Shown`.
static func shown_of(f: FightSim) -> Shown:
	if f.behavior == FightSim.Behavior.RUNNING:
		return Shown.RUNNING
	if f.is_overloaded():
		return Shown.FAR
	if f.in_perfect():
		return Shown.SWEET
	if f.in_band():
		return Shown.BAND
	return Shown.CALM


## Is this angler's line in the water? Known for OTHER players too (the public row).
func line_out() -> bool:
	return _line_out


func line_target() -> Vector3:
	return _line_target


func line_spot() -> String:
	return _line_spot


## Every catch this entity has ever landed, oldest first: the journal and the records (#171).
func all_catches() -> Array[Dictionary]:
	var ids: Array[int] = []
	ids.assign(_catches.keys())
	ids.sort()
	var out: Array[Dictionary] = []
	for id: int in ids:
		out.append(_catches[id])
	return out


## This entity's catches in one round of one session, oldest first.
func catches_in(session_id: int, round: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[int] = []
	ids.assign(_catches.keys())
	ids.sort()
	for id: int in ids:
		var c: Dictionary = _catches[id]
		if int(c["session"]) == session_id and int(c["round"]) == round:
			out.append(c)
	return out


# --- the rig: input -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_local_authority:
		return
	_tick_rig()
	_restore_look(delta)
	# The mouse belongs to looking around until it is captured; a click then is MouseCapture's.
	if not MouseCapture.is_captured() or not InputMap.has_action(ACTION_CAST):
		return
	if Input.is_action_just_pressed(ACTION_CAST):
		press_cast()
	elif Input.is_action_just_released(ACTION_CAST):
		release_cast()
	if InputMap.has_action(ACTION_GIVE) and Input.is_action_just_pressed(ACTION_GIVE):
		cancel_charge()


## The cast button went down. What it means depends on the rig: start charging, reel in an
## unbitten line, or set the hook. Public so a playtest can press it without faking input.
func press_cast() -> void:
	match _rig:
		Rig.READY:
			var why: String = _why_not_fishing()
			if not why.is_empty():
				cast_refused.emit(why)
				return
			_charge = 0.0
			_set_rig(Rig.CHARGING)
			_update_aim()
			# Aiming draws the rod (#159): the aim shows while it comes out.
			if _equip != null:
				_equip.needed()
		Rig.WAITING:
			reel_in("reeled in — nothing on it yet")
		Rig.STRIKE:
			_set_hook()
		_:
			pass


## The cast button came up: let fly, if the ring is somewhere the server will take it. NOT UNTIL
## THE ROD IS IN HAND (#159): let go while it is still being drawn, and the cast waits, aiming,
## and goes the moment it is.
func release_cast() -> void:
	if _rig != Rig.CHARGING:
		return
	if _equip != null and not _equip.is_equipped():
		_release_waiting = true
		_equip.needed()
		return
	_release_waiting = false
	_update_aim()
	if not _aim_valid:
		_set_rig(Rig.READY)
		cast_refused.emit(_aim_reason)
		return
	var target: Vector3 = _aim_point
	_release_msec = Time.get_ticks_msec()
	_splash_msec = _release_msec + int((RELEASE_SEC + _aim_flight) * 1000.0)
	_bite_msec = -1
	_cast = {}
	_set_rig(Rig.FLYING)
	if _interaction != null:
		_interaction.announce_interact(entity_id)   # the swing (ANIMATION_SPEC §2)
	cast_released.emit(target, _aim_flight)
	request_cast(target)


## Put the rod down without casting.
func cancel_charge() -> void:
	if _rig == Rig.CHARGING:
		_set_rig(Rig.READY)


## Take an unbitten line out of the water. Also what a missed hook-set does.
func reel_in(reason: String) -> void:
	if _rig != Rig.WAITING and _rig != Rig.STRIKE and _rig != Rig.FLYING:
		return
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"reel_in", [], [])
	if req == null:
		push_warning("FishingComponent: reel_in could not be sent")
	_cast = {}
	_set_rig(Rig.READY)
	line_lost.emit(reason)


# --- the rig: time ------------------------------------------------------------------------

func _tick_rig() -> void:
	var now: int = Time.get_ticks_msec()
	match _rig:
		Rig.CHARGING:
			_charge = minf(1.0, _charge + get_process_delta_time() / CHARGE_SEC)
			_update_aim()
			if _equip != null:
				_equip.needed()
				if _release_waiting and _equip.is_equipped():
					release_cast()
		Rig.FLYING:
			if _cast.is_empty():
				if now - _release_msec > int((RELEASE_SEC + _aim_flight + CONFIRM_TIMEOUT_SEC) * 1000.0):
					_set_rig(Rig.READY)
					line_lost.emit("the cast was never confirmed")
			elif now >= _splash_msec:
				_bite_msec = _splash_msec + int(float(_cast["bite"]) * 1000.0)
				_set_rig(Rig.WAITING)
		Rig.WAITING:
			if _bite_msec >= 0 and now >= _bite_msec:
				_window_sec = FishingData.hookset_window(float(_cast.get("window_mult", 1.0)))
				_set_rig(Rig.STRIKE)
				bite_started.emit()
		Rig.STRIKE:
			if now > _bite_msec + int(_window_sec * 1000.0):
				reel_in("too slow — it spat the hook")
		Rig.FIGHTING:
			pass   # stepped in _physics_process, on the fight's own fixed tick
		Rig.RESOLVING:
			if now - _resolve_msec > int(RESOLVE_TIMEOUT_SEC * 1000.0):
				# No catch came back. The module's replay of the fight is the one that counts, and
				# it did not land it (or the round had ended): say so rather than going quiet.
				_cast = {}
				_set_rig(Rig.READY)
				line_lost.emit("…it got away")
		_:
			pass


func _set_hook() -> void:
	var reaction: float = FishingData.f32((Time.get_ticks_msec() - _bite_msec) / 1000.0)
	var grade: FishingData.HookSet = FishingData.grade_hookset(reaction, float(_cast.get("window_mult", 1.0)))
	hookset_graded.emit(grade, reaction)
	if grade == FishingData.HookSet.NONE:
		reel_in("too early — it let go")
		return
	_start_fight(grade, reaction)


# --- the fight ------------------------------------------------------------------------------

## THE HOOK IS SET. The fight is built from exactly what the server will replay it with — the
## cast's own record in the payload: its seed, the range in centimetres, the gear AT THE CAST —
## plus the grade the press just earned.
func _start_fight(grade: FishingData.HookSet, reaction: float) -> void:
	var key: String = str(_cast.get("catch", ""))
	var prof: FightSim.Profile = FightSim.profile_of(key)
	if prof == null:
		push_warning("FishingComponent: '%s' has no fight profile; submitting the hook-set alone" % key)
	var params: FightSim.Params = FightSim.params_for(int(_cast.get("rod", 0)), int(_cast.get("reel", 0)),
		int(_cast.get("line", 0)), grade, bool(_cast.get("deadlift", false)))
	# The button that set the hook is still down; the fight ignores it until it comes up.
	_fight = FightSim.new(params, prof if prof != null else FightSim.profile_of("bluegill"),
		int(_cast.get("fight_seed", 0)), float(_cast.get("range_cm", 1000)) / 100.0, true)
	_fight.pumped.connect(func(g: FightSim.Grade, metres: float) -> void: pumped.emit(g, metres))
	_show_sent_msec = -1
	_show_sent_state = -1
	_reaction = reaction
	_log.clear()
	_crank = 0.0
	_wheel_crank = 0.0
	_turn_accum = 0.0
	_set_rig(Rig.FIGHTING)
	set_physics_process(true)
	fight_started.emit(key)


## One tick of the fight, on the physics clock: the fight's step is fixed (`FightSim.dt`), and the
## physics tick is the clock that keeps to it. Input is sampled HERE, logged, and fed in.
func _physics_process(delta: float) -> void:
	if _rig != Rig.FIGHTING or _fight == null:
		return
	var live: bool = MouseCapture.is_captured()
	var loading: bool = live and InputMap.has_action(ACTION_CAST) and Input.is_action_pressed(ACTION_CAST)
	var giving: bool = live and InputMap.has_action(ACTION_GIVE) and Input.is_action_pressed(ACTION_GIVE)
	var crank_q: int = _sample_crank(delta, live)
	var flags: int = (1 if loading else 0) | (2 if giving else 0)
	if not _log.is_empty() and _log[-1][1] == flags and _log[-1][2] == crank_q:
		_log[-1][0] += 1
	else:
		_log.append(PackedInt32Array([1, flags, crank_q]))
	_fight.tick(loading, giving, crank_q)
	if _fight.state != FightSim.State.FIGHTING or _fight.ticks >= FightSim.max_ticks():
		_finish_fight()
	else:
		_report_fight()


## Tell the others what our fight looks like (DECISIONS #170): a few times a second, and at once
## when the tell changes. Presentation only: the module bounds it and decides nothing on it.
func _report_fight() -> void:
	var state: int = shown_of(_fight)
	var now: int = Time.get_ticks_msec()
	if state == _show_sent_state and _show_sent_msec >= 0 and now - _show_sent_msec < int(SHOW_INTERVAL_SEC * 1000.0):
		return
	_show_sent_state = state
	_show_sent_msec = now
	SpaceTimeSync.call_reducer(&"show_fight",
		[state, FishingFeedback.pump_of(_fight), _fight.line_out_m()], ["u8", "f32", "f32"])


## Send the reaction and the whole log; the server replays it and decides. The client already
## knows how its own fight ended, and says so now rather than a round trip later.
func _finish_fight() -> void:
	var ended: FightSim.State = _fight.state
	var id: int = int(_cast.get("id", -1))
	var args: Array[float] = [_reaction]
	args.append_array(FightSim.encode_log(_log))
	SpaceTimeSync.call_reducer(&"submit_challenge_result", [id, args], ["u64", "f32"])
	set_physics_process(false)
	_look_restore = LOOK_RESTORE_SEC
	fight_ended.emit(ended)
	if ended == FightSim.State.LANDED:
		_resolve_msec = Time.get_ticks_msec()
		_set_rig(Rig.RESOLVING)
	else:
		_cast = {}
		_set_rig(Rig.READY)
		line_lost.emit("the line snapped!" if ended == FightSim.State.SNAPPED
			else "the line was cut: that fight went on too long")


## Wheel notches and mouse circling, turned into 0..255 the way FfC's rig did: whichever is being
## worked harder, easing down rather than strobing between motion events.
func _sample_crank(delta: float, live: bool) -> int:
	var dt: float = maxf(delta, 0.0001)
	var turn_rate: float = _turn_accum / dt
	_turn_accum = 0.0
	_wheel_crank = maxf(_wheel_crank - CRANK_WHEEL_DECAY * dt, 0.0)
	var target: float = maxf(clampf(turn_rate / CRANK_TURN_REF, 0.0, 1.0), _wheel_crank) if live else 0.0
	_crank = maxf(target, _crank - dt * 4.0)
	return clampi(int(round(_crank * 255.0)), 0, 255)


func _unhandled_input(event: InputEvent) -> void:
	if _rig != Rig.FIGHTING or not is_local_authority or not MouseCapture.is_captured():
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		# Bank how far the direction of travel TURNED: circling accumulates, a straight drag not.
		if motion.relative.length() > 2.0:
			var dir: Vector2 = motion.relative.normalized()
			if _last_dir != Vector2.ZERO:
				_turn_accum += absf(_last_dir.angle_to(dir))
			_last_dir = dir
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_wheel_crank = minf(_wheel_crank + CRANK_WHEEL_NOTCH, 1.0)


## Mouse look is damped while the mouse is the reel handle, and eases back after.
func _restore_look(delta: float) -> void:
	var input: LocalInputComponent = _local_input()
	if input == null:
		return
	if _rig == Rig.FIGHTING:
		input.look_scale = FIGHT_LOOK_SCALE
		return
	if _look_restore > 0.0:
		_look_restore = maxf(_look_restore - delta, 0.0)
		input.look_scale = lerpf(FIGHT_LOOK_SCALE, 1.0, 1.0 - _look_restore / LOOK_RESTORE_SEC)
	elif input.look_scale != 1.0:
		input.look_scale = 1.0


func _set_rig(to: Rig) -> void:
	if to == _rig:
		return
	_rig = to
	if to != Rig.CHARGING:
		_release_waiting = false
	# THE ANGLER FACES THE CAST. While charging, the body turns with the aim, standing still or
	# not, so a cast thrown behind you is thrown by someone who turned round first. It lets go on
	# release: the body keeps the heading it threw on, and looking around while the float sits
	# does not turn it away from the line.
	var input: LocalInputComponent = _local_input()
	if input != null:
		input.hold_facing(FACING_REASON, to == Rig.CHARGING)
	rig_changed.emit(to)


## Why this angler cannot start a cast right now, or "" when they can. The server decides and
## always has; this is only about not animating a cast it will certainly refuse.
func _why_not_fishing() -> String:
	if not _cast.is_empty():
		return "you already have a line out"
	var level: LakesideLevel = _level()
	if level == null or level.bake() == null:
		return "there is no water to fish here"
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var sess: SessionComponent = ent.find_component(SessionComponent) as SessionComponent \
		if ent != null else null
	# An UNKNOWN phase is not a refusal: a client holds its `session_member` row before the
	# `session` row arrives, and refusing then would swallow the first cast of every join.
	if sess != null and sess.is_in_session() and sess.get_phase() >= 0 \
			and sess.get_phase() != SessionComponent.Phase.PLAYING:
		return "you can only fish during the PLAYING phase"
	return ""


# --- the aim ----------------------------------------------------------------------------

## Where a float cast now, at this charge, would land — and whether the server will take it.
func _update_aim() -> void:
	var level: LakesideLevel = _level()
	var ent: Node3D = entity as Node3D
	if level == null or level.bake() == null or ent == null or not ent.is_inside_tree():
		_aim_valid = false
		_aim_reason = "there is no water to fish here"
		return
	var bake: LevelBake = level.bake()
	var reach: float = FishingData.max_cast_m(_rod_tier())
	var solved: Dictionary = solve_cast(ent.global_position, _aim_direction(ent), _charge, reach,
		bake.water_y)
	_aim_point = solved["point"]
	_aim_range = solved["range"]
	_aim_flight = solved["flight"]
	_aim_arc = solved["arc"]
	_aim_spot = bake.spot_at(_aim_point.x, _aim_point.z)
	_aim_beyond = spot_beyond(bake, ent.global_position, _aim_point, _rod_tier())
	var min_range: float = FishingData.cast_setting("min_range_m")
	if _aim_range < min_range:
		_aim_valid = false
		_aim_reason = "too close — hold longer, or look further out"
	elif not bake.is_water(_aim_point.x, _aim_point.z):
		_aim_valid = false
		_aim_reason = "that is dry land — aim at the water"
	else:
		_aim_valid = true
		_aim_reason = ""


## THE GATE, SAID OUT LOUD. Spots are water like any other, and a rod decides which of them can
## be reached at all (`FishingData.min_rod`), so the aim names the first spot further along this
## throw — out to the best rod's reach — that needs a better rod than `rod_tier`: what buying one
## would open, in the direction the player is already looking. {} when there is none.
static func spot_beyond(bake: LevelBake, feet: Vector3, point: Vector3, rod_tier: int) -> Dictionary:
	var out := Vector2(point.x - feet.x, point.z - feet.z)
	if out.length() < 0.01:
		return {}
	var best: float = FishingData.max_cast_m(FishingData.max_tier()) + FishingData.cast_setting("range_slack_m")
	var d: float = out.length()
	while d <= best:
		var p: Vector2 = Vector2(feet.x, feet.z) + out.normalized() * d
		var s: Dictionary = bake.spot_at(p.x, p.y)
		if not s.is_empty() and FishingData.min_rod(str(s.get("id", ""))) > rod_tier:
			return s
		d += 1.0
	return {}


## The cast's arc, as a pure function so tests and tools can ask it: from an angler standing at
## `feet`, thrown along `dir` at `charge`, with a rod that reaches `reach` metres. Lands on the
## water plane at `water_y`, and never further out than the rod reaches.
##   {point: Vector3, range: float, flight: float, arc: PackedVector3Array}
static func solve_cast(feet: Vector3, dir: Vector3, charge_amount: float, reach: float,
		water_y: float) -> Dictionary:
	var from: Vector3 = feet + Vector3(0.0, 1.7, 0.0)
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	from += flat * 0.4
	# At 45 degrees over flat ground, v^2 / g is the range: so a full charge on this rod is its
	# reach, and an empty one is a lob.
	var v_max: float = sqrt(maxf(reach, 1.0) * CAST_GRAVITY)
	var v_min: float = sqrt(3.0 * CAST_GRAVITY)
	var speed: float = lerpf(v_min, v_max, clampf(charge_amount, 0.0, 1.0))
	var d: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else flat
	# Never a downward throw: aiming at your feet still lobs it.
	if d.y < 0.15:
		d = (flat * 0.95 + Vector3(0.0, 0.15, 0.0)).normalized()
	var vel: Vector3 = d * speed
	var pos: Vector3 = from
	var arc := PackedVector3Array([pos])
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while t < 8.0:
		var next: Vector3 = pos + vel * dt
		vel.y -= CAST_GRAVITY * dt
		t += dt
		if next.y <= water_y and vel.y < 0.0:
			var k: float = (pos.y - water_y) / maxf(pos.y - next.y, 0.0001)
			pos = pos.lerp(next, clampf(k, 0.0, 1.0))
			arc.append(pos)
			break
		pos = next
		arc.append(pos)
	var out: Vector3 = Vector3(pos.x - feet.x, 0.0, pos.z - feet.z)
	var range_m: float = out.length()
	if range_m > reach:
		out = out * (reach / range_m)
		range_m = reach
	var point: Vector3 = Vector3(feet.x + out.x, water_y, feet.z + out.z)
	return {"point": point, "range": range_m, "flight": t, "arc": arc}


func _aim_direction(ent: Node3D) -> Vector3:
	var cam: Camera3D = ent.get_viewport().get_camera_3d() if ent.is_inside_tree() else null
	if cam != null:
		return -cam.global_transform.basis.z
	return -ent.global_transform.basis.z + Vector3(0.0, 0.7, 0.0)


func _local_input() -> LocalInputComponent:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	return ent.find_component(LocalInputComponent) as LocalInputComponent if ent != null else null


func _rod_tier() -> int:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var gear: GearComponent = ent.find_component(GearComponent) as GearComponent if ent != null else null
	return gear.rod_tier() if gear != null else 0


## The level with water in it, if this scene has one.
func _level() -> LakesideLevel:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(LakesideLevel.GROUP) as LakesideLevel


# --- intent ------------------------------------------------------------------------------

## Whether our session is past its PLAYING phase (an unknown phase is not over).
func _round_over() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var sess: SessionComponent = ent.find_component(SessionComponent) as SessionComponent \
		if ent != null else null
	return sess != null and sess.is_in_session() and sess.get_phase() >= 0 \
		and sess.get_phase() != SessionComponent.Phase.PLAYING


## Ask to cast at a point. The server checks the phase, the reach, the water and that no line is
## out; a refusal comes back on `cast_refused`, whoever asked. Watching the answer belongs HERE
## rather than at each call site, or a cast made any other way fails silently.
func request_cast(target: Vector3) -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"cast", [target], ["vector3[f32,f32,f32]"])
	if req == null:
		_on_cast_refused_locally("the request could not be sent")
		return null
	if req.is_pending():
		req.settled.connect(_on_cast_settled)
	else:
		_on_cast_settled(req)
	return req


func _on_cast_settled(req: ReducerRequest) -> void:
	if req.is_ok():
		return
	var why: String = req.error_message
	if why.is_empty():
		why = ReducerRequest.Outcome.keys()[req.outcome]
	_on_cast_refused_locally(why)


func _on_cast_refused_locally(why: String) -> void:
	if _rig == Rig.FLYING:
		_cast = {}
		_set_rig(Rig.READY)
	cast_refused.emit(why.trim_prefix("cast: "))


# --- rows ----------------------------------------------------------------------------------

func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	match table:
		CHALLENGE_TABLE:
			_on_challenge(old, new)
		CATCH_TABLE:
			_on_catch(new)
		LINE_TABLE:
			_on_line(new)
		SHOW_TABLE:
			_shown_serial += 1
			_shown_fight = {} if new == null else {
				"state": int(new.get(&"state")),
				"load": float(new.get(&"load")),
				"line_m": float(new.get(&"line_m")),
			}
		_:
			pass


func _on_challenge(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		# Resolved, reeled in or expired. If it was the cast in the water, it is over.
		if old != null and not _cast.is_empty() and int(old.get(&"id")) == int(_cast["id"]):
			var was: Rig = _rig
			_cast = {}
			# Still in the air counts: the server can close a cast before its float lands (a
			# reel-in from another session, an expiry), and FLYING with no cast would otherwise
			# sit out the confirm timeout and blame the server for never confirming it. So does a
			# fight: a line the server closed mid-fight (its life ran out) is not a fight any more.
			if was == Rig.WAITING or was == Rig.STRIKE or was == Rig.FLYING or was == Rig.FIGHTING:
				if was == Rig.FIGHTING:
					set_physics_process(false)
					_look_restore = LOOK_RESTORE_SEC
				_set_rig(Rig.READY)
				# The bell brings in every line nothing has bitten (DECISIONS #161): say so.
				line_lost.emit("the round is over: line in" if _round_over() else "the line came in")
			elif was == Rig.RESOLVING:
				# The catch row, if there is one, arrives in the same transaction; give it a moment.
				_resolve_msec = Time.get_ticks_msec() - int((RESOLVE_TIMEOUT_SEC - 0.6) * 1000.0)
		return
	if int(new.get(&"kind")) != KIND_FISH:
		return   # someone else's challenge kind
	var payload: String = str(new.get(&"payload"))
	if payload.is_empty():
		return   # issued, not yet rolled: the roll lands in the same transaction
	var parsed: Variant = JSON.parse_string(payload)
	if not parsed is Dictionary:
		push_warning("FishingComponent: unreadable cast payload %s" % payload)
		return
	var info: Dictionary = parsed as Dictionary
	info["id"] = int(new.get(&"id"))
	var fresh: bool = _cast.is_empty() or int(_cast.get("id", -1)) != int(info["id"])
	_cast = info
	if not fresh:
		return
	# A cast confirmed while we were not flying one — a rejoin with a line already out. It was
	# not cast just now; count the bite from now, which errs on the late side of the server.
	if _rig == Rig.READY:
		_release_msec = Time.get_ticks_msec()
		_splash_msec = _release_msec
		_set_rig(Rig.FLYING)


func _on_line(new: RefCounted) -> void:
	var out: bool = new != null
	var target: Vector3 = Vector3.ZERO
	var spot: String = ""
	if out:
		target = Vector3(float(new.get(&"x")), _water_y(), float(new.get(&"z")))
		spot = str(new.get(&"spot"))
	if out == _line_out and target == _line_target:
		return
	_line_out = out
	_line_target = target
	_line_spot = spot
	var news: bool = is_bound()
	line_changed.emit(out, target, spot, news)
	# ANOTHER ANGLER'S CAST, SEEN LIVE: their character should swing its rod on this screen too.
	# The row is the first this client hears of it, so it announces the verb for them, and their
	# animation driver plays it exactly as it does for a local press (DECISIONS #115). Our OWN cast
	# was announced on release, a round trip before this row, so it is not repeated.
	if news and out and not is_local_authority and _interaction != null:
		_interaction.announce_interact(entity_id)


func _on_catch(new: RefCounted) -> void:
	if new == null:
		return
	# `catch` is append-only and arrives for this entity because the row carries
	# `owner_entity_id` (DECISIONS #52). Dedupe in case the cache replays on reconnect.
	var id: int = int(new.get(&"id"))
	if _catches.has(id):
		return
	var c: Dictionary = {
		"id": id,
		"key": str(new.get(&"catch_key")),
		"kg": float(new.get(&"kg")),
		"quality": float(new.get(&"quality")),
		"hookset": int(new.get(&"hookset")),
		"spot": str(new.get(&"spot")),
		"deadlift": bool(new.get(&"deadlift")),
		"coins": int(new.get(&"coins")),
		"session": int(new.get(&"session_id")),
		"round": int(new.get(&"round")),
		"best_combo": int(new.get(&"best_combo")),
		"fight_s": float(new.get(&"fight_s")),
		"clean": bool(new.get(&"clean")),
	}
	_catches[id] = c
	# ANNOUNCED ONLY IF IT IS NEWS. `bind()` replays every catch this angler ever made (DECISIONS
	# #180: it once handed over only the newest, and the journal showed one catch each); rows that
	# were already true when we arrived are history — recorded above for the journal, not
	# celebrated.
	if not is_bound():
		return
	if is_local_authority and _rig == Rig.RESOLVING:
		_cast = {}
		_set_rig(Rig.READY)
	catch_landed.emit(c)


func _water_y() -> float:
	var level: LakesideLevel = _level()
	return level.water_y() if level != null else 0.0
