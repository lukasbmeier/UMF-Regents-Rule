extends Node
## CONNECT PLAYTEST: can a person get into a game, out of it, and back in again?
##
## Every other harness launches headless and connects on its own, so none of them has ever seen
## the connect screen — and the screen is the first thing a friend meets, usually with a mistyped
## address or a host who forgot the firewall. This drives it the way a player would: typing into
## the real fields, pressing Enter and clicking the real buttons, against the live module.
##
##   greeting      the screen asks first; nothing connects until the player says where to
##   bad address   refused on the form, with the reason, and nothing is dialled
##   no answer     a port nobody listens on: the adapter reports the SDK's error, and the screen
##                 gives up after its timeout with the address in the explanation
##   other version the right server, running a schema this build was not generated from: refused
##                 before connecting, in words a player can act on (DECISIONS #164)
##   character     the connect screen's Character opens the picker; the look picked is remembered,
##                 reaches the server on connect, and the player is built wearing it; in the
##                 Escape menu another look rebuilds the player in it, the HUD and cursor intact
##                 (DECISIONS #166)
##   connect       a bare address gets SpacetimeDB's port; the world loads, the screen goes, the
##                 server learns the typed name, and the profile remembers both
##   Escape menu   Escape frees the cursor and opens the menu; Resume and Escape close it; a
##                 click on the world closes it too — and its buttons can be clicked at all
##   disconnect    the world is torn down, the cursor comes back, and the form returns filled in
##   back in       same process, same identity, same entity: a rename and auto-connect stick
##
## Driven by tests/connect_playtest.sh with `--connect-screen --token=connecttest`. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 150.0
const STEP_TIMEOUT_SEC: float = 25.0
## Nothing listens here. The harness passes a short `--connect-timeout` so the give-up is quick.
const DEAD_HOST: String = "127.0.0.1:3999"
## The harness runs a plain HTTP server here: an answer, from the wrong kind of server.
const WRONG_HOST: String = "127.0.0.1:3998"

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false

var _screen: ConnectScreen = null
var _menu: PauseMenu = null
var _hud: Control = null
var _errors_seen: Array[String] = []
var _first_entity: int = -1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	print("== connect playtest ==")
	SpaceTimeSync.connection_error.connect(func(_c: int, why: String) -> void:
		_errors_seen.append(why))
	if not await _step_greeting():
		_finish()
		return
	await _step_bad_address()
	await _step_no_answer()
	await _step_wrong_server()
	await _step_other_version()
	await _step_pick_character()
	# Two failed attempts on a FRESH INSTALL (no saved identity yet) before the right address:
	# this ordering is what exposed the SDK's stale identity request (_sdk_reset_token_fetch).
	if not await _step_connect():
		_finish()
		return
	await _step_look_arrived()
	await _step_lobby_screen()
	await _step_menu()
	await _step_menu_character()
	if not await _step_disconnect():
		_finish()
		return
	await _step_back_in()
	_finish()


# --- steps -----------------------------------------------------------------------------

func _step_greeting() -> bool:
	print("-- the greeting --")
	_screen = get_parent().get_node_or_null(^"Game/Boot/ConnectScreen") as ConnectScreen
	_menu = get_parent().get_node_or_null(^"Game/Boot/PauseMenu") as PauseMenu
	_hud = get_parent().get_node_or_null(^"Game/HUD") as Control
	_check(_screen != null, "boot built the connect screen from the scene's export")
	_check(_menu != null, "and the Escape menu")
	if _screen == null or _menu == null:
		return false
	await _frames(60)
	_check(_screen.is_open() and _screen.visible, "the screen greets the player")
	_check(SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED,
		"and nothing connects until they say where to (state %s)" % _state_name())
	_check(EntitySpawner.spawned_count() == 0, "no world behind it yet")
	_check(_field(^"%Host").text == NetConfig.new().host,
		"a fresh install offers the shipped server (%s)" % _field(^"%Host").text)
	_check(_field(^"%Name").text.is_empty(), "and no name yet")
	_check(_hud_status() == "not connected", "the HUD agrees: \"%s\"" % _hud_status())
	return true


