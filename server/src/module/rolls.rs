//! THE DODGE ROLL ON THE SERVER (DECISIONS #309): an ability whose content `rolls` (`crate::roll::ROLLS`) is
//! checked (not in the air, unless it may) and, once used, put on its user: its status as an EFFECT for its
//! length (a status that is not `hittable`: nothing a referee judges hits them), and the moment they PRESSED it as
//! they saw it, kept in `roll_state` so a hit that landed while the roll was on its way is judged against it
//! (`rolled_clear`). Every genre then hears it (`Genre::on_roll`): what else a roll does is theirs (a swing
//! canceled, a block lowered, a waiting hit taken back). The movement is the user's own dash, which their client
//! predicts and the module bounds as any. `mod.rs` says why the module is wasm-only.

use super::*;

/// AN ENTITY'S LAST ROLL (DECISIONS #309): which, when it arrived, when its player pressed it as they saw it,
/// and how long it lasts. Private: the server's own judging; clients see the roll's effect (`status_effect`).
/// A side table: no table any old client reads changed shape.
#[table(accessor = roll_state)]
pub struct RollState {
    #[primary_key]
    pub entity_id: u64,
    pub world_id: u32,
    pub ability_id: u32,
    /// When it arrived here.
    pub at: Timestamp,
    /// When it was pressed, on the server's clock of what its player saw (`roll::seen_us`), in micros.
    pub seen_us: i64,
    /// Its length (ms), as it was when it began (its hot rule may change later).
    pub ms: u32,
    /// The status that holds its user for it (an effect).
    pub status: u8,
}

/// The roll `ability_id` is, if it is one (`roll::ROLLS`).
pub fn roll_of(ability_id: u32) -> Option<&'static crate::roll::RollSeed> {
    crate::roll::find(ability_id)
}

/// A roll's length now (ms): its hot rule's value when it names one, else its content's.
pub fn roll_ms(ctx: &ReducerContext, seed: &crate::roll::RollSeed) -> u32 {
    let rule = if seed.ms_rule.is_empty() { None } else { crate::hot::find(seed.ms_rule) };
    crate::roll::length_ms(seed, rule.map(|r| hot_number(ctx, r)))
}

/// Ok when `actor` may begin roll `seed` now: on the ground, unless it may roll in the air ("no roll in the air":
/// its client holds the press until it lands). Only a player is held to it: a referee drives a bot's body itself.
pub(crate) fn may_roll(ctx: &ReducerContext, actor: u64, seed: &crate::roll::RollSeed) -> Result<(), String> {
    if seed.in_air || ctx.db.player().entity_id().find(actor).is_none() {
        return Ok(());
    }
    if ctx.db.movement_state().entity_id().find(actor).is_some_and(|m| !m.grounded) {
        return Err("use_ability: no roll in the air".into());
    }
    Ok(())
}

/// `actor` ROLLED (`seed`, already checked and its cooldown set): its status on them as an effect for its length,
/// the moment they pressed it as they saw it kept, and every genre told. `view_delay_ms`: how far behind the server
/// its player sees everyone, as their client said with the use (0 from a build before `use_ability_seen`).
pub(crate) fn begin_roll(ctx: &ReducerContext, actor: u64, seed: &crate::roll::RollSeed, view_delay_ms: u32) {
    let ms = roll_ms(ctx, seed);
    let min_rtt = ctx.db.client_rtt().entity_id().find(actor).map(|r| r.min_ms);
    let credit = crate::challenge::press_credit_ms(min_rtt, hot_number(ctx, crate::hot::foundation::PRESS_CREDIT_CAP_MS).max(0.0) as u32);
    let cap = hot_number(ctx, crate::hot::foundation::REWIND_MAX_MS).clamp(0.0, 1000.0) as u32;
    let seen_us = crate::roll::seen_us(ctx.timestamp.to_micros_since_unix_epoch(), credit, view_delay_ms, cap);
    let world_id = ctx.db.entity().entity_id().find(actor).map(|e| e.world_id).unwrap_or(0);
    let row = RollState { entity_id: actor, world_id, ability_id: seed.ability_id, at: ctx.timestamp, seen_us, ms, status: seed.status };
    if ctx.db.roll_state().entity_id().find(actor).is_some() {
        ctx.db.roll_state().entity_id().update(row);
    } else {
        ctx.db.roll_state().insert(row);
    }
    if ms > 0 {
        if let Err(e) = add_effect_internal(ctx, actor, seed.status, ms, actor) {
            log::warn!("entity {actor} rolled, but: {e}");
        }
    }
    log::info!("entity {actor} rolled ({}): {ms} ms, pressed {} ms before it arrived", seed.ability_id,
        (ctx.timestamp.to_micros_since_unix_epoch() - seen_us) / 1000);
    let kind = ctx.db.entity().entity_id().find(actor).map(|e| e.kind).unwrap_or(0);
    crate::game::on_roll(ctx, actor, kind, seed.ability_id, seen_us, ms);
}

/// Whether `entity_id`'s last roll, judged where its player pressed it, CLEARS a hit that landed at `land_us`
/// (server micros): begun before it landed (or at most `foundation.roll_late_ms` after) and still rolling then.
/// What a genre asks of a hit it judges itself (a hit held for a parry, one dealt to be taken back); the module
/// asks it of every hit a referee reports (`resolve_action`).
pub fn rolled_clear(ctx: &ReducerContext, entity_id: u64, land_us: i64) -> bool {
    let Some(r) = ctx.db.roll_state().entity_id().find(entity_id) else { return false };
    let late = hot_number(ctx, crate::hot::foundation::ROLL_LATE_MS).max(0.0) as u32;
    crate::roll::clears(r.seen_us, land_us, r.ms, late)
}

/// Whether `entity_id` is rolling now: under its last roll's status, as an effect.
pub fn is_rolling(ctx: &ReducerContext, entity_id: u64) -> bool {
    ctx.db.roll_state().entity_id().find(entity_id)
        .is_some_and(|r| ctx.db.status_effect().entity_id().filter(entity_id).any(|e| e.status == r.status))
}

/// An entity is gone: its roll with it.
pub(crate) fn forget_roll(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.roll_state().entity_id().delete(entity_id);
}
