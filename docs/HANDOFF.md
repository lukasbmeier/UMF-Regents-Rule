# Handoff — Regent's Rule, 2026-10-24 (the continent built; next, the load test harness)

## Where it stands
- **PROGRESS step 23, the continent: built and green, NOT committed** (last commit `531ac53`, pushed).
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
1. Luke: walk the continent (Play), say what to change in the shape; commit step 23.
2. **THE LOAD TEST HARNESS**, in the TEMPLATE (a milestone of its own): a light bot client (likely Rust on the
   SpacetimeDB client SDK, many connections in one process; check the SDK first), each bot asking the
   ring's queries and sending real inputs (walk, gather, swing at dummies); run from the M1 so it does not
   take the server's CPU; 50 -> 100 -> 300, measuring rows and bytes a second per client and in total (the
   upload), reducer p95, the referee's lag, cell swaps a minute, nine cell sets against one OR'd query.
3. The combat design talk alongside it (`GAME.md` order (3)), then the in-game lookup, herbalism, economy.

## Waiting on Luke
- His look at the continent: the mountains' height and steepness, the camp's spot, the test placement.
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
