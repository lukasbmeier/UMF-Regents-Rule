# Handoff — Regent's Rule, 2026-11-16 (THE ARMOR RUN IS DONE: steps 87-100, templates 1.8.3 and 1.8.4)

## Where it stands
- Everything is committed on `main` and PUSHED. The armor run (`docs/regents_rule/MASTER_RUN.md`, its §7 ledger) is
  finished: every item merged, the end sweep (M9) run.
- Suites on `main`, 2026-11-16, with everything merged: unit whole **5154/0** (lints, engine-error checks ok),
  `cargo test` green, wasm clean; `combat_playtest.sh` 144/0, `spells_seen_playtest.sh` 8/0 + 12/0,
  `caster_playtest.sh` 20/0, `armor_seen_playtest.sh` 11/0 + 7/0; INTEGRATION **1761/0** on its second run (the
  first: 1766 passed, 4 failed, all four stale or order-dependent TESTS in the genre hook; PROGRESS "end sweep").
  The integration pass was run on the fix branch (main + only the hook's fix), not again on `main` after the merge.
- The play database: PUBLISHED 2026-11-16 with `--codegen` after step 100 (64 tables, 111 reducers). Luke restarts
  the editor's game before he plays. Templates 1.8.3 (#313-#315) and 1.8.4 (#316) are shipped to all four games.
- Current section in `docs/regents_rule/PROGRESS.md`: steps 87-100 and "The armor run's end sweep".
- What waits on Luke: `docs/regents_rule/WAITING_ON_LUKE.md` (§1 decisions, §2 every placeholder with its file, §3
  what to play).

## This session (the master; each step is in PROGRESS with its tests)
- 87 NPCs bind at once (`bind_playtest.sh`). 88 another player's effects are the lighter version; rings one
  MultiMesh; the camera shakes from `shook`. 89 a sweep that hits all (Cleave), template #314. 90 the town world in
  4 s (`TownKit.piece`), the village's props (`VillageDressing`). 91 placeholder pools per weapon kind, the staff's
  ult Meteor, the Bolt at 12.
- 92 THE ARMOR CORE: the `worn` table, `wear` / `take_off` out of a fight, Defense in every hit (`rules::through`,
  `regents.defense_k` 67). 94 17 ARMOR PIECES from the material table (metal, leather, linen; real recipes;
  placeholder shares, tiers, amounts; trait pools EMPTY). 97 F IS THE WORN CHEST'S: the robe Blink (off the staff),
  jerkin Snare and cuirass Shove (placeholders). 100 EACH SWORD HANDLE ITS OWN SET (`KitRole.skills`).
- 93, 95 players are Peasant-only `RegentsFigure`s in their own colors; the picker's five color rows (template
  #316). 96 worn armor is SEEN (`ArmorLookComponent`, `wardrobe/armor_looks.tres`, `armor_seen_playtest.sh`).
  98 the dye measured cheap at 300 (`dye_bench.tscn`), the material cache bounded. 99 THE DOLL in the bag: wear and
  take off by a click, each piece's words (`RegentsDefense`, the server formula's twin).
- Template: `ModularCharacter.wear` + `assembled` (#313), `resolve_action_all` (#314), NPCs bind without a session
  row (#315), a color option in `CharacterPicker` (#316).

## Next, in order
1. Luke plays it (`WAITING_ON_LUKE.md` §3, the doll first) and answers §1; his rewrites replace §2's placeholders.
2. Armor's real parts, traits and numbers (`ARMOR_PREP.md` §0), once he has answered; then the UI rebuild's four
   to-dos (`GAME.md`), each his to shape first.
3. Small, left by the run: remove S2's practice pieces (40067, 40068) once nothing uses them; a missile's riding
   look lighter for others; per-role sets for the axe and bow when a handle gives them a role; the chest's level;
   a foundation per-bot admin hook if `load_300.sh` should have worn rows; `kit_def.gd`'s comment on F is stale;
   `GAME.md` does not yet record this run's built state (its decisions are unchanged: nothing of Luke's was decided).
4. From before: the role abilities' real content (`ABILITIES_PREP.md` §9, his rewrite); towns S1-S8.

## Waiting on Luke
- `WAITING_ON_LUKE.md`. Loudest: confirm "Blink moves to the cloth chest" (a staff with no robe has an empty F); his
  level-33 staff's R offers the placeholder Meteor; old sword picks outside a handle's set read as empty (free to
  choose again); a saved character that was Ranger / Wizard / Knight / Noble is now a Peasant.

## Watch out
- AFTER A MERGE THAT ADDS A `class_name`, run Godot `--headless --path . --import` before `run_tests.sh`; READ THE
  RESULT BEFORE PUSHING (step 88's first, red run was pushed for a few minutes).
- `ship_template.sh` pushes each game's `main` with the pull before any suite ran there. No suites were run in
  Fishing, Fowl Play or DiscGolf for 1.8.3 / 1.8.4: run theirs at their next session.
- A new session can only be started when Luke asks in the chat (the app refuses a start from an automated turn): a
  master reuses idle children by SendMessage. The 5-hour usage limit cut every child three times: a cut child shows
  "failed"; message it to continue.
- An integration leg that measures a number sets its own state or reads the server's rows (the rule, from M9).
- Locks: `../.umf-locks/regents-rule-test`, `../.umf-locks/umf-template-test` (mkdir, `owner.txt`), both free now.
- Four child worktrees are still checked out under `.claude/worktrees/` (their sessions are idle; all merged):
  remove them once the sessions are archived. Removed worktrees leave empty locked folders (Windows): delete by hand.
- From before: `combat_playtest.sh` can flake at its first skeleton, `caster_playtest.sh` at the imp noticing (rerun
  once); every writer of `instance_data` keeps `"x"` and `"k"`; `run_tests.sh` ignores `-- --only=`; a Python patch
  on Windows writes CRLF unless `newline=''`; shader edits need the windowed lab shots; a playtest's referee stops
  when a project file changes in its checkout; a content SOURCE edit needs a re-bake before a publish.
