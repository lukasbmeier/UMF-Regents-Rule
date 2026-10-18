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
| Genres | none yet (`shared/game.json` `genres: []`); the genre is added with step 1 |
| Database | `regents-rule`; the suites use `regents-rule-test` |
| Main scene | `res://game/greybox_game.tscn` (the template's, until step 1) |
| Genre rules files | none yet |
| Genre manifest | none yet (`tools/template/genres/<genre>.paths` once the genre exists: AGENTS.md rule 16) |

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
- **#17 Minigames**: Rhythm (Woodcutting), Trace (Mining), Tension (Herbalism).
- **`chunk`**: added to the template's existing positional tables in a **template 1.0** (a reshape:
  every game's database wiped once, older builds stop connecting), not a side table.
- Still open: #7 loot, #10 hosting (after measuring Maincloud round trips), #12 day/night.

## Current state (2026-10-18): forked, nothing built
A fork of the template at 0.51.1 (title, database `regents-rule`, this file, the design in
`docs/regents_rule/`, bindings regenerated). No genre yet. Next: step 1 of the design's §12 (the
fight), which needs the template's ability/effect pipeline and cast queue (M20) and stats (M21); the
template 1.0 is planned before step 3.
