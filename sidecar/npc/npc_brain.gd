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
	var to: Vector3 = _goal - me.pos
	to.y = 0.0
	if to.length() < arrive_radius():
		_has_goal = false
		return f
	# `move_dir` is a WORLD direction — the client's input component has already rotated the
	# player's stick by their look angle before it reaches here (DECISIONS #100), so a brain that
	# produced a body-relative direction would walk in a circle.
	var dir: Vector3 = to.normalized()
	f.move_dir = Vector2(dir.x, dir.z)
	f.look_yaw = atan2(dir.x, dir.z) + PI   # face the way we are going: -Z is forward
	f.slow = walks()
	return f


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


func clear_goal() -> void:
	_has_goal = false


func has_goal() -> bool:
	return _has_goal


func goal() -> Vector3:
	return _goal
