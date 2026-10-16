class_name SessionRecorder extends Node
## A RECORDING OF EVERY ROUND (DECISIONS #235, Fowl Play's OPEN_ITEMS A5: "SessionRecorder replay is the
## debugging tool: build it before the first human playtest"). The world's referee sees every row of its
## world, so it writes down each round as it is played: where everyone was ten times a second, and what
## happened (statuses, hits and misses, holds done, noises, the phases, the standings at the end). One
## file a round, `user://recordings/`, one JSON object a line:
##
##   {"recording": 1, "world": 0, "session": 3, "round": 2, "level": "res://...", "started": <unix s>,
##    "kinds": {"100": "Hen", ...}, "names": {"<entity>": "Luke", ...}}        the first line
##   {"t": 12.3, "e": [[id, kind, x, y, z, yaw, status], ...]}                 where everyone was
##   {"t": 12.3, "ev": "status", "id": 9, "from": 0, "to": 1}                  what happened
##   {"t": 12.3, "ev": "action", "actor": 9, "ability": 10000, "target": 7, "outcome": 1}
##   {"t": 12.3, "ev": "hold", "hold": 10001, "target": 12, "doers": 2}
##   {"t": 12.3, "ev": "noise", "kind": 100, "pos": [x, y, z], "source": 9, "target": 12}
##   {"t": 12.3, "ev": "phase", "phase": 4}
##   {"t": 12.3, "ev": "brain", "id": 9, "state": "flee", "goal": [x, z]}         what a bot decided
##   {"t": 30.0, "ev": "standings", "scores": {"<entity>": 12, ...}}
##
## A round starts when its session leaves the lobby and ends when it comes back to it (or the round's
## number changes). `tools/replay/replay_viewer.tscn` plays one back. Reads the rows only: it changes
## nothing in the world.
##
## SERVER-ONLY (hard rule 7b).

const DIR: String = "user://recordings"
const FORMAT: int = 1
## How many recordings are kept: the oldest go as a new one starts.
const KEEP: int = 60
## Ten frames a second.
const FRAME_S: float = 0.1
const LOBBY: int = 0
const RESULTS: int = 2

var world_id: int = 0
## The level the world runs, for the viewer (`level_of`, asked as each round starts, when given).
var level_path: String = ""
var level_of: Callable = Callable()
## kind -> what it is called (the definitions the sidecar knows).
var kind_names: Dictionary = {}
## TESTING: the rows of a table in this world (default: the client cache, `SpaceTimeSync`).
var rows_of: Callable = Callable()
## TESTING: the clock, in seconds (default: the engine's).
var clock: Callable = Callable()
## TESTING: the bots' brains, [[id, state, goal or null], ...] (default: every bot this sidecar drives).
var brains_of: Callable = Callable()
## A goal further than this from the last one written is a new decision.
const GOAL_JUMP_M: float = 3.0
var _brain_seen: Dictionary[int, Array] = {}

var _file: FileAccess = null
var _path: String = ""
var _session_id: int = -1
var _round: int = -1
var _phase: int = -1
var _t0: float = 0.0
var _accum: float = 0.0
var _statuses: Dictionary[int, int] = {}
var _seen_actions: Dictionary[int, bool] = {}
var _seen_noises: Dictionary[int, bool] = {}
var _seen_holds: Dictionary[int, bool] = {}
var _frames: int = 0
## The recordings this run wrote, oldest first.
var written: PackedStringArray = PackedStringArray()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < FRAME_S:
		return
	_accum = fmod(_accum, FRAME_S)
	tick()


func _exit_tree() -> void:
	stop()


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else float(Time.get_ticks_msec()) / 1000.0


func _rows(table: StringName) -> Array:
	if rows_of.is_valid():
		return rows_of.call(table) as Array
	return SpaceTimeSync.find_rows(table, func(r: RefCounted) -> bool:
		return r.get(&"world_id") == null or int(r.get(&"world_id")) == world_id)


