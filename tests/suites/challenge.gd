extends "res://tests/suite_base.gd"
## The `challenge` suite (tests/test_runner.gd runs it; `-- --only=challenge` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_challenge_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- ChallengeModel parity (Phase 3 Task 1) -------------------------------------------

const CHALLENGE_GOLDEN: String = "res://shared/golden/challenge/challenge_timing.json"


## Rebuild the u64 seed from the 32-bit halves the golden file stores. A u64 above 2^53 cannot
## survive JSON -> float -> int, which is why the file does not carry it as one number.
static func _join_seed(hi: int, lo: int) -> int:
	return ((hi & ChallengeModel.M32) << 32) | (lo & ChallengeModel.M32)


func _run_challenge_tests() -> void:
	print("== ChallengeModel ==")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHALLENGE_GOLDEN))
	if not doc is Dictionary:
		_check(false, "cannot read " + CHALLENGE_GOLDEN)
		return
	var tol: float = float(doc.get("tolerance", 1e-5))
	print("  %s (model=%s, %d cases, %d rejects)" % [
		doc["name"], doc["model_version"], doc["cases"].size(), doc["rejects"].size()])

	for c: Dictionary in doc["cases"]:
		var seed_value: int = _join_seed(int(c["seed_hi"]), int(c["seed_lo"]))
		var difficulty: float = _f32(float(c["difficulty"]))
		var worst: float = 0.0

		var centers: Vector3 = ChallengeModel.timing_centers(seed_value)
		var exp_c: Array = c["expected_centers"]
		worst = maxf(worst, absf(centers.x - _f32(float(exp_c[0]))))
		worst = maxf(worst, absf(centers.y - _f32(float(exp_c[1]))))
		worst = maxf(worst, absf(centers.z - _f32(float(exp_c[2]))))

		var half: float = ChallengeModel.timing_half_width(difficulty)
		worst = maxf(worst, absf(half - _f32(float(c["expected_half_width"]))))

		var result: PackedFloat32Array = PackedFloat32Array()
		for v: float in c["result"]:
			result.append(v)
		var quality: float = ChallengeModel.validate_challenge(
			int(c["kind"]), seed_value, difficulty, result)
		_check(quality >= 0.0, "%s: validator rejected a valid case" % c["name"])
		worst = maxf(worst, absf(quality - _f32(float(c["expected_quality"]))))

		var ok: bool = worst <= tol
		_check(ok, "%s: quality %f expected %f" % [c["name"], quality, _f32(float(c["expected_quality"]))])
		# Parity means bit-equality, not "within tolerance" (AGENTS rule 7).
		_check(worst == 0.0, "%s: drifted from the golden vector by %s" % [c["name"], _sci(worst)])
		print("    %-24s %s  max_err=%s" % [c["name"], "ok " if ok else "BAD", _sci(worst)])

	for r: Dictionary in doc["rejects"]:
		var rresult: PackedFloat32Array = PackedFloat32Array()
		for v: float in r["result"]:
			rresult.append(v)
		var got: float = ChallengeModel.validate_challenge(
			int(r["kind"]),
			_join_seed(int(r["seed_hi"]), int(r["seed_lo"])),
			_f32(float(r["difficulty"])),
			rresult)
		_check(got < 0.0, "%s: malformed submission was accepted (%f)" % [r["name"], got])

	# Sanity: the validator must actually read the player's input.
	var s: int = 4242
	var cen: Vector3 = ChallengeModel.timing_centers(s)
	var perfect_in: PackedFloat32Array = PackedFloat32Array([cen.x, cen.y, cen.z])
	var off_in: PackedFloat32Array = PackedFloat32Array([
		minf(cen.x + 0.05, 1.0), minf(cen.y + 0.05, 1.0), minf(cen.z + 0.05, 1.0)])
	var perfect: float = ChallengeModel.validate_challenge(0, s, 0.5, perfect_in)
	var worse: float = ChallengeModel.validate_challenge(0, s, 0.5, off_in)
	_check(perfect > worse, "accuracy must change quality (%f vs %f)" % [perfect, worse])
	_check(absf(perfect - 1.0) < 1e-6, "hitting every centre scores 1.0, got %f" % perfect)
