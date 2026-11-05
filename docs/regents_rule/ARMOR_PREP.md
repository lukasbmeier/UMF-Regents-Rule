# Before armor: the road, and the decisions that are yours (2026-11-03, revised 2026-11-04)

## 0. PARKED (Luke, 2026-11-04)
"It seems we may be too early for armor without more resources and content." Armor comes back after the spelling
pass, the minigame overhaul, and herbalism and hunting (`GAME.md`, "The order of work, armor parked"), when there is
cloth, leather and foes worth defending against. Two outside reviews showed why: with metal only, the armor traits
do nothing (nothing pushes, burns or slows a player) and a piece has one trait-bearing part, so Fine and Masterwork
have nothing more to pick.

**Settled now, in `GAME.md`** (no new content changes them): A1 with A1.1 and A1.2 (Defense, `regents.defense_k`,
multiplied in order, `FoeDef.defense`); A2 (no weight, no player poise); A4.3 (quality raises Defense); A5; A6;
the words (§3, as amended by §6 below); A8-A10 as recommended.

**Open when armor comes back** (start here):
1. **Parts**: plates (the core) + which secondary parts, enough of them for three traits (§6, point 3).
2. **Traits**: which, on which part. Padded and Warded likely move to the lining, alive once foes push, poison or
   slow; the metal parts want traits that work with blocks, health and regeneration (§6, point 1).
3. **Lighter armor's reason to be worn** (A2.2): the combat triangle, with cloth, leather and foes that cast.
4. **Materials and numbers**: which tiers of cloth and leather, the slot shares, K (A7, shown to a decimal).

Everything below is revision 2 as it stood when parked.

Luke, 2026-11-03: armor is the next new content piece ("yeah I like armor being next"), planned first in a prep
session as `ROLES_PREP.md` was for roles. **Revision 2 (2026-11-04)** folds in an outside review of the first
version and Luke's reply to it: the good parts taken, player poise and weight's movement cost dropped (§5 lists what
was taken and what was not). Each decision now carries a **proposed answer**; this sheet goes for one more pass,
then the answers go to `GAME.md` and §4 becomes the build's order of work. Nothing is built until then.

