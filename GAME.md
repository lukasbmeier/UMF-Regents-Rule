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
| Main scene | `res://game/greybox_game.tscn` (the template's, until step 1) |
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
- **#2 Resource**: one 100-point pool, the same rules for every kit, named by the kit.
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
- Still open: #7 loot, #10 hosting (after measuring Maincloud round trips), #12 day/night, #22 handles
  and kits, #23 how a score maps to yield; the other skills' minigames.

## Current state (2026-10-18): the genre, and woodcutting's minigame to play
A fork of the template at 0.51.2. The `regents` genre (no tables yet) and **woodcutting's branch dodge**,
played on its own with no server: open `game/regents/skilling/woodcutting/chop_lab.tscn` and press F6.
Space starts a round, A/D or the arrows or a click on either side chops, 1-3 pick the tree (Tree, Oak,
Yew: `trees/*.tres`, edit them in the Inspector). `ChopModel` is the pure model (seed + inputs -> score,
integers only) that the server will replay; its Rust twin and the server's half (a challenge kind of
this genre's, a node you press E on, AFK and active yield) come once the feel is right. Next: Luke's
playtest of the chop, then mining, smelting and smithing to the same pattern.
