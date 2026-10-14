//! WHAT A WORLD HEARS (DECISIONS #233, Fowl Play's OPEN_ITEMS C2): a noise is a row everyone in its
//! world receives as it is made: an egg cracking, a raid, a player's ping. What each kind sounds like,
//! how far it carries and who is shown where it was are content (`NoiseDef`, the client's); the server
//! says only that it happened, where, by whom and about what. Gone a few seconds later: a noise is heard
//! when it is made, not by whoever arrives after.
//!
//! A genre makes its own (`make_noise`, numbered from 100: its `NoiseDef.kind`s). A player makes only a
//! ping (`ping`): kind 1, at a place within reach of them, at the rate `shared/rules.json` allows.

use super::*;

/// How long a noise's row stays (its sound is played as it arrives).
pub const NOISE_TTL_MICROS: i64 = 10_000_000;
/// The foundation's noise kinds: a player's ping. A genre numbers its own from `NOISE_GENRE_FROM`.
pub const NOISE_PING: u16 = 1;
pub const NOISE_GENRE_FROM: u16 = 100;
/// How far from themselves a player may ping (they ping where they look).
pub const PING_RANGE_M: f32 = 80.0;

#[table(accessor = noise, public)]
pub struct Noise {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub kind: u16,
    pub pos: Vector3,
    /// Who made it (0: the world itself, a genre's rule).
    pub source_id: u64,
    /// What it is about (a ping at the wolf, a nest that cracked; 0: a place).
    pub target_id: u64,
    pub at: Timestamp,
}

/// MAKE A NOISE in `world_id`, for code that has already decided it happened (a genre's rule). Its id.
pub fn make_noise(ctx: &ReducerContext, world_id: u32, kind: u16, pos: Vector3, source_id: u64, target_id: u64) -> u64 {
    ctx.db.noise().insert(Noise { id: 0, world_id, kind, pos, source_id, target_id, at: ctx.timestamp }).id
}

/// A PLAYER'S PING (a hen's Bawk): a noise of kind 1 where they point, about what they point at, if
/// anything. Not from someone out of the game or watching (out, got away), not further than
/// `PING_RANGE_M`, not at something in another world, and no faster than the `ping` rate.
#[reducer]
pub fn ping(ctx: &ReducerContext, pos: Vector3, target_id: u64) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("ping: no player row")?;
    let me = ctx.db.movement_state().entity_id().find(player.entity_id).ok_or("ping: you have no body")?;
    let status = ctx.db.status_state().entity_id().find(player.entity_id).map(|r| r.status).unwrap_or(crate::status::NORMAL);
    if matches!(status, crate::status::OUT | crate::status::ESCAPED) {
        return Err("ping: not while you are watching".into());
    }
    let (dx, dy, dz) = (pos.x - me.pos.x, pos.y - me.pos.y, pos.z - me.pos.z);
    if (dx * dx + dy * dy + dz * dz).sqrt() > PING_RANGE_M {
        return Err(format!("ping: further than {PING_RANGE_M} m from you"));
    }
    if target_id != 0 && ctx.db.entity().entity_id().find(target_id).is_none_or(|e| e.world_id != me.world_id) {
        return Err("ping: nothing like that here".into());
    }
    spend_rate(ctx, player.entity_id, "ping")?;
    make_noise(ctx, me.world_id, NOISE_PING, pos, player.entity_id, target_id);
    Ok(())
}

/// Noises older than `NOISE_TTL_MICROS` (with the action events' prune).
pub(crate) fn prune_noise(ctx: &ReducerContext) {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(NOISE_TTL_MICROS);
    let stale: Vec<u64> = ctx.db.noise().iter().filter(|n| n.at < cutoff).map(|n| n.id).collect();
    for id in stale {
        ctx.db.noise().id().delete(id);
    }
}
