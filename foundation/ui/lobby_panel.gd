class_name LobbyPanel extends CanvasLayer
## THE LOBBY (DECISIONS #174): while a round's lobby is open, who is here, who is ready and which
## team each is on, with the keys to say you are ready (R) and to change team (T). For a session kind
## whose rules give it a lobby (`shared/rules.json`); otherwise it never shows.
##
## The cursor stays the game's: two keys, rather than a mouse UI that would take it away, like the
## shop's. The server decides: a refused key says why here. Assembled from the components, like the
## standings: every member in view carries a SessionComponent (ready, team) and a NameplateComponent.

const ACTION_READY: StringName = &"lobby_ready"
const ACTION_TEAM: StringName = &"lobby_team"

var _panel: PanelContainer = null
var _title: Label = null
var _grid: GridContainer = null
var _hint: Label = null
var _said: String = ""
var _drawn: String = ""


func _init() -> void:
	name = "LobbyPanel"
	layer = 12


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override(&"panel", SettingsPanel._panel_style())
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -190.0
	_panel.offset_right = 190.0
	_panel.offset_top = 70.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	margin.add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 18)
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.name = "Members"
	_grid.columns = 3
	_grid.add_theme_constant_override(&"h_separation", 16)
	box.add_child(_grid)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.modulate = Color(1, 1, 1, 0.7)
	_hint.add_theme_font_size_override(&"font_size", 13)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	visible = false


## The local player's session component, or null.
func _mine() -> SessionComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	return ent.find_component(SessionComponent) as SessionComponent if ent != null else null


## Whether the lobby belongs on screen now: we are in a session in its lobby, and its kind has one,
## and the lobby screen (the match's lobby, #182) is not already showing it.
func should_show() -> bool:
	var me: SessionComponent = _mine()
	return me != null and me.is_in_session() and me.get_phase() == SessionComponent.Phase.LOBBY \
		and not Rules.lobby(me.get_session_kind()).is_empty() and LobbyScreen.showing(get_tree()) == null


## Everyone in our session, as the lobby lists them: {id, name, ready, team, player, is_local},
## players first, then by name.
func members() -> Array[Dictionary]:
	return members_of(_mine())


## Everyone in `me`'s session (the lobby panel's list, and the lobby screen's stage).
static func members_of(me: SessionComponent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if me == null:
		return out
	for id: int in EntityRegistry.all_entity_ids():
		var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		var sess: SessionComponent = ent.find_component(SessionComponent) as SessionComponent if ent != null else null
		if sess == null or sess.get_session_id() != me.get_session_id():
			continue
		var plate: NameplateComponent = ent.find_component(NameplateComponent) as NameplateComponent
		var local: bool = EntityRegistry.is_local(id)
		var player: bool = local or (plate != null and plate.is_online())
		if not player and ent.definition != null and ent.definition.kind == 0:
			continue   # a player who left: not waited for, not listed
		out.append({"id": id, "name": plate.display_name() if plate != null else "Player %d" % id,
			"ready": sess.is_ready(), "team": sess.team(), "player": player, "is_local": local})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["player"]) != bool(b["player"]):
			return bool(a["player"])
		return String(a["name"]) < String(b["name"]))
	return out


func _process(_delta: float) -> void:
	var show: bool = should_show()
	if show != visible:
		visible = show
		_said = ""
	if not show:
		return
	var me: SessionComponent = _mine()
	var lobby: Dictionary = Rules.lobby(me.get_session_kind())
	var teams: PackedStringArray = Rules.teams(me.get_session_kind())
	var left: int = int(maxf(0.0, me.seconds_remaining()))
	_title.text = "Lobby  ·  round %d starts when everyone is ready" % me.get_match_round() if me.is_waiting() \
		else "Lobby  ·  round %d starts in %ds" % [me.get_match_round(), left]
	var rows: Array[Dictionary] = members()
	var sig: String = str(rows) + str(teams)
	if sig != _drawn:
		_drawn = sig
		_draw_members(rows, teams)
	var keys: PackedStringArray = PackedStringArray()
	if bool(lobby.get("ready_up", false)):
		keys.append("%s: %s" % [_key_name(ACTION_READY), "not ready" if me.is_ready() else "ready"])
	if teams.size() > 1:
		keys.append("%s: change team" % _key_name(ACTION_TEAM))
	var waiting: String = ""
	if bool(lobby.get("ready_up", false)):
		var need: int = int(lobby.get("min_players", 1))
		var players: int = 0
		var ready: int = 0
		for r: Dictionary in rows:
			if bool(r["player"]):
				players += 1
				ready += 1 if bool(r["ready"]) else 0
		waiting = "%d of %d ready%s" % [ready, players, "" if players >= need else ", %d needed" % need]
	_hint.text = "  ·  ".join(keys) + ("" if waiting.is_empty() else "\n" + waiting) \
		+ ("" if _said.is_empty() else "\n" + _said)


func _draw_members(rows: Array[Dictionary], teams: PackedStringArray) -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for r: Dictionary in rows:
		var colour: Color = Color(0.7, 1.0, 0.75) if bool(r["is_local"]) else Color.WHITE
		_cell(str(r["name"]), colour)
		_cell(teams[int(r["team"])] if int(r["team"]) < teams.size() else "", Color(0.8, 0.85, 1.0))
		_cell(("ready" if bool(r["ready"]) else "…") if bool(r["player"]) else "plays every round",
			Color(0.6, 1.0, 0.6) if bool(r["ready"]) else Color(1, 1, 1, 0.5))


func _cell(text: String, colour: Color) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = colour
	_grid.add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var me: SessionComponent = _mine()
	if me == null:
		return
	if InputMap.has_action(ACTION_READY) and event.is_action_pressed(ACTION_READY) \
			and bool(Rules.lobby(me.get_session_kind()).get("ready_up", false)):
		get_viewport().set_input_as_handled()
		_ask(&"set_ready", [not me.is_ready()], ["bool"])
	elif InputMap.has_action(ACTION_TEAM) and event.is_action_pressed(ACTION_TEAM):
		var teams: PackedStringArray = Rules.teams(me.get_session_kind())
		if teams.size() > 1:
			get_viewport().set_input_as_handled()
			_ask(&"set_team", [(me.team() + 1) % teams.size()], ["u8"])


## Ask the server, and say why if it says no (a press that silently does nothing is the bug).
func _ask(reducer: StringName, args: Array, types: Array[String]) -> void:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(reducer, args, types)
	req.settled.connect(func(r: ReducerRequest) -> void:
		_said = "" if r.is_ok() else r.error_message.get_slice(": ", 1) if r.error_message.contains(": ") else r.error_message)
	if not req.is_pending() and not req.is_ok():
		_said = req.error_message


func said() -> String:
	return _said


static func _key_name(action: StringName) -> String:
	var v: Variant = Settings.get_value(action)
	return Settings.binding_label(String(v)) if v != null else String(action)
