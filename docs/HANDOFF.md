# Handoff — Regent's Rule, 2026-11-05 (the minigame overhaul, step 1: PROGRESS 40)

## Where it stands
- Pushed through step 38 (`b0fac474`). Committed, not pushed: `13d16e99`, `2a46b0ab` (the prep sheet, revisions 1-2).
- **NOT committed**: Luke's answers (`GAME.md`, the sheet's top), PROGRESS 40 (the readout, core-only quality, the
  round titles), `CLAUDE.md` (the readout's command), this file.
- Play database `regents-rule`: as published after step 36. NOT published since: step 38's manifest, step 40's
  server change (core-only quality: no play difference today) and rebaked content (round titles). Publish with the
  next step that changes play.
- Last runs (step 40): unit (lints + regents) 3147/0; `cargo test --test regents` 45/0; `cargo check --target
  wasm32-unknown-unknown`. Not run: integration (last 1298/0 at step 37).

## This session
- `MINIGAMES_PREP.md`: written, revised twice after outside reviews (§9), ANSWERED by Luke (`GAME.md` "The minigame
  overhaul, ANSWERED": all as proposed; M2's band 3 waits on the metals after steel; M7 gathering as a 3D stage too).
- Step 1 built (PROGRESS 40): `SimPlayer` + `MinigameReadout` (lab T; `game/regents/tests/minigame_readout.sh`);
  `rules::sets_quality` + `make_batch` + `SkillingComponent.made_quality` (the core alone sets quality); the material
  table titles a round as its recipe, seven titles fixed.
- The readout's findings: the anvil's ceiling is ~80 % (Masterwork is the seed's); active smelting pays less than
  AFK for all but a flawless player; trees and copper max out for anyone attentive.

## Next, in order
1. `MINIGAMES_PREP.md` §8 step 2: the look on smithing: a 3D stage in the panel (`SubViewport`, the Quaternius anvil,
   the bar as a mesh glowing by heat), sparks, sound, a font and theme, and the two strikes (§3.1: add-only params
   `tap_drop`, `tap_spread_pct`, three models + goldens; the buttons a UI setting, both mappings). Luke plays it.
2. Step 3, smithing's ladder: first fix the ceiling (the outline must be reachable: the tap helps; check the readout's
   flawless player reaches ~100 %), then heat colors, the quench, rank easing; pin M4's target shares in the suite.
3. Then gathering's cadence and pay (M11, the 3D side panel test), the other three, carving.

## Waiting on Luke
- The metals after steel (sets where band 3 starts, M2).
- Whether the readout's presets feel like real hands: play a few rounds of the copper bar and an axe head in the lab
  and compare with its Skilled / Average lines (T).
- From before: "Cancelled." on the connect screen (a template change); where combat steps 5-7 and the lookup go;
  the tutorial's words; PROGRESS 30's list; a loot table with swords; which foes are bosses.

## Watch out
- A `--script` run can't see autoloads (`HotRules`): a tool that needs them is a scene (`minigame_readout_cli.tscn`).
- Restoring a file with `git checkout --` also drops your own uncommitted edits to it: back it up first.
- Python patch strings in a Bash heredoc mangle `\r`, `\t` (GAME.md got a CR once): write patch scripts with Write.
- The minigame UIs only draw their models: a new look must not touch a model, a Rust twin or a golden. A new
  mechanic is add-only params defaulting off, or a new challenge kind.
- New text and names in American spelling; never rename the kept British names (`.claude/rules/regents-genre.md`).
- Never run two server suites at once; never kill all Godot/Python processes, by PID only.
