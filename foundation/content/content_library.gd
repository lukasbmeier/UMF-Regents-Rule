@tool
class_name ContentLibrary extends RefCounted
## EVERY QUESTION ABOUT CONTENT, ANSWERED IN ONE PLACE (docs/rules/content.md, DECISIONS #200):
## which content types exist, where each owner's content lives, which pieces there are, the next
## free id, a piece by its id. The bake, the Content Dock, the workbenches, the Catalog and the
## running game all ask here, so none of them has its own idea of where content is.
##
## THE LAYOUT IT ENFORCES:
##   owners   "foundation", then each genre shared/game.json lists, in order
##   roots    foundation/content/  and  game/<genre>/content/
##   folders  <root>/<content_type>/<name>.tres   (one type per folder, nothing else in it)
##   types    every non-abstract ContentDef subclass, found in Godot's class list: no registry.
##            A type whose script is under game/<genre>/ is that genre's: only it makes them.
##   ids      unique per type across the whole game; a genre's new pieces start at its
##            `GenreModule.content_id_base`, so two genres' content never collides
##
## Works in the editor, headless and in an exported game (ResourceLoader.list_directory sees a
## pack's resources).

const FOUNDATION: String = "foundation"
const FOUNDATION_ROOT: String = "res://foundation/content"
const BASE_CLASS: StringName = &"ContentDef"

## TESTING: put every root under this directory instead (`<dir>/foundation/content`,
## `<dir>/game/<genre>/content`), so a suite can make content without touching the project's.
static var root_override: String = ""
## TESTING: stands in for shared/game.json's genre list: a PackedStringArray (an EMPTY one means
## "no genres"), or null for the game's own.
static var genres_override: Variant = null


## Who owns content: the foundation, then each genre the game is made of.
static func owners() -> PackedStringArray:
	var out := PackedStringArray([FOUNDATION])
	out.append_array(_genres())
	return out


## Where an owner's content lives.
static func root_of(owner: String) -> String:
	var base: String = root_override if not root_override.is_empty() else "res://"
	if owner == FOUNDATION:
		return FOUNDATION_ROOT if root_override.is_empty() else base.path_join("foundation/content")
	return base.path_join("game/%s/content" % owner)


## The folder a type's pieces go in, for an owner.
static func folder_for(type: StringName, owner: String) -> String:
	return root_of(owner).path_join(String(type))