(American spelling from here, Luke's call of 2026-11-04.)

What is already settled (Luke's, `GAME.md`): **five equipment slots: weapon, head, chest, legs, trinket** (#15, no
tool slot); **melee never rolls to hit, only armor reduces it** (`LOOT_AND_STYLES.md` §1.5); items have three
grades and a Power, a trait changes how an item plays and never its Power, every trait trades (#275); crafted gear is
a generated table of materials x patterns, its core sets the tier, secondary parts carry traits, Common 1 / Fine 2 /
Masterwork 3 traits picked by the player (`MATERIALS.md`); show, don't name.

**Today, for scale** (checked against the content, 2026-11-04): a player has **100 HP**. A foe deals its attack's
damage x its `damage_pct` (warrior 50 %, axeman 55 %), so a skeleton's hits LAND at:

| skeleton hit | attack's damage | lands at | blockable? |
|---|---|---|---|
| Rusted cut (warrior) | 14 | 7 | yes |
| Rusted backswing (warrior) | 16 | 8 | yes |
| Hack (axeman) | 20 | 11 | yes |
| Skull splitter (warrior's last hit) | 28 | 14 | **no**: red glint, roll or take it |
| Crushing overhead (axeman's last hit) | 34 | 19 | **no**: red glint, roll or take it |

(Version 1 used the attack's damage, 14 and 34, as if it landed, and said a full block took the 34 to 6: a foe's
last hit is unblockable, so no block ever touches it.) The sword's string is 8 / 10 / then 14-26 for its last hit.
Only the weapon slot exists (`wielded`).

---

## 1. The road to armor

| | what | needs |
|---|---|---|
| 1 | **Luke's answers to §2** (A1, A3-A6 start it; A7-A10 can follow) | Luke |
| 2 | **Wearing**: a server-side table for what each player wears (head, chest, legs, trinket), `wear`/`take_off` reducers, the bag's paper doll; the hit's damage reads it | A1, A6 |
| 3 | **Armor as content**: armor patterns in the material table (a helm, a chestpiece, leggings), their cells in copper / iron / steel, a Defense per cell, made at the anvil and assembled at the workbench | A3, A4, A7 |
| 4 | **The look**: the worn pieces drawn on the body (the Quaternius outfits share our skeleton) | A5 |
| 5 | **Armor traits** (the rivets' third trait) | A4 |
| - | Later, not in this piece: armor on drops (with the loot-table pass), foes' own Defense in use (the combat triangle), the trinket's content (with herbalism and creature drops), durability (parked), lighter armor's trade (with cloth and leather, A2.2) | |

Steps 2-3 are playable on their own (wear an iron chestpiece, take less from a skeleton).

---

## 2. Armor decisions

### A1. What armor does to a hit — **proposed: (a) Defense, with a live divisor**
Each piece has a **Defense**, a whole number; worn pieces add up; a hit becomes

    damage x K / (K + Defense)        K = the hot rule regents.defense_k, starting at 67

It never reaches zero, every hit is cut by the same share (a 3-a-second burn as much as an overhead), each point of
Defense adds the same effective health (1/K of it, about 1.5 %), and it is one sentence in a tooltip: "takes 23 %
less damage". K is live, so the whole curve is tuned without touching an item.
- Rejected: (b) flat reduction per hit (minus 5 a hit) and (c) both. A flat cut erases small hits and burns, and
  hurts the sword's quick string more than the axe's two slow blows once foes wear armor. It may come back as a FOE
  trait (`LOOT_AND_STYLES.md` §7.3), never as the player's defense.
- **A1.1 — proposed: the guard first, then armor, then traits, all MULTIPLIED, never added.**
  `dealt = damage x block share x K / (K + Defense) x trait multipliers`. Adding percentages runs toward immunity;
  multiplying never does. A parry still deals 0.
- **A1.2 — proposed: yes, `FoeDef.defense` (a whole number) now, 0 on today's skeletons**, so armored foes are
  content, not code, when foe design brings them.

### A2. Armor weight — **proposed: no weight. No movement cost, no poise for players.**
Version 1 recommended weight that costs the roll and sprint, maybe buying poise. Dropped (Luke, 2026-11-04):
- **Movement cost, rejected.** Armor cuts the damage you take, and good players take little; a slower roll costs
  most the players who rely on the roll. Heavy armor would be a tax on skill, and good players would go light.
- **Player poise, rejected: poise stays a FOE mechanic.** Today's rule is readable and stays: a foe's last hit that
  lands unblocked staggers you, every time. A hidden meter would make the same hit stagger you sometimes and not
  others; showing your own poise needs a new HUD element; and it is the "spine to min-max" Luke already turned down
  (2026-10-30). Foe poise stays a tool for foe design (bosses more, rushers less).
- So armor is Defense by tier, and the choice between pieces comes from their TRAITS (A4), which always trade.
- **A2.1 — later, with duels (not now):** against being staggered again and again (two foes, or PvP), a player could
  be **Steadied** for a few seconds after a stagger, the foes' own status: yes or no, shown as a status, no meter.
- **A2.2 — later, with cloth and leather:** what makes light armor worth wearing. The lead idea: each kind stops a
  different KIND of hit best (plate against blows, cloth against spells), as RuneScape's combat triangle does; it
  needs foes that cast, so it is decided then.
- (Version 1's A2.1 numbers, A2.2 weight bar and A3.1 "weight before the lighter materials" fall with this.)

### A3. What armor is made of, first — **proposed: (a) metal first**
Copper, iron and steel plate pieces from the materials we have: the anvil smiths the plates (a round of shape, as a
blade), the workbench assembles the piece. Leather and cloth arrive with herbalism and creature drops.
Rejected: (b) wait for all three (nothing to wear until then); (c) a placeholder hide.

### A4. Crafted armor's parts and traits — **proposed: (a) plates + rivets now, a lining later**
A piece is PLATES (the core: metal, sets tier and Defense) + RIVETS (secondary: the trait). A LINING slot (cloth or
leather, a second trait) joins the patterns when those materials exist: content, not code.
- **A4.1 — proposed: yes, a third trait per material, an ARMOR trait**, on the rivets: copper **Padded** and iron
  **Warded**, as `LOOT_AND_STYLES.md` §6 already defines them:

  | trait | gives | costs |
  |---|---|---|
  | Padded (copper rivets) | knockback moves you 25 % less | sprint 5 % slower |
  | Warded (iron rivets) | Burning and Slowed on you end 30 % sooner | a stun on you lasts 15 % longer |
  | steel rivets | **open: Luke's** | |

  **Watch out:** today nothing pushes, burns or slows a player, so both do nothing yet; they come alive with foes
  that do. **A4.1b, the steel rivets' trait**, one that matters against today's skeletons. A candidate: *Braced*, a
  stagger on you lasts 25 % less, your roll's cooldown 10 % longer (it shortens the stagger without a meter).
  (The review's damage-kind versions of Padded and Warded, x0.88 / x1.12, need damage kinds, which do not exist:
  every hit today is a blow, so one would be a free 12 % and the other a pure loss. Its Buttressed and Articulated
  read poise and weight, both dropped.)
- **A4.2 — proposed: yes**, grade gives trait slots (1 / 2 / 3) on armor too, picked in the same workbench window.
- **A4.3 — proposed: yes**, quality raises Defense as it raises a weapon's damage, up to +20 % at 1000 (one rule).

### A5. How armor looks — **proposed: (a) the Quaternius Modular Fantasy outfits**
Luke's, CC0, on our 65-bone skeleton: Knight for metal plate (body armor, arms, legs, feet, the armet helm), Ranger
later for leather, Peasant / Wizard for cloth; one look per piece, recolored by material (copper, iron, steel).
- **A5.1 — proposed:** helms always shown; a "hide my helm" toggle later.
- **A5.2 — proposed: yes**, the chestpiece draws torso and arms, the leggings legs and feet; the five slots stay.

### A6. Wearing it — **proposed: yes to all three**
- **A6.1** Put on from the bag (I) by clicking a piece, as wielding, plus a paper doll of the four slots in the bag.
- **A6.2** Out of combat only (`regen_delay_s` since your last hit), as re-hilting is; a refusal says why.
- **A6.3** Others see your armor: a public row like `wielded`, sent by the ring.

### A7. Numbers to start from — **proposed: whole-number slot shares x the material's tier**
A pattern's share: **head 2, chest 5, legs 3** (a full set is 10); the material's tier: **copper x1, iron x2, steel
x3**. At quality 0 (quality adds up to +20 %; Defense is kept to a tenth, the tooltip shows the share):

| full set | head / chest / legs | Defense | takes less | overhead 19 | skull splitter 14 | hack 11 | rusted cut 7 |
|---|---|---|---|---|---|---|---|
| none | 0 / 0 / 0 | 0 | 0 % | 19 | 14 | 11 | 7 |
| copper | 2 / 5 / 3 | 10 | 13 % | 16 | 12 | 10 | 6 |
| iron | 4 / 10 / 6 | 20 | 23 % | 14 | 11 | 8 | 5 |
| steel | 6 / 15 / 9 | 30 | 31 % | 13 | 10 | 8 | 5 |

Six crushing overheads kill an unarmored player; a steel set takes eight. A blocked hack (25 % through) is 3, 2 in
steel. **A7.1 — proposed: yes, "steel takes about a third off" is the slice's ceiling** (a Masterwork steel set,
36 Defense, about 35 %). The guard stays the main defense against what can be blocked; armor is the steady one, and
the only one besides the roll against the red-glint hits.

### A8. The trinket — **proposed: leave it empty** in this piece (shown on the doll), filled with herbalism.
### A9. Drops — **proposed: crafted only** until the loot-table pass (Luke's, "a loot table with swords"); drops then roll grade and traits as weapons do.
### A10. Gear XP — **proposed: yes, armor earns it by being hit**, when gear ranks are built; nothing in this piece.

---

## 3. Not Luke's (the agent's calls, listed for his look)
- A new table `worn` (entity, world, chunk, a row per slot: the bag row worn), public, a cell table like `wielded`
  (add-only: old clients keep working, rule 17); a piece worn stays in the bag, marked, as a wielded weapon does.
- Defense is computed on the server from the rows at the hit (the referee never needs it); the client shows it.
- The patterns join the material table, so the bake, ids and tooltips work as now; a piece's Defense is the
  pattern's share x the material's tier, overridable per cell.
- The tooltip and the doll say what it does ("takes 23 % less damage"), never "Defense 20" alone or Light / Heavy.

## 4. Order of work once answered
1. `worn` + wear / take off + Defense in the hit, `regents.defense_k`, `FoeDef.defense` (A1, A6); 2. plate patterns
and their cells, made and assembled (A3, A4, A7); 3. the look (A5); 4. armor traits (A4.1); then the trinket, drops,
ranks later. Each step: the unit suite, the native tests, the integration suite, a playtest by a real client; then
Luke's look.

## 5. The outside review (2026-11-04): what was taken, what was not
**Taken:** the live divisor `regents.defense_k` (67) with whole-number slot shares x tier; multiplying, never adding,
in a fixed order; the reasons against flat reduction; `FoeDef.defense` now; one plain sentence in the tooltip; yes to
the rest of version 1's recommendations (A3-A10).
**Not taken:** player poise and weight's movement cost (§A2, Luke); the damage-kind Padded and Warded, and the
Buttressed / Articulated steel traits (§A4.1); the table of armor across the three styles and roles (its bow and
staff role handles, Bracer, Ward, Conduit, Censer, Flare, an area taunt, are not designed: those role finishers are
Luke's); "set K to 74 at quality 500" (K is one number for everyone, quality is per item).
**Corrected:** a foe's last hit is unblockable (no "34 to 8.5 on a block"); hits land at the foe's `damage_pct`;
the bow's riposte makes the next draw fill twice as fast, not "50 %".

## 6. The second outside review (2026-11-04), checked against the code
1. **The metal armor traits are dead on day one: VALID.** Nothing pushes, burns, slows or stuns a player, so Warded
   does nothing and Padded is only its sprint cost. Its fix "a knockback on the crushing overhead" goes against
   Luke's 2026-10-31 "no finisher shove". Its candidates, all on systems that exist (a new trait atom each):
   *Stalwart* (blocked hits x0.85, unblocked x1.08), *Hardy* (regeneration starts 2 s sooner, `regen_delay_s` 8,
   runs 15 % slower, `regen_pct_per_s` 4: about 35 s instead of 33 s from empty, sooner for a top-up), *Unyielding*
   (x0.85 taken below 35 % health, x1.08 above 70 %: Brutal's mirror on your own health).
2. **Braced (A4.1b) taxes the roll again and barely matters: VALID.** A player's stagger is 800 ms; the next foe
   waits `token_gap_ms` 600 after a swing lands, then winds up 550-850 ms, so you are free well before it lands.
   Braced is dropped.
3. **Too few parts for the grades: VALID, and worse than it said.** The core (plates) offers no trait, so plates +
   rivets offer ONE (`offered_traits`: each secondary part's trait that fits, none twice). Weapons already leave
   Masterwork's third slot empty (two trait-bearing parts). Its fixes (the plates offer a trait; pick any metal's
   trait) break "secondary parts carry traits". Better: accept one until the lining; or a LINING now of metal MAIL
   (copper, iron, steel rings), cloth and leather joining it later: two traits from the start.
4. **The iron-to-steel rounding plateau: NOT VALID.** Health is an `f32` and a hit is never rounded
   (`damage_entity`): steel takes 7.6 off a hack where iron takes 8.5, every hit. Only A7's table rounded for show;
   show it to a decimal. K is not lowered for this.
5. **A piece's tooltip vs the total: VALID** (iron chest alone 13 %, with iron legs 19 %, the legs alone "8 %"). A
   piece shows its Defense as a number, as Power is, and what wearing it does to YOU ("you'd take 19 % less, now
   13 %"); the doll shows the total.
