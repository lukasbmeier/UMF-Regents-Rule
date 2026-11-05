# Handoff — Regent's Rule, 2026-11-04 (American spelling: PROGRESS 38; armor parked; integration hardened: 37)

## Where it stands
- Committed and pushed: step 36 (`9612bd64`), step 37 (the integration suite's referee checks) with template 1.7.3
  merged. Template 1.7.3 pushed and merged into every game.
- **NOT committed**: the armor review and step 38 (the spelling pass): `GAME.md`, `CLAUDE.md`,
  `.claude/rules/regents-genre.md`, `docs/regents_rule/ARMOR_PREP.md` (renamed from `ARMOUR_PREP.md`), PROGRESS,
  ~50 genre files (comments, test messages, genre-only names), `shared/content/manifest.json`.
- Play database `regents-rule`: as published after step 36. Step 38 changes no behavior; the rebaked manifest goes
  out with the next publish.
- Last runs (step 38): unit 3138/0 (lints + regents); `cargo check --target wasm32-unknown-unknown`;
  `cargo test --test regents` 45/0. Step 37: integration 1298/0. Not run for 38: integration (no server behavior
  changed: comments and a log line).

## This session
- Armor reviewed twice from outside reviews; `ARMOR_PREP.md` revision 2, then PARKED (Luke): §0 says what is settled
  (in `GAME.md`: Defense `x K/(K+Defense)`, `regents.defense_k` 67, multiplied in order, `FoeDef.defense`, NO weight,
  NO player poise, wearing, the look, the words) and the four places to restart; §6 the second review checked.
- The order of work (Luke, `GAME.md` "armor parked"): spelling pass, minigame overhaul, herbalism and hunting, armor.
- Step 38, American spelling (PROGRESS 38): ~370 words in 53 files; `swing_canceled`, `color_of`; KEPT British: the
  `swing` table's `cancelled` column (rule 17), the foundation's `UiKit.colour`, `InterestManager.centre`,
  `Cells.recentre` (listed in the genre rules). Player text was already American.

## Next, in order
1. Luke: commit this session's work (or say so and I will); restart the game for step 36's walls if not done.
2. **The minigame overhaul**: design talk with Luke first (the skills' minigames are his, `GAME.md` #17); the
   minigames are `game/regents/skilling/` (each with a `*_model.gd`, `*_params.gd`, the server's twin in
   `server/src/genre/regents/`), the lab `skilling_lab.tscn`.
3. Then herbalism and hunting; armor after (`ARMOR_PREP.md` §0).
4. Watch the continent under load: run `load_300.sh` once and look for `[Sidecar] a walk map ... again` piling up.

## Waiting on Luke
- The foundation's one British word a player sees: "Cancelled." on the connect screen
  (`foundation/ui/connect_screen.gd:229`): a template change reaching every game; his call.
- Where the rest of the combat deep-dive (overhaul steps 5-7) and the in-game lookup go (proposed in `GAME.md`:
  combat after hunting).
- From before: the tutorial's words; PROGRESS 30's "Not Luke's" list; a loot table with swords; which foes are bosses.

## Watch out
- New text and names in American spelling (`.claude/rules/regents-genre.md`); never rename the kept British names.
- Python on this machine writes files through Windows text mode: open with `newline=""` to keep LF.
- A new referee check in integration: use `standin_up`, and send what must land inside a window as one
  `timed`/`hits` run; a CLI call here takes 0.5-3 s. The pass count moves ~30 between runs.
- A heredoc through Git Bash can mangle backslashes in Python source: write patch scripts with the Write tool.
- `walls_playtest.sh` is laid out in the glade's own placement (copper rock 20 at (23, 14)).
- A `-s` SceneTree script in this project starts a referee of its own (an autoload): stop both by PID.
- The foundation's `content` check "a script runs from the repo root" is flaky under load.
- `RegentsContent` caches in a running game: a test that writes content must use `ContentLibrary.root_override` or
  call `RegentsContent.clear()`.
- Never run two server suites at once; never kill all Godot/Python processes, by PID only.
