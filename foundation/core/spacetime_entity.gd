class_name SpaceTimeEntity extends CharacterBody3D
## The root of every networked entity — local player, remote player and NPC all use this same
## scene (ARCHITECTURE §3). It is the ONLY node that knows the component list; components never
## look each other up by path.
##
## Two-phase init (hard rule 8): `_ready()` runs before any row has arrived and must not touch
## synced data. The spawner calls `bind()` once rows exist, and `bind()` cascades to components.
##
## Row routing: the entity owns a table -> components index built from each component's
## `required_tables()`, so an incoming `RowEvent` is delivered only to the components that asked
## for that table.

## Emitted once this entity and all its components are bound and safe to read.
signal bound()

## Which kind this is, and what scene the spawner used. Set by the spawner before `bind()`.
@export var definition: EntityDefinition

## How long to wait for the rest of the required tables before binding anyway. Rows for one
## entity can arrive across several cache updates; binding on the first one would hand
## components a half-populated world.
@export var bind_timeout_sec: float = 2.0

## PHYSICS LAYERS. Level geometry is on layer 1; every entity body is on layer 2 and collides
## with layer 1 only. Entities deliberately do not collide with each other: a remote entity is
## drawn where it was ~100 ms ago (interpolation), so a locally predicted body that bumped into
## it would be colliding with the past, in a way the server can never reproduce. It also means
## everyone can spawn on the same point without standing on each other's heads.
##
## Layer 3 is BARRIERS: invisible walls that stop bodies and nothing else — the lake's edge at
## wading depth, the dock's open sides, the edge of the world. Entity bodies collide with them;
## the camera boom and every ray that asks "what is the player looking at" use WORLD_MASK alone,
## so a barrier never pulls the camera in and never hides the water from the crosshair.
## Bit values, for `collision_layer` / `collision_mask` / ray query masks.
const WORLD_MASK: int = 1 << 0
const ENTITY_MASK: int = 1 << 1
const BARRIER_MASK: int = 1 << 2

var entity_id: int = -1
var world_id: int = 0
var owner_identity: PackedByteArray = PackedByteArray()
## True only on the client that owns this entity. Components read it to decide whether to
## predict, sample input, or just interpolate.
var is_local_authority: bool = false

var _components: Array[SpaceTimeComponent] = []
## table -> the components that declared it in `required_tables()`.
var _routes: Dictionary[StringName, Array] = {}
## Latest row seen per table, before bind. Handed to components as their initial state.
var _rows: Dictionary[StringName, RefCounted] = {}
## EVERY row seen per table before bind, in arrival order (DECISIONS #180): a collection (an
## angler's catches, an inventory's stacks) is many rows, and bind hands over all of them.
var _history: Dictionary[StringName, Array] = {}
var _required: Array[StringName] = []
var _is_bound: bool = false
## Every entity's status and holds (`_ensure_status_component`).
const STATUS_COMPONENT: String = "res://foundation/components/status_component.gd"
const HOLD_COMPONENT: String = "res://foundation/components/hold_component.gd"
const TIMED_PRESS_COMPONENT: String = "res://foundation/components/timed_press_component.gd"
const CARRY_COMPONENT: String = "res://foundation/components/carry_component.gd"
## Why its body is hidden (`set_hidden_by`): reason -> true. Empty: shown.
var _hidden_by: Dictionary = {}
var _saved_layer: int = 0
var _bind_timer: SceneTreeTimer = null

## THE LOOK THIS ENTITY WAS BUILT WEARING (DECISIONS #166): its `appearance` row's text when the
## model was made, "" for none. The row is read here rather than by a component, because the model
## is chosen before any component binds; a different one arriving later rebuilds the entity
## (`EntitySpawner.respawn`), once nothing of the game's is in the middle of something
## (`SpaceTimeComponent.blocks_respawn`).
const APPEARANCE_TABLE: StringName = &"appearance"
var appearance: String = ""
## A newer look is waiting for the entity to be free to rebuild.
var _look_pending: bool = false


