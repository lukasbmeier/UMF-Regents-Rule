# Handoff — Regent's Rule, 2026-11-07 (playtest crashes: the referee's own log, a debug build to name the line)

## Where it stands
- Steps 41-44 committed and pushed. On top: the template's 1.7.5 (`84d15000`) and 1.7.6 (`7c157b36`) merged, tools
  and docs only (nothing to publish, no codegen), pushed with this HANDOFF.
- THE DEBUG BUILD for the crash hunt: `build/releases/Regent's_Rule-331b21db0518-debug.zip` (Luke sends it to Fin;
  both play it). Same fingerprint and code as the 2026-11-06 release; made from a clean worktree of `7c157b36`.
- Left uncommitted ON PURPOSE: Luke's editor (13 `.png.import`, `game/regents/anim/adventurer.tres`); `shared/compat/`
  untracked (the 2026-11-06 release snapshot: Luke commits it); and ANOTHER SESSION'S smelting "beat" minigame,
  mid-work on 2026-11-07 (`game/regents/skilling/smelting/beat_*`, `skill_minigames.gd`, `recipe_def.gd`, the bar
  recipes, `server/src/genre/regents/beat.rs`, `mod.rs`, goldens, sounds). Not this session's: never touch or commit it.
- Play database `regents-rule`: published with step 44, unchanged. Luke's `tools\host.cmd` must be restarted once to
  get the split referee log (1.7.5).
- The plan for the minigames: `docs/regents_rule/MINIGAMES_PREP.md` (§7 Luke's M1-M12, §8 the order of work).

## This session
- THE CRASH (Luke and Fin, exported client, 2026-11-06 23:18:38 and 23:20:36; Fin crashed more often, alone too):
  Windows "Application Error", `umf.exe` 0xc0000005 at the same offset 0x4dc82bb both times; dumps in Luke's
  `%LOCALAPPDATA%\CrashDumps\umf.exe.{108904,100076}.dmp`. Unwound by hand: `SpacetimeDBClient._physics_process` →
  the SDK's `row_inserted` → `SpaceTimeSync` `_emit_row` → `_deliver_row` → `EntityRegistry._on_row_event` → two more
  script calls on one Node (most likely Fin's `SpaceTimeEntity.receive_row_event` and one of its own) → a TYPED ASSIGN
  of a FREED object (the release build reads the dangling pointer). An INSERT for entity 12289 (Fin), while Fin was
  mining Copper rock 57. The exact line is NOT known yet.
- Template 1.7.5 (DECISIONS #306): `tools/host.sh` gives the referee `--log-file build/host/referee.log` (the run
  before: `referee.prev.log`); it used to write the game's own `user://logs/godot.log` too, over Luke's crash lines.
- Template 1.7.6 (DECISIONS #307): `tools\release.cmd --debug`. Luke asked for script call stacks as a Settings
  toggle; measured, Godot's RELEASE template has no crash handler, so no setting can make it name a native crash's
  line. The DEBUG template turns this crash's cause into `SCRIPT ERROR: Trying to assign invalid previously freed
  instance` at the script line, with a backtrace, and the game plays on. Luke chose a debug build for now. Proved:
  the debug build connects to `regents-rule-test` and plays with no errors; its start check stopped a build exported
  from this checkout while the other session's scripts were half-written.

## Next, in order
1. Fin's logs (Luke is getting them): `%APPDATA%\Godot\app_userdata\Regent's Rule\logs\` and, if his PC keeps them,
   `%LOCALAPPDATA%\CrashDumps\umf.exe.*.dmp` (offset 0x4dc82bb means the same crash).
2. Name the line: Luke and Fin play the debug build; where the release one crashed, its `godot.log` has
   `SCRIPT ERROR: Trying to assign invalid previously freed instance` with the file, line and backtrace.
3. Then the fix: the typed assign that takes a freed object (check `is_instance_valid` first, or drop the reference
   when it is freed). Suspects: `SpaceTimeEntity`'s untyped `_routes` arrays of components (looped as
   `for c: SpaceTimeComponent in targets`); a component's node lookups. A test: the row arriving after the node it
   names was freed, run against an EXPORTED build (the editor and debug builds report it, they do not crash).
4. Then the minigame plan as before: Luke plays steps 41-44; smithing numbers, M3/M4; §8 step 4 (M11); step 5's
   band rules; woodworking; the XP curve (GAME.md "Outranked XP").

## Waiting on Luke
- Fin's logs; a session on the debug build that hits the crash.
- His play of steps 41-44; synthesized sounds or CC0; the tap buttons; metals after steel; the readout presets.
- The work spot only steps for the node ahead, not one at the side of the 120 degree arc.
- From before: "Cancelled." on the connect screen; combat steps 5-7; the tutorial's words; PROGRESS 30's list;
  a loot table with swords; which foes are bosses.

## Watch out
- Any export (`release.cmd`, `--debug`) packs what is ON DISK: with another session's half-written scripts in this
  checkout it ships broken code. Export from a clean worktree (`git worktree add` outside the repo, copy `.godot/`
  and `tools/local.env` in, `--import`, then the release; ~5 min).
- Two editor instances (or an export beside an editor run) still share `user://logs/godot.log`.
- Telemetry and the server log give WHEN and WHO of a crash, never the line: that is only inside the crashed process.
- INTEGRATION FLAKES (seen across 4 runs): `foe_kill` loot reads after the row expired; the pommel bash; once a
  crossguard craft. The skilling playtest's pass count moves by one between runs.
- A `.tscn` writes a Transform3D's basis by ROWS. A scratch script under `game/` or `tools/` trips the lints (a bare
  `quit()`): use `AppExit.quit`. Never run imports or windowed shots during a server suite; never two server suites.
- Heredocs with Python patch strings break in this shell (backslashes): write patch scripts with the Write tool.
- New minigame input codes must be positive; a new round param defaults to 0 = off; recipes copy a pattern's round once.
