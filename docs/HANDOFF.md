# Handoff — Regent's Rule, 2026-11-13 (steps 72-76: the bar; 1-33; item levels, picks, changes; R; the abilities window)

## Where it stands
- Last commit `dfc5062e` "Steps 59-71" (NOT PUSHED). NOT COMMITTED since: steps 72-76 (code, content, bindings, docs)
  and the B1-B15 docs. Leave out of any commit, as before: `addons/SpacetimeDB/plugin_config.tres`,
  `game/regents/cinema/` and its lines in `game/regents/tests/suites/regents.gd` (`_run_cinema_lab`; that file also has
  72-73's changed checks).
- Current section in `docs/regents_rule/PROGRESS.md`: **Step 76**.
- The play database `regents-rule` is at step 76 (published `--codegen`, 108 reducers, not fresh: XP kept). Restart the game AND its
  referee. Older exported builds are refused (new bindings: export again before a playtest with friends).
- Suites (2026-11-13): `cargo test --test regents` 58/0, wasm clean; unit whole run 3875/0 (`regents_bar` 93/0);
  at step 74: `skilling_playtest.sh` 118/0 + 8/0; `combat_playtest.sh` 119/0; integration first run
  1596/6 (the new leg's own and the 1-33 axe round; hooks fixed), rerun **1653/0** at 74; at 75 **1583/0**, at 76 **1589/0** (totals vary: loops over rows); combat at 76: 67/50 once (a skeleton never
  noticed: a flake), rerun 119/0; unit 3884/0 (`regents_bar` 102/0).

## This session
- Step 72, THE BAR (`game/regents/ui/ability_bar.gd`, `ability_slot.gd`, `bar_style.gd`, `bar_round/square.tres`, the
  lab `bar_lab.tscn`); slot keys are Settings actions; the fight shown; the bar hides during a minigame round.
- Step 73, EVERY SKILL 1-33 (Luke's S1 + S2): `RANK_TOP` / `mastery_bp` (server and `SkillDef`); GALE BUFFED (S4:
  18 dmg, 12 s, slows, wears poise as a last hit); `ABILITIES_PREP.md` §9, the sword's pools, a draft for Luke.
- Step 74, ITEM LEVELS AND PICKS: the item's `"x"` and `"k"` in its own `instance_data` (`genre/regents/mod.rs`),
  `KitDef.skill_slots` / `unlock_levels`, `train` (catch-up, hot rule `regents.item_catch_up`), `need_slot`,
  `choose_pick`, `admin_set_item_level`; the client twin `RegentsItemLevel`; the bar and the bag's chooser.
- Step 76: R ASSIGNED (no ult yet: the last pick, at 20, takes the option E did not); THE WEAPON'S ABILITIES WINDOW
  (`game/regents/ui/abilities_window.gd`; click the weapon on the bar, or Abilities in the bag); the UI to-dos (`GAME.md`).
- Step 75, CHANGING A PICK (B13): `change_pick` (free weekly from level 20; else the head's material at a workbench,
  doubling, forgiven weekly), the item's `"f"`/`"e"`/`"c"`, five `regents.respec_*` hot rules; the bag's change row.

## Next, in order
1. Luke plays: the bar (round or square), Gale, a staff levelling to 5 and its pick in the bag (I).
2. Luke writes the axe's, sword's and bow's role abilities (his word: "for next time"; §9 is the sword's draft); then
   their slices of step 2, and the bow's and axe's pools (§7 step 4).
2b. THE UI REBUILD soon after armor (`GAME.md`, "THE UI, A REBUILD SOON AFTER ARMOR": inventory drag/resize, C the
   character sheet, one look, reorderable keys; window resizing is template work).
3. Step 2's rest: upgrades, the Tester page's item-level control, marks in B13's price (when marks exist).
4. §7 step 3 (areas that hit all) is FOUNDATION work (`sidecar/combat/action_referee.gd`, `resolve_action`).

## Waiting on Luke
- His rewrite of §9; round or square; whether to push `dfc5062e` (and commit 72-75).
- B13 as read: the free change anywhere, paid ones at a workbench; "halving weekly" as one doubling forgiven a week.
- From before: the lead's share; the archer's and imp's numbers; step 68's calls; step 62's two; #12 day/night, tree
  scale, the wolf pack's place, `string_chase_ms`, the glade's grass and colors.

## Watch out
- `combat_playtest.sh` CAN FLAKE at its first skeleton (it never notices the fighter, and 50 checks follow it down): rerun
  once before suspecting a change; the fix is to stand where the foe faces NOW (`regents-genre.md`, NOTICING).
- EVERY WRITER OF AN ITEM'S `instance_data` KEEPS `"x"` AND `"k"` (`keep_level`); combat XP goes through `train`.
- HEADLESS WINDOWS ARE 64 PX and injected clicks land at (0,0): HUD controls there PASS the mouse; the bar hides in rounds.
- `run_tests.sh` IGNORES `-- --only=`: one suite alone is
  `"$GODOT" --headless --path . res://tests/test_runner.tscn -- --only=regents_bar`.
- Ranks move in 15 XP steps now: a test expecting damage or speed reads `SkillDef.mastery_bp` / holds the rank.
- The integration suite prints only failures; `IDATA` there is the raw SQL string (read fields by regex).
- `game/regents/cinema/` and its suite lines are ANOTHER SESSION'S. NEVER EDIT A SHELL SUITE WHILE IT RUNS.
