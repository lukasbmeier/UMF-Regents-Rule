# Loot, items, combat styles, spells, summons, crafting

The owner's decisions of 2026-10-20 (workshopped outside, then checked against the code). **The
amendments below override the body where they differ**; the body follows, as the owner gave it.

## Amendments (owner, 2026-10-20, after the agent's review)

1. **Grades are bands of quality, not three steps.** Quality stays a 0-1000 number on the item (the
   minigame round sets it, and it moves damage and tool speed a little per point). Common / Fine /
   Masterwork are bands of it (cut points hot), for the colour, the name and the trait count. Power is
   derived from tier and quality.
2. **Durability and repair: kept as an option**, not "never". `ItemDef.durability` is optional and a
   rule switches wear on; built after the loot work. (This doc's §9 said no durability; RULE_DESIGN
   §7.4 had it as the material sink. The option keeps both open.)
3. **Mana on the Staff only**, through a generic resource. This **reverses RULE_DESIGN #2** (one pool
   for every kit): melee is paced by its combo and the roll, the bow by its arrows.
4. **Every trait trades.** Today's handle traits (oak: quality, yew: speed) are pure gains and get a
   cost side.
5. **Melee always lands what it reaches**: no hit roll, only armour reduces it (and may block a weak
   hit). **Ranged rolls to hit**: the bow and the Staff (Bolt) at a target, the chance falling with
   distance and a moving target, and later an accuracy-vs-evasion pair. (Answers §11 question 2.)
6. **No global cooldown**: each ability its own cooldown, MOBA-style. The cast queue is only input
   buffering: a press during another ability's cast or recovery is held (one deep, the latest replaces
   it, a roll clears it) and fires the moment that ends, re-checked on the server. (Answers §11 question 1:
   not built yet; today the server refuses and the client holds the press.)
7. **Controls stay as they are**: roll on Ctrl, abilities on **Q E R F**, LMB tap the light combo, LMB
   hold the heavy, RMB the block (the bow: RMB lets the draw go). Each weapon's combo length is its
   content (dagger 2, sword 3, axe 4...), and its last step may be a finisher.
8. **Answers to §11 questions 3 and 4**: bodies already report every contact (a list; each reaches the
   genre); pierce is a flag plus a small referee change so the body passes through someone it has hit.
   Quality has no named grades today: it is the 0-1000 number of amendment 1.

**Order** (§10 with two additions): grade bands and Power; loot tables with personal rolls (and the
damage tally per attacker they need: today the killing blow takes everything); ground items (template);
the Staff with mana and the server-side cast queue; icons alongside.

---


Answers to the agent's questions of 2026-10-20, one decision per question with its because, cost flagged (S / M / L), and "undecided" where that is the honest state. Everything generic here (ground items, loot tables, grades, traits, resource, telemetry) is **template** work: it must serve any game, not only this one. Constraints stand: the server decides everything; content is data; numbers are hot rules.

This closes three items the design doc had left open: **#2 resource** (mana, on the Staff only, via a generic resource), **#3 unlock placement** (weapon mastery ranks 1 / 3 / 6 / 9), **#7 loot** (personal rolls). Record them in `DECISIONS.md`.

---

## 0. Vocabulary (use these words in code, content and UI)
| Word | Meaning | Lives on |
|---|---|---|
| **Tier** | the material / design level: iron, steel, mithril. Sets the power band. | `ItemDef` (fixed) |
| **Grade** | how well made this one is: **Common, Fine, Masterwork** (three in v1; collapse any extra existing quality steps into these). Moves within the band. **This is the colour.** | item instance |
| **Frequency** | how often a thing drops: a chance on a loot-table line. Never stored on the item. | loot table line |
| **Power** | one number per item combining tier and grade. The only thing a player needs to compare. | derived, shown on every card |
| **Trait** | a qualitative modifier that changes how an item plays and **never changes Power**. | item instance (0 / 1 / 2 by grade) |
| **each** | a loot container where every line rolls independently. Default. | loot table |
| **one-of** | a loot container where exactly one line wins; lines carry absolute percentages; the remainder is nothing. | loot table |
| **Personal roll** | the server runs a foe's table once per contributing player; results are that player's. | loot engine |
| **Pity** | a per-player, per-table counter on one line that raises its odds after misses and resets on a hit. | `drop_pity` |

