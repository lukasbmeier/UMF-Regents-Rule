@tool
class_name NodeDef extends ContentDef
## A GATHERING NODE (design §7.1, §7.4): a tree, a rock, later a herb patch or a fishing spot. A static
## world object a level places (a `LevelPoint` of kind "node", tagged with this node's name), shared by
## everyone: it is worked out for everyone (a stump, rubble) and comes back after `regrow_s`. Worked two
## ways at the player's choice (owner, 2026-10-18):
##   AFK      tap E: one `yield_item` every `afk_ms_per_item` (faster with a better tool, a higher rank)
##   active   hold E: a round of `minigame` (its tier band's: branch dodge for trees 1-3, crack the rock
##            for rocks 1-3), paying what AFK makes in the round's time x `regents.active_yield_mult` x
##            the score
## Each item gives `xp` in its skill, may bring `rare_item`, and may exhaust the node (`deplete_permille`).
## The server compiles these numbers in (`server/build/regents.rs`).

enum Depleted { STUMP, RUBBLE }

## The skill it trains (and whose rank it needs).
@export var skill: SkillDef
## Its tier: harder rounds, better yields, slower AFK.
@export_range(1, 20) var tier: int = 1
## Its round (a `ChopParams`, a `CrackParams`: `SkillMinigames`). Played in the skilling lab.
@export var minigame: Resource
@export_group("Working it")
## What it gives.
@export var yield_item: ItemDef
## The tool it needs (in the bag): "axe", "pick". And the lowest tier of it.
@export var tool_tag: StringName = &"axe"
@export_range(1, 20) var min_tool_tier: int = 1
## The rank in `skill` it needs.
@export_range(1, 99) var min_rank: int = 1
## XP each item gives.
@export_range(0, 10000) var xp: int = 10
## AFK: one item this often (before the tool's and the rank's speed).
@export_range(500, 120000, 100, "suffix:ms") var afk_ms_per_item: int = 4000
## Each item: the chance in thousandths that it is the last (the node is worked out).
@export_range(0, 1000, 5, "suffix:‰") var deplete_permille: int = 250
## How long it stays worked out.
@export_range(1.0, 3600.0, 1.0, "suffix:s") var regrow_s: float = 30.0
## A rare find that may come with an item (empty: none), and its chance per item AFK.
@export var rare_item: ItemDef
@export_range(0, 1000, 1, "suffix:‰") var rare_permille: int = 0
@export_group("How it shows")
## Its looks (one is picked per node, by its entity).
@export var models: Array[PackedScene] = []
@export_range(0.1, 5.0, 0.05) var model_scale: float = 1.0
## What is left when it is worked out: a stump (it tips over) or rubble (it crumbles).
@export var depleted: Depleted = Depleted.STUMP
@export var depleted_color: Color = Color(0.42, 0.29, 0.18)
## Ore showing on a rock (its nuggets' color); transparent for none.
@export var ore_color: Color = Color(0, 0, 0, 0)

static var _by_id: Dictionary[int, NodeDef] = {}
## Each model's footprint (`footprint_cm`), worked out once per model and scale.
static var _footprints: Dictionary[String, int] = {}


func content_type() -> StringName:
	return &"node"


func why_no_workbench() -> String:
	return "its round is tried in the skilling lab (game/regents/skilling/skilling_lab.tscn), its look in the glade"


func summary() -> String:
	return "%s tier %d (rank %d): AFK every %.1f s, out 1 in %d" % [skill.display_name if skill != null else "?", tier, min_rank,
		afk_ms_per_item / 1000.0, 1000 / maxi(deplete_permille, 1)]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"skill": ContentDef.ref(skill),
		"tier": tier,
		"minigame": SkillMinigames.bake(minigame),
		"yield_item": ContentDef.ref(yield_item),
		"tool_tag": String(tool_tag),
		"min_tool_tier": min_tool_tier,
		"min_rank": min_rank,
		"xp": xp,
		"afk_ms_per_item": afk_ms_per_item,
		"deplete_permille": deplete_permille,
		"regrow_ms": int(regrow_s * 1000.0),
		"rare_item": ContentDef.ref(rare_item),
		"rare_permille": rare_permille,
		"radii_cm": radii_cm(),
	}


