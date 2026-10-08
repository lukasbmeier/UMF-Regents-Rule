class_name LobbyScreen extends CanvasLayer
## THE LOBBY SCREEN (DECISIONS #182): where a player lands after connecting, before the game. Everyone
## in the session stands on a stage in the looks they chose, with their names and whether they are
## ready; the player picks their character (Choose character opens the character picker) and says
## they are ready. When the match's first round starts the screen goes and the game is there. A
## player who arrives in the middle of a match sees it too, with Join instead of Ready.
##
## Between rounds the in-world `LobbyPanel` takes over (it stays hidden while this is open). What
## starts a round is the server's (`session_match`, the lobby rules in `shared/rules.json`); this
## only shows the state and asks. While it is open the player is held still and has the cursor
## (`MouseCapture.hold_free`: not the player's release, so the Escape menu stays shut until Escape).
##
## Boot builds one (its `lobby_screen` flag) for a build with a window; a harness that connects for
## the player (`--autoconnect`) goes straight into a match already under way (`auto_join`).

## Choose character was pressed: Boot opens its character picker over this (`character_page`).
signal character_requested()

const GROUP: StringName = &"lobby_screen"
## How far apart the characters stand on the stage, metres.
const SPACING: float = 1.15
const STAGE_SIZE: Vector2i = Vector2i(960, 440)

## Whether to show at all (Boot: a window, or `--lobby-screen` for a headless test).
var enabled: bool = true
## Arriving in a match already under way, join it without being asked (a harness).
var auto_join: bool = false
## The character picker Boot opens from here, parented to this screen.
var character_page: CharacterPicker = null

var _root: Control = null
var _content: Control = null
var _title: Label = null
var _status: Label = null
var _said: Label = null
var _ready_button: Button = null
var _team_button: Button = null
var _join_button: Button = null
var _character_button: Button = null
var _viewport: SubViewport = null
var _stage: Node3D = null
var _camera: Camera3D = null
## Pressed Join, or was here when the match started: the game is theirs until a new match begins.
var _joined: bool = false
## Saw the match's lobby (so its start is ours to join, not a match to be asked about).
var _saw_lobby: bool = false
var _match_seen: int = -1
var _drawn: String = ""
var _holding: LocalInputComponent = null


func _init() -> void:
	name = "LobbyScreen"
	layer = 14


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	visible = false
	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		if s != SpaceTimeSync.ConnectionState.CONNECTED:
			_joined = false
			_saw_lobby = false
			_match_seen = -1)


## Gone while open (a scene change, a test): let go of the player and the cursor.
func _exit_tree() -> void:
	MouseCapture.hold_free(&"lobby_screen", false)
	_hold(false)


## The screen open in `tree`, or null (the in-world lobby panel stays out of its way).
static func showing(tree: SceneTree) -> LobbyScreen:
	if tree == null:
		return null
	var s: LobbyScreen = tree.get_first_node_in_group(GROUP) as LobbyScreen
	return s if s != null and s.visible else null


## Whether it belongs on screen now (tests read it).
func should_show() -> bool:
	var me: SessionComponent = _mine()
	if not enabled or me == null or not me.is_in_session() or _joined:
		return false
	return not me.is_match_started() or not auto_join


## Join the match under way: the screen goes (Join does this).
func join() -> void:
	_joined = true


## The members as the stage shows them (`LobbyPanel.members_of`).
func members() -> Array[Dictionary]:
	return LobbyPanel.members_of(_mine())


## The models on the stage, by entity id (tests).
func stage_models() -> Dictionary[int, Node3D]:
	var out: Dictionary[int, Node3D] = {}
	if _stage == null:
		return out
	for c: Node in _stage.get_children():
		if c.has_meta(&"entity_id"):
			out[int(c.get_meta(&"entity_id"))] = c as Node3D
	return out


func _mine() -> SessionComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	return ent.find_component(SessionComponent) as SessionComponent if ent != null else null


func _process(_delta: float) -> void:
	var me: SessionComponent = _mine()
	if me != null and me.match_number() != _match_seen:
		# A new match (or the first we have seen): its lobby is everyone's again.
		if _match_seen >= 0:
			_joined = false
			_saw_lobby = false
		_match_seen = me.match_number()
	if me != null and visible and not me.is_match_started():
		_saw_lobby = true
	if me != null and visible and me.is_match_started() and _saw_lobby:
		_joined = true   # we were in its lobby: the first round is ours
	var show: bool = should_show()
	if show != visible:
		_set_open(show)
	_hold(show)
	if not show:
		return
	_content.visible = character_page == null or not character_page.is_open()
	_refresh(me)


