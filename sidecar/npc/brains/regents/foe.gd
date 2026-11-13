class_name RegentsFoeBrain extends NpcBrain
## A FOE'S BRAIN (owner, 2026-10-19: the first enemies attack on sight): every foe has this one, and its
## `FoeDef` (by its entity kind) says how near it notices, how far it chases, how near it swings, and its
## rhythm. It fights with its own FOE KIT (COMBAT_OVERHAUL.md §2: slow, readable swings) through
## `use_ability_as`, judged by the same referee and the same `hit` as a player's.
##
##   idle     at rest round its home (its level point): a stand, then a few steps at a walk to a spot within
##            `wander_m`, and again (Luke's F10, 2026-11-13); back from a fight, home first
##   NOTICING (Luke's F9, 2026-11-13): it SEES a player within `notice_m`, in sight and inside `notice_arc_deg` in front
##            of it, and HEARS one all round within `hear_m` (`hear_sprint_m` sprinting), seen or not
##   chase    a player noticed: runs at them, round what is in the way (the
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
## ITS TREE (Luke's F2, 2026-11-12; `FOES_PREP.md` section 3.1): WHAT it does first is a LimboAI behavior tree,
## `trees/<FoeDef.behavior>.tres` ("melee": the states above, in that order), stepped once a think. Each task of a tree
## (`tasks/`) calls one STEP of this brain (`be_slain`, `go_home`, `rest`, `chase`, `wait_turn`, `close_in`, `swing`);
## this script keeps what a foe knows (its target, its turn, its string, its pack, its aim). A new KIND of foe is a
## new tree, with new steps here and tasks for them; a foe is given it by `FoeDef.behavior`.
##
## A FOE THAT SHOOTS (Luke's F1-F6, 2026-11-12; `trees/ranged.tres`, the skeleton archer): after `rest` it minds, in
## order: `hold_lock` (mid-draw or mid-shove it stands), `shove` (its target in reach: its string), `step_back` (its
## target within `back_within_m`: `back_m` away at a walk, at most every `back_every_ms`), `approach` (out of sight or
## past `shot_range_m`: in), `shoot` (it stands and draws its shot, `shot_rest_ms` between two). A SHOT'S TURN is its
## own (`shots`, `regents.ranged_tokens`: one foe drawing on or with a shot in the air at a player), never a melee
## turn, and it keeps the gap from every other foe's hit (it counts when its arrow arrives). The server aims and
## flies the shot (PROGRESS step 64); this only says when, and at whom.
##
## AIM: it turns to follow its target through a swing's wind-up and stops turning
## `regents.foe_aim_lock_ms` before the hit lands. The referee sweeps along the way it faces AT the
## landing (its movement history), so a step aside late in the wind-up slips the swing; one early does not.

const SLAIN: int = 106
## The server's Startled (`content/status/startled.tres`): set on ANY fighting foe hit while it does nothing else
## (Luke, 2026-11-11: "Every foe", not pack foes only), so one hit from beyond its sight turns on who hit it: the
## status row's `by_entity` (Luke's F11, 2026-11-13: WHO HIT IT, not the nearest).
const STATUS_STARTLED: int = 109
## At rest, it stands this long (at random between the two) before its next few steps (F10).
const WANDER_STAND_MIN_MS: int = 4000
const WANDER_STAND_MAX_MS: int = 10000
## A wander's few steps that have not got there in this long are over (something was in the way).
const WANDER_MAX_MS: int = 6000
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
const RANGED_TOKENS: StringName = &"regents.ranged_tokens"
## A step back that has not got there in this long is over (something was in the way).
const BACK_MAX_MS: int = 4000
## A step back ends this near where it was going.
const BACK_NEAR_M: float = 0.6
## Walking in to shoot, it stops this far inside its range (never nearer than `shot_near_m`).
const RANGE_IN_M: float = 2.0
## Its shot is counted in the air this long past when it should arrive.
const SHOT_SETTLE_MS: int = 200

## Per player, the turns of every foe this referee runs: target id -> {"holders": {foe id: ms last kept},
## "land_ms": when the last foe swing on them lands}.
static var turns: Dictionary[int, Dictionary] = {}
## PACKS (Luke, 2026-11-10: wolves hunt in packs of 2-3): each fighting pack foe reports its target here
## (`self_id` -> {"kind": kind, "pos": Vector3, "target": target_id, "last_seen": Vector3, "at": _seen_at_ms}),
## so packmates of its kind within `foe.pack_m` join in.
static var packs: Dictionary[int, Dictionary] = {}

