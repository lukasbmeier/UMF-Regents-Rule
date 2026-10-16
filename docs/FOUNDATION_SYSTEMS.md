# Foundation systems for the next games (Fowl Play first)

Fowl Play's open items (§D) list the systems every later game needs too (survival, disc golf), so
they are built HERE, in the template, and pulled by each game. This is the plan: the order, the data
each system adds, and how each stays compatible and tunable. Each milestone ships as its own
release with its own tests, so it can be played and judged before the next is built on it.

## The rules every system follows
1. **No table changes shape** (docs/rules/compatibility.md). New state goes in NEW side tables keyed
   by `entity_id` (or its own id), never as new columns on `health_state`, `session_member` or
   `movement_state`. The handoff's plan added columns to `health_state`; that would strand every
   friend's build, so statuses get their own table.
2. **Numbers are hot rules or content from the first commit.** Durations, speeds, radii and costs
   are `RuleEntry`s (tuned live) or fields of content (`*Def`, benched). Only what a client predicts
   exactly (the movement model's own numbers) is baked and goes through the goldens.
3. **The foundation defines the mechanism; a genre fills in the meaning.** Statuses, interaction
   verbs, noise kinds, ping kinds are numbers the foundation stores and moves around; what they MEAN
   (a stashed chicken, a nest's progress) is the genre's, through hooks. Foundation numbers are
   0-99, a genre's 100+ (as entity kinds and challenge kinds already are).
4. **Authority stays where it is.** Outcomes are decided by the module or the sidecar, never by a
   client (hard rule 13). The client predicts the start of things and is corrected.
5. **Every system has a workbench or a test scene a designer can open**, and a two-client or bot
   test that proves it end to end, with a negative.

## The milestones, in order
Order follows Fowl Play's first playable (GAME2_FOWL_PLAY §6): a chase first, then what a chase
needs, then the objective loop, then the match around it.

| # | System | Adds | Proves it |
|---|---|---|---|
| 1 ✔ 0.33.0 | **Movement profiles per character** (A3) | `MovementProfileDef` content: a character's overrides of the default movement (speeds, accel, flaps, glide); `EntityDefinition.movement_profile`; prediction and the sidecar use the entity's profile; the module's speed envelope per kind | two characters in one world move at their own speeds, predicted without corrections; Tier A refuses a claim beyond the kind's speed |
| 2 ✔ 0.34.0 | **Statuses and their timers** (§3.4) + spectate | side table `status_state {entity_id, world_id, status, since, until, by_entity, data}`; foundation statuses (0 normal, 1 injured, 2 downed, 3 carried, 4 out, 5 hidden, 6 escaped), a genre's 100+; `set_status` for authorities; a timer that moves a status on when `until` passes (a genre hook decides to what); movement MODIFIERS from status (a profile says each status's speed factor, whether it can jump); `SPECTATE` when out | a player injured runs faster for 1.5 s then normal; downed crawls; out spectates a teammate; all predicted |
| 3 ✔ 0.36.0 | **Hold to interact** (§3.5) | table `interaction {id, world_id, actor_id, target_id, verb, started_at, progress}`; `begin_interact` / `end_interact`; a 10 Hz tick (range, status interrupts) and genre hooks for the RATE (by participants) and COMPLETION; the prompt shows progress | three bots lay a nest in ~6 s, one in ~58 s (genre data); a hit interrupts |
| 4 ✔ 0.37.0 | **Server-timed skill checks** (A4, also fixes fishing's timing bar) | challenge kind 0 becomes a press judged by the server's clock (issued_at, measured RTT credit), the client sends only the press | a press with simulated 150 ms latency is judged as the player saw it; a client-reported result is impossible |
| 5 ✔ 0.40.0 | **Abilities on the sidecar, lag-compensated** (A1) | `use_ability` -> `action_request` for SIDECAR worlds; sidecar resolution with a 300 ms ring of transforms, rewound by the attacker's RTT, capped by a hot rule (150 ms, favour attacker) | a pounce issued at t-100 ms hits a chicken that entered a gap at t; one at t+50 ms misses |
| 6 ✔ 0.41.0 | **Attach and carry** (C1) | table `attachment {entity_id, carrier_id, socket, since}`; CARRIED movement mode (the carried entity renders from its carrier); the character bench fits the socket | a carried entity rides its carrier on every client, late joiners included |
| 7 ✔ 0.43.0 | **Bots in the lobby** (B3) | a bot is an entity with an `npc_brain` row and a `session_member` row (no new column: membership + brain says bot); fill empty slots on ready (hot rule) | a 1v4 match with 3 bots runs headless to results |
| 8 | **A world per match** (B1) | table `world_state {world_id, state (pending, live, closing)}`; `destroy_world` (cascades); the sidecar hosts several worlds | lobby start makes a world the sidecar loads; results destroy it; the next match reuses the process |
| 9 | **Noise and pings** (C2) | tables `noise {id, world_id, pos, radius, kind, until, source_team}`, `ping {id, world_id, entity_id, kind, pos, until}`; the client turns them into sound and markers (`FeedbackSet` later) | a crack is heard across the farm; a ping shows to its team only |
| 10 | **Team-aware collision** (A6) | collision layers from `session_member.team` on client and sidecar; a hot rule for friendly collision | teammates pass through each other when the rule says so |
| 11 | **First-person rig and comfort settings** | the first-person camera rig finished (no body, head bob off by default, FOV setting) | a predator plays in first person with the settings applied |
| 12 | **Recording and replay** (A5) | `SessionRecorder` (inputs sent, rows received, timestamps) and a replay scene | a recorded chase replays with predicted vs authoritative paths |

As built, milestone 2 differs from the line above in two ways: what a status does to movement is on
the STATUS (`StatusDef`: a share of each character's own speed), not per profile, and a genre may
replace one of the foundation's statuses by number. A per-character override (a fox crawls faster
than a hen) would be a new profile field with a default that changes nothing.

As built, milestone 3 keeps two rows rather than one (`hold_progress` per thing held, `hold_member`
per doer), its progress a line (how far along at a time, and how fast) so it is written only when
the rate changes; WHAT a hold is (which press, how long with how many, what stops it, the status it
leaves) is content, `HoldDef`, so the foundation ships one (Help up) and a nest is Fowl Play's data
plus a `hold_rate` hook for its cooling. Bots hold through `begin_interact_as` (the authority's).

As built, milestone 4 is a NEW challenge kind (1, the timed press) beside the timing bar (0), which
old builds may still submit and nothing issues: the challenge table keeps its shape, the sweep and the
presses as judged are a side table (`timed_press`), and each player's quickest round trip is the
server's own private record (`client_rtt`). The sweep's numbers are hot rules frozen on the row when
issued. Fishing's hook-set (a reaction time the client reports, bounded by the server's clock) is the
next to move to it: a Fishing change, with its own compatibility step.

Between milestones 4 and 5, Fowl Play's first loop (the nest) asked for five small pieces (0.39.0-0.39.2,
DECISIONS #217-#220): choosing a character (Play as: `EntityDefinition.playable`, `choose_character`,
`set_character_of`), the skill check's own key (Space: a check comes up while E is held), a genre's own
checks (`issue_timed_press` with one to three presses, unscored; `press_result`; `close_if_expired`;
`challenge::grade`), a genre moving a hold along (`nudge_hold`), and a genre's word on the hold prompt.

As built, milestone 5 is a REFEREE: the sidecar judges abilities whether or not it moves the world
(DECISIONS #226). In a MODULE world (players move themselves, as Fowl Play's farm does) it is started
with `--referee`, builds no entities and reads the rows; in a SIDECAR world the same process does both.
What is judged is content (`AbilityDef.judged`: reach, radius, height), carried to the referee in its
`ability_def` row. The client sends its view delay (`use_ability_seen`), the module caps it, and the
referee rewinds everyone but the user by it. An editor run starts the referee itself (`RefereeLauncher`,
a one-time code). Driving NPCs from the referee while players move themselves is milestone 7's.

As built, milestone 6 has no new movement mode: the module keeps a carried entity's row at its
carrier (its own frames consumed), and `CarryComponent` draws it at the carrier's carry point
(`EntityDefinition.carry_offset`) every frame after movement (DECISIONS #228). The carry point is a
field on the carrier's definition, edited in the Inspector; a marker for it in the character bench is
still to come. SIDECAR worlds are not handled yet.

Between milestones 2 and 3, Workbenches 2 (0.35.0, DECISIONS #207) reworked the benches after
Luke's first real use of them, so every bench from milestone 3 on is built the new way.

As built, milestone 7's bots are driven by the world's REFEREE (DECISIONS #230), in a MODULE world: it
builds only the bots (a member with a brain row and no player) and drives them as a sidecar drives a
SIDECAR world's entities, while the players move themselves. A genre fills a session with them from
its own rules (`add_bot_internal`), not a hot rule of the foundation's. Brains walk a navigation mesh
baked from the level's collision per body size, and act through the authority's reducers. Milestone
8 (a world per match) is not built yet: one world plays one match at a time.

Milestones 1-4 are the chase and the nest; 5-6 the hunt; 7-8 the match; 9-12 the polish a first human
playtest needs (12 before it, per A5). Milestones 9-12 were built in 0.44.0-0.45.0 (noise and pings,
friendly collision as a kin layer, first-person comfort, recording).

## The next milestones (DiscGolf, game 3: `docs/discgolf/DISCGOLF_DESIGN.md` in that repo)
Disc golf is the first game whose world has things in it that the SERVER moves: discs and items in
flight and at rest, hitting trees, each other and people. Players still move themselves (Tier A, as
Fowl Play's farm); the world's referee moves the things.

| # | System | Adds | Proves it |
|---|---|---|---|
| 13 ✔ 0.49.0 | **Bodies the referee moves** (projectiles and physics) | `BodyDef` content; a thrown thing is an ENTITY (kind 3, `body`) with a `movement_state` row like anyone's and a `body_state` side row (its spin, its turn, at rest); `launch_body` (a player's, bounded) and `launch_body_internal` (a genre's); the referee flies each one as a `RigidBody3D` (`FlyingBody`) against the level, the other bodies and stand-ins for the people (`write_body_batch`, `report_body_contacts`); the thrower's game flies its own at once and is corrected toward the referee's | a ball thrown at 150 ms flies on the thrower's screen from the click and lands where the referee says, a second client draws it smoothly, it hits a wall, a person and another ball |
| 14 | **A camera on any entity** | the follow rig for an entity you do not control (your disc in flight); spectating reuses it | the flight cam follows a disc and comes back |
| 15 | **The server pushes people; statuses from collisions** | `push` rows a client applies inside its own prediction, the module widening that entity's bound for those frames; a body's contact may set a status (knocked down) | a blower pushes a player who is never corrected for it |
| 16 | **Items** | pick one up, hold one, use it up; thrown or placed ones fly on 13 | a pad thrown, armed, launching what touches it |
| 17 | **Joining between rounds** | a player who arrives mid-round joins at the next one | a drop-in at the next tee |
Beside them: the aim-and-charge input (Fishing's cast, made the foundation's) and a level change with a
short fade, everyone put at the new level's start.

## Milestone 13: bodies the referee moves (the design)
**A thrown thing is an entity.** `entity` (kind 3, `entity_kind::BODY`), `movement_state` (its place and
velocity: written by the referee, so every client's spawner, interest, interpolation, spectate and the
round's recording take it as they take anyone), and a side row `body_state {entity_id, world_id, def_id,
owner_id, launch_id, launched_at, rot, spin, at_rest}` (no table changes shape: rule 1). Its look is its
`BodyDef`'s, not a character's: one `EntityDefinition` (`body.tres`, `body.tscn`) draws every body.
- **Content**: `BodyDef` (`foundation/content/body_def.gd`, its bench `tools/workbench/body_workbench.tscn`):
  its shape and size, mass, bounce, friction, damping, gravity scale, the fastest it may be launched and
  spun, how far from its launcher it may start, when it is at rest, how long it lasts, how many one
  launcher may have, who may launch it, its look, and its FORCES (`BodyForces`, a resource a genre
  extends: a disc's lift, turn and fade). The module compiles in what it checks (`body.rs`, from the bake).
- **Launching** (rule 13: the client sends the throw, the server bounds it, as Tier A bounds a step):
  `launch_body(def_id, launch_id, origin, vel, spin)`: the launcher's kind may launch it, the origin is
  within its reach of where the server last had the launcher, the speed and spin within the def's, at the
  rate `rules.json` allows, with a referee online (a body no referee moves would hang in the air: said,
  not guessed), and the genre agrees (`may_launch`). Over `max_per_owner`, the launcher's oldest goes. A
  genre launches its own with `launch_body_internal` (a disc thrown from the lie, its speed from the
  disc's numbers). The genre hears every launch (`on_body_launched`).
- **The referee flies them** (`sidecar/physics/body_referee.gd`, in both of a sidecar's jobs): a
  `FlyingBody` (`foundation/physics/flying_body.gd`: a `RigidBody3D` built from the def, its forces
  applied every physics frame) per body, from its rows, against the level it loaded, the other bodies,
  and STAND-INS for the people (a capsule per person, where their newest row puts them). Each server tick
  one `write_body_batch` (movement and body rows of every body that moved; `last_processed_seq` is its
  physics frames since launch, so every client's timeline is the referee's own 60 Hz). A body slower than
  its def's rest speed for its rest time is at rest: written once, and it stops costing anything. A
  contact faster than the def's contact speed is reported (`report_body_contacts`: a row everyone gets
  for a few seconds, what it hit, where, how fast) and the genre hears it (`on_body_contact`); so is a
  body coming to rest (`on_body_rest`). A body the server moves (`place_entity`: a disc put back at its
  lie) is taken from its row.
- **The thrower sees it at once** (`BodyComponent`, `BodyLaunch`): the thrower's game launches the same
  `FlyingBody` locally the moment it throws, with the same def and forces, and draws that; when the
  referee's rows come it compares each with its own flight at the same frame since launch and moves its
  flight toward them (a share of the difference each row, all of it beyond a snap distance: hot rules),
  so the two agree without a pop. At rest, it glides to where the referee put it. Everyone else
  interpolates the rows (and the turn, from `body_state`), behind as they see everyone.
- **What it does not do**: push people (15: a body hits a person and the genre hears it; nobody is
  moved), let a client say where a body landed, or run in a SIDECAR world's own entity simulation (the
  body referee is the one place bodies move, in both kinds of world).

As built (0.49.0, DECISIONS #246): as designed, with three findings from its tests. Godot reports only the
contacts still there after a physics step, and a fast hit bounces clear within it, so a body finds what it
hits by casting its own shape along each frame's motion. Godot's physics has no rolling resistance, so a
body has a `ground_drag` while it touches something. `Engine.time_scale` makes physics frames longer
rather than more of them, so the physics tests run in real time. Its playtest found two more: a new
entity's rows that came just after its `entity` row waited 2 s for its bind to give up (DECISIONS #247,
every entity's, fixed in the registry), and a body's rows placed on its watchers' timeline by seq sat a
referee's round trip early (they are placed by when the server wrote them). Proved by the `bodies` suite, the
integration suite and `tests/bodies_playtest.sh` (a real referee, a thrower and a watcher at 150 ms).

## Owner decisions in force (2026-10-07)
Lag compensation capped at 150 ms, favouring the attacker; hosting a friend-hosted bundle first; the
hatch also starts Dawn; the first-person predator shows no body. Each is a hot rule where it is a number.
