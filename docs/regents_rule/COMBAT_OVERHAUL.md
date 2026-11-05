# Regent's Rule: the combat overhaul (settled with Luke 2026-10-30)

What combat becomes, and the order it is built in. It starts from `COMBAT_CURRENT.md` (combat as built,
2026-10-29), Luke's working notes, and two outside reviews of a first draft. Luke's calls are listed in `GAME.md`
(owner decisions, "Combat overhaul"); where this file and `RULE_DESIGN.md` §4 or `COMBAT_CURRENT.md` differ, this
file wins. What is still Luke's to decide is §8: never defaulted.

---

## 1. Why: the playtest, read against the code

The one playtester found combat **too fast**: attacks (theirs and the skeletons') came too quick, landed at the
same time, and were hard to read. Luke found it **generic**, not a fun MMO-lite of its own. The goal: **easy to
learn, hard to master**, with varied but simple systems.

From the code, four causes:
1. **Foes swing the player's abilities** (`foe.gd`: the kit's light combo). Slash winds up in 180 ms. Reaction
   (~250 ms) plus the view delay (~150 ms: a client draws others that far in the past) means a foe's hit lands
   before you see it start.
2. **Foes never take turns.** Each runs its own combo with `rest_ms` 900, so a group attacks back to back.
3. **Parry counts from raising the block**, not from the foe's hit: it is "hold RMB early", not a read. The
   block covers every direction.
4. **A foe's aim follows you to the hit.** (Corrected 2026-10-31, from the code: the referee already sweeps
   along the foe's facing AT THE LANDING, from its movement history, and the brain turned to its target every
   think, so no step aside ever slipped a swing.) With a long wind-up that would make positioning worthless.

What was looked at and turned down:
- **A Break/poise meter that every system feeds** (Luke: players would min-max stagger instead of choosing
  damage or utility). Stagger stays a payoff; there is no visible bar.
- **A separate heavy AND a separate finisher** (both exist today): merged into one (§3).
- **An off-hand slot for roles** (Option A): the bow and staff are two-handed, so it only shows on the sword and
  axe, and it overrides the five slots. Roles come from the handle instead (§5). A shield off-hand for the sword
  and axe can come later on top.
- **"Parry jumps your combo to the finisher"**: replaced by a riposte (§4).
- **Three telegraph colors** (white parry, red dodge, purple interrupt): replaced by the pose plus one red
  glint (§2).
- **Shots that fly true where aimed**: the bow and Staff keep their hit roll on a Tab target (as built).

---

## 2. Pace and readability (step 1: what fixes the playtest)

| | today | the overhaul |
|---|---|---|
| a foe's wind-up | the player's (180-450 ms) | **its own abilities**: lights ~550 ms, the finisher ~850 ms |
| foes on one player | every foe in reach | **at most `regents.attack_tokens`** (1-2) |
| gap between foe swings | none | **`regents.token_gap_ms`** (~600 ms) |
| a foe's rest after its combo | 900 ms | 1.5-2.5 s, with jitter |
| a foe's aim | follows you to the hit | **tracks, then locks** for the last `regents.foe_aim_lock_ms` (~300 ms) |
| telegraphs | none | the pose; **a red glint** on unblockable attacks only |

- **Foe kits of their own**: `FoeDef.kit` points to foe-only kits and abilities (new 40xxx ids). Player
  abilities are untouched. A foe's finisher is the natural one to make **unblockable** (dodge or step out).
- **Unblockable**: a flag on the ability. `hit` skips block and parry. The client plays the glint at the
  wind-up's start from the ability event (presentation reads state; AGENTS rule 11).
- **Attack tokens** live in the foe brain (`sidecar/npc/brains/regents/foe.gd`), per region referee. A freed
  token waits `token_gap_ms` **from the last foe swing's LANDING time on that player, whatever it did** (hit,
  parried, rolled through, stepped out of): otherwise a dodge hands the next foe a zero gap. Foes without a
  token circle at reach + 1-2 m. A player on the edge of two region referees may face one extra foe: accepted.
  Tokens also cut the swings the referee judges at 300 (`REFEREE_SCALING.md`).
- **Aim tracks, then locks**: the foe turns after its target through the wind-up and stops turning
  `foe_aim_lock_ms` before the hit lands; the referee sweeps along its facing at the landing (as it always did).
  Stepping out works late in a swing (positioning is a real answer), not by walking at the start. **Built in the
  foe brain alone** (2026-10-31): the referee needed no change, so there is no template work for it.
- **Time to kill comes from the pace, not from HP.** Defending and waiting for openings already slows a kill.
  Targets with a matched iron weapon: about **12 s attacking only**, **7-8 s with ripostes and finishers**. Foe
  HP moves only if the playtest says so.
