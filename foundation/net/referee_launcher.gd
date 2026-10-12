class_name RefereeLauncher extends Node
## STARTS THE WORLD'S REFEREE FOR AN EDITOR RUN (DECISIONS #226), so a designer presses Play and
## nothing else: when this client is the admin, run from the editor against a server on this machine,
## and the game has an ability a referee judges but the world has no referee online, it offers the
## module a one-time code (`offer_referee`) and starts the project's sidecar headless beside it
## (`--referee --claim=<code> --parent-pid=<this>`), which presents the code and is registered. The
## sidecar ends when this game does. It looks again every few seconds, so a referee that went away
## (the last run's, quitting just as this one started) is replaced; a second instance finds the
## referee online, or the offer standing, and starts nothing.
##
## Outside an editor run (an exported client, a friend's build) it does nothing: a host starts its
## referee as it starts its server. The scene it runs is the sidecar's (hard rule 7b: this only
## STARTS a separate process from the project folder the editor has open; nothing here uses its code).

## The sidecar's entry scene, run in its own process.
const SIDECAR_SCENE: String = "res://sidecar/sidecar_main.tscn"
## How long to wait for the connection and the authority rows before first looking, and between looks.
const SETTLE_S: float = 3.0
const LOOK_EVERY_S: float = 5.0
## The least time between two starts (an offer stands 30 s).
const RESTART_S: float = 30.0

## Off: never starts one (a test, a game that runs its referee itself).
@export var enabled: bool = true

## The process started, if any (0: none).
var started_pid: int = 0
## How many times it has started one this run.
var starts: int = 0
## Why it did not start one, the last time it looked (for the log and tests).
var reason: String = ""

var _wait: float = 0.0
var _since_start: float = INF
var _said: String = ""


func _process(delta: float) -> void:
	if not enabled:
		return
	if not SpaceTimeSync.is_connected_to_server() or not InterestManager.has_world():
		return
	_wait += delta
	_since_start += delta
	if _wait < SETTLE_S:
		return
	_wait = SETTLE_S - LOOK_EVERY_S   # the next look in LOOK_EVERY_S
	reason = why_not()
	if reason.is_empty() and _since_start < RESTART_S:
		reason = "one was started %.0f s ago" % _since_start
	if not reason.is_empty():
		if reason != _said:
			print("[Referee] not starting one: ", reason)
			_said = reason
		return
	_said = ""
	_since_start = 0.0
	start()


## Why this run should not start a referee, or "" when it should.
func why_not() -> String:
	if not OS.has_feature("editor"):
		return "not an editor run"
	if not Roles.is_local_admin():
		return "this client is not the admin"
	if SpaceTimeSync.config == null or not is_local_host(SpaceTimeSync.config.host):
		return "the server is not on this machine"
	if not wants_referee():
		return "nothing in this game is judged by a referee"
	if referee_online(InterestManager.world_id):
		return "world %d has a referee" % InterestManager.world_id
	if not ResourceLoader.exists(SIDECAR_SCENE):
		return "this project has no sidecar"
	return ""


## Offer a code and start the sidecar with it.
func start() -> void:
	var world: int = InterestManager.world_id
	starts += 1
	var code: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"offer_referee", [world, code], ["u32", "String"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.outcome != ReducerRequest.Outcome.OK:
			reason = r.error_message
			print("[Referee] not starting one: ", r.error_message)
			return
		# The sidecar reads the database name the way this client did (UMF_DB, else shared/game.json).
		OS.set_environment("UMF_DB", SpaceTimeSync.database_name(SpaceTimeSync.config))
		# Its log where the game's is (user://referee.log): it has no window to show it.
		var args: PackedStringArray = ["--headless", "--log-file", ProjectSettings.globalize_path("user://referee.log"),
			"--path", ProjectSettings.globalize_path("res://"), SIDECAR_SCENE,
			"--", "--world=%d" % world, "--referee", "--claim=" + code, "--parent-pid=%d" % OS.get_process_id()]
		started_pid = OS.create_process(OS.get_executable_path(), args)
		print("[Referee] started the referee for world %d (pid %d)" % [world, started_pid]))


## Whether any ability in this game's content is judged by a referee.
static func wants_referee() -> bool:
	for d: ContentDef in ContentLibrary.items(&"ability"):
		var a: AbilityDef = d as AbilityDef
		if a != null and a.judged:
			return true
	return false


## Whether `world_id` has a referee: a sidecar authority for it that beat in the last 5 s (the
## module's `referee_online`, as this client can see it).
static func referee_online(world_id: int) -> bool:
	var now: int = ClockSync.server_usec()
	return not SpaceTimeSync.find_rows(&"authority", func(row: RefCounted) -> bool:
		return int(row.get(&"role")) == Roles.SIDECAR and int(row.get(&"world_id")) == world_id \
			and now - int(row.get(&"last_seen")) < 5_000_000).is_empty()


## A host this machine is: the loopback names.
static func is_local_host(host: String) -> bool:
	var h: String = host.get_slice("://", 1) if host.contains("://") else host
	h = h.get_slice(":", 0).strip_edges().to_lower()
	return h in ["127.0.0.1", "localhost", "::1", "[::1]", ""]
