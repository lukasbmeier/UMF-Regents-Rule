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
  with accounts** (TAKEN 2026-10-24; this game's half DONE the same day, PROGRESS step 22: ring interest,
  3 characters an account, parked 30 s after leaving, `chunk` on Regent's own placed tables; Luke chose a
  second wipe for it, `compat` 3, since no compat-2 build had gone out) (chunks, streaming, interest management; SpacetimeAuth accounts and characters that outlive
  a machine), template work pulled here, one wipe; (2b, Luke 2026-10-24) **the load test** on the continent
  (PROGRESS step 23 the continent; the harness next, in the template), the combat talk alongside;
  (3) **the combat deep-dive**, folding in equipment and
  armor (the five slots, stats), the server-side cast queue, crits and NPC tiers; (4) **the in-game lookup**
  (added 2026-10-24, below); (5) **herbalism and the
  economy** (marks, vendors). After those: writs, potions, death and shrines; party, duels, the lair and the
  Undercroft (M8, M25); the 300-bot load test. Movement feel from the template and Fishing that Regent's
  lost (the camera orbiting a still character without turning it; diagonal strafing that blends well) is
  noted for when it suits, likely with combat.
- **The order of work from here** (Luke, 2026-11-03): after his melee spot check and its fixes, (1) **ARMOR** next:
  the equipment slots and their stats, planned first in a prep session (as `ROLES_PREP.md` was for roles; the prep
  doc is not written yet: the next session starts with it); (2) **the rest of the combat deep-dive** (overhaul steps
  5-7: mastery picks, threat and Support, content fill; the cast queue, crits, NPC tiers); (3) **a MINIGAME
  OVERHAUL**: the skilling minigames made fun and engaging, so the skill that earns Fine and Masterwork materials is
  real, with progression as a skill levels up; before the in-game lookup; (4) **the in-game lookup**; (5)
  **herbalism and the economy**; (6) writs, potions, death and shrines; (7) party, duels, the lair, the Undercroft.
  **REPLACED 2026-11-04**, below ("The order of work, armor parked").
- **The order of work, armor parked** (Luke, 2026-11-04: "it seems we may be too early for armor without more
  resources and content"): (1) **the American-spelling pass**; (2) **the MINIGAME OVERHAUL** (as above: Fine and
  Masterwork take real skill, progression as a skill levels up); (3) **herbalism and hunting**: fiber and hides, and
  the creatures hunted for them (foe design too: the place for foes that push, poison or slow); (4) **ARMOR**, back
  with cloth, leather and real threats (`ARMOR_PREP.md`, parked). Not yet placed by Luke, the agent's proposal: the
  rest of the combat deep-dive (overhaul steps 5-7: mastery picks, threat and Support, content fill; the cast queue,
  crits, NPC tiers) AFTER hunting, so its new creatures give them something to work against; the in-game lookup, the
  economy (marks, vendors), writs, potions, death and shrines, party, duels, the lair and the Undercroft after that.
