# Handoff — UMF Template, 2026-10-21

## Where it stands
The chronicle and the telemetry page (DECISIONS #276) are committed and pushed (`24af605`). They were
merged into Regent's Rule by hand, because that repo holds Luke's uncommitted grip edits and
`ship_template.sh` refuses a dirty game. Fishing, Fowl Play and DiscGolf have NOT been merged yet: the
next ship merges them. Suites green: unit 2069/0, cargo test all, `tests/telemetry_test.sh` 21/0 (new).
Not re-run this session: the integration suite (the module change is the 1 Hz tick calling
`sample_where`; the telemetry suite covers it on a real server).

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
- Tests: `tests/telemetry/test_chronicle.py`, `tests/telemetry_test.sh`, the `referee` suite (the lock),
  native `telemetry`. Docs: HANDBOOK "Looking back at everything", file map, AGENTS verify loop.

## Next, in order
1. Ship to the other games at the next release (`ship_template.sh`); each republishes with `--codegen`.
2. Give the releases since 0.51.2 a CHANGELOG section (chat, held jump, traits, the chronicle).
3. Regent's Rule's foundation asks (its `GAME.md`): M8, M16, M18-M26, the template 1.0 `chunk` reshape.

## Waiting on Luke
- Nothing new.

## Watch out
- The CLI's own player flips online/offline as other CLI calls connect and leave (one identity). The
  chronicle marks it a tool while it has no name. Suites that name the CLI's player make it a "player".
- `spacetime.exe` is a launcher: killing it leaves the `spacetimedb-cli subscribe` child running. The
  chronicle kills the tree (`taskkill /T`), and the suite cleans up leftovers by command line.
