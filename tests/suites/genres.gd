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
	_check(Genres.listed() == PackedStringArray(["fishing"]) and not Genres.title().is_empty(),
		"shared/game.json makes the game of fishing (%s, \"%s\")" % [str(Genres.listed()), Genres.title()])
	var mods: Array[GenreModule] = Genres.modules()
	_check(mods.size() == 1 and mods[0].id == &"fishing" and mods[0].entity_definitions.size() == 3
		and mods[0].tables.has(&"catch") and mods[0].scenes.size() == 2,
		"each genre's client half loads: fishing's definitions, tables and scenes")
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
	var cfg := NetConfig.new()
	Genres.merge_tables(cfg, mods)
	_check(cfg.core_tables.has(&"fishing_line") and cfg.world_tables.has(&"fishing_line")
		and cfg.core_tables.has(&"entity") and cfg.core_tables.count(&"catch") == 1,
		"a game's subscription is the foundation's tables and its genres', each once")
	Genres.merge_tables(cfg, mods)
	_check(cfg.core_tables.count(&"catch") == 1, "merging twice adds nothing twice")
	# Boot, in a game scene: the genres' definitions are registered, their tables subscribed, their
	# scenes put in the game.
	var game: Node = (load("res://game/fishing/fishing_game.tscn") as PackedScene).instantiate()
	var boot: Node = game.get_node(^"Boot")
	boot.set("connect_screen", null)   # no screen: it would connect at once, and there is no server
	boot.set("pause_menu", null)
	var prev_cfg: NetConfig = SpaceTimeSync.config
	var prev_defs: Array[EntityDefinition] = EntitySpawner.definitions.duplicate()
	var prev_state: int = SpaceTimeSync.state
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var booted: Array = boot.get("genres")
	var cfg_used: NetConfig = boot.get("net_config") as NetConfig
	_check(booted.size() == 1 and cfg_used.core_tables.has(&"fight_show") and cfg_used.world_tables.has(&"fight_show"),
		"Boot loads the genres and subscribes their tables")
	_check(EntitySpawner._by_kind.has(0) and (EntitySpawner._by_kind[0] as EntityDefinition).resource_path.ends_with("fisher_definition.tres"),
		"their entity definitions are what the spawner builds (kind 0 is the angler)")
	_check(game.get_node_or_null(^"HUD") != null and game.get_node_or_null(^"FishingWorld/SkyDirector") != null,
		"and their scenes are in the game: the HUD, the sky")
	SpaceTimeSync.disconnect_from_server("test over")
	game.queue_free()
	await get_tree().process_frame
	SpaceTimeSync.config = prev_cfg
	EntitySpawner.definitions = prev_defs
	# An unknown genre is reported, by name.
	Genres.override_list = PackedStringArray(["no_such_genre"])
	var bad: Array[GenreModule] = Genres.modules()
	Genres.override_list = PackedStringArray()
	_check(bad.is_empty(), "a genre with no genre.tres is skipped (and reported)")
