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
## THE WORK'S PROGRESS (owner, 2026-10-21: "progress bar on crafting/refining"): when the piece now being
## worked began and when it comes (server microseconds), from the row's `started_at` and `next_at`.
var afk_from_us: int = 0
var afk_next_us: int = 0
## MAKE 1 / X / ALL (owner, 2026-10-21): how many batches this AFK run makes before it stops itself (0: until
## the bag runs out, as before), and how many it has made. The stop is the player's own input (`work_stop`).
var make_limit: int = 0
var made: int = 0
## The round being played (a challenge id), or -1; and what it is of (a NodeDef or a RecipeDef).
var round_id: int = -1
var round_def: ContentDef = null
## XP per skill id.
var xp: Dictionary[int, int] = {}
## The choice picked at each kind of station (its key: `_choice_key`).
var recipe_pick: Dictionary[StringName, String] = {}
## THE PARTS AND TRAITS CHOSEN (owner, 2026-10-23, MATERIALS.md step 3), per recipe id: the item in each of its
## part slots (`parts_of`), and the traits wanted on what it makes, in order (`traits_of`; none picked yet:
## every trait its parts offer). What the station's window sets; `work` sends both (`craft_choosing`).
var part_pick: Dictionary[int, PackedInt32Array] = {}
var trait_pick: Dictionary[int, PackedInt32Array] = {}
## THE GRADE OF HEAD picked per recipe id (owner, 2026-10-23, after his playtest): 0 Common, 1 Fine, 2 Masterwork;
## absent: the best the bag has. Sent as `set_craft_grade` before `craft_choosing`.
var grade_pick: Dictionary[int, int] = {}
## REFIT choices per bag row (owner, 2026-10-23): the part in each slot, the traits wanted in order.
var refit_part_pick: Dictionary[int, PackedInt32Array] = {}
var refit_trait_pick: Dictionary[int, PackedInt32Array] = {}
## The bag read in place of our entity's (a test's; null: our own).
var bag: SpaceTimeInventoryComponent = null
## `set_craft_grade`'s "any grade" (the server's `ANY_GRADE`).
const ANY_GRADE: int = 3
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
	# One a recipe (its parts are picked in the window, MATERIALS.md step 3), grouped by what it makes: a
	# cell of the material table by its pattern, then its material's tier; the rest after, as listed.
	var recipes: Array[RecipeDef] = station.recipes()
	recipes.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool: return _order_key(a) < _order_key(b))
	for r: RecipeDef in recipes:
		out.append({"recipe": r})
	# REFIT (owner, 2026-10-23): each item in the bag made here of parts, last, under its own heading.
	var inv: SpaceTimeInventoryComponent = _bag()
	if inv != null:
		for st: SpaceTimeInventoryComponent.Stack in inv.items():
			for r: RecipeDef in recipes:
				if r.output != null and r.output.id == st.item_def_id and not r.pick_slots().is_empty():
					out.append({"refit": st.id, "made_by": r, "data": st.instance_data})
					break
	return out


## Where a recipe sorts in a station's list: by its output's pattern and material tier; not a cell, last.
static func _order_key(r: RecipeDef) -> String:
	var it: ItemDef = r.output
	if it != null and it.pattern != null and it.material != null:
		return "0 %06d %02d %06d" % [it.pattern.id, it.material.tier, r.id]
	return "1 000000 00 %06d" % r.id


## The heading a recipe sits under in a station's list ("Axes", "Bars"; "Other" for what is no cell).
static func group_of(r: RecipeDef) -> String:
	var it: ItemDef = r.output if r != null else null
	return it.pattern.display_name + "s" if it != null and it.pattern != null else "Other"


## The item in each of `r`'s part slots: the one picked there, while it is still of the slot's kind; else
## the slot's own (the plain handle).
func parts_of(r: RecipeDef) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	var picked: PackedInt32Array = part_pick.get(r.id, PackedInt32Array())
	var slots: PackedInt32Array = r.pick_slots()
	for n: int in slots.size():
		var choices: Array[ItemDef] = r.part_choices(slots[n])
		var it: ItemDef = choices[0] if not choices.is_empty() else null
		for c: ItemDef in choices:
			if n < picked.size() and c.id == picked[n]:
				it = c
		out.append(it)
	return out


## Put item `item_id` in `r`'s part slot `n` (the n-th of its part slots). The traits wanted start over as
## every one the parts now offer (a yew handle picked: its Springy ticked).
func set_part(r: RecipeDef, n: int, item_id: int) -> void:
	trait_pick.erase(r.id)
	var picked: PackedInt32Array = PackedInt32Array()
	for it: ItemDef in parts_of(r):
		picked.append(it.id if it != null else 0)
	if n >= 0 and n < picked.size():
		picked[n] = item_id
	part_pick[r.id] = picked


