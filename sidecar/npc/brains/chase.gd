class_name ChaseBrain extends NpcBrain
## Runs at the nearest player it can see, and wanders when it cannot see one.
##
## The chase half is what `docs/PHASE3_SPEC.md` Task 14 specifies; the wander half matters as
## much in practice, because a predator that stands still whenever nobody is in sight reads as
## broken rather than as patient.

## Kind 0 is the player (EntityDefinition.kind; a genre numbers its own from 100).
@export var target_kind: int = 0
@export var sight_radius: float = 18.0
## Once chasing, it keeps going a bit past sight range rather than giving up at the boundary and
## re-acquiring a tick later, which makes it stutter on the spot.
@export var give_up_radius: float = 24.0

var target_id: int = 0
var _idle: WanderBrain = null


func _init(seed_value: int = 0) -> void:
	_idle = WanderBrain.new(seed_value)
	state = &"idle"


func think(me: MovementState, world: NpcWorldView) -> void:
	if me == null or world == null:
		return
	_idle.home = _idle.home if _idle.home != Vector3.ZERO else me.pos
	var keep: bool = false
	if target_id != 0:
		var held: MovementState = world.state_of(target_id)
		keep = held != null and me.pos.distance_to(held.pos) <= give_up_radius \
			and world.can_see(me.pos, held.pos)
	if not keep:
		target_id = 0
		var found: int = world.nearest_of_kind(me.pos, target_kind, sight_radius, self_id)
		if found != 0:
			var cand: MovementState = world.state_of(found)
			if cand != null and world.can_see(me.pos, cand.pos):
				target_id = found
	if target_id == 0:
		state = &"idle"
		_idle.think(me, world)
		return
	state = &"chase"
	var t: MovementState = world.state_of(target_id)
	if t != null:
		set_goal(t.pos)


func frame(me: MovementState) -> InputFrame:
	if target_id == 0:
		return _idle.frame(me)
	return super(me)


func walks() -> bool:
	return false   # chasing runs


func target() -> int:
	return target_id


func describe() -> String:
	return "target %d, %s" % [target_id, _idle.describe()]


## Who it was after, and — through its idle half — where it roams when it has lost them.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["target_id"] = target_id
	d["idle"] = _idle.save_state()
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	target_id = int(d.get("target_id", target_id))
	var idle: Variant = d.get("idle")
	if idle is Dictionary:
		_idle.load_state(idle)
