extends NpcBrain
## A FOE'S BRAIN (owner, 2026-10-19: the first enemies attack on sight): every foe has this one, and its
## `FoeDef` (by its entity kind) says how near it notices, how far it chases, how near it swings, and its
## rhythm. It fights with its own FOE KIT (COMBAT_OVERHAUL.md §2: slow, readable swings) through
## `use_ability_as`, judged by the same referee and the same `hit` as a player's.
##
##   idle     stands at home (its level point)
##   chase    a player came within `notice_m` and in sight: runs at them, round what is in the way (the
##            level's walk map, `go_to`); out of sight, to where it last saw them, for `lose_sight_ms`
##   fight    within `reach_m` and holding a TURN: faces them, swings its kit's string (the last its
##            finisher); each swing waits out the last one's lock, and the string ends with a rest.
##            A target that steps out of reach between swings is run down (chase) and the string goes on
##            where it stopped; out of reach past `string_chase_ms`, the string is dropped (2026-11-11)
##   circle   in reach but no turn: walks round them at `reach_m` + `CIRCLE_M`, facing them, waiting
##   return   past `leash_m` from home: walks back, deaf to players until it is home
##   slain    lies still (the server's Slain status)
##
## TAKING TURNS (COMBAT_OVERHAUL.md §2, 2026-10-31; the playtest: "attacks came at the same time"). Every
## foe this referee runs shares, per player, who holds a turn and when the last foe swing lands on them:
##   - at most `regents.attack_tokens` foes swing at one player; the rest circle
##   - no foe swing lands sooner than `regents.token_gap_ms` after another landed on that player, whatever
##     it did (hit, parried, rolled through, missed): its press waits until it would land late enough
##   - a turn is the whole string; it is given back once the finisher's lock is over (or the fight ends)
## A player on the edge of two region referees may face one foe more: accepted.
##
## AIM: it turns to follow its target through a swing's wind-up and stops turning
## `regents.foe_aim_lock_ms` before the hit lands. The referee sweeps along the way it faces AT the
## landing (its movement history), so a step aside late in the wind-up slips the swing; one early does not.

const SLAIN: int = 106
## The server's Startled (`content/status/startled.tres`): set on ANY fighting foe hit while it does nothing else
## (Luke, 2026-11-11: "Every foe", not pack foes only), so one hit from beyond its sight turns on who hit it.
const STATUS_STARTLED: int = 109
## Home is reached this near.
const HOME_M: float = 1.5
## Waiting for a turn, it circles this far beyond its reach.
const CIRCLE_M: float = 1.5
## How far round it steps each think while circling (radians).
const CIRCLE_STEP: float = 0.35
## A turn not kept up this long (the foe sleeps, falls, its referee lost it) is free again.
const TURN_STALE_MS: int = 1500
## After a hit lands its aim stays held this much longer, so the referee's settle sees it.
const AIM_SETTLE_MS: int = 100

const TOKENS: StringName = &"regents.attack_tokens"
const GAP: StringName = &"regents.token_gap_ms"
const AIM_LOCK: StringName = &"regents.foe_aim_lock_ms"

## Per player, the turns of every foe this referee runs: target id -> {"holders": {foe id: ms last kept},
## "land_ms": when the last foe swing on them lands}.
static var turns: Dictionary[int, Dictionary] = {}
## PACKS (Luke, 2026-11-10: wolves hunt in packs of 2-3): each fighting pack foe reports its target here
## (`self_id` -> {"kind": kind, "pos": Vector3, "target": target_id, "last_seen": Vector3, "at": _seen_at_ms}),
## so packmates of its kind within `foe.pack_m` join in.
static var packs: Dictionary[int, Dictionary] = {}

var foe: FoeDef = null
var home: Vector3 = Vector3.ZERO
var target_id: int = 0
var returning: bool = false
var _home_known: bool = false
var _next_swing_ms: int = 0
var _swings: int = 0
var _step: int = 0
## When its last swing lands (its aim holds from `AIM_LOCK` before it), and when its lock ends.
var _land_ms: int = -1
var _lock_end_ms: int = -1
## Where to face this tick (in a fight or circling), and whether to.
var _face: Vector3 = Vector3.ZERO
var _facing: bool = false
## Circling: it walks to its goal while facing `_face`.
var _circling: bool = false
## Where it last saw its target, when, and whether it sees them now.
var _last_seen: Vector3 = Vector3.ZERO
var _seen_at_ms: int = 0
var _in_sight: bool = false
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	state = &"idle"
	_rng.seed = seed_value


