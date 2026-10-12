extends Node
## InterestManager — THE ONLY PLACE SUBSCRIPTION SQL IS BUILT (`docs/PHASE3_SPEC.md` Task 11,
## and a Phase 3 definition-of-done criterion).
##
## A client does not want every row in the database; it wants the rows for the world it is in.
## This autoload owns that decision. `SpaceTimeSync` still owns the connection, the SDK and the
## handles — it no longer decides what to ask for.
##
## WHY IT IS ITS OWN OBJECT. Three layers need to change the question without changing anything
## else: a match-based genre re-subscribes when the player joins another world, a sidecar adds
## the tables only an authority reads (`input_queue`, `npc_brain`), and an MMO replaces the whole
## thing with a 3x3 cell neighbourhood rebuilt as the player walks (`docs/GENRE_ADAPTERS.md` §3).
## All three override `build_queries()` or append to `extra_tables`; none of them touches a
## component, and no SQL is written anywhere else.
##
## SWITCHING WORLDS OVERLAPS ON PURPOSE. The new set is subscribed first and the old one dropped
## only once the new one has APPLIED. Dropping first would delete every row in the cache and
## re-insert it a moment later, which the spawner cannot tell from a reconnect: every entity
## despawns and respawns, every component unbinds and rebinds (DECISIONS #17). The overlap costs
## one redundant set for a few hundred milliseconds and is invisible instead.
##
## The set is not rebuilt on a reconnect. SDK subscription handles survive it — they suspend and
## re-apply — so `applied` simply fires again on the set we already hold.

## The world this client is subscribed to changed, and the new set has applied. Fires on the
## FIRST set too — going from no world to world 0 is a change, and a listener that reacts to
## "we are in world N now" should not have to special-case the one at boot.
signal world_changed(world_id: int)

## Tables whose rows belong to ONE world, and are therefore filtered to it. Everything else in
## `NetConfig.core_tables` is subscribed whole: static catalogues (`item_def`, `ability_def`),
## identity-keyed rows (`player`), rows keyed by entity rather than world
## (`inventory_item`, `ability_state`, `session_member`, `challenge`, `catch`), and
## `world_config`, which is how a client learns that the other worlds exist at all.
##
## A table listed here MUST have a `world_id` column or its subscription fails at the server.
## Tables EVERY client and sidecar subscribes, whatever its config lists: what the foundation itself
## needs everywhere: the hot rules (DECISIONS #201: every client follows the live values) and who
## is trusted (`authority`: the client shows the admin's pages only to the admin, `Roles`).
const ALWAYS_TABLES: Array[StringName] = [&"hot_rule", &"authority"]

const WORLD_TABLES: Array[StringName] = [
	&"entity", &"movement_state", &"health_state", &"session", &"action_event", &"equip_state",
	&"appearance", &"lobby_member", &"world_level", &"session_match", &"status_state", &"hold_progress", &"hold_member", &"attachment",
	# Not in the client's core set, but a sidecar adds it and it is the highest-volume table
	# there is: an authority for world 3 must not be fed every other world's input.
	&"input_queue",
	# Also sidecar-only: a world's NPC brains, for its authority to resume after a restart.
	&"npc_brain",
]

## `module.rs` DEFAULT_WORLD: where `client_connected` puts a player that has not joined anything.
const DEFAULT_WORLD: int = 0

## Extra tables to subscribe beyond `NetConfig.core_tables`, filtered by the same rule. The
## sidecar adds `input_queue` and `npc_brain` here rather than subclassing, because it wants the
## foundation's queries plus its own rather than a different set (`docs/SIDECAR_SPEC.md` §3).
var extra_tables: Array[StringName] = []

## The world currently subscribed to. Read-only from outside; call `set_world()`.
var world_id: int = DEFAULT_WORLD

## The set whose rows are in the cache right now.
var _active: SubscriptionSet = null
## Subscribed, not yet confirmed by the server. At most one.
var _incoming: SubscriptionSet = null
## Subscription set names must be unique while active, and an overlap means two are.
var _serial: int = 0


func _ready() -> void:
	SpaceTimeSync.connection_state_changed.connect(_on_connection_state_changed)


# =============================================================================
# PUBLIC API
# =============================================================================

## Subscribe to `new_world`, keeping the current rows until the new set applies. Safe to call
## with the world already set: it does nothing rather than churning the cache.
func set_world(new_world: int) -> void:
	if new_world == world_id and (_active != null or _incoming != null):
		return
	world_id = new_world
	if SpaceTimeSync.state == SpaceTimeSync.ConnectionState.CONNECTED:
		_apply()