func _step_bad_address() -> void:
	print("-- a bad address --")
	await _type_into(_field(^"%Host"), "not an address!")
	await _press_enter()
	await _frames(5)
	_check(_screen.is_open() and not _screen.is_connecting(),
		"Enter on a bad address stays on the form")
	_check(_screen.status_text().contains("not a server address"),
		"and says why: \"%s\"" % _screen.status_text())
	_check(SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED,
		"nothing was dialled")


func _step_no_answer() -> void:
	print("-- nobody home --")
	_errors_seen.clear()
	# NO CLICK: the refusal put the caret back in the address field, so a player just retypes.
	# This is the step that found a LineEdit keeping focus but ignoring every key after Enter.
	var host_field: LineEdit = _field(^"%Host")
	_check(host_field.has_focus() and host_field.is_editing(),
		"after a refusal the address field is focused AND editing, ready to be retyped")
	await _type_into(host_field, DEAD_HOST, false)
	await _click(_button(^"%Connect"))
	await _frames(5)
	_check(_screen.is_connecting(), "Connect starts an attempt")
	_check(_screen.status_text().begins_with("Connecting to http://127.0.0.1:3999"),
		"at the address as understood: \"%s\"" % _screen.status_text())
	_check(not _field(^"%Host").editable, "and the fields are locked while it tries")
	var gave_up: bool = await _until(func() -> bool: return not _screen.is_connecting(),
		"the screen to give up on %s" % DEAD_HOST)
	_check(gave_up, "an address that never answers is given up on")
	print("   the screen said: %s" % _screen.status_text().replace("\n", " / "))
	_check(_screen.status_text().begins_with("No answer from http://127.0.0.1:3999"),
		"with the address in the explanation")
	_check(SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED,
		"the attempt is really over, not retrying behind the form (%s)" % _state_name())
	_check(_field(^"%Host").editable, "and the form can be used again")
	# Nothing should keep dialling a dead port once the player has been told it is dead.
	await _frames(120)
	_check(SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED,
		"two seconds later it is still not retrying (%s)" % _state_name())


## Something answers, but it is not SpacetimeDB — a friend typed the port of some other server.
## The harness runs a plain HTTP server there, which refuses the identity request at once. This
## is the case where the SDK has words of its own, and the player should see them.
func _step_wrong_server() -> void:
	print("-- the wrong kind of server --")
	_errors_seen.clear()
	await _type_into(_field(^"%Host"), WRONG_HOST)
	await _press_enter()
	var said: bool = await _until(func() -> bool: return not _errors_seen.is_empty(),
		"the SDK to report the refused identity request")
	_check(said, "the adapter passed the SDK's own error on (connection_error: %s)"
		% str(_errors_seen))
	await _frames(2)
	_check(_screen.is_connecting() and _screen.status_text().contains("(%s)" % _errors_seen[0])
		if said else false,
		"and the screen shows it while still trying: \"%s\""
		% _screen.status_text().replace("\n", " / "))
	var gave_up: bool = await _until(func() -> bool: return not _screen.is_connecting(),
		"the screen to give up on %s" % WRONG_HOST)
	_check(gave_up and _screen.status_text().contains("(%s)" % _errors_seen[0]) if said else false,
		"the final explanation keeps the SDK's words: \"%s\""
		% _screen.status_text().replace("\n", " / "))


## The right server, but this build's bindings came from another schema. The adapter asks the
## server for its schema first and refuses the difference, so nothing is decoded into the wrong
## columns. The build's own fingerprint is replaced for this one attempt.
func _step_other_version() -> void:
	print("-- another version of the game --")
	_errors_seen.clear()
	_check(not SpaceTimeSync.bindings_fingerprint().is_empty(),
		"this build knows which schema it was generated from (%s)" % SpaceTimeSync.bindings_fingerprint())
	SpaceTimeSync.fingerprint_override = "000000000000"
	await _type_into(_field(^"%Host"), "127.0.0.1")
	await _press_enter()
	var refused: bool = await _until(func() -> bool: return not _screen.is_connecting(),
		"the screen to report the other version")
	SpaceTimeSync.fingerprint_override = ""
	_check(refused and _screen.status_text().contains("different version of the game")
		and _screen.status_text().contains("000000000000")
		and _screen.status_text().contains(SpaceTimeSync.bindings_fingerprint()),
		"a server running another schema is refused, and the screen says why: \"%s\""
			% _screen.status_text().replace("\n", " / "))
	_check(SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED
		and EntitySpawner.spawned_count() == 0 and not SpaceTimeSync.is_world_ready,
		"and nothing connected: no world, no entity (%s)" % _state_name())
	_check(_field(^"%Host").editable, "the form can be used again")


