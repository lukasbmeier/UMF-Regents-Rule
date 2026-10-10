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
| 5 | **Abilities on the sidecar, lag-compensated** (A1) | `use_ability` -> `action_request` for SIDECAR worlds; sidecar resolution with a 300 ms ring of transforms, rewound by the attacker's RTT, capped by a hot rule (150 ms, favour attacker) | a pounce issued at t-100 ms hits a chicken that entered a gap at t; one at t+50 ms misses |
| 6 | **Attach and carry** (C1) | table `attachment {entity_id, carrier_id, socket, since}`; CARRIED movement mode (the carried entity renders from its carrier); the character bench fits the socket | a carried entity rides its carrier on every client, late joiners included |
| 7 | **Bots in the lobby** (B3) | a bot is an entity with an `npc_brain` row and a `session_member` row (no new column: membership + brain says bot); fill empty slots on ready (hot rule) | a 1v4 match with 3 bots runs headless to results |
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

Between milestones 2 and 3, Workbenches 2 (0.35.0, DECISIONS #207) reworked the benches after
Luke's first real use of them, so every bench from milestone 3 on is built the new way.

Milestones 1-4 are the chase and the nest; 5-6 the hunt; 7-8 the match; 9-12 the polish a first human
playtest needs (12 before it, per A5).

## Owner decisions in force (2026-10-07)
Lag compensation capped at 150 ms, favouring the attacker; hosting a friend-hosted bundle first; the
hatch also starts Dawn; the first-person predator shows no body. Each is a hot rule where it is a number.
