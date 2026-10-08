class_name Genres extends RefCounted
## THE GAME'S GENRES, ON THE CLIENT (DECISIONS #173): `res://shared/game.json` names them, the same
## file `server/build.rs` compiles the server from, so the two halves cannot be made of different
## genres (and if they were, the version check would refuse the connection: the schemas differ).
## Each genre's client half is `res://game/<id>/genre.tres` (a `GenreModule`).

const GAME_PATH: String = "res://shared/game.json"
const MODULE_PATH: String = "res://game/%s/genre.tres"

## TESTING: stands in for the file's list.
static var override_list: PackedStringArray = PackedStringArray()


## The whole file, or {} when it is missing or unreadable.
static func game() -> Dictionary:
	if not FileAccess.file_exists(GAME_PATH):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(GAME_PATH)) != OK or not json.data is Dictionary:
		push_error("Genres: %s is not a JSON object" % GAME_PATH)
		return {}
	return json.data as Dictionary


## The genres' names, in order.
static func listed() -> PackedStringArray:
	if not override_list.is_empty():
		return override_list
	var out := PackedStringArray()
	for g: Variant in game().get("genres", []) as Array:
		out.append(str(g))
	return out


## The game's title, as the file gives it ("" for none).
static func title() -> String:
	return str(game().get("title", ""))


## Each listed genre's `GenreModule`, in order. A genre with no file is reported and skipped.
static func modules() -> Array[GenreModule]:
	var out: Array[GenreModule] = []
	for id: String in listed():
		var path: String = MODULE_PATH % id
		var m: GenreModule = load(path) as GenreModule if ResourceLoader.exists(path) else null
		if m == null:
			push_error("Genres: shared/game.json names '%s', but there is no %s" % [id, path])
			continue
		if String(m.id) != id:
			push_warning("Genres: %s says its id is '%s', not '%s'" % [path, m.id, id])
		out.append(m)
	return out


## `cfg` with every module's tables added (in order, without repeats).
static func merge_tables(cfg: NetConfig, mods: Array[GenreModule]) -> void:
	var core: Array[StringName] = cfg.core_tables.duplicate()
	var world: Array[StringName] = cfg.world_tables.duplicate()
	for m: GenreModule in mods:
		for t: StringName in m.tables:
			if not core.has(t):
				core.append(t)
		for t: StringName in m.world_tables:
			if not world.has(t):
				world.append(t)
	cfg.core_tables = core
	cfg.world_tables = world


## Every module's entity definitions, in order.
static func definitions(mods: Array[GenreModule]) -> Array[EntityDefinition]:
	var out: Array[EntityDefinition] = []
	for m: GenreModule in mods:
		for d: EntityDefinition in m.entity_definitions:
			if d != null and not out.has(d):
				out.append(d)
	return out