## Before connecting: the connect screen's Character, the next look and a hair colour, Done.
var _picked_look: String = ""


func _step_pick_character() -> void:
	print("-- the character, before connecting --")
	var button: BaseButton = _button(^"%Character")
	_check(button != null and button.visible, "the connect screen offers Character")
	if button == null:
		return
	await _click(button)
	await _frames(2)
	var picker: CharacterPicker = _screen.character_page as CharacterPicker
	_check(picker != null and picker.is_open() and not (_screen.get_node(^"Center") as Control).visible,
		"it opens the character picker in place of the form")
	if picker == null:
		return
	var first: String = picker.current()
	await _click(picker.find_child("Next", true, false) as Control)
	var hair: OptionButton = picker.find_child("hair", true, false) as OptionButton
	if hair != null:
		hair.select(4)
		hair.item_selected.emit(4)
	_picked_look = picker.current()
	_check(_picked_look != first and _picked_look.contains("hair=4"),
		"> and a hair colour change the look (%s, was %s)" % [_picked_look, first])
	await _click(picker.find_child("Done", true, false) as Control)
	await _frames(2)
	_check(not picker.is_open() and (_screen.get_node(^"Center") as Control).visible,
		"Done goes back to the form")
	_check(_saved(&"appearance") == _picked_look, "and the look is remembered (%s)" % str(_saved(&"appearance")))


## After connecting: the server has the look, and the player is built wearing it.
func _step_look_arrived() -> void:
	print("-- the look reached everyone --")
	var arrived: bool = await _until(func() -> bool: return _server_look() == _picked_look,
		"the server to have the look")
	_check(arrived, "the server's appearance row is the look picked (%s)" % _server_look())
	var dressed: bool = await _until(func() -> bool:
		return _local() != null and _local().is_bound() and _model_name() == Appearance.look_name(_picked_look),
		"the player to wear it")
	_check(dressed, "and the player is wearing it (%s)" % _model_name())


## In the game: Escape, Character, the next look, Done. The player is rebuilt in it.
func _step_menu_character() -> void:
	print("-- the character, from the Escape menu --")
	var before: SpaceTimeEntity = _local()
	await _key(KEY_ESCAPE)
	await _frames(2)
	var button: BaseButton = _menu.find_child("Character", true, false) as BaseButton
	_check(_menu.visible and button != null, "the Escape menu offers Character")
	if button == null:
		return
	await _click(button)
	await _frames(2)
	var picker: CharacterPicker = null
	for c: Node in _menu.get_children():
		if c is CharacterPicker:
			picker = c as CharacterPicker
	_check(picker != null and picker.is_open() and picker.current() == _picked_look,
		"it opens on the look being worn (%s)" % (picker.current() if picker != null else "no picker"))
	if picker == null:
		return
	await _click(picker.find_child("Next", true, false) as Control)
	var next_look: String = picker.current()
	await _click(picker.find_child("Done", true, false) as Control)
	var rebuilt: bool = await _until(func() -> bool:
		return _local() != null and _local() != before and _local().is_bound() \
			and _model_name() == Appearance.look_name(next_look), "the player to be rebuilt in the new look")
	_check(rebuilt, "the player is rebuilt wearing the new look (%s, server says %s)" % [_model_name(), _server_look()])
	await _frames(5)
	var cam: Camera3D = get_viewport().get_camera_3d()
	_check(cam != null and _local() != null and _local().is_ancestor_of(cam),
		"and we look through the new player's camera")
	await _key(KEY_ESCAPE)
	await _frames(3)
	_check(not _menu.visible and MouseCapture.is_captured(), "Escape closes the menu, the cursor is the game's again")
	var hud_entity: SpaceTimeEntity = _hud.get(&"_entity") as SpaceTimeEntity
	_check(hud_entity != null and hud_entity == _local(), "the HUD follows the rebuilt player")
	_picked_look = next_look