## Per player, the foes drawing on them or with a shot in the air (`regents.ranged_tokens`): target id ->
## {foe id: the ms its shot is over}.
static var shots: Dictionary[int, Dictionary] = {}

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
## Stepping back: it goes to its goal at its own pace (no slow walk) while facing `_face`.
var _backing: bool = false
## Where it last saw its target, when, and whether it sees them now.
var _last_seen: Vector3 = Vector3.ZERO
var _seen_at_ms: int = 0
var _in_sight: bool = false
var _rng := RandomNumberGenerator.new()
## This think's reading of its target, set by `rest` for the steps after it: who (null: nobody, or `rest` has not
## run), the way and how far to them, the time, and whether its string is under way.
var _t: MovementState = null
var _to: Vector3 = Vector3.ZERO
var _dist: float = 0.0
var _now: int = 0
var _mid_string: bool = false
## Whether its status lets it act this think (not Staggered, Flinched, Slain): set by `rest`.
var _can_act: bool = true
var _tree_missing: bool = false
## A foe that shoots: its shots so far, when the next may be drawn, its step back (where to, until when; -1: none)
## and when the next may begin, and whether it is walking in to its range.
var _shots: int = 0
var _next_shot_ms: int = 0
var _back_to: Vector3 = Vector3.ZERO
var _back_until_ms: int = -1
var _next_back_ms: int = 0
var _closing: bool = false
## At rest (F10): walking to a wander's spot (it walks, `walks`), until when, and when the next may begin (0: not yet set).
var _wandering: bool = false
## Walking home after a fight, until it is there (then it wanders again).
var _homing: bool = false
var _wander_until_ms: int = 0
var _next_wander_ms: int = 0

## TESTING: who put entity `id` in its status (`status_by`), in place of the status row's `by_entity`.
var status_by_of: Callable = Callable()

## Where the foes' trees are: one a behavior (`FoeDef.behavior`).
const TREES_DIR: String = "res://sidecar/npc/brains/regents/trees/"


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
	_backing = false
	_t = null
	# ITS TREE (Luke's F2, 2026-11-12): the first of its tasks that is its to do, each think. The steps below are
	# what the tasks call; the tree puts them in order.
	var path: String = tree_path(foe.behavior)
	if not ResourceLoader.exists(path):
		if not _tree_missing:
			push_warning("RegentsFoeBrain %d: no behavior tree '%s' (%s); it stands still." % [self_id, foe.behavior, path])
			_tree_missing = true
		state = &"lost"
		clear_goal()
		return
	run_tree(path, me, world)


## Where the tree of behavior `behavior` (`FoeDef.behavior`: "melee") is.
static func tree_path(behavior: StringName) -> String:
	return TREES_DIR + String(behavior) + ".tres"


# --- the steps (its tree's tasks call these; true: it was this step's to do, and it is done for this think) ---

## SLAIN: it lies still, its turn and its pack's word given up.
func be_slain(world: NpcWorldView) -> bool:
	if world.status_of(self_id) != SLAIN:
		return false
	state = &"slain"
	_let_turn_go()
	packs.erase(self_id)
	target_id = 0
	clear_goal()
	return true


## PAST THE LEASH: home, deaf to everyone until it gets there.
func go_home(me: MovementState, world: NpcWorldView) -> bool:
	var from_home: float = _from_home(me)
	if not returning and from_home <= foe.leash_m:
		return false
	returning = from_home > HOME_M
	if not returning:
		return false
	_let_turn_go()
	packs.erase(self_id)
	target_id = 0
	state = &"return"
	go_to(home, me, world)
	return true


## IT LOOKS FOR SOMEONE TO FIGHT (the one it has, the nearest it sees in front or hears, who hit it, its pack's).
## Nobody: it rests round its home (it wanders, `_wander`), and that was this step's to do. Somebody: it reads where they are for the steps after this one
## (never put a fighting step above this one in a tree: it would have nobody to fight).
func rest(me: MovementState, world: NpcWorldView) -> bool:
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
		_wander(me, world)
		return true
	_wandering = false
	_t = world.state_of(target_id)
	# WHETHER IT MAY ACT (Luke, 2026-11-13: parried, a skeleton went "straight to hit 3"): staggered or flinched, its
	# next swing or cast is not sent to be refused, which used up a step of its string; it waits, and goes on after.
	var st: StatusDef = StatusDef.find(world.status_of(self_id))
	_can_act = st == null or st.can_act
	_to = _t.pos - me.pos
	_to.y = 0.0
	_dist = _to.length()
	_now = now_ms()
	# ITS STRING FOLLOWS ITS TARGET (Luke, 2026-11-11): between two swings (the last one's lock over), a target out of
	# reach, or of sight, for longer than `string_chase_ms` loses it the string: the next is its first swing again.
	if _step > 0 and _now - _lock_end_ms > foe.string_chase_ms and (_dist > foe.reach_m or not _in_sight):
		_drop_string()
	_mid_string = _step > 0 or _now < _lock_end_ms
	return false


