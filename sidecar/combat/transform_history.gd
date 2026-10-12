class_name TransformHistory extends RefCounted
## WHERE ONE ENTITY WAS, a little while back (OPEN_ITEMS A1, DECISIONS #226): its authoritative
## position and heading as the server stamped them (`movement_state.server_ts`), kept for `keep_usec`,
## so the referee can ask where it was when an attacker saw it.
##
## Between two samples it is the straight line between them (a row comes 20 times a second; nothing
## moves far in 50 ms). Before the oldest it is the oldest, after the newest the newest: it never
## guesses beyond what the server said.
##
## SERVER-ONLY (hard rule 7b).

## How much it keeps: the longest rewind (`foundation.rewind_max_ms`, at most 300 ms), the wait for
## the attacker's own row, and margin.
var keep_usec: int = 1_000_000

## [ts_usec, pos, yaw], oldest first.
var _samples: Array = []


## A sample at server time `ts_usec`. One older than the newest is put in its place (rows can arrive
## out of order across a reconnect); one at the same time replaces it.
func push(ts_usec: int, pos: Vector3, yaw: float) -> void:
	var i: int = _samples.size()
	while i > 0 and int(_samples[i - 1][0]) > ts_usec:
		i -= 1
	if i > 0 and int(_samples[i - 1][0]) == ts_usec:
		_samples[i - 1] = [ts_usec, pos, yaw]
	else:
		_samples.insert(i, [ts_usec, pos, yaw])
	var newest: int = int(_samples[_samples.size() - 1][0])
	while _samples.size() > 2 and int(_samples[1][0]) < newest - keep_usec:
		_samples.pop_front()


func is_empty() -> bool:
	return _samples.is_empty()


func size() -> int:
	return _samples.size()


## The newest sample's time (0: none).
func newest_usec() -> int:
	return int(_samples[_samples.size() - 1][0]) if not _samples.is_empty() else 0


## Where it was at `ts_usec`: {pos, yaw}. Empty when it has no samples.
func at(ts_usec: int) -> Dictionary:
	if _samples.is_empty():
		return {}
	if ts_usec <= int(_samples[0][0]):
		return {"pos": _samples[0][1], "yaw": _samples[0][2]}
	var last: Array = _samples[_samples.size() - 1]
	if ts_usec >= int(last[0]):
		return {"pos": last[1], "yaw": last[2]}
	for i: int in range(1, _samples.size()):
		var b: Array = _samples[i]
		if int(b[0]) < ts_usec:
			continue
		var a: Array = _samples[i - 1]
		var span: float = float(int(b[0]) - int(a[0]))
		var t: float = float(ts_usec - int(a[0])) / span if span > 0.0 else 1.0
		return {"pos": (a[1] as Vector3).lerp(b[1] as Vector3, t), "yaw": lerp_angle(float(a[2]), float(b[2]), t)}
	return {"pos": last[1], "yaw": last[2]}
