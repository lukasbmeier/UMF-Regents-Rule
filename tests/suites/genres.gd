extends "res://tests/suite_base.gd"
## The `genres` suite (tests/test_runner.gd runs it; `-- --only=genres` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_genre_tests()



## A GAME IS A LIST OF GENRES (DECISIONS #173): shared/game.json names them, each has its client
## file (genre.tres) and its server file (server/src/game/<id>.rs); Boot takes the genres'
## definitions, tables and scenes; a genre that is not listed is not loaded at all; one with no
## file is said, not swallowed.
func _run_genre_tests() -> void:
	print("== genres ==")
	var game: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/game.json")) as Dictionary
	var want: PackedStringArray = PackedStringArray(game.get("genres", []) as Array)
	_check(Genres.listed() == want and not Genres.title().is_empty(),
		"shared/game.json makes the game (%s, \"%s\")" % [str(Genres.listed()), Genres.title()])
	var mods: Array[GenreModule] = Genres.modules()
	var ids: PackedStringArray = PackedStringArray()
	for m: GenreModule in mods:
		ids.append(String(m.id))
	_check(ids == want, "each listed genre's client half loads, in order (%s)" % str(ids))
	var server_missing: Array[String] = []
	for id: String in Genres.listed():
		if not FileAccess.file_exists(ProjectSettings.globalize_path("res://server/src/game/%s.rs" % id)):
			server_missing.append(id)
	_check(server_missing.is_empty(), "and its server half exists (server/src/game/<id>.rs) %s" % str(server_missing))
	# Every table a genre names is per world or not, decided like the foundation's.
	for m: GenreModule in mods:
		var stray: Array[StringName] = []
		for t: StringName in m.world_tables:
			if not m.tables.has(t):
				stray.append(t)
		_check(stray.is_empty(), "%s's per-world tables are tables it subscribes %s" % [m.id, str(stray)])
		var off_world: Array[StringName] = []
		for t: StringName in m.cell_tables:
			if not m.world_tables.has(t):
				off_world.append(t)
		_check(off_world.is_empty(), "%s's cell tables are per-world tables too %s" % [m.id, str(off_world)])
	var cfg := NetConfig.new()
	Genres.merge_tables(cfg, mods)
	var once: bool = cfg.core_tables.has(&"entity")
	for m: GenreModule in mods:
		for t: StringName in m.tables:
			once = once and cfg.core_tables.count(t) == 1
		for t: StringName in m.world_tables:
			once = once and cfg.world_tables.has(t)
	_check(once, "a game's subscription is the foundation's tables and its genres', each once")
	Genres.merge_tables(cfg, mods)
	var twice: bool = true
	for t: StringName in cfg.core_tables:
		twice = twice and cfg.core_tables.count(t) == 1
	_check(twice, "merging twice adds nothing twice")
	# A genre's cell tables reach the config (template 1.5): a region referee and a ring client ask for them by cell.
	var celled := GenreModule.new()
	celled.id = &"celled"
	celled.tables = [&"crop"]
	celled.world_tables = [&"crop"]
	celled.cell_tables = [&"crop"]
	var ccfg := NetConfig.new()
	Genres.merge_tables(ccfg, [celled] as Array[GenreModule])
	Genres.merge_tables(ccfg, [celled] as Array[GenreModule])
	_check(ccfg.cell_tables.count(&"crop") == 1 and InterestManager.is_cell_table(&"crop", ccfg)
		and not InterestManager.is_cell_table(&"crop", NetConfig.new()),
		"a genre's cell tables are the config's, once: asked for by cell (a config without the genre: the whole world)")
	# (Boot in a game scene, taking the genres' definitions and scenes, is each genre's own suite.)
	# A genre scene named like one of the game scene's own children replaces it (DECISIONS #197):
	# the foundation's HUD gives way to a genre's; a name nobody has is simply added.
	var root := Node.new()
	var own_hud := Control.new()
	own_hud.name = "HUD"
	root.add_child(own_hud)
	var boot: Node = (load("res://foundation/boot.gd") as GDScript).new()
	var genre_hud := Control.new()
	genre_hud.name = "HUD"
	boot.call(&"_add_genre_scene", root, genre_hud)
	var sky := Node.new()
	sky.name = "Sky"
	boot.call(&"_add_genre_scene", root, sky)
	_check(root.get_child_count() == 2 and root.get_node_or_null(^"HUD") == genre_hud
		and own_hud.is_queued_for_deletion() and root.get_node_or_null(^"Sky") == sky,
		"a genre's HUD replaces the game scene's own; a scene with a new name is added beside it")
	root.free()
	boot.free()
	var greybox: Node = (load("res://game/greybox_game.tscn") as PackedScene).instantiate()
	_check(greybox.get_node_or_null(^"HUD") is FoundationHud,
		"the greybox game carries the foundation's HUD")
	greybox.free()
	# An unknown genre is reported, by name.
	Genres.override_list = PackedStringArray(["no_such_genre"])
	var bad: Array[GenreModule] = Genres.modules()
	Genres.override_list = PackedStringArray()
	_check(bad.is_empty(), "a genre with no genre.tres is skipped (and reported)")
