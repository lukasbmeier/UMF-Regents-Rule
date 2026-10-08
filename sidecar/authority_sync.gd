class_name AuthoritySync extends Node
## Writes what this process simulated back to the database, once per server tick.
##
## ONE reducer call per world per tick, never one per entity: at 20 Hz with thirty entities that
## is the difference between twenty calls a second and six hundred (`docs/SIDECAR_SPEC.md` §3).
## An entity whose state did not change contributes nothing, so a world where everybody is
## standing still costs no calls at all rather than a steady stream of identical rows.
##
## It also sends the heartbeat. `check_authorities` flips `authority_online` off after five
## seconds of silence, and clients freeze remote interpolation and show "world paused" when it
## does — so a sidecar that stops beating is worse than one that stops writing.
##
## SERVER-ONLY (hard rule 7b): this lives under `sidecar/`, which is excluded from the client
## export, and nothing in `foundation/` or `game/` may reference it.

## A batch went out. `count` is how many entities were in it.
signal batch_sent(world_id: int, count: int)

@export var world_id: int = 0
## Matches `NetConfig.server_tick_hz`: there is no point writing faster than the module ticks.
@export var tick_hz: float = 20.0
@export var heartbeat_sec: float = 1.0
## Off in tests, which have no server to call. `flush()` still gathers and reports the payload.
@export var send: bool = true

var batches_sent: int = 0
var writes_sent: int = 0
## Writes the module did not accept, which have been re-queued. Anything but zero on a healthy
## sidecar means it is not registered as an authority for this world.
var writes_refused: int = 0
## The worst per-entity input backlog seen. A number that climbs means this process cannot keep
## up with its world, which is the one failure that has no other symptom.
var worst_backlog: int = 0

var _accum: float = 0.0
var _hb: float = 0.0


func _physics_process(delta: float) -> void:
	var period: float = 1.0 / maxf(tick_hz, 1.0)
	_accum += delta
	if _accum >= period:
		# Subtract rather than zero, so the rate does not drift with the physics step; but a long
		# stall must not then fire a burst of catch-up ticks, one per frame.
		_accum = minf(_accum - period, period)
		flush()
	_hb += delta
	if _hb >= heartbeat_sec:
		_hb = 0.0
		_beat()


## Collect every entity's owed write and send them as one batch. Returns what it gathered, so a
## test can assert on the payload rather than on a reducer call it has no way to observe.
func flush() -> Array[Dictionary]:
	var writes: Array[Dictionary] = []
	for mv: SpaceTimeMovementComponent in authorities():
		worst_backlog = maxi(worst_backlog, mv.authority_backlog())
		var w: Dictionary = mv.take_authority_write()
		if not w.is_empty():
			writes.append(w)
	if writes.is_empty():
		return writes
	batches_sent += 1
	writes_sent += writes.size()
	if send:
		var ids: Array[int] = []
		for w: Dictionary in writes:
			ids.append(int(w["entity_id"]))
		var req: ReducerRequest = SpaceTimeSync.write_movement_batch(world_id, writes)
		req.settled.connect(func(r: ReducerRequest) -> void: _on_batch_settled(r, ids))
	batch_sent.emit(world_id, writes.size())
	return writes


## A batch the module refused is not a batch. Nothing would ever retry it on its own: the
## entity's simulated state has not changed, so it never becomes dirty again, and the database
## keeps the stale row until that entity happens to move. Owe them again instead.
func _on_batch_settled(req: ReducerRequest, ids: Array[int]) -> void:
	if req.outcome == ReducerRequest.Outcome.OK:
		return
	writes_refused += ids.size()
	for mv: SpaceTimeMovementComponent in authorities():
		if ids.has(mv.entity_id):
			mv.mark_authority_dirty()


## Every movement component this process is authoritative for. Read from the spawner rather than
## kept as a list of our own: entities come and go through the same row events as anywhere else,
## and a second list would be a second thing to get wrong.
func authorities() -> Array[SpaceTimeMovementComponent]:
	var out: Array[SpaceTimeMovementComponent] = []
	for node: Node in EntitySpawner.entity_nodes():
		var ent: SpaceTimeEntity = node as SpaceTimeEntity
		if ent == null:
			continue
		var mv: SpaceTimeMovementComponent = ent.find_component(
			SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		if mv != null and mv.mode == SpaceTimeMovementComponent.Mode.SERVER_AUTHORITY:
			out.append(mv)
	return out


func _beat() -> void:
	if send and SpaceTimeSync.is_connected_to_server():
		SpaceTimeSync.call_reducer(&"heartbeat", [world_id], ["u32"])
