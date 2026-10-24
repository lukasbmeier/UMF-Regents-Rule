@tool
class_name RecipeDef extends ContentDef
## A RECIPE (design §7.3, §7.4): what a station makes from what. Ore into bars at the furnace (smelting),
## bars into parts at the anvil (smithing), logs into handles and parts into tools at the workbench
## (crafting). Worked like a node, at the player's choice:
##   AFK      tap E at the station: one batch every `afk_ms` while the bag has the inputs and you stay
##   active   hold E: a round of `minigame` (none: AFK only). A recipe whose output's QUALITY comes from
##            the round (smithing) makes one, as good as the score; any other makes what AFK would in the
##            round's time x `regents.active_yield_mult` x the score
## Quality (thousandths, on the item: an unstacking item): from the round (AFK makes `afk_quality`), or
## from the inputs (an assembled tool is as good as its head).

enum Quality { NONE, FROM_ROUND, FROM_INPUTS }

## The station it is made at: "furnace", "anvil", "workbench" (a `StationDef`'s key).
@export var station: StringName = &"furnace"
## The skill it trains (and whose rank it needs).
@export var skill: SkillDef
## What it takes, with how many of each (one number per input).
@export var inputs: Array[ItemDef] = []
@export var input_qty: PackedInt32Array = PackedInt32Array()
## What it makes, and how many a batch.
@export var output: ItemDef
@export_range(1, 1000) var output_qty: int = 1
## XP a batch gives, and the rank it needs.
@export_range(0, 10000) var xp: int = 10
@export_range(1, 99) var min_rank: int = 1
## AFK: one batch this often.
@export_range(500, 120000, 100, "suffix:ms") var afk_ms: int = 3000
## Its round (a `SmeltParams`, a `ShapeParams`), or none: AFK only.
@export var minigame: Resource
@export var quality: Quality = Quality.NONE
## The quality AFK makes, when the round decides it (thousandths).
@export_range(0, 1000, 10, "suffix:‰") var afk_quality: int = 350
## The input that is the made tool's HANDLE (an index into `inputs`; -1: none). Any item of that input's
## `part_tag` may take its place, picked at the station, and its trait goes on the tool. Kept for builds
## before `part_slots` (they pick this one only): the first of `part_slots`.
@export_range(-1, 8) var part_slot: int = -1
## EVERY INPUT THE PLAYER PICKS (`docs/regents_rule/MATERIALS.md` §3-§4, step 3): indexes into `inputs`, each
## a part (a handle, a binding) any item of whose kind may take its place at the station, its trait
## offered for the made item. Empty: `part_slot` alone (when it is one).
@export var part_slots: PackedInt32Array = PackedInt32Array()
## MADE BY THE MATERIAL TABLE for its output's cell (`MaterialTable`, `docs/regents_rule/MATERIALS.md`):
## its station, skill, inputs, output and part slot follow the cell's pattern and material; its numbers
## (XP, rank, AFK time, how many of each input, its round) are yours to tune, here or on the recipe bench.
@export var from_table: bool = false

static var _all: Array[RecipeDef] = []
## `work_xp` worked out once per item in a running game (content does not change there).
static var _work_xp: Dictionary[int, int] = {}


func content_type() -> StringName:
	return &"recipe"



func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in inputs.size():
		parts.append("%d %s" % [input_qty[i] if i < input_qty.size() else 1, inputs[i].display_name if inputs[i] != null else "?"])
	return "%s: %s -> %d %s" % [station, ", ".join(parts), output_qty, output.display_name if output != null else "?"]


func to_bake() -> Dictionary:
	var ins: Array = []
	for i: int in inputs.size():
		ins.append([ContentDef.ref(inputs[i]), input_qty[i] if i < input_qty.size() else 1])
	return {
		"id": id,
		"name": display_name,
		"station": String(station),
		"skill": ContentDef.ref(skill),
		"inputs": ins,
		"output": ContentDef.ref(output),
		"output_qty": output_qty,
		"xp": xp,
		"min_rank": min_rank,
		"afk_ms": afk_ms,
		"minigame": SkillMinigames.bake(minigame),
		"quality": int(quality),
		"afk_quality": afk_quality,
		"part_slot": part_slot,
		"part_slots": Array(pick_slots()),
	}


## The XP of the work that went into one item (`genre::regents::work_xp`, the server's): gathered, its
## node's XP; made, its recipe's XP and its inputs' work over the batch; the cheapest way; else 0.
static func work_xp(item: ItemDef, depth: int = 0) -> int:
	if item == null or depth > 8:
		return 0
	if depth == 0 and not Engine.is_editor_hint() and _work_xp.has(item.id):
		return _work_xp[item.id]
	var w: int = _work_xp_of(item, depth)
	if depth == 0 and not Engine.is_editor_hint():
		_work_xp[item.id] = w
	return w


