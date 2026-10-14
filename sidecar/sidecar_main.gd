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
## TWO JOBS (DECISIONS #226). In a SIDECAR world it moves everyone and judges abilities; started with
## `--referee` it JUDGES (`ActionReferee`): the world's players move themselves (a MODULE world), and
## it builds only the world's BOTS (an entity with an `npc_brain` row and no player: DECISIONS #230),
## driving each by its brain, with the walls of the level it loaded, as it would in a SIDECAR world. `--claim=CODE` presents an admin's
## one-time code (`offer_referee`) to be registered for the world, and `--parent-alive=FILE` ends it
## when the game that started it does (`RefereeLauncher`, an editor run: the game keeps the file
## touched; stale or gone, the game is gone).
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
## or those entities never exist here and nothing simulates them. The scene lists the foundation's
## (a player, kind 0; an NPC, kind 1); a genre's definition for the same kind replaces it.
@export var entity_definitions: Array[EntityDefinition] = []
## Also take every genre's entity definitions and tables (shared/game.json, DECISIONS #173), the
## way Boot does, so the sidecar knows the game's kinds without its scene naming a genre.
@export var load_genres: bool = true

var world: SimWorld = null
var referee: ActionReferee = null
## Its world's rounds, written down (DECISIONS #235); off with `--no-record`.
var recorder: SessionRecorder = null
## Started with `--referee`: judging only.
var referee_only: bool = false

var _claim: String = ""
var _parent_alive: String = ""
var _watch: float = 0.0


func _ready() -> void:
	var cfg: NetConfig = (net_config if net_config != null else NetConfig.new()).duplicate()
	referee_only = _flag("--referee")
	_claim = _value("--claim=")
	_parent_alive = _value("--parent-alive=")
	# A referee is the authority for the bots it drives, and builds nothing else.
	cfg.authority_process = true
	EntitySpawner.spawning = true
	if referee_only:
		EntitySpawner.spawn_filter = is_bot
	if cfg.token_path.is_empty() or cfg.token_path == NetConfig.new().token_path:
		cfg.token_path = "user://sidecar_token.dat"
	var world_id: int = _world_from_cli()

	world = SimWorld.new()
	add_child(world)
	world.setup(world_id, level_scene, float(cfg.server_tick_hz))
	world.follow_level()
	referee = ActionReferee.new()
	referee.name = "Referee"
	referee.world_id = world_id
	world.add_child(referee)

	var defs: Array[EntityDefinition] = entity_definitions.duplicate()
	if load_genres:
		var mods: Array[GenreModule] = Genres.modules()
		for d: EntityDefinition in Genres.definitions(mods):
			if not defs.has(d):
				defs.append(d)
		Genres.merge_tables(cfg, mods)
		print("[Sidecar] genres: ", ", ".join(Genres.listed()))
	# A RECORDING OF EVERY ROUND (DECISIONS #235): this process sees every row of its world.
	if not _flag("--no-record"):
		recorder = SessionRecorder.new()
		recorder.name = "Recorder"
		recorder.world_id = world_id
		recorder.level_of = func() -> String: return world.level().scene_file_path if world.level() != null else ""
		add_child(recorder)
	for defn: EntityDefinition in defs:
		EntitySpawner.register_definition(defn)
		referee.know(defn)
		if recorder != null:
			recorder.kind_names[defn.kind] = defn.display_name
	EntitySpawner.world_root_path = EntitySpawner.get_path_to(world.entity_root())

	# The frames to replay. `input_queue` is already in InterestManager's world-filtered list, so
	# this asks for THIS world's input and nobody else's (DECISIONS #104).
	if not InterestManager.extra_tables.has(&"input_queue"):
		InterestManager.extra_tables.append(&"input_queue")
	# And the brains it left behind the last time it ran, so an NPC resumes instead of restarting.
	if not InterestManager.extra_tables.has(&"npc_brain"):
		InterestManager.extra_tables.append(&"npc_brain")
	# What it judges, and the level it judges against (DECISIONS #226).
	for t: StringName in [&"action_request", &"world_level", &"status_state", &"player"]:
		if not InterestManager.extra_tables.has(t):
			InterestManager.extra_tables.append(t)
	InterestManager.world_id = world_id

	SpaceTimeSync.identity_ready.connect(func(id: PackedByteArray) -> void:
		# An operator (and tests/sidecar_test.sh) needs this to run `register_authority`. Until it
		# is registered this process is nobody: every write is refused, and `input_queue` is
		# invisible to it, because that table's RLS filter joins on the `authority` table.
		print("[Sidecar] identity 0x", id.hex_encode()))
	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		print("[Sidecar] connection: ", SpaceTimeSync.ConnectionState.keys()[s]))
	SignalBus.world_ready.connect(func() -> void:
		print("[Sidecar] %s world %d" % ["refereeing" if referee_only else "authoritative for", world_id])
		if not _claim.is_empty():
			var req: ReducerRequest = SpaceTimeSync.call_reducer(&"claim_referee", [world_id, _claim], ["u32", "String"])
			req.settled.connect(func(r: ReducerRequest) -> void:
				print("[Sidecar] claim_referee: ", "registered" if r.outcome == ReducerRequest.Outcome.OK else r.error_message)))
	SpaceTimeSync.row_event.connect(_on_brain_row)
	SignalBus.entity_spawned.connect(func(eid: int, kind: int) -> void:
		print("[Sidecar] simulating entity ", eid, " kind ", kind)
		attach_brain(eid))
	SignalBus.entity_despawned.connect(func(eid: int) -> void:
		print("[Sidecar] released entity ", eid))
	SpaceTimeSync.connect_to_server(cfg)


