extends "res://tests/suite_base.gd"
## The `version` suite (tests/test_runner.gd runs it; `-- --only=version` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_version_tests()
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
