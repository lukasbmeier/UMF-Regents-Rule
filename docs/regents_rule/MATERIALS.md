# Materials and modular gear (the deep-dive, owner 2026-10-23)

Luke's decisions of 2026-10-23, after the agent's proposal and an outside spec
(`modular_harvesting_and_tool_crafting_spec.md`, taken in part: what was kept and what was cut is
below). **This doc wins over `RULE_DESIGN.md` §7.4 and `LOOT_AND_STYLES.md` where they differ**, and
over `GAME.md`'s 2026-10-21 Traits call on one point: a handle's trait no longer always applies (§4).

## 1. The shape in one paragraph
Every tool and weapon is a PATTERN (an axe, a sword, a bow) assembled from PARTS in slots. One slot is
the CORE: its material sets the tier, and the tier sets Power (tier dominates, as before). Every other
slot is SECONDARY: its material carries a trait, a sideways choice that never touches Power. Parts come
from different skills (mining and smithing, woodcutting, herbalism and creature drops), so every item
needs more than one skill. Materials are content (`MaterialDef`); the bake makes every material x part
cell a real item, so the bag, loot lines, stacks, the tool picker and Power work as they do now.
Raw materials never have qualities; quality is made at the anvil and the workbench.

## 2. Data: a generated table (decision 1)
- **`MaterialDef`**: key, name, tier, the families it serves (metal, wood, fibre, hide...), its look
  (colour, metallic, roughness: one model per pattern, recoloured), and the trait it carries when it is
  a secondary part, per rank.
- **`PatternDef`**: what is made (axe head, sword blade, handle, binding; the assembled axe), its kit or
  tool tag, speed and reach (the TYPE's, never the material's: `LOOT_AND_STYLES.md` §7.1), its smithing
  outline, and for an assembled pattern its SLOTS (§3).
- **Make the table** (`MaterialTable`; built in step 1, PROGRESS step 17) crosses them into items and
  recipes with ids of their own, written as ordinary content files and marked (`ItemDef.material` /
  `pattern`, `RecipeDef.from_table`), so the bake, the server and the client need nothing new. It sets
  only the table's fields (names, tier, Power, tool, part, trait; a recipe's inputs, station, output) and
  keeps the designer's (colour, looks, words; a recipe's XP, rank, time, quantities, round). Any one cell
  may be written by hand (`by_hand`). The ids already in players' bags (iron axe head 40014, iron axe
  40015, oak handle 40016...) are kept: today's files ARE the cells. The bake refuses a table out of date.
- **A Materials bench** (a genre workbench): the table as a grid, each cell's Power, tier overlaps
  flagged, the pattern's model in the material's look.
- **Trait ranks are a third axis of the table** (a rank II oak handle is its own item), so nothing about
  a rank is stored per row.

## 3. Parts: open-ended slots (decision 2)
- A pattern lists its slots; **head, handle, binding is the usual three**, not a fixed number. A slot
  says which families it takes, whether it is required, and whether it is the core. An optional fourth
  (an oil, an enhancement) or a complex weapon needing five parts is a pattern with more slots, not code.
- **Melee and tools**: metal core (the head or blade); wood handle and binding secondary.
- **Bows and staves** (decision 5): WOOD core (a yew bow is the tier-3 bow); metal (copper imbued into
  the tips, a ferrule) and the binding are the secondary parts. Same machinery: the core is whichever
  slot the pattern marks as the core.
