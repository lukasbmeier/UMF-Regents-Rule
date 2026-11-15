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
| `docs/regents_rule/HERBALISM_HUNTING_PREP.md` | before herbalism and hunting (2026-11-07): what is settled, what is built, herbalism's and hunting's proposed shape, the first creatures, what fiber and hide make; Luke's open decisions H1-H11 | herbalism, hunting, creatures, fiber and hide work: his answers go to `GAME.md` |
| `docs/regents_rule/FOES_PREP.md` | before new foes (2026-11-12): how a foe thinks today, LimboAI (unused here) and the trees proposed, the rules for smart but fun foes, the Bestiary models, a skeleton archer and an imp caster, what a ranged foe needs on the server; Luke's open decisions F1-F16; its §9 is the order of work | new foes, foe brains and trees: his answers go to `GAME.md` |
| `docs/regents_rule/ABILITIES_PREP.md` | the ability rework (2026-11-13): the bar, four slots (Q, E, R the weapon's, F the chest's), item levels with mastery catch-up, a 1-99 track (picks ~5 and ~12, the ult ~20), the chest's ability; Luke's decisions B1-B15, ALL ANSWERED (`GAME.md`); its §7 the order of work (step 1, the bar: PROGRESS 72) | ability work, before armor |
| `docs/regents_rule/SETTLEMENTS_PREP.md` | towns (2026-11-15): the Medieval Village and Fantasy Props kits, the town dye and `SettlementStyle`, castle and capital pieces, the routes to a castle; Luke's open decisions S1-S8; its §8 what is built (the town world, the town lab, `KitHouse`, `CastleWall`, `Settlement`) | villages, towns, castles, town shaders: his answers go to `GAME.md` |
| `docs/regents_rule/AI_ASSET_AUDIT.md` | the AI asset audit (2026-11-14): Steam's AI disclosure, what to replace (the continent map and its terrain), what is clean, the code-made gray area, how to make art without AI | before adding any asset (the rule: `GAME.md`, "No AI disclosure") |
| `docs/regents_rule/WARDROBE.md` | the wardrobe (2026-11-14, before armor): every outfit piece we have and what each is made of, the Knight (the plate armor), the dye (six slots, any color, the painting kept), one mesh for every metal tier (`MetalFinish`), the gaps, into the game; Luke's open W1-W8 | armor's look, clothes, colors, the character picker |
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
GODOT=<path> ./tests/run_tests.sh                           # every unit suite and the lints (it takes no arguments)
"$GODOT" --headless --path . res://tests/test_runner.tscn -- --only=regents,regents_bar   # the genre's unit suites alone
GODOT=<path> ./game/regents/tests/skilling_playtest.sh       # the whole chain by a real client at 150 ms
GODOT=<path> ./game/regents/tests/walls_playtest.sh         # a real referee: a bot goes round a rock, through it once worked out
GODOT=<path> ./game/regents/tests/deer_playtest.sh          # a real referee: the deer grazes, bolts from a player, calms and walks home
"$GODOT" --path . res://game/regents/tests/glade_shot.tscn -- <out dir>   # windowed, no server: the glade from six fixed cameras (a look change, before and after)
GODOT=<path> ./game/regents/tests/combat_playtest.sh          # a real client and a real referee at 150 ms (~12 min): the string, roll, guard, parry, the camp, roles, the bow; LATENCY=20 for how soon a hit shows
GODOT=<path> ./game/regents/tests/archer_playtest.sh          # a real client and referee (~3 min): the archer's arrow taken, blocked, rolled, knocked away; it steps back, shoves
GODOT=<path> ./game/regents/tests/caster_playtest.sh          # a real client and referee (~3 min): the imp's bolt taken and sidestepped, its ring stood in and left, its cast stopped
GODOT=<path> ./game/regents/tests/spells_seen_playtest.sh     # two real clients (~2 min, no referee): another player's Gale seen, a stale one and a refused one not
"$GODOT" --path . res://game/regents/tests/aim_shot.tscn -- <out dir>     # windowed, no server: the aim poses against the crosshair (measured), a foe's swing trail, the shots in flight
"$GODOT" --path . res://game/regents/ui/bar_lab.tscn -- <out dir>        # windowed, no server: the ability bar, round and square, per kit and state (F6 in the editor: the lab itself)
"$GODOT" --path . res://game/regents/town/town_world.tscn -- <out dir>   # windowed, no server: the 1 km town world (village, market town, castle) by day and night
"$GODOT" --path . res://game/regents/town/town_lab.tscn -- <out dir>     # windowed, no server: one street in every preset style, seeds, a style edited live
"$GODOT" --path . res://game/regents/vfx/vfx_lab.tscn -- <out dir> [name] # windowed, no server: a contact sheet of six moments of each effect showcase, day and night (F6: the lab; unit suite regents_vfx)
"$GODOT" --path . res://game/regents/vfx/vfx_lab.tscn -- cost             # windowed: what each showcase adds at its peak (draw calls, particles, GPU ms)
"$GODOT" --path . res://game/regents/wardrobe/wardrobe_lab.tscn -- <out dir>  # windowed, no server: every outfit, the metal tiers, the zones, the colorways painted beside dyed, and the piece inventory (F6: the lab; unit suite regents_wardrobe)
"$GODOT" --path . res://game/regents/showcase/vista_lab.tscn -- stills <out dir>   # windowed, no server: the showcase valley's shots in their moods (F6: the lab, M moods, F free camera; also battle_lab.tscn; unit suite regents_showcase)
GODOT=<path> ./game/regents/tests/showcase_render.sh [stills|films|all]  # windowed (~15 min): the login, the vista and the battle shots at 1080p, stills and .ogv films, into export/showcase/<date>/ (for the composers)
GODOT=<path> ./game/regents/tests/minigame_readout.sh         # every minigame round by four simulated players (~15 s, no server)
GODOT=<path> ./game/regents/tests/load_300.sh                # 50-300 bots on the continent (~25 min): docs/regents_rule/REFEREE_SCALING.md
```
