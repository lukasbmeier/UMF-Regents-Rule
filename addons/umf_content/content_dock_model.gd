@tool
class_name ContentDockModel extends RefCounted
## WHAT THE CONTENT DOCK KNOWS AND DOES, without any of its buttons (DECISIONS #200): the types
## and their pieces, the problems, making a piece, baking. The dock (`content_dock.gd`) only draws
## this and passes clicks to it, so the whole of its behaviour is tested headless (the `content`
## suite) and a later step adds a toolbar action (`add_action`) without touching the view.

const BAKE: GDScript = preload("res://tools/bake_content.gd")

## The toolbar, in order: [{ id, label, tooltip, run: Callable }]. The dock draws a button for each.
var actions: Array[Dictionary] = []

## The last check: [{ path, text }], a path ("" when the problem is not one file's) and a sentence.
var problems: Array[Dictionary] = []
## Whether the bake on disk was current at the last check, and what was out of date.
var stale: Array[String] = []


## A toolbar button. Later steps (the rules panel, the Catalog) add theirs here.
func add_action(id: StringName, label: String, tooltip: String, run: Callable) -> void:
	actions.append({"id": id, "label": label, "tooltip": tooltip, "run": run})


## Every type with how many pieces it has and how many problems: [{ type, owner, count, problems }].
func type_rows() -> Array[Dictionary]:
	var counts: Dictionary = {}
	for e: Dictionary in ContentLibrary.load_all():
		var def: ContentDef = e["def"]
		if def != null:
			counts[def.content_type()] = int(counts.get(def.content_type(), 0)) + 1
	var out: Array[Dictionary] = []
	for t: Dictionary in ContentLibrary.types():
		var type: StringName = t["type"]
		out.append({"type": type, "owner": t["owner"], "count": int(counts.get(type, 0)),
			"problems": problems_for_type(type).size()})
	return out


## A type's pieces whose name, id or file matches `filter` (any of them; empty: all), by id:
## [{ def, path, owner, problems }].
func item_rows(type: StringName, filter: String = "") -> Array[Dictionary]:
	var f: String = filter.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	for e: Dictionary in ContentLibrary.load_all():
		var def: ContentDef = e["def"]
		if def == null or def.content_type() != type:
			continue
		var path: String = e["path"]
		if not f.is_empty() and not (def.display_name.to_lower().contains(f) or str(def.id) == f
				or path.get_file().to_lower().contains(f)):
			continue
		out.append({"def": def, "path": path, "owner": e["owner"], "problems": problems_for(path).size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["def"] as ContentDef).id < (b["def"] as ContentDef).id)
	return out


## Who may make a piece of `type`: the foundation and every genre for a foundation type, the genre
## alone for a genre's.
func owners_for(type: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for o: String in ContentLibrary.owners():
		if ContentLibrary.may_own(type, o):
			out.append(o)
	return out


## Check everything, as the bake would (it is the bake, writing nothing). Returns the problems.
func check() -> Array[Dictionary]:
	var r: Dictionary = BAKE.call(&"bake", false)
	problems.clear()
	for e: String in r["errors"] as Array:
		problems.append(_problem(e))
	stale.assign(r["stale"])
	return problems


## Bake (writes the files). Returns { ok, problems, summary }.
func bake() -> Dictionary:
	var r: Dictionary = BAKE.call(&"bake", true)
	problems.clear()
	for e: String in r["errors"] as Array:
		problems.append(_problem(e))
	if problems.is_empty():
		stale.clear()
	else:
		stale.assign(r["stale"])
	return {"ok": problems.is_empty(), "problems": problems, "summary": r["summary"]}


## Make a piece: returns its path, or "" with `error` filled in.
func create(type: StringName, owner: String, display_name: String, error: Array[String] = []) -> String:
	if display_name.strip_edges().is_empty():
		error.append("give it a name first")
		return ""
	return ContentLibrary.create(type, owner, display_name.strip_edges(), error)


func problems_for(path: String) -> Array[Dictionary]:
	return problems.filter(func(p: Dictionary) -> bool: return p["path"] == path)


func problems_for_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in problems:
		var path: String = p["path"]
		if path.is_empty():
			continue
		var res: Resource = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
		var folder_type: String = path.get_base_dir().get_file()
		if (res is ContentDef and (res as ContentDef).content_type() == type) or folder_type == String(type):
			out.append(p)
	return out


## "res://x.tres: why" -> { path, text }.
static func _problem(e: String) -> Dictionary:
	if e.begins_with("res://") or e.begins_with("user://"):
		var cut: int = e.find(": ")
		if cut > 0:
			return {"path": e.substr(0, cut), "text": e.substr(cut + 2)}
		var sp: int = e.find(" ")
		if sp > 0:
			return {"path": e.substr(0, sp), "text": e.substr(sp + 1)}
	return {"path": "", "text": e}
