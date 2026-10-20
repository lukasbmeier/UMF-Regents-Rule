class_name SkillingComponent extends SpaceTimeComponent
## THE PLAYER'S SKILLING (design §7.4): what pressing E on a node or a station does, and what the server
## says back. TAP E to work it AFK (tap again to stop; moving stops it too); HOLD E (`hold_s`) to play its
## round (owner, 2026-10-18). At a station, Q picks what to make. It claims the E press from the foundation's
## `InteractionComponent` (`interact_handler`) only for nodes and stations, so everything else still works.
##
## The server decides everything (`server/src/game/regents.rs`): `gather(node, active)` and `craft(station,
## recipe, active)` start the work; a round is a challenge the server deals (`round_dealt`), which the HUD
## plays and this submits (`submit_round`: the inputs only); AFK is an `afk_work` row (everyone's, so their
## clients draw them at it); what came out is a `work_result` row; mastery is `skill_xp`. Presentation and
## the press only: it never decides an outcome (AGENTS.md rule 4).

const TABLE_CHALLENGE: StringName = &"challenge"
const TABLE_AFK: StringName = &"afk_work"
const TABLE_RESULT: StringName = &"work_result"
const TABLE_XP: StringName = &"skill_xp"
const TABLE_LOG: StringName = &"recipe_log"
const TABLE_ORDER: StringName = &"work_order"
const TABLE_FILLED: StringName = &"order_filled"
const ACTION_INTERACT: StringName = &"interact"
## The order board's station key (`content/station/orders.tres`; the server's `ORDER_BOARD`).
const ORDER_BOARD: StringName = &"orders"

## The server dealt this player a round: play `params` from `seed_value` (for `target_id`, called `name`).
signal round_dealt(challenge_id: int, seed_value: int, params: Resource, target_id: int, name: String)
## The round is gone from the server (scored, withdrawn or expired).
signal round_closed(challenge_id: int)
## This player started (or stopped) working `target_id` AFK.
signal afk_changed(working: bool, target_id: int)
## Work paid (or ran out): the `work_result` row's values.
signal worked(result: Dictionary)
## This player's XP in a skill changed.
signal xp_changed(skill_id: int, xp: int)
## Work was refused, and why (the server's words, or the client's own).
signal refused(why: String)
## E was tapped at station `target` (and nothing is being made there): its window opens (the HUD's).
signal station_opened(target: int)

## How long E must be held to open a round rather than work AFK.
@export_range(0.1, 1.5, 0.05, "suffix:s") var hold_s: float = 0.35

## The node or station worked AFK (an entity id), or -1; and its row's values.
var afk_target: int = -1
var afk: Dictionary = {}
## The round being played (a challenge id), or -1; and what it is of (a NodeDef or a RecipeDef).
var round_id: int = -1
var round_def: ContentDef = null
## XP per skill id.
var xp: Dictionary[int, int] = {}
## The choice picked at each kind of station (its key: `_choice_key`).
var recipe_pick: Dictionary[StringName, String] = {}
## Our record of each recipe (by id): {"made", "fresh_pm", "at_us"}, from our `recipe_log` rows.
var recipe_log: Dictionary[int, Dictionary] = {}
## The work orders we have filled (order ids).
var orders_filled: Dictionary[int, bool] = {}
var _press_target: int = -1
var _press_ms: int = -1
var _interaction: InteractionComponent = null


func required_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_AFK, TABLE_RESULT, TABLE_XP, TABLE_LOG, TABLE_FILLED]


func optional_tables() -> Array[StringName]:
	return [TABLE_CHALLENGE, TABLE_AFK, TABLE_RESULT, TABLE_XP, TABLE_LOG, TABLE_FILLED]


func _on_bound() -> void:
	set_physics_process(is_local_authority)
	if not is_local_authority:
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_interaction = ent.find_component(InteractionComponent) as InteractionComponent if ent != null else null
	if _interaction != null:
		_interaction.interact_handler = claim_press


## The node component of entity `target`, or null when it is not a node.
static func node_of(target: int) -> NodeComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(target) as SpaceTimeEntity
	return ent.find_component(NodeComponent) as NodeComponent if ent != null else null


## The station component of entity `target`, or null when it is not a station.
static func station_of(target: int) -> StationComponent:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(target) as SpaceTimeEntity
	return ent.find_component(StationComponent) as StationComponent if ent != null else null


