class_name SchemaContract extends RefCounted
## WHAT A CLIENT NEEDS FROM A SERVER (docs/rules/compatibility.md, DECISIONS #198): every public
## table its bindings decode, with the same row, and every reducer it can call, with the same
## arguments. A server may have MORE (new tables, new reducers, private anything): an old client
## never asks for them. So a build keeps working on a newer server as long as the server only added.
##
## The contract is written beside the bindings at codegen (`tools/write_schema_fingerprint.gd` ->
## `spacetime_bindings/schema_contract.json`), and at connect the client checks it against the
## schema the server serves. The fingerprint (`SchemaFingerprint`) is still what a player is shown
## to tell versions apart; it no longer decides.
##
## Types are compared by shape AND name, refs resolved: a row is its columns in order, each column
## its name and type, a named type its name and shape. Column order matters (rows are decoded in
## order), so a column added to an existing table breaks old clients, and is caught.

## Bump when the contract's form changes; a contract of another format is not compared (the
## client falls back to the fingerprint).
const FORMAT: int = 1
## The reducer whose name carries a build's compatibility generation (`compat_generation_<N>`,
## written by server/build.rs from shared/game.json `compat`). Two builds of different generations
## never play together, whatever else they share: it is how a deliberate break (a change to what
## clients simulate) is made.
const GENERATION_PREFIX: String = "compat_generation_"


