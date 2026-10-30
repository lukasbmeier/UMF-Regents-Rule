class_name SidecarMain extends Node
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
## driving each by its brain, with the walls of the level it loaded, as it would in a SIDECAR world; it is
## sent only the tables it reads, never `input_queue` (`referee_feed`, DECISIONS #286). `--claim=CODE` presents an admin's
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

## `entity_kind::BODY` (server/src/module/constants.rs).
const BODY_KIND: int = 3

## What a REFEREE reads itself (DECISIONS #286): the bots and who is a player, where everyone is and their
## status (the brains' world view), the abilities it judges and the requests to judge, the level, bodies and
## pushes, the brains it left behind. Its feed is these, the tables its entity scenes' components declare,
## each genre's `referee_tables`, and the recorder's while it records; never `input_queue`, which only a
## sidecar that MOVES the players replays (80 % of what a referee was sent: Regent's Rule's load test).
const REFEREE_TABLES: Array[StringName] = [&"world_config", &"entity", &"player", &"movement_state",
	&"status_state", &"ability_def", &"action_request", &"world_level", &"body_state", &"push", &"npc_brain"]

var world: SimWorld = null
var referee: ActionReferee = null
## Flies the world's bodies (DECISIONS #246), in both jobs.
var bodies: BodyReferee = null
## Its world's rounds, written down (DECISIONS #235); off with `--no-record`.
var recorder: SessionRecorder = null
## Started with `--referee`: judging only.
var referee_only: bool = false
## Started with `--region=x0,z0,x1,z1` too (DECISIONS #288): a referee for those cells of its world (and
## `--border=N` cells round them it watches, 1 by default; `--hand-on=M` metres past its edge an NPC is handed
## on, 8 by default); null, the whole world. What it runs is `keeper`'s.
var region: RefereeRegion = null
var keeper: RegionKeeper = null

var _claim: String = ""
var _parent_alive: String = ""
var _watch: float = 0.0
## The project as it was when this started (`ProjectStamp`), and how often it looks again.
var started_stamp: int = 0
var _stamp_watch: float = 0.0
const STAMP_EVERY_S: float = 10.0
## Off with `--keep-when-stale` (a test that changes files under a running sidecar).
var stop_when_stale: bool = true