- **Bushes are not solid** (Luke's playtest note, 2026-10-24; CONFIRMED 2026-10-26: "bushes should be passable
  like the other grass foliage"): of a level's props only ROCKS stop you and a foe's sight
  (`RegentsSolidProps.solid_models`); bushes, grass and flowers are walked and seen through. Narrows his
  2026-10-21 "every 3d object should have collisions".
- **The world map** (2026-10-26): **M opens a full world map** with hoverable icons. A node you have
  DISCOVERED says exactly what it is ("Coal ore"); one you have not says its skill and ??? ("Mining ???").
  **Discovered is per node, by being near it** (Luke chose "seen, per node" over "gathered once" and "seen
  per kind"). **Points of interest** are marked on it: the test zones, harvest zones, camps and so on.
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
  grade not in the bag grayed, and a run uses only that grade; **metal rivets now** (not after herbalism):
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
- **Load test before combat** (2026-10-24): the 300-bot load test moves ahead of the combat deep-dive, the
  combat design talk alongside it. It runs on **the continent** (PROGRESS step 23), Luke's map's main
  landmass (no islands; the name on the map, Aethel, not taken): **about 3 km across**, the camp in the
  **center-west lowlands**. A greybox for testing: its node and skeleton placement is a test one, and the
  world's regions, roads, towns, the lair and the Undercroft are Luke's to design later. A fresh database
  still starts in the glade (level 20); the continent is level 21 (`set_world_level 0 21`).
- **A Skyrim-size test world** (2026-10-30): "try it on a world close to the same size as skyrim with 300
  players to see ... how many refs I need ... with me playing a local user as well". The **expanse** (level 22,
  PROGRESS step 25) is that: the continent's map 3.7 times as wide, ~37 km2 of land, its test placement at the
  continent's density. A TEST world for the load test (the test database only); the continent stays the world.
- **The combat overhaul** (2026-10-30, `docs/regents_rule/COMBAT_OVERHAUL.md`, which wins over the 2026-10-19
  Combat line, the 2026-10-20 controls and `RULE_DESIGN.md` §4 where they differ). From the playtester's "too
  fast, at the same time, hard to read" and Luke's "generic":
  - **Pace: deliberate.** Foes get their own abilities (wind-ups ~550-850 ms), rest 1.5-2.5 s, and at most 1-2
    attack one player at once (attack tokens, a ~600 ms gap counted from each swing's landing, hit or not). A
    foe's aim tracks, then locks for the last ~300 ms. TTK about 12 s attacking only, 7-8 s played well; HP
    moves only if play says so; loot judged per minute. **Built 2026-10-31** (PROGRESS step 26) but loot per
    minute, waiting on the playtest.
  - **No Break/poise spine and no bar** (Luke: it would be min-maxed over damage and utility). Stagger is a
    payoff; systems stay varied but simple.
  - **One combo, no separate heavy**: LMB taps a string, each step a little heavier; **the last hit is the
    finisher and the heavy** (armor, flinches a light, staggers). No hold-LMB on melee. A swing at air still
    advances the combo. The window is a hot rule, 2000 ms; follow-through replaces `chain_ms` (fixes #8).
    The Heavy trait becomes a longer stagger on the finisher.
  - **RMB is only defense**: tap = parry for every kit and role (judged on the hit as you saw it; a missed
    parry locks parrying ~400 ms); hold = a front block, real for the Tank, **weak for Damage and Support**.
    **A parry pays stagger + a riposte** that counts as combo step 1; the bow's riposte makes the next draw
    fill twice as fast. Bow: RMB while drawing lets the draw go and parries.
  - **Built 2026-10-31** (PROGRESS step 27), the string and the guard, with Luke's three calls that day: **the
    riposte is the string's first step with bonus damage** (`regents.riposte_damage_pct`, no clip of its
    own); **the parry is front-only like the block** (one arc, `regents.guard_arc_deg`); **every player has
    the weak block until roles come** (step 4). The staff's riposte waits.
  - **Feel first, numbers after** (Luke, 2026-10-31, after playing steps 1-2: "we can adjust values after
    stagger has visual clarity and animations feel better"). His calls for the first feel pass: a HIT-STOP
    and a SPARK where the blow lands; no screen shake, no finisher shove, no sound yet; the foundation's part
    in the template, then pulled (1.6.7, #301). Built: PROGRESS step 28.
  - **Roles, settled before building them** (Luke, 2026-11-01, answering `docs/regents_rule/ROLES_PREP.md`):
    - **SHOW, DON'T NAME.** "Let's avoid naming conventions specifically, same with the tutorial: we can show
      the player without telling them behind the scenes or using explicit gamer titles." The roles (Damage,
      Tank, Support) and the "finisher" are words for code and docs only: the player sees a badge and what a
      handle DOES ("holds a full guard; foes come for you"), and the last hit of the string has no name on
      screen (each weapon's own last hit is named in its tooltip: "Piercing thrust").
    - **A handle pattern per role** (the sword: grip, crossguard hilt, banner hilt), each crossed with the woods,
      a real item; the **same cost and Crafting rank** as the plain handle; **one mesh** per weapon for now.
    - **Each role carries its block and threat only**; passives come later. **Healing draws no more threat
      than damage.** Whether the guard handle's extra threat applies to every foe or only bosses is to be TESTED:
      its multiplier and its scope are live rules.
    - **Support works solo**: its heals reach you; with players near, your own share goes down (the ratio after
      playing it solo and grouped: a live rule).
    - **The sword's three last hits to start**: Piercing thrust (26, reach 2.4 m, 380 ms), Pommel bash (14, a
      1.2 s stagger that holds the foe, 340 ms), Rallying cut (14, a wider arc, heals players near you, 400 ms).
    - **Drops** roll a handle shape: 50 % plain, 25 / 25 (a live rule). **Re-hilting** loses the old handle.
    - **The tutorial**: in the camp's yard, offered (a reminder after the first death), replayable; taught
      mostly by playing, with a few words and the first friendly NPC (a camp character); a closing ring as a
      parry aid in the yard only. **Roles first**, then the tutorial. (Mastery pick pools, D7, wait.)
    - **Built for the sword 2026-11-01** (PROGRESS step 30): the crossguard and banner hilts (each wood), the role
      map and its three last hits, the server choosing which fires (template 1.7.1), re-hilting, drops, badges
      and words. The starting values and choices that were not his (the live rules' first numbers, the rallying
      cut not healing off a dummy, the badges, the words) are listed in PROGRESS step 30 for his look.
  - **Roles by the handle's SHAPE** (Damage / Tank / Support; Option B, not an off-hand slot); its MATERIAL
    still sets the trait (#22 intact). **The role changes only the finisher.** Changing role = re-hilting at
    the workbench. The sword's three roles first.
  - **Mastery picks at 3/6/9** (tall or wide: the next active, an upgrade, or a passive), changeable out of
    combat.
  - **Telegraphs: the pose plus one red glint**, for unblockable attacks only. **Ranged keeps its hit roll.**
  - Still his: the 12 role finishers and the pick pools, the bow's Q, a respec's cost, the combat triangle as
    foe design.
- **Luke's first look at roles** (2026-11-01, built: PROGRESS 31): the sparks and glint were untextured squares; the
  swing snapped back to idle; a status bar under the target's health; a stagger that roots and dazes ("we can
  experiment with both": the Staggered status's `speed`, 0 now, 0.4 before); the workbench's doubled Handles heading.
  Then: the tutorial, "a walk through with crafting + combat to teach the basics".
  And (2026-11-02): no "Staggered" word floating over the body: the status bar under its health says it, and how long.
  **Stagger by POISE** (Luke, 2026-11-02, choosing option A with a short B, after "the guard grip plus Heavy staggers
  almost forever"): every melee hit wears a foe's poise, only the last hit breaks it, then a stagger and a short
  Steadied; Heavy breaks it sooner instead of staggering longer. **Shown on the target marker**, not a bar under the
  health ("the top status is getting clutter"): an arc round the ring under your target. Players keep the old rule
  (a foe's last hit staggers you). The banner cut's clip changed (it looked jumpy).
- **Handles: one family of three SHAPES for every tool and weapon** (Luke, 2026-11-01, option (b) of three; built,
  PROGRESS 32): the grip (the plain handle, renamed), the crossguard grip and the banner grip, each in every wood; any
  tool or weapon takes any shape; a shape matters only when swung, and only on a weapon whose kit has roles (the
  sword so far). Tools as weak weapons with kits of their own (option (c)) are later.
- **The tutorial** (Luke, 2026-11-01, answering two questions): it walks a new player through MAKING THEIR OWN SWORD
  first (chop a tree and carve a grip; mine copper, smelt a bar, smith a blade; assemble a copper sword at the
  workbench, picking its grip's shape), then the fighting lessons with that sword, ending on what its grip's shape
  does. PROGRESS IS ON THE SERVER, per character, each lesson ticked by the server seeing it done. With T1-T5 (the
  camp's yard, offered, mostly play, a few words, a friendly camp character, the parry ring in the yard only).
  First pass built (PROGRESS 33): the Drillmaster by the yard, fifteen lessons, a sparring skeleton, the ring.
- **Leaving a round** (Luke's play, 2026-11-03, feedback #8193: "need to be able to cancel out of anvil minigame if you
  accidentally started one, maybe for all games, for harvesting can reward what we get, for refining/crafting can just
  cancel and not use resources"): built (PROGRESS 35): **Escape** ends a gathering round at once and pays what was
  played; a refining or crafting round is dropped, nothing used, nothing made.
- **Armor prep** (2026-11-03): `docs/regents_rule/ARMOR_PREP.md`, decisions A1-A10, waiting on his answers.
  His first pass (2026-11-04, an outside review of the sheet): AGAINST player poise (hard to track, feels bad when it
  breaks: poise stays a foe mechanic) and AGAINST weight slowing movement (good players avoid damage and go light).
  The sheet is revised with both (revision 2, every decision with a proposed answer); a second outside review found
  the metal-only traits dead and too few parts for the grades.
- **ARMOR PARKED** (Luke, 2026-11-04) until cloth, hides and new foes exist (the order of work above). **Settled now**,
  because no new content changes them (`ARMOR_PREP.md` §0):
  - **Defense**: each piece a Defense, worn pieces add up, a hit becomes `damage x K / (K + Defense)`, K the hot rule
    `regents.defense_k` (67 to start); never a flat cut. The guard first, then armor, then traits, MULTIPLIED, never
    added. `FoeDef.defense` (0 on today's skeletons). Quality raises Defense as it raises damage (+20 % at 1000).
  - **No armor weight and no player poise**: armor never costs the roll or sprint; POISE IS A FOE MECHANIC ONLY; a
    foe's last hit that lands unblocked always staggers a player. (A short Steadied after a player's stagger is an
    idea for duels, not decided.)
  - **Wearing**: from the bag (I), a paper doll of head, chest, legs and trinket; out of combat only
    (`regen_delay_s`); others see it (a public row, by the ring).
  - **The look**: the Quaternius Modular Fantasy outfits, recolored by material; helms always shown (a toggle later);
    the chestpiece draws the arms, the leggings the feet; the five slots stay.
  - **Words**: a piece shows its Defense as a number (as Power is) and what wearing it does to you ("you'd take 19 %
    less, now 13 %"); the doll shows the total; never Light / Medium / Heavy.
  - Later, as recommended: the trinket empty until herbalism; armor crafted first, on drops with the loot-table pass;
    gear XP by being hit when ranks are built.
  - **Open, for when armor comes back**: the parts and traits (plates + what secondary parts; each piece needs enough
    trait-bearing parts for Fine and Masterwork), which traits (Padded and Warded likely move to the lining), what
    makes lighter armor worth wearing (the combat triangle), the materials' tiers and the numbers.
- **Minigame prep** (2026-11-04; revision 2 2026-11-05 after an outside review): `docs/regents_rule/MINIGAMES_PREP.md`,
  decisions M1-M12 (the ladder's shape, the bands, rank easing a round, what a score is worth, woodworking's minigame,
  smelting's reward and bellows, the look, art sources, each band's new thing, the new skills' minigames, what active
  gathering pays and how often its panel opens, an assembled item's quality).
- **The minigame overhaul, ANSWERED** (Luke, 2026-11-05: "all as proposed except for below"; the sheet's §7 says each
  in full, §8 is the order of work):
  - **One game per skill for life** (M1): numbers tighten within a band; each new band adds ONE new thing on top.
  - **Bands** (M2): band 1 = tiers 1-2 (copper, iron; tree, oak), band 2 = tier 3 and up (steel, coal, yew). Where
    band 2 ends and band 3 starts **waits on which metals come after steel** (Luke's, with the next metals).
  - **Rank eases the round** (M3): a few percent wider windows a rank above the requirement, capped at three (hot rules).
  - **Quality = the score** (M4), the difficulty tuned to target shares: a fresh band Fine ~50 %, Masterwork ~10 %;
    three ranks on, Masterwork ~33 %. Measured by simulated players (the readout), AFK always Common.
  - **Woodworking gets carve to the line** (M5): grips, hilts, bows and staves get a quality. Assembly stays a choice
    screen.
  - **Smelting** (M6): bars stay without quality; the score pays in bars and catalysts; the bellows pump in RHYTHM,
    never mashing.
  - **The look** (M7): a 3D stage in the panel (`SubViewport`, the game's own Quaternius models, lit like the world),
    sound from the start; smithing first. **Gathering ALSO as a 3D stage, in the smaller side panel, as a TEST**
    (Luke: "lets do gathering as 3d too with smaller side panel as a test"). **After the test (2026-11-06): every
    round in the MIDDLE panel** (the side panel sat over the minimap), and **NO CHARACTER ON A STAGE: the tool floats
    and swings on its own**, as the anvil's hammer (Luke: "does it feel weird to have a character on a small panel
    while you see your main character ... consistent with hammer floating, pick floating, axe floating, etc since we
    know we as the character as doing the action").
  - **THE WORK SPOT** (Luke, 2026-11-06, PROGRESS 44): the world's pick and axe went into big rocks and trees; of a
    picture-only stand-off and moving the player, Luke chose **"Move the player"**: pressing E at a node first walks
    the player back (or in) to where the swing meets the rock or the bark, facing it, then the work starts there.
    "Visuals and server body should match in case they get attacked or shot at while harvesting ... smooth and not
    jarring ... facing them": an eased turn to the node, then a walk (not a run). Then (same day): "have the model
    face them but allow the camera to rotate as it is since we are standing still": the BODY turns, the camera stays
    the player's (the template's `hold_body_yaw`, 1.7.4, DECISIONS #305). And "dont want to wait more than a few
    moments (.5 maybe less?)": the step goes at the plain gait (a run), about half a second.
  - **THE WORK REACH IS FROM A NODE'S EDGE** (Luke, 2026-11-06: "Measure from its edge"): `regents.work_reach_m` (3 m)
    is counted from where a body walking up is stopped, not from the node's middle: a rock's drawn footprint, a tree's
    trunk (`NodeDef.radii_cm`, baked from the models). The big iron rock (2.57 m) fits its work spot now.
  - **Art** (M8): the game's own models plus CC0 (Kenney, freesound); Gemini for mockups only. (Paid packs and AI art
    not chosen.)
  - **Each band's new thing** (M9): smithing first: two strikes in band 1 (the buttons a UI setting, tried both ways),
    heat colors with hard and soft spots in band 2, a quench in band 3 that lifts or lowers but never destroys a part;
    the others' band things are prototyped and played before deciding.
  - **New skills** (M10): pull the root (herbalism), the cut line (skinning) and the rest as the sheet's §2 table,
    each confirmed with its step.
  - **Active pay** (M11, revisiting 2026-10-18's 1.25x): a good round beats AFK and a poor one still falls short
    (break-even near half a score, not 80 %: a floor); the catalysts lean hard to active play; gathering and smelting
    rounds run back to back hands free once started (E or Escape ends a run, as does a round with no input), each
    round paid as it ends. The numbers come from the readout and his play.
  - **An assembled item's quality** (M12): the CORE part alone sets it; a secondary part's grade starts its trait a
    rank higher (this settles the "a better-made part starts higher" half of trait ranks, `MATERIALS.md` §5).
  - **The anvil, after playing step 2** (Luke, 2026-11-05: "the time between hitting reheat and then being able to use
    the hammer again was too long, could only ever get two reheats"): **a set number of heats instead of a clock**,
    and **each reheat lowers the part's quality ceiling**; the outline **varies every round** (still the part's
    shape, different each time, so no one memorizes the hits); the outline can be **re-laid on the bar as a template,
    but no strikes while it is up**.
  - **The anvil's bands, A TEST** (Luke, 2026-11-05: "so I can test both, lets make copper band 1, iron band 2, steel
    band 3 and we can redistribute the bands per metal as we introduce more"): **band 1 (copper)** the outline shows
    only when laid on (a key or a button), no strikes while it is up, each reheat lowers the quality ceiling; **band 2
    (iron)** the metal is harder (more hits), and each lay of the template AND each reheat lowers the ceiling; **band
    3 (steel)** as band 2, plus heat colors and the quench. Revisit once played.
  - **For every skill** (Luke, 2026-11-05, "yes"): **rank eases the numbers; a band adds one rule.** A band's rule
    belongs to that band's items, never to the player's rank: an outranked tier never gains rules.
  - **Outranked XP** (Luke, 2026-11-05, a direction, not settled): rather than XP falling off, shape the rank curve
    so a lower tier is never worth doing for XP (as OSRS's: its XP per level grows so steeply that level 92 is half of
    99). Today's smithing curve (60 ... 2400 over 10 ranks) grows gently; to retune with the ladder.
- **American spelling** (Luke, 2026-11-04): "all spelling in the game is not English version, but American": armor,
  defense, color, gray, center, meter, canceled. Everything a player reads, and every new name, rule and doc from now
  on (`regents.defense_k`). The first sweep was done 2026-11-04 (PROGRESS step 38).
- Still open: #12 day/night; how the minimap grows; the ore nuggets' placement (Luke's, by hand).

## Current state (2026-10-19, with steps 9-16 since: see `PROGRESS.md`): the skilling chain in the frontier glade
A fork of the template at 0.51.2 with the `regents` genre. **Press Play**: the frontier glade (level 20):
trees (Tree, Oak, Yew), copper, iron and coal rocks, and a camp with a furnace, an anvil, a workbench and an order board.
Gather (woodcutting, mining), smelt, smith and craft your way from a log to an **Iron axe**, then an iron
pickaxe for coal and **steel** (the ladder: copper, iron, steel; `MATERIALS.md`, the material table): at a node or a
station **tap E** to work AFK, **hold E** to play its minigame (branch dodge, crack the rock, bellows then
pour, shape to the outline), **Q** at a station picks the recipe (and the handle: plain, oak or yew). **Escape** during a minigame leaves it (gathering keeps what you got; making uses nothing). The
camp's **order board** wants rotating batches for bonus XP; crafting pays for the work in its inputs, a
first make pays extra, and a recipe repeated too long wears stale. Tune a recipe on the **recipe bench**.
**Combat, the first slice**: wield a weapon from the bag (I), Tab onto one of camp's training dummies (a
ring under it), tap LMB for the string (its last hit the finisher, which staggers), tap RMB to parry a hit
as it lands (then tap LMB at once: the riposte), hold RMB to block what is in front, Ctrl to roll, Q for the
kit's first skill; the world's referee judges every swing (an editor run starts it). A sword's HANDLE picks its
last hit (a plain grip a piercing thrust, a crossguard hilt a pommel bash and a full guard, a banner hilt a
rallying cut that mends those near you): make or re-hilt one at the workbench. **The tutorial**: the Drillmaster by the training yard
(walk up, E, E again) walks you through making your own copper sword, then fighting with it against a slow sparring
skeleton (a ring closes on each of its blows); N sets it aside. Each lesson ticks when the server sees it done. The server replays every round from its
inputs; mastery ranks 1-10 per skill gate the better nodes. How to play it, what makes it, how it is
tested and what is left: **`docs/regents_rule/PROGRESS.md`**. Every minigame alone:
`game/regents/skilling/skilling_lab.tscn` (F6); **T** there shows the round's **difficulty readout** (four simulated
players of set skill on many seeds: their mean, Fine and Masterwork shares, how often they beat AFK), and
`tools\run.cmd game\regents\tests\minigame_readout.sh` prints it for every round (`MINIGAMES_PREP.md` §6).
**The anvil** (PROGRESS 41-42) is a 3D stage of the game's own anvil and hammer: left click a column for a heavy
strike (it spreads into its neighbors), right click for a light tap (finishing the line), R to put the bar back in the
fire; or Shift + click taps and right click reheats (Controls, "Smithing: the light tap"; **B** in the lab switches
it). No clock: **5 heats**, each costing the best the part can be; **the pattern** (the outline) is on the bar at the
start and when laid on with **Space** (no strikes while it is on); the outline varies every round; **Enter** sets the
part down. Iron charges for each look; steel goes **red** (a strike cracks it) and ends in a **quench** (Enter while
the heat bar is in the gold mark). **Every minigame is a 3D stage** (PROGRESS 43), in the panel in the middle, with no
character: the axe chops into the trunk's side, the pick hovers by the mouse and comes down on the seam, the bellows
pump on their own.

```bash
GODOT=<path> ./game/regents/tests/skilling_playtest.sh   # the whole chain by a real client at 150 ms
```

**300 bots on a Skyrim-size world, and you among them** (PROGRESS step 25, the test database only):
`tools\run.cmd game\regents\tests\expanse_watch.sh` (a game window opens: press Play as a guest at the camp;
Ctrl+C in the terminal ends it); how many referees it needs: `tools\run.cmd game\regents\tests\expanse_referees.sh`.
