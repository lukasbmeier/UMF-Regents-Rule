class_name SchemaFingerprint extends RefCounted
## WHICH VERSION OF THE GAME A SERVER RUNS, as far as a client can tell: a short hash of the parts
## of the module's schema that the generated bindings depend on (DECISIONS #164).
##
## A client and a server only work together when the client's bindings were generated from the
## schema the server runs. A friend on last week's build against this week's server fails in
## confusing ways (a table that does not exist, a reducer with other arguments, rows decoded into
## the wrong columns), so the adapter fetches the server's schema before it connects and refuses a
## mismatch with words a player can act on.
##
## What counts: the types (their names and shapes), every table's name, row type and access
## (public or private), every reducer's name and arguments, and the explicit names. What does not:
## indexes, sequences, schedules, row-level security, reducer bodies, the data in shared/. Those
## change what the server does, not whether this client can talk to it.
##
## The same function runs at codegen (`tools/write_schema_fingerprint.gd` writes the bindings'
## fingerprint) and at connect, on the same JSON, so no other implementation has to agree with it.

## Hex characters kept. 12 (48 bits) is plenty to tell versions apart and short enough to read
## out to a friend.
const LENGTH: int = 12


## The fingerprint of a schema as the server serves it (`/v1/database/<db>/schema?version=10`).
## Empty when the text is not a schema.
static func of(schema_text: String) -> String:
	# An instance rather than JSON.parse_string, which reports bad text as an engine error: an
	# answer that is not a schema (a web page, an empty body) is expected here.
	var json := JSON.new()
	if json.parse(schema_text) != OK or not json.data is Dictionary:
		return ""
	var canonical: Variant = _what_counts(json.data as Dictionary)
	if canonical == null:
		return ""
	return JSON.stringify(canonical, "", true).sha256_text().left(LENGTH)


## The parts that count, in a form whose text does not depend on key order. The v10 schema is
## a list of one-key sections; an unknown format counts in full (safer to call it different).
static func _what_counts(schema: Dictionary) -> Variant:
	var sections: Variant = schema.get("sections")
	if not sections is Array:
		return schema if not schema.is_empty() else null
	var out: Dictionary = {}
	for section: Variant in sections as Array:
		if not section is Dictionary or (section as Dictionary).size() != 1:
			continue
		var key: String = String((section as Dictionary).keys()[0])
		var body: Variant = (section as Dictionary)[key]
		# ORDER IS NOT A VERSION (DECISIONS #186): the server lists its tables, reducers and names in
		# a different order on each publish, and a fingerprint of that order called every republish
		# "a different version of the game". Those lists are sorted; the Typespace is not (tables
		# point into it by position, so its order is part of the schema).
		match key:
			"Typespace":
				out[key] = body
			"Types":
				out[key] = _sorted(body)
			"ExplicitNames":
				var names: Variant = body
				if names is Dictionary and (names as Dictionary).get("entries") is Array:
					names = {"entries": _sorted((names as Dictionary)["entries"])}
				out[key] = names
			"Tables":
				out[key] = _sorted(_pick(body, ["source_name", "product_type_ref", "table_access", "table_type", "is_event"]))
			"Reducers":
				out[key] = _sorted(_pick(body, ["source_name", "params", "visibility"]))
	return out if not out.is_empty() else null


## A list in an order of its own content's (each entry's text, keys sorted), whatever order it came in.
static func _sorted(list: Variant) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	var keyed: Array = []
	for entry: Variant in list as Array:
		keyed.append([JSON.stringify(entry, "", true), entry])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	for k: Array in keyed:
		out.append(k[1])
	return out


## Each entry of a list reduced to the named fields.
static func _pick(list: Variant, fields: Array[String]) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for entry: Variant in list as Array:
		if not entry is Dictionary:
			continue
		var kept: Dictionary = {}
		for f: String in fields:
			if (entry as Dictionary).has(f):
				kept[f] = (entry as Dictionary)[f]
		out.append(kept)
	return out


## The schema endpoint a client asks for `database` on `host` (any of http, https, ws, wss).
static func url(host: String, database: String) -> String:
	var base: String = host.strip_edges().rstrip("/")
	if base.begins_with("wss://"):
		base = "https://" + base.substr("wss://".length())
	elif base.begins_with("ws://"):
		base = "http://" + base.substr("ws://".length())
	return "%s/v1/database/%s/schema?version=10" % [base, database.uri_encode()]


## What a player is told when the two differ.
static func mismatch_message(ours: String, theirs: String) -> String:
	return ("This server is running a different version of the game. Get the host's current "
		+ "build (or, if you are the host, export the game again).\n(your game: %s, the server: %s)") \
		% [ours, theirs]
