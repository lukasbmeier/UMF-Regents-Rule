# Regent's Rule: combat as built (2026-10-29), for the combat overhaul

> **Kept current through the overhaul.** Step 1 (2026-10-31, PROGRESS step 26: foe kits, turns, the aim lock,
> unblockable) is in §11; step 2 (2026-10-31, PROGRESS step 27: one string whose last hit is the finisher,
> follow-throughs, the parry on the seen hit, the riposte, weak and full front blocks) rewrote §2-§5, §7, §9
> and §13. Step 4 (2026-11-01, PROGRESS step 30: ROLES by the handle's shape, the sword first) added §3.3 and
> touched §2, §3.1, §5, §7, §12-§15. POISE (2026-11-02, PROGRESS step 34: a foe staggers only when the last hit
> breaks its poise, shown on the target marker) touched §4, §7, §9, §12, §13; the tutorial's yard (PROGRESS step 33:
> the sparring skeleton, the parry ring) is in §11. Where this doc and `COMBAT_OVERHAUL.md` differ, this one says
> what is built.

A complete account of the combat that exists in the game today: what the player does, what happens, every
number, how it is timed, who decides what, where it lives in the code, and what is known to be wrong or
missing. Written to be handed to someone (or another model) designing the overhaul, the way the materials
deep-dive started from a picture of what was there (`MATERIALS.md`).

Sources: the code (`game/regents/combat/`, `server/src/game/regents.rs`, `server/src/genre/regents/mod.rs`,
`sidecar/combat/action_referee.gd`, `sidecar/npc/brains/regents/foe.gd`), the baked content
(`shared/content/regents/*.json`), the hot rules (`game/regents/content/rules/regents.tres`), and
`PROGRESS.md` steps 4-16 and 23. Where the design (`RULE_DESIGN.md` §4) says something different, §15 says
so. Luke's standing calls are in `GAME.md` and `.claude/rules/regents-genre.md`; the overhaul may revisit
any of them, but it should know which ones are his.

---

## 1. The shape of it in one paragraph

Hybrid action combat in third person. **The weapon you hold is your class**: wielding an axe, sword, bow or
staff gives you that kit's moves. Melee swings are aimed by your facing (the body faces the camera in a
fight) and are **judged by the world's referee** (a headless Godot process, the sidecar) as a sweep
against everyone where you saw them. Arrows and spells are **real bodies the referee flies**. The SERVER
(the SpacetimeDB module) decides what every hit does: damage, block, parry, stagger, flinch, XP, death,
loot. The client predicts its own movement and swing timing and never decides an outcome. There is no
global cooldown: each ability has its own, and the swing's **animation lock** paces melee. Foes
(skeletons) fight with the very same kits and are driven by brains in the referee.

---

## 2. Inputs (the keys, as bound today)

