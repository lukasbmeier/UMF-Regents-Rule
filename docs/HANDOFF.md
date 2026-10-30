# Handoff — UMF Template, 2026-10-29 (night: the referee at 300 players; 1.2.2, 1.3.0, 1.4.0)

## Where it stands
**1.4.0, region referees** (DECISIONS #288) on top of **1.3.0** (#287) and **1.2.2** (#286): committed and
pushed. Pulled into Regent's Rule (local merge commits there); NOT shipped to Fishing, Fowl Play, DiscGolf
(`ship_template.sh` not run since 1.1.1: each has its codegen debug dump uncommitted, Luke's). 1.4.0 adds a
table: each game republishes `--codegen` (data kept).
Suites here: unit 2260/0; integration 644/0; sidecar 13/0; bodies 20/0 + 10/0; regions 25/0 (a keeper that
never lets go fails 4); native 92/0; `tests/load/test_load.py` all green.

## This session (all from Regent's Rule's load test, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- **1.2.2 (#286)**: a referee subscribes only what it reads (`SidecarMain.referee_feed`; `GenreModule.
  referee_tables`, `*` by default; `SpaceTimeComponent.also_reads`), never `input_queue`; reading an unasked
  table is an error in its log. The integration suite reads the feed from the bots' referee's log.
- **1.3.0 (#287)**: the brains' world view once a think period (not every tick); NPC tiers behind
  `foundation.npc_tiers` (off; 200 / 400 m / 30 s); FIXED: the view never knew who the players were.
- **1.4.0 (#288)**: region referees (`--region`, `--border`, `--hand-on`, `--name`), `npc_driver` +
  `drive_npcs` + `offer_region_referee`, `RegionKeeper`, `RefereeRegion` (clipped to the level's bake bounds;
  no cell asked for until the world's level is known), `InterestManager.set_region`; the load test's
  `referees` split; `tests/regions_test.sh`. HANDBOOK "Several referees for one big world", AGENTS verify loop.
- Measured on Regent's continent: one referee 19.5 ms p95 at 100 bots, breaks at 200; four region referees
  hold at 300 (21 ms p95 the worst of them; the server's tick 46 of 50, its reducers' wait 47.6 of 50).

## Next, in order
1. Ship 1.2.0-1.4.0: `bash "../ship_template.sh" "1.4.0: region referees"` once Luke commits the games'
   debug dumps; each game republishes `--codegen` and runs its unit suite and its referee suites. Fowl Play
   and DiscGolf keep `referee_tables = *` (their brains read genre tables) until they list theirs.
2. The SERVER is now the ceiling at 300 (tick 46 ms, reducer wait 47.6 ms of 50): `prune_action_events`
   scans the whole `action_event` table every time (4 ms at 300); `work_tick` 2.4 ms (Regent's); then the
   reducers' queue.
3. Genre cell tables are asked for whole by a region referee (its config has the foundation's cell tables
   only): give the sidecar the game's net config's `cell_tables`.
4. Template 1.0 milestone A's last measurement (OR'd ring query against nine one-cell ones).

## Waiting on Luke
- The per-player bandwidth budget (`client_kb_per_s_p95`): ~120 KB/s at 300 dense; his home upload is
  39 Mbit/s (fits ~30-40 dense players), so 300 means a rented host.
- Fowl Play's `powers_playtest.sh` eagle check is stale (the eagle rests), not the template.

## Watch out
- A referee errors on any read of a table it does not subscribe: a component's `also_reads`, a genre's
  `referee_tables`.
- Region referees are static rectangles the operator gives; they must cover the world between them.
- SpacetimeDB on Windows answers on the 15.6 ms timer: round trips p95 ~15 ms whatever the load.
- The load suite wipes the test database several times: run nothing else on the server meanwhile.
