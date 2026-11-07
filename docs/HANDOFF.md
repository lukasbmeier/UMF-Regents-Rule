# Handoff — UMF Template, 2026-11-06 (1.7.4: a genre may turn the body without the camera; shipped to every game)

## Where it stands
- **1.7.4** (client only: nothing to republish, no codegen) committed, pushed and merged into Fishing, Fowl Play,
  DiscGolf and Regent's Rule by `ship_template.sh`. 1.7.3 shipped 2026-11-04.
- Green: unit (`tests/run_tests.sh`) 2370/0 here; negative: the held yaw not applied fails both new checks.

## This session (a small fix found in a Regent's Rule session, made here: `umf-session.md`, Across repos)
- `LocalInputComponent.hold_body_yaw(reason, on, yaw)` (DECISIONS #305): the body faces a genre's yaw (on the wire
  as aiming: `face`, the frame's `look_yaw`), the keys walk relative to it, the camera's own yaw is untouched; an
  aim (`hold_facing`) wins over it; let go, the body keeps its heading until it moves. Regent's Rule turns a worker
  to the tree or rock it works without swinging the player's view round (its PROGRESS 44, the work spot).
- `tests/suites/input.gd`: four checks. `docs/rules/movement.md` (GAITS AND FACING), CHANGELOG 1.7.4.

## Next, in order
1. From before: effects' own presentation; the SDK btree patch upstream (ask Luke); a region referee's ~375 MB level load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.

## Watch out
- `hold_body_yaw` keeps ONE yaw: two genre holders at once face the last one's (DECISIONS #305's "revisit").
- A CLI-timed check that must land inside a window (a status's time, a request's 3 s, a row that goes) reads too late
  on a busy machine: read what you need the moment it exists, or lengthen the window for the test.
- A kind whose character names a brain (the NPC's `wander`) drives its bots by that one, whatever `add_bot` names.
- `tests/walls_test.sh` keeps the referee's log with `WALLS_LOG=<file>`.
- Python through a Bash heredoc mangles `\` (line continuations, `\n`): write patch scripts as files.
- `run_tests.sh` passes no arguments: one suite is `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames).