func _ready() -> void:
	var cfg: NetConfig = (net_config if net_config != null else NetConfig.new()).duplicate()
	referee_only = _flag("--referee")
	_claim = _value("--claim=")
	_parent_alive = _value("--parent-alive=")
	stop_when_stale = not _flag("--keep-when-stale")
	started_stamp = ProjectStamp.now()
	# A referee is the authority for the bots it drives, and builds nothing else.
	cfg.authority_process = true
	EntitySpawner.spawning = true
	# A body is flown by the body referee, never simulated as a character (DECISIONS #246).
	EntitySpawner.spawn_filter = is_bot_not_body if referee_only else is_not_body
	if cfg.token_path.is_empty() or cfg.token_path == NetConfig.new().token_path:
		cfg.token_path = "user://sidecar_token.dat"
	# `--name=N`: an identity of its own (`user://sidecar_token_N.dat`), so several referees run on one machine.
	var own_name: String = _value("--name=")
	if not own_name.is_empty():
		cfg.token_path = "user://sidecar_token_%s.dat" % own_name.validate_filename()
	var world_id: int = _world_from_cli()
	if referee_only and not _value("--region=").is_empty():
		region = RefereeRegion.parse(_value("--region="))
		if region == null:
			push_error("[Sidecar] --region=%s is not x0,z0,x1,z1 (cell squares): refereeing the whole world" % _value("--region="))
		else:
			if _value("--border=").is_valid_int():
				region.border = maxi(0, int(_value("--border=")))
			if _value("--hand-on=").is_valid_float():
				region.hand_on_m = maxf(0.0, float(_value("--hand-on=")))
	if region != null:
		keeper = RegionKeeper.new()
		keeper.name = "Region"
		keeper.region = region
		keeper.world_id = world_id
		add_child(keeper)
		EntitySpawner.spawn_filter = func(eid: int, kind: int = -1) -> bool: return is_bot_not_body(eid, kind) and keeper.drives(eid)

	world = SimWorld.new()
	add_child(world)
	world.setup(world_id, level_scene, float(cfg.server_tick_hz))
	world.follow_level()
	referee = ActionReferee.new()
	referee.name = "Referee"
	referee.world_id = world_id
	world.add_child(referee)
	bodies = BodyReferee.new()
	bodies.name = "Bodies"
	bodies.world_id = world_id
	bodies.tick_hz = float(cfg.server_tick_hz)
	world.add_child(bodies)
	if keeper != null:
		bodies.may_fly = keeper.drives
		referee.may_judge = _judges
		keeper.on_mine = _run_mine
		keeper.on_not_mine = _let_go_of
		InterestManager.region_columns = region.columns()
		print("[Sidecar] a region referee: %s" % region.describe())

	var defs: Array[EntityDefinition] = entity_definitions.duplicate()
	var mods: Array[GenreModule] = []
	if load_genres:
		mods = Genres.modules()
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
		bodies.know(defn)
		if recorder != null:
			recorder.kind_names[defn.kind] = defn.display_name
	EntitySpawner.world_root_path = EntitySpawner.get_path_to(world.entity_root())

	if referee_only:
		# A REFEREE ASKS FOR WHAT IT READS (DECISIONS #286), and reading anything else is an error.
		cfg.core_tables = referee_feed(defs, mods, recorder != null)
		if region != null:
			cfg.core_tables.append(&"npc_driver")
		InterestManager.extra_tables.erase(&"input_queue")
		var asked: Dictionary[StringName, bool] = {}
		for t: StringName in cfg.core_tables + InterestManager.extra_tables + InterestManager.ALWAYS_TABLES:
			asked[t] = true
		SpaceTimeSync.read_only = asked
		print("[Sidecar] a referee's feed: %d tables (%s)" % [cfg.core_tables.size(), ", ".join(cfg.core_tables)])
	else:
		# The frames to replay. `input_queue` is already in InterestManager's world-filtered list, so
		# this asks for THIS world's input and nobody else's (DECISIONS #104).
		if not InterestManager.extra_tables.has(&"input_queue"):
			InterestManager.extra_tables.append(&"input_queue")
		# And what it reads itself: the brains it left behind the last time it ran (an NPC resumes instead
		# of restarting), what it judges and the level it judges against (DECISIONS #226).
		for t: StringName in REFEREE_TABLES:
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


## The game that started it has gone (`--parent-alive`: its file stale or removed): so does it. And the
## project changed under it (a publish, a bake, new code: `ProjectStamp`): it stops, so whatever started
## it starts one running the project as it is now (DECISIONS #272).
func _process(delta: float) -> void:
	_stamp_watch += delta
	if stop_when_stale and _stamp_watch >= STAMP_EVERY_S:
		_stamp_watch = 0.0
		if is_stale():
			print("[Sidecar] the project changed since it started (its code or content is newer): stopping, for one that runs it as it is")
			AppExit.quit(get_tree())
			return
	if _parent_alive.is_empty():
		return
	_watch += delta
	if _watch < 1.0:
		return
	_watch = 0.0
	if not RefereeLauncher.is_alive(_parent_alive):
		print("[Sidecar] the game that started it has gone (%s): stopping" % _parent_alive)
		AppExit.quit(get_tree())


## Whether the project is newer than this sidecar.
func is_stale() -> bool:
	return ProjectStamp.newer_than(started_stamp)


func _flag(name: String) -> bool:
	return (OS.get_cmdline_user_args() + OS.get_cmdline_args()).has(name)


func _value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


## A REFEREE'S FEED (DECISIONS #286): what it reads itself (`REFEREE_TABLES`), what the components of every
## entity it may build declare (`scene_tables`), what each genre says its brains read (`referee_tables`:
## `*`, every one of its tables), and the recorder's while it records. Never `input_queue`.
static func referee_feed(defs: Array[EntityDefinition], mods: Array[GenreModule], recording: bool) -> Array[StringName]:
	var out: Array[StringName] = REFEREE_TABLES.duplicate()
	var add: Callable = func(tables: Array[StringName]) -> void:
		for t: StringName in tables:
			if not out.has(t):
				out.append(t)
	for d: EntityDefinition in defs:
		add.call(scene_tables(d.scene))
	for m: GenreModule in mods:
		add.call(m.tables if m.referee_tables.has(&"*") else m.referee_tables)
	if recording:
		add.call(SessionRecorder.TABLES)
	out.erase(&"input_queue")
	return out