## OUT OF SIGHT, OR FAR: it runs at them (to where it last saw them), round what is in the way. Near enough to
## fight or circle (inside its reach, or the circle's and a little), or mid-string, is not this step's.
func chase(me: MovementState, world: NpcWorldView) -> bool:
	if _t == null:
		return false
	var near: bool = _dist <= foe.reach_m + CIRCLE_M + 1.0
	if _in_sight and (near or _mid_string):
		return false
	_let_turn_go()
	state = &"chase"
	go_to(_t.pos if _in_sight else _last_seen, me, world)
	return true


## NO TURN ON THEM: it circles, facing them, until one is free. Its aim follows them here and in the steps after
## (except in the last `AIM_LOCK` before a hit lands). Holding a turn (kept, or just taken) is not this step's.
func wait_turn(me: MovementState, world: NpcWorldView) -> bool:
	if _t == null:
		return false
	var locked: bool = _land_ms >= 0 and _now >= _land_ms - aim_lock_ms() and _now < _land_ms + AIM_SETTLE_MS
	if not locked:
		_face = _to.normalized() if _dist > 0.01 else Vector3.FORWARD
	if _keep_turn(_now):
		return false
	state = &"circle"
	_facing = true
	_circle(me, _t, world)
	return true


## ITS TURN, AND THEY ARE OUT OF ITS REACH: in to its reach. Mid-string too, once the last swing's lock is over (it
## cannot move before): it closes the gap and the string goes on where it stopped, never a swing at the air.
func close_in(me: MovementState, world: NpcWorldView) -> bool:
	if _t == null or _dist <= foe.reach_m or (_mid_string and _now < _lock_end_ms):
		return false
	state = &"chase"
	go_to(_t.pos, me, world)
	return true


## IN REACH, ITS TURN: it stands, faces them and swings its string, each swing after the last one's lock.
func swing() -> bool:
	if _t == null:
		return false
	state = &"fight"
	_facing = true
	clear_goal()
	if _now >= _next_swing_ms and _can_act:
		_swing_if_spaced(_now)
	return true


# --- the steps of a foe that shoots (`trees/ranged.tres`) ---

## Its aim follows its target, except in the last `AIM_LOCK` before its swing lands or its shot is loosed.
func _follow_aim() -> void:
	var locked: bool = _land_ms >= 0 and _now >= _land_ms - aim_lock_ms() and _now < _land_ms + AIM_SETTLE_MS
	if not locked:
		_face = _to.normalized() if _dist > 0.01 else Vector3.FORWARD


## MID-DRAW, OR MID-SHOVE: it stands where it is, facing them, until that move's lock is over. This is its
## opening: it cannot step back or turn away from a draw it has begun.
func hold_lock() -> bool:
	if _t == null or _now >= _lock_end_ms:
		return false
	_follow_aim()
	state = &"fight"
	_facing = true
	clear_goal()
	return true


## CAUGHT (its target in its reach, in sight, and a melee turn free): its string, a shove. No turn: not this step's
## (it steps back or shoots instead of circling).
func shove() -> bool:
	if _t == null or not _in_sight or _dist > foe.reach_m:
		return false
	_follow_aim()
	if not _keep_turn(_now):
		return false
	return swing()


## IT KEEPS ITS DISTANCE, AND IS CAUGHT (Luke's F3): its target within `back_within_m`, it backs `back_m` straight
## away from them at its own pace, facing them, at most once every `back_every_ms` (counted from the step's end) and never past its
## leash. Between two steps it stands its ground.
func step_back(me: MovementState, world: NpcWorldView) -> bool:
	if _t == null or foe.back_m <= 0.0:
		return false
	if _back_until_ms < 0:
		if not _in_sight or _dist > foe.back_within_m or _now < _next_back_ms:
			return false
		var away: Vector3 = (-_to).normalized() if _dist > 0.01 else Vector3.BACK
		var spot: Vector3 = me.pos + away * foe.back_m
		if Vector2(spot.x - home.x, spot.z - home.z).length() > foe.leash_m - 1.0:
			_next_back_ms = _now + foe.back_every_ms
			return false
		_back_to = spot
		_back_until_ms = _now + BACK_MAX_MS
	if _now >= _back_until_ms or Vector2(me.pos.x - _back_to.x, me.pos.z - _back_to.z).length() <= BACK_NEAR_M:
		_back_until_ms = -1
		_next_back_ms = _now + foe.back_every_ms
		return false
	_let_turn_go()
	_follow_aim()
	state = &"back"
	_facing = true
	_backing = true   # backing off at its own pace, facing its target (`frame`)
	go_to(_back_to, me, world)
	return true


