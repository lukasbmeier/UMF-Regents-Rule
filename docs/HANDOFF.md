# Handoff — Regent's Rule, 2026-10-30 (a Skyrim-size world, 300 bots, how many referees: step 25)

## Where it stands
- Template **1.5.5** merged (1.5.0-1.5.5, DECISIONS #290-#294). Everything committed and pushed (step 24's work
  and step 25's). Play database `regents-rule` republished (code only, data kept): restart the game.
- Suites green: genre unit 2735/0, native 127/0, integration 1100/0, combat playtest 51/0; the expanse load
  test at 300 holds every limit but referee net stalls (below).

## This session
- **The expanse** (level 22, a TEST world, PROGRESS step 25): the continent's map at 3.7x, 36.9 km2 of land
  (Skyrim ~37), 10,245 nodes, 660 skeletons. `build_expanse.tscn` (the continent's generator, `world` setting).
- **Watch and join**: `tools\run.cmd game\regents\tests\expanse_watch.sh` (300 bots, then a game window on the
  test database). **How many referees**: `tools\run.cmd game\regents\tests\expanse_referees.sh`.
- Found by it and fixed: `populate` compared every node with every node on each connect (hash sets, here);
  in the template the ring's unnarrowable queries, the tick's still rows, walk maps all at once, idle foes
  stepped every tick, and the big one, the brains' view searching every node per think
  (`REFEREE_SCALING.md`, "A Skyrim-size world"). Four referees at 300: frames 147 → 26-30 ms, ~1 GB each, flat.
- The bot hook's gatherers: wait for the server before E, walk on with no node near, never across a bay, and
  no longer stay paused after a correction. A timing race in the integration hook's burn check fixed.

## Next, in order
1. Two of four expanse referees (regions 1 and 2) stall ~30 s just after their skeletons bind; the server drops
   them for idle timeout and they reconnect (the run's only broken limit: net stalls). Find what blocks.
2. Then run `expanse_referees.sh` to the end for the table (each cut breaks on that stall until then). ONE
   referee for the whole expanse drops out; four run it at ~30 ms.
3. The combat overhaul (Luke, `COMBAT_CURRENT.md`): how often an idle skeleton thinks is its call.

## Waiting on Luke
- His playtest: `expanse_watch.sh` (walk among 300 bots), and the 10-29 changes on the continent.
- The server's levers at 300 (density, cell size, write rate, input batch); the per-player bandwidth budget.
- Where 300 is hosted; the recorder in an MMO; `FoeDef.lose_sight_ms`; SpacetimeAuth client id; trait ranks; #12.

## Watch out
- Never kill all Godot/Python processes (Luke's editor): stop a stuck run by its PID.
- This PC has ~9 GB free with Luke's apps open: four expanse referees take ~4 GB; nine would not fit.
- The expanse is generated: never hand-edit `levels/expanse/`; re-run `build_expanse.tscn` (~75 s, bakes too).
- Heredocs through the Bash tool mangle `\r`/`\t` in text (paths): write patch scripts with the file tool.