## The traits `parts` offer `made`: each part's that fits it (a tool's trait for a tool, an axe too; a weapon's
## for a weapon: `ItemDef.trait_for`), in slot order, none twice.
static func offered_traits(parts: Array[ItemDef], made: ItemDef) -> Array[TraitDef]:
	var out: Array[TraitDef] = []
	for it: ItemDef in parts:
		var t: TraitDef = it.trait_for(made) if it != null else null
		if t != null and not out.has(t):
			out.append(t)
	return out


## The traits wanted on what `r` makes, in order: those picked that its parts still offer; none picked yet,
## every one they offer.
func traits_of(r: RecipeDef) -> Array[TraitDef]:
	return _wanted(offered_traits(parts_of(r), r.output), trait_pick.get(r.id, null))


## Want trait `trait_id` on what `r` makes (last in the order), or not.
func want_trait(r: RecipeDef, trait_id: int, on: bool) -> void:
	trait_pick[r.id] = _toggled(traits_of(r), trait_id, on)


static func _wanted(offered: Array[TraitDef], picked: Variant) -> Array[TraitDef]:
	if picked == null:
		return offered
	var out: Array[TraitDef] = []
	for id: int in picked as PackedInt32Array:
		for t: TraitDef in offered:
			if t.id == id and not out.has(t):
				out.append(t)
	return out


static func _toggled(now: Array[TraitDef], trait_id: int, on: bool) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for t: TraitDef in now:
		if t.id != trait_id:
			ids.append(t.id)
	if on:
		ids.append(trait_id)
	return ids


## THE CORE INPUT of `r` (the head: an input that does not stack and is no part slot), or null.
static func core_of(r: RecipeDef) -> ItemDef:
	var slots: PackedInt32Array = r.pick_slots()
	for i: int in r.inputs.size():
		if not slots.has(i) and r.inputs[i] != null and r.inputs[i].max_stack == 1:
			return r.inputs[i]
	return null


## How many of `r`'s core the bag holds of each grade: {2: Masterwork, 1: Fine, 0: Common}.
func core_grades(r: RecipeDef, inv: SpaceTimeInventoryComponent = null) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {2: 0, 1: 0, 0: 0}
	var core: ItemDef = core_of(r)
	inv = inv if inv != null else _bag()
	if core == null or inv == null:
		return out
	for st: SpaceTimeInventoryComponent.Stack in inv.items():
		var q: int = RegentsGrade.quality_of(st.instance_data)
		if st.item_def_id == core.id and q >= 0:
			out[RegentsGrade.of_quality(q)] += st.qty
	return out


## The grade of core `r` is made with: the one picked while the bag has some, else the best it has; -1 none.
func grade_of(r: RecipeDef, inv: SpaceTimeInventoryComponent = null) -> int:
	var have: Dictionary[int, int] = core_grades(r, inv)
	if grade_pick.has(r.id) and have.get(grade_pick[r.id], 0) > 0:
		return grade_pick[r.id]
	for g: int in [2, 1, 0]:
		if have[g] > 0:
			return g
	return -1


func _bag() -> SpaceTimeInventoryComponent:
	if bag != null:
		return bag
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	return ent.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent if ent != null else null


## THE PARTS an item already made carries (`"p"`; one made before: its handle, then each slot's own).
func parts_on(r: RecipeDef, instance_data: String) -> Array[ItemDef]:
	var had: Array = RegentsGrade.data_of(instance_data).get("p", [])
	if had.is_empty():
		var h: int = int(RegentsGrade.data_of(instance_data).get("h", 0))
		had = [h] if h > 0 else []
	var out: Array[ItemDef] = []
	var slots: PackedInt32Array = r.pick_slots()
	for n: int in slots.size():
		var it: ItemDef = r.inputs[slots[n]]
		if n < had.size() and ItemDef.by_id(int(had[n])) != null:
			it = ItemDef.by_id(int(had[n]))
		out.append(it)
	return out


## REFIT bag row `row` (made by `r`, carrying `instance_data`): the parts picked for it (as it is, to start).
func refit_parts(row: int, r: RecipeDef, instance_data: String) -> Array[ItemDef]:
	var out: Array[ItemDef] = parts_on(r, instance_data)
	var picked: PackedInt32Array = refit_part_pick.get(row, PackedInt32Array())
	var slots: PackedInt32Array = r.pick_slots()
	for n: int in mini(picked.size(), out.size()):
		for c: ItemDef in r.part_choices(slots[n]):
			if c.id == picked[n]:
				out[n] = c
	return out