func think(me: MovementState, world: NpcWorldView) -> void:
	if me == null or world == null:
		return
	if foe == null:
		foe = FoeDef.by_kind(int(world.kinds.get(self_id, -1)))
		if foe == null or foe.kit == null:
			state = &"lost"
			return
	if not _home_known:
		home = me.pos
		_home_known = true
	_facing = false
	_circling = false
	if world.status_of(self_id) == SLAIN:
		state = &"slain"
		_let_turn_go()
		packs.erase(self_id)
		target_id = 0
		clear_goal()
		return
	var from_home: float = Vector2(me.pos.x - home.x, me.pos.z - home.z).length()
	# Past the leash: home, deaf to everyone until it gets there.
	if returning or from_home > foe.leash_m:
		returning = from_home > HOME_M
		if returning:
			_let_turn_go()
			packs.erase(self_id)
			target_id = 0
			state = &"return"
			go_to(home, me, world)
			return
	var had: int = target_id
	_pick_target(me, world)
	if had != 0 and had != target_id:
		_let_turn_go(had)
	if foe.pack_m > 0.0 and target_id != 0:
		packs[self_id] = {
			"kind": int(world.kinds.get(self_id, -1)),
			"pos": me.pos,
			"target": target_id,
			"last_seen": _last_seen,
			"at": _seen_at_ms,
		}
	else:
		packs.erase(self_id)
	if target_id == 0:
		state = &"idle"
		_drop_string()   # nobody to finish it on: the next fight starts with its first swing
		if from_home > HOME_M:
			go_to(home, me, world)
		else:
			clear_goal()
		return
	var t: MovementState = world.state_of(target_id)
	var to: Vector3 = t.pos - me.pos
	to.y = 0.0
	var dist: float = to.length()
	var now: int = now_ms()
	# ITS STRING FOLLOWS ITS TARGET (Luke, 2026-11-11): between two swings (the last one's lock over), a target out of
	# reach, or of sight, for longer than `string_chase_ms` loses it the string: the next is its first swing again.
	if _step > 0 and now - _lock_end_ms > foe.string_chase_ms and (dist > foe.reach_m or not _in_sight):
		_drop_string()
	var mid_string: bool = _step > 0 or now < _lock_end_ms
	# Near enough to fight or circle: inside its reach, or the circle's and a little.
	var near: bool = dist <= foe.reach_m + CIRCLE_M + 1.0
	if not _in_sight or (not near and not mid_string):
		_let_turn_go()
		state = &"chase"
		go_to(t.pos if _in_sight else _last_seen, me, world)
		return
	# Its aim follows them, except in the last `AIM_LOCK` before a hit lands.
	var locked: bool = _land_ms >= 0 and now >= _land_ms - aim_lock_ms() and now < _land_ms + AIM_SETTLE_MS
	if not locked:
		_face = to.normalized() if dist > 0.01 else Vector3.FORWARD
	if not _keep_turn(now):
		state = &"circle"
		_facing = true
		_circle(me, t, world)
		return
	# Its turn, and they are out of its reach: in to its reach. Mid-string too, once the last swing's lock is over (it
	# cannot move before): it closes the gap and the string goes on where it stopped, never a swing at the air.
	if dist > foe.reach_m and (not mid_string or now >= _lock_end_ms):
		state = &"chase"
		go_to(t.pos, me, world)
		return
	state = &"fight"
	_facing = true
	clear_goal()
	if now >= _next_swing_ms:
		_swing_if_spaced(now)