## True once the core set for the current world has applied.
func has_world() -> bool:
	return _active != null


## The set backing the current world, or null. For tests and the debug overlay.
func active_set() -> SubscriptionSet:
	return _active


## OVERRIDE POINT. Everything else in this class is plumbing; this is the question being asked.
## An MMO zone returns its cell neighbourhood here, ignoring `world_id` entirely.
func build_queries(for_world: int) -> Array[String]:
	var out: Array[String] = []
	var tables: Array[StringName] = []
	if SpaceTimeSync.config != null:
		tables.assign(SpaceTimeSync.config.core_tables)
	for t: StringName in extra_tables:
		if not tables.has(t):
			tables.append(t)
	for t: StringName in ALWAYS_TABLES:
		if not tables.has(t):
			tables.append(t)
	for t: StringName in tables:
		out.append(query_for(t, for_world))
	return out


## Every table the current set asks for: the config's core tables and the extras. What an entity
## is rebuilt from when it respawns (`EntitySpawner.respawn`).
func subscribed_tables() -> Array[StringName]:
	var tables: Array[StringName] = []
	if SpaceTimeSync.config != null:
		tables.assign(SpaceTimeSync.config.core_tables)
	for t: StringName in extra_tables:
		if not tables.has(t):
			tables.append(t)
	for t: StringName in ALWAYS_TABLES:
		if not tables.has(t):
			tables.append(t)
	return tables


## The query for one table. Split out so an override can reuse the world-filtering rule for the
## tables it agrees about and replace only the ones it does not.
func query_for(table: StringName, for_world: int, cfg: NetConfig = null) -> String:
	if is_world_table(table, cfg):
		return "SELECT * FROM %s WHERE world_id = %d" % [table, for_world]
	return "SELECT * FROM %s" % table


## Whether `table`'s rows each belong to one world: the foundation's (`WORLD_TABLES`) or the
## game's (`NetConfig.world_tables`, of `cfg` or the connection's).
func is_world_table(table: StringName, cfg: NetConfig = null) -> bool:
	var c: NetConfig = cfg if cfg != null else SpaceTimeSync.config
	return WORLD_TABLES.has(table) or (c != null and c.world_tables.has(table))


# =============================================================================
# INTERNALS
# =============================================================================

func _on_connection_state_changed(state: SpaceTimeSync.ConnectionState) -> void:
	match state:
		SpaceTimeSync.ConnectionState.CONNECTED:
			# A reconnect arrives here too, with the handles intact — see the header.
			if _active == null and _incoming == null:
				_apply()
		SpaceTimeSync.ConnectionState.DISCONNECTED, SpaceTimeSync.ConnectionState.FAILED:
			# `disconnected` is terminal in this SDK: every handle is gone and SpaceTimeSync has
			# already dropped its own references.
			_active = null
			_incoming = null


func _apply() -> void:
	if _incoming != null:
		# Superseded before the server ever confirmed it. Drop it now rather than letting it
		# apply into a world we have already left.
		SpaceTimeSync.unsubscribe(_incoming)
		_incoming = null
	_serial += 1
	var set := SubscriptionSet.new()
	set.name = StringName("core#%d" % _serial)
	for q: String in build_queries(world_id):
		set.add_query(q)
	set.applied.connect(_on_applied)
	set.ended.connect(_on_ended)
	_incoming = set
	SpaceTimeSync.subscribe(set)


func _on_applied(set: SubscriptionSet) -> void:
	if set == _active:
		# A reconnect re-applied the handle we already hold. Everything downstream of
		# `world_ready` is written to expect that (it fired on every reconnect before this class
		# existed), so it must keep firing.
		SpaceTimeSync.mark_world_ready()
		return
	if set != _incoming:
		return   # already superseded and unsubscribed
	var old: SubscriptionSet = _active
	_active = set
	_incoming = null
	if old != null:
		SpaceTimeSync.unsubscribe(old)   # only now: the new rows are already in the cache
	SpaceTimeSync.mark_world_ready()
	world_changed.emit(world_id)


func _on_ended(set: SubscriptionSet, error: String) -> void:
	if error.is_empty():
		return
	# A malformed query is silent otherwise: no rows arrive, every entity stalls on its bind
	# timeout, and the game comes up empty with nothing in the log.
	push_error("InterestManager: subscription '%s' failed for world %d: %s\n  %s"
		% [set.name, world_id, error, "\n  ".join(set.queries)])
	if set == _incoming:
		_incoming = null
	if set == _active:
		_active = null
	# It never worked; do not leave it counted among the live sets.
	SpaceTimeSync.unsubscribe(set)