## The contract of a schema as the server serves it (`/v1/database/<db>/schema?version=10`).
## Empty when the text is not a schema.
static func of(schema_text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(schema_text) != OK or not json.data is Dictionary:
		return {}
	var sections: Variant = (json.data as Dictionary).get("sections")
	if not sections is Array:
		return {}
	var by_key: Dictionary = {}
	for section: Variant in sections as Array:
		if section is Dictionary and (section as Dictionary).size() == 1:
			var key: String = String((section as Dictionary).keys()[0])
			by_key[key] = (section as Dictionary)[key]
	var typespace: Array = []
	var ts: Variant = by_key.get("Typespace")
	if ts is Dictionary and (ts as Dictionary).get("types") is Array:
		typespace = (ts as Dictionary)["types"]
	var names: Dictionary = {}
	if by_key.get("Types") is Array:
		for t: Variant in by_key["Types"] as Array:
			if t is Dictionary:
				var sn: Variant = (t as Dictionary).get("source_name")
				var n: String = String((sn as Dictionary).get("source_name", "")) if sn is Dictionary else ""
				names[int((t as Dictionary).get("ty", -1))] = n
	var tables: Dictionary = {}
	if by_key.get("Tables") is Array:
		for t: Variant in by_key["Tables"] as Array:
			if not t is Dictionary or not _has_key((t as Dictionary).get("table_access"), "Public"):
				continue
			var row: String = _type({"Ref": (t as Dictionary).get("product_type_ref", -1)}, typespace, names, [])
			tables[String((t as Dictionary).get("source_name", ""))] = row
	var reducers: Dictionary = {}
	if by_key.get("Reducers") is Array:
		for r: Variant in by_key["Reducers"] as Array:
			if not r is Dictionary or not _has_key((r as Dictionary).get("visibility"), "ClientCallable"):
				continue
			var params: Variant = (r as Dictionary).get("params", {})
			reducers[String((r as Dictionary).get("source_name", ""))] = _type({"Product": params}, typespace, names, [])
	if tables.is_empty() and reducers.is_empty():
		return {}
	return {"format": FORMAT, "tables": tables, "reducers": reducers}


## Why `contract` cannot use the server whose schema is `server_schema_text`, one sentence each;
## empty when it can. A server that answers with something other than a schema is not judged here.
static func problems(contract: Dictionary, server_schema_text: String) -> PackedStringArray:
	return problems_against(contract, of(server_schema_text))


## The same, against a server contract already worked out.
static func problems_against(contract: Dictionary, server: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if server.is_empty() or int(contract.get("format", 0)) != FORMAT:
		return out
	var theirs_t: Dictionary = server.get("tables", {})
	var ours_t: Dictionary = contract.get("tables", {})
	for t: String in _sorted_keys(ours_t):
		if not theirs_t.has(t):
			out.append("the server has no table '%s'" % t)
		elif String(theirs_t[t]) != String(ours_t[t]):
			out.append("the server's table '%s' has other columns" % t)
	var theirs_r: Dictionary = server.get("reducers", {})
	var ours_r: Dictionary = contract.get("reducers", {})
	var g_ours: int = generation(contract)
	var g_theirs: int = generation(server)
	if g_ours > 0 and g_ours != g_theirs:
		out.insert(0, "this build is compatibility generation %d and the server is %s" % [g_ours,
			"generation %d" % g_theirs if g_theirs > 0 else "older than generations"])
	for r: String in _sorted_keys(ours_r):
		if r.begins_with(GENERATION_PREFIX):
			continue
		if not theirs_r.has(r):
			out.append("the server has no action '%s'" % r)
		elif String(theirs_r[r]) != String(ours_r[r]):
			out.append("the server's action '%s' takes other arguments" % r)
	return out


## A contract's compatibility generation; 0 for one from before generations (DECISIONS #198).
static func generation(contract: Dictionary) -> int:
	var reducers: Variant = contract.get("reducers")
	if not reducers is Dictionary:
		return 0
	for r: Variant in (reducers as Dictionary).keys():
		var n: String = String(r)
		if n.begins_with(GENERATION_PREFIX) and n.substr(GENERATION_PREFIX.length()).is_valid_int():
			return n.substr(GENERATION_PREFIX.length()).to_int()
	return 0


## What a player is told when this build cannot play on the server.
static func refusal_message(problems_found: PackedStringArray, ours: String, theirs: String) -> String:
	var shown: PackedStringArray = problems_found.slice(0, 3)
	var more: String = " (and %d more)" % (problems_found.size() - 3) if problems_found.size() > 3 else ""
	return ("This server runs a version of the game this build cannot play: %s%s. Get the host's "
		+ "current build (or, if you are the host, export the game again).\n(your game: %s, the server: %s)") \
		% ["; ".join(shown), more, ours, theirs]


## A type as text: its shape and the names in it, refs resolved (a ref already being resolved is
## named only, so a recursive type ends).
static func _type(t: Variant, typespace: Array, names: Dictionary, seen: Array) -> String:
	if not t is Dictionary or (t as Dictionary).size() != 1:
		return JSON.stringify(t, "", true)
	var kind: String = String((t as Dictionary).keys()[0])
	var body: Variant = (t as Dictionary)[kind]
	match kind:
		"Ref":
			var i: int = int(body)
			var named: String = String(names.get(i, "#%d" % i))
			if seen.has(i) or i < 0 or i >= typespace.size():
				return named
			return named + _type(typespace[i], typespace, names, seen + [i])
		"Product":
			return "(" + ",".join(_fields(body, "elements", typespace, names, seen)) + ")"
		"Sum":
			return "<" + "|".join(_fields(body, "variants", typespace, names, seen)) + ">"
		"Array":
			return "[" + _type(body, typespace, names, seen) + "]"
		"Map":
			var m: Dictionary = body if body is Dictionary else {}
			return "{" + _type(m.get("key_ty"), typespace, names, seen) + ":" \
				+ _type(m.get("ty"), typespace, names, seen) + "}"
	if body is Array and (body as Array).is_empty():
		return kind   # a primitive: U32, String, Bool, ...
	return JSON.stringify(t, "", true)


static func _fields(body: Variant, key: String, typespace: Array, names: Dictionary, seen: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not body is Dictionary or not (body as Dictionary).get(key) is Array:
		return out
	for e: Variant in (body as Dictionary)[key] as Array:
		if not e is Dictionary:
			continue
		var n: Variant = (e as Dictionary).get("name")
		var label: String = String((n as Dictionary).get("some", "")) if n is Dictionary else ""
		out.append(label + ":" + _type((e as Dictionary).get("algebraic_type"), typespace, names, seen))
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


static func _has_key(d: Variant, key: String) -> bool:
	return d is Dictionary and (d as Dictionary).has(key)
