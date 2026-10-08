//! Input, the movement tick, Tier A trust, worlds, levels, spawns, the dev tools. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// GAMEPLAY REDUCERS
// =============================================================================

/// Client → server. Frames are queued, not simulated here, so the tick reducer stays the single
/// place where movement is resolved. Invalid frames are dropped silently: returning Err would
/// roll back the whole batch and make one bad frame cost the client three good ones.
#[reducer]
pub fn submit_input(ctx: &ReducerContext, frames: Vec<InputFrame>) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(ctx.sender())
        .ok_or("submit_input: sender has no player row")?;

    if frames.is_empty() || frames.len() > MAX_BATCH {
        return Err(format!("submit_input: batch size {} out of range 1..={}", frames.len(), MAX_BATCH));
    }

    let state = ctx
        .db
        .movement_state()
        .entity_id()
        .find(player.entity_id)
        .ok_or("submit_input: entity has no movement_state")?;

    let mut queued: Vec<InputQueueRow> = ctx.db.input_queue().entity_id().filter(player.entity_id).collect();
    if queued.len() + frames.len() > MAX_QUEUE_DEPTH {
        return Err("submit_input: queue depth exceeded".into());
    }
    let mut last_seq = queued.iter().map(|q| q.frame.seq).max().unwrap_or(state.last_processed_seq);

    for f in frames {
        // Strictly increasing: anything else is a replay. Gaps are ALLOWED. A batch lost to a
        // dropped connection leaves one, and refusing gaps (this used to cap them at one batch)
        // froze a reconnected player forever: every later frame was too far ahead. A gap buys
        // nothing, because each frame is still bounded by the trust envelope and the per-tick
        // frame budget in tick_world_module.
        if f.seq <= last_seq {
            log::debug!("drop input seq={} (last={}) for entity {}", f.seq, last_seq, player.entity_id);
            continue;
        }
        last_seq = f.seq;
        queued.push(ctx.db.input_queue().insert(InputQueueRow {
            id: 0,
            entity_id: player.entity_id,
            world_id: state.world_id,
            frame: f,
            received_at: ctx.timestamp,
        }));
    }
    Ok(())
}

/// Scheduled at SERVER_TICK_HZ. MODULE authority: drains every entity's queue through the frozen
/// gravity-only twin and applies client trust. SIDECAR authority: only prunes inputs older than
/// 2 s so a dead sidecar cannot grow the queue unbounded (the sidecar deletes consumed rows itself
/// via write_movement_batch — Phase 3).
#[reducer]
pub fn tick_movement(ctx: &ReducerContext, _sched: TickSchedule) -> Result<(), String> {
    // Only the scheduler may call this.
    if ctx.sender() != ctx.database_identity() {
        return Err("tick_movement: scheduler only".into());
    }

    // Every world advances on the same schedule but decides independently who simulates it.
    // Collected up front: the loop body updates world_config and movement_state, and mutating a
    // table while iterating it is not something to rely on.
    let worlds: Vec<WorldConfig> = ctx.db.world_config().iter().collect();
    let cfg = crate::movement_config::default_config();

    for mut world in worlds {
        let wid = world.world_id;
        world.server_tick += 1;
        world.server_ts = ctx.timestamp;
        let tick = world.server_tick;
        let authority = world.sim_authority;
        ctx.db.world_config().world_id().update(world);

        if authority == SIM_SIDECAR {
            // Sidecar owns motion. Drop inputs it has evidently abandoned.
            let cutoff = ctx.timestamp - TimeDuration::from_micros(2_000_000);
            for q in ctx.db.input_queue().world_id().filter(wid) {
                if q.received_at < cutoff {
                    ctx.db.input_queue().id().delete(q.id);
                }
            }
            continue;
        }

        tick_world_module(ctx, wid, tick, &cfg);
    }
    Ok(())
}

