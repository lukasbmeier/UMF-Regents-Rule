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
- One 100-point resource pool, the same rules for every kit, named by the kit; nothing ticks (#270).
- Mastery: XP stored, rank from a content curve (v1 ranks 1-10, abilities at 1/3/6/9); harder nodes
  need a gathering rank AND a tool tier.
- Items: three grades; Power is the number; a trait changes how an item plays and never its Power,
  and every trait trades (#275, `LOOT_AND_STYLES.md` §2, §6).
- The server judges every swing, round and roll from inputs; the referee (sidecar) runs the foes.
- `chunk` comes to the template's positional tables in the template 1.0 reshape, not a side table:
  never add a chunk side table here.
- Still open, Luke's to decide (never default): #7 loot, #10 hosting, #12 day/night, #22 handles and
  kits, the other skills' minigames.
- A content change publishes (`tools\publish.cmd`): the server takes content from the bake.
