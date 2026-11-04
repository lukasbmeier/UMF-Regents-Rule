# Before armour: the road, and the decisions that are yours (2026-11-03)

Luke, 2026-11-03: armour is the next new content piece ("yeah I like armor being next"), planned first in a prep
session as `ROLES_PREP.md` was for roles: the slots, stats, armour weight and what it costs, crafted armour's
traits. Each decision below has options and a recommendation. **Nothing here is built until you answer**; your
answers go to `GAME.md`, then this sheet becomes the build's order of work (§4).

What is already settled (yours, `GAME.md`): **five equipment slots: weapon, head, chest, legs, trinket** (#15, no
tool slot); **melee never rolls to hit, only armour reduces it** (`LOOT_AND_STYLES.md` §1.5); items have three
grades and a Power, a trait changes how an item plays and never its Power, every trait trades (#275); crafted gear is
a generated table of materials x patterns, its core sets the tier, secondary parts carry traits, Common 1 / Fine 2 /
Masterwork 3 traits picked by the player (`MATERIALS.md`); armour weight was left "until the slots arrive"
(`COMBAT_OVERHAUL.md` §8); show, don't name.

Today, for scale: a player has **100 HP**; a skeleton's hits are 14 (rusted cut) to 34 (crushing overhead); the
sword's string is 8 / 10 / then 14-26 for its last hit. Only the weapon slot exists (`wielded`).

---

## 1. The road to armour

| | what | needs |
|---|---|---|
| 1 | **Your answers to §2** (A1-A6 are enough to start; A7-A10 can follow) | you |
| 2 | **Wearing**: a server side table for what each player wears (head, chest, legs, trinket), `wear`/`take_off` reducers, the bag's paper doll; the hit's damage reads it | A1, A6 |
| 3 | **Armour as content**: armour patterns in the material table (a helm, a chestpiece, leggings), their cells in copper / iron / steel, a defence number per cell, made at the anvil and assembled at the workbench | A2, A3, A4 |
| 4 | **Weight and its cost** | A2 |
| 5 | **The look**: the worn pieces drawn on the body (the Quaternius outfits share our skeleton) | A5 |
| 6 | **Armour traits** (Padded, Warded, and the parts' third trait) | A4 |
| - | Later, not in this piece: armour on drops (with the loot-table pass), foes' own armour (the combat triangle), the trinket's content (with herbalism and creature drops), durability (parked) | |

Steps 2-3 are playable on their own (wear an iron chestpiece, take less from a skeleton). Nothing in the combat
deep-dive's steps 5-7 waits on armour, but threat (step 6) reads better once a guard grip can wear real weight.

---

## 2. Armour decisions

### A1. What armour does to a hit (the core stat)
- **(a) Recommended: DEFENCE, the design's formula.** Each piece has a Defence; worn pieces add up; a hit becomes
  `damage x 100 / (100 + defence)` (`RULE_DESIGN.md` §4.3). It never reaches zero, each point is worth a little less
  than the last, and it is one number a tooltip can say ("takes 23 % less").
- (b) Flat reduction per hit (minus 5 a hit). Favours heavy hits over many small ones; a skeleton's rusted cut
  would lose a third, its overhead a seventh. Good as a FOE trait later (`LOOT_AND_STYLES.md` §7.3), harsh as the
  player's whole defence.
- (c) Both: Defence on every piece, flat reduction as an armour trait.

**A1.1** Does the parry or block apply before or after armour? (Recommend: the guard first, then armour on what
gets through: a full block's 25 % is then cut again.) **A1.2** Do foes get Defence too, as a number on `FoeDef`?
(Recommend: yes, 0 for today's skeletons; armoured foes come with foe design.)

### A2. Armour weight, and what it costs
The overhaul left this to the slots. Every piece has a weight; the pieces you wear add up.
- **(a) Recommended: three weights by what it is made of, the cost on your MOVEMENT.** Cloth (light), leather
  (medium), metal plate (heavy). More weight = more Defence, and a cost you feel: the roll's cooldown longer and its
  distance shorter, sprint a little slower. No cost on damage (so a damage player is not pushed out of armour).
- (b) The cost on your stamina or a resource. There is none: mana is the Staff's only (your 2026-10-20 call).
- (c) No weight: each piece is just its Defence by material tier. Simplest; armour becomes a pure stat stick and
  every player wears the best.
- (d) Weight buys POISE for players (heavier = harder to stagger), which answers "whether players get poise too",
  still waiting on you from the poise look. Can sit on top of (a).

**A2.1** First numbers to argue with (all live rules): a full metal set +25 % roll cooldown, roll 15 % shorter,
sprint 8 % slower; leather half that; cloth nothing. **A2.2** Show, don't name: the bag shows a weight bar and what it
does ("your roll: 1.25 s"), not the words Light / Medium / Heavy? (Recommend: the bar and the effect line; the
item's name says what it is, "Iron chestpiece".)

### A3. What armour is made of, first
Cloth needs fibre (herbalism) and leather needs hide (creature drops); neither exists yet.
- **(a) Recommended: metal first.** Copper, iron and steel plate pieces, from the materials we have: the anvil
  smiths the plates (a round of shape, as a blade), the workbench assembles the piece. Leather and cloth arrive with
  herbalism and creature drops, which brings weight choices.
- (b) Wait and build all three weights together (after herbalism): nothing to wear until then.
- (c) Add a placeholder hide now (skeletons drop "Rotted leather"): leather early, at the cost of a material that is
  later thrown away or kept.

**A3.1** Until cloth and leather arrive, every crafted piece is heavy. Do you want weight to exist from the start
anyway (so the roll cost is felt and tuned now), or switched on with the lighter materials? (Recommend: from the
start, so the cost is tuned before there is a choice.)

### A4. Crafted armour's parts and traits
Weapons are a core (the head or blade: metal, the tier) plus secondary parts (grip, rivets: the traits).
- **(a) Recommended: the same shape, two slots now.** A piece is PLATES (the core: metal, sets tier and Defence) +
  RIVETS (secondary, the trait, as on weapons). A LINING slot (cloth or leather, a second trait) is added to the
  patterns when those materials exist: a pattern's slots are open-ended, so that is content, not code.
- (b) Three slots from the start, the lining taking wood for now (oak, yew strips): traits sooner, but a wooden
  lining is odd and would be swapped out later.
- (c) Armour is one smithed part (plates only), no secondary, so no traits until cloth and leather.

**A4.1** Every part now offers a tool trait and a weapon trait; a third, an ARMOUR trait, per material? (Recommend:
yes; the rivets' armour traits first: copper Padded, iron Warded, steel a new one, all trading as #275 requires.)
**A4.2** Grade gives trait slots (1 / 2 / 3) on armour too, picked at the workbench as for weapons? (Recommend: yes,
the same window.) **A4.3** Quality raises Defence as it raises a weapon's damage (up to +20 % at 1000)? (Recommend:
yes, one rule for both.)

### A5. How armour looks
- **(a) Recommended: the Quaternius Modular Fantasy outfits** (yours, CC0, on our 65-bone skeleton): Knight for metal
  plate (body armour, arms, legs, feet, the armet helm), Ranger later for leather, Peasant / Wizard for cloth. One look
  per piece and weight, recoloured by material (copper, iron, steel), as weapons are.
- (b) One generic look for every piece until there is art of our own.

**A5.1** Head: a helm hides the hair; show helms always, or a "hide my helm" toggle? (Recommend: always, a toggle
later.) **A5.2** The pack splits arms and feet from the body and legs: the chestpiece draws the arms, the leggings
the feet? (Recommend: yes; no hand or foot slots, the five slots stay.)

### A6. Wearing it
- **A6.1** Put on from the bag (I): click a piece to wear it, as wielding? (Recommend: yes, plus a paper doll of the
  four slots in the bag window.)
- **A6.2** May you change armour in a fight? (Recommend: only out of combat, `regen_delay_s` since your last hit, as
  re-hilting at the workbench is out of combat; a refusal says why.)
- **A6.3** Do others see your armour? (Recommend: yes; it is a public row like `wielded`, sent by the ring.)

### A7. Numbers to start from (live rules, to argue with)
Defence per FULL SET (head 20 %, chest 50 %, legs 30 % of it), at quality 500:

| set | Defence | a 34 hit becomes | a 14 hit becomes |
|---|---|---|---|
| none | 0 | 34 | 14 |
| copper plate | 15 | 30 | 12 |
| iron plate | 30 | 26 | 11 |
| steel plate | 45 | 23 | 10 |

**A7.1** Is "a steel set takes about a third off" the right ceiling for this slice? (Recommend: yes; with a full
block that is 34 to 6, so the guard stays the main defence and armour the steady one.)

### A8. The trinket
No Defence. Its content (a charm, a ring) wants herbalism and creature drops. **A8.1** Leave the slot empty in this
piece (shown on the doll, nothing to put in it), or one placeholder trinket with a trait? (Recommend: empty, filled
with herbalism.)

### A9. Drops
**A9.1** Armour on skeletons' loot now, or crafted only until the loot-table pass (already waiting on you: "a loot
table with swords")? (Recommend: crafted only; drops with that pass, rolling grade and traits as weapons do.)

### A10. Gear XP and ranks on armour
Weapons and tools earn gear XP by use, which gates trait-rank upgrades (`MATERIALS.md` §5, not built). **A10.1** Does
armour earn it by being hit? (Recommend: yes, when ranks are built; nothing to do in this piece.)

---

## 3. Not yours (the agent's calls, listed for your look)
- A new table `worn` (entity, world, chunk, a row per slot: the bag row worn), public, a cell table like `wielded`
  (add-only: old clients keep working, rule 17); a piece worn stays in the bag, marked, as a wielded weapon does.
- Defence is computed on the server from the rows at the hit (the referee never needs it); the client shows it.
- The patterns join the material table, so the bake, ids and tooltips work as they do now; armour's Defence is the
  pattern's share x the material's tier number, overridable per cell.

## 4. Order of work once answered
1. `worn` + wear / take off + Defence in the hit (A1, A6); 2. plate patterns and their cells, made and assembled (A3,
A4, A7); 3. weight and its cost (A2); 4. the look (A5); 5. armour traits (A4.1); then the trinket, drops, ranks later.
Each step: the unit suite, the native tests, the integration suite, a playtest by a real client; then your look.