## Whether it is writing a round now, and where.
func is_recording() -> bool:
	return _file != null


func path() -> String:
	return _path


## One step: start or end a round as its session says, and while one is on, a frame and what happened.
func tick() -> void:
	var sess: RefCounted = _session()
	var phase: int = int(sess.get(&"phase")) if sess != null else LOBBY
	var sid: int = int(sess.get(&"id")) if sess != null else -1
	var rnd: int = int(sess.get(&"round")) if sess != null else -1
	if _file != null and (sid != _session_id or rnd != _round or phase == LOBBY):
		stop()
	if _file == null:
		if sess != null and phase != LOBBY:
			start(sid, rnd)
		else:
			_phase = phase
			return
	var t: float = snappedf(_now() - _t0, 0.01)
	if phase != _phase:
		_phase = phase
		_line({"t": t, "ev": "phase", "phase": phase})
		if phase == RESULTS:
			_line({"t": t, "ev": "standings", "scores": _scores(sid)})
		_file.flush()
	_frame(t)
	_events(t)


## The world's own session (kind 0), or null.
func _session() -> RefCounted:
	for r: RefCounted in _rows(&"session"):
		if int(r.get(&"kind")) == 0:
			return r
	return null


## Begin writing round `rnd` of session `sid`: a new file, its first line saying what it is.
func start(sid: int, rnd: int) -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	prune(KEEP)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_path = "%s/%s_w%d_s%d_r%d.jsonl" % [DIR, stamp, world_id, sid, rnd]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("[Recorder] could not write %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return
	_session_id = sid
	_round = rnd
	_phase = -1
	if level_of.is_valid():
		level_path = String(level_of.call())
	_t0 = _now()
	_frames = 0
	_statuses.clear()
	_seen_actions.clear()
	_seen_noises.clear()
	_seen_holds.clear()
	# What is already there is not news (events from the lobby, a noise just before).
	for r: RefCounted in _rows(&"action_event"):
		_seen_actions[int(r.get(&"id"))] = true
	for r: RefCounted in _rows(&"noise"):
		_seen_noises[int(r.get(&"id"))] = true
	for r: RefCounted in _rows(&"status_state"):
		_statuses[int(r.get(&"entity_id"))] = int(r.get(&"status"))
	var kinds: Dictionary = {}
	for k: Variant in kind_names:
		kinds[str(k)] = kind_names[k]
	var names: Dictionary = {}
	for r: RefCounted in _rows(&"player"):
		names[str(int(r.get(&"entity_id")))] = String(r.get(&"name"))
	_line({"recording": FORMAT, "world": world_id, "session": sid, "round": rnd, "level": level_path,
		"started": Time.get_unix_time_from_system(), "kinds": kinds, "names": names})
	print("[Recorder] recording round %d of session %d to %s" % [rnd, sid, ProjectSettings.globalize_path(_path)])


## Delete all but the newest `keep` recordings (their names sort by when they were made).
static func prune(keep: int) -> int:
	var d: DirAccess = DirAccess.open(DIR)
	if d == null:
		return 0
	var files: Array = Array(d.get_files()).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))
	files.sort()
	var gone: int = 0
	while files.size() > keep:
		d.remove(String(files.pop_front()))
		gone += 1
	return gone


## Close the round's file (its last frame written).
func stop() -> void:
	if _file == null:
		return
	_file.close()
	_file = null
	written.append(_path)
	print("[Recorder] round %d recorded: %d frames, %s" % [_round, _frames, ProjectSettings.globalize_path(_path)])
	_session_id = -1
	_round = -1


func _frame(t: float) -> void:
	var kinds: Dictionary = {}
	for r: RefCounted in _rows(&"entity"):
		kinds[int(r.get(&"entity_id"))] = int(r.get(&"kind"))
	var statuses: Dictionary = {}
	for r: RefCounted in _rows(&"status_state"):
		statuses[int(r.get(&"entity_id"))] = int(r.get(&"status"))
	var e: Array = []
	for r: RefCounted in _rows(&"movement_state"):
		var id: int = int(r.get(&"entity_id"))
		var p: Vector3 = r.get(&"pos")
		e.append([id, int(kinds.get(id, 0)), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(float(r.get(&"yaw")), 0.01), int(statuses.get(id, 0))])
	_line({"t": t, "e": e})
	_frames += 1
	if _frames % 10 == 0:
		_file.flush()   # a second at a time on disk: a round still going can be read (and survives a crash)


