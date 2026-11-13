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
## Whether it fights at all (hunting, 2026-11-09: a deer never does). One that does not needs no kit: its character's
## brain runs it (the deer's: `sidecar/npc/brains/regents/deer.gd`, it flees), and a hit STARTLES it
## (`regents.startle_ms`), so it bolts even from an arrow it never saw coming.
@export var fights: bool = true
## What it fights with: a FOE KIT of its own (COMBAT_OVERHAUL.md §2, 2026-10-31: slow, readable swings;
## never a player's), its light combo swung as one string, the last its finisher (often `unblockable`).
@export var kit: KitDef
## Its health.
@export_range(1, 100000) var hp: int = 120
## Its hits, as a weapon of this damage % (an iron sword is 100).
@export_range(0, 1000, 1, "suffix:%") var damage_pct: int = 60
## ITS POISE (Luke, 2026-11-02: staggers came too often): every melee hit wears it (`regents.poise_light`, the
## string's last `regents.poise_finisher`), and only the last hit can break it: then it staggers, and is Steadied
## (`regents.steadied_ms`: nothing wears it) after. Unhit for `regents.poise_regen_ms`, it is whole again. 0: no
## poise, every last hit staggers it (the old way).
@export_range(0, 10000) var poise: int = 70
## Mastery XP for hitting it, as a share of the usual (a dummy pays `regents.dummy_xp_pct`).
@export_range(0, 1000, 1, "suffix:%") var xp_pct: int = 100

@export_group("Behavior")
## HOW IT FIGHTS (Luke's F2, 2026-11-12): its behavior tree, by name. "melee": it chases, takes its turn, swings its
## string, rests (the skeletons, the wolf). The trees are the referee's (`sidecar/npc/brains/regents/trees/<name>.tres`,
## opened in the LimboAI tab: reorder a foe's tasks there); a name with no tree leaves the foe standing still, and the
## regents suite fails it. Not read for a creature that does not fight (its character's brain runs it).
@export var behavior: StringName = &"melee"
## It notices a player this near, in sight and IN FRONT of it (`notice_arc_deg`).
@export_range(1.0, 100.0, 0.5, "suffix:m") var notice_m: float = 10.0
## HOW WIDE IT SEES (Luke's F9, 2026-11-13): a player is seen only inside this arc in front of it, so a camp can be
## come at from behind. 360: it sees all round (the first build).
@export_range(10.0, 360.0, 5.0, "suffix:deg") var notice_arc_deg: float = 140.0
## IT HEARS all round (F9), seen or not: a player walking or running this near ...
@export_range(0.0, 50.0, 0.5, "suffix:m") var hear_m: float = 4.0
## ... and a SPRINTING one this near (faster than halfway from a run to a sprint, `shared/movement_config.json`).
@export_range(0.0, 50.0, 0.5, "suffix:m") var hear_sprint_m: float = 8.0
## AT REST IT WANDERS (Luke's F10, 2026-11-13): a few steps at a walk to a spot this near its point, a stand, and again,
## so it faces about. 0: it stands at its point (the first build).
@export_range(0.0, 20.0, 0.5, "suffix:m") var wander_m: float = 3.0
## It gives up and walks home once this far from home.
@export_range(2.0, 200.0, 0.5, "suffix:m") var leash_m: float = 25.0
## It stops and swings this near its target.
@export_range(0.5, 10.0, 0.1, "suffix:m") var reach_m: float = 1.9
## A breath after each combo: the opening a player gets (COMBAT_OVERHAUL.md §2: 1.5-2.5 s).
@export_range(0, 5000, 50, "suffix:ms") var rest_ms: int = 2000
## The rest is this much longer or shorter at random, so a group never falls into step.
@export_range(0, 2000, 50, "suffix:ms") var rest_jitter_ms: int = 500
## A target lost from sight (behind a rock, round a hut) is chased to where it was last seen for this long
## before the foe gives up on it (Luke's continent playtest, 2026-10-24, #4: one turned back at a bush).
@export_range(0, 10000, 100, "suffix:ms") var lose_sight_ms: int = 2500
## ITS STRING FOLLOWS ITS TARGET (Luke, 2026-11-11: a wolf's second and third bites "just hit air instead of gap
## closing"): between two swings of its string, a target that stepped out of reach is run down and the string goes on
## where it stopped, for this long after the last swing's lock ended; longer, the string is dropped (the next is its
## first swing again, after its rest, which the chase counts toward). 0: it gives the string up at once.
@export_range(0, 10000, 100, "suffix:ms") var string_chase_ms: int = 1500
## PACKS (Luke, 2026-11-10: wolves hunt in packs of 2-3): alerting or hitting one calls other foes of its kind within
## this far to join the fight (0: each for itself).
@export_range(0.0, 50.0, 0.5, "suffix:m") var pack_m: float = 0.0

