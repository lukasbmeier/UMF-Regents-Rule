//! init, connect and disconnect, the player's name. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// LIFECYCLE REDUCERS
// =============================================================================

#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ctx.db.world_config().insert(WorldConfig {
        world_id: DEFAULT_WORLD,
        sim_authority: SIM_MODULE,
        authority_online: true,   // MODULE worlds are always "online": this module IS the authority
        server_tick: 0,
        server_ts: ctx.timestamp,
        spawn: default_spawn(),
    });
    // The publisher is admin. This is the root of trust for every privileged reducer:
    // `spacetime publish` runs as this identity, so whoever deploys the module controls it.
    ctx.db.authority().insert(Authority {
        identity: ctx.sender(),
        role: ROLE_ADMIN,
        world_id: 0,
        last_seen: ctx.timestamp,
    });
    ctx.db.authority_check_schedule().insert(AuthorityCheckSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    ctx.db.phase_schedule().insert(PhaseSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    ctx.db.challenge_prune_schedule().insert(ChallengePruneSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(5_000_000).into(),
    });
    ctx.db.action_prune_schedule().insert(ActionPruneSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    // The hot rules' rows, with this build's values (DECISIONS #201).
    sync_hot_rules(ctx);
    // The abilities, as baked from their .tres (foundation/content/abilities/, a genre's
    // content/; DECISIONS #199). The foundation's own, `melee`, makes the action path work out of
    // the box (PHASE3_SPEC Task 12).
    for a in crate::content::ABILITIES {
        ctx.db.ability_def().insert(AbilityDef {
            ability_id: a.ability_id,
            cooldown_ms: a.cooldown_ms,
            range: a.range,
            wind_up_ms: a.wind_up_ms,
            damage: a.damage,
            data: a.data.to_string(),
        });
    }
    // A default session on the default world, so a client that just connects lands somewhere
    // with a phase machine already running rather than in a null session.
    let sess = ctx.db.session().insert(Session {
        id: 0,
        world_id: DEFAULT_WORLD,
        kind: SESSION_KIND_DEFAULT,
        phase: PHASE_LOBBY,
        phase_ends_at: ctx.timestamp
            + TimeDuration::from_micros(phase_duration_micros(SESSION_KIND_DEFAULT, PHASE_LOBBY).unwrap_or(HOLD_MICROS)),
        seed: ctx.timestamp.to_micros_since_unix_epoch() as u64,
        max_members: 0,   // 0 = uncapped
        round: 1,
    });
    // Its first match, waiting for players (DECISIONS #182).
    begin_match(ctx, sess);
    let interval = TimeDuration::from_micros((1_000_000 / crate::movement_config::SERVER_TICK_HZ) as i64);
    ctx.db.tick_schedule().insert(TickSchedule {
        scheduled_id: 0,
        scheduled_at: interval.into(),   // TimeDuration → ScheduleAt::Interval (loop)
    });
    log::info!("UMF module initialised: sim_authority=MODULE, server_tick_hz={}", crate::movement_config::SERVER_TICK_HZ);
    // The genre layer seeds its own static content last, once the foundation exists.
    crate::game::on_init(ctx);
}

/// Longest name a player may set. Long enough for a nickname, short enough that a nameplate
/// cannot be used to draw a wall of text over somebody else's screen.
pub const MAX_NAME_LEN: usize = 20;

/// Set your own display name. The only thing a player may write about themselves, so it is the
/// one place untrusted text enters the database — and every client renders it over someone's
/// head, which is why it is cleaned here rather than at each of them.
///
/// Names are NOT unique. Enforcing that needs a rejection path, a retry UI and a decision about
/// what happens when two friends both want "Luke"; a nameplate showing two of them is a smaller
/// problem than any of that. The identity is what the module keys on regardless.
#[reducer]
pub fn set_player_name(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let mut p = ctx
        .db
        .player()
        .identity()
        .find(ctx.sender())
        .ok_or("set_player_name: no player row")?;
    spend_rate(ctx, p.entity_id, "set_player_name")?;

    // Control characters cover newlines and the bidi overrides that let a name rewrite the line
    // it is drawn on. Whitespace is collapsed so " a   b " and "a b" cannot look like two names.
    let cleaned: String = name
        .chars()
        .filter(|c| !c.is_control())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if cleaned.is_empty() {
        return Err("set_player_name: a name cannot be blank".into());
    }
    // By CHARACTERS, not bytes: truncating a multi-byte character mid-way would panic.
    let trimmed: String = cleaned.chars().take(MAX_NAME_LEN).collect();
    if trimmed == p.name {
        return Ok(());   // idempotent: clients send this on every connect
    }
    log::info!("player {} is now '{}'", p.entity_id, trimmed);
    p.name = trimmed;
    ctx.db.player().identity().update(p);
    Ok(())
}


/// A client connected. Creates its player row, entity and state on first sight; flips
/// `online` back on for a returning identity.
#[reducer(client_connected)]
pub fn client_connected(ctx: &ReducerContext) {
    // A republish does not run init: the first connect after one brings the hot rules up to date.
    sync_hot_rules(ctx);
    if let Some(mut p) = ctx.db.player().identity().find(ctx.sender()) {
        p.online = true;
        let entity_id = p.entity_id;
        ctx.db.player().identity().update(p);
        player_arrived(ctx, entity_id);
        crate::game::on_player_returned(ctx, entity_id);
        return;
    }
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id: DEFAULT_WORLD,
        kind: entity_kind::PLAYER,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    ctx.db.player().insert(Player {
        identity: ctx.sender(),
        entity_id: ent.entity_id,
        name: String::new(),
        online: true,
    });
    let spawn = ctx
        .db
        .world_config()
        .world_id()
        .find(DEFAULT_WORLD)
        .map(|w| w.spawn)
        .unwrap_or_else(default_spawn);
    ctx.db.movement_state().insert(MovementStateRow {
        entity_id: ent.entity_id,
        world_id: DEFAULT_WORLD,
        pos: spawn,
        vel: Vector3::ZERO,
        yaw: 0.0,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, DEFAULT_WORLD),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    ctx.db.health_state().insert(HealthStateRow {
        entity_id: ent.entity_id,
        world_id: DEFAULT_WORLD,
        current: hot_number(ctx, crate::hot::foundation::NEW_PLAYER_HEALTH) as f32,
        max: hot_number(ctx, crate::hot::foundation::NEW_PLAYER_HEALTH) as f32,
        is_dead: false,
        last_damage_source: 0,
        last_change_server_tick: current_tick(ctx, DEFAULT_WORLD),
    });
    // Join whatever session owns the default world, if one exists.
    if let Some(sess) = ctx.db.session().world_id().find(DEFAULT_WORLD) {
        let _ = add_member(ctx, &sess, ent.entity_id);
    }
    player_arrived(ctx, ent.entity_id);
    crate::game::on_player_created(ctx, ent.entity_id);
}

#[reducer(client_disconnected)]
pub fn client_disconnected(ctx: &ReducerContext) {
    if let Some(mut p) = ctx.db.player().identity().find(ctx.sender()) {
        p.online = false;
        let entity_id = p.entity_id;
        ctx.db.player().identity().update(p);
        // Persistence policy is the genre's: the foundation keeps the entity, and the hook may
        // despawn it (a party game) or keep it (an MMO).
        crate::game::on_player_left(ctx, entity_id);
    }
}