/// MODULE authority for one world. A client-driven entity's position comes from its client,
/// bounded per frame by `apply_client_trust`; the frozen gravity-only twin only moves entities
/// that nobody is driving.
pub(crate) fn tick_world_module(
    ctx: &ReducerContext,
    world_id: u32,
    tick: u64,
    cfg: &crate::sim::MovementConfig,
) {
    let rows: Vec<MovementStateRow> = ctx.db.movement_state().world_id().filter(world_id).collect();
    // Where a player may stand in this world's level (REVIEW B2); the greybox (0) has no bake.
    let level = crate::level::by_id(world_level_of(ctx, world_id));
    for row in rows {
        let mut inputs: Vec<InputQueueRow> = ctx.db.input_queue().entity_id().filter(row.entity_id).collect();
        inputs.sort_by_key(|q| q.frame.seq);

        let mut s = MovementState {
            pos: row.pos,
            vel: row.vel,
            yaw: row.yaw,
            grounded: row.grounded,
            move_state: row.move_state,
        };
        let mut last_seq = row.last_processed_seq;
        let mut epoch = row.correction_epoch;

        if inputs.is_empty() {
            // Nobody's frames landed this tick. For a CONNECTED player that only means batching
            // and the tick drifted past each other: the frames are late, and they carry the
            // client's own gravity when they arrive. Simulating it here as well puts the module
            // one step ahead of the client for a tick, which the client sees as a correction
            // mid-jump. Only an entity nobody is driving (an NPC, a player who has left) falls.
            let driven = ctx.db.player().entity_id().find(row.entity_id).map(|p| p.online).unwrap_or(false);
            if !driven && !s.grounded {
                s = crate::sim::simulate(&s, &InputFrame::default(), cfg, SERVER_DT);
            }
        } else {
            inputs.truncate(MAX_FRAMES_PER_TICK);
            let mut correction = ctx.db.correction().entity_id().find(row.entity_id);
            for q in &inputs {
                ctx.db.input_queue().id().delete(q.id);
                last_seq = q.frame.seq;
                if q.frame.epoch != epoch {
                    // Produced before the client saw our last override: it describes a path the
                    // server has already replaced. Consume it and move nothing. Taking it would
                    // pull the entity back toward the rejected path, the client would then be
                    // corrected toward THAT, and the two would chase each other indefinitely.
                    continue;
                }
                // The first frame of a new epoch carries the client's replay of everything since
                // the override; every later frame is one step.
                let mut frames: f32 = 1.0;
                if let Some(c) = correction.take() {
                    if c.epoch == epoch {
                        let by_seq = q.frame.seq.saturating_sub(c.from_seq).max(1) as f32;
                        let elapsed = (ctx.timestamp.to_micros_since_unix_epoch()
                            - c.at.to_micros_since_unix_epoch()).max(0) as f32 / 1_000_000.0;
                        let by_time = elapsed / CLIENT_DT * TRUST_SPEED_SLACK + MAX_FRAMES_PER_TICK as f32;
                        frames = by_seq.min(by_time).max(1.0);
                    }
                    ctx.db.correction().entity_id().delete(row.entity_id);
                }
                let (next, clamped) = apply_client_trust(&s, &q.frame, cfg, frames, level);
                s = next;
                if clamped {
                    // We just overrode the client. Everything it sends until it has seen this
                    // row is from the old path; a new epoch is how we will recognise it.
                    epoch = epoch.wrapping_add(1);
                    record_correction(ctx, row.entity_id, epoch, q.frame.seq);
                    correction = ctx.db.correction().entity_id().find(row.entity_id);
                }
            }
        }

        let changed = s.pos != row.pos || s.vel != row.vel || s.grounded != row.grounded
            || last_seq != row.last_processed_seq || epoch != row.correction_epoch || row.teleport_flag;
        if changed {
            ctx.db.movement_state().entity_id().update(MovementStateRow {
                entity_id: row.entity_id,
                world_id: row.world_id,
                pos: s.pos,
                vel: s.vel,
                yaw: s.yaw,
                grounded: s.grounded,
                move_state: s.move_state,
                last_processed_seq: last_seq,
                server_tick: tick,
                server_ts: ctx.timestamp,
                teleport_flag: false,
                correction_epoch: epoch,
            });
        }
    }
}

