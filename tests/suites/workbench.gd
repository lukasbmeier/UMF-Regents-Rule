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
	await _run_character_bench()
	await _run_movement_profiles()
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


const CHARACTER_BENCH: String = "res://tools/workbench/character_workbench.tscn"
const HUMANOID: String = "res://foundation/content/character/humanoid.tres"


## THE CHARACTER BENCH (DECISIONS #204): the real humanoid, fitted (feet on the floor, as tall as its
## capsule), every clip it needs; the facing read from a walk that travels; a new character made
## from a rigged model, in the right folder, playing the humanoid's animations when it has its rig.
func _run_character_bench() -> void:
	print("== workbench: characters ==")
	var bench: CharacterWorkbench = (load(CHARACTER_BENCH) as PackedScene).instantiate() as CharacterWorkbench
	bench.seconds_each = 0.01
	get_tree().root.add_child(bench)
	var humanoid: EntityDefinition = load(HUMANOID) as EntityDefinition
	bench.item = humanoid
	await get_tree().process_frame
	await get_tree().process_frame
	var cap: MeshInstance3D = bench.get_node(^"Capsule") as MeshInstance3D
	_check(bench.badge()["level"] == "green" and cap.visible and is_equal_approx((cap.mesh as CapsuleMesh).height, 1.8),
		"the humanoid on the bench is green: feet on the floor, as tall as the 1.8 m capsule shown beside it %s" % str(bench.fit_checks()))
	var clips: String = await bench.run_named_test(&"every_clip")
	_check(clips.contains("every clip the game needs is there") and clips.contains("played %d clip" % humanoid.animation_set.clips.size()),
		"every clip it names plays, and none the game needs is missing: %s" % clips)
	var looks: String = await bench.run_named_test(&"looks")
	_check(looks.begins_with("looks: %d look(s)" % humanoid.visual_variants.size()), "and it wears each of its looks: %s" % looks.left(80))
	var facing: String = await bench.run_named_test(&"walk_facing")
	_check(facing.contains("in place") and facing.contains("arrow") and bench.get_node_or_null(^"Forward") != null,
		"its walk is in place, so the bench says so and points at the arrow that is the game's forward")

	# A walk that travels: +Z, the way a Quaternius rig is authored.
	var lib := AnimationLibrary.new()
	var walk := Animation.new()
	walk.length = 1.0
	var t: int = walk.add_track(Animation.TYPE_POSITION_3D)
	walk.track_set_path(t, ^"Skeleton3D:root")
	walk.position_track_insert_key(t, 0.0, Vector3.ZERO)
	walk.position_track_insert_key(t, 1.0, Vector3(0, 0, 1.2))
	lib.add_animation(&"Walk", walk)
	var still := Animation.new()
	still.length = 1.0
	var t2: int = still.add_track(Animation.TYPE_POSITION_3D)
	still.track_set_path(t2, ^"Skeleton3D:root")
	still.position_track_insert_key(t2, 0.0, Vector3.ZERO)
	still.position_track_insert_key(t2, 1.0, Vector3(0.01, 0, 0.01))
	lib.add_animation(&"Still", still)
	var set := AnimationSet.new()
	set.libraries = {&"": lib}
	set.clips = {&"locomotion.walk": AnimationClipRef.make(&"Walk", true)}
	var d := EntityDefinition.new()
	d.animation_set = set
	d.visual_yaw_deg = 180.0
	var turned: String = CharacterWorkbench.facing(d)
	d.visual_yaw_deg = 0.0
	var unturned: String = CharacterWorkbench.facing(d)
	set.clips = {&"locomotion.walk": AnimationClipRef.make(&"Still", true)}
	var in_place: String = CharacterWorkbench.facing(d)
	_check(turned == "forward" and unturned == "backward" and in_place == "in_place",
		"a walk that travels says which way the rig faces: turned 180 it walks forward, unturned it would moonwalk, a walk in place cannot say (%s, %s, %s)" % [turned, unturned, in_place])

	d.display_name = "Walker"
	bench.item = d
	await get_tree().process_frame
	var thin: String = await bench.run_named_test(&"every_clip")
	_check(thin.contains("MISSING") and thin.contains("locomotion.idle") and thin.contains("jump.start"),
		"a set without what the game needs says which clips are missing: %s" % thin)

	var raised: EntityDefinition = humanoid.duplicate() as EntityDefinition
	raised.visual_offset = Vector3(0, 0.3, 0)
	bench.item = raised
	await get_tree().process_frame
	await get_tree().process_frame
	var warn: Array[String] = bench.fit_checks()
	_check(bench.badge()["level"] == "amber" and warn.size() == 1 and warn[0].contains("30 cm above"),
		"a model floating 30 cm up is amber, and the bench says what to set: %s" % str(warn))

	# NEW FROM A FILE, into a scratch project.
	var root: String = "user://character_bench_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray()
	var made: String = bench.new_from_file("res://game/characters/mannequin_f.glb", "foundation")
	var nd: EntityDefinition = ResourceLoader.load(made, "", ResourceLoader.CACHE_MODE_IGNORE) as EntityDefinition if not made.is_empty() else null
	_check(made == root.path_join("foundation/content/character/mannequin_f.tres") and nd != null
		and nd.visual_scene != null and nd.visual_scene.resource_path.ends_with("mannequin_f.glb") and nd.scene != null
		and bench.item != null and bench.item.resource_path == made,
		"New From File makes a character from a rigged model, in its type's folder, and puts it on the bench (%s)" % made)
	_check(nd != null and nd.animation_set == humanoid.animation_set and is_equal_approx(nd.visual_yaw_deg, humanoid.visual_yaw_deg),
		"with the humanoid's rig, it plays the humanoid's animations, turned the same way")
	var refused: String = bench.new_from_file("res://foundation/content/rules/foundation.tres", "foundation")
	_check(refused.is_empty() and bench.last_result.contains("not a model")
		and not FileAccess.file_exists(root.path_join("foundation/content/character/foundation.tres")),
		"a file that is not a model is refused, and nothing is left behind: %s" % bench.last_result)
	bench.queue_free()
	await get_tree().process_frame
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	_wipe(root)


