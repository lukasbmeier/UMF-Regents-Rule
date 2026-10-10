@tool
class_name RuleSetDef extends ContentDef
## A SET OF HOT RULES (CONTENT_TOOLING_SPEC §4, docs/rules/content.md, DECISIONS #201): numbers the
## game is tuned by while it runs, served by the server in the `hot_rule` table so every client,
## old builds too, follows the live value, and changed by an admin without a republish.
##
## `rules` declares this owner's rules (key `<owner>.<name>`). `overrides` sets THIS GAME's value
## for another owner's rule (a genre tuning the foundation's interact range), so no game edits the
## foundation's own file. The server reads them through `hot::<owner>::<NAME>` (generated, so a
## misspelt rule does not build); the client through `HotRules`.
##
## Group rules however reads best (one set per owner, or "lobby", "economy"); a key is unique
## across every set in the game.

## This owner's rules.
@export var rules: Array[RuleEntry] = []
## This game's values for other owners' rules.
@export var overrides: Array[RuleOverride] = []


func content_type() -> StringName:
	return &"rules"


func why_no_workbench() -> String:
	return "rules are numbers to tune while the game runs, so the game is their workbench. Change a default here in the Inspector (Rules: open one); a game changes one of the template's with an entry in its genre's rule set (Overrides). Try values live as the admin (in game: Escape, Rules), then the Content panel's Keep live tuning writes them back here"


func to_bake() -> Dictionary:
	var owner: String = ContentLibrary.owner_of_path(resource_path)
	var out_rules: Array = []
	for r: RuleEntry in rules:
		if r != null:
			out_rules.append(r.to_bake(owner))
	var out_over: Array = []
	for o: RuleOverride in overrides:
		if o != null:
			out_over.append({"key": o.key, "number": o.number, "text": o.text})
	return {"id": id, "name": display_name, "rules": out_rules, "overrides": out_over}


func validate() -> Array[String]:
	var out: Array[String] = super()
	var seen: Dictionary = {}
	for r: RuleEntry in rules:
		if r == null:
			out.append("an empty slot in its rules")
			continue
		out.append_array(r.problems())
		if seen.has(r.name):
			out.append("rule '%s' is declared twice" % r.name)
		seen[r.name] = true
		if parity_names().has(String(r.name)):
			out.append("rule '%s' is a movement number clients predict exactly (shared/movement_config.json): it cannot be hot" % r.name)
	for o: RuleOverride in overrides:
		if o == null:
			out.append("an empty slot in its overrides")
	return out


## Against every rule set in the game: keys unique, each override of a rule that exists, of
## another owner's, within its bounds, and one per key.
func validate_with(all: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	var mine: String = ContentLibrary.owner_of_path(resource_path)
	var declared: Dictionary = {}   # key -> [RuleEntry, owner, set path]
	var overridden: Dictionary = {} # key -> set path
	for d: ContentDef in all:
		var s: RuleSetDef = d as RuleSetDef
		if s == null:
			continue
		var owner: String = ContentLibrary.owner_of_path(s.resource_path)
		for r: RuleEntry in s.rules:
			if r == null:
				continue
			var key: String = "%s.%s" % [owner, r.name]
			if declared.has(key) and s == self and declared[key][2] != s.resource_path:
				out.append("rule '%s' is also declared in %s" % [key, declared[key][2]])
			if not declared.has(key):
				declared[key] = [r, owner, s.resource_path]
		if s != self:
			for o: RuleOverride in s.overrides:
				if o != null:
					overridden[o.key] = s.resource_path
	for o: RuleOverride in overrides:
		if o == null:
			continue
		if not declared.has(o.key):
			out.append("it overrides '%s', which no rule set declares" % o.key)
			continue
		var r: RuleEntry = declared[o.key][0]
		if declared[o.key][1] == mine:
			out.append("it overrides its own rule '%s': change that rule's value instead" % o.key)
		if overridden.has(o.key):
			out.append("'%s' is also overridden in %s: a game sets each rule once" % [o.key, overridden[o.key]])
		if r.kind != RuleEntry.Kind.TEXT and (o.number < r.minimum or o.number > r.maximum):
			out.append("its value for '%s' (%s) is outside %s..%s" % [o.key, o.number, r.minimum, r.maximum])
		if r.kind == RuleEntry.Kind.INTEGER and o.number != floorf(o.number):
			out.append("its value for '%s' is not a whole number" % o.key)
		if r.kind == RuleEntry.Kind.FLAG and o.number != 0.0 and o.number != 1.0:
			out.append("its value for '%s' is a flag: 0 or 1" % o.key)
	return out


## THIS GAME'S RULES: every declared rule with its default here (its declared value, or a listed
## genre's override), from `sets` (all of them when empty): { key: { entry: RuleEntry, owner,
## number, text, overridden_by } }. The same sum build.rs makes for the server.
static func effective(sets: Array[ContentDef] = []) -> Dictionary:
	var all: Array[ContentDef] = sets if not sets.is_empty() else ContentLibrary.items(&"rules")
	var out: Dictionary = {}
	for d: ContentDef in all:
		var s: RuleSetDef = d as RuleSetDef
		if s == null:
			continue
		var owner: String = ContentLibrary.owner_of_path(s.resource_path)
		for r: RuleEntry in s.rules:
			if r != null:
				out["%s.%s" % [owner, r.name]] = {"entry": r, "owner": owner, "number": r.number, "text": r.text, "overridden_by": ""}
	for d: ContentDef in all:
		var s: RuleSetDef = d as RuleSetDef
		if s == null:
			continue
		for o: RuleOverride in s.overrides:
			if o != null and out.has(o.key):
				var e: Dictionary = out[o.key]
				e["number"] = o.number
				e["text"] = o.text
				e["overridden_by"] = ContentLibrary.owner_of_path(s.resource_path)
	return out


## The names clients predict exactly, which no hot rule may take (the movement model's).
static func parity_names() -> PackedStringArray:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/movement_config.json"))
	var out := PackedStringArray()
	if parsed is Dictionary:
		for k: Variant in (parsed as Dictionary).keys():
			if not String(k).begins_with("_"):
				out.append(String(k))
	return out
