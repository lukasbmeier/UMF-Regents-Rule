# Handoff — Regent's Rule, 2026-11-04 (everything committed and shipped; foes stop at rocks: PROGRESS 36)

## Where it stands
- **Committed and pushed** (Luke's go, 2026-11-04): steps 26-35 (`f27e0924`), template 1.7.1 + 1.7.2 merged
  (`b9c16b49`), then step 36 (this session's walls). The template is pushed too, and shipped to Fishing, Fowl Play
  and DiscGolf (each republished `--codegen`, unit suites green, pushed).
- Play database `regents-rule`: republished at the end (content manifest; data kept; no `--codegen` needed). Restart
  the game and its referee.
- Last runs: unit 3138/0; `game/regents/tests/walls_playtest.sh` 16/0 (and its negative fails 4); integration
  1268/15 with NO host running (so the host was not the cause): the same CLI-timed referee family as last session's
  20 and 25 (the overhead's cancel race cascading, mana regrown between calls, the Frost Ring after it) plus "the hold
  tick runs while something is held". Not run: cargo (no server change), the skilling and combat playtests.

## This session
- Shipped: template 1.7.1 (#303) and 1.7.2 (#304) committed, pushed, merged into all four games (`ship_template.sh`).
- Fowl Play's gate half ran in its own session: bot hens open a shut gate, predators shoulder it open (Fowl Play
  `d54407e`, its `gates_test.sh` 19/0).
- Fishing: its copies of two foundation checks updated (`game/fishing/tests/suites/`): 3147/0. DiscGolf 2441/0.
- **#8196 fixed here**: `sidecar/genres/regents.gd` sizes each rock (its model's meshes x scale), tree (trunk:
  `NodeComponent.TRUNK_RADIUS`/`TRUNK_HEIGHT`) and station (body + pieces) for the referee; `node.tres` Blocks In =
  [Normal]. Tests: the regents suite's `_run_referee_walls`; `walls_playtest.sh` (a real referee, bot round copper
  rock 20 in the glade, through it once worked out).

## Next, in order
1. Luke: restart the game; spar by a copper rock, a tree, the anvil: the skeleton should go round.
2. Luke's answers to `ARMOUR_PREP.md` (A1-A6 start the build); then build it by its §4 order.
3. Watch the continent under load: a node worked out or back re-bakes its 256 m walk map tile (1 s after, at most
   every 5 s a map, one at a time). Run `load_300.sh` once and look for `[Sidecar] a walk map ... again` piling up.
4. Harden integration's referee checks (`game/regents/tests/hooks/integration_genre.sh`): 15 fail with no host; start
   at "the overhead is cancelled" (the rest cascade from it), then the hold tick (a foundation check: template?).

## Waiting on Luke
- `ARMOUR_PREP.md` A1-A10.
- From before: poise's numbers and whether players get poise (A2 (d) ties in); the tutorial's words; PROGRESS 30's
  "Not Luke's" list; a loot table with swords; which foes are bosses.

## Watch out
- The template's walk-map read warns "parsed RenderingServer meshes at runtime" (`NpcNav._source_with_walls`, once per
  area, kept): harmless in the glade; a template look if the continent's reads are slow.
- `walls_playtest.sh` is laid out in the glade's own placement (copper rock 20 at (23, 14)): moving the glade's nodes
  moves its lane; it checks the rock is there first.
- A `-s` SceneTree script in this project starts a referee of its own (an autoload): stop both by PID; time things
  inside the unit suite instead.
- The foundation's `content` check "a script runs from the repo root" is flaky under load (600 headless frames).
- `RegentsContent` caches in a running game: a test that writes content must use `ContentLibrary.root_override` or
  call `RegentsContent.clear()`.
- A published table is never removed (`poise` stays declared); the integration CLI is slow; never run two server
  suites at once; never kill all Godot/Python processes, by PID only.
