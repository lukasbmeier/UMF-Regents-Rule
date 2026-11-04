# Handoff — UMF Template, 2026-11-04 (1.7.3: the integration suite on a busy machine; shipped to every game)

## Where it stands
- **1.7.3** (tests only, nothing to republish) committed, pushed and merged into Fishing, Fowl Play, DiscGolf and
  Regent's Rule. 1.7.1 (#303) and 1.7.2 (#304) shipped earlier today.
- Green: `tests/integration_test.sh` 667/0 here; Regent's integration (which runs it) 1328/0, 1298/0.

## This session
- Found from Regent's Rule's integration runs (a CLI call there takes 0.5-3 s), in `tests/integration_test.sh`:
  - the hold tick is looked for while the first helper holds alone (read after three joined, their 2 s had run);
  - "two effects at once": the timed effect lasts 5 s (was 1.5);
  - the timed press's `starts_at` is read while its row stands (the judgement check printed nothing without it);
  - a failed `assert_ok`/`assert_rejected` names the server's words (`said`), not the CLI's "UNSTABLE" line.
- Regent's Rule's own half (its step 37) is a stand-in referee that keeps beating and timed HTTP calls
  (`game/regents/tests/timed_calls.py`): a pattern the foundation's referee checks could take if they flake here.

## Next, in order
1. From before: effects' own presentation; the SDK btree patch upstream (ask Luke); a region referee's ~375 MB level load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.

## Watch out
- A CLI-timed check that must land inside a window (a status's time, a request's 3 s, a row that goes) reads too late
  on a busy machine: read what you need the moment it exists, or lengthen the window for the test.
- A kind whose character names a brain (the NPC's `wander`) drives its bots by that one, whatever `add_bot` names.
- `tests/walls_test.sh` keeps the referee's log with `WALLS_LOG=<file>`.
- Python through a Bash heredoc mangles `\` (line continuations, `\n`): write patch scripts as files.
- `run_tests.sh` passes no arguments: one suite is `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames).
