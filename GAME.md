# GAME.md — what this repo is

**Regent's Rule** (game 4, working title): a fantasy MMO-lite for 100–300 concurrent players in one
database. One seamless world you log back into where you left; the weapon you hold is your class;
trees, veins and herbs are shared world objects worked through minigames the server scores; a lair in
the open and a procedurally assembled dungeon in an instance. A fork of the UMF template
(UMF-Foundation); foundation updates arrive with `git pull template main`
(`docs/TEMPLATE_WORKFLOW.md`), and foundation work is done in the template, not here. This game asks
for more of the foundation than games 1–3 together (M8, M16, M18–M26, the template 1.0): those are
built in the TEMPLATE and pulled.

| | |
|---|---|
| Genres | `regents` (`shared/game.json`): its client in `game/regents/` (content id base 40000), its server in `server/src/game/regents.rs` |
| Database | `regents-rule`; the suites use `regents-rule-test` |
| Main scene | `res://game/regents/regents_game.tscn` (the frontier glade, level 20) |
| Genre rules files | the hot rules `game/regents/content/rules/regents.tres` (the Rules page, `regents.*`) |
| Genre manifest | `tools/template/genres/regents.paths` (AGENTS.md rule 16) |
| Genre suites | `game/regents/tests/suites/regents.gd` (`-- --only=regents`) |

## The design
| File | What it is |
|---|---|
| `docs/regents_rule/RULE_DESIGN.md` | THE DESIGN: pillars, combat (four resolution kinds, the cast queue), the world and its chunks, NPC tiers, nodes and minigames, items, accounts, scale, the build plan (§12), open items (§13) |

Owner decisions (2026-10-13 scope; 2026-10-18 open items), which win where the design doc differs:
- **Scale**: 100–300 CCU per database, never more; a seamless open world; hybrid combat (tab-target
  basics, aimed skill shots); no global cooldown (a cast queue, cooldowns pace it).
- **#1 Universe**: a new fantasy setting; Hollow Hill's animals are assets, not lore.
- **#2 Resource**: ~~one 100-point pool for every kit~~ REVERSED 2026-10-20: **mana on the Staff only**
  (a generic resource); melee is paced by its combo and the roll, the bow by its arrows.
- **#3 Mastery**: XP stored, rank from a content curve; v1 ranks 1–10 (production will go higher);
  abilities at 1/3/6/9; harder nodes need a gathering rank AND a tool tier.
- **#13 Accounts**: SpacetimeAuth, an account that several identities link to (Steam later).
- **#15 Tools**: no tool slot; the best matching tool in the bag is used (OSRS-style). Five
  equipment slots: weapon, head, chest, legs, trinket.
- **#17 Minigames**: immersive to their skill (revised the same day): woodcutting is branch dodge; the
  others (mining, herbalism, smelting, smithing) are designed to that bar with Luke.
- **`chunk`**: added to the template's existing positional tables in a **template 1.0** (a reshape:
  every game's database wiped once, older builds stop connecting), not a side table.
