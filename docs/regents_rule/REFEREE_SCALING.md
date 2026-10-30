# The referee at 200+ players: what was measured, and what each fix buys (2026-10-29)

Luke asked (2026-10-29): measure what each of the five ways to keep the referee up at 200+ players actually
provides, then go with the best first. This is the record: the method, the numbers, and the order of work.

## The method

`game/regents/tests/load_300.sh` (the template's load test, #284, on the continent, level 21): guest bots in
steps of 50, 100, 200, 300 walk cell to cell over an 8 x 8-cell square (512 m) round the spawn; a third swing
the Copper axe's combo (judged by the referee), a third gather AFK, a third only walk
(`game/regents/load_bot.py`). Each step settles 15 s, then is measured for 60 s. The server, the referee and
the six bot processes all ran on this one PC.

The referee was given TEMPORARY timers (reverted after): every 10 s it logged its main thread's milliseconds
a second in each part, and the rows a second it received by table. The parts:
- **apply**: the SDK applying received rows and every handler they fire (the decoding itself runs on the
  SDK's worker thread);
- **brains**: the 51 skeletons' brains (think and frame);
- **foe writes**: `AuthoritySync`, writing the foes' movement back to the server each tick;
- **judge**: judging swings (`ActionReferee`);
- **bodies**: flying arrows and missiles (none in this test: ~0).

Five configurations:
| run | what it models |
|---|---|
| **full** | today's referee |
| **walk** | today's referee, bots only walking (`LOAD_BOT_PLAY=0`): the feed without the play |
| **thin** | the referee subscribed only to what it reads (7 core tables + its own), no `input_queue`, no genre tables: option 2, fewer tables |
| **region** | thin, and only a 5 x 5-cell region round the spawn (39 % of the bots' area, 5 of the 51 foes): options 1 and 3, a referee for a part of the world |
| **commit** | thin, with the fighters standing for each swing's committed part (as a real client slow-walks): the server's tick |

## The numbers

Referee frame p95, ms (the limit is 50):

| bots | full | walk | thin | region |
|---|---|---|---|---|
| 50 | 37 | 30 | 31 | **7** |
| 100 | 127 | 124 | **35** | **7** |
| 200 | 120 | 129 | 147 | **14** |
| 300 | 90 (*) | 122 | 146 | **16** |

(*) misleadingly good: at 300 the full referee was drowning. It received 5,700 rows a second where about
43,000 were sent, 4,700 of them `input_queue`, and only 900 of the ~7,000 movement rows: it judged against
positions seconds old.

Where its main thread went (ms a second; a second has 1,000):

| run, bots | apply | brains | foe writes | judge | rows a second received |
|---|---|---|---|---|---|
| full 50 | 174 | 178 | 77 | 28 | 8,130 (input_queue 6,000) |
| full 100 | 332 | 170 | 76 | 35 | 14,120 (input_queue 11,230) |
| walk 100 | 332 | 223 | 79 | 1 | 14,400 |
| thin 100 | 125 | 222 | 74 | 45 | 3,030 |
| thin 200 | 230 | 301 | 77 | 91 | 4,940 |
| thin 300 | 308 | 286 | 62 | 125 | 5,880 |
| region 300 | 118 | 94 | 18 | 108 | 3,230 |

The server's movement tick p95 (its budget is 50 ms):

| bots | full | walk | commit |
|---|---|---|---|
| 200 | 9.5 | 8.6 | 8.6 |
| 300 | 45 | 9.7 | **23.6** |

Per player on the wire: 34 KB/s at 50, ~80 at 200, ~120 at 300 (all runs alike: the ring is the players').

## What it says

1. **80 % of what the referee was sent it never used.** `input_queue` (every player's raw inputs, which only a
   referee that MOVES the players replays; this one does not) was 6,000 of 8,100 rows a second at 50 bots and
   would be ~36,000 at 300. With it gone (thin), the referee holds at 100 (35 ms against 127). The skeletons
   fought as before (65-99 hits judged a run): nothing it does needed it.
2. **What a referee is responsible for, not how many players there are, is its cost.** The region referee
   (5 foes, 39 % of the bots) held at every step, 16 ms at 300. Its brains fell from 286 to 94 ms a second
   and its foe writes from 62 to 18: those are paid per NPC, and paid for every NPC, whether a player is near
   or not.
3. **Applying rows costs ~50 microseconds a row** on the referee's main thread (thin 300: 308 ms for 5,880
   rows). It grows with what it is sent.
4. **Judging is ~1 ms a swing** (thin 300: 125 ms for ~113 requests a second): a sixth of the referee at 300.
   The region referee still judged EVERY swing in the world (108 ms): swing requests are not split by cell
   yet.
5. **The server's tick at 300 was half the bots' fault**: running through a swing at full speed, every frame
   was clamped and corrected. Standing for the committed part (as a client does) took it from 45 to 23.6 ms.
   The rest is real and comes with play (9.7 ms walking): `prune_action_events` scans the whole
   `action_event` table (4.1 ms at 300), `work_tick` 2.4 ms, and every reducer waits behind the others (wait
   p95 44.5 ms at 300).

## What each option buys

| option | what it is | measured gain | cost |
|---|---|---|---|
| **2a, fewer tables** | the referee subscribes only what it reads; no `input_queue` in a referee | holds at 100 instead of 50; −75 % rows at 100 | a config change in the foundation (`sidecar_main.gd`, the referee's tables) |
| **2b, thinner movement** | a compact position feed at 10 Hz for the referee | about half of **apply** (~150 ms/s at 300) | a side table the server writes every tick (server cost) |
| **1, interest round its work** | a referee asks for the cells round what it is responsible for | (as region, when its work is in part of the world) | the building block of 3 |
| **3, region referees** | each referee one region of cells (and a border), running everything there | **holds at 300 with room to spare** (16 ms) | foundation work: authority per region, handing a foe or a body across a border, swings routed by cell |
| **4, the server judges basic melee** | basics judged in the module, from rows (range, cone) | ~1 ms a swing off the referee (~16 % at 300) | moves the work to the server, which is the tighter of the two now; no walls on the server |
| **5, cheaper rows** | a native (GDExtension) row decoder and applier | most of **apply** (~40 % of the referee at 300); and the PLAYERS' clients, which apply ~3,900 rows a second at 300 too | the largest piece of work; a native build per platform |
| **NPC tiers** (design §6.1) | a foe with no player near sleeps: no brain, no writes | most of **brains** and **foe writes** (~350 ms/s at 300 here) | foundation + genre: waking, and the referee's interest following it |

## The order of work (best first)

1. **2a, fewer tables** (template): no input queue in a referee, only the tables it reads. No cons; the
   biggest single gain. Then the load test again.
2. **NPC tiers, and no write for a foe that has not moved** (template, then the genre): the brains and the foe
   writes are half the referee at 300, and they grow with content, not players. Without it every new camp
   makes every referee slower.
3. **3 on 1, region referees** (template milestone): each referee asks for its region's cells (option 1) and
   runs everything in them: brains, bodies, judging (swings routed by cell). The one option that scales with
   the world as content grows, because a new system's work lands in the region it happens in.
4. **Then measure again**, and only then: **5** (cheaper rows) if one region's referee is still tight, and it
   also helps every player's frame rate at 300; **2b** if one more cut is needed; **4** as a combat-overhaul
   design choice (who judges basics), not for the referee's load.

And on the server's side, separately: `prune_action_events` should not scan the whole table every time (an
index by time, or prune a little each time); then look again at the reducers' wait at 300.

## Caveats

- One machine for everything: the bots took ~6 cores. A real host with the bots elsewhere does better.
- The region test is one region of a split, not a split: it shows the cost of a referee's share, not the
  border hand-off.
- The temporary timers are reverted; `LOAD_BOT_PLAY=0` and the committed swing stay in the bots' hook.

## After fixes 1 and 2 (template 1.2.2 and 1.3.0, DECISIONS #286, #287; measured 2026-10-29 night)

Built: **(a)** a referee subscribes only what it reads (its own tables, what its entity scenes' components
declare, each genre's `referee_tables`, the recorder's when recording), never `input_queue`; reading anything
else is an error in its log. Regent's Rule lists none of its own tables (`genre.tres` `referee_tables` empty):
37 tables. **(b)** the brains' world view is built once a think period (100 ms), not every physics tick, and
NPC TIERS (RULE_DESIGN §6.1) are on here: a foe with no player within 400 m for 30 s sleeps until one comes
within 200 m. On the continent 24 of the 51 skeletons slept (their camps are far from the bots' square).

Found on the way: the brains' view had NEVER known who was a player (the `player` table is keyed by identity
and was looked up by entity id), so `players` was always empty; with tiers on, every foe slept. Fixed in the
template; Regent's combat playtest is the proof (it fails with the old lookup).

Referee frame p95, ms (limit 50), `load_300.sh` as before:

| bots | before | thin (a alone, earlier) | a + b |
|---|---|---|---|
| 50 | 37 | 31 | 31 (and one 1.2 s stall, the first walk-map tiles: the step's verdict) |
| 100 | 127 | 35 | **19.5** |
| 200 | 120 | 147 | 118 |
| 300 | 90 (stale) | 146 | 147 |

Where its main thread goes at 300 now (ms a second, from temporary timers, reverted):

| apply rows | brains: view / think (of it paths) / frame | foe writes | judging |
|---|---|---|---|
| 273-353 (~5,000 movement rows a second) | 60-80 / 70-115 (12-68) / 7 | 62-74 | 105-138 |

So: 100 players hold with room on one referee. Past that, everything left grows with the PLAYERS in what
the referee watches: rows applied (~55 µs each), the view (every entity, ten times a second), the swings
judged. That is what a region referee divides, so **fix 3 (region referees) is next**, and the measurement
confirms it is the one that scales. Memory: the referee peaked at 1.4 GB at 300 bots (680 MB at 100; the
continent and its walk maps are ~600 MB of it), about 1.2 cores busy; the server 600 MB.

## After fix 3, region referees (template 1.4.0, DECISIONS #288; measured 2026-10-29, late)

Built in the template: several referees for one world, each for a rectangle of cells (`--region`), watching a
cell round it, asking only for its cells (one query a column, clipped to the level's bounds), running the
NPCs and bodies standing there, judging its own people's swings. The module keeps who drives each NPC
(`npc_driver`), so one walking over an edge is handed on 8 m past it and never driven twice; a referee that
dies loses its NPCs after 5 s. `tests/regions_test.sh` proves the hand-off on a real server. Here
`shared/regents/load.json` now runs the load test with four (`"referees": [2, 2]`).

`load_300.sh`, four region referees (the bots' square cut 2 x 2, the outer regions to the grid's edge):

| bots | worst referee's frame p95 | server tick p95 | reducer wait p95 | per client KB/s p95 |
|---|---|---|---|---|
| 50 | 6.9 | 4.8 | 7.8 | 35 |
| 100 | 6.9 | 7.7 | 11.7 | 53 |
| 200 | 6.9 | 40.9 | 46.2 | 86 |
| **300** | **16.2** | 46.0 | 47.7 | 121 |

**300 holds.** Each referee ~620 MB (the continent is most of it) and ~0.6 of a core at 300; four together
~2.5 GB and ~2.4 cores. Foes crossed between the two regions that meet at the spawn and were handed on
(8 and 9 times in one run), with nothing refused that is not play.

Found and fixed while measuring: a region to the grid's edge asked a query for each of its 513 columns,
~7,700 a referee; four of them queued the server's reducers 260 ms at 50 players. Now clipped to the level's
bake bounds (22-23 columns here), and nothing is asked until the world's level is known.

**What is left, in order:**
1. **The server is now the ceiling**: its movement tick (46 of 50 ms) and its reducers' queue (47.7 of 50)
   at 300. First `prune_action_events`, which scans the whole `action_event` table every time (4 ms at
   300), then `work_tick` (2.4 ms), then the queue itself (one module, one thread). Bots and the server share
   this PC: a host with the bots elsewhere has more room, but not 2x.
2. Steps 50 and 100 still report ONE "net stall" each (a 0.5-0.8 s gap in a referee's rows while they were
   flowing), with one referee as with four (1.2 s at 50 in the single-referee run): each referee about 30 s
   after it starts. Not yet explained; it is why those two steps say BREAKS while their frames are 6.9 ms.
3. Genre cell tables (`wielded`, `combat_state`, ...) are asked for whole by a region referee (cheap at 300:
   ~50 rows a second each).

## The server at 300, read right (template 1.4.1, DECISIONS #289; measured 2026-10-30)

**The tables above misread the server.** SpacetimeDB times each call as two transactions, the reducer and the
subscription update after it, and the load test added the two together: every call was counted twice and the
two times were mixed. Its p95s were also linear guesses inside the server's buckets (1, 5, 10, 50 ms). So
"tick 46 of 50" only said "between 10 and 50", and "`prune_action_events` 4 ms" said "a few calls between 1
and 5". The report now gives exact means from the histograms' sums, each reducer's subscription update on
its own, how much of every second each reducer held the module (`busy ms/s`), and how busy the module was
(it runs one reducer at a time: 100 % is the ceiling).

Read right, 300 bots, four region referees (`STEPS=100,300 MEASURE=45`):

| | module busy | `tick_movement` ms/s (its code + its update, a tick) | `submit_input` | `write_movement_batch` | `use_ability_seen` | prune / work_tick |
|---|---|---|---|---|---|---|
| before (1.4.0) | 76 % | 438 (~6.4 + ~15.3 ms) | 136 | 95 | 55 | 2 / 5 |
| after (1.4.1) | **68 %** | 372 (3.2 + 15.3 ms) | 132 | 92 | 51 | 2 / 4 |
| after, bots on no compression | 61 % | 327 (3.2 + 13.1 ms) | 128 | 75 | 47 | - |

At 100 bots: 29 % busy before, 25 % after. Round trips at 300 went from 11.2 to 7.9 ms at the median (p95
34.5 to 28.8), "input sent to processed" p95 from 80 to 75.5 ms.

- **The prune and `work_tick` needed nothing** (2 and 4-5 ms a second). The movement tick's own code made
  ~13 lookups a player a tick; it now reads the world's rows once a tick, and its code halved (3.2 ms a tick).
- **What is left is SpacetimeDB's**: the subscription updates (each moved row sent to everyone whose cells
  see it: 300 players, each seen by ~47, 20 times a second) are about two thirds of the module's time. Gzip
  is a small part of that (no compression: 14 % less update for 2.2 times the bytes, 122 to 271 KB/s a
  player), so it stays.
- **The levers left are the game's** (Luke's): how dense players are (the test puts 300 in 8 x 8 cells, a
  town everywhere), the cell size (64 m: a player sees the 3 x 3 round them; 48 m would see ~0.56 as many
  others), how often others' movement is written (20 Hz), and `input_batch_size` (3: each player calls
  `submit_input` 20 times a second, 128 ms/s of the module at 300).
- The load test's limits still judge the bucketed p95s (50 is a bucket's edge, so they can hardly break);
  `module_busy_pct` (reported) is the one to judge, once agreed.

## A Skyrim-size world: 300 players spread out (template 1.5.0-1.5.4, DECISIONS #290-#294; 2026-10-30)

Luke (2026-10-30): "try it on a world close to the same size as skyrim with 300 players to see if there is a way
to test how many refs I need and simulate that many bots with me playing a local user as well". Worried about
running several referees on his machine.

**The world**: the EXPANSE (level 22, PROGRESS step 25), the continent's map at 3.7 times its width: 8.3 x 11.1
km, **36.9 km2 of land** (Skyrim's is about 37), the continent's test placement at the same density (10,245
nodes, 220 skeleton camps, **660 skeletons**). 300 bots spread over its land: a fifth in a town round the spawn,
the rest anywhere, each roaming 8 cells round home, walking on the ground's height (`load_expanse.json`).

**What it found, in order** (each a fix; the first run had the server's queue at 99,000 operations):

| found | where | fix | measured |
|---|---|---|---|
| every connection compared each of 10,400 node points with every node spawned (100 M string compares) | `regents.rs` `populate` | hash sets | a connect 275 ms → under 1 |
| the ring's cell queries `world_id = W AND chunk = N` are not narrowed by SpacetimeDB; spread out, every player's 9 cells are its own (~2,700 a table) and every moved row was checked against all | template `cell_query` | `chunk = N` alone; another world's rows kept back where they arrive (#291) | the tick's subscription update 111 → 19 ms; a referee write's 55 → 7 |
| the movement tick read every entity of the world (12,000) and asked of every still row whether a player drives it | template `tick_world_module` | still rows passed before any lookup (#292) | the tick's own code 16.9 → 7.3 ms |
| region cuts by players alone: one referee of four got 328 of the 660 skeletons | the load test | cut by players and the level's NPCs (`npc_kinds`) (#292) | 148-177 skeletons each |
| every awake camp's walk-map tile read the level on the main thread and baked at once | template `NpcNav` | one bake at a time, read when it starts; the level's bounds found once, not by searching 20,000 nodes on every brain's every ask (#293) | (the brains' share below) |
| a skeleton idle in camp was stepped 60 times a second and written 20; every NPC's pose worked out every frame | template movement component, animation driver | a still frame for a body at rest dropped; a referee poses nobody (#294) | foes' writes ~1,000 → 146 in a 30 s window; ~250 MB a referee |
| **the brains' world view held every movement row the referee had (~3,000 nodes in a region) and every skeleton's every think searched them all for the nearest player** | template `NpcWorldView` | indexed by kind; unchanged rows not decoded again; statuses from their rows (#294) | **referee frame p95 145 → 24-27 ms; its memory flat (it had climbed ~5 MB a second, a referee too far behind to keep up)** |

300 bots, four region referees, after all of it (`expanse_watch.sh`, measured, then two minutes watched):

| | worst referee frame p95 | the referees' cores, memory | the module | round trips p50 / p95 | per player |
|---|---|---|---|---|---|
| first run | 147 ms (two never reported) | 3.9, 4.9 GB and climbing | 100 % busy, queue 99,000 | 5-43 s | - |
| after #294 | **27 ms** | 3.7 cores, **4.1 GB flat** (~1 GB each) | 77-89 % busy | ~32 / 75 ms | 17 KB/s, 2.4 others seen |
| after 1.5.5 (no trees in a referee) and the bot fixes | **30 ms** | 3.9 cores, **4.0 GB** (700-730 MB static each) | 78 % | 38 ms p95 | 24 KB/s p95 |

With 1.5.5 every limit holds at 300 except **referee net stalls** (7, worst 834 ms): two of the four referees
(regions 1 and 2) lose their connection once or twice in the first minutes. The server closes the socket for
idle timeout, which means the referee's main thread did nothing for 30 s, and this happens just after the last of
its ~170 skeletons binds. They reconnect, rebuild their NPCs and carry on; the other two never do it. Ruled out:
the animation trees (1.5.5), walk-map reads (1.5.3, one tile at a time). Not yet found: the next to look at.

**What a referee costs on this world**: about 1 GB of memory (the level whole is ~375 MB of it: every referee
loads all of it) and ~1 core when its region is busy. Its frames grow with the skeletons awake in its region,
not the players (150 bots woke as many as 300: spread out, players come within 200 m of most camps).

**What is left** (in order):
0. The two referees' 30 s main-thread stall after their skeletons bind (above): what blocks, and fix it.
1. The server: 77-89 % busy at 300 spread out (the movement tick 7.3 ms + its update 18 ms, 20 times a second).
   The design levers (#289) are unchanged; the per-player bandwidth is 17 KB/s here (spread) against 120 dense.
2. A region referee loads the whole level (~375 MB static of its ~1 GB): loading only its region's cells and
   terrain would save a few hundred MB each.
3. The skeletons' brains (the genre's `foe.gd`) and the movement step are what a busy referee spends now; the
   combat overhaul is the place to set how often an idle foe thinks.
