extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fight` suite (`-- --only=fight` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	_run_fight_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## THE FIGHT'S TWIN (DECISIONS #140). The client plays the fight for feel; the module replays the
## inputs through `genre::fight` to decide what happened. So `FightSim` must BE that simulation:
## every field, as the bytes of its f64, at every checkpoint of every scripted fight in
## `shared/golden/fishing/fight.json` (written by `server/tests/fight.rs`). Not close — equal. A
## difference of one bit here is a catch the client showed landing and the server says snapped.
func _run_fight_tests() -> void:
	print("== the fight: FightSim against genre::fight ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/fishing/fight.json", FileAccess.READ)
	_check(f != null, "the fight's golden file is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var hex := func(v: float) -> String: return PackedFloat64Array([v]).to_byte_array().hex_encode()
	# THE NUMBERS FIRST: both sides must have read the same file into the same bits.
	var base: FightSim.Params = FightSim.base_params()
	var consts: Dictionary = doc.get("constants", {}) as Dictionary
	var wrong_consts: Array[String] = []
	for k: String in consts:
		var v: float = FightSim.dt() if k == "dt" else float(base.get(k))
		if hex.call(v) != str(consts[k]):
			wrong_consts.append(k)
	_check(consts.size() >= 5 and wrong_consts.is_empty(),
		"fight.json and the fixed step read to the module's exact bits (%s)" % str(wrong_consts))

	var hooksets: Dictionary[String, FishingData.HookSet] = {"perfect": FishingData.HookSet.PERFECT,
		"good": FishingData.HookSet.GOOD, "late": FishingData.HookSet.LATE}
	var cases: Array = doc.get("cases", []) as Array
	var tally: Array[int] = [0]   # values compared; an array so the helper can count into it
	var first_bad: String = ""
	var bad_cases: Array[String] = []
	var outcomes: Dictionary[int, int] = {}
	for c: Variant in cases:
		var d: Dictionary = c as Dictionary
		var params: FightSim.Params = FightSim.params_for(int(d["rod"]), int(d["reel"]), int(d["line"]),
			hooksets[str(d["hookset"])], bool(d["deadlift"]))
		var prof: FightSim.Profile = FightSim.profile_of(str(d["catch"]))
		if prof == null:
			bad_cases.append("%s: no profile for %s" % [d["name"], d["catch"]])
			continue
		var sim := FightSim.new(params, prof, int(d["seed"]), float(d["cast_cm"]) / 100.0, true)
		var checks: Array = d["checks"] as Array
		var k: int = 0
		var mismatch: String = ""
		for r: Variant in d["runs"] as Array:
			var run: Array = r as Array
			for i: int in range(int(run[0])):
				sim.tick(int(run[1]) & 1 != 0, int(run[1]) & 2 != 0, int(run[2]))
				while mismatch.is_empty() and k < checks.size() 						and int((checks[k] as Dictionary)["tick"]) == sim.ticks:
					mismatch = _fight_mismatch(sim, checks[k] as Dictionary, tally)
					k += 1
		# The last checkpoint is the end state, taken after the fight was decided.
		while mismatch.is_empty() and k < checks.size():
			mismatch = _fight_mismatch(sim, checks[k] as Dictionary, tally)
			k += 1
		if not mismatch.is_empty():
			bad_cases.append(str(d["name"]))
			if first_bad.is_empty():
				first_bad = "%s %s" % [d["name"], mismatch]
		outcomes[sim.state] = outcomes.get(sim.state, 0) + 1
		# The static replay the client submits through reaches the same place.
		var again: FightSim = FightSim.replay(params, prof, int(d["seed"]), float(d["cast_cm"]) / 100.0,
			d["runs"] as Array)
		if again.ticks != sim.ticks or again.state != sim.state:
			bad_cases.append("%s: replay() ended at %d/%d, ticking at %d/%d" % [d["name"], again.ticks,
				again.state, sim.ticks, sim.state])
	var compared: int = tally[0]
	print("   %d cases, %d values compared" % [cases.size(), compared])
	_check(cases.size() >= 10 and bad_cases.is_empty(),
		"every scripted fight plays out in GDScript exactly as in the module, max_err = 0 (%s; first: %s)"
			% [str(bad_cases), first_bad])
	_check(compared > 5000, "and that is thousands of values, not a handful (%d)" % compared)
	_check(outcomes.get(FightSim.State.LANDED, 0) >= 5 and outcomes.get(FightSim.State.SNAPPED, 0) >= 2,
		"the cases land catches and snap lines both (%s)" % str(outcomes))

	# Every catch the roll can hand out has a fight.
	var missing: Array[String] = []
	for c: Variant in FishingData.doc().get("catches", []) as Array:
		var id: String = str((c as Dictionary)["id"])
		if FightSim.profile_of(id) == null:
			missing.append(id)
	_check(missing.is_empty(), "every catch in the catalogue has a fight profile (%s)" % str(missing))

	# THE LOG, as it rides in submit_challenge_result.
	var runs: Array[PackedInt32Array] = [PackedInt32Array([12, 0, 0]), PackedInt32Array([90, 1, 0]),
		PackedInt32Array([40, 0, 255])]
	_check(FightSim.encode_log(runs) == [3.0, 12.0, 0.0, 0.0, 90.0, 1.0, 0.0, 40.0, 0.0, 255.0],
		"the log encodes as [n, (ticks, flags, crank) x n] (%s)" % str(FightSim.encode_log(runs)))


## "" when every field of `sim` has the bytes `want` has; otherwise which field, where.
func _fight_mismatch(sim: FightSim, want: Dictionary, tally: Array[int]) -> String:
	for pair: Array in sim.snapshot():
		tally[0] += 1
		var got: String = PackedFloat64Array([float(pair[1])]).to_byte_array().hex_encode()
		if got != str(want.get(pair[0], "")):
			return "at tick %d: %s is %s (%s), the module has %s" % [sim.ticks, pair[0], str(pair[1]), got,
				str(want.get(pair[0], "missing"))]
	return ""
