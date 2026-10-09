class_name PauseMenu extends CanvasLayer
## Escape. The world does not stop — this is multiplayer, and the other players are still
## playing — so this is a menu over a running game, shown while the player has taken the cursor
## back with Escape and gone as soon as they click back into the world.
##
## It reads `MouseCapture` rather than tracking Escape itself: MouseCapture already decides who
## has the cursor (DECISIONS #89), and a second opinion about whether the game is "paused" is how
## a menu ends up open over a captured cursor, or closed over a free one. Its buttons can be
## clicked at all only because MouseCapture leaves a click on UI to the UI.
##
## Disconnect ends the session through the adapter. What happens next is the connect screen's
## business — it comes back by itself on DISCONNECTED — so this menu knows nothing about it.
##
## FULLSCREEN is here too (WindowMode): the button, and F11 or Alt+Enter at any time — this menu
## is in every scene that has a game in it, open or not. Where the window is not the game's to
## change (the editor's game view), the button is greyed and the menu says what to do instead.
##
## SETTINGS opens the settings screen (`SettingsPanel`, DECISIONS #165) in place of the menu, and
## OPEN LOG FOLDER shows this game's log file, the thing to send when something broke on a
## friend's machine. A genre adds its own buttons with `add_button` (fishing's journal).

## False hides Disconnect: a scene with no connect screen would leave the player in a void.
var can_disconnect: bool = true

@onready var _resume: Button = %Resume
@onready var _fullscreen: Button = %Fullscreen
@onready var _settings: Button = %Settings
@onready var _logs: Button = %Logs
@onready var _disconnect: Button = %Disconnect
@onready var _quit: Button = %Quit
@onready var _info: Label = %Info
@onready var _box: Control = $Center

var _panel: SettingsPanel = null
## What a genre's button opens in place of the menu (a CanvasItem with a `closed` signal), if open.
var _open_page: Control = null


## The menu's group: a genre finds the menu here to add its own buttons and pages.
const GROUP: StringName = &"pause_menu"

var _rules: RulesPanel = null
var _rules_button: Button = null


func _ready() -> void:
	visible = false
	add_to_group(GROUP)
	_resume.pressed.connect(_on_resume)
	_fullscreen.pressed.connect(toggle_fullscreen)
	_settings.pressed.connect(open_settings)
	_logs.pressed.connect(func() -> void: open_log_folder())
	_disconnect.pressed.connect(_on_disconnect)
	_quit.pressed.connect(func() -> void: AppExit.quit(get_tree()))
	_panel = SettingsPanel.new()
	add_child(_panel)
	_panel.closed.connect(_show_menu)
	# The hot rules page (DECISIONS #201): its button is shown to the admin only (`Roles`); the
	# server refuses anyone else's change regardless.
	_rules = RulesPanel.new()
	add_child(_rules)   # in the tree from the start (hidden), so it is freed with the menu
	_rules_button = add_button("Rules (admin)", "Rules")
	_rules_button.pressed.connect(func() -> void: open_page(_rules))
	_rules_button.visible = false


## The settings screen, in place of the menu.
func open_settings() -> void:
	open_page(_panel)


## Show `page` in place of the menu until it emits `closed` (a genre's own page: the journal).
## The page is added to this menu if it has no parent yet.
func open_page(page: Control) -> void:
	if page.get_parent() == null:
		add_child(page)
	if not page.is_connected(&"closed", _show_menu):
		page.connect(&"closed", _show_menu)
	_open_page = page
	_box.visible = false
	if page.has_method(&"open"):
		page.call(&"open")
	else:
		page.visible = true


## The menu in this scene, or null.
static func find(tree: SceneTree) -> PauseMenu:
	return tree.get_first_node_in_group(GROUP) as PauseMenu if tree != null else null


## Free the cursor (the menu comes up, as Escape would) and show `page` in it: a genre's key for its
## own page, like the journal's J.
func show_page(page: Control) -> void:
	MouseCapture.release()
	open_page(page)


