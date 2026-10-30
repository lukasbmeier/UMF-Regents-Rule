extends Node
## SpaceTimeSync — the SDK adapter.
##
## THIS IS THE ONLY SCRIPT IN THE PROJECT THAT MAY REFERENCE SpacetimeDB SDK TYPES.
## Everything else speaks RowEvent, ReducerRequest, SubscriptionSet and the signals below.
##
## Responsibilities
##   • connection lifecycle + identity
##   • subscription sets
##   • reducer calls → ReducerRequest handles
##   • SDK row signals → RowEvent → EntityRegistry
##   • feeding ClockSync
##
## Every direct SDK touchpoint lives in the "SDK BINDING SURFACE" section at the bottom and
## is tagged `# SDK:`. All bindings are verified against the plaught-armor SDK docs/api.md
## (v2.x) and docs/codegen.md. Generated bindings live in res://spacetime_bindings/; the
## client we drive is SpacetimeDB.<module_alias>, and generated types are <Alias><TypeName>.
##
## SDK facts that shape the design (from api.md):
##   • Rows are the cache's own Resource instances. NEVER mutate them — duplicate() first.
##     Components copy values out (MovementState.from_row) and never hold mutable refs.
##   • A reconnect looks like a full teardown: every row fires row_deleted, then rows that
##     still exist are re-inserted. The spawner must despawn/respawn on that; nothing is diffed.
##   • Subscription handles survive a reconnect (suspended → applied again). Never resubscribe
##     from `reconnected`; hold the handle.
##   • Reducer handles have no completion signal; we await wait_for_response() per call.

signal connection_state_changed(state: ConnectionState)
signal identity_ready(identity: PackedByteArray)
## Core subscription set applied: the cache reflects the visible world. Fired once per connect.
signal world_ready()
## Every cache change, normalised. EntityRegistry is the primary consumer.
signal row_event(ev: RowEvent)
signal reducer_settled(req: ReducerRequest)
## A connection attempt failed, with the SDK's own words. Fired on the FIRST failure of an
## attempt; with `NetConfig.reconnect` on, the SDK then keeps retrying and reports progress as
## RECONNECTING. A connect screen shows `reason` — "no answer" and "refused" send a player to
## different places.
signal connection_error(code: int, reason: String)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, FAILED }

var config: NetConfig
## This game's performance reports to the host (`Telemetry`, DECISIONS #244); null without the SDK.
var telemetry: Telemetry = null
var state: ConnectionState = ConnectionState.DISCONNECTED:
	set(v):
		if v == state:
			return
		state = v
		connection_state_changed.emit(v)

var local_identity: PackedByteArray = PackedByteArray()
## A SIGN-IN's ID token to connect with (template 1.0, `SignIn`): the identity is the sign-in's, the
## same on every machine. Empty: the identity's own token file (a guest, the editor, the suites).
var sign_in_token: String = ""
var is_world_ready: bool = false
## Why the last session ended. Empty while a session is live or being attempted.
var last_disconnect_reason: String = ""
## True when this client ASKED to disconnect (a menu, a cancel), false when the connection was
## taken from it. The same DISCONNECTED state means "you left" in one case and "you were
## dropped" in the other, and a player needs to be told which.
var last_disconnect_requested: bool = false
## Set only for the duration of `disconnect_from_server`, which is how `_on_disconnected` tells
## the terminal signal we caused from one we did not.
var _disconnecting: bool = false

## THE VERSION CHECK (DECISIONS #164, #198). Before it opens the socket, the adapter asks the
## server for its schema and checks THIS BUILD'S CONTRACT against it (`SchemaContract`, written
## beside the bindings at codegen by `tools/write_schema_fingerprint.gd`): every table the bindings
## decode has the same row there, every reducer the same arguments, and the compatibility
## generation is the same. A server that only ADDED is played on: an old build keeps working on a
## new server (docs/rules/compatibility.md). A refusal is said here, in words a player can act on,
## instead of failing later in ways nobody can read. A build with no contract (from before #198)
## falls back to the exact fingerprint. A server that does not answer the question (no answer, not
## SpacetimeDB, no such database) is left to the connection itself to explain, exactly as before.
const BINDINGS_FINGERPRINT_PATH: String = "res://spacetime_bindings/schema_fingerprint.json"
const BINDINGS_CONTRACT_PATH: String = "res://spacetime_bindings/schema_contract.json"
## The schema the last codegen read (editor and tests only: the export leaves it out).
const CODEGEN_SCHEMA_PATH: String = "res://spacetime_bindings/codegen_debug/unparsed_schema_%s.json"
## How long the schema question may take before the adapter connects without an answer.
const SCHEMA_CHECK_TIMEOUT_SEC: float = 3.0
## Why the last attempt was refused before connecting, for the player; empty otherwise.
var incompatible_reason: String = ""
## TESTING: stand in for the bindings' fingerprint and contract (the connect playtest plays an
## older build and a newer one this way).
var fingerprint_override: String = ""
var contract_override: Dictionary = {}
## Counts attempts, so a check that answers after its attempt was cancelled does nothing.
var _attempt: int = 0
var _schema_request: HTTPRequest = null

var _sdk: Node = null
var _sets: Dictionary[StringName, SubscriptionSet] = {}
var _pending: Dictionary[int, ReducerRequest] = {}
var _next_local_req_id: int = 1
## Artificial latency for testing prediction on localhost. Inert unless configured
## (`NetConfig.sim_latency_ms`, `--latency=`, or the F3 overlay).
var _latency: LatencySim = LatencySim.new()