func set_refit_part(row: int, r: RecipeDef, instance_data: String, n: int, item_id: int) -> void:
	refit_trait_pick.erase(row)
	var picked: PackedInt32Array = PackedInt32Array()
	for it: ItemDef in refit_parts(row, r, instance_data):
		picked.append(it.id if it != null else 0)
	if n >= 0 and n < picked.size():
		picked[n] = item_id
	refit_part_pick[row] = picked


## The traits wanted on refitted row `row`: picked, else those it has that its parts still offer, else all.
func refit_traits(row: int, r: RecipeDef, instance_data: String) -> Array[TraitDef]:
	var offered: Array[TraitDef] = offered_traits(refit_parts(row, r, instance_data), r.output)
	if refit_trait_pick.has(row):
		return _wanted(offered, refit_trait_pick[row])
	if not refit_part_pick.has(row):
		return _wanted(offered, PackedInt32Array(ItemDef.trait_ids(instance_data)))
	return offered


func want_refit_trait(row: int, r: RecipeDef, instance_data: String, trait_id: int, on: bool) -> void:
	refit_trait_pick[row] = _toggled(refit_traits(row, r, instance_data), trait_id, on)


## What a refit of row `row` costs: [[item, qty], ...]: each part changed, and the bars of its head's metal.
func refit_cost(row: int, r: RecipeDef, instance_data: String) -> Array:
	var out: Array = []
	var now: Array[ItemDef] = parts_on(r, instance_data)
	var want: Array[ItemDef] = refit_parts(row, r, instance_data)
	var slots: PackedInt32Array = r.pick_slots()
	for n: int in want.size():
		if want[n] != now[n]:
			out.append([want[n], r.input_qty[slots[n]]])
	var core: ItemDef = core_of(r)
	var bars: int = int(HotRules.number(&"regents.refit_bars"))
	for x: RecipeDef in RecipeDef.all():
		if core != null and x.output == core and not x.inputs.is_empty() and bars > 0:
			out.append([x.inputs[0], bars])
			break
	return out


## What `refit` is sent for row `row` at station `target`.
func refit_args(target: int, row: int, r: RecipeDef, instance_data: String) -> Array:
	var parts: Array = []
	for it: ItemDef in refit_parts(row, r, instance_data):
		parts.append(it.id if it != null else 0)
	var traits: Array = []
	for t: TraitDef in refit_traits(row, r, instance_data):
		traits.append(t.id)
	return [target, row, parts, traits]


## REFIT row `row` at station `target` as picked.
func refit(target: int, row: int, r: RecipeDef, instance_data: String) -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"refit", refit_args(target, row, r, instance_data), ["u64", "u64", "u32", "u32"])
	_watch(req)
	return req


## The quality `r` would make now (the best of its inputs in the bag, as the server takes them: best
## first), or -1 when nothing it takes has one (or its output has none). `inv`: the bag to read (none: ours).
func made_quality(r: RecipeDef, inv: SpaceTimeInventoryComponent = null) -> int:
	if r == null or r.quality != RecipeDef.Quality.FROM_INPUTS:
		return -1
	inv = inv if inv != null else _bag()
	if inv == null:
		return -1
	var grade: int = grade_of(r, inv)
	var best: int = -1
	for it: ItemDef in _inputs_now(r):
		for s: SpaceTimeInventoryComponent.Stack in inv.items():
			var q: int = RegentsGrade.quality_of(s.instance_data)
			if s.item_def_id == it.id and (grade < 0 or q < 0 or RegentsGrade.of_quality(q) == grade):
				best = maxi(best, q)
	return mini(best, 1000)


## How many traits a crafted item of quality `q` holds (its grade's: `regents.crafted_traits_*`).
static func trait_room(q: int) -> int:
	match RegentsGrade.of_quality(maxi(q, 0)):
		2:
			return int(HotRules.number(&"regents.crafted_traits_masterwork"))
		1:
			return int(HotRules.number(&"regents.crafted_traits_fine"))
	return int(HotRules.number(&"regents.crafted_traits_common"))


## `r`'s inputs for one batch with its part slots filled as picked.
func _inputs_now(r: RecipeDef) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	out.assign(r.inputs)
	var parts: Array[ItemDef] = parts_of(r)
	var slots: PackedInt32Array = r.pick_slots()
	for n: int in slots.size():
		if parts[n] != null:
			out[slots[n]] = parts[n]
	return out


