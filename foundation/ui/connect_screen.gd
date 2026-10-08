class_name ConnectScreen extends CanvasLayer
## The front door: where a player says which server and what to be called, and where they land
## again when a session ends.
##
## It owns ONLY the conversation with the player. Boot owns the NetConfig and makes the
## connection (`connect_requested`); the adapter owns the socket. The screen watches the
## adapter's state to know what to say, and calls `disconnect_from_server` for the two ways a
## player can ask to stop: Cancel while connecting, and an attempt that never got an answer.
##
## It comes back by itself whenever a session ends — whoever ended it — so a dropped game lands
## on a form that says what happened, with the address still filled in, rather than on a frozen
## world. Foundation UI rather than genre UI: every game needs a way in.

## The player pressed Connect with an address that parsed. `host` is already normalised
## (`ConnectSettings.normalize_host`).
signal connect_requested(host: String, player_name: String, auto_connect: bool)

## An attempt that has not reached the world after this long is given up on and explained. The
## SDK retries for ever (`NetConfig.max_reconnect_attempts = 0`), which is right for a game that
## dropped and wrong for a mistyped address: the player would watch "connecting…" indefinitely.
@export var first_connect_timeout_sec: float = 10.0
## Shown above the form. Empty means the project's own name.
@export var title: String = ""

enum Mode { HIDDEN, FORM, CONNECTING }

@onready var _title: Label = %Title
@onready var _host: LineEdit = %Host
@onready var _name: LineEdit = %Name
## A switch rather than a box: the default theme draws an unchecked box dark on a dark panel.
@onready var _auto: BaseButton = %AutoConnect
@onready var _connect: Button = %Connect
@onready var _quit: Button = %Quit
@onready var _status: Label = %Status
@onready var _settings: Button = %Settings
## Opens the character picker (`character_page`), hidden when there is none.
@onready var _character: Button = %Character
@onready var _center: Control = $Center

## What Character opens in place of the form: a Control with `open()` and a `closed` signal (boot
## hands in the character picker, DECISIONS #166). Null hides the button.
var character_page: Control = null:
	set(v):
		character_page = v
		# The screen's from now on (hidden until opened), so it goes when the screen does.
		if v != null and v.get_parent() == null:
			add_child(v)
		if is_node_ready():
			_character.visible = v != null
var _panel: SettingsPanel = null
var _page: Control = null

var _mode: Mode = Mode.HIDDEN
## The address being tried, normalised.
var _target: String = ""
var _elapsed: float = 0.0
## The SDK's own words for the latest failure of this attempt, if it gave any.
var _last_error: String = ""
## Set when the screen ended the attempt itself, so the DISCONNECTED that follows is explained
## in the screen's words rather than as a lost connection.
var _pending_message: String = ""
var _pending_is_error: bool = false
## A session reached its world since the form was last shown. The difference between "the game
## dropped" and "the attempt never got anywhere".
var _was_playing: bool = false


func _ready() -> void:
	visible = false
	_title.text = title if not title.is_empty() \
		else String(ProjectSettings.get_setting("application/config/name", "Multiplayer"))
	_connect.pressed.connect(_on_connect_pressed)
	_quit.pressed.connect(func() -> void: AppExit.quit(get_tree()))
	# Enter in either field is Connect: the common case is "the address is already right".
	_host.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	_name.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	# Ticking the box is a decision in its own right; it should not need a connect to stick.
	_auto.toggled.connect(func(on: bool) -> void: ConnectSettings.save_auto_connect(on))
	# Settings and the character before connecting, in place of the form (DECISIONS #165, #166).
	_panel = SettingsPanel.new()
	add_child(_panel)
	_settings.pressed.connect(func() -> void: _open_page(_panel))
	_character.visible = character_page != null
	_character.pressed.connect(func() -> void:
		if character_page != null:
			character_page.set(&"appearance", ConnectSettings.appearance())
			_open_page(character_page))
	SpaceTimeSync.connection_state_changed.connect(_on_state)
	SpaceTimeSync.connection_error.connect(_on_connection_error)
	SignalBus.world_ready.connect(_on_world_ready)


# --- API -------------------------------------------------------------------------------

## Does the screen greet the player at launch, or connect for them? Pure, so the rule is tested
## as a table rather than by launching windows.
##
##   forced          `--connect-screen`: always greet (the test that drives the screen)
##   no display      nobody to ask: connect (every headless harness, the sidecar)
##   a flag / auto   `--autoconnect`, `--host=`, or the player ticked "connect automatically"
static func should_greet(has_display: bool, forced: bool, autoconnect_flag: bool,
		host_flag: bool, saved_auto: bool) -> bool:
	if forced:
		return true
	if not has_display:
		return false
	return not (autoconnect_flag or host_flag or saved_auto)


## Show the form, filled in. `message` explains why it is showing, if anything needs saying.
func open(host: String, player_name: String, auto_connect: bool, message: String = "",
		is_error: bool = false) -> void:
	_host.text = host
	_name.text = player_name
	_auto.set_pressed_no_signal(auto_connect)
	_show_form(message, is_error)


## Press Connect on the player's behalf: auto-connect, and `--host=` launches with a screen.
## Going through the button's own path is the point — a remembered address that has stopped
## answering gets the same timeout and the same explanation as a freshly mistyped one, instead
## of an endless "connecting" with the form out of reach.
func submit() -> void:
	if _mode == Mode.FORM:
		_on_connect_pressed()


func is_open() -> bool:
	return _mode != Mode.HIDDEN


func is_connecting() -> bool:
	return _mode == Mode.CONNECTING


func status_text() -> String:
	return _status.text


