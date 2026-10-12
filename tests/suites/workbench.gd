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
	await _run_status_bench()
	await _run_workbenches_2()
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


const STATUS_BENCH: String = "res://tools/workbench/status_workbench.tscn"


## THE STATUS BENCH (DECISIONS #206): a status measured on a real character by the real movement
## model, as the game steps it: downed crawls and cannot jump; an injury bursts and the burst ends;
## out cannot move; the timeline follows `then` to its end; a pose the character has no clip for is
## said (amber); an edit is followed.
func _run_status_bench() -> void:
	print("== workbench: statuses ==")
	StatusDef.clear_cache()
	var bench: StatusWorkbench = (load(STATUS_BENCH) as PackedScene).instantiate() as StatusWorkbench
	get_tree().root.add_child(bench)
	var own: MovementConfig = bench.character.movement_config()
	var downed: StatusDef = (StatusDef.find(StatusDef.DOWNED) as StatusDef).duplicate() as StatusDef
	bench.item = downed
	await get_tree().process_frame
	var moves: String = await bench.run_named_test(&"moves")
	_check(is_equal_approx(float(bench.last_measure["run"]), own.run_speed * 0.25)
		and is_equal_approx(float(bench.last_measure["sprint"]), own.run_speed * 0.25)
		and float(bench.last_measure["jump_m"]) == 0.0 and moves.contains("cannot jump"),
		"downed on the humanoid: a crawl at a quarter of its run, sprint or not, and no jump: %s" % moves)
	var timeline: String = await bench.run_named_test(&"timeline")
	_check(timeline.contains("Downed for 60.0 s, then Out until something changes it"), "its timeline follows `then`: %s" % timeline)
	var pose: String = await bench.run_named_test(&"pose")
	_check(not bool(bench.last_measure["pose"]) and pose.contains("no 'status.downed' clip")
		and bench.badge()["level"] == "amber", "a pose the character has no clip for is said, and the badge is amber: %s" % pose)
	downed.speed = 0.5
	await get_tree().create_timer(0.3).timeout
	await bench.run_named_test(&"moves")
	_check(is_equal_approx(float(bench.last_measure["run"]), own.run_speed * 0.5), "an edit is followed (speed 0.5: %.2f m/s)" % float(bench.last_measure["run"]))

	bench.item = StatusDef.find(StatusDef.INJURED)
	await get_tree().process_frame
	var burst: String = await bench.run_named_test(&"burst")
	_check(is_equal_approx(float(bench.last_measure["during"]), own.sprint_speed * StatusDef.find(StatusDef.INJURED).burst)
		and is_equal_approx(float(bench.last_measure["after"]), own.sprint_speed), "an injury's burst, then its sprint: %s" % burst)
	bench.item = StatusDef.find(StatusDef.OUT)
	await get_tree().process_frame
	var out_moves: String = await bench.run_named_test(&"moves")
	_check(out_moves.contains("cannot move") and not (bench.get_node(^"Mannequin") as Node3D).visible,
		"out: it cannot move, and its body is not shown: %s" % out_moves)
	bench.queue_free()
	await get_tree().process_frame


