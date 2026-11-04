# Handoff — UMF Template, 2026-11-03 (1.7.2 written over 1.7.1, NEITHER committed: referee walls per entity)

## Where it stands
- **1.7.2** (DECISIONS #304) and **1.7.1** (#303) are both in this working tree, NOT committed (Luke commits).
  1.7.1's own files: `server/src/game/mod.rs`, `server/src/module/authorities.rs`, `server/src/module/loot.rs`,
  `foundation/components/status_component.gd`, `tests/integration_test.sh`. 1.7.2's: `sidecar/referee_genre.gd`
  (new), `sidecar/npc/brains/patrol.gd` (new), `sidecar/combat/action_referee.gd`, `sidecar/npc/npc_nav.gd`,
  `sidecar/sidecar_main.gd`, `foundation/core/entity_blocker.gd`, `foundation/core/entity_definition.gd`,
  `tests/walls_test.sh` + `tests/e2e/walls_genre.gd` (new), `tests/suites/bots.gd`, `tests/suites/referee.gd`,
  `AGENTS.md` (the verify loop's line), `docs/rules/sidecar_and_npcs.md`, `docs/rules/file_map.md`,
  `docs/FOUNDATION_SYSTEMS.md`. Shared by both: `docs/DECISIONS.md`, `docs/CHANGELOG.md`, `docs/HANDBOOK.md`.
  Two commits are possible (1.7.1's files first), or one.
- 1.7.2 is sidecar only: no table or reducer changed, nothing to republish or `--codegen`; restart the referee.
- Green: the full unit sweep `tests/run_tests.sh` 2366/0; `bots` + `referee` three times in a row; `tests/walls_test.sh`
  21/21, and its negative (the referee without the genre's say) fails 4 checks as it should. Server untouched by
  1.7.2 (no cargo run this session; 1.7.1's were green). 1.6.7, 1.7.0 are still in Regent's Rule only.

## This session (Regent's Rule feedback #8196: "Sparring skeleton walks right through the copper mine ore")
- `RefereeGenre`: a genre's `sidecar/genres/<id>.gd` sizes each entity's wall for its referee (`sizes_kind`, `walls`
  -> `Array[AABB]`, `wall_tables` re-asked on their rows and added to the referee's feed); the kind's `blocks_in`
  still switches it (`EntityDefinition.blocks_in_status`, works with no `blocker_size`). Referee only (#304).
- `EntityBlocker.of_boxes`/`set_boxes`: several boxes, reshaped in place; `ActionReferee.boxes_of`, `add_genre`.
- Walls in the walk maps: `NpcNav.set_wall`/`drop_wall`, carved as projected obstructions; a change marks the maps
  it touches, re-baked 1 s later, at most every 5 s a map, through the one-at-a-time queue; the level's read kept
  per area (`SOURCE_KEEP` 4) so a re-bake does not read the level on the main thread.
- Found and fixed: a region put on its map before its mesh sometimes never got the mesh taken in (Godot 4.7.1):
  `ready` stayed false and brains walked straight forever. Regions now join their map with their first mesh.
- `patrol` brain (memory `{"to": [x,y,z]}`); `--referee-genre=` sidecar flag; `tests/walls_test.sh`.
- Regent's HANDOFF Next 3 says exactly what Regent's adds; the shared notes folder has the hand-over too.

## Next, in order
1. **Luke: commit 1.7.1 and 1.7.2 here**, push; merge into Regent's Rule after its own work is committed, then its
   half (its HANDOFF, Next 3: `sidecar/genres/regents.gd`, `node.tres` Blocks In = [Normal], its tests).
2. Then 1.6.7-1.7.2 into Fishing, Fowl Play and DiscGolf (`--codegen` for 1.7.0's table), each unit suite. Fowl Play:
   run its bots suites too (its shut gates are now in its walk maps; a brain sent to a gate still walks up to it).
3. From before: effects' own presentation; the SDK btree patch upstream (ask Luke); a region referee's ~375 MB level load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.

## Watch out
- A kind whose character names a brain (the NPC's `wander`) drives its bots by that one, whatever `add_bot` names:
  the walls test's bots are kind 0 for that reason (existing behaviour, `SidecarMain.attach_brain`).
- A patrol runs: `spacetime sql` sampling (~1.4 s a look) misses its turns; the test reads its "reached its far end" log.
- `tests/walls_test.sh` keeps the referee's log with `WALLS_LOG=<file>`.
- Python through a Bash heredoc eats `\` line continuations: patch scripts as files.
- `run_tests.sh` passes no arguments: one suite is `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