## The game that started it has gone (`--parent-alive`: its file stale or removed): so does it.
func _process(delta: float) -> void:
	if _parent_alive.is_empty():
		return
	_watch += delta
	if _watch < 1.0:
		return
	_watch = 0.0
	if not RefereeLauncher.is_alive(_parent_alive):
		print("[Sidecar] the game that started it has gone (%s): stopping" % _parent_alive)
		AppExit.quit(get_tree())


func _flag(name: String) -> bool:
	return (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has(name)


func _value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


## A BOT: an entity with an `npc_brain` row and no player row (DECISIONS #230). A referee drives these.
static func is_bot(entity_id: int, _kind: int = -1) -> bool:
	return SpaceTimeSync.get_row(&"npc_brain", entity_id) != null and SpaceTimeSync.get_row(&"player", entity_id) == null


## A bot's brain row came (a bot added to the world after its entity row): a referee builds it now; its
## row gone, it lets it go.
func _on_brain_row(ev: RowEvent) -> void:
	if ev.table != &"npc_brain" or not referee_only:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		if SpaceTimeSync.get_row(&"npc_brain", ev.entity_id) == null:
			EntitySpawner.release(ev.entity_id)
		return
	if is_bot(ev.entity_id) and EntitySpawner.get_entity_node(ev.entity_id) == null:
		EntitySpawner.spawn_now(ev.entity_id)


## Give an entity whose definition names a brain, or whose `npc_brain` row does (a bot), something to
## drive it.
##
## Attached here rather than in the entity scene because nothing in `foundation/` or `game/` may
## reference `res://sidecar` (hard rule 7b) — so the scene cannot name the component and the
## authority has to add it and bind it by hand. Public so the scene test can call it.
func attach_brain(entity_id: int) -> NpcBrainComponent:
	var ent: SpaceTimeEntity = EntitySpawner.get_entity_node(entity_id) as SpaceTimeEntity
	if ent == null or ent.definition == null:
		return null
	var named: StringName = ent.definition.brain
	var row: RefCounted = SpaceTimeSync.get_row(&"npc_brain", entity_id)
	if String(named).is_empty() and row != null:
		named = StringName(String(row.get(&"brain")))
	if String(named).is_empty():
		return null
	var existing: SpaceTimeComponent = ent.find_component(NpcBrainComponent)
	if existing != null:
		return existing as NpcBrainComponent
	var brain := NpcBrainComponent.new()
	brain.name = "NpcBrain"
	brain.brain_name = named
	ent.add_runtime_component(brain)
	print("[Sidecar] entity %d is driven by brain '%s'" % [entity_id, named])
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
