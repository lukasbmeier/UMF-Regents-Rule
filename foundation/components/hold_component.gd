class_name HoldComponent extends SpaceTimeComponent
## HOLDS ON THIS ENTITY, AND THE ONE IT IS DOING (docs/FOUNDATION_SYSTEMS.md milestone 3, DECISIONS
## #209), from the server's rows:
##
##   `hold_progress`  each thing being held ON it (a downed player being helped up, a nest being laid
##                    in): how far along, how fast, by how many. The bar is drawn from this, moving
##                    between rows (a row says how far along it was and how fast it goes, and is
##                    written only when that changes).
##   `hold_member`    what it is holding itself, if anything: its pose (`HoldDef.pose`) while it does.
##
## The server decides every hold (`begin_interact`, its tick, a genre's hooks); this only shows it
## (hard rule 11). The interact key starts and stops one (`InteractionComponent`), the HUD draws the
## prompt and the bar (`HoldPrompt`). Every entity has one: `SpaceTimeEntity` adds it when its scene
## does not, as it does a status.

## Something held on this entity changed: begun, joined, let go of, done (`hold_finished` too).
signal hold_changed(hold_id: int)
## Something held on this entity is done.
signal hold_finished(hold_id: int, hold: int)

const TABLE_PROGRESS: StringName = &"hold_progress"
const TABLE_MEMBER: StringName = &"hold_member"
## `hold_progress.state` (crate::hold).
const GOING: int = 0
const DONE: int = 1

## hold_id -> {hold, progress, rate, at_usec, doers, state}: what is being held on it.
var _on_me: Dictionary = {}
## What it is holding: {hold_id, target_id, hold}, or empty.
var _doing: Dictionary = {}
var _holding_pose: bool = false


func required_tables() -> Array[StringName]:
	return [TABLE_PROGRESS, TABLE_MEMBER]


## Nothing held, nothing doing: the usual. Nobody waits for a row.
func optional_tables() -> Array[StringName]:
	return [TABLE_PROGRESS, TABLE_MEMBER]


func rebind(initial_rows: Dictionary[StringName, RefCounted], history: Dictionary[StringName, Array] = {}) -> void:
	_on_me.clear()
	_doing = {}
	super(initial_rows, history)


# --- read API ------------------------------------------------------------------------------------

## The ids of what is being held on it now (not counting what has just finished).
func holds_on_me() -> Array[int]:
	var out: Array[int] = []
	for id: int in _on_me:
		if int(_on_me[id]["state"]) == GOING:
			out.append(id)
	out.sort()
	return out


## The hold being done on it of content id `hold` (`HoldDef.id`), or -1.
func hold_id_for(hold: int) -> int:
	for id: int in holds_on_me():
		if int(_on_me[id]["hold"]) == hold:
			return id
	return -1


## How far along `hold_id` is now (0..1), moving at its rate since the server last said; 1 once done,
## 0 for one it does not know.
func progress(hold_id: int) -> float:
	var h: Dictionary = _on_me.get(hold_id, {})
	if h.is_empty():
		return 0.0
	if int(h["state"]) == DONE:
		return 1.0
	var since: float = float(ClockSync.server_usec() - int(h["at_usec"])) / 1_000_000.0
	return clampf(float(h["progress"]) + float(h["rate"]) * maxf(since, 0.0), 0.0, 1.0)


## How many are doing `hold_id`.
func doers(hold_id: int) -> int:
	return int((_on_me.get(hold_id, {}) as Dictionary).get("doers", 0))


## Its content (`HoldDef`), or null when this build does not have it.
func def_of(hold_id: int) -> HoldDef:
	var h: Dictionary = _on_me.get(hold_id, {})
	return HoldDef.by_id(int(h["hold"])) if not h.is_empty() else null


## What this entity is holding: {hold_id, target_id, hold}, or empty when nothing.
func doing() -> Dictionary:
	return _doing


func is_holding() -> bool:
	return not _doing.is_empty()


# --- rows ------------------------------------------------------------------------------------

func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table == TABLE_PROGRESS:
		_progress_row(old, new)
	elif table == TABLE_MEMBER:
		_member_row(new)


func _progress_row(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		if old != null:
			var gone: int = int(old.get(&"hold_id"))
			_on_me.erase(gone)
			_announce(gone)
		return
	var id: int = int(new.get(&"hold_id"))
	var was: int = int((_on_me.get(id, {}) as Dictionary).get("state", GOING))
	_on_me[id] = {
		"hold": int(new.get(&"hold")),
		"progress": float(new.get(&"progress")),
		"rate": float(new.get(&"rate")),
		"at_usec": int(new.get(&"at")),
		"doers": int(new.get(&"doers")),
		"state": int(new.get(&"state")),
	}
	_announce(id)
	if int(_on_me[id]["state"]) == DONE and was != DONE and is_bound():
		var d: HoldDef = def_of(id)
		print("[Hold] %s on entity %d: done" % [d.display_name if d != null else "hold %d" % int(_on_me[id]["hold"]), entity_id])
		hold_finished.emit(id, int(_on_me[id]["hold"]))
		SignalBus.hold_finished.emit(entity_id, int(_on_me[id]["hold"]))


func _member_row(new: RefCounted) -> void:
	var was: Dictionary = _doing
	if new == null:
		_doing = {}
	else:
		_doing = {"hold_id": int(new.get(&"hold_id")), "target_id": int(new.get(&"target_id")), "hold": int(new.get(&"hold"))}
	if is_bound() and was != _doing:
		var d: HoldDef = HoldDef.by_id(int(_doing.get("hold", was.get("hold", -1))))
		print("[Hold] entity %d %s %s" % [entity_id, "holds" if not _doing.is_empty() else "lets go of",
			d.display_name if d != null else "a hold"])
		SignalBus.entity_holding_changed.emit(entity_id, int(_doing.get("target_id", -1)))


func _announce(hold_id: int) -> void:
	if not is_bound():
		return
	hold_changed.emit(hold_id)
	SignalBus.hold_changed.emit(entity_id)


# --- presentation ------------------------------------------------------------------------------

## The doer's pose, held every frame it holds something with one (hard rule 11: the driver asks
## nothing of us), let go once when it stops. Moving lets the driver drop it.
func _process(_delta: float) -> void:
	if not is_bound():
		return
	var pose: StringName = &""
	if not _doing.is_empty():
		var d: HoldDef = HoldDef.by_id(int(_doing["hold"]))
		if d != null:
			pose = d.pose
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var anim: AnimationDriverComponent = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent if ent != null else null
	if anim == null:
		return
	if not pose.is_empty():
		anim.hold_pose(pose, 1.0, -1.0, false)
		_holding_pose = true
	elif _holding_pose:
		anim.release_pose()
		_holding_pose = false
