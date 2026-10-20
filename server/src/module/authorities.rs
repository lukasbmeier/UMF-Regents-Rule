//! Admins and sidecars (SIDECAR_SPEC §2), authoritative writes, damage, abilities, NPCs. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// AUTHORITY (SIDECAR_SPEC §2)
// =============================================================================

/// Sender must hold an admin row.
pub fn require_admin(ctx: &ReducerContext) -> Result<(), String> {
    match ctx.db.authority().identity().find(ctx.sender()) {
        Some(a) if a.role == ROLE_ADMIN => Ok(()),
        _ => Err("admin only".into()),
    }
}

/// Sender must be authorised for `world_id` (or for every world, `world_id = 0`).
/// Every reducer that writes authoritative state begins with this.
pub(crate) fn require_authority(ctx: &ReducerContext, world_id: u32) -> Result<(), String> {
    match ctx.db.authority().identity().find(ctx.sender()) {
        Some(a) if a.world_id == 0 || a.world_id == world_id => Ok(()),
        Some(_) => Err(format!("not authorised for world {world_id}")),
        None => Err("not an authority".into()),
    }
}

/// Add or update a trusted identity. Run once per sidecar from the publishing machine:
///   spacetime call umf register_authority <identity-hex> 1 1
#[reducer]
pub fn register_authority(
    ctx: &ReducerContext,
    identity: Identity,
    role: u8,
    world_id: u32,
) -> Result<(), String> {
    require_admin(ctx)?;
    if role > ROLE_SIDECAR {
        return Err(format!("unknown role {role}"));
    }
    // Demoting yourself would drop admin rights with no way to get them back short of a
    // republish — `require_admin` is the only gate on this reducer.
    if identity == ctx.sender() && role != ROLE_ADMIN {
        return Err("refusing to drop your own admin role".into());
    }
    // A sidecar must name its world: the input_queue RLS filter joins on equal world_id, so a
    // wildcard sidecar could write movement but would never see an input to act on.
    if role == ROLE_SIDECAR && world_id == 0 {
        return Err("a sidecar must be registered for a specific world, not the 0 wildcard".into());
    }
    if let Some(mut a) = ctx.db.authority().identity().find(identity) {
        a.role = role;
        a.world_id = world_id;
        ctx.db.authority().identity().update(a);
    } else {
        ctx.db.authority().insert(Authority { identity, role, world_id, last_seen: ctx.timestamp });
    }
    if role == ROLE_SIDECAR {
        drop_sidecar_player(ctx, identity);
    }
    Ok(())
}

#[reducer]
pub fn revoke_authority(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    if identity == ctx.sender() {
        return Err("refusing to revoke your own authority".into());
    }
    ctx.db.authority().identity().delete(identity);
    Ok(())
}

/// Sidecar liveness ping, 1 Hz (SIDECAR_SPEC §3).
#[reducer]
pub fn heartbeat(ctx: &ReducerContext, world_id: u32) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let mut a = ctx.db.authority().identity().find(ctx.sender()).ok_or("not an authority")?;
    let is_sidecar = a.role == ROLE_SIDECAR;
    a.last_seen = ctx.timestamp;
    ctx.db.authority().identity().update(a);

    // Only a SIDECAR heartbeat may bring a world online, because only a sidecar simulates it.
    // `check_authorities` applies the same rule; if this accepted an admin ping, the two would
    // disagree and the world would flip online→offline within the same second, republishing
    // `world_config` to every subscribed client each time.
    if is_sidecar {
        if let Some(mut w) = ctx.db.world_config().world_id().find(world_id) {
            if !w.authority_online {
                w.authority_online = true;
                ctx.db.world_config().world_id().update(w);
                log::info!("world {world_id}: authority back online");
            }
        }
    }
    Ok(())
}

