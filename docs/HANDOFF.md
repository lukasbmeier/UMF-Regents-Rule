# Handoff — Regent's Rule, 2026-11-03 (Luke's play notes #8193-#8196; the armour prep sheet: PROGRESS 35)

## Where it stands
- **Built, NOT committed** (Luke commits), over the earlier sessions' uncommitted steps 26-34 (~150 files).
  Template 1.7.1 (DECISIONS #303) is still written but uncommitted in `../UMF Template`, its five files here byte for
  byte (`server/src/game/mod.rs`, `server/src/module/authorities.rs`, `server/src/module/loot.rs`,
  `foundation/components/status_component.gd`, `tests/integration_test.sh`): commit the template's first, then this.
- Play database `regents-rule`: published with `--codegen` at the session's end (`round_cancel`; data kept;
  schema 331b21db0518, 103 reducers). Restart the game to pick it up. SpacetimeDB was restarted from this session
  (`spacetime start`) after Luke stopped his host.
- Last runs: unit 3081/0; native `cargo test` 138/0 (the full set, first since poise); integration 1284/20, then 1289/25: every new
  `round_cancel` check passed; the failures are all CLI-timed referee checks (the overhead's roll race cascading,
  requests gone before the CLI answered, mana regrown between calls) and both runs were made while Luke's host
  (`tools/host.sh`, 17:35) ran on the same SpacetimeDB server. Not proven: rerun integration with the host stopped.
  Not run this session: the skilling and combat playtests.

## This session
- **#8194/#8195 lag and 50-70 fps**: client frames of 139/208 ms by the workbench, not the server. The station
  window's twice-a-second look listed the patterns folder from disk per sort comparison (199 ms). Fixed in
  `content/material_table.gd` (through `RegentsContent`), `content/regents_content.gd` (no cache while
  `ContentLibrary.root_override` is set), `skilling/skilling_component.gd` (sort keys once). Now under 4 ms; checked
  in the regents suite (its negative failed at 199 ms).
- **#8193 leave a minigame**: Escape (`regents_hud.gd` `_input`/`leave_round`; HUD var `_input` renamed
  `_local_input`). Gathering sends what was played (scores count work done); making is withdrawn by the new reducer
  `round_cancel` (`regents.rs`, rate line in `shared/rules.json`), nothing used. Hint under the minigame's time bar.
- **#8196 skeleton through the copper rock**: found, NOT fixed. The referee has no walls for nodes or stations (no
  definition sets `blocker_size`, #229), so every foe walks through every rock, tree and station.
- **`docs/regents_rule/ARMOUR_PREP.md`**: armour's road and Luke's decisions A1-A10 (listed in `CLAUDE.md`).

## Next, in order
1. Luke: restart the game; try Escape at the anvil and a tree; stand by the workbench (fps should hold ~140).
2. Luke's answers to `ARMOUR_PREP.md` (A1-A6 start the build); then build it by its §4 order.
3. #8196: the template's half is BUILT as 1.7.2 (DECISIONS #304; uncommitted in `../UMF Template` over 1.7.1;
   its unit suites and `tests/walls_test.sh` green). After Luke commits it and it is merged here, Regent's adds:
   - `sidecar/genres/regents.gd` (`extends RefereeGenre`; add `sidecar/genres/regents.gd` to
     `tools/template/genres/regents.paths`): `sizes_kind(k)` true for 100 (nodes) and 101 (stations);
     `wall_tables()` `[&"gather_node", &"station"]` (the referee is then sent them although `genre.tres`
     `referee_tables` is empty); `walls(eid, kind)` from `SpaceTimeSync.get_row(&"gather_node"/&"station", eid)`:
     a rock: the box of the model `NodeComponent` picks for that entity (same pick by entity id) times
     `model_scale`, measured once per model and cached, or a size baked on the NodeDef; a tree: its trunk only
     (~0.9 m, a NodeDef number); a station: its box. Boxes are `AABB`s from the feet (`RefereeGenre.box(size,
     centre)`), turned with the entity's yaw. Empty until its row has come (it is asked again when it does).
   - `node.tres`: Blocks In = [Normal] (Depleted, 100, is then rubble: no wall); leave `blocker_size` zero.
   - Tests: the regents suite (a rock's and a tree's boxes from real NodeDefs; nothing before the row) and a
     skeleton routed round a rock (the template's `tests/walls_test.sh` shows the shape: a real referee, a negative).
   - Watch: a node worked out or back re-bakes its 256 m tile (1 s after, at most every 5 s a map, one at a time);
     see whether the expanse's busy mines keep the bake queue full (`[Sidecar] a walk map ... again` lines).
4. The handoff before this one: commit (template 1.7.1 first), ship 1.6.7-1.7.1 to the other games, harden the
   roll-in-the-overhead check (`game/regents/tests/hooks/integration_genre.sh`).

## Waiting on Luke
- `ARMOUR_PREP.md` A1-A10.
- From before: poise's numbers and whether players get poise (A2 (d) ties in); the tutorial's words; PROGRESS 30's
  "Not Luke's" list; a loot table with swords; which foes are bosses.

## Watch out
- A `-s` SceneTree script in this project starts a referee of its own (an autoload): stop both by PID; time things
  inside the unit suite instead.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames for
  Git Bash): 2 fails in 5 runs. A template fix.
- `RegentsContent` caches in a running game: a test that writes content must use `ContentLibrary.root_override` (it
  bypasses the cache) or call `RegentsContent.clear()`.
- From before: a published table is never removed (`poise` stays declared); the integration CLI is slow; never run two
  server suites at once; never kill all Godot/Python processes, by PID only.
