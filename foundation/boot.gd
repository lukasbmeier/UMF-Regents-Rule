extends Node
## Boot — registers entity definitions, then starts the connection. Nothing else.
## Genre layers replace main_scene; they should still register their definitions and call
## SpaceTimeSync.connect_to_server.
##
## With a `connect_screen`, "starts the connection" means "asks the player where to": the screen
## greets them, and boot connects when they press Connect. Without one — tests, the greybox demo,
## anything headless — boot connects straight away, exactly as it always has.

@export var net_config: NetConfig
## Which entity kinds this build knows how to spawn. The foundation ships kind 0 (player);
## a genre appends its own.
@export var entity_definitions: Array[EntityDefinition] = []
## Where spawned entities are parented. Leave empty to use the scene root. A genre's level
## scene points this at whatever node holds its dynamic content.
@export var world_root: NodePath
## The front door (`res://foundation/ui/connect_screen.tscn`). Empty: connect immediately.
@export var connect_screen: PackedScene
## The Escape menu (`res://foundation/ui/pause_menu.tscn`). Optional.
@export var pause_menu: PackedScene
## Offer the character picker (DECISIONS #166) on the connect screen and in the Escape menu, when
## the player's definition (kind 0) has more than one look to choose from.
@export var character_picker: bool = true
## THE GAME'S GENRES (DECISIONS #173): load every genre `shared/game.json` names
## (`res://game/<id>/genre.tres`): their entity definitions and tables join the ones above, and
## their scenes (a HUD, the sky, the music) are put under this scene's root. Off in a scene that
## is not the game (the foundation's own boot, a test level).
@export var load_genres: bool = false

## The genres booted, in order (empty with `load_genres` off).
var genres: Array[GenreModule] = []
## Show the lobby (DECISIONS #174) while a round's lobby is open, for a session kind whose rules
## give it one: who is here, who is ready, the teams.
@export var lobby_panel: bool = true
var _lobby: LobbyPanel = null
## THE LOBBY SCREEN (DECISIONS #182): after connecting, before the game: everyone's characters,
## Choose character, Ready (or Join, arriving mid-match). On a build with a window.
@export var lobby_screen: bool = true
var _lobby_screen: LobbyScreen = null
## THE SPLASH (DECISIONS #183): played before the connect screen on a build with a window (a
## scene with `SplashScreen` at its root: the game's is `res://game/splash_screen.tscn`). Empty: none.
@export var splash_screen: PackedScene

## What this client will call itself. A flag, else what was saved, else nothing — a player with
## no name is shown by entity id rather than being refused a game.
var _player_name: String = ""
var _screen: ConnectScreen = null
var _menu: PauseMenu = null
## The look this player chose (`Appearance` text), sent on every connect like the name.
var _appearance: String = ""
## True while boot presses Connect on the player's behalf from a flag. A flag overrides one run;
## it is not the player choosing an address, so it is not remembered (ConnectSettings).
var _suppress_save: bool = false

# What the command line said. Recorded first and applied in order, because the saved settings
# are keyed by the identity and the identity comes from the command line too.
var _flag_host: String = ""
var _flag_name: String = ""
var _flag_name_given: bool = false
var _flag_connect_screen: bool = false
var _flag_autoconnect: bool = false
var _flag_connect_timeout: float = -1.0
var _flag_no_splash: bool = false
var _flag_lobby_screen: bool = false