/// MODULE authority (Tier A): the client's position, bounded by how far a legitimate client
/// could have moved in one frame. Returns the accepted state and whether the claim was CLAMPED.
///
/// A claim inside the envelope is taken exactly, bit for bit: that is what lets the owning
/// client's reconciliation see zero error in normal play. A claim outside it is clamped to the
/// envelope rather than rejected. Rejecting strands the server behind a client that then
/// carries on normally; clamping always converges.
///
/// The previous policy ran the gravity-only twin and trusted `client_pos` within 0.5 m of it.
/// The twin cannot see the level, so for a client standing on anything above `ground_y` its
/// fall velocity kept growing until the positions diverged past the radius, and the module
/// dropped the player through the floor (DECISIONS #70).
pub(crate) fn apply_client_trust(
    prev: &MovementState,
    frame: &InputFrame,
    cfg: &crate::sim::MovementConfig,
    frames: f32,
    level: Option<&crate::level::LevelBake>,
) -> (MovementState, bool) {
    let claimed = frame.client_pos.sub(prev.pos);
    // The fastest a legitimate client can go: a sprint, plus a dash burst when dashing is on;
    // and upward, a jump or (when flapping is on) a flap.
    use crate::movement_config::{DASH_IMPULSE, FLAP_CHARGES, FLAP_VELOCITY};
    let burst = if DASH_IMPULSE > 0.0 { DASH_IMPULSE } else { 0.0 };
    let lift = if FLAP_CHARGES > 0 { cfg.jump_velocity.max(FLAP_VELOCITY) } else { cfg.jump_velocity };
    let max_h = (cfg.sprint_speed + burst) * TRUST_SPEED_SLACK * CLIENT_DT * frames;
    let max_up = lift * TRUST_SPEED_SLACK * CLIENT_DT * frames;
    let max_down = TRUST_MAX_FALL_SPEED * CLIENT_DT * frames;

    let h_sq = claimed.x * claimed.x + claimed.z * claimed.z;
    let within = h_sq <= max_h * max_h && claimed.y <= max_up && claimed.y >= -max_down;
    let (pos, step) = if within {
        (frame.client_pos, claimed)
    } else {
        let h_scale = if h_sq > max_h * max_h { max_h / h_sq.sqrt() } else { 1.0 };
        // A claim too far to believe is scaled AS A WHOLE: the height of a place the server does
        // not think the player reached is no more credible than its distance. Clamped on its own,
        // a claim 53 m off at the dock's height dropped a player standing by the village 1.35 m
        // into the ground, stuck there (DECISIONS #149). A claim whose distance IS believable
        // keeps its own vertical limits, because a real fall is fast.
        let step = Vector3::new(claimed.x * h_scale, (claimed.y * h_scale).clamp(-max_down, max_up), claimed.z * h_scale);
        (prev.pos.add(step), step)
    };
    // THE LAKE IS NOT A ROAD (REVIEW 0.23.1 B2): the envelope bounds how FAST a client moved, not
    // WHERE to. A claim that leaves ground a player may stand on (`LevelBake::can_stand`: land,
    // wading water, the dock) for deep water is refused whole: the player stays where they were,
    // and the correction epoch tells the client so. A player already off it (an admin's teleport)
    // is let walk out rather than trapped.
    let off_ground = level.is_some_and(|l| !l.can_stand(pos.x, pos.z) && l.can_stand(prev.pos.x, prev.pos.z));
    let (pos, step) = if off_ground { (prev.pos, Vector3::ZERO) } else { (pos, step) };
    let next = MovementState {
        pos,
        // What the client's motion implies. Remote clients extrapolate briefly with it, and an
        // entity whose client disconnects mid-air falls from it.
        vel: step.scale(1.0 / (CLIENT_DT * frames)),
        // Facing follows the camera only while there is movement input — standing still and
        // looking around must not spin the body — or while the frame says something is being
        // aimed (`face`). The client applies this same rule to the same frame, so both sides
        // always agree.
        yaw: if frame.face || frame.move_x != 0.0 || frame.move_y != 0.0 { frame.look_yaw } else { prev.yaw },
        // GROUNDED IS THE CLIENT'S OWN ANSWER when its model gave one (DECISIONS #192): AIR is in
        // the air, a gait is on the ground, whatever the step's height. Read off the step alone,
        // every stride up a slope was a jump to everyone watching and a jump's top was a landing,
        // so other players' jump and land restarted over and over. Other states (a dash, a
        // genre's own) still go by the step.
        grounded: match frame.move_state {
            MOVE_AIR => false,
            MOVE_IDLE | MOVE_WALK | MOVE_SPRINT | MOVE_RUN => true,
            _ => step.y.abs() < GROUNDED_EPS,
        },
        // The client's model decided what this movement is; the module cannot, so it mirrors it —
        // but only a state someone defined.
        move_state: if frame.move_state <= MOVE_STATE_FOUNDATION_MAX || frame.move_state >= MOVE_STATE_GENRE_FROM {
            frame.move_state
        } else {
            prev.move_state
        },
    };
    (next, !within || off_ground)
}

