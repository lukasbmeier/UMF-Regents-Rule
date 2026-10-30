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

## RING interest (template 1.0, DECISIONS #278): the cells round this client's player moved and the
## new ones have arrived. `centre` is the cell the ring is round.
signal cells_changed(centre: int)

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
const ALWAYS_TABLES: Array[StringName] = [&"hot_rule", &"authority",
	# Your own account, its characters and your link code (template 1.0): the server sends each player
	# only their own rows (row-level security), so they are asked for whole.
	&"account_login", &"account_character", &"link_code"]

const WORLD_TABLES: Array[StringName] = [
	&"entity", &"movement_state", &"health_state", &"session", &"action_event", &"equip_state",
	&"appearance", &"lobby_member", &"world_level", &"session_match", &"status_state", &"hold_progress", &"hold_member", &"attachment", &"noise",
	&"body_state", &"body_contact", &"push", &"ground_item", &"resource_state", &"chat_message",
	# Not in the client's core set, but a sidecar adds it and it is the highest-volume table
	# there is: an authority for world 3 must not be fed every other world's input.
	&"input_queue",
	# Also sidecar-only: a world's NPC brains, for its authority to resume after a restart.
	&"npc_brain",
	# And who drives each NPC, in a world split into regions (DECISIONS #288).
	&"npc_driver",
]

## Tables whose rows carry the cell of a placed thing (`chunk`, template 1.0, DECISIONS #278): a RING
## client asks for them cell by cell, in a set of their own (`_ring_active`), swapped as its player
## walks; everything else stays in the world's set, which only a change of world swaps. Every one is
## also a WORLD table (what a WORLD client asks).
const CELL_TABLES: Array[StringName] = [
	&"entity", &"movement_state", &"health_state", &"equip_state", &"appearance", &"status_state",
	&"attachment", &"resource_state", &"hold_progress", &"body_state",
	&"noise", &"body_contact", &"push", &"action_event", &"ground_item",
]

## Of `CELL_TABLES`, those whose rows describe an entity by `entity_id` and follow it: a RING client is
## always sent its own player's, by id, wherever the cells are (and before it knows where it is).
const FOLLOW_TABLES: Array[StringName] = [
	&"entity", &"movement_state", &"health_state", &"equip_state", &"appearance", &"status_state",
	&"attachment", &"resource_state", &"hold_progress", &"body_state",
]

## The cell of a PARKED character (the module's `cell::NOWHERE`): its rows are kept there, sent to nobody.
const NOWHERE: int = 4294967295

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

## RING interest: the cell the ring is round, -1 until this client's own movement row says.
var centre: int = -1
## RING interest: the entity whose rows are asked for by id (this client's player), -1 until known.
var own_entity: int = -1
## RING interest: the set of cell rows in the cache, and the one replacing it. Swapped with the same
## overlap as a world (the new one applied before the old is dropped), so a neighbour in a cell both
## rings share is never deleted and re-inserted; one walking between two cells of one ring is an update
## inside the set (the SDK pairs its delete and insert).
var _ring_active: SubscriptionSet = null
var _ring_incoming: SubscriptionSet = null
## A REGION REFEREE'S cells (DECISIONS #288): the chunks it watches, one range a column
## ([Vector2i(first, last)], `RefereeRegion.columns`). Set, the cell tables are asked for by these, in the
## cells' set, whatever the config says; empty (every other client and referee), as before.
var region_columns: Array[Vector2i] = []
## RING interest: the set of our own rows (by id), and the one replacing it (another character).
var _own_active: SubscriptionSet = null
var _own_incoming: SubscriptionSet = null


func _ready() -> void:
	SpaceTimeSync.connection_state_changed.connect(_on_connection_state_changed)
	SpaceTimeSync.row_event.connect(_on_row_event)
	SignalBus.local_entity_assigned.connect(_on_local_entity)


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
		if is_ring():
			_apply_ring()   # the same cells in another world are other rows


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
		if is_ring() and is_cell_table(t):
			continue   # asked for by cell, in the ring's own set (`build_ring_queries`)
		out.append(query_for(t, for_world))
	return out


