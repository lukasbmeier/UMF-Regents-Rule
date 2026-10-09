extends "res://tests/suite_base.gd"
## The `content` suite (tests/test_runner.gd runs it; `-- --only=content` runs it alone).
## CONTENT IS RESOURCES, BAKED (docs/CONTENT_TOOLING_SPEC.md §1, DECISIONS #199): the bake on disk is
## the one the .tres files make now, every piece of content is valid, and a type says what is wrong
## with bad content in words. (That the server refuses a stale bake is tests/content_test.sh.)

const BAKE: GDScript = preload("res://tools/bake_content.gd")


func run() -> void:
	_run_content_tests()
	_run_library_tests()
	await _run_task_tests()
	_run_hot_rule_tests()
	await _run_hot_rule_live_tests()
	_run_keep_live_tests()
	await get_tree().process_frame


func _run_content_tests() -> void:
	print("== content ==")
	var result: Dictionary = BAKE.call(&"bake", false)
	_check((result["errors"] as Array).is_empty(), "every piece of content is valid %s" % str(result["errors"]))
	_check((result["stale"] as Array).is_empty(),
		"the bake on disk is current (Bake, or tools/bake_content.gd) %s" % str(result["stale"]))
	var melee: AbilityDef = load("res://foundation/content/ability/melee.tres") as AbilityDef
	_check(melee != null and melee.validate().is_empty(), "the foundation's ability, melee, is content")
	var baked: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/content/foundation/ability.json"))
	var item: Dictionary = ((baked as Dictionary)["items"] as Array)[0] if baked is Dictionary else {}
	_check(melee != null and int(item.get("ability_id", -1)) == melee.id and int(item.get("wind_up_ms", -1)) == melee.wind_up_ms
		and String(item.get("name", "")) == melee.display_name and not item.has("designer_notes"),
		"its baked row is its Inspector values, without the designer's notes")
	var bad := AbilityDef.new()
	bad.display_name = ""
	bad.wind_up_ms = 50
	var why: Array[String] = bad.validate()
	_check(why.size() == 2 and why[1].contains("50 ms") and why[0].contains("no display name"),
		"bad content is refused in words: %s" % str(why))
	_check(BAKE.call(&"hash_bytes", "a".to_utf8_buffer()) == "e40c292c"
		and BAKE.call(&"hash_bytes", PackedByteArray()) == "811c9dc5",
		"the manifest's hash is FNV-1a 32 (build.rs computes the same)")


