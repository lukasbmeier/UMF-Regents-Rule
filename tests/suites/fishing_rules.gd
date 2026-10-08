extends "res://tests/suite_base.gd"
## The `fishing_rules` suite (tests/test_runner.gd runs it; `-- --only=fishing_rules` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_fishing_rules_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine


## THE HOOK-SET TWIN (DECISIONS #136). The client grades a press the instant it is made, a round
## trip before the module's verdict, so its grade has to BE the module's: the same f32 rounding,
## the same thresholds, from the same file. Both run the NumPy-generated golden cases
## (tools/fishing/gen_goldens.py); `server/tests/fishing.rs` is the other half.
func _run_fishing_rules_tests() -> void:
	print("== fishing rules: the hook-set twin ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/fishing/hookset.json", FileAccess.READ)
	_check(f != null, "the hook-set golden file is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var grades: Dictionary[String, int] = {"none": FishingData.HookSet.NONE,
		"perfect": FishingData.HookSet.PERFECT, "good": FishingData.HookSet.GOOD,
		"late": FishingData.HookSet.LATE}
	var cases: Array = doc.get("cases", []) as Array
	var wrong: Array[String] = []
	var seen: Dictionary[int, bool] = {}
	for c: Variant in cases:
		var d: Dictionary = c as Dictionary
		var want: int = grades[str(d["grade"])]
		var got: int = FishingData.grade_hookset(float(d["reaction"]), float(d["window_mult"]))
		seen[want] = true
		if got != want:
			wrong.append("%s @x%s -> %s, want %s" % [str(d["reaction"]), str(d["window_mult"]), got, want])
	_check(cases.size() >= 100 and wrong.is_empty(),
		"every one of the %d golden reactions is graded exactly as the module grades it (%s)"
			% [cases.size(), str(wrong.slice(0, 4))])
	_check(seen.size() == 4, "and the cases cover all four grades (%d)" % seen.size())
	_check(FishingData.grade_hookset(NAN, 1.0) == FishingData.HookSet.NONE
			and FishingData.grade_hookset(INF, 1.0) == FishingData.HookSet.NONE,
		"a reaction that is not a number sets no hook")
	# The windows the HUD draws are the ones the grades come from.
	var perfect: float = FishingData.timing("hookset_perfect_s")
	var late: float = FishingData.timing("hookset_late_s")
	_check(FishingData.timing("min_reaction_s") < perfect and perfect < late
			and late < FishingData.hookset_window(1.0),
		"too fast < perfect < good < late < the window, in the shared file")
	_check(FishingData.hookset_window(FishingData.hookset_window_mult(FishingData.max_tier()))
			> FishingData.hookset_window(1.0), "and a better reel widens the window")
