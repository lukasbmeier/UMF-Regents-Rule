extends "res://tests/suite_base.gd"
## The `record` suite (DECISIONS #235): a recording of every round, and playing one back.
##   - nothing is written in the lobby; a round leaving it starts a file, its first line saying what it is
##   - where everyone was, each frame; what happened: statuses, uses, holds done, noises, the phases, the
##     standings as results come; the round back in the lobby closes it
##   - the viewer reads it back: where everyone was at any moment (between frames), and what each
##     event says in words
##   - only the newest recordings are kept
## That a real referee writes one through a real night: game/chicken/tests/night_playtest.sh.


class Row extends RefCounted:
	var d: Dictionary
	func _init(p: Dictionary) -> void:
		d = p
	func _get(property: StringName) -> Variant:
		return d.get(String(property))


var _tables: Dictionary = {}
var _now: float = 100.0


func run() -> void:
	_run_recording()
	_run_viewer()
	_run_prune()
	await get_tree().process_frame


func _set_rows(table: StringName, rows: Array[Dictionary]) -> void:
	var out: Array = []
	for r: Dictionary in rows:
		out.append(Row.new(r))
	_tables[table] = out


func _session(phase: int, rnd: int = 3) -> void:
	_set_rows(&"session", [{"id": 7, "world_id": 0, "kind": 0, "phase": phase, "round": rnd}])