func settings_panel() -> SettingsPanel:
	return _panel


## A page (settings, the character) shown in place of the form until it closes.
func _open_page(page: Control) -> void:
	if page.get_parent() == null:
		add_child(page)
	if not page.is_connected(&"closed", _close_page):
		page.connect(&"closed", _close_page)
	_page = page
	_center.visible = false
	page.call(&"open")


func _close_page() -> void:
	_page = null
	_center.visible = true
	if _mode == Mode.FORM:
		_connect.grab_focus()


# --- the form --------------------------------------------------------------------------

func _show_form(message: String, is_error: bool) -> void:
	_mode = Mode.FORM
	_was_playing = false
	visible = true
	_set_editable(true)
	_connect.text = "Connect"
	_set_status(message, is_error)
	# The next keypress should do the likely thing: fill in whatever is missing, else connect.
	if _host.text.strip_edges().is_empty():
		_type_in(_host)
	elif _name.text.strip_edges().is_empty():
		_type_in(_name)
	else:
		_connect.grab_focus()


## Focus a field AND start editing it. A LineEdit that merely has focus ignores typing, and one
## that has just submitted stops editing while keeping focus — so after a refused address the
## caret sat in the field and every key did nothing.
func _type_in(field: LineEdit) -> void:
	field.grab_focus()
	field.edit()


func _on_connect_pressed() -> void:
	if _mode == Mode.CONNECTING:
		_end_attempt("Cancelled.", false)
		return
	if _mode != Mode.FORM:
		return
	var host: String = ConnectSettings.normalize_host(_host.text)
	if host.is_empty():
		_set_status("\"%s\" is not a server address. Try 192.168.1.20, or http://host:3000."
			% _host.text.strip_edges(), true)
		_type_in(_host)
		return
	_host.text = host   # show the player what their address was understood as
	_mode = Mode.CONNECTING
	_target = host
	_elapsed = 0.0
	_last_error = ""
	_set_editable(false)
	_connect.text = "Cancel"
	_set_status("Connecting to %s…" % host, false)
	connect_requested.emit(host, _name.text.strip_edges(), _auto.button_pressed)


func _process(delta: float) -> void:
	if _mode != Mode.CONNECTING:
		return
	_elapsed += delta
	var joined: bool = SpaceTimeSync.state == SpaceTimeSync.ConnectionState.CONNECTED
	if _elapsed >= first_connect_timeout_sec:
		if joined:
			# The socket opened and the world never arrived: a different problem from no answer,
			# and one the player cannot fix by retyping the address.
			_end_attempt(("Connected to %s, but the world never loaded. The server may be "
				+ "running a different version of the game.") % _target, true)
		else:
			_end_attempt(("No answer from %s after %d s. Check the address; the host has to "
				+ "start the server with  spacetime start --listen-addr 0.0.0.0:3000  and let "
				+ "port 3000 through their firewall.") % [_target, int(first_connect_timeout_sec)]
				+ _error_suffix(), true)
		return
	if joined:
		_set_status("Connected. Joining the world…", false)
	else:
		_set_status("Connecting to %s…  %d s%s"
			% [_target, int(_elapsed), _error_suffix()], false)


func _error_suffix() -> String:
	return "" if _last_error.is_empty() else "\n(%s)" % _last_error


## Stop the attempt this screen started, and say why once the adapter reports it has stopped.
func _end_attempt(message: String, is_error: bool) -> void:
	_pending_message = message
	_pending_is_error = is_error
	SpaceTimeSync.disconnect_from_server(message)
	# Normally the adapter's DISCONNECTED has just shown the form. If it was already
	# disconnected (the SDK had nothing to close), nothing fired, so show it here.
	if _mode == Mode.CONNECTING:
		_show_pending()


func _show_pending() -> void:
	var msg: String = _pending_message
	var err: bool = _pending_is_error
	_pending_message = ""
	_pending_is_error = false
	_show_form(msg, err)


# --- the adapter -------------------------------------------------------------------------

func _on_state(state: SpaceTimeSync.ConnectionState) -> void:
	if state != SpaceTimeSync.ConnectionState.DISCONNECTED:
		return
	if not _pending_message.is_empty():
		_show_pending()
	elif not SpaceTimeSync.incompatible_reason.is_empty():
		# The server answered, and runs another version of the game (DECISIONS #164).
		_show_form(SpaceTimeSync.incompatible_reason, true)
	elif SpaceTimeSync.last_disconnect_requested:
		_show_form("Disconnected.", false)
	elif _was_playing:
		_show_form("Lost connection to %s." % _target_or_config(), true)
	else:
		_show_form("Could not connect to %s.%s" % [_target_or_config(), _error_suffix()], true)


func _on_connection_error(_code: int, reason: String) -> void:
	_last_error = reason


func _on_world_ready() -> void:
	# Reached from the form too: a game that connected on its own (auto-connect) still wants the
	# screen to know a session is live, so that a later drop is reported as one.
	_was_playing = true
	if _mode == Mode.HIDDEN:
		return
	_mode = Mode.HIDDEN
	if _page != null:
		_page.call(&"close")
	visible = false
	# Let go of keyboard focus, or the first E pressed in game types into a hidden field.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


func _target_or_config() -> String:
	if not _target.is_empty():
		return _target
	return SpaceTimeSync.config.host if SpaceTimeSync.config != null else "the server"


# --- presentation ------------------------------------------------------------------------

func _set_editable(on: bool) -> void:
	_host.editable = on
	_name.editable = on
	_auto.disabled = not on
	_character.disabled = not on
	_quit.disabled = false


func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.62, 0.45) if is_error else Color(0.85, 0.9, 0.95)