## THE LIBRARY AND THE RULES IT KEEPS (DECISIONS #200): types are found, not registered, and every
## one is a tool; a new piece goes in its type's folder with the next free id at or above its
## owner's base; links between content are checked; a stray file is an error.
func _run_library_tests() -> void:
	print("== content: the library ==")
	var types: Array[Dictionary] = ContentLibrary.types()
	var ability: Dictionary = ContentLibrary.type_info(&"ability")
	_check(not ability.is_empty() and ability["class_name"] == &"AbilityDef" and String(ability["owner"]).is_empty(),
		"types are found in the class list, with no registry: ability is the foundation's (%d type(s))" % types.size())
	var not_tool: Array[String] = []
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var t: Dictionary = {}
		for x: Dictionary in types:
			if x["class_name"] == c["class"]:
				t = x
		if (not t.is_empty() or c["class"] == &"ContentDef") and not bool(c.get("is_tool", false)):
			not_tool.append(String(c["class"]))
	_check(not_tool.is_empty(), "every content script is @tool, so the editor can check and bake it %s" % str(not_tool))
	_check(ContentLibrary.folder_for(&"ability", "foundation") == "res://foundation/content/ability"
		and ContentLibrary.folder_for(&"ability", "fishing") == "res://game/fishing/content/ability",
		"a type's pieces live in <root>/<type>/")
	_check(ContentLibrary.file_stem("  Big Bass!  ") == "big_bass" and ContentLibrary.file_stem("???") == "new",
		"a name becomes a file name")

	# A scratch project under user://: two owners, a genre with an id base.
	var root: String = "user://content_library_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["testgenre"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("game/testgenre")))
	var mod := GenreModule.new()
	mod.id = &"testgenre"
	mod.content_id_base = 10000
	ResourceSaver.save(mod, root.path_join("game/testgenre/genre.tres"))
	var errors: Array[String] = []
	var a: String = ContentLibrary.create(&"ability", "foundation", "Kick", errors)
	var b: String = ContentLibrary.create(&"ability", "foundation", "Kick", errors)
	var c: String = ContentLibrary.create(&"ability", "testgenre", "Peck", errors)
	var d: String = ContentLibrary.create(&"ability", "testgenre", "Flap", errors)
	_check(errors.is_empty() and a == root.path_join("foundation/content/ability/kick.tres")
		and b.ends_with("ability/kick_2.tres") and c == root.path_join("game/testgenre/content/ability/peck.tres"),
		"New puts a piece in its owner's folder for its type, named after it (a second Kick is kick_2) %s" % str(errors))
	var ids: Array[int] = []
	for p: String in [a, b, c, d]:
		ids.append((ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as ContentDef).id)
	_check(ids == [0, 1, 10000, 10001], "with the next free id at or above its owner's base (%s)" % str(ids))
	_check(ContentLibrary.items(&"ability").size() == 4 and ContentLibrary.find(&"ability", 10001) != null
		and ContentLibrary.find(&"ability", 10001).display_name == "Flap",
		"the library lists every owner's pieces and finds one by id")
	_check(ContentLibrary.create(&"ability", "nobody", "X", errors).is_empty() and not errors.is_empty(),
		"an owner the game does not have cannot make content: %s" % str(errors))

	# THE DOCK, built and clicked with no editor.
	print("== content: the dock ==")
	var bridge := ContentDockBridge.new()
	var dock := ContentDock.new()
	get_tree().root.add_child(dock)
	dock.setup(ContentDockModel.new(), bridge)
	var names: Array[String] = []
	for a2: Dictionary in dock.model.actions:
		names.append(String(a2["id"]))
	_check(names == ["validate", "bake", "publish", "play", "keep_live"], "its toolbar: %s" % str(names))
	_check(dock.selected_type() == &"ability" and dock.listed_paths().size() == 4,
		"it opens on a type and lists its pieces, every owner's (%s)" % str(dock.listed_paths()))
	dock.select_path(c)
	_check(bridge.asked.has("edit " + c), "choosing one opens it in the Inspector %s" % str(bridge.asked))
	var model: ContentDockModel = dock.model
	_check(model.owners_for(&"ability") == PackedStringArray(["foundation", "testgenre"]),
		"a foundation type may be made by any owner")
	var made: String = model.create(&"ability", "testgenre", "  ", errors)
	_check(made.is_empty() and errors[errors.size() - 1].contains("name"), "New wants a name")
	(dock.find_child("New", true, false) as Button).disabled = false
	var bad: AbilityDef = ResourceLoader.load(d, "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDef
	bad.wind_up_ms = 20
	ResourceSaver.save(bad, d)
	dock.validate()
	_check(dock.log_text().contains("1 problem") and dock.log_text().contains("flap.tres") and dock.log_text().contains("20 ms"),
		"Validate lists the problem, naming the file, in words: %s" % dock.log_text().replace("\n", " / "))
	_check(model.type_rows()[0]["problems"] == 1 and model.item_rows(&"ability", "flap")[0]["problems"] == 1,
		"and marks its type and its piece")
	_check(model.item_rows(&"ability", "10000").size() == 1 and model.item_rows(&"ability", "kick").size() == 2,
		"search finds by id, name or file")
	dock.queue_free()

	# What the bake refuses, beyond validate(): links to content that is not baked content.
	var linking := GDScript.new()
	linking.source_code = "@tool\nextends ContentDef\n@export var other: ContentDef\nfunc content_type() -> StringName:\n\treturn &\"linking\"\nfunc to_bake() -> Dictionary:\n\treturn {\"other\": ContentDef.ref(other)}\n"
	linking.reload()
	var l: ContentDef = linking.new() as ContentDef
	var baked: Dictionary = {a: true}
	l.set(&"other", ResourceLoader.load(a))
	var ok_links: Array[String] = BAKE.call(&"_bad_links", l, baked)
	l.set(&"other", AbilityDef.new())
	var inside: Array[String] = BAKE.call(&"_bad_links", l, baked)
	l.set(&"other", ResourceLoader.load(b))
	var outside: Array[String] = BAKE.call(&"_bad_links", l, {a: true})
	_check(ok_links.is_empty() and inside.size() == 1 and inside[0].contains("made inside")
		and outside.size() == 1 and outside[0].contains("not in a content folder"),
		"a link must be to baked content: %s %s" % [str(inside), str(outside)])
	l.set(&"other", ResourceLoader.load(a))
	_check(l.to_bake()["other"] == 0 and ContentDef.ref(null) == -1, "and is baked as its id (-1 for none)")

	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = PackedStringArray()
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


## A PROJECT SCRIPT RUN FROM THE EDITOR (the dock's Publish): it runs the way toolsun.cmd runs
## one, through Git Bash and tools/run_env.sh, and its output arrives line by line with its exit code.
func _run_task_tests() -> void:
	print("== content: a project task ==")
	var script: String = ProjectSettings.globalize_path("user://project_task_test.sh")
	var f: FileAccess = FileAccess.open(script, FileAccess.WRITE)
	f.store_string("echo first
echo \"second, from $(basename \"$(pwd)\")\"
echo oops >&2
exit 3
")
	f.close()
	var task := ProjectTask.new()
	var lines: Array[String] = []
	task.line.connect(func(t: String) -> void: lines.append(t))
	var started: bool = task.start(script)
	var frames: int = 0
	while task.is_running() and frames < 600:
		task.poll()
		await get_tree().process_frame
		frames += 1
	var root_name: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	_check(started and lines.has("first") and lines.has("second, from %s" % root_name) and lines.has("oops")
		and task.exit_code == 3,
		"a script runs from the repo root, its lines (and errors) arrive, then its exit code: %s, exit %d" % [str(lines), task.exit_code])
	DirAccess.remove_absolute(script)


## HOT RULES AS CONTENT (DECISIONS #201): a rule says what is wrong with it in words; keys are
## `<owner>.<name>` and unique; a genre sets this game's value for another owner's rule with an
## override (one per key, within bounds), and that is the default the game uses.
func _run_hot_rule_tests() -> void:
	print("== content: hot rules ==")
	var hot: Dictionary = RuleSetDef.effective()
	_check(hot.has("foundation.interact_range_m") and hot.has("foundation.new_player_health"),
		"the foundation declares its rules: %s" % str(hot.keys()))
	var r := RuleEntry.new()
	r.name = &"Bad Name"
	r.number = 5.0
	r.minimum = 0.0
	r.maximum = 1.0
	var why: Array[String] = r.problems()
	_check(why.size() == 3 and why[0].contains("lower case") and why[1].contains("outside") and why[2].contains("description"),
		"a rule says what is wrong with it: %s" % str(why))
	var walk := RuleEntry.new()
	walk.name = &"walk_speed"
	walk.description = "x"
	walk.maximum = 10.0
	var set_walk := RuleSetDef.new()
	set_walk.display_name = "x"
	set_walk.rules = [walk]
	_check(set_walk.validate().any(func(s: String) -> bool: return s.contains("predict exactly")),
		"a movement number clients predict exactly cannot be a hot rule")

	# A scratch game: the foundation's rules, a genre overriding one, a second genre trying too.
	var root: String = "user://hot_rules_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["alpha", "beta"])
	var base := RuleSetDef.new()
	base.display_name = "base"
	var range := RuleEntry.new()
	range.name = &"reach_m"
	range.number = 3.0
	range.minimum = 1.0
	range.maximum = 10.0
	range.description = "how far"
	base.rules = [range]
	_save(base, root.path_join("foundation/content/rules/base.tres"))
	var alpha := RuleSetDef.new()
	alpha.display_name = "alpha"
	var o := RuleOverride.new()
	o.key = "foundation.reach_m"
	o.number = 4.5
	alpha.overrides = [o]
	_save(alpha, root.path_join("game/alpha/content/rules/alpha.tres"))
	var eff: Dictionary = RuleSetDef.effective()
	_check(eff.size() == 1 and is_equal_approx(float(eff["foundation.reach_m"]["number"]), 4.5)
		and eff["foundation.reach_m"]["overridden_by"] == "alpha",
		"a genre's override is this game's default: %s" % str(eff))
	var sets: Array[ContentDef] = ContentLibrary.items(&"rules")
	var clean: bool = true
	for s: ContentDef in sets:
		clean = clean and s.validate_with(sets).is_empty() and s.validate().is_empty()
	_check(clean, "and every set agrees with the others")
	var beta := RuleSetDef.new()
	beta.display_name = "beta"
	var o2 := RuleOverride.new()
	o2.key = "foundation.reach_m"
	o2.number = 50.0
	var o3 := RuleOverride.new()
	o3.key = "foundation.nothing"
	beta.overrides = [o2, o3]
	var dup := RuleEntry.new()
	dup.name = &"reach_m"
	dup.number = 2.0
	dup.maximum = 5.0
	dup.description = "again"
	_save(beta, root.path_join("game/beta/content/rules/beta.tres"))
	var base2 := RuleSetDef.new()
	base2.display_name = "base2"
	base2.rules = [dup]
	_save(base2, root.path_join("foundation/content/rules/base2.tres"))
	sets = ContentLibrary.items(&"rules")
	var found: Array[String] = []
	for s: ContentDef in sets:
		found.append_array(s.validate_with(sets))
	var text: String = " / ".join(found)
	_check(text.contains("also overridden") and text.contains("outside 1.0..10.0") and text.contains("no rule set declares")
		and text.contains("also declared"),
		"two overrides of one key, a value out of bounds, a key nobody declares and a key declared twice are each refused: %s" % text)
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = PackedStringArray()
	_wipe(root)


## THE LIVE VALUE: a `hot_rule` row (as the server sends it) wins over this build's default, its
## change is announced, and a disconnect puts the defaults back.
func _run_hot_rule_live_tests() -> void:
	HotRules.reset()
	var key: StringName = &"foundation.interact_range_m"
	var default: float = HotRules.number(key)
	var heard: Array[StringName] = []
	var on_change: Callable = func(k: StringName) -> void: heard.append(k)
	HotRules.changed.connect(on_change)
	var row := _FakeRow.new()
	row.key = String(key)
	row.number = default + 2.5
	row.overridden = true
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, &"hot_rule", null, row))
	_check(is_equal_approx(HotRules.number(key), default + 2.5) and HotRules.is_live(key) and HotRules.is_overridden(key)
		and is_equal_approx(Rules.interact_range(), default + 2.5) and heard == [key],
		"the server's value wins over this build's (%s over %s), and the change is announced" % [HotRules.number(key), default])
	HotRules._on_connection(SpaceTimeSync.ConnectionState.DISCONNECTED)
	_check(is_equal_approx(HotRules.number(key), default) and not HotRules.is_live(key) and heard.size() == 2,
		"offline, this build's default is back")
	HotRules.changed.disconnect(on_change)
	await get_tree().process_frame


