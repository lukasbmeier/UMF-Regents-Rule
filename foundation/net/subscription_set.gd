class_name SubscriptionSet extends RefCounted
## A named group of subscription queries that are applied and torn down together.
##
## The foundation boots with one "core" set. Genre layers add more — e.g. an MMO adds a
## spatial set whose queries are rebuilt as the player crosses grid cells. Keeping this as
## its own object (rather than raw SQL strings on SpaceTimeSync) is what makes that swap
## possible without touching components.

signal applied(set: SubscriptionSet)
signal ended(set: SubscriptionSet, error: String)

var name: StringName
var queries: Array[String] = []
var is_applied: bool = false
var error_message: String = ""
## Opaque SDK subscription handle. Only SpaceTimeSync reads or writes this.
var _handle: RefCounted = null

static func for_tables(p_name: StringName, tables: Array[StringName]) -> SubscriptionSet:
	var s := SubscriptionSet.new()
	s.name = p_name
	for t in tables:
		s.add_table(t)
	return s

func add_table(table: StringName) -> SubscriptionSet:
	queries.append("SELECT * FROM %s" % table)
	return self

## Raw SQL. Prefer SpaceTimeSync.query_builder() for anything with user-provided values.
func add_query(sql: String) -> SubscriptionSet:
	queries.append(sql)
	return self

func _to_string() -> String:
	return "SubscriptionSet(%s, %d queries, applied=%s)" % [name, queries.size(), is_applied]
