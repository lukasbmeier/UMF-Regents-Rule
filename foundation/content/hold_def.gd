@tool
class_name HoldDef extends ContentDef
## A HOLD (docs/FOUNDATION_SYSTEMS.md milestone 3, DECISIONS #209): something done by holding the
## interact key on it until it is finished: helping a downed teammate up, laying an egg in a nest,
## opening a gate. Faster with more doing it together, stopped by moving away or being hurt. The
## server keeps who is holding what and how far along it is (`hold_progress`, `hold_member`);
## everything a hold MEANS is here, so a designer makes a new one without code. A genre's code may
## add to it (`game::hold_rate`: a nest cooling while nobody sits on it; `on_hold_completed`).
##
## WHICH PRESS STARTS IT: the interact key (verb 0, or a genre's own verb) on an entity of one of
## `done_to`'s kinds, by one of `done_by`'s (none: anyone), while the target is `only_when` (none:
## whatever its status). Two holds one press could start are refused, unless one is a genre's and
## the other the foundation's: the genre's then REPLACES the foundation's for those presses.
##
## The numbers under "Doing it" are the server's (baked); "How it shows" is presentation only.

## The interact verb that starts it: 0 is the interact key (E). A genre may give its own keys verbs.
@export_range(0, 255) var verb: int = 0
## The characters it is done to (their kinds: every character of the kind).
@export var done_to: Array[EntityDefinition] = []
## The characters that may do it (their kinds). None: anyone.
@export var done_by: Array[EntityDefinition] = []
## The status the target must be in (a downed teammate). None: whatever its status.
@export var only_when: StatusDef

@export_group("Doing it")
## Seconds to finish with one doing it, then two together, then three... The last applies to more.
## (A nest: 58 alone, 20 with two, 6 with three.) The rule `foundation.hold_speed` scales every hold's
## pace live, for tuning in the game.
@export var seconds_with: PackedFloat32Array = PackedFloat32Array([4.0])
## How near a doer must be (0: the game's interact range, the rule `foundation.interact_range_m`).
@export_range(0.0, 20.0, 0.1, "suffix:m") var range_m: float = 0.0
## How many may do it at once (0: any number).
@export_range(0, 16) var max_doers: int = 0
## Whether what was done stays when everyone lets go (a half-laid nest), or is lost (helping up).
@export var keeps_progress: bool = false
## A doer who is hurt lets go.
@export var stopped_by_damage: bool = true
## A doer who moves this far from where they started lets go (0: moving does not stop it).
@export_range(0.0, 20.0, 0.05, "suffix:m") var stopped_by_moving_m: float = 0.75
## The status the target is put in when it is done (Normal: back on its feet). None: unchanged.
@export var then_status: StatusDef

@export_group("How it shows")
## What the prompt says: "Hold E: <prompt>".
@export var prompt: String = ""
## A clip from the doer's AnimationSet held while doing it; a character without it shows nothing.
## Moving lets it go. Empty: none.
@export var pose: StringName = &""
## The progress bar's colour.
@export var color: Color = Color(0.45, 0.85, 0.5)

## Folder name -> paths, the genres' first (see `_table`): filled on first use while the game runs.
static var _paths: Array[String] = []
## The holds themselves, while the game runs (DECISIONS #224): each `find` used to `load()` its path,
## and once nothing else referenced a hold Godot's cache let it go, so the next `find` read the .tres
## and everything it links from disk again: 1 ms a call in Luke's game, asked for every entity in
## reach every physics frame and by the prompt every frame (the hen's frame rate fell with a wolf
## and a nest beside her). Dropped on `clear_cache` and at exit (`AppExit`); the editor reads afresh.
static var _held: Array[HoldDef] = []


func content_type() -> StringName:
	return &"hold"


## Tuned in the Inspector and tried in the game: everything about it is a number or a link, and how
## long it takes with each count of doers is its `summary()` in the Content panel. (Benches are made
## for a game's own content once its mechanics are known: a nest's would be Fowl Play's.)
func why_no_workbench() -> String:
	return "a hold is a few numbers and links, tuned in the Inspector and tried in the game; the line above says how long it takes with each count of doers"


func summary() -> String:
	return "Takes %s" % timing_note()


func on_created() -> void:
	if prompt.is_empty():
		prompt = display_name


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"verb": verb,
		"targets": kinds_of(done_to),
		"doers": kinds_of(done_by),
		"when": ContentDef.ref(only_when),
		"seconds_with": Array(seconds_with),
		"range_m": range_m,
		"max_doers": max_doers,
		"keeps_progress": keeps_progress,
		"stopped_by_damage": stopped_by_damage,
		"stopped_by_moving_m": stopped_by_moving_m,
		"then": ContentDef.ref(then_status),
	}


## The kinds of `defs`, each once, in order.
static func kinds_of(defs: Array[EntityDefinition]) -> Array:
	var out: Array = []
	for d: EntityDefinition in defs:
		if d != null and not out.has(d.kind):
			out.append(d.kind)
	out.sort()
	return out


