class_name PatrolBrain extends NpcBrain
## WALKS TO AND FRO between where it started (`home`) and a point (`to`), ROUND WHAT IS IN THE WAY (`go_to`:
## its walk map, walls entities put up included, DECISIONS #304), turning at each end. Both are its memory
## (`npc_brain.data`: `{"to": [x, y, z]}`, written by whoever set it going: a genre, an admin, a test).
## With no `to` it stands. A guard's round, a cart's run; and the referee walls test's bot
## (tests/walls_test.sh), which crosses a wall's line on every leg.
##
## SERVER-ONLY (hard rule 7b).

var home: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO
var has_to: bool = false
## Heading out to `to` (true) or back home.
var outward: bool = true
var _has_home: bool = false


func _init(_seed_value: int = 0) -> void:
	state = &"idle"


func think(me: MovementState, world: NpcWorldView) -> void:
	if me == null:
		return
	if not _has_home:
		home = me.pos
		_has_home = true
	if not has_to:
		state = &"idle"
		clear_goal()
		return
	var end: Vector3 = to if outward else home
	if Vector2(end.x - me.pos.x, end.z - me.pos.z).length() < arrive_radius():
		print("[Sidecar] entity %d's patrol reached its %s end (%.1f, %.1f)" % [self_id, "far" if outward else "home",
			me.pos.x, me.pos.z])
		outward = not outward   # there: turn
		end = to if outward else home
	state = &"out" if outward else &"back"
	go_to(end, me, world)   # asked again every think: a map baked again since is walked at once


func walks() -> bool:
	return true


func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["to"] = _v3(to)
	d["has_to"] = has_to
	d["home"] = _v3(home)
	d["has_home"] = _has_home
	d["outward"] = outward
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	if d.has("to"):
		to = _from_v3(d["to"], to)
		has_to = bool(d.get("has_to", true))
	if bool(d.get("has_home", false)):
		home = _from_v3(d.get("home"), home)
		_has_home = true
	outward = bool(d.get("outward", outward))


func describe() -> String:
	return "patrol %s <-> %s, %s" % [str(home), str(to) if has_to else "nowhere", "out" if outward else "back"]
