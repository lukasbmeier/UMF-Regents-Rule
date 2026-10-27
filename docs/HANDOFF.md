# Handoff — Regent's Rule, 2026-10-27 (the continent playtest's dropped connection found and fixed; NEXT: the load test)

## Where it stands
- **The continent playtest is GREEN again**: 22/0 headless (27 s), 23/0 windowed (`WINDOWED=1`), its new
  discovery and M checks included. Regents unit suite 2661/0. Committed (this session's commit, after
  `b06fdd0`); not pushed unless the closing note says so.
- The fix is client-only (`game/regents/ui/world_map.gd`): the play database `regents-rule` needs no
  republish (still on the continent, level 21, published with codegen 2026-10-26). Restart the game to get it.
- Template 1.1.1 is pulled here; NOT yet shipped to the other games (the template's HANDOFF).
- Not run this session: integration, accounts, skilling, combat (nothing they cover changed).

## This session
- **The cause of the "dropped connection"**: not the network. Opening M froze the main thread ~90 s per
  call, so the client answered no keep-alive and the server closed it for idle (30 s).
  `RegentsWorldMap.icons_of` looked up each node point's content with `ContentLibrary.items`, which lists the
  content folders and loads every piece on each call. That ran 545 times on the continent but only 38 in the
  glade. Now the node defs are listed once per call, through `RegentsContent` (the genre's cache);
  `node_named` uses it too.
- Found by timing the playtest's steps: the 181 s gap sat between "M opens" and the next step. Restarting the
  local `spacetime start` changed nothing; no bisect was needed.
- New unit check (`game/regents/tests/suites/regents.gd`, `_run_polish`): the continent's icons in under 2 s,
  every node known. With the per-point lookup put back it FAILS (19.6 s).
- PROGRESS step 23, "The world map", records it.

## Next, in order
1. **The load test harness** (Tuesday after 5 pm), in the TEMPLATE: a light bot client, many connections in
   one process; 50 -> 100 -> 300; rows and bytes a second, reducer p95, the referee's lag, cell swaps.
   Note #1 (the referee's stalls) is for it.
2. Before or with it: ship template 1.1.1 to the other games (the template's HANDOFF).
3. The combat deep-dive: the LMB spam cut, foes pathing round obstacles (#4), a server refusal of a roll
   in the air, the cast queue.

## Waiting on Luke
- His look: the Lunge whole; bushes passable (and are the shadows near them still odd?); does "Player 39"
  still show (if so: where he walked from, and whether it was the body or only its name).
- M, the world map: built (2026-10-26); his look at it on the continent.
- Still open: the SpacetimeAuth client id (`shared/game.json` `sign_in`); trait ranks; #12 day/night.

## Watch out
- **`ContentLibrary.items` / `find` rescan and reload every content file on each call** (right for the
  editor and the bake). In game code use `RegentsContent.items`; never call either per point, per row or
  per frame. Other direct callers remain (workbenches, `material_table.gd`, `make_ore_layouts.gd`: tools
  and once-at-load, fine as they are). A foundation-level cache would be a template change.
- The local `spacetime start` was restarted by this session (log `%TEMP%\spacetime_server.log`, the old one
  `spacetime_server.old.log`, 27 MB). If it is down next time, start it again.
- The playtest log prints `[Nameplate] nameplate: 39 = Player 39` for the CLI's player; the test still
  finds it hidden as a tool. A lead for #7 if Luke still sees the name.
- `continent_playtest.sh` polls the CLI every 3 s for the whole run; `continent.tscn` and its cells are
  generated (never hand-edit); a game's hot-rule override is every client's and referee's default too.
- Older traps: Terrain3D's region grid; rebuilding the continent is a ~16 MB diff; `TaskStop` leaves a
  suite's children running; the CLI referee is online only 5 s after its claim.
