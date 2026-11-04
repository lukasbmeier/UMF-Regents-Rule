# Handoff — UMF Template, 2026-11-04 (1.7.1 and 1.7.2 committed, pushed and shipped to every game)

## Where it stands
- **1.7.2** (DECISIONS #304, referee walls sized per entity) and **1.7.1** (#303) committed and pushed (1.7.1's five
  files first, then 1.7.2 with both releases' docs), and merged into Fishing, Fowl Play, DiscGolf and Regent's
  Rule by `ship_template.sh` (Luke's go, 2026-11-04). The games that had not taken 1.6.7-1.7.0 took them too.
- Green before shipping: the unit sweep 2366/0; `bots` + `referee` three times in a row; `tests/walls_test.sh`
  21/21 (and its negative, the referee without the genre's say, fails 4 checks).
- 1.7.0 added a table (`status_effect`): each game republishes with `--codegen`. 1.7.2 is sidecar only.

## This session
- Committed and shipped; no foundation code changed after the 1.7.2 session (see its CHANGELOG entry).

## Next, in order
1. Regent's Rule: its half of the walls (its HANDOFF): `sidecar/genres/regents.gd` sizing rocks, trees, stations.
2. Fowl Play: its shut gates are in its bots' walk maps now; its own half is game work in its repo: brains that
   open a gate (hens) or break it (predators) instead of walking up to it.
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
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames):
  2 fails in 5 runs in Regent's Rule, 2026-11-03.