func _lines(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var l: String = f.get_line()
		if not l.is_empty():
			out.append(JSON.parse_string(l) as Dictionary)
	return out


var _path: String = ""


func _run_recording() -> void:
	print("== record: a round written down ==")
	var rec := SessionRecorder.new()
	rec.world_id = 0
	rec.level_path = "res://tests/levels/greybox.tscn"
	rec.kind_names = {100: "Hen", 101: "Wolf"}
	rec.rows_of = func(t: StringName) -> Array: return _tables.get(t, [])
	rec.clock = func() -> float: return _now
	var brains: Array = []
	rec.brains_of = func() -> Array: return brains
	add_child(rec)
	rec.set_process(false)
	_set_rows(&"entity", [{"entity_id": 1, "world_id": 0, "kind": 100}, {"entity_id": 2, "world_id": 0, "kind": 101}])
	_set_rows(&"movement_state", [{"entity_id": 1, "world_id": 0, "pos": Vector3(1, 0, 2), "yaw": 0.5}, {"entity_id": 2, "world_id": 0, "pos": Vector3(5, 0, 5), "yaw": 0.0}])
	_set_rows(&"player", [{"entity_id": 1, "name": "Luke"}])
	_set_rows(&"action_event", [{"id": 40, "world_id": 0, "actor_id": 2, "ability_id": 9, "target_id": 0, "outcome": 1}])
	_set_rows(&"noise", [])
	_set_rows(&"status_state", [])
	_set_rows(&"hold_progress", [])
	_set_rows(&"session_member", [{"session_id": 7, "entity_id": 1, "score": 4}, {"session_id": 7, "entity_id": 2, "score": 9}, {"session_id": 8, "entity_id": 3, "score": 1}])
	_session(0)
	rec.tick()
	_check(not rec.is_recording(), "in the lobby: nothing written")
	_session(1)
	brains.assign([[2, "patrol", Vector3(0, 0, 0)]])
	rec.tick()
	_path = rec.path()
	_check(rec.is_recording() and _path.begins_with(SessionRecorder.DIR) and _path.ends_with("_w0_s7_r3.jsonl"), "the round starts: a file for it (%s)" % _path.get_file())
	_now = 100.5
	_set_rows(&"status_state", [{"entity_id": 1, "world_id": 0, "status": 1}])
	_set_rows(&"action_event", [{"id": 40, "world_id": 0, "actor_id": 2, "ability_id": 9, "target_id": 0, "outcome": 1},
		{"id": 41, "world_id": 0, "actor_id": 2, "ability_id": 10000, "target_id": 1, "outcome": 0}])
	_set_rows(&"noise", [{"id": 5, "world_id": 0, "kind": 100, "pos": Vector3(3, 0, 3), "source_id": 1, "target_id": 12}])
	_set_rows(&"hold_progress", [{"hold_id": 9, "world_id": 0, "entity_id": 12, "hold": 10001, "state": 1, "doers": 2}])
	_set_rows(&"movement_state", [{"entity_id": 1, "world_id": 0, "pos": Vector3(2, 0, 2), "yaw": 0.5}, {"entity_id": 2, "world_id": 0, "pos": Vector3(4, 0, 4), "yaw": 0.0}])
	brains.assign([[2, "patrol", Vector3(1, 0, 0)]])   # the same goal, moved a metre: no new decision
	rec.tick()
	brains.assign([[2, "chase", Vector3(1, 0, 0)]])
	rec.tick()   # nothing new but the bot's step: written once
	_now = 101.0
	_session(2)
	brains.assign([[2, "chase", Vector3(10, 0, 0)]])   # its goal somewhere else: a new decision
	rec.tick()
	_session(0, 4)
	rec.tick()
	_check(not rec.is_recording() and rec.written.has(_path), "back in the lobby: the file closed")
	var lines: Array[Dictionary] = _lines(_path)
	var head: Dictionary = lines[0] if not lines.is_empty() else {}
	_check(int(head.get("recording", 0)) == SessionRecorder.FORMAT and int(head.get("session", -1)) == 7 and int(head.get("round", -1)) == 3
		and String(head.get("level", "")) == "res://tests/levels/greybox.tscn" and String((head.get("kinds", {}) as Dictionary).get("100", "")) == "Hen"
		and String((head.get("names", {}) as Dictionary).get("1", "")) == "Luke",
		"its first line: the round, the level, what each kind is called, who each player is")
	var frames: Array = lines.filter(func(l: Dictionary) -> bool: return l.has("e"))
	var evs: Array = lines.filter(func(l: Dictionary) -> bool: return l.has("ev"))
	_check(frames.size() == 4, "a frame each step of the round (%d)" % frames.size())
	var second: Array = (frames[1] as Dictionary)["e"] if frames.size() > 1 else []
	_check(second.size() == 2 and is_equal_approx(float(second[0][2]), 2.0) and int(second[0][1]) == 100 and int(second[0][6]) == 1,
		"each one: id, kind, where, facing, status (%s)" % str(second))
	var kinds: Array = evs.map(func(e: Dictionary) -> String: return String(e["ev"]))
	_check(kinds.count("status") == 1 and kinds.count("action") == 1 and kinds.count("noise") == 1 and kinds.count("hold") == 1,
		"what happened, once each: a status, a use (not the one from before the round), a noise, a hold done (%s)" % str(kinds))
	var standings: Array = evs.filter(func(e: Dictionary) -> bool: return e["ev"] == "standings")
	_check(kinds.has("phase") and standings.size() == 1 and int((standings[0]["scores"] as Dictionary).get("2", -1)) == 9
		and not (standings[0]["scores"] as Dictionary).has("3"), "the results: the phase, and this session's standings")
	var decided: Array = evs.filter(func(e: Dictionary) -> bool: return e["ev"] == "brain")
	_check(decided.size() == 3 and String(decided[0]["state"]) == "patrol" and String(decided[1]["state"]) == "chase"
		and is_equal_approx(float((decided[2]["goal"] as Array)[0]), 10.0) and int(decided[0]["id"]) == 2,
		"what each bot decided: its step as it changes, its goal as it jumps, not as it moves a metre (%s)" % str(decided.map(func(e: Dictionary) -> String: return "%s %s" % [e["state"], str(e["goal"])])))
	var act: Array = evs.filter(func(e: Dictionary) -> bool: return e["ev"] == "action")
	_check(not act.is_empty() and is_equal_approx(float(act[0]["t"]), 0.5), "times from the round's start (%.1f s)" % (float(act[0]["t"]) if not act.is_empty() else -1.0))
	rec.queue_free()


func _run_viewer() -> void:
	print("== record: played back ==")
	var r: Dictionary = preload("res://tools/replay/replay_viewer.gd").read(_path)
	var frames: Array[Dictionary] = r["frames"]
	_check(int((r["header"] as Dictionary).get("session", -1)) == 7 and frames.size() == 4 and (r["events"] as Array).size() >= 5,
		"the viewer reads it: the round, %d frames, %d events" % [frames.size(), (r["events"] as Array).size()])
	var viewer: Script = preload("res://tools/replay/replay_viewer.gd")
	var mid: Dictionary = viewer.state_at(frames, 0.25)
	_check(mid.has(1) and (mid[1][1] as Vector3).is_equal_approx(Vector3(1.5, 0, 2)), "half way between two frames: half way between where they were (%s)" % str(mid.get(1, [])))
	var late: Dictionary = viewer.state_at(frames, 999.0)
	_check(late.has(1) and (late[1][1] as Vector3).is_equal_approx(Vector3(2, 0, 2)), "after the end: where they ended")
	var hit: Dictionary = (r["events"] as Array).filter(func(e: Dictionary) -> bool: return e["ev"] == "action")[0]
	_check(viewer.describe(hit, r["header"]).contains("hit") and viewer.describe(hit, r["header"]).contains("Luke"), "an event in words, with the names: \"%s\"" % viewer.describe(hit, r["header"]))
	DirAccess.remove_absolute(_path)


func _run_prune() -> void:
	print("== record: only the newest kept ==")
	if not DirAccess.dir_exists_absolute(SessionRecorder.DIR):
		DirAccess.make_dir_recursive_absolute(SessionRecorder.DIR)
	var mine: Array[String] = []
	for i: int in 3:
		var p: String = "%s/0000-test-%d.jsonl" % [SessionRecorder.DIR, i]
		FileAccess.open(p, FileAccess.WRITE).store_line("{}")
		mine.append(p)
	var before: int = preload("res://tools/replay/replay_viewer.gd").list_recordings().size()
	var gone: int = SessionRecorder.prune(before - 2)
	_check(gone == 2 and not FileAccess.file_exists(mine[0]) and not FileAccess.file_exists(mine[1]) and FileAccess.file_exists(mine[2]),
		"the oldest go first (these sort before any real recording's date)")
	DirAccess.remove_absolute(mine[2])
