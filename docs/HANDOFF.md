# Handoff — UMF Template, 2026-10-30 (a Skyrim-size world's worth of bots: 1.5.0-1.5.5)

## Where it stands
**1.5.5** (DECISIONS #290-#294) on 1.4.1: committed and pushed. Pulled into Regent's Rule; shipped to Fishing,
Fowl Play, DiscGolf with `ship_template.sh` (each republished `--codegen`: 1.4.0 added a table). Their suites:
Fishing unit 3053, integration 850; Fowl Play unit 2557, integration 1136, chase 28, nest 17, hunt 13; DiscGolf
unit 2347, bots 15, all green; this suite's integration in DiscGolf fails 22, against 32 before the ship (its
round plan, interact and bodies sections: DiscGolf's to look at, its HANDOFF). Suites here: unit 2272/0 (the ground bake, the ring's world filter and the
still-frame drop each failed by a negative), integration 644/0, e2e 11/0, ring 15+47/0, sidecar 13/0,
regions 25/0, native 92/0, `tests/load/test_load.py` 33/0.

## This session (from Regent's Rule's 300 bots on a Skyrim-size world, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`)
- 1.5.0 (#290): `LevelInfo.bake_ground`; the load test spreads bots over a level's land (`tools/load/level.py`),
  cuts region referees where they live, `LOAD=<name>`, `WATCH`/`PLAYER=1` (watch and join), each referee's
  frames/cores/memory, judged by `module_busy_pct` 80 and the tick's mean 25; `tests/referee_sweep.sh`;
  `GenreModule.cell_tables`.
- 1.5.1 (#291): ring cell queries are `chunk = N` alone (SpacetimeDB narrows no conjunction: the tick's update
  111 → 19 ms spread out); another world's rows kept back in `SpaceTimeSync._emit_row`, a world change replays.
- 1.5.2 (#292): the movement tick passes still rows before any lookup; cuts weigh the level's NPCs (`npc_kinds`);
  the registry's orphan warning once a minute.
- 1.5.3 (#293): walk-map bakes one at a time; a level's bounds found once (it searched every node per brain ask).
- 1.5.4/1.5.5 (#294): `NpcWorldView` indexed by kind (THE referee cost: every think searched every node); a
  still frame for a body at rest dropped; a referee builds and advances no animation trees. Four referees on
  the 37 km2 world at 300: frame p95 145 → 26-30 ms, memory flat ~1 GB each (it had climbed ~5 MB/s each).

## Next, in order
1. Two of four region referees on Regent's expanse stall their main thread ~30 s just after their skeletons
   bind (the server drops them for idle timeout; they reconnect). Not animation, not walk-map reads. Find it
   (a probe of `_process`/`_physics_process` parts, as in `REFEREE_SCALING.md`, during the binding).
2. A region referee loads the whole level (~375 MB static on the expanse): load only its cells and terrain.
3. The server at 300 spread out: 77-89 % busy (the tick 7.3 ms + its update 18 ms, 20 Hz). Design levers #289.
4. Template 1.0 milestone A's last measurement (OR'd ring query against nine one-cell ones): note #291 first,
   an OR is not narrowed either.

## Waiting on Luke
- The per-player bandwidth budget; the server's levers at 300 (#289).
- Whether a referee may step NPCs and think less often when idle (it is most of a busy referee now).

## Watch out
- Heredocs through the Bash tool turn `\r`/`\t` in text into control characters: write patch scripts with the
  file tool (`chr(92)` for a backslash) — the HANDBOOK had a mangled path from it.
- A ring now hears another world's rows in its cells and drops them in `SpaceTimeSync`: a component that reads
  the SDK cache directly (`find_rows`) can still see them; filter by `world_id` there.
- The load suite wipes the test database several times: run nothing else on the server meanwhile.