/// Switch a world's motion authority. Admin only.
#[reducer]
pub fn set_sim_authority(ctx: &ReducerContext, world_id: u32, mode: u8) -> Result<(), String> {
    require_admin(ctx)?;
    if mode > SIM_SIDECAR {
        return Err(format!("unknown sim_authority {mode}"));
    }
    let mut w = ctx
        .db
        .world_config()
        .world_id()
        .find(world_id)
        .ok_or(format!("no world_config for world {world_id}"))?;
    w.sim_authority = mode;
    // A SIDECAR world is offline until its sidecar heartbeats; a MODULE world is always online.
    w.authority_online = mode == SIM_MODULE;
    ctx.db.world_config().world_id().update(w);
    Ok(())
}

/// Set where new players in a world appear. The genre's own entry point: it knows its levels
/// (see `crate::level`); nothing here checks that the point is on the ground.
/// Point a world at a level: record it, move the world's spawn to the bake's (the default spawn for
/// level 0, which has no bake), and tell every genre (`on_level_changed`: fishing stocks the
/// greybox's ponds, places its rival, rolls the conditions). The caller has decided it may.
pub fn set_world_level_internal(ctx: &ReducerContext, world_id: u32, level_id: u8) -> Result<(), String> {
    let spawn = match crate::level::by_id(level_id) {
        Some(b) => Vector3::new(b.spawn[0], b.spawn[1], b.spawn[2]),
        None if level_id == 0 => default_spawn(),
        None => return Err(format!("unknown level {level_id} (the baked levels: {:?})",
            crate::level::ALL.iter().map(|l| (l.id, l.name)).collect::<Vec<_>>())),
    };
    set_world_spawn_internal(ctx, world_id, spawn)?;
    let row = WorldLevel { world_id, level_id };
    if ctx.db.world_level().world_id().find(world_id).is_some() {
        ctx.db.world_level().world_id().update(row);
    } else {
        ctx.db.world_level().insert(row);
    }
    crate::game::on_level_changed(ctx, world_id, level_id);
    log::info!("world {world_id} now runs level {level_id}");
    Ok(())
}

/// The level a world runs (0 for none).
pub fn world_level_of(ctx: &ReducerContext, world_id: u32) -> u8 {
    ctx.db.world_level().world_id().find(world_id).map(|w| w.level_id).unwrap_or(0)
}

/// Switch a world to a baked level (or 0, none). Admin only. It moves where the NEXT player
/// appears; anyone already connected stays put, so call it before clients connect.
#[reducer]
pub fn set_world_level(ctx: &ReducerContext, world_id: u32, level_id: u8) -> Result<(), String> {
    require_admin(ctx)?;
    set_world_level_internal(ctx, world_id, level_id)
}

pub fn set_world_spawn_internal(ctx: &ReducerContext, world_id: u32, pos: Vector3) -> Result<(), String> {
    if !(pos.x.is_finite() && pos.y.is_finite() && pos.z.is_finite()) {
        return Err("set_world_spawn: spawn must be finite".into());
    }
    let mut w = ctx
        .db
        .world_config()
        .world_id()
        .find(world_id)
        .ok_or(format!("set_world_spawn: no world {world_id}"))?;
    w.spawn = pos;
    ctx.db.world_config().world_id().update(w);
    Ok(())
}

