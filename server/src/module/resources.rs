//! RESOURCES: AN ENTITY'S POOLS, SPENT (DECISIONS #270; what each pool is and how it fills:
//! `crate::resource`). A genre gives an entity a pool (`ensure_resource`: Regent's Rule's staff gives
//! mana) and spends it when it acts (`spend_resource`, refused when short). A row holds what the pool
//! held after its last spend and when (`stored`, `at`); nothing ticks: what it holds now is
//! `resource::level` from there, worked out here and on every client alike.

use super::*;

#[table(accessor = resource_state, public)]
pub struct ResourceState {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// Its `ResourceDef`'s content id.
    pub resource_id: u32,
    /// What it held at `at` (after its last spend).
    pub stored: f32,
    pub at: Timestamp,
}

fn seconds_since(ctx: &ReducerContext, at: Timestamp) -> f32 {
    ((ctx.timestamp.to_micros_since_unix_epoch() - at.to_micros_since_unix_epoch()) as f64 / 1_000_000.0) as f32
}

/// `entity_id` has pool `resource_id` (full, when it had none; as it was, when it had one). Err for a
/// resource this game does not have, or an entity that is not there.
pub fn ensure_resource(ctx: &ReducerContext, entity_id: u64, resource_id: u32) -> Result<(), String> {
    let seed = crate::resource::find(resource_id).ok_or(format!("no resource {resource_id} in this game"))?;
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("ensure_resource: no such entity")?;
    if ctx.db.resource_state().entity_id().filter(entity_id).any(|r| r.resource_id == resource_id) {
        return Ok(());
    }
    ctx.db.resource_state().insert(ResourceState { id: 0, entity_id, world_id: ent.world_id, resource_id, stored: seed.max, at: ctx.timestamp });
    Ok(())
}

/// What `entity_id`'s pool `resource_id` holds now; None when it has none.
pub fn resource_now(ctx: &ReducerContext, entity_id: u64, resource_id: u32) -> Option<f32> {
    let seed = crate::resource::find(resource_id)?;
    let r = ctx.db.resource_state().entity_id().filter(entity_id).find(|r| r.resource_id == resource_id)?;
    Some(crate::resource::level_of(seed, r.stored, seconds_since(ctx, r.at)))
}

/// SPEND `amount` of `entity_id`'s pool `resource_id`: refused, and nothing spent, when it holds less
/// (or has none). Spending starts a fight's slower filling.
pub fn spend_resource(ctx: &ReducerContext, entity_id: u64, resource_id: u32, amount: f32) -> Result<(), String> {
    let seed = crate::resource::find(resource_id).ok_or(format!("no resource {resource_id} in this game"))?;
    let mut r = ctx.db.resource_state().entity_id().filter(entity_id).find(|r| r.resource_id == resource_id)
        .ok_or(format!("no {}", seed.key))?;
    if !amount.is_finite() || amount < 0.0 {
        return Err("spend_resource: a cost must be a number, 0 or more".into());
    }
    let now = crate::resource::level_of(seed, r.stored, seconds_since(ctx, r.at));
    if now + 1e-4 < amount {
        return Err(format!("not enough {} ({:.0} of {:.0})", seed.key, now, amount));
    }
    r.stored = now - amount;
    r.at = ctx.timestamp;
    ctx.db.resource_state().id().update(r);
    Ok(())
}

/// An entity's pools, as it goes.
pub(crate) fn forget_resources(ctx: &ReducerContext, entity_id: u64) {
    let ids: Vec<u64> = ctx.db.resource_state().entity_id().filter(entity_id).map(|r| r.id).collect();
    for id in ids {
        ctx.db.resource_state().id().delete(id);
    }
}