const MOVEMENT_BENCH: String = "res://tools/workbench/movement_workbench.tscn"


## MOVEMENT PROFILES (DECISIONS #205): a new profile starts as the default, number for number; a
## character with one moves by it; the movement bench measures it with the real model, and its
## numbers agree with what the movement playtest measures through the game (a 1.53 m jump, a 0.47 m
## slide from a sprint).
func _run_movement_profiles() -> void:
	print("== workbench: movement profiles ==")
	var root: String = "user://movement_bench_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray()
	var errors: Array[String] = []
	# The default changed for a moment: a new profile must copy what the default IS, not what the
	# script's own initial values happen to be.
	var real_run: float = MovementConfig.shared().run_speed
	MovementConfig.shared().run_speed = 5.75
	var path: String = ContentLibrary.create(&"movement", "foundation", "Hen", errors)
	var hen: MovementProfileDef = load(path) as MovementProfileDef
	var same: bool = hen != null
	for f: StringName in MovementProfileDef.PROFILE_FIELDS:
		same = same and hen.get(f) == MovementConfig.shared().get(f)
	MovementConfig.shared().run_speed = real_run
	_check(same and is_equal_approx(hen.run_speed, 5.75), "a new profile starts as the default movement, number for number (%s)" % path)
	hen.run_speed = real_run
	hen.run_speed = 4.0
	hen.sprint_speed = 6.0
	hen.flap_charges = 2
	var d := EntityDefinition.new()
	_check(d.movement_config() == MovementConfig.shared(), "a character with no profile moves by the default")
	d.movement_profile = hen
	var cfg: MovementConfig = d.movement_config()
	_check(is_equal_approx(cfg.run_speed, 4.0) and cfg.flap_charges == 2
		and cfg.reconcile_smooth_time == MovementConfig.shared().reconcile_smooth_time,
		"one with a profile moves by its numbers, with the game's network numbers")
	_check(d.to_bake()["movement"] == hen.id, "and its bake names its profile, for the server's bound")
	hen.walk_speed = 9.0
	_check(hen.validate().any(func(s: String) -> bool: return s.contains("out of order")), "gaits out of order are refused")
	hen.walk_speed = 1.2

	var bench: MovementWorkbench = (load(MOVEMENT_BENCH) as PackedScene).instantiate() as MovementWorkbench
	get_tree().root.add_child(bench)
	bench.item = load(path)
	await get_tree().process_frame
	var base: MovementProfileDef = load(path) as MovementProfileDef
	base.fill_from(MovementConfig.shared())
	var jump: String = await bench.run_named_test(&"jump")
	_check(absf(float(bench.last_measure["height_m"]) - 1.53) < 0.02 and jump.contains("jumps 1.53 m"),
		"the default jump measures 1.53 m on the bench, as the playtest measures it in the game: %s" % jump)
	var acc: String = await bench.run_named_test(&"accelerate")
	_check(absf(float(bench.last_measure["stop_m"]) - 0.47) < 0.02, "and slides 0.47 m to a stop from a sprint, as in the game: %s" % acc)
	_check((bench.get_node(^"Trace") as MultiMeshInstance3D).multimesh.instance_count > 10, "the test leaves its path drawn")
	base.flap_charges = 2
	await get_tree().create_timer(0.3).timeout
	var flaps: String = await bench.run_named_test(&"flaps")
	var heights: Array = bench.last_measure["flap_heights_m"]
	_check(heights.size() == 2 and float(heights[0]) > 1.6 and float(heights[1]) > float(heights[0]),
		"two flaps, each at the top of a rise, each higher: %s" % flaps)
	base.run_speed = 3.0
	base.sprint_speed = 4.0
	await get_tree().create_timer(0.3).timeout
	await bench.run_named_test(&"accelerate")
	_check(float(bench.last_measure["stop_m"]) < 0.47, "a slower profile measures slower (an edit followed: %.2f m slide)" % float(bench.last_measure["stop_m"]))
	bench.queue_free()
	await get_tree().process_frame
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	_wipe(root)