func _server_look() -> String:
	var row: RefCounted = SpaceTimeSync.get_row(&"appearance", EntityRegistry.local_entity_id)
	return String(row.get(&"look")) if row != null else ""


func _model_name() -> String:
	var m: Node = _local().get_node_or_null(^"Visual/Model") if _local() != null else null
	return m.scene_file_path.get_file().get_basename() if m != null else ""


func _step_connect() -> bool:
	print("-- connect --")
	await _type_into(_field(^"%Host"), "127.0.0.1")
	await _type_into(_field(^"%Name"), "Tester One")
	await _press_enter()
	var ready: bool = await _until(func() -> bool:
		return SpaceTimeSync.is_world_ready and EntityRegistry.local_entity_id >= 0 \
			and _local() != null and _local().is_bound(), "the world and the local player")
	_check(ready, "Enter in the name field connects, and the local player spawns and binds")
	if not ready:
		return false
	_first_entity = EntityRegistry.local_entity_id
	_check(SpaceTimeSync.config.host == "http://127.0.0.1:3000",
		"a bare address was dialled on the server's default port (%s)" % SpaceTimeSync.config.host)
	await _frames(2)
	_check(not _screen.is_open() and not _screen.visible, "the screen gets out of the way")
	var focus: Control = get_viewport().gui_get_focus_owner()
	_check(focus == null,
		"and lets go of the keyboard, so E casts instead of typing into a hidden field (%s)" % (focus.get_path() if focus != null else "nothing"))
	var named: bool = await _until(func() -> bool: return _server_name() == "Tester One",
		"the server to learn the typed name")
	_check(named, "the server calls this player what they typed (\"%s\")" % _server_name())
	_check(_saved(&"host") == "http://127.0.0.1:3000" and _saved(&"name") == "Tester One"
		and _saved(&"auto_connect") == false,
		"and the profile remembers it for next time (%s)" % ConnectSettings.path())
	_check(not _hud_status().is_empty() and _hud_status() != "not connected",
		"the HUD found its player: \"%s\"" % _hud_status())
	return true


func _step_menu() -> void:
	print("-- the Escape menu --")
	_check(MouseCapture.is_wanted() and MouseCapture.is_captured(),
		"in the world, the game has the cursor")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(not MouseCapture.is_captured() and MouseCapture.released_by_player(),
		"Escape gives the cursor back")
	_check(_menu.visible, "and opens the menu")
	await _click(_button(^"%Resume", _menu))
	await _frames(2)
	_check(MouseCapture.is_captured() and not _menu.visible,
		"Resume is clickable with the cursor free, and closes it")

	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(_menu.visible, "Escape opens it again")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(MouseCapture.is_captured() and not _menu.visible, "and Escape closes it")

	await _key(KEY_ESCAPE)
	await _frames(2)
	_click_at(Vector2(24.0, 600.0))   # open floor: nothing but the world under it
	await _frames(2)
	_check(MouseCapture.is_captured() and not _menu.visible,
		"a click on the world, outside the menu, takes the cursor back and closes it")


func _step_disconnect() -> bool:
	print("-- disconnect --")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check(_menu.visible, "the menu is open")
	await _click(_button(^"%Disconnect", _menu))
	var down: bool = await _until(func() -> bool:
		return SpaceTimeSync.state == SpaceTimeSync.ConnectionState.DISCONNECTED \
			and EntitySpawner.spawned_count() == 0, "the world to be torn down")
	_check(down, "Disconnect ends the session and tears the world down (%d entities left)"
		% EntitySpawner.spawned_count())
	await _frames(2)
	_check(EntityRegistry.local_entity_id < 0, "nobody is the local player any more")
	_check(not MouseCapture.is_wanted() and not MouseCapture.is_captured(),
		"the cursor is handed back, so the form can be used")
	_check(not _menu.visible, "the menu goes with the session")
	_check(_screen.is_open() and _screen.status_text() == "Disconnected.",
		"the connect screen comes back and says what happened: \"%s\"" % _screen.status_text())
	_check(_field(^"%Host").text == "http://127.0.0.1:3000" and _field(^"%Name").text == "Tester One",
		"still filled in with where they were and who they were")
	_check(_hud_status() == "not connected", "the HUD let go of the old player: \"%s\""
		% _hud_status())
	return down