## A small model with clips of its own (a stand-in for a chicken: Idle, Walk, Jump on one bone, a
## 0.4 m box for a body), saved as a scene under `dir`. Laid out as a glTF is: the skeleton under an
## armature node, its clips addressed from the model's root ("Armature/Skeleton:root").
func _clip_model(dir: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Hen"
	var armature := Node3D.new()
	armature.name = "Armature"
	root.add_child(armature)
	armature.owner = root
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	skel.add_bone("root")
	armature.add_child(skel)
	skel.owner = root
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.5, 0.4)
	box.subdivide_width = 6
	box.subdivide_height = 6
	box.subdivide_depth = 6
	body.mesh = box
	body.position = Vector3(0, 0.25, 0)
	root.add_child(body)
	body.owner = root
	# A beak out in front and a crest on top: the outermost bits the body's fit leaves out.
	for bit: Array in [["Beak", Vector3(0.04, 0.04, 0.3), Vector3(0, 0.4, -0.35)], ["Crest", Vector3(0.02, 0.3, 0.05), Vector3(0, 0.65, 0)]]:
		var mi := MeshInstance3D.new()
		mi.name = String(bit[0])
		var b := BoxMesh.new()
		b.size = bit[1]
		mi.mesh = b
		mi.position = bit[2]
		root.add_child(mi)
		mi.owner = root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()
	for clip: String in ["Idle", "Walk", "Jump"]:
		var a := Animation.new()
		a.length = 1.0
		var t: int = a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, ^"Armature/Skeleton:root")
		a.position_track_insert_key(t, 0.0, Vector3.ZERO)
		a.position_track_insert_key(t, 1.0, Vector3(0, 0.1 if clip == "Jump" else 0.0, 0.4 if clip == "Walk" else 0.0))
		lib.add_animation(StringName(clip), a)
	player.add_animation_library(&"", lib)
	root.add_child(player)
	player.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path: String = dir.path_join("hen_model.tscn")
	ResourceSaver.save(scene, path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene


## The names of a packed node's stored properties.
static func _stored(state: SceneState, node: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in state.get_node_property_count(node):
		out.append(String(state.get_node_property_name(node, i)))
	return out


## WORKBENCHES 2 (DECISIONS #207), from Luke's first real use: the piece in the Inspector and the
## bench in its panel; a bench never changes its own scene; the character bench as the start of a
## character (any clip played closely, a model's own clips made into its set and mapped, its body
## fitted and drawn around it, its movement and abilities made from it); the movement bench
## performing each test on a character; New from this, Copy into a genre, the template's content
## read-only in a game; Play as this.
func _run_workbenches_2() -> void:
	print("== workbench: Workbenches 2 ==")
	var root: String = "user://workbench2_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray()
	StatusDef.clear_cache()

	# A BENCH KEEPS NOTHING IN ITS SCENE: what is on it, the character it is tried on, the mannequin's
	# model are the session's.
	var hen_scene: PackedScene = _clip_model(root.path_join("models"))
	var errors: Array[String] = []
	var hen_path: String = ContentLibrary.create(&"character", "foundation", "Hen", errors)
	var hen: EntityDefinition = load(hen_path) as EntityDefinition
	hen.visual_scene = hen_scene
	hen.scene = load("res://foundation/entities/player.tscn") as PackedScene
	ResourceSaver.save(hen, hen_path)
	var bench: CharacterWorkbench = (load(CHARACTER_BENCH) as PackedScene).instantiate() as CharacterWorkbench
	get_tree().root.add_child(bench)
	bench.item = hen
	await get_tree().process_frame
	var packed := PackedScene.new()
	for c: Node in bench.get_children():
		c.owner = bench
	packed.pack(bench)
	var state: SceneState = packed.get_state()
	var leaked := PackedStringArray()
	for i: int in state.get_node_count():
		for p: String in _stored(state, i):
			if p in ["item", "character", "definition", "look", "seconds_each", "preview_clip", "intake_file", "test", "status"]:
				leaked.append("%s.%s" % [state.get_node_name(i), p])
	_check(leaked.is_empty(), "a bench saved with a piece on it keeps none of it in its scene: %s" % str(leaked))

	# ITS BODY, AROUND IT: the capsule drawn on the model, not beside it; fitted to the model.
	var cap: MeshInstance3D = bench.get_node(^"Capsule") as MeshInstance3D
	_check(is_zero_approx(cap.position.x) and is_zero_approx(cap.position.z), "the body is drawn around the model (at its feet), not beside it")
	_check(bench.badge()["level"] == "amber" and str(bench.fit_checks()).contains("its body 1.80 m"),
		"a 0.5 m hen in a person's 1.8 m body is amber, and says so: %s" % str(bench.fit_checks()))
	bench.fit_body()
	var whole: AABB = CharacterWorkbench.model_bounds((bench.get_node(^"Mannequin") as Mannequin).model)
	_check(absf(hen.collision_height - 0.5) < 0.03 and hen.collision_radius > 0.12 and hen.collision_radius < 0.24
		and absf((cap.mesh as CapsuleMesh).height - hen.collision_height) < 0.001 and whole.size.y > 0.75,
		"Fit the body to the model fits its CORE: %.2f m tall, %.2f m radius, though the crest makes it %.2f m and the beak reaches 0.5 m out; the drawn body follows" % [hen.collision_height, hen.collision_radius, whole.size.y])
	bench.set_control(&"body_height", 0.6)
	bench.set_control(&"body_radius", 0.22)
	_check(is_equal_approx(hen.collision_height, 0.6) and is_equal_approx(hen.collision_radius, 0.22) and is_equal_approx((cap.mesh as CapsuleMesh).height, 0.6),
		"then fine-tuned from the panel's Body height and Body radius, the drawn body following")
	hen.collision_height = 0.5
	hen.collision_radius = 0.2
	hen.visual_scale = 2.0
	await get_tree().create_timer(0.3).timeout
	var m: Mannequin = bench.get_node(^"Mannequin") as Mannequin
	_check(m.model != null and is_equal_approx(m.model.scale.x, 2.0), "visual_scale sizes the model on the bench")
	# AND IN THE GAME: the entity a character spawns has its body and its model's size.
	var ent: SpaceTimeEntity = (load("res://foundation/entities/player.tscn") as PackedScene).instantiate() as SpaceTimeEntity
	ent.definition = hen
	ent._apply_presentation()
	var shape: CollisionShape3D = ent.get_node(^"CollisionShape3D") as CollisionShape3D
	var body: CapsuleShape3D = shape.shape as CapsuleShape3D
	var model: Node3D = ent.get_node_or_null(^"Visual/Model") as Node3D
	_check(is_equal_approx(body.radius, 0.2) and is_equal_approx(body.height, 0.5) and is_equal_approx(shape.position.y, 0.25)
		and model != null and is_equal_approx(model.scale.x, 2.0),
		"the entity a character spawns has its body (0.5 m by 0.2 m, standing on the ground) and its model's scale")
	var plain: SpaceTimeEntity = (load("res://foundation/entities/player.tscn") as PackedScene).instantiate() as SpaceTimeEntity
	_check(is_equal_approx(((plain.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).height, 1.8),
		"and resizing one character's body leaves the scene's own capsule as it was")
	ent.free()
	plain.free()
	hen.visual_scale = 1.0
	var thin_body := EntityDefinition.new()
	thin_body.display_name = "Thin"
	thin_body.scene = hen.scene
	thin_body.collision_radius = 0.5
	thin_body.collision_height = 0.6
	_check(thin_body.validate().any(func(s: String) -> bool: return s.contains("at least as tall as it is wide")),
		"a body wider than it is tall is refused")

	# ITS OWN CLIPS: an animation set made from the model, each thing the game needs matched by name;
	# the landing it lacks stood in for; every clip playable closely.
	_check(bench.actions().any(func(a: Dictionary) -> bool: return a["name"] == &"make_set"), "a model with clips of its own offers \"Animation set from the model\"")
	_check(bench.make_set_from_model(), "it makes one: %s" % bench.last_result)
	var set: AnimationSet = hen.animation_set
	_check(set != null and set.resource_path == root.path_join("game/anim/characters/hen.tres") and FileAccess.file_exists(set.resource_path),
		"saved beside the owner's content, not in a content folder (%s)" % (set.resource_path if set != null else "none"))
	var clip_of: Callable = func(semantic: StringName) -> StringName:
		var ref: AnimationClipRef = set.clips.get(semantic) if set != null else null
		return ref.anim_name if ref != null else &""
	_check(set != null and clip_of.call(&"locomotion.idle") == &"Idle" and clip_of.call(&"locomotion.walk") == &"Walk"
		and clip_of.call(&"jump.start") == &"Jump" and clip_of.call(&"jump.land") == &"Jump" and set.missing_required().is_empty(),
		"Idle, Walk and Jump matched by name, the landing it lacks stood in by its jump: nothing the game needs is missing")
	_check(bench.last_result.contains("stand-in"), "and it says which clips are stand-ins")
	# THE CLIPS MOVE ITS BONES, played as the game plays a set (from the skeleton's parent), though the
	# model's own were addressed from its root.
	bench.set_control(&"paused", true)
	bench.set_control(&"animation", &"locomotion.walk")
	bench.set_control(&"position", 0.5)
	await get_tree().create_timer(0.1).timeout
	var walked: Vector3 = m.skeleton.get_bone_pose_position(0) if m.skeleton != null else Vector3.ZERO
	_check(m.playing() == &"locomotion.walk" and absf(walked.z - 0.2) < 0.03,
		"its walk moves its bones as the game plays a set (the root bone %.2f m along, half way through)" % walked.z)
	bench.set_control(&"paused", false)
	var choices: Array = m.clip_choices()
	var names: Array = choices.map(func(c: Array) -> String: return String(c[0]))
	_check(names.has("locomotion.walk") and names.has("Walk") and names.has("model/Walk"),
		"ANY clip can be chosen: what the game plays, the set's clips, the model's own (%d choices)" % choices.size())
	bench.set_control(&"paused", true)
	bench.set_control(&"animation", &"model/Walk")
	bench.set_control(&"position", 0.5)
	await get_tree().create_timer(0.25).timeout
	_check(m.playing() == &"model/Walk" and absf(m.preview_fraction() - 0.5) < 0.02, "a clip is held paused where it is scrubbed to (%.2f, a quarter second later)" % m.preview_fraction())
	var held: Vector3 = m.skeleton.get_bone_pose_position(0) if m.skeleton != null else Vector3.ZERO
	_check(absf(held.z - 0.2) < 0.03, "and the model's OWN clip moves its bones there too, its skeleton renamed for the game's (%.2f m)" % held.z)
	bench.set_control(&"paused", false)
	bench.set_control(&"speed", 0.5)
	_check(m.preview_speed == 0.5, "and played slower")
	bench.set_control(&"map:jump.land", &"Idle")
	bench.save()
	var reread: AnimationSet = ResourceLoader.load(set.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationSet
	_check(reread.clips[&"jump.land"].anim_name == &"Idle", "each thing the game needs is a choice of clip, and Save keeps it")
	_check(bench.controls().any(func(c: Dictionary) -> bool: return c.get("name") == &"map:jump.land"),
		"the panel lists what the game needs to choose for")

	# The panel keeps a field it is drawing while only its value moves (a number being dragged).
	var bridge0 := ContentDockBridge.new()
	var panel0 := WorkbenchPanel.new()
	get_tree().root.add_child(panel0)
	panel0.setup(bridge0)
	panel0.show_bench(bench)
	var field: Control = panel0.control(&"body_height")
	bench.set_control(&"body_height", 0.55)
	await get_tree().process_frame
	_check(field != null and is_instance_valid(field) and panel0.control(&"body_height") == field and is_equal_approx((field as SpinBox).value, 0.55),
		"a setting whose value changes keeps its field (so dragging a number is not interrupted) and shows the new value")
	hen.collision_height = 0.5
	panel0.queue_free()

	# THE WORKBENCH PANEL: the bench's tests, settings and actions, drawn from what it declares.
	var bridge := ContentDockBridge.new()
	var panel := WorkbenchPanel.new()
	get_tree().root.add_child(panel)
	panel.setup(bridge)
	panel.show_bench(bench)
	var labels: PackedStringArray = panel.button_labels()
	_check(labels.has("Play every clip") and labels.has("Play as this") and labels.has("New from this") and labels.has("New movement for it")
		and panel.control(&"animation") != null, "the panel shows its tests, its actions and its settings: %s" % ", ".join(labels))
	panel.press_action(&"play_as")
	_check(bridge.asked.has("play --character=" + hen_path), "Play as this plays the game as it %s" % str(bridge.asked))
	panel.press_action(&"new_movement")
	var mv: MovementProfileDef = hen.movement_profile
	# A CHOICE shows the bench's value now, not the one it was drawn with (Luke: "Tried on: Chicken" on
	# a bench whose ability no character listed, so on the humanoid).
	var bridge3 := ContentDockBridge.new()
	var panel3 := WorkbenchPanel.new()
	get_tree().root.add_child(panel3)
	panel3.setup(bridge3)
	panel3.show_bench(bench)
	var move_opt: OptionButton = panel3.control(&"movement") as OptionButton
	panel3.set_control(&"movement", null)
	await get_tree().process_frame
	_check(move_opt != null and panel3.control(&"movement") == move_opt and move_opt.get_item_text(move_opt.selected).begins_with("(the game's default"),
		"a choice changed shows its new value (%s)" % (move_opt.get_item_text(move_opt.selected) if move_opt != null and move_opt.selected >= 0 else "nothing"))
	panel3.set_control(&"movement", mv)
	await get_tree().process_frame
	_check(move_opt.get_item_text(move_opt.selected).begins_with(mv.display_name), "and back (%s)" % move_opt.get_item_text(move_opt.selected))
	panel3.queue_free()
	_check(mv != null and mv.resource_path.begins_with(root.path_join("foundation/content/movement"))
		and bridge.asked.has("open res://tools/workbench/movement_workbench.tscn"),
		"New movement for it makes one, links it to the character, and opens it on its own bench %s" % str(bridge.asked))
	panel.press_action(&"new_ability")
	_check(hen.abilities.size() == 1 and bridge.asked.has("open res://tools/workbench/ability_workbench.tscn"),
		"New ability for it: made, listed on the character, opened")
	var reread_hen: EntityDefinition = ResourceLoader.load(hen_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EntityDefinition
	_check(reread_hen.movement_profile != null and reread_hen.abilities.size() == 1, "and both links are saved")
	_check(bench.actions().any(func(a: Dictionary) -> bool: return a["name"] == &"open_ability:0" and String(a["label"]).begins_with("Open ")),
		"the character offers each of its abilities to open")
	# CHOOSE FROM WHAT THERE IS: a movement and an ability picked from lists, not made blank inside it.
	var spare_path: String = ContentLibrary.create(&"ability", "foundation", "Spare", errors)
	var spare: AbilityDef = load(spare_path) as AbilityDef
	bench.set_control(&"movement", null)
	_check(hen.movement_profile == null, "its movement can be set back to the game's default")
	bench.set_control(&"movement", mv)
	var add_ctl: Dictionary = {}
	for c: Dictionary in bench.controls():
		if c.get("name") == &"add_ability":
			add_ctl = c
	_check(not add_ctl.is_empty() and (add_ctl["options"] as Array).any(func(o: Array) -> bool: return o[0] == spare)
		and not (add_ctl["options"] as Array).any(func(o: Array) -> bool: return o[0] == hen.abilities[0]),
		"Add ability lists the abilities it does not have yet")
	bench.set_control(&"add_ability", spare)
	_check(hen.movement_profile == mv and hen.abilities.has(spare) and hen.abilities.size() == 2, "a movement and an ability chosen from the lists are linked")
	hen.abilities.erase(spare)

	# PIECES MADE INSIDE IT (the Inspector's New on a link) are made their own when it is saved.
	hen.movement_profile = MovementProfileDef.new()
	hen.movement_profile.run_speed = 4.0
	hen.abilities.append(AbilityDef.new())
	bench.save()
	_check(not hen.movement_profile.resource_path.is_empty() and not hen.movement_profile.resource_path.contains("::")
		and hen.movement_profile.resource_path.begins_with(root.path_join("foundation/content/movement")) and is_equal_approx(hen.movement_profile.run_speed, 4.0)
		and not hen.abilities[1].resource_path.is_empty() and bench.last_result.contains("made its own piece"),
		"a movement and an ability made inside the character are saved as their own pieces, numbers kept, and linked: %s" % bench.last_result)
	var reread2: EntityDefinition = ResourceLoader.load(hen_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EntityDefinition
	_check(reread2.movement_profile != null and reread2.movement_profile.resource_path == hen.movement_profile.resource_path,
		"and the character's file links to them")
	hen.abilities.resize(1)
	hen.movement_profile = mv
	ResourceSaver.save(hen, hen_path)
	var baked: Dictionary = hen.to_bake()
	_check(baked["abilities"] == [hen.abilities[0].id], "the character's abilities are baked for the server (%s)" % str(baked["abilities"]))

	# THE MOVEMENT BENCH: tried on the character that moves by it, and PERFORMED.
	var mbench: MovementWorkbench = (load(MOVEMENT_BENCH) as PackedScene).instantiate() as MovementWorkbench
	get_tree().root.add_child(mbench)
	mbench.item = mv
	await get_tree().process_frame
	_check(mbench.character == hen, "a movement is tried on the character that moves by it (%s)" % (mbench.character.display_name if mbench.character != null else "none"))
	panel.show_bench(mbench)
	labels = panel.button_labels()
	_check(labels.has("Start and stop") and labels.has("Turn around") and labels.has("Play as this") and panel.control(&"character") != null,
		"its tests say what they play; it is tried on a character of your choice: %s" % ", ".join(labels))
	panel.press_action(&"play_as")
	_check(bridge.asked.has("play --movement=" + mv.resource_path), "Play as this: the game's character moving by it")
	_check(mbench.actions().any(func(a: Dictionary) -> bool: return a["name"] == &"open_character" and String(a["label"]) == "Open character: Hen"),
		"a bench tried on a character can always open that character")
	panel.press_action(&"open_character")
	_check(bridge.asked.back() == "open res://tools/workbench/character_workbench.tscn", "and does")
	# BACK: the panel remembers the bench a bench was opened from.
	var bridge2 := ContentDockBridge.new()
	var panel2 := WorkbenchPanel.new()
	get_tree().root.add_child(panel2)
	panel2.setup(bridge2)
	panel2.show_bench(bench)
	panel2.press_action(&"open_movement")
	panel2.show_bench(mbench)
	var back: Button = panel2.find_child("Back", true, false) as Button
	_check(back != null and back.visible and back.text.begins_with("← Back to Hen"), "a bench opened from another shows the way back: %s" % (back.text if back != null else "none"))
	panel2.go_back()
	_check(bridge2.asked.back() == "open res://tools/workbench/character_workbench.tscn", "and Back opens it")
	panel2.queue_free()
	mbench.replay_speed = 2.0
	await mbench.run_named_test(&"accelerate")
	_check(mbench.performing(), "a test is performed by the character")
	var hm: Mannequin = mbench.get_node(^"Mannequin") as Mannequin
	var start_z: float = hm.position.z
	await get_tree().create_timer(0.5).timeout
	_check(hm.position.z < start_z - 1.0 and hm.definition == hen, "the hen runs along the path (%.2f m)" % (start_z - hm.position.z))
	var marks: Node = mbench.get_node(^"Marks")
	var texts: Array = marks.get_children().filter(func(n: Node) -> bool: return n is Label3D).map(func(n: Node) -> String: return (n as Label3D).text)
	_check(texts.has("1 m") and texts.any(func(t: String) -> bool: return t.begins_with("stopped: slid")) and texts.any(func(t: String) -> bool: return t.begins_with("running speed")),
		"with a ruler under it and the moments labelled where they happen (%d labels)" % texts.size())
	var p: MovementProfileDef = mv
	_check(MovementWorkbench.performance_clip({"vel": Vector3.ZERO, "grounded": true}, p) == AnimationSet.IDLE
		and MovementWorkbench.performance_clip({"vel": Vector3(0, 0, -p.sprint_speed), "grounded": true}, p) == AnimationSet.SPRINT
		and MovementWorkbench.performance_clip({"vel": Vector3(0, 0, -p.run_speed), "grounded": true}, p) == AnimationSet.RUN
		and MovementWorkbench.performance_clip({"vel": Vector3(0, 3, 0), "grounded": false}, p) == AnimationSet.JUMP_START,
		"it plays the gait its speed is (idle, run, sprint; a jump in the air)")
	mbench.queue_free()

	# NEW FROM THIS, COPY INTO A GENRE, THE TEMPLATE'S CONTENT READ-ONLY IN A GAME.
	var sbench: StatusWorkbench = (load(STATUS_BENCH) as PackedScene).instantiate() as StatusWorkbench
	get_tree().root.add_child(sbench)
	var downed_path: String = ContentLibrary.create(&"status", "foundation", "Downed", errors)
	var downed: StatusDef = load(downed_path) as StatusDef
	downed.status = 2
	downed.speed = 0.25
	ResourceSaver.save(downed, downed_path)
	sbench.item = downed
	await get_tree().process_frame
	var copy: String = sbench.duplicate_item("foundation")
	var copied: StatusDef = load(copy) as StatusDef
	_check(copied != null and copied.id != downed.id and copied.status != 2 and is_equal_approx(copied.speed, 0.25) and sbench.item == copied,
		"New from this: its own id and file, a free status number, every other field copied, on the bench (status %d)" % (copied.status if copied != null else -1))
	ContentLibrary.genres_override = PackedStringArray(["hens"])
	sbench.item = downed
	await get_tree().process_frame
	_check(sbench.read_only_here() and sbench.actions().any(func(a: Dictionary) -> bool: return a["name"] == &"copy_into:hens")
		and String(sbench.status).contains("read-only"), "in a game, the template's piece is read-only, and offers Copy into the genre")
	sbench.do_action(&"copy_into:hens")
	var theirs: StatusDef = sbench.item as StatusDef
	_check(theirs != null and theirs.resource_path.begins_with(root.path_join("game/hens/content/status")) and theirs.status == 2
		and theirs.display_name == "Downed", "Copy into hens: hens' own, the same number (so it takes the template's place), to change")
	StatusDef.clear_cache()
	_check(StatusDef.find(2) == theirs, "and the game now uses it")
	_check(not bench.actions().any(func(a: Dictionary) -> bool: return a["name"] == &"new_movement"), "the template's character offers nothing that would change it")
	ContentLibrary.genres_override = PackedStringArray()

	# A FILE DRAGGED IN ARRIVES AS ITS UID: named from its real name.
	var uid: int = ResourceLoader.get_resource_uid("res://game/characters/mannequin_f.glb")
	var made: String = bench.new_from_file(ResourceUID.id_to_text(uid), "foundation")
	_check(made.get_file() == "mannequin_f.tres", "a model dragged in (a uid) makes a character named after its file (%s)" % made.get_file())

	panel.queue_free()
	bench.queue_free()
	sbench.queue_free()
	await get_tree().process_frame
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	StatusDef.clear_cache()
	_wipe(root)
	# The humanoid's set is made by a tool for many characters (game/anim/humanoid.tres): shared, never
	# offered as the humanoid's own to change clip by clip.
	var cb: CharacterWorkbench = (load(CHARACTER_BENCH) as PackedScene).instantiate() as CharacterWorkbench
	get_tree().root.add_child(cb)
	cb.item = load(HUMANOID) as EntityDefinition
	await get_tree().process_frame
	_check(not cb._owns_set(cb.item as EntityDefinition) and not cb.controls().any(func(c: Dictionary) -> bool: return String(c.get("name", "")).begins_with("map:")),
		"a set made for many characters (the humanoid's) is shared, not one character's to change here")
	cb.queue_free()
	await get_tree().process_frame
