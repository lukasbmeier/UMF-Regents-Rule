# FOLLOWUP_RUN — the follow-up run's ledger (2026-11-17)

After the armor run (steps 87-100) and step 101 (the world builder, committed `54c7ecb4`). One master in the main
checkout, two children in their own worktrees. The ground rules, conflict map, child protocol and merge procedure
are `MASTER_RUN.md` §1, §3, §4, §5; this file replaces its work list and ledger. Only the master edits it.

Differences from the armor run: two children only (both started in Luke's first turn); a child runs only the suites
its change touches plus a negative, the master runs the whole unit suite once per merge; `--import` after a merge that
adds a `class_name`; never push red; `docs/HANDBOOK.md` is never edited here (rule lines go to `GAME.md` or
`.claude/rules/regents-genre.md`).

## Lanes
| Lane | Session | Model, effort | Holds |
|---|---|---|---|
| A, server and tests | `lane-a` (local_c717109f) | Opus 5.5, high | server/genre files, playtests |
| B, client | `lane-b` (local_156a298f) | Opus 5.5, medium | the `ui/` token, `vfx/` |

## Items
| Item | What | Branch | State | Step | Merge commit |
|---|---|---|---|---|---|
| M1 | Fishing, Fowl Play, DiscGolf: `publish.sh --codegen`, `run_tests.sh` | (in place) | done: Fowl Play 2815/0, DiscGolf 2605/0; Fishing 3309/2 (the held-items grip suite: the rod 33 cm into the body at worst, Luke's grips; needed an `--import` first for `RollComponent`); bindings committed in each, not pushed | - | Fishing `4eddebd`, Fowl Play `e75c2fb`, DiscGolf `832e3e0` |
| A1 | The bow's Q, an option and the ult pressed by a real client (combat_playtest) | lane A | building | - | - |
| A2 | The practice armor (40067, 40068) removed; legs on real pieces; re-bake | - | waiting on A1 | - | - |
| A3 | On call for M9's integration findings | - | - | - | - |
| B1 | The bar's and tooltips' words: slow, shove, every foe in the sweep | lane B | building | - | - |
| B2 | Bolt's cast flash; Meteor's ring in fire; others' missile lighter | - | waiting on B1 | - | - |
| M9 | Unit, cargo, wasm, integration once, combat / caster / spells_seen / armor_seen; publish; HANDOFF; cleanup | - | waiting | - | - |

## Tokens
- `ui/`: lane B (B1).
- The test-database lock: by the file (`../.umf-locks/regents-rule-test`), one server suite at a time.
