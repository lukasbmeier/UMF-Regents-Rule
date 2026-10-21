class_name PresenceComponent extends SpaceTimeComponent
## IS THIS PLAYER HERE? (DECISIONS #202) A player who disconnects leaves the world: after a short
## grace (the hot rule `foundation.offline_linger_s`, so a dropped connection that comes straight
## back does not make anyone blink out), their character is hidden and no longer collides or can
## be aimed at. When they connect again it comes back where they left it. Their record stays:
## progress, catches, standings.
##
## Reads `player.online`, which the server keeps (client_connected / client_disconnected). An
## entity with no player row (an NPC, a prop) is always present. The local player is always
## present: if we can see our own entity, we are connected.
##
## A TOOL IS NOT A PERSON (DECISIONS #272): an admin who has never said a name (the database's own CLI:
## a publish, a query, the host's feedback watcher) is given a player entity like anyone who connects,
## and nobody sees it (Luke saw a nameless "Player 30" blink in and out every few seconds while a
## watcher polled).
##
## Presentation only (hard rule 11): it hides a body; the server decides who is online.

const TABLE: StringName = &"player"
const LINGER_RULE: StringName = &"foundation.offline_linger_s"

var _online: bool = true
var _hidden: bool = false
var _left_at_usec: int = -1
## Whether an identity is an admin's: the `authority` table (tests set their own).
static var admin_check: Callable = Callable()


func required_tables() -> Array[StringName]:
	return [TABLE]


## NPCs and props have no player row; they must not wait for one (DECISIONS #69).
func optional_tables() -> Array[StringName]:
	return [TABLE]


## Whether the character is in the world now (false once the grace after a disconnect is over).
func is_present() -> bool:
	return not _hidden


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null:
		ent.set_hidden_by(&"tool", is_tool(new))
	var was: bool = _online
	_online = new == null or bool(new.get(&"online"))
	if _online:
		_left_at_usec = -1
		_set_hidden(false)
	elif was or _left_at_usec < 0:
		# Gone just now: the grace starts. Gone before we ever saw them: no grace to give.
		_left_at_usec = Time.get_ticks_usec() if is_bound() else 0


func _process(_delta: float) -> void:
	if _online or _left_at_usec < 0 or _hidden or _is_local():
		return
	var linger_usec: int = int(HotRules.number(LINGER_RULE) * 1_000_000.0)
	if _left_at_usec == 0 or Time.get_ticks_usec() - _left_at_usec >= linger_usec:
		_set_hidden(true)


func _set_hidden(hide: bool) -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null or hide == _hidden:
		return
	_hidden = hide
	# Through the entity: an out player (StatusComponent) who leaves stays hidden either way.
	ent.set_hidden_by(&"offline", hide)
	print("[Presence] entity %d %s" % [entity_id, "left the world" if hide else "is back"])


## Whether player row `row` is a tool's: no name, and its identity is an admin's.
static func is_tool(row: RefCounted) -> bool:
	if row == null:
		return false
	var name_v: Variant = row.get(&"name")
	if name_v == null or not String(name_v).strip_edges().is_empty():
		return false
	var identity: Variant = row.get(&"identity")
	if identity == null:
		return false
	if admin_check.is_valid():
		return bool(admin_check.call(identity))
	var a: RefCounted = SpaceTimeSync.get_row(&"authority", identity)
	return a != null and int(a.get(&"role")) == Roles.ADMIN


func _is_local() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	return ent != null and EntityRegistry.is_local(ent.entity_id)
