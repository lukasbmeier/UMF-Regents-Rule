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
| M1 | Fishing, Fowl Play, DiscGolf: `publish.sh --codegen`, `run_tests.sh` | (in place) | done: Fowl Play 2815/0, DiscGolf 2605/0; Fishing 3309/2 (the held-items grip suite: the rod 33 cm into the body at worst, Luke's grips; needed an `--import` first for `RollComponent`); bindings committed and pushed in each (Luke's yes) | - | Fishing `4eddebd`, Fowl Play `e75c2fb`, DiscGolf `832e3e0` |
| A1 | The bow's Q, an option and the ult pressed by a real client (combat_playtest) | `claude/followup-a1-bow-client-0980ca` | merged, unit 5228/0 on main, pushed | 103 | `79cf6bc5` |
| A2 | The practice armor (40067, 40068) removed; legs on real pieces; re-bake | `claude/followup-a2-practice-armor` | merged; on main unit 5247/0 (11 fewer than 5258: per-item checks of the two deleted items, not traced one by one), content 18/0, cargo test, wasm clean; pushed; play DB published | 105 | `5e01ac41` |
| A3 | M9's findings: integration's poise leg ("the bar full", 3 checks: Steadied not run out on a fast run, a `sleep 14` leaning on the slow CLI); caster_playtest's walked-into bolt (0.00 taken, 1 check) | lane A | building | - | - |
| B1 | The bar's and tooltips' words: slow, shove, every foe in the sweep | `claude/followup-b1-ability-words-b17159` | merged, unit 5228/0 on main, pushed | 102 | `cf259946` |
| B2 | Bolt's cast flash; Meteor's ring in fire; others' missile lighter | `claude/followup-b2-effects` | merged, unit 5258/0 on main, pushed | 104 | `dec49de2` |
| B2b | B2's one-frame violet circle at the Bolt's cast: found and fixed, or shown older than B2 | `claude/followup-b2b-bolt-circle` | merged, unit 5249/0 on main, pushed (a lab-only leftover hit flash) | 106 | `de5f7099` |
| M9 | Unit, cargo, wasm, integration once, combat / caster / spells_seen / armor_seen; publish; HANDOFF; cleanup | (main) | unit 5249/0, cargo test and wasm green; integration 1734/3 (14 min; poise leg, A3), combat 157/0, caster 19/1 (A3), spells_seen 12/0, armor_seen 7/0; play DB published after A2 | - | - |

## Tokens
- `ui/`: lane B (B1, then B2 if it needs it).
- The test-database lock: by the file (`../.umf-locks/regents-rule-test`), one server suite at a time.
