# Before new foes: how foes think today, what a smart and fun foe is, and the decisions that are yours (2026-11-12)

**ANSWERED (Luke, 2026-11-12): "Accept all proposed".** F1-F16 as proposed, in full in `GAME.md` ("NEW FOES,
ANSWERED"); §9 below is the order of work.

Luke, 2026-11-12: "Write foes prep and also take this time to deep dive enemy AI and if we are using limboai to its
potential and creating smart but fun (not annoying or painful) enemies." This is item (2) of his order (`GAME.md`,
"HIS VERDICT"): one or two new foe types, a caster or an archer, "so armor has its triangle". Like the other prep
sheets, every decision (§8) carries a proposed answer; nothing is built until Luke answers; his answers go to
`GAME.md` and §9 becomes the order of work.

Three findings come first, because they change the size of the work:
1. **Regent's Rule uses none of LimboAI.** Every foe runs one hand-written script (`sidecar/npc/brains/regents/foe.gd`,
   400 lines); the deer has another. No tree, no task. §3.
2. **A foe cannot shoot today.** `loose_arrow` and `cast_spell` are a player's reducers (they read the bag, the draw,
   the mastery), and a shot or a circle is written never to harm a player. A ranged foe is server work before it is
   content. §7.
3. **The models and clips are there.** The whole Bestiary pack is on Luke's PC; five of its seven models are unused;
   the bow and spell clips the player uses fit them. §5.

## 1. What is already settled (Luke's, with where)
- **A foe fights with a FOE KIT of its own**: slow, readable swings, a string whose last hit is the finisher, a rest
  after it (`COMBAT_OVERHAUL.md` §2). Never a player's kit.
- **Foes take turns** (2026-10-31): at most `regents.attack_tokens` foes swing at one player, no two foe hits land
  within `regents.token_gap_ms`, the rest circle.
- **A foe staggers by poise; players have no poise** (2026-11-02, 2026-11-04): a foe's unblocked last hit always
  staggers a player.
- **A hit on a player is dealt at once and taken back by a late parry or roll** (step 62); anything new a hit DOES to
  a player is owed until it can no longer be taken back. A roll is judged where it was pressed.
- **Face your target; shots go to the crosshair** (steps 60, 61). A new creature gives `aim_height_m` its body's.
- **Every foe hit from beyond its sight turns on who hit it** (Startled, 2026-11-11). Wolves hunt in packs (`pack_m`).
- **A foe's string follows its target** (`string_chase_ms`, 2026-11-11).
- **Show, don't name**: no role or mechanic names on screen; a tell is a pose, a glint, a ring.
- **Loot is personal**; a camp's table is content (`LootTableDef`).
- **The continent's foe placement is a test one**: Luke's own replaces it.

