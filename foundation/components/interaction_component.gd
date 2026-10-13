class_name InteractionComponent extends SpaceTimeComponent
## "What am I looking at, and can I use it?" — a raycast from the local camera each physics
## tick, and an intent reducer when the player presses the key.
##
## The client's opinion of the target is a PROMPT, never a permission. `interact` re-checks
## distance and eligibility server-side (module `interact`), because the raycast runs on a
## machine the player controls. Treat `target_changed` as "show a prompt", nothing more.
##
## A target is either a `SpaceTimeEntity` (a player, an NPC, a resource node) or any node in
## the `interactable` group carrying an `entity_id` meta — which lets a genre put an Area3D or
## a static prop in front of an entity without making the whole prop an entity.
##
## WHERE THE RAY STARTS. At the camera, along the camera's forward axis — so it goes exactly
## where the crosshair points, in first person and in third. In third person the camera sits on
## a boom BEHIND the player, so the ray is extended by that much before `interaction_range` is
## measured; a ray merely `interaction_range` long from a 4.5 m boom ends a metre and a half
## behind the player and can never hit anything they are looking at. The range that decides is
## then measured from the PLAYER to the target, which is the same distance the server checks
## (`INTERACT_RANGE` in module.rs) — the prompt has to promise only what the server will allow.
##
## WHAT IS IN FRONT OF THE CHARACTER (DECISIONS #211, #213, #214). In third person a player looks
## around while they act (a predator scouting), so the CHARACTER decides, not the camera: the target
## is in FRONT of it, within reach and inside `front_arc_deg` (120: a hitbox across the front of the
## model), nearest and most squarely in front first; never beside or behind. In third person the
## crosshair has no say at all (Luke: the ray offered Help up for someone the character was not
## facing); in first person, where the crosshair IS where the character looks, it goes first
## (`targeting` AUTO, from the camera rig). Only what there is something to do with counts: an
## entity a hold applies to (a downed teammate), anything that is not a person (a resource node, a
## genre's own kinds), a prop in the `interactable` group, or what a genre's `nearby_wanted`
## accepts, so a crowd of players standing about is never "the target".
##
## HOLDS (DECISIONS #209). Where a press would start a hold (`HoldDef.find`: the target's kind and
## status, this player's kind, the verb: helping a downed teammate up), the key is HELD: down begins
## it (`begin_interact`), up lets go (`end_interact`). Everything else is a press, as before.

## The entity now under the crosshair, or NO_TARGET. Fires only on CHANGE.
signal target_changed(entity_id: int)
## The player pressed the interact key on a target. Fired whoever ends up handling it and
## BEFORE the reducer, so presentation (the reach animation, a sound) plays immediately rather
## than a round trip later — the same rule as predicted movement events (DECISIONS #83).
## `docs/ANIMATION_SPEC.md` section 2 names this as the driver's `interact` one-shot.
signal interact_requested(entity_id: int)

const NO_TARGET: int = -1
## People (module `entity_kind`): offered in front only when there is something to do with them.
const KIND_PLAYER: int = 0
const KIND_NPC: int = 1
const GROUP_INTERACTABLE: StringName = &"interactable"
const ACTION_INTERACT: StringName = &"interact"
## THE SKILL CHECK'S OWN KEY (DECISIONS #218, Space by default): a check comes up WHILE a hold is held
## (an egg wobbles under a sitting hen), and the interact key is down, so it cannot press it. The
## interact key still presses a check when nothing is being held (as before).
const ACTION_SKILL_CHECK: StringName = &"skill_check"

enum Targeting { CROSSHAIR, NEARBY, BOTH, AUTO }
## How the target is chosen: what the crosshair is on, what is in front of the character, the
## crosshair's and else the one in front, or AUTO: in front only in third person, both in first
## person (the camera rig's `first_person`).
@export var targeting: Targeting = Targeting.AUTO
## The arc in front of the character (the whole of it, centred on where it faces) inside which
## something within reach is the target without the crosshair on it.
@export_range(0.0, 360.0, 1.0, "suffix:deg") var front_arc_deg: float = 120.0

## How far (m) the prompt reaches. 0 or less: the server's own range, `shared/rules.json`
## `interact_range_m` (DECISIONS #154). Never more than that, or prompts appear for things the
## server will refuse.
@export var interaction_range: float = 0.0
## Which interaction this component sends. Genres define their own verbs.
@export var verb: int = 0


## How far the prompt reaches right now: `interaction_range`, or the server's when that is unset.
func range_m() -> float:
	return interaction_range if interaction_range > 0.0 else Rules.interact_range()


