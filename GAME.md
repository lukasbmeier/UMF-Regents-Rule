# GAME.md — what this repo is

**Regent's Rule** (game 4, working title): a fantasy MMO-lite for 100–300 concurrent players in one
database. One seamless world you log back into where you left; the weapon you hold is your class;
trees, veins and herbs are shared world objects worked through minigames the server scores; a lair in
the open and a procedurally assembled dungeon in an instance. A fork of the UMF template
(UMF-Foundation); foundation updates arrive with `git pull template main`
(`docs/TEMPLATE_WORKFLOW.md`), and foundation work is done in the template, not here. This game asks
for more of the foundation than games 1–3 together (M8, M16, M18–M26, the template 1.0): those are
built in the TEMPLATE and pulled.

| | |
|---|---|
| Genres | `regents` (`shared/game.json`): its client in `game/regents/` (content id base 40000), its server in `server/src/game/regents.rs` |
| Database | `regents-rule`; the suites use `regents-rule-test` |
| Main scene | `res://game/regents/regents_game.tscn` (the frontier glade, level 20) |
| Genre rules files | the hot rules `game/regents/content/rules/regents.tres` (the Rules page, `regents.*`) |
| Genre manifest | `tools/template/genres/regents.paths` (AGENTS.md rule 16) |
| Genre suites | `game/regents/tests/suites/regents.gd` (`-- --only=regents`) |

## The design
| File | What it is |
|---|---|
| `docs/regents_rule/RULE_DESIGN.md` | THE DESIGN: pillars, combat (four resolution kinds, the cast queue), the world and its chunks, NPC tiers, nodes and minigames, items, accounts, scale, the build plan (§12), open items (§13) |

Owner decisions (2026-10-13 scope; 2026-10-18 open items), which win where the design doc differs:
- **Scale**: 100–300 CCU per database, never more; a seamless open world; hybrid combat (tab-target
  basics, aimed skill shots); no global cooldown (a cast queue, cooldowns pace it).
- **#1 Universe**: a new fantasy setting; Hollow Hill's animals are assets, not lore.
- **#2 Resource**: ~~one 100-point pool for every kit~~ REVERSED 2026-10-20: **mana on the Staff only**
  (a generic resource); melee is paced by its combo and the roll, the bow by its arrows.
- **#3 Mastery**: XP stored, rank from a content curve; v1 ranks 1–10 (production will go higher);
  abilities at 1/3/6/9; harder nodes need a gathering rank AND a tool tier.
- **#13 Accounts**: SpacetimeAuth, an account that several identities link to (Steam later).
- **#15 Tools**: no tool slot; the best matching tool in the bag is used (OSRS-style). Five
  equipment slots: weapon, head, chest, legs, trinket.
- **#17 Minigames**: immersive to their skill (revised the same day): woodcutting is branch dodge; the
  others (mining, herbalism, smelting, smithing) are designed to that bar with Luke.
- **`chunk`**: added to the template's existing positional tables in a **template 1.0** (a reshape:
  every game's database wiped once, older builds stop connecting), not a side table.
