# Regent's Rule: the animation checklist (for the combat overhaul)

Every clip the combat overhaul (`COMBAT_OVERHAUL.md`) needs, with the best candidates found in each source.
**Keep it current**: tick a box when a clip is in `game/regents/anim/adventurer.tres` (or a foe's set) and
playing in game, and write which candidate won. Sections follow the overhaul's order of work (§9), so the
top of the list is what is needed first.

Scanned 2026-10-30: Quaternius UAL1 and UAL2 (every clip, with its length, read from Luke's files), Mixamo (its
catalogue searched by weapon, reaction and foe terms), and other free or licensed sources (§2).

---

## 1. How to read and use it

**Sources** (the codes used below):

| code | source | licence | rig |
|---|---|---|---|
| **Q1** | Quaternius Universal Animation Library 1 (127 clips) | CC0 (no credit needed) | our 65-bone skeleton: no retarget |
| **Q2** | Quaternius Universal Animation Library 2 (135 clips) | CC0 | our skeleton: no retarget |
| **M** | Mixamo (Adobe), free | royalty-free in games; never redistribute the raw files | Mixamo rig: **retarget** |
| **KI** | Kevin Iglesias, Human Melee / Archer / Magic packs (itch.io, ~$23 each; free cut-downs) | **not stated on the page: ask before buying** | his rig: retarget; Godot tutorial on the page |
| **RK** | Rokoko free packs (magic-themed, others) | "any game ... including commercial use" | exported for the Mixamo rig: retarget |
| **CMU** | Carnegie Mellon mocap database | "free for all uses"; may ship in a product; not resold as data | raw BVH: retarget and heavy cleanup |

- **Quaternius first**: no retarget, CC0, and the same feel as what is in already. Luke's copies:
  `Downloads\04_GameAssets\Quaternius_Assets\Animation Libs\` (the import procedure: `game/anim/ATTRIBUTION.md`).
  Q1's clips come from its Unreal export (`AL.fbx`), not its Godot export (that one is a different rig).
- **Mixamo**: download **FBX Binary, "Without Skin", "In Place"** (except moves that should travel: a lunge,
  a dash), 30 fps. Mixamo names repeat ("Great Sword Impact" is five clips), so each is listed as
  **Name: description**, which is unique. Pack names checked: *Great Sword Pack* (51), *Pro Sword And Shield
  Pack* (51), *Sword And Shield Pack* (49), *Lite Sword And Shield Pack* (17). The axe, bow and magic clips
  come as families ("... With Axe", "... With Bow", "Standing 1H/2H Magic ..."); their pack names were not
  checked.
- **Retargeting Mixamo onto our skeleton is not set up yet.** The first Mixamo clip settles how: Godot's
  import retarget (a BoneMap to the Humanoid profile) or retarget in Blender onto the Quaternius rig and
  export a `.glb` into today's pipeline. Do that once, with one clip, before buying anything.
- **Lengths matter**: a clip's length at its speed IS the lock (`COMBAT_CURRENT.md` §4). A long wind-up needs
  a clip with a real drawn-back pose; slowing a fast clip slows the whole swing, not just the wind-up.
- Mixamo has **no clip called a parry**. Its quick arm blocks ("Inward Block", "Right Block") have the right
  timing; KI's melee pack is the one source with a parry for each weapon.

---

## 2. In already (the adventurer set, 2026-10-30)

- [x] Locomotion: idle, walk, jog 4-way, sprint, jumps (Q1)
- [x] Roll (Q1 `Roll`), hit (Q1 `Hit_Chest`), death (Q1 `Death01`), interact, push
- [x] Sword string A/B and its finisher (Q2 `Sword_Light_A/B/C`, retimed 2026-10-31 to the slower wind-ups:
  ×0.83, ×1.04, ×1.18), lunge (Q2 `Sword_Regular_C`). The heavy cut is retired (its clip, `Sword_Heavy_A`,
  is now the axe's finisher, ×0.7)
- [x] Block pose (Q2 `Sword_Block`)
- [x] Bow notch, aim, shoot (Q2 `Bow_Notch`, `Bow_Aim_Neutral`, `Bow_Shoot`)
- [x] Spells (Q1 `Spell_Simple_Idle/Shoot`, `Spell_Double_Idle/Shoot`)
- [x] Sword draw and sheathe (Q1 `Sword_Enter/Exit`)
- [ ] **The axe has no axe clips**: it borrows the sword's (Chop `Sword_Regular_A` ×0.73, its finisher the
  Overhead `Sword_Heavy_A` ×0.7, since 2026-10-31). §4 fixes it.

---

## 3. Step 1: foes you can read (needed first)

Foes get their own kits (`COMBAT_OVERHAUL.md` §2). These clips are the skeletons'.

**Placeholders in use** (2026-10-31, PROGRESS step 26), UAL2 clips slowed in `game/regents/anim/adventurer.tres`
until the real ones come: warrior `Sword_Heavy_A` ×0.7, `Sword_Heavy_B` ×0.75, finisher `Sword_Light_C` ×0.53;
axeman `Sword_Heavy_A` ×0.65, finisher `Sword_Heavy_C` ×0.55. A new clip's wind-up is where its hand moves
fastest (divided by its speed): set the ability's `wind_up_ms` to it when you swap one in.

- [ ] **Skeleton light swing, a long wind-up (~550 ms to the hit)**
  - M: *Zombie Attack: Zombie Swipe Attack* · *Mutant Swiping: Mutant Attacking With Left Hand* ·
    *Standing Melee Attack Horizontal: Right To Left Attack With Axe* · *Stable Sword Outward Slash*
  - Q2: `Zombie_Scratch` (1.80 s) · `Sword_Regular_A` + `_Rec` slowed (fallback)
- [ ] **Skeleton second light** (a combo needs two)
  - M: *Standing Melee Attack Backhand: Backhanded Upward Attack With Axe* · *Stable Sword Inward Slash*
  - Q2: `Sword_Regular_B` + `_Rec`
- [ ] **Skeleton finisher, unblockable, big (~850 ms), gets the red glint**
  - M: *Zombie Attack: Zombie Overhead Two-Hand Attack* · *Standing Melee Attack Downward: Downward Attack
    With Axe* · *Mutant Jump Attack* · *Great Sword Jump Attack: from Run* · *Standing Melee Attack 360 High*
  - Q2: `Sword_Heavy_D` (2.33 s) · `Sword_GroundPound_RM` (1.17 s)
- [ ] **Skeleton axeman's set** (the axe family): *Standing Melee Combo Attack Ver. 1 / 2 / 3* (two-, three-
  and two-hit combos), *Standing Melee Attack 360 Low*
- [ ] **Circling, waiting for a token**: a slow side-step left and right
  - Q2: `Zombie_Walk_L_Loop` / `_R_Loop` · `Walk_L_Loop` / `Walk_R_Loop`
  - M: *Great Sword Strafe: Left Walk / Right Walk* · *Sword And Shield Strafe: Left / Right Strafe Walk* ·
    *Standing Walk Left / Right: With Axe*
- [ ] **A menacing idle while circling**
  - Q2: `Zombie_Idle_Loop` · M: *Threatening: Being Threatening While Standing* · *Standing Taunt Chest Thump:
    Banging Axe On Chest* · *Zombie Idle: Zombie Alert Idle*
- [x] **Recoil when parried** (the attacker's 800 ms stagger): `react.stagger` = Q2 `Idle_Shield_Break` (2026-10-31,
  PROGRESS step 28; the player's stagger too: one set)
  - Q2: `Idle_Shield_Break` (1.07 s: a guard knocked aside; the best fit) · M: *Standing Block React Large:
    Large Block Reaction With Axe* · *Zombie Reaction Hit: Stumble Back*
- [ ] **Death variants** (2-3)
  - Q1: `Death02` · M: *Zombie Death: Falling Onto Back* · *Zombie Dying: Falling Forward* · *Sword And Shield
    Death: Falling Forward / Falling Back*
- [ ] **Rising from the ground** (respawn)
  - Q2: `Zombie_Spawn` (2.83 s) · M: *Zombie Stand Up: Laying On Stomach / On Side / On Back To Standing Up*
- Not an animation: the red glint is a VFX on the ability event.

---

## 4. Step 2: the combo and defence (the player)

### Every weapon
- [ ] **Combat idle per weapon**
  - sword: Q1 `Sword_Idle` · M *Sword And Shield Idle* (several)
  - axe: M *Standing Idle: Standing Idle With Axe*
  - bow: M *Standing Aim Idle 01: Aiming Idle With Bow* · *Standing Idle 01: With Bow*
  - staff: M *Standing Idle: Standing Idle Ready To Cast Spell*
- [ ] **Combat strafe walk, 4-way, per weapon** (walking while blocking and in stance)
  - any: Q2 `Walk_Fwd/Bwd/L/R_Loop` (+ the upper body's hold)
  - sword: M *Sword And Shield Strafe: Left / Right Strafe Walk*, *Sword And Shield Walk*, *Backward Walk*
  - axe: M *Standing Walk Forward / Back / Left / Right: With Axe*
  - bow: M *Standing Aim Walk Forward / Back / Left / Right: While Aiming With Bow*
- [ ] **Parry: a quick deflect (~300 ms), per weapon**
  - sword: M *Inward Block* · *Blocking: Blocking Outward* · *Right Block: High Right Block* · *Center Block:
    High Center Block* (arm blocks: the right timing; the weapon hand carries the sword) · Q2 `Sword_Block`'s
    start · KI melee "parry with each weapon"
  - axe: M *Standing Block React Large: Large Block Reaction With Axe*
  - bow (the stave): M *Standing Block: Blocking An Attack With Bow*
  - staff (the ward flash): M *Standing Block Start: Standing Idle To Block Idle* · *Standing Block Idle:
    Blocking With Both Arms Out*
- [ ] **Block: a held loop plus the hit-while-blocking recoil** (Tank full, others weak; same clips)
  - sword: M *Great Sword Blocking: Blocking Idle* (two-handed, no shield: the best fit) · *Great Sword Impact:
    Blocked Impact* · *Sword And Shield Block Idle* (has a shield arm: check)
  - axe: M *Standing Block Idle: Blocking An Attack With Axe* + *Standing Block React Large*
  - bow: M *Standing Block: With Bow* · staff: M *Standing Block Idle: Both Arms Out*, *Standing Block End*
- [ ] **Hit reactions from four sides** (a hit from behind now matters)
  - M: *Standing React Small From Front / Back / Left / Right* and *Standing React Large From Front / Back /
    Left / Right* (unarmed; bow and axe versions exist too)
  - Q1: `Hit_Chest`, `Hit_Head`, `Hit_Shoulder_L`, `Hit_Shoulder_R`, `Hit_Stomach`
- [ ] **Flinch (350 ms)**: Q1 `Hit_Chest` (0.33 s), `Hit_Head` (0.43 s) · M *Zombie Reaction Hit: Flinches*
- [x] **Stagger (800 ms), the player's**: Q2 `Idle_Shield_Break` (1.07 s; in as `react.stagger`, 2026-10-31) · M *Standing React Large Gut: With
  Axe* · *Big Body Blow* · *Receiving A Big Uppercut*
- [ ] **Riposte, per weapon** (fast)
  - sword: M *Stable Sword Inward Slash* · *Sword And Shield Slash: Cross Slash* · Q2 `Sword_Light_A` faster
  - axe: M *Standing Melee Attack Backhand: With Axe*
  - staff (a point-blank bolt): Q1 `Spell_Simple_Shoot` · M *Standing 1H Magic Attack 01*
  - bow (a faster draw): Q2 `Bow_Notch` sped up · M *Standing Draw Arrow: Reloading Bow*
- [ ] **Sword string: Slash, Slash, Thrust**
  - L1 and L2: Q2 `Sword_Light_A`, `Sword_Light_B` (in already)
  - the Thrust finisher: M *Sword And Shield Attack: High Attack* · *Sword And Shield Slash: Power Slash* ·
    Q2 `Sword_Heavy_A` (in already as the heavy: may become the finisher)
- [ ] **Axe string: Chop, Overhead** (its own clips at last)
  - Chop: M *Standing Melee Attack Horizontal: With Axe* · *Standing Melee Combo Attack Ver. 1* (two hits)
  - Overhead: M *Standing Melee Attack Downward: Downward Attack With Axe*
- [ ] **Staff weave: Bolt, Bolt, Surge**
  - Bolt (alternating hands): Q1 `Spell_Simple_Shoot` · M *Standing 1H Magic Attack 01: Forwards*, *02: Sweep
    Right To Left*
  - Surge (two hands): Q1 `Spell_Double_Shoot` · M *Standing 2H Magic Attack 01 / 02: Forwards*
- [ ] **Bow**: a quick shot M *Standing Aim Recoil: Standing Aim Fire Arrow* · the full-draw hold M *Standing
  Aim Overdraw: Charging Bow For Powershot* · aim up Q2 `Bow_Aim_Up`, down `Bow_Aim_Down`
- [ ] **Draw and sheathe for the other weapons**
  - axe: M *Unarmed Equip Underarm / Over Shoulder: Equipping Axe*, *Standing Disarm Underarm / Over Shoulder*
  - bow: M *Standing Equip Bow*, *Standing Disarm Bow*
  - staff: **none found** (the axe's over-the-shoulder pair is the nearest)
- [ ] **Knockdown and get-up** (Gale, the horn blast): Q2 `Hit_Knockback` (0.83 s), `KipUp`, `LayToIdle` ·
  M *Knocked Down: To Stomach* · *Knocked Out: Falling To Back* · *Getting Up: From Back / From Stomach*
- [ ] **Pushed back** (a short slide): Q2 `Hit_Knockback_RM`
- [ ] **More deaths** (players): Q1 `Death02` · M *Falling Back Death* · *Standing React Death Forward*
- [ ] (optional) **Side dodges**: Q1 `Dodge_Left` / `Dodge_Right` · M *Standing Dodge Forward / Backward / Left
  / Right: With Bow*

---

## 5. Step 4: the role finishers (the sword first)

The finishers are first proposals (`COMBAT_OVERHAUL.md` §5); Luke settles them, then the clip.

- [ ] **Sword, Damage: a big thrust** (Piercing thrust, 40003): placeholder 2026-11-01, the old finisher's Q2
  `Sword_Light_C` x1.18 (a rising cut, its hand fastest at 381 ms). Q2 `Sword_Light_D` IS a thrust (hand forward
  at 300 ms) but holds the arm out 1.3 s: x0.79 for a 380 ms wind-up makes a 2.1 s lock. Wanted: a thrust that
  recovers in ~0.4 s. M *Sword And Shield Slash: Power Slash* · Q2 `Sword_Dash_RM` (1.57 s, travels) · `Sword_Heavy_D`
- [x] **Sword, Tank: a pommel bash** (Pommel bash, 40022): Q2 `Melee_Hook` x0.735, a hilt-first punch, its hand
  fastest (forward) at 340 ms, lock 635 ms (2026-11-01, a placeholder until a real hilt strike). Others: M *Sword
  And Shield Attack: Hilt Melee* · *Great Sword Attack: Hilt Melee* · Q2 `Shield_OneShot` (its right hand barely
  moves) · `Melee_Knee` · M *Sword And Shield Kick: Sparta Kick*
- [x] **Sword, Support: a wide sweep** (Rallying cut, 40023): Q2 `Sword_Light_D` x0.75, cut in two by
  `game/regents/tools/cut_clips.gd` into `cuts/Sword_Light_D_Cut` (0.5 s) and its `_Rec` (the game's own library,
  `game/regents/anim/regents_cuts.res`): a wide sweep across the body, facing forward; its hand fastest at 400 ms, lock
  667 ms (2026-11-02). Was `Sword_Heavy_C` x1.21, which began turned away: from the second slash the blend whipped the
  body round (Luke: "looks more jumpy"; its chest turned 1258 deg/s in the fade, the thrust's 604, the bash's 815; the
  regents suite now holds every last hit's fade to 1000). Others: M *Great Sword High Spin Attack* ·
  *Standing Melee Attack 360 High*
- [ ] **Axe, Damage: a rending cleave**: M *Standing Melee Attack 360 High / Low: Spin Attack With Axe*
- [ ] **Axe, Tank: a hook-and-yank**: Q2 `Melee_Hook` (0.47 s) + `Melee_Hook_Rec` · M *Standing Melee Attack
  Backhand*
- [ ] **Axe, Support: a horn blast**: no horn clip anywhere; M *Standing Taunt Battlecry: Battlecry With Axe*
  stands in
- [ ] **Staff (Surge), Damage: detonate**: M *Standing 2H Magic Attack 05: Pull Up And Clap Hands* · *Standing
  1H Cast Spell 01: Upwards*
- [ ] **Staff, Tank: a ward**: M *Standing 2H Magic Attack 03 / 04: Forwards Sustained* · *Standing Block Idle:
  Both Arms Out*
- [ ] **Staff, Support: mend**: M *Magic Heal: Casting A Healing Spell With One Hand* · *Spell Casting:
  Resurrection Or Summon Spell* · RK magic pack
- [ ] **Bow role shots**: the same loose; Support's flare aims up (Q2 `Bow_Aim_Up`); the full-draw hold is M
  *Standing Aim Overdraw*

---

## 6. Steps 5-7: picks, threat, content

- [ ] **Taunt shout** (Tank): M *Standing Taunt Battlecry* · *Mutant Roaring* · *Zombie Scream* · *Yelling Out:
  Stepping Forward And Yelling Out* · *Standing Yell: Long Yell*
- [ ] **Rally / war cry** (Support): M *Rallying: Rallying The Crowd* · *Cheering: Two Fists Pump* · *Sword And
  Shield Power Up* · *Great Sword Power Up*
- [ ] **Hold the line** (an all-round guard, 3 s): M *Great Sword Blocking: Blocking Idle* · *Sword And Shield
  Crouch Block Idle*
- [ ] **Execute** (a downward finishing stab): M *Sword And Shield Slash: Downward Slash* · *Great Sword Slash:
  Downward Slash* · Q2 `Sword_GroundPound_RM`
- [ ] **Bleed cut** (low): M *Great Sword Slash: Low Slash* · *Sword And Shield Slash: Crouch Slash*
- [ ] **Lunge II / a dash**: Q2 `Sword_Dash_RM`, `Shield_Dash_RM`
- [ ] **Fireball** (throw): M *Casting Spell: Conjuring Magic And Throwing* · Q2 `OverhandThrow`
- [ ] **Frost Ring** (at the ground): M *Standing 2H Magic Area Attack 01: Towards Ground*
- [ ] **Gale** (a sweeping push): M *Standing 2H Magic Area Attack 02: Pull In Blast Out* · *Wide Arm Spell
  Casting*
- [ ] **Blink**: M *Standing 1H Magic Attack 03: Upward Sweep* (+ a VFX)
- [ ] **The bow's Q** (not designed yet): candidates M *Standing Dive Forward: With Bow* (evasive) · Q2
  `Bow_RapidShoot_Loop` (a volley)

---

## 7. Later (not this overhaul)

- Shields (an off-hand later): Mixamo's *Sword And Shield* packs (block, impact, bash, crouch block).
- Potions and food: Q1 `Drink`, Q2 `Consume`, `Bandage_Loop`.
- Getting downed / a death penalty: Q2 `IdleToLay`, `LayToIdle`; Mixamo *Injured* walks and idles.
- Two-handed great swords: Mixamo *Great Sword Pack* (51 clips) has a whole set.

## 8. Gaps nothing free covers

- A **parry WITH a weapon in hand** (Mixamo's are arm blocks): KI's melee pack ("parry with each weapon"), or
  hand-key one in Blender from Q2 `Sword_Block`'s first frames.
- **Staff draw and sheathe**, **blowing a horn**: nothing found; a stand-in or hand-keyed.

Sources: [Quaternius UAL](https://quaternius.com/packs/universalanimationlibrary.html) ·
[Mixamo](https://www.mixamo.com) (licence: [Adobe's Mixamo FAQ, as quoted in its forum](https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/td-p/13234775)) ·
[Kevin Iglesias, Human Melee Animations](https://kevdev.itch.io/human-melee-animations) ·
[Rokoko free magic animations](https://www.rokoko.com/resources/rokoko-mocap-free-magic-themed-animations) ·
[CMU mocap](http://mocap.cs.cmu.edu/). Not usable: Bandai Namco's mocap set (non-commercial only).
