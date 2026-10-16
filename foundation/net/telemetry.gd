class_name Telemetry extends Node
## HOW THIS GAME RAN, REPORTED TO THE HOST (DECISIONS #244, Luke 2026-10-15: "metrics and performance
## reported remotely across games/users"; "I dont want this to affect performance"). Every player's game
## and every referee keeps one (made by `SpaceTimeSync`), always on: nothing personal goes in it.
##
## Each frame it keeps one number (the frame's time) and notes a SPIKE: a frame slower than
## `foundation.telemetry_spike_ms`, or the server's rows stopping for `NET_STALL_MS` after flowing (a
## network stall: what freezes everyone else on screen). Every `foundation.telemetry_window_s` (30 s) it
## sends one small call, `report_perf` (well under a kilobyte): the window's frame times (median, 95th,
## 99th, worst), its spikes with the server time of each, ping, corrections, memory, entities. Off the
## input path; a server that has no `report_perf` (an older one) is asked once, then left alone.
##
## `moment()` is the same, up to now, for feedback (`FeedbackPage`): what the game was like as the
## player pressed the key.

## Rows that stop this long, having arrived faster than `FLOWING_MS` apart, are a network stall.
const NET_STALL_MS: int = 400
const FLOWING_MS: int = 150
## At most this many spikes are described in a report (all of them are counted).
const MAX_SPIKES: int = 12
## A window shorter than this is not reported (the game just started, or a test's).
const MIN_WINDOW_S: float = 1.0

## The current window: each frame's time (ms), when it began, its spikes ([server s, ms, cause]).
var _frames: PackedFloat32Array = PackedFloat32Array()
var _started_msec: int = 0
var _spikes: Array = []
var _spike_count: int = 0
var _rtt_sum: float = 0.0
var _rtt_n: int = 0
var _rtt_max: float = 0.0
var _corrections_at: int = -1
## The rows' rhythm, for stalls.
var _last_row_msec: int = 0
var _row_gap_msec: int = 100000
## The last window sent, for feedback.
var _previous: Dictionary = {}
## A server with no `report_perf`: asked no more.
var _unsupported: bool = false
var _platform: String = ""
## Reports sent this run (for tests).
var sent: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_msec = Time.get_ticks_msec()
	_platform = platform()
	if not SpaceTimeSync.row_event.is_connected(_on_row):
		SpaceTimeSync.row_event.connect(_on_row)


## What this machine is, coarsely: its OS, CPU and GPU names, cores and memory. Nothing personal.
static func platform() -> String:
	var mem: Dictionary = OS.get_memory_info()
	var gb: int = roundi(float(mem.get("physical", 0)) / 1073741824.0)
	return "%s %s | %s x%d | %s | %d GB" % [OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(),
		RenderingServer.get_video_adapter_name(), gb]


## Whether this process is a referee (or another authority) rather than a player's game.
static func is_authority() -> bool:
	return SpaceTimeSync.config != null and SpaceTimeSync.config.authority_process


func _process(delta: float) -> void:
	var ms: float = delta * 1000.0
	_frames.append(ms)
	if ms > HotRules.number(&"foundation.telemetry_spike_ms"):
		_spike(ms, "frame")
	var rtt: float = float(ClockSync.rtt_usec()) / 1000.0
	if rtt > 0.0:
		_rtt_sum += rtt
		_rtt_n += 1
		_rtt_max = maxf(_rtt_max, rtt)
	if Time.get_ticks_msec() - _started_msec >= int(window_s() * 1000.0):
		send_window()


## How long a window is (`foundation.telemetry_window_s`, at least a second).
static func window_s() -> float:
	return maxf(HotRules.number(&"foundation.telemetry_window_s"), MIN_WINDOW_S)


func _on_row(_ev: RowEvent) -> void:
	var now: int = Time.get_ticks_msec()
	if _last_row_msec > 0:
		var gap: int = now - _last_row_msec
		if gap > NET_STALL_MS and _row_gap_msec < FLOWING_MS:
			_spike(float(gap), "net")
		_row_gap_msec = gap
	_last_row_msec = now


func _spike(ms: float, cause: String) -> void:
	_spike_count += 1
	if _spikes.size() < MAX_SPIKES:
		_spikes.append([snappedf(ClockSync.server_sec(), 0.01), snappedf(ms, 0.1), cause])


## The window so far, summed up: frames, frame times, spikes, ping.
func summary() -> Dictionary:
	var sorted: PackedFloat32Array = _frames.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var at := func(q: float) -> float: return sorted[clampi(int(ceil(q * float(n))) - 1, 0, n - 1)] if n > 0 else 0.0
	return {
		"window_s": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
		"frames": n,
		"p50": snappedf(at.call(0.5), 0.01), "p95": snappedf(at.call(0.95), 0.01), "p99": snappedf(at.call(0.99), 0.01),
		"max": snappedf(sorted[n - 1], 0.01) if n > 0 else 0.0,
		"spikes": _spike_count, "spike_list": _spikes.duplicate(),
		"rtt_ms": snappedf(_rtt_sum / float(_rtt_n), 0.1) if _rtt_n > 0 else 0.0, "rtt_max_ms": snappedf(_rtt_max, 0.1),
		"corrections": maxi(_corrections() - _corrections_at, 0) if _corrections_at >= 0 else 0,
		"memory_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1),
		"entities": EntityRegistry.all_entity_ids().size(),
	}


## For feedback: the game as it was a moment ago (this window so far, and the one before).
func moment() -> Dictionary:
	return {"now": summary(), "before": _previous}


## The local player's movement corrections so far (0 with none).
func _corrections() -> int:
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if me != null else null
	return int(mv.get_reconcile_stats()["reconciles"]) if mv != null else 0


## End the window: report it (when there is a server to tell, that takes it), and start the next.
func send_window() -> void:
	var s: Dictionary = summary()
	_previous = s
	if float(s["window_s"]) >= MIN_WINDOW_S and not _unsupported and SpaceTimeSync.is_connected_to_server():
		var detail: String = JSON.stringify({"spikes": s["spike_list"], "screen": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y] if DisplayServer.get_name() != "headless" else "headless",
			"physics_hz": Engine.physics_ticks_per_second, "max_fps": Engine.max_fps})
		var req: ReducerRequest = SpaceTimeSync.call_reducer(&"report_perf", [SpaceTimeSync.bindings_fingerprint(), _platform,
			float(s["window_s"]), int(s["frames"]), float(s["p50"]), float(s["p95"]), float(s["p99"]), float(s["max"]),
			int(s["spikes"]), float(s["rtt_ms"]), float(s["rtt_max_ms"]), int(s["corrections"]), float(s["memory_mb"]), int(s["entities"]), detail],
			["string", "string", "f32", "u32", "f32", "f32", "f32", "f32", "u32", "f32", "f32", "u32", "f32", "u32", "string"])
		sent += 1
		var first: bool = sent == 1
		req.settled.connect(func(r: ReducerRequest) -> void:
			if first or not r.is_ok():
				print("[Telemetry] a window of %.0f s reported: %s" % [float(s["window_s"]), "ok" if r.is_ok() else r.error_message])
			# An older server, with no such reducer: not asked again this run.
			if not r.is_ok() and (r.error_message.contains("no such reducer") or r.error_message.contains("not found")):
				_unsupported = true)
	_frames = PackedFloat32Array()
	_spikes = []
	_spike_count = 0
	_rtt_sum = 0.0
	_rtt_n = 0
	_rtt_max = 0.0
	_corrections_at = _corrections()
	_started_msec = Time.get_ticks_msec()