## OUT OF SIGHT, OR PAST ITS RANGE: in, round what is in the way (out of sight: to where it last saw them), until
## they are in sight and a little inside `shot_range_m` (never nearer than `shot_near_m`).
func approach(me: MovementState, world: NpcWorldView) -> bool:
	if _t == null:
		return false
	var stop_m: float = maxf(foe.shot_near_m, foe.shot_range_m - RANGE_IN_M)
	if not _in_sight or _dist > foe.shot_range_m:
		_closing = true
	elif _dist <= stop_m:
		_closing = false
	if not _closing:
		return false
	_let_turn_go()
	state = &"chase"
	go_to(_t.pos if _in_sight else _last_seen, me, world)
	return true


## IN RANGE AND IN SIGHT: it stands, faces them, and draws its shot when it is rested, a shot's turn is free
## (`regents.ranged_tokens`) and its arrow would arrive at least the gap after every other foe's hit. The server
## flies it at where they stand as the aim locks.
func shoot() -> bool:
	if _t == null or not _in_sight:
		return false
	_follow_aim()
	state = &"aim"
	_facing = true
	clear_goal()
	var a: AbilityDef = foe.cast_at(_shots)   # its shot, or every so often its ring (`FoeDef.ring_every`)
	if a == null or _now < _next_shot_ms or not _can_act:
		return true
	var holders: Dictionary = _shot_holders(_now)
	if not holders.has(self_id) and holders.size() >= ranged_tokens():
		return true
	var spell: SpellDef = SpellDef.by_ability(a.id)
	var flight_ms: int = int(_dist / maxf(spell.speed_mps if spell != null else 30.0, 1.0) * 1000.0)
	if spell != null and spell.kind == SpellDef.Kind.AREA:
		flight_ms = spell.delay_ms   # a ring: from its cast's end until it fills
	var lands: int = _now + a.wind_up_ms + flight_ms
	var turn: Dictionary = _turn(_now)
	var last: int = int(turn["land_ms"])
	if last >= 0 and lands < last + gap_ms():
		return true   # too soon after another's hit: it waits a think
	turn["land_ms"] = maxi(last, lands)
	holders[self_id] = lands + SHOT_SETTLE_MS
	_shots += 1
	use_ability(a.id, _face, target_id)
	_land_ms = _now + a.wind_up_ms
	_lock_end_ms = _now + foe.kit.lock_ms(a)
	_next_shot_ms = _lock_end_ms + foe.shot_rest_ms
	return true


## Who is drawing on its target or has a shot in the air at them, those whose shot is over dropped.
func _shot_holders(now: int) -> Dictionary:
	var holders: Dictionary = shots.get(target_id, {})
	if not shots.has(target_id):
		shots[target_id] = holders
	for id: int in holders.keys():
		if now >= int(holders[id]):
			holders.erase(id)
	return holders


func ranged_tokens() -> int:
	return maxi(0, int(HotRules.number(RANGED_TOKENS)))   # 0: no foe shoots


func _from_home(me: MovementState) -> float:
	return Vector2(me.pos.x - home.x, me.pos.z - home.z).length()


## AT REST IT WANDERS (Luke's F10, 2026-11-13): it stands a while, then walks a few steps to a spot within `wander_m`
## of home, and again; so it faces about, and a camp can be come at from behind. Further from home than that (back
## from a fight) it goes home first, at its own pace. `wander_m` 0: it stands at home, as the first build did.
func _wander(me: MovementState, world: NpcWorldView) -> void:
	var now: int = now_ms()
	var from_home: float = _from_home(me)
	# Back from a fight (past its wander), or one that stands: home, ALL THE WAY (not to the wander's edge).
	if foe.wander_m <= 0.0 or from_home > foe.wander_m + HOME_M:
		_homing = true
	if _homing:
		_wandering = false
		if from_home > HOME_M:
			go_to(home, me, world)
			return
		_homing = false
		clear_goal()
		_next_wander_ms = 0
		if foe.wander_m <= 0.0:
			return
	if _wandering:
		if has_goal() and now < _wander_until_ms:
			return   # still on its way
		_wandering = false
		_next_wander_ms = 0
	if _next_wander_ms == 0:
		clear_goal()
		_next_wander_ms = now + _rng.randi_range(WANDER_STAND_MIN_MS, WANDER_STAND_MAX_MS)
	if now < _next_wander_ms:
		return
	var ang: float = _rng.randf() * TAU
	var r: float = _rng.randf_range(0.3, 1.0) * foe.wander_m
	go_to(home + Vector3(cos(ang) * r, 0.0, sin(ang) * r), me, world)
	_wandering = true
	_wander_until_ms = now + WANDER_MAX_MS