Tier **strictly dominates**: every steel item beats every iron item; grade decides among steel. No band overlap. Power example (hot numbers):

| Power | Common | Fine | Masterwork |
|---|---|---|---|
| Iron | 10 | 12 | 14 |
| Steel | 16 | 19 | 22 |
| Mithril | 25 | 29 | 33 |

Names read "Fine Steel Axe"; the border is the grade colour; the number is Power; traits are italic lines. Nothing is ever called "4.1".

---

## 1. Ground loot and dropping
| Question | Decision | Because | Cost |
|---|---|---|---|
| Bag, corpse window, or ground? | **Ground**, as a template system: `ground_item{stack, pos, chunk, owner, owner_until, despawn_at}`. Loot lines may say `to_bag: true` (currency, writ items), which keeps today's into-the-bag path. **No corpse loot window.** | Ground items serve every game (foe drops, node drops, player drops, Chain Reaction's pads). A corpse window is UI plus corpse persistence and nothing reusable. | **M** |
| Can players drop? Can others pick up? | **Yes, both.** `drop_item` makes a ground item owned by the dropper with the same timing as a kill drop. | A trade path without building a trade window; friends-scale risk accepted. | S on top |
| Who may loot, how long, groups? | **Personal rolls.** Every contributor (≥ 5% of damage, hot) gets their own run of the table. Each result is **visible only to its owner for 60 s** (RLS), then **public for 60 s**, then despawns (120 s total, hot). No need/greed, no round robin, no master looter. | No ninja looting, no loot UI, works with strangers at a lair, and the pity counter is naturally per player. | S |
| 3D models or a generic bag? Despawn? | **Generic sack with a grade-coloured glow**; `ItemDef.world_model` is an optional override later. Boss drops land in a chest `node` with a 10 min life. | One model and one shader; rows stay cheap. | S |
| Icons | **Rendered from the 3D model at workbench intake** (offscreen viewport, fixed camera and light, cached PNG). The UI overlays the grade border and a small trait badge; **Power is on the card** with a green/red delta against the equipped item. | Zero per-item art; consistent across packs and games; content-as-data needs it. | **M once** |

