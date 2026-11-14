# Before the ability rework: item levels, the long track, the bar, four slots, picks, the chest (2026-11-13)

Luke, 2026-11-13: "I want to do the ability rework before armor as armor chest piece will add 1 ability." This sheet
says what is settled, what is built, the shape proposed, and the decisions that are his (§6, B1-B15), taken ONE BY ONE
(his word). His answers go to `GAME.md`; the order of work (§7) starts once they are in. Nothing here is built.
Revision 2 (2026-11-13): after his first read: plan for a long track, item levels over mastery-only, pools not
minimized, and two early questions (trading a levelled item; losing one).

## 1. What is settled, or his leaning (his)
- Settled 2026-11-13 (`GAME.md`, "THE ABILITY REWORK BEFORE ARMOR"): the light attacks stay (the staff's suffers from
  its placeholder bolt and low damage); at most FOUR abilities, on Q, E, F, R, from the weapon and the chest (a set:
  open); a clean bottom bar ("albion like or other examples"); every weapon's BASE ability (Q) comes with crafting,
  "unique to each weapon or role type"; the weapon's 2nd and 3rd levels each offer a 2nd ability OR an upgrade of the
  base, its 4th an "ult"; an empty slot may hold a potion or another thing.
- His direction, revision 2 (not final: he answers in §6):
  - PLAN FOR THE FUTURE SCOPE: "wont we go from to 99 or 60 or something longer reaching. If we want to position this
    as a fun time sink, we should plan for future scope not build it to just match todays design/prototype."
  - ITEM LEVELS, Tinkers'-style: "the whole idea from tinkers tools that lets you master an item until you find
    something that is so much better you need to start fresh. its a trade". Leaning: a new item CATCHES UP fast to
    your mastery (option A); feeding an old item into a new one (B) and upgrading an item's head (C) liked, later, with
    the GROUNDWORK for C laid now; an item's picks living on the item (D) "is just how things should happen".
  - CONTENT IS THE THING NOW: "content will soon be THE thing that we are adding ... I want to make sure we arent
    minimizing just for the sake of it ... unique playstyles are important so everyone isnt running around the exact
    same build."
  - Early questions he raised: is a levelled item tradeable or bound; what happens when one is lost (insurance, "some
    portion of XP given in a lamp to be used on a new weapon").
- From before: abilities by the weapon's kit at mastery 1/3/6/9 (#3, the v1 cap of 10, "production will go higher");
  mastery picks "tall or wide", changeable out of combat (2026-11-01); no global cooldown; mana on the staff only; roles
  by the handle's shape; SHOW, DON'T NAME; gear XP earned by use pays trait ranks, never Power; parts swapped at the
  workbench keep the item's gear XP (the head and quality never change); the design doc: gear "gains XP through use",
  "ways to lose gear (PvP, NPC quests) come later", no item loss in v1.

## 2. What is built
| | Its light string (LMB) | Its abilities today |
|---|---|---|
| Sword | Slash, Slash, its role's last hit (thrust, pommel bash, rallying cut) | Lunge |
| Axe | Chop, Overhead | Cleave (hits ONE: the referee reports a sweep's first body) |
| Bow | the draw and loose | none |
| Staff | Bolt (12 a hit) | Fireball, Frost Ring, Blink, Gale |
- `KitDef.skills` and `skill_ranks` (1, 3, 6, 9): the MASTERY rank each needs; the server refuses one under it.
- Mastery per weapon kind, per character: `xp_to_rank` cumulative to rank 10 (60 ... 2400), 0.5 XP a point of damage.
  A skeleton warrior pays ~60: RANK 9 IS ABOUT 30 KILLS. Each rank past the first adds 3 % damage (to +27 % at 10).
- An item's gear XP: earned by use (where the item's row keeps it), paid for trait ranks; kept when its parts are
  swapped. The head (metal) and quality of an item never change.
- Items move between players only by DROPPING (yours 60 s, then anyone's: template #269): no trade window, no vendors,
  no market yet. Death: no item loss, no durability (v1); "death and shrines" is later (`RULE_DESIGN.md` §4).
- The bottom of the screen is a TEXT line; abilities fire "in stance"; E is also the world's key.

## 3. The shape proposed (the agent's; each part a decision in §6)
### 3.1 Two layers: what you KNOW, and what THIS ITEM has learned (B1)
- MASTERY (the character, per weapon kind, as now): never lost. It sets how fast a new item catches up, gates the
  better gear and the deeper options (3.2), and keeps the 3 % a rank.
- THE ITEM'S LEVEL (Tinkers'): XP by use on the item; its LEVEL opens its slots and picks (3.3, 3.4). ITS PICKS ARE
  ITS OWN (D): two swords can be two builds.
- CATCH-UP (A): while an item's level is below your mastery of its kind, it earns XP several times as fast (the
  multiplier a hot rule; 5x proposed); above your mastery, normal speed. A fresh steel sword gets back to where your
  copper one was in a fraction of the time: the restart and the choice stay, the lost hours do not.
