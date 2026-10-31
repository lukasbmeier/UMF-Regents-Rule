# Handoff — UMF Template, 2026-10-30 (Jolt in every game; a big world's referee stalls: 1.5.0-1.6.2)

## Where it stands
**1.6.2** (DECISIONS #290-#296): committed and pushed, merged into all four games and pushed there.
1.6.0 names **Jolt Physics** in `project.godot` (restart the editor in every game). Each game's levels were
re-baked on Jolt's rays where their bake checks asked (the example here, Fishing's meadow, Regent's continent
and expanse); Fishing's and Regent's play databases republished. Suites here on Jolt: unit 2274/0, integration
644/0, movement playtest 41/0 (0/100/200 ms), remote 30+7, e2e 47+11, sidecar 13/0, regions 25/0, press 6+7,
native 92/0. Games on Jolt: Fishing unit 3053, native 133; Fowl Play unit 2558, chase 28, nest 17, hunt 13,
launch 8 (its powers playtest fails 1 on either engine: its eagle is switched off by a hot rule, its HANDOFF);
DiscGolf unit 2348, throw 17, bots 15; Regent's unit 2736, native 127, combat 51, continent 22.

## This session (Regent's Rule's 300 bots on a Skyrim-size world, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- 1.5.0-1.5.5 (#290-#294): bots over a level, watch and join, per-referee cost, the sweep; ring queries by cell
  number; still rows passed; walk maps queued; the brains' view by kind; idle NPCs and poses cost nothing.
- 1.6.0 (#295): Jolt. The default engine's step froze region referees 15-65 s when ~170 NPCs first moved.
- 1.6.1: the level baker is a scene (`tools/world/bake_level.tscn`): as a bare `-s` script it had no autoloads
  and cut a streamed level's cells all into one (LevelInfo's Bake button ran it that way).
- 1.6.2 (#296): a referee's look for a changed project (0.4 s over 8,000 files every 10 s) on a worker thread.
- Result: 2 region referees hold 300 bots on the 37 km2 expanse; 4 and 6 overload the server (below).

## Next, in order
1. Region referees' queries the server can narrow: `region_query` is one `chunk >= a AND chunk <= b` a column
   (not narrowed, #291); a strip of whole columns can be one range (chunks are `x * 1024 + z`, and nothing exists
   outside the level). With four or six referees the module went 55 → 82-87 % busy from this.
2. One ~0.9 s stall in some region referees a minute (not walk maps: 140 ms reads).
3. A region referee loads the whole level (~375 MB on the expanse); the server at 300 spread (#289 levers).

## Waiting on Luke
- The per-player bandwidth budget; the server's levers at 300 (#289). Fowl Play: the eagle and its playtest.

## Watch out
- Never put a `.gd` copy inside a project (even `build/`): two of a class and every spawn fails.
- Bake through `tools/world/bake_level.tscn` (or the button), never `-s bake_level.gd`.
- Heredocs through the Bash tool mangle `\r`/`\t` in text: write patch scripts with the file tool.
- A ring hears another world's rows in its cells and drops them in `SpaceTimeSync`; `find_rows` still sees them.