/// Scheduled 1 Hz. Marks SIDECAR worlds offline once their sidecar stops heartbeating, so
/// clients can freeze remote interpolation instead of extrapolating into nonsense.
/// MODULE worlds are always online — this module is their authority.
#[reducer]
pub fn check_authorities(ctx: &ReducerContext, _sched: AuthorityCheckSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("check_authorities: scheduler only".into());
    }
    let cutoff = ctx.timestamp - TimeDuration::from_micros(AUTHORITY_TIMEOUT_MICROS);
    let worlds: Vec<WorldConfig> = ctx.db.world_config().iter().collect();

    for mut w in worlds {
        if w.sim_authority != SIM_SIDECAR {
            continue;
        }
        let live = ctx.db.authority().iter().any(|a| {
            a.role == ROLE_SIDECAR && (a.world_id == 0 || a.world_id == w.world_id) && a.last_seen >= cutoff
        });
        if w.authority_online != live {
            w.authority_online = live;
            let wid = w.world_id;
            ctx.db.world_config().world_id().update(w);
            log::warn!("world {wid}: authority_online -> {live}");
        }
    }
    Ok(())
}

/// The sidecar's motion write-back: one call per world per server tick. Also prunes the inputs
/// it has consumed, which is what keeps `input_queue` bounded under SIDECAR authority.
#[reducer]
pub fn write_movement_batch(
    ctx: &ReducerContext,
    world_id: u32,
    writes: Vec<MovementWrite>,
) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let tick = current_tick(ctx, world_id);

    for w in writes {
        let Some(row) = ctx.db.movement_state().entity_id().find(w.entity_id) else {
            continue;   // entity despawned between the sidecar's read and this write
        };
        if row.world_id != world_id {
            continue;   // authority for one world may not move an entity in another
        }
        let age_us = ctx.timestamp.to_micros_since_unix_epoch() - row.server_ts.to_micros_since_unix_epoch();
        if crate::placed::stale(row.teleport_flag, row.pos, age_us, w.teleport_flag, w.pos) {
            continue;   // from before it saw the server move this entity: that move stands (#252)
        }
        ctx.db.movement_state().entity_id().update(MovementStateRow {
            entity_id: w.entity_id,
            world_id,
            pos: w.pos,
            vel: w.vel,
            yaw: w.yaw,
            grounded: w.grounded,
            move_state: w.move_state,
            last_processed_seq: w.last_processed_seq,
            server_tick: tick,
            server_ts: ctx.timestamp,
            teleport_flag: w.teleport_flag,
            correction_epoch: if w.teleport_flag { row.correction_epoch.wrapping_add(1) } else { row.correction_epoch },
        });
        let consumed: Vec<u64> = ctx
            .db
            .input_queue()
            .entity_id()
            .filter(w.entity_id)
            .filter(|q| q.frame.seq <= w.last_processed_seq)
            .map(|q| q.id)
            .collect();
        for id in consumed {
            ctx.db.input_queue().id().delete(id);
        }
    }
    Ok(())
}

/// Damage from an AUTHORITY (the sidecar, an admin tool). Players have no damage API at all
/// (ARCHITECTURE §7): their only route to hurting anything is `use_ability`, which validates the
/// action first. Both end in `damage_entity`, the one place health changes.
#[reducer]
pub fn apply_damage(
    ctx: &ReducerContext,
    target_id: u64,
    amount: f32,
    source_id: u64,
) -> Result<(), String> {
    let h = ctx
        .db
        .health_state()
        .entity_id()
        .find(target_id)
        .ok_or("apply_damage: no health_state for target")?;
    require_authority(ctx, h.world_id)?;
    damage_entity(ctx, target_id, amount, source_id)
}

