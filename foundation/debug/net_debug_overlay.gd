class_name NetDebugOverlay extends CanvasLayer
## Live netcode readout for playtesting. Drop `net_debug_overlay.tscn` into any game scene.
##
##   F3        show / hide
##   F4        cycle simulated round trip: 0 → 50 → 100 → 200 → 0 ms
##   Shift+F4  cycle simulated jitter:     0 → 20 → 50 → 0 ms
##
## What each line tells you when something feels wrong:
##   server rtt     the real network. Localhost is ~1-5 ms.
##   input ack      how long the server takes to confirm an input: batching + tick + network.
##                  Prediction hides this; if it is large and movement still feels instant,
##                  prediction is doing its job.
##   pending        inputs predicted but not yet confirmed (~ack latency x 60 Hz).
##   corrections    server disagreements. Normal play: 0. Each one is a glide (or a snap past
##                  1 m). A climbing count while you just walk around is a bug.
##   remote         how far in the past other players are drawn. Grows with measured jitter.
##
## Reads only public APIs (SpaceTimeSync, ClockSync, EntityRegistry, component getters), never
## the SDK, and produces no gameplay events: removing it changes nothing.

const LATENCY_STEPS: Array[int] = [0, 50, 100, 200]
const JITTER_STEPS: Array[int] = [0, 20, 50]
const ACK_WINDOW: int = 120

## Visible at start. Defaults to on when running from the editor, off in exported builds.
@export var start_visible: bool = true

@onready var _label: Label = $Panel/Label

var _movement: SpaceTimeMovementComponent = null
var _input: LocalInputComponent = null
var _sent_at: Dictionary[int, int] = {}
var _acked_seq: int = 0
var _ack_ms: Array[float] = []
var _refresh: float = 0.0


func _ready() -> void:
	visible = start_visible and OS.has_feature("editor")
	SignalBus.local_entity_assigned.connect(func(_eid: int) -> void: _movement = null)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F4:
		var sim: Vector2i = SpaceTimeSync.get_simulated_latency()
		if key.shift_pressed:
			SpaceTimeSync.set_simulated_latency(sim.x, _next(JITTER_STEPS, sim.y))
		else:
			SpaceTimeSync.set_simulated_latency(_next(LATENCY_STEPS, sim.x), sim.y)
		visible = true
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _movement == null:
		_bind_local()
		return
	# Input acknowledgement latency: when a seq is confirmed, how long ago did we send it?
	var acked: int = _movement.get_last_processed_seq()
	while _acked_seq < acked:
		_acked_seq += 1
		if _sent_at.has(_acked_seq):
			_ack_ms.append(float(Time.get_ticks_usec() - _sent_at[_acked_seq]) / 1000.0)
			_sent_at.erase(_acked_seq)
	while _ack_ms.size() > ACK_WINDOW:
		_ack_ms.pop_front()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.1
	_label.text = _compose()


func _bind_local() -> void:
	var id: int = EntityRegistry.local_entity_id
	if id < 0:
		return
	var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	if e == null or not e.is_bound():
		return
	_movement = e.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_input = e.find_component(LocalInputComponent) as LocalInputComponent
	if _input != null and not _input.input_sampled.is_connected(_on_sampled):
		_input.input_sampled.connect(_on_sampled)
	_acked_seq = _movement.get_last_processed_seq() if _movement != null else 0


func _on_sampled(f: InputFrame) -> void:
	_sent_at[f.seq] = Time.get_ticks_usec()
	if _sent_at.size() > 600:
		_sent_at.clear()   # the server stopped acknowledging; do not grow forever


func _compose() -> String:
	var sim: Vector2i = SpaceTimeSync.get_simulated_latency()
	var lines: PackedStringArray = []
	lines.append("NET   F3 hide · F4 latency · Shift+F4 jitter")
	lines.append("fps %d   physics %d Hz   interpolation %s" % [
		Engine.get_frames_per_second(),
		Engine.physics_ticks_per_second,
		"on" if ProjectSettings.get_setting("physics/common/physics_interpolation", false) else "off"])
	var sim_txt: String = "none" if sim.x == 0 and sim.y == 0 else "+%d ms ±%d" % [sim.x, sim.y]
	lines.append("server rtt   %4d ms    simulated %s" % [ClockSync.rtt_usec() / 1000, sim_txt])
	if SpaceTimeSync.state != SpaceTimeSync.ConnectionState.CONNECTED:
		lines.append("state        %s" % SpaceTimeSync.ConnectionState.keys()[SpaceTimeSync.state])
	if _movement == null:
		lines.append("(waiting for the local player)")
		return "\n".join(lines)

	lines.append("input ack    %s" % _ack_summary())
	var stats: Dictionary = _movement.get_reconcile_stats()
	lines.append("pending      %d inputs   epoch %d" % [_movement.pending_count(), _movement.get_epoch()])
	lines.append("corrections  %d (%d snapped)   last %.2f m   glide %.2f m" % [
		int(stats["reconciles"]), int(stats["snaps"]), float(stats["last_error"]),
		_movement.get_visual_offset().length()])
	lines.append(_remote_summary())
	return "\n".join(lines)


func _ack_summary() -> String:
	if _ack_ms.is_empty():
		return "—"
	var s: Array[float] = _ack_ms.duplicate()
	s.sort()
	return "%d ms p50   %d ms p95" % [int(s[s.size() / 2]), int(s[mini(s.size() - 1, int(s.size() * 0.95))])]


func _remote_summary() -> String:
	var count: int = 0
	var worst: float = 0.0
	for id: int in EntityRegistry.all_entity_ids():
		if id == EntityRegistry.local_entity_id:
			continue
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e == null or e.definition == null or e.definition.kind != 0:
			continue
		var m: SpaceTimeMovementComponent = e.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
		if m == null:
			continue
		count += 1
		worst = maxf(worst, m.get_interp_delay_sec())
	if count == 0:
		return "remote       no other players"
	return "remote       %d player%s drawn %d ms in the past" % [count, "" if count == 1 else "s", int(worst * 1000.0)]


static func _next(steps: Array[int], current: int) -> int:
	for v: int in steps:
		if v > current:
			return v
	return steps[0]