- Bindings: fibre from herbalism, hide and sinew from creature drops. Copper rivets are the plain binding
  (no trait). No Hunting skill and no separate grip slot (the spec's fourth part is cut).
- An item's `instance_data` grows add-only keys: its parts (`"p"`), the traits chosen (`"t"` as now),
  their ranks, and its gear XP. Old rows (`{"q","h","t"}`) read as before.

## 4. Traits on crafted items: the grade gives slots, the player chooses (decision 3a)
- **A crafted item holds traits by grade: Common 1, Fine 2, Masterwork 3** (hot rules). This REPLACES
  "a handle's trait always applies": a Common axe holds one trait, from whichever part the player picks.
- **The player chooses** which of the parts' traits fill the slots, at assembly. The station must show
  plainly how many slots this grade gives and which traits are in use and which are not.
- Drops keep their own rolled counts (Common 0, Fine 1, Masterwork 2).
- Every trait, at every rank, still trades (#275's bake refuses a pure gain).

## 5. Trait ranks: the material sink (decision 3b, durability stays parked)
- A secondary part's trait comes in **ranks I, II, III**. Rank sets how strong the trait is; grade sets
  how many traits an item holds.
- Raising a rank costs **bulk base material** (the spec's 5 / 40 / 150, hot), **a catalyst** (§6) and
  **gear XP** (§7). Low-tier materials stay wanted forever, because ranks are paid in them.
- Durability and repair stay an option, switched off.

## 6. Catalysts from the rank gap (decision 4)
- Working a node whose required rank is well below yours can yield a catalyst: an uncommon one from
  about **+3 ranks** over the node, a rare one from about **+6** (hot: production ranks go past 10).
  The gem and the bird's nest become the first ones (mining and woodcutting).
- **Normal depletion**: a high-ranked player depletes a low node as anyone does.

## 7. Gear XP, now (decision 7)
- An item earns XP as it is used (a weapon's hits that land, a tool's rounds worked), kept in its
  `instance_data`. **It gates the rank upgrade**: a trait rises to rank II or III only on an item used
  enough. It never touches Power.

## 8. The slice's ladder (decision 6)
| Tier | Metal (cores of melee and tools) | Wood (handles; cores of bows and staves) |
|---|---|---|
| 1 | Copper (the starter "bronze" tools are renamed copper) | Logs (Tree) |
| 2 | Iron | Oak |
| 3 | **Steel** = iron + **coal** (a new rock, an ingredient only) | Yew |
Tiers 4-6 and their names (a new setting: not Runite or Mithril) come later.

## 9. From the outside spec: kept and cut
- **Kept**: core vertical and the rest sideways; each part from a different skill; low-tier parts useful
  forever; catalysts from the rank gap; bulk-material rank upgrades as the sink; no raw qualities.
- **Cut**: traits that only give (Deep Grain, Heavy Cleave, Seeker's, Field-Mended); durability-shaped
  traits (until durability); ticks, carry weight, stamina; automation (walking to the next node,
  refining on harvest, banking); one-swing felling of low nodes (shared nodes: griefing); the
  instability budget (a third number set; revisit if low parts go unused); the 4th part and Hunting;
  its 1-99 numbers (ours are ranks 1-10).

## 10. Order of work (proposed; each step playable)
1. **Built 2026-10-23 (PROGRESS step 17)**: `MaterialDef`, `PatternDef` with slots, Make the table;
   today's hand-written items re-expressed as cells with their ids pinned. Nothing a player sees changes.
2. **Built 2026-10-23 (PROGRESS step 18)**: copper as tier 1 (the starters are copper's cells, ids kept),
   the pickaxe patterns, coal and its rock, steel as tier 3 (its bar a cell by hand).
3. **Built 2026-10-23 (PROGRESS step 20)**: assembly with slots: the station rework (slots shown, the grade's
   trait count, the player's pick; several part slots a recipe; `craft_choosing`).
4. Bindings from fibre and drops; bows and staves with a wood core.
5. Gear XP on the item; trait ranks and the upgrade recipe (bulk + catalyst + XP).
6. Catalysts from the rank gap (the gem and the nest first).
7. The Materials bench.

## 11. Luke's answers (2026-10-23) and what is still his
- **The bindings' traits** (revised after his playtest): METAL RIVETS NOW. Each part offers a tool trait and a
  weapon trait: oak Steady / Heavy, yew Springy / Balanced, copper rivets Gentle / Thirsting, iron Lucky /
  Brutal, steel Prospector's / (Keen, with crits). Fibre wraps and oils, and their traits: with herbalism.
- **Changing an item after assembly** (revised after his playtest, the same day): **swap a part at the
  workbench**, at a cost (the new part, the old lost, bars of the head's metal); traits re-picked within the
  grade's room. The head and quality never change.
- **Where trait ranks come from**: both a better-made part (a higher start) and upgrades through use are
  liked; open until the minigames are harder (Masterwork not routine) and AFK crafting still pays.
- **A dropped or given item keeps its traits, their ranks and its gear XP**: a player may level an item and
  hand it to a friend, or sell it for more for the hours put in.
- **Gear XP per rank, and what earns it**: hot rules, starting from base numbers (to be set when step 5 is
  built), tuned live.
- **Names for tiers 4-6, the fibres and the hides**: with herbalism.
