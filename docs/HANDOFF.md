# Handoff — Regent's Rule, 2026-11-06 (the minigame overhaul: PROGRESS 40-44, a multi-day run, ends here)

## Where it stands
- Steps 41-44 COMMITTED (`bfb35c98`) and the template's 1.7.4 merged (`3dfa9560`), all PUSHED with the ship;
  the body-facing and quicker step on top (`git log -3`), all pushed.
- Left uncommitted ON PURPOSE (Luke's editor): 13 `.png.import` re-imports, `game/regents/anim/adventurer.tres` (an
  editor re-save) and `game/regents/skilling/mining/mine_stage.tscn` (LUKE MOVED the pick's `PickRest`/`PickHit`
  markers in the editor, 2026-11-06: his pose; ask before committing or touching it).
- Play database `regents-rule`: PUBLISHED with step 44 (2026-11-06, no wipe: content + server). Restart the game.
- Last runs: unit (lints + regents) 3172/0 and the skilling playtest 81 + 8 / 0 on the final work spot (the body
  turns, the camera stays, the step takes 0.13-0.37 s); before it, on step 44: `cargo test` all green (regents 45/0),
  wasm check, integration 1330 / 3 (known timing flakes only, none in skilling: "Watch out"); the work-spot shot:
  every node's swing lands 1-13 cm short of the surface, the big iron rock too.
- The plan: `docs/regents_rule/MINIGAMES_PREP.md` (its §7 is Luke's decisions M1-M12, §8 the order of work);
  Luke's calls are in `GAME.md` (search "The look (M7)", "THE WORK SPOT", "THE WORK REACH", "The anvil, after").

## What was built (PROGRESS 40-44)
- 40: the difficulty readout (`MinigameReadout`, `SimPlayer`: four simulated hands, shares per grade); titles.
- 41-42: SMITHING on a 3D stage (`AnvilStage`), heavy strike + light tap, 5 heats (each costs the ceiling), the
  pattern (Space; no strikes while on), a varying outline; bands as a TEST: copper 1, iron 2 (each look costs),
  steel 3 (red heat cracks, the quench). `ShapeModel` + Rust twin `shape.rs` + goldens (21 cases).
- 43: woodcutting, mining, smelting on 3D stages (`WoodStage`, `MineStage`, `SmeltStage`); every round in the
  960 x 620 MIDDLE panel; NO character on a stage: the tool floats (`FloatingTool`: rest and hit poses are
  `Marker3D`s in each stage scene, each holding an editor-only tool preview: drag them); the pick lands point first;
  the stump wears the tree's bark; all sounds synthesized by `game/regents/tools/make_skill_sounds.py`.
- 44: THE WORK SPOT: E at a node turns the BODY to face it (eased; the camera stays the player's: the template's
  `hold_body_yaw`, 1.7.4, DECISIONS #305) and WALKS them back or in until the swing's
  front (`SkillingComponent.swing_front`, per skill pose, measured by `game/regents/tests/work_spot_shot.tscn`)
  meets the drawn rock or bark, then the work starts (`WorkSpot`, `SkillingComponent.begin`). The server's work
  reach is now from a node's EDGE (`NodeDef.radii_cm`, baked from the models: a rock as drawn, a tree its trunk).
  Moving 0.15 m off the spot stops AFK work (`afk_leave_m`, the client's; the server's 1 m is the backstop). The
  pick swings in from the left, its point the model's own (-0.31, 0.67, 0).

## Next, in order
1. LUKE PLAYS (nothing below is decided until he has): the anvil per band (copper, iron, steel heads and blades),
   the three gathering stages, the work spot at trees and rocks (the big iron rock too).
2. From his play: smithing's numbers (the steel sword blade is very hard: average 97 % Common in the readout),
   M3 rank easing and M4 grade shares (tune with `tools\run.cmd game\regents\tests\minigame_readout.sh`); tool poses.
3. `MINIGAMES_PREP.md` §8 step 4: gathering's back-to-back runs and pay (M11), from the work spot.
4. §8 step 5's rest: each band's new rule for woodcutting, mining, smelting (knots, brittle notches, slag): prototype,
   Luke plays each before the next. Then §8 step 6 (woodworking's carve to the line), 7 (herbalism, hunting).
5. The XP curve (GAME.md "Outranked XP": steep, so a lower tier is never worth it for XP).

## Waiting on Luke
- His play of steps 41-44; whether the synthesized sounds stay or CC0 recordings replace them; the tap buttons.
- The metals after steel (M2's band 3); whether the readout's presets feel like real hands.
- The work spot only steps for the node ahead (where the camera faces), not one at the side of the 120 degree arc.
- From before the overhaul: "Cancelled." on the connect screen; combat steps 5-7 and the lookup; the tutorial's
  words; PROGRESS 30's list; a loot table with swords; which foes are bosses.

## Watch out
- INTEGRATION FLAKES (none from this work; seen across 4 runs): the loot reads of `foe_kill` after its row expired;
  the pommel bash ("no such request (answered, or run out)", or 0 damage: the dummy is whole again 4 s after a hit and
  the CLI's reads took longer: the local `spacetimedb-standalone` has run since 11/3, restarting it may help); and once (likely the
  order board's random order taking the iron axe head the workbench check needs later) a crossguard craft and 3 after.
- The skilling playtest's pass count moves by one between runs (a check that runs only on some timings).
- A `.tscn` writes a Transform3D's basis by ROWS. The headless playtest's viewport is 64 x 64: measure from edges.
- A scratch script under `game/` or `tools/` trips the lints (a bare `quit()`): use `AppExit.quit`.
- Never run Godot imports or windowed shots during a server suite (timing checks fail); never two server suites.
- Heredocs with Python patch strings break in this shell: write patch scripts with the Write tool.
- New minigame input codes must be positive (the server refuses a round with a value under -1); a new round param
  defaults to 0 = off (old rounds replay); recipes copy a pattern's round once (edit the recipes too).
