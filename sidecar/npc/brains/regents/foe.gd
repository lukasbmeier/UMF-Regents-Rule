extends NpcBrain
## A FOE'S BRAIN (owner, 2026-10-19: the first enemies attack on sight): every foe has this one, and its
## `FoeDef` (by its entity kind) says how near it notices, how far it chases, how near it swings, and its
## rhythm. It fights with its kit exactly as a player does: the same abilities through `use_ability_as`,
## the same wind-ups, Swinging status, blocks, parries and flinches, judged by the same referee.
##
##   idle     stands at home (its level point)
##   chase    a player came within `notice_m` and in sight: runs at them, round what is in the way (the
##            level's walk map, `go_to`); out of sight, to where it last saw them, for `lose_sight_ms`
##   fight    within `reach_m`: stops, faces them, swings its kit's light combo, every `heavy_every`th
##            swing the heavy; each swing waits out the last one's lock, and a combo ends with `rest_ms`
##   return   past `leash_m` from home: walks back, deaf to players until it is home
##   slain    lies still (the server's Slain status)

const SLAIN: int = 106
## Home is reached this near.
const HOME_M: float = 1.5

var foe: FoeDef = null
var home: Vector3 = Vector3.ZERO
var target_id: int = 0
var returning: bool = false
var _home_known: bool = false
var _next_swing_ms: int = 0
var _swings: int = 0
var _step: int = 0
## Where to face this tick (in a fight), and whether to.
var _face: Vector3 = Vector3.ZERO
var _facing: bool = false
## Where it last saw its target, when, and whether it sees them now.
var _last_seen: Vector3 = Vector3.ZERO
var _seen_at_ms: int = 0
var _in_sight: bool = false


func _init(_seed_value: int = 0) -> void:
	state = &"idle"


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
	if world.status_of(self_id) == SLAIN:
		state = &"slain"
		target_id = 0
		clear_goal()
		return
	var from_home: float = Vector2(me.pos.x - home.x, me.pos.z - home.z).length()
	# Past the leash: home, deaf to everyone until it gets there.
	if returning or from_home > foe.leash_m:
		returning = from_home > HOME_M
		target_id = 0
		if returning:
			state = &"return"
			go_to(home, me, world)
			return
	_pick_target(me, world)
	if target_id == 0:
		state = &"idle"
		if from_home > HOME_M:
			go_to(home, me, world)
		else:
			clear_goal()
		return
	var t: MovementState = world.state_of(target_id)
	var to: Vector3 = t.pos - me.pos
	to.y = 0.0
	if to.length() > foe.reach_m or not _in_sight:
		state = &"chase"
		go_to(t.pos if _in_sight else _last_seen, me, world)
		return
	state = &"fight"
	clear_goal()
	_face = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	_facing = true
	if now_ms() >= _next_swing_ms:
		_swing(_face)


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
			if _in_sight or now_ms() - _seen_at_ms <= foe.lose_sight_ms:
				return
		target_id = 0
	var found: int = world.nearest_of_kind(me.pos, 0, foe.notice_m, self_id)
	if found == 0 or world.status_of(found) == SLAIN:
		return
	var cand: MovementState = world.state_of(found)
	if cand != null and world.can_see(me.pos, cand.pos):
		target_id = found
		_in_sight = true
		_last_seen = cand.pos
		_seen_at_ms = now_ms()


## One swing of its kit, aimed `aim`: the combo's next light, or the heavy every `heavy_every`th. The next
## waits out its lock, and a combo's end (or a heavy) adds `rest_ms`.
func _swing(aim: Vector3) -> void:
	var kit: KitDef = foe.kit
	var a: AbilityDef = null
	_swings += 1
	var heavy: bool = foe.heavy_every > 0 and kit.heavy != null and _swings % foe.heavy_every == 0
	if heavy:
		a = kit.heavy
		_step = 0
	else:
		a = kit.light[_step % kit.light.size()]
		_step += 1
	use_ability(a.id, aim, target_id)
	var wait: int = kit.lock_ms(a)
	if heavy or _step >= kit.light.size():
		_step = 0
		wait += foe.rest_ms
	_next_swing_ms = now_ms() + wait


func frame(me: MovementState) -> InputFrame:
	if not _facing:
		return super(me)
	# In a fight it stands and faces its target (-Z is forward), so its swings sweep at them.
	var f := InputFrame.new()
	f.look_yaw = atan2(_face.x, _face.z) + PI
	f.face = true
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
