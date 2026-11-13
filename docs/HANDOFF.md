# Handoff — Regent's Rule, 2026-11-13 (steps 67-71: a foe's shot leads; noticing and rest; the foe bench; integration; parrying hit 2)

## Where it stands
- Last commit `e272626a` (pushed). NOT COMMITTED: steps 59 to 71, `GAME.md`, `FOES_PREP.md`, the integration hook's
  fixes, `PROGRESS.md` 58-71. Left out on purpose as before: `addons/SpacetimeDB/plugin_config.tres`.
  `spacetime_bindings/` regenerated (steps 64 and 68): commit it, new type files included. New files since step 63,
  to commit: `sidecar/npc/brains/regents/tasks/`, `trees/`; the archer's and the imp's content (`content/ability/
  foe_*.tres`, `spell/foe_*.tres`, `kit/skeleton_bow.tres`, `kit/imp.tres`, `character/skeleton_archer.tres`,
  `imp.tres`, `foe/skeleton_archer.tres`, `imp.tres`); `combat/foe_look.gd`, `missile_flight.gd`; `art/monsters/Imp.glb`
  and its textures, `T_Skeleton_BaseColor_2.png`; `tests/archer_playtest.sh`, `caster_playtest.sh`,
  `tests/playtest/archer_playtest.*`, `caster_playtest.*`; the continent's regenerated files (about 490).
- Current section in `docs/regents_rule/PROGRESS.md`: **Step 71**.
- The play database `regents-rule` is at step 71 (published; step 68's was `--codegen`; not fresh). Restart the game AND its
  referee. The schema fingerprint moved: an exported build from before is refused (export again for friends).
- Suites (2026-11-13): `cargo test --test regents` **56/0**; wasm check clean; regents unit **3749/0** (step 71);
  `caster_playtest.sh` **17/0 + 6/6** and `archer_playtest.sh` **19/0 + 5/5** (step 68); `combat_playtest.sh`
  **121/0** + its server checks (step 71). INTEGRATION **1544/5** (step 71): the dummy's full-bar poise leg (3, NOT
  EXPLAINED) and the archer's two shot checks, since rewritten for an offline CLI player and NOT YET RUN.

## To playtest (Luke)
- PARRYING HIT 2 (step 71): a parried skeleton's next swing is now its second, not its finisher; the backswing has a
  new clip with a wind-up to read (`Sword_Light_B`). Restart the game AND its referee.
- THE LEAD (step 67): walk across an archer's or imp's line as it draws: it meets you; turn, stop or roll after the
  glint and it misses. `regents.foe_shot_lead_pct` (100) on the Rules page.
- NOTICING (step 68): walk up behind a skeleton (it turns at 4 m), sprint (8 m), stand in front (10 m). Watch the camp
  wander. Shoot one from behind from 20 m with a friend nearer it: it comes for the shooter. With the three on you,
  a second finisher inside 1.5 s of a stagger hurts but does not stagger (`regents.unchained_ms`).

## This session
- Step 67: `rules::lead_point`, `foe_shot_due` leads a shot (not a ring); hot rule `regents.foe_shot_lead_pct`;
  two new imp legs. F5's "no leading" reversed in `GAME.md` (his words).
- Step 68: `FoeDef` `notice_arc_deg`, `hear_m`, `hear_sprint_m`, `wander_m`; `foe.gd` `_notice`, `sees`, `hears`,
  `_wander`, `status_by`; server `hurt_now(.., by)`, private table `unchained`, `unchained`/`chained_by`,
  `rules::is_chained`, hot rule `regents.unchained_ms`. Docs: `COMBAT_CURRENT.md`, `regents-genre.md`, `FOES_PREP.md`.
- The three live suites reworked for a foe that sees in front and wanders (`PROGRESS.md` step 68, "Tested").
- Step 69: the foe bench shows a shooter (`shot_rhythm`, `fight_rhythm`, `noticing`); `COMBAT_CURRENT.md` §11
  rewritten whole, §13 gains the foe rules. No server change (step 68's publish stands).
- Step 70: the hook's checks for the startle's `by_entity`, not chained (two wolves) and a foe's shot; the run;
  fixes to the hook for a quick CLI; F15 confirmed in place (step 66).

## Next, in order (`FOES_PREP.md` §9 done but its integration)
1. Luke's play of hit 2, the lead and noticing, and his numbers (`PROGRESS.md` 67, 68, 71 "Decided here"/"Fixed").
2. The next integration run: the archer's two rewritten checks; the dummy's full-bar poise leg (`PROGRESS.md` 70, 71).
3. After foes: ARMOR's prep session (`ARMOR_PREP.md` §0); the rest of the combat deep-dive.

## Waiting on Luke
- The lead's share; the archer's and the imp's numbers; step 68's calls (a still player within 4 m is heard; the
  window counts from the landing; the sparring skeleton does not wander).
- Later levers he was shown: a shooter timing its shot to your commitment.
- Whether his ability bar and Q/E/R list comes before armor (`GAME.md`, "STILL HIS").
- From step 62: a foe's swing skipping the start of its wind-up by your delay; a foe's LAST hit dealt at once too.
- A roll from a run goes a meter further than from a standstill: one length needs a foundation switch.
- From before: #12 day/night, tree scale, the wolf pack's place, `string_chase_ms`, the glade's grass and colors.

## Watch out
- THE CLI'S PLAYER IS OFFLINE between its calls (it connects for each, is parked after): anything the server does
  only for an online player (a foe's shot) cannot be checked by a CLI suite; a read of `online` always says true.
- A SUITE THAT NEEDS A FOE TO NOTICE IT stands in front of where it faces NOW or within its hearing of where it stands
  NOW, and keeps other foes down when their wander could bring them in (`regents-genre.md`).
- TEMPLATE ASK: `NpcWorldView` could carry a status's `by_entity`; the referee reads it from `SpaceTimeSync` today.
- I edited `@tool` task scripts and ran a headless `--import` with Luke's editor open; restart the editor if a tree
  shows a stale task name.
- A GDScript ternary of two array literals is untyped: assign, then `if`.
- `combat_playtest.sh` failures are read from `KEEP_LOGS=<dir>` and the server's log, never rerun for a pass.
- NEVER EDIT A SHELL SUITE WHILE IT RUNS, and never run the unit suite beside a server suite.
- The Bash tool breaks a heredoc holding an odd number of apostrophes: write the script with the Write tool.
- Never pipe `tools\publish.cmd` to `| Out-Default`; a `.tres` content edit needs `tools/bake_content.gd`, then a publish.