## 2. Rarity vs the quality we already have
| Question | Decision | Because | Cost |
|---|---|---|---|
| Same thing or separate axis? | **One visible axis: grade.** "Rarity" as a colour *is* the grade. "Rarity" as how-often is a line frequency, not an item property. Tier is the third word and it dominates (§0). Drops roll a grade from a **distribution on the loot line**, using the engine crafting already uses. | The quality system exists and already makes one axe better than another. A second axis doubles balancing and tooltips for no new play; Albion-style fog comes from overlapping axes, so there is no overlap. | S |
| Random affixes or fixed items? | **Fixed items with pooled traits.** No random affixes, now or planned. | Affixes (Diablo: 1–6 random modifiers with random ranges from a pool of hundreds) need a stat system where anything can modify anything, generated tooltips and endless balancing. Traits are hand-authored, bounded, and are what handles already are. | avoids **L** |
| Can crafted match or beat dropped? | **Yes.** All standard gear is craftable to Masterwork (skill rank, minigame round, tool grade and input grades shift the grade roll). Drops reach the same grades by luck. The only exceptions are **uniques** (`unique: true`, boss-only, not craftable; grade rolls from the boss line's distribution) and **recipes that drop**. | OSRS-shaped: most gear is made, the few best things are found, so gathering and smithing stay relevant forever. Rare components raise the *tier* of what you can make, never the grade; the grade is the smith's. | S |
| Traits (how many, where from) | Count by grade: **Common 0, Fine 1, Masterwork 2** (a hot dial; 1 / 1 / 2 is the alternative). **Crafted items choose traits through components** (handle carries the first, fitting the second — today's handles system); **dropped items roll** from the `ItemDef`'s pool. Rule for every `TraitDef`: **it trades or it is situational, never a pure gain.** | A pure-gain trait becomes mandatory within a week. Component-chosen traits make a smith someone you ask for a *specific* axe. | S–M (modifier atoms, §6) |

## 3. Loot tables
| Question | Decision | Because | Cost |
|---|---|---|---|
| Per-foe, shared, nested? | **Nested, two container kinds.** A table is a list of lines; a line is an item or another table (that is all "nested" means). **`each`** (default): every line rolls its own chance; several can drop; adding a line changes no other line. **`one-of`**: exactly one line wins; designers type **absolute percentages** (10 / 20 / 30 / 40), the **bake computes the conditional cascade** (10%, 22.2%, 41.7%, 100%) and a **lint fails if shares exceed 100**; the remainder is nothing. A foe's table composes shared tables (`undead_common`, `currency_small`) plus its own lines. | This is the dilution problem from the loot-design short, solved at the tooling layer: new commons never lower rare rates, a hot-disabled line's share goes to "nothing", and nobody computes 30 / (0.9 × 0.8) by hand (the cascade's known trap). | S |
| Guaranteed drops | A line at **100%** inside an `each`. No flag. | Falls out of the container. | — |
| Pity (bad-luck protection) | On lines marked `pity`: `drop_pity{player, table, line, rolls_since}`; effective chance = `base × (1 + rolls_since / N)`, hard guarantee at `K` rolls; `N`, `K` hot (e.g. 1/200 base, N = 200, K = 1,000); reset on hit; per player per table. | A dozen lines of code; the 3,000-kill dry streak cannot happen; expected kills barely move. | S |
| Rare drops to everyone or each? | **Each contributor rolls independently.** A unique can land for two of four. | Your odds per kill are the same solo or grouped, so there is no reason to avoid groups and nothing to argue over. Circulation rises with group size; if a market ever exists, lower the per-player chance (one hot number). | — |

Reference example (the agent's test fixture):
```
warden (each):
  bones           100%   to_bag
  marks            80%   → one-of: 5 marks 50%, 10 marks 35%, 15 marks 15%
  undead_common   100%   → each: rusted dagger 10%, tattered cloth 25%, bone shard 40%
  warden_recipe     2%   pity, N = 200, K = 1000
```
Four players kill the Warden: the server runs this **four times**. Anna: bones hit (bag); marks hit, inner one-of gives 10 (bag); dagger misses, cloth hits, shard hits (two sacks on the ground, owner-only for 60 s); recipe at 2% × (1 + 150 / 200) = 3.5% misses, her counter becomes 151. Ben's run is separate: his recipe roll hits, his counter resets. Adding `cracked skull 15%` to `undead_common` changes nothing else.

## 4. Combat styles
| Question | Decision | Because | Cost |
|---|---|---|---|
| Classes or weapon? | **The weapon decides** (standing). Third style for this slice: **Staff** (a caster). Spear, mace, dagger, greataxe later as content. | Three kits to balance, not nine classes; already the template's position. | — |
| Mage resource | A **generic `resource` system** on the template (`ResourceDef{name, max, regen_in_combat, regen_out}`), **attached only to the Staff as mana** for now (`kit.resource` is optional). Melee and bow stay cooldown-only. **Reagents** come later as an optional `reagent_cost` on any ability (consumes a bag item). | One system; the two existing kits don't need rebalancing today; reagents are a cheap later hook that ties gathering to combat and is the natural cost for summons and utility spells. | S now, S later |
| Casting while moving | **Per ability**: instants and casts under 0.8 s may move; longer casts root and are cancelled by movement (`cast_while_moving` flag). | Keeps the chain fluid, gives big spells a tell. | — |
| Projectiles, instants, areas | **All three, on what exists**: **Bolt** = targeted basic with the bow's server-rolled hit chance; **Fireball** = a body (as arrows are) with a splash applied on its hit report; **Frost Ring** = a ground circle resolved **in the module** by a scheduled reducer against position rows at fire time (1 s delay); **Blink** = module-validated teleport (walkable mask, max 8 m). | No new authority machinery for the slice; referee rewind for aimed abilities is a later refinement, not a prerequisite. | **M** (the Staff kit as a whole) |

## 5. Spells vs abilities
| Question | Decision | Because | Cost |
|---|---|---|---|
| Different system? | **No.** A spell is an ability with a `cost` and a `school` tag (UI, sound). | One pipeline for players and foes is the whole point. | — |
| Utility spells (teleport, enchant, alch) | **Same system**: two new targeting kinds (`ITEM` = a bag slot, `FAR_POINT`) and new effect atoms (`teleport_to{shrine | point}`, `add_trait{trait}`, `transmute{item → marks}`), plus a **spellbook UI** for `school: utility` abilities that never sit on the bar; utility casts give skill XP. Order: **teleport first** (shrines + reagents), **enchant second** (a crafting step cast as a spell), **alch undecided** until the economy pass (it is a price floor under every item). | Magic becomes a profession, not only a damage type; each spell is one atom. | S each |
| Where do skills come from? | **Weapon mastery rank: 1 / 3 / 6 / 9** unlock the kit's four abilities. `unlock_source` is a content field (`rank | item | trainer`) so books and trainers can be added without code. | The agent needs numbers; the field keeps the door open. | S |
| How many on the bar? | Basic (LMB), **four** kit abilities (1–4), dodge (Shift), one consumable slot (5). | Four is what a kit has. | — |
| Bow skill shots | **Aimed Shot** = charged body; **Volley** = module ground circle; **Disengage** = self-impulse (`push` row); **Piercing Arrow** = an arrow body with `pierce: true` that reports every contact. | Bodies already report what they hit; piercing is a flag, not a system. | S each |

## 6. Traits (new section; the data for §2)
- **`TraitDef{id, name, applies_to tags, modifiers[]}`**; modifier atoms the pipeline reads: `ability_mod{tag, field, mult}`, `on_hit{chance, effect}`, `conditional{condition, stat_mod}`, `status_mod`, `tool_mod`. Traits never touch Power or the stats view's base numbers.
- v1 pools (content; every number hot), each a trade or a condition:

| Trait | Pool | Gives | Costs / condition |
|---|---|---|---|
| Balanced | weapons | basics recover 15% faster | abilities −10% damage |
| Heavy | melee | heavies and the combo's last hit **stagger** (interrupt a cast) | basics 15% slower |
| Keen | weapons | crits apply Bleeding 3 s | crit chance −3% |
| Brutal | weapons | +25% damage below 30% HP | −10% above |
| Reaching | melee | +0.5 m range | recovery +10% |
| Thirsting | weapons | 5% of basic damage as HP | healing received −15% |
| Swift Draw | bow | draw 20% faster | projectile 15% slower |
| Hunter's | bow | +15% vs beasts | −15% vs humanoids |
| Padded | armour | impulses move you 25% less | sprint 5% slower |
| Warded | armour | Burning / Slowed on you 30% shorter | Stunned 15% longer |
| Gentle | tools | depletion chance halved | rounds 15% longer |
| Lucky | tools | 10% chance of an extra yield roll | depletion ×1.3 |
| Prospector's | tools | 5% rare component per success | base yield −1 |
- **Cost**: the atoms and `TraitDef` are **S–M**, right after the slice, since handles already exist and need something to carry.

## 7. Weapon viability (standing principles, so the agent builds the atoms with them in mind)
1. **Equal DPS at equal Power is the baseline, not the goal.** At Power 19: sword 19 / 0.8 s, greataxe 38 / 1.6 s, dagger 9.5 / 0.4 s. Tier scales Power only; speed, reach, stagger and cleave belong to the weapon *type* and never change with tier.
2. **Abilities scale from per-hit damage, not DPS**, so slow weapons are the burst kits by construction.
3. **Foes ask different questions**: flat armour per hit (favours heavy hits), percent armour (favours status stacks), interruptible casters (favours stagger), swarms (cleave), kiting (reach, projectiles), low-HP fodder (fast, less overkill). Encounter content must carry all of these or we have rebuilt the scimitar.
4. **Pareto check in CI** (on the existing balance sim, **M**): every weapon type at equal Power against a fixed dummy set (bare, flat armour 5, percent armour 30%, three-target swarm, interruptible caster, 20-HP fodder), traits off. Fail the build if any weapon is top-two in every column or top-two in none; print the table.
5. **Live meta telemetry** (**S**, owner priority): a scheduled reducer rolls `hit` rows (attacker, ability, kind, at) joined to the activity (overworld / lair / dungeon / duel) into `meta_share{hour, activity, weapon_type, share}` hourly; queryable live, dashboarded, with a hot alarm threshold (45%). Same rollup for trait share, kit share and time-to-kill by foe. All of it is already in the database; this is one reducer and one table.
6. **Make slow feel good**: hitstop, stagger animation and sound on heavies; fast weapons win on feel alone otherwise.

## 8. Summoning
| Question | Decision | Because | Cost |
|---|---|---|---|
| What, how many, how long? | Summons are **NPCs with a brain owned by a player**. Cap by **points, not count**: a `summon_cap` stat from kit and mastery (e.g. 6) buys one 6-point greater summon, two 3-point, or six 1-point imps. Spell summons are timed (60 s); a later pet kit is until-slain. Despawn on owner logout. | Reuses `BrainDef` and spawning; the mass-summon build exists as a mastery choice instead of being forbidden. | **M** |
| Controlled, or own brain? | **Own brain with three commands** (attack my target, follow, stay) for the greater summon; small summons take no commands and share a **pack brain** (the wolves' mechanism). | Direct control is a second predicted entity per player and a camera/control swap — the expensive version. | avoids **L** |
| Dies? Targetable? | Yes and yes: HP, statuses, a corpse like any foe. Small summons die individually. | Anything else is special cases through the whole pipeline. | — |
| MMO fit, PvP | CPU: a swarm costs roughly one brain. Rows are the real cost, so a swarm is **one entity on the wire**: a single row with the leader's position, a formation id and a member-HP array; clients and the referee derive member positions deterministically from the formation; hits resolve against members. **Until that exists, cap summoned bodies at three.** Duel: attackable by the opponent, dies when the duel ends; contested zone: carries the owner's flags. | Six imps then cost what one wolf costs; load is bounded by `summon_cap` per player. | **M** (swarm entity) |
| When | **Not in this slice**; after reagents, since a reagent is the right cost for a summon. | — | — |

## 9. Crafting gear
| Question | Decision | Because | Cost |
|---|---|---|---|
| Crafted vs only dropped | **All standard gear is crafted.** Drops give materials and components, currency, consumables, recipes (rare), and uniques (boss). | Follows from §2. | — |
| Do drops feed crafting? | **Yes**: raw components on tables (bone, sinew, ore) and **salvage** at a station (`ItemDef.salvage_yield`, scaled by grade). | One reducer; every drop is worth picking up. | S |
| Repair / durability? | **No durability in v1.** `durability` reserved as an optional field. | A decrement per hit, UI, a repair reducer and a vendor sink, for a problem we don't have. | avoids **M** |

## 10. Order
**This slice**
1. Vocabulary in data and UI: three grades, tier dominates, Power on every card with the compare delta, grade colours (S).
2. Loot tables: `each` / `one-of`, bake normalisation + lint, pity, personal rolls per contributor; the Warden fixture above as the test (S).
3. Ground items: table, drop and pickup, sack + glow, visibility windows, despawn sweep (**M**). The foundation piece of the slice.
4. The Staff kit with the generic resource and four abilities on existing machinery (**M**).
5. In parallel: icons rendered at intake (**M once**).

**Next** (in this order): trait atoms + `TraitDef` + the v1 pools; meta telemetry rollup; salvage and components; reagent cost hook; teleport spell; Pareto check in the sim; enchant; summons with points cap (bodies capped at three); the swarm entity.

**Undecided**: alch (economy pass); trainers and books as unlock sources (field exists, no content).

**Never, or not until a reason appears**: random affixes (**L**), corpse loot window (**M**, nothing reusable), player-controlled summons (**L**), durability (**M**).

## 11. Questions back to the agent
1. Does the **cast queue** from the design exist (one queued ability, re-validated at fire time), or do abilities still gate on animation only? It changes how "Balanced" and the Staff's chain are tuned.
2. Is the bow's **server-rolled hit chance** meant to stand for all targeted basics? Owner leans yes: make hit chance a stat pair (accuracy vs evasion) and use it for Slash and Bolt too.
3. Can **bodies report multiple contacts** today? That decides whether `pierce` is a flag or a job.
4. How many **quality grades** exist now, so we know what collapsing to three touches.
