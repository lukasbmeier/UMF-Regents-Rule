# Handoff — UMF Template, 2026-10-23

## Where it stands
The chronicle and the telemetry page (DECISIONS #276) and #277 are SHIPPED to every game
(`ship_template.sh`, 2026-10-23); Fishing, Fowl Play and DiscGolf republished with `--codegen` (data kept)
and checked (cargo test, content, the unit suite, each game's playtest: all green); Regent's Rule already
was. Then `tests/content_test.sh` was fixed (below) and shipped again. Suites green here: unit 2075/0,
cargo test all, telemetry 21/0, content 18/0.

## This session
- `where_sample` (private table, `server/src/module/telemetry.rs`): each online player's place every
  `foundation.telemetry_where_s` (a new hot rule, 5 s; 0 off), at the server's time.
- `tools/telemetry/chronicle.py`: the owner's `spacetime subscribe` to every table except those
  `shared/telemetry.json` skips. Writes every change to `build/telemetry/<db>.sqlite` (`change`,
  `position`, `player_name`, `run`) and reconnects as a new run.
- `tools/telemetry/dashboard.py` + `page.html` (`tools\telemetry.cmd`): panels are SQL in the JSON (line,
  bar, table, heatmap), with range and player filters and a 15 s refresh. 127.0.0.1 only.
- Who runs the chronicle: `tools/host.sh`, `ChronicleLauncher` (editor runs, beside `RefereeLauncher` in
  Boot), and the page when nothing else records. One per file, through a lock.
- Later the same session: `content_name` (every piece of content's name, for panels); a panel's `step`;
  heatmap squares floor (z -7 is the -8 square); a nameless player is "Player 37"; codegen waits 30 s for
  the schema (`addons/SpacetimeDB/cli.gd`: Godot took 2.3 s for Regent's 137 KB schema and the 4 s limit
  failed; the editor plugin's own 4 s in `spacetime.gd` is unchanged, since rewriting a @tool script
  under an open editor has crashed it).
- DECISIONS #277 (from Regent's playtest): `AnimationTreeBuilder.apply_clip` loops a clip on its NODE, never
  by changing the shared clip; a status holding `react.hit` as a looping pose had made every later hit
  reaction loop for ever. `animation` 2075/0, with checks that fail the old way.
- `tests/content_test.sh`: "a status that becomes something that is not a status" broke the foundation's
  status at index 2 (Downed), which Fowl Play's chicken genre replaces with its own, so it had failed
  there since 2026-10-12; it now breaks a foundation status no genre redefines.
- Tests: `tests/telemetry/test_chronicle.py`, `tests/telemetry_test.sh`, the `referee` suite (the lock),
  native `telemetry`. Docs: HANDBOOK "Looking back at everything", file map, AGENTS verify loop.

## Next, in order
1. Give the releases since 0.51.2 a CHANGELOG section (chat, held jump, traits, the chronicle).
2. Regent's Rule's foundation asks (its `GAME.md`): M8, M16, M18-M26, the template 1.0 `chunk` reshape.

## Waiting on Luke
- Nothing new.

## Watch out
- The CLI's own player flips online/offline as other CLI calls connect and leave (one identity). The
  chronicle marks it a tool while it has no name. Suites that name the CLI's player make it a "player".
- The editor plugin's schema fetch still times out at 4 s (`spacetime.gd`): codegen from the editor's dock
  may fail on a big schema; `tools/publish.sh --codegen` uses `cli.gd` (30 s). Change it with the editor
  closed.
- A chronicle killed hard (Task Manager, a console closed under the page) can leave its `spacetime
  subscribe` child connected until its next write fails. host.sh and editor runs stop it cleanly.
- `spacetime.exe` is a launcher: killing it leaves the `spacetimedb-cli subscribe` child running. The
  chronicle kills the tree (`taskkill /T`), and the suite cleans up leftovers by command line.
