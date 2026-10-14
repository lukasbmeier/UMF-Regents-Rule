class_name NpcBrainComponent extends SpaceTimeComponent
## Drives one NPC. Thinks a few times a second, produces an input frame every physics tick, and
## hands it to the movement component through exactly the path a player's queued frames take.
##
## THE POINT IS THE PATH, not the brain. An NPC that got its own movement code would be subject
## to its own gravity, its own collision and its own speeds — three more things to keep in step
## with the player's, none of which would report drifting. Going through `push_authority_input`
## means an NPC is stopped by the same walls, at the same speed, by the same model
## (`docs/SIDECAR_SPEC.md` §3).
##
## It is a `SpaceTimeComponent` with no required tables, so the sidecar can attach it to an
## already-spawned entity and bind it by hand — the entity scene cannot carry it, because nothing
## in `foundation/` or `game/` may reference `res://sidecar` (hard rule 7b).
##
## SERVER-ONLY.

## The brain changed its mind about what it is doing. `write_npc_brain` persists this for
## spectators and restarts; the debug overlay prints it.
signal state_changed(state: StringName)
## A write to `npc_brain` settled. For tests: persistence is otherwise invisible until a restart.
signal persisted(ok: bool)
## Something the brain asked to do was sent ({do: hold|let_go|ability, ...}). For tests and the log.
signal sent(act: Dictionary)

const TABLE: StringName = &"npc_brain"
## The spec's ceiling on how often a brain is written (SIDECAR_SPEC §2: "on change, <= 1 Hz").
const PERSIST_MIN_SEC: float = 1.0

## Which brain. Resolved through `make_brain()` — the one place names map to classes.
@export var brain_name: StringName = &"wander"
## Reasoning runs at this rate; movement still runs every physics tick. A brain that reasoned per
## tick would cost sixty times as much and behave no better.
@export var think_hz: float = 10.0

var brain: NpcBrain = null

var _movement: SpaceTimeMovementComponent = null
var _accum: float = 0.0
var _last_state: StringName = &""
## What the database holds for this brain, as far as we know: the last write it ACCEPTED, or the
## row we restored from. A write is only sent when the brain differs from it.
var _persisted_key: String = ""
var _persist_in_flight: bool = false
var _last_persist_msec: int = -100000
## Set once this brain has written or restored anything. Before that, a row arriving late (the
## authority registered after we bound, and the filter let it through) is still worth reading.
var _has_memory: bool = false


## The brain's row, so a restart can resume it. Optional: a new NPC has none, and this component
## is attached after the entity bound (it cannot gate that) — see `_on_bound`.
func required_tables() -> Array[StringName]:
	return [TABLE]


func optional_tables() -> Array[StringName]:
	return [TABLE]


## Our own writes echo back through here; they change nothing. The one row that matters is one
## that became visible after we bound, before this brain had anything of its own.
func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE or new == null or brain == null or _has_memory:
		return
	_restore(new)


## Name -> brain: the foundation's by name, else the script `res://sidecar/npc/brains/<name>.gd` (a
## genre's in its own folder: `chicken/hen`), made with the seed. The name is what an
## `EntityDefinition` or a bot's `npc_brain` row carries, so a designer picks behaviour without code.
static func make_brain(name: StringName, seed_value: int) -> NpcBrain:
	match name:
		&"wander":
			return WanderBrain.new(seed_value)
		&"chase":
			return ChaseBrain.new(seed_value)
	var path: String = BRAINS_DIR + String(name) + ".gd"
	if not String(name).contains("..") and ResourceLoader.exists(path):
		var script: GDScript = load(path) as GDScript
		var made: Variant = script.new(seed_value) if script != null else null
		if made is NpcBrain:
			return made as NpcBrain
	push_warning("NpcBrainComponent: no brain named '%s'; the entity will stand still." % name)
	return null


## Where a genre's brains are (`make_brain`).
const BRAINS_DIR: String = "res://sidecar/npc/brains/"


func _on_bound() -> void:
	set_physics_process(false)
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_movement = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if _movement == null:
		push_warning("NpcBrainComponent: entity %d has no movement component" % entity_id)
		return
	if _movement.mode != SpaceTimeMovementComponent.Mode.SERVER_AUTHORITY:
		# Not ours to drive. A client build that somehow attached one must do nothing rather than
		# fight the prediction.
		return
	brain = make_brain(brain_name, entity_id)
	if brain == null:
		return
	brain.self_id = entity_id
	var cap: CapsuleShape3D = ent.definition.body_capsule() if ent.definition != null else null
	if cap != null:
		brain.body_radius = cap.radius
		brain.body_height = cap.height
	var here: MovementState = _movement.get_authority_state()
	var wander: WanderBrain = brain as WanderBrain
	if wander != null and here != null:
		wander.home = here.pos
	# RESUME, IF THERE IS ANYTHING TO RESUME. Read from the cache directly: this component is
	# attached after the entity bound, so the entity never kept a row for a table nobody had
	# asked for yet.
	var row: RefCounted = SpaceTimeSync.get_row(TABLE, entity_id)
	if row != null:
		_restore(row)
	else:
		print("[Sidecar] entity %d starts brain '%s' fresh (%s)"
			% [entity_id, brain_name, brain.describe()])
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if brain == null or _movement == null:
		return
	var me: MovementState = _movement.get_authority_state()
	if me == null:
		return
	_accum += delta
	var period: float = 1.0 / maxf(think_hz, 1.0)
	if _accum >= period:
		_accum = minf(_accum - period, period)
		brain.think(me, NpcWorldView.current(_space(), _level()))
		if brain.state != _last_state:
			_last_state = brain.state
			state_changed.emit(brain.state)
		_send_acts(brain.take_acts())
		_maybe_persist()
	var f: InputFrame = brain.frame(me)
	if _lunge_at_msec > 0 and Time.get_ticks_msec() >= _lunge_at_msec:
		_lunge_at_msec = 0
		f.dash = true   # its ability's lunge (DECISIONS #232), as a player's client presses it
	_movement.push_authority_input(f)


