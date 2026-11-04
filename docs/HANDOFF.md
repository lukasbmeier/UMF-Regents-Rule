# Handoff — Regent's Rule, 2026-11-04 (integration hardened: PROGRESS 37; the armor review; foes stop at rocks: 36)

## Where it stands
- Committed and pushed: step 36 (`9612bd64`), then step 37 (the integration suite's referee checks) with template
  1.7.3 merged (tests only: nothing to republish). Template 1.7.3 pushed and merged into every game.
- **Uncommitted on purpose**: `GAME.md` and `.claude/rules/regents-genre.md`, the armor review session's (Luke's
  leanings, American spelling). Commit them with that work.
- Play database `regents-rule`: as published after step 36 (restart the game and its referee for the walls).
- Last runs: integration 1328/0, 1328/1 (a template check, fixed in 1.7.3), 1298/0; its negative (Cleave past the
  hold, the roll past the wind-up) fails exactly those 3 checks. Template integration 667/0. Unit 3138/0 (step 36);
  `walls_playtest.sh` 16/0.

## Sessions today
- Step 37 (this one): `game/regents/tests/timed_calls.py` (steps over one HTTP connection, each a set time after the
  last, with `sql`/`sqlwait` reads the next steps use); in `hooks/integration_genre.sh`: a stand-in referee that keeps
  beating (`standin_up`/`standin_down`), `hits` (a string, each swing answered at once, health read after), the spells
  in timed runs, the camp's respawn 40 s for the test. Template 1.7.3: the hold tick, the 5 s effect, the timed press's
  start read early, failures name the server's words.
- The armor review (session 2): reviewed Luke's outside critique of `ARMOUR_PREP.md`. Its wrong facts: a foe's
  finisher is UNBLOCKABLE ("34 to 6 on a full block" in the doc AND in A7.1 is wrong); the 14/34 are raw ability
  damage, a skeleton lands them at `damage_pct` 50-55 % (7-19); its Padded/Warded contradict `LOOT_AND_STYLES.md` §6
  and there are no damage kinds; its bow/staff role names are invented. Luke leans against player poise and against
  weight slowing movement (`GAME.md`); not decided. American spelling is Luke's call; the sweep is not done.
- Step 36: `sidecar/genres/regents.gd` sizes rocks, trees and stations for the referee (#8196); `node.tres` Blocks In
  = [Normal]; `walls_playtest.sh`. Template 1.7.1/1.7.2 shipped; Fowl Play's gates in its own session.

## Next, in order
1. Luke: restart the game; spar by a copper rock, a tree, the anvil: the skeleton should go round.
2. Luke's answers to `ARMOUR_PREP.md` (A1-A6 start the build; A2 is the open one: weight and poise); then build it
   by its §4 order. The American-spelling sweep (player text first) before or with it.
3. Watch the continent under load: a node worked out or back re-bakes its 256 m walk map tile (1 s after, at most
   every 5 s a map, one at a time). Run `load_300.sh` once and look for `[Sidecar] a walk map ... again` piling up.

## Waiting on Luke
- `ARMOUR_PREP.md` A1-A10.
- From before: poise's numbers and whether players get poise (A2 (d) ties in); the tutorial's words; PROGRESS 30's
  "Not Luke's" list; a loot table with swords; which foes are bosses.

## Watch out
- A new referee check in integration: use `standin_up`, and send what must land inside a window (a request's 3 s, a
  missile's 3 s, a cast, a string's 2 s, a dummy's 4 s reset) as one `timed`/`hits` run, reading the result in the
  run; a CLI call here takes 0.5-3 s. The pass count moves ~30 between runs (loops over random rolls).
- A heredoc through Git Bash turns `\\n` in Python source into a real newline: write patch scripts with the Write tool.
- The template's walk-map read warns "parsed RenderingServer meshes at runtime" (`NpcNav._source_with_walls`).
- `walls_playtest.sh` is laid out in the glade's own placement (copper rock 20 at (23, 14)).
- A `-s` SceneTree script in this project starts a referee of its own (an autoload): stop both by PID.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames).
- `RegentsContent` caches in a running game: a test that writes content must use `ContentLibrary.root_override` or
  call `RegentsContent.clear()`.
- Never run two server suites at once; never kill all Godot/Python processes, by PID only.
