@tool
class_name FoeDef extends ContentDef
## A FOE (owner, 2026-10-19: the first enemies are skeletons from the Bestiary pack): a monster placed on a
## level's points of kind `key`, that notices a player within `notice_m`, chases, fights with its `kit`
## (the same swings, timing, blocks and flinches as a player's), and gives up past `leash_m` from home.
## Slain, it pays mastery XP and a roll of its `loot_table` to each player who did enough of the damage (a
## personal roll, DECISIONS #268), lies there `regents.foe_corpse_s` and
## comes back `regents.foe_respawn_s` after it fell. The server keeps the numbers that decide outcomes
## (baked: health, damage, XP, loot); its brain (`sidecar/npc/brains/regents/foe.gd`) reads the rest here.

## The level points it stands on (a LevelPoint's `kind`): "skeleton_warrior".
@export var key: StringName = &""
## What it is in the world: its model, animations, movement and kind (a genre kind, 100 or more).
@export var character: EntityDefinition
## What it fights with: a weapon kit's light combo and heavy (it uses no skills).
@export var kit: KitDef
## Its health.
@export_range(1, 100000) var hp: int = 120
## Its hits, as a weapon of this damage % (an iron sword is 100).
@export_range(0, 1000, 1, "suffix:%") var damage_pct: int = 60
## Mastery XP for hitting it, as a share of the usual (a dummy pays `regents.dummy_xp_pct`).
@export_range(0, 1000, 1, "suffix:%") var xp_pct: int = 100

@export_group("Behaviour")
## It notices a player this near (and in sight).
@export_range(1.0, 100.0, 0.5, "suffix:m") var notice_m: float = 10.0
## It gives up and walks home once this far from home.
@export_range(2.0, 200.0, 0.5, "suffix:m") var leash_m: float = 25.0
## It stops and swings this near its target.
@export_range(0.5, 10.0, 0.1, "suffix:m") var reach_m: float = 1.9
## Every this many swings is the kit's heavy (0: never).
@export_range(0, 20) var heavy_every: int = 3
## A breath after each combo: the opening a player gets.
@export_range(0, 5000, 50, "suffix:ms") var rest_ms: int = 900
## A target lost from sight (behind a rock, round a hut) is chased to where it was last seen for this long
## before the foe gives up on it (Luke's continent playtest, 2026-10-24, #4: one turned back at a bush).
@export_range(0, 10000, 100, "suffix:ms") var lose_sight_ms: int = 2500

## Its FAMILY ("undead", "beast", "humanoid"): what a trait made against one reads (Hunter's: more against
## beasts, less against humanoids).
@export var family: StringName = &""
@export_group("Loot")
## What a kill drops (a loot table: each line its chance, shared tables, pity). Empty: nothing.
@export var loot_table: LootTableDef

static var _all: Array[FoeDef] = []


func content_type() -> StringName:
	return &"foe"


func summary() -> String:
	return "%s: %d hp, %s at %d%%, drops %s" % [key, hp, kit.key if kit != null else "?", damage_pct, loot_table.display_name if loot_table != null else "nothing"]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"kind": character.kind if character != null else 0,
		"kit": String(kit.key) if kit != null else "",
		"hp": hp,
		"damage_pct": damage_pct,
		"xp_pct": xp_pct,
		"loot_table": ContentDef.ref(loot_table),
		"family": String(family),
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key: the level points it stands on are named by it")
	if character == null or character.kind < 100:
		out.append("its character must be a genre kind (100 or more)")
	if kit == null:
		out.append("it fights with no kit: set `kit`")
	return out


## The foe that is entity kind `kind`, or null.
static func by_kind(kind: int) -> FoeDef:
	for f: FoeDef in all():
		if f.character != null and f.character.kind == kind:
			return f
	return null


static func all() -> Array[FoeDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var out: Array[FoeDef] = []
		for d: ContentDef in RegentsContent.items(&"foe"):
			var f: FoeDef = d as FoeDef
			if f != null:
				out.append(f)
		_all = out
	return _all