func _ready() -> void:
	# THE GAME'S LOOK (DECISIONS #265): every window, menu and button in it is drawn with its UiStyle.
	UiStyle.apply(get_tree().root)
	# The window's close button quits through AppExit like everything else: sounds stopped and
	# released first (DECISIONS #151).
	AppExit.hold_close_request(get_tree())
	if net_config == null:
		net_config = NetConfig.new()
	else:
		# Don't mutate the shared .tres on disk when applying per-instance overrides.
		net_config = net_config.duplicate()
	_apply_cli_overrides()
	# The saved settings belong to this identity, which `_apply_cli_overrides` has just settled.
	# Then flag > saved > the NetConfig's own default: a player who typed a server address once
	# should not have to type it again, and a harness that passes a flag should not be
	# overridden by whatever they typed.
	ConnectSettings.use_profile(_identity_tag())
	net_config.host = _flag_host if not _flag_host.is_empty() \
		else ConnectSettings.host(net_config.host)
	_player_name = _flag_name if _flag_name_given else ConnectSettings.player_name()
	_appearance = ConnectSettings.appearance()
	if load_genres:
		_load_genres()
	EntityDefinition.add_foundation_kinds(entity_definitions)
	for defn: EntityDefinition in entity_definitions:
		EntitySpawner.register_definition(defn)
	if not world_root.is_empty():
		var root_node: Node = get_node_or_null(world_root)
		if root_node != null:
			EntitySpawner.world_root_path = EntitySpawner.get_path_to(root_node)
		else:
			push_warning("[Boot] world_root '%s' not found; spawning into the scene root" % world_root)

	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		print("[Boot] connection: ", SpaceTimeSync.ConnectionState.keys()[s]))
	SignalBus.world_ready.connect(func() -> void: print("[Boot] world ready"))
	SignalBus.local_entity_assigned.connect(func(eid: int) -> void:
		print("[Boot] local entity: ", eid)
		_announce_name()
		_announce_appearance())
	SignalBus.entity_spawned.connect(func(eid: int, kind: int) -> void:
		print("[Boot] entity spawned: ", eid, " kind ", kind,
			" local=", EntityRegistry.is_local(eid))
		if EntityRegistry.is_local(eid):
			_report_view.call_deferred())
	SignalBus.entity_despawned.connect(func(eid: int) -> void: print("[Boot] entity despawned: ", eid))
	SignalBus.entity_health_changed.connect(func(eid: int, cur: float, mx: float) -> void:
		print("[Boot] health: entity ", eid, " ", cur, "/", mx))
	SignalBus.entity_died.connect(func(eid: int, killer: int) -> void:
		print("[Boot] DIED: entity ", eid, " killed by ", killer))
	SignalBus.entity_revived.connect(func(eid: int) -> void: print("[Boot] revived: ", eid))
	_start()


## Either greet the player or connect. The screen is built whenever there is someone to show it
## to, even when it is not greeting them: it is also where a player lands when a session ends.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		AppExit.quit(get_tree())


## Whether the splash plays: a game that has one, a window to show it in, a player who has not turned
## it off (Settings: "Splash screen at start"), and no harness connecting for them.
func wants_splash(has_display: bool) -> bool:
	return splash_screen != null and has_display and not _flag_no_splash and not _flag_autoconnect \
		and _flag_host.is_empty() and bool(Settings.get_value(&"splash_at_start"))


func _start() -> void:
	var has_display: bool = DisplayServer.get_name() != "headless"
	# The splash first, for a player: never for a harness that connects for them, nor headless.
	if wants_splash(has_display):
		var splash: SplashScreen = splash_screen.instantiate() as SplashScreen
		if splash != null:
			add_child(splash)
			splash.finished.connect(func() -> void:
				splash.queue_free()
				_start_game(has_display), CONNECT_ONE_SHOT)
			splash.play()
			print("[Boot] splash")
			return
	_start_game(has_display)


