class_name NpcWorldView extends RefCounted
## What a brain is allowed to know. Built once per think tick and handed to `NpcBrain.think`.
##
## It exists so a brain cannot reach for whatever it likes. Everything here comes from the
## authoritative simulation this process is already running — no rows, no SDK, no scene lookups —
## which means a brain is a pure function of the world state and can be tested by handing it a
## made-up one (`docs/SIDECAR_SPEC.md` §3).
##
## SERVER-ONLY (hard rule 7b).

## entity_id -> its simulated state, this tick. Includes the asking NPC.
var states: Dictionary[int, MovementState] = {}
## entity_id -> definition kind, so a brain can tell a player from a fish.
var kinds: Dictionary[int, int] = {}
## Space to raycast against, for line of sight. Null in a test with no level.
var space: PhysicsDirectSpaceState3D = null
## Collision mask for a line-of-sight test: the world, not other entities.
var world_mask: int = 1


## ONE SNAPSHOT PER PHYSICS TICK, shared by every brain that asks for it. Each brain needs to
## know about every entity, so building a view per brain would be quadratic in the number of
## NPCs — at ten think ticks a second that is the difference between nothing and something.
static var _cache: NpcWorldView = null
static var _cache_frame: int = -1


static func current(space: PhysicsDirectSpaceState3D = null) -> NpcWorldView:
	var frame: int = Engine.get_physics_frames()
	if _cache != null and _cache_frame == frame:
		return _cache
	var view := NpcWorldView.new()
	view.space = space
	for node: Node in EntitySpawner.entity_nodes():
		var ent: SpaceTimeEntity = node as SpaceTimeEntity
		if ent == null:
			continue
		var mv: SpaceTimeMovementComponent = ent.find_component(
			SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		if mv == null:
			continue
		var st: MovementState = mv.get_authority_state()
		if st == null:
			st = mv.get_render_state()
		if st == null:
			continue
		view.states[ent.entity_id] = st
		view.kinds[ent.entity_id] = ent.definition.kind if ent.definition != null else -1
	_cache = view
	_cache_frame = frame
	return view


## Drop the shared snapshot. Tests build their own worlds and must not inherit another's.
static func invalidate() -> void:
	_cache = null
	_cache_frame = -1


func state_of(entity_id: int) -> MovementState:
	return states.get(entity_id, null)


## The nearest entity of `kind` within `radius`, or 0. Ties go to the lower entity_id so two
## brains asked the same question in the same tick agree.
func nearest_of_kind(from: Vector3, kind: int, radius: float, except_id: int = 0) -> int:
	var best: int = 0
	var best_d: float = radius * radius
	for id: int in states:
		if id == except_id or kinds.get(id, -1) != kind:
			continue
		var st: MovementState = states[id]
		if st == null:
			continue
		var d: float = from.distance_squared_to(st.pos)
		if d < best_d or (is_equal_approx(d, best_d) and (best == 0 or id < best)):
			best = id
			best_d = d
	return best


## Is there a clear line from `a` to `b`? True when there is no level geometry between them —
## and true when there is no space to ask, so a brain in a test level behaves rather than freezing.
func can_see(a: Vector3, b: Vector3) -> bool:
	if space == null:
		return true
	# Eye height: a ray along the floor hits the floor.
	var from := a + Vector3.UP * 1.2
	var to := b + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = world_mask
	return space.intersect_ray(query).is_empty()