## Every content type: [{ type, class_name, script, owner }] sorted by type. `owner` is the genre a
## type belongs to, or "" for a foundation type (any owner may make those).
static func types() -> Array[Dictionary]:
	var bases: Dictionary = {}
	var info: Dictionary = {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		bases[c["class"]] = c["base"]
		info[c["class"]] = c
	var out: Array[Dictionary] = []
	for cls: StringName in info:
		var c: Dictionary = info[cls]
		if bool(c.get("is_abstract", false)) or not _extends(cls, bases):
			continue
		var script: Script = load(String(c["path"])) as Script
		var def: ContentDef = script.new() as ContentDef if script != null else null
		if def == null:
			continue
		out.append({"type": def.content_type(), "class_name": cls, "script": c["path"],
			"owner": _owner_of_script(String(c["path"]))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["type"]) < String(b["type"]))
	return out


## One type's entry from `types()`, or {}.
static func type_info(type: StringName) -> Dictionary:
	for t: Dictionary in types():
		if t["type"] == type:
			return t
	return {}


## Whether `owner` may make pieces of `type` (a genre's type is that genre's alone).
static func may_own(type: StringName, owner: String) -> bool:
	var t: Dictionary = type_info(type)
	return not t.is_empty() and owners().has(owner) and (String(t["owner"]).is_empty() or t["owner"] == owner)


## Where a type's workbench is by convention (DECISIONS #203): `tools/workbench/<type>_workbench.tscn`
## for a foundation type, `game/<genre>/workbench/<type>_workbench.tscn` for a genre's. "" when the
## scene is not there.
static func workbench_for(type: StringName) -> String:
	var t: Dictionary = type_info(type)
	if t.is_empty():
		return ""
	var owner: String = t["owner"]
	var path: String = ("res://tools/workbench/%s_workbench.tscn" % type) if owner.is_empty() 		else ("res://game/%s/workbench/%s_workbench.tscn" % [owner, type])
	return path if ResourceLoader.exists(path) else ""


## Who owns the content at `path`: "foundation", a genre, or "" when it is under no content root.
static func owner_of_path(path: String) -> String:
	for owner: String in owners():
		if path.begins_with(root_of(owner) + "/"):
			return owner
	return ""


## Every content file: [{ owner, path }], by owner then path.
static func files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for owner: String in owners():
		for path: String in _tres_under(root_of(owner)):
			out.append({"owner": owner, "path": path})
	return out


## Every piece of content, loaded: [{ owner, path, def }] (def is null for a file that is not
## content; the bake reports those). `fresh`: read the files as they are on disk now, not the
## editor's open copies (the bake wants disk; the dock wants what the Inspector is editing).
static func load_all(fresh: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_IGNORE if fresh else ResourceLoader.CACHE_MODE_REUSE
	for f: Dictionary in files():
		var res: Resource = ResourceLoader.load(String(f["path"]), "", mode)
		out.append({"owner": f["owner"], "path": f["path"], "def": res as ContentDef})
	return out


## A type's pieces, by id.
static func items(type: StringName) -> Array[ContentDef]:
	var out: Array[ContentDef] = []
	for e: Dictionary in load_all():
		var def: ContentDef = e["def"]
		if def != null and def.content_type() == type:
			out.append(def)
	out.sort_custom(func(a: ContentDef, b: ContentDef) -> bool: return a.id < b.id)
	return out


## A piece by type and id, or null.
static func find(type: StringName, id: int) -> ContentDef:
	for def: ContentDef in items(type):
		if def.id == id:
			return def
	return null


## The id a new piece of `type` made by `owner` gets: the owner's base (0 for the foundation, the
## genre's `content_id_base`), or one past the highest id of that type at or above it.
static func next_free_id(type: StringName, owner: String) -> int:
	var base: int = id_base(owner)
	var next: int = base
	for def: ContentDef in items(type):
		if def.id >= base:
			next = maxi(next, def.id + 1)
	return next


## Where an owner's new ids start.
static func id_base(owner: String) -> int:
	if owner == FOUNDATION:
		return 0
	var base: String = root_override if not root_override.is_empty() else "res://"
	var path: String = base.path_join("game/%s/genre.tres" % owner)
	if not ResourceLoader.exists(path):
		return 0
	var mod: Resource = load(path)
	return int(mod.get(&"content_id_base")) if mod != null and mod.get(&"content_id_base") != null else 0


## Make a new piece: a `type` resource for `owner`, with the next free id and `display_name`,
## saved as `<folder>/<file>.tres`. Returns its path, or "" with `error` filled in.
static func create(type: StringName, owner: String, display_name: String, error: Array[String] = []) -> String:
	if not may_own(type, owner):
		error.append("%s cannot make %s content (a genre's type is that genre's alone)" % [owner, type])
		return ""
	var script: Script = load(String(type_info(type)["script"])) as Script
	var def: ContentDef = script.new() as ContentDef
	def.id = next_free_id(type, owner)
	def.display_name = display_name
	def.on_created()
	return _save_new(def, type, owner, display_name, error)


static func _save_new(def: ContentDef, type: StringName, owner: String, display_name: String, error: Array[String]) -> String:
	var folder: String = folder_for(type, owner)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var stem: String = file_stem(display_name)
	var path: String = folder.path_join(stem + ".tres")
	var n: int = 2
	while FileAccess.file_exists(path):
		path = folder.path_join("%s_%d.tres" % [stem, n])
		n += 1
	var err: Error = ResourceSaver.save(def, path)
	if err != OK:
		error.append("could not save %s: %s" % [path, error_string(err)])
		return ""
	return path


## NEW FROM THIS (DECISIONS #207): a copy of `source` for `owner` (every field, its sub-resources
## copied too), with the next free id, `display_name`, its own file in `owner`'s folder. The kind, a
## status number, the links to other content stay as they were. Returns its path, or "" with
## `error` filled in.
## `replacing`: the copy is to take the source's place (Copy into a genre), so what makes it the same
## thing (a status's number) stays; otherwise the copy is a new thing beside it (`on_copied`).
static func create_copy(source: ContentDef, owner: String, display_name: String, error: Array[String] = [], replacing: bool = false) -> String:
	var type: StringName = source.content_type()
	if not may_own(type, owner):
		error.append("%s cannot make %s content (a genre's type is that genre's alone)" % [owner, type])
		return ""
	# Its own sub-resources are copied; what it links to on disk (a model, another piece) is shared.
	var def: ContentDef = source.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as ContentDef
	def.id = next_free_id(type, owner)
	def.display_name = display_name
	def.on_copied(owner, replacing)
	return _save_new(def, type, owner, display_name, error)


## A name as a file name: lower case, words joined by underscores, nothing else.
static func file_stem(display_name: String) -> String:
	var out: String = ""
	for ch: String in display_name.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "new"


static func _genres() -> PackedStringArray:
	if genres_override != null:
		return PackedStringArray(genres_override)
	var game: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/game.json"))
	var out := PackedStringArray()
	if game is Dictionary:
		for g: Variant in (game as Dictionary).get("genres", []) as Array:
			out.append(String(g))
	return out


static func _extends(cls: StringName, bases: Dictionary) -> bool:
	var c: StringName = bases.get(cls, &"")
	var guard: int = 0
	while c != &"" and guard < 64:
		if c == BASE_CLASS:
			return true
		c = bases.get(c, &"")
		guard += 1
	return false


static func _owner_of_script(path: String) -> String:
	if path.begins_with("res://game/"):
		return path.trim_prefix("res://game/").get_slice("/", 0)
	return ""


static func _tres_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry: String in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			out.append_array(_tres_under(dir.path_join(entry.trim_suffix("/"))))
		elif entry.ends_with(".tres"):
			out.append(dir.path_join(entry))
	out.sort()
	return out
