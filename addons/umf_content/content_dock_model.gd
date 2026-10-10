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


## THE CATALOG (CONTENT_TOOLING_SPEC §3.3, DECISIONS #203): every piece of every type as a card:
## [{ def, path, owner, type, badge, sentence, thumbnail, workbench }], by type then id. `badge`:
## "red" (something is wrong: the first problem is `sentence`), "amber" (valid, but not yet seen in
## its workbench: no thumbnail), "green". Filters: a type (&"" all) and a badge ("" all).
func catalog_rows(type_filter: StringName = &"", badge_filter: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in ContentLibrary.load_all():
		var def: ContentDef = e["def"]
		if def == null:
			continue
		var type: StringName = def.content_type()
		if type_filter != &"" and type != type_filter:
			continue
		var path: String = e["path"]
		var why: Array[String] = def.validate()
		for p: Dictionary in problems_for(path):
			why.append(String(p["text"]))
		var bench: String = def.workbench_scene()
		var thumb: String = Workbench.thumbnail_path(def)
		var badge: String = "red" if not why.is_empty() else ("amber" if not bench.is_empty() and not FileAccess.file_exists(thumb) else "green")
		var sentence: String = why[0] if not why.is_empty() else ("not yet seen in its workbench (no picture): open it there, or Regenerate" if badge == "amber" else "")
		if not badge_filter.is_empty() and badge != badge_filter:
			continue
		out.append({"def": def, "path": path, "owner": e["owner"], "type": type, "badge": badge,
			"sentence": sentence, "thumbnail": thumb, "workbench": bench})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["type"]) < String(b["type"]) or (a["type"] == b["type"] and (a["def"] as ContentDef).id < (b["def"] as ContentDef).id))
	return out


## Who may make a piece of `type`: the foundation and every genre for a foundation type, the genre
## alone for a genre's.
## Who may make a new piece of `type` HERE: in the template (no genres) the foundation; in a game its
## genres only, because the foundation's content is the template's and comes in with its updates
## (DECISIONS #207: a game's foundation piece would collide with the template's).
func owners_for(type: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var game: bool = ContentLibrary.owners().size() > 1
	for o: String in ContentLibrary.owners():
		if game and o == ContentLibrary.FOUNDATION:
			continue
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


## The rows `tools/rules_live.sh` prints (`spacetime sql`'s table): [{ key, number, text }].
static func parse_live(lines: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var past_header: bool = false
	for l: String in lines:
		if not past_header:
			past_header = l.strip_edges().begins_with("---")
			continue
		var cells: PackedStringArray = l.split("|")
		if cells.size() < 3:
			continue
		var key: String = cells[0].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if key.is_empty():
			continue
		out.append({"key": key, "number": cells[1].strip_edges().to_float(),
			"text": cells[2].strip_edges().trim_prefix("\"").trim_suffix("\"")})
	return out


## KEEP LIVE TUNING (DECISIONS #201): make the values an admin set on the server this game's
## defaults. A rule this game's genre declares takes the value itself; a foundation rule becomes an
## override in a genre's rule set (the one already overriding it, else the first genre's: never the
## foundation's own file, which every game shares), except in the template, which has no genre.
## Returns { kept: [sentences], problems: [sentences] }; the files are saved.
func keep_live(rows: Array[Dictionary]) -> Dictionary:
	var kept: Array[String] = []
	var bad: Array[String] = []
	var eff: Dictionary = RuleSetDef.effective()
	var sets: Array[ContentDef] = ContentLibrary.items(&"rules")
	var genres: PackedStringArray = ContentLibrary.owners().slice(1)
	var touched: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = row["key"]
		if not eff.has(key):
			bad.append("'%s' is live on the server but no rule set here declares it" % key)
			continue
		var entry: RuleEntry = eff[key]["entry"]
		var number: float = float(row["number"])
		if entry.kind != RuleEntry.Kind.TEXT and (number < entry.minimum or number > entry.maximum):
			bad.append("'%s' = %s on the server is outside %s..%s here: not kept" % [key, number, entry.minimum, entry.maximum])
			continue
		var owner: String = eff[key]["owner"]
		if owner != ContentLibrary.FOUNDATION or genres.is_empty():
			entry.number = number
			entry.text = String(row["text"])
			var home: RuleSetDef = _set_declaring(sets, entry)
			touched[home] = true
			kept.append("%s = %s (its own value, %s)" % [key, _shown(entry, number, row), home.resource_path.get_file()])
			continue
		var target: RuleSetDef = null
		var override: RuleOverride = null
		for d: ContentDef in sets:
			var s: RuleSetDef = d as RuleSetDef
			if s == null or not genres.has(ContentLibrary.owner_of_path(s.resource_path)):
				continue
			for o: RuleOverride in s.overrides:
				if o != null and o.key == key:
					target = s
					override = o
		if target == null:
			for d: ContentDef in sets:
				if d is RuleSetDef and ContentLibrary.owner_of_path(d.resource_path) == genres[0]:
					target = d as RuleSetDef
					break
		if target == null:
			var errors: Array[String] = []
			var path: String = ContentLibrary.create(&"rules", genres[0], "%s rules" % genres[0], errors)
			if path.is_empty():
				bad.append("no rule set for %s and none could be made: %s" % [genres[0], "; ".join(errors)])
				continue
			target = ResourceLoader.load(path) as RuleSetDef
			sets.append(target)
		if override == null:
			override = RuleOverride.new()
			override.key = key
			override.reason = "Kept from live tuning on the server."
			target.overrides.append(override)
		override.number = number
		override.text = String(row["text"])
		touched[target] = true
		kept.append("%s = %s (this game's override, %s)" % [key, _shown(entry, number, row), target.resource_path.get_file()])
	for s: RuleSetDef in touched:
		ResourceSaver.save(s, s.resource_path)
	return {"kept": kept, "problems": bad}


static func _set_declaring(sets: Array[ContentDef], entry: RuleEntry) -> RuleSetDef:
	for d: ContentDef in sets:
		var s: RuleSetDef = d as RuleSetDef
		if s != null and s.rules.has(entry):
			return s
	return null


static func _shown(entry: RuleEntry, number: float, row: Dictionary) -> String:
	return "\"%s\"" % row["text"] if entry.kind == RuleEntry.Kind.TEXT else str(number)


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
