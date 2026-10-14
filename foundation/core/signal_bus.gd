extends Node
## SignalBus — global, UI-facing event bus.
##
## RULES
##  • Zero logic. Only signal declarations live here.
##  • Every gameplay signal carries entity_id as its FIRST argument so listeners can filter.
##  • Low-frequency only. Position, velocity, and per-tick state NEVER go on the bus;
##    they are pulled from components via their read API.
##  • Component-to-component communication inside one entity uses entity-local signals,
##    not this bus.
##  • Emitters are core systems. Listeners are UI/audio/VFX controllers. Never the reverse.

# --- World / session ---------------------------------------------------------
## Initial subscription applied; the local cache now reflects the full visible world.
signal world_ready()
## The server has told us which entity we control.
signal local_entity_assigned(entity_id: int)
## An entity scene has been instantiated and bound. `kind` matches the server `entity.kind` enum.
signal entity_spawned(entity_id: int, kind: int)
signal entity_despawned(entity_id: int)

## Session phase machine. `session_id` first because these are not entity-scoped; the phase is
## a property of the match, not of any one player. `ends_at_usec` is server-clock micros, so UI
## countdowns compare it against ClockSync.server_usec().
signal session_phase_changed(session_id: int, old_phase: int, new_phase: int, ends_at_usec: int)
## Entity-scoped, so entity_id leads as usual.
signal session_score_changed(entity_id: int, score: int, coins: int)

# --- Health ------------------------------------------------------------------
signal entity_health_changed(entity_id: int, current: float, max: float)
signal entity_died(entity_id: int, killer_id: int)
signal entity_revived(entity_id: int)
## Its status changed (`StatusComponent`, DECISIONS #206): numbers, `from` == `to` when the same one
## was set again.
signal entity_status_changed(entity_id: int, from: int, to: int)
## Something held ON `target_id` changed: begun, joined, let go of, done (`HoldComponent`, DECISIONS #209).
signal hold_changed(target_id: int)
## Something held on `target_id` is done (`hold`: its `HoldDef.id`).
signal hold_finished(target_id: int, hold: int)
## `entity_id` began holding something on `target_id`, or let go (`target_id` -1).
signal entity_holding_changed(entity_id: int, target_id: int)
## The server judged one of `entity_id`'s timed presses (`TimedPressComponent`, DECISIONS #210).
signal timed_press_judged(entity_id: int, round: int, quality: float)

# --- Movement (discrete events only) -----------------------------------------
signal entity_jumped(entity_id: int)
signal entity_landed(entity_id: int, impact_speed: float)
signal entity_teleported(entity_id: int)
## A noise this player heard (`NoiseFeedback`, DECISIONS #233): its kind, where, who made it (0: the
## world), what it was about (0: a place).
signal noise_heard(kind: int, pos: Vector3, source_id: int, target_id: int)

# --- Inventory ---------------------------------------------------------------
## Something in this entity's inventory changed. Deliberately coarse: the component holds the
## detail and UI pulls it, so a 40-slot bag does not put 40 signals on the bus.
signal entity_inventory_changed(entity_id: int)

# --- Interaction / feedback --------------------------------------------------
## What the local player is looking at, or -1 for nothing. A PROMPT hint only — the server
## re-checks eligibility when `interact` is actually called.
signal interact_target_changed(entity_id: int)
## An action happened (a row in `action_event`), announced once by the ACTOR's component.
## `outcome` is SpaceTimeActionComponent.Outcome.
signal entity_action(actor_id: int, ability_id: int, target_id: int, outcome: int)
## A reducer the local player issued was rejected by the server. UI may show a toast.
signal action_rejected(reducer_name: StringName, reason: String)
## Generic user-facing notice. severity: 0 info, 1 warning, 2 error.
signal notification_requested(text: String, severity: int)