class _FakeRow extends RefCounted:
	var key: String = ""
	var number: float = 0.0
	var text: String = ""
	var overridden: bool = false


func _save(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	ResourceSaver.save(res, path)
	res.take_over_path(path)


## KEEP LIVE TUNING (DECISIONS #201): what an admin set on the server becomes this game's default,
## in the right file: a genre's own rule takes the value; a foundation rule becomes the genre's
## override (made, or updated), never an edit of the foundation's file; with no genre (the template)
## the foundation's own value. A key nobody declares and a value outside the bounds are refused.
func _run_keep_live_tests() -> void:
	print("== content: keep live tuning ==")
	var printed := PackedStringArray(["database: x", "", " key                           | number | text ",
		"-------------------------------+--------+------", " \"foundation.reach_m\" | 4.5    | \"\"   ",
		" \"alpha.bite_s\"      | 7      | \"\"   ", " \"foundation.gone\"   | 1      | \"\"   "])
	var rows: Array[Dictionary] = ContentDockModel.parse_live(printed)
	_check(rows.size() == 3 and rows[0]["key"] == "foundation.reach_m" and is_equal_approx(float(rows[0]["number"]), 4.5)
		and rows[1]["key"] == "alpha.bite_s", "the server's table is read: %s" % str(rows))
	var root: String = "user://keep_live_test"
	_wipe(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["alpha"])
	var base := RuleSetDef.new()
	base.display_name = "base"
	var reach := RuleEntry.new()
	reach.name = &"reach_m"
	reach.number = 3.0
	reach.minimum = 1.0
	reach.maximum = 10.0
	reach.description = "how far"
	base.rules = [reach]
	_save(base, root.path_join("foundation/content/rules/base.tres"))
	var alpha := RuleSetDef.new()
	alpha.display_name = "alpha"
	var bite := RuleEntry.new()
	bite.name = &"bite_s"
	bite.number = 5.0
	bite.minimum = 1.0
	bite.maximum = 20.0
	bite.description = "how long"
	alpha.rules = [bite]
	_save(alpha, root.path_join("game/alpha/content/rules/alpha.tres"))
	var model := ContentDockModel.new()
	var r: Dictionary = model.keep_live(rows)
	var base_after: RuleSetDef = ResourceLoader.load(root.path_join("foundation/content/rules/base.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	var alpha_after: RuleSetDef = ResourceLoader.load(root.path_join("game/alpha/content/rules/alpha.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	_check((r["kept"] as Array).size() == 2 and (r["problems"] as Array).size() == 1
		and String((r["problems"] as Array)[0]).contains("foundation.gone"),
		"two kept, the undeclared one refused: %s" % str(r))
	_check(is_equal_approx(alpha_after.rules[0].number, 7.0), "a genre's own rule takes the server's value (%s)" % alpha_after.rules[0].number)
	_check(is_equal_approx(base_after.rules[0].number, 3.0) and alpha_after.overrides.size() == 1
		and alpha_after.overrides[0].key == "foundation.reach_m" and is_equal_approx(alpha_after.overrides[0].number, 4.5),
		"a foundation rule becomes the genre's override; the foundation's file is untouched")
	var again: Array[Dictionary] = [{"key": "foundation.reach_m", "number": 6.0, "text": ""}, {"key": "foundation.reach_m", "number": 99.0, "text": ""}]
	r = model.keep_live(again)
	alpha_after = ResourceLoader.load(root.path_join("game/alpha/content/rules/alpha.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(alpha_after.overrides.size() == 1 and is_equal_approx(alpha_after.overrides[0].number, 6.0)
		and String((r["problems"] as Array)[0]).contains("outside"),
		"a second keep updates the same override, and refuses a value out of bounds")
	var template_root: String = "user://keep_live_template"
	_wipe(template_root)
	ContentLibrary.root_override = template_root
	ContentLibrary.genres_override = PackedStringArray()
	var only := RuleSetDef.new()
	only.display_name = "only"
	var reach2: RuleEntry = reach.duplicate()
	only.rules = [reach2]
	_save(only, template_root.path_join("foundation/content/rules/only.tres"))
	model.keep_live([{"key": "foundation.reach_m", "number": 2.5, "text": ""}] as Array[Dictionary])
	var only_after: RuleSetDef = ResourceLoader.load(template_root.path_join("foundation/content/rules/only.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(is_equal_approx(only_after.rules[0].number, 2.5) and only_after.overrides.is_empty(),
		"with no genre (the template) the foundation's own value takes it")
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = PackedStringArray()
	_wipe(root)
	_wipe(template_root)
