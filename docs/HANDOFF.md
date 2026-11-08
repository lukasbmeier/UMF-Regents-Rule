# Handoff — Regent's Rule, 2026-11-08 (a side session: the integration suite's combat checks, on its own branch)

## Where it stands
- Branch `claude/compassionate-panini-246b25` (a worktree), on top of `54c1973b`: tests and docs only, committed, not
  pushed; Luke merges. Nothing published (no game code changed); the play database `regents-rule` untouched.
- Integration on `regents-rule-test`, the final hook, three runs in a row: 1303/0, 1290/1, 1286/2; no combat check among the failures
  (the three are foundation timing races, below).
- THE MAIN CHECKOUT has another session's uncommitted minigame work (PROGRESS steps 45-49, its own HANDOFF): this
  branch's step is numbered 50 for that. Merging: PROGRESS and this file will conflict at their ends; keep both
  sides (this HANDOFF's "This session" is a section to fold into that session's).
- The crash hunt (2026-11-07) stands as it was: the debug build `build/releases/Regent's_Rule-331b21db0518-debug.zip`
  for Luke and Fin; the "Multiplayer crash investigation" session has it in hand.

## This session
- WHY 5-8 COMBAT CHECKS FAILED EVERY RUN: CLI calls (1-3 s each) between a thing that runs out and the step that needs
  it: a judged request (3 s after due), a dummy's health (whole 4 s after its last hit), a kill's `foe_kill` row
  (10 s), an arrow (8 s; a report of a gone body is passed over silently). PROGRESS step 50 has each.
- THE FIX (`game/regents/tests/hooks/integration_genre.sh`): the roles' string ends (943/953/963), the skeleton's
  swings, the rallying cut on a foe, the slaying chop's loot and the bow's three shots (`shot`) each in one `timed`
  run with the reads they need taken in it; "the camp waits" read before the loot; `timed_val` reads an empty value.
- Found on the way: a foe's hit on a player is HELD ~540 ms for a late parry (`held_hit`): read health 1 s after.

## Next, in order
1. Luke merges this branch with the main checkout's minigame work (PROGRESS and HANDOFF by hand: keep both).
2. The template (`../UMF Template`, `tests/integration_test.sh`): three of its checks race the CLI the same way, one a
   run here: "the push stays where it happened" (a push lives 5 s), the body contact "once" (5 s), Help up's "again"
   (the first two finish the hold before the third joins). Timed calls there too, as here.
3. Then as the minigame session's HANDOFF says (Fin's logs, the debug build's crash line, the minigame plan).

## Waiting on Luke
- The merge. Everything else as the main checkout's HANDOFF lists it.

## Watch out
- STOPPING A SUITE: a background task's stop can leave `tests/integration_test.sh` running (re-parented). Kill its
  whole process tree, or two suites end up on the test database at once (this session did, 2026-11-07: its own
  baseline and fix runs, the failures all over the foundation's sections were that).
- Sessions share ONE CLI identity: every session's suite is player 41 on `regents-rule-test`. One suite at a time,
  across sessions; say so in the shared notes folder before taking it.
- A worktree with `.godot/` copied in needs `--import` first. The skilling bot prints compile errors for autoloads
  (`HotRules`, `Settings`) on every run, in the main checkout too, and still plays: harmless.
- `play_round` has a margin, not a failure: the bot (6-7 s) + three CLI reads + a sleep from the bot's end run
  close to a round's 30 s when the CLI is slow.