/// The one place health changes. `apply_damage` (authority) and `use_ability` (a validated
/// player action) both come through here.
pub(crate) fn damage_entity(ctx: &ReducerContext, target_id: u64, amount: f32, source_id: u64) -> Result<(), String> {
    let mut h = ctx.db.health_state().entity_id().find(target_id).ok_or("no health_state for target")?;
    if !amount.is_finite() {
        return Err("apply_damage: non-finite amount".into());
    }
    h.current = (h.current - amount).clamp(0.0, h.max);
    h.is_dead = h.current <= 0.0;
    h.last_damage_source = source_id;
    h.last_change_server_tick = current_tick(ctx, h.world_id);
    ctx.db.health_state().entity_id().update(h);
    if amount > 0.0 {
        hurt(ctx, target_id);   // a hold that stops when its doer is hurt (DECISIONS #209)
        record_damage(ctx, target_id, source_id, amount);   // who earned its loot (DECISIONS #268)
    }
    Ok(())
}

/// Admin: add or change an ability. A genre's content, like `seed_fish_defs`.
#[reducer]
pub fn define_ability(
    ctx: &ReducerContext,
    ability_id: u32,
    cooldown_ms: u32,
    range: f32,
    wind_up_ms: u32,
    damage: f32,
    data: String,
) -> Result<(), String> {
    require_admin(ctx)?;
    if !range.is_finite() || range < 0.0 || !damage.is_finite() {
        return Err("define_ability: range and damage must be finite, range >= 0".into());
    }
    let row = AbilityDef { ability_id, cooldown_ms, range, wind_up_ms, damage, data };
    if ctx.db.ability_def().ability_id().find(ability_id).is_some() {
        ctx.db.ability_def().ability_id().update(row);
    } else {
        ctx.db.ability_def().insert(row);
    }
    Ok(())
}

/// A player uses an ability (PHASE3_SPEC Task 12; Tier A resolution per PHASE4_SPEC §3).
/// `predicted_id` is the client's own number for this use, echoed on the event so its
/// prediction can be confirmed. Refusals are Errs — only the caller needs to know.
#[reducer]
pub fn use_ability(
    ctx: &ReducerContext,
    ability_id: u32,
    target_id: u64,
    aim: Vector3,
    predicted_id: u32,
) -> Result<(), String> {
    let actor = ctx.db.player().identity().find(ctx.sender()).ok_or("use_ability: no player")?.entity_id;
    use_ability_from(ctx, actor, ability_id, target_id, aim, predicted_id, 0)
}

/// `use_ability`, saying how far behind the server this client sees everyone else (`view_delay_ms`:
/// its interpolation delay and half its round trip), so the referee can judge a judged ability as it
/// saw things (DECISIONS #226). A client from before it calls `use_ability`: judged as things are.
#[reducer]
pub fn use_ability_seen(
    ctx: &ReducerContext,
    ability_id: u32,
    target_id: u64,
    aim: Vector3,
    predicted_id: u32,
    view_delay_ms: u32,
) -> Result<(), String> {
    let actor = ctx.db.player().identity().find(ctx.sender()).ok_or("use_ability: no player")?.entity_id;
    use_ability_from(ctx, actor, ability_id, target_id, aim, predicted_id, view_delay_ms)
}