static func _work_xp_of(item: ItemDef, depth: int) -> int:
	var best: int = -1
	for d: ContentDef in RegentsContent.items(&"node"):
		var n: NodeDef = d as NodeDef
		if n != null and n.yield_item == item:
			best = n.xp if best < 0 else mini(best, n.xp)
	for r: RecipeDef in all():
		if r.output == item:
			var ins: int = 0
			for i: int in r.inputs.size():
				ins += r.input_qty[i] * work_xp(r.inputs[i], depth + 1)
			var w: int = (r.xp + ins) / maxi(1, r.output_qty)
			best = w if best < 0 else mini(best, w)
	return maxi(0, best)


## A batch's XP before variety and first-make: its own plus `share_pct` of its inputs' work (as the
## server pays it, `genre::regents::craft_xp`).
func craft_xp(share_pct: int) -> int:
	var ins: int = 0
	for i: int in inputs.size():
		ins += input_qty[i] * work_xp(inputs[i])
	return xp + ins * share_pct / 100


## Every input the player picks (`part_slots`, else `part_slot` when it is one), in order.
func pick_slots() -> PackedInt32Array:
	if not part_slots.is_empty():
		return part_slots
	return PackedInt32Array([part_slot]) if part_slot >= 0 else PackedInt32Array()


## The items that may fill input `slot` (any item of its kind), its own first; empty when it is no part
## (-1: the first picked slot).
func part_choices(slot: int = -1) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	if slot < 0:
		slot = pick_slots()[0] if not pick_slots().is_empty() else -1
	if slot < 0 or slot >= inputs.size() or inputs[slot] == null:
		return out
	var kind: StringName = inputs[slot].part_tag
	out.append(inputs[slot])
	for d: ContentDef in RegentsContent.items(&"item"):
		var it: ItemDef = d as ItemDef
		if it != null and it != inputs[part_slot] and it.part_tag == kind:
			out.append(it)
	return out


func validate() -> Array[String]:
	var out: Array[String] = super()
	if skill == null:
		out.append("it trains no skill: set `skill`")
	if inputs.is_empty() or inputs.has(null):
		out.append("it takes nothing (or an empty slot): set `inputs`")
	if input_qty.size() != inputs.size():
		out.append("`input_qty` needs one number per input (%d inputs, %d numbers)" % [inputs.size(), input_qty.size()])
	if output == null:
		out.append("it makes nothing: set `output`")
	var kind: StringName = SkillMinigames.kind_of(minigame)
	if minigame != null and kind != SkillMinigames.SMELT and kind != SkillMinigames.SHAPE:
		out.append("its `minigame` is not a station round (a SmeltParams or a ShapeParams)")
	if quality == Quality.FROM_ROUND and minigame == null:
		out.append("its quality comes from a round it does not have")
	if quality != Quality.NONE and output != null and output.max_stack != 1:
		out.append("an item with a quality does not stack: its output's `max_stack` must be 1")
	if part_slot >= inputs.size():
		out.append("its `part_slot` (%d) is past its inputs" % part_slot)
	elif part_slot >= 0 and inputs[part_slot] != null and inputs[part_slot].part_tag == &"":
		out.append("its part slot is %s, which is no part: set that item's `part_tag`" % inputs[part_slot].display_name)
	for i: int in part_slots:
		if i < 0 or i >= inputs.size():
			out.append("its `part_slots` name input %d, which it does not have" % i)
		elif inputs[i] != null and inputs[i].part_tag == &"":
			out.append("its part slot %d is %s, which is no part: set that item's `part_tag`" % [i, inputs[i].display_name])
	if not part_slots.is_empty() and part_slot != part_slots[0]:
		out.append("its `part_slot` must be the first of its `part_slots` (%d), for older builds" % part_slots[0])
	if from_table and output != null and (output.material == null or output.by_hand):
		out.append("it is the material table's, but %s is no cell the table makes: untick `from_table` to make it yours" % output.display_name)
	return out


static func by_id(recipe_id: int) -> RecipeDef:
	for r: RecipeDef in all():
		if r.id == recipe_id:
			return r
	return null


## Every recipe made at `station_key`, in id order.
static func at(station_key: StringName) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for r: RecipeDef in all():
		if r.station == station_key:
			out.append(r)
	return out


static func all() -> Array[RecipeDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var out: Array[RecipeDef] = []
		for d: ContentDef in RegentsContent.items(&"recipe"):
			var r: RecipeDef = d as RecipeDef
			if r != null:
				out.append(r)
		out.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool: return a.id < b.id)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all
