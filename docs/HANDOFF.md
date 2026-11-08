# Handoff — UMF Template, 2026-11-07 (1.7.7: chat no longer crashes the game; 1.7.6 debug builds; 1.7.5 referee log)

## Where it stands
- **1.7.7** (client only: nothing to republish, no codegen; friends need a new build), **1.7.6** and **1.7.5** (tools
  and docs) committed and pushed, and merged into Regent's Rule only (by hand: `ship_template.sh` stops while a game
  has uncommitted work, and Regent's Rule holds Luke's editor edits and another session's smelting work). Fishing,
  Fowl Play and DiscGolf get all three with the next `ship_template.sh`. 1.7.4 shipped to every game on 2026-11-06.
- Unit suite: 2373 passed, 1 failed: `content`'s "a script runs from the repo root" fails on this machine with or
  without 1.7.7 (checked with the change stashed): its Git Bash script gets 600 headless frames, under a second.

## This session (fixes found in a Regent's Rule session, made here: `umf-session.md`, Across repos)
- THE PLAYTEST CRASH, found (DECISIONS #308): Regent's Rule's exported clients crashed on chat. `ChatBox._bubble` cast
  the speaker's last bubble (`as Label3D`) before checking it was still there; it had freed itself (its fade) or gone
  with the character, and a release build casting a freed object reads freed memory. Five dumps from two PCs, the
  host's telemetry (every crash within seconds of a chat line) and Regent's debug build (the error at
  `chat_box.gd:260`) agree. Fix: `_bubble_label`, `is_instance_valid` first; bubbles forgotten on `tree_exiting`.
  `tests/suites/chat.gd` covers it (negative-tested); `.claude/rules/umf-gdscript.md` states the rule for all code.
- 1.7.6 (DECISIONS #307): `tools\release.cmd --debug`, the Windows client on Godot's debug template. Godot's RELEASE
  template has no crash handler (its binary lacks the handler's text): no setting can make it name a native crash's
  line; the debug template reports the same mistakes as SCRIPT ERRORs at the line and plays on.
- 1.7.5 (DECISIONS #306): `tools/host.sh` gives the referee `--log-file build/host/referee.log` (the run before:
  `referee.prev.log`); it used to write the game's own `user://logs/godot.log` too, over the host's crash lines.

## Next, in order
1. Ship 1.7.5-1.7.8 to Fishing, Fowl Play and DiscGolf (`ship_template.sh`); each game's friends need a new build
   for 1.7.7 (chat is in every game). 1.7.8 (2026-11-08, tests only): `export_test.sh` publishes its own server
   fresh before running the exported client (a release stopped on another session's leftover entities).
2. The `content` project-task check: wait on the process, not a frame count (it fails on this machine now).
3. From before: effects' own presentation; the SDK btree patch upstream (ask Luke); a region referee's ~375 MB load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.

## Watch out
- A freed node `as`-cast is an ERROR in the editor and a silent CRASH in a release export: the unit runner fails on
  the error, so a test that frees the node first catches it (`tests/suites/chat.gd`).
- `release.sh --debug` (and every export) packs what is ON DISK: from a checkout another session is editing it packs
  half-written scripts (its start check stops that build). Make it from a clean worktree then.
- Two editor instances of one game (and an export run beside the editor) still share `user://logs/godot.log`.
- A referee that dies before Godot's logger is up leaves nothing (its console goes to /dev/null): run its line by hand.
- `hold_body_yaw` keeps ONE yaw: two genre holders at once face the last one's (DECISIONS #305's "revisit").
- `tests/walls_test.sh` keeps the referee's log with `WALLS_LOG=<file>`.
- Python through a Bash heredoc mangles backslashes (it once turned `tools\release` into a carriage return here):
  write patch scripts as files.
- `run_tests.sh` passes no arguments: one suite is `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
