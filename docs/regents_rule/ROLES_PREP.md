# Before roles: what is left, and the decisions that are yours (2026-10-31)

Luke, 2026-10-31: "I would like to get to roles soonish, what steps/stages are needed before that. I think some
content decisions need to be made for roles, from how they appear in the crafting UI to what traits/abilities/
finishers do etc. Also not sure if finisher is the best name for the last hit of a combo? We can brainstorm it,
and probably need a combat tutorial for trailer and new players."

Each decision below has options and a recommendation. Nothing here is built until you answer. The spec is
`COMBAT_OVERHAUL.md` (§5 roles, §6 picks, §8 what is yours); this sheet turns its open items into questions.

---

## 1. The road to roles

| | what | state |
|---|---|---|
| 1 | Pace and readability (foe kits, turns, aim lock, unblockable) | built (PROGRESS 26) |
| 2 | One string, the guard (parry, riposte, blocks) | built (PROGRESS 27) |
| - | The first feel pass (hit-stop, sparks, the stagger clip, death stops a swing, refusals aside) | built (PROGRESS 28), for your playtest |
| - | **Your playtest of the feel pass; then the values** (damage, wind-ups, hit-stop, stagger) | yours: "values after the feel" |
| 3 | **Statuses that stack** (template): Blocking no longer wipes Slowed; Shielded, Weakened, Support's effects become possible | built (template 1.7.0, PROGRESS 29) |
| - | **The decisions in §2** (sword first: D1-D6 are enough to start) | yours |
| 4 | **Roles, the sword first**: handle shapes, `RoleDef`, the role map, its three finishers, re-hilt, drops | after D1-D6 |
| 5 | Mastery picks | after D7 |
| 6 | Threat and Support (taunt, threat targeting, helping players near you) | after step 4 |
| - | **The combat tutorial** (§4) | can start once T1-T5 are answered; best after step 4 |

Nothing else blocks roles. Steps 4-6 are each playable on their own.

---

## 2. Role decisions

### D1. How a role shows in crafting (the recommended shape is the spec's)
A weapon's role is its HANDLE'S SHAPE (your Option B); the handle's material still gives the trait.
- **(a) Recommended: a handle pattern per role.** The sword gets three handle patterns (grip, crossguard hilt,
  banner hilt), each crossed with the woods like today's handle (an oak crossguard hilt is an item, and has
  oak's trait). In the craft window the handle row lists them with a ROLE BADGE and one line ("Tank: a full
  block, foes come for you"). The made weapon shows its role in its name ("Iron sword (Tank)"?), its tooltip
  and the bag.
- (b) One handle item, the role a choice in the craft window. Fewer items, but the role is no part you hold,
  sell or re-hilt with: it breaks "the handle is a real item" (§5).

Sub-questions under (a):
- **D1.1** The handle names. The spec's first proposals: sword grip / crossguard hilt / banner hilt; axe haft /
  bearded haft / war-horn haft; bow recurve grip / bracer grip / wayfinder grip; staff conduit shaft / ward
  shaft / censer shaft.
- **D1.2** Do Tank and Support handles cost more, or need a Crafting rank? (Recommend: the same cost and rank
  as the plain handle: the role is a choice, not a tier.)