## How near `target_id` must be to be offered: a hold's own reach (`HoldDef.range_m`, as the server
## measures it), else `range_m()`. Offering a hold from further than its reach promised what the
## server then refused ("out of range": Luke's wolf, offered a larder's Stash at 2.9 m of its 2.2).
func reach_for(target_id: int) -> float:
	var h: HoldDef = hold_for(target_id)
	if h != null and h.range_m > 0.0:
		return h.range_m
	return range_m()

var _target: int = NO_TARGET
## A hold was asked for and not yet let go of: the key's release lets go.
var _holding_sent: bool = false

## A genre's own nearby targets: `func(entity_id: int) -> bool`, true for an entity the interact key
## should offer when the player stands at it (a nest, a gate). Holds are offered without it.
var nearby_wanted: Callable = Callable()

## A genre's own verb for the interact key: `func(target_id: int) -> bool`, returning true if it
## handled the press — in which case the foundation's `interact` reducer is NOT called. Fishing
## sets this so that E on a pond casts. A genre component installs it from its own `_on_bound`;
## component order does not matter, because it is only read when the key goes down.
var interact_handler: Callable = Callable()


func required_tables() -> Array[StringName]:
	return []


## No tables; required because the base declares it abstract.
func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	# Only the owning client aims a crosshair.
	set_physics_process(is_local_authority)


# --- read / intent -------------------------------------------------------------------

func get_target() -> int:
	return _target


func has_target() -> bool:
	return _target != NO_TARGET


## `entity.kind` of the current target, or -1 when it is unknown (a prop, or an entity this
## client has no definition for). A genre prompts on this, so "press E" is only offered for the
## things its verb actually applies to.
func get_target_kind() -> int:
	var node: Node = EntityRegistry.get_entity(_target)
	var ent: SpaceTimeEntity = node as SpaceTimeEntity
	if ent == null or ent.definition == null:
		return -1
	return ent.definition.kind


## Distance from the player to the current target, or INF. This is the number the server's range
## check will use, so UI can show how much closer to walk.
func target_distance() -> float:
	if _target == NO_TARGET:
		return INF
	return _distance_to(_target, Vector3.ZERO, false)


## Ask the server to interact with the current target. Returns null if nothing is targeted.
## The server decides whether it actually happens.
func request_interact(override_verb: int = -1) -> ReducerRequest:
	if _target == NO_TARGET:
		return null
	var v: int = override_verb if override_verb >= 0 else verb
	return SpaceTimeSync.call_reducer(&"interact", [_target, v], ["u64", "u8"])


# --- scanning ------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	scan()
	if InputMap.has_action(ACTION_SKILL_CHECK) and Input.is_action_just_pressed(ACTION_SKILL_CHECK):
		press_timed()
	if not InputMap.has_action(ACTION_INTERACT):
		return
	if Input.is_action_just_pressed(ACTION_INTERACT) and not press_timed():
		if _target != NO_TARGET:
			press_interact()
	if _holding_sent and not Input.is_action_pressed(ACTION_INTERACT):
		release_interact()


## The interact key went down on the current target. Public so a playtest can press it without
## faking an input event, and so a genre can bind a second key to the same verb.
func press_interact() -> void:
	if _target == NO_TARGET:
		return
	# ASK BEFORE ANNOUNCING. This used to emit first, so the character played its interact
	# animation for every press — including the ones the genre was about to drop, which is why
	# casting in the shop phase produced a cast animation and no cast. Presentation must not wait
	# for the SERVER's answer (that is a round trip, DECISIONS #93), but waiting for the CLIENT's
	# own answer costs nothing and is the difference between "optimistic" and "wrong".
	#
	# A genre that claims the press owns what it should look like, and says so with
	# `announce_interact()` — only it knows whether this press is a cast, a second press on a
	# timing bar, or a refusal it has already decided.
	if interact_handler.is_valid() and bool(interact_handler.call(_target)):
		return
	if hold_for(_target) != null:
		begin_hold(_target)
		return
	announce_interact(_target)
	request_interact()


## While a timed press is being played (DECISIONS #210), the key presses IT, not what is in front of
## the player. True when it did.
func press_timed() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var tp: TimedPressComponent = ent.find_component(TimedPressComponent) as TimedPressComponent if ent != null else null
	if tp == null or not tp.wants_press():
		return false
	tp.press()
	return true


