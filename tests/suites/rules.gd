extends "res://tests/suite_base.gd"
## The `rules` suite (tests/test_runner.gd runs it; `-- --only=rules` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_rules_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## THE FOUNDATION'S RULES ARE DATA (DECISIONS #154): `shared/rules.json`, read by the client here
## and compiled into the module by build.rs. The integration suite proves the module took the
## same numbers; this proves the client reads them and the build reads the same file.
func _run_rules_tests() -> void:
	print("== rules: shared/rules.json ==")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Rules.PATH)) as Dictionary
	_check(raw != null and raw.has("sessions"), "shared/rules.json parses")
	if raw == null:
		return
	# Moved to hot rules (DECISIONS #201): build.rs refuses a rules.json that still sets them.
	_check(not raw.has("player") and not raw.has("interact_range_m"),
		"a new player's health and the interact range are not in it: they are hot rules")
	var hot: Dictionary = HotRules.defaults()
	_check(is_equal_approx(Rules.max_health(), float((hot["foundation.new_player_health"] as Dictionary)["number"]))
			and is_equal_approx(Rules.interact_range(), float((hot["foundation.interact_range_m"] as Dictionary)["number"])),
		"Rules reads them from the hot rules (%s, %s m)" % [Rules.max_health(), Rules.interact_range()])
	var names: Array[String] = []
	var total: float = 0.0
	for p: Variant in Rules.phases(0):
		names.append(Rules.phase_name(0, int((p as Dictionary)["phase"])))
		total += Rules.phase_seconds(0, int((p as Dictionary)["phase"]))
	# The file's own plan for kind 0 (a game sets its own: Fowl Play's night is lobby, night, dawn, results).
	var file_names: Array[String] = []
	var file: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/rules.json"))
	for kind: Variant in ((file as Dictionary).get("sessions", []) as Array) if file is Dictionary else []:
		if int((kind as Dictionary).get("kind", -1)) == 0:
			for ph: Variant in (kind as Dictionary).get("phases", []):
				file_names.append(String((ph as Dictionary)["name"]))
	_check(not names.is_empty() and names == file_names and total > 0.0,
		"session kind 0 goes round its phases in the file's order: %s (%.0f s a round)" % [", ".join(names), total])
	_check(Rules.phase_name(0, 42).is_empty() and Rules.phases(77).is_empty() and is_zero_approx(Rules.phase_seconds(77, 1)),
		"a phase or a kind the file does not plan has no name and no length")
	_check(FileAccess.get_file_as_string("res://server/build.rs").contains("../shared/rules.json"),
		"and the server's build compiles the same file in")
	# THE DATABASE: the test suites set UMF_DB, people do not.
	var cfg := NetConfig.new()
	var was: String = OS.get_environment("UMF_DB")
	OS.unset_environment("UMF_DB")
	var plain: String = SpaceTimeSync.database_name(cfg)
	OS.set_environment("UMF_DB", "umf_probe")
	var steered: String = SpaceTimeSync.database_name(cfg)
	if was.is_empty():
		OS.unset_environment("UMF_DB")
	else:
		OS.set_environment("UMF_DB", was)
	# The game's database (shared/game.json, DECISIONS #195); the config's only when the game names none.
	var game_db: String = str(Genres.game().get("database", cfg.module_name))
	_check(plain == game_db and steered == "umf_probe",
		"a client joins the game's database (%s, wanted %s), or the one UMF_DB names (%s)" % [plain, game_db, steered])
