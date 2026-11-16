# Handoff — Regent's Rule, 2026-11-16 (the armor run, in progress: steps 87-98 merged, template 1.8.4 pulled)

## Where it stands
- THE ARMOR RUN IS IN PROGRESS (a master session). `docs/regents_rule/MASTER_RUN.md` is the work list; its §7
  LEDGER says who runs what and what is merged. A restarted master is given the prompt in MASTER_RUN §8, reads the
  ledger, and MESSAGES the existing child sessions (ids in the ledger): a new session can only be started when Luke
  asks in the chat (the app refuses a start from an automated turn), so idle children are reused for the next item.
- `main` is committed and PUSHED through step 98. On `main` 2026-11-16 after step 98: unit whole **5103/0**, lints
  and engine-error checks ok, `cargo test` green, wasm check clean. Playtests on `main` not re-run (the children ran
  theirs on their branches: combat 130/0 with Cleave on both dummies, spells_seen 8/0 + 12/0, bind 3/0).
  Integration last ran at step 77; it runs ONCE at the run's end (M9), with the legs S1 and P1 wrote.
- Template 1.8.3 is shipped and pulled (`aca81080`): `ModularCharacter.wear` + `assembled` (#313), a sweep that
  hits all (`AbilityDef.hits_all`, `resolve_action_all`, #314), NPCs bind without a session row (#315).
- Template 1.8.4 shipped and pulled (`e15c2f16`): a free color option in `CharacterPicker` (#316).
- The play database: PUBLISHED 2026-11-16 with `--codegen` after step 98 (64 tables, 111 reducers: `worn`, `wear`,
  `take_off`, `resolve_action_all`, the placeholder pools). Luke restarts the editor's game before he plays.
- Running, the LAST TWO: S1b (per-role pools + the workbench look's early-out; four small client edits allowed:
  `combat_component.gd`, `ui/ability_bar.gd` model_for, `ui/abilities_window.gd`, `ui/station_window.gd` refresh) in
  the Lane S session; W3 (the doll in the bag; holds the rest of `ui/`) in the E1/W session. Then M9. Idle and reusable: the P1, E3, T1 sessions.
- What waits on Luke: `docs/regents_rule/WAITING_ON_LUKE.md`.

## This session (the master)
- M1 the town worktree removed; M2 `WAITING_ON_LUKE.md`; M3 template 1.8.3 merged (T1 + S1's half) and shipped.
- Step 87 (E2): NPCs bind at once; `bind_playtest.sh`. Step 88 (E1): another player's effects are the lighter
  version, rings one MultiMesh, the camera shakes from `shook`. Step 89 (S1): Cleave hits every foe in its sweep; a
  rally heals once a swing. Step 90 (E3): `TownKit.piece` cache (the town world 24 s -> 4 s), the village's props
  (`VillageDressing`). Step 91 (P1): one PLACEHOLDER pool per weapon kind (sword, axe, bow), the staff's ult Meteor,
  the Bolt at 12; Whirlwind and Arrow Volley marked `hits_all` at the merge. Step 92 (S2): THE ARMOR CORE: the `worn`
  table, `wear` / `take_off` out of a fight, Defense in every hit (`rules::through`), `regents.defense_k` 67, two
  practice pieces. Step 93 (W1): players are Peasant-only `RegentsFigure`s in their own colors (`RegentsColors` keys
  on the appearance text, shared materials); `wear_armor` is W2's way in. Step 94 (S3): 17 ARMOR PIECES from the
  material table (metal, leather, linen; recipes at the anvil and workbench; placeholder shares, tiers, amounts; trait
  pools empty). Step 97 (S4): F IS THE WORN CHEST'S: the robe Blink (off the staff), jerkin Snare and cuirass Shove
  (placeholders); no mana, no level. Step 98 (W4): the dye measured cheap at 300 (`dye_bench.tscn`), the shared
  material cache bounded; `load_300.sh` with dressed bots NOT run (no client draws there; bots cannot wear without a
  foundation per-bot admin hook). Step 96 (W2): WORN ARMOR IS SEEN: `ArmorLookComponent` on the adventurer, the table
  `wardrobe/armor_looks.tres`, `armor_seen_playtest.sh` (client only: no publish). Step 95 (W1b): the picker's five color rows confirmed on 1.8.4; the NPC session override removed. Each in PROGRESS with its tests.

## Next, in order
1. As S1b and W3 report: MASTER_RUN §5 each (inbox -> PROGRESS step 99+, WAITING_ON_LUKE, rules, ledger, this file).
   They share `ui/` files: merge one, have the other `git merge main` and re-run before its merge.
3. M9 at the end: unit, `cargo test`, wasm, integration once, combat / spells_seen / caster playtests (and one look
   at a bow skill pressed by a real client), publish, the final HANDOFF and report.

## Waiting on Luke
- `WAITING_ON_LUKE.md`: §1 decisions, §2 the placeholders (the pools, the village's props), §3 what to play.
  Loudest: his level-33 staff's R now offers the placeholder Meteor (Gale / Frost Ring on R no longer fire).

## Watch out
- A LOAD-SENSITIVE CHECK: "the workbench window's look with nothing changed ... (under 4)" (`regents.gd` ~2354)
  fails at 4.06-4.14 ms when another Godot run loads the machine (S3's 20 armor recipes brought it to 3.6-3.7 ms).
  Rerun with the machine quiet; the real fix (a cheaper unchanged look, NOT a higher limit) is queued with S1b.
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
