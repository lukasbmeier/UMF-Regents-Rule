---
paths:
  - "game/regents/**"
  - "server/src/game/regents.rs"
  - "server/src/genre/regents/**"
  - "server/build/regents.rs"
  - "server/tests/regents.rs"
  - "shared/content/regents/**"
  - "sidecar/npc/brains/regents/**"
  - "docs/regents_rule/**"
---
# Regent's Rule's standing rules (Luke's decisions; `GAME.md` has the full list and dates)

- Scale is 100-300 CCU per database, one seamless world. Design every per-player cost for 300.
- The skilling loop comes first, then fun combat. Every skill is dual-mode: tap E works AFK, hold E
  plays its minigame for AFK x 1.25 x score and 1.3x rares. Those numbers are hot rules
  (`game/regents/content/rules/regents.tres`, `regents.*`), never constants.
- No tool slot: the best matching tool in the bag is used. Five equipment slots: weapon, head, chest,
  legs, trinket. The weapon you hold is your class (its kit).
- Mana is on the Staff only (Luke reversed the one-pool decision on 2026-10-20); a resource never
  ticks (#270). Melee is paced by its combo and the roll, the bow by its arrows.
- No global cooldown: each ability has its own; the cast queue only buffers a press. Melee never
  rolls to hit; the bow and the Staff do.
- Mastery: XP stored, rank from a content curve (v1 ranks 1-10, abilities at 1/3/6/9); harder nodes
  need a gathering rank AND a tool tier.
- Items: three grades; Power is the number; a trait changes how an item plays and never its Power,
  and every trait trades (#275, `LOOT_AND_STYLES.md` §2, §6). Materials and modular gear:
  `docs/regents_rule/MATERIALS.md` (2026-10-23; crafted items hold Common 1 / Fine 2 / MW 3 traits, picked).
- The server judges every swing, round and roll from inputs; the referee (sidecar) runs the foes.
- `chunk` comes to the template's positional tables in the template 1.0 reshape, not a side table:
  never add a chunk side table here.
- The client has RING interest (`game/regents/regents_net_config.tres`, PROGRESS step 22). A new table of
  ours that describes a placed thing: `world_id` and an indexed `chunk` (set at insert: `place_of`,
  `chunk_of_entity`; an event `cell::chunk_of(pos)`), moved in `follow_place` if it follows an entity, listed
  in the net config's `cell_tables` (and `follow_tables` when a player's) and in `genre.tres` `world_tables`.
  The regents suite fails a table with a chunk that is not a cell table.
- The continent (level 21, PROGRESS step 23) is GENERATED: never hand-edit `continent.tscn`, its
  `continent_cells/` or `terrain/`; change `continent_shape.gd`, `build_continent.gd` or the map and run
  `build_continent.tscn` (it bakes too), then publish. Its node and skeleton placement is a TEST one: Luke's
  own replaces it. The glade (level 20) stays the suites' level and a fresh database's.
- Still open, Luke's to decide (never default): #12 day/night, the other skills' minigames, how the
  minimap grows, what is still open in `MATERIALS.md` §11. The order of work: `GAME.md`. (#7 loot and #22 handles are settled:
  `GAME.md`.)
- The weapon and tool GRIPS (`*_grip.tres`, `*_grip_preview.tscn`) are Luke's to fix himself: never
  restore, rewrite or commit his edits to them; ask.
- A content change publishes (`tools\publish.cmd`): the server takes content from the bake.