- **D1.3** How the weapon names its role: in the name, as a badge, or a color? (Recommend: a small badge and a
  tooltip line; the name stays the material's.)
- **D1.4** Does the model change? Each handle could need a mesh (a crossguard shows). (Recommend: one mesh
  per weapon for now, the role on the badge; meshes later with the art.)

### D2. What every role carries (`RoleDef`)
| | Damage | Tank | Support |
|---|---|---|---|
| held block (decided) | weak, 60 % through | full, 25 % through | weak, 60 % through |
| threat multiplier (step 6) | x1.0 | proposal x2.5 | proposal x1.5 (healing draws foes too) |
| a passive? | none | proposal: 10 % less damage taken | proposal: your heals 10 % stronger |

**D2.1** Keep a passive per role at all, or only the block and threat? (Recommend: block and threat only at
first; passives come from mastery picks, so roles stay simple.)

### D3. The sword's three finishers (the 12 come later; the sword proves the shape)
First proposals (spec §5), with numbers to argue with. Each needs a clip (`ANIMATIONS.md`).

| | Damage | Tank | Support |
|---|---|---|---|
| name | Piercing thrust | Pommel bash | Rallying cut |
| hit | 26 (today's 20 +30 %), reach 2.4 m | 14 | 14, a wider arc |
| stagger | as now (800 ms) | x1.5 (1.2 s), and draws the foe's turn to you | as now |
| its own | the biggest hit | holds the foe, sets threat (step 6) | heals players within 6 m for 8 (not you?) |

**D3.1** Does Support's heal include yourself? (Recommend: yes, half.) **D3.2** Do the three cost the same
wind-up (380 ms) or differ? (Recommend: Damage 380, Tank 340, Support 400.)

### D4. A dropped weapon's handle
**D4.1** Equal odds of the three shapes, or mostly Damage? (Recommend: 50 % Damage, 25 / 25: the plain
handle stays the common one.)

### D5. Re-hilting
Decided: changing role = re-hilting at the workbench under the part-swap rule (the new handle used up, the old
one lost, plus bars). **D5.1** Keep the old handle instead of losing it? (Recommend: lost, as today's refit.)

### D6. The name of the last hit (§3 below)

### D7. Mastery pick pools (step 5; can wait)
Sword pools, first proposals: Damage Bleed cut, Execute (below 30 % health); Tank Taunt shout, Hold the line (a
3 s all-round block); Support Rally (heal over time near you), War cry (damage up near you). **D7.1** A
respec's cost once testing is over.

---

## 3. Brainstorm: a name for the last hit of the string

What it does: the string's last, slowest, hardest step; it cannot be interrupted; it interrupts; it staggers;
the role changes it. It is also the word on the HUD, in the tutorial and in the trailer.

| name | for | against |
|---|---|---|
| **Finisher** (today) | instantly clear | generic; sounds like a kill move |
| **Verdict** | the game's own (a REGENT's rule: the last word on the matter); "the sword's verdict"; roles read well: "a Tank's verdict" | needs one tutorial line to explain |
| **Ender** | a fighting-game term ("combo ender"), exact | gamer jargon; flat |
| **Crescendo** | the string is a rhythm; this is its peak | long; musical rather than martial |
| **Decree** | regal, short | close to Verdict, less clear |
| **Coup** (de grâce) | dramatic | means the killing blow |
| **Breaker** | says what it does (breaks guard and swing) | sounds like a different mechanic |

Recommendation: **Verdict**, with the string itself kept as "the string" ("three cuts and a verdict"). A
second option worth a look: name each finisher only (Piercing thrust, Pommel bash) and call the slot nothing
on the HUD.

---

## 4. The combat tutorial (new players and the trailer)

> **Built, first pass (PROGRESS 33, 2026-11-01)**, with Luke's two answers: the sword is MADE first (wood, grip, copper,
> bar, blade, rivets, the sword), then lessons 1-5 and 7 below against the yard's sparring skeleton; progress is a
> server table, each lesson ticked by the server. Lesson 6 (two foes) is not built yet.

Proposal: **the Proving Yard**, a fenced corner of the frontier camp beside the dummies, with a SPARRING
PARTNER (a skeleton in a tutorial FoeDef: slow swings, low damage, its glint and turns as the real ones'). A
short run of lessons, each a prompt, a try, and a tick when the server reports it done (rule 13: the server
says you parried, not the client):

1. **The string**: Tab the dummy, tap LMB three times; the last hit staggers it (the finisher, or its new name).
2. **The roll**: the partner winds up a big swing; Ctrl through it.
3. **The parry**: the partner's lights, slowed (a 900 ms wind-up); tap RMB as the blow lands. Then the
   **riposte**: tap LMB at once.
4. **The block and its arc**: hold RMB facing it (60 % comes through); turn your back and see it fail.
5. **The glint**: a red-glinting swing goes through a block: roll it.
6. **Two foes**: they take turns; wait for the opening.
7. (After roles) **your role**: what your handle's finisher does.

For the TRAILER: the same yard, a camera rig on rails, the partner scripted, every hit-stop and spark in shot.

Questions:
- **T1** Where: the camp's yard (optional, walk in), a private copy of the yard (no one else in it), or the
  first thing a new character sees? (Recommend: the camp's yard, offered once by a prompt; replayable.)
- **T2** Forced for new characters, or offered? (Recommend: offered, with a reminder after the first death.)
- **T3** Who speaks: a camp character (a drillmaster) or plain HUD prompts? (Recommend: prompts now, a
  character when there is voice or portraits.)
- **T4** A timing aid in the tutorial only (a ring closing on the blow) for the parry? (Recommend: yes, in
  the yard only; the real fight keeps the pose and the glint.)
- **T5** Before roles, or after? (Recommend: the first six lessons as soon as T1-T4 are answered; lesson 7
  with step 4.)

---

## 5. Your answers (2026-11-01; recorded in `GAME.md`)

- **The rule over all of it**: show, don't name. No "Tank", "Damage", "Support" or "finisher" on screen, nor in
  the tutorial; the player sees a badge and what a handle does.
- **D1** a handle pattern per role (the spec's names for the sword). **D1.2** same cost and rank. **D1.3** a badge
  and a tooltip, no role word. **D1.4** one mesh for now.
- **D2.1** block and threat only; passives later. Healing draws no more threat than damage (Support x1.0). The
  guard handle's threat: maybe bosses only; test it, adjustable (live rules).
- **D3** the sword's three as proposed, to start. **D3.1** the heal reaches you: full solo, less with players
  near (a live rule, decided after play). **D3.2** they differ (380 / 340 / 400 ms).
- **D4.1** 50 % plain, 25 / 25. **D5.1** the old handle is lost.
- **D6** no name on screen.
- **T1** the camp's yard. **T2** offered. **T3** mostly play, a few words, and the first friendly NPC. **T4** the
  ring, in the yard only. **T5** roles first.
- **D7** (pick pools) waits for step 5.
