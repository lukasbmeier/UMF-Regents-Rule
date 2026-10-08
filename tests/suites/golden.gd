extends "res://tests/suite_base.gd"
## The `golden` suite (tests/test_runner.gd runs it; `-- --only=golden` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_golden_vectors()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine

## Headless test runner. No framework dependency. Golden vectors here are GDScript regression
## tests for movement_model.gd (the live model shared by client and sidecar).
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 on success, 1 on any failure. Add new suites to _run_all().
##
## This is a SCENE, not a `--script` runner, and that is deliberate. `--script` compiles the
## runner (and every script it names as a type) BEFORE the autoloads are registered, so any
## foundation script that references `SignalBus` or `EntityRegistry` fails with
## "Identifier not found" the moment a test annotates a variable with its class. Running as a
## scene puts the harness in the same startup order as the real game, which also means the
## foundation stays free to use autoloads the idiomatic way.

const GOLDEN_DIR: String = "res://shared/golden/movement/"


# --- golden vectors --------------------------------------------------------------

func _run_golden_vectors() -> void:
	print("== golden vectors ==")
	var dir: DirAccess = DirAccess.open(GOLDEN_DIR)
	if dir == null:
		_check(false, "cannot open " + GOLDEN_DIR)
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			_run_golden_file(GOLDEN_DIR + file)


func _run_golden_file(path: String) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		_check(false, "bad JSON: " + path)
		return
	var cfg: MovementConfig = MovementConfig.from_dict(doc["config"])
	var dt: float = float(doc["dt"])
	var tol: float = float(doc.get("tolerance", 1e-5))
	# Files regenerated since the model started classifying movement (PHASE4_SPEC §2.5) assert
	# move_state too. Neither harness used to compare it, so a wrong one could never fail.
	var check_ms: bool = bool(doc.get("asserts_move_state", false))
	print("  %s (model=%s, %d cases)" % [doc["name"], doc["model_version"], doc["cases"].size()])

	for c: Dictionary in doc["cases"]:
		var s: MovementState = MovementState.from_dict(c["initial"])
		var expected_at: Dictionary = c.get("expected_at", {})
		var worst: float = 0.0
		var inputs: Array = c["inputs"]
		for i in inputs.size():
			s = MovementModel.simulate(s, InputFrame.from_dict(inputs[i]), cfg, dt)
			var key: String = str(i)
			if expected_at.has(key):
				var exp_i: MovementState = MovementState.from_dict(expected_at[key])
				worst = maxf(worst, s.max_error(exp_i))
				_check(s.approx_equals(exp_i, tol), "%s @frame %d: got %s expected %s" % [c["name"], i, s, exp_i])
				if check_ms:
					_check(s.move_state == exp_i.move_state, "%s @frame %d: move_state %d, expected %d"
						% [c["name"], i, s.move_state, exp_i.move_state])
		var exp: MovementState = MovementState.from_dict(c["expected_final"])
		worst = maxf(worst, s.max_error(exp))
		var ok: bool = s.approx_equals(exp, tol) and (not check_ms or s.move_state == exp.move_state)
		_check(ok, "%s final: got %s (move_state %d) expected %s (move_state %d)"
			% [c["name"], s, s.move_state, exp, exp.move_state])
		print("    %-28s %s  max_err=%s" % [c["name"], "ok " if ok else "BAD", _sci(worst)])