- **The skilling loop comes first** (gather, refine, smith, then fun combat): every skill is dual-mode, AFK
  or an immersive minigame worth 1.25x yield and 1.3x rares (hot rules); woodcutting is branch dodge;
  gear is modular (Tinkers'-style core + handle, gear XP, durability and repair). Design doc §7.4.
- Decided since: yield = AFK x 1.25 x score; tap E = AFK, hold E = minigame; tier bands (1-3, 4-5, 6)
  each get a harder minigame.
- **Combat** (2026-10-19): hybrid control (aimed light/heavy, a dodge roll, block, Q E R F skills);
  abilities come from the weapon type (its kit), unlocked at mastery 1/3/6/9; **#22 settled**: the
  smithed handle or hilt adds a trait. Tab picks a target (a ring) but attacks stay aimed. Swings are
  animation-locked with a one-press buffer; a roll cancels a wind-up; heavies flinch lights.
- **Loot, items, styles** (2026-10-20): `docs/regents_rule/LOOT_AND_STYLES.md`, whose AMENDMENTS win
  over its body (this settles **#7 loot**): quality 0-1000 shown as Common / Fine / Masterwork bands;
  Power from tier and quality, tier dominates; personal loot rolls on the ground; durability and repair
  an option; **no global cooldown** (each ability its own; the cast queue is input buffering only);
  **melee never rolls to hit**, ranged (bow, Staff) rolls; controls: Ctrl roll, Q E R F, LMB tap the
  combo / hold the heavy, RMB block.
- **Traits** (2026-10-21): every trait trades and never touches Power; **a handle's trait always
  applies**, whatever the item's grade (grade sets how many a drop rolls); Brutal reads the TARGET's
  health; the handles are toned to the early game (oak Steady, yew Springy) until **a materials and
  Tinkers' deep-dive**, which Luke wants later. (The "always applies" part is REPLACED 2026-10-23, below.)
- **Materials and modular gear** (2026-10-23, `docs/regents_rule/MATERIALS.md`, which wins over §7.4 and
  `LOOT_AND_STYLES.md` where they differ): materials are a GENERATED table (`MaterialDef` x `PatternDef`,
  baked to real items, any cell overridable, today's ids pinned); a pattern lists open-ended part SLOTS
  (head, handle, binding usually; an oil or a 4th/5th part is more slots); the CORE's material sets the
  tier (metal for melee and tools, WOOD for bows and staves, metal then secondary); secondary parts carry
  traits; **a crafted item holds traits by grade, Common 1 / Fine 2 / Masterwork 3, and the player picks
  which** (the station shows the count and which are in use); trait RANKS I-III paid in bulk base
  material + a catalyst + **gear XP** (now: earned by use, it gates the rank upgrade, never Power);
  catalysts drop from about +3 / +6 ranks over a node, with NORMAL depletion; the slice's ladder is
  **copper, iron, steel** (iron + coal; the bronze starters renamed copper); durability stays parked.
- **Telemetry** (2026-10-21): live, for looking back, with full history: BOTH a chronicle on the host's
  disk (every change of every table, a place every 5 s; template #276) and the meta rolled up in the
  database (`meta_share`, the 45 % alarm); a local dashboard (`tools	elemetry.cmd`). Then a polish round
  before the materials deep-dive: health bar, work progress, roll cooldown, minimap (OSRS style, to
  iterate), hit flashes, Make 1 / X / all.
- **Tester tools** (2026-10-23, after his first look at the ladder: "an admin button to reset the stats or
  manually adjust them"): a **Tester (admin)** page in the Escape menu, the admin only, acting on **any
  player** in the world: set a skill's rank, reset all skills (with recipe records and orders), give any
  item (a quality for one that does not stack), reset the bag to the starter kit.
- **The order of work** (2026-10-23): (1) Luke's playtest of steps 17-20, then fixes; (2) **the template 1.0
  with accounts** (TAKEN 2026-10-24; this game's half DONE the same day, PROGRESS step 22: ring interest,
  3 characters an account, parked 30 s after leaving, `chunk` on Regent's own placed tables; Luke chose a
  second wipe for it, `compat` 3, since no compat-2 build had gone out) (chunks, streaming, interest management; SpacetimeAuth accounts and characters that outlive
  a machine), template work pulled here, one wipe; (2b, Luke 2026-10-24) **the load test** on the continent
  (PROGRESS step 23 the continent; the harness next, in the template), the combat talk alongside;
  (3) **the combat deep-dive**, folding in equipment and
  armor (the five slots, stats), the server-side cast queue, crits and NPC tiers; (4) **the in-game lookup**
  (added 2026-10-24, below); (5) **herbalism and the
  economy** (marks, vendors). After those: writs, potions, death and shrines; party, duels, the lair and the
  Undercroft (M8, M25); the 300-bot load test. Movement feel from the template and Fishing that Regent's
  lost (the camera orbiting a still character without turning it; diagonal strafing that blends well) is
  noted for when it suits, likely with combat.
- **The order of work from here** (Luke, 2026-11-03): after his melee spot check and its fixes, (1) **ARMOR** next:
  the equipment slots and their stats, planned first in a prep session (as `ROLES_PREP.md` was for roles; the prep
  doc is not written yet: the next session starts with it); (2) **the rest of the combat deep-dive** (overhaul steps
  5-7: mastery picks, threat and Support, content fill; the cast queue, crits, NPC tiers); (3) **a MINIGAME
  OVERHAUL**: the skilling minigames made fun and engaging, so the skill that earns Fine and Masterwork materials is
  real, with progression as a skill levels up; before the in-game lookup; (4) **the in-game lookup**; (5)
  **herbalism and the economy**; (6) writs, potions, death and shrines; (7) party, duels, the lair, the Undercroft.
  **REPLACED 2026-11-04**, below ("The order of work, armor parked").
- **The order of work, armor parked** (Luke, 2026-11-04: "it seems we may be too early for armor without more
  resources and content"): (1) **the American-spelling pass**; (2) **the MINIGAME OVERHAUL** (as above: Fine and
  Masterwork take real skill, progression as a skill levels up); (3) **herbalism and hunting**: fiber and hides, and
  the creatures hunted for them (foe design too: the place for foes that push, poison or slow); (4) **ARMOR**, back
  with cloth, leather and real threats (`ARMOR_PREP.md`, parked). Not yet placed by Luke, the agent's proposal: the
  rest of the combat deep-dive (overhaul steps 5-7: mastery picks, threat and Support, content fill; the cast queue,
  crits, NPC tiers) AFTER hunting, so its new creatures give them something to work against; the in-game lookup, the
  economy (marks, vendors), writs, potions, death and shrines, party, duels, the lair and the Undercroft after that.
- **COMBAT BEFORE ARMOR** (Luke, 2026-11-11, after playing the wolf: "The playtest is decent, i think its in a fine
  spot for now until I get more eyes"; "Combat definitely needs some work but armor first or after we get combat in a
  good spot?"; of the two, "Combat first"). The order from here: (1) the wolf's server tests and one integration run;
  (2) a BOUNDED combat pass: what Luke felt in play (his list, still to come) and a real-referee fight check; (3) one or
  two new foe types (a caster or an archer), so armor has its combat triangle; (4) **ARMOR** (`ARMOR_PREP.md` §0, a
  prep session first); (5) the rest of the combat deep-dive (mastery picks, threat and Support). The parked hunting
  items (stag, sinew, the fang charm, hemp and nettle) come as content when armor's material tiers need them. Why
  combat first (the agent's reasons, accepted): armor's numbers are tuned against how hard and how often foes hit, and
  its open question (why wear lighter armor) needs foes that do not exist yet.
- **THE COMBAT PASS, his list** (Luke, 2026-11-11, `PROGRESS.md` step 60). What he felt, in his words, and what he
  chose when asked before he stepped away:
  - **A free shot goes TO THE CROSSHAIR** (asked: to the crosshair, the same with a light assist, or level and lower;
    his pick, the first): "arrows and magic attacks dont come from where you think they would ... point the hand and
    the bow less to the left and more to the center of the screen", "they also fly at a height that makes hitting
    wolves nearly impossible". A bolt with no Tab target lands where the crosshair is; an arrow lands on the BODY
    the crosshair is on, and with the crosshair on the ground or the sky leaves straight for that point and falls
    short as an arrow does (the agent's narrowing, found in the playtest: arced to a far point it flew over whatever
    stood near the crosshair; Luke's to overrule); the upper body
    turns so the bow and the casting hand point there; a shot the server aims at a Tab target goes to the middle of
    its body (a wolf's is 0.5 m up, not a man's 1.1). No aim assist.
  - **A roll is judged where it was pressed; a hit shows as soon as your own line allows** (asked whether the server
    may credit the network delay to a roll, for foes and players alike, foes only, or not at all; his pick: "Yes,
    credit the delay"): "the LAG when getting hit is really annoying, the delay that I think I dodged an attack only
    for .5 or .8 seconds later to get hit". Capped as a parry's is (`foundation.rewind_max_ms` 150 +
    `foundation.press_credit_cap_ms` 120). In PvP, when there is any, an attacker will sometimes see a hit that
    looked good roll clear: accepted with the pick.
  - **A roll goes a set length**: "if I roll forward but then press s it goes a short distance. I think maybe we make
    it a set amount for consistency?" Held to the way it began for its whole length.
  - **Melee is visual clarity**: "trails for weapon swings (enemy and yours) mixed with slowing some things down
    (antipaction for enemy attacks)"; and "trails for arrow projectile ... and better magic vfx" as juice.
  - CLAUDE'S NUMBERS in it, his to change: `regents.roll_late_ms` 50 (a roll up to 50 ms late still clears, as the
    parry's late window) and `regents.hit_hold_slack_ms` 40, both on the Rules page; the foes' light swings a fifth
    slower (rusted cut 550 -> 660 ms, backswing 580 -> 700, hack 590 -> 710, wolf bite 550 -> 650, hamstring 620 ->
    720; the finishers as they were); every trail's color, width and length (the three `*_look.tscn` and the
    `SwingTrail` node in `adventurer.tscn` and `foe.tscn`).
  - **HIS PLAY OF IT, the same day** (2026-11-12, `PROGRESS.md` step 61):
    - "if tab target hand and bow should point towards them": the upper body turns to the Tab target, not the
      crosshair, and a shot is seen to leave the hand ("rather at the middle of where my character is standing").
      He will adjust the last degrees himself if needed (`CombatLook`'s "pose points", `tests/aim_shot.tscn`).
    - **FACE YOUR TARGET**: "I can tab target and then face AWAY from the target and still shoot, I think either it
      should turn the model and force facing ... or refuse to shoot if not facing somewhat near". Asked (refuse, turn
      to face it, or shoot at the crosshair instead); his pick: **refuse the shot**, inside the same 120 degree arc
      Tab picks from (`regents.aim_arc_deg`).
    - **A FULL POISE BAR BREAKS ON ANY HIT**: "if the stagger bar is full (orange) the next hit should stagger not
      just the next finisher hit". Narrows 2026-11-02's "only the last hit breaks it": a light still cannot empty a
      bar in one go (it fills it), but the hit after, of any kind, breaks it.
    - He played at 200 ms with 50 ms of jitter: "the combat still works but feels worse", and asked how other games
      give immediate feedback when a hit waits for a late parry. Given the options, his word: "Lets either build
      'deal the hit at once, take it back on a late parry' or have No late window whichever is preferred for
      gameplay and latency." BUILT: **deal at once, take back** (the agent's choice of his two, `PROGRESS.md` step
      62: no late window would cut a 200 ms player's parry window from 250 ms to about 80); a hit that would
      stagger or kill still waits; `regents.hit_at_once` 0 puts the wait back. NOT DECIDED, his: a foe's swing
      shown landing at the server's time (skipping the start of its wind-up by the delay); your own hits' spark
      shown at once.
  - **HIS VERDICT** (2026-11-12, after playing step 62): "Combat feels better." The combat pass is CLOSED. Next, his
    word: a new session "to continue through the order sent with the first message": (1) the combat pass, done;
    (2) one or two new foe types, a caster or an archer, "so armor has its triangle"; (3) armor, starting with a prep
    session on what was left open when it was parked (`ARMOR_PREP.md` §0); (4) the rest of the combat deep-dive:
    mastery picks, threat and Support. His own list's later items (just below) are for "answering and more depth".
  - STILL HIS, for the next session (not built, not defaulted): the ability bar in place of the text at the bottom,
    with each weapon's choices and its XP and next unlock shown ("like albion"); Q, E, R at the least on every weapon,
    more for ranged and melee, with AOE (the axe's Cleave hits one today: the referee reports a sweep's first body);
    single combat zones against multi combat ("like osrs or not").
- **THE ABILITY REWORK BEFORE ARMOR** (Luke, 2026-11-13, after the foes: "I want to do the ability rework before armor
  as armor chest piece will add 1 ability"). What he said is settled, the rest is open in
  `docs/regents_rule/ABILITIES_PREP.md` (its decisions B1-B15):
  - The light attacks stay as they are: "for melee and ranged (bow) the auto attacks feel good. Mage autos feel less
    good but I think because of the placeholder projectile model and the low damage."
  - At most FOUR abilities on Q, E, F, R, "added from weapons and armor chest (or set bonus maybe ... lets brainstorm".
  - A clean bottom bar ("albion like or other examples"), in place of the text line.
  - Every weapon starts with its base ability (Q) as part of crafting, "unique to each weapon or role type"; the rest
    come from leveling the weapon: the 2nd level a choice of a 2nd ability OR enhancing the base, the 3rd the same,
    the 4th an "ult". A player will not always have four; an empty slot may hold a potion or another thing ("maybe").
  - Open in his words: "im torn if we offer more levels (cause level 1-4 wont take that long or if it does take that
    long then the player is missing abilites for a long time) that offer damage and other perks".
  - His direction after the sheet's first draft (not final; the sheet's revision 2): plan for a long track ("99 or 60
    ... a fun time sink, we should plan for future scope"); ITEM levels over mastery-only ("tinkers tools ... its a
    trade"), leaning to a new item catching up fast to your mastery, feeding an old item into a new and re-heading an
    item later (re-heading's groundwork now), an item's picks its own; content not minimized ("unique playstyles are
    important"); and two questions to answer early: trading a levelled item, and losing one ("insurance ... or some
    portion of XP given in a lamp to be used on a new weapon").
  - ALL ANSWERED (B1-B15, 2026-11-13), one by one (`ABILITIES_PREP.md` §6); the order of work is its §7:
    - B1 ITEM LEVELS (Luke, 2026-11-13: "Accept B1"): two layers. MASTERY, the character's per weapon kind, never
      lost: it sets the catch-up, gates better gear and the deepest options, keeps its 3 % a rank. THE ITEM'S LEVEL,
      by use: it opens the item's slots and picks, and its PICKS ARE ITS OWN. CATCH-UP: below your mastery an item
      earns XP faster (a hot rule, 5x to start), above it at normal speed; the deepest options need both. Feeding an
      old item into a new (with the "lamp") and re-heading come later; re-heading's GROUNDWORK now: level, XP and
      picks keyed by the item, the head stored as a part.
    - B2 TRADING A LEVELLED ITEM (Luke, 2026-11-13: "T4, use up to mastery"): tradeable WITH its level; a holder uses
      it only up to their own mastery of its kind (a 40 sword works as 25 for a mastery-25 holder, the rest opening
      as their mastery grows). The tooltip shows both numbers. Not bound.
    - B3 LOSING A LEVELLED ITEM (Luke, 2026-11-13: "As proposed"): nothing is lost now (as v1). A RULE FROM NOW: an
      item is only ever lost where the place says so (a PvP zone, a hardcore realm, a quest), with INSURANCE bought
      before, once marks and vendors exist. THE LAMP is how loss and salvage both work when either is built: a lost or
      salvaged item leaves an essence of half its XP, poured into a new item of its kind (the essence trades as an
      item does, T4). Durability stays parked.
    - B4 THE LONG TRACK (Luke, 2026-11-13: "99, slots by 20"): mastery and item levels run 1-99 (replacing v1's 10).
      All four slots open by ~20 (Q at 1, the 2nd pick ~5, the 3rd ~12, the ult ~20); 20-99 is depth, never slots
      (more options in each pool, ability ranks, passives, gear needing the rank, a mark at 99). The curve steep at
      the top; the hours to 99 (a first guess 100-200 of fighting a kind) tuned in play. All of it content (curves,
      unlock levels), not code.
    - B5 THE SLOTS (Luke, 2026-11-13: "Fix where they come from (3 from weapon, only one from chestpiece ...) but let
      the player reassign to any order if they want? for now we can just keep it simple but input reassign/
      accessibility is nice to have"): the SOURCES are fixed: up to three from the weapon (its base, its 2nd ability,
      its ult), at most one from the chest. The KEYS are the player's to reorder, later; for now the default stands:
      Q, E, R the weapon's, F the chest's. Build the bar so a slot's key is a setting, not a constant.
    - B6 THE PICKS (Luke, 2026-11-13: "Accept b6 but changing picks should cost something"): at the item's ~5 and ~12,
      one pick each: a 2nd ability for E (one of its pool's) or an upgrade (of Q, or E once there); the ult at ~20.
      Each item's its own; changed out of combat, AT A COST (which cost: B13).
    - B7 CONSUMABLES AND AN EMPTY SLOT (Luke, 2026-11-13: "I like option 3", after: "potions and food seem like a
      necessary eventuality so maybe we just make them their own thing"): ONE POTION KEY for everyone (a combat potion,
      its own key, G proposed, its own cooldown); FOOD eaten from the bag out of combat as a long buff (no slot); an
      EMPTY ABILITY SLOT (E for a tall build, F with a chest that has no ability) takes UTILITY TOOLS only (a bomb, a
      trap, throwing knives, a smoke flask: crafted, used up, in stacks), never potions. His worry, "does a wide build
      miss out on utility tools (so less people go wide)": answered by the trade (abilities free and growing, tools
      paid and used up) and by F (a plain chest frees a tool slot for anyone); the levers, a tool's strength and cost,
      tuned on the bench and in play. Until tools exist an empty slot shows what fills it.
    - B8 THE CHEST'S ABILITY (Luke, 2026-11-13: "accept b8 with me liking future full set bonuses being a thing
      (either enhancing the ability or something else)"): the CHEST carries its own ability on F, by its material
      family (cloth casting and moving, leather quick utility, metal guarding), which of its family's picked at
      crafting as traits are, the chest levelling as a weapon does (B1); a chest made without one frees F for a tool
      (B7). BLINK MOVES from the staff to cloth chests. FULL-SET BONUSES are WANTED LATER (enhancing the chest's
      ability, or something else), on top of the chest's ability, never in place of it.
    - B9 POOLS IN LAYERS (Luke, 2026-11-13: "Accept B9"): an item's options are ASSEMBLED from layers, each content a
      designer adds without code: its weapon KIND (the core), its ROLE (the handle's own options), THE ITEM (a unique
      drop, later a rare pattern), later its material or a trait, and the chest (F). The system holds every layer from
      the start; content ships in slices, the roles' options in the first. A pick shows every option you qualify for
      (more open along the long track); a unique's option is sideways, not stronger.
    - ROLES IN THE LAST HIT AND IN Q (Luke, 2026-11-13, B10's discussion): every weapon's BASE Q DIFFERS BY ROLE
      ("sword dps is lunge, sword support is healing swipe, etc.  kinda an extension of how finishers play now").
      The role's LAST HIT stays, as a SMALL ALWAYS-ON effect distinct from its Q (option C: "the small effects can be
      universal per weapon type ... all dps swords have the small effect on finisher all axes have same effects etc";
      not by material); "if we dont feel like C is feasible to maintain content wise, b is safest option" (B: roles
      in abilities only, one last hit per weapon kind).
    - SEPARATE POOLS PER ROLE (Luke, 2026-11-13): each role of each weapon its OWN full set (no shared weapon-kind
      pool that a role adds to: that made a damage role strictly worse). He wants "each weapon of each role a unique
      set of abilites even if that means way more content work" (a sword 9-12, 3-4 a role).
    - MATERIALS: he likes "the twist/variance per metal" (a metal giving its role's abilities a twist, or an extra
      option, rather than a whole new set), keeping "every upgrade is new toys and exploration"; wood for bows and
      staves as metal for melee. Whole sets per material: open until the ANIMATION INVENTORY (UAL1, UAL2) says what is
      feasible.
    - B10 THE POOLS' CONTENT (Luke, 2026-11-13: "Yes, roles + twist", after the inventory, `ABILITIES_PREP.md` 3.11):
      PER-ROLE SETS (3-4 abilities a role, separate pools, each role's own base Q) for every weapon kind, motions
      shared between abilities and the EFFECT carrying the difference (the bow and the staff lean on effects); a
      MATERIAL gives its role's abilities a TWIST (an effect and a rule: iron sparks or bleeds, steel pierces, oak
      staggers, yew flies further), never a whole new set. The real content (names, numbers) is designed at each
      weapon's build step, played and benched; §3.8 is a draft.
    - B11 THE BAR (Luke, 2026-11-13: "I like round or square, maybe we do a small build of both like cinema lab has
      speech bubbles and osrs like boxes. otherwise accept b11"): a row low in the middle, Q, E, R, F (keys
      reorderable later, B5), the potion key G a little apart; on each its key, its cooldown counted on it, a locked
      one dim with what opens it, an empty one showing it takes a tool; a ring round the weapon's three filling to the
      item's next unlock; health above, mana or arrows beside; hover for what it does, no role or mechanic names; the
      mouse's string and guard off it, the text line's hints to the tutorial and a tooltip; it fades out of stance.
      The item's level against your mastery in the item's tooltip, not on the bar. ROUND AND SQUARE BOTH BUILT FIRST,
      a small lab to switch between (as the cinema lab shows its presenters), his pick after seeing them.
    - B12 KEYS (Luke, 2026-11-13: "keep as now with clear indication if in combat/stance or not. i do like context for
      option 3, but that can come later"): Q, E, R, F fire in stance; out of it E is the world's key (gather, talk),
      as now. The bar and the HUD SHOW CLEARLY whether you are in stance or in combat. LATER, liked: a context E in
      stance (looting a sack, reviving a downed player without putting the weapon away).
    - B13 CHANGING PICKS (Luke, 2026-11-13: "I like 2, 3, 4, 5. dont like 1 because as you stated can always make a
      new sword (but lose xp). I do think before level 20, the price should be equal to the amount of abilites unlocked
      so respecing one thing cost less than 3 or all 4"): ONE FREE CHANGE PER ITEM PER WEEK; past it, MATERIALS of the
      item's head at a workbench, out of combat, ESCALATING with each change (1x, 2x, 4x), the escalation halving each
      week without one; MARKS join the cost when they exist; a NEWLY OPENED pick is always free to choose. The price is
      PER PICK CHANGED: changing one costs less than three or four, so an item below 20 (fewer picks open) is cheaper
      to change. No free changes below 20. Every number a hot rule.
    - B14 THE STAFF'S BOLT (Luke, 2026-11-13: "Accept B14"): inside this rework: a real projectile (flight, trail, a
      cast flash, an impact burst, from the arrow's and fireball's looks), its damage benched against the other light
      strings and set in line, a feel check in play; it stays free (no mana). When: with the axe's and bow's pools (the
      order of work's step 4) unless he asks for it sooner.
    - B15 ONE XP TRACK (Luke, 2026-11-13: "one xp track is fine", with a REFIT): an item's XP is its LEVEL and is never
      spent. Trait ranks are GATED by the item's level (the level each rank needs is placed on the 99 track, hot rules)
      and paid in bulk material and a catalyst (`MATERIALS.md` §5), never in XP. Once levelled, an item is REFIT at the
      workbench with higher-ranked parts (a handle, a binding) its level now takes: the swap `MATERIALS.md` §11 already
      allows (the new part, the old lost, bars of the head's metal; traits re-picked within the grade's room), and the
      item keeps its level (keyed by the item, B1's groundwork). A part of a rank above the item's level does not fit.
      Trait ranks work for WHOEVER HOLDS the item (they are the item's, like its metal); only abilities and picks follow
      the holder's mastery (B2). The grade still sets how many traits it holds: a Common item holds one at any level.
    - AFTER STEP 1 (the bar, PROGRESS 72), S1-S4 (`ABILITIES_PREP.md` §8):
      - S1 + S2, THE LONG TRACK IN CHUNKS (Luke, 2026-11-13: "lets do it in chunks, lets move everything from 1-10 to
        1-33 (a third of 99) for testing. There will be wipes between now and the demo for public so we can finalize
        it then"): EVERY skill (weapon masteries, gathering, making) runs 1-33 for now, a third of B4's 99; the 99
        curve, its hours and the bonuses are finalized before the public demo, with a wipe.
      - S3 THE SWORD'S POOLS (Luke, 2026-11-13: "draft a short sheet for me to rewrite"): the agent drafts, he rewrites.
      - S4 THE STAFF'S POOL (Luke, 2026-11-13: "yes on s4, but gale needs buffed largely as it does 8 dmg and nothing
        else right now on a long cooldown"): Q Fireball; its first pick (~5) Frost Ring OR Gale OR a Fireball upgrade;
        Blink on F until cloth chests (step 5); no ult before step 4. GALE BUFFED LARGELY.
      - R ASSIGNED (Luke, 2026-11-14, after play: "right now mage seems to only be able to take an e ability (gale or
        frost ring) even though I am level 33 ... fix the R ability not being assigned"; "the mage abilites are in an okay
        spot"): until a weapon has an ult of its own, its LAST PICK (level 20, R) takes the option E did not, so a staff
        at 20 has Fireball, Frost Ring, Gale and Blink. He fleshes out the axe's, sword's and bow's role abilities next.
- **THE UI, A REBUILD SOON AFTER ARMOR** (Luke, 2026-11-14: "we need a separate ui from the bag and possibly new UI
  anyway to match the feel of our ability bar. The inventory and other UI was placeholder and its about time we were able
  to drag, resize, etc in a most robust inventory system plus C for character sheet when armor is introduced. we dont have
  to do that now, but lets at least write some to dos and later work for it soon after armor. for now basic weapon
  ability ui once you click a weapon in your bar or your bag will work"). Built now: the weapon's ABILITIES WINDOW
  (PROGRESS 76). TO DO, soon after armor (each his to shape before it is built):
  1. THE INVENTORY REBUILT in the bar's look: DRAG AND DROP (move, swap, split a stack, drag out to drop on the ground),
     windows that DRAG AND RESIZE and remember their place and size (a player setting), sort and filter, a tooltip that
     compares with what you wield or wear.
  2. C, THE CHARACTER SHEET (with armor): the five slots (weapon, head, chest, legs, trinket: the standing rule) on a
     figure, equip by dragging from the bag, what each piece gives (armor's numbers, the chest's ability on F, full-set
     bonuses later: B8), the weapon's level and picks (the abilities window folds in here or opens from it).
  3. ONE LOOK for every window (the bag, the skills K, the stations, the world map, the Tester page): a UiStyle theme
     from `RegentsBarStyle` (round or square), so a window and the bar read as one game.
  4. The bar's keys reordered by the player (B5: accessibility), from the sheet or the Settings.
  The foundation's `UiWindow` drags but does not resize or remember: that part is TEMPLATE work (`foundation/ui/kit/`).
- **NEW FOES, ANSWERED** (Luke, 2026-11-12: "Accept all proposed"; the sheet is `docs/regents_rule/FOES_PREP.md`, its §9
  the order of work). His word for the aim: foes "smart but fun (not annoying or painful)"; the sheet's §4 rules stand
  for every foe (every hurt announced, one question per foe, nothing from off screen, a foe that keeps its distance is
  caught, a fair miss, an opening always, never chained).
  - F1 the foes: a SKELETON ARCHER and an IMP CASTER; the Puglin with AOE and the Hellwarden as the first boss, later.
  - F2 foes run on LimboAI TREES, the melee brain moved first with no change in behavior.
  - F3 the archer up close: one step back at most every 6 s, then a slow shove. It never runs for good.
  - F4 your defenses against an arrow or a bolt: a held guard facing it blocks it as a swing; a timed parry knocks it
    away, no riposte; a roll passes through it. A ring on the ground is only left.
  - F5 a shot's tell: the draw pose 1200 ms, a glint as it is about to loose, aim locked the last 250 ms. "No leading"
    REVERSED (Luke, 2026-11-13, his playtest: ranged foes "much easier to handle than melee", "the no prediction casts
    are easy to dodge"; asked whether shots should lead: "Yes, lead first"): A SHOT LEADS A MOVER, to where the walk it
    reads at the lock carries you as it arrives (`regents.foe_shot_lead_pct`, 100). A turn, a stop or a roll after the
    lock, a guard, a parry or a rock still answer it. Rings are not led (PROGRESS step 67).
  - F6 shots and turns: a shot keeps the gap between foe hits; one foe shot in the air per player
    (`regents.ranged_tokens`, a hot rule); a shooter takes no melee turn.
  - F7 any hit that flinches stops a cast; its cooldown is still spent.
  - F8 a foe's spell does damage only (no slow, burn or root) until armor says what resists what.
  - F9 a foe notices in FRONT (140 degrees at `notice_m`) and hears all round at 4 m, further if you sprint.
  - F10 foes at rest wander a few meters round their point.
  - F11 hit from out of sight, a foe turns on WHO HIT IT; switching by threat waits for the overhaul's threat step.
  - F12 NOT CHAINED: after a stagger or a slow from a foe, no other foe's can land on you for 1500 ms (the hit hurts).
  - F9 to F12 BUILT 2026-11-13 (PROGRESS step 68, "Luke: Start step 5"); the agent's calls there are his to change.
  - F13 the imp's family is "fiend". F14 loot: the archer the camp's table and 2 to 5 arrows half the time; the imp
    the camp's table for now. F15 the glade gets one archer and one imp by the skeleton camp; the continent one archer
    in each camp of three or more (a test placement). F16 the sheet's §6 numbers as a start (the agent's, his to change).
- **Bushes are not solid** (Luke's playtest note, 2026-10-24; CONFIRMED 2026-10-26: "bushes should be passable
  like the other grass foliage"): of a level's props only ROCKS stop you and a foe's sight
  (`RegentsSolidProps.solid_models`); bushes, grass and flowers are walked and seen through. Narrows his
  2026-10-21 "every 3d object should have collisions".
- **The world map** (2026-10-26): **M opens a full world map** with hoverable icons. A node you have
  DISCOVERED says exactly what it is ("Coal ore"); one you have not says its skill and ??? ("Mining ???").
  **Discovered is per node, by being near it** (Luke chose "seen, per node" over "gathered once" and "seen
  per kind"). **Points of interest** are marked on it: the test zones, harvest zones, camps and so on.
- **The in-game lookup** (2026-10-24, scheduled before herbalism and the economy, "to look into" with Luke
  first): WAILA/Jade-style help that is player friendly without being hand-holdy or cluttered. Wanted early:
  a **glance** line for the current target (name, needs: rank and tool tier, green/red for you), a **detail**
  card on a key (a node's drops, a foe's loot, a station's recipes; drops shown as `???` until you have
  found them, with their chances), and OSRS-style **skill guides** (what each rank opens) in the skills
  window. **No full in-game handbook for now**: the wiki (`UMF ALL\Regents Wiki`) is to be shared later.
  Known before the look: the client already has every number; a per-player "found" record is the one new
  server table (add-only); Q is taken (station recipe pick, kit skill 1), so the key is to choose. Open,
  Luke's: exact chances or words ("rare"); what `???` hides (the item, or its chance too); the key.
- **Answers** (2026-10-23): **hosting** on Luke's machine for now, then a VPS, before any Maincloud
  measurement; **the bow's damage scales with the draw** (built: a quick release 30 %, a full draw 100 %,
  `regents.draw_min_power_pct`); herbalism's and the higher bands' minigames when they are made; **the minimap
  gets a choice: locked north-up, or turning with the facing** (how it grows: open). Materials §11: see
  `MATERIALS.md` §11.
- **The step 2-3 defaults, confirmed** (2026-10-23): steel Power 140 and tools at 75 %; coal needs an iron
  pick and mining rank 3, a steel bar 2 iron ore + 2 coal at smelting rank 3; swapping a part re-ticks every
  trait the new parts offer; a lower-grade batch keeps the FIRST traits in the order wanted.
- **After his playtest of the crafting rework** (2026-10-23): the traits header says the grade without the
  quality number; **the head (any core) is picked BY GRADE** in a list ("Masterwork iron axe head (1)"), a
  grade not in the bag grayed, and a run uses only that grade; **metal rivets now** (not after herbalism):
  rivets are a pattern (copper, iron, steel), the binding slot takes any; **every part offers a tool trait and
  a weapon trait** (only one that fits the item counts: an axe takes the tool's): oak Steady / Heavy, yew
  Springy / Balanced, copper rivets Gentle / Thirsting, iron Lucky / Brutal, steel Prospector's / none until
  Keen (crits, the combat deep-dive); stacking allowed; **parts can be swapped after an item is made**, at
  the workbench: the new part used up, the old lost, plus bars of the head's metal (hot rule, start 2), the
  head and quality never change, gear XP kept, traits re-picked; tooltips on materials and parts say what
  they lead to. **Trait ranks: both paths** (a better-made part starts higher; upgrades through use) are
  liked but NOT decided: the minigames must be harder first so Masterwork is not routine, and AFK crafting
  must still pay (an AFK part is Common): to think through before `MATERIALS.md` step 5.
- **Crafting signed off** (2026-10-23, after step 21): "pretty good as it stands". Later: revisit the refining
  and other minigames so Common, Fine and Masterwork take real skill (also what trait ranks wait on).
- **Load test before combat** (2026-10-24): the 300-bot load test moves ahead of the combat deep-dive, the
  combat design talk alongside it. It runs on **the continent** (PROGRESS step 23), Luke's map's main
  landmass (no islands; the name on the map, Aethel, not taken): **about 3 km across**, the camp in the
  **center-west lowlands**. A greybox for testing: its node and skeleton placement is a test one, and the
  world's regions, roads, towns, the lair and the Undercroft are Luke's to design later. A fresh database
  still starts in the glade (level 20); the continent is level 21 (`set_world_level 0 21`).
- **A Skyrim-size test world** (2026-10-30): "try it on a world close to the same size as skyrim with 300
  players to see ... how many refs I need ... with me playing a local user as well". The **expanse** (level 22,
  PROGRESS step 25) is that: the continent's map 3.7 times as wide, ~37 km2 of land, its test placement at the
  continent's density. A TEST world for the load test (the test database only); the continent stays the world.
- **The combat overhaul** (2026-10-30, `docs/regents_rule/COMBAT_OVERHAUL.md`, which wins over the 2026-10-19
  Combat line, the 2026-10-20 controls and `RULE_DESIGN.md` §4 where they differ). From the playtester's "too
  fast, at the same time, hard to read" and Luke's "generic":
  - **Pace: deliberate.** Foes get their own abilities (wind-ups ~550-850 ms), rest 1.5-2.5 s, and at most 1-2
    attack one player at once (attack tokens, a ~600 ms gap counted from each swing's landing, hit or not). A
    foe's aim tracks, then locks for the last ~300 ms. TTK about 12 s attacking only, 7-8 s played well; HP
    moves only if play says so; loot judged per minute. **Built 2026-10-31** (PROGRESS step 26) but loot per
    minute, waiting on the playtest.
  - **No Break/poise spine and no bar** (Luke: it would be min-maxed over damage and utility). Stagger is a
    payoff; systems stay varied but simple.
  - **One combo, no separate heavy**: LMB taps a string, each step a little heavier; **the last hit is the
    finisher and the heavy** (armor, flinches a light, staggers). No hold-LMB on melee. A swing at air still
    advances the combo. The window is a hot rule, 2000 ms; follow-through replaces `chain_ms` (fixes #8).
    The Heavy trait becomes a longer stagger on the finisher.
  - **RMB is only defense**: tap = parry for every kit and role (judged on the hit as you saw it; a missed
    parry locks parrying ~400 ms); hold = a front block, real for the Tank, **weak for Damage and Support**.
    **A parry pays stagger + a riposte** that counts as combo step 1; the bow's riposte makes the next draw
    fill twice as fast. Bow: RMB while drawing lets the draw go and parries.
  - **Built 2026-10-31** (PROGRESS step 27), the string and the guard, with Luke's three calls that day: **the
    riposte is the string's first step with bonus damage** (`regents.riposte_damage_pct`, no clip of its
    own); **the parry is front-only like the block** (one arc, `regents.guard_arc_deg`); **every player has
    the weak block until roles come** (step 4). The staff's riposte waits.
  - **Feel first, numbers after** (Luke, 2026-10-31, after playing steps 1-2: "we can adjust values after
    stagger has visual clarity and animations feel better"). His calls for the first feel pass: a HIT-STOP
    and a SPARK where the blow lands; no screen shake, no finisher shove, no sound yet; the foundation's part
    in the template, then pulled (1.6.7, #301). Built: PROGRESS step 28.
  - **Roles, settled before building them** (Luke, 2026-11-01, answering `docs/regents_rule/ROLES_PREP.md`):
    - **SHOW, DON'T NAME.** "Let's avoid naming conventions specifically, same with the tutorial: we can show
      the player without telling them behind the scenes or using explicit gamer titles." The roles (Damage,
      Tank, Support) and the "finisher" are words for code and docs only: the player sees a badge and what a
      handle DOES ("holds a full guard; foes come for you"), and the last hit of the string has no name on
      screen (each weapon's own last hit is named in its tooltip: "Piercing thrust").
    - **A handle pattern per role** (the sword: grip, crossguard hilt, banner hilt), each crossed with the woods,
      a real item; the **same cost and Crafting rank** as the plain handle; **one mesh** per weapon for now.
    - **Each role carries its block and threat only**; passives come later. **Healing draws no more threat
      than damage.** Whether the guard handle's extra threat applies to every foe or only bosses is to be TESTED:
      its multiplier and its scope are live rules.
    - **Support works solo**: its heals reach you; with players near, your own share goes down (the ratio after
      playing it solo and grouped: a live rule).
    - **The sword's three last hits to start**: Piercing thrust (26, reach 2.4 m, 380 ms), Pommel bash (14, a
      1.2 s stagger that holds the foe, 340 ms), Rallying cut (14, a wider arc, heals players near you, 400 ms).
    - **Drops** roll a handle shape: 50 % plain, 25 / 25 (a live rule). **Re-hilting** loses the old handle.
    - **The tutorial**: in the camp's yard, offered (a reminder after the first death), replayable; taught
      mostly by playing, with a few words and the first friendly NPC (a camp character); a closing ring as a
      parry aid in the yard only. **Roles first**, then the tutorial. (Mastery pick pools, D7, wait.)
    - **Built for the sword 2026-11-01** (PROGRESS step 30): the crossguard and banner hilts (each wood), the role
      map and its three last hits, the server choosing which fires (template 1.7.1), re-hilting, drops, badges
      and words. The starting values and choices that were not his (the live rules' first numbers, the rallying
      cut not healing off a dummy, the badges, the words) are listed in PROGRESS step 30 for his look.
  - **Roles by the handle's SHAPE** (Damage / Tank / Support; Option B, not an off-hand slot); its MATERIAL
    still sets the trait (#22 intact). **The role changes only the finisher.** Changing role = re-hilting at
    the workbench. The sword's three roles first.
  - **Mastery picks at 3/6/9** (tall or wide: the next active, an upgrade, or a passive), changeable out of
    combat.
  - **Telegraphs: the pose plus one red glint**, for unblockable attacks only. **Ranged keeps its hit roll.**
  - Still his: the 12 role finishers and the pick pools, the bow's Q, a respec's cost, the combat triangle as
    foe design.
- **Luke's first look at roles** (2026-11-01, built: PROGRESS 31): the sparks and glint were untextured squares; the
  swing snapped back to idle; a status bar under the target's health; a stagger that roots and dazes ("we can
  experiment with both": the Staggered status's `speed`, 0 now, 0.4 before); the workbench's doubled Handles heading.
  Then: the tutorial, "a walk through with crafting + combat to teach the basics".
  And (2026-11-02): no "Staggered" word floating over the body: the status bar under its health says it, and how long.
  **Stagger by POISE** (Luke, 2026-11-02, choosing option A with a short B, after "the guard grip plus Heavy staggers
  almost forever"): every melee hit wears a foe's poise, only the last hit breaks it, then a stagger and a short
  Steadied; Heavy breaks it sooner instead of staggering longer. **Shown on the target marker**, not a bar under the
  health ("the top status is getting clutter"): an arc round the ring under your target. Players keep the old rule
  (a foe's last hit staggers you). The banner cut's clip changed (it looked jumpy).
  **A FOE'S STRING FOLLOWS ITS TARGET** (Luke, 2026-11-11, playing the wolf: "the wolves start their attack and dont
  stop even if I move far away from the first one (so second and 3rd attack just hit air instead of gap closing and
  then performing the 2nd and 3rd hits) and I suspect skeletons do that too"): every foe runs down a target that
  steps out of reach between two swings and goes on with its string; out of reach too long (`FoeDef.string_chase_ms`,
  1500, Claude's number) it drops the string and starts over. Built as PROGRESS 57.
  **EVERY FOE TURNS ON WHO HIT IT FROM BEYOND ITS SIGHT** (Luke, 2026-11-11, asked every foe or pack foes only: "Every
  foe"): a fighting foe hit while it does nothing else is Startled (as the deer is, which bolts) and goes for the
  nearest player, if they are within its leash of its home; a pack foe's packmates come too. Built with the wolf
  (PROGRESS 56), kept for skeletons and all to come.
- **Handles: one family of three SHAPES for every tool and weapon** (Luke, 2026-11-01, option (b) of three; built,
  PROGRESS 32): the grip (the plain handle, renamed), the crossguard grip and the banner grip, each in every wood; any
  tool or weapon takes any shape; a shape matters only when swung, and only on a weapon whose kit has roles (the
  sword so far). Tools as weak weapons with kits of their own (option (c)) are later.
- **The tutorial** (Luke, 2026-11-01, answering two questions): it walks a new player through MAKING THEIR OWN SWORD
  first (chop a tree and carve a grip; mine copper, smelt a bar, smith a blade; assemble a copper sword at the
  workbench, picking its grip's shape), then the fighting lessons with that sword, ending on what its grip's shape
  does. PROGRESS IS ON THE SERVER, per character, each lesson ticked by the server seeing it done. With T1-T5 (the
  camp's yard, offered, mostly play, a few words, a friendly camp character, the parry ring in the yard only).
  First pass built (PROGRESS 33): the Drillmaster by the yard, fifteen lessons, a sparring skeleton, the ring.
- **Leaving a round** (Luke's play, 2026-11-03, feedback #8193: "need to be able to cancel out of anvil minigame if you
  accidentally started one, maybe for all games, for harvesting can reward what we get, for refining/crafting can just
  cancel and not use resources"): built (PROGRESS 35): **Escape** ends a gathering round at once and pays what was
  played; a refining or crafting round is dropped, nothing used, nothing made.
- **Armor prep** (2026-11-03): `docs/regents_rule/ARMOR_PREP.md`, decisions A1-A10, waiting on his answers.
  His first pass (2026-11-04, an outside review of the sheet): AGAINST player poise (hard to track, feels bad when it
  breaks: poise stays a foe mechanic) and AGAINST weight slowing movement (good players avoid damage and go light).
  The sheet is revised with both (revision 2, every decision with a proposed answer); a second outside review found
  the metal-only traits dead and too few parts for the grades.
- **ARMOR PARKED** (Luke, 2026-11-04) until cloth, hides and new foes exist (the order of work above). **Settled now**,
  because no new content changes them (`ARMOR_PREP.md` §0):
  - **Defense**: each piece a Defense, worn pieces add up, a hit becomes `damage x K / (K + Defense)`, K the hot rule
    `regents.defense_k` (67 to start); never a flat cut. The guard first, then armor, then traits, MULTIPLIED, never
    added. `FoeDef.defense` (0 on today's skeletons). Quality raises Defense as it raises damage (+20 % at 1000).
  - **No armor weight and no player poise**: armor never costs the roll or sprint; POISE IS A FOE MECHANIC ONLY; a
    foe's last hit that lands unblocked always staggers a player. (A short Steadied after a player's stagger is an
    idea for duels, not decided.)
  - **Wearing**: from the bag (I), a paper doll of head, chest, legs and trinket; out of combat only
    (`regen_delay_s`); others see it (a public row, by the ring).
  - **The look**: the Quaternius Modular Fantasy outfits, recolored by material; helms always shown (a toggle later);
    the chestpiece draws the arms, the leggings the feet; the five slots stay.
  - **Words**: a piece shows its Defense as a number (as Power is) and what wearing it does to you ("you'd take 19 %
    less, now 13 %"); the doll shows the total; never Light / Medium / Heavy.
  - Later, as recommended: the trinket empty until herbalism; armor crafted first, on drops with the loot-table pass;
    gear XP by being hit when ranks are built.
  - **Open, for when armor comes back**: the parts and traits (plates + what secondary parts; each piece needs enough
    trait-bearing parts for Fine and Masterwork), which traits (Padded and Warded likely move to the lining), what
    makes lighter armor worth wearing (the combat triangle), the materials' tiers and the numbers.
- **THE WARDROBE: WHO WEARS WHAT** (Luke, 2026-11-14, after the wardrobe lab, `docs/regents_rule/WARDROBE.md`, PROGRESS
  81): "all players start as peasant outfit but can pick the color they want (plus hair style and any other things)
  then leather is ranger, cloth is wizard, noble is not usable (so we can use it on higher npcs and things) and metal
  is metal." So: EVERY PLAYER STARTS IN THE PEASANT CLOTHES, colors of their own choosing, with hair and the rest;
  LEATHER armor is the RANGER outfit, CLOTH the WIZARD, METAL the KNIGHT; the NOBLE is NOT for players (higher NPCs).
  Tiers look like: "green base is not good, I think brown leather to start and then can scale with different
  animals. Cloth feels like it needs more neutral too": LEATHER STARTS BROWN and changes with its animal (deer, wolf,
  stag); CLOTH stays NEUTRAL. The tier palettes proposed for his look: `wardrobe/palettes/leather_*`, `cloth_*`,
  `starter_*` (the lab's Tiers view), ACCEPTED with W1-W8 below.
  - **W1-W8 ANSWERED** (Luke, 2026-11-14: "Yes, all stand", to WARDROBE.md §7 as proposed, and the tier colors):
    - W1 THE PIECES: metal = the armet; plate torso + plate arms + round pauldrons + the scarf as the CHEST; plate legs
      + feet. Leather = the Ranger's hood (dyed as leather); jerkin + bracers + its pauldron; trousers + boots. Cloth
      = no headwear yet (hair shows); robe + sleeves; trousers + shoes. The Knight's tabard torso is for NPCs, with the
      Noble.
    - W2 COLORS: the starting clothes the player's, freely; ARMOR shows its TIER'S palette (leather by animal, cloth by
      fiber, metal by bar), so a tier reads at a glance; LATER, herbalism DYES recolor armor's cloth and leather slots,
      NEVER its metal. Dyes are not in the armor step.
    - W3 TIERS BEYOND COLOR: the finish and the fittings (buckles and clasps in the tier's metal), plus ONE shape
      step: steel wears the SPIKED pauldrons. The horned helm is kept for a later tier or a rare. Trim glow from tier 4.
    - W4 AN EMPTY SLOT shows the player's own starting Peasant pieces, in their colors.
    - W5 THE GAPS: leather's head is the dyed hood; cloth's head shows hair until a HAT exists (one rigid mesh on the
      head bone; its source, by hand, CC0 or commissioned, still his).
    - W6 GRADE AND QUALITY on the look: not now.
    - W7 THE FOUR METAL STUDIES (blued, gilded, blackened, pale): candidates, chosen when tiers 4-6 are named.
    - W8 THE PICKER: WITH THE ARMOR WORK, colors for the starting clothes, one per slot (main, accent, under, trim,
      leather) on the `appearance` text (add-only), a free picker with a row of suggested swatches.
- **Minigame prep** (2026-11-04; revision 2 2026-11-05 after an outside review): `docs/regents_rule/MINIGAMES_PREP.md`,
  decisions M1-M12 (the ladder's shape, the bands, rank easing a round, what a score is worth, woodworking's minigame,
  smelting's reward and bellows, the look, art sources, each band's new thing, the new skills' minigames, what active
  gathering pays and how often its panel opens, an assembled item's quality).
- **Herbalism and hunting prep** (2026-11-07): `docs/regents_rule/HERBALISM_HUNTING_PREP.md`, decisions H1-H11.
- **Herbalism and hunting, ANSWERED** (Luke, 2026-11-07, going through them one by one; the sheet's §7 is the order):
  - **A SKINNING skill** (H1; revises 2026-10-23's "No Hunting skill", which stays true of the chase: the hunt is the
    fight): a kill leaves a CARCASS you skin, tap E AFK or hold E for its round; Skinning rank gates the better hides.
  - **Herbalism's tool is a TROWEL** (H2): asked about a sickle, Luke: "Im not sure I like a sickle since we are pulling
    the plants, either the minigame should change to use the tool or we come up with a different requirment like
    gloves or gardening trowel/weeder/cultivator/Extractigator/Uprooter"; of a trowel, a forked root-puller or leather
    gloves he chose the trowel: smithed (copper, iron, steel: the material table), its tier gating the plants; the
    round shows it loosening the soil before the pull.
  - **Pull the root as proposed** (H3): hold to pull, strain rises and eases when let go, the plant trembles before a
    jump, past the top it snaps; band 2 roots that branch, band 3 a wilting clock.
  - **A ROUND IS A CLUMP** (Luke, 2026-11-08, asked one plant a round or a clump: "A: a clump"): stems pulled one after
    another until the time runs out; a snap loses the rest of that stem, not the round (as chop and crack count
    pieces). Everything else in the round is Claude's, built after his first play the same night and left for him to
    change (PROGRESS 51: the trowel digging round each stem and cutting the side roots where the soil cracks, the
    stage redrawn, the numbers).
  - **SKINNING'S TOOL IS A SMITHED KNIFE** (Luke, 2026-11-09, as proposed): a skinning knife of the material table, as
    the trowel (a blade at the anvil, copper, iron, steel, and a grip at the workbench); its tier gates the better
    hides; new characters start with a copper one. **WHO SKINS: the killer first, then anyone** (as proposed): the
    player who did the most damage has the carcass to themselves a while (60 s), then anyone may; it rots away after
    3 minutes unskinned.
  - **Skinning's round: DRAG the knife along the cut line** (H4): a new continuous model (off the line tears the hide).
  - **A DEER HOLDS SEVERAL HIDES** (Luke, 2026-11-10, asked what a better cut should get when a carcass held one hide:
    "Skinning a whole deer would get you multiple hides so we can have it be like a node depletion and good rounds
    reward more up to a cap of course"): a carcass gives hides as a node gives logs (each the last with a chance) up
    to a CAP; a played round skins the whole carcass and pays more the better it is cut, never past the cap. (Not hide
    grades.) Built as PROGRESS 55; the numbers are Claude's.
  - **The deer is SMOOTH SHADED** (Luke, 2026-11-10: "id prefer it to be smooth shading instead of low poly").
  - **Tanning and spinning keep no round for now; the WOLF is next** (Luke, 2026-11-10, after skinning's round: of
    spinning's round, both, or neither, "Neither yet, wolf next"). The leather wrap and a cloth plant wait on his
    traits ("I havent decided on cloth (new plant for herbalism) or leather traits").
  - **The first creatures: deer (tier 1, flees), wolf (tier 2, packs; a lunge that knocks back, a bite that slows),
    stag (tier 3, flees, charges when cornered)** (H5), from Quaternius's animal pack. Poison waits for an asset.
  - **Tanning and spinning are AFK crafting stations** (H6): a tanning rack and a spinning wheel, trained by Crafting;
    their own skills and rounds later if they earn them.
  - **Names** (H7): fibers Flax, Hemp, Nettle; hides Deer hide, Wolf pelt, Stag hide; leathers Soft, Supple, Hardened.
  - **First products** (H8): the bowstring and STRINGING the carved unstrung yew bow; a fiber wrap and a leather wrap
    as bindings with traits (designed with Luke; each trades).
  - **A FIRST TRINKET NOW** (H9, not the proposal): a creature-trophy charm (a fang, an antler) with a trait, designed
    with Luke when its creature is built.
  - **Rares** (H10): a seed pod from plants, a fang from wolves, an antler from stags.
  - **No meat yet** (H11): it comes with cooking.
- **The minigame overhaul, ANSWERED** (Luke, 2026-11-05: "all as proposed except for below"; the sheet's §7 says each
  in full, §8 is the order of work):
  - **One game per skill for life** (M1): numbers tighten within a band; each new band adds ONE new thing on top.
  - **Bands** (M2): band 1 = tiers 1-2 (copper, iron; tree, oak), band 2 = tier 3 and up (steel, coal, yew). Where
    band 2 ends and band 3 starts **waits on which metals come after steel** (Luke's, with the next metals).
  - **Rank eases the round** (M3): a few percent wider windows a rank above the requirement, capped at three (hot rules).
  - **Quality = the score** (M4), the difficulty tuned to target shares: a fresh band Fine ~50 %, Masterwork ~10 %;
    three ranks on, Masterwork ~33 %. Measured by simulated players (the readout), AFK always Common.
  - **Woodworking gets carve to the line** (M5): grips, hilts, bows and staves get a quality. Assembly stays a choice
    screen.
  - **Smelting** (M6): bars stay without quality; the score pays in bars and catalysts; the bellows pump in RHYTHM,
    never mashing.
  - **The look** (M7): a 3D stage in the panel (`SubViewport`, the game's own Quaternius models, lit like the world),
    sound from the start; smithing first. **Gathering ALSO as a 3D stage, in the smaller side panel, as a TEST**
    (Luke: "lets do gathering as 3d too with smaller side panel as a test"). **After the test (2026-11-06): every
    round in the MIDDLE panel** (the side panel sat over the minimap), and **NO CHARACTER ON A STAGE: the tool floats
    and swings on its own**, as the anvil's hammer (Luke: "does it feel weird to have a character on a small panel
    while you see your main character ... consistent with hammer floating, pick floating, axe floating, etc since we
    know we as the character as doing the action").
  - **THE WORK SPOT** (Luke, 2026-11-06, PROGRESS 44): the world's pick and axe went into big rocks and trees; of a
    picture-only stand-off and moving the player, Luke chose **"Move the player"**: pressing E at a node first walks
    the player back (or in) to where the swing meets the rock or the bark, facing it, then the work starts there.
    "Visuals and server body should match in case they get attacked or shot at while harvesting ... smooth and not
    jarring ... facing them": an eased turn to the node, then a walk (not a run). Then (same day): "have the model
    face them but allow the camera to rotate as it is since we are standing still": the BODY turns, the camera stays
    the player's (the template's `hold_body_yaw`, 1.7.4, DECISIONS #305). And "dont want to wait more than a few
    moments (.5 maybe less?)": the step goes at the plain gait (a run), about half a second.
  - **THE WORK REACH IS FROM A NODE'S EDGE** (Luke, 2026-11-06: "Measure from its edge"): `regents.work_reach_m` (3 m)
    is counted from where a body walking up is stopped, not from the node's middle: a rock's drawn footprint, a tree's
    trunk (`NodeDef.radii_cm`, baked from the models). The big iron rock (2.57 m) fits its work spot now.
  - **Art** (M8): the game's own models plus CC0 (Kenney, freesound); Gemini for mockups only. (Paid packs and AI art
    not chosen.)
  - **NO AI DISCLOSURE** (Luke, 2026-11-14, after the audit `docs/regents_rule/AI_ASSET_AUDIT.md`): look first to make
    a thing procedurally, in code (draw calls, shaders, noise, synthesis, renders of the game's own models), and never
    add anything that would need Steam's AI disclosure: no image, model, texture, sound, music, voice or text from a
    generative model, nor anything traced or derived from one, in the build or on the store page. Otherwise
    human-made (CC0 or licensed, its source noted). The continent map is the one known exception, to be replaced.
  - **Each band's new thing** (M9): smithing first: two strikes in band 1 (the buttons a UI setting, tried both ways),
    heat colors with hard and soft spots in band 2, a quench in band 3 that lifts or lowers but never destroys a part;
    the others' band things are prototyped and played before deciding.
  - **New skills** (M10): pull the root (herbalism), the cut line (skinning) and the rest as the sheet's §2 table,
    each confirmed with its step.
  - **Active pay** (M11, revisiting 2026-10-18's 1.25x): a good round beats AFK and a poor one still falls short
    (break-even near half a score, not 80 %: a floor); the catalysts lean hard to active play; gathering and smelting
    rounds run back to back hands free once started (E or Escape ends a run, as does a round with no input), each
    round paid as it ends. The numbers come from the readout and his play.
  - **SMELTING IS A RHYTHM GAME** (Luke, 2026-11-07: "smelting needs to be changed to a rhythm game"; of a full
    rhythm track or beat-timed bellows on today's band he chose **"Full rhythm track"**; PROGRESS 45): the bellows
    breathe on a beat you hear (a count-in, then the track); notes come along a track to the bellows and you press on
    each, holding the long draws to their end; nearer the beat pays more, a press on no note is wasted breath and
    costs (mashing scores nothing). The track is drawn from the round's seed (no two alike). **The pour stays** (hold,
    let go at the mold's line). Each metal a quicker beat, more off-beats, a tighter window. Taken as defaults, his to
    change: our own synthesized beat sounds (no music track), the pour kept, the back-to-back runs still M11's step.
    Bars still have no quality (M6).
  - **WOODWORKING STARTS WITH THE BOW AND THE STAFF** (Luke, 2026-11-07): asked whether a graded grip stops stacking, he
    said "Yes, stop stacking"; then, told that a grip's grade does nothing yet (an assembled item takes its quality from
    the head alone, M12, and a grip's grade only starts its trait higher once trait ranks are built, `MATERIALS.md` §10
    step 5), he chose **"Bow and staff first"**: the carve round goes on the yew bow and the yew staff (their grade sets
    their Power now); GRIPS KEEP STACKING, with no round, until trait ranks give their grade a job (then they stop
    stacking, as he said). Then: "I think I want to have woodcarve/woodworking be vertical and have wood you can take of
    from either side (to allow asymmetry for bows/staffs) instead of just being a duplicate of smithing": **the carve is
    its own game**, a vertical stave with a left and a right profile (PROGRESS 49). On the shots: "make it a unstrung bow
    shape and backwards (curve going right or left) with variation for difficulty" (stringing it later, with
    herbalism): the bow is carved as an UNSTRUNG C, bending left or right by the round's seed.
  - **Woodcutting's difficulty stays** (Luke, 2026-11-07, after playing it: "the woodcutting minigame is pretty hard but
    im not saying thats a bad thing. . takes skill and precision"): not to be eased without his say.
  - **An assembled item's quality** (M12): the CORE part alone sets it; a secondary part's grade starts its trait a
    rank higher (this settles the "a better-made part starts higher" half of trait ranks, `MATERIALS.md` §5).
  - **The anvil, after playing step 2** (Luke, 2026-11-05: "the time between hitting reheat and then being able to use
    the hammer again was too long, could only ever get two reheats"): **a set number of heats instead of a clock**,
    and **each reheat lowers the part's quality ceiling**; the outline **varies every round** (still the part's
    shape, different each time, so no one memorizes the hits); the outline can be **re-laid on the bar as a template,
    but no strikes while it is up**.
  - **The anvil's bands, A TEST** (Luke, 2026-11-05: "so I can test both, lets make copper band 1, iron band 2, steel
    band 3 and we can redistribute the bands per metal as we introduce more"): **band 1 (copper)** the outline shows
    only when laid on (a key or a button), no strikes while it is up, each reheat lowers the quality ceiling; **band 2
    (iron)** the metal is harder (more hits), and each lay of the template AND each reheat lowers the ceiling; **band
    3 (steel)** as band 2, plus heat colors and the quench. Revisit once played.
  - **For every skill** (Luke, 2026-11-05, "yes"): **rank eases the numbers; a band adds one rule.** A band's rule
    belongs to that band's items, never to the player's rank: an outranked tier never gains rules.
  - **LUKE'S PLAY OF EVERY MINIGAME** (2026-11-09, PROGRESS 52): mining and woodcutting good through tier 3; smelting
    good, with a slower start to read the directions (the count-in 8 beats, the directions shown through it); **every
    round shows how many rounds and the pay so far**, as woodcutting's logs did. **THE PATTERN FADES BY BAND** (his
    words: "ghost for copper 3 second but stays faint, iron 1.5 even fainter, steel 3 seconds and disappears ... same
    with woodcarving"): copper 3 s to a faint ghost that stays, iron 1.5 s to a fainter one, steel 3 s to nothing; the
    yew carve as copper. **THE QUENCH IS OUT FOR NOW** ("maybe we get rid of quenching for now or redesign it so it
    makes more sense as a skill thing and described better in instructions"): to come back redesigned, his call.
    **PULL THE ROOT: "Cutaway, no chore"**: some sides of a stem start loose (dig only the packed ones), a cut-away of
    the soil shows the root and its side roots coming. Not his pick, taken as a default to change: setting a part down
    is a HOLD of Enter (one Enter had ended rounds at once), flax four stems a round, the strain shown as a bar.
  - **AFTER PLAYING STEP 52** (Luke, 2026-11-09): pull the root is "still the one that feels the worst fun wise. I cant
    put my finger on it so lets leave it for now and move on" (parked, his to reopen). Steel's red heat "cracks with no
    indicator, not sure on that change"; "we might need to rethink quenching and bands for [smithing] / carving but can
    do those later"; smithing and woodcarving "need some rules tweaks like timing and such but those can be adjusted
    later". Then: on to hunting.
  - **Outranked XP** (Luke, 2026-11-05, a direction, not settled): rather than XP falling off, shape the rank curve
    so a lower tier is never worth doing for XP (as OSRS's: its XP per level grows so steeply that level 92 is half of
    99). Today's smithing curve (60 ... 2400 over 10 ranks) grows gently; to retune with the ladder.
- **American spelling** (Luke, 2026-11-04): "all spelling in the game is not English version, but American": armor,
  defense, color, gray, center, meter, canceled. Everything a player reads, and every new name, rule and doc from now
  on (`regents.defense_k`). The first sweep was done 2026-11-04 (PROGRESS step 38).
- **THE GLADE'S LOOK, a first pass** (Luke, 2026-11-11, from his comparison with other games on the same kits:
  "Do A to D"): the sun lower and warmer with air in the distance; the nature kit's leaves and grass lit on both
  sides; a darker ground with dirt where the level is used and soil under trees and rocks, painted from the level's
  own markers; grass as MultiMesh clutter (PROGRESS step 59). To change it, in `frontier.tscn`: move a station or a
  trail's curve under `GroundPaint` and press Repaint; the grass is `Clutter`'s `kinds`; the colors are the ground
  material's. HELD, his to say: tree scale, volumetric fog, station lights, the continent's ground; **Sky3D only if
  #12 (day/night) is a yes** (he asked 2026-11-11: it is a day/night sky, not fog; the time would come from the
  server's clock, no table).
- Still open: #12 day/night; how the minimap grows; the ore nuggets' placement (Luke's, by hand).
- **THE LOGIN SCREEN AND THE SHOWCASE** (Luke, 2026-11-15, commissioning music: "a login screen is a classic must
  have ... build a few labs that can really showcase the visuals ... and then a few still or short videos of combat"):
  built in PROGRESS 84. Press Play: the form over the valley at dusk (`RegentsLogin`); the vista and battle labs
  (`game/regents/showcase/`); the composers' pictures and films by `showcase_render.sh` into `export/showcase/`. The
  forest's colors, the moods, the keep and the login's words are the agent's first pass: his to change.

## Current state (2026-10-19, with steps 9-16 since: see `PROGRESS.md`): the skilling chain in the frontier glade
A fork of the template at 0.51.2 with the `regents` genre. **Press Play**: the login screen (the valley at dusk behind the form, PROGRESS 84), then the frontier glade (level 20):
trees (Tree, Oak, Yew), copper, iron and coal rocks, and a camp with a furnace, an anvil, a workbench and an order board.
Gather (woodcutting, mining), smelt, smith and craft your way from a log to an **Iron axe**, then an iron
pickaxe for coal and **steel** (the ladder: copper, iron, steel; `MATERIALS.md`, the material table): at a node or a
station **tap E** to work AFK, **hold E** to play its minigame (branch dodge, crack the rock, pull the root at the flax, the furnace's
rhythm track then the pour, shape to the outline, the carve), **Q** at a station picks the recipe (and the handle: plain, oak or yew). **Escape** during a minigame leaves it (gathering keeps what you got; making uses nothing). The
camp's **order board** wants rotating batches for bonus XP; crafting pays for the work in its inputs, a
first make pays extra, and a recipe repeated too long wears stale. Tune a recipe on the **recipe bench**.
**Combat, the first slice**: wield a weapon from the bag (I), Tab onto one of camp's training dummies (a
ring under it), tap LMB for the string (its last hit the finisher, which staggers), tap RMB to parry a hit
as it lands (then tap LMB at once: the riposte), hold RMB to block what is in front, Ctrl to roll, Q for the
kit's first skill; the world's referee judges every swing (an editor run starts it). **The ability bar** (PROGRESS 72)
sits low in the middle: health above, the weapon's three slots (Q E R) in a ring filling toward the next unlock, the
chest's (F), the roll and the potion key (G); it fades out of stance, lights in it, glows red in a fight; hover (with
the cursor free) for what each does; Settings, Game, "Ability bar" picks round or square, and
`game/regents/ui/bar_lab.tscn` (F6) shows both. **The VFX lab** (PROGRESS 78): `game/regents/vfx/vfx_lab.tscn` (F6)
plays the spells' and blows' effects on a stage as they would happen in a fight (Fireball, Frost Ring, Blink, Gale, the
axe's heavy hit and the sword's string, each cut drawn along the real blade, and both beside today's swing trail, a
parry, the imp's cinder ring), down to a
tenth of the speed, by day, dusk or night; all made in code (no images). **They are in the fights** (PROGRESS 82): every swing leaves the crescent, Fireball and the Bolt fly and burst as in the lab, the rings are the lab's, a cast shows its charge in the hands, Blink its columns, Gale its gust (everyone near sees it, and the caster's arms push it: Luke, 2026-11-15, "yes, add it", "yes, add the pose"; PROGRESS 83), a parry its flash; which effect an ability shows is `game/regents/vfx/ability_vfx.tres`. **Weapons level** (PROGRESS 74): a weapon levels as you fight with it (five
times as fast while below your mastery), counts only up to your mastery, and opens its slots by its level: a staff
has Fireball (Q) and Blink (F) at once, and at level 5 a pick of Frost Ring or Gale for E, chosen in the bag (I). A pick
is CHANGED in the bag too (PROGRESS 75): free once a week from the weapon's level 20, anywhere; otherwise at a workbench
for the weapon's head's material (2, doubling with each paid change, a doubling forgiven each week without one). A sword's HANDLE picks its
last hit (a plain grip a piercing thrust, a crossguard hilt a pommel bash and a full guard, a banner hilt a
rallying cut that mends those near you): make or re-hilt one at the workbench. **The tutorial**: the Drillmaster by the training yard
(walk up, E, E again) walks you through making your own copper sword, then fighting with it against a slow sparring
skeleton (a ring closes on each of its blows); N sets it aside. Each lesson ticks when the server sees it done. The server replays every round from its
inputs; mastery ranks 1-33 per skill (PROGRESS 73: the old 1-10 spread a third of the way to 99) gate the better nodes. How to play it, what makes it, how it is
tested and what is left: **`docs/regents_rule/PROGRESS.md`**. Every minigame alone:
`game/regents/skilling/skilling_lab.tscn` (F6); **T** there shows the round's **difficulty readout** (four simulated
players of set skill on many seeds: their mean, Fine and Masterwork shares, how often they beat AFK), and
`tools\run.cmd game\regents\tests\minigame_readout.sh` prints it for every round (`MINIGAMES_PREP.md` §6).
**The anvil** (PROGRESS 41-42) is a 3D stage of the game's own anvil and hammer: left click a column for a heavy
strike (it spreads into its neighbors), right click for a light tap (finishing the line), R to put the bar back in the
fire; or Shift + click taps and right click reheats (Controls, "Smithing: the light tap"; **B** in the lab switches
it). No clock: **5 heats**, each costing the best the part can be; **the pattern** (the outline) is on the bar at the
start and when laid on with **Space** (no strikes while it is on); the outline varies every round; **Enter** sets the
part down. Iron charges for each look; steel goes **red** (a strike cracks it) and ends in a **quench** (Enter while
the heat bar is in the gold mark). **Every minigame is a 3D stage** (PROGRESS 43), in the panel in the middle, with no
character: the axe chops into the trunk's side, the pick hovers by the mouse and comes down on the seam, the bellows
pump on their own. **The furnace is a rhythm track** (PROGRESS 45): after a count-in, press Space or click as each
ember reaches the bellows' mark at the left, hold the long ones to their end (a press on no note wastes breath and
costs); then hold to pour and let go at the mold's line. **Rounds run back to back** (PROGRESS 46, M11): once a round
at a tree, a rock or the furnace starts, the next comes by itself into the same panel; **E** stops after the round on
now, **Escape** at once, and a round left untouched ends the run. A played round pays from 0.75 of AFK (nothing played)
to 1.25 (a full score), so half a score is AFK's; rare finds up to 3x at a full score. **Rank eases a round**
(PROGRESS 47, M3): each mastery rank above what a node or recipe needs makes its windows 4 % wider, three ranks at most.
**Band 2's rules, a test** (PROGRESS 48): the yew has KNOTS (a dark burl: two quick chops from one side), the coal rock
BRITTLE NOTCHES (pale: wait for the rock to stop ringing), the steel bar SLAG (gray squares: skim with F or right click).
**Carving** (PROGRESS 49): the yew bow and the yew staff are carved at the workbench (hold E): a stave stands upright;
look at the pattern (both sides' lines), lift it, then click a row left or right of its middle to cut that side, left
click deep and right click a fine shave; Enter when done. The bow's or staff's grade comes from it.
**Hunting and skinning** (PROGRESS 53-56): deer graze west of the flax and over the continent's meadows; they bolt
(a bow, or corner one). **Wolves** prowl in packs of 2 in the glade (northwest of camp) and 2-3 along the continent's
forest edges; alerting or hitting one calls its packmates within 15 m (sharing the referee's attack tokens while the
others circle), and their 3-step string ends in a hamstring bite (3 s slow) and an unblockable lunge (leaps forward and
knocks back). A slain deer or wolf leaves its CARCASS (yours first for a minute). Tap E with a knife (new characters
have a copper one) to skin it AFK, a hide every 5 s or a pelt every 6 s until it gives out (up to 4; the wolf needs Skinning 2
and has a 0.8 % rare **Wolf fang**); hold E for **the cut line**: press the
mouse on the gold ring and drag the knife along the marked line (off it, or too fast, tears the hide); the round skins
the whole carcass, 2 to 3 hides or pelts for a clean one. The tanning rack (by the spinning wheel) turns a deer hide
into soft leather and a wolf pelt into supple leather (Crafting 2).
**Labs with no server** (F6 on each; nothing in them is in the game's levels yet): **the wardrobe**
(PROGRESS 81) `game/regents/wardrobe/wardrobe_lab.tscn`, every outfit dyed any color, the metal tiers;
**the towns** (PROGRESS 85) `game/regents/town/town_world.tscn`, a kilometer with a village, a walled market town and a
castle, every building the Medieval Village kit's pieces in the town dye (L day/dusk/night, S the next style), and
`game/regents/town/town_lab.tscn`, one street in eight styles, live-edited; **the showcase** (PROGRESS 84)
`game/regents/showcase/vista_lab.tscn` and `battle_lab.tscn`.

```bash
GODOT=<path> ./game/regents/tests/skilling_playtest.sh   # the whole chain by a real client at 150 ms
```

**300 bots on a Skyrim-size world, and you among them** (PROGRESS step 25, the test database only):
`tools\run.cmd game\regents\tests\expanse_watch.sh` (a game window opens: press Play as a guest at the camp;
Ctrl+C in the terminal ends it); how many referees it needs: `tools\run.cmd game\regents\tests\expanse_referees.sh`.