# --- doing things (DECISIONS #230) ----------------------------------------------------------------

## When its last ability's lunge is due (ticks msec; 0: none).
var _lunge_at_msec: int = 0

## What the brain asked to do, as the authority's reducers: the server judges each as a player's.
## Sent, never waited for: a refusal (out of reach, already held) is the brain's to notice by what
## happens (or does not), as a player notices.
func _send_acts(acts: Array[Dictionary]) -> void:
	for a: Dictionary in acts:
		match String(a.get("do", "")):
			"hold":
				SpaceTimeSync.call_reducer(&"begin_interact_as", [entity_id, int(a["target"]), int(a.get("verb", 0))], ["u64", "u64", "u8"])
			"let_go":
				SpaceTimeSync.call_reducer(&"end_interact_as", [entity_id], ["u64"])
			"ability":
				SpaceTimeSync.call_reducer(&"use_ability_as", [entity_id, int(a["ability"]), int(a.get("target", 0)), a["aim"] as Vector3, 0],
					["u64", "u32", "u64", "vector3[f32,f32,f32]", "u32"])
				var wind_up: int = SpaceTimeActionComponent.lunge_wind_up_ms(SpaceTimeSync.get_row(&"ability_def", int(a["ability"])))
				if wind_up >= 0:
					_lunge_at_msec = Time.get_ticks_msec() + wind_up
		sent.emit(a)


## The level this entity's world runs (for paths): the SimWorld it is simulated in.
func _level() -> Node3D:
	var n: Node = entity as Node
	while n != null:
		if n.has_method(&"level"):
			return n.call(&"level") as Node3D
		n = n.get_parent()
	return null


# --- persistence ------------------------------------------------------------------------------

## Pick up where a previous run left off. A row written by a DIFFERENT brain is ignored: its data
## means something else, and misreading it is worse than starting fresh.
func _restore(row: RefCounted) -> void:
	var written_by: StringName = StringName(String(row.get(&"brain")))
	if written_by != brain_name:
		print("[Sidecar] entity %d has a '%s' brain row; '%s' starts fresh"
			% [entity_id, written_by, brain_name])
		return
	var parsed: Variant = JSON.parse_string(String(row.get(&"data")))
	if parsed is Dictionary:
		brain.load_state(parsed)
	brain.state = StringName(String(row.get(&"state")))
	_has_memory = true
	_persisted_key = _key()
	print("[Sidecar] entity %d resumes brain '%s' in state '%s' (%s)"
		% [entity_id, brain_name, brain.state, brain.describe()])


## Write the brain's memory if it changed — at most once a second, one write at a time. A write
## the module refused (an authority not registered yet) leaves `_persisted_key` as it was, so the
## same memory is OWED AGAIN on the next think (DECISIONS #108).
func _maybe_persist() -> void:
	if _persist_in_flight:
		return
	var key: String = _key()
	if key == _persisted_key:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_persist_msec < int(PERSIST_MIN_SEC * 1000.0):
		return
	_last_persist_msec = now
	_persist_in_flight = true
	_has_memory = true
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"write_npc_brain",
		[entity_id, String(brain_name), String(brain.state), brain.target(),
			JSON.stringify(brain.save_state())],
		["u64", "string", "string", "u64", "string"])
	# A request that could not even be sent (not connected) comes back ALREADY settled, before
	# anything could connect to it — and a handler connected late would never run, leaving the
	# write "in flight" for ever and the brain never persisting again.
	if req.is_pending():
		req.settled.connect(_on_persist_settled.bind(key))
	else:
		_on_persist_settled(req, key)


func _on_persist_settled(req: ReducerRequest, key: String) -> void:
	_persist_in_flight = false
	if req.is_ok():
		_persisted_key = key
	persisted.emit(req.is_ok())


## Everything the row would hold, as one comparable string.
func _key() -> String:
	return "%s|%s|%d|%s" % [brain_name, brain.state, brain.target(),
		JSON.stringify(brain.save_state())]



## The physics space to raycast line of sight against. Null before the entity is in a tree, and
## in a test with no world — `NpcWorldView.can_see` treats that as "can see", so a brain behaves
## rather than freezing.
func _space() -> PhysicsDirectSpaceState3D:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null or ent.body == null or not ent.body.is_inside_tree():
		return null
	var world: World3D = ent.body.get_world_3d()
	return world.direct_space_state if world != null else null
