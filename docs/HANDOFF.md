# Handoff — Regent's Rule, 2026-11-16 (the armor run, in progress: steps 87-91 merged, template 1.8.3 pulled)

## Where it stands
- THE ARMOR RUN IS IN PROGRESS (a master session). `docs/regents_rule/MASTER_RUN.md` is the work list; its §7
  LEDGER says who runs what and what is merged. A restarted master is given the prompt in MASTER_RUN §8, reads the
  ledger, and MESSAGES the existing child sessions (ids in the ledger): a new session can only be started when Luke
  asks in the chat (the app refuses a start from an automated turn), so idle children are reused for the next item.
- `main` is committed and PUSHED through step 91. On `main` 2026-11-16 after step 91: unit whole **4719/0**, lints
  and engine-error checks ok, `cargo test` green, wasm check clean. Playtests on `main` not re-run (the children ran
  theirs on their branches: combat 130/0 with Cleave on both dummies, spells_seen 8/0 + 12/0, bind 3/0).
  Integration last ran at step 77; it runs ONCE at the run's end (M9), with the legs S1 and P1 wrote.
- Template 1.8.3 is shipped and pulled (`aca81080`): `ModularCharacter.wear` + `assembled` (#313), a sweep that
  hits all (`AbilityDef.hits_all`, `resolve_action_all`, #314), NPCs bind without a session row (#315).
- The play database: PUBLISHED 2026-11-16 with `--codegen` after step 91 (the new reducer, the private `rallied`
  table, the placeholder pools). Luke restarts the editor's game before he plays.
- Running: S2 (armor core) in the S1 session, W1 (the picker's colors) in the E1 session, T2 (a color option in the
  foundation's CharacterPicker, template 1.8.4) in the T1 session. Not started: S3, S1b, S4, W2, W3, W4.
- What waits on Luke: `docs/regents_rule/WAITING_ON_LUKE.md`.

## This session (the master)
- M1 the town worktree removed; M2 `WAITING_ON_LUKE.md`; M3 template 1.8.3 merged (T1 + S1's half) and shipped.
- Step 87 (E2): NPCs bind at once; `bind_playtest.sh`. Step 88 (E1): another player's effects are the lighter
  version, rings one MultiMesh, the camera shakes from `shook`. Step 89 (S1): Cleave hits every foe in its sweep; a
  rally heals once a swing. Step 90 (E3): `TownKit.piece` cache (the town world 24 s -> 4 s), the village's props
  (`VillageDressing`). Step 91 (P1): one PLACEHOLDER pool per weapon kind (sword, axe, bow), the staff's ult Meteor,
  the Bolt at 12; Whirlwind and Arrow Volley marked `hits_all` at the merge. Each in PROGRESS with its tests.

## Next, in order
1. As S2, W1, T2 report: MASTER_RUN §5 each (inbox -> PROGRESS step 92+, WAITING_ON_LUKE §2, rules, ledger, this
   file). T2: merge into the template's `main`, its unit suite, `bash ../ship_template.sh "1.8.4: ..."`, then W1.
2. Lane S, one at a time, in the same session: S3 (armor pieces) after S2, then S1b (per-role pools), then S4 (the
   chest's F; needs the `ui/` token). W2 (the look, reads `worn`) after S2 + S3; W3 (the doll) after S4; W4 after W2.
3. After the pull of #315: remove `npc_session_component.gd` and the two scene overrides if redundant
   (`bind_playtest.sh` must stay 3/0).
4. M9 at the end: unit, `cargo test`, wasm, integration once, combat / spells_seen / caster playtests (and one look
   at a bow skill pressed by a real client), publish, the final HANDOFF and report.

## Waiting on Luke
- `WAITING_ON_LUKE.md`: §1 decisions, §2 the placeholders (the pools, the village's props), §3 what to play.
  Loudest: his level-33 staff's R now offers the placeholder Meteor (Gale / Frost Ring on R no longer fire).

## Watch out
- AFTER A MERGE THAT ADDS A `class_name`, run Godot `--headless --path . --import` before `run_tests.sh`: without it
  the suite fails with "class not declared" (step 88's first run: 8 failed; green after the import). READ THE RESULT
  BEFORE PUSHING (that red run was pushed for a few minutes).
- `ship_template.sh` merges into Fishing, Fowl Play, DiscGolf too, refuses if any is dirty, and PUSHES each game's
  `main` with the pull before any suite ran there: run the unit suite right after. No suites were run in the other
  three games for 1.8.3.
- THE 5-HOUR USAGE LIMIT cut every child at once on 2026-11-15: a cut child shows "failed"; SendMessage it to continue.
- Locks: `../.umf-locks/regents-rule-test` and `../.umf-locks/umf-template-test` (mkdir, `owner.txt`).
- A content SOURCE edit makes `spacetime publish` fail until re-baked; baked `shared/content/**` conflicts are
  resolved by re-baking on `main`.
- Removed worktrees leave empty locked folders under `.claude/worktrees/` (Windows): delete by hand.
- From before: `combat_playtest.sh` can flake at its first skeleton, `caster_playtest.sh` at the imp noticing (rerun
  once); every writer of `instance_data` keeps `"x"` and `"k"`; `run_tests.sh` ignores `-- --only=`; a Python patch
  on Windows writes CRLF unless `newline=''`; shader edits need the windowed lab shots; a playtest's referee stops
  when a project file changes in its checkout.
