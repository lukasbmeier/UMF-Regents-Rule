# Handoff — Regent's Rule, 2026-10-26 (Luke's playtest notes fixed; NEXT: the load test, Tuesday after 5 pm)

## Where it stands
- **Luke's 9 playtest notes (PROGRESS step 23, "Luke's solo playtest") worked through, one commit each,
  all pushed** (last `f4a1a2d`). Template **1.1.1** pulled (four foundation fixes; NOT yet shipped to the
  other games: the template's HANDOFF).
- **The play database `regents-rule` is published** (data kept) and still runs the continent (level 21).
- Suites: unit 2657/0; combat playtest 51/0; continent playtest 20/0 in a window (`WINDOWED=1`), 19/0
  headless. Each fix's new check failed with the fix taken out. Not run: integration, accounts, skilling
  (no server code changed; the module was rebuilt by the publish).

## This session (details per note in PROGRESS step 23)
- #2/#3 skeletons hitting each other: template #283, hot rule `foundation.referee_two_sides`, ON here
  (`game/regents/content/rules/regents.tres`): a sweep passes through its user's own side.
- #9 T-pose on spawn: template, a character is posed the moment it is built.
- #7 "Player 39" (the CLI's own player): cause on Luke's night NOT proven. Found and fixed on the way: the
  ring held its old centre after a long jump back onto the spawn (it is ON a cell edge); a late admin row.
  `continent_playtest` now keeps the CLI coming back and checks it hidden, at the camp and after a trip.
- #5 minimap: a big level is pictured round the player and follows them (`game/regents/ui/minimap.gd`).
- #4 bushes: walked and seen through, rocks solid (`solid_props.gd`; one line of `continent.tscn`). Luke's
  call from his note, recorded in GAME.md, to confirm.
- #6 roll in the air: held and taken on landing (client only). #8: the Lunge plays whole (not seen in a
  game); the LMB-spam cut is combo design, for the deep-dive.

## Next, in order
1. **The load test harness** (Tuesday after 5 pm), in the TEMPLATE: as the previous HANDOFF had it (a light
   bot client, many connections in one process; 50 -> 100 -> 300; rows and bytes a second, reducer p95,
   the referee's lag, cell swaps). Note #1 (the referee's stalls) is for it.
2. Before or with it: ship template 1.1.1 to the other games (the template's HANDOFF).
3. The combat deep-dive: the LMB spam cut, foes pathing round obstacles (#4), a server refusal of a roll
   in the air, the cast queue.

## Waiting on Luke
- His look: the Lunge whole; bushes passable (and are the shadows near them still odd?); does "Player 39"
  still show (if so: where he walked from, and whether it was the body or only its name).
- M for a full world map (his idea, note #5): wanted now or later?
- Still open: the SpacetimeAuth client id (`shared/game.json` `sign_in`); trait ranks; #12 day/night.

## Watch out
- `continent_playtest.sh` polls the CLI every 3 s for the whole run (as the host's watcher does); set
  `WINDOWED=1` to also check the minimap (headless takes no pictures).
- `continent.tscn` is generated: its `solid_models` line was edited to what the generator now writes;
  a rebuild writes the same.
- A game's hot-rule override is the build default on every client and referee too, so tests that assume a
  foundation default must set the rule themselves.
- Older traps: Terrain3D's region grid; rebuilding the continent is a ~16 MB diff; `TaskStop` leaves a
  suite's children running; the CLI referee is online only 5 s after its claim.
