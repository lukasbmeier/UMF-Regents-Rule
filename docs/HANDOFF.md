# Handoff — UMF Template, 2026-10-30 (the server at 300 players, read right: 1.4.1)

## Where it stands
**1.4.1** (DECISIONS #289) on 1.4.0 (#288), 1.3.0 (#287), 1.2.2 (#286): committed and pushed. Pulled into
Regent's Rule (local merge commits there). NOT shipped to Fishing, Fowl Play, DiscGolf (`ship_template.sh`
not run since 1.1.1: each has its codegen debug dump uncommitted, Luke's). 1.4.0 adds a table (each game
republishes `--codegen`); 1.4.1 is code only.
Suites for 1.4.1: integration 644/0 (the tick ignoring statuses fails 2); e2e 11/0; movement playtest
(0/100/200 ms) 41/0; native green; `tests/load/test_load.py` 23/0 (the old harness fails it).

## This session (from Regent's Rule's load test, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- THE LOAD TEST READ THE SERVER WRONG: SpacetimeDB times each call as two transactions (`Reducer`, then
  the subscription `Update`), and the harness summed them (every call counted twice); its p95s are guesses
  inside 1/5/10/50 ms buckets. Now: exact means, each reducer's update apart, `busy ms/s`, the module's
  busy % (`module_busy_pct`, `tick_movement_mean_ms` reported). `tools/load/load_test.py`, HANDBOOK.
- Read right, 300 bots: the module 76 % busy, `tick_movement` 438 ms/s; `prune_action_events` 2 ms/s
  and `work_tick` 5 (last handoff's "4 ms" was the bucket's guess: nothing to fix there).
- `tick_world_module` (`module/movement.rs`) reads each world's rows once a tick, one delete a player's
  frames, `write_movement_over` (`module/place.rs`; also `write_movement_batch`). The tick's own code
  halved (3.2 ms at 300); its subscription update is 15.3 ms; the module 68 % busy.

## Next, in order
1. Ship 1.2.0-1.4.1: `bash "../ship_template.sh" "1.4.1: the server at 300"` once Luke commits the games'
   debug dumps; each game republishes `--codegen` and runs its unit suite and its referee suites. Fowl Play
   and DiscGolf keep `referee_tables = *` until they list theirs.
2. The load test's limits judge bucketed p95s (`tick_movement_p95_ms`, `reducer_wait_p95_ms`: 50 sits on a
   bucket edge); judge `module_busy_pct` (say <= 80) instead, once Luke agrees.
3. Genre cell tables are asked for whole by a region referee: give the sidecar the game's `cell_tables`.
4. Template 1.0 milestone A's last measurement (OR'd ring query against nine one-cell ones).

## Waiting on Luke
- What is left at 300 is SpacetimeDB's subscription fan-out (~2/3 of the module): players x neighbours x
  20 Hz. Levers are design: how dense players are (the test is a town everywhere, ~47 seen each), the cell
  size (64 m), how often others' movement is written, `input_batch_size` (3: 20 calls a second each).
- The per-player bandwidth budget (~120 KB/s at 300 dense; gzip saves 2.2x for ~14 % of the update cost).

## Watch out
- Python's text-mode write on Windows makes CRLF: `io.open(..., newline="")` or `sed -i 's/\r$//'` after.
- SpacetimeDB on Windows answers on the 15.6 ms timer: round trips p95 ~15 ms whatever the load.
- The load suite wipes the test database several times: run nothing else on the server meanwhile.