func _ready() -> void:
	# SDK: codegen registers `SpacetimeDB` (res://spacetime_bindings/schema/spacetime_autoload.gd),
	# a container holding one generated ModuleClient per configured module, exposed as a
	# property named by the module alias: SpacetimeDB.<Alias>. That client is what we drive.
	var container: Node = get_node_or_null(^"/root/SpacetimeDB")
	if container != null:
		var alias: StringName = StringName(_default_alias())
		var client: Variant = container.get(alias)
		_sdk = client if client is Node else null
		if _sdk == null:
			push_error("SpaceTimeSync: SpacetimeDB.%s not found — module alias in NetConfig must match the codegen alias." % alias)
	if _sdk == null:
		var msg: String = "SpaceTimeSync: generated SpacetimeDB autoload not found. Install the addon, run codegen, and move the SpacetimeDB autoload to the top of the Autoload list."
		if DisplayServer.get_name() == "headless":
			push_warning(msg + " (headless: continuing without SDK)")
		else:
			push_error(msg)
		set_process(false)
		return
	_bind_sdk_signals()
	# HOW THIS GAME RUNS, REPORTED TO THE HOST (DECISIONS #244): in every player's game and every referee.
	telemetry = Telemetry.new()
	telemetry.name = "Telemetry"
	add_child(telemetry)


func _process(_delta: float) -> void:
	_latency.pump()


# =============================================================================
# PUBLIC API
# =============================================================================

## Add `rtt_ms` of round trip (half each way) plus up to `jitter_ms` per direction to everything
## this client sends and receives. 0/0 turns it off. Testing only — see LatencySim.
func set_simulated_latency(rtt_ms: int, jitter_ms: int = 0) -> void:
	_latency.configure(rtt_ms, jitter_ms)


## (round trip ms, jitter ms) currently simulated.
func get_simulated_latency() -> Vector2i:
	return Vector2i(_latency.rtt_ms, _latency.jitter_ms)


## The database to join: `--db=<name>` on the command line, else the `UMF_DB` environment
## variable, else the game's (shared/game.json `database`, DECISIONS #195), else the config's
## `module_name`. How the test suites keep off the database a person
## plays in: they publish `umf-test` and set `UMF_DB` for every process they start (DECISIONS #154).
static func database_name(cfg: NetConfig) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--db="):
			return arg.substr("--db=".length())
	var env: String = OS.get_environment("UMF_DB")
	if not env.is_empty():
		return env
	var game_db: String = str(Genres.game().get("database", ""))
	if not game_db.is_empty():
		return game_db
	return cfg.module_name if cfg != null else "umf"


func connect_to_server(cfg: NetConfig) -> void:
	assert(cfg != null, "NetConfig required")
	if _sdk == null:
		return
	config = cfg
	_resolve_client(cfg.module_alias)
	if _sdk == null:
		state = ConnectionState.FAILED
		return
	is_world_ready = false
	last_disconnect_reason = ""
	last_disconnect_requested = false
	ClockSync.reset()
	_latency.configure(cfg.sim_latency_ms, cfg.sim_jitter_ms)
	incompatible_reason = ""
	_attempt += 1
	state = ConnectionState.CONNECTING
	_check_version_then_connect(cfg, _attempt)


## The fingerprint of the schema this build's bindings were generated from. Empty when no codegen
## has written one, and then nothing is checked.
static func bindings_fingerprint() -> String:
	if not FileAccess.file_exists(BINDINGS_FINGERPRINT_PATH):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS_FINGERPRINT_PATH))
	return String((parsed as Dictionary).get("fingerprint", "")) if parsed is Dictionary else ""