func _step_back_in() -> void:
	print("-- back in, same process --")
	await _type_into(_field(^"%Name"), "Tester Two")
	await _click(_button(^"%AutoConnect"))
	_check((_screen.get_node(^"%AutoConnect") as BaseButton).button_pressed,
		"the auto-connect box ticks")
	_check(_saved(&"auto_connect") == true and _saved(&"name") == "Tester One",
		"ticking it is remembered at once, and nothing else changes until Connect")
	await _click(_button(^"%Connect"))
	var ready: bool = await _until(func() -> bool:
		return SpaceTimeSync.is_world_ready and EntityRegistry.local_entity_id >= 0 \
			and _local() != null and _local().is_bound(), "the world again")
	_check(ready, "a second session in the same process reaches its world")
	if not ready:
		return
	_check(EntityRegistry.local_entity_id == _first_entity,
		"as the SAME entity: the identity survived the disconnect (%d, was %d)"
		% [EntityRegistry.local_entity_id, _first_entity])
	var renamed: bool = await _until(func() -> bool: return _server_name() == "Tester Two",
		"the rename")
	_check(renamed, "and the new name reached the server (\"%s\")" % _server_name())
	_check(_saved(&"name") == "Tester Two" and _saved(&"auto_connect") == true,
		"the profile now says auto-connect as Tester Two")
	# The match is under way now: the lobby screen offers Join rather than Ready (DECISIONS #182).
	var screen: LobbyScreen = _lobby_screen()
	var offered: bool = await _until(func() -> bool: return screen != null and screen.visible, "the lobby screen")
	var join: Button = screen.find_child("Join", true, false) as Button if screen != null else null
	_check(offered and join != null and join.visible and not (screen.find_child("Ready", true, false) as Button).visible,
		"back in while the match is under way, the lobby screen offers Join")
	if join != null:
		await _click(join)
	await _frames(10)
	_check(screen != null and not screen.visible, "and Join puts them in the game")
	_check(MouseCapture.is_wanted() and MouseCapture.is_captured(),
		"the new player has the cursor again")
	var hud_entity: SpaceTimeEntity = _hud.get(&"_entity") as SpaceTimeEntity
	_check(hud_entity != null and hud_entity == _local(),
		"the HUD latched onto the new player node, not the freed one")
	_check(EntitySpawner.spawned_count() > 1,
		"the rest of the world came back too (%d entities)" % EntitySpawner.spawned_count())


