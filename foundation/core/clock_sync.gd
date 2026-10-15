extends Node
## ClockSync — estimates the server clock in microseconds.
##
## Used ONLY for remote interpolation timing. Reconciliation keys on input `seq`, never on time.
## Samples come from two places, both fed by SpaceTimeSync:
##   • server Timestamp fields on rows we receive (SDK surfaces them as int microseconds)
##   • reducer round-trip times (from the SDK's request stats)
## Offset is filtered with a clamped EMA so a single late packet cannot yank the clock.

const EMA_ALPHA: float = 0.1
const MAX_STEP_USEC: int = 50_000   # never move the estimate more than 50 ms per sample
const SNAP_USEC: float = 1_000_000.0   # further than this from the estimate: it was behind, or the stamp is old

var _offset_usec: float = 0.0       # server_time ≈ local_time + offset
var _has_sample: bool = false
var _rtt_usec: float = 0.0

func local_usec() -> int:
	return Time.get_ticks_usec()

## Current best estimate of the server clock.
func server_usec() -> int:
	return local_usec() + int(_offset_usec)

func server_sec() -> float:
	return float(server_usec()) / 1_000_000.0

func rtt_usec() -> int:
	return int(_rtt_usec)

func has_sync() -> bool:
	return _has_sample

## Feed a server timestamp that was stamped when a row was written. It took roughly half the
## RTT to reach us, so by now the server clock has moved on by that much: ADD rtt/2. (This used
## to subtract it, which left `server_usec()` a full round trip behind the server — harmless
## only because remote interpolation happened to be padded by it; interpolation now keeps its
## own per-entity timeline, DECISIONS #75 and #78.)
##
## A STAMP IS WHEN A ROW WAS WRITTEN, NOT WHEN IT WAS SENT (Luke, on his Mac against a database kept
## for days: a night's clock read 5000 minutes and no egg could be laid). A prop that never moves
## (a nest, a gate) keeps the stamp of the day it was placed, and the first row a subscription hands
## over may be one: taken as "now", the estimate started days behind and the clamped EMA would take
## years to catch up. So the server is never earlier than a stamp it sent: one more than `SNAP_USEC`
## ahead of the estimate puts it there at once (it was behind), and one more than that behind it is an
## old row's, not a late packet's, and says nothing about now. Between, the clamped EMA as ever.
func observe_server_timestamp(server_ts_usec: int) -> void:
	var sample: float = float(server_ts_usec - local_usec()) + _rtt_usec * 0.5
	if not _has_sample:
		_offset_usec = sample
		_has_sample = true
		return
	var delta: float = sample - _offset_usec
	if delta > SNAP_USEC:
		_offset_usec = sample
		return
	if delta < -SNAP_USEC:
		return
	delta = clampf(delta * EMA_ALPHA, -MAX_STEP_USEC, MAX_STEP_USEC)
	_offset_usec += delta

func observe_rtt(rtt: int) -> void:
	if _rtt_usec == 0.0:
		_rtt_usec = float(rtt)
	else:
		_rtt_usec = lerpf(_rtt_usec, float(rtt), EMA_ALPHA)

func reset() -> void:
	_offset_usec = 0.0
	_rtt_usec = 0.0
	_has_sample = false
