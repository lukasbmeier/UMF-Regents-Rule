class_name NetConfig extends Resource
## Connection + timing settings. One .tres per environment (local / staging / prod).

@export_group("Server")
@export var host: String = "http://127.0.0.1:3000"
@export var module_name: String = "umf"
## Codegen module alias (SpacetimeDB dock → module alias). The generated client is
## SpacetimeDB.<module_alias> and generated types are <module_alias><TypeName>. PascalCase.
@export var module_alias: String = "Umf"
## Persisted auth token path (user://). Empty string = anonymous identity each launch.
@export var token_path: String = "user://spacetime_token.txt"

## THIS PROCESS IS AN AUTHORITY, not a player: a headless sidecar simulating a world rather than
## watching one (`docs/SIDECAR_SPEC.md` §3). It changes two things in the foundation and nothing
## else: every entity's movement runs in SERVER_AUTHORITY instead of predicted/interpolated, and
## the movement component asks for `input_queue` as well as `movement_state`.
##
## It lives here because "what kind of process am I" is an environment fact, exactly like the
## host and the token path, and a sidecar already needs its own NetConfig for the stable identity.
@export var authority_process: bool = false

@export_group("Debug")
## TESTING ONLY. Round trip added to everything this client sends and receives, half each way,
## so prediction and interpolation can be judged on localhost. Also `--latency=<ms>` and the F3
## overlay. 0 = off. See LatencySim.
@export var sim_latency_ms: int = 0
## TESTING ONLY. Random extra delay per direction, 0..this. Order is still preserved.
@export var sim_jitter_ms: int = 0

@export_group("Transport")
## 0 = none, 1 = gzip, 2 = brotli. The adapter maps this onto the SDK's enum (whose order differs).
@export_range(0, 2) var compression: int = 1
@export var threaded_parse: bool = true
@export var reconnect: bool = true
## 0 = retry forever.
@export var max_reconnect_attempts: int = 0
## false = server sends updates on in-memory commit (lower latency, the right choice for
## predicted movement). true = waits for durable commit; a crash can retract shown rows either way
## from the player's perspective, so we take the latency win.
@export var confirmed_reads: bool = false
## Awaited per reducer call. SDK clamps to 0.05..3600 s.
@export var reducer_timeout_sec: float = 5.0

@export_group("Simulation")
@export var client_tick_hz: int = 60
@export var server_tick_hz: int = 20
## How many client ticks of input are bundled into one submit_input reducer call.
@export_range(1, 8) var input_batch_size: int = 3

@export_group("Subscriptions")
## The GAME's tables whose rows each belong to one world (they have a `world_id` column): asked
## for `WHERE world_id = <yours>`, like the foundation's own (`InterestManager.WORLD_TABLES`).
## Anything in `core_tables` not here or there is subscribed whole (DECISIONS #154).
@export var world_tables: Array[StringName] = []
## Tables always subscribed at boot. Genre layers add spatial/filtered sets later.
## MUST cover every table a foundation component declares in `required_tables()`, or that
## component's entity stalls on its bind timeout and comes up with default state. A missing
## table here is silent: nothing errors, the entity is simply wrong for 2 s and then wrong
## forever. `tests/e2e_test.sh` is what catches it.
@export var core_tables: Array[StringName] = [
	# Identity and world
	&"world_config", &"entity", &"player",
	# Component-backing tables: movement, health, session, inventory
	&"movement_state", &"health_state", &"session", &"session_member",
	&"item_def", &"inventory_item",
	# Owner-visible only, under RLS (DECISIONS #32)
	&"challenge",
	# Actions (Task 12): the catalogue, per-entity cooldowns, and what happened
	&"ability_def", &"ability_state", &"action_event",
	# In hand or put away (EquipComponent, DECISIONS #160)
	&"equip_state",
	# The look a player chose (the character picker, DECISIONS #166)
	&"appearance",
	# Ready and team in the lobby (DECISIONS #174)
	&"lobby_member",
	# Which level each world runs (DECISIONS #175)
	&"world_level",
	# Each session's match: where its rounds count from, whether it has started (DECISIONS #182)
	&"session_match",
]