func _set_open(open: bool) -> void:
	visible = open
	_drawn = ""
	_hold(open)
	MouseCapture.hold_free(&"lobby_screen", open)
	if not open:
		if character_page != null and character_page.is_open():
			character_page.close()
		_clear_stage()


## Hold the local player still while open: whichever input component is theirs NOW (a look chosen
## here rebuilds the entity, and the new one must be held too), and let go when closed.
func _hold(open: bool) -> void:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var input: LocalInputComponent = ent.find_component(LocalInputComponent) as LocalInputComponent if ent != null and open else null
	if input == _holding and (input == null or is_instance_valid(input)):
		return
	if _holding != null and is_instance_valid(_holding):
		_holding.hold_still(&"lobby_screen", false)
	_holding = input
	if input != null:
		input.hold_still(&"lobby_screen", true)


func _refresh(me: SessionComponent) -> void:
	var kind: int = me.get_session_kind()
	var lobby: Dictionary = Rules.lobby(kind)
	var ready_up: bool = bool(lobby.get("ready_up", false))
	var teams: PackedStringArray = Rules.teams(kind)
	var started: bool = me.is_match_started()
	var rows: Array[Dictionary] = members()
	var players: int = 0
	var ready: int = 0
	for r: Dictionary in rows:
		if bool(r["player"]):
			players += 1
			ready += 1 if bool(r["ready"]) else 0
	if started:
		_status.text = "A match is under way: round %d, %s. Choose your character, then join." % [
			me.get_match_round(), Rules.phase_name(kind, me.get_phase())]
	elif ready_up:
		var need: int = int(lobby.get("min_players", 1))
		var left: float = me.seconds_remaining()
		_status.text = "Round 1 starts when everyone is ready: %d of %d%s%s" % [ready, players,
			"" if players >= need else ", %d needed" % need,
			"" if left > 3600.0 or left <= 0.0 else ", or in %ds" % int(left)]
	else:
		_status.text = "Round 1 starts in %ds" % int(maxf(0.0, me.seconds_remaining()))
	_ready_button.visible = not started and ready_up
	_ready_button.text = "Not ready" if me.is_ready() else "Ready"
	_join_button.visible = started
	_team_button.visible = teams.size() > 1 and not started
	if _team_button.visible:
		_team_button.text = "Team: %s" % (teams[me.team()] if me.team() < teams.size() else "?")
	_character_button.visible = character_page != null
	var sig: String = str(rows)
	for r: Dictionary in rows:
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(int(r["id"])) as SpaceTimeEntity
		sig += "|%s" % (ent.appearance if ent != null else "")
	if sig != _drawn:
		_drawn = sig
		_draw_stage(rows)


# --- building ------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.065, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_content = VBoxContainer.new()
	_content.name = "Content"
	(_content as VBoxContainer).add_theme_constant_override(&"separation", 12)
	center.add_child(_content)
	_title = Label.new()
	_title.name = "Title"
	var game: String = Genres.title()
	_title.text = "%s  ·  Lobby" % game if not game.is_empty() else "Lobby"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 30)
	_content.add_child(_title)
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 1, 1, 0.75)
	_content.add_child(_status)
	_content.add_child(_build_stage())
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 12)
	_content.add_child(buttons)
	_character_button = _button(buttons, "Character", "Choose character", func() -> void: character_requested.emit())
	_team_button = _button(buttons, "Team", "Team", _change_team)
	_ready_button = _button(buttons, "Ready", "Ready", _toggle_ready)
	_join_button = _button(buttons, "Join", "Join the game", join)
	_said = Label.new()
	_said.name = "Said"
	_said.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_said.modulate = Color(1.0, 0.75, 0.45)
	_content.add_child(_said)
	var hint := Label.new()
	hint.text = "Esc: menu (settings, disconnect)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.4)
	hint.add_theme_font_size_override(&"font_size", 12)
	_content.add_child(hint)