## Injected into components so they never reach for `get_parent()` (ARCHITECTURE §3).
var body: CharacterBody3D:
	get:
		return self


func _ready() -> void:
	assert(entity_id == -1 or _is_bound,
		"hard rule 8: _ready() must not run after bind(). The spawner adds the scene to the " \
		+ "tree first and binds it afterwards.")


func is_bound() -> bool:
	return _is_bound


func get_components() -> Array[SpaceTimeComponent]:
	return _components.duplicate()


## Find a sibling component by class. Components use this instead of node paths or
## `get_parent()`, so a genre can reorder or rename nodes under Components/ freely.
## Returns null when absent — a component must cope with a sibling it expected not existing.
## Attach a component AFTER the entity has bound, and route rows to it like any other.
##
## The authority process does this for NPC brains: the entity scene cannot name that component,
## because nothing in `foundation/` or `game/` may reference `res://sidecar` (hard rule 7b). A
## component added this way does NOT gate the bind — that already happened — so it must be one
## that can start from whatever rows are present, which is why brains declare no required tables.
func add_runtime_component(c: SpaceTimeComponent) -> void:
	if c == null or _components.has(c):
		return
	if c.get_parent() == null:
		var holder: Node = get_node_or_null(^"Components")
		(holder if holder != null else self).add_child(c)
	_components.append(c)
	for t: StringName in c.required_tables():
		if not _routes.has(t):
			_routes[t] = []
		_routes[t].append(c)
	if _is_bound:
		c.bind(self, _rows, _history)


func find_component(type: Script) -> SpaceTimeComponent:
	for c: SpaceTimeComponent in _components:
		if is_instance_of(c, type):
			return c
	return null


## Called by the spawner. `initial_events` is whatever `EntityRegistry` buffered for this entity
## before its scene existed.
func bind(p_entity_id: int, p_world_id: int, p_owner: PackedByteArray,
		initial_events: Array) -> void:
	entity_id = p_entity_id
	world_id = p_world_id
	owner_identity = p_owner
	is_local_authority = EntityRegistry.is_local(p_entity_id)

	_collect_components()
	appearance = _appearance_in(initial_events)
	_apply_presentation()
	_apply_local_role()

	for ev: RowEvent in initial_events:
		_absorb(ev)

	if _missing_tables().is_empty():
		_finish_bind()
	else:
		# Wait for the stragglers rather than binding components to nothing.
		_bind_timer = get_tree().create_timer(bind_timeout_sec)
		_bind_timer.timeout.connect(_on_bind_timeout)


## Reconnect path: the SDK deletes every row and re-inserts it, and the spawner recognises that
## as a rebind rather than a despawn (DECISIONS #17). Components keep their nodes and signal
## connections; only their state is refreshed.
func rebind(initial_events: Array) -> void:
	_rows.clear()
	_history.clear()
	for ev: RowEvent in initial_events:
		_absorb(ev)
	for c: SpaceTimeComponent in _components:
		c.rebind(_rows, _history)
	bound.emit()


## Entry point from `EntityRegistry`. Before bind, events accumulate as initial state; after,
## they are routed to the components that asked for that table.
func receive_row_event(ev: RowEvent) -> void:
	if ev.table == APPEARANCE_TABLE:
		_on_appearance(ev)
	if not _is_bound:
		_absorb(ev)
		if _bind_timer != null and _missing_tables().is_empty():
			_finish_bind()
		return
	var targets: Array = _routes.get(ev.table, [])
	for c: SpaceTimeComponent in targets:
		c.receive_row_event(ev)


# --- the chosen look ---------------------------------------------------------------

## The look the initial rows say, "" for none.
func _appearance_in(events: Array) -> String:
	var look: String = ""
	for ev: RowEvent in events:
		if ev.table == APPEARANCE_TABLE:
			var row: RefCounted = ev.current()
			look = String(row.get(&"look")) if row != null and ev.kind != RowEvent.Kind.DELETED else ""
	return look