## What can be done at `station`, in Q's order: {"recipe": RecipeDef, "part": ItemDef or null} for each
## recipe (one per handle in the bag for a recipe with a part slot, the plain one always), or at the
## order board {"order": its row's values} for each order on it.
func choices_at(station: StationComponent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if station.key == ORDER_BOARD:
		for o: Dictionary in orders():
			out.append({"order": o})
		return out
	for r: RecipeDef in station.recipes():
		var parts: Array[ItemDef] = r.part_choices()
		if parts.is_empty():
			out.append({"recipe": r, "part": null})
			continue
		for i: int in parts.size():
			if i == 0 or count_of(parts[i].id) > 0:
				out.append({"recipe": r, "part": parts[i]})
	return out


## The choice Q has picked at `station` ({} when there is nothing to do there): the one picked last, while
## it is still there (a handle running out drops its choice: then the first).
func choice_at(station: StationComponent) -> Dictionary:
	var list: Array[Dictionary] = choices_at(station)
	if list.is_empty():
		return {}
	return list[_picked_index(station, list)]


## The recipe picked at `station` (null when it makes nothing).
func recipe_at(station: StationComponent) -> RecipeDef:
	return choice_at(station).get("recipe", null) as RecipeDef


## Pick the next thing to do at `station` (Q).
func next_recipe(station: StationComponent) -> RecipeDef:
	var list: Array[Dictionary] = choices_at(station)
	if not list.is_empty():
		recipe_pick[station.key] = _choice_key(list[(_picked_index(station, list) + 1) % list.size()])
	return recipe_at(station)


func _picked_index(station: StationComponent, list: Array[Dictionary]) -> int:
	var want: String = String(recipe_pick.get(station.key, ""))
	for i: int in list.size():
		if _choice_key(list[i]) == want:
			return i
	return 0


## What names a choice whatever else the list holds: its recipe and part, or its order's slot.
static func _choice_key(c: Dictionary) -> String:
	if c.has("order"):
		return "order:%d" % int((c["order"] as Dictionary)["slot"])
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	var part: ItemDef = c.get("part", null) as ItemDef
	return "%d:%d" % [r.id if r != null else 0, part.id if part != null else 0]


## How many of item `item_id` are in our bag.
func count_of(item_id: int) -> int:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var inv: SpaceTimeInventoryComponent = ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent if ent != null else null
	return inv.count(item_id) if inv != null else 0


## The work orders on our world's board, by slot: each {"id", "slot", "item_id", "qty", "skill_id", "xp",
## "filled"} (filled: by us already).
func orders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var world: int = ent.world_id if ent != null else 0
	for row: RefCounted in SpaceTimeSync.find_rows(TABLE_ORDER, func(r: RefCounted) -> bool: return int(r.get(&"world_id")) == world):
		var id: int = int(row.get(&"id"))
		out.append({"id": id, "slot": int(row.get(&"slot")), "item_id": int(row.get(&"item_id")), "qty": int(row.get(&"qty")),
			"skill_id": int(row.get(&"skill_id")), "xp": int(row.get(&"xp")), "filled": orders_filled.has(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	return out


## Recipe `recipe_id` as we have made it: {"made", "fresh_pm" (now, with what has recovered)}; made 0 when
## never (its first batch pays the first-make bonus).
func recipe_record(recipe_id: int) -> Dictionary:
	var rec: Dictionary = recipe_log.get(recipe_id, {})
	if rec.is_empty():
		return {"made": 0, "fresh_pm": 1000}
	var secs: int = maxi(0, int((ClockSync.server_usec() - int(rec["at_us"])) / 1000000))
	var recover: float = HotRules.number(&"regents.variety_recover_pm_per_min")
	return {"made": int(rec["made"]), "fresh_pm": mini(1000, int(rec["fresh_pm"]) + int(float(secs) * recover / 60.0))}


## This player's rank in `skill`.
func rank_in(skill: SkillDef) -> int:
	return skill.rank_of(int(xp.get(skill.id, 0))) if skill != null else 1


## The E key went down on `target` (the foundation asks first, `interact_handler`). Claims it when it is a
## node or a station: the press is timed in `_physics_process` (tap or hold). Public so a playtest can press.
func claim_press(target: int) -> bool:
	var node: NodeComponent = node_of(target)
	var station: StationComponent = station_of(target)
	if node == null and station == null:
		return false
	if _in_combat():
		return true   # in combat stance E is a skill (CombatComponent): claimed, and nothing worked
	if node != null and node.depleted:
		refused.emit("Worked out: it comes back soon")
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
		work(target, true)
	elif not down:
		_press_target = -1
		tap(target)


## What E would work now (the node or station in front of us), or -1.
func target_now() -> int:
	return _interaction.get_target() if _interaction != null else -1


## Whether this player is in combat stance (Q E R F are skills then).
func _in_combat() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var c: CombatComponent = ent.find_component(CombatComponent) as CombatComponent if ent != null else null
	return c != null and c.in_stance()


## A tap on `target`: work a node AFK; at a station, open its window (owner, 2026-10-20: a station's
## window, not Q); stop, if that is what we are doing there.
func tap(target: int) -> void:
	if afk_target == target:
		stop_afk()
	elif station_of(target) != null:
		station_opened.emit(target)
	else:
		work(target, false)


## Ask the server to work `target`: a round (`active`) or AFK. A station makes its picked recipe.
func work(target: int, active: bool) -> ReducerRequest:
	var station: StationComponent = station_of(target)
	if station != null:
		var c: Dictionary = choice_at(station)
		var req: ReducerRequest = null
		if c.has("order"):
			var o: Dictionary = c["order"]
			req = SpaceTimeSync.call_reducer(&"fill_order", [target, int(o["id"])], ["u64", "u64"])
		elif c.has("recipe"):
			var r: RecipeDef = c["recipe"]
			var part: ItemDef = c.get("part", null) as ItemDef
			if part != null and r.part_slot >= 0 and part != r.inputs[r.part_slot]:
				req = SpaceTimeSync.call_reducer(&"craft_with", [target, r.id, active, part.id], ["u64", "u32", "bool", "u32"])
			else:
				req = SpaceTimeSync.call_reducer(&"craft", [target, r.id, active], ["u64", "u32", "bool"])
		else:
			refused.emit("Nothing to do here" if station.key != ORDER_BOARD else "The board has no orders yet")
			return null
		_watch(req)
		return req
	var req2: ReducerRequest = SpaceTimeSync.call_reducer(&"gather", [target, active], ["u64", "bool"])
	_watch(req2)
	return req2


func stop_afk() -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"work_stop", [], [])
	_watch(req)
	return req


## The round `challenge_id` was played: send its inputs (flat). The server replays them.
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
	for prefix: String in ["gather: ", "craft: ", "work_stop: ", "fill_order: "]:
		why = why.trim_prefix(prefix)
	refused.emit(why)


## The skill being worked now (AFK from the row, a round from what it is of), or null.
func working_skill() -> SkillDef:
	if round_def is NodeDef:
		return (round_def as NodeDef).skill
	if round_def is RecipeDef:
		return (round_def as RecipeDef).skill
	if afk_target >= 0:
		return SkillDef.by_id(int(afk.get("skill_id", 0)))
	return null


## The tool in the hand while working now (an item, from the AFK row; for our own round, our best).
func working_tool() -> ItemDef:
	if afk_target >= 0 and int(afk.get("tool_item", 0)) > 0 and not bool(afk.get("craft", false)):   # a craft's is its part
		return ItemDef.by_id(int(afk["tool_item"]))
	if round_def is NodeDef:
		return best_tool((round_def as NodeDef).tool_tag)
	return null


## Our best tool of `tag` in our bag (by tier), or null.
func best_tool(tag: StringName) -> ItemDef:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var inv: SpaceTimeInventoryComponent = ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent if ent != null else null
	var best: ItemDef = null
	if inv == null:
		return null
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		var it: ItemDef = ItemDef.by_id(s.item_def_id)
		if it != null and it.tool_tag == tag and (best == null or it.tool_tier > best.tool_tier):
			best = it
	return best


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_CHALLENGE:
			_on_challenge(old, new)
		TABLE_AFK:
			var t: int = int(new.get(&"target_id")) if new != null else -1
			afk = {} if new == null else {"target_id": t, "def_id": int(new.get(&"def_id")), "craft": bool(new.get(&"craft")),
				"skill_id": int(new.get(&"skill_id")), "tool_item": int(new.get(&"tool_item"))}
			if t != afk_target:
				afk_target = t
				afk_changed.emit(t >= 0, t)
		TABLE_RESULT:
			if new != null and old == null and is_bound():
				var r: Dictionary = {}
				for key: String in ["skill_id", "item_id", "qty", "rare_item", "score_pm", "quality", "xp", "rank", "target_id"]:
					r[key] = int(new.get(StringName(key)))
				for key: String in ["depleted", "ran_out", "active"]:
					r[key] = bool(new.get(StringName(key)))
				worked.emit(r)
		TABLE_XP:
			if new != null:
				var sid: int = int(new.get(&"skill_id"))
				xp[sid] = int(new.get(&"xp"))
				xp_changed.emit(sid, xp[sid])
		TABLE_LOG:
			if new != null:
				recipe_log[int(new.get(&"recipe_id"))] = {"made": int(new.get(&"made")), "fresh_pm": int(new.get(&"fresh_pm")), "at_us": int(new.get(&"at"))}
		TABLE_FILLED:
			if new != null:
				orders_filled[int(new.get(&"order_id"))] = true
			elif old != null:
				orders_filled.erase(int(old.get(&"order_id")))


func _on_challenge(old: RefCounted, new: RefCounted) -> void:
	if new == null:
		if old != null and int(old.get(&"id")) == round_id:
			round_id = -1
			round_def = null
			round_closed.emit(int(old.get(&"id")))
		return
	var kind: StringName = SkillMinigames.kind_of_challenge(int(new.get(&"kind")))
	if old != null or kind == &"":
		return
	var parts: PackedStringArray = String(new.get(&"payload")).split(" ")
	if parts.size() < 3:
		push_warning("skilling: a round with a payload of no known shape (%s)" % new.get(&"payload"))
		return
	var def: ContentDef = NodeDef.by_id(int(parts[1])) if kind == SkillMinigames.CHOP or kind == SkillMinigames.CRACK else RecipeDef.by_id(int(parts[1]))
	var minigame: Resource = (def as NodeDef).minigame if def is NodeDef else ((def as RecipeDef).minigame if def is RecipeDef else null)
	if minigame == null or SkillMinigames.kind_of(minigame) != kind:
		push_warning("skilling: a round of no known content (%s)" % new.get(&"payload"))
		return
	round_id = int(new.get(&"id"))
	round_def = def
	round_dealt.emit(round_id, int(new.get(&"seed")), SkillMinigames.with_speed(minigame, int(parts[2])), int(parts[0]), def.display_name)
