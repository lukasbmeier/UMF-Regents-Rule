extends "res://tests/suite_base.gd"
## The `version` suite (tests/test_runner.gd runs it; `-- --only=version` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_version_tests()
	_run_contract_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## THE VERSION CHECK (DECISIONS #164). The fingerprint is of what the bindings depend on: the
## same for the same schema in any key order or with other indexes, different for a changed
## reducer, column, table or access. And the bindings' recorded fingerprint is the schema the last
## codegen actually read: a stale one would refuse every server, or none.
func _run_version_tests() -> void:
	print("== the version check ==")
	var text: String = SpaceTimeSync.codegen_schema_text()
	_check(not text.is_empty(), "the last codegen's schema is on disk")
	var fp: String = SchemaFingerprint.of(text)
	_check(fp.length() == SchemaFingerprint.LENGTH, "a schema has a fingerprint (%s)" % fp)
	_check(fp == SpaceTimeSync.bindings_fingerprint(),
		"the bindings' fingerprint (%s) is the schema codegen read (%s): run tools/publish.sh --codegen"
			% [SpaceTimeSync.bindings_fingerprint(), fp])
	_check(SchemaFingerprint.of("") == "" and SchemaFingerprint.of("<html>not found</html>") == ""
		and SchemaFingerprint.of("[1, 2]") == "", "text that is not a schema has none")
	var schema: Dictionary = JSON.parse_string(text) as Dictionary
	# The same schema, every key in reverse order.
	_check(SchemaFingerprint.of(JSON.stringify(_reversed_keys(schema), "", false)) == fp,
		"the same schema with its keys in another order has the same fingerprint")
	# The server lists its tables, reducers and names in another order on every publish (#186).
	var shuffled: Dictionary = schema.duplicate(true)
	for section: String in ["Tables", "Reducers", "Types"]:
		_schema_section(shuffled, section).reverse()
	var named: Variant = _schema_section_dict(shuffled, "ExplicitNames").get("entries")
	if named is Array:
		(named as Array).reverse()
	_check(SchemaFingerprint.of(JSON.stringify(shuffled)) == fp,
		"the same schema with its tables, reducers and names listed in another order has the same fingerprint")
	var tables: Array = _schema_section(schema, "Tables")
	var reducers: Array = _schema_section(schema, "Reducers")
	_check(not tables.is_empty() and not reducers.is_empty(), "the schema lists tables and reducers")
	if tables.is_empty() or reducers.is_empty():
		return
	var same: Dictionary = schema.duplicate(true)
	(_schema_section(same, "Tables")[0] as Dictionary)["indexes"] = []
	_schema_section(same, "RowLevelSecurity").clear()
	_check(SchemaFingerprint.of(JSON.stringify(same)) == fp,
		"another index or another row-level filter does not change it (the client is unaffected)")
	var cases: Dictionary[String, Callable] = {
		"a reducer's argument retyped": func(d: Dictionary) -> void:
			var params: Array = ((_schema_section(d, "Reducers")[0] as Dictionary)["params"] as Dictionary)["elements"]
			(params[0] as Dictionary)["algebraic_type"] = {"String": []},
		"a reducer added": func(d: Dictionary) -> void:
			var r: Dictionary = (_schema_section(d, "Reducers")[0] as Dictionary).duplicate(true)
			r["source_name"] = "brand_new_reducer"
			_schema_section(d, "Reducers").append(r),
		# The FIRST PUBLIC table: the server lists tables in a new order on each publish (#186), and
		# when a private one came first this case changed nothing and failed.
		"a table made private": func(d: Dictionary) -> void:
			for t: Variant in _schema_section(d, "Tables"):
				if (t as Dictionary)["table_access"].has("Public"):
					(t as Dictionary)["table_access"] = {"Private": []}
					return,
		"a table renamed": func(d: Dictionary) -> void:
			(_schema_section(d, "Tables")[0] as Dictionary)["source_name"] = "renamed",
		"a column added to a row type": func(d: Dictionary) -> void:
			var types: Array = (_schema_section_dict(d, "Typespace")["types"]) as Array
			var product: Dictionary = (types[0] as Dictionary)["Product"]
			(product["elements"] as Array).append({"name": {"some": "extra"}, "algebraic_type": {"U8": []}}),
	}
	for what: String in cases:
		var changed: Dictionary = schema.duplicate(true)
		cases[what].call(changed)
		var other: String = SchemaFingerprint.of(JSON.stringify(changed))
		_check(not other.is_empty() and other != fp, "%s changes it (%s -> %s)" % [what, fp, other])
	_check(SchemaFingerprint.url("http://127.0.0.1:3000/", "umf-test")
			== "http://127.0.0.1:3000/v1/database/umf-test/schema?version=10"
		and SchemaFingerprint.url("wss://maincloud.spacetimedb.com", "my game").begins_with(
			"https://maincloud.spacetimedb.com/v1/database/my%20game/"),
		"the schema is asked for at the server's address, over http(s)")
	_check(SchemaFingerprint.mismatch_message("aaa", "bbb").contains("different version")
		and SchemaFingerprint.mismatch_message("aaa", "bbb").contains("aaa"),
		"a mismatch is explained, with both fingerprints")


