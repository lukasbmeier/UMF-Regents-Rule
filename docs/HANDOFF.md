# Handoff — UMF Template, 2026-10-31 (1.6.6: the town strip's frames)

## Where it stands
**1.6.6** committed and pushed (`d747a3d`), merged into all four games and pushed. Client, sidecar and the vendored
SDK: restart a game and its referees; nothing to republish. Games' unit suites after the merge: Fishing 3090/0,
Fowl Play 2594/0, DiscGolf 2384/0, Regent's 2884/0. Suites here: unit 2309/0, e2e 11/0, sidecar 13/0,
regions 25/0; every negative of the new checks fails (7 mutations).

## This session (Regent's Rule's referees, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- 1.6.6 (#300): the SDK's `_ModuleTableBTreeIndex` searched its bucket for every updated row; every
  movement row of a world is one `world_id` bucket (~4,000 on the expanse): ~85 us a row, the town strip's
  2x. Now `_slots` (row -> index), order unchanged. FIRST UMF PATCH TO THE VENDORED SDK:
  `tests/suites/sdk_patches.gd` holds it (hard rule 3's one exception).
- 1.6.6: `ActionReferee._people`: a swing looks at people, not ~3,800 movement rows.
- Expanse sweep (300 bots, strips): 1 ref 433 ms p95, 2 146, 3 43.7 (holds now), 4 30.4, 6 21.2 (room).
  Reports in `../Regents Rule/build/load/strip_sweep_166/` (gitignored).

## Next, in order
1. (Done: shipped; Regent's `REFEREE_SCALING.md` last section, PROGRESS step 25.) The combat session ships
   1.6.7 next (animation driver and tree builder, DECISIONS #301).
2. Offer the btree patch upstream (plaught-armor SDK): outward-facing, ask Luke first.
3. A region referee loads the whole level (~375 MB); the 2-3 s start-up stalls.

## Waiting on Luke
- How many strips the expanse runs by default (three hold at 43.7 of 50 ms; four have room).
- Whether to send the SDK fix upstream. The bandwidth budget; the server's levers at 300.

## Watch out
- The sweep's test database `regents-rule-sweep-test` is left on the local server (the worktree is removed).
- `run_tests.sh` passes no arguments: run one suite with `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The runner prints failures to stderr: grep "failed" counts, not "FAIL" on stdout.
- Heredocs through the Bash tool mangle backslashes: write patch scripts with the file tool.
