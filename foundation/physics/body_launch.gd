class_name BodyLaunch extends Node
## THROWING SOMETHING, AS THE THROWER SEES IT (FOUNDATION_SYSTEMS milestone 13, DECISIONS #246): the
## throw goes to the server (`launch_body`) and, the same moment, the thrower's game flies its own
## `FlyingBody` from the hand, so it leaves the hand on the click, not a round trip later. When the
## body's rows come, its `BodyComponent` takes this flight over (`take`) and keeps it near the
## referee's. A throw the server refused, or that never came, is taken away.
##
## One node under the tree's root, made when first needed; its methods are static. A game calls
## `throw_body` (or a genre's own reducer with `launch_id` and `fly`, when its rules launch it).

## Said when a throw the server refused is taken away (the HUD may say why).
signal refused(launch_id: int, why: String)

## A throw nothing answered in this long is taken away.
const FORGET_MS: int = 3000

static var _me: BodyLaunch = null
## launch_id -> {body: FlyingBody, at_ms}
static var _flying: Dictionary[int, Dictionary] = {}
static var _next_id: int = 0


## The node, made under the tree's root when first asked for.
static func node(tree: SceneTree) -> BodyLaunch:
	if _me == null or not is_instance_valid(_me):
		_me = BodyLaunch.new()
		_me.name = "BodyLaunch"
		tree.root.add_child(_me)
	return _me


## A fresh number for a throw by this game.
static func next_id() -> int:
	if _next_id == 0:
		_next_id = (Time.get_ticks_usec() & 0xFFFF) * 1000 + 1
	_next_id = (_next_id + 1) & 0x7FFFFFFF
	return _next_id


## THROW body `def` from `origin` at `vel`, turned `rot` (a rotation vector), spinning `spin`: the
## server is asked (`launch_body`), and the flight starts here at once under `parent` (the world the
## bodies are in). Returns the throw's number; the request settles later (refused: `refused`).
static func throw_body(parent: Node, def: BodyDef, origin: Vector3, vel: Vector3, rot: Vector3 = Vector3.ZERO,
		spin: Vector3 = Vector3.ZERO) -> int:
	var launch_id: int = next_id()
	fly(parent, def, launch_id, origin, vel, rot, spin)
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"launch_body", [def.id, launch_id, origin, vel, rot, spin],
		["u32", "u32", "vector3[f32,f32,f32]", "vector3[f32,f32,f32]", "vector3[f32,f32,f32]", "vector3[f32,f32,f32]"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.outcome != ReducerRequest.Outcome.OK:
			forget(launch_id, r.error_message))
	return launch_id


## The thrower's own flight of throw `launch_id`, started now (a genre's own throw reducer calls this
## beside its request, with the same numbers it sends).
static func fly(parent: Node, def: BodyDef, launch_id: int, origin: Vector3, vel: Vector3, rot: Vector3, spin: Vector3) -> FlyingBody:
	var me: BodyLaunch = node(parent.get_tree())
	var b: FlyingBody = FlyingBody.make(def)
	b.name = "Throw%d" % launch_id
	parent.add_child(b)
	b.launch(origin, vel, rot, spin)
	var v: Node3D = def.make_visual()
	v.name = "Visual"
	b.add_child(v)
	_flying[launch_id] = {"body": b, "at_ms": Time.get_ticks_msec()}
	me.set_process(true)
	return b


## The flight of throw `launch_id`, handed to whoever takes it (its body's `BodyComponent`), or null.
static func take(launch_id: int) -> FlyingBody:
	var e: Dictionary = _flying.get(launch_id, {})
	_flying.erase(launch_id)
	var b: FlyingBody = e.get("body", null)
	return b if b != null and is_instance_valid(b) else null


## How many throws are flying unanswered.
static func waiting() -> int:
	return _flying.size()


## Take throw `launch_id`'s flight away (refused: `why`).
static func forget(launch_id: int, why: String = "") -> void:
	var b: FlyingBody = take(launch_id)
	if b != null:
		b.queue_free()
	if not why.is_empty() and _me != null and is_instance_valid(_me):
		push_warning("[BodyLaunch] throw %d refused: %s" % [launch_id, why])
		_me.refused.emit(launch_id, why)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for id: int in _flying.keys():
		if now - int(_flying[id]["at_ms"]) > FORGET_MS:
			forget(id)
	if _flying.is_empty():
		set_process(false)


func _exit_tree() -> void:
	if _me == self:
		_me = null
