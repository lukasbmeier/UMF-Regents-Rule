# Handoff — Regent's Rule, 2026-10-31 (strip referees: the server no longer pays for more referees)

## Where it stands
- Template **1.6.3** merged (DECISIONS #297; 1.6.0-1.6.2 before it: Jolt, the baker as a scene, the referee's
  project look on a thread). This session's work committed and pushed. Sidecar only: restart the referees;
  nothing republished (no server change), the play database `regents-rule` as it was.
- **Another session (the combat overhaul) was at work in this checkout** during this one: its uncommitted
  files (foe and kit content, `server/src/game/regents.rs`, `sidecar/npc/brains/regents/foe.gd`, the suites,
  Luke's `CLAUDE.md`, `GAME.md`, `COMBAT_OVERHAUL.md`, `ANIMATIONS.md`) were left alone and not committed.
- Suites for 1.6.3: template unit 2281/0, regions 25/0; the expanse sweep (strips) run to the end.

## This session
- A region referee as tall as the level asks for its cells as ONE range a table (`RefereeRegion.ranges()`), not a
  range a column (12-46 a referee here, each checked against every moved row: SpacetimeDB narrows no range).
- `expanse_referees.sh` cuts strips (`1x1 2x1 3x1 4x1 6x1`); a cut with rows (`2x2`) still costs a range a column.
- The sweep, 300 bots on the expanse: the module 34-40 % busy at 2-6 referees (55-87 % before). Two hold (40.0
  ms); 3, 4 and 6 break only on one ~0.9 s net stall in each referee (six: 10-16 ms frames).
  `REFEREE_SCALING.md` last section, PROGRESS step 25.
- `load_bot.py`: "you cannot while slain" is an in-play refusal (a skeleton killed a fighter as it swung).

## Next, in order
1. The ~0.9 s stall once in each referee of three or more, each at its own moment (not the server): breadcrumbs
   as in #295. Then four or six strips hold 300 with room.
2. Why the middle strip of three (the town) ran 104 ms frames at p95.
3. The combat overhaul (Luke's `COMBAT_OVERHAUL.md`, the other session); how often an idle skeleton thinks
   belongs to it.

## Waiting on Luke
- His playtest: `tools\run.cmd game\regents\tests\expanse_watch.sh` (REFEREES=2x1 is the cut that holds).
- The server's levers at 300; the per-player bandwidth budget; where 300 is hosted.

## Watch out
- The combat session may rewrite this file when it finishes: this session's state is also in PROGRESS step 25.
- The sweep ran from a worktree in this session's scratchpad on its own database (`regents-rule-sweep-test`),
  so the combat session's half-done server never went into it. Do the same while another session works here.
- Never copy a `.gd` into the project (even `build/`): Godot sees two of its class and every spawn fails.
- Bake a streamed level through `tools/world/bake_level.tscn` (or its button), never `-s bake_level.gd`.
- Heredocs through the Bash tool mangle backslashes (`\r`, `\t`, Windows paths): use the file tool or Edit.
- Never kill all Godot/Python processes: by PID only (the godot_ai and wiki processes are Luke's).
