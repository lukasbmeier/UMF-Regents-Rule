class_name LatencySim extends RefCounted
## Client-side network latency simulator, so prediction and interpolation can be tested on
## localhost, where the real round trip is ~0 ms and every netcode bug hides.
##
## `SpaceTimeSync` routes its traffic through this: reducer calls on the way out; row events,
## reducer results and subscription confirmations on the way in. Each direction is delayed by
## half the configured round trip plus up to `jitter_ms` of random extra.
##
## ORDER IS PRESERVED in each direction, exactly as on the WebSocket (TCP) transport SpacetimeDB
## uses: jitter stretches the gaps between messages but never reorders them. A simulator that
## reordered would be testing a failure this transport cannot have.
##
## LIMITATION: it delays what the client SEES, not what the SDK knows. The SDK's local cache still
## updates the moment a message lands, so code that reads the cache directly (`get_row`) sees
## rows early. Everything that follows the RowEvent stream — every component — sees the delay.

## Added round trip, milliseconds. Split evenly between the two directions.
var rtt_ms: int = 0
## Extra random delay per direction, 0..jitter_ms.
var jitter_ms: int = 0

var _out: Array[Array] = []   # [[deliver_at_usec: int, fn: Callable], ...] in delivery order
var _in: Array[Array] = []
var _last_out_usec: int = 0
var _last_in_usec: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func configure(p_rtt_ms: int, p_jitter_ms: int) -> void:
	rtt_ms = maxi(0, p_rtt_ms)
	jitter_ms = maxi(0, p_jitter_ms)


func is_active() -> bool:
	return rtt_ms > 0 or jitter_ms > 0


## True when a message may be handled on the spot. Also requires both queues to be empty:
## turning the simulator off mid-session must not let a new message overtake a queued one.
func is_passthrough() -> bool:
	return not is_active() and _out.is_empty() and _in.is_empty()


## Client -> server.
func send(fn: Callable) -> void:
	_last_out_usec = _enqueue(_out, fn, _last_out_usec)


## Server -> client.
func receive(fn: Callable) -> void:
	_last_in_usec = _enqueue(_in, fn, _last_in_usec)


## Deliver everything that is due. `SpaceTimeSync` calls this every frame.
func pump() -> void:
	var now: int = Time.get_ticks_usec()
	_drain(_out, now)
	_drain(_in, now)


## Drop everything in flight. On a terminal disconnect nothing queued should ever arrive.
func clear() -> void:
	_out.clear()
	_in.clear()


func queued() -> int:
	return _out.size() + _in.size()


func _enqueue(q: Array[Array], fn: Callable, last_usec: int) -> int:
	if is_passthrough():
		fn.call()
		return last_usec
	var one_way_usec: int = (rtt_ms * 1000) / 2
	var extra_usec: int = _rng.randi_range(0, jitter_ms) * 1000 if jitter_ms > 0 else 0
	# Never overtake the previous message in this direction.
	var at: int = maxi(Time.get_ticks_usec() + one_way_usec + extra_usec, last_usec)
	q.append([at, fn])
	return at


func _drain(q: Array[Array], now: int) -> void:
	while not q.is_empty() and int(q[0][0]) <= now:
		var item: Array = q.pop_front()
		(item[1] as Callable).call()