## THE HOLD a press on `target_id` would start (DECISIONS #209), or null: the target's kind and
## status as this client knows them, this player's kind, this component's verb. The server checks
## the same (`hold::find`).
func hold_for(target_id: int, override_verb: int = -1) -> HoldDef:
	var target: SpaceTimeEntity = EntityRegistry.get_entity(target_id) as SpaceTimeEntity
	var me: SpaceTimeEntity = entity as SpaceTimeEntity
	if target == null or target.definition == null or me == null or me.definition == null:
		return null
	var st: StatusComponent = target.find_component(StatusComponent) as StatusComponent
	var status: int = st.status() if st != null else StatusDef.NORMAL
	return HoldDef.find(target.definition.kind, override_verb if override_verb >= 0 else verb, status, me.definition.kind)


## Begin holding on `target_id`: the server starts the hold, or joins this player to it. The key's
## release lets go (`release_interact`).
func begin_hold(target_id: int, override_verb: int = -1) -> ReducerRequest:
	_holding_sent = true
	var v: int = override_verb if override_verb >= 0 else verb
	return SpaceTimeSync.call_reducer(&"begin_interact", [target_id, v], ["u64", "u8"])


## The interact key went up: let go of what this player is holding. Public so a playtest can let go.
func release_interact() -> ReducerRequest:
	if not _holding_sent:
		return null
	_holding_sent = false
	return SpaceTimeSync.call_reducer(&"end_interact", [], [])


## Whether a hold was asked for and the key is still down.
func is_holding_key() -> bool:
	return _holding_sent


## Tell presentation a verb is starting NOW. The foundation calls this for its own `interact`;
## a genre calls it when its handler decides the press really is an action (ANIMATION_SPEC §2).
func announce_interact(target_id: int) -> void:
	interact_requested.emit(target_id)


## Recompute the target. Split out of `_physics_process` so a test can step it deliberately.
func scan() -> void:
	var how: Targeting = effective_targeting()
	var id: int = _raycast_target() if how == Targeting.CROSSHAIR or how == Targeting.BOTH else NO_TARGET
	if id == NO_TARGET and how != Targeting.CROSSHAIR:
		id = nearby_target()
	_set_target(id)


## How the target is chosen now: `targeting`, with AUTO settled by the camera: in front of the
## character only in third person (or with no rig), the crosshair first in first person.
func effective_targeting() -> Targeting:
	if targeting != Targeting.AUTO:
		return targeting
	var rig: CameraRig = (entity as Node).get_node_or_null(^"CameraRig") as CameraRig if entity != null else null
	return Targeting.BOTH if rig != null and rig.config != null and rig.config.first_person else Targeting.NEARBY


## THE TARGET IN FRONT: of the entities there is something to do with (`_wanted_nearby`), the one
## within reach (measured as the server measures it) and inside `front_arc_deg` of the way the
## character faces, nearest and most squarely in front first. NO_TARGET when there is none.
func nearby_target() -> int:
	var body: CharacterBody3D = entity.body if entity != null else null
	if body == null or not body.is_inside_tree():
		return NO_TARGET
	var facing: Vector3 = facing()
	var best: int = NO_TARGET
	var best_score: float = INF
	# Every entity, and every prop standing in for one (`interactable`, with an `entity_id`).
	var candidates: Array = []
	for id: int in EntityRegistry.all_entity_ids():
		candidates.append([id, EntityRegistry.get_entity(id) as Node3D, false])
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(GROUP_INTERACTABLE):
			if n is Node3D and n.has_meta(&"entity_id"):
				candidates.append([int(n.get_meta(&"entity_id")), n as Node3D, true])
	for c: Array in candidates:
		var id: int = int(c[0])
		var node: Node3D = c[1]
		if id == entity_id or node == null or not node.is_inside_tree() or not node.visible:
			continue
		var to: Vector3 = node.global_position - body.global_position
		var d: float = to.length()
		if d > range_m() or (not bool(c[2]) and d > reach_for(id)):
			continue
		var flat: Vector3 = Vector3(to.x, 0.0, to.z)
		var angle: float = rad_to_deg(facing.angle_to(flat)) if flat.length() > 0.05 else 0.0
		if angle > front_arc_deg * 0.5 or not (bool(c[2]) or _wanted_nearby(id)):
			continue
		var score: float = d + angle / 90.0
		if score < best_score:
			best_score = score
			best = id
	return best