## 2. What is built that this leans on
| Piece | State | What new foes need from it |
|---|---|---|
| `FoeDef` | key, character, kit, hp, damage, poise, notice, leash, reach, rest, pack, family, boss, loot, carcass | a way to say HOW it fights (which behavior), and a ranged foe's distances |
| The foe brain | one script for every fighting foe: idle, chase, fight, circle, return, slain | see §3 |
| Foe kits | sword, axe, sparring sword, wolf: `light` strings only; `KitHit` for a push or a status | a kit whose ability is a SHOT or a SPELL |
| The referee | judges sweeps, flies arrows and bolts (players'), walls, walk maps | a foe's shot flown and judged against a player |
| The server | `use_ability_as` for a foe's swing; `hit`, `dealt_hit`, `take_back` | §7 |
| Tells | wind-up pose, the red glint (unblockable), swing trails, the parry ring (yard only) | a tell for a draw and a cast |
| Shot looks | arrow, bolt, fireball (`shot_look.gd`), impact bursts, the area ring on the ground | reused as they are; a foe's in a warm color, as its swing trail |
| Clips | Q2 `Bow_Notch`, `Bow_Aim_Neutral`, `Bow_Shoot`; Q1 `Spell_Simple_*`, `Spell_Double_*` | reused: the skeletons and the Bestiary share the skeleton |

## 3. The deep dive: how a foe thinks today
The brain is asked ten times a second (`think`), and answers with a goal to walk to, a way to face, and at most one
ability to use. It is a cascade of `if`s, top to bottom: slain → past the leash, go home → pick a target → none, idle →
out of sight or far, chase → no turn, circle → out of reach, close in → swing.

**What is good, and stays**
- The turn system (tokens, the gap between landings, stale turns freed). It is why a group fight is readable.
- The string that follows its target and is dropped after `string_chase_ms`; the rest after it, with jitter.
- The aim lock before a hit lands (`regents.foe_aim_lock_ms`): a late sidestep slips the swing. It is the fair miss.
- Chasing to where the target was last seen; packs sharing a sighting.
- It moves by the same input and the same walls as a player. It never cheats a position.

**Where it is thin** (from reading the code; none of these is a bug)
| # | Today | What a player meets |
|---|---|---|
| a | It notices all round at `notice_m`, in sight. No front, no hearing (the deer has hearing; foes do not) | you cannot come up behind one; it turns on you through its back |
| b | Idle is standing on its point | a camp looks switched off until you are 10 m away |
| c | One target, the nearest when it noticed, kept until sight, leash or death. Threat is computed and never read | in a party it never turns on who hurts it; a guard handle has nothing to hold |
| d | Startled turns on the NEAREST player within twice its leash, not on who shot | two players: the wrong one is chased |
| e | It reads nothing of what you do: not your guard, your draw, your cast, your roll, your health | every skeleton fights the same fight every time |
| f | It has one string and nothing else: no block, no step back, no skill, no second move at range | the only question a foe asks is "can you parry the last hit" |
| g | Every fighting foe is the same script; a difference is a number on `FoeDef` or an `if` on `pack_m` | a new KIND of behavior (hold a distance, cast, guard a spot) means more `if`s in one file |
| h | What it remembers across a referee restart is its home | accepted |

(g) is the one that matters now. An archer and a caster in this script would be `if ranged` through every branch,
and the fourth and fifth foe types worse.

### 3.1 LimboAI: are we using it to its potential? No, not at all
- The template carries LimboAI and the glue (`NpcBrain.run_tree`, `BrainTask`; template DECISIONS #245), chosen so
  "a designer reorders a bot's steps and sets their numbers without code".
- **Fowl Play** uses it: a hen tree (ten tasks) and a wolf tree (seven), each ONE priority list (`BTDynamicSelector`
  over `BTAction`s). That is LimboAI as an ordered list: its lightest use.
- **Regent's Rule** has no tree and no task. `foe.gd` is the same priority list, written as code.
- Unused in both games: sequences (do this, THEN that), decorators (a cooldown on a branch, a time limit, a chance),
  subtrees shared between foes, blackboard plans, its state machines.

**What is worth taking, and what is not** (my reading)
| LimboAI piece | Take it? | For what |
|---|---|---|
| One tree per BEHAVIOR (`melee`, `ranged`, `caster`), named on `FoeDef` | yes | a new kind of foe is a new tree from the same tasks; a foe's behavior is a file Luke can open |
| `BTDynamicSelector` at the top (highest need first, re-checked every think) | yes | what the `if` cascade is today |
| `BTSequence` | yes | "back off, THEN shoot"; "tell, THEN cast" |
| `BTCooldown`, `BTTimeLimit`, `BTProbability` decorators | yes | "step back at most once every 6 s"; "sometimes a second shot": numbers in the Inspector |
| Subtrees (`BTSubtree`) | yes | "go home", "slain", "wait for a turn" written once, used by every tree |
| The blackboard for a foe's plan | a little | the target and where it was last seen; the rest stays on the brain |
| `LimboHSM` (state machines) | no | it wants nodes updated every frame; a brain is stepped ten times a second by hand, and five states do not need it |
| Its visual debugger | not checked | the referee is a separate headless process; whether the debugger can attach to it is to be tried in step 1 |

**The shape proposed**: `foe.gd` stays as the foe's BODY OF KNOWLEDGE (its target, its turn, its string, its pack, the
aim lock: everything tested today), and its `think` becomes "step my tree". The cascade's branches become tasks
(`sidecar/npc/brains/regents/tasks/`: `FoeSlain`, `FoeGoHome`, `FoePickTarget`, `FoeChase`, `FoeWaitTurn`,
`FoeCloseIn`, `FoeSwing`), each a few lines calling the brain's own steps. `melee_tree.tres` puts them in today's
order. It is a move with NO change in behavior, proved by the suites that pass today (regents unit, the combat
playtest's 119). Then the archer is new tasks (`FoeHoldRange`, `FoeBackOff`, `FoeShoot`) in a `ranged_tree.tres`.

**The cost, plainly**: a step that changes nothing a player sees; a risk of a small timing change (a tree answers
through one more layer); trees are `.tres` files under `sidecar/`, edited in LimboAI's tab. The alternative (F2) is
to leave melee as code and write only the new foes as trees: less risk now, two ways of writing a foe for good.

## 4. Smart but fun: the rules proposed for every foe
"Smart" is a foe that seems to mean what it does. "Annoying" is a foe whose best play takes the game away from you
(it runs, it stuns, it hits from where you cannot see). The rules, each one checkable:
1. **Every hurt is announced.** A swing has its wind-up; a shot has a draw and a glint; a spell has a cast pose and,
   on the ground, a ring. Nothing lands sooner than its tell (a ranged tell proposed: 1000 ms or more).
2. **Each foe asks ONE question, and the answer is a thing you do.** Warrior: parry or roll the last hit. Wolf: keep
   moving, mind the pack. Archer: close the gap, use a rock, or roll the arrow. Caster: hit it while it casts, or
   step out of the ring.
3. **Nothing from off screen without warning.** A ranged foe shoots only a target it sees, and its first shot of a
   fight has the long tell.
4. **Turns cover shots too.** No shot lands within `token_gap_ms` of another foe's hit on you; one shot in the air at
   a player at a time.
5. **A foe that keeps its distance is caught.** It is slower than you (4.2 against 5 m/s, as now), steps back at
   most once in a while and never past its leash; reached, it fights badly up close. It never runs for good.
6. **A fair miss exists.** Its aim locks before it looses: a sidestep or a rock works. (Since 2026-11-13 a shot LEADS
   the walk it reads at the lock, Luke's call after his playtest: the miss is a turn, a stop or a roll after the glint.)
7. **An opening always comes.** A rest after a string; a reload after a shot; a breath after a cast.
8. **You are never chained.** A shot never staggers. A slow or a stagger from one foe is not followed by another's
   inside a short window (a new rule; today two foes' last hits can stagger you back to back within the gap).
9. **A group is more than its sum, and readable.** Melee in front take the turns; ranged stand behind them; killing
   the front changes what the back does (it steps back once, or comes on).
10. **Variety comes from choice, not from dice on the outcome.** Jitter on rests and sides, never on whether a
    telegraphed hit can be answered.

## 5. The models (read from the files, 2026-11-12)
The Bestiary pack is extracted on Luke's PC (`Downloads/Bestiary - Dungeon Monsters Kit[Source]/`). In the game:
Skeleton A and B only, plus the wolf and deer from the animal pack.
| Model | Skeleton | Meshes | Fits as |
|---|---|---|---|
| Skeleton A / B | 65 bones (the player's) | body, greaves, helm, pauldron, and its axe or sword as SEPARATE meshes | **the archer**: hide the blade, a bow in the hand; texture sets 2 and 3 (with glow) tell it from the warriors |
| Imp | 55 bones | body, chains, mace, spiked collar | **the caster**: small, red, plainly not a skeleton; hide the mace |
| Puglin | 55 bones | body, stick, tusks | a weak swarmer for groups and AOE (later, with the ability bar's AOE) |
| Lycan | 71 (65 and a 6-bone tail) | one body | fast unarmed melee, a pack's leader; the tail has no clips |
| Hellwarden | 65 | armor in six pieces, a sword | an armored elite or the first boss (`FoeDef.boss` exists, unused) |
| Tidebreaker | 65 | body, anchor | a slow heavy hitter, a lair boss; wants two-handed heavy clips |

- Not verified: that the Imp's and Puglin's 55 bones (ten fewer: fingers, by the count) play the humanoid clips
  cleanly. One import in step 3 settles it; the fallback for the caster is a skeleton in texture set 3.
- The Rivals and Races packs were not found on this PC. Neither is needed here. Races would dress a BANDIT camp later
  (`RULE_DESIGN.md` §6.3: bandits are humanoids in the players' own outfits).
- No new clip is needed for an archer or a caster. A foe's draw is the player's, slowed, as its swings are.

## 6. The two foes proposed
| | Skeleton archer | Imp caster |
|---|---|---|
| Its question | "can you reach me, or roll my arrow?" | "can you stop my cast, or leave the ring?" |
| Stands | 9 to 14 m off, in sight | 7 to 11 m off, in sight |
| Its shot | draws 1200 ms (pose, then a glint), aim locked the last 250 ms, no lead; an arrow at 55 % | a bolt: slow enough to sidestep at 8 m, 45 % |
| Its second move | you within 4 m: one step back of 5 m, at most every 6 s; caught, a slow bow shove (pushes, 15 %) | every third cast a RING on the ground where you stand, 1500 ms to fill, 80 % inside it |
| Its opening | 1800 ms between shots; helpless in a shove's recovery | a hit while it casts stops the cast (poise 30); 2200 ms between casts |
| Health, poise | 80, 50 | 70, 30 |
| Never | staggers you; shoots what it cannot see; runs past its leash | blinks or teleports; slows or roots you (see F8) |
| Family | undead | a new one (see F13) |
All numbers are mine and Luke's to change; each is a `FoeDef` or ability field, or a hot rule where it is worth
tuning live.

## 7. What a ranged foe needs that is not built
| Layer | Missing | Rule it must keep |
|---|---|---|
| Server | a foe's shot and cast: an authority path (the referee asks, as `use_ability_as` for a swing), with no bag, no draw status, no mastery; its power from `FoeDef.damage_pct` | rule 13: the referee sends the wish, the server derives the outcome; rule 17: a NEW reducer, nothing reshaped |
| Server | a missile and a ring that HURT A PLAYER (today both skip players) | no harm between players stays: only a FOE's shot hurts one |
| Server | your guard, parry and roll against a shot (F4); the hit dealt at once and taken back as a swing's is | `regents-genre.md`: never a fixed wait on a hit; what a hit does is owed until it cannot be taken back |
| Referee | flying a foe's arrow and judging it against a player's body | the same flight as a player's arrow (`FlyingBody`) |
| Brain | holding a distance, keeping sight, stepping back, a ranged turn | §4 rules 3 to 6 |
| Content | `FoeDef`: its behavior (a tree), its near and far distance; a foe kit with a shot | a designer's fields, in the Inspector and the foe bench |
| Client | a foe's draw pose and glint; its arrow in a warm color; the ring on the ground under YOU | show, don't name |
| Bench | the foe bench's time-to-kill for a foe that shoots | "no content type without a workbench" |
Not read yet: exactly how `use_ability_as` hands a kit's ability to the swing path; step 2 starts there.

## 8. The decisions that are yours
| # | Decision | Proposed |
|---|---|---|
| F1 | Which foes | a skeleton archer and an imp caster (§6); the Puglin with AOE, the Hellwarden as the first boss, later |
| F2 | Foes on LimboAI trees | yes, and melee moved first with no change in behavior (§3.1). Or: new foes only. Or: stay code |
| F3 | The archer up close | one step back at most every 6 s, then a slow shove. Or: it never moves (a turret). Or: it draws a blade |
| F4 | Your defenses against an arrow | a held guard facing it blocks it as a swing (chip through, "Blocked"); a timed parry knocks it away, no riposte; a roll passes through it. A bolt the same; a ring is only left |
| F5 | The tell of a shot | the draw pose 1200 ms, a glint as it is about to loose, aim locked the last 250 ms, no leading a runner |
| F6 | Shots and turns | a shot keeps the gap between foe hits; ONE foe shot in the air per player (`regents.ranged_tokens` 1, a hot rule); a shooter takes no melee turn |
| F7 | Stopping a cast | any hit that flinches stops it (the caster's poise is low); the cast's cooldown is still spent |
| F8 | What a foe's spell does besides damage | nothing yet: no slow, burn or root from a foe until armor says what resists what |
| F9 | How a foe notices you | a front (140 degrees at `notice_m`) and hearing all round at 4 m, further if you sprint; so a camp can be come at from behind. Or: all round, as now |
| F10 | A camp at rest | foes at rest wander a few meters round their point and face about. Or: stand, as now |
| F11 | Who a foe turns on | hit from out of sight, it turns on WHO HIT IT (not the nearest) now; switching target by threat waits for the overhaul's threat step |
| F12 | Not chained | after a stagger or a slow from a foe, no other foe's can land on you for 1500 ms (the hit still hurts). Or: as now |
| F13 | The imp's family | "fiend" (a third family beside undead and beast, for traits like Hunter's). Or: none yet |
| F14 | Loot | the archer: the camp's table and 2 to 5 arrows half the time; the imp: the camp's table until its own is designed |
| F15 | Where they stand | the glade: one archer and one imp by the skeleton camp, for the suites and your playtest; the continent: one archer in each camp of three or more, a test placement |
| F16 | Numbers | §6's, as a start |
Linked, not asked here: whether an arrow and a spell are different KINDS of damage for armor (`ARMOR_PREP.md`, its
prep session); the ability bar and Q/E/R list (`GAME.md`, "STILL HIS").

## 9. The order of work (once answered; each step ends playable or proved)
1. **The foe brain on a tree** (F2): tasks, `melee_tree.tres`, `FoeDef.behavior`; no change in behavior. Proved by
   the regents unit suite and `combat_playtest.sh` at today's counts, and a unit check that a foe with no tree is
   refused by `validate`. Try LimboAI's debugger against a running referee; write what was found in the handbook.
2. **A foe's shot on the server**: the authority path, a shot that hurts a player, guard, parry and roll against it
   (F4), dealt at once and taken back. `cargo test --test regents` with its negatives (a player's call of the foe
   path refused; a shot between players still harmless); the integration hook's checks written, run in step 7.
3. **The skeleton archer**: model, character, kit, `ranged_tree.tres`, the tell, turns for shots (F5, F6), its
   place in the glade. A leg in the combat playtest (a shot rolled, blocked, parried, out-walked behind a rock).
   Bake, publish, hand over: Luke plays.
4. **The imp caster**: the import check, kit, `caster_tree.tres`, the ring under a player, the stopped cast (F7).
   A playtest leg. Publish: Luke plays.
5. **Noticing and rest** (F9, F10, F11, F12), if yes: for every foe; the wolf and skeleton legs re-run. BUILT
   2026-11-13 (PROGRESS step 68; step 67 before it: a foe's shot leads a mover, Luke's call after his playtest).
6. **The foe bench** shows a shooter; `COMBAT_CURRENT.md` §11 rewritten; the handbook. BUILT 2026-11-13 (PROGRESS step 69).
7. **Integration, once**, then the continent's test placement (F15). RUN 2026-11-13 (PROGRESS step 70): 1524/38,
   diagnosed; the hook fixed, a rerun to confirm; one poise leg open. F15 in place since step 66.