## RING interest: the queries of the cell set for `for_world`: every cell table subscribed, by each cell
## of the ring round `centre` (none until it is known). One query per cell rather than one OR'd ring: two
## clients in the same cells ask the same queries, which the server works out once for both.
func build_ring_queries(for_world: int) -> Array[String]:
	var out: Array[String] = []
	if not region_columns.is_empty():
		for t: StringName in subscribed_tables():
			if is_cell_table(t):
				for col: Vector2i in region_columns:
					out.append(region_query(t, for_world, col.x, col.y))
		return out
	if centre < 0:
		return out
	var cells: PackedInt64Array = Cells.ring(centre, Cells.ring_radius())
	for t: StringName in subscribed_tables():
		if not is_cell_table(t):
			continue
		for c: int in cells:
			out.append(cell_query(t, for_world, c))
	return out


## RING interest: the query for one cell table's rows in one cell. Also what the load test's bots ask
## (`tools/load/interest_dump.gd`), so they are sent what a real client is.
func cell_query(table: StringName, for_world: int, cell: int) -> String:
	return "SELECT * FROM %s WHERE world_id = %d AND chunk = %d" % [table, for_world, cell]


## A REGION REFEREE: one cell table's rows in one column of its cells (chunks `first` to `last`).
func region_query(table: StringName, for_world: int, first: int, last: int) -> String:
	return "SELECT * FROM %s WHERE world_id = %d AND chunk >= %d AND chunk <= %d" % [table, for_world, first, last]


## RING interest: the query for one follow table's row of our own entity.
func own_query(table: StringName, entity: int) -> String:
	return "SELECT * FROM %s WHERE entity_id = %d" % [table, entity]


## RING interest: this client's own rows of the tables that follow an entity, by id, in a set of their
## own that only a new player (another character) swaps: our own body is never one cell's to drop.
## Kept apart from the cells, so no row is matched by two queries of one set.
func build_own_queries() -> Array[String]:
	var out: Array[String] = []
	if own_entity < 0:
		return out
	for t: StringName in subscribed_tables():
		if is_cell_table(t) and is_follow_table(t):
			out.append(own_query(t, own_entity))
	return out


## Whether this client is sent only the cells round it: its config says RING, and it is not an
## authority (a sidecar or referee takes the whole world it runs).
func is_ring(cfg: NetConfig = null) -> bool:
	var c: NetConfig = cfg if cfg != null else SpaceTimeSync.config
	if not region_columns.is_empty():
		return true   # a region referee: its cells, asked for the way a ring is
	return c != null and c.interest == NetConfig.Interest.RING and not c.authority_process


## Whether `table`'s rows carry a placed thing's cell: the foundation's (`CELL_TABLES`) or the game's.
func is_cell_table(table: StringName, cfg: NetConfig = null) -> bool:
	var c: NetConfig = cfg if cfg != null else SpaceTimeSync.config
	return CELL_TABLES.has(table) or (c != null and c.cell_tables.has(table))


## Whether `table`'s rows describe an entity by `entity_id` and follow it.
func is_follow_table(table: StringName, cfg: NetConfig = null) -> bool:
	var c: NetConfig = cfg if cfg != null else SpaceTimeSync.config
	return FOLLOW_TABLES.has(table) or (c != null and c.follow_tables.has(table))


## The ring's set in the cache, or null. For tests and the debug overlay.
func ring_set() -> SubscriptionSet:
	return _ring_active


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
	if is_cell_table(table, cfg):
		# A parked character's rows sit in the NOWHERE cell (template 1.0): nobody is sent them.
		return "SELECT * FROM %s WHERE world_id = %d AND chunk != %d" % [table, for_world, NOWHERE]
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
			if is_ring() and _ring_active == null and _ring_incoming == null:
				_apply_ring()
			if is_ring() and _own_active == null and _own_incoming == null:
				_apply_own()
		SpaceTimeSync.ConnectionState.DISCONNECTED, SpaceTimeSync.ConnectionState.FAILED:
			# `disconnected` is terminal in this SDK: every handle is gone and SpaceTimeSync has
			# already dropped its own references.
			_active = null
			_incoming = null
			_ring_active = null
			_ring_incoming = null
			_own_active = null
			_own_incoming = null
			centre = -1
			own_entity = -1