## The way the character faces (the front of its model), flat: its BODY's heading (DECISIONS #221).
## The body turns to the camera only while it moves or aims (DECISIONS #100), so standing still and
## looking round does not swing what is in front of it. (This read the input's yaw, which follows
## the camera even standing still: in front of the character meant where the camera looked, and Luke
## had to aim the camera at a nest the hen was already facing.)
func facing() -> Vector3:
	var body: Node3D = entity.body if entity != null and entity.body != null else entity as Node3D
	if body == null:
		return Vector3.FORWARD
	var f: Vector3 = -body.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


## Whether entity `id` is something to offer when it is in front: a hold applies to it, it is not a
## person (a resource node, a genre's own kind: what `interact` is for), or a genre says so.
func _wanted_nearby(id: int) -> bool:
	if hold_for(id) != null:
		return true
	var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	if e != null and e.definition != null and not is_person(e):
		return true
	return nearby_wanted.is_valid() and bool(nearby_wanted.call(id))


## Whether `e` is a PERSON (a player, an NPC, a hen: offered in front only when there is something to
## do with them), not a thing (a resource node, a nest: offered to be used). By the foundation's
## people kinds, a character a player may choose (DECISIONS #217), or a player row: a game whose
## players are another kind (Fowl Play's hens, 100) counts them as people too, or a hen crowding a
## nest would be the target instead of the nest.
static func is_person(e: SpaceTimeEntity) -> bool:
	if e == null or e.definition == null:
		return false
	if e.definition.kind == KIND_PLAYER or e.definition.kind == KIND_NPC or e.definition.playable:
		return true
	var plate: NameplateComponent = e.find_component(NameplateComponent) as NameplateComponent
	return plate != null and plate.is_player()


func _raycast_target() -> int:
	var cam: Camera3D = _camera()
	if cam == null or not cam.is_inside_tree():
		return NO_TARGET
	var world: World3D = cam.get_world_3d()
	if world == null:
		return NO_TARGET

	# Looking through yourself: in first person the camera sits inside the player's own capsule.
	var body: CharacterBody3D = entity.body if entity != null else null
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	var to: Vector3 = from + dir * (_camera_setback(from, dir, body) + range_m())
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if body != null:
		query.exclude = [body.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	var id: int = _target_id_of(hit.get("collider"))
	if id == NO_TARGET:
		return NO_TARGET
	var point: Vector3 = Vector3.ZERO
	var has_point: bool = hit.has("position")
	if has_point:
		point = hit["position"]
	if body != null and _distance_to(id, point, has_point) > reach_for(id):
		return NO_TARGET   # in view but out of reach (a hold's own reach): the server would refuse it
	return id


## How far the camera is behind the player along its own forward axis. Zero in first person,
## the boom length in third. Negative results are clamped away: a camera somehow in FRONT of
## the player must not shorten the reach.
func _camera_setback(from: Vector3, dir: Vector3, body: CharacterBody3D) -> float:
	if body == null or not body.is_inside_tree():
		return 0.0
	return maxf(0.0, (body.global_position - from).dot(dir))


## Player-to-target distance, measured the way the server measures it: between entity origins.
## Falls back to the hit point for a prop that stands in for an entity it is not co-located
## with — still an under-estimate of nothing, because the prop is what the player sees.
func _distance_to(id: int, point: Vector3, has_point: bool) -> float:
	var body: CharacterBody3D = entity.body if entity != null else null
	if body == null or not body.is_inside_tree():
		return INF
	var node: Node3D = EntityRegistry.get_entity(id) as Node3D
	if node != null and node.is_inside_tree():
		return body.global_position.distance_to(node.global_position)
	if has_point:
		return body.global_position.distance_to(point)
	return INF


## An entity, or a prop standing in for one.
func _target_id_of(node: Variant) -> int:
	if node == null or not (node is Node):
		return NO_TARGET
	var n: Node = node
	var as_entity: SpaceTimeEntity = n as SpaceTimeEntity
	if as_entity != null:
		return as_entity.entity_id
	if n.is_in_group(GROUP_INTERACTABLE) and n.has_meta(&"entity_id"):
		return int(n.get_meta(&"entity_id"))
	return NO_TARGET


## The one place the signal is emitted, so a target held across many frames announces once.
func _set_target(id: int) -> void:
	if id == _target:
		return
	_target = id
	target_changed.emit(id)
	SignalBus.interact_target_changed.emit(id)


func _camera() -> Camera3D:
	if entity == null:
		return null
	var rig: Node = entity.get_node_or_null(^"CameraRig")
	if rig == null:
		return null
	for child: Node in rig.get_children():
		var cam: Camera3D = child as Camera3D
		if cam != null:
			return cam
	return null
