class_name Rules
## THE FOUNDATION'S RULES, AS THE GAME SETS THEM: `res://shared/rules.json` (DECISIONS #154) — the
## same file `server/build.rs` compiles into the module, so the two halves read one number. A new
## player's health, how close you must be to use something, and each session kind's round plan
## (its phases in order, their names and lengths).
##
## Change the file, republish (`tools/publish.sh`), restart. The client reads it fresh each run.

const PATH: String = "res://shared/rules.json"

static var _doc: Dictionary = {}


## The whole file, parsed once.
static func doc() -> Dictionary:
	if _doc.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_doc = parsed as Dictionary
		else:
			push_error("Rules: %s is missing or malformed" % PATH)
	return _doc


## A new player's health.
static func max_health() -> float:
	var player: Dictionary = doc().get("player", {}) as Dictionary
	return float(player.get("max_health", 100.0))


## How close (m) a player must be for the server to accept `interact`. The client's prompt uses it
## too, so it never offers what the server will refuse.
static func interact_range() -> float:
	return float(doc().get("interact_range_m", 3.0))


## A session kind's phases, in order: [{phase, name, seconds}]. Empty for a kind with no plan.
static func phases(kind: int) -> Array:
	for s: Variant in doc().get("sessions", []) as Array:
		var plan: Dictionary = s as Dictionary
		if int(plan.get("kind", -1)) == kind:
			return plan.get("phases", []) as Array
	return []


## A session kind's lobby (DECISIONS #174): {ready_up, min_players, teams: [{name}]}, or {} for a
## kind with none.
static func lobby(kind: int) -> Dictionary:
	for s: Variant in doc().get("sessions", []) as Array:
		var plan: Dictionary = s as Dictionary
		if int(plan.get("kind", -1)) == kind:
			return plan.get("lobby", {}) as Dictionary
	return {}


## A session kind's team names, in order (empty for none).
static func teams(kind: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Variant in lobby(kind).get("teams", []) as Array:
		out.append(str((t as Dictionary).get("name", "")))
	return out


## What the game calls a phase ("lobby", "playing"...), or "" when the kind does not plan it.
static func phase_name(kind: int, phase: int) -> String:
	for p: Variant in phases(kind):
		if int((p as Dictionary).get("phase", -1)) == phase:
			return str((p as Dictionary).get("name", ""))
	return ""


## How long a phase lasts (s); 0 when it is held until something moves it on, or not planned.
static func phase_seconds(kind: int, phase: int) -> float:
	for p: Variant in phases(kind):
		if int((p as Dictionary).get("phase", -1)) == phase:
			return float((p as Dictionary).get("seconds", 0.0))
	return 0.0
