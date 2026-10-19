class_name SkillingComponent extends SpaceTimeComponent
## THE PLAYER'S SKILLING (design §7.4): what pressing E on a node does, and what the server says back.
## On a TREE (owner, 2026-10-18): TAP E to chop it AFK (a log now and then, until you move; tap again to
## stop); HOLD E (`hold_s`) to play a round of its minigame. It claims the E press from the foundation's
## `InteractionComponent` (`interact_handler`) only for trees, so everything else keeps working.
##
## The server decides everything (`server/src/game/regents.rs`): `chop(tree, active)` starts either; a
## round is a challenge the server deals (`round_dealt`), which the HUD plays and this submits
## (`submit_round`: the inputs only); AFK is an `afk_chop` row; what came out is a `harvest` row.
## Presentation and the press only: it never decides an outcome (AGENTS.md rule 4).

const TABLE_CHALLENGE: StringName = &"challenge"
const TABLE_AFK: StringName = &"afk_chop"
const TABLE_HARVEST: StringName = &"harvest"
const CHALLENGE_CHOP: int = 100
const ACTION_INTERACT: StringName = &"interact"

## The server dealt this player a round of tree `tree` (entity `tree_id`): play it from `seed_value`.
signal round_dealt(challenge_id: int, seed_value: int, tree: TreeDef, tree_id: int)
## The round is gone from the server (scored, withdrawn or expired).
signal round_closed(challenge_id: int)
## This player started (or stopped) chopping tree `tree_id` AFK.
signal afk_changed(chopping: bool, tree_id: int)
## A chop paid: `qty` of `item_id`, perhaps a rare find, perhaps the tree fell; `score_pm` -1 for AFK.
signal harvested(item_id: int, qty: int, rare_item: int, felled: bool, active: bool, score_pm: int)
## A chop was refused, and why (the server's words, or the client's own for a stump).
signal refused(why: String)

## How long E must be held to open a round rather than chop AFK.
@export_range(0.1, 1.5, 0.05, "suffix:s") var hold_s: float = 0.35

## The tree chopped AFK (an entity id), or -1.
var afk_tree: int = -1
## The round being played (a challenge id), or -1.
var round_id: int = -1
var _press_target: int = -1
var _press_ms: int = -1
var _interaction: InteractionComponent = null


func required_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_AFK, TABLE_HARVEST]


func optional_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_AFK, TABLE_HARVEST]


func _on_bound() -> void:
	set_physics_process(is_local_authority)
	if not is_local_authority:
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_interaction = ent.find_component(InteractionComponent) as InteractionComponent if ent != null else null
	if _interaction != null:
		_interaction.interact_handler = claim_press


## The tree component of entity `target`, or null when it is not a tree.
static func tree_of(target: int) -> TreeNodeComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(target) as SpaceTimeEntity
	return ent.find_component(TreeNodeComponent) as TreeNodeComponent if ent != null else null


## The E key went down on `target` (the foundation asks first, `interact_handler`). Claims it when it is
## a tree: the press is timed in `_physics_process` (tap or hold). Public so a playtest can press.
func claim_press(target: int) -> bool:
	var tree: TreeNodeComponent = tree_of(target)
	if tree == null:
		return false
	if tree.felled:
		refused.emit("A stump: it grows back soon")
		return true
	if round_id >= 0:
		return true
	_press_target = target
	_press_ms = Time.get_ticks_msec()
	return true


func _physics_process(_delta: float) -> void:
	if _press_target < 0:
		return
	var down: bool = InputMap.has_action(ACTION_INTERACT) and Input.is_action_pressed(ACTION_INTERACT)
	var target: int = _press_target
	if down and Time.get_ticks_msec() - _press_ms >= int(hold_s * 1000.0):
		_press_target = -1
		chop(target, true)
	elif not down:
		_press_target = -1
		tap(target)


## A tap on `target`: chop it AFK, or stop if that is what we are doing.
func tap(target: int) -> void:
	if afk_tree == target:
		stop_afk()
	else:
		chop(target, false)


## Ask the server to chop `target`: a round (`active`) or AFK.
func chop(target: int, active: bool) -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"chop", [target, active], ["u64", "bool"])
	_watch(req)
	return req


func stop_afk() -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"chop_stop", [], [])
	_watch(req)
	return req


## The round `challenge_id` was played: send its inputs (flat time, side pairs). The server replays them.
func submit_round(challenge_id: int, inputs: PackedInt32Array) -> ReducerRequest:
	var values: Array[float] = []
	for v: int in inputs:
		values.append(float(v))
	return SpaceTimeSync.call_reducer(&"submit_challenge_result", [challenge_id, values], ["u64", "f32"])


func _watch(req: ReducerRequest) -> void:
	if req == null:
		refused.emit("the request could not be sent")
	elif req.is_pending():
		req.settled.connect(_on_settled)
	else:
		_on_settled(req)


func _on_settled(req: ReducerRequest) -> void:
	if req.is_ok():
		return
	var why: String = req.error_message
	if why.is_empty():
		why = ReducerRequest.Outcome.keys()[req.outcome]
	refused.emit(why.trim_prefix("chop: ").trim_prefix("chop_stop: "))


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_CHALLENGE:
			_on_challenge(old, new)
		TABLE_AFK:
			var t: int = int(new.get(&"tree_id")) if new != null else -1
			if t != afk_tree:
				afk_tree = t
				afk_changed.emit(t >= 0, t)
		TABLE_HARVEST:
			if new != null and old == null and is_bound():
				harvested.emit(int(new.get(&"item_id")), int(new.get(&"qty")), int(new.get(&"rare_item")),
					bool(new.get(&"felled")), bool(new.get(&"active")), int(new.get(&"score_pm")))


func _on_challenge(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		if old != null and int(old.get(&"id")) == round_id:
			round_id = -1
			round_closed.emit(int(old.get(&"id")))
		return
	if old != null or int(new.get(&"kind")) != CHALLENGE_CHOP:
		return
	var parts: PackedStringArray = String(new.get(&"payload")).split(" ")
	var tree: TreeDef = TreeDef.by_id(int(parts[1])) if parts.size() == 2 else null
	if tree == null:
		push_warning("skilling: a round of no known tree (%s)" % new.get(&"payload"))
		return
	round_id = int(new.get(&"id"))
	round_dealt.emit(round_id, int(new.get(&"seed")), tree, int(parts[0]))
