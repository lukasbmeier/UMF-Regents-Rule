# Handoff — UMF Template, 2026-10-29

## Where it stands
**1.2.0, the load test (DECISIONS #284)**: committed and pushed with this HANDOFF; NOT yet shipped to the
games (`ship_template.sh` not run for 1.2.0; no schema change, nothing to republish). **1.1.1 is shipped**
to Fishing, Fowl Play, DiscGolf (and Regent's Rule) this session, each republished `--codegen` (data kept).
Suites here: unit sweep 2205/0 (lints clean), `tests/load/test_load.py` 19/0, `tests/load_test.sh` run three
times (10 bots; 50/100/300; 50-300 by 50s, the run of record) with both negative runs passing. Its exit is 2
("breaks"): the referee breaks between 150 and 200 bots (below).

## This session
- **1.2.1, the walk map a tile at a time** (DECISIONS #285, from Regent's Rule's session): a level wider than
  256 m is baked in 128 m tiles on first asking, every walk map off the main thread. Unit sweep 2211/0; the
  new 3 km check fails baked whole. Fowl Play's farm keeps one map (its bots suites, at the ship).
- **1.2.1** (from Regent's Rule's session, 2026-10-29): `shared/load.json` `"level"` (0) is the level the load
  test puts world 0 on; a game overrides it in `shared/<genre>/load.json`. `tests/load_test.sh` read 0 always.
  A hook may name refusals that are play (`EXPECTED_REFUSALS`), hear answers (`on_result`), read rows as the
  owner (`bot.sql`). Checked: unit 20/0 (the new check fails with the change taken out); a 10-bot run holds. Pushed; shipped to Regent's Rule only (by merge), not yet to the others.
- Shipped 1.1.1: games' suites after the pull: Fishing unit 2985/0, content 18/0, fishing playtest 106/0 +
  observer 18/0; Fowl Play unit 2489/0 (referee two sides off), content 18/0, hunt 13/0, launch 8/0, powers
  2/1 (stale test, below); DiscGolf unit 2279/0, content 18/0, bots 15/0. Each game has one uncommitted
  file, `spacetime_bindings/codegen_debug/unparsed_schema_umf.json` (the codegen's debug dump): Luke's to commit.
- The load test (#284): `tools/load/` (`wire.py` WebSocket + BSATN from the module's schema + v3 messages;
  `bots.py` many guests a process; `cells.py` the Cells twin; `load_test.py` steps, server metrics, the
  referee's `perf_report`, the report; `interest_dump.gd/.tscn` the game's own queries), `tests/load_test.sh`,
  `tests/load/test_load.py`, `shared/load.json`. `InterestManager.cell_query` / `own_query` split out.
- MEASURED (`docs/load/2026-10-29_greybox.md`): the server keeps up at 300 (tick p95 9.5 ms of 50;
  `submit_input` queue wait p95 41 ms at 300, 6000 calls/s); per player at 300: 57 KB/s wire, 2000 rows/s,
  55 others in view. THE REFEREE: frame p95 6.9 ms at 100, 13.8 at 150, 76 at 200, 100 at 300; stalls to 2 s
  (6.6 s in an earlier run); its ping in seconds. It is sent every bot's movement (whole-world subscription).
- HANDBOOK "The load test" (section 3) and §10; AGENTS verify loop; testing.md; file_map; CHANGELOG 1.2.0;
  FOUNDATION_SYSTEMS "The load test".

## Next, in order
1. Ship 1.2.0 and 1.2.1: `bash "../ship_template.sh" "1.2.0: the load test"` (games committed first; Luke has the
   debug-dump files to commit), then each game's unit suite (no republish needed).
2. Regent's Rule pulls it and writes its `load_300.sh` on the continent with `game/regents/load_bot.py`
   (cast basics, harvest) and its own `shared/regents/load.json`.
3. The referee's feed: MEASURED in Regent's Rule (`../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`): first a referee
   subscribes only what it reads (no `input_queue`), then NPC tiers, then region referees. Was (Luke's call on the approach): a ring/cell interest of its own for what it judges,
   or thinner movement rows to it; then this suite says how far it goes.
4. Template 1.0 milestone A's last measurement: one OR'd ring query per table against nine one-cell ones
   (an interest file with OR'd cell queries; `bots.py` builds per cell today).

## Waiting on Luke
- The per-player bandwidth budget (`shared/load.json` `client_kb_per_s_p95`, `client_rows_per_s_p95`: null,
  reported only). 57 KB/s on the wire at 300 bots on the greybox is the number to set it against.
- Which way to fix the referee's feed (Next 3).
- Fowl Play's `powers_playtest.sh` fails "Play as: built again as the eagle": the eagle rests since
  2026-10-15 (`chicken.eagle_playable` off, "a hen instead"), so the test is stale, not the template.
  A Fowl Play fix (skip the eagle when it is resting), not done here.

## Watch out
- SpacetimeDB on Windows answers reducers on the 15.6 ms timer: round trips p95 ~15 ms whatever the load
  (server time 0.05 ms). Do not read it as server load; read the server's own histograms in the report.
- asyncio's clock on Windows ticks every 15.6 ms: the bots measure with `perf_counter`; keep it that way.
- The load suite wipes `umf-template-test` several times and runs six Python processes and a referee:
  run nothing else on the server meanwhile, or the numbers are not the game's.
