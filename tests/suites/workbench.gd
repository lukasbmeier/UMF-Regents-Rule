extends "res://tests/suite_base.gd"
## The `workbench` suite (tests/test_runner.gd runs it; `-- --only=workbench` runs it alone).
## WORKBENCHES AND THE CATALOG (CONTENT_TOOLING_SPEC §3, DECISIONS #203): no content type without a
## workbench (or a stated reason); the ability bench shows the piece, follows edits, and its tests
## say what the server would do; the dock hands a piece to its bench; the Catalog shows every piece
## with its badge. (Thumbnails need a renderer: tests/render_test.sh.)

const ABILITY_BENCH: String = "res://tools/workbench/ability_workbench.tscn"


func run() -> void:
	_run_every_type_has_a_bench()
	await _run_ability_bench()
	await _run_catalog()


func _run_every_type_has_a_bench() -> void:
	print("== workbench: no content type without one ==")
	var missing: Array[String] = []
	var said: Array[String] = []
	for t: Dictionary in ContentLibrary.types():
		var def: ContentDef = (load(String(t["script"])) as Script).new() as ContentDef
		var bench: String = def.workbench_scene()
		if bench.is_empty():
			if def.why_no_workbench().is_empty():
				missing.append(String(t["type"]))
			else:
				said.append("%s (%s)" % [t["type"], def.why_no_workbench().left(60)])
			continue
		var root: Node = (load(bench) as PackedScene).instantiate()
		if not (root is Workbench) or (root as Workbench).content_type() != t["type"]:
			missing.append("%s (its scene is not a %s workbench)" % [t["type"], t["type"]])
		root.free()
	_check(missing.is_empty(), "every content type has a workbench, or says why not %s; without one: %s" % [str(missing), str(said)])
	_check(ContentLibrary.workbench_for(&"ability") == ABILITY_BENCH, "the ability's is found by its name, tools/workbench/ability_workbench.tscn")


