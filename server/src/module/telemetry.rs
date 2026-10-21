//! TELEMETRY (DECISIONS #244, Luke 2026-10-15: "metrics and performance reported remotely across
//! games/users and feedback that can be sent back in with their context of the game and timestamps").
//! Every game's own, on whoever hosts it, and the genre's none of its business:
//!
//!   perf_report   a player's game (or a referee) says how it ran over its last window (30 s): frame
//!                 times, every spike with when it was, ping, corrections, memory, entities. One small
//!                 call a window, off the input path (the client's `Telemetry`).
//!   feedback      a player marks a moment (F8, or the Esc menu) and says what they noticed: the
//!                 server stamps it with who, where and when from its OWN rows (their entity, its world,
//!                 level, session, round and phase, where it stood), so a report says truly whose it is.
//!
//!   where_sample  each online player's place, rewritten every `foundation.telemetry_where_s` (5 s) by the
//!                 module's own tick (DECISIONS #276): the trail the host's chronicle keeps forever
//!                 (`tools/chronicle.py`), one small row a player rather than every step they take.
//!
//! PRIVATE TABLES: no client receives them (nothing for every player's bandwidth); the database's owner
//! reads them (`tools/feedback.sh`, `spacetime sql`). Nothing personal: `crate::telemetry`.

use super::*;
use crate::telemetry as rules;

#[table(accessor = perf_report)]
pub struct PerfReport {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    /// When the server heard it (the end of its window).
    #[index(btree)]
    pub at: Timestamp,
    pub identity: Identity,
    /// The player's entity (0: a referee).
    pub entity_id: u64,
    pub world_id: u32,
    pub level: u8,
    /// `ROLE_CLIENT` (a player's game) or `ROLE_REFEREE`.
    pub role: u8,
    /// The build (its schema fingerprint) and what it runs on (OS, CPU, GPU, memory: nothing personal).
    pub build: String,
    pub platform: String,
    /// The window it covers, its frames, and their frame times (ms).
    pub window_s: f32,
    pub frames: u32,
    pub fps: f32,
    pub frame_ms_p50: f32,
    pub frame_ms_p95: f32,
    pub frame_ms_p99: f32,
    pub frame_ms_max: f32,
    /// Frames slower than the client's spike threshold (each one's moment and cause in `detail`).
    pub spikes: u32,
    pub rtt_ms: f32,
    pub rtt_ms_max: f32,
    /// Times the server corrected this player's movement in the window.
    pub corrections: u32,
    pub memory_mb: f32,
    pub entities: u32,
    /// JSON: the spikes ([server seconds, ms, "frame"/"net"], at most a dozen) and anything a later
    /// build adds, without reshaping the table.
    pub detail: String,
}

#[table(accessor = feedback)]
pub struct Feedback {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    /// When the server heard it, and the moment the player marked (pressed the key).
    #[index(btree)]
    pub at: Timestamp,
    pub noticed_at: Timestamp,
    pub identity: Identity,
    pub name: String,
    pub entity_id: u64,
    /// Their character's kind and status then, and where it stood.
    pub kind: u8,
    pub status: u8,
    pub pos: Vector3,
    pub world_id: u32,
    pub level: u8,
    pub session_id: u64,
    pub round: u32,
    pub phase: u8,
    /// `FEEDBACK_BUG`, `_LAG`, `_IDEA`, `_OTHER`, and what they wrote.
    pub category: u8,
    pub text: String,
    pub build: String,
    pub platform: String,
    /// JSON from their game: its performance up to the moment (the window so far and the one before),
    /// the camera, what they were holding, the last errors it logged.
    pub context: String,
}

