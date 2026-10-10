class_name FoundationHud extends Control
## THE FOUNDATION'S HUD: one status line, what the connection is doing and then the local player's
## round (phase, time left, score), the hold prompt (`HoldPrompt`) and the timed press's bar (`TimingBar`). The greybox game carries it as `HUD`; a genre that brings its
## own `HUD` scene (`genre.tres` `scenes`) replaces it, the way a genre's entity definition replaces
## the foundation's for the same kind (Boot, DECISIONS #197).
##
## It latches onto the local player when it spawns and lets go when it leaves (a disconnect, the
## Escape menu's Disconnect), so it never reads a freed node.

## The session kind the foundation's rounds run as (`shared/rules.json` names its phases).
const SESSION_KIND: int = 0

@onready var _status: Label = $Status

var _entity: SpaceTimeEntity = null
var _session: SessionComponent = null
var _status_c: StatusComponent = null


func _ready() -> void:
	# The hold prompt and its bar (DECISIONS #209): it finds the local player itself.
	add_child(HoldPrompt.new())
	# The timed press's bar (DECISIONS #210), likewise.
	add_child(TimingBar.new())
	SignalBus.entity_spawned.connect(_on_entity_spawned)
	SignalBus.entity_despawned.connect(_on_entity_despawned)
	_status.text = connection_line()


func _process(_delta: float) -> void:
	_status.text = status_line()


## What the status line says now.
func status_line() -> String:
	if _entity == null or not is_instance_valid(_entity):
		return connection_line()
	if _session == null:
		return "in the world"
	var phase: String = Rules.phase_name(SESSION_KIND, _session.get_phase()).to_upper()
	if phase.is_empty():
		phase = "PHASE %d" % _session.get_phase()
	var time: String = "waiting for players" if _session.is_waiting() \
		else "%ds left" % int(maxf(0.0, _session.seconds_remaining()))
	return "%s  •  %s  •  %d pts%s" % [phase, time, _session.get_score(), status_part()]


## The player's own status, when it is not normal: "  •  DOWNED 42s".
func status_part() -> String:
	if _status_c == null or not is_instance_valid(_status_c) or _status_c.status() == StatusDef.NORMAL:
		return ""
	var left: float = _status_c.seconds_left()
	return "  •  %s%s" % [_status_c.def().display_name.to_upper(), "" if is_inf(left) else " %ds" % ceili(left)]


## Before the local player exists: what the connection is doing.
static func connection_line() -> String:
	match SpaceTimeSync.state:
		SpaceTimeSync.ConnectionState.CONNECTED:
			return "joining…"
		SpaceTimeSync.ConnectionState.CONNECTING:
			return "connecting…"
		SpaceTimeSync.ConnectionState.RECONNECTING:
			return "reconnecting…"
		_:
			return "not connected"


func _on_entity_spawned(entity_id: int, _kind: int) -> void:
	if not EntityRegistry.is_local(entity_id):
		return
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(entity_id) as SpaceTimeEntity
	if ent == null:
		return
	_entity = ent
	_session = ent.find_component(SessionComponent) as SessionComponent
	_status_c = ent.find_component(StatusComponent) as StatusComponent


func _on_entity_despawned(entity_id: int) -> void:
	if _entity == null or not is_instance_valid(_entity) or _entity.entity_id != entity_id:
		return
	_entity = null
	_session = null
	_status_c = null
