# Handoff — Regent's Rule, 2026-11-06 late (playtest crashes investigated; the host's referee log split)

## Where it stands
- Steps 41-44 committed and pushed (`git log`). On top: the template's 1.7.5 merged (`84d15000`, tools and docs
  only: nothing to publish, no codegen). Not pushed yet with this HANDOFF: see "This session".
- Left uncommitted ON PURPOSE (Luke's editor): 13 `.png.import` re-imports and `game/regents/anim/adventurer.tres`
  (an editor re-save); `shared/compat/` untracked. Ask before committing or touching them.
- Play database `regents-rule`: published with step 44, unchanged tonight. Luke's `tools\host.cmd` from 23:06 still
  runs the OLD host line (its referee writes `user://logs/godot.log`): restart it to get the split log.
- The plan for the minigames: `docs/regents_rule/MINIGAMES_PREP.md` (§7 Luke's M1-M12, §8 the order of work).

## This session
- THE CRASH (Luke and Fin, exported client, 2026-11-06 23:18:38 and 23:20:36; Fin crashed more often, alone too):
  Windows "Application Error", `umf.exe` 0xc0000005 at the same offset 0x4dc82bb both times; dumps in Luke's
  `%LOCALAPPDATA%\CrashDumps\umf.exe.{108904,100076}.dmp`. Unwound by hand (the release template has no symbols;
  scratch tools: PE `.pdata` unwind + capstone): `SpacetimeDBClient._physics_process` → the SDK's `row_inserted` →
  `SpaceTimeSync` lambda → `_emit_row` → `_emit_row_now` → `_deliver_row` → `row_event.emit` →
  `EntityRegistry._on_row_event` → two more script calls on one Node (most likely Fin's `SpaceTimeEntity`:
  `receive_row_event` then one of its own) → a TYPED ASSIGN of a native-class value (`ClassDB::is_parent_class` on
  `get_class_name()` of a FREED object: a release build reads the dangling pointer; the editor only errors
  "previously freed instance", so no test ever saw it). The row was an INSERT for entity 12289 (Fin), stamped
  04:20:36.46 UTC, while Fin was mining Copper rock 57. The exact line is NOT known.
- Template 1.7.5 (DECISIONS #306, made in the template, merged here): `tools/host.sh` gives the referee
  `--log-file build/host/referee.log` (the run before: `referee.prev.log`). It used to write the default
  `user://logs/godot.log` too, the exported game's file on this PC: both wrote over each other and Luke's crash lines
  were lost (runs of NUL bytes). Proved with a real host run on `umf-template-test`, a killed referee restarted.

## Next, in order
1. Fin's logs (Luke is getting them): `%APPDATA%\Godot\app_userdata\Regent's Rule\logs\` and, if his PC keeps them,
   `%LOCALAPPDATA%\CrashDumps\umf.exe.*.dmp`. His `godot.log` is clean (no referee on his PC): its last lines name
   the event; a dump of his can be unwound the same way (offset 0x4dc82bb means the same crash).
2. Name the line: Luke's call (asked, not answered): `debug/settings/gdscript/always_track_call_stacks=true` in
   `project.godot` (exists in 4.7.1), re-export, and the next crash prints the script file and line in `godot.log`.
   Or a debug export, where it is an error with a backtrace instead of a crash.
3. Then the fix: the typed assign that takes a freed object (check `is_instance_valid` first, or keep the reference
   where it is dropped when freed). Suspects: what `SpaceTimeEntity` and its components hold in untyped containers
   (`_routes` arrays of components, looped as `for c: SpaceTimeComponent in targets`); a component's node lookups.
   A test: the row arriving after the node it names was freed, run against an EXPORTED build (the editor won't crash).
4. Then the minigame plan as before: Luke plays steps 41-44; smithing numbers, M3/M4; §8 step 4 (M11); step 5's
   band rules; woodworking; the XP curve (GAME.md "Outranked XP").

## Waiting on Luke
- Whether to turn on `always_track_call_stacks` (a little slower; both players need the new export).
- His play of steps 41-44; synthesized sounds or CC0; the tap buttons; metals after steel; the readout presets.
- The work spot only steps for the node ahead, not one at the side of the 120 degree arc.
- From before: "Cancelled." on the connect screen; combat steps 5-7; the tutorial's words; PROGRESS 30's list;
  a loot table with swords; which foes are bosses.

## Watch out
- Two editor instances (or an export beside an editor run) still share `user://logs/godot.log` and write over each
  other: read logs from a run that had the PC to itself, or the crash dump.
- Telemetry and the server log give WHEN and WHO of a crash, never the line: that is only inside the crashed process.
- INTEGRATION FLAKES (seen across 4 runs): `foe_kill` loot reads after the row expired; the pommel bash; once a
  crossguard craft. The skilling playtest's pass count moves by one between runs.
- A `.tscn` writes a Transform3D's basis by ROWS. A scratch script under `game/` or `tools/` trips the lints (a bare
  `quit()`): use `AppExit.quit`. Never run imports or windowed shots during a server suite; never two server suites.
- Heredocs with Python patch strings break in this shell: write patch scripts with the Write tool.
- New minigame input codes must be positive; a new round param defaults to 0 = off; recipes copy a pattern's round once.