func _on_appearance(ev: RowEvent) -> void:
	var row: RefCounted = ev.current()
	var look: String = String(row.get(&"look")) if row != null and ev.kind != RowEvent.Kind.DELETED else ""
	if look == appearance or _look_pending:
		return
	_look_pending = true
	_rebuild_when_free.call_deferred()


## Rebuild for the new look as soon as no component is in the middle of something it would lose
## (a fish on the line): checked again every half second until then.
func _rebuild_when_free() -> void:
	while is_inside_tree():
		var busy: bool = not _is_bound
		for c: SpaceTimeComponent in _components:
			if c.blocks_respawn():
				busy = true
		if not busy:
			EntitySpawner.respawn(entity_id)
			return
		await get_tree().create_timer(0.5).timeout


# --- internals ----------------------------------------------------------------------

func _collect_components() -> void:
	_components.clear()
	_routes.clear()
	_required.clear()
	if not has_node(^"Components"):
		return
	_ensure_status_component()
	for child: Node in get_node(^"Components").get_children():
		var c: SpaceTimeComponent = child as SpaceTimeComponent
		if c == null:
			push_warning("SpaceTimeEntity %d: '%s' under Components is not a SpaceTimeComponent"
				% [entity_id, child.name])
			continue
		_components.append(c)
		var optional: Array[StringName] = c.optional_tables()
		for t: StringName in c.required_tables():
			if not _routes.has(t):
				_routes[t] = []
			_routes[t].append(c)
			# A table gates the bind if ANY component needs a row from it to be useful.
			if not optional.has(t) and not _required.has(t):
				_required.append(t)


## EVERY ENTITY HAS A STATUS, HOLDS, TIMED PRESSES AND CAN BE CARRIED (DECISIONS #206, #209, #210,
## #228): a scene that does not carry a `StatusComponent`, `HoldComponent`, `TimedPressComponent` or
## `CarryComponent` (a genre's own entity, one made before them) is given one, so they work everywhere.
##
## By PATH, not by class: those components name this class, and two scripts naming each other this
## way were never freed at exit (the unit run's leak check caught it).
func _ensure_status_component() -> void:
	for pair: Array in [[STATUS_COMPONENT, "Status"], [HOLD_COMPONENT, "Holds"], [TIMED_PRESS_COMPONENT, "TimedPress"], [CARRY_COMPONENT, "Carry"]]:
		var script: Script = load(String(pair[0])) as Script
		var holder: Node = get_node(^"Components")
		if holder.get_children().any(func(child: Node) -> bool: return child.get_script() == script):
			continue
		var c: Node = script.new() as Node
		c.name = String(pair[1])
		holder.add_child(c)


func _on_blocker_status(_from: int, to: int) -> void:
	var wall: EntityBlocker = get_node_or_null(^"Blocker") as EntityBlocker
	if wall != null:
		wall.follow_status(to)


## HIDE THE BODY for a reason (`&"offline"`: PresenceComponent; `&"status"`: an out player), or show
## it again. It is drawn, and others collide with it, only while no reason holds, so two of them never
## undo each other (a player who is out AND has left stays hidden when either ends).
##
## Hidden, nothing collides WITH it (its layer is cleared), but it still stands on the world (its
## mask is kept): clearing the mask too let an out player's own game drop them through the floor,
## into the void, and that is where they were when they came back in (Luke, 2026-10-10).
func set_hidden_by(reason: StringName, hide: bool) -> void:
	var was: bool = not _hidden_by.is_empty()
	if hide:
		_hidden_by[reason] = true
	else:
		_hidden_by.erase(reason)
	var now: bool = not _hidden_by.is_empty()
	if now == was:
		return
	visible = not now
	if now:
		_saved_layer = collision_layer
		collision_layer = 0
	else:
		collision_layer = _saved_layer


