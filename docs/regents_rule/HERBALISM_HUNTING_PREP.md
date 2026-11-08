# Before herbalism and hunting: what is there, what is coming, and the decisions that are yours (2026-11-07)

**ANSWERED (Luke, 2026-11-07), as proposed except**: H2, herbalism's tool is a TROWEL, not a sickle ("we are pulling
the plants"); H9, a FIRST TRINKET NOW (a creature-trophy charm, its trait designed with him). In full in `GAME.md`
("Herbalism and hunting, ANSWERED"); §7 below is the order of work with both folded in.

Luke, 2026-11-07, after the minigame overhaul's build steps: "Yes, prep sheet". This is item (3) of `GAME.md`'s
order of work ("The order of work, armor parked"): **herbalism and hunting: fiber and hides, and the creatures hunted
for them (foe design too: the place for foes that push, poison or slow)**. Armor waits on it (`ARMOR_PREP.md`: cloth
and leather). Like the minigame and armor sheets, every decision (§6) carries a proposed answer; nothing is built until
Luke answers; his answers go to `GAME.md` and §7 becomes the order of work.

## 1. What is already settled (Luke's, with where)
- **Every skill is dual-mode** (#23): tap E works AFK, hold E plays a round; rounds back to back (M11); a played round
  pays 0.75 to 1.25 of AFK by score; rank eases it (M3). Herbalism and anything new follow this.
- **Gathering nodes are shared world objects** (`RULE_DESIGN.md` §7.1): placed in the level, depleted for everyone,
  back at the same moment for all. An herb patch is a node.
- **Tools come from the bag** (#15): no tool slot; the best matching tool is used.
- **No Hunting skill** (`MATERIALS.md` §3, 2026-10-23): "hide and sinew from creature drops ... No Hunting skill". The
  minigame sheet later proposed SKINNING the kill (M10, "confirmed with its step"): the two need settling (H1).
- **Bindings**: fiber from herbalism, hide and sinew from creatures (`MATERIALS.md` §3); "fiber wraps and oils, and
  their traits: with herbalism" (§11); "names for tiers 4-6, the fibers and the hides: with herbalism" (§11).
- **The bow is carved unstrung** (2026-11-07, PROGRESS 49): "with herbalism, seems we can do unstrung bow into strung
  bow". The string is the first thing fiber makes.
- **New skills' minigames** (M10): pull the root (herbalism), the cut line (skinning), each confirmed with its step.
- **Loot is personal** (#7): rolled per contributing player; a drop is yours for a while, then anyone's.
- **The trinket stays empty until herbalism** (`ARMOR_PREP.md` A8): it is filled from here or from creature drops.

## 2. What is built that this leans on
| Piece | State | What this needs from it |
|---|---|---|
| `NodeDef` + node scenes | trees, rocks; skill, tier, tool tag and tier, rank, yield, rare (catalyst) | an herb patch is a `NodeDef` with a new skill; its look from the nature pack (fern, flowers, mushroom, bush) |
| Skills | woodcutting, mining, smelting, smithing, crafting; four weapon kits | Herbalism a new `SkillDef` (content); Skinning only if H1 says so |
| The material table | metal and wood families; patterns cross materials | a FIBER and a HIDE family; their cells (flax, wolf pelt...); a sickle pattern if H2 says so |
| Foes | three skeletons (`FoeDef`), one brain: chase, swing, leash | animals: a FLEE brain (deer), a pack brain (wolves); loot tables per creature |
| Characters | the humanoid rig (Quaternius UAL), its `AnimationSet` | Quaternius's Ultimate Animated Animals (on Luke's PC: Deer, Stag, Wolf, Fox, Husky, farm animals; NO boar, NO bear): a quadruped rig with its own clips: a new `AnimationSet` per animal, and the animation tree builder checked on a non-humanoid skeleton (foundation: template work if it needs widening) |
| Minigames | five models (chop, crack, beat, shape, carve), the readout | pull the root: a new TENSION model; skinning: see H4 |
| Loot | `LootTableDef`, personal drops on the ground | hides, sinew, meat drops; or a carcass to skin (H1) |

## 3. Herbalism, proposed shape
- **What you gather**: FIBER plants first (they feed bowstrings, bindings, later cloth). Herbs for potions come with
  potions (later in the order), so no herb sits in a bag with no use.
- **The ladder** (names are Luke's, `MATERIALS.md` §11; proposed): tier 1 **Flax** (a meadow plant), tier 2 **Hemp**,
  tier 3 **Nettle** (stings: a band-2 rule could live here). Their fibers are the fiber family's three materials.
- **The look**: the nature pack's Flower_3_Group, Fern and Bush, tinted per plant; picked, it is a stub that regrows.
- **The minigame: PULL THE ROOT** (Tension family, `MINIGAMES_PREP.md` §2): hold to pull the plant up out of the
  ground; strain rises while you hold and eases when you let go; past the top it SNAPS and the round ends with what you
  had. The plant TREMBLES (seen and heard) just before the strain jumps, so a player reads the plant, not a meter. A
  clean pull (whole root) scores well; the score pays fiber by M11's curve and the rare find (a seed pod?) by M11's
  edge. Band 2's rule (proposed: roots that branch, two strains to watch); band 3 (a wilting plant: the whole pull on
  a clock). A NEW MODEL: params, GDScript, Rust twin, goldens, a stage (the plant at your feet, the hand pulling: no
  character, as the others).

## 4. Hunting, proposed shape
- **The hunt is the fight** (weapon mastery as now): no tracking minigame, no Hunting skill for the chase itself.
- **What a kill gives**: hides, sinew and meat. Two ways (H1): straight into personal loot as the skeletons' drops are
  now (simple, no new skill), or a CARCASS you skin (tap E AFK, hold E the cut-line round) for a new SKINNING skill,
  its rank gating the better hides as gathering ranks gate the better nodes.
- **The creatures, first three** (from the animals on hand):
  | Creature | How it acts | Gives | Proves |
  |---|---|---|---|
  | **Deer** (tier 1) | grazes; FLEES when it hears or sees you (a new brain); never fights | deer hide, meat | a non-combat brain; the bow's use (catch it from range) |
  | **Wolf** (tier 2, packs of 2-3) | hunts you as a pack; its LUNGE knocks you back (push); a HAMSTRING bite slows you | wolf pelt, sinew | "foes that push or slow" (`GAME.md`), the pack brain (Fowl Play's predator brain adapted, `RULE_DESIGN.md` §6.3) |
  | **Stag** (tier 3) | flees, but CHARGES when cornered or hurt (a big push) | stag hide, antler (a catalyst?) | a creature that changes its mind |
  POISON has no fitting animal in the pack (no snake, no spider): it waits for an asset (Luke's? a CC0 pack) or a
  bandit's poisoned blade.
- **Where**: the continent's meadows for deer and flax, the forest edges for wolves, high ground for stags (its
  placement is a TEST one until Luke's own, `.claude/rules/regents-genre.md`); the glade (level 20) gets one deer and a
  flax patch for the suites.

## 5. What fiber and hide turn into (the first products, so each is useful the day it lands)
- **The bowstring**: fiber (or sinew) at the workbench; then **stringing**: the carved UNSTRUNG yew bow + a string =
  the Yew bow (its quality from the stave, the core: M12). The yew bow recipe today makes the bow directly: it becomes
  the stave's recipe, and stringing a new one. Bows already in bags stay bows.
- **Wraps** (bindings with traits, `MATERIALS.md` §11): a FIBER WRAP and a LEATHER WRAP as binding parts, each with a
  tool trait and a weapon trait (names and traits are Luke's: proposed flax wrap Light / Quick, leather wrap Sure-grip
  / Steady-hand... to be designed with him).
- **Leather**: hides become leather (TANNING) before they are used: H6.
- **Later, not in this piece**: cloth and leather ARMOR (armor resumes after this, `ARMOR_PREP.md`); potions; the
  trinket (H9); meat (cooking, later).

## 6. Decisions for Luke
Each with the proposed answer. The bold part is what needs his yes or no.

- **H1. Skinning: a skill, or drops?** **Proposed: a SKINNING skill** (dual-mode like all the others: a kill leaves a
  carcass you skin, tap E AFK or hold E for the cut-line round; skinning rank gates the better hides). It keeps
  "every material from a skill you level", gives hunters a craft, and is where M10's cut line lives. This REVISES
  2026-10-23's "No Hunting skill" (which was about the chase, not the skinning). The other way: hides drop as loot
  from a kill (no new skill, no minigame), as the skeletons' ore does today.
- **H2. Herbalism's tool.** **Proposed: a SICKLE**, a pattern of the material table (copper, iron, steel sickles:
  smithing gets a fourth tool), its tier gating the plants' tiers as an axe's gates trees. Or bare hands (no tool,
  simpler; nothing gates the plants but rank).
- **H3. Pull the root, as §3.** **Proposed: yes**: hold to pull, strain rises, it trembles before a jump, a snap ends
  it; the score pays fiber and the rare. Band 2: branching roots; band 3: a wilting clock. (A new model.)
- **H4. Skinning's round.** **Proposed: a new TRACE model you DRAG**: hold the mouse and draw the knife along the hide's
  cut line; time near the line scores, wandering off tears the hide (less of it). Its feel is continuous, unlike
  mining's clicks on notches. The other way: mining's model with a hide stage (no new model; it would feel like
  mining, and Luke turned down a duplicate for carving).
- **H5. The first creatures.** **Proposed: deer (tier 1, flees), wolf (tier 2, packs; pushes and slows), stag (tier 3,
  flees, charges when cornered)**, from the animal pack on hand. Poison waits for an asset: **does Luke have a
  snake, spider or similar pack**, or should one be found (CC0)?
- **H6. What turns hides and fiber into leather and string.** **Proposed: crafting recipes for now** (a TANNING RACK and
  a SPINNING WHEEL as stations, AFK only, trained by Crafting), with their own skills and minigames later if they earn
  them (tanning: a scrape rhythm; spinning: the shuttle, `MINIGAMES_PREP.md` §2). Or new skills (Tanning, Spinning)
  now, each needing a round.
- **H7. The names.** Proposed: fibers **Flax, Hemp, Nettle**; hides **Deer hide, Wolf pelt, Stag hide**; leathers
  **Soft, Supple, Hardened leather**? All his (`MATERIALS.md` §11).
- **H8. The first products, as §5.** **Proposed: the bowstring and stringing the yew bow; a fiber wrap and a leather
  wrap as bindings with traits.** Their traits are designed with him (each must trade, `LOOT_AND_STYLES.md` §2).
- **H9. The trinket.** **Proposed: still empty in this piece**; filled when potions or the creature trophies (an
  antler, a fang) have a design. Or a first trinket now (a wolf-fang charm).
- **H10. Rare finds (catalysts).** **Proposed: a seed pod from plants, an antler or a fang from carcasses**, as the
  gem and the nest are for rocks and trees (`MATERIALS.md` §6).
- **H11. Meat.** **Proposed: not dropped yet** (cooking is later; a bag item with no use is clutter). Or dropped now
  for a vendor later.

## 7. The order of work (once answered)
1. **Herbalism, AFK first**: the skill, flax patches (nodes) in the glade and the continent, the TROWEL (a pattern of
   the material table: copper, iron, steel), fiber into the bag; the bowstring and STRINGING the yew bow (the carved stave becomes "Unstrung yew bow"). Playable.
2. **Pull the root** (H3): the Tension model, its twin and goldens, its stage; the readout's players; tuned to M11.
3. **The deer**: the animal imported (its rig, an `AnimationSet`, the tree builder checked on it: foundation work goes
   to the template first if it needs widening), the FLEE brain, a spawner; its kill gives a carcass (H1) or hides.
4. **Skinning** (H1, H4): AFK first, then its round; deer hide; tanning (H6) into leather; the leather wrap.
5. **The wolf**: the pack brain, the lunge's push and the hamstring's slow (statuses exist: `status_state`), wolf
   pelt and sinew, the fang (a rare); THE FIRST TRINKET, a fang charm, its trait designed with Luke; the stag after it
   (the antler).
6. **Hemp and nettle, the higher tiers**, band 2 rules for pull the root and skinning; the readout and Luke's play.
7. Then ARMOR resumes (`ARMOR_PREP.md`, §0: cloth and leather), and the combat deep-dive after it with real creatures.

## 8. Costs to know before answering
- **Animals are the biggest piece**: a new rig and clips per animal, two new brains (flee, pack), the hit and death
  for a body that is not a person (its collider, where an arrow lands). The deer alone is about a step; each further
  animal is mostly content once the first works.
- **Each new minigame model is about one step** (the five built so far): pull the root and skinning (if H4's drag) are
  two.
- **The material table needs two new families** (fiber, hide) and their cells; a sickle is one more pattern (content).
- Nothing here reshapes a table: new content and side tables only (rule 17).