## Every table the components of an entity scene declare (`required_tables`, `also_reads`), the ones every entity is
## given (`SpaceTimeEntity._ensure_status_component`) too: what an entity built from it waits for and is fed.
static func scene_tables(scene: PackedScene) -> Array[StringName]:
	var out: Array[StringName] = []
	if scene == null:
		return out
	var root: Node = scene.instantiate()
	var parts: Array[Node] = []
	var holder: Node = root.get_node_or_null(^"Components")
	if holder != null:
		parts.assign(holder.get_children())
	for path: String in [SpaceTimeEntity.STATUS_COMPONENT, SpaceTimeEntity.HOLD_COMPONENT,
			SpaceTimeEntity.TIMED_PRESS_COMPONENT, SpaceTimeEntity.CARRY_COMPONENT]:
		parts.append((load(path) as Script).new() as Node)
	for n: Node in parts:
		var c: SpaceTimeComponent = n as SpaceTimeComponent
		if c != null:
			for t: StringName in c.required_tables() + c.also_reads():
				if not out.has(t):
					out.append(t)
		if n.get_parent() == null:
			n.free()
	root.free()
	return out


## A BOT: an entity with an `npc_brain` row and no player row (DECISIONS #230). A referee drives these.
static func is_bot(entity_id: int, _kind: int = -1) -> bool:
	if SpaceTimeSync.get_row(&"npc_brain", entity_id) == null:
		return false
	# A `player` row is keyed by its identity, so it is found by its entity, not looked up by it.
	return SpaceTimeSync.find_rows(&"player", func(r: RefCounted) -> bool: return int(r.get(&"entity_id")) == entity_id).is_empty()


## A BODY (kind 3, DECISIONS #246): flown by the body referee, so no entity node simulates it.
static func is_body(entity_id: int, kind: int = -1) -> bool:
	return kind == BODY_KIND or SpaceTimeSync.get_row(&"body_state", entity_id) != null


static func is_not_body(entity_id: int, kind: int = -1) -> bool:
	return not is_body(entity_id, kind)


static func is_bot_not_body(entity_id: int, kind: int = -1) -> bool:
	return is_bot(entity_id, kind) and not is_body(entity_id, kind)


## A REGION REFEREE judges a use of someone it runs (an NPC it drives) or of a player standing in its cells.
func _judges(actor_id: int) -> bool:
	if keeper.drives(actor_id):
		return true
	var m: RefCounted = SpaceTimeSync.get_row(&"movement_state", actor_id)
	return m != null and not is_bot(actor_id) and region.runs(m.get(&"pos") as Vector3)


## The module gave this region referee `eid`: fly it (a body) or build and drive it (a bot).
func _run_mine(eid: int) -> void:
	if is_body(eid):
		bodies.take_body(eid)
	elif is_bot(eid) and EntitySpawner.get_entity_node(eid) == null:
		EntitySpawner.spawn_now(eid)


## It walked out of this region (or the module gave it to another): stop running it.
func _let_go_of(eid: int) -> void:
	bodies.let_go_body(eid)
	if EntitySpawner.get_entity_node(eid) != null:
		print("[Sidecar] entity %d leaves this region: handed on" % eid)
		EntitySpawner.release(eid)


## A bot's brain row came (a bot added to the world after its entity row): a referee builds it now; its
## row gone, it lets it go.
func _on_brain_row(ev: RowEvent) -> void:
	if ev.table != &"npc_brain" or not referee_only:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		if SpaceTimeSync.get_row(&"npc_brain", ev.entity_id) == null:
			EntitySpawner.release(ev.entity_id)
		return
	if is_bot(ev.entity_id) and EntitySpawner.get_entity_node(ev.entity_id) == null 			and (keeper == null or keeper.drives(ev.entity_id)):
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