## THE LOBBY SCREEN (DECISIONS #182): a fresh publish is a match waiting for its players. Connected,
## the lobby screen stands us on its stage, holds us still and gives us the cursor; Choose character
## opens the picker over it; Ready, clicked as a player does, starts the match's first round (we are
## everyone here) and the screen goes. (R in the in-world lobby between rounds: the `lobby` suite.)
func _step_lobby_screen() -> void:
	print("-- the lobby screen --")
	var screen: LobbyScreen = _lobby_screen()
	var sess: SessionComponent = _local().find_component(SessionComponent) as SessionComponent if _local() != null else null
	var open: bool = await _until(func() -> bool: return screen != null and screen.visible, "the lobby screen")
	_check(open and sess != null and not sess.is_match_started(),
		"connected to a match waiting for its players, the lobby screen opens")
	if not open or sess == null:
		return
	await _frames(3)
	_check(screen.stage_models().has(EntityRegistry.local_entity_id), "we stand on its stage")
	var input: LocalInputComponent = _local().find_component(LocalInputComponent) as LocalInputComponent
	_check(input != null and input.is_held_still() and not MouseCapture.is_captured(),
		"held still behind it, with the cursor")
	var panel: LobbyPanel = null
	for n: Node in get_tree().root.find_children("*", "", true, false):
		if n is LobbyPanel:
			panel = n as LobbyPanel
	_check(panel != null and not panel.visible, "the in-world lobby panel keeps out of its way")
	await _click(screen.find_child("Character", true, false) as Control)
	await _frames(2)
	var picker: CharacterPicker = screen.character_page
	_check(picker != null and picker.is_open(), "Choose character opens the picker over it")
	if picker != null:
		await _click(picker.find_child("Cancel", true, false) as Control)
		await _frames(2)
		_check(not picker.is_open() and screen.visible, "and Cancel comes back to the lobby")
	await _click(screen.find_child("Ready", true, false) as Control)
	var started: bool = await _until(func() -> bool:
		return sess.get_phase() == SessionComponent.Phase.PLAYING and sess.is_match_started(), "the first round")
	_check(started, "Ready, with everyone here ready, starts the match's first round (%s)" % screen.said())
	await _frames(5)
	input = _local().find_component(LocalInputComponent) as LocalInputComponent
	_check(not screen.visible and input != null and not input.is_held_still(),
		"the screen goes and the player is free to move")
	_check(sess.get_match_round() == 1, "it is round 1 of the match (%d)" % sess.get_match_round())


func _lobby_screen() -> LobbyScreen:
	return get_parent().get_node_or_null(^"Game/Boot/LobbyScreen") as LobbyScreen


# --- input, as a player makes it ----------------------------------------------------------

## Click into the field (unless the screen already put the caret there), select everything, and
## type over it. Key events all the way.
func _type_into(field: LineEdit, text: String, click_first: bool = true) -> void:
	if click_first:
		await _click(field)
	await _frames(1)
	var sel := InputEventKey.new()
	sel.keycode = KEY_A
	sel.ctrl_pressed = true
	sel.pressed = true
	get_viewport().push_input(sel)
	for ch: String in text:
		var k := InputEventKey.new()
		k.pressed = true
		k.unicode = ch.unicode_at(0)
		k.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE
		get_viewport().push_input(k)
	await _frames(1)
	_check(field.text == text, "typed \"%s\" into %s (it reads \"%s\")" % [text, field.name, field.text])


func _press_enter() -> void:
	await _key(KEY_ENTER)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		get_viewport().push_input(k)
	await _frames(1)


## A real click at the control's centre. Headless has no hover tracking and a Button only takes
## a MOUSE press while hovered, so the notification a window would send as the pointer arrived
## is sent here; the press and release themselves go through the viewport like any other click.
func _click(control: Control) -> void:
	if control == null:
		_check(false, "the control to click exists")
		return
	control.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_click_at(control.get_global_rect().get_center())
	await _frames(1)


func _click_at(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move)
	for pressed: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = at
		b.global_position = at
		get_viewport().push_input(b)


# --- reading -------------------------------------------------------------------------------

func _field(path: NodePath) -> LineEdit:
	return _screen.get_node(path) as LineEdit


func _button(path: NodePath, owner_node: Node = null) -> BaseButton:
	var from: Node = owner_node if owner_node != null else _screen
	return from.get_node_or_null(path) as BaseButton


func _local() -> SpaceTimeEntity:
	return EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity


func _server_name() -> String:
	var row: RefCounted = SpaceTimeSync.get_row(&"player", SpaceTimeSync.local_identity)
	return String(row.get(&"name")) if row != null else ""


func _saved(key: StringName) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(ConnectSettings.path()) != OK:
		return null
	return cfg.get_value(ConnectSettings.SECTION, String(key), null)


func _hud_status() -> String:
	var l: Label = _hud.get_node_or_null(^"Status") as Label if _hud != null else null
	return l.text if l != null else ""


func _state_name() -> String:
	return SpaceTimeSync.ConnectionState.keys()[SpaceTimeSync.state]


# --- plumbing ------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().process_frame


func _until(pred: Callable, what: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	printerr("  TIMEOUT after %.0fs waiting for %s" % [STEP_TIMEOUT_SEC, what])
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: playtest exceeded %.0fs overall" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n%d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