/// AUTHORITY: `actor_id` (an NPC, a bot) uses an ability, as a player's `use_ability_seen`.
#[reducer]
pub fn use_ability_as(
    ctx: &ReducerContext,
    actor_id: u64,
    ability_id: u32,
    target_id: u64,
    aim: Vector3,
    view_delay_ms: u32,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(actor_id).ok_or("use_ability_as: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    use_ability_from(ctx, actor_id, ability_id, target_id, aim, 0, view_delay_ms)
}

/// A use, by whoever asked: the checks every use makes, then the referee's queue (a judged ability)
/// or the module's coarse resolution.
pub fn use_ability_from(
    ctx: &ReducerContext,
    actor: u64,
    ability_id: u32,
    target_id: u64,
    aim: Vector3,
    predicted_id: u32,
    view_delay_ms: u32,
) -> Result<(), String> {
    let def = ctx.db.ability_def().ability_id().find(ability_id).ok_or("use_ability: unknown ability")?;
    // A downed or carried player cannot (their status, DECISIONS #206).
    require_can_act(ctx, actor, "use_ability")?;
    // Nor an ability its character does not have (DECISIONS #207: a hen pecks, it does not pounce).
    let kind = ctx.db.entity().entity_id().find(actor).map(|e| e.kind).unwrap_or(0);
    if !crate::content::kind_may_use(kind, ability_id) {
        return Err(format!("use_ability: this character cannot use ability {ability_id}"));
    }
    if let Some(h) = ctx.db.health_state().entity_id().find(actor) {
        if h.is_dead {
            return Err("use_ability: the dead cannot act".into());
        }
    }
    let state = ctx.db.ability_state().entity_id().filter(actor).find(|a| a.ability_id == ability_id);
    if let Some(st) = &state {
        if st.cooldown_until > ctx.timestamp {
            return Err("use_ability: on cooldown".into());
        }
    }
    let me = ctx.db.movement_state().entity_id().find(actor).ok_or("use_ability: actor has no movement_state")?;
    // The game's own word (DECISIONS #228: a predator carrying a hen does not pounce).
    crate::game::may_use_ability(ctx, actor, ability_id)?;

    if is_judged(&def) {
        queue_judged(ctx, actor, me.world_id, &def, target_id, aim, predicted_id, view_delay_ms)?;
        set_cooldown(ctx, actor, &def, state);
        crate::game::on_ability_used(ctx, actor, kind, ability_id, aim);
        return Ok(());
    }

    // Tier A resolution is coarse: a targeted ability hits if the target is in range. The
    // sidecar (Task 13) replaces this with a real hit test against the level.
    let mut outcome = OUTCOME_MISS;
    if target_id != 0 && def.range > 0.0 {
        let them = ctx.db.movement_state().entity_id().find(target_id).ok_or("use_ability: no such target")?;
        // A player who is not connected is not in the world (DECISIONS #202).
        if ctx.db.player().entity_id().find(target_id).is_some_and(|p| !p.online) {
            return Err("use_ability: they are not here".into());
        }
        // Nor is one whose status takes them out of reach (escaped, out, hidden: DECISIONS #206).
        if !is_targetable(ctx, target_id) {
            return Err("use_ability: they cannot be reached".into());
        }
        if them.world_id != me.world_id {
            return Err("use_ability: target is in another world".into());
        }
        if them.pos.sub(me.pos).length_sq() > def.range * def.range {
            return Err("use_ability: out of range".into());
        }
        if def.damage > 0.0 {
            damage_entity(ctx, target_id, def.damage, actor)?;
        }
        outcome = OUTCOME_HIT;
    }

    set_cooldown(ctx, actor, &def, state);
    ctx.db.action_event().insert(ActionEvent {
        id: 0,
        world_id: me.world_id,
        actor_id: actor,
        ability_id,
        target_id,
        aim,
        outcome,
        predicted_id,
        server_ts: ctx.timestamp,
    });
    crate::game::on_ability_used(ctx, actor, kind, ability_id, aim);
    Ok(())
}

/// `actor` may next use `def` its cooldown from now.
fn set_cooldown(ctx: &ReducerContext, actor: u64, def: &AbilityDef, state: Option<AbilityState>) {
    let until = ctx.timestamp + TimeDuration::from_micros(def.cooldown_ms as i64 * 1000);
    match state {
        Some(mut st) => {
            st.cooldown_until = until;
            ctx.db.ability_state().id().update(st);
        }
        None => {
            ctx.db.ability_state().insert(AbilityState { id: 0, entity_id: actor, ability_id: def.ability_id, cooldown_until: until, charges: 0 });
        }
    }
}

/// Scheduled 1 Hz: drop action events older than ACTION_EVENT_TTL_MICROS, and end the referee's
/// requests nobody answered (DECISIONS #226).
#[reducer]
pub fn prune_action_events(ctx: &ReducerContext, _sched: ActionPruneSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("prune_action_events: scheduler only".into());
    }
    let cutoff = ctx.timestamp - TimeDuration::from_micros(ACTION_EVENT_TTL_MICROS);
    let stale: Vec<u64> = ctx.db.action_event().iter().filter(|e| e.server_ts < cutoff).map(|e| e.id).collect();
    for id in stale {
        ctx.db.action_event().id().delete(id);
    }
    expire_requests(ctx);
    prune_noise(ctx);
    prune_perf(ctx);
    prune_bodies(ctx);
    prune_pushes(ctx);
    prune_damage_shares(ctx);
    Ok(())
}