## Whether its body is hidden, and why (for tests and the debug overlay).
func is_hidden() -> bool:
	return not _hidden_by.is_empty()


func hidden_reasons() -> Array:
	return _hidden_by.keys()


## Keep only the rows that some component actually asked for; the rest would just be retained
## references to cache objects we never read.
func _absorb(ev: RowEvent) -> void:
	if not _routes.has(ev.table):
		return
	# The cache hands an update or delete the very row it replaces (`ev.old`), so the history
	# keeps one entry per row the entity has.
	var held: Array = _history.get_or_add(ev.table, [])
	if ev.old != null:
		held.erase(ev.old)
	if ev.kind != RowEvent.Kind.DELETED and ev.new != null:
		held.append(ev.new)
	if held.is_empty():
		_rows.erase(ev.table)
	else:
		_rows[ev.table] = held.back()


func _missing_tables() -> Array[StringName]:
	var missing: Array[StringName] = []
	for t: StringName in _required:
		if not _rows.has(t):
			missing.append(t)
	return missing


func _on_bind_timeout() -> void:
	if _is_bound:
		return
	var missing: Array[StringName] = _missing_tables()
	push_warning("SpaceTimeEntity %d: binding after %.1fs without rows for %s. Components will "
		% [entity_id, bind_timeout_sec, str(missing)]
		+ "start from their defaults; check the subscription covers these tables.")
	_finish_bind()


func _finish_bind() -> void:
	if _is_bound:
		return
	_is_bound = true
	if _bind_timer != null:
		if _bind_timer.timeout.is_connected(_on_bind_timeout):
			_bind_timer.timeout.disconnect(_on_bind_timeout)
		_bind_timer = null

	# Who predicts and who watches is a property of the entity, not of the scene file — the
	# same player.tscn is used for the local player, remote players and NPCs (ARCHITECTURE §3).
	for c: SpaceTimeComponent in _components:
		var mv: SpaceTimeMovementComponent = c as SpaceTimeMovementComponent
		if mv != null:
			if SpaceTimeMovementComponent.is_authority_process():
				# A sidecar simulates EVERY entity in its worlds, players and NPCs through the same
				# code (SIDECAR_SPEC §3). Nothing here is local or remote; it is all ours.
				mv.mode = SpaceTimeMovementComponent.Mode.SERVER_AUTHORITY
			else:
				mv.mode = SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED if is_local_authority 					else SpaceTimeMovementComponent.Mode.REMOTE_INTERPOLATED

	# Tree order, so a component may rely on its siblings above it already being bound.
	for c: SpaceTimeComponent in _components:
		c.bind(self, _rows, _history)

	var wall: EntityBlocker = get_node_or_null(^"Blocker") as EntityBlocker
	if wall != null:
		var sc: StatusComponent = find_component(StatusComponent) as StatusComponent
		if sc != null:
			wall.follow_status(sc.status())
			if not sc.status_changed.is_connected(_on_blocker_status):
				sc.status_changed.connect(_on_blocker_status)

	EntityRegistry.register(entity_id, self)
	bound.emit()
	SignalBus.entity_spawned.emit(entity_id, definition.kind if definition != null else -1)


