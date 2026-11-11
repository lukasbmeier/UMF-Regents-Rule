extends NpcBrain
## A DEER'S BRAIN (hunting, Luke's H5, 2026-11-07; built 2026-11-09, HERBALISM_HUNTING_PREP.md §7 step 3): a creature
## that never fights. Its `FoeDef` (by its entity kind) says how far it sees and hears, how far it runs, how soon it
## calms and how far it wanders; the server STARTLES it on any hit (`regents.startle_ms`, status 109).
##
##   graze    round its home (its level point): a few steps at a walk to a spot within `graze_m`, then it stands
##            (its clip grazes) a while, and again
##   flee     a player in sight within `notice_m`, or heard within `startle_m`, or it was hit (startled: the nearest
##            player within `HIT_FLEE_M`, seen or not): it gallops `flee_m` straight away from them (round what is in
##            the way), never past `leash_m` from home; it keeps going while anyone is near, and calms `calm_ms` after
##            the last one was
##   home     calmed, away from home: it walks back, still watchful (a player seen sends it off again)
##   slain    lies still (the server's Slain status)
##
## It never asks to swing: the server's foe kit is for fighters, and a deer has none. A route is planned only when its
## goal changes (a new threat, the threat moved, a new grazing spot), not each think: a meadow of deer stays cheap.

const SLAIN: int = 106
const STARTLED: int = 109
## Home (and a grazing spot) is reached this near.
const HOME_M: float = 1.5
## Hit by someone it never saw: it runs from the nearest player this near.
const HIT_FLEE_M: float = 60.0
## A threat that has moved this far since it planned its flight: it plans again.
const REPLAN_M: float = 4.0
## Grazing, it stands this long (ms) between its few steps, somewhere between these.
const GRAZE_STAND_MIN_MS: int = 4000
const GRAZE_STAND_MAX_MS: int = 10000

var foe: FoeDef = null
var home: Vector3 = Vector3.ZERO
var _home_known: bool = false
## Who it is running from (0: nobody), where they were when it planned, and when anyone was last near.
var threat_id: int = 0
var _fled_from: Vector3 = Vector3.ZERO
var _last_near_ms: int = -1000000
## Grazing: when it next takes a few steps.
var _next_graze_ms: int = 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	state = &"graze"
	_rng.seed = seed_value


func think(me: MovementState, world: NpcWorldView) -> void:
	if me == null or world == null:
		return
	if foe == null:
		foe = FoeDef.by_kind(int(world.kinds.get(self_id, -1)))
		if foe == null:
			state = &"lost"
			return
	if not _home_known:
		home = me.pos
		_home_known = true
	if world.status_of(self_id) == SLAIN:
		state = &"slain"
		threat_id = 0
		clear_goal()
		return
	var now: int = now_ms()
	var scare: int = _scared_by(me, world)
	if scare != 0:
		_last_near_ms = now
		var at: Vector3 = world.state_of(scare).pos
		if state != &"flee" or scare != threat_id or _flat(at - _fled_from) > REPLAN_M or not has_goal():
			threat_id = scare
			_fled_from = at
			go_to(_flight_goal(me.pos, at), me, world)
		state = &"flee"
		return
	if state == &"flee":
		if now - _last_near_ms < foe.calm_ms:
			return   # where it ran to it stands, ears up, until it calms
		threat_id = 0
		state = &"home"
		clear_goal()   # its flight's goal is done with: home from here
	if state == &"home":
		if _flat(me.pos - home) > foe.graze_m:
			if not has_goal():
				go_to(home, me, world)
			return
		state = &"graze"
		clear_goal()
		_next_graze_ms = now + _rng.randi_range(GRAZE_STAND_MIN_MS, GRAZE_STAND_MAX_MS)
	# Grazing: stand, then a few steps to another spot near home.
	if has_goal() and _flat(me.pos - goal()) <= HOME_M:
		clear_goal()
		_next_graze_ms = now + _rng.randi_range(GRAZE_STAND_MIN_MS, GRAZE_STAND_MAX_MS)
	if not has_goal() and now >= _next_graze_ms and foe.graze_m > 0.0:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(0.3, 1.0) * foe.graze_m
		go_to(home + Vector3(cos(ang) * r, 0.0, sin(ang) * r), me, world)
		_next_graze_ms = now + GRAZE_STAND_MAX_MS * 3   # a guard: the next stand starts when it gets there


## Who scares it now (0: nobody): a player seen within `notice_m`, heard within `startle_m`, or (just hit) the nearest
## within `HIT_FLEE_M`. Slain players scare nobody.
func _scared_by(me: MovementState, world: NpcWorldView) -> int:
	if world.status_of(self_id) == STARTLED:
		var hitter: int = world.nearest_of_kind(me.pos, 0, HIT_FLEE_M, self_id)
		if hitter != 0 and world.status_of(hitter) != SLAIN:
			return hitter
	var near: int = world.nearest_of_kind(me.pos, 0, maxf(foe.notice_m, foe.startle_m), self_id)
	if near == 0 or world.status_of(near) == SLAIN:
		return 0
	var p: MovementState = world.state_of(near)
	if p == null:
		return 0
	var d: float = _flat(p.pos - me.pos)
	if d <= foe.startle_m or (d <= foe.notice_m and world.can_see(me.pos, p.pos)):
		return near
	return 0


## Where it runs to from a threat at `at`: `flee_m` straight away, pulled back inside `leash_m` of home (it runs along
## the edge of its range rather than out of it).
func _flight_goal(from: Vector3, at: Vector3) -> Vector3:
	var away: Vector3 = from - at
	away.y = 0.0
	if away.length() < 0.01:
		var ang: float = _rng.randf() * TAU
		away = Vector3(cos(ang), 0.0, sin(ang))
	var to: Vector3 = from + away.normalized() * foe.flee_m
	var off: Vector3 = to - home
	off.y = 0.0
	if off.length() > foe.leash_m:
		to = home + off.normalized() * foe.leash_m
		to.y = from.y
	return to


## It walks except when it runs for its life.
func walks() -> bool:
	return state != &"flee"


func target() -> int:
	return threat_id


func describe() -> String:
	return "%s from %d, home %s" % [state, threat_id, str(home)]


func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["home"] = [home.x, home.y, home.z]
	d["home_known"] = _home_known
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	if d.has("home"):
		home = NpcBrain._from_v3(d["home"], home)
		_home_known = bool(d.get("home_known", true))


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
