@tool
class_name TreeDef extends ContentDef
## A TREE TO CHOP (design §7.1, §7.4): a static world object a level places (a `LevelPoint` of kind
## "tree", tagged with the tree's name), which every player shares: it falls to a stump for everyone and
## grows back. Worked two ways at the player's choice (owner, 2026-10-18):
##   AFK      tap E: a log every `afk_ms_per_log`, until you move or it falls
##   active   hold E: a round of its minigame (`chop`: woodcutting's branch dodge for tiers 1-3); the
##            round yields what AFK would in the same time x `regents.active_yield_mult` x its score
## Each log may fell it (`fell_permille`) and may come with a rare find (`rare_item`, more likely when
## played: `regents.active_rare_mult`). The server compiles these numbers in (`server/build/regents.rs`).

## Its tier: harder rounds, better logs, slower to work AFK.
@export_range(1, 20) var tier: int = 1
## Its round: woodcutting's branch dodge (`ChopModel`). Played in `chop_lab.tscn` (F6).
@export var chop: ChopParams
@export_group("What it gives")
## What a log of it is.
@export var log_item: ItemDef
## The lowest tier of axe that works it.
@export_range(1, 20) var min_axe_tier: int = 1
## AFK: one log this often.
@export_range(500, 120000, 100, "suffix:ms") var afk_ms_per_log: int = 4000
## Each log: the chance in thousandths that it is the last (the tree falls).
@export_range(0, 1000, 5, "suffix:‰") var fell_permille: int = 250
## How long its stump stands before it grows back.
@export_range(1.0, 3600.0, 1.0, "suffix:s") var regrow_s: float = 30.0
## A rare find that may come with a log (empty: none).
@export var rare_item: ItemDef
## Its chance per log AFK, in thousandths (active play multiplies it).
@export_range(0, 1000, 1, "suffix:‰") var rare_permille: int = 0
@export_group("How it shows")
## Its looks standing (one is picked per tree, by where it stands).
@export var models: Array[PackedScene] = []
@export_range(0.1, 5.0, 0.05) var model_scale: float = 1.0
## Its stump's colour (a greybox stump until there is a model for one).
@export var stump_color: Color = Color(0.42, 0.29, 0.18)

static var _by_id: Dictionary[int, TreeDef] = {}


func content_type() -> StringName:
	return &"tree"


func why_no_workbench() -> String:
	return "its round is tried in the chop lab (game/regents/skilling/woodcutting/chop_lab.tscn), its look in the glade"


func summary() -> String:
	return "Tier %d: a log AFK every %.1f s, falls 1 in %d" % [tier, afk_ms_per_log / 1000.0, 1000 / maxi(fell_permille, 1)]


func to_bake() -> Dictionary:
	var c: ChopParams = chop if chop != null else ChopParams.new()
	return {
		"id": id,
		"name": display_name,
		"tier": tier,
		"chop": {
			"duration_ms": c.duration_ms, "swing_ms": c.swing_ms, "stagger_ms": c.stagger_ms,
			"branch_permille": c.branch_permille, "safe_segments": c.safe_segments, "target_chops": c.target_chops,
		},
		"log_item": ContentDef.ref(log_item),
		"min_axe_tier": min_axe_tier,
		"afk_ms_per_log": afk_ms_per_log,
		"fell_permille": fell_permille,
		"regrow_ms": int(regrow_s * 1000.0),
		"rare_item": ContentDef.ref(rare_item),
		"rare_permille": rare_permille,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if chop == null:
		out.append("it has no round: give it `chop` (ChopParams)")
	elif chop.target_chops > ChopModel.max_chops(chop):
		out.append("its round's target (%d) is more than a round can chop (%d)" % [chop.target_chops, ChopModel.max_chops(chop)])
	if log_item == null:
		out.append("it gives nothing: set `log_item`")
	if rare_permille > 0 and rare_item == null:
		out.append("a rare chance with no rare item: set `rare_item` or the chance to 0")
	if models.is_empty() or models.has(null):
		out.append("it has no look: add `models`")
	return out


## The tree with content id `tree_id`, or null.
static func by_id(tree_id: int) -> TreeDef:
	if Engine.is_editor_hint() or _by_id.is_empty():
		var all: Dictionary[int, TreeDef] = {}
		for d: ContentDef in ContentLibrary.items(&"tree"):
			var t: TreeDef = d as TreeDef
			if t != null:
				all[t.id] = t
		if Engine.is_editor_hint():
			return all.get(tree_id, null)
		_by_id = all
	return _by_id.get(tree_id, null)


## Every tree, lowest tier first.
static func all_by_tier() -> Array[TreeDef]:
	var out: Array[TreeDef] = []
	for d: ContentDef in ContentLibrary.items(&"tree"):
		var t: TreeDef = d as TreeDef
		if t != null:
			out.append(t)
	out.sort_custom(func(a: TreeDef, b: TreeDef) -> bool: return a.tier < b.tier or (a.tier == b.tier and a.id < b.id))
	return out