func _run_ability_bench() -> void:
	print("== workbench: abilities ==")
	var root: String = "user://workbench_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray()
	var errors: Array[String] = []
	var a_path: String = ContentLibrary.create(&"ability", "foundation", "Jab", errors)
	var b_path: String = ContentLibrary.create(&"ability", "foundation", "Lob", errors)
	var jab: AbilityDef = load(a_path) as AbilityDef
	var lob: AbilityDef = load(b_path) as AbilityDef
	jab.range_m = 2.0
	jab.wind_up_ms = 120
	jab.cooldown_ms = 300
	jab.damage = 7.0
	lob.range_m = 0.0
	ResourceSaver.save(jab, a_path)
	ResourceSaver.save(lob, b_path)

	var bench: AbilityWorkbench = (load(ABILITY_BENCH) as PackedScene).instantiate() as AbilityWorkbench
	bench.playback_speed = 2.0
	get_tree().root.add_child(bench)
	await get_tree().process_frame
	_check(bench.item == jab, "a bench opened on its own takes the first piece of its type (%s)" % (bench.item.display_name if bench.item != null else "none"))
	_check(is_equal_approx(bench.ring_radius(), 2.0) and bench.badge()["level"] == "green",
		"it shows the piece: the ring is its range (%s m), and the badge is green" % bench.ring_radius())
	var who: Mannequin = bench.get_node(^"Mannequin") as Mannequin
	_check(who.model != null and who.skeleton != null, "the real character stands on the bench")
	# An edit in the Inspector: the field changes, nothing is announced; the bench must follow.
	jab.range_m = 3.5
	await get_tree().create_timer(0.35).timeout
	_check(is_equal_approx(bench.ring_radius(), 3.5), "an edit to the piece is followed at once (the ring is now %s m)" % bench.ring_radius())

	var hit: String = await bench.run_named_test(&"use_in_range")
	_check(hit.contains("HIT for 7") and bench.last_outcome == "hit", "in range, it lands, as the server would judge it: %s" % hit)
	var far: String = await bench.run_named_test(&"use_out_of_range")
	_check(far.contains("refused: out of range") and bench.last_outcome == "out_of_range", "past the ring it is refused: %s" % far)
	var cool: String = await bench.run_named_test(&"cooldown")
	_check(cool.contains("at once: refused: on cooldown") and cool.contains("after the cooldown: HIT"),
		"used twice at once, the second is refused until the cooldown is over: %s" % cool)
	_check(bench.status.contains("GREEN") and bench.status.contains("cooldown:"), "and the bench's status says so")
	_check(AbilityWorkbench.judge(lob, 1.0, INF) == "miss" and AbilityWorkbench.judge(jab, 1.0, 100.0) == "cooling_down"
		and AbilityWorkbench.judge(jab, 9.0, INF) == "out_of_range",
		"its judgement is the server's: untargeted is a miss, inside the cooldown refused, past the range refused")

	bench.next_item()
	_check(bench.item == lob and not bench.get_node(^"RangeRing").visible, "Next goes to the next piece (an untargeted one: no ring)")
	bench.previous_item()
	_check(bench.item == jab, "Previous comes back")
	jab.wind_up_ms = 40
	await get_tree().create_timer(0.35).timeout
	_check(bench.badge()["level"] == "red" and bench.status.contains("RED") and bench.status.contains("40 ms"),
		"a piece that would not bake is red, with the reason")
	jab.wind_up_ms = 150
	_check(bench.save() == OK and (ResourceLoader.load(a_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDef).wind_up_ms == 150,
		"Save writes the piece to its file")
	bench.queue_free()

	# The dock's handoff: the piece chosen there is the one on the bench when it opens.
	Workbench.pending = lob
	var second: AbilityWorkbench = (load(ABILITY_BENCH) as PackedScene).instantiate() as AbilityWorkbench
	get_tree().root.add_child(second)
	await get_tree().process_frame
	_check(second.item == lob and Workbench.pending == null, "a bench opened from the dock has the chosen piece on it")
	second.queue_free()
	await get_tree().process_frame
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	_wipe(root)


func _run_catalog() -> void:
	print("== workbench: the Catalog ==")
	var root: String = "user://catalog_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray()
	var errors: Array[String] = []
	var good: String = ContentLibrary.create(&"ability", "foundation", "Good", errors)
	var bad_path: String = ContentLibrary.create(&"ability", "foundation", "Bad", errors)
	var bad: AbilityDef = load(bad_path) as AbilityDef
	bad.wind_up_ms = 10
	ResourceSaver.save(bad, bad_path)
	var bridge := ContentDockBridge.new()
	var dock := ContentDock.new()
	get_tree().root.add_child(dock)
	dock.setup(ContentDockModel.new(), bridge)
	dock.show_catalog()
	await get_tree().process_frame
	_check(dock.catalog_paths() == [good, bad_path], "every piece is a card (%s)" % str(dock.catalog_paths()))
	var rows: Array[Dictionary] = dock.model.catalog_rows()
	_check(rows[0]["badge"] == "amber" and String(rows[0]["sentence"]).contains("workbench")
		and rows[1]["badge"] == "red" and String(rows[1]["sentence"]).contains("10 ms"),
		"a valid piece never seen in its bench is amber; a broken one red, with its first problem")
	_check(dock.model.catalog_rows(&"", "red").size() == 1 and dock.model.catalog_rows(&"rules").is_empty(),
		"the cards filter by badge and by type")
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var thumb: String = Workbench.thumbnail_path(load(good) as ContentDef)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(thumb.get_base_dir()))
	img.save_png(thumb)
	_check(dock.model.catalog_rows()[0]["badge"] == "green" and Workbench.thumbnail_of(load(good) as ContentDef) != null,
		"once its picture exists (seen in its bench) it is green, and the card shows the picture")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(thumb))
	Workbench.pending = null
	dock.open_card(good)
	_check(bridge.asked.has("edit " + good) and bridge.asked.has("open " + ABILITY_BENCH)
		and Workbench.pending != null and Workbench.pending.resource_path == good,
		"a card clicked opens the piece in the Inspector and in its workbench, the piece on the bench %s" % str(bridge.asked))
	Workbench.pending = null
	dock.queue_free()
	await get_tree().process_frame
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	_wipe(root)


func _wipe(dir: String) -> void:
	var abs: String = ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	for d: String in DirAccess.get_directories_at(abs):
		_wipe(dir.path_join(d))
	DirAccess.remove_absolute(abs)
