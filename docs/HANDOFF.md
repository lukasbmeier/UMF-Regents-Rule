# Handoff — Regent's Rule, 2026-10-30 (the server at 300, read right: template 1.4.1)

## Where it stands
- Template **1.2.2, 1.3.0, 1.4.0, 1.4.1** merged here (local merge commits, not pushed); template pushed.
- This game's own work from 2026-10-29 and today's docs are **uncommitted** (PROGRESS step 24 lists it).
  Published to the play database `regents-rule` (1.4.1, code only, data kept): restart the game.
- Suites green: integration 1084/0 (its count moves with rolled loot and registered referees), the load test
  at 100 and 300; 2026-10-29: genre unit 2716/0, native 35/0, combat playtest 51/0, `load_300.sh` to the end.

## This session
- The load test misread the server (template #289): every call counted twice (a call is a Reducer and an
  Update transaction), p95s guessed inside 1/5/10/50 ms buckets. Now exact means and the module's busy %.
- Read right at 300: `prune_action_events` 2 ms/s and `work_tick` 5 (no fix needed); the movement tick 438.
- Template 1.4.1: the tick reads each world once a tick; its code halved; the module 76 → 68 % busy at 300.
- What is left is SpacetimeDB's subscription fan-out (~2/3 of the module): `REFEREE_SCALING.md`, "The
  server at 300, read right"; gzip measured (stays).

## Next, in order
1. Luke's call on the levers below; then judge `module_busy_pct` in the load test instead of the p95s.
2. One "net stall" (0.5-0.8 s gap in a referee's rows) at the 50 and 100 steps, ~30 s after each referee
   starts: unexplained (`REFEREE_SCALING.md`, "What is left" 2).
3. Ship 1.2.0-1.4.1 to Fishing, Fowl Play, DiscGolf once Luke commits their debug dumps.
4. The combat overhaul (Luke, from `COMBAT_CURRENT.md`).

## Waiting on Luke
- The server's levers at 300 dense: how dense a real crowd is (the test is a town everywhere, ~47 seen each),
  the cell size (64 m), how often others' movement is written (20 Hz), `input_batch_size` (3).
- His playtest of the 10-29 changes (foes sleep far from players; the "cut short" refusal; no roll in air).
- Where 300 is hosted (home upload fits ~30-40 dense players) and the per-player bandwidth budget (~120 KB/s).
- The recorder in an MMO; `FoeDef.lose_sight_ms` 2500 (mine). Still open: SpacetimeAuth client id; trait ranks; #12.

## Watch out
- Never kill all Godot/Python processes (it would take Luke's editor too): stop a stuck run by its PID.
- Read the load report's server table by its means and busy ms/s, not its p95s.
- A referee errors on any read of a table it does not subscribe: `also_reads`, or `genre.tres` `referee_tables`.
- The load test's numbers are this PC's: the server, four referees and six bot processes share it.