/// Who is reporting: a player's game (their entity and world), or a referee (its world). Err: neither.
fn reporter(ctx: &ReducerContext) -> Result<(u64, u32, u8), String> {
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        let world = ctx.db.movement_state().entity_id().find(p.entity_id).map(|m| m.world_id).unwrap_or(DEFAULT_WORLD);
        return Ok((p.entity_id, world, rules::ROLE_CLIENT));
    }
    if let Some(a) = ctx.db.authority().identity().find(ctx.sender()) {
        return Ok((0, a.world_id, rules::ROLE_REFEREE));
    }
    Err("telemetry: neither a player nor an authority".into())
}

/// A PERFORMANCE REPORT for the window just ended. Numbers out of sense are stored as their floor, long
/// strings cut; a player at most at the `report_perf` rate (a referee is trusted to its window).
#[reducer]
#[allow(clippy::too_many_arguments)]
pub fn report_perf(
    ctx: &ReducerContext,
    build: String,
    platform: String,
    window_s: f32,
    frames: u32,
    frame_ms_p50: f32,
    frame_ms_p95: f32,
    frame_ms_p99: f32,
    frame_ms_max: f32,
    spikes: u32,
    rtt_ms: f32,
    rtt_ms_max: f32,
    corrections: u32,
    memory_mb: f32,
    entities: u32,
    detail: String,
) -> Result<(), String> {
    let (entity_id, world_id, role) = reporter(ctx)?;
    if role == rules::ROLE_CLIENT {
        spend_rate(ctx, entity_id, "report_perf")?;
    }
    let window_s = rules::sane(window_s, 0.0, rules::MAX_WINDOW_S);
    ctx.db.perf_report().insert(PerfReport {
        id: 0,
        at: ctx.timestamp,
        identity: ctx.sender(),
        entity_id,
        world_id,
        level: world_level_of(ctx, world_id),
        role,
        build: rules::cut(&build, rules::MAX_BUILD),
        platform: rules::cut(&platform, rules::MAX_PLATFORM),
        window_s,
        frames,
        fps: if window_s > 0.0 { frames as f32 / window_s } else { 0.0 },
        frame_ms_p50: rules::sane(frame_ms_p50, 0.0, 60_000.0),
        frame_ms_p95: rules::sane(frame_ms_p95, 0.0, 60_000.0),
        frame_ms_p99: rules::sane(frame_ms_p99, 0.0, 60_000.0),
        frame_ms_max: rules::sane(frame_ms_max, 0.0, 600_000.0),
        spikes,
        rtt_ms: rules::sane(rtt_ms, 0.0, 60_000.0),
        rtt_ms_max: rules::sane(rtt_ms_max, 0.0, 600_000.0),
        corrections,
        memory_mb: rules::sane(memory_mb, 0.0, 1_000_000.0),
        entities,
        detail: rules::cut(&detail, rules::MAX_DETAIL),
    });
    Ok(())
}

/// FEEDBACK: what a player noticed at `noticed_usec` (server time by their clock), in their words; who,
/// where and in what part of the game from the server's own rows. Logged as a warning too, so a host
/// watching the server's log sees it arrive.
#[reducer]
pub fn send_feedback(ctx: &ReducerContext, noticed_usec: i64, category: u8, text: String, build: String, platform: String, context: String) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("send_feedback: no player row")?;
    spend_rate(ctx, player.entity_id, "send_feedback")?;
    let text = rules::cut(text.trim(), rules::MAX_TEXT);
    let me = ctx.db.movement_state().entity_id().find(player.entity_id);
    let world_id = me.as_ref().map(|m| m.world_id).unwrap_or(DEFAULT_WORLD);
    let kind = ctx.db.entity().entity_id().find(player.entity_id).map(|e| e.kind).unwrap_or(0);
    let status = ctx.db.status_state().entity_id().find(player.entity_id).map(|r| r.status).unwrap_or(crate::status::NORMAL);
    let sess = ctx.db.session().world_id().find(world_id);
    let heard = ctx.timestamp.to_micros_since_unix_epoch();
    let row = ctx.db.feedback().insert(Feedback {
        id: 0,
        at: ctx.timestamp,
        noticed_at: Timestamp::from_micros_since_unix_epoch(rules::noticed_at(noticed_usec, heard)),
        identity: ctx.sender(),
        name: player.name.clone(),
        entity_id: player.entity_id,
        kind,
        status,
        pos: me.as_ref().map(|m| m.pos).unwrap_or(Vector3::ZERO),
        world_id,
        level: world_level_of(ctx, world_id),
        session_id: sess.as_ref().map(|s| s.id).unwrap_or(0),
        round: sess.as_ref().map(|s| s.round).unwrap_or(0),
        phase: sess.as_ref().map(|s| s.phase).unwrap_or(0),
        category: rules::category(category),
        text: text.clone(),
        build: rules::cut(&build, rules::MAX_BUILD),
        platform: rules::cut(&platform, rules::MAX_PLATFORM),
        context: rules::cut(&context, rules::MAX_CONTEXT),
    });
    log::warn!("FEEDBACK {} from {} ({}): {}", row.id, player.name, player.entity_id, text);
    Ok(())
}

