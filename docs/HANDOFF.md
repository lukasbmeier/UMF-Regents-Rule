# Handoff — UMF Template, 2026-10-31 (1.6.3: a strip region referee asks for one range)

## Where it stands
**1.6.3** (DECISIONS #297): committed and pushed, merged into all four games and pushed there. Sidecar only:
restart a game's referees; nothing to republish. 1.6.0-1.6.2 (Jolt, the baker as a scene, the project look on a
thread) as the last handoff said: restart the editor in every game once for Jolt. Suites here for 1.6.3: unit
2281/0 (the new checks' negative fails 3), regions 25/0. Nothing else was touched, so nothing else was rerun.

## This session (Regent's Rule's referees on its Skyrim-size expanse, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- `RefereeRegion.ranges()` (`sidecar/region/referee_region.gd`): a region as tall as the level (a strip, cut
  `Nx1`) subscribes its columns as ONE `chunk >= a AND chunk <= b` a cell table; a region cut across the height
  keeps a range a column. `sidecar_main.gd` subscribes `ranges()` and logs "N columns, M ranges".
- `tests/referee_sweep.sh` cuts strips by default (`1x1 2x1 3x1 4x1 6x1`); HANDBOOK "Cut them in strips".
- Result, 300 bots on the expanse: the module 34-40 % busy at two to six strips (55-87 % before, cut 2x2/3x2).
  Two referees hold; three, four and six break only on one ~0.9 s net stall in each referee.

## Next, in order
1. The ~0.9 s stall once in each region referee of three or more, each at its own moment (not the server). With
   it gone, four or six strips hold 300 with room (six ran 10-16 ms frames). The breadcrumbs method of #295 finds it.
2. A region referee loads the whole level (~375 MB on the expanse); the server at 300 spread (#289 levers).

## Waiting on Luke
- The per-player bandwidth budget; the server's levers at 300 (#289). Fowl Play: the eagle and its playtest.

## Watch out
- Regent's Rule had another session at work (the combat overhaul) during this one: its sweep ran from a worktree
  at the merge, on its own database (`regents-rule-sweep-test`), to leave that session's files and test DB alone.
- Never put a `.gd` copy inside a project (even `build/`): two of a class and every spawn fails.
- Bake through `tools/world/bake_level.tscn` (or the button), never `-s bake_level.gd`.
- Heredocs through the Bash tool mangle backslashes (`\r`, `\t`, a Windows path): write patch scripts with the
  file tool, or edit with Edit.
