@AGENTS.md

# CLAUDE.md — Regent's Rule (game 4; this repo's own, kept on a template pull)

A fantasy MMO-lite for 100-300 players in one database, a fork of the UMF template. Genre
`regents`: client `game/regents/`, server `server/src/game/regents.rs` + `server/src/genre/regents/`,
content id base 40000. Database `regents-rule`; suites use `regents-rule-test`, never the play one.

## Session protocol
`.claude/rules/umf-session.md` (loaded every session): on start read `docs/HANDOFF.md`, `GAME.md`,
the current step of the progress file and `tail -n 20 docs/DECISIONS.md`; on finish update progress,
record decisions, rewrite `docs/HANDOFF.md`. This game's decisions never go in `docs/DECISIONS.md`
(the template's): Luke's in `GAME.md`, the rest in `PROGRESS.md`'s step.

## The files
| File | What it is | When |
|---|---|---|
| `docs/HANDOFF.md` | where the last session stopped; overwritten every session | first, every session |
| `GAME.md` | what the game is, Luke's decisions (they win over the design doc), how to play it now | every session |
| `docs/regents_rule/PROGRESS.md` | THE PROGRESS FILE: each step built, how to play it, how it was tested, what was left | every session: the current step |
| `docs/regents_rule/RULE_DESIGN.md` | THE DESIGN: combat, world and chunks, NPC tiers, nodes and minigames, items, accounts, scale; build plan §12, open items §13 | before a new system |
| `docs/regents_rule/LOOT_AND_STYLES.md` | loot, grades, traits, spells; its §10 is the order of work | loot and items work |
| `docs/regents_rule/COMBAT_OVERHAUL.md` | the combat overhaul (2026-10-30): pace and foe tokens, one combo whose last hit is the heavy, RMB defense (parry, riposte, blocks), roles by the handle's shape, mastery picks; its §9 is the order of work, §8 what is Luke's | combat work (with `COMBAT_CURRENT.md`, as built) |
| `docs/regents_rule/ROLES_PREP.md` | before roles (2026-10-31): the road to roles, Luke's open role decisions (D1-D7), the last hit's name, the combat tutorial (T1-T5) | before roles work: his answers go to `GAME.md` |
| `docs/regents_rule/ARMOR_PREP.md` | before armor (2026-11-03): the road to armor, Luke's open armor decisions (A1-A10: Defense, weight and its cost, metal first, parts and traits, the look, wearing, numbers) | PARKED 2026-11-04 until herbalism and hunting: its §0 says what is settled (in `GAME.md`) and where to restart |
| `docs/regents_rule/MINIGAMES_PREP.md` | before the minigame overhaul (2026-11-04): the four built, what each score pays, the tier ladder today, the skills to come and their families, tiers "harder but similar", the look (2D, in the world, a 3D stage), the difficulty readout; Luke's open decisions M1-M12 (revision 2, 2026-11-05) | minigame work: his answers go to `GAME.md` |
| `docs/regents_rule/ANIMATIONS.md` | the animation checklist for the overhaul: every clip needed, the best Quaternius / Mixamo / other candidates, ticked as they go in | before adding a clip |
| `docs/regents_rule/MATERIALS.md` | materials and modular gear (2026-10-23): the generated table, slots, trait picks and ranks, gear XP, catalysts; its §10 is the order of work | materials, parts, crafting work |
| `docs/DECISIONS.md` | the FOUNDATION's decision log (arrives with pulls) | the last ~20, plus your system's rows |
| `docs/FOUNDATION_SYSTEMS.md` | the foundation milestones; this game asks for M8, M16, M18-M26, the template 1.0 | when a step needs the foundation |
| `docs/HANDBOOK.md` | the human guide | when a change alters how something works |
| `.claude/rules/regents-genre.md` | this game's standing rules; loads with the genre's files | automatic |

## Working here
- Foundation work (any `foundation/`, `server/src/module/`, `sidecar/` outside `npc/brains/regents/`)
  goes in `../UMF Template`, then this game pulls it (`.claude/rules/umf-session.md`, Across repos).
- Every game decision goes to Luke first; the open items in `GAME.md` are his.
- While iterating on feel (combat, minigames): the unit suite plus the one playtest or shot that shows
  the change, publish the play database, hand over for Luke's playtest; integration once it feels right.
```bash
GODOT=<path> ./tests/run_tests.sh -- --only=regents         # the genre's unit suite
GODOT=<path> ./game/regents/tests/skilling_playtest.sh       # the whole chain by a real client at 150 ms
GODOT=<path> ./game/regents/tests/walls_playtest.sh         # a real referee: a bot goes round a rock, through it once worked out
GODOT=<path> ./game/regents/tests/minigame_readout.sh         # every minigame round by four simulated players (~15 s, no server)
GODOT=<path> ./game/regents/tests/load_300.sh                # 50-300 bots on the continent (~25 min): docs/regents_rule/REFEREE_SCALING.md
```
