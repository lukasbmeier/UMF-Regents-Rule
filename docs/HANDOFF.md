# Handoff — Regent's Rule, 2026-11-16 (the armor run, in progress: step 87 merged)

## Where it stands
- THE ARMOR RUN IS IN PROGRESS (a master session). `docs/regents_rule/MASTER_RUN.md` is the work list; its §7
  LEDGER says who runs what and what is merged. A restarted master is given the prompt in MASTER_RUN §8, reads the
  ledger, and messages the SAME child sessions (ids in the ledger) to continue: never starts a second child for an item.
- `main` is committed and PUSHED through step 87 (E2, merge `ebead5ac`). Unit whole on `main` 2026-11-16: **4610/0**,
  lints and engine-error checks ok. No server change since step 83: `cargo test`, the playtests and integration not
  re-run (integration last ran at step 77; it runs ONCE at the run's end, M9).
- The play database: as published 2026-11-15 (`--codegen`, 63 tables). Step 87 is client scenes only: no publish.
- Children (each its own worktree under `.claude/worktrees/`, branch `claude/<name>-...`; none pushed):
  T1 DONE on its template branch `claude/t1-wear-hook-69d351` (`235313e`, 1.8.3: `ModularCharacter.wear` + `assembled`
  #313, NPCs bind without a session row #315), NOT merged or shipped; S1 running (game branch + template branch
  `claude/s1-resolve-action-all`); P1, E1, E3 running. Not started: S1b, S2-S4, W1-W4.
- What waits on Luke: `docs/regents_rule/WAITING_ON_LUKE.md`.

## This session (the master)
- M1: the town worktree and branch removed (an empty locked folder `.claude/worktrees/medieval-village-...` is left).
- M2: `docs/regents_rule/WAITING_ON_LUKE.md` (decisions, placeholders, what to play).
- Step 87 (E2): NPCs bind at once. `game/regents/npc_session_component.gd`, `npc.tscn`, `combat/foe.tscn`,
  `guide.tres`, NEW `game/regents/tests/bind_playtest.sh`; a rule line in `regents-genre.md`. PROGRESS 87.
- Found by the children, recorded in the ledger: S1's gap is the referee-JUDGED sweep (Cleave), which is FOUNDATION
  (add-only `AbilityDef.hits_all` + `resolve_action_all`, built by S1 in a template worktree, shipped with T1);
  P1 found per-role pools need server code (queued as S1b, Lane S) and ships one placeholder pool per weapon KIND;
  E3 found the town world's 17-30 s was piece lookups (a cache: 4.2 s) and builds no saved bake.

## Next, in order
1. When S1 reports: merge T1's and S1's template branches into the template's `main` (T1's version bump; S1's
   DECISIONS number after #315), run the template unit suite, then M3: `bash ../ship_template.sh "1.8.3: ..."`
   (every game must be clean), `publish.sh --codegen` here, unit, push.
2. Then merge S1's game branch (drop its "TEMP foundation copy" commit's content in favor of the pull), P1, E1, E3
   as they report: MASTER_RUN §5 each (inbox -> PROGRESS step 88+, WAITING_ON_LUKE §2, rules, ledger, this file).
3. Start S1b (per-role pools) and S2 (armor core) in Lane S, one at a time; W1 after M3; then S3, S4, W2, W3, W4.
4. After M3: remove `npc_session_component.gd` and the two scene overrides if the pulled fix (#315) makes them
   redundant (run `bind_playtest.sh`).
5. M9 at the end: the whole sweep, integration once, publish, the final HANDOFF and report.

## Waiting on Luke
- Everything in `WAITING_ON_LUKE.md` §1. From this run so far: E3 built no saved bake of merged buildings (~80 MB of
  binaries to save ~1 s): say if you want it anyway. Per-role ability pools are not in until S1b.

## Watch out
- THE 5-HOUR USAGE LIMIT cut every child at once on 2026-11-15: a cut child shows "failed"; SendMessage it to
  continue. At most ~5 children at once.
- Locks: `../.umf-locks/regents-rule-test` and `../.umf-locks/umf-template-test` (mkdir, `owner.txt`); a lock held
  over 2 hours: check its holder is alive before breaking it.
- A content SOURCE edit (`guide.tres`) makes `spacetime publish` fail until re-baked (the stale-bake check): that
  was E2's "publish failed".
- A PLAYTEST'S REFEREE STOPS when any project file changes on disk in ITS checkout: no writes in a worktree while its
  playtest runs. The main checkout is the master's; Luke's editor may be open on it.
- `ship_template.sh` merges into Fishing, Fowl Play, DiscGolf too and refuses if any has uncommitted changes.
- From before: `combat_playtest.sh` can flake at its first skeleton, `caster_playtest.sh` at the imp noticing (rerun
  once); every writer of an item's `instance_data` keeps `"x"` and `"k"`; `run_tests.sh` ignores `-- --only=`;
  a Python patch on Windows writes CRLF unless `newline=''`; shader edits need the windowed lab shots; towns: a
  building goes through `TownKit.instance_building` / a `Settlement` (Jolt's 10240-body limit).
