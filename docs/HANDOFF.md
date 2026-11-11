# Handoff — Regent's Rule, 2026-11-11 (step 57: Luke's play of the wolf; step 56 reviewed)

## Where it stands
- COMMITTED 2026-11-11 (by Claude, at Luke's word): `31522d2b` "Steps 51-57", then the merge of
  `claude/compassionate-panini-246b25` (`4ede0bfa`, the integration suite's CLI-timed combat checks in timed runs:
  `PROGRESS.md` step 50b). PUSHED to origin (main at `89cce913`). Left out on purpose: `addons/SpacetimeDB/plugin_config.tres` (a tool's re-save
  that dropped its uids; revert it or leave it). Current section in `docs/regents_rule/PROGRESS.md`: **Step 57**.
- PUBLISHED to the play database `regents-rule` after step 57 (no wipe, no codegen). Restart the game.
- Suites on this tree: regents unit **3392/0** (after the merge too); skilling playtest (a real client) **117/0 + 8/0**;
  `cargo test` **146/0** and the wasm check (before step 57, which touches no Rust; the publish built it).
- NOT RUN since the wolf (step 56) NOR SINCE THE MERGE: integration, any real-referee fight. The merged hook parses
  (`bash -n`) and its timed-run helpers are there; whether its combat checks are green now is the next run's to say.

## To playtest (Luke)
- Skin a wolf (hold E): its carcass lies under the cut line now.
- Drag a line to its end and keep holding: no tear; let go, press the next gold ring.
- Fight a wolf or a skeleton and step back after its first hit: it runs you down and lands the second; stay out
  1.5 s and it starts its string over when it catches you (`FoeDef.string_chase_ms`, each foe's own).
- The wolf itself (step 56): 110 health, notices at 10 m, a pack of 2 northwest of the glade's camp
  (`(-32, -14)`), packs of 2-3 in the continent's woods; bite 14, hamstring 16 (Slowed 3 s), lunge 28 (unblockable,
  thrown back), each at 55 %. `admin_slay <wolf> <you>` for a carcass without a fight.

## This session
- Reviewed step 56 (the wolf, built by Gemini in Antigravity) against our patterns: it follows them; its doc numbers
  were wrong and are corrected (`PROGRESS.md` step 56, `GAME.md`); open items below.
- Step 57, from Luke's play (`PROGRESS.md` step 57):
  - the wolf on the skinning stage: `art/animals/wolf_carcass.tscn` turned as the deer's; every carcass placed by
    hand under `Carcasses` in `skilling/skinning/skin_stage.tscn`, `SkinStage.set_carcass` shows the round's;
  - a line's end never tears: `SkinMinigame._look` runs the model before it sends the knife's place (no rule changed,
    goldens untouched);
  - a foe's string follows its target: `sidecar/npc/brains/regents/foe.gd` (`_drop_string`), `FoeDef.string_chase_ms`;
    Luke's call in `GAME.md`; `COMBAT_CURRENT.md` §11.
  - Luke's call, "Every foe": any fighting foe hit from beyond its sight turns on who hit it (`GAME.md`; step 56's
    code kept; `startled.tres` and `regents.startle_ms` say so; a skeleton check added);
  - tests in `game/regents/tests/suites/regents.gd` (`_run_skin_line_end`, `_run_skin_stage_carcasses`,
    `_run_foe_string_chase`), each with its negative run.

## Next, in order
1. Luke plays step 57 and the wolf.
2. The wolf's missing server tests, then ONE integration run for steps 56-57 and the merged step 50b (its first
   run on main: the combat checks called "known red" since step 53 should be green): checks in
   `game/regents/tests/hooks/integration_genre.sh` (a hamstring slows a player, a lunge pushes one, a blocked bite does
   neither, Startled on an idle wolf, its carcass and pelts, tanning) and a wolf leg in `skilling_playtest.sh`.
3. `HERBALISM_HUNTING_PREP.md` §7 step 5's rest (parked by Luke): sinew, the wolf-fang charm, the stag (place its
   carcass on the skinning stage). Then step 6.

## Waiting on Luke
- The glade's pack stands about 19 m from the deer, near a new character's start: there, or further out?
- `string_chase_ms` 1500 and the wolf's size on the stage are Claude's numbers.

## Watch out
- Never pipe `tools\publish.cmd` to `| Out-Default` (its background `spacetime start` holds the pipe). One shell call
  that ran `tests/content_test.sh` and then other commands hung past its timeout this session (cause not found): run
  it on its own.
- The cut line's bots and the readout LOOK before they press, so they never met the line's-end bug: a check of the
  minigame's own frame order needs `SkinMinigame._look` (or a real client), not the model alone.
- A `.tres`'s `designer_notes` is not baked, but the bake's manifest hashes the file: any edit to a content file
  needs `tools/bake_content.gd` (the unit suite's "the bake on disk is current" fails until then), then a publish.
- The merged branch's worktree is still there (`.claude/worktrees/compassionate-panini-246b25`, about 1 GB) and its
  branch: both can go now (`git worktree remove`, `git branch -d`), Luke's word first.
- Another model's doc numbers: check them against the `.tres` files before trusting them (step 56's were wrong).