## What it takes for one batch, picked parts and all: [[item, qty], ...].
func takes(r: RecipeDef) -> Array:
	var out: Array = []
	var now: Array[ItemDef] = _inputs_now(r)
	for i: int in now.size():
		out.append([now[i], r.input_qty[i] if i < r.input_qty.size() else 1])
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
	if c.has("refit"):
		return "refit:%d" % int(c["refit"])
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	return "%d" % (r.id if r != null else 0)


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
	if _fighting():
		return true   # fighting (a target picked) E is a skill (CombatComponent): claimed, and nothing worked
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


## Whether this player is fighting (a target picked): E is a skill then, not work (owner, 2026-10-20).
func _fighting() -> bool:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var c: CombatComponent = ent.find_component(CombatComponent) as CombatComponent if ent != null else null
	return c != null and c.fighting()


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
		elif c.has("refit"):
			return refit(target, int(c["refit"]), c["made_by"] as RecipeDef, String(c["data"]))
		elif c.has("recipe"):
			var r: RecipeDef = c["recipe"]
			if r.pick_slots().is_empty():
				req = SpaceTimeSync.call_reducer(&"craft", [target, r.id, active], ["u64", "u32", "bool"])
			else:
				# The grade of head first (none picked: the best the bag has), then the craft, on one connection, in order.
				var g: int = grade_of(r)
				SpaceTimeSync.call_reducer(&"set_craft_grade", [g if g >= 0 else ANY_GRADE], ["u32"])
				# A list argument's hint is its ELEMENT's type: the SDK writes the length, then each element so.
				req = SpaceTimeSync.call_reducer(&"craft_choosing", craft_args(target, r, active), ["u64", "u32", "bool", "u32", "u32"])
		else:
			refused.emit("Nothing to do here" if station.key != ORDER_BOARD else "The board has no orders yet")
			return null
		_watch(req)
		return req
	var req2: ReducerRequest = SpaceTimeSync.call_reducer(&"gather", [target, active], ["u64", "bool"])
	_watch(req2)
	return req2


## What `craft_choosing` is sent for `r` at station `target`: the station, the recipe, `active`, the item in each
## part slot, and the traits wanted in order.
func craft_args(target: int, r: RecipeDef, active: bool) -> Array:
	var parts: Array = []
	for it: ItemDef in parts_of(r):
		parts.append(it.id if it != null else 0)
	var traits: Array = []
	for t: TraitDef in traits_of(r):
		traits.append(t.id)
	return [target, r.id, active, parts, traits]


## MAKE `count` batches of what is picked at station `target` AFK (0: all the bag allows), then stop.
func make(target: int, count: int) -> ReducerRequest:
	make_limit = maxi(0, count)
	made = 0
	return work(target, false)


## How far the piece being worked is (0..1, at server time `now_us`); 0 when nothing is.
func afk_progress(now_us: int) -> float:
	if afk_target < 0 or afk_next_us <= afk_from_us:
		return 0.0
	return clampf(float(now_us - afk_from_us) / float(afk_next_us - afk_from_us), 0.0, 1.0)


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
			if new == null:
				afk_from_us = 0
				afk_next_us = 0
			else:
				var next_us: int = int(new.get(&"next_at"))
				# A new run begins at its start; each new piece when the last one came.
				if old == null or t != afk_target or afk_next_us == 0:
					afk_from_us = int(new.get(&"started_at"))
					afk_next_us = next_us
				elif next_us != afk_next_us:
					afk_from_us = afk_next_us
					afk_next_us = next_us
			afk = {} if new == null else {"target_id": t, "def_id": int(new.get(&"def_id")), "craft": bool(new.get(&"craft")),
				"skill_id": int(new.get(&"skill_id")), "tool_item": int(new.get(&"tool_item"))}
			if t != afk_target:
				afk_target = t
				if t < 0:
					make_limit = 0
					made = 0
				afk_changed.emit(t >= 0, t)
		TABLE_RESULT:
			if new != null and old == null and is_bound():
				var r: Dictionary = {}
				for key: String in ["skill_id", "item_id", "qty", "rare_item", "score_pm", "quality", "xp", "rank", "target_id"]:
					r[key] = int(new.get(StringName(key)))
				for key: String in ["depleted", "ran_out", "active"]:
					r[key] = bool(new.get(StringName(key)))
				worked.emit(r)
				_count_made(r)
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


## A batch made AFK at a station counts toward Make X; the last one asked for stops the run.
func _count_made(r: Dictionary) -> void:
	if make_limit <= 0 or bool(r["active"]) or int(r["qty"]) <= 0 or int(r["target_id"]) != afk_target:
		return
	if not bool(afk.get("craft", false)):
		return   # gathering is not made in batches
	made += 1
	if made >= make_limit:
		make_limit = 0
		stop_afk()


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
