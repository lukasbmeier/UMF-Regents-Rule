extends Node
## THE HOT RULES, AS THIS CLIENT SEES THEM (autoload `HotRules`, DECISIONS #201): the numbers the
## game is tuned by while it runs. The live value is the server's `hot_rule` row (the foundation
## subscribes every client to it, `InterestManager.ALWAYS_TABLES`); before one arrives, or offline,
## it is this build's default, from the rule sets (`RuleSetDef.effective`). An admin's change
## (`set_rule`) reaches every client at once, old builds included: that is what lets the game be
## tuned without anyone re-downloading it.
##
##   HotRules.number(&"foundation.interact_range_m")      a number, a whole number, a flag as 0/1
##   HotRules.flag(&"...") / HotRules.text(&"...")
##   HotRules.changed.connect(func(key): ...)             when a value changes
##
## Keys are `<owner>.<name>`; an unknown key is an error said once, and 0 / "".

## A rule's value changed (a row arrived, changed, or the connection went and defaults are back).
signal changed(key: StringName)

const TABLE: StringName = &"hot_rule"

var _defaults: Dictionary = {}
var _live: Dictionary = {}       # key -> { number, text, overridden }
var _warned: Dictionary = {}


func _ready() -> void:
	EntityRegistry.global_row_event.connect(_on_row)
	SpaceTimeSync.connection_state_changed.connect(_on_connection)


## A rule's number (a flag is 0 or 1).
func number(key: StringName) -> float:
	if _live.has(key):
		return float((_live[key] as Dictionary)["number"])
	var d: Dictionary = _default(key)
	return float(d.get("number", 0.0))


func flag(key: StringName) -> bool:
	return number(key) != 0.0


func text(key: StringName) -> String:
	if _live.has(key):
		return String((_live[key] as Dictionary)["text"])
	return String(_default(key).get("text", ""))


## Whether the value is the server's (else this build's default).
func is_live(key: StringName) -> bool:
	return _live.has(key)


## Whether an admin set it on the server.
func is_overridden(key: StringName) -> bool:
	return _live.has(key) and bool((_live[key] as Dictionary)["overridden"])


## Every rule this build knows: { key: { entry: RuleEntry, owner, number, text, overridden_by } }.
func defaults() -> Dictionary:
	if _defaults.is_empty():
		_defaults = RuleSetDef.effective()
	return _defaults


## TESTING: forget the server's values and this build's (re-read on next use).
func reset() -> void:
	_live.clear()
	_defaults.clear()


func _default(key: StringName) -> Dictionary:
	var all: Dictionary = defaults()
	if all.has(String(key)):
		return all[String(key)]
	if not _warned.has(key):
		_warned[key] = true
		push_error("HotRules: no rule '%s' (keys are <owner>.<name>; the rule sets are under */content/rules/)" % key)
	return {}


func _on_row(ev: RowEvent) -> void:
	if ev.table != TABLE:
		return
	var row: RefCounted = ev.new if ev.kind != RowEvent.Kind.DELETED else ev.old
	if row == null:
		return
	var key: StringName = StringName(String(row.get(&"key")))
	if ev.kind == RowEvent.Kind.DELETED:
		_live.erase(key)
	else:
		_live[key] = {"number": float(row.get(&"number")), "text": String(row.get(&"text")),
			"overridden": bool(row.get(&"overridden"))}
	changed.emit(key)


func _on_connection(state: int) -> void:
	if state == SpaceTimeSync.ConnectionState.DISCONNECTED and not _live.is_empty():
		var keys: Array = _live.keys()
		_live.clear()
		for k: StringName in keys:
			changed.emit(k)