## OLD CLIENTS ON NEW SERVERS (docs/rules/compatibility.md, DECISIONS #198). A build's contract is
## what it needs: a server that ADDED (a table, a reducer, anything private) still satisfies it; one
## that changed or removed what the build uses, or is of another generation, does not. And every
## release snapshot of this generation (`shared/compat/<database>/`) still plays on this schema.
func _run_contract_tests() -> void:
	print("== compatibility: the contract ==")
	var text: String = SpaceTimeSync.codegen_schema_text()
	var mine: Dictionary = SchemaContract.of(text)
	var saved: Dictionary = SpaceTimeSync.bindings_contract()
	_check(not mine.is_empty() and int(saved.get("format", 0)) == SchemaContract.FORMAT
		and JSON.stringify(saved.get("tables"), "", true) == JSON.stringify(mine["tables"], "", true)
		and JSON.stringify(saved.get("reducers"), "", true) == JSON.stringify(mine["reducers"], "", true),
		"the bindings' contract is the schema codegen read (run tools/publish.sh --codegen)")
	var gen: int = SchemaContract.generation(mine)
	_check(gen >= 1, "the server carries its compatibility generation (%d)" % gen)
	_check(SchemaContract.problems(mine, text).is_empty(), "a build plays on the server it was made from")
	_check(SchemaContract.of("").is_empty() and SchemaContract.problems(mine, "<html></html>").is_empty(),
		"text that is not a schema is not judged (the connection explains it)")
	var schema: Dictionary = JSON.parse_string(text) as Dictionary
	var public_table: Dictionary = {}
	for t: Variant in _schema_section(schema, "Tables"):
		if ((t as Dictionary)["table_access"] as Dictionary).has("Public"):
			public_table = t
			break
	var callable: Dictionary = {}
	for r: Variant in _schema_section(schema, "Reducers"):
		var rd: Dictionary = r as Dictionary
		if (rd["visibility"] as Dictionary).has("ClientCallable") \
				and not ((rd["params"] as Dictionary)["elements"] as Array).is_empty() \
				and not String(rd["source_name"]).begins_with(SchemaContract.GENERATION_PREFIX):
			callable = rd
			break
	var pt_name: String = String(public_table.get("source_name", ""))
	var r_name: String = String(callable.get("source_name", ""))
	_check(not pt_name.is_empty() and not r_name.is_empty(),
		"the schema has a public table (%s) and a callable reducer (%s)" % [pt_name, r_name])
	if pt_name.is_empty() or r_name.is_empty():
		return
	# A NEWER SERVER that only added: the old build still plays.
	var added: Dictionary = schema.duplicate(true)
	var t2: Dictionary = public_table.duplicate(true)
	t2["source_name"] = "a_table_from_the_future"
	_schema_section(added, "Tables").append(t2)
	var r2: Dictionary = callable.duplicate(true)
	r2["source_name"] = "an_action_from_the_future"
	_schema_section(added, "Reducers").append(r2)
	var types: Array = (_schema_section_dict(added, "Typespace")["types"]) as Array
	types.append({"Product": {"elements": [{"name": {"some": "x"}, "algebraic_type": {"U8": []}}]}})
	var r3: Dictionary = callable.duplicate(true)
	r3["source_name"] = r_name + "_v2"
	((r3["params"] as Dictionary)["elements"] as Array).append({"name": {"some": "extra"}, "algebraic_type": {"U8": []}})
	_schema_section(added, "Reducers").append(r3)
	var found: PackedStringArray = SchemaContract.problems(mine, JSON.stringify(added))
	_check(found.is_empty(),
		"an older build plays on a server that added a table, a type and reducers (a _v2 beside the old) %s" % str(found))
	_check(SchemaFingerprint.of(JSON.stringify(added)) != SchemaFingerprint.of(text),
		"(while the fingerprint, which a player is shown, does differ)")
	# What an old build cannot survive.
	var breaks: Dictionary[String, Callable] = {
		"a column added to a table it decodes": func(d: Dictionary) -> void:
			var ts: Array = (_schema_section_dict(d, "Typespace")["types"]) as Array
			var product: Dictionary = (ts[int(public_table["product_type_ref"])] as Dictionary)["Product"]
			(product["elements"] as Array).append({"name": {"some": "extra"}, "algebraic_type": {"U8": []}}),
		"a table it decodes removed": func(d: Dictionary) -> void:
			var tl: Array = _schema_section(d, "Tables")
			for i: int in tl.size():
				if String((tl[i] as Dictionary)["source_name"]) == pt_name:
					tl.remove_at(i)
					return,
		"a table it decodes made private": func(d: Dictionary) -> void:
			for t: Variant in _schema_section(d, "Tables"):
				if String((t as Dictionary)["source_name"]) == pt_name:
					(t as Dictionary)["table_access"] = {"Private": []},
		"a reducer's argument retyped": func(d: Dictionary) -> void:
			for r: Variant in _schema_section(d, "Reducers"):
				if String((r as Dictionary)["source_name"]) == r_name:
					var el: Array = ((r as Dictionary)["params"] as Dictionary)["elements"]
					(el[0] as Dictionary)["algebraic_type"] = {"String": []},
		"a reducer removed": func(d: Dictionary) -> void:
			var rl: Array = _schema_section(d, "Reducers")
			for i: int in rl.size():
				if String((rl[i] as Dictionary)["source_name"]) == r_name:
					rl.remove_at(i)
					return,
	}
	for what: String in breaks:
		var changed: Dictionary = schema.duplicate(true)
		breaks[what].call(changed)
		var why: PackedStringArray = SchemaContract.problems(mine, JSON.stringify(changed))
		_check(why.size() >= 1 and (why[0].contains(pt_name) or why[0].contains(r_name)),
			"%s: refused, naming it %s" % [what, str(why)])
	# A NEWER BUILD on an older server: it needs what the server never had.
	var newer: Dictionary = mine.duplicate(true)
	(newer["tables"] as Dictionary)["a_table_from_the_future"] = "()"
	var why_newer: PackedStringArray = SchemaContract.problems(newer, text)
	_check(why_newer.size() == 1 and why_newer[0].contains("a_table_from_the_future"),
		"a newer build on an older server is refused, naming what is missing %s" % str(why_newer))
	# THE GENERATION: a deliberate break, both ways round, said in its own words.
	var next_gen: Dictionary = schema.duplicate(true)
	for r: Variant in _schema_section(next_gen, "Reducers"):
		if String((r as Dictionary)["source_name"]) == SchemaContract.GENERATION_PREFIX + str(gen):
			(r as Dictionary)["source_name"] = SchemaContract.GENERATION_PREFIX + str(gen + 1)
	var why_gen: PackedStringArray = SchemaContract.problems(mine, JSON.stringify(next_gen))
	_check(why_gen.size() == 1 and why_gen[0].contains("generation %d" % gen)
		and why_gen[0].contains("generation %d" % (gen + 1)),
		"a server of the next generation refuses this build, in those words %s" % str(why_gen))
	var newer_gen: Dictionary = SchemaContract.of(JSON.stringify(next_gen))
	_check(SchemaContract.problems(newer_gen, text).size() == 1, "and a next-generation build refuses this server")
	var msg: String = SpaceTimeSync.compatibility_problem("aaa", mine, JSON.stringify(next_gen))
	_check(msg.contains("cannot play") and msg.contains("generation") and msg.contains("aaa"),
		"the player is told why, with both versions: \"%s\"" % msg.replace("\n", " / "))
	_check(SpaceTimeSync.compatibility_problem("aaa", {}, text).contains("different version")
		and SpaceTimeSync.compatibility_problem(SchemaFingerprint.of(text), {}, text).is_empty(),
		"a build with no contract (from before #198) still needs the exact fingerprint")
	# EVERY RELEASE SNAPSHOT of this generation still plays here.
	var db: String = str(Genres.game().get("database", "umf"))
	var dir: String = "res://shared/compat/%s" % db
	var checked: int = 0
	var stranded: PackedStringArray = PackedStringArray()
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var snap: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, f]))
			if not snap is Dictionary or SchemaContract.generation(snap as Dictionary) != gen:
				continue
			checked += 1
			var why_snap: PackedStringArray = SchemaContract.problems(snap as Dictionary, text)
			if not why_snap.is_empty():
				stranded.append("%s: %s" % [f, "; ".join(why_snap)])
	_check(stranded.is_empty(), "every released build of generation %d still plays on this schema (%d checked in %s) %s"
		% [gen, checked, dir, str(stranded)])


func _schema_section(schema: Dictionary, key: String) -> Array:
	for s: Variant in schema.get("sections", []) as Array:
		if s is Dictionary and (s as Dictionary).has(key) and (s as Dictionary)[key] is Array:
			return (s as Dictionary)[key] as Array
	return []


func _schema_section_dict(schema: Dictionary, key: String) -> Dictionary:
	for s: Variant in schema.get("sections", []) as Array:
		if s is Dictionary and (s as Dictionary).has(key) and (s as Dictionary)[key] is Dictionary:
			return (s as Dictionary)[key] as Dictionary
	return {}


func _reversed_keys(v: Variant) -> Variant:
	if v is Dictionary:
		var out: Dictionary = {}
		var keys: Array = (v as Dictionary).keys()
		keys.reverse()
		for k: Variant in keys:
			out[k] = _reversed_keys((v as Dictionary)[k])
		return out
	if v is Array:
		var out: Array = []
		for e: Variant in v as Array:
			out.append(_reversed_keys(e))
		return out
	return v
