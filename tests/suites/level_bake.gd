extends "res://tests/suite_base.gd"
## The `level_bake` suite (tests/test_runner.gd runs it; `-- --only=level_bake` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_level_bake_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- LevelBake parity (server/src/level.rs) -----------------------------------------------

const PROBE_DIR: String = "res://shared/golden/level/"

## The client's answer to "is that water, which spot, may I stand here" must be the server's,
## point for point, for EVERY baked level (`<level>_probes.json`); the Rust twin runs the same
## files (`cargo test --test level`). A level's own facts are its game's suites' (fishing's lakeside).
func _run_level_bake_tests() -> void:
	print("== LevelBake ==")
	var checked: int = 0
	for f: String in DirAccess.get_files_at(PROBE_DIR):
		if not f.ends_with("_probes.json"):
			continue
		var level_name: String = f.trim_suffix("_probes.json")
		if not FileAccess.file_exists(LevelBake.DIR + level_name + ".json"):
			continue
		_check_probes(PROBE_DIR + f)
		checked += 1
	_check(checked >= 1 and FileAccess.file_exists(PROBE_DIR + "example_probes.json"),
		"the example level's probes were checked (%d levels)" % checked)
	# The foundation's example level (level 200): the pond is water, its shore is not.
	var bake: LevelBake = LevelBake.load_level("example")
	_check(bake != null, "the example bake loads")
	if bake == null:
		return
	_check(not bake.is_water(bake.spawn.x, bake.spawn.z) and bake.can_stand(bake.spawn.x, bake.spawn.z),
		"players arrive on dry land they may stand on")
	_check(bake.is_water(0.0, -10.0) and not bake.can_stand(0.0, -10.0) and bake.spot_at(0.0, -10.0).get("id", "") == "example_pond",
		"the pond's middle is water too deep to stand in, and it is the Example Pond")
	# NaN fails every comparison: without its guard it would index a real cell.
	_check(bake.cell(NAN, 0.0) == Vector2i(-1, -1) and bake.cell(0.0, NAN) == Vector2i(-1, -1),
		"a NaN position is off the grid, not cell zero")
	_check(bake.depth_dm_at(INF, 0.0) == 0, "infinity is dry land")


func _check_probes(path: String) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:
		_check(false, "cannot read " + path)
		return
	var bake: LevelBake = LevelBake.load_level(str(doc["level"]))
	_check(bake != null, "the %s bake loads, grid and all" % str(doc["level"]))
	if bake == null:
		return
	var probes: Array = doc["probes"] as Array
	var mismatches: int = 0
	var wet: int = 0
	var deep: int = 0
	for item: Variant in probes:
		var probe: Dictionary = item as Dictionary
		# Through a Vector3, as the client holds positions: its components are f32, and the probes
		# are f32 values that Godot's JSON parser can hand back one f64 ULP out (see `_f32`).
		var v := Vector3(float(probe["x"]), 0.0, float(probe["z"]))
		var c: Vector2i = bake.cell(v.x, v.z)
		var want_cell: Variant = probe["cell"]
		var cell_ok: bool = c == Vector2i(-1, -1) if want_cell == null \
			else c == Vector2i(int((want_cell as Array)[0]), int((want_cell as Array)[1]))
		var spot: Dictionary = bake.spot_at(v.x, v.z)
		var spot_id: Variant = null if spot.is_empty() else spot["id"]
		var water: bool = bake.is_water(v.x, v.z)
		var stand: bool = bake.can_stand(v.x, v.z)
		if water:
			wet += 1
		if not stand:
			deep += 1
		if not (cell_ok and bake.depth_dm_at(v.x, v.z) == int(probe["depth_dm"])
				and water == bool(probe["is_water"]) and spot_id == probe["spot"] and stand == bool(probe["can_stand"])):
			mismatches += 1
			printerr("  level probe %s (%s, %s): cell=%s dm=%d water=%s spot=%s stand=%s; want %s" % [
				probe["name"], v.x, v.z, c, bake.depth_dm_at(v.x, v.z), water, spot_id, stand, probe])
	print("  %s: %d probes, %d over water" % [doc["level"], probes.size(), wet])
	_check(mismatches == 0, "every %s probe matches the Rust twin (%d mismatches)" % [doc["level"], mismatches])
	_check(wet > 0 and wet < probes.size(), "the %s probes cover both water and land" % doc["level"])
	_check(deep > 0 and deep < wet, "and both wading water and water too deep to stand in (%d of %d wet)" % [deep, wet])
