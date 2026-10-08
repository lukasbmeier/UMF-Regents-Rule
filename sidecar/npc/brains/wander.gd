class_name WanderBrain extends NpcBrain
## Ambles. Picks somewhere nearby, walks to it, waits a moment, picks again.
##
## It deliberately does NOT use the navmesh. A navmesh point is the better answer on a level that
## has one, and most do not — the greybox does not, and a genre's first level usually does not
## either. Walking at a point and giving up when the walk stops making progress works anywhere
## and degrades into "mills about near a wall" instead of into "stands still forever", which is
## what a navmesh brain does on a level with no navmesh baked (`docs/SIDECAR_SPEC.md` §3 leaves
## `NavigationServer3D` as the upgrade for a level that has one).

## How far from home it is willing to get.
@export var roam_radius: float = 8.0
## How long it stands still between walks, in seconds of think ticks.
@export var rest_sec: float = 1.5
## Progress slower than this counts as being stuck against something.
@export var stuck_speed: float = 0.25

var home: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _rest_left: float = 0.0
var _stuck_for: float = 0.0


func _init(seed_value: int = 0) -> void:
	# Seeded per entity, so two NPCs spawned in the same tick do not walk in lockstep.
	_rng.seed = hash(seed_value)
	state = &"wander"


func think(me: MovementState, _world: NpcWorldView) -> void:
	if me == null:
		return
	var dt: float = 1.0 / 10.0   # think_hz; only used for the two timers below
	if _rest_left > 0.0:
		_rest_left -= dt
		state = &"rest"
		clear_goal()
		return
	if has_goal():
		# Stuck against something the goal is on the far side of: take the rest early and pick
		# somewhere else. Without this it leans on a wall for the whole session.
		if Vector2(me.vel.x, me.vel.z).length() < stuck_speed:
			_stuck_for += dt
			if _stuck_for > 0.7:
				_stuck_for = 0.0
				_rest_left = rest_sec
				clear_goal()
		else:
			_stuck_for = 0.0
		return
	state = &"wander"
	_rest_left = rest_sec
	var angle: float = _rng.randf_range(-PI, PI)
	var dist: float = _rng.randf_range(roam_radius * 0.3, roam_radius)
	set_goal(home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist))
	_rest_left = 0.0


func walks() -> bool:
	return true


## HOME is the one that matters. Without it a restarted sidecar takes wherever the NPC happens to
## be standing as its new home, and every restart walks it further across the level.
##
## Decisions only: the rest countdown ticks every think, and persisting it would rewrite the row
## once a second for no decision at all. A restarted brain simply rests from the top.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["home"] = _v3(home)
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	home = _from_v3(d.get("home"), home)


func describe() -> String:
	return "home (%.2f, %.2f, %.2f)" % [home.x, home.y, home.z]