## Add a button to the menu, above Disconnect; returns it so the genre can connect it.
func add_button(text: String, button_name: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.name = button_name if not button_name.is_empty() else text.validate_node_name()
	b.custom_minimum_size = Vector2(0, 36)
	_disconnect.get_parent().add_child(b)
	_disconnect.get_parent().move_child(b, _disconnect.get_index())
	return b


func rules_panel() -> RulesPanel:
	return _rules


func settings_panel() -> SettingsPanel:
	return _panel


func is_page_open() -> bool:
	return _open_page != null


func _show_menu() -> void:
	_open_page = null
	_box.visible = true
	_rules_button.visible = Roles.is_local_admin()
	if visible:
		_resume.grab_focus()


## Where this game writes its log: user://logs/godot.log (Godot's file logging, on by default on
## desktop). Shown in the file manager with the file selected; the folder itself when there is no
## log yet. Returns the path shown.
static func open_log_folder() -> String:
	var log_file: String = ProjectSettings.globalize_path("user://logs/godot.log")
	var target: String = log_file if FileAccess.file_exists("user://logs/godot.log") \
		else ProjectSettings.globalize_path("user://")
	if DisplayServer.get_name() != "headless":
		OS.shell_show_in_file_manager(target)
	return target


## Whether the menu belongs on screen right now. Static so tests ask the same question.
static func should_show() -> bool:
	if not (MouseCapture.is_wanted() and MouseCapture.released_by_player()):
		return false
	return SpaceTimeSync.state == SpaceTimeSync.ConnectionState.CONNECTED \
		or SpaceTimeSync.state == SpaceTimeSync.ConnectionState.RECONNECTING


func _process(_delta: float) -> void:
	var want: bool = should_show()
	if want == visible:
		return
	visible = want
	if want:
		_disconnect.visible = can_disconnect
		_rules_button.visible = Roles.is_local_admin()
		_refresh_fullscreen()
		_info.text = _describe()
		if _open_page == null:
			_resume.grab_focus()
	else:
		_close_page()
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus != null and is_ancestor_of(focus):
			focus.release_focus()


func _close_page() -> void:
	if _open_page == null:
		return
	var page: Control = _open_page
	if page.has_method(&"close"):
		page.call(&"close")
	else:
		page.visible = false
	_show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if WindowMode.is_toggle_key(event):
		get_viewport().set_input_as_handled()
		toggle_fullscreen()
		return
	# Escape again closes it. MouseCapture only acts on Escape while it HAS the cursor, so the
	# second press arrives here rather than there. With a page open, Escape is the page's (it goes
	# back to the menu).
	if visible and _open_page == null and event.is_action_pressed(MouseCapture.RELEASE_ACTION):
		get_viewport().set_input_as_handled()
		_on_resume()


## Fullscreen, or back to a window — or, where that is not the game's to do, why not (the Output
## panel shows it when the menu is closed).
func toggle_fullscreen() -> void:
	var why: String = WindowMode.toggle()
	if not why.is_empty():
		push_warning("Fullscreen: " + why)
	else:
		Settings.set_value(&"fullscreen", WindowMode.is_fullscreen())   # remembered (#165)
	_refresh_fullscreen()


func _refresh_fullscreen() -> void:
	var why: String = WindowMode.cannot()
	_fullscreen.disabled = not why.is_empty()
	_fullscreen.tooltip_text = why
	_fullscreen.text = "Leave fullscreen  (F11)" if WindowMode.is_fullscreen() else "Fullscreen  (F11)"


func _on_resume() -> void:
	MouseCapture.recapture()


func _on_disconnect() -> void:
	SpaceTimeSync.disconnect_from_server("left the game")


func _describe() -> String:
	var host: String = SpaceTimeSync.config.host if SpaceTimeSync.config != null else "?"
	var who: String = ConnectSettings.player_name()
	var line: String = "Connected to %s" % host
	if not who.is_empty():
		line += " as %s" % who
	var rtt_ms: int = roundi(ClockSync.rtt_usec() / 1000.0)
	if rtt_ms > 0:
		line += "  ·  %d ms" % rtt_ms
	if Engine.is_embedded_in_editor():
		line += "\n" + WindowMode.IN_EDITOR
	return line