@export_group("A foe that shoots (behavior \"ranged\")")
## ITS SHOT is its kit's first skill that a bolt `SpellDef` flies (`shot()`). It walks in until its target is this near
## (and in sight), then stands and shoots: it never shoots what it cannot see.
@export_range(2.0, 60.0, 0.5, "suffix:m") var shot_range_m: float = 14.0
## Walking in, it stops this near (so it stands between this and `shot_range_m`, not at the edge of its range).
@export_range(1.0, 60.0, 0.5, "suffix:m") var shot_near_m: float = 9.0
## Between two shots (after the last one's lock): the opening a player gets to close in.
@export_range(0, 10000, 50, "suffix:ms") var shot_rest_ms: int = 1800
## A RING (the imp's): every `ring_every`-th cast is its kit's first skill an AREA `SpellDef` lays (`ring()`), on the
## ground where its target stands as the cast ends; the others are its shot. 0: it never lays one.
@export_range(0, 10) var ring_every: int = 0
## IT KEEPS ITS DISTANCE, AND IS CAUGHT (Luke's F3): a target within `back_within_m` and it steps back `back_m`, at a
## walk, at most once every `back_every_ms`; in between it stands its ground, and in `reach_m` it swings its string
## (a shove). 0 `back_m`: it never steps back.
@export_range(0.0, 20.0, 0.5, "suffix:m") var back_within_m: float = 4.0
@export_range(0.0, 20.0, 0.5, "suffix:m") var back_m: float = 5.0
@export_range(0, 60000, 100, "suffix:ms") var back_every_ms: int = 6000

@export_group("Its look")
## IN ITS HAND (a `HeldItem` scene, as a weapon's `ItemDef.held_scene`: the archer's bow). Empty: only what its model
## carries.
@export var held_scene: PackedScene
## Meshes of its model to hide, by node name (the archer's "Skeleton_Sword": the same model as the warrior).
@export var hidden_meshes: Array[StringName] = []
## Its model's colors (a texture over every mesh's own: the pack's other texture sets). Empty: the model's own.
@export var albedo: Texture2D

@export_group("A creature that flees (one that does not fight)")
## It sees a player within `notice_m` (in sight) and bolts; this near it hears them, seen or not.
@export_range(0.0, 50.0, 0.5, "suffix:m") var startle_m: float = 5.0
## It runs this far from what scared it each time (round what is in the way), never past `leash_m` from home.
@export_range(1.0, 100.0, 0.5, "suffix:m") var flee_m: float = 25.0
## With nobody near (within `notice_m`) this long, it calms and walks back to graze.
@export_range(0, 60000, 500, "suffix:ms") var calm_ms: int = 6000
## Grazing, it wanders this far from home, a few steps at a time.
@export_range(0.0, 50.0, 0.5, "suffix:m") var graze_m: float = 6.0

## Its FAMILY ("undead", "beast", "humanoid"): what a trait made against one reads (Hunter's: more against
## beasts, less against humanoids).
@export var family: StringName = &""
## A BOSS (COMBAT_OVERHAUL.md §5, Luke 2026-11-01): what a guard handle's extra threat counts against when
## `regents.guard_threat_bosses_only` is on (to be tested).
@export var boss: bool = false
## THE PARRY RING (Luke, 2026-11-01, T4: a timing aid in the tutorial's yard only): a ring closes on each of its
## swings, shut as the blow lands. On for the yard's sparring partner; the real fight keeps the pose and the glint.
@export var parry_ring: bool = false
@export_group("Loot")
## What a kill drops (a loot table: each line its chance, shared tables, pity). Empty: nothing.
@export var loot_table: LootTableDef
## What a kill LEAVES (skinning, Luke 2026-11-09): a CARCASS, this node, where it fell (its body taken away at once),
## skinned with a knife; its top damager's alone `regents.carcass_own_s`, then anyone's; it rots away after
## `regents.carcass_rot_s`. Empty: its body only, as a skeleton's.
@export var carcass: NodeDef