## Apply the definition's presentation choices: model and camera framing. Both are pure swaps —
## a game changes what it looks like without touching a line of foundation code.
func _apply_presentation() -> void:
	if definition == null:
		return

	var look: PackedScene = definition.visual_for(entity_id, appearance)
	if look != null and has_node(^"Visual"):
		var visual: Node = get_node(^"Visual")
		# Drop the greybox placeholder, if the scene still has one.
		var placeholder: Node = visual.get_node_or_null(^"Model")
		if placeholder != null:
			visual.remove_child(placeholder)
			placeholder.queue_free()
		var model: Node = look.instantiate()
		model.name = "Model"
		# The rest of a chosen look (its colours) is the model's to apply (EntityDefinition).
		if not appearance.is_empty() and model.has_method(&"apply_appearance"):
			model.call(&"apply_appearance", appearance)
		visual.add_child(model)
		var model3d: Node3D = model as Node3D
		if model3d != null:
			model3d.position = definition.visual_offset
			model3d.rotation.y = deg_to_rad(definition.visual_yaw_deg)
			model3d.scale = Vector3.ONE * definition.visual_scale

	# ITS BODY (DECISIONS #207): a character's own capsule size, standing on the ground as the
	# scene's does. Before bind, so the first predicted (or simulated) step already collides as it.
	if definition.collision_radius > 0.0 or definition.collision_height > 0.0:
		var shape_node: CollisionShape3D = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		var cap: CapsuleShape3D = definition.body_capsule()
		if shape_node != null and cap != null and shape_node.shape is CapsuleShape3D:
			shape_node.shape = cap
			shape_node.position.y = cap.height * 0.5

	# SOLID TO ITS KIN when the rule says (DECISIONS #238), from now and as the rule changes.
	if definition.kin_layer > 0:
		apply_kin_collision()
		if not HotRules.changed.is_connected(_on_rule_changed):
			HotRules.changed.connect(_on_rule_changed)

	# A WALL IT PUTS UP (DECISIONS #229): built now, raised by its status once bound.
	if definition.has_blocker() and get_node_or_null(^"Blocker") == null:
		var wall: EntityBlocker = EntityBlocker.make(definition, entity_id)
		add_child(wall)
		wall.follow_status(StatusDef.NORMAL)

	if definition.camera_rig != null and has_node(^"CameraRig"):
		var rig: CameraRig = get_node(^"CameraRig") as CameraRig
		if rig != null:
			rig.config = definition.camera_rig

	# How this character moves (its movement profile, DECISIONS #205), before bind: the movement
	# component predicts (or, on the sidecar, simulates) with these numbers from its first frame.
	var mover: SpaceTimeMovementComponent = find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if mover != null and definition.movement_profile != null:
		mover.config = definition.movement_config()

	# Before bind, because the driver builds its tree in `_on_bound`.
	if definition.animation_set != null:
		var driver: AnimationDriverComponent = find_component(
			AnimationDriverComponent) as AnimationDriverComponent
		if driver != null:
			driver.animation_set = definition.animation_set


## FRIENDLY COLLISION (DECISIONS #238): on its character's `kin_layer` always (so others of its kind
## can be solid to it), and solid to that layer itself only while `foundation.friendly_collision` is on.
func apply_kin_collision() -> void:
	if definition == null or definition.kin_layer <= 0:
		return
	var bit: int = 1 << (definition.kin_layer - 1)
	collision_layer = collision_layer | bit
	collision_mask = (collision_mask | bit) if HotRules.flag(&"foundation.friendly_collision") else (collision_mask & ~bit)


func _on_rule_changed(key: StringName) -> void:
	if key == &"foundation.friendly_collision":
		apply_kin_collision()


## Free the half of the rig this instance will never use. A remote entity has no camera; the
## local one does not render its own nameplate.
func _apply_local_role() -> void:
	if is_local_authority:
		# Take the view. The rig cannot do this in its own `_ready()`: that runs when the
		# spawner adds this entity to the tree, before `bind()` above learned whose entity it
		# is. Without this call no camera in the scene is ever current and the game renders
		# nothing — and because the HUD is a CanvasLayer it keeps drawing, so the symptom is a
		# grey screen with a working UI rather than an error.
		var rig: CameraRig = get_node_or_null(^"CameraRig") as CameraRig
		if rig != null:
			rig.activate()

	var drop: StringName = &"CameraRig" if not is_local_authority else &"Nameplate"
	if not has_node(NodePath(drop)):
		return
	var n: Node = get_node(NodePath(drop))
	# Detach NOW, free later. `queue_free()` alone leaves the node in the tree until the end of
	# the frame, and a remote entity that still holds a live Camera3D for a frame can make
	# itself the active camera.
	remove_child(n)
	n.queue_free()