/// Performance reports older than `PERF_KEEP_MICROS` (once a minute, with the action events' prune).
pub(crate) fn prune_perf(ctx: &ReducerContext) {
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    if (now / 1_000_000) % 60 != 0 {
        return;
    }
    let cutoff = Timestamp::from_micros_since_unix_epoch(now - rules::PERF_KEEP_MICROS);
    let stale: Vec<u64> = ctx.db.perf_report().at().filter(..cutoff).map(|r| r.id).collect();
    for id in stale {
        ctx.db.perf_report().id().delete(id);
    }
}

/// WHERE EVERYONE WAS (DECISIONS #276): an online player's place, noted every
/// `foundation.telemetry_where_s` seconds. The host's chronicle (`tools/chronicle.py`) is subscribed and
/// keeps each one on disk, so the database holds only the latest (one row a player) and the trail costs
/// nobody's bandwidth: `movement_state` changes with every step, this every few seconds. A player who goes
/// offline loses their row at the next note (the chronicle sees them leave).
#[table(accessor = where_sample)]
pub struct WhereSample {
    #[primary_key]
    pub entity_id: u64,
    pub world_id: u32,
    pub level: u8,
    pub pos: Vector3,
    pub yaw: f32,
    pub at: Timestamp,
}

/// Note where every online player is, when it is time (`rules::where_due`); called by the module's
/// once-a-second tick. The rule at 0 clears the notes and takes none.
pub(crate) fn sample_where(ctx: &ReducerContext) {
    let every = hot_number(ctx, crate::hot::foundation::TELEMETRY_WHERE_S);
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    if !(every > 0.0) {
        let all: Vec<u64> = ctx.db.where_sample().iter().map(|w| w.entity_id).collect();
        for id in all {
            ctx.db.where_sample().entity_id().delete(id);
        }
        return;
    }
    let last = ctx.db.where_sample().iter().map(|w| w.at.to_micros_since_unix_epoch()).max().unwrap_or(0);
    if !rules::where_due(now, last, every) {
        return;
    }
    let online: std::collections::HashSet<u64> = ctx.db.player().iter().filter(|p| p.online).map(|p| p.entity_id).collect();
    let gone: Vec<u64> = ctx.db.where_sample().iter().filter(|w| !online.contains(&w.entity_id)).map(|w| w.entity_id).collect();
    for id in gone {
        ctx.db.where_sample().entity_id().delete(id);
    }
    for id in online {
        let Some(m) = ctx.db.movement_state().entity_id().find(id) else { continue };
        let row = WhereSample { entity_id: id, world_id: m.world_id, level: world_level_of(ctx, m.world_id), pos: m.pos, yaw: m.yaw, at: ctx.timestamp };
        if ctx.db.where_sample().entity_id().find(id).is_some() {
            ctx.db.where_sample().entity_id().update(row);
        } else {
            ctx.db.where_sample().insert(row);
        }
    }
}