| Input | Melee kit (axe, sword) | Bow | Staff |
|---|---|---|---|
| **LMB tap** | the next step of the string; its last is the FINISHER (no hold-LMB: the heavy merged in) | — | Bolt |
| **LMB hold** | — | draw; **release looses** (a release under 120 ms lets the draw go) | — |
| **RMB tap** | THE GUARD: a parry, judged on the hit as you saw it (§5) | lets the draw go AND parries with the stave | a parry |
| **RMB hold** | the block, front-only: a FULL guard with a guard handle (a sword's crossguard hilt: 25 % through), else light (60 %) | (the block) | (the block) |
| **Ctrl** | dodge roll (everyone, any weapon or none) | same; ends the draw | same; ends a cast |
| **Q E R F** | the kit's skills, at mastery ranks 1 / 3 / 6 / 9, **in stance only** | (none yet) | Fireball, Frost Ring, Blink, Gale |
| **Tab** | next target in front (25 m, a 120° arc, nearest the crosshair first): a ring under it, its health at the top | same | same |
| **Esc** | drops the target (the menu opens on the next Esc) | | |
| **I** | the bag: Wield / Put away on each weapon | | |
| Alt | slow-walk (Ctrl's old job) | | |

- **Stance**: you have a target, or you swung in the last 5 s (`stance_s`). In stance the body faces where
  the camera looks, and Q/E are skills. Out of stance E works what is in front of you (stations, nodes),
  and a key with no skill on it is never taken.
- **Targeting is a reference, not aim**: a melee swing hits what it sweeps, target or not. The bow and the
  Bolt auto-aim at a Tab target (the server rolls the hit); with no target they fly where you look.
  **Whatever your swing, arrow or spell hits becomes your target** if you have none.
- Only foes and dummies can be targeted (an entity with health, alive, not a player, not a skilling
  character). No duels, no PvP.

Client code: `CombatComponent._unhandled_input`, `_process` (`game/regents/combat/combat_component.gd`).

---

## 3. The kits (content: `game/regents/content/kit/`, baked to `shared/content/regents/kit.json`)

A `KitDef` has: a key, the mastery skill it trains, its STRING (`light`, in order; its last step is the
FINISHER), a FOLLOW-THROUGH per step (`follow_ms`, 200 each: how long after a step lands the next may start),
its skills (with the ranks they unlock at, default 1/3/6/9), `unblockable` (a foe's finisher), `draws` /
`draw_full_ms` for a bow, a `resource` for a caster, and a `timing_set` (the animation set whose clip
lengths ARE the locks, below). The string's window is the hot rule `regents.combo_window_ms` (2 s). Retired
with the heavy (2026-10-31): `heavy`, `heavy_hold_ms`, `chain_ms`, the kit's `combo_window_ms`.

### 3.1 Every ability (`content/ability/`; the foundation's `AbilityDef`)

| id | name | kit / slot | damage | wind-up ms | cooldown ms | reach m | radius m | lock ms (clip) |
|---|---|---|---|---|---|---|---|---|
| 40001 | Slash | sword step 1 | 8 | 220 | 450 | 1.7 | 0.45 | 442 |
| 40002 | Slash (second) | sword step 2 | 10 | 240 | 450 | 1.7 | 0.45 | 417 |
| 40003 | Piercing thrust | sword step 3 with a plain grip (the plain role's FINISHER) | 26 | 380 | 700 | 2.4 | 0.5 | 734 |
| 40022 | Pommel bash | sword step 3 with a crossguard hilt (stagger x1.5: 1.2 s) | 14 | 340 | 700 | 2.1 | 0.5 | 635 |
| 40023 | Rallying cut | sword step 3 with a banner hilt (heals 8 within 6 m) | 14 | 400 | 700 | 2.1 | 0.9 | 579 |
| ~~40004~~ | ~~Heavy cut~~ | retired 2026-10-31 (the server refuses it) | | | | | | |
| 40005 | Lunge | sword skill (rank 1, Q) | 16 | 250 | 6000 | 3.2 | 0.45 | 1250 (lunges: moves the body) |
| 40006 | Chop | axe step 1 | 12 | 320 | 550 | 1.6 | 0.45 | 594 |
| ~~40007~~ | ~~Chop (second)~~ | retired 2026-10-31 (the server refuses it) | | | | | | |
| 40008 | Overhead | axe step 2, the FINISHER | 26 | 550 | 900 | 1.9 | 0.55 | 1048 |
| 40009 | Cleave | axe skill (rank 1, Q) | 18 | 350 | 7000 | 2.2 | 0.9 | 875 |
| 40010 | Dodge roll | everyone | — | 100 | 1500 | — | — | (the roll, 550 ms) |
| 40011 | Loose | bow | 30 (full draw) | 100 | — | range 40 | — | 556 |
| 40012 | Bolt | staff LMB | 9 | 100 | 600 | range 25 | — | 500 |
| 40013 | Fireball | staff Q (Sorcery 1) | 20 | 100 | 7000 | range 30 | — | 500 |
| 40014 | Frost Ring | staff E (Sorcery 3) | 6 | 100 | 14000 | range 20 | — | 333 |
| 40015 | Blink | staff R (Sorcery 6) | — | 100 | 15000 | 8 m | — | 500 |
| 40016 | Gale | staff F (Sorcery 9) | 6 | 100 | 20000 | 8 m | — | 333 |

All melee abilities have a sweep height of 0.9 m. "Lock" is the length of the ability's clip in the kit's
`timing_set` at its playback speed (`KitDef.lock_ms`, baked for the server): change a clip's speed in the
animation set and the swing's timing follows on both sides. A lock is never shorter than the wind-up +
`KitDef.MIN_RECOVERY_MS`. **Cooldowns never outlast locks** for lights and heavies (a test enforces it),
so in practice the lock is what paces them; skills have long cooldowns of their own.

The sword's E/R/F and the axe's E/R/F are empty (only Q exists). The bow has no skills.

### 3.3 Roles by the handle (step 4, 2026-11-01; `COMBAT_OVERHAUL.md` §5, Luke's calls in `GAME.md`)

**The handle's SHAPE sets the role; its MATERIAL still sets the trait.** The role changes only the string's
last hit, and carries its guard and its threat. SHOW, DON'T NAME: the player sees a BADGE (a point, a shield, a
cross) and what the handle does; "Damage", "Tank", "Support" and "finisher" are for code and docs only.

| role (`RoleDef`, `content/role/`) | sword handle (items, ids pinned) | its last hit | guard | threat (stored, step 6) |
|---|---|---|---|---|
| Damage (40001, the PLAIN role) | the grip: Grip 40013, Oak 40016, Yew 40017 (any grip that names no role) | Piercing thrust 40003: 26, 2.4 m, 380 ms | light (60 %) | 100 % |
| Tank (40002) | Crossguard grip 40040, Oak 40042, Yew 40044 | Pommel bash 40022: 14, 340 ms, stagger x1.5 (1.2 s) | FULL (25 %) | `regents.guard_threat_pct` (250 %), scope `guard_threat_bosses_only` (off: every foe) |
| Support (40003) | Banner grip 40041, Oak 40043, Yew 40045 | Rallying cut 40023: 14, 400 ms, a wider sweep (0.9 m), heals players within 6 m for 8 | light (60 %) | 100 % (healing no more than damage) |

- **Items** (since 2026-11-01, PROGRESS 32: one family of three SHAPES for every tool and weapon): the grip (the
  plain handle, renamed), the crossguard grip (40010) and the banner grip (40011), each in every wood by Make the table,
  each with its wood's trait, the same cost, time and Crafting rank as the plain grip of its wood (recipes
  40032-40037). Any tool or weapon takes any shape; the shape gives its role only on a weapon whose kit has roles (the
  sword so far). One mesh.
- **The role map** (`KitDef.roles`, a `KitRole` each: role, last hit, `stagger_pct`, `heal`, `heal_radius_m`,
  `does`: the one line the player reads). The plain role's last hit is the string's own last step.
- **The server decides which last hit fires** (`resolve_ability`, template 1.7.1, DECISIONS #303): a player
  pressing the string's last step fires the one their wielded weapon's handle gives (`role_of`: the first
  part, `"p"`, whose shape gives a role, else the plain one), whatever the client asked for; a build from
  before roles asks for the thrust and gets its handle's. The client predicts the same (`CombatComponent.role()`,
  `KitDef.light_at`): its clip and its lock.
- **The rallying cut's heal**: landing on a foe (not a training dummy, as Thirsting), every other living,
  online player within 6 m gets 8; its user all 8 alone, `regents.rally_self_share_pct` (50 %) of it with
  players near; each through `healing_received` (Thirsting). One hit per swing (`resolve_action` lands one).
- **Re-hilting** is the refit (§9 of `MATERIALS.md`): the new hilt used up, the old one LOST, plus
  `regents.refit_bars` of the head's metal.
- **A dropped sword rolls its handle's shape** (template `loot_data`, #303): of the plain-wood handles,
  weighted by `regents.drop_handle_damage_pct` / `_tank_pct` / `_support_pct` (50 / 25 / 25), its data
  `{"h":H,"p":[H],"t":[]}`. NO LOOT TABLE DROPS A SWORD YET: dormant until one does.

### 3.2 The weapons (items; `content/item/`)

| item | kit | weapon_damage_pct | tier | as a tool |
|---|---|---|---|---|
| Copper axe (starter kit) | axe | 70 | 1 | axe tier 1 |
| Iron axe | axe | 100 | 2 | axe tier 2 |
| Steel axe | axe | 140 | 3 | axe tier 3 |
| Copper sword | sword | 70 | | |
| Iron sword | sword | 100 | | |
| Steel sword | sword | 140 | | |
| Yew bow | bow | 100 | | |
| Yew staff | staff | 100 | | |
| Copper arrows (ammo) | | ammo 100 | | |

Axes are both weapons and tools (a starter's Copper axe chops trees and fights). Weapons are made from
parts (`MATERIALS.md`: a head or blade, a handle, rivets/binding), and carry a quality 0-1000 and up to 1/2/3
traits by grade (Common/Fine/Masterwork; §9). **Power** (the bag's one number) is the weapon's damage % with
its quality in: exactly what the server deals.

---

## 4. Melee: the swing's timeline (server and client agree, ms after the press)

```
press ─► 0 ── wind-up ──► HIT (judged) ── +chain_ms ─► (next light may start) ── … ──► LOCK ends
         │◄──── committed: walk only (Swinging status) ────►│+swing_hold_ms (80)
         │◄────────────── the whole clip holds you (lock) ─────────────────────────────►│
```

- **The hit lands at the wind-up.** The referee judges it then (§6).
- **The lock** = the clip's length (table above). Until it ends nothing else starts, except:
- **The follow-through** (2026-10-31): the string's NEXT step may start from `wind_up + follow` (the step's
  `KitDef.follow_ms`, 200 ms after its hit), canceling the rest of the recovery. (It was `chain_ms`, 60 ms:
  why "spamming LMB cut the second swing's animation", #8.)
- **The string**: each tap is the next step if it comes within `regents.combo_window_ms` (2 s) after the last
  step's lock, else step 1 again; a guard press restarts the window, a roll ends the string. The server
  refuses a step out of order ("out of the combo's order"). After the finisher the string starts over. A
  sword's string: Slash 220, Slash 240, the finisher 380 ms wind-ups; an axe's: Chop 320, Overhead 550.
- **The buffer (client)**: a press while you are held is QUEUED (one deep; the latest press wins) and fires
  the moment it may; it lapses after `combo_window_ms`. Mashing gives one swing per animation, never faster,
  and no press is lost. This buffer is client-side only; the server has no queue.
- **Committed**: from the press until `swing_hold_ms` (80 ms) after the hit you can only walk: the server's
  **Swinging** status (speed ×0.25, no sprint, no jump; dash allowed so a roll is a full roll) and the
  client's slow-walk. In the recovery you move freely, and running (above 1.6 m/s, the adventurer's
  `action_cancel_speed`) cuts the animation's tail; the hit has already landed. `swing_slack_ms` (120 ms):
  the server lets go of the status that much early so a client already running is never snapped back.
- **No swing in the air or mid-roll**: the server refuses both ("not in the air", "still rolling"); the
  client holds the press until you land or the roll is over.
- **No swing while blocking** ("lower your block to swing").
- **The finisher** (the string's last step; the heavy merged in, 2026-10-31): its wind-up has **armor**
  (never flinched); it **flinches** a step in its wind-up that it hits (cancels it: it never lands; the
  **Flinched** status for `flinch_ms`, 350 ms); and when it lands unblocked it **staggers** (`stagger_ms`,
  800 ms: no acting, a cast let go): a player always, a foe or a dummy only when it breaks their POISE (§7, 8).
  Other steps never interrupt anything. Foes use the same grammar: a skeleton's finisher staggers you.
- **Lunge** (sword Q): moves the body itself; its animation is held its whole clip.
- **Animations**: swings play in place (root motion taken out); others see your swing from the same
  ability event; a hit plays `react.hit` on what was hit, held while Flinched/Staggered.

Server: the `swing` table (one row per fighter: ability, start, wind-up, lock, light step, canceled),
`combat_state` (combo step, when, blocking, block_since); `may_fight` (every refusal), `fought` (records
the swing, sets Swinging), `hit` (what a hit does). Client: `CombatComponent.may_start`, `swing`, `press`,
`_try`, the queue in `_process`.

---

## 5. Defense: block, parry, roll

- **The guard** (RMB, every kit; `guard(on, seen_delay_ms)`, 2026-10-31; `block` still works for old builds):
  - **The parry** (the press): a hit **in front** landing within `parry_ms` (200 ms) before the press, or
    `parry_late_ms` (50) after, deals **0**, and the ATTACKER is **Staggered** for `stagger_ms` (800 ms).
    It is judged on the hit **as the player saw it**: the press's arrival less its trip (half the round trip
    the server measured, #210, or the client's own until one is) and how late the client shows another's
    swing (its half round trip), at most `foundation.rewind_max_ms`. Every hit on a player WAITS for a press
    still on its way (`held_hit`, until ~320 ms after it landed; an unparryable one as long, so hits keep the
    spacing they landed with), then is dealt as judged.
  - **The whiff lockout**: a press under `parry_whiff_ms` (400) after one that parried nothing parries
    nothing (it still blocks); after a parry, never.
  - **The riposte**: the string's first step begun within `riposte_ms` (1 s) of a parry deals
    `riposte_damage_pct` (150 %); the next tap after a parry is always that first step. A bow's draw begun in
    the window fills in `riposte_draw_pct` (50 %) of its time. (The staff's riposte is not built.)
  - **The block** (held): the **Blocking** status (speed ×0.5, no sprint/jump); a hit **in front** deals the
    role's share (§3.3): a full guard's `block_damage_pct` (25 %) with a guard handle (the crossguard hilt),
    else the light `weak_block_pct` (60 %). **Front-only**: `guard_arc_deg` (120°) for the parry and the block
    both; from behind, full damage. An unblockable swing (a foe's finisher) goes through either.
- **Dodge roll (Ctrl)**: the Dodge roll ability (cooldown 1500 ms) gives **Rolling** for `roll_ms`
  (550 ms): not hittable (i-frames), can act, no jump/sprint. The movement is the foundation's **dash**
  (the adventurer's profile: a 16 m/s impulse over 15 ticks, its own cooldown 84 ticks = 1.4 s), moved by
  the client the moment Ctrl is pressed (predicted) and bounded by the server like any movement. Ctrl only
  dashes when the roll is taken. The roll plays its Roll animation whole, facing the way it goes.
  - In a swing's **wind-up** a roll **cancels** the swing (it never lands, on screen or on the server).
    In its **recovery** a roll ends it. Either way the combo is over and the queue is cleared.
  - A roll ends a draw and lets a cast go (nothing paid).
  - **No roll in the air** (since 2026-10-29 the server refuses it too: "no roll in the air"): Ctrl in the
    air is held and rolls as you land, within 1.5 s.
  - The HUD has a thin roll bar refilling over the cooldown.

---

## 6. How a melee hit is judged (the referee, `sidecar/combat/action_referee.gd`, foundation)

1. The client calls `use_ability_seen(ability, target 0, aim = its facing, predicted id, view_delay_ms)`.
   `view_delay_ms` is how far behind the server this client draws everyone else (its interpolation plus
   half its round trip).
2. The module checks the use (`may_fight`, cooldowns, statuses) and, for a **judged** ability, queues an
   `action_request` for the referee (refused when no referee is online: "nobody is judging world N").
3. The referee keeps every entity's movement history. At the request's landing time (+80 ms to settle) it
   places the user where it was, everyone else where they were `rewind` ms earlier (the user's view delay,
   capped at `foundation.rewind_max_ms`, 150 ms: favors the attacker), and sweeps a capsule of the
   ability's `radius` and `height` forward `reach` meters along the aim, against the level's walls and the
   bodies. With `foundation.referee_two_sides` ON (Regent's Rule turns it on), the sweep passes through its
   user's own side (players, or everyone else) to the first of the other.
4. It reports the first body hit (`resolve_action`). The module checks again (who may hurt whom) and the
   genre's `hit` does the rest (§7). The referee only proposes.

Only "people" can be hit (a player, anything a brain drives, a dummy), in a status that is targetable and
hittable (Rolling and Slain are not hittable).

---

## 7. What a hit does (server, `game/regents.rs` `hit`)

In order:
1. `hurts`: a foe hurts only players; a player hurts anything but players (no PvP, no friendly fire).
2. A swing canceled in its wind-up (roll, flinch) does nothing.
3. A finisher flinches a target in a step's wind-up (§4).
4. **The guard** (§5), for a player hit from in front by anything not unblockable: a parry already pressed
   takes it; one that may still arrive holds it (`held_hit`) until it could; then it is dealt (`deal`).
5. **Damage** = `ability damage × weapon_damage_pct/100 × quality × mastery` (× `riposte_damage_pct` for a riposte)
   - quality: `1 + quality/5000` (+0 to +20 %); mastery: `1 + 3 % per rank above 1` (at most +27 % at
     rank 10). A foe uses its `FoeDef.damage_pct` and no quality or mastery.
   - then the weapon's **traits** (§9) on damage, by the action (`basic`, `combo_last`, `skill`)
     and the target's health and family.
6. **Through the block** if it was up and faced the hit (§5).
6. A **training dummy** never falls (it keeps 1 hp) and is whole again `dummy_reset_s` (4 s) after its last
   hit; `dummy_hp` 500.
7. The damage is dealt (`damage_entity`); the target's regeneration waits (`regen_delay_s`).
8. **The last hit staggers** what it lands on unblocked: a PLAYER every time; a FOE or a DUMMY only when it breaks
   their **POISE** (Luke, 2026-11-02): every melee hit wears it (`poise_light` 10, the last `poise_finisher` 40, Heavy
   ×1.35 on the last), a light never below 1; broken, it is whole again, the stagger (the role's `stagger_pct`: the
   pommel bash ×1.5), then **Steadied** (`steadied_ms` 3 s after the stagger: nothing wears it); unhit for
   `poise_regen_ms` (8 s) it is whole. A foe's poise is its `FoeDef.poise` (70), a dummy's `dummy_poise` (50); a
   parry staggers whatever the poise (a punish). Shown on the TARGET MARKER: an arc round the ring under your target
   fills as it wears, pale to red, bursts as it breaks, gray while Steadied (no bar: Luke); Thirsting heals (not off a dummy); the rallying cut heals players
   near (§3.3, not off a dummy).
9. **Mastery XP** to the attacker: `damage × combat_xp_per_damage (0.5) × share`, at least 1. The share is
   `dummy_xp_pct` (50 %) on a dummy, else the foe's `xp_pct` (100 %). The XP goes to the kit's skill
   (Swordsmanship, Axemanship, Archery, Sorcery).
10. **The meta tally**: every player hit on a foe (not a dummy) adds to the hour's damage by weapon type;
    an hour's close writes each weapon's share and an ALARM when one passes 45 % in 50+ hits (telemetry).
11. If it died: `fell` (§11).

Health: a player has 100 (the foundation's default). **Regeneration**: out of a fight (`regen_delay_s`,
8 s after the last hit that landed), `regen_pct_per_s` 4 % of max a second, players and foes alike (a foe led
off heals as it walks home). A placeholder until food or potions are decided.

---

## 8. Ranged

### 8.1 The yew bow (kit `bow`, skill Archery)
- **Hold LMB: draw.** The **Drawing** status (speed ×0.25, no sprint, no jump; you walk), the arms draw
  then hold aim on the upper body only (the legs keep walking). A bar fills over `draw_full_ms` (800 ms).
  **Release: loose** (`loose_arrow`); under 120 ms the draw is let go. RMB or a roll lets it go. Not in the
  air, not mid-roll or mid-swing, not with no arrows ("No arrows").
- **The draw's power**: `min + (1-min) × draw/full`, `draw_min_power_pct` 30 %. The server times the draw
  from `draw_bow` to `loose_arrow`.
- **With a Tab target** within `bow_range_m` (40 m) the server **rolls the hit**: `hit_near_pct` 95 % at
  `hit_near_m` 8 m falling evenly to `hit_far_pct` 55 % at `hit_far_m` 40 m, minus `hit_moving_pct` 15 if
  the target is moving (or rolling). A hit is aimed on a ballistic low arc to land on the target, at a
  speed from `arrow_speed_min` 20 to `arrow_speed_max` 50 m/s by the draw; a miss is aimed beside it. The
  HUD shows the chance while you aim. **With no target** it flies along your look.
- **The arrow is a real body** (BodyDef 40001) the referee flies, nose into the wind; what it hits is
  reported and the server deals: `30 × power × bow % × arrow % × quality × mastery`, at `point_blank_pct`
  60 % inside `point_blank_m` 4 m. An arrow in a foe stays in it; when it falls, `arrow_recover_pct` 40 %
  of them come back to whoever shot them. Arrows come from the bag (no quiver slot).

### 8.2 The Staff (kit `staff`, skill Sorcery, resource Mana)
- **Mana**: the Staff's only (no other kit has a resource). Max 100; fills 10/s out of a fight and 4/s in
  one (a fight: 5 s after the last spell). Given on wielding, kept as it is when you change weapons. Never
  ticks (it is worked out from the time, template #270). Paid **when a spell lands**, not at press.
  `mana_cost_pct` scales every cost live.
- **Casting**: through the same press, queue and lock as a swing; a spell with a cast time shows a cast
  bar and a casting pose; a press meanwhile is held by the client and sent when the cast ends (client
  only: the server refuses "already casting"). A cast of 0.8 s or more **roots**: moving more than 0.5 m
  off where it began, or rolling, lets it go (`cancel_cast`, nothing paid). `cast_time_pct` scales every
  cast live. Each spell has its own cooldown (no GCD).
- **The spells** (`content/spell/`, a `SpellDef` of one of four kinds):

| spell | kind | cost | cast | cooldown | what it does |
|---|---|---|---|---|---|
| Bolt (LMB) | bolt | 0 | instant | 0.6 s | a missile (32 m/s, straight) at your target (the hit rolled like the bow's) or where you look: 9 |
| Fireball (Q, rank 1) | bolt | 25 | 0.6 s (walk) | 7 s | a missile (20 m/s): 20 to what it hits, 40 % to anything within 3 m, Burning 3/s for 3 s |
| Frost Ring (E, rank 3) | area | 30 | 1.0 s (roots) | 14 s | a 4 m circle where the crosshair meets the ground (within 20 m), shown filling, lands 1 s later: 6 and Slowed (×0.6, no sprint) for 3 s; foes only |
| Blink (R, rank 6) | blink | 20 | instant | 15 s | 8 m the way you look, at once, onto ground you can stand on |
| Gale (F, rank 9) | cone | 35 | instant | 20 s | everything within 8 m and 45° of your look: 6 and pushed back at 9 m/s |

Missiles are bodies the referee flies (Bolt, Fireball need a referee running). Server: `casting`,
`spell_cooldown`, `missile`, `spell_area`, `burning`, `spell_timer` (scheduled); `cast_spell`,
`cancel_cast`, `land_spell`, `launch_missile`, `missile_hit`, `land_area`, `spell_hurt`, `tick_spells`.

---

## 9. Traits on weapons (template DECISIONS #275; `LOOT_AND_STYLES.md` §2, §6)

A trait changes how an item plays, **never its Power**, and every trait trades. Content
(`game/regents/content/trait/`), each made of atoms (`what`, `on` an action, a condition, a mult or value).
A crafted weapon holds 1/2/3 traits by grade (`crafted_traits_*`), chosen from what its parts offer.
`foundation.trait_strength_pct` turns every trait up, down or off live.

| trait | on | gives | costs |
|---|---|---|---|
| Balanced | any weapon | basic attacks' recovery ×0.85 (a lock of 900 becomes 825) | skills' damage ×0.9 |
| Heavy | melee | the last hit wears 35 % more poise (`poise`, 2026-11-02; was the stagger ×1.35) | basic recovery ×1.15 (975 for 900) |
| Brutal | any weapon | ×1.25 damage when the target is under 30 % health | ×0.9 when it is above |
| Thirsting | any weapon | basic hits heal you 5 % of their damage | out-of-fight regeneration ×0.85 |
| Swift Draw | bow | draw time ×0.8 (640 for 800) | arrow speed ×0.85 |
| Hunter's | bow | ×1.15 against beasts | ×0.85 against humanoids |

Recovery is the part of the lock after the wind-up: `lock = wind_up + (lock - wind_up) × recovery`. The
client predicts the same lock. Waiting on systems that do not exist: Keen (crits, Bleeding), Padded and
Warded (armor), Reaching (per-wielder reach for the referee).

---

## 10. Statuses that combat uses (`content/status/`; the foundation's status system)

| status | id | lasts | speed | can act | dash | jump | sprint | hittable | targetable |
|---|---|---|---|---|---|---|---|---|---|
| Rolling | 101 | `roll_ms` 550 | ×1 | yes | yes | no | no | **no** | yes |
| Blocking | 102 | while held | ×0.5 | yes | yes | no | no | yes | yes |
| Staggered | 103 | `stagger_ms` 800 (the pommel bash 1200) | ×0 (rooted, 2026-11-01) | **no** | no | no | no | yes | yes |
| Swinging | 104 | wind-up + 80 − 120 slack | ×0.25 | yes | yes | no | no | yes | yes |
| Flinched | 105 | `flinch_ms` 350 | ×0.5 | **no** | no | no | no | yes | yes |
| Slain | 106 | until up / gone | 0 | no | no | no | no | no | no |
| Drawing | 107 | while drawn | ×0.25 | yes | yes | no | no | yes | yes |
| Slowed | 108 | the spell's 3 s | ×0.6 | yes | yes | yes | no | yes | yes |

A player holds one status at a time (the foundation's `status_state`: one row per entity). Burning is its
own table, not a status.

---

## 11. Foes (`content/foe/`, `FoeDef`; brain `sidecar/npc/brains/regents/foe.gd`)

| foe | kind | kit | hp | damage % | xp % | family | poise |
|---|---|---|---|---|---|---|---|
| Skeleton warrior | 103 | sword | 120 | 50 | 100 | undead | 70 |
| Skeleton axeman | 104 | axe | 150 | 55 | 100 | undead | 70 |
| Sparring skeleton (the tutorial's yard, `sparring_1`) | 105 | sparring_sword (950 / 950 / 1200 ms, the last glints) | 1500 | 10 | 0 | undead | 70 |

The sparring skeleton notices you at 4 m (leash 8 m), rests 2.5 s, drops nothing, and shows the PARRY RING
(`FoeDef.parry_ring`): the only foe with it (PROGRESS step 33).

Behavior (FoeDef defaults, both): notices a player within `notice_m` 10 m **and in sight** (a ray at eye
height against the level); chases at 4.2 m/s (a player runs 5, so you can always get away); stops at
`reach_m` 1.9 m and fights; every `heavy_every` 3rd swing is its heavy; each swing waits out the last one's
lock; a combo ends with `rest_ms` 900 (your opening); past `leash_m` 25 m from home it walks back, deaf to
everyone until home. Since 2026-10-29 its chase follows the level's walk map round obstacles, and a target
lost from sight is chased to where it was last seen for `lose_sight_ms` (2500) before it gives up.
Since 2026-11-11 ITS STRING FOLLOWS ITS TARGET (Luke: the wolves' second and third bites hit air): a target that
steps out of `reach_m` between two swings is run down once the last swing's lock is over, and the string goes on
where it stopped; out of reach longer than `string_chase_ms` (1500, per foe) the string is dropped, and the next
is its first swing again after its rest (the chase counts toward it). It never swings at a target out of reach.

- A foe fights with its kit exactly as a player: the same abilities (`use_ability_as`), wind-ups, Swinging,
  flinches, the same referee. It does not block, roll, parry or use skills.
- **Slain**: the Slain status. Each player who did at least 5 % of the recent damage (60 s) gets mastery XP
  for their hits and their OWN loot roll (personal rolls with pity, template #268), dropped as sacks on
  the ground: yours alone for 60 s, then anyone's for 60 s (template #269). The body lies `foe_corpse_s`
  (6 s); it comes back on its point `foe_respawn_s` (60 s) after it fell. Loot: the Skeleton camp table
  (copper ore 60 %, iron ore 30 %, an uncut gem 4 % with pity).
- **A player slain** gets up at the spawn, whole, `player_respawn_s` (5 s) later. **No death penalty**
  (a placeholder).
- The foe bench (`game/regents/workbench/foe_workbench.tscn`) shows a foe's damage a second, time to kill a
  player and to be killed by each weapon, and its loot.
- Placement: level points of kind = the foe's key. The continent's camps are a TEST placement (Luke's own
  replaces it): 34 warriors and 17 axemen.

---

## 12. Feedback and HUD

- Numbers float up from what was hit; a little shake; a heal floats green.
- Flashes: what you hit lights white, you light red and the screen's edge pulses red (more for a bigger
  hit); a hit the guard stopped flashes steel blue "Blocked"; a stagger flashes gold (no word since 2026-11-02:
  the status bar under the target's health says it); your own parry says "Parried".
- **The target marker** (a gold ring under your target) carries its POISE (2026-11-02): an arc just outside it fills
  as poise wears, pale to red, bursts as it breaks, gray while Steadied (`CombatComponent._place_poise_arc`).
- **The parry ring** (`FoeDef.parry_ring`, the tutorial's sparring skeleton only): a ring closes on each swing, shut
  as the blow lands.
- **Weight** (Luke's feedback 4098, 2026-10-31): a SPARK where the blow lands (warm, bigger on a hit of 20+,
  steel on a block, gold on a stagger), and a HIT-STOP: both bodies' animation stands still
  `regents.hitstop_ms` (60), a big hit or a stagger `regents.hitstop_big_ms` (110); the local player's own
  swing is not held (it played before the server's word). The template's `hold_still` (#301).
- **The stagger reads** (2026-11-01, PROGRESS 31): the guard knocked aside once (`react.stagger`, Q2
  `Idle_Shield_Break`), then a dazed sway held for its length (`react.dazed`, Q2 `Zombie_Idle`), ROOTED (speed 0);
  the player and the skeletons alike; a flinch keeps the quick hit react. Under the target's health, a draining bar
  for each status done to it ("Staggered 1.1 s") and each effect.
- **A swing comes back**: each strike is followed by its recovery (`recover.<id>`, the clip's `_Rec`), cross-faded in
  as it ends; the lock is still the strike's. Sparks, streaks and the glint are soft light; the flash is a rim.
- **Death interrupts at once** (feedback 4099): the server cancels a falling fighter's swing and drops its
  hits held for a parry, and lands nothing a dead fighter swung; on screen the swing fades as the fall
  begins (template #301). **Swing follows swing** with a cross-fade (two action slots, #301).
- Bottom left: health, the Staff's mana while wielded, the roll's cooldown bar. The action bar text names
  the kit's keys, the string by its moves' own names, its last the handle's, and the guard by what it does
  ("Iron sword:  LMB Slash - Slash (second) - Pommel bash   RMB tap parry, hold for a full guard   Ctrl roll
  Tab target | Q Lunge"). Never a role's name nor "finisher".
- **Roles shown** (§3.3): the craft window's handle list puts each handle's BADGE beside it and, under the row,
  one line on what the picked one does; the bag puts the badge in a sword's slot corner, and its tooltip and
  detail name its last hit and say what the handle does (`RegentsRoleBadge`, `game/regents/ui/role_badge.gd`).
- Tab target: a ring under it, its health at the top. Bow: the draw bar and "to hit N %". Staff: each
  spell's cost and cooldown, a cast bar, an area spell's ring filling on the ground. A burning thing
  flickers with fire.
- Refusals come back as a line in a small column at the right (feedback 4097: not the middle of the screen),
  three at most ("No skill on that key yet", "Sorcery rank 3 needed", "No arrows"). A swing or a roll pressed
  while staggered, flinched or slain waits until you can act, rather than being sent to be refused.
- `game/regents/combat/hit_feedback_component.gd`, `combat_look.gd`, `spell_looks.gd`, `regents_hud.gd`.

---

## 13. Every hot rule combat reads (`regents.*`, live on the Rules page; Luke's Escape → Rules (admin))

| rule | value | what |
|---|---|---|
| roll_ms | 550 ms | how long Rolling lasts (i-frames) |
| combo_window_ms | 2000 ms | the string's next step this long after a lock (2026-10-31; was the kit's 900) |
| parry_ms / parry_late_ms | 200 / 50 ms | a guard press this long before (or after) the hit as seen parries |
| parry_whiff_ms | 400 ms | a press this soon after one that parried nothing is no parry |
| riposte_ms / riposte_damage_pct / riposte_draw_pct | 1000 ms / 150 % / 50 % | the riposte window, its damage, a bow's draw in it |
| stagger_ms | 800 ms | a parried attacker, a player a last hit lands on, or a foe whose poise breaks, is staggered this long |
| poise_light / poise_finisher | 10 / 40 | what a melee hit wears off a foe's or a dummy's poise (a light never below 1; Heavy x1.35 on the last) |
| poise_regen_ms / steadied_ms | 8000 / 3000 ms | unhit this long, poise is whole; after a break's stagger, this long nothing wears it |
| dummy_poise | 50 | a training dummy's poise (a foe's is `FoeDef.poise`, 70) |
| block_damage_pct | 25 % | the full guard (a guard handle: the crossguard hilt): what a blocked hit still deals |
| weak_block_pct | 60 % | the light guard (a plain or banner handle) |
| guard_threat_pct / guard_threat_bosses_only | 250 % / off | the guard handle's threat and its scope (stored for step 6; nothing targets by it yet) |
| rally_self_share_pct | 50 % | the rallying cut's heal for its user with players near (alone: all of it) |
| drop_handle_damage_pct / _tank_pct / _support_pct | 50 / 25 / 25 | a dropped weapon's handle shape, by weight |
| guard_arc_deg | 120° | the parry and the block stop only a hit inside this arc in front |
| flinch_ms | 350 ms | a finisher's flinch |
| swing_hold_ms | 80 ms | committed this long after the hit |
| swing_slack_ms | 120 ms | network forgiveness on swing and roll timing |
| combat_xp_per_damage | 0.5 | mastery XP per point of damage |
| dummy_xp_pct / dummy_hp / dummy_reset_s | 50 % / 500 / 4 s | the training dummy |
| foe_corpse_s / foe_respawn_s / player_respawn_s | 6 / 60 / 5 s | bodies and returns |
| regen_delay_s / regen_pct_per_s | 8 s / 4 % | out-of-fight regeneration |
| draw_min_power_pct | 30 % | the weakest loose |
| arrow_speed_min / max | 20 / 50 m/s | by the draw |
| bow_range_m, hit_near_m, hit_far_m, hit_near_pct, hit_far_pct, hit_moving_pct | 40 m, 8 m, 40 m, 95 %, 55 %, 15 % | the ranged hit roll (bow and Bolt) |
| point_blank_m / point_blank_pct | 4 m / 60 % | arrows up close |
| arrow_recover_pct | 40 % | arrows back from a kill |
| mana_cost_pct / cast_time_pct | 100 % / 100 % | every spell's cost and cast time |
| meta_period_s, meta_alarm_pct, meta_alarm_min_hits, meta_keep_days | 1 h, 45 %, 50, 14 | the weapon meta |
| grade_fine_q / grade_masterwork_q, crafted_traits_* | 400 / 800; 1/2/3 | grades and trait room |

Foundation rules combat reads: `foundation.rewind_max_ms` 150, `foundation.referee_two_sides` (on here),
`foundation.trait_strength_pct` 100, `foundation.loot_*`, `foundation.ground_*`.

Content numbers (per ability, kit, spell, foe, item, trait) are in the Inspector and baked; changing them
needs a bake and a publish. Hot rules need neither.

---

## 14. The technical picture

### 14.1 Who decides what
| | client (Godot) | server (SpacetimeDB module, Rust) | referee (headless Godot sidecar) |
|---|---|---|---|
| movement, the dash | predicts and sends inputs (60 Hz, 3 frames a call) | bounds every frame (a speed envelope by status; deep water refused) | — |
| swing timing | predicts the lock, buffers presses | refuses an early, out-of-order, airborne, mid-roll or blocking swing; records the swing | — |
| melee hit | never | checks, then deals damage / block / parry / flinch / XP | judges the sweep with rewind |
| arrows, missiles | draws them | aims them, rolls the hit, deals damage | flies them, reports contacts |
| area, cone, blink | shows the ring, sends the point | judges and lands them (scheduled) | — |
| foes | draws them | spawns, deals their hits, death, loot, respawn | runs their brains (think a few times a second; input like a player's) |

Rule 13: clients send inputs; servers derive outcomes. No reducer takes a client's result.

### 14.2 The rows and reducers
- Player-callable: `wield`, `unwield`, `guard` (and `block`, old builds'), `use_ability` / `use_ability_seen` (the foundation's; every
  swing and the roll), `draw_bow`, `loose_arrow`, `cast_spell`, `cancel_cast`, `set_item_traits` (dev).
- Tables (genre): `wielded` (public), `combat_state` (combo, block), `swing` (the swing's timeline),
  `guard_state` (private: the last counting press as seen, the last parry), `held_hit` (private, scheduled:
  a hit waiting for a parry that may still arrive),
  `foe`, `foe_kill`, `hurt` (recent damage for loot shares), `arrow`, `stuck_arrow`, `casting`,
  `spell_cooldown`, `missile`, `spell_area`, `burning`, `spell_timer`, `dummy`, `meta_tally`, `meta_share`.
  Foundation: `ability_def`, `action_request`, `status_state`, `health_state`, `resource_state`,
  `movement_state`, bodies.
- Every placed row carries `world_id` and an indexed `chunk` (64 m cells); a player's client is sent only
  the 3 x 3 cells round it (ring interest). **The referee is sent the whole world** (every entity's
  movement) because it judges anyone anywhere.
- Ticks: the movement tick at 20 Hz; statuses, regeneration, spells and foes on their own schedules; nothing
  ticks per entity for mana (#270).

### 14.3 The rate limits (`shared/rules.json` `rate_limits`)
Every player-callable combat reducer spends from a per-player bucket (rule 14).

### 14.4 How it scales (the load test, 2026-10-29; the full measurement and the order of fixes:
`docs/regents_rule/REFEREE_SCALING.md`)
300 guest bots on the continent, a third swinging the axe's combo every 1.5-3 s (judged), a third gathering:
- **The server keeps up at 300** (movement tick p95 45 ms of its 50 at 300: close to the edge; 9.6 ms at
  200; 9.5 ms on the greybox at 300).
- **The referee breaks first**: frame p95 35 ms at 50 bots, 106 at 100, 128 at 200, 126 at 300 (limit 50),
  and a stall of 0.5-0.85 s in which no rows reached it at 50 and at 200 (in an earlier run, swings were
  refused during one: "nobody is judging"). It is fed every bot's movement row (the whole world). This is
  what combat at 200+ players depends on.
- Per player: 35 KB/s at 50, 78 at 200, 124 KB/s at 300 (p95), about 3900 rows a second at 300 (the ring).
  Swings judged: 11 a second at 50 bots, 44 at 200, 65 at 300.

---

## 15. Known problems, gaps and open questions (for the overhaul)

**Luke's notes not yet fixed**
- **#8 the LMB spam**: the next light starts 60 ms after the last one's hit (`chain_ms`), cutting its
  animation; the sword's second swing looks cut off. Combo design: should a chain wait for more of the
  clip, or should the clip be made to blend?
- The sword's light combo kills slower than the axe's (the foe bench: warrior 5.6 s to the iron sword,
  4.6 s to the iron axe). A balance question.
- The draw scaling the bow's damage: Luke was torn; look again.

**Roles (step 4, 2026-11-01): what is left**
- THREAT is stored, not used: `RoleDef` and the two live rules exist, `role_threat_pct` and `rules::threat_pct`
  / `heal_threat` compute it, nothing targets by it (step 6). So the guard handle's line says its full guard,
  not "foes come for you". No foe is a boss yet (`FoeDef.boss`), so the bosses-only scope changes nothing.
- The rallying cut's share with players NEAR is checked natively and by the server's log, not by two real
  clients (the playtest is one); alone, all 8 is checked end to end.
- No loot table drops a sword: the dropped-weapon roll is wired and unit-checked, dormant in play.
- The three last hits' clips are placeholders (the thrust plays the old finisher's `Sword_Light_C`;
  `ANIMATIONS.md` §5); one mesh for every handle (Luke: meshes later, with the art).
- Only the sword has roles; the axe, bow and staff role maps are step 7 (content fill).

**Design (RULE_DESIGN §4) not built**
- **The server-side cast queue** (§4.3: one queued ability, re-validated at the end of the cast/recovery,
  hiding the round trip). Today the buffer is the client's, for swings and spells alike; the server refuses
  what comes early.
- **TARGETED abilities** judged by the module (tab-target basics on the target, 120° cone, range from
  rows): basics today are all sweeps (HITSCAN-like, judged by the referee) or missiles.
- The **Effect → Status pipeline as content** (`EffectDef` atoms, `AbilityDef.kind`, `effects[]`): each
  spell kind and swing is code today (`land_spell`, `hit`), with numbers in content.
- **Stats** (power, defense, a `stats` view), **armor** (head, chest, legs, trinket slots: only the weapon
  slot exists), crits (10 % × 1.5 in the design), the ±5 % damage roll, the design's damage formula
  `base × (1 + power/100) × 100/(100 + defense)`.
- **One resource per kit** (stamina / focus / mana in the design; Luke reversed it on 2026-10-20: mana is the
  Staff's only).
- Statuses not built: Stunned, Rooted (as a status: the long cast roots by rule), Weakened, Evading (Rolling
  stands in), Knocked Down, Shielded, Kneeling (duels).
- **Duels** (a kneel at 1 HP, leaving the area loses), PvP, parties, threat/aggro tables, taunts.
- **NPC tiers** (awake / dormant by distance), packs, the six v1 NPCs (the wolf, the bandit camp...), NPCs
  using skills, the cast queue on an NPC, leash with threat decay.
- The sword's and axe's E/R/F skills; bow skills (skill shots); more arrow kinds; a quiver slot.
- A death penalty; food or potions (regeneration is the placeholder).
- Others seeing your spell's release animation (they see the cast pose and the missile).

**Technical**
- **The referee's feed at 200+** (the load test): it is sent the whole world's movement. Luke's call
  (template HANDOFF): give it a cell interest of its own (only the cells round each foe and each fight), or
  send it thinner movement rows. Combat at scale needs one of them.
- A cheating client could run while swinging (a status's speed scales the dash; the foundation's tweak).
- One status at a time per entity: a slowed player who blocks loses Slowed (the foundation's
  `status_state` is one row).
- The skeletons' `family = &"undead"` sits above `script = ...` in their `.tres` files, so Godot drops it on
  load: their family is really empty (the bake says `""`), and Hunter's and any family condition never
  apply to them. FIXED 2026-10-29 (the line moved, baked, published; a unit check fails the old order).
- Foes path round obstacles only within a 256 m tile of where they are (the continent's walk map is baked a
  tile at a time, template #285); a chase leaving the tile walks straight.
- The referee has no LoS check for TARGETED abilities (`needs_los`) because there are none.

---

## 16. Where everything lives

| what | file |
|---|---|
| the player's combat (keys, timeline, queue, bow, staff, targeting) | `game/regents/combat/combat_component.gd` |
| hit numbers, flashes, burning | `game/regents/combat/hit_feedback_component.gd`, `combat_look.gd`, `spell_looks.gd` |
| the HUD | `game/regents/regents_hud.gd` |
| content types | `game/regents/content/kit_def.gd`, `spell_def.gd`, `foe_def.gd`, trait and item defs |
| content | `game/regents/content/{kit,ability,spell,status,foe,item,trait,resource}/` (baked to `shared/content/regents/`) |
| ROLES (§3.3): the role, the kit's role map, the hilts, the badge | `game/regents/content/role_def.gd`, `kit_role.gd`, `role/`, `pattern/{crossguard,banner}_hilt.tres`; `game/regents/ui/role_badge.gd`; the server's `role_of`, `resolve_last_hit`, `rally`, `dropped_weapon_data` |
| hot rules | `game/regents/content/rules/regents.tres` |
| the server's combat | `server/src/game/regents.rs` (from `wielded` ~line 1417 to the dummies ~2800) |
| the pure maths (damage, combo, draw, hit chance, arcs, lock, ranks) | `server/src/genre/regents/mod.rs` |
| the referee | `sidecar/combat/action_referee.gd` (foundation) |
| foe brain | `sidecar/npc/brains/regents/foe.gd`; walk maps `sidecar/npc/npc_nav.gd` (foundation) |
| the animations and their lengths (the locks) | `game/regents/anim/adventurer.tres` |
| tests | `server/tests/regents.rs` (native), `game/regents/tests/suites/regents.gd` (unit), `tests/integration_test.sh` + `game/regents/tests/hooks/integration_genre.sh`, `game/regents/tests/combat_playtest.sh` (a real client and referee at 150 ms), `game/regents/tests/load_300.sh` |