- **The skilling loop comes first** (gather, refine, smith, then fun combat): every skill is dual-mode, AFK
  or an immersive minigame worth 1.25x yield and 1.3x rares (hot rules); woodcutting is branch dodge;
  gear is modular (Tinkers'-style core + handle, gear XP, durability and repair). Design doc §7.4.
- Decided since: yield = AFK x 1.25 x score; tap E = AFK, hold E = minigame; tier bands (1-3, 4-5, 6)
  each get a harder minigame.
- **Combat** (2026-10-19): hybrid control (aimed light/heavy, a dodge roll, block, Q E R F skills);
  abilities come from the weapon type (its kit), unlocked at mastery 1/3/6/9; **#22 settled**: the
  smithed handle or hilt adds a trait. Tab picks a target (a ring) but attacks stay aimed. Swings are
  animation-locked with a one-press buffer; a roll cancels a wind-up; heavies flinch lights.
- **Loot, items, styles** (2026-10-20): `docs/regents_rule/LOOT_AND_STYLES.md`, whose AMENDMENTS win
  over its body (this settles **#7 loot**): quality 0-1000 shown as Common / Fine / Masterwork bands;
  Power from tier and quality, tier dominates; personal loot rolls on the ground; durability and repair
  an option; **no global cooldown** (each ability its own; the cast queue is input buffering only);
  **melee never rolls to hit**, ranged (bow, Staff) rolls; controls: Ctrl roll, Q E R F, LMB tap the
  combo / hold the heavy, RMB block.
- **Traits** (2026-10-21): every trait trades and never touches Power; **a handle's trait always
  applies**, whatever the item's grade (grade sets how many a drop rolls); Brutal reads the TARGET's
  health; the handles are toned to the early game (oak Steady, yew Springy) until **a materials and
  Tinkers' deep-dive**, which Luke wants later. (The "always applies" part is REPLACED 2026-10-23, below.)
- **Materials and modular gear** (2026-10-23, `docs/regents_rule/MATERIALS.md`, which wins over §7.4 and
  `LOOT_AND_STYLES.md` where they differ): materials are a GENERATED table (`MaterialDef` x `PatternDef`,
  baked to real items, any cell overridable, today's ids pinned); a pattern lists open-ended part SLOTS
  (head, handle, binding usually; an oil or a 4th/5th part is more slots); the CORE's material sets the
  tier (metal for melee and tools, WOOD for bows and staves, metal then secondary); secondary parts carry
  traits; **a crafted item holds traits by grade, Common 1 / Fine 2 / Masterwork 3, and the player picks
  which** (the station shows the count and which are in use); trait RANKS I-III paid in bulk base
  material + a catalyst + **gear XP** (now: earned by use, it gates the rank upgrade, never Power);
  catalysts drop from about +3 / +6 ranks over a node, with NORMAL depletion; the slice's ladder is
  **copper, iron, steel** (iron + coal; the bronze starters renamed copper); durability stays parked.
- **Telemetry** (2026-10-21): live, for looking back, with full history: BOTH a chronicle on the host's
  disk (every change of every table, a place every 5 s; template #276) and the meta rolled up in the
  database (`meta_share`, the 45 % alarm); a local dashboard (`tools	elemetry.cmd`). Then a polish round
  before the materials deep-dive: health bar, work progress, roll cooldown, minimap (OSRS style, to
  iterate), hit flashes, Make 1 / X / all.
- **Tester tools** (2026-10-23, after his first look at the ladder: "an admin button to reset the stats or
  manually adjust them"): a **Tester (admin)** page in the Escape menu, the admin only, acting on **any
  player** in the world: set a skill's rank, reset all skills (with recipe records and orders), give any
  item (a quality for one that does not stack), reset the bag to the starter kit.
- **The order of work** (2026-10-23): (1) Luke's playtest of steps 17-20, then fixes; (2) **the template 1.0
  with accounts** (TAKEN 2026-10-24; this game's half next: ring interest, its overrides, its cell tables) (chunks, streaming, interest management; SpacetimeAuth accounts and characters that outlive
  a machine), template work pulled here, one wipe; (3) **the combat deep-dive**, folding in equipment and
  armour (the five slots, stats), the server-side cast queue, crits and NPC tiers; (4) **the in-game lookup**
  (added 2026-10-24, below); (5) **herbalism and the
  economy** (marks, vendors). After those: writs, potions, death and shrines; party, duels, the lair and the
  Undercroft (M8, M25); the 300-bot load test. Movement feel from the template and Fishing that Regent's
  lost (the camera orbiting a still character without turning it; diagonal strafing that blends well) is
  noted for when it suits, likely with combat.
- **The in-game lookup** (2026-10-24, scheduled before herbalism and the economy, "to look into" with Luke
  first): WAILA/Jade-style help that is player friendly without being hand-holdy or cluttered. Wanted early:
  a **glance** line for the current target (name, needs: rank and tool tier, green/red for you), a **detail**
  card on a key (a node's drops, a foe's loot, a station's recipes; drops shown as `???` until you have
  found them, with their chances), and OSRS-style **skill guides** (what each rank opens) in the skills
  window. **No full in-game handbook for now**: the wiki (`UMF ALL\Regents Wiki`) is to be shared later.
  Known before the look: the client already has every number; a per-player "found" record is the one new
  server table (add-only); Q is taken (station recipe pick, kit skill 1), so the key is to choose. Open,
  Luke's: exact chances or words ("rare"); what `???` hides (the item, or its chance too); the key.
- **Answers** (2026-10-23): **hosting** on Luke's machine for now, then a VPS, before any Maincloud
  measurement; **the bow's damage scales with the draw** (built: a quick release 30 %, a full draw 100 %,
  `regents.draw_min_power_pct`); herbalism's and the higher bands' minigames when they are made; **the minimap
  gets a choice: locked north-up, or turning with the facing** (how it grows: open). Materials §11: see
  `MATERIALS.md` §11.
- **The step 2-3 defaults, confirmed** (2026-10-23): steel Power 140 and tools at 75 %; coal needs an iron
  pick and mining rank 3, a steel bar 2 iron ore + 2 coal at smelting rank 3; swapping a part re-ticks every
  trait the new parts offer; a lower-grade batch keeps the FIRST traits in the order wanted.
- **After his playtest of the crafting rework** (2026-10-23): the traits header says the grade without the
  quality number; **the head (any core) is picked BY GRADE** in a list ("Masterwork iron axe head (1)"), a
  grade not in the bag greyed, and a run uses only that grade; **metal rivets now** (not after herbalism):
  rivets are a pattern (copper, iron, steel), the binding slot takes any; **every part offers a tool trait and
  a weapon trait** (only one that fits the item counts: an axe takes the tool's): oak Steady / Heavy, yew
  Springy / Balanced, copper rivets Gentle / Thirsting, iron Lucky / Brutal, steel Prospector's / none until
  Keen (crits, the combat deep-dive); stacking allowed; **parts can be swapped after an item is made**, at
  the workbench: the new part used up, the old lost, plus bars of the head's metal (hot rule, start 2), the
  head and quality never change, gear XP kept, traits re-picked; tooltips on materials and parts say what
  they lead to. **Trait ranks: both paths** (a better-made part starts higher; upgrades through use) are
  liked but NOT decided: the minigames must be harder first so Masterwork is not routine, and AFK crafting
  must still pay (an AFK part is Common): to think through before `MATERIALS.md` step 5.
- **Crafting signed off** (2026-10-23, after step 21): "pretty good as it stands". Later: revisit the refining
  and other minigames so Common, Fine and Masterwork take real skill (also what trait ranks wait on).
- Still open: #12 day/night; how the minimap grows; the ore nuggets' placement (Luke's, by hand).

## Current state (2026-10-19, with steps 9-16 since: see `PROGRESS.md`): the skilling chain in the frontier glade
A fork of the template at 0.51.2 with the `regents` genre. **Press Play**: the frontier glade (level 20):
trees (Tree, Oak, Yew), copper, iron and coal rocks, and a camp with a furnace, an anvil, a workbench and an order board.
Gather (woodcutting, mining), smelt, smith and craft your way from a log to an **Iron axe**, then an iron
pickaxe for coal and **steel** (the ladder: copper, iron, steel; `MATERIALS.md`, the material table): at a node or a
station **tap E** to work AFK, **hold E** to play its minigame (branch dodge, crack the rock, bellows then
pour, shape to the outline), **Q** at a station picks the recipe (and the handle: plain, oak or yew). The
camp's **order board** wants rotating batches for bonus XP; crafting pays for the work in its inputs, a
first make pays extra, and a recipe repeated too long wears stale. Tune a recipe on the **recipe bench**.
**Combat, the first slice**: wield a weapon from the bag (I), Tab onto one of camp's training dummies (a
ring under it), LMB for the light combo, hold LMB for a heavy, hold RMB to block, Ctrl to roll, Q for the
kit's first skill; the world's referee judges every swing (an editor run starts it). The server replays every round from its
inputs; mastery ranks 1-10 per skill gate the better nodes. How to play it, what makes it, how it is
tested and what is left: **`docs/regents_rule/PROGRESS.md`**. Every minigame alone:
`game/regents/skilling/skilling_lab.tscn` (F6).

```bash
GODOT=<path> ./game/regents/tests/skilling_playtest.sh   # the whole chain by a real client at 150 ms
```