func _button(parent: Control, node_name: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(170, 40)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _build_stage() -> Control:
	var holder := SubViewportContainer.new()
	holder.name = "Stage"
	holder.stretch = true
	holder.custom_minimum_size = Vector2(STAGE_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = STAGE_SIZE
	holder.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.7
	_viewport.add_child(env)
	for l: Array in [[Vector3(-30.0, -35.0, 0.0), 1.2], [Vector3(-15.0, 40.0, 0.0), 0.45], [Vector3(-20.0, 180.0, 0.0), 0.6]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = l[0]
		light.light_energy = float(l[1])
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_camera.current = true
	_stage = Node3D.new()
	_stage.name = "Characters"
	_viewport.add_child(_stage)
	return holder


func _clear_stage() -> void:
	if _stage == null:
		return
	for c: Node in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()


## Everyone in a row, ourselves first, each in their look, idling, a name over their head.
func _draw_stage(rows: Array[Dictionary]) -> void:
	_clear_stage()
	var order: Array[Dictionary] = rows.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a["is_local"]) and not bool(b["is_local"]))
	var n: int = order.size()
	for i: int in range(n):
		var r: Dictionary = order[i]
		var id: int = int(r["id"])
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		var defn: EntityDefinition = ent.definition if ent != null else null
		var scene: PackedScene = defn.visual_for(id, ent.appearance) if defn != null else null
		var spot := Node3D.new()
		spot.set_meta(&"entity_id", id)
		spot.position = Vector3((float(i) - float(n - 1) * 0.5) * SPACING, 0.0, 0.0)
		_stage.add_child(spot)
		if scene != null:
			var model: Node3D = scene.instantiate() as Node3D
			if model != null:
				if model.has_method(&"apply_appearance"):
					model.call(&"apply_appearance", ent.appearance)
				model.rotation.y = deg_to_rad(defn.visual_yaw_deg + 180.0)
				spot.add_child(model)
				CharacterPicker.play_idle(model, defn)
		var plate := Label3D.new()
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.position = Vector3(0.0, 2.0, 0.0)
		plate.pixel_size = 0.0028
		plate.font_size = 40
		plate.outline_size = 10
		var state: String = ("Ready" if bool(r["ready"]) else "…") if bool(r["player"]) else "plays every round"
		plate.text = "%s\n%s" % [str(r["name"]), state]
		plate.modulate = Color(0.7, 1.0, 0.75) if bool(r["is_local"]) else Color.WHITE
		spot.add_child(plate)
	# Far enough back that the whole row and the names over it fit: 2.5 m of height, and the
	# row's width at the stage's own aspect.
	var width: float = float(n - 1) * SPACING + 1.6
	var half_v: float = tan(deg_to_rad(_camera.fov * 0.5))
	var aspect: float = float(STAGE_SIZE.x) / float(STAGE_SIZE.y)
	var distance: float = maxf(1.3 / half_v, width * 0.5 / (half_v * aspect))
	_camera.look_at_from_position(Vector3(0.0, 1.25, distance), Vector3(0.0, 1.15, 0.0))


# --- asking the server -------------------------------------------------------------------------

## R says ready here too, as in the in-world lobby.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _ready_button == null or not _ready_button.visible:
		return
	if InputMap.has_action(LobbyPanel.ACTION_READY) and event.is_action_pressed(LobbyPanel.ACTION_READY):
		get_viewport().set_input_as_handled()
		_toggle_ready()


func _toggle_ready() -> void:
	var me: SessionComponent = _mine()
	if me != null:
		_ask(&"set_ready", [not me.is_ready()], ["bool"])


func _change_team() -> void:
	var me: SessionComponent = _mine()
	var teams: PackedStringArray = Rules.teams(me.get_session_kind()) if me != null else PackedStringArray()
	if teams.size() > 1:
		_ask(&"set_team", [(me.team() + 1) % teams.size()], ["u8"])


## Ask, and say why if the server says no (a press that silently does nothing is the bug).
func _ask(reducer: StringName, args: Array, types: Array[String]) -> void:
	_said.text = ""
	var req: ReducerRequest = SpaceTimeSync.call_reducer(reducer, args, types)
	req.settled.connect(func(r: ReducerRequest) -> void:
		_said.text = "" if r.is_ok() else r.error_message.get_slice(": ", 1) if r.error_message.contains(": ") else r.error_message)
	if not req.is_pending() and not req.is_ok():
		_said.text = req.error_message


func said() -> String:
	return _said.text
