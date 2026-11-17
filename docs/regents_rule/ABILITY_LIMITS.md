# ABILITY_LIMITS — what an ability can be, before the abilities are decided (2026-11-17)

Luke asked, before deciding every ability: "what are some technical limits I want to make sure I'm in. I don't want to
describe an ability that we are feasibly unable to make", with League of Legends as the yardstick. This is the answer,
read from the code as it stands at step 108 (`AbilityDef`, `SpellDef`, `StatusDef`, `KitHit`, `BodyDef`, the module's
`place_entity` and `push_entity`, DECISIONS #206, #226, #228, #246, #251, #302, #309). It decides nothing: every
ability is Luke's (`ABILITIES_PREP.md`, `WAITING_ON_LUKE.md`).

Short answer: almost everything is buildable. The limits are six facts about how the game works (§5), not cleverness.

## 1. What an ability can be today, as CONTENT only (a `.tres`, no code)
- A melee SWEEP (`AbilityDef`, judged by the referee): reach, width, height; the first foe or every foe in it
  (`hits_all`).
- A LUNGE (`lunges`): a dash forward into a strike.
- A dodge ROLL (`rolls`, its status and length).
- A SPELL (`SpellDef`), four kinds:
  - BOLT: a real missile the referee flies (`body`, `speed_mps`), with splash (`splash_m`, `splash_pct`) and burn.
  - AREA: a circle (`radius_m`) where you aim, landing `delay_ms` later.
  - BLINK: a teleport along your look onto ground you can stand on.
  - CONE: everything within range and `angle_deg`, with a push (`push_mps`).
- ON HIT (`KitHit` for a weapon's ability, `SpellDef.status` for a spell): a knockback (up to 40 m/s) and a STATUS for N ms.
  A status (`StatusDef`) can slow by any share (`speed`), root (speed 0), stop sprint, jump or dash, stun (`can_act`
  false), or make its holder untargetable (`targetable`) and unhittable (`hittable`). Statuses stack (`status_effect`,
  #302).
- TIMING: cast time (`cast_ms`; walking allowed under 0.8 s), cooldown, mana (the staff's).

A new ability OF an existing kind is content. A new KIND is about one step (Rust, the client, an effect, a test).

## 2. League's abilities mapped here
| Ability | Verdict | What it needs |
|---|---|---|
| LeBlanc W (jump, hit, jump back) | Yes | Blink + an Area where you land, both exist. The return is NEW: the server remembers where you left and takes a second press within a window. A "recast" kind, useful to many. |
| Ashe W (a fan of arrows) | Yes | Arrow Volley already hits a cone (a judged sweep, `hits_all`). Separate dodgeable arrows are several BOLT missiles at once: fine at 5-10 a cast, not hundreds. |
| Blitzcrank Q (hook, pull in) | Yes | The BOLT exists; "pull" is a new on-hit kind. A FOE is easy (the referee moves foes). A PLAYER: a push toward you through their own prediction (#251), or a held drag with carry (#228, built). |
| Fizz E (hop, untargetable, land) | Yes | Mostly existing: an unhittable, untargetable status, a raised body (presentation), an Area at the landing. Moving while up is the recast kind again. |
| Blade waltz (dash between foes, untouchable) | Yes | A new SEQUENCE kind: the server teleports you target to target over ~1 s (`place_entity`), each hit judged, you unhittable throughout. Medium. |
| Shaco's clone | Yes | An NPC dressed as you, with a simple brain, run by the referee like the foes; foes can be made to chase it. Medium to big, every piece exists. |
| Shaco's invisibility | Against foes: easy and secure. Against players: not secure yet | Foes are the server's: they ignore a hidden status. Against PLAYERS, `hide_body` is presentation only and the server still sends your place, so a cheater sees you. Duels and PvP zones are planned (`RULE_DESIGN.md` §4.5): a secure version means the server stops sending your row to them. Template work, to be load-tested at 300. |

## 3. League's most complex, here
- TERRAIN YOU CANNOT WALK THROUGH (Anivia's wall, Taliyah's wall, Jarvan's ult): the HARDEST for us. Every player's game
  predicts its own walking against the level and the server must agree exactly (AGENTS.md rule 7): a temporary
  walking-blocker changes the movement model on both sides, a template milestone. A wall that blocks only FOES, or
  hurts or slows whoever crosses it, is easy.
- Ekko's rewind (4 s back): easy. The server keeps a few seconds of places and teleports you back.
- Sylas and Viego (use another's ability): cheap. Abilities are content with ids: using a foe's is a lookup, if it is a
  kind a player can cast.
- Yuumi and Kalista (attach to an ally, throw them): carry exists (#228).

## 4. Cost tiers
- FREE (content): any mix of §1.
- A NEW KIND (about one step each):
  - recast / a second press
  - pull
  - dash to a target
  - a chain or sequence of hits
  - a spread of missiles
  - return to a mark
  - a tether
  - lasting ground zones and traps
  - summons and clones
  - heals and shields on allies
  - swapping the kit mid-fight
- TEMPLATE WORK: stealth hidden from other players' games; walls that block walking; anything that changes walking itself
  (flight, wall-running).
- AVOID: hundreds of missiles; reaction windows under ~0.2 s; long forced paths on players.

## 5. The six limits
1. PLAYERS MOVE THEMSELVES. The server moves a player only by a PUSH (a velocity they feel, at most 40 m/s, #251), a
   TELEPORT (`place_entity`) or a CARRY (#228). Forced movement is built from those; a long smooth curving path forced on
   a player feels rubbery. Foes have no such limit.
2. 150 MS IS THE DESIGN LATENCY. A hit on a player lands at once and is taken back by a late parry or roll; anything ELSE
   it does to a player (a pull, a stun) is owed until it can no longer be taken back (`settle_dealt_hit`), so it lands a
   little later, by that player's own delay. Nothing another player must answer in under ~0.2 s.
3. 300 PLAYERS IN ONE WORLD. Every missile is an entity the referee flies: a few a cast is fine, a bullet hell is not.
   Anything lasting and ticking (traps, zones, pets) needs a cap a player. Missile counts at scale are NOT measured yet:
   a busy ability gets a load check (`load_300.sh`).
4. STEALTH AGAINST PLAYERS AND WALKING-BLOCKERS are template work (§2, §3).
5. ANIMATIONS are the biggest practical limit on how an ability LOOKS: the Quaternius and Mixamo clips we have, nothing
   AI-made (`ANIMATIONS.md`, `AI_ASSET_AUDIT.md`). A flip, a spin or a slam needs a clip we have. Effects are far freer:
   shaders and particles made in code (`vfx/`, `regents-genre.md` "AN EFFECT").
6. NO CLIENT DECIDES AN OUTCOME (rule 13). Every ability needs a rule the server can judge from inputs. "Hits what the
   player's screen showed" is fine (the referee rewinds up to 150 ms, #226); "the client says it hit" is not.

## 6. What could make ours stand out
- REAL PHYSICS for thrown things (`BodyDef`: bounce, friction, gravity, the referee flies it): an axe that ricochets off a
  wall, a boulder that rolls downhill, a bolt that skips across water.
- THE PARRY, STAGGER AND POISE combat: a stagger that gives a cooldown back, a riposte that opens a recast, a slow that
  grows while a foe's poise is low. Things a moba's abilities cannot lean on.
