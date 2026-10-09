extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fishing_level_bake` suite (`-- --only=fishing_level_bake` runs it alone), run because shared/game.json
## lists fishing. The fishing half of tests/suites/level_bake.gd (the original, run on the angler and the lakeside). Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	_run_level_bake_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



# --- LevelBake parity (server/src/level.rs) -----------------------------------------------

const LEVEL_PROBES: String = "res://shared/golden/level/lakeside_probes.json"

## The client's answer to "is that water, which spot" must be the server's, point for point:
## a float the aim ring shows landing in the lake has to be one the module accepts. The Rust
## twin runs the same file (`cargo test --test level`).
func _run_level_bake_tests() -> void:
	print("== LevelBake ==")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PROBES))
	if not doc is Dictionary:
		_check(false, "cannot read " + LEVEL_PROBES)
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
	_check(mismatches == 0, "every level probe matches the Rust twin (%d mismatches)" % mismatches)
	_check(wet > 0 and wet < probes.size(), "the probes cover both water and land")
	_check(deep > 0 and deep < wet, "and both wading water and water too deep to stand in (%d of %d wet)" % [deep, wet])
	# WHERE A PLAYER MAY STAND (REVIEW B2): the module refuses a claim anywhere else.
	_check(bake.can_stand(bake.spawn.x, bake.spawn.z) and bake.can_stand(0.0, 40.0) and bake.can_stand(3.0, 25.0),
		"the spawn and the dock's planks are ground a player may stand on")
	_check(not bake.can_stand(0.0, 16.0) and not bake.can_stand(0.0, -24.0),
		"past the end of the dock and the Deep Hole are not")
	# The things the game relies on, whatever the probe file says.
	_check(not bake.is_water(bake.spawn.x, bake.spawn.z), "players arrive on dry land")
	_check(bake.is_water(0.0, 16.0), "the end of the dock is fishable")
	_check(not bake.is_water(0.0, 40.0) and not bake.is_water(3.0, 25.0),
		"but a float cannot land on the dock's planks, though they stand over water")
	_check(bake.spot_at(0.0, 16.0).get("id", "") == "dock_end", "and it is the Dock End spot")
	_check(bake.spot_at(0.0, -24.0).get("id", "") == "deep_hole", "the middle of the lake is the Deep Hole")
	_check(bake.is_water(-60.0, -20.0) and bake.spot_at(-60.0, -20.0).is_empty(),
		"and west of it is open water, no spot")
	# NaN fails every comparison: without its guard it would index a real cell.
	_check(bake.cell(NAN, 0.0) == Vector2i(-1, -1) and bake.cell(0.0, NAN) == Vector2i(-1, -1),
		"a NaN position is off the grid, not cell zero")
	_check(bake.depth_dm_at(INF, 0.0) == 0, "infinity is dry land")