static var _all: Array[FoeDef] = []


func content_type() -> StringName:
	return &"foe"


func summary() -> String:
	var how: String = ("%s at %d%%" % [kit.key if kit != null else "?", damage_pct]) if fights else "flees"
	return "%s: %d hp, %s, drops %s" % [key, hp, how, loot_table.display_name if loot_table != null else "nothing"]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"kind": character.kind if character != null else 0,
		"kit": String(kit.key) if kit != null else "",
		"fights": fights,
		"brain": String(character.brain) if character != null else "",
		"hp": hp,
		"damage_pct": damage_pct,
		"xp_pct": xp_pct,
		"loot_table": ContentDef.ref(loot_table),
		"family": String(family),
		"boss": boss,
		"poise": poise,
		"carcass": ContentDef.ref(carcass),
		# Where a shot aimed at it by the server goes: the middle of its body (a wolf is half a man's height:
		# aimed at a man's chest, every arrow at a Tab-targeted wolf flew over its back; Luke, 2026-11-11).
		"aim_height_m": aim_height_m(),
	}


## The height above its feet a shot aimed at it is sent to: the middle of its character's body.
func aim_height_m() -> float:
	return character.collision_height * 0.5 if character != null and character.collision_height > 0.0 else DEFAULT_AIM_HEIGHT_M


## Where a shot is aimed on a body with no size of its own (a player, a dummy). Twin: `rules::AIM_HEIGHT_M`.
const DEFAULT_AIM_HEIGHT_M: float = 1.1


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key: the level points it stands on are named by it")
	if character == null or character.kind < 100:
		out.append("its character must be a genre kind (100 or more)")
	if fights and behavior == &"":
		out.append("it fights with no behavior: set `behavior` to one of the referee's trees (\"melee\")")
	if fights and behavior == &"ranged":
		var a: AbilityDef = shot()
		if a == null:
			out.append("its behavior is ranged, but its kit has no shot: a skill with a bolt SpellDef (content/spell/)")
		elif a.range_m > 0.0 or a.judged:
			out.append("its shot (%s) must have range_m 0 and judged off: its missile carries the hit" % a.display_name)
		var r: AbilityDef = ring()
		if ring_every > 0 and r == null:
			out.append("`ring_every` is set, but its kit has no ring: a skill with an area SpellDef")
		elif r != null and (r.range_m > 0.0 or r.judged):
			out.append("its ring (%s) must have range_m 0 and judged off: its circle carries the hit" % r.display_name)
		if shot_near_m > shot_range_m:
			out.append("`shot_near_m` is past `shot_range_m`: it would never stand in range")
	if fights and kit == null:
		out.append("it fights with no kit: set `kit` (or untick `fights`, for a creature that only flees)")
	if not fights and (character == null or character.brain == &""):
		out.append("it never fights, so its character's brain runs it: set the character's `brain`")
	return out


## ITS SHOT: its kit's first skill that a bolt spell flies (null: it has none, a melee foe).
func shot() -> AbilityDef:
	if kit == null:
		return null
	for a: AbilityDef in kit.skills:
		var s: SpellDef = SpellDef.by_ability(a.id) if a != null else null
		if s != null and s.kind == SpellDef.Kind.BOLT:
			return a
	return null


## ITS RING: its kit's first skill that an area spell lays (null: it has none).
func ring() -> AbilityDef:
	if kit == null:
		return null
	for a: AbilityDef in kit.skills:
		var s: SpellDef = SpellDef.by_ability(a.id) if a != null else null
		if s != null and s.kind == SpellDef.Kind.AREA:
			return a
	return null


## Its `n`-th cast (0 the first): its ring every `ring_every`-th, else its shot.
func cast_at(n: int) -> AbilityDef:
	var r: AbilityDef = ring() if ring_every > 0 and n % ring_every == ring_every - 1 else null
	return r if r != null else shot()


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