## HOW BIG IT STANDS (Luke, 2026-11-06, PROGRESS 44: the work reach is "measured from its edge"): each model's
## footprint in whole centimeters: where a body walking up is stopped (`NodeComponent`'s solid). A rock is solid as
## drawn: the farthest of its drawn points under `FOOTPRINT_UNDER_M` from its middle, flat, at `model_scale`; a tree
## only at its trunk (`NodeComponent.TRUNK_RADIUS` x `model_scale`: its crown and low boughs are walked under).
## Worked out from the models themselves, so a new model needs nothing typed; baked for the server (`radii_cm`),
## which picks a node's by its entity as the client picks its model.
const FOOTPRINT_UNDER_M: float = 2.0
func radii_cm() -> Array[int]:
	var out: Array[int] = []
	for scene: PackedScene in models:
		out.append(_footprint_cm_of(scene))
	return out


## The footprint of the model a node of entity `entity_id` shows, in meters (the client's half of `radii_cm`).
func radius_for(entity_id: int) -> float:
	if models.is_empty():
		return 0.0
	return _footprint_cm_of(models[absi(entity_id) % models.size()]) / 100.0


func _footprint_cm_of(scene: PackedScene) -> int:
	if depleted != Depleted.RUBBLE:
		return ceili(NodeComponent.TRUNK_RADIUS * model_scale * 100.0)   # a tree: its trunk
	return footprint_cm(scene, model_scale)


## `scene`'s drawn footprint at `scale`, in whole centimeters (rounded up): the farthest of its meshes' points under
## `FOOTPRINT_UNDER_M` from its middle, flat.
static func footprint_cm(scene: PackedScene, scale: float) -> int:
	if scene == null:
		return 0
	var key: String = "%s@%.3f" % [scene.resource_path, scale]
	if _footprints.has(key):
		return _footprints[key]
	var root: Node3D = scene.instantiate() as Node3D
	var r: float = 0.0
	if root != null:
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p != null and p != root:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for surface: int in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in verts:
					var w: Vector3 = (xf * v) * scale
					if w.y <= FOOTPRINT_UNDER_M:
						r = maxf(r, Vector2(w.x, w.z).length())
		root.free()
	var cm: int = ceili(r * 100.0)
	_footprints[key] = cm
	return cm


func validate() -> Array[String]:
	var out: Array[String] = super()
	if skill == null:
		out.append("it trains no skill: set `skill`")
	var kind: StringName = SkillMinigames.kind_of(minigame)
	# None: AFK only (holding E works it AFK too), as a plant before its round is built (2026-11-07).
	if minigame != null and kind != SkillMinigames.CHOP and kind != SkillMinigames.CRACK:
		out.append("its `minigame` is not a gathering round (a ChopParams or a CrackParams; or none: AFK only)")
	if yield_item == null:
		out.append("it gives nothing: set `yield_item`")
	if rare_permille > 0 and rare_item == null:
		out.append("a rare chance with no rare item: set `rare_item` or the chance to 0")
	if models.is_empty() or models.has(null):
		out.append("it has no look: add `models`")
	return out


static func by_id(node_id: int) -> NodeDef:
	if Engine.is_editor_hint() or _by_id.is_empty():
		var all: Dictionary[int, NodeDef] = {}
		for d: ContentDef in RegentsContent.items(&"node"):
			var n: NodeDef = d as NodeDef
			if n != null:
				all[n.id] = n
		if Engine.is_editor_hint():
			return all.get(node_id, null)
		_by_id = all
	return _by_id.get(node_id, null)


## Every node, by skill then tier.
static func all_by_tier() -> Array[NodeDef]:
	var out: Array[NodeDef] = []
	for d: ContentDef in RegentsContent.items(&"node"):
		var n: NodeDef = d as NodeDef
		if n != null:
			out.append(n)
	out.sort_custom(func(a: NodeDef, b: NodeDef) -> bool:
		var sa: int = a.skill.id if a.skill != null else 0
		var sb: int = b.skill.id if b.skill != null else 0
		return sa < sb or (sa == sb and (a.tier < b.tier or (a.tier == b.tier and a.id < b.id))))
	return out
