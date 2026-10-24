//! THE SERVER PUSHES PEOPLE AND BODIES (FOUNDATION_SYSTEMS milestone 15, DECISIONS #251; the rules are
//! `crate::push`). A genre writes a push (`push_entity`): a row everyone in the world receives. The
//! pushed player's own client adds it to their velocity in their prediction (and carries its sideways
//! speed a while); the module lets them move that much faster while it lasts (`push_limits`, in the
//! movement tick; `foundation.push_grace_s` longer, for the rows' lag). A body's push is
//! applied by the world's referee, which flies it. Gone a few seconds later, like a noise.

use super::*;

/// How long a push's row stays.
pub const PUSH_TTL_MICROS: i64 = 5_000_000;

#[table(accessor = push, public)]
pub struct Push {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    /// Who or what is pushed (a player, a body).
    #[index(btree)]
    pub entity_id: u64,
    /// The change of velocity, m/s.
    pub vel: Vector3,
    /// What pushed them (a player, a body; 0: the world).
    pub by_id: u64,
    pub at: Timestamp,
}

/// PUSH `entity_id` by `vel` (m/s), for code that has already decided it happened (a genre's rule):
/// clamped to `crate::push::MAX_PUSH_MPS`. Its id; Err for an entity that is not there or a push that is
/// not a number.
pub fn push_entity(ctx: &ReducerContext, entity_id: u64, vel: Vector3, by_id: u64) -> Result<u64, String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("push: no such entity")?;
    let vel = crate::push::bounded(vel).ok_or("push: a push must be finite")?;
    Ok(ctx.db.push().insert(Push { id: 0, world_id: ent.world_id, chunk: chunk_of_entity(ctx, entity_id), entity_id, vel, by_id, at: ctx.timestamp }).id)
}

/// `limits` widened by the pushes `entity_id` is under (`crate::push::widened`).
pub fn push_limits(ctx: &ReducerContext, entity_id: u64, limits: crate::content::MovementLimits) -> crate::content::MovementLimits {
    let grace = hot_number(ctx, crate::hot::foundation::PUSH_GRACE_S) as f32;
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    crate::push::widened(limits, ctx.db.push().entity_id().filter(entity_id)
        .map(|p| (p.vel, ((now - p.at.to_micros_since_unix_epoch()).max(0) as f32) / 1_000_000.0)), grace)
}

/// Dev/test helper: push an entity, as a genre would. Gated like `teleport` (`require_dev_tools`).
#[reducer]
pub fn dev_push(ctx: &ReducerContext, entity_id: u64, vel: Vector3) -> Result<(), String> {
    require_dev_tools(ctx, "dev_push")?;
    push_entity(ctx, entity_id, vel, 0).map(|_| ())
}

/// Pushes older than `PUSH_TTL_MICROS` (with the action events' prune).
pub(crate) fn prune_pushes(ctx: &ReducerContext) {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(PUSH_TTL_MICROS);
    let stale: Vec<u64> = ctx.db.push().iter().filter(|p| p.at < cutoff).map(|p| p.id).collect();
    for id in stale {
        ctx.db.push().id().delete(id);
    }
}
