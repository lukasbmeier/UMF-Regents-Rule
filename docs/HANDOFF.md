# Handoff — UMF Template, 2026-11-06 (1.7.5: a hosted referee writes its own log)

## Where it stands
- **1.7.5** (tools only: nothing to republish, no codegen) committed and pushed, and merged into Regent's Rule only
  (by hand: `ship_template.sh` stops while a game has uncommitted work, and Regent's Rule holds Luke's editor edits).
  Fishing, Fowl Play and DiscGolf get it with the next `ship_template.sh`. 1.7.4 shipped to every game earlier today.
- Proved by a real `tools/host.sh` run on `umf-template-test` (world 1): see CHANGELOG 1.7.5. No suite covers host.sh.

## This session (a small fix found in a Regent's Rule session, made here: `umf-session.md`, Across repos)
- Regent's Rule's playtest crashed twice (a native crash in the exported client; its own investigation is in that
  repo's HANDOFF). Luke's `godot.log` had lost the crash's last lines: the referee `tools/host.sh` started had no
  `--log-file`, so Godot also wrote the project's default `user://logs/godot.log`, the file the exported game on the
  hosting PC writes. Two processes in one file, each over the other.
- `tools/host.sh` (DECISIONS #306): the referee runs with `--log-file build/host/referee.log`, its console to nothing;
  the run before is moved to `referee.prev.log` before each start. Measured on Godot 4.7.1: `--log-file` replaces the
  default file log, is not rotated, and is flushed as it runs (the "registered" wait reads it).
- HANDBOOK "Playing with a friend" step 4: the host's logs, the client's own, Event Viewer and crash dumps.

## Next, in order
1. Ship 1.7.5 to Fishing, Fowl Play and DiscGolf with the next release (`ship_template.sh`).
2. From before: effects' own presentation; the SDK btree patch upstream (ask Luke); a region referee's ~375 MB level load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.

## Watch out
- Two editor instances of one game (and an export run beside the editor) still share `user://logs/godot.log`, each
  writing over the other: read a log from a run that had the PC to itself, or the crash dump.
- A referee that dies before Godot's logger is up leaves nothing (its console goes to /dev/null): run its line by hand.
- `hold_body_yaw` keeps ONE yaw: two genre holders at once face the last one's (DECISIONS #305's "revisit").
- A CLI-timed check that must land inside a window reads too late on a busy machine: read it the moment it exists.
- `tests/walls_test.sh` keeps the referee's log with `WALLS_LOG=<file>`.
- Python through a Bash heredoc mangles `\` (line continuations, `\n`): write patch scripts as files.
- `run_tests.sh` passes no arguments: one suite is `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames).