#[reducer]
pub fn spawn_npc(ctx: &ReducerContext, world_id: u32, kind: u8, pos: Vector3) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    spawn_npc_internal(ctx, world_id, kind, pos, 0.0);
    Ok(())
}

/// An NPC's rows, for code that has already decided it may (a genre's level set-up). Returns its id.
pub fn spawn_npc_internal(ctx: &ReducerContext, world_id: u32, kind: u8, pos: Vector3, yaw: f32) -> u64 {
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id,
        kind,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    ctx.db.movement_state().insert(MovementStateRow {
        entity_id: ent.entity_id,
        world_id,
        pos,
        vel: Vector3::ZERO,
        yaw,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, world_id),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    ctx.db.health_state().insert(HealthStateRow {
        entity_id: ent.entity_id,
        world_id,
        current: 100.0,
        max: 100.0,
        is_dead: false,
        last_damage_source: 0,
        last_change_server_tick: current_tick(ctx, world_id),
    });
    ent.entity_id
}

#[reducer]
pub fn despawn_entity(ctx: &ReducerContext, entity_id: u64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    if ctx.db.player().entity_id().find(entity_id).is_some() {
        return Err("refusing to despawn a player entity".into());
    }
    despawn_entity_internal(ctx, entity_id);
    Ok(())
}

/// Every row of an entity, for code that has already decided it may (an authority above, a genre
/// taking its own NPC away).
pub fn despawn_entity_internal(ctx: &ReducerContext, entity_id: u64) {
    // What it carried is put down where it is, while its row still says where that is (DECISIONS #228).
    forget_carry(ctx, entity_id);
    ctx.db.entity().entity_id().delete(entity_id);
    ctx.db.movement_state().entity_id().delete(entity_id);
    ctx.db.health_state().entity_id().delete(entity_id);
    ctx.db.input_queue().entity_id().delete(entity_id);
    ctx.db.correction().entity_id().delete(entity_id);
    ctx.db.dash_window().entity_id().delete(entity_id);
    ctx.db.ability_state().entity_id().delete(entity_id);
    ctx.db.inventory_item().owner_entity_id().delete(entity_id);
    ctx.db.npc_brain().entity_id().delete(entity_id);
    ctx.db.equip_state().entity_id().delete(entity_id);
    ctx.db.appearance().entity_id().delete(entity_id);
    forget_damage(ctx, entity_id);
    ctx.db.rate_budget().entity_id().delete(entity_id);
    let open: Vec<Challenge> = ctx.db.challenge().entity_id().filter(entity_id).collect();
    for ch in open {
        ctx.db.challenge().id().delete(ch.id);
        forget_press(ctx, ch.id);
        crate::game::on_challenge_closed(ctx, &ch);
    }
    ctx.db.client_rtt().entity_id().delete(entity_id);
    let memberships: Vec<u64> =
        ctx.db.session_member().entity_id().filter(entity_id).map(|m| m.id).collect();
    for id in memberships {
        ctx.db.session_member().id().delete(id);
    }
    ctx.db.lobby_member().entity_id().delete(entity_id);
    forget_status(ctx, entity_id);
    forget_holds(ctx, entity_id);
    forget_body(ctx, entity_id);
}
