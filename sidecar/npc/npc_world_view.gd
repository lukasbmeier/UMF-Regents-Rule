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
## entity_id -> its status (`status_state`; 0, normal, when it has none), and which are players.
var statuses: Dictionary[int, int] = {}
var players: Dictionary[int, bool] = {}
## The level its world runs, for paths (`path`). Null in a test with none.
var level: Node3D = null


## ONE SNAPSHOT PER PHYSICS TICK, shared by every brain that asks for it. Each brain needs to
## know about every entity, so building a view per brain would be quadratic in the number of
## NPCs — at ten think ticks a second that is the difference between nothing and something.
static var _cache: NpcWorldView = null
static var _cache_frame: int = -1


static func current(space: PhysicsDirectSpaceState3D = null, p_level: Node3D = null) -> NpcWorldView:
	var frame: int = Engine.get_physics_frames()
	if _cache != null and _cache_frame == frame:
		return _cache
	var view := NpcWorldView.new()
	view.space = space
	view.level = p_level
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
	# EVERYONE ELSE, as the server has them (DECISIONS #230): a referee drives its bots and simulates
	# nobody else (the players move themselves, the props stand), so the rest come from their rows.
	for row: RefCounted in SpaceTimeSync.find_rows(&"movement_state", func(_r: RefCounted) -> bool: return true):
		var eid: int = int(row.get(&"entity_id"))
		if view.states.has(eid):
			continue
		view.states[eid] = MovementState.from_row(row)
		var e: RefCounted = SpaceTimeSync.get_row(&"entity", eid)
		view.kinds[eid] = int(e.get(&"kind")) if e != null else -1
	for eid: int in view.states:
		var s: RefCounted = SpaceTimeSync.get_row(&"status_state", eid)
		view.statuses[eid] = int(s.get(&"status")) if s != null else 0
		if SpaceTimeSync.get_row(&"player", eid) != null:
			view.players[eid] = true
	_cache = view
	_cache_frame = frame
	return view


## Drop the shared snapshot. Tests build their own worlds and must not inherit another's.
static func invalidate() -> void:
	_cache = null
	_cache_frame = -1


func state_of(entity_id: int) -> MovementState:
	return states.get(entity_id, null)


## Its status (0, normal, when it has none).
func status_of(entity_id: int) -> int:
	return int(statuses.get(entity_id, 0))


## Every entity of `kind`, by id.
func all_of_kind(kind: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in kinds:
		if kinds[id] == kind:
			out.append(id)
	out.sort()
	return out


## A way from `from` to `to` for a body of `radius` by `height` (`NpcNav`); empty with no level.
func path(from: Vector3, to: Vector3, radius: float, height: float) -> PackedVector3Array:
	return NpcNav.path(level, from, to, radius, height)


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
