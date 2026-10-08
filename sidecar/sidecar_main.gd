extends Node
## The sidecar's entry point: headless Godot as a world's motion authority.
##
##   godot --headless --path . res://sidecar/sidecar_main.tscn -- --world=1
##
## It is the ordinary client stack with two settings changed. `NetConfig.authority_process`
## makes every entity bind in SERVER_AUTHORITY instead of predicted/interpolated, and
## `InterestManager.extra_tables` adds `input_queue` so the frames to replay arrive. Everything
## else — the spawner, the entity scenes, the movement model, the collision resolver — is the
## same code the players run, which is the entire point: the authority cannot disagree with a
## client about physics it is not running separately (`docs/SIDECAR_SPEC.md` §3).
##
## IDENTITY IS STABLE ACROSS RESTARTS (`token_path`), because the module keys authority on it:
## a sidecar that came back with a new identity would no longer be an authority for its world
## and every write would be refused.
##
## ONE WORLD PER PROCESS. The spec allows `--world=1,2,3` for small party worlds, but
## `InterestManager` subscribes to one world at a time and `EntitySpawner` has one world root,
## so a second world would need both to become per-world. `--world=` takes the first and says so.
##
## SERVER-ONLY (hard rule 7b).

## Its own NetConfig: `authority_process` on, and a token path no player will collide with.
@export var net_config: NetConfig
## The level to resolve movement against. The same scene the clients load — see SimWorld.
@export var level_scene: PackedScene
## Entity kinds this process knows how to spawn. Must cover every kind in the worlds it serves,
## or those entities never exist here and nothing simulates them.
@export var entity_definitions: Array[EntityDefinition] = []

var world: SimWorld = null


func _ready() -> void:
	var cfg: NetConfig = (net_config if net_config != null else NetConfig.new()).duplicate()
	cfg.authority_process = true
	if cfg.token_path.is_empty() or cfg.token_path == NetConfig.new().token_path:
		cfg.token_path = "user://sidecar_token.dat"
	var world_id: int = _world_from_cli()

	world = SimWorld.new()
	add_child(world)
	world.setup(world_id, level_scene, float(cfg.server_tick_hz))

	for defn: EntityDefinition in entity_definitions:
		EntitySpawner.register_definition(defn)
	EntitySpawner.world_root_path = EntitySpawner.get_path_to(world.entity_root())

	# The frames to replay. `input_queue` is already in InterestManager's world-filtered list, so
	# this asks for THIS world's input and nobody else's (DECISIONS #104).
	if not InterestManager.extra_tables.has(&"input_queue"):
		InterestManager.extra_tables.append(&"input_queue")
	# And the brains it left behind the last time it ran, so an NPC resumes instead of restarting.
	if not InterestManager.extra_tables.has(&"npc_brain"):
		InterestManager.extra_tables.append(&"npc_brain")
	InterestManager.world_id = world_id

	SpaceTimeSync.identity_ready.connect(func(id: PackedByteArray) -> void:
		# An operator (and tests/sidecar_test.sh) needs this to run `register_authority`. Until it
		# is registered this process is nobody: every write is refused, and `input_queue` is
		# invisible to it, because that table's RLS filter joins on the `authority` table.
		print("[Sidecar] identity 0x", id.hex_encode()))
	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		print("[Sidecar] connection: ", SpaceTimeSync.ConnectionState.keys()[s]))
	SignalBus.world_ready.connect(func() -> void:
		print("[Sidecar] authoritative for world ", world_id))
	SignalBus.entity_spawned.connect(func(eid: int, kind: int) -> void:
		print("[Sidecar] simulating entity ", eid, " kind ", kind)
		attach_brain(eid))
	SignalBus.entity_despawned.connect(func(eid: int) -> void:
		print("[Sidecar] released entity ", eid))
	SpaceTimeSync.connect_to_server(cfg)


## Give an entity whose definition names a brain something to drive it.
##
## Attached here rather than in the entity scene because nothing in `foundation/` or `game/` may
## reference `res://sidecar` (hard rule 7b) — so the scene cannot name the component and the
## authority has to add it and bind it by hand. Public so the scene test can call it.
func attach_brain(entity_id: int) -> NpcBrainComponent:
	var ent: SpaceTimeEntity = EntitySpawner.get_entity_node(entity_id) as SpaceTimeEntity
	if ent == null or ent.definition == null or String(ent.definition.brain).is_empty():
		return null
	var existing: SpaceTimeComponent = ent.find_component(NpcBrainComponent)
	if existing != null:
		return existing as NpcBrainComponent
	var brain := NpcBrainComponent.new()
	brain.name = "NpcBrain"
	brain.brain_name = ent.definition.brain
	ent.add_runtime_component(brain)
	print("[Sidecar] entity %d is driven by brain '%s'" % [entity_id, ent.definition.brain])
	return brain


## `--world=N`, from after `--` or from the raw command line. Defaults to the module's default
## world, which is the one a single-world game uses.
func _world_from_cli() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for arg: String in args:
		if not arg.begins_with("--world="):
			continue
		var spec: String = arg.substr("--world=".length())
		var parts: PackedStringArray = spec.split(",", false)
		if parts.size() > 1:
			push_warning("[Sidecar] --world=%s names %d worlds; this process serves one. "
				% [spec, parts.size()] + "Taking %s and ignoring the rest." % parts[0])
		if parts.size() > 0 and parts[0].is_valid_int():
			return int(parts[0])
		push_warning("[Sidecar] --world=%s is not a number; using the default world." % spec)
	return InterestManager.DEFAULT_WORLD
