class_name NpcBrain extends RefCounted
## What an NPC wants to do, expressed as the same input a player sends.
##
## A brain NEVER writes a position. It answers "which way would this character push the stick
## this tick", and the ordinary movement path turns that into motion — same model, same collision
## resolver, same seq bookkeeping as a player (`docs/SIDECAR_SPEC.md` §3). That is what keeps an
## NPC subject to the walls, the gravity and the speeds everyone else is subject to, instead of
## sliding through the world on a separate set of rules.
##
## THINKING AND MOVING RUN AT DIFFERENT RATES. `think()` is called a few times a second and is
## where the expensive questions go (who is nearby, where shall I go, is there a wall in the
## way); `frame()` is called every physics tick and only reads what `think` decided. A brain that
## did its reasoning per tick would cost sixty times as much for no better behaviour.
##
## DOING THINGS (milestone 7, DECISIONS #230): besides where it goes, a brain may ask, from `think`, to
## hold something (`hold`: a nest, a gate, a downed hen), to let go (`let_go`) and to use an ability
## (`use_ability`). Its component sends each as the authority's reducer (`begin_interact_as`,
## `end_interact_as`, `use_ability_as`): the server judges a bot's hold or pounce exactly as a player's.
##
## GOING ROUND THINGS: `go_to(p, world)` asks the world for a path its body fits (`NpcNav`, from the
## level's collision) and walks it; with no level, straight there.
##
## A GENRE'S BRAINS: `res://sidecar/npc/brains/<name>.gd` (a genre's in its own folder, named
## `chicken/hen`), extending this, made with the seed: `NpcBrainComponent.make_brain`.
##
## SERVER-ONLY (hard rule 7b): brains live under `sidecar/`, which the client export excludes.

## What this brain is doing, for `write_npc_brain` and for the debug overlay. Short and stable:
## it goes on the wire.
var state: StringName = &"idle"
## The entity this brain is attached to, and the world it can see. Set by NpcBrainComponent.
var self_id: int = 0

## Where the brain wants to go, in world space. `frame()` steers towards it; a brain that has
## nowhere to go leaves it at the character's own position and stands still.
var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
## Its body (its character's capsule): what it fits through. Set by its component.
var body_radius: float = 0.35
var body_height: float = 1.8
## The way to the goal, when it was asked to go round things: points still to pass, nearest first.
var _route: PackedVector3Array = PackedVector3Array()
## What it asked to do since its component last looked: [{do, ...}].
var _acts: Array[Dictionary] = []


## Called at `think_hz`. `me` is this entity's simulated state; `world` gives access to the
## others. Override this: it is where a brain's behaviour lives.
func think(_me: MovementState, _world: NpcWorldView) -> void:
	pass


## Called every physics tick. The default steers at whatever `think` last chose as a goal, which
## is all most brains need; override for anything that has to react per tick.
func frame(me: MovementState) -> InputFrame:
	var f := InputFrame.new()
	if not _has_goal or me == null:
		return f
	# A route: the next point on it, passed ones dropped (the goal is its last).
	while _route.size() > 1 and Vector2(_route[0].x - me.pos.x, _route[0].z - me.pos.z).length() < WAYPOINT_M:
		_route.remove_at(0)
	var aim: Vector3 = _route[0] if not _route.is_empty() else _goal
	var to: Vector3 = aim - me.pos
	to.y = 0.0
	if _route.size() <= 1 and Vector2(_goal.x - me.pos.x, _goal.z - me.pos.z).length() < arrive_radius():
		_has_goal = false
		_route.clear()
		return f
	if to.length() < 0.01:
		return f
	# `move_dir` is a WORLD direction — the client's input component has already rotated the
	# player's stick by their look angle before it reaches here (DECISIONS #100), so a brain that
	# produced a body-relative direction would walk in a circle.
	var dir: Vector3 = to.normalized()
	f.move_dir = Vector2(dir.x, dir.z)
	f.look_yaw = atan2(dir.x, dir.z) + PI   # face the way we are going: -Z is forward
	f.slow = walks()
	return f


## How near a route's point counts as passed.
const WAYPOINT_M: float = 0.5


## How close counts as arrived. Smaller than this and the character jitters on the spot, because
## one tick of movement overshoots the goal and the next one turns around.
func arrive_radius() -> float:
	return 0.6


## True for a brain that should amble rather than run. Wildlife walks; a rival runs.
func walks() -> bool:
	return false


## What this brain needs in order to CARRY ON after the sidecar restarts, rather than start
## over. JSON-able — it goes in `npc_brain.data` (SIDECAR_SPEC §3) — and small: a brain's
## memory, not a save file. The base keeps the goal; a brain adds whatever else it would lose.
func save_state() -> Dictionary:
	return {"goal": _v3(_goal), "has_goal": _has_goal}


## The reverse of `save_state`. Missing keys leave the fresh brain's defaults: a row written by
## an older version of the brain is not an error.
func load_state(d: Dictionary) -> void:
	if d.has("goal"):
		_goal = _from_v3(d["goal"], _goal)
	_has_goal = bool(d.get("has_goal", _has_goal))


## Who the brain is after, for `npc_brain.target_id`. 0 for nobody.
func target() -> int:
	return 0


## One line about what the brain remembers, for the sidecar's log.
func describe() -> String:
	return "goal %s" % (str(_goal) if _has_goal else "none")


static func _v3(v: Vector3) -> Array[float]:
	return [v.x, v.y, v.z]


static func _from_v3(a: Variant, fallback: Vector3) -> Vector3:
	if not (a is Array) or (a as Array).size() != 3:
		return fallback
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func set_goal(p: Vector3) -> void:
	_goal = p
	_has_goal = true
	_route.clear()


## GO THERE, ROUND WHAT IS IN THE WAY: a path its body fits (`world.path`), walked point by point; with
## none (no level, no way found yet), straight at it, as `set_goal`.
func go_to(p: Vector3, me: MovementState, world: NpcWorldView) -> void:
	_goal = p
	_has_goal = true
	_route = world.path(me.pos, p, body_radius, body_height) if world != null and me != null else PackedVector3Array()
	if not _route.is_empty():
		_route.remove_at(0)   # where it stands
		if _route.is_empty() or Vector2(_route[_route.size() - 1].x - p.x, _route[_route.size() - 1].z - p.z).length() > 1.0:
			_route.append(p)   # the mesh's nearest point fell short: the last stretch straight


## The points it still means to pass (for tests and the log).
func route() -> PackedVector3Array:
	return _route


func clear_goal() -> void:
	_has_goal = false
	_route.clear()


## HOLD `target_id` (its press `verb`, 0: interact): the server begins the hold its content says, as a
## player's press of E. Asked from `think`; sent once.
func hold(target_id: int, verb: int = 0) -> void:
	_acts.append({"do": "hold", "target": target_id, "verb": verb})


## Let go of whatever it holds.
func let_go() -> void:
	_acts.append({"do": "let_go"})


## Use ability `ability_id` (aimed `aim`, a world direction; at `target_id`, or 0).
func use_ability(ability_id: int, aim: Vector3, target_id: int = 0) -> void:
	_acts.append({"do": "ability", "ability": ability_id, "aim": aim, "target": target_id})


## What it asked to do since the last call, oldest first; the list is emptied.
func take_acts() -> Array[Dictionary]:
	var out: Array[Dictionary] = _acts
	_acts = []
	return out


func has_goal() -> bool:
	return _has_goal


func goal() -> Vector3:
	return _goal
