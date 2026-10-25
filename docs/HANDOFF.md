# Handoff — Regent's Rule, 2026-10-24 (the continent built; NEXT SESSION: Luke's playtest fixes, then the load test)

## Where it stands
- **PROGRESS step 23, the continent: built, green, committed and pushed** (`36e5861`).
  A generated greybox of Luke's map's main continent (2.25 x 3 km, level 21, streamed in 484 cells) with the
  glade's camp copied in at its origin and a test placement (516 nodes, 16 skeleton camps).
- **The play database `regents-rule` runs the continent**: published (data kept), then
  `spacetime call regents-rule set_world_level 0 21` (back to the glade: `... 0 20`). A fresh database, and
  so every suite, still starts in the glade (level 20).
- Step 22 (ring interest, overrides, cell tables; compat 3) and template 1.1.0 are committed and pushed.
- **Suites, step 23**: unit 2643/0, `cargo test` green (the continent's 82 parity probes on both sides),
  the new continent playtest 17/0, skilling 62+7, combat 50. Not rerun: integration and accounts (no server
  or schema code changed; the level is data).

## This session
- Step 22: this game's half of the 1.0 (see PROGRESS); template 1.1.0 shipped to all four games, with the
  accounts suite's pinned defaults (`511eee3`).
- `game/regents/levels/continent/`: `continent_map.webp` (Luke's map), `continent_shape.gd` (land, ridge,
  heights read off it), `build_continent.tscn/.gd` (the generator: terrain, sea, wading wall, camp, test
  placement, then the bake and the cell cut). Outputs: `continent.tscn`, `continent_cells/`, `terrain/`,
  `shared/world/continent.json` + `_depth.bin`, `shared/golden/level/continent_probes.json`.
- `game/regents/levels/solid_props.gd`: a streamed cell's rocks and bushes are wrapped as it arrives.
- `game/regents/tests/continent_playtest.sh` (+ `playtest/continent_playtest.*`): a real client on the ring.
- `GAME.md`: Luke's calls (load test first, on the continent, 3 km, camp centre-west). Genre rules: the
  continent is generated, never hand-edited.

## Next, in order
1. **FIRST, THE NEXT SESSION (Sunday, before Tuesday 5 pm): fix Luke's playtest notes** (PROGRESS step 23,
   "Luke's solo playtest": 9 notes, sorted, none fixed) with the usage left before his reset. Luke's
   words: "fix what we can". Usage is short: one note at a time, its suite and its negative, COMMIT AND
   PUSH after each, so stopping anywhere loses nothing. Suggested order (real bugs first):
   a. #2/#3 skeletons stop doing damage, and hit each other (the referee's sweep, likely the first body);
   b. #9 the skeleton T-posing near the origin as it spawns;
   c. #7 the nameless "Player 39" (the CLI's player, drawn);
   d. #4 bushes not solid: ASK Luke first (all bushes? rocks stay solid); then the shadows near them;
   e. #5 the minimap out on the continent (M for a world map: ask, it is an idea);
   f. #6 no roll in the air, #8 the sword's cut-off swings: only if small, else to the deep-dive.
   Leave the referee's stalls (#1, 3-4.5 s) for the load test.
2. **THE LOAD TEST HARNESS** (Luke: Tuesday, after 5 pm, when his usage resets), in the TEMPLATE (a milestone of its own): a light bot client (likely Rust on the
   SpacetimeDB client SDK, many connections in one process; check the SDK first), each bot asking the
   ring's queries and sending real inputs (walk, gather, swing at dummies); run from the M1 so it does not
   take the server's CPU; 50 -> 100 -> 300, measuring rows and bytes a second per client and in total (the
   upload), reducer p95, the referee's lag, cell swaps a minute, nine cell sets against one OR'd query.
3. The combat design talk alongside it (`GAME.md` order (3)), then the in-game lookup, herbalism, economy.

## Waiting on Luke
- His look at the continent: the mountains' height and steepness, the camp's spot, the test placement.
- Bushes not solid (his note #4): confirm it is all bushes, rocks staying solid; and whether M opens a world map.
- The SpacetimeAuth client id (`shared/game.json` `sign_in`); open: trait ranks, #12 day/night, the minimap.

## Watch out
- Terrain3D puts an import's corner on its region grid (512 m at 2 m spacing): `build_continent.gd` starts
  the terrain on one; a terrain that does not lands up to a region off its shape.
- Rebuilding the continent rewrites `terrain/`, `continent_cells/` and the bake: publish after, and expect a
  ~16 MB diff. Never hand-edit those files.
- After a teleport the new cells load on a thread (only the very first load is immediate): props appear a
  moment later; the ground is the terrain, always there.
- `TaskStop` on a background suite stops the shell, not its children (two suites then shared the database).
- The integration hook's CLI referee is online only 5 s after its claim: a long block needs a fresh one.
- Older traps: a digit after `_` in a reducer name; list hints are the element's type; the CLI runs array
  numbers together; Python reads Windows-1252 unless told UTF-8; `NodeDef`/`RuleOverride` are `@tool`.