## The contract this build's bindings were generated with (`SchemaContract`). Empty when no codegen
## has written one, and then the fingerprint decides.
static func bindings_contract() -> Dictionary:
	if not FileAccess.file_exists(BINDINGS_CONTRACT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS_CONTRACT_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


## Why a build with fingerprint `ours` and `contract` cannot play on the server whose schema is
## `server_schema_text`, for the player; empty when it can, or when the text is not a schema.
static func compatibility_problem(ours: String, contract: Dictionary, server_schema_text: String) -> String:
	var theirs: String = SchemaFingerprint.of(server_schema_text)
	if theirs.is_empty():
		return ""
	if int(contract.get("format", 0)) == SchemaContract.FORMAT:
		var found: PackedStringArray = SchemaContract.problems(contract, server_schema_text)
		return "" if found.is_empty() else SchemaContract.refusal_message(found, ours, theirs)
	if not ours.is_empty() and theirs != ours:
		return SchemaFingerprint.mismatch_message(ours, theirs)
	return ""


## The schema text the last codegen read, for `module` (the tests compare its fingerprint with the
## bindings'). Empty in an export.
static func codegen_schema_text(module: String = "umf") -> String:
	var path: String = CODEGEN_SCHEMA_PATH % module
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _check_version_then_connect(cfg: NetConfig, attempt: int) -> void:
	var ours: String = fingerprint_override if not fingerprint_override.is_empty() else bindings_fingerprint()
	var contract: Dictionary = contract_override if not contract_override.is_empty() else bindings_contract()
	if not ours.is_empty() or not contract.is_empty():
		var text: String = await _server_schema(cfg)
		if attempt != _attempt or state != ConnectionState.CONNECTING:
			return   # given up on while the server was asked
		var problem: String = compatibility_problem(ours, contract, text)
		if not problem.is_empty():
			incompatible_reason = problem
			last_disconnect_reason = incompatible_reason
			push_warning("[SpaceTimeSync] %s runs schema %s, which this build (%s) cannot play. Not connecting."
				% [cfg.host, SchemaFingerprint.of(text), ours])
			connection_error.emit(0, incompatible_reason)
			state = ConnectionState.DISCONNECTED
			return
	_sdk_connect(cfg)


## The schema the server runs, as it serves it, or "" when it does not say.
func _server_schema(cfg: NetConfig) -> String:
	_cancel_schema_request()
	var http := HTTPRequest.new()
	http.timeout = SCHEMA_CHECK_TIMEOUT_SEC
	add_child(http)
	_schema_request = http
	if http.request(SchemaFingerprint.url(cfg.host, database_name(cfg))) != OK:
		_cancel_schema_request()
		return ""
	var result: Array = await http.request_completed
	if _schema_request == http:
		_schema_request = null
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return ""
	return (result[3] as PackedByteArray).get_string_from_utf8()


func _cancel_schema_request() -> void:
	if _schema_request == null:
		return
	_schema_request.cancel_request()
	_schema_request.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
	_schema_request = null


## End the session on purpose. `reason` is kept on `last_disconnect_reason` for whoever explains
## it to the player. Safe mid-handshake and mid-reconnect: the SDK cancels both.
func disconnect_from_server(reason: String = "client disconnect") -> void:
	if _sdk == null:
		return
	last_disconnect_reason = reason
	last_disconnect_requested = true
	_attempt += 1   # a version check still asking is now for nothing
	_cancel_schema_request()
	_disconnecting = true
	_sdk_disconnect()
	_disconnecting = false
	# An abandoned attempt must not keep an identity request open for another 15 s either.
	_sdk_reset_token_fetch(config.host if config != null else "")
	_fail_all_pending(ReducerRequest.Outcome.DISCONNECTED, reason)
	# The SDK emits its terminal `disconnected` synchronously from disconnect_db, which has
	# already run `_on_disconnected`. Setting the state again is a no-op then; it matters only
	# when the SDK had nothing to close and emitted nothing.
	is_world_ready = false
	state = ConnectionState.DISCONNECTED


func is_connected_to_server() -> bool:
	return state == ConnectionState.CONNECTED


## Called by InterestManager when the core set applies — on first connect, and again each time
## a reconnect re-applies the same handle. The announcement lives here rather than there because
## `is_world_ready` is read all over the project through the adapter.
##
## `local_entity_assigned` is deliberately NOT emitted with it: EntityRegistry owns
## `local_entity_id` and is its single emitter, listening to `world_ready` for the already-cached
## case and to `row_event` for the arrives-later one. Emitting here too fired it twice per
## connect and again on every reconnect (DECISIONS #28).
func mark_world_ready() -> void:
	is_world_ready = true
	world_ready.emit()
	SignalBus.world_ready.emit()


## Apply a subscription set. Its `applied` signal fires when the server confirms.
func subscribe(set: SubscriptionSet) -> void:
	assert(not _sets.has(set.name), "SubscriptionSet '%s' already active" % set.name)
	_sets[set.name] = set
	_sdk_subscribe(set)


func unsubscribe(set: SubscriptionSet) -> void:
	if not _sets.has(set.name):
		return
	_sets.erase(set.name)
	_sdk_unsubscribe(set)
	# An unsubscribed set lets go of the SDK's handle: it releases the SDK's own subscription
	# object, and it is how `_on_sdk_subscription_ended` tells an ending we ASKED for from one
	# the server refused. (The reference cycle this also used to break is now prevented at the
	# source — see the note on the two `connect` calls in _sdk_subscribe.)
	set._handle = null


## Call a reducer. `arg_types` is the SDK's BSATN hint list for non-default numeric widths
## (e.g. ["u32", "f32"]). Prefer the generated typed wrappers via call_generated() when
## codegen is present; this generic path exists so the foundation compiles before codegen.
func call_reducer(name: StringName, args: Array, arg_types: Array[String] = [], seq_from: int = -1, seq_to: int = -1) -> ReducerRequest:
	var req := ReducerRequest.new()
	req.reducer_name = name
	req.args = args
	req.seq_from = seq_from
	req.seq_to = seq_to
	req.sent_usec = Time.get_ticks_usec()
	var local_id: int = _next_local_req_id
	_next_local_req_id += 1
	_pending[local_id] = req

	if state != ConnectionState.CONNECTED:
		_settle(local_id, ReducerRequest.Outcome.DISCONNECTED, "not connected")
		return req

	_sdk_call_reducer(local_id, req, arg_types)
	return req


## Access a generated table wrapper by name (e.g. &"movement_state"). Returned object is
## SDK-typed; only components may call read helpers on it (find, filter, get_all_rows).
## Components must NOT connect to its signals — row_event is the single delivery path.
func get_table(table: StringName) -> Object:
	return _sdk_get_table(table)


## Untyped primary-key lookup through the SDK's LocalDatabase. Returned row is the cache's
## own instance: read-only.
func get_row(table: StringName, pk: Variant) -> RefCounted:
	if not read_only.is_empty() and not read_only.has(table):
		_read_unasked(table)
	return _sdk_get_row_by_pk(table, pk)


## A REFEREE asks only for the tables it reads (DECISIONS #286): these. Reading any other finds nothing,
## ever, so it is an error, once a table, saying where to list it. Empty (every player's client): anything.
var read_only: Dictionary[StringName, bool] = {}
var _unasked: Dictionary[StringName, bool] = {}


func _read_unasked(table: StringName) -> void:
	if _unasked.has(table):
		return
	_unasked[table] = true
	push_error("[SpaceTimeSync] this referee read '%s', which it does not subscribe: list it in the genre's " % table
		+ "genre.tres `referee_tables` (or the foundation's `SidecarMain.REFEREE_TABLES`), DECISIONS #286")


## Every cached row of `table` that `pred` (row -> bool) accepts: the cache's own instances, read-only.
func find_rows(table: StringName, pred: Callable) -> Array:
	if not read_only.is_empty() and not read_only.has(table):
		_read_unasked(table)
	if _sdk == null:
		return []
	var ldb: Object = _sdk.call(&"get_local_database")
	return ldb.call(&"find_where", table, pred) if ldb != null else []


## Every cached row of `tables` that belongs to entity `eid` (by RowEvent's own rule: `entity_id`,
## else `owner_entity_id`), as INSERTED events: what an entity is built from again when it
## respawns (DECISIONS #166).
func entity_rows_as_events(eid: int, tables: Array[StringName]) -> Array[RowEvent]:
	var out: Array[RowEvent] = []
	if _sdk == null:
		return out
	# SDK: LocalDatabase.find_where(table_name, predicate) -> Array of the cache's own rows.
	var ldb: Object = _sdk.call(&"get_local_database")
	if ldb == null:
		return out
	for t: StringName in tables:
		var rows: Array = ldb.call(&"find_where", t, func(r: RefCounted) -> bool:
			return RowEvent._extract_entity_id(r) == eid)
		for r: Variant in rows:
			out.append(RowEvent.make(RowEvent.Kind.INSERTED, t, null, r as RefCounted))
	return out


func get_local_entity_id() -> int:
	## The `player` row keyed by our identity carries our entity_id.
	if local_identity.is_empty():
		return -1
	var row: Variant = _sdk_first_by(&"player", &"identity", local_identity)
	if row == null:
		return -1
	var eid: Variant = row.get(&"entity_id")
	return int(eid) if eid != null else -1


## Batched movement input. Kept in the adapter because the argument is a Vec<InputFrame> of
## generated struct Resources — the one place foundation structs are converted to wire types.
func submit_input(frames: Array[InputFrame]) -> ReducerRequest:
	var req := ReducerRequest.new()
	req.reducer_name = &"submit_input"
	req.seq_from = frames[0].seq if not frames.is_empty() else -1
	req.seq_to = frames[-1].seq if not frames.is_empty() else -1
	req.sent_usec = Time.get_ticks_usec()
	var local_id: int = _next_local_req_id
	_next_local_req_id += 1
	_pending[local_id] = req
	if state != ConnectionState.CONNECTED:
		_settle(local_id, ReducerRequest.Outcome.DISCONNECTED, "not connected")
		return req
	_sdk_submit_input(local_id, req, frames)
	return req


## A world's worth of authoritative movement in ONE reducer call (SIDECAR_SPEC §3). At 20 Hz
## with thirty entities, one call per entity would be six hundred reducer calls a second.
##
## `writes` are the dictionaries `SpaceTimeMovementComponent.take_authority_write()` produces;
## their keys match `MovementWrite` in `server/src/module.rs` field for field.
func write_movement_batch(world_id: int, writes: Array[Dictionary]) -> ReducerRequest:
	var req := ReducerRequest.new()
	req.reducer_name = &"write_movement_batch"
	req.sent_usec = Time.get_ticks_usec()
	var local_id: int = _next_local_req_id
	_next_local_req_id += 1
	_pending[local_id] = req
	if state != ConnectionState.CONNECTED:
		_settle(local_id, ReducerRequest.Outcome.DISCONNECTED, "not connected")
		return req
	_sdk_write_movement_batch(local_id, req, world_id, writes)
	return req


## THE REFEREE'S BODIES, one call a server tick for its world (DECISIONS #246): `writes` are
## {entity_id, pos, vel, rot, spin, at_rest, frames}, as `BodyWrite` in server/src/module/bodies.rs.
func write_body_batch(world_id: int, writes: Array[Dictionary]) -> ReducerRequest:
	return _struct_batch(&"write_body_batch", &"BodyWrite", world_id, writes,
		[[&"entity_id", TYPE_INT], [&"pos", TYPE_VECTOR3], [&"vel", TYPE_VECTOR3], [&"rot", TYPE_VECTOR3],
		[&"spin", TYPE_VECTOR3], [&"at_rest", TYPE_BOOL], [&"frames", TYPE_INT]])


## WHAT THE REFEREE'S BODIES HIT (DECISIONS #246): `contacts` are {body_id, other_id, pos, normal,
## speed}, as `BodyContactWrite`.
func report_body_contacts(world_id: int, contacts: Array[Dictionary]) -> ReducerRequest:
	return _struct_batch(&"report_body_contacts", &"BodyContactWrite", world_id, contacts,
		[[&"body_id", TYPE_INT], [&"other_id", TYPE_INT], [&"pos", TYPE_VECTOR3], [&"normal", TYPE_VECTOR3],
		[&"speed", TYPE_FLOAT]])


## A reducer taking (world_id: u32, Vec<a generated struct>): each dictionary becomes one `type_name`,
## its `fields` set in order with their Godot types.
func _struct_batch(reducer: StringName, type_name: StringName, world_id: int, items: Array[Dictionary], fields: Array) -> ReducerRequest:
	var req := ReducerRequest.new()
	req.reducer_name = reducer
	req.sent_usec = Time.get_ticks_usec()
	var local_id: int = _next_local_req_id
	_next_local_req_id += 1
	_pending[local_id] = req
	if state != ConnectionState.CONNECTED:
		_settle(local_id, ReducerRequest.Outcome.DISCONNECTED, "not connected")
		return req
	if _sdk == null:
		_settle(local_id, ReducerRequest.Outcome.FAILED, "SDK client missing — run codegen")
		return req
	var wire: Array = []
	for it: Dictionary in items:
		var m: Resource = _new_generated_type(type_name)
		if m == null:
			_settle(local_id, ReducerRequest.Outcome.FAILED, "generated %s type missing — run codegen" % type_name)
			return req
		for f: Array in fields:
			var key: StringName = f[0]
			match int(f[1]):
				TYPE_INT:
					m.set(key, int(it[key]))
				TYPE_FLOAT:
					m.set(key, float(it[key]))
				TYPE_BOOL:
					m.set(key, bool(it[key]))
				_:
					m.set(key, it[key])
		wire.append(m)
	var elem_type: StringName = StringName(config.module_alias + String(type_name))
	_latency.send(func() -> void:
		var call: RefCounted = _sdk.call(&"call_reducer", String(reducer), [world_id, wire], ["u32", elem_type], &"")
		_track_call(local_id, req, call))
	return req


# =============================================================================
# INTERNAL
# =============================================================================

## Alias used before connect_to_server() hands us a NetConfig: the default NetConfig's.
func _default_alias() -> String:
	return NetConfig.new().module_alias


func _resolve_client(alias: String) -> void:
	var container: Node = get_node_or_null(^"/root/SpacetimeDB")
	if container == null:
		return
	var client: Variant = container.get(StringName(alias))
	if client is Node and client != _sdk:
		_sdk = client
		_bind_sdk_signals()


func _on_connected(identity: PackedByteArray, _token: String) -> void:
	local_identity = identity
	identity_ready.emit(local_identity)
	# InterestManager subscribes off `connection_state_changed`. WHAT to ask for is its decision,
	# not the adapter's: see `foundation/net/interest_manager.gd`.
	state = ConnectionState.CONNECTED


func _on_disconnected() -> void:
	# `disconnected` is TERMINAL in this SDK: transient drops surface as `reconnecting`, never
	# here. Every subscription handle has ended; a new connect_to_server() starts fresh.
	if not _disconnecting:
		last_disconnect_requested = false
		if last_disconnect_reason.is_empty():
			last_disconnect_reason = "connection lost"
	_latency.clear()
	_fail_all_pending(ReducerRequest.Outcome.DISCONNECTED, "connection closed")
	is_world_ready = false
	for s: SubscriptionSet in _sets.values():
		s._handle = null   # every handle died with the connection; see unsubscribe()
	_sets.clear()
	state = ConnectionState.DISCONNECTED


func _on_reconnected() -> void:
	# Same handles, re-applied by the SDK. Our SubscriptionSets flip back to applied via
	# their existing `applied` connections. Nothing to resubscribe here.
	state = ConnectionState.CONNECTED


func _on_reconnect_failed() -> void:
	state = ConnectionState.FAILED
	SignalBus.notification_requested.emit("Lost connection to server.", 2)


## A RING'S CELLS NAME NO WORLD (template 1.5.1, DECISIONS #291): SpacetimeDB narrows a subscription by
## one `column = value`, never by `world_id = W AND chunk = N`, so a ring asked that way had every row moved
## checked against every client's every cell query (on a world as big as Skyrim's, each player's nine
## cells their own: the server's whole tick). A ring asks `chunk = N` alone, and the rows of another world
## that share the cell number are kept from the game HERE: `ring_world` is the world shown (-1: nothing
## kept back), `ring_tables` the cell tables. A row moving out of it is a delete, into it an insert; our
## own entity's rows always pass (its world changes before the ring's does).
var ring_world: int = -1
var ring_tables: Dictionary[StringName, bool] = {}


## Show world `world` of the ring's tables (InterestManager, on a world change): the cached rows of the
## world left are deleted, the new world's (held back until now) inserted, as if they had just arrived.
func show_ring_world(world: int, tables: Dictionary[StringName, bool]) -> void:
	var was: int = ring_world
	ring_world = world
	ring_tables = tables
	if was < 0 or was == world:
		return
	var own: int = EntityRegistry.local_entity_id
	for t: StringName in tables:
		for r: Variant in find_rows(t, func(row: RefCounted) -> bool: return _world_of(row) == was):
			if RowEvent._extract_entity_id(r as RefCounted) != own:
				_emit_row_now(RowEvent.Kind.DELETED, t, r as RefCounted, null)
		for r: Variant in find_rows(t, func(row: RefCounted) -> bool: return _world_of(row) == world):
			if RowEvent._extract_entity_id(r as RefCounted) != own:
				_emit_row_now(RowEvent.Kind.INSERTED, t, null, r as RefCounted)


static func _world_of(row: RefCounted) -> int:
	var w: Variant = row.get(&"world_id") if row != null else null
	return int(w) if w != null else -1


func _emit_row(kind: RowEvent.Kind, table: StringName, old: RefCounted, new: RefCounted) -> void:
	if ring_world >= 0 and ring_tables.has(table):
		var row: RefCounted = new if new != null else old
		if RowEvent._extract_entity_id(row) != EntityRegistry.local_entity_id or EntityRegistry.local_entity_id < 0:
			var was_in: bool = old != null and _world_of(old) == ring_world
			var is_in: bool = new != null and _world_of(new) == ring_world
			match kind:
				RowEvent.Kind.INSERTED:
					if not is_in:
						return
				RowEvent.Kind.DELETED:
					if not was_in:
						return
				_:
					if was_in and not is_in:
						kind = RowEvent.Kind.DELETED
						new = null
					elif is_in and not was_in:
						kind = RowEvent.Kind.INSERTED
						old = null
					elif not is_in:
						return
	_emit_row_now(kind, table, old, new)


func _emit_row_now(kind: RowEvent.Kind, table: StringName, old: RefCounted, new: RefCounted) -> void:
	if _latency.is_passthrough():
		_deliver_row(kind, table, old, new)
	else:
		_latency.receive(func() -> void: _deliver_row(kind, table, old, new))


## The clock is fed HERE, at delivery, so its offset estimate includes any simulated delay —
## otherwise remote interpolation would think packets arrive earlier than they do.
func _deliver_row(kind: RowEvent.Kind, table: StringName, old: RefCounted, new: RefCounted) -> void:
	var ev := RowEvent.make(kind, table, old, new)
	# Feed the clock from any row carrying a server timestamp column.
	var cur: RefCounted = ev.current()
	if cur != null:
		var ts: Variant = cur.get(&"server_ts")
		if ts != null:
			ClockSync.observe_server_timestamp(int(ts))
	row_event.emit(ev)


func _settle(local_id: int, outcome: ReducerRequest.Outcome, msg: String = "") -> void:
	var req: ReducerRequest = _pending.get(local_id)
	if req == null:
		return
	_pending.erase(local_id)
	req._settle(outcome, msg)
	if outcome == ReducerRequest.Outcome.OK and req.rtt_usec() > 0:
		ClockSync.observe_rtt(req.rtt_usec())
	elif outcome == ReducerRequest.Outcome.REJECTED:
		SignalBus.action_rejected.emit(req.reducer_name, msg)
	reducer_settled.emit(req)


func _fail_all_pending(outcome: ReducerRequest.Outcome, msg: String) -> void:
	for id: int in _pending.keys():
		_settle(id, outcome, msg)


# =============================================================================
# SDK BINDING SURFACE
# Every line that names an SDK symbol is here. Nothing above this comment does.
# Verified against plaught-armor Godot-SpacetimeDB-SDK docs/api.md and docs/codegen.md.
# =============================================================================

## SpacetimeDBReducerCall.Outcome — copied so we never depend on the enum being loadable here.
enum _SdkOutcome { PENDING, OK, OK_EMPTY, ERROR, INTERNAL_ERROR, TIMEOUT, DISCONNECTED }
## SpacetimeDBConnection.CompressionPreference
enum _SdkCompression { NONE = 0, BROTLI = 1, GZIP = 2 }


func _bind_sdk_signals() -> void:
	# SDK: SpacetimeDBClient signals
	_sdk.connect(&"connected", _on_connected)                       # (identity: PackedByteArray, token: String)
	_sdk.connect(&"disconnected", _on_disconnected)                 # ()
	_sdk.connect(&"connection_error", func(code: int, reason: String) -> void:
		push_warning("SpacetimeDB connection_error %d: %s" % [code, reason])
		connection_error.emit(code, reason))
	_sdk.connect(&"reconnecting", func(attempt: int, max_attempts: int) -> void:
		state = ConnectionState.RECONNECTING
		if attempt == 1:
			SignalBus.notification_requested.emit("Reconnecting…", 1)
		elif max_attempts > 0 and attempt == max_attempts:
			SignalBus.notification_requested.emit("Reconnecting (last attempt)…", 1))
	_sdk.connect(&"reconnected", _on_reconnected)                   # ()
	_sdk.connect(&"reconnect_failed", _on_reconnect_failed)         # ()

	# SDK: row signals — rows are Resources owned by the cache (read-only for us)
	_sdk.connect(&"row_inserted", func(table: StringName, row: Resource) -> void:
		_emit_row(RowEvent.Kind.INSERTED, table, null, row))
	_sdk.connect(&"row_updated", func(table: StringName, old_row: Resource, new_row: Resource) -> void:
		_emit_row(RowEvent.Kind.UPDATED, table, old_row, new_row))
	_sdk.connect(&"row_deleted", func(table: StringName, row: Resource) -> void:
		_emit_row(RowEvent.Kind.DELETED, table, row, null))


func _sdk_connect(cfg: NetConfig) -> void:
	_sdk_reset_token_fetch(cfg.host)
	# SDK: SpacetimeDBConnectionOptions (Resource)
	var opts: Resource = _sdk_new_options()
	if opts != null:
		opts.set(&"compression", _compression_from_config(cfg.compression))
		opts.set(&"threading", cfg.threaded_parse)
		opts.set(&"auto_reconnect", cfg.reconnect)
		opts.set(&"max_reconnect_attempts", cfg.max_reconnect_attempts)
		opts.set(&"confirmed_reads", cfg.confirmed_reads)
		opts.set(&"one_time_token", cfg.token_path.is_empty())
		opts.set(&"save_token", not cfg.token_path.is_empty())
		opts.set(&"process_while_paused", true)
		if not sign_in_token.is_empty():
			# A sign-in's token: used as it is, never written over the identity's token file.
			opts.set(&"token", sign_in_token)
			opts.set(&"one_time_token", false)
			opts.set(&"save_token", false)
	# SDK: token file path lives on the client, not the options
	if not cfg.token_path.is_empty() and sign_in_token.is_empty():
		_sdk.set(&"token_save_path", cfg.token_path)
	# SDK: connect_db(host_url, database_name, options). Failures arrive via connection_error.
	_sdk.call(&"connect_db", cfg.host, database_name(cfg), opts)


func _sdk_disconnect() -> void:
	# SDK: disconnect_db() — terminal; ends every subscription handle
	_sdk.call(&"disconnect_db")


## SDK WORKAROUND (vendored plaught-armor v2.8.0). A client with no saved identity fetches one
## over HTTP first, through a helper node, and that helper has two faults:
##
##   1. It is built ONCE, with the first host the client was ever given; `connect_db` never
##      tells it about a new one. After one attempt at a wrong address, every later identity
##      request still went to the wrong address.
##   2. `disconnect_db` leaves its request running, and while one runs it refuses to start
##      another — printing "Cannot request token while another request is pending" and
##      emitting nothing, so the attempt just hangs. A dead port holds it for the full 15 s
##      HTTP timeout.
##
## Together: a fresh install that mistyped the address once could not connect ANYWHERE until it
## was restarted, which is precisely what a friend joining for the first time does. Found by
## tests/connect_playtest.sh. Delete this when the SDK repoints and cancels the helper itself.
##
## `host` empty only cancels. Before the first connect the helper does not exist yet, and is
## then built with the right host.
func _sdk_reset_token_fetch(host: String) -> void:
	# SDK: SpacetimeDBClient adds its SpacetimeDBRestAPI as a child named "RestAPI".
	var rest: Node = _sdk.get_node_or_null(^"RestAPI")
	if rest == null:
		return
	# SDK: private members of SpacetimeDBRestAPI — `_http_request` (HTTPRequest),
	# `_pending_request_type` (RequestType, NONE = 0) and `_base_url` (String, no trailing /).
	var http: HTTPRequest = rest.get(&"_http_request") as HTTPRequest
	if http != null:
		http.cancel_request()
	rest.set(&"_pending_request_type", 0)
	if not host.is_empty():
		rest.set(&"_base_url", host.rstrip("/"))


func _sdk_new_options() -> Resource:
	# SDK: SpacetimeDBConnectionOptions is a global class_name registered by the addon.
	if ClassDB.class_exists(&"SpacetimeDBConnectionOptions"):
		return ClassDB.instantiate(&"SpacetimeDBConnectionOptions") as Resource
	var found: Variant = _find_global_class(&"SpacetimeDBConnectionOptions")
	return found.new() if found != null else null


func _compression_from_config(v: int) -> int:
	# NetConfig: 0 none, 1 gzip, 2 brotli  →  SDK enum: NONE 0, BROTLI 1, GZIP 2
	match v:
		1: return _SdkCompression.GZIP
		2: return _SdkCompression.BROTLI
		_: return _SdkCompression.NONE


func _sdk_subscribe(set: SubscriptionSet) -> void:
	# SDK: subscribe(queries: PackedStringArray) -> SpacetimeDBSubscription
	var handle: RefCounted = _sdk.call(&"subscribe", PackedStringArray(set.queries))
	set._handle = handle
	if handle == null:
		set.ended.emit(set, "subscribe returned null")
		return
	# A handle that never went out is already ended with error != OK and query_id == -1.
	var err: int = int(handle.get(&"error"))
	if err != OK:
		set.error_message = "subscribe failed: %s" % error_string(err)
		set.ended.emit(set, set.error_message)
		return
	# BOUND METHODS, NOT LAMBDAS. A lambda that reads `handle.error_message` captures the handle,
	# and it is stored on that same handle's signal: the handle references itself and never frees,
	# taking the subscription set and every query string with it. One pair per subscribe.
	handle.connect(&"applied", _on_sdk_subscription_applied.bind(set))
	handle.connect(&"end", _on_sdk_subscription_ended.bind(set))


## Through the latency queue like the rows it confirms: `applied` overtaking its own initial rows
## would announce world_ready before the world had arrived.
func _on_sdk_subscription_applied(set: SubscriptionSet) -> void:
	_latency.receive(func() -> void:
		set.is_applied = true
		set.applied.emit(set))


func _on_sdk_subscription_ended(set: SubscriptionSet) -> void:
	set.is_applied = false
	# Null once `unsubscribe()` has broken the cycle — an ending we asked for carries no error.
	if set._handle != null:
		set.error_message = str(set._handle.get(&"error_message"))
	set.ended.emit(set, set.error_message)


func _sdk_unsubscribe(set: SubscriptionSet) -> void:
	# SDK: SpacetimeDBSubscription.unsubscribe() -> Error. `end` fires on server confirm.
	if set._handle != null:
		set._handle.call(&"unsubscribe")


func _sdk_call_reducer(local_id: int, req: ReducerRequest, arg_types: Array[String]) -> void:
	_latency.send(func() -> void:
		# SDK: call_reducer(name: String, args: Array, types: Array, ret_bsatn_type: StringName)
		var call: RefCounted = _sdk.call(&"call_reducer", String(req.reducer_name), req.args, arg_types)
		_track_call(local_id, req, call))


func _sdk_submit_input(local_id: int, req: ReducerRequest, frames: Array[InputFrame]) -> void:
	# SDK: generated reducer wrapper `_sdk.reducers.submit_input(frames: Array[<Alias>InputFrame])`.
	# Type hints for u32/u8/f32 fields come from the generated struct's BSATN_TYPES, which is
	# why this path is used instead of the generic call_reducer.
	# NOTE: we deliberately do NOT call the generated `reducers.submit_input(frames)` wrapper.
	# Its parameter is `Array[<Alias>InputFrame]`, and GDScript refuses an untyped Array with
	# "does not have the same element type as the expected typed array argument" — so every
	# input submission failed. The wrapper itself just forwards to the generic entry point
	# with the element type as a BSATN hint, which is what we do here, minus the typed-array
	# construction. Caught by tests/e2e_test.sh; no unit test can see it.
	if _sdk == null:
		_settle(local_id, ReducerRequest.Outcome.FAILED, "SDK client missing — run codegen")
		return
	var wire: Array = []
	for f in frames:
		var w: Resource = _new_generated_type(&"InputFrame")
		if w == null:
			_settle(local_id, ReducerRequest.Outcome.FAILED, "generated InputFrame type missing — run codegen")
			return
		w.set(&"seq", f.seq)
		w.set(&"client_tick", f.client_tick)
		w.set(&"move_x", f.move_dir.x)
		w.set(&"move_y", f.move_dir.y)
		w.set(&"look_yaw", f.look_yaw)
		w.set(&"look_pitch", f.look_pitch)
		w.set(&"jump", f.jump)
		w.set(&"sprint", f.sprint)
		w.set(&"client_pos", f.client_pos)     # Rust Vec3{x,y,z: f32} ⇄ Godot Vector3
		w.set(&"epoch", f.epoch)
		w.set(&"move_state", f.move_state)
		w.set(&"dash", f.dash)
		w.set(&"slow", f.slow)
		w.set(&"face", f.face)
		wire.append(w)
	var elem_type: StringName = StringName(config.module_alias + "InputFrame")
	_latency.send(func() -> void:
		var call: RefCounted = _sdk.call(&"call_reducer", "submit_input", [wire], [elem_type], &"")
		_track_call(local_id, req, call))


## Same shape as `_sdk_submit_input`: build the generated struct by hand and hand the generic
## entry point the element type as a BSATN hint, because the generated wrapper's parameter is a
## TYPED array that GDScript will not accept an untyped one for.
##
## ASSUMPTION: the hint list is positional, one entry per reducer argument — `submit_input` has a
## single argument and passes a single hint. `tests/integration_test.sh` is what proves it, since
## a wrong hint is a BSATN error at the server, not a GDScript one.
func _sdk_write_movement_batch(local_id: int, req: ReducerRequest, world_id: int,
		writes: Array[Dictionary]) -> void:
	if _sdk == null:
		_settle(local_id, ReducerRequest.Outcome.FAILED, "SDK client missing — run codegen")
		return
	var wire: Array = []
	for w: Dictionary in writes:
		var m: Resource = _new_generated_type(&"MovementWrite")
		if m == null:
			_settle(local_id, ReducerRequest.Outcome.FAILED,
				"generated MovementWrite type missing — run codegen")
			return
		m.set(&"entity_id", int(w["entity_id"]))
		m.set(&"pos", w["pos"])                  # Rust Vec3{x,y,z: f32} ⇄ Godot Vector3
		m.set(&"vel", w["vel"])
		m.set(&"yaw", float(w["yaw"]))
		m.set(&"grounded", bool(w["grounded"]))
		m.set(&"move_state", int(w["move_state"]))
		m.set(&"last_processed_seq", int(w["last_processed_seq"]))
		m.set(&"teleport_flag", bool(w["teleport_flag"]))
		wire.append(m)
	var elem_type: StringName = StringName(config.module_alias + "MovementWrite")
	_latency.send(func() -> void:
		var call: RefCounted = _sdk.call(&"call_reducer", "write_movement_batch",
			[world_id, wire], ["u32", elem_type], &"")
		_track_call(local_id, req, call))


func _track_call(local_id: int, req: ReducerRequest, call: RefCounted) -> void:
	if call == null:
		_settle(local_id, ReducerRequest.Outcome.FAILED, "reducer call returned null handle")
		return
	req.request_id = int(call.get(&"request_id"))
	# SDK: handle.error is the send result; a refused send never gets a response
	var send_err: int = int(call.get(&"error"))
	if send_err != OK:
		_settle(local_id, ReducerRequest.Outcome.FAILED, "send failed: %s" % error_string(send_err))
		return
	_await_call(local_id, call)


func _await_call(local_id: int, call: RefCounted) -> void:
	# SDK: await SpacetimeDBReducerCall.wait_for_response(timeout_sec) -> self.
	# Deadline must be 0.05..3600 s; the SDK falls back to 10 s otherwise.
	await call.call(&"wait_for_response", clampf(config.reducer_timeout_sec, 0.05, 3600.0))
	var msg: String = str(call.get(&"error_message"))
	var sdk_outcome: int = int(call.get(&"outcome"))
	if _latency.is_passthrough():
		_settle_from_sdk(local_id, sdk_outcome, msg)
	else:
		_latency.receive(func() -> void: _settle_from_sdk(local_id, sdk_outcome, msg))


func _settle_from_sdk(local_id: int, sdk_outcome: int, msg: String) -> void:
	match sdk_outcome:
		_SdkOutcome.OK, _SdkOutcome.OK_EMPTY:
			_settle(local_id, ReducerRequest.Outcome.OK)
		_SdkOutcome.ERROR:
			_settle(local_id, ReducerRequest.Outcome.REJECTED, msg)      # module returned Err(...)
		_SdkOutcome.INTERNAL_ERROR:
			_settle(local_id, ReducerRequest.Outcome.FAILED, msg)
		_SdkOutcome.TIMEOUT:
			_settle(local_id, ReducerRequest.Outcome.TIMEOUT, msg)
		_SdkOutcome.DISCONNECTED:
			_settle(local_id, ReducerRequest.Outcome.DISCONNECTED, msg)
		_:
			_settle(local_id, ReducerRequest.Outcome.FAILED, "still pending after wait: %s" % msg)


func _sdk_get_table(table: StringName) -> Object:
	# SDK: generated ModuleClient.db.<table_snake_case> → ModuleTable wrapper
	var db: Object = _sdk.get(&"db")
	if db == null:
		return null
	var t: Variant = db.get(table)
	return t if t is Object else null


func _sdk_get_row_by_pk(table: StringName, pk: Variant) -> RefCounted:
	# SDK: LocalDatabase.get_row_by_pk(table_name, primary_key_value)
	var ldb: Object = _sdk.call(&"get_local_database")
	return ldb.call(&"get_row_by_pk", table, pk) if ldb != null else null


func _sdk_first_by(table: StringName, field: StringName, value: Variant) -> Variant:
	# SDK: LocalDatabase.first_by(table_name, field, value) — untyped, needs no generated wrapper
	var ldb: Object = _sdk.call(&"get_local_database")
	return ldb.call(&"first_by", table, field, value) if ldb != null else null


func _new_generated_type(type_name: StringName) -> Resource:
	# SDK: codegen emits one global class_name per module type as <Alias><TypeName>
	# (docs/codegen.md: table `root_thing` in module alias `MyMod` → `MyModRootThing`).
	var found: Variant = _find_global_class(StringName(config.module_alias + String(type_name)))
	if found == null:
		return null
	return found.new() as Resource


func _find_global_class(class_name_sn: StringName) -> Variant:
	for info: Dictionary in ProjectSettings.get_global_class_list():
		if info["class"] == class_name_sn:
			return load(info["path"])
	return null
