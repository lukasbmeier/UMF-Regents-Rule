# Handoff — UMF Template, 2026-11-15 (1.8.3: a game wears its own pieces; branch claude/t1-wear-hook-69d351)

## Where it stands
- 1.8.3 (DECISIONS #313) committed on branch `claude/t1-wear-hook-69d351` (child T1 of Regent's Rule's armor run),
  not merged to main, not pushed, not shipped: the run's master merges and ships. Client only (no republish/codegen).
- 1.8.2 (DECISIONS #312) on main, not pushed (from before).
- Green: the `looks` suite 55/0. Mutation-checked: 5 of 6 mutations failed the suite (rebuild skeleton, appearance
  drops overrides, head not restored, no emit on re-dress, null slot ignored); the 6th (freeing every skeleton mesh)
  survived at first, and a game mesh on the skeleton was added to the test, not re-run against the mutation.
- NOT RUN: the full `tests/run_tests.sh` (usage limit). Run it before merging.

## This session
- `game/characters/modular_character.gd`: `wear(pieces, slot_name)`, `overrides`, `slot_namer`, signal `assembled`,
  `HEAD_META`, `_rewear` (in place on the same skeleton), `wearing()` includes overrides, `_put_on` split out.
- `tests/suites/looks.gd` `_run_wear_tests`. HANDBOOK (a game's own pieces), CHANGELOG 1.8.3, DECISIONS #313.

## Next, in order
1. `tools\run.cmd tests\run_tests.sh` once; re-run the held-item mutation (`scratchpad mutate.py` idea).
2. The master merges and ships 1.8.3; Regent's W2 look component uses `wear` + `assembled`.

## Waiting on Luke
- From before: strips per expanse; the SDK fix upstream; bandwidth budget; greybox humanoid roll default.

## Watch out
- DECISIONS #313 may collide with another template child's row number at merge: renumber then.
- A respawn (appearance row change) shows the appearance's pieces until the genre's component binds and wears.