## RING interest: subscribe the cells round `centre` (and our own rows), keeping the ring in the cache
## until the new one has applied. Nothing to ask yet (no player, no place): nothing subscribed.
func _apply_ring() -> void:
	if _ring_incoming != null:
		SpaceTimeSync.unsubscribe(_ring_incoming)   # superseded: the player moved on again
		_ring_incoming = null
	if SpaceTimeSync.state != SpaceTimeSync.ConnectionState.CONNECTED:
		return
	var queries: Array[String] = build_ring_queries(world_id)
	if queries.is_empty():
		return
	_serial += 1
	var set := SubscriptionSet.new()
	set.name = StringName("cells#%d" % _serial)
	for q: String in queries:
		set.add_query(q)
	set.applied.connect(_on_ring_applied)
	set.ended.connect(_on_ended)
	_ring_incoming = set
	SpaceTimeSync.subscribe(set)


func _on_ring_applied(set: SubscriptionSet) -> void:
	if set == _ring_active or set != _ring_incoming:
		return   # a reconnect re-applying the one we hold, or one already superseded
	var old: SubscriptionSet = _ring_active
	_ring_active = set
	_ring_incoming = null
	if old != null:
		SpaceTimeSync.unsubscribe(old)   # only now: the shared cells' rows are held by the new one too
	cells_changed.emit(centre)


## RING interest: subscribe our own rows, keeping the old player's until the new one's have applied.
func _apply_own() -> void:
	if _own_incoming != null:
		SpaceTimeSync.unsubscribe(_own_incoming)
		_own_incoming = null
	if SpaceTimeSync.state != SpaceTimeSync.ConnectionState.CONNECTED:
		return
	var queries: Array[String] = build_own_queries()
	if queries.is_empty():
		return
	_serial += 1
	var set := SubscriptionSet.new()
	set.name = StringName("own#%d" % _serial)
	for q: String in queries:
		set.add_query(q)
	set.applied.connect(_on_own_applied)
	set.ended.connect(_on_ended)
	_own_incoming = set
	SpaceTimeSync.subscribe(set)


func _on_own_applied(set: SubscriptionSet) -> void:
	if set == _own_active or set != _own_incoming:
		return
	var old: SubscriptionSet = _own_active
	_own_active = set
	_own_incoming = null
	if old != null:
		SpaceTimeSync.unsubscribe(old)


## The set of our own rows in the cache, or null. For tests and the debug overlay.
func own_set() -> SubscriptionSet:
	return _own_active


## Our player is known: its rows are asked for by id from now on, wherever it stands.
func _on_local_entity(eid: int) -> void:
	if eid == own_entity:
		return
	own_entity = eid
	if is_ring():
		_apply_own()


## Our player's movement row: the ring follows it, once it is well inside another cell (`Cells.recentre`).
func _on_row_event(ev: RowEvent) -> void:
	if own_entity < 0 or ev.entity_id != own_entity or ev.table != &"movement_state" or not is_ring():
		return
	if ev.kind == RowEvent.Kind.DELETED:
		return   # gone from the cache (a world being left): the next row says where it is
	var row: RefCounted = ev.current()
	if row == null:
		return
	var pos: Variant = row.get(&"pos")
	if not pos is Vector3:
		return
	var next: int = Cells.recentre(centre, pos as Vector3)
	if next != centre:
		centre = next
		_apply_ring()


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
	if set == _ring_incoming:
		_ring_incoming = null
	if set == _ring_active:
		_ring_active = null
	if set == _own_incoming:
		_own_incoming = null
	if set == _own_active:
		_own_active = null
	# It never worked; do not leave it counted among the live sets.
	SpaceTimeSync.unsubscribe(set)
