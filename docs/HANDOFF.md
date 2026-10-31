# Handoff — Regent's Rule, 2026-10-30 (Jolt; the referees' stalls fixed; 2 referees hold 300 on the expanse)

## Where it stands
- Template **1.6.2** merged (1.6.0 Jolt Physics, 1.6.1 the baker as a scene, 1.6.2 the referee's project look
  on a thread; DECISIONS #295, #296). This game's step-25 work and the re-baked levels committed and pushed;
  Luke's own uncommitted files left alone: `CLAUDE.md`, `GAME.md`, `docs/regents_rule/COMBAT_OVERHAUL.md`,
  `docs/regents_rule/ANIMATIONS.md` (his combat overhaul in progress).
- Play database `regents-rule` republished (code only, data kept). **Restart the editor** (project.godot now
  names Jolt) and the game.
- Suites green on Jolt: genre unit 2736/0, native 127/0, combat playtest 51/0, continent playtest 22/0; the
  expanse sweep run to the end.

## This session
- The 15-65 s referee stall: Godot's default physics engine (the project never named one). Jolt now, every
  game (template 1.6.0). Levels re-baked on Jolt's rays: continent and expanse depth grids (0.1 m at edges).
- The 0.5-1.5 s stall every 10 s: the referee's look for a changed project, 8,217 files, on its main thread
  (template 1.6.2: a worker thread). The level baker as a bare script cut the continent into one cell (1.6.1).
- `expanse_referees.sh` to the end: **2 referees hold 300 bots** (38.8 ms, no stalls, ~1 GB and a core each);
  1 cannot; 4 and 6 break the server (82-87 % busy). `REFEREE_SCALING.md`, last section.

## Next, in order
1. Region referees' queries the server can narrow (`chunk >= a AND chunk <= b` a column, #291): a strip of whole
   columns as one range; then four or more referees stop costing the server.
2. One ~0.9 s stall in some referees a minute (not walk maps: they read in 140 ms).
3. The combat overhaul (Luke's `COMBAT_OVERHAUL.md`); how often an idle skeleton thinks belongs to it.

## Waiting on Luke
- His playtest: `tools\run.cmd game\regents\tests\expanse_watch.sh` (REFEREES=2x1 is the cut that holds).
- The server's levers at 300; the per-player bandwidth budget; where 300 is hosted.

## Watch out
- Never copy a `.gd` into the project (even `build/`): Godot sees two of its class and every spawn fails
  ("hides a global script class"). Back up outside `res://` or as `.keep`.
- Bake a streamed level through `tools/world/bake_level.tscn` (or its button), never `-s bake_level.gd`.
- Heredocs through the Bash tool mangle `\r`/`\t` in text: write patch scripts with the file tool.
- Never kill all Godot/Python processes: by PID only (the godot_ai and wiki processes are Luke's).