func validate() -> Array[String]:
	var out: Array[String] = super()
	if kinds_of(done_to).is_empty():
		out.append("it is done to nothing: add the characters it is done to (`done_to`)")
	if done_to.has(null) or done_by.has(null):
		out.append("an empty slot in `done_to` or `done_by`: pick a character or remove the slot")
	if seconds_with.is_empty():
		out.append("it has no `seconds_with`: how long it takes one doer (then two, three...)")
	for s: float in seconds_with:
		if s <= 0.0:
			out.append("`seconds_with` has %s: every time must be more than 0 s" % s)
			break
	if prompt.strip_edges().is_empty():
		out.append("it has no prompt: what the player is told (\"Hold E: <prompt>\")")
	return out


## A press two of them could start (the build refuses the same: server/build/hold_rules.rs).
func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	var mine: String = ContentLibrary.owner_of_path(resource_path)
	for other: ContentDef in all_of_type:
		var o: HoldDef = other as HoldDef
		if o == null or o == self or not overlaps(o):
			continue
		var theirs: String = ContentLibrary.owner_of_path(o.resource_path)
		if theirs == mine:
			out.append("'%s' and '%s' could both be started by one press (verb %d, the same kind, doer and status): tell them apart" % [display_name, o.display_name, verb])
		elif mine != ContentLibrary.FOUNDATION and theirs != ContentLibrary.FOUNDATION:
			out.append("'%s' (%s) and '%s' (%s) could both be started by one press: only one genre may have it" % [display_name, mine, o.display_name, theirs])
	return out


## Whether one press could start both.
func overlaps(o: HoldDef) -> bool:
	var mine_to: Array = kinds_of(done_to)
	var mine_by: Array = kinds_of(done_by)
	var theirs_by: Array = kinds_of(o.done_by)
	return o.verb == verb \
		and kinds_of(o.done_to).any(func(k: int) -> bool: return mine_to.has(k)) \
		and (mine_by.is_empty() or theirs_by.is_empty() or theirs_by.any(func(k: int) -> bool: return mine_by.has(k))) \
		and (only_when == null or o.only_when == null or only_when.status == o.only_when.status)


## Whether a press of `p_verb` by a `doer_kind` on a `target_kind` in `target_status` starts it.
func applies(target_kind: int, p_verb: int, target_status: int, doer_kind: int) -> bool:
	return p_verb == verb and kinds_of(done_to).has(target_kind) \
		and (done_by.is_empty() or kinds_of(done_by).has(doer_kind)) \
		and still_applies(target_status)


## Whether a target in `target_status` is still something it is done to.
func still_applies(target_status: int) -> bool:
	return only_when == null or only_when.status == target_status


## How fast it goes with `doers` doing it: a share of the whole per second (0 with nobody).
func rate(doers: int) -> float:
	if doers <= 0 or seconds_with.is_empty():
		return 0.0
	var s: float = seconds_with[mini(doers, seconds_with.size()) - 1]
	return 1.0 / s if s > 0.0 else 0.0


## "4.0 s alone, 2.5 s with 2, 2.0 s with 3+": the time to finish with each count of doers.
func timing_note() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in seconds_with.size():
		var who: String = "alone" if i == 0 else "with %d%s" % [i + 1, "+" if i == seconds_with.size() - 1 else ""]
		parts.append("%s s %s" % [String.num(seconds_with[i], 1), who])
	return ", ".join(parts)


# --- the game's holds ------------------------------------------------------------------------

## The hold a press of `p_verb` by a `doer_kind` on a `target_kind` in `target_status` starts, or
## null: a genre's before the foundation's, as the server matches them (`hold::find`).
static func find(target_kind: int, p_verb: int, target_status: int, doer_kind: int) -> HoldDef:
	for h: HoldDef in _loaded():
		if h != null and h.applies(target_kind, p_verb, target_status, doer_kind):
			return h
	return null


## The hold with content id `hold_id` (what `hold_progress.hold` names), or null.
static func by_id(hold_id: int) -> HoldDef:
	for h: HoldDef in _loaded():
		if h != null and h.id == hold_id:
			return h
	return null


## Forget what was read (a suite that changes the content, or the genres; the game quitting).
static func clear_cache() -> void:
	_paths.clear()
	_held.clear()


## Every hold, loaded: kept while the game runs, read afresh in the editor.
static func _loaded() -> Array[HoldDef]:
	if not _held.is_empty() and not Engine.is_editor_hint():
		return _held
	var out: Array[HoldDef] = []
	for path: String in _table():
		out.append(load(path) as HoldDef)
	if not Engine.is_editor_hint():
		_held = out
	return out


## Every hold's path: each genre's in the game's order, then the foundation's. Paths, not resources,
## so this static never keeps one alive on its own (as `StatusDef._table`).
static func _table() -> Array[String]:
	if not _paths.is_empty() and not Engine.is_editor_hint():
		return _paths
	var genres: Array[String] = []
	var foundation: Array[String] = []
	for f: Dictionary in ContentLibrary.files():
		var owner: String = String(f["owner"])
		if not String(f["path"]).begins_with(ContentLibrary.folder_for(&"hold", owner) + "/"):
			continue
		if owner == ContentLibrary.FOUNDATION:
			foundation.append(String(f["path"]))
		else:
			genres.append(String(f["path"]))
	var out: Array[String] = genres
	out.append_array(foundation)
	_paths = out
	return out
