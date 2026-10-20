//! LOOT: WHO HURT WHAT, AND A PERSONAL ROLL FOR EACH OF THEM (DECISIONS #268; the tables and the roll
//! are `crate::loot`). Every damage with a source adds to a private tally (`damage_share`); a genre
//! that decides something is slain calls `drop_loot`, which rolls the table once for each PLAYER who
//! dealt at least `foundation.loot_share_min_pct` of the recent damage (hits older than
//! `foundation.loot_share_forget_s` do not count), with that player's own pity (`drop_pity`, kept by
//! identity), and gives each what they rolled. Until the ground items, every drop goes to the bag.

use super::*;

/// What one attacker has dealt one target (private: the server's own count).
#[table(accessor = damage_share)]
pub struct DamageShare {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub target_id: u64,
    pub source_id: u64,
    pub amount: f32,
    pub last_at: Timestamp,
}

/// A player's run of misses on one pity line (private).
#[table(accessor = drop_pity)]
pub struct DropPity {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub identity: Identity,
    pub table_id: u32,
    pub line: u32,
    pub rolls_since: u32,
}

/// `source_id` dealt `amount` to `target_id` (from `damage_entity`, the one place health changes).
pub(crate) fn record_damage(ctx: &ReducerContext, target_id: u64, source_id: u64, amount: f32) {
    if amount <= 0.0 || !amount.is_finite() || source_id == 0 || source_id == target_id {
        return;
    }
    if let Some(mut s) = ctx.db.damage_share().target_id().filter(target_id).find(|s| s.source_id == source_id) {
        s.amount += amount;
        s.last_at = ctx.timestamp;
        ctx.db.damage_share().id().update(s);
    } else {
        ctx.db.damage_share().insert(DamageShare { id: 0, target_id, source_id, amount, last_at: ctx.timestamp });
    }
}

/// Forget who hurt `target_id` (it was looted, it healed whole, it is gone).
pub fn forget_damage(ctx: &ReducerContext, target_id: u64) {
    let ids: Vec<u64> = ctx.db.damage_share().target_id().filter(target_id).map(|s| s.id).collect();
    for id in ids {
        ctx.db.damage_share().id().delete(id);
    }
}

/// The players who earned a roll of `target_id`'s loot now, most damage first.
pub fn loot_contributors(ctx: &ReducerContext, target_id: u64) -> Vec<u64> {
    let shares: Vec<(u64, f32, i64)> = ctx.db.damage_share().target_id().filter(target_id)
        .filter(|s| ctx.db.player().entity_id().find(s.source_id).is_some())
        .map(|s| (s.source_id, s.amount, s.last_at.to_micros_since_unix_epoch()))
        .collect();
    crate::loot::contributors(&shares, ctx.timestamp.to_micros_since_unix_epoch(),
        hot_number(ctx, crate::hot::foundation::LOOT_SHARE_MIN_PCT), hot_number(ctx, crate::hot::foundation::LOOT_SHARE_FORGET_S))
}

/// `target_id` IS SLAIN: roll loot table `table_id` once for each player who earned it (a personal roll,
/// their own pity), give each theirs, and forget the tally. Returns (player entity, what they got).
/// A table this game does not have, or nobody who earned it: nothing.
pub fn drop_loot(ctx: &ReducerContext, target_id: u64, table_id: u32) -> Vec<(u64, Vec<crate::loot::Drop>)> {
    let who = loot_contributors(ctx, target_id);
    forget_damage(ctx, target_id);
    if crate::loot::find(table_id).is_none() {
        return Vec::new();
    }
    let ramp = hot_number(ctx, crate::hot::foundation::LOOT_PITY_RAMP_X);
    let cap = hot_number(ctx, crate::hot::foundation::LOOT_PITY_CAP_X);
    let now = ctx.timestamp.to_micros_since_unix_epoch() as u64;
    let mut out = Vec::new();
    for player_entity in who {
        let Some(p) = ctx.db.player().entity_id().find(player_entity) else { continue };
        let pity_rows: Vec<DropPity> = ctx.db.drop_pity().identity().filter(p.identity).collect();
        let since = |t: u32, l: u32| pity_rows.iter().find(|r| r.table_id == t && r.line == l).map_or(0, |r| r.rolls_since);
        let mut n: u64 = 0;
        let seed = now ^ target_id.rotate_left(17) ^ player_entity.rotate_left(41) ^ (table_id as u64).rotate_left(5);
        let mut rng = || {
            n += 1;
            crate::loot::roll_from(seed ^ n.wrapping_mul(0xD6E8_FEB8_6659_FD93))
        };
        let (drops, pity) = crate::loot::roll(crate::loot::LOOT_TABLES, table_id, &mut rng, &since, ramp, cap);
        for pr in pity {
            let next = if pr.hit { 0 } else { since(pr.table, pr.line).saturating_add(1) };
            match pity_rows.iter().find(|r| r.table_id == pr.table && r.line == pr.line) {
                Some(r) => {
                    ctx.db.drop_pity().id().update(DropPity { id: r.id, identity: r.identity, table_id: r.table_id, line: r.line, rolls_since: next });
                }
                None => {
                    ctx.db.drop_pity().insert(DropPity { id: 0, identity: p.identity, table_id: pr.table, line: pr.line, rolls_since: next });
                }
            }
        }
        // ASSUMPTION: until the ground items (LOOT_AND_STYLES order 3), a line not marked to_bag goes to
        // the bag too.
        for d in &drops {
            if let Err(e) = grant_item_internal(ctx, player_entity, d.item, d.qty) {
                log::warn!("drop_loot: {player_entity} rolled {} x{} but: {e}", d.item, d.qty);
            }
        }
        out.push((player_entity, drops));
    }
    out
}

/// Tallies of targets nobody has hit for a long while (with the action events' prune, once a second).
pub(crate) fn prune_damage_shares(ctx: &ReducerContext) {
    let forget = hot_number(ctx, crate::hot::foundation::LOOT_SHARE_FORGET_S).max(1.0);
    let cutoff = ctx.timestamp - TimeDuration::from_micros((forget * 1_000_000.0) as i64 * 2);
    let stale: Vec<u64> = ctx.db.damage_share().iter().filter(|s| s.last_at < cutoff).map(|s| s.id).collect();
    for id in stale {
        ctx.db.damage_share().id().delete(id);
    }
}