func _events(t: float) -> void:
	for r: RefCounted in _rows(&"status_state"):
		var id: int = int(r.get(&"entity_id"))
		var to: int = int(r.get(&"status"))
		var from: int = int(_statuses.get(id, 0))
		if to != from:
			_line({"t": t, "ev": "status", "id": id, "from": from, "to": to})
		_statuses[id] = to
	for r: RefCounted in _rows(&"action_event"):
		var id: int = int(r.get(&"id"))
		if _seen_actions.has(id):
			continue
		_seen_actions[id] = true
		_line({"t": t, "ev": "action", "actor": int(r.get(&"actor_id")), "ability": int(r.get(&"ability_id")),
			"target": int(r.get(&"target_id")), "outcome": int(r.get(&"outcome"))})
	for r: RefCounted in _rows(&"noise"):
		var id: int = int(r.get(&"id"))
		if _seen_noises.has(id):
			continue
		_seen_noises[id] = true
		var p: Vector3 = r.get(&"pos")
		_line({"t": t, "ev": "noise", "kind": int(r.get(&"kind")), "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
			"source": int(r.get(&"source_id")), "target": int(r.get(&"target_id"))})
	for r: RefCounted in _rows(&"hold_progress"):
		var id: int = int(r.get(&"hold_id"))
		if int(r.get(&"state")) != 1 or _seen_holds.has(id):
			continue
		_seen_holds[id] = true
		_line({"t": t, "ev": "hold", "hold": int(r.get(&"hold")), "target": int(r.get(&"entity_id")), "doers": int(r.get(&"doers"))})
	# WHAT EACH BOT DECIDED (Luke, after watching bot hens "go back and forth without clear directions and
	# goals"): its brain's step whenever it changes, and its goal whenever it jumps somewhere new (not a
	# goal that moves with what it follows).
	for b: Array in _brains():
		var id: int = int(b[0])
		var state: String = String(b[1])
		var goal: Variant = b[2]
		var was: Array = _brain_seen.get(id, ["", null])
		var jumped: bool = goal is Vector3 and (not (was[1] is Vector3) or (goal as Vector3).distance_to(was[1] as Vector3) > GOAL_JUMP_M)
		if state != String(was[0]) or jumped or (goal == null) != (was[1] == null):
			var g: Variant = [snappedf((goal as Vector3).x, 0.1), snappedf((goal as Vector3).z, 0.1)] if goal is Vector3 else null
			_line({"t": t, "ev": "brain", "id": id, "state": state, "goal": g})
			_brain_seen[id] = [state, goal]


## [entity id, its brain's state, its goal (null: none)] for every bot this sidecar drives.
func _brains() -> Array:
	if brains_of.is_valid():
		return brains_of.call() as Array
	var out: Array = []
	for n: Node in EntitySpawner.entity_nodes():
		var e: SpaceTimeEntity = n as SpaceTimeEntity
		var c: NpcBrainComponent = e.find_component(NpcBrainComponent) as NpcBrainComponent if e != null else null
		if c != null and c.brain != null:
			out.append([e.entity_id, c.brain.state, c.brain.goal() if c.brain.has_goal() else null])
	return out


func _scores(sid: int) -> Dictionary:
	var out: Dictionary = {}
	for r: RefCounted in _rows(&"session_member"):
		if int(r.get(&"session_id")) == sid:
			out[str(int(r.get(&"entity_id")))] = int(r.get(&"score"))
	return out


func _line(d: Dictionary) -> void:
	if _file != null:
		_file.store_line(JSON.stringify(d))