## The nearest player in reach of its notice and in sight who is up; the one it has, while they stay
## inside the leash's reach and in sight, or out of sight for no longer than `lose_sight_ms`.
func _pick_target(me: MovementState, world: NpcWorldView) -> void:
	if target_id != 0:
		var held: MovementState = world.state_of(target_id)
		var keep: bool = held != null and world.status_of(target_id) != SLAIN \
			and Vector2(held.pos.x - home.x, held.pos.z - home.z).length() <= foe.leash_m
		if keep:
			_in_sight = world.can_see(me.pos, held.pos)
			if _in_sight:
				_last_seen = held.pos
				_seen_at_ms = now_ms()
			elif foe.pack_m > 0.0:
				_hear_pack(me, world)
			if _in_sight or now_ms() - _seen_at_ms <= foe.lose_sight_ms:
				return
		target_id = 0
	var found: int = world.nearest_of_kind(me.pos, 0, foe.notice_m, self_id)
	if found != 0 and world.status_of(found) != SLAIN:
		var cand: MovementState = world.state_of(found)
		if cand != null and world.can_see(me.pos, cand.pos):
			target_id = found
			_in_sight = true
			_last_seen = cand.pos
			_seen_at_ms = now_ms()
			return
	# Hit from beyond its sight (the server's Startled): it turns on the nearest player within twice its leash.
	if world.status_of(self_id) == STATUS_STARTLED:
		var shooter: int = world.nearest_of_kind(me.pos, 0, foe.leash_m * 2.0, self_id)
		var at: MovementState = world.state_of(shooter) if shooter != 0 and world.status_of(shooter) != SLAIN else null
		if at != null and Vector2(at.pos.x - home.x, at.pos.z - home.z).length() <= foe.leash_m:
			target_id = shooter
			_in_sight = world.can_see(me.pos, at.pos)
			_last_seen = at.pos
			_seen_at_ms = now_ms()
			return
	if foe.pack_m > 0.0:
		_hear_pack(me, world)


## A packmate of the same kind within `foe.pack_m` has a fresh sighting of a target inside this foe's leash:
## take up the chase (or refresh where they were last seen).
func _hear_pack(me: MovementState, world: NpcWorldView) -> void:
	var kind: int = int(world.kinds.get(self_id, -1))
	var now: int = now_ms()
	var best_d: float = foe.pack_m + 0.01
	var best: Dictionary = {}
	for other_id: int in packs.keys():
		if other_id == self_id or world.state_of(other_id) == null or world.status_of(other_id) == SLAIN:
			continue
		var entry: Dictionary = packs[other_id]
		if int(entry.get("kind", -2)) != kind:
			continue
		var at_ms: int = int(entry.get("at", -100000))
		if now < at_ms or now - at_ms > foe.lose_sight_ms:
			continue
		var ppos: Vector3 = entry.get("pos", Vector3.ZERO) as Vector3
		var d: float = Vector2(me.pos.x - ppos.x, me.pos.z - ppos.z).length()
		if d > best_d:
			continue
		var who: int = int(entry.get("target", 0))
		if target_id != 0 and who != target_id:
			continue
		var tstate: MovementState = world.state_of(who) if who != 0 and world.status_of(who) != SLAIN else null
		if tstate == null or Vector2(tstate.pos.x - home.x, tstate.pos.z - home.z).length() > foe.leash_m:
			continue
		best_d = d
		best = entry
	if best.is_empty():
		return
	var picked: int = int(best["target"])
	var held: MovementState = world.state_of(picked)
	target_id = picked
	_in_sight = world.can_see(me.pos, held.pos)
	if _in_sight:
		_last_seen = held.pos
		_seen_at_ms = now
	elif int(best["at"]) >= _seen_at_ms:
		_last_seen = best["last_seen"] as Vector3
		_seen_at_ms = int(best["at"])


# --- turns ------------------------------------------------------------------------------------

## Its target's turns (made on first ask), stale holders dropped.
func _turn(now: int) -> Dictionary:
	var turn: Dictionary = turns.get(target_id, {})
	if turn.is_empty():
		turn = {"holders": {}, "land_ms": -1}
		turns[target_id] = turn
	var holders: Dictionary = turn["holders"]
	for id: int in holders.keys():
		if now - int(holders[id]) > TURN_STALE_MS:
			holders.erase(id)
	return turn