/// Set where new players in a world appear. Admin only. Players already in the world stay where
/// they are: this decides where the NEXT one arrives.
#[reducer]
pub fn set_world_spawn(ctx: &ReducerContext, world_id: u32, pos: Vector3) -> Result<(), String> {
    require_admin(ctx)?;
    set_world_spawn_internal(ctx, world_id, pos)
}

/// Create a world. Admin only.
#[reducer]
pub fn create_world(ctx: &ReducerContext, world_id: u32, sim_authority: u8) -> Result<(), String> {
    require_admin(ctx)?;
    if sim_authority > SIM_SIDECAR {
        return Err(format!("unknown sim_authority {sim_authority}"));
    }
    if ctx.db.world_config().world_id().find(world_id).is_some() {
        return Err(format!("world {world_id} already exists"));
    }
    ctx.db.world_config().insert(WorldConfig {
        world_id,
        sim_authority,
        authority_online: sim_authority == SIM_MODULE,
        server_tick: 0,
        server_ts: ctx.timestamp,
        spawn: default_spawn(),
    });
    Ok(())
}

/// Admin only: turn the dev tools (`teleport`, `dev_nudge`) on or off for every player of this
/// database. The test suites call it after publishing `umf-test`; nobody else should.
#[reducer]
pub fn set_dev_tools(ctx: &ReducerContext, enabled: bool) -> Result<(), String> {
    require_admin(ctx)?;
    let row = DevTools { id: 0, enabled };
    if ctx.db.dev_tools().id().find(0).is_some() {
        ctx.db.dev_tools().id().update(row);
    } else {
        ctx.db.dev_tools().insert(row);
    }
    Ok(())
}

/// An admin always may; anyone else only while the dev tools are on (`DevTools`). In a Tier A
/// world a self-teleport walks past every rule that is a place: the rod-reach gate (#143) first.
pub(crate) fn require_dev_tools(ctx: &ReducerContext, verb: &str) -> Result<(), String> {
    if require_admin(ctx).is_ok() || ctx.db.dev_tools().id().find(0).is_some_and(|d| d.enabled) {
        return Ok(());
    }
    Err(format!("{verb} is a dev tool, and the dev tools are off on this server"))
}

/// Dev/test helper: place an entity somewhere and flag it as a teleport. Gated by `require_dev_tools`.
#[reducer]
pub fn teleport(ctx: &ReducerContext, pos: Vector3) -> Result<(), String> {
    require_dev_tools(ctx, "teleport")?;
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("no player")?;
    let mut m = ctx.db.movement_state().entity_id().find(p.entity_id).ok_or("no movement_state")?;
    m.pos = pos;
    m.vel = Vector3::ZERO;
    m.grounded = false;
    m.teleport_flag = true;
    // An override: frames the client sends before it sees this row are from the old position.
    m.correction_epoch = m.correction_epoch.wrapping_add(1);
    m.server_ts = ctx.timestamp;
    record_correction(ctx, m.entity_id, m.correction_epoch, m.last_processed_seq);
    ctx.db.movement_state().entity_id().update(m);
    Ok(())
}

/// Dev/test helper: shift YOUR entity's authoritative position without flagging a teleport,
/// the way a server correction would. Exists to prove the owner glides to a correction rather
/// than popping (PHASE4_SPEC section 5). Gated like `teleport`.
#[reducer]
pub fn dev_nudge(ctx: &ReducerContext, offset: Vector3) -> Result<(), String> {
    require_dev_tools(ctx, "dev_nudge")?;
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("no player")?;
    let mut m = ctx.db.movement_state().entity_id().find(p.entity_id).ok_or("no movement_state")?;
    m.pos = m.pos.add(offset);
    m.correction_epoch = m.correction_epoch.wrapping_add(1);
    m.server_ts = ctx.timestamp;
    record_correction(ctx, m.entity_id, m.correction_epoch, m.last_processed_seq);
    ctx.db.movement_state().entity_id().update(m);
    Ok(())
}