## Everything after the splash: the menu, the connect screen (or connecting), the lobby.
func _start_game(has_display: bool) -> void:
	# What the game tells the player briefly (lost connection, a name taken): in every game scene,
	# outside the HUD, so a genre's own HUD keeps them (DECISIONS #202).
	if has_display:
		var notices := Notices.new()
		notices.name = "Notices"
		add_child(notices)
	# Items on the ground, shown and walked over (DECISIONS #269): every game, outside the HUD.
	if has_display:
		add_child(GroundItems.new())
	# Chat (DECISIONS #273): every game, outside the HUD.
	if has_display:
		var chat := ChatBox.new()
		chat.name = "Chat"
		add_child(chat)
	# An editor run starts the world's referee if the game needs one and it is not running
	# (DECISIONS #226): pressing Play is all a designer does.
	if has_display:
		var referee := RefereeLauncher.new()
		referee.name = "RefereeLauncher"
		add_child(referee)
	if pause_menu != null:
		_menu = pause_menu.instantiate() as PauseMenu
		add_child(_menu)
	if connect_screen != null and (has_display or _flag_connect_screen):
		_screen = connect_screen.instantiate() as ConnectScreen
		if _flag_connect_timeout > 0.0:
			_screen.first_connect_timeout_sec = _flag_connect_timeout
		add_child(_screen)
		_screen.connect_requested.connect(_on_connect_requested)
		_screen.open(net_config.host, _player_name, ConnectSettings.auto_connect())
	if _menu != null:
		_menu.can_disconnect = _screen != null
	_add_character_pickers(has_display or _flag_connect_screen)
	if lobby_panel:
		_lobby = LobbyPanel.new()
		add_child(_lobby)
	if lobby_screen:
		_add_lobby_screen(has_display or _flag_lobby_screen)
	if _screen == null:
		_connect()
		return
	var greet: bool = ConnectScreen.should_greet(has_display, _flag_connect_screen,
		_flag_autoconnect, not _flag_host.is_empty(), ConnectSettings.auto_connect())
	print("[Boot] connect screen: ", "waiting for the player" if greet else "connecting for them")
	if not greet:
		# Through the screen's own Connect, so a remembered address that has stopped answering
		# is timed out and explained rather than retried for ever behind a hidden form.
		_suppress_save = not _flag_host.is_empty() or _flag_name_given
		_screen.submit()
		_suppress_save = false


func _on_connect_requested(host: String, player_name: String, auto_connect: bool) -> void:
	net_config.host = host
	_player_name = player_name
	if not _suppress_save:
		ConnectSettings.save(host, player_name, auto_connect)
	print("[Boot] server: ", host)
	_connect()


func _connect() -> void:
	SpaceTimeSync.connect_to_server(net_config)


## The identity tag the token path was chosen by: "" for the default identity, "dev2" for editor
## slot 2, the `--token=` tag otherwise. ConnectSettings keys its profile on it.
func _identity_tag() -> String:
	var base: String = net_config.token_path.get_file().get_basename()
	const PREFIX: String = "spacetime_token_"
	return base.substr(PREFIX.length()) if base.begins_with(PREFIX) else ""