## Whether it holds a turn on its target now: kept if it had one, taken if one is free and it is rested.
func _keep_turn(now: int) -> bool:
	var holders: Dictionary = _turn(now)["holders"]
	if holders.has(self_id):
		if _step == 0 and now >= _lock_end_ms and now < _next_swing_ms:
			holders.erase(self_id)   # its string is over and it rests: the turn goes
			return false
		holders[self_id] = now
		return true
	if now < _next_swing_ms or holders.size() >= tokens():
		return false
	holders[self_id] = now
	return true


## Give its turn on `on` (its target) back.
func _let_turn_go(on: int = 0) -> void:
	var who: int = on if on != 0 else target_id
	var turn: Dictionary = turns.get(who, {})
	if not turn.is_empty():
		(turn["holders"] as Dictionary).erase(self_id)


## Waiting for a turn: a step round its target, at its reach and a little more, facing them.
func _circle(me: MovementState, t: MovementState, world: NpcWorldView) -> void:
	var from: Vector3 = me.pos - t.pos
	from.y = 0.0
	if from.length() < 0.01:
		from = Vector3.BACK
	var way: float = CIRCLE_STEP if self_id % 2 == 0 else -CIRCLE_STEP
	var spot: Vector3 = t.pos + from.normalized().rotated(Vector3.UP, way) * (foe.reach_m + CIRCLE_M)
	go_to(spot, me, world)
	_circling = true


# --- swinging ---------------------------------------------------------------------------------

## The string's next swing, if it would land at least `GAP` after the last foe swing on its target.
func _swing_if_spaced(now: int) -> void:
	var a: AbilityDef = _next_ability()
	var turn: Dictionary = _turn(now)
	var lands: int = now + a.wind_up_ms
	var last: int = int(turn["land_ms"])
	if last >= 0 and lands < last + gap_ms():
		return   # too soon after another's: it waits a think
	_swing(a, now)
	turn["land_ms"] = maxi(last, lands)


## Which ability the next swing is: the string's next (its last is the finisher).
func _next_ability() -> AbilityDef:
	var kit: KitDef = foe.kit
	return kit.light[_step % kit.light.size()]


## One swing of `a`, aimed where it faces. The next waits out its lock; the string's end (its finisher) adds
## its rest, `rest_ms` give or take `rest_jitter_ms`.
func _swing(a: AbilityDef, now: int) -> void:
	var kit: KitDef = foe.kit
	_swings += 1
	_step += 1
	use_ability(a.id, _face, target_id)
	_land_ms = now + a.wind_up_ms
	var wait: int = kit.lock_ms(a)
	_lock_end_ms = now + wait
	if _step >= kit.light.size():
		_step = 0
		wait += maxi(0, foe.rest_ms + _rng.randi_range(-foe.rest_jitter_ms, foe.rest_jitter_ms))
	_next_swing_ms = now + wait


## Its string given up part way (its target stayed out of reach too long, or it has none): the next swing is its
## first again, after its rest, counted from the last swing's lock (the time it chased is rest it has had).
func _drop_string() -> void:
	if _step == 0:
		return
	_step = 0
	_next_swing_ms = _lock_end_ms + maxi(0, foe.rest_ms + _rng.randi_range(-foe.rest_jitter_ms, foe.rest_jitter_ms))


func tokens() -> int:
	return maxi(1, int(HotRules.number(TOKENS)))


func gap_ms() -> int:
	return maxi(0, int(HotRules.number(GAP)))


func aim_lock_ms() -> int:
	return maxi(0, int(HotRules.number(AIM_LOCK)))


func frame(me: MovementState) -> InputFrame:
	if not _facing:
		return super(me)
	# Circling: it walks round its goal, facing its target; fighting, it stands and faces them (-Z is
	# forward), so its swings sweep at them.
	var f: InputFrame = super(me) if _circling else InputFrame.new()
	f.look_yaw = atan2(_face.x, _face.z) + PI
	f.face = true
	if _circling:
		f.slow = true
	return f


func target() -> int:
	return target_id


func describe() -> String:
	return "%s, target %d, swings %d" % [state, target_id, _swings]


func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["home"] = [home.x, home.y, home.z]
	d["home_known"] = _home_known
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	var h: Variant = d.get("home")
	if h is Array and (h as Array).size() == 3:
		home = Vector3(float(h[0]), float(h[1]), float(h[2]))
		_home_known = bool(d.get("home_known", true))