- **Loot is judged per minute**: if kills slow down, the Skeleton camp table pays more per kill (content), so
  farming does not get worse.
- The foe bench (`foe_workbench.tscn`) gains "foe hits on you a second" and "least gap between two foe hits".
  Its TTK is the attack-only case; the skilled case is judged in play.

---

## 3. One combo (step 2)

```
tap ─ tap ─ tap        L1 ─ L2 ─ FINISHER
parry, tap ─ tap       RIPOSTE (= step 1) ─ L2 ─ FINISHER
```

- **LMB taps one string.** Each step is a little heavier and slower (more damage, a longer wind-up): a rhythm
  you feel and foes can read. **No hold-LMB on melee**: the old hold-LMB heavy is gone.
- **The last hit is the finisher AND the heavy**: armor (never flinched), it flinches a light it hits (the old
  heavy's rule), and it **staggers** (`stagger_ms`). Stagger only on the finisher: on every hit it would
  stunlock, and foes use the same grammar.
- **Your role changes only the finisher** (§5).
- **A swing at air still advances the combo** (as today). Pre-loading the finisher while closing in is allowed:
  it costs walking at ×0.25 per swing and the window.
- `chain_ms` (60, kit-wide) is replaced by a **per-ability follow-through** (content, ~200 ms after the hit):
  the next step waits for the swing's arc. Fixes Luke's #8 (the sword's second swing cut off).
- `combo_window_ms` (900, on `KitDef`) becomes the hot rule **`regents.combo_window_ms`**, 2000. A parry
  pauses its decay; a roll ends the combo (as today).

| kit | the string | example wind-ups (ms) | its finisher |
|---|---|---|---|
| sword | Slash, Slash, Thrust | 220, 240, 350 | precise, longer reach |
| axe | Chop, Overhead | 320, 550 | the heaviest single hit; cleaves two |
| staff | Bolt, Bolt, Surge | instant, instant, a short cast | gives back a little mana |
| bow | the draw | full at `draw_full_ms` | **the full-draw shot** (no overdraw) |

The sword is three quick hits and precise reach; the axe two slow hits, the biggest hit and an arc. The foe
bench's kill times should land close together (today the axe kills faster: `COMBAT_CURRENT.md` §15).

- **The Heavy trait is repurposed**: it made heavies and finishers stagger, which every finisher now does. It
  becomes **a longer stagger on the finisher** (`stagger_ms` × ~1.35), still paid with slower recovery. Every
  trait atom's `on: heavy` becomes `on: combo_last`, and the `heavy` action is retired (a re-bake). Oak handles
  keep offering it; nothing in a bag breaks.
- `KitDef`'s heavy field and `heavy_hold_ms` are retired.

---

## 4. Defense: RMB is only defense (step 2)

| | Damage | Tank | Support |
|---|---|---|---|
| **tap RMB** | parry | parry | parry |
| **hold RMB** | weak front block (`regents.weak_block_pct`, ~60 % through) | real front block (`block_damage_pct`, 25 %) | weak front block |
| **Ctrl** | roll | roll | roll |

- **Parry, every kit and role**: it counts if the hit lands within `parry_ms` of the press, **judged on the hit
  as you saw it** (like the template's server-timed presses, DECISIONS #210). As built (2026-10-31): the press's
  arrival less its trip and how late the client shows another's swing (a swing's animation starts as its event
  arrives: half a round trip, not the body's interpolation); a hit a press still on its way could parry waits
  for it (at most ~320 ms). A parry pays **0 damage, the attacker Staggered, and a riposte window**.
- **Whiff lockout**: a missed parry locks parrying for `regents.parry_whiff_ms` (~400 ms), so tapping RMB
  nonstop does not work.
- **Riposte**: LMB within `regents.riposte_ms` of a parry fires the kit's riposte (bonus damage), and it counts
  as combo step 1, so a parry shortens the road to the finisher.
- **Blocks are front-only** (~120°, hot). A hit from behind takes full damage.
- **Staff**: the parry is a ward flash; the riposte a point-blank bolt.
- **Bow**: RMB while drawing lets the draw go **and** parries with the stave in one press (an answer to a
  rusher). The bow's riposte is **"your next draw fills twice as fast"** (`regents.riposte_draw_pct`): parry →
  the foe staggered 800 ms → a 400 ms draw → the full-draw role shot lands while it is still staggered.
- The roll is as built (`COMBAT_CURRENT.md` §5).

---

## 5. Roles by the handle (step 4, the sword first)

**The handle's SHAPE sets the role; its MATERIAL still sets the trait** (#22 intact). This is what makes the game
its own: how you smith a weapon decides how you fight with it.

| weapon | Damage | Tank | Support |
|---|---|---|---|
| sword | grip | crossguard hilt | banner hilt |
| axe | haft | bearded haft | war-horn haft |
| bow | recurve grip | bracer grip | wayfinder grip |
| staff | conduit shaft | ward shaft | censer shaft |

- **Items**: new handle PATTERNS crossed with the materials by Make the table (`MATERIALS.md` §2): an oak
  crossguard hilt, a yew ward shaft, each a real item with its material's trait. Ids pinned. Today's plain
  handle is the Damage one. A dropped weapon rolls a handle shape.
- **Changing role = re-hilting at the workbench**, under the existing part-swap rule (the new handle used up,
  the old one lost, plus bars of the head's metal). To flex, carry two weapons.
- **Server**: the role is read from the wielded item's parts (`instance_data` `"p"`). `wielded` is unchanged.
- **`RoleDef`** (new content type, with a bench or folded into the kit bench) holds what the roles SHARE: the
  threat multiplier, which block (full or weak), passive atoms.
- **The abilities are per (kit, role)**, in a role map on `KitDef`: the finisher and the pick pool. They cannot
  be shared across kits: a lock comes from each weapon's clips, and the referee judges sweeps, missiles and
  rings differently. That is **12 finishers**; the sword's three come first to prove the shape.
- **No PvP, so every player is an ally**: Support works without parties (it helps players near you).
- **Threat** (step 6): the brain targets by damage from `hurt` × the role's threat multiplier, not just the
  nearest; taunt is a Tank pick; the threat target gets tokens first. The referee reads `hurt`
  (`genre.tres` `referee_tables`).

**The finishers, first proposals** (Luke's to settle, §8):

| | Damage | Tank | Support |
|---|---|---|---|
| sword | the biggest thrust | a longer stagger plus threat (a pommel bash) | a wide cut that heals nearby players a little |
| axe | a rending cleave, a wider arc | a hook: pulls the foe to you and taunts it | a horn blast: a short push-back that steadies players near you |
| staff (Surge) | bursts on the target | wards you and taunts what is round you | heals players in a small circle |
| bow (full draw) | piercing: through two targets | pinning: slows, builds threat | a flare: heals players where it lands |

---

## 6. Mastery picks: tall or wide (step 5)

- **Rank 1: Q** (sword Lunge, axe Cleave, staff Blink; the bow's is open). **Ranks 3, 6, 9: one pick each** from
  the (kit, role) pool: unlock the next active (E, R, F), **upgrade** an active (once each), or a **passive**.
- **Tall** (OSRS-like, 1-2 buttons): Q, upgrade Q, two passives; E, R, F stay empty, so E still works stations.
  **Wide**: Q, E, R, F.
- Today's Fireball, Frost Ring and Gale move into the staff's role pools (Fireball and Gale for Damage, Frost
  Ring for Tank and Support). Pool examples (first proposals): sword Damage Bleed cut, Execute (below 30 %
  health); Tank Taunt shout, Hold the line (a 3 s all-round block); Support Rally (heal over time near you),
  War cry (damage up near you).
- **Storage**: a new table `mastery_pick` (player, skill, role, rank → choice). Rows can change (rule 17's
  "add-only" is about the schema): **picks change out of combat** through an upsert reducer. A respec's cost is
  Luke's (free while testing); the Tester page's skill reset clears picks too.
- **Passives reuse the trait atoms** (`what` / `on` / condition / mult), so `hit` reads them like traits.
  **Upgrades are their own `AbilityDef`s** (Lunge II); the server resolves which ability a key fires.
- The pick panel goes in the skills window, at each rank.

---

## 7. What the foundation needs (template sessions, then pulled)

- **Statuses that stack** (built 2026-11-01: template 1.7.0, DECISIONS #302: EFFECTS in `status_effect` beside the
  one state, the bound the stricter). `status_state` held one row per entity: blocking wiped Slowed. A multi-status table
  where the action states (Swinging, Blocking, Drawing, Rolling) and the effects (Slowed, Staggered, Shielded,
  Weakened) coexist; the movement envelope takes the strongest. Not "action states on `combat_state`": the
  foundation's speed bounding reads statuses. Needed before Shielded, Weakened and Support.
- ~~The referee's NPC aim from facing~~: not needed; the referee already judges along the facing at the landing
  (2026-10-31), so the lock is the brain's.
- The referee's feed at 200+ (`REFEREE_SCALING.md`) is separate; tokens make it lighter.

---

## 8. Still open (Luke's; never defaulted)

- The 12 role finishers and the pick pools (the tables in §5 and §6 are first proposals; the sword first).
- The bow's Q; the bow's skills.
- A respec's cost once testing is over.
- The combat triangle as FOE design (armored, caster and archer foes, each weak to one style), not PvP rules.
- Armor weight (light, medium, heavy) arrives with the armor slots, not in this overhaul.
- The exact numbers: every timing above is a starting point, tuned in play (hot rules where it says so).
- **HOW OFTEN A STAGGER** (SETTLED 2026-11-02: Luke chose A with a short B, shown on the target marker, not a bar;
  built, PROGRESS 34) (Luke, 2026-11-02: "tank sword seems too strong as the heavy trait plus its role allows for
  almost infinite stagger. even the normal stagger is a lot when fighting one enemy"). Why: every finisher staggers,
  and the sword's string comes round in ~1.2-1.4 s: a plain stagger is 800 ms, the guard grip's bash 1200, with Heavy
  1620, so the foe never gets a swing off (and one it starts is flinched by the next finisher's armor). The options,
  for Luke to choose (the 2026-11-02 brainstorm):
  - **A. Poise, a bar that breaks** (the souls games' poise; Lost Ark's and Guild Wars 2's boss bars): each foe has
    poise (FoeDef), each hit takes some (lights a little, the finisher a lot); empty, it staggers, and fills again
    after a moment unhit. Shown as a bar under its health. Heavy: the finisher breaks more of it, not a longer stagger.
  - **B. Steadied**: after a stagger, immune to stagger for a few seconds (MMO crowd-control immunity and diminishing
    returns). One live rule and a stacking effect (template 1.7.0); the quickest to try.
  - **C. Diminishing**: each stagger within a few seconds half as long as the last.
  - **D. Only a punish staggers**: the finisher staggers only a foe caught in its wind-up, or just parried; otherwise it
    is damage.
  - Recommended: A, with a short B after each break. Heavy then trades as a trait should (breaks the bar sooner,
    slower basics) without being the only way to stagger.

---

## 9. The order of work (each step playable; Luke playtests between)

| step | what | where |
|---|---|---|
| 1 | **Pace and readability** (§2): foe kits, aim track-then-lock, tokens with the gap, rests, unblockable plus the glint, loot per minute. Hand to the tester. **Built 2026-10-31** (PROGRESS step 26) but loot per minute: judged after the playtest. | foe brain, foe content, `regents.rs` `hit` |
| 2 | **The combo and defense** (§3, §4): the merged finisher, follow-through, the window hot rule, parry on the seen hit, the whiff lockout, riposte (the bow's fast draw), weak and full front blocks, the Heavy trait repurposed. **Built 2026-10-31** (PROGRESS step 27) but the staff's riposte and the axe finisher's cleave. | `combat_component.gd`, `kit_def.gd`, `regents.rs`, `genre/regents/mod.rs`, trait content |
| 3 | **Statuses that stack** (§7). **Built 2026-11-01**: template 1.7.0 (#302), pulled (PROGRESS step 29) | the template, pulled |
| 4 | **Roles** (§5), the sword first: handle patterns, `RoleDef`, the role map, the role finishers, re-hilt, loot. **Built 2026-11-01** for the sword (PROGRESS step 30; template 1.7.1, #303: the server resolves which last hit fires); threat stored for step 6 | material table, kit content, `regents.rs` |
| 4b | **Poise** (§8, "How often a stagger": Luke chose A with a short B): a foe staggers only when the last hit breaks its poise; Steadied after; Heavy wears more; shown on the target marker. **Built 2026-11-02** (PROGRESS step 34) | `regents.rs` `wear_poise`, `combat_component.gd` |
| 5 | **Mastery picks** (§6) | `mastery_pick`, the skills window |
| 6 | **Threat and Support**: threat targeting, taunt, help for players near you | foe brain, `regents.rs` |
| 7 | **Content fill**: the rest of the role maps and pools, the bow's skills, foe casters (a finisher's interrupt has nothing to interrupt until foes cast) | content |

## 10. How it is tested

- Unit suite (`--only=regents`) and native `cargo test`: the string and its finisher (armor, flinch, stagger),
  follow-through, the window, parry on the seen hit, the whiff lockout, riposte as step 1, weak vs full block and
  front-only, unblockable, role from parts, picks. Each with its negative: a riposte outside its window refused,
  an unblockable never parried, a parry inside the lockout fails, a block from behind takes full damage, a pick
  change in combat refused.
- `integration_test.sh` for every new reducer (pick, re-hilt) and its refusals.
- `combat_playtest.sh` at 150 ms: a real client parries a foe's light it SAW; a parry pressed too early fails;
  three foes never exceed the token count, and no two foe swings land closer than `token_gap_ms`, even after a
  roll; a sidestep at the wind-up's start does not dodge, one in its last 300 ms does.
- The foe bench: attack-only TTK about 12 s; the least gap between foe hits at or above the gap rule.
- `load_300.sh` after step 1: swings judged a second fall (tokens); the referee's frame no worse.
- Luke's and the tester's playtest after steps 1 and 2: readability is answered by play, not by numbers.