## Tell the server what to call us, once it knows who we are. Sent on every connect rather than
## only when it changes: the reducer is idempotent, and a client that only sent it once would
## lose its name against a freshly published module.
func _announce_name() -> void:
	if _player_name.is_empty():
		return
	var req: ReducerRequest = SpaceTimeSync.call_reducer(
		&"set_player_name", [_player_name], ["string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if not r.is_ok():
			push_warning("[Boot] the server would not take the name '%s': %s"
				% [_player_name, r.error_message])
			# Said to the player too: a name another player holds is refused (DECISIONS #202).
			SignalBus.notification_requested.emit("The server would not take the name '%s': %s. Escape, Disconnect, and choose another."
				% [_player_name, r.error_message.trim_prefix("set_player_name: ")], 1))


## The genres' definitions, tables and scenes (DECISIONS #173). The scenes go under this scene's
## root, deferred: the root is still adding its own children while this runs. A genre scene whose
## root has the name of one of the game scene's own children REPLACES it (DECISIONS #197): the
## greybox game's `HUD` is the foundation's, and a genre's `HUD` takes its place.
func _load_genres() -> void:
	genres = Genres.modules()
	for d: EntityDefinition in Genres.definitions(genres):
		if not entity_definitions.has(d):
			entity_definitions.append(d)
	Genres.merge_tables(net_config, genres)
	var root: Node = get_parent() if get_parent() != null else self
	for m: GenreModule in genres:
		for scene: PackedScene in m.scenes:
			if scene != null:
				_add_genre_scene.call_deferred(root, scene.instantiate())
	print("[Boot] genres: ", ", ".join(Genres.listed()))


func _add_genre_scene(root: Node, node: Node) -> void:
	var existing: Node = root.get_node_or_null(NodePath(String(node.name)))
	if existing != null:
		root.remove_child(existing)
		existing.queue_free()
	root.add_child(node)


## The player's look, chosen in the picker (DECISIONS #166). Like the name: sent on every connect,
## idempotent at the server, and refused words are surfaced rather than swallowed.
func _announce_appearance() -> void:
	if _appearance.is_empty() or not Appearance.is_valid(_appearance):
		return
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"set_appearance", [_appearance], ["string"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if not r.is_ok():
			push_warning("[Boot] the server would not take the look '%s': %s" % [_appearance, r.error_message]))


## The player's definition: the one for kind 0.
func player_definition() -> EntityDefinition:
	for defn: EntityDefinition in entity_definitions:
		if defn != null and defn.kind == 0:
			return defn
	return null


## A picker on the connect screen and one in the Escape menu, when there are looks to pick from.
func _add_character_pickers(has_display: bool) -> void:
	var defn: EntityDefinition = player_definition()
	if not character_picker or not has_display or defn == null or defn.variant_names().size() < 2:
		return
	if _screen != null:
		_screen.character_page = _make_picker(defn)
	if _menu != null:
		var picker: CharacterPicker = _make_picker(defn)
		_menu.add_child(picker)   # the menu's from now on, hidden until opened
		var button: Button = _menu.add_button("Character")
		button.pressed.connect(func() -> void:
			picker.appearance = _current_look(defn)
			_menu.open_page(picker))


## The lobby screen (DECISIONS #182), with its own character picker when there are looks to pick.
func _add_lobby_screen(show: bool) -> void:
	_lobby_screen = LobbyScreen.new()
	_lobby_screen.enabled = show
	# A harness that connects for the player goes straight into a match already under way.
	_lobby_screen.auto_join = _flag_autoconnect or not _flag_host.is_empty()
	add_child(_lobby_screen)
	var defn: EntityDefinition = player_definition()
	if not character_picker or not show or defn == null or defn.variant_names().size() < 2:
		return
	var picker: CharacterPicker = _make_picker(defn)
	_lobby_screen.add_child(picker)   # drawn over the lobby, hidden until opened
	_lobby_screen.character_page = picker
	_lobby_screen.character_requested.connect(func() -> void:
		picker.appearance = _current_look(defn)
		picker.open())


## The look to open a picker on: the one chosen, else the one this player wears now (picked from
## their entity id), so the picker never opens on somebody else's.
func _current_look(defn: EntityDefinition) -> String:
	if not _appearance.is_empty() or EntityRegistry.local_entity_id < 0:
		return _appearance
	return defn.look_worn(EntityRegistry.local_entity_id)


## The lobby screen, or null (tests).
func lobby_screen_node() -> LobbyScreen:
	return _lobby_screen


func _make_picker(defn: EntityDefinition) -> CharacterPicker:
	var picker := CharacterPicker.new()
	picker.definition = defn
	picker.appearance = _appearance
	picker.chosen.connect(_on_look_chosen)
	return picker


func _on_look_chosen(text: String) -> void:
	_appearance = text
	ConnectSettings.save_appearance(text)
	print("[Boot] look: ", text)
	if SpaceTimeSync.is_connected_to_server() and EntityRegistry.local_entity_id >= 0:
		_announce_appearance()


## How many editor instances can be handed an automatic identity before we give up.
const DEV_IDENTITY_SLOTS: int = 8


## Per-instance overrides. Read both from after `--` (`OS.get_cmdline_user_args()`, what
## `play_local.sh` passes) and from the raw command line, because the editor's
## Debug ▸ Customize Run Instances dialog appends its per-instance arguments without a `--`.
##
##   --host=<url>      the server to connect to, e.g. http://192.168.1.20:3000, for this run
##                     only. Without one, whatever the player last connected to, else the
##                     NetConfig's own host. Skips the connect screen's greeting.
##   --name=<name>     display name for this run, sent once connected and shown on other
##                     players' screens. Not remembered: the connect screen is what remembers.
##   --connect-screen  show the connect screen even headless or with auto-connect on (tests).
##   --autoconnect     skip the greeting and connect with the saved settings.
##   --connect-timeout=<s>  how long the connect screen waits before giving up (tests).
##   --no-splash       skip the splash screen (it is skipped anyway with --autoconnect or --host).
##   --lobby-screen    show the lobby screen even headless (tests).
##   --token=<name>    use a separate identity file. TWO CLIENTS ON ONE MACHINE MUST NOT SHARE
##                     ONE: the server keys entities by identity, so they would be handed the
##                     same entity and look like a single player. Absent, and running from the
##                     editor, a free slot is claimed automatically — see _claim_dev_identity.
##   --character=<res path>  play as this character (an EntityDefinition): it replaces the scene's
##                     definition of the same kind, for this run. The character workbench's way to
##                     play what is on it; the movement playtest's way to play a movement profile.
##   --movement=<res path>  the player's character moves by this movement profile, for this run (the
##                     movement workbench's Play as this).
##   --first-person    swap the camera rig, to show that the view is a resource swap.
##   --third-person
##   --latency=<ms>    TESTING: add this much round trip (half each way) to all traffic.
##   --jitter=<ms>     TESTING: plus up to this much random delay per direction.
func _apply_cli_overrides() -> void:
	var explicit_identity: bool = false
	var movement: String = ""
	for arg: String in _cli_args():
		if arg.begins_with("--host="):
			var raw: String = arg.substr("--host=".length())
			_flag_host = ConnectSettings.normalize_host(raw)
			if _flag_host.is_empty():
				push_warning("[Boot] --host=%s is not a server address; ignoring it" % raw)
		elif arg.begins_with("--name="):
			_flag_name = arg.substr("--name=".length()).strip_edges()
			_flag_name_given = true
		elif arg == "--connect-screen":
			_flag_connect_screen = true
		elif arg == "--autoconnect":
			_flag_autoconnect = true
		elif arg.begins_with("--connect-timeout="):
			_flag_connect_timeout = float(arg.substr("--connect-timeout=".length()))
		elif arg == "--no-splash":
			_flag_no_splash = true
		elif arg == "--lobby-screen":
			_flag_lobby_screen = true
		elif arg.begins_with("--token="):
			var tag: String = arg.substr("--token=".length())
			net_config.token_path = "user://spacetime_token_%s.txt" % tag
			explicit_identity = true
			print("[Boot] identity file: ", net_config.token_path)
		elif arg.begins_with("--character="):
			_use_character(arg.substr("--character=".length()))
		elif arg.begins_with("--movement="):
			movement = arg.substr("--movement=".length())
		elif arg == "--first-person" or arg == "--third-person":
			_set_camera_rig("first_person" if arg == "--first-person" else "third_person")
		elif arg.begins_with("--latency="):
			net_config.sim_latency_ms = int(arg.substr("--latency=".length()))
			print("[Boot] simulated latency: %d ms round trip" % net_config.sim_latency_ms)
		elif arg.begins_with("--jitter="):
			net_config.sim_jitter_ms = int(arg.substr("--jitter=".length()))
			print("[Boot] simulated jitter: up to %d ms each way" % net_config.sim_jitter_ms)
	if not movement.is_empty():
		_use_movement(movement)
	if not explicit_identity and OS.has_feature("editor"):
		_claim_dev_identity()


## Play as `path`'s character this run: it takes the place of the scene's definition of its kind.
func _use_character(path: String) -> void:
	var def: EntityDefinition = load(path) as EntityDefinition if ResourceLoader.exists(path) else null
	if def == null:
		push_warning("[Boot] --character=%s is not a character (an EntityDefinition); ignoring it" % path)
		return
	for i: int in entity_definitions.size():
		if entity_definitions[i] != null and entity_definitions[i].kind == def.kind:
			entity_definitions[i] = def
			print("[Boot] playing as %s (%s)" % [def.display_name, path])
			return
	entity_definitions.append(def)
	print("[Boot] playing as %s (%s)" % [def.display_name, path])


## PLAY AS A MOVEMENT PROFILE (the movement workbench's Play as this, DECISIONS #207): the player's
## character (kind 0) moves by the profile at `path` this run. Applied after the arguments, so it
## also holds for a `--character=` given with it.
func _use_movement(path: String) -> void:
	var profile: MovementProfileDef = load(path) as MovementProfileDef if ResourceLoader.exists(path) else null
	if profile == null:
		push_warning("[Boot] --movement=%s is not a movement profile; ignoring it" % path)
		return
	for i: int in entity_definitions.size():
		var d: EntityDefinition = entity_definitions[i]
		if d != null and d.kind == 0:
			var moved: EntityDefinition = d.duplicate() as EntityDefinition
			moved.movement_profile = profile
			entity_definitions[i] = moved
			print("[Boot] moving by %s (%s)" % [profile.display_name, path])
			return
	push_warning("[Boot] --movement: there is no player character (kind 0) to move by it")


## The editor's per-instance arguments arrive on the raw command line; the launch scripts pass
## theirs after `--`. Scan both rather than making the caller know which launcher they used.
func _cli_args() -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	return args


## Give every editor instance its own identity, so pressing Play twice produces two players
## rather than two windows fighting over one entity. Editor-only: an exported build keeps the
## single persisted identity, which is what a shipped game wants.
##
## A slot is claimed by binding a loopback port, which is a real cross-process mutex: the OS
## refuses the second bind, and releases the port the instant the holder dies — so a crashed
## instance frees its slot with no stale lock to clean up, and an instance paused on a breakpoint
## keeps its claim. A lock FILE cannot do this. The first attempt here used one, with
## `OS.is_process_running` to spot dead holders, and tests/multiclient_test.sh caught it
## immediately: on Windows that call only knows processes Godot itself launched, so every
## instance read the other's lock as dead and they all claimed slot 1.
##
## The listener is never connected to; binding it IS the claim. It is held in a static so it
## outlives this node — freeing the Boot node on a scene change would otherwise release the port
## while the connection it guards is still live.
static var _identity_lock: TCPServer = null

## Slot N binds IDENTITY_LOCK_PORT + N, on loopback only (a loopback-bound listener does not
## raise a Windows Firewall prompt).
const IDENTITY_LOCK_PORT: int = 47820


func _claim_dev_identity() -> void:
	if net_config.token_path != NetConfig.new().token_path:
		return   # something already chose an identity file; don't second-guess it
	var lock := TCPServer.new()
	for slot: int in range(1, DEV_IDENTITY_SLOTS + 1):
		if lock.listen(IDENTITY_LOCK_PORT + slot, "127.0.0.1") != OK:
			continue   # held by another instance, or the port belongs to something else
		_identity_lock = lock
		net_config.token_path = "user://spacetime_token_dev%d.txt" % slot
		print("[Boot] editor instance: dev identity slot ", slot, " (", net_config.token_path, ")")
		return
	push_warning("[Boot] all %d dev identity slots are held; falling back to the shared identity, so this instance will collide with another one" % DEV_IDENTITY_SLOTS)


## Swap every definition's camera rig. The definitions are shared .tres resources, so each one is
## duplicated first: mutating them in place would leak this instance's view choice into every
## other holder of that resource (and, in the editor, mark it dirty).
func _set_camera_rig(preset: String) -> void:
	var rig: CameraRigConfig = load("res://foundation/camera/%s.tres" % preset) as CameraRigConfig
	if rig == null:
		push_warning("[Boot] unknown camera rig preset '%s'" % preset)
		return
	for i: int in range(entity_definitions.size()):
		var defn: EntityDefinition = entity_definitions[i]
		if defn == null:
			continue
		var copy: EntityDefinition = defn.duplicate() as EntityDefinition
		copy.camera_rig = rig
		entity_definitions[i] = copy
	print("[Boot] camera: ", preset)


## Say whether this client is looking through anything. A client with no current camera renders
## nothing at all, and the HUD is a CanvasLayer so it keeps drawing over the void — the symptom
## is a grey screen with a working UI and no error. Deferred by one call so the entity has
## finished binding, which is where the camera is switched on.
func _report_view() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		push_error("[Boot] no camera is current — this client is rendering nothing")
		return
	print("[Boot] view: looking through ", cam.get_path())
