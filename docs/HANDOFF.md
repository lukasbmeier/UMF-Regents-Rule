# Handoff — UMF Template, 2026-10-31 (1.6.6: the town strip's frames)

## Where it stands
**1.6.6** committed and pushed (`d747a3d`), NOT yet merged into any game. Client, sidecar and the vendored
SDK: restart a game and its referees; nothing to republish. Suites here: unit 2309/0, e2e 11/0, sidecar 13/0,
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
1. Ship 1.6.6 to the four games: merge `d747a3d` (not this HANDOFF commit: Regent's HANDOFF is dirty) by
   hand into each (Regent's has the combat session's ~59 uncommitted files: none overlap), run each unit
   suite, push; a HANDOFF note in each game.
2. Regent's docs: `REFEREE_SCALING.md` new last section, PROGRESS step 25, `load_expanse.json` (three
   strips now hold; four kept for room is Luke's call), memory `load-test-harness.md`.
3. Offer the btree patch upstream (plaught-armor SDK): outward-facing, ask Luke first.
4. A region referee loads the whole level (~375 MB); the 2-3 s start-up stalls.

## Waiting on Luke
- How many strips the expanse runs by default (three hold at 43.7 of 50 ms; four have room).
- Whether to send the SDK fix upstream. The bandwidth budget; the server's levers at 300.

## Watch out
- The sweep worktree `rs` (scratchpad, db `regents-rule-sweep-test`) still exists: remove it when done.
- `run_tests.sh` passes no arguments: run one suite with `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The runner prints failures to stderr: grep "failed" counts, not "FAIL" on stdout.
- Heredocs through the Bash tool mangle backslashes: write patch scripts with the file tool.