## Wandering at rest it walks; everything else at its own pace.
func walks() -> bool:
	return _wandering


## WHO IT NOTICES (Luke's F9, 2026-11-13): the nearest player who is up and either SEEN (`sees`) or HEARD (`hears`).
## 0: nobody.
func _notice(me: MovementState, world: NpcWorldView) -> int:
	var reach: float = maxf(foe.notice_m, maxf(foe.hear_m, foe.hear_sprint_m))
	var best: int = 0
	var best_d: float = INF
	for id: int in world.all_of_kind(0):
		if id == self_id or world.status_of(id) == SLAIN:
			continue
		var p: MovementState = world.state_of(id)
		if p == null:
			continue
		var d: float = Vector2(p.pos.x - me.pos.x, p.pos.z - me.pos.z).length()
		if d > reach or d >= best_d:
			continue
		if hears(p, d) or sees(me, p, d, world):
			best = id
			best_d = d
	return best


## IT SEES `p` (`d` off): within `notice_m`, inside `notice_arc_deg` in front of it, and in sight.
func sees(me: MovementState, p: MovementState, d: float, world: NpcWorldView) -> bool:
	return d <= foe.notice_m and in_front(me.yaw, p.pos - me.pos, foe.notice_arc_deg) and world.can_see(me.pos, p.pos)


## IT HEARS `p` (`d` off) all round, seen or not: within `hear_m`, or `hear_sprint_m` if they sprint.
func hears(p: MovementState, d: float) -> bool:
	var sprinting: bool = Vector2(p.vel.x, p.vel.z).length() > sprint_heard_mps()
	return d <= foe.hear_m or (sprinting and d <= foe.hear_sprint_m)


## Faster than this on the flat is a SPRINT: halfway between a run and a sprint (`shared/movement_config.json`).
static func sprint_heard_mps() -> float:
	var c: MovementConfig = MovementConfig.shared()
	return (c.run_speed + c.sprint_speed) * 0.5


## Whether a body facing `yaw` (-Z forward, as every body here) has `to` (flat) inside `arc_deg` in front of it. 360
## is all round; a point on top of it is in front.
static func in_front(yaw: float, to: Vector3, arc_deg: float) -> bool:
	var flat: Vector2 = Vector2(to.x, to.z)
	if arc_deg >= 360.0 or flat.length() < 0.01:
		return true
	var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	return fwd.dot(flat.normalized()) >= cos(deg_to_rad(arc_deg * 0.5)) - 1e-6


## Who put entity `id` in its status: the server's `by_entity` on its status row (0: nobody, or no row).
func status_by(id: int) -> int:
	if status_by_of.is_valid():
		return int(status_by_of.call(id))
	var row: RefCounted = SpaceTimeSync.get_row(&"status_state", id)
	return int(row.get(&"by_entity")) if row != null else 0


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
	var found: int = _notice(me, world)
	if found != 0:
		var cand: MovementState = world.state_of(found)
		target_id = found
		_in_sight = world.can_see(me.pos, cand.pos)   # heard from behind a rock: after where it was heard
		_last_seen = cand.pos
		_seen_at_ms = now_ms()
		return
	# Hit from beyond its sight (the server's Startled): it turns on WHO HIT IT (F11), if they are up and inside its
	# leash; with no word of who (an older server), on the nearest player within twice its leash.
	if world.status_of(self_id) == STATUS_STARTLED:
		var shooter: int = status_by(self_id)
		if shooter == 0 or int(world.kinds.get(shooter, -1)) != 0:
			shooter = world.nearest_of_kind(me.pos, 0, foe.leash_m * 2.0, self_id)
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
	var f: InputFrame = super(me) if (_circling or _backing) else InputFrame.new()
	f.look_yaw = atan2(_face.x, _face.z) + PI
	f.face = true
	if _circling:
		f.slow = true
	return f


func target() -> int:
	return target_id


func describe() -> String:
	return "%s, target %d, swings %d, shots %d" % [state, target_id, _swings, _shots]


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