- Later, his leaning: FEED THE OLD INTO THE NEW (B: salvage an item into an "essence" of part of its XP for a new one
  of its kind), and RE-HEAD AN ITEM (C: the head swapped at the workbench as a handle is today, the item keeping its
  level, at a cost). GROUNDWORK FOR C NOW: the item's level, XP and picks are keyed by the ITEM (not by its parts), so a
  head swap later is a rule and a recipe, not a reshape; and the head is stored as a part like the handle.
- One XP or two (B15): the item's XP both raises its level and pays trait ranks today. Proposed: ONE track, the level;
  trait ranks GATED by item level (not paid out of it), so ranking a trait never lowers a level. ACCEPTED (Luke,
  2026-11-13), with a REFIT: a levelled item takes higher-ranked parts at the workbench (`MATERIALS.md` §11's swap),
  keeping its level; a part above the item's level does not fit; trait ranks work for any holder.

### 3.2 A long track: slots early, depth late (B4)
The cap goes from 10 to a long one (60 or 99: his call); the curve and the rank each unlock needs are content (no code
to change them). The trap is spreading four slots over 99 levels: an empty bar for most of a life. Proposed, for the
item's level against a long cap:
| Stretch (of a 1-99 track; scaled for 60) | What it gives |
|---|---|
| ~1-20 | the four: Q at 1, the 2nd pick ~5, the 3rd ~12, the ult ~20 (a new player's whole kit within days) |
| ~20-99 | depth, never slots: more OPTIONS opening in each pool (a 3rd E choice at 35, a second ult at 60); RANKS of each ability (I-V), each changing how it plays (further, through two, burns), not only numbers; small passives every few levels; the gear that needs the rank; a mark of mastery at the top (as a 99 cape) |
Mastery (the character's) runs the same long track; an item can be deeper than your mastery (at normal speed), and
the deepest options need BOTH (the item's level and your mastery).

### 3.3 Four slots: Q, E, R from the weapon, F from the chest (B5)
| Slot | From | When |
|---|---|---|
| Q | the item's BASE ability | from its making (level 1) |
| E | its 2nd ability, if a pick took one | the 2nd or 3rd pick |
| R | its ULT | the 4th tier |
| F | the CHEST's ability | when you wear one that has one |

### 3.4 The picks: wide or tall (B6)
At the 2nd and 3rd tiers, ONE pick: a 2nd ability for E (one of the pool's), OR an UPGRADE (of Q, or of E once it is
there). At the 4th, the ult (one of the pool's). Picks change out of combat (decided), each item's its own (D).

### 3.5 An empty slot (B7)
Tall leaves E empty, no chest leaves F empty: an empty slot takes a CONSUMABLE (potion, food, bomb) once those exist,
so tall is "a stronger Q and a potion on E". Until then it shows what opens it. No extra potion slots: the bar stays four.

### 3.6 The chest's ability, not a set (B8)
The chest's own ability: one piece, one slot, swapped with the piece. A set asks for every piece, makes a mixed outfit
a loss, and pushes one best set. Choosing a chest for its ability is the point when its other side costs: armor's open
question ("why wear lighter armor", `ARMOR_PREP.md`) answered: CLOTH chests casting and moving (Blink moves here),
LEATHER quick utility, METAL guarding; which of its family's a chest carries picked at crafting, as traits are; the
chest levels as a weapon does. A small set passive later is not ruled out.

### 3.7 Pools from LAYERS, built to grow (B9)
An item's options are ASSEMBLED, each layer content a designer adds without code:
| Layer | Gives | Why |
|---|---|---|
| its weapon KIND | the core: a sword still feels like a sword | the identity of the weapon |
| its ROLE (the handle) | options of its own (the crossguard guards, the banner supports) besides its last hit | roles become playstyles |
| THE ITEM (a unique drop, later a rare pattern) | an option nothing else has | drops become events; builds diverge; prized items |
| its material or a trait (later) | a variant (an iron spin that sparks) | depth from the crafting side |
| the chest | F | the armor's answer |
Variety comes from multiplying layers (kind x role x picks x chest x traits), not from one huge pool. THE SYSTEM holds
every layer from the start; the CONTENT ships in slices, the roles' options in the first. Cost, plainly: every new
weapon kind then wants a set per role; more to balance; a unique can be an outlier players chase.

### 3.8 A first sketch of the pools (B10: his to rewrite; numbers after)
| | Q (base) | E options | Upgrades | R (ult) |
|---|---|---|---|---|
| Sword | Lunge | a spin that hits all round; a blow that wears poise twice; (crossguard) a taunting bash; (banner) a rally that heals near | Lunge further and through two; Lunge's cooldown halved | a blow that deals more the lower the foe's health |
| Axe | Cleave, made to hit ALL in its arc | a hamstring (slows); a thrown axe | Cleave wider; Cleave staggers a full bar | a whirlwind you walk in |
| Bow | a fan of three arrows up close (its first Q) | a pinning shot (slows); a roll back that looses as it lands | the fan five; the pin longer | arrows rained on a ring for seconds |
| Staff | Fireball | Frost Ring; Gale | Fireball burns where it lands; Frost Ring wider | a meteor after a long cast |
| Chest (F) | cloth: Blink, a mana well; leather: a burst of speed, a sidestep that clears a hit; metal: a held full guard 3 s, a shout that draws foes | | | |

### 3.9 Trading a levelled item (B2, an early question)
Today anything can change hands by dropping it. Options:
| | What | Pros | Cons |
|---|---|---|---|
| T1 | tradeable, its level with it | a market for levelled gear; levelling as a trade | buying power; bots level items to sell; real-money trade bait |
| T2 | bound once levelled (or once wielded) | levels purely personal; fresh crafted gear trades | a bind rule to show and enforce (dropping, sacks); a dead item if you quit its kind |
| T3 | tradeable, its level reset on a trade | a market for the item itself; no binds | the seller's work vanishes; a "reset" surprises people |
| T4 | tradeable with its level, USED only up to the holder's mastery (the rest waits until you reach it) | a market without buying past your skill; levels keep value for masters; works with catch-up (A) | one more rule to explain ("this sword is 40, you can use 25 of it") |
Proposed: T4 (the level is the item's, the right to use it is yours). T2 if he wants levels never to trade.

### 3.10 Losing a levelled item (B3, an early question)
Today nothing is lost. With A, any loss is already soft: a new item climbs back fast to your mastery; what is lost is
the levels above your mastery, its picks, and the item itself (its traits, a unique). Options:
| | What | Pros | Cons |
|---|---|---|---|
| L1 | items are never lost (as v1) | no feel-bad | no stakes; no sink beyond crafting |
| L2 | loss only where a place says so (a PvP zone, a hardcore realm, a quest), with INSURANCE bought before | stakes chosen by the player; a coin sink | needs an economy (marks) first |
| L3 | THE LAMP (his idea): a lost or salvaged item leaves an essence of part of its XP (half proposed) for a new item of its kind | progress never all gone; one mechanic for salvage (B) and loss | essence could be traded (rules as T1-T4) |
| L4 | durability: a broken item loses levels | a steady sink | grinding repairs; feels bad daily |
Proposed: L1 now (no loss anywhere yet), decided now that loss only ever happens where a place says so (L2), and the
lamp (L3) as THE mechanic for both salvage and loss when either is built. Durability stays parked.

### 3.11 The animation inventory (2026-11-13: can abilities be per weapon, per role, per material?)
Both Quaternius libraries are in the game already (`game/anim/humanoid_core.res`, UAL1, 127 clips;
`humanoid_extra.res`, UAL2, 135), on our 65-bone skeleton (no retarget). Sorted by what an ability can use:
| Kind of motion | Clips (Q1 = UAL1, Q2 = UAL2) | Distinct motions |
|---|---|---|
| One-handed sword strikes | Q2 `Sword_Regular_A/B/C`, `Sword_Light_A/B/C/D`, `Sword_Heavy_A/B/C/D` (each with a `_Rec`), `Sword_Aerial_A/B`; Q1 `Sword_Attack` | ~14 |
| Sword strings (multi-hit) | Q2 `Sword_Regular_Combo`, `Sword_Light_Combo`, `Sword_Heavy_Combo`, `Sword_Aerial_Combo` | 4 |
| Strikes that move | Q2 `Sword_Dash_RM` (a lunge), `Sword_UpperCut_RM` (a launcher), `Sword_GroundPound_RM` (a slam) | 3 |
| Guard and shield | Q2 `Sword_Block`, `Shield_OneShot` (a bash), `Shield_Dash_RM` (a charge), `Idle_Shield`, `Idle_Shield_Break`, `Sprint_Shield` | 3 actions |
| Unarmed | Q1 `Punch_Jab`, `Punch_Cross`, `Kick`; Q2 `Melee_Hook`, `Melee_Uppercut`, `Melee_Knee`, `Melee_Combo` | ~7 (a kick or knee fits any weapon) |
| Throwing | Q2 `OverhandThrow` | 1 (a thrown axe, a bomb, knives: the tools) |
| Bow | Q2 `Bow_Notch`, `Bow_Aim_Up/Neutral/Down`, `Bow_Shoot`, `Bow_RapidShoot` | 2 shots (+ draw and aim) |
| Casting | Q1 `Spell_Simple_*` (one hand), `Spell_Double_*` (two hands), `Pistol_Shoot` (a pointing cast) | 3 |
| Moving | Q1 `Roll`, `Dodge_Left/Right`, `BackFlip`; Q2 `JogToFlip`, `NinjaJump_*`, `DoubleJump`, `Slide`, `WallRun_*`, `SafetyVault_RM` | ~10 |
| Support and self | Q1 `Celebration` (a rally), `Drink`; Q2 `Idle_Rail_Call` (a shout), `Bandage`, `Consume`, `Yes` | ~5 |
| Reactions, foes | Q1 `Hit_*`, `Death*`; Q2 `Hit_Knockback`, `LiftAir_*` (thrown up), `Zombie_*` | for what abilities DO to foes |
About ten of these are in use today (the strings, the finishers, the foes). Nothing for a two-handed weapon, an axe
of its own, a staff's own swing, or a second bow shot style.

What that makes feasible:
| | Per role (3-4 each, 9-12 a weapon) | Per material, whole new sets | Per material, a TWIST |
|---|---|---|---|
| Sword | YES from Quaternius alone: ~14 strikes, 4 strings, 3 moving strikes, shield bash and charge, kicks, a rally and a shout | NO: the same motions repeat across tiers | YES: an effect, not a motion |
| Axe | PARTLY: it shares the sword's one-handed motions (fine for a hand axe; it looks like a sword with an axe in it). A two-handed axe needs Mixamo's *Great Sword* pack (51 clips, a retarget) | NO | YES |
| Bow | THIN: two shot motions; abilities differ by WHAT FLIES (spread, pin, rain, explode) and by moving shots (a roll or backflip that looses), a kick, a throw. Workable, visually samey; Kevin Iglesias's Archer pack or Mixamo for more | NO | YES |
| Staff | THIN in motion, as most games are: three casting motions; magic reads by its EFFECT (what forms, where, its color). Rokoko's free magic pack (commercial use allowed, a retarget) adds | NO | YES |
WHERE THE DIFFERENCE LIVES: an ability is its motion, its timing, its effect (trail, burst, what flies, what forms),
its sound and what it does. Motions are the scarcest; effects are the cheapest and the most readable. So per-role
sets are feasible with clips SHARED between abilities and the effect carrying the difference; a material's twist is
an effect and a rule (sparks, a bleed, a burn, a chill, a heavier impact), no clip at all.
Ways to stretch the clips, each to try: speed and timing (as the foes' are); MIRRORED copies (left and right swapped:
a tool to write, to verify); the upper body over the legs (casting on the move, built); strings cut into single
strikes (as `regents_cuts.res` does); root-motion variants. Sources past Quaternius, each a retarget: Mixamo (free,
royalty-free in games), Rokoko (free, commercial use), Kevin Iglesias (paid; license to ask).

### 3.10b The bar (B11), keys (B12), respec (B13), the staff's Bolt (B14)
- THE BAR: round slots low in the middle (Albion), Q, E, R, F, each with its key and its cooldown on it, a locked one
  dim with what opens it, a thin ring round the weapon's three filling toward its next tier, health above, mana or
  arrows beside; hover for what it does, no role or mechanic names; the mouse's string and guard off the bar.
- KEYS: Q, E, R, F in stance as now (E the world's key out of it), or abilities on other keys and E always the world's.
- RESPEC: picks change out of combat, free; or at a cost (his open item).
- THE BOLT: a real projectile and more damage, inside this rework.

## 4. What this needs that is not built
| Layer | Missing |
|---|---|
| Content | per weapon kind and role: Q, E, R pools, upgrades (each a modifier that changes how its ability plays), ranks, passives; a unique's option; a chest's ability; each with its look |
| Server | the item's LEVEL and PICKS (side tables keyed by the item, rule 17), catch-up against mastery, picks out of combat, `may_fight` reading them, upgrades applied where their ability lands, the slot an ability fires from; the long curves; trade and loss rules as answered |
| Client | the bar (its own HUD); the pick screen; an item's level and picks in its tooltip and the bag |
| Referee | an area that hits ALL in it (Cleave, a spin, a whirlwind) |
| Bench | the kit bench: each pick's damage a second, wide against tall; an item's level over hours played |

## 5. Risks, plainly
- Content is most of it (four kinds x three roles x (Q, E options, upgrades, an ult), the chests, uniques), each with
  a clip, a look and a sound. The system first, the content in slices.
- Item levels and trading meet the economy: decide B2 and B3 before levels exist in the world, or a later rule takes
  something away from players.
- An area that hits all is a referee change, and the template's if general.

## 6. The decisions that are yours (one by one)
| # | Decision | Proposed |
|---|---|---|
| B1 | Item levels | ACCEPTED (Luke, 2026-11-13): two layers, mastery and the item's level, with CATCH-UP (A, 5x to start, a hot rule); B and C later; C's groundwork now (3.1) |
| B2 | Trading a levelled item | ACCEPTED (Luke, 2026-11-13): T4, tradeable with its level, used only up to your mastery (3.9) |
| B3 | Losing one | ACCEPTED (Luke, 2026-11-13): L1 now; loss only where a place says so, with insurance (L2); the lamp (L3, half the XP) for loss and salvage; durability parked (3.10) |
| B4 | The long track | ACCEPTED (Luke, 2026-11-13): 99; the four slots by ~20 (Q 1, picks ~5 and ~12, the ult ~20), depth after (3.2) |
| B5 | Which slots | ACCEPTED, changed (Luke, 2026-11-13): sources fixed (three from the weapon, one from the chest); keys reorderable by the player later (accessibility); for now Q, E, R the weapon's, F the chest's; a slot's key a setting, not a constant |
| B6 | The picks | ACCEPTED (Luke, 2026-11-13): at ~5 and ~12 a 2nd ability or an upgrade; the ult at ~20; changing them COSTS something (B13) |
| B7 | An empty slot | ACCEPTED, changed (Luke, 2026-11-13: option 3): one potion key for everyone (G), food from the bag (a buff, no slot), an empty ability slot (E tall, F with a plain chest) takes UTILITY TOOLS only; until they exist it shows what fills it |
| B8 | Chest or set | ACCEPTED (Luke, 2026-11-13): the chest's own ability, by family, picked at crafting, levelling as a weapon; Blink to cloth; FULL-SET BONUSES wanted later, on top (enhancing the ability or something else) |
| B9 | Pools | ACCEPTED (Luke, 2026-11-13): layers (kind, role, the item, later material or trait, the chest); all in the system now, content in slices, the roles' in the first; a pick shows every option you qualify for (3.7) |
| B10 | The pools' content | ACCEPTED (Luke, 2026-11-13: "Yes, roles + twist"): per-role sets with each role's own base Q, separate pools, a material's TWIST as an effect and a rule; content designed at each weapon's build step (the discussion that led there: each ROLE's base Q differs ("sword dps is lunge, sword support is healing swipe"); the role's last hit stays a small always-on effect, the same for every material of a weapon kind (C; B, roles in abilities only, the fallback); SEPARATE POOLS PER ROLE, 3-4 each; a material's TWIST wanted, whole sets per material open: the inventory (3.11) says sets per role are feasible, per material only as a twist) |
| B11 | The bar | ACCEPTED (Luke, 2026-11-13): low in the middle, as 3.10b; ROUND AND SQUARE both built in a small lab to switch between, his pick after seeing them |
| B12 | Keys | ACCEPTED (Luke, 2026-11-13): as now, with a CLEAR sign of being in stance or in combat; a context E in stance (loot, revive) liked for later |
| B13 | Respec | ACCEPTED (Luke, 2026-11-13): one free change per item a week; then the head's materials at a workbench, escalating per change and halving weekly; marks later; a newly opened pick free; the price PER PICK CHANGED (fewer open below 20, so cheaper); no free changes below 20; all hot rules |
| B14 | The staff's Bolt | ACCEPTED (Luke, 2026-11-13): a real projectile, its damage benched in line with the other light strings, free of mana; with step 4 unless he asks sooner |
| B15 | One XP or two on an item | ACCEPTED (Luke, 2026-11-13): one, its level, never spent; trait ranks gated by level and paid in bulk + a catalyst; a levelled item is REFIT with higher-ranked parts its level takes (the workbench swap), keeping its level; trait ranks work for any holder, abilities follow mastery |

## 7. The order of work (once answered; each step ends playable or proved)
1. THE BAR with today's abilities (no new content): four slots, cooldowns, locks, the hints moved, the stance/combat
   indicator (B12); round AND square built in a lab for Luke to pick (B11). Luke plays it.
2. (FIRST SLICE BUILT, PROGRESS 74: the item's XP and picks in its own data, catch-up, T4, the slot gate, `choose_pick`,
   the bag's chooser, the staff's pool; LEFT: the sword's pools (§9, his rewrite), upgrades. CHANGING PICKS (B13) BUILT, PROGRESS 75.)
   ITEM LEVELS AND PICKS on the server (side tables keyed by the item; catch-up; the out-of-combat change; trade and
   loss rules as answered), the pick screen, the long curves as content; the sword's and staff's pools first, the
   sword's roles with them. Unit and integration checks with negatives.
3. AREAS THAT HIT ALL (the referee).
4. The axe's and bow's pools; the ults; the staff's Bolt.
5. The chest's ability (the slot, one ability a family), then ARMOR's prep session (`ARMOR_PREP.md` §0).
Later: the lamp (B and loss), re-heading (C), uniques' options, ranks and passives along the long track.

## 8. Before step 2: what blocks it (2026-11-13, after step 1; Luke's, one by one)
Step 1 (the bar) is built (PROGRESS 72). Step 2 (item levels and picks) needs these first; each changes what players
have today, so none is defaulted.
| # | Question | Today | Proposed |
|---|---|---|---|
| S1 | MASTERY TO 99 NOW? B4 says mastery and item levels both run 1-99; catch-up compares the two, so they need one scale | weapon mastery 1-10 (`xp_to_rank` 60 ... 2400, rank 9 ~30 skeletons), +3 % damage a rank (+27 % at 10), abilities at 1/3/6/9 | with step 2: a 99 curve (a guess: 20 in ~6-8 h of fighting, 99 in ~150 h), +0.3 % a level (+29 % at 99), XP kept and read on the new curve, the 1/3/6/9 locks gone (the ITEM's level opens slots: 1, ~5, ~12, ~20) |
| S2 | THE GATHERING AND MAKING SKILLS too? | 1-10, nodes and recipes gated by rank (`min_rank`), a rank eases a round 4 % (three at most) | weapon masteries only now; the rest when their own long track is designed (their gates are content) |
| S3 | THE SWORD'S POOLS for step 2 (B10: designed at its build step): each role's base Q and its 3-4 options | Lunge for every sword | his names and what each does, or the agent drafts a short sheet (as the foes had) for him to rewrite: e.g. plain grip Q Lunge, crossguard Q a bash that draws the foe, banner Q a cut that mends those near |
| S4 | THE STAFF'S POOL from today's spells | Fireball 1, Frost Ring 3, Blink 6, Gale 9 (mastery) | Q Fireball; the ~5 pick Frost Ring OR Gale OR a Fireball upgrade; Blink stays on F until cloth chests (step 5); no ult until step 4 |

ANSWERED (Luke, 2026-11-13, `GAME.md`): S1 + S2 every skill to 1-33 for now (a third of 99; finalized before the
public demo, with a wipe); S3 the agent drafts the sword's pools (§9) for him to rewrite; S4 as proposed, and Gale
buffed largely ("8 dmg and nothing else right now on a long cooldown").

## 9. THE SWORD'S POOLS, a draft for Luke to rewrite (S3, 2026-11-13)
His frame (`GAME.md`, B10 and its discussion): each ROLE its own full set, its own base Q, 3-4 options a role; the
role's last hit stays a small always-on effect; a material gives a TWIST (an effect and a rule), never a new set.
Slots open on the ITEM's level: Q at 1, a pick at ~5 and ~12 (a 2nd ability on E, or an upgrade of Q or E), the ult
on R at ~20. Every motion below exists in UAL1/UAL2 (§3.11); names are working names, numbers come on the bench.
Words a player reads never name the role (show, don't name): the plain grip, the crossguard hilt, the banner hilt.

**The plain grip** (its last hit the piercing thrust: reach and damage). Plays as: in, hurt, out.
| Slot | Draft | Motion | What it does |
|---|---|---|---|
| Q | LUNGE (today's) | `Sword_Dash_RM` | dash 3 m through the target, a hard hit |
| E option | RIPOSTE STANCE | `Sword_Block` held, then `Sword_Light_C` | hold a moment: a hit that lands on you in it is turned and answered at double damage; nothing comes, it ends |
| E option | FLURRY | `Sword_Light_Combo` | four quick cuts that wear poise like lights; you walk, not run |
| E option | HAMSTRING CUT | `Sword_Light_D` | a low cut: slowed 3 s, and the next hit you land on it is harder |
| Upgrades | Lunge through two; Lunge's cooldown cut; Flurry a fifth cut; Riposte Stance longer | | |
| R (ult) | EXECUTE | `Sword_Heavy_C` | one blow that deals more the lower the foe's health |

**The crossguard hilt** (its last hit the pommel bash, a longer stagger; its guard the full guard). Plays as: hold them,
take it, punish.
| Slot | Draft | Motion | What it does |
|---|---|---|---|
| Q | SHIELD BASH | `Shield_OneShot` | a short bash in front: a big poise hit, and the foe turns to you (it draws the foe) |
| E option | CHALLENGE | `Idle_Rail_Call` (a shout) | foes within 8 m turn to you for 4 s (the attack tokens go to you first) |
| E option | BRACE | `Idle_Shield` held | for 3 s your block in front takes nothing, and a light that lands on it knocks the attacker off balance |
| E option | CHARGE | `Shield_Dash_RM` | run 6 m into a foe: knocked back and staggered if its poise is worn |
| Upgrades | Bash wider (all in front); Challenge longer; Charge through two | | |
| R (ult) | BULWARK | `Sword_Block` + a ring on the ground | 5 s: players behind you take half from anything in front of you |

**The banner hilt** (its last hit the rallying cut that mends those near). Plays as: stay in the fight, keep others in it.
| Slot | Draft | Motion | What it does |
|---|---|---|---|
| Q | HEALING SWIPE (his example) | `Sword_Regular_B` | a cut that mends you and the players within 6 m by a share of what it dealt |
| E option | WAR CRY | `Celebration` | you and players near hit harder for 6 s |
| E option | BANNER PLANT | `Sword_GroundPound_RM` | plant a mark for 8 s: players inside regain health slowly and are not knocked down |
| E option | SHOULDER CHECK | `Melee_Knee` / a shoulder | a short shove that breaks a foe's cast and turns it to you |
| Upgrades | Swipe's mend wider; War Cry longer; the Banner larger | | |
| R (ult) | LAST STAND | `Idle_Rail_Call` | 6 s: players within 10 m cannot drop below 1 health |

**A metal's twist** (one each, on every sword ability of that metal; the effect is the look): COPPER none (the
plain); IRON sparks, its hits wear a little more poise; STEEL bites, a hit that lands opens a short bleed.

**What this asks of the server** (step 2 and after): a stance window answered at once (Riposte Stance: the parry's
lines), a buff on players near (War Cry, the banner), a floor on health (Last Stand), a mend by a share of damage
(Swipe), a cooldown cut and a "through two" (upgrades as modifiers), and the referee's area hit (step 3) for
anything that hits all in front. The first slice to build after his rewrite: the three Qs and one E each.
