//! THE SERVER-TIMED PRESS (docs/FOUNDATION_SYSTEMS.md milestone 4, DECISIONS #210): a skill check
//! judged by the SERVER's clock. The client sends only "pressed" (`challenge_press`); where the
//! marker was is the server's to work out (`crate::challenge::judged_position`), from the press's
//! arrival less half the player's quickest round trip, which the server measured itself: the client
//! acknowledges each press challenge the moment it arrives (`challenge_seen`), and the time from
//! issuing it to hearing back is a round trip the server started and timed. A late ack only makes a
//! trip look slower, which the minimum ignores. `mod.rs` says why the module is wasm-only.

use super::*;
use crate::challenge::{KIND_TIMED_PRESS, TIMING_ROUNDS};

/// A TIMED PRESS BEING PLAYED (DECISIONS #210), beside its `challenge` row (whose shape no old client
/// may see change): the sweep, frozen when it was issued, so the client draws exactly what the server
/// judges by, and each press as judged. Private to its player, like the challenge (it would tell
/// another player nothing they could use, but the rule is one row-level filter for both).
#[table(accessor = timed_press, public)]
pub struct TimedPress {
    #[primary_key]
    pub challenge_id: u64,
    #[index(btree)]
    pub entity_id: u64,
    /// When the marker starts to sweep (issued, plus `foundation.press_lead_in_ms`).
    pub starts_at: Timestamp,
    /// A sweep across and back, in ms.
    pub period_ms: u32,
    /// The target's half-width (`crate::challenge::timing_half_width`).
    pub half_width: f32,
    /// How many presses it takes.
    pub rounds: u8,
    /// When the player's game acknowledged it, in ms after it was issued (0: not yet).
    pub seen_ms: u32,
    /// Each press as judged: ms after the sweep began (the credit taken off), the marker's position
    /// then, its quality.
    pub at_ms: Vec<i32>,
    pub positions: Vec<f32>,
    pub qualities: Vec<f32>,
    /// The credit each press was given (half the quickest round trip, capped), in ms.
    pub credit_ms: u32,
    /// Every press made: judged and scored (the challenge is gone; this stays a few seconds, so the
    /// player's game sees the last press judged).
    pub done: bool,
}

/// A client may see only its own presses.
#[client_visibility_filter]
pub(crate) const TIMED_PRESS_IS_PRIVATE: Filter = Filter::Sql(
    "SELECT c.* FROM timed_press c JOIN player p ON c.entity_id = p.entity_id WHERE p.identity = :sender",
);

/// Each player's quickest round trip the server has measured (`challenge_seen`). Private: the server's
/// own measurement, used for the credit.
#[table(accessor = client_rtt)]
pub struct ClientRtt {
    #[primary_key]
    pub entity_id: u64,
    pub min_ms: u32,
    pub samples: u32,
    pub at: Timestamp,
}

/// A CHECK THAT SCORES NOTHING (DECISIONS #219): a genre's skill check whose result is the genre's to
/// pay (an egg's wobble warms a nest, it is not points), so the foundation's award (score and coins
/// for every check) leaves it alone. Private; gone when its challenge closes.
#[table(accessor = unscored_press)]
pub struct UnscoredPress {
    #[primary_key]
    pub challenge_id: u64,
}

/// How long a judged press row stays after its challenge ended.
const PRESS_LINGER_MICROS: i64 = 5_000_000;
/// A round trip longer than this is not a measurement (a client that acked hours later).
const RTT_SANE_MS: u32 = 5_000;

/// The sweep for a new timed-press challenge, from the rules as they are now (frozen on the row).
pub(crate) fn start_timed_press(ctx: &ReducerContext, ch: &Challenge) {
    let lead = hot_number(ctx, crate::hot::foundation::PRESS_LEAD_IN_MS).max(0.0) as i64;
    let period = crate::challenge::sweep_period_s(ch.difficulty,
        hot_number(ctx, crate::hot::foundation::PRESS_SWEEP_EASY_S) as f32,
        hot_number(ctx, crate::hot::foundation::PRESS_SWEEP_HARD_S) as f32);
    ctx.db.timed_press().insert(TimedPress {
        challenge_id: ch.id,
        entity_id: ch.entity_id,
        starts_at: ch.issued_at + TimeDuration::from_micros(lead * 1000),
        period_ms: (period * 1000.0).round().max(1.0) as u32,
        half_width: crate::challenge::timing_half_width(ch.difficulty),
        rounds: TIMING_ROUNDS as u8,
        seen_ms: 0,
        at_ms: Vec::new(),
        positions: Vec::new(),
        qualities: Vec::new(),
        credit_ms: 0,
        done: false,
    });
}

fn ms_between(from: Timestamp, to: Timestamp) -> i64 {
    (to.to_micros_since_unix_epoch() - from.to_micros_since_unix_epoch()) / 1000
}

fn own_challenge(ctx: &ReducerContext, challenge_id: u64, verb: &str) -> Result<(u64, Challenge), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or(format!("{verb}: no player row"))?;
    let ch = ctx.db.challenge().id().find(challenge_id).ok_or(format!("{verb}: no such challenge"))?;
    if ch.entity_id != player.entity_id {
        return Err(format!("{verb}: not your challenge"));
    }
    Ok((player.entity_id, ch))
}

/// THE PLAYER'S GAME HAS IT: sent the moment a timed press arrives. The time since it was issued is a
/// round trip the server started and timed; the player's quickest is kept (`client_rtt`). Once per
/// challenge; nothing for another kind.
#[reducer]
pub fn challenge_seen(ctx: &ReducerContext, challenge_id: u64) -> Result<(), String> {
    let (entity_id, ch) = own_challenge(ctx, challenge_id, "challenge_seen")?;
    let Some(mut row) = ctx.db.timed_press().challenge_id().find(challenge_id) else { return Ok(()) };
    if row.seen_ms != 0 {
        return Ok(());
    }
    let rtt = ms_between(ch.issued_at, ctx.timestamp).clamp(1, u32::MAX as i64) as u32;
    row.seen_ms = rtt;
    ctx.db.timed_press().challenge_id().update(row);
    if rtt <= RTT_SANE_MS {
        match ctx.db.client_rtt().entity_id().find(entity_id) {
            Some(mut r) => {
                r.min_ms = r.min_ms.min(rtt);
                r.samples += 1;
                r.at = ctx.timestamp;
                ctx.db.client_rtt().entity_id().update(r);
            }
            None => {
                ctx.db.client_rtt().insert(ClientRtt { entity_id, min_ms: rtt, samples: 1, at: ctx.timestamp });
            }
        }
    }
    log::info!("challenge {challenge_id}: seen {rtt} ms after it was issued");
    Ok(())
}

/// THE PLAYER PRESSED. No payload: where the marker was is the server's to judge, from when this
/// arrived, less the credit for the trip here (`challenge::press_credit_ms`: half the quickest round
/// trip measured, at most `foundation.press_credit_cap_ms`). After the last press, the challenge is
/// scored and closed as a timing bar is. A press after the last, or for another kind, is refused.
#[reducer]
pub fn challenge_press(ctx: &ReducerContext, challenge_id: u64) -> Result<(), String> {
    let (entity_id, ch) = own_challenge(ctx, challenge_id, "challenge_press")?;
    spend_rate(ctx, entity_id, "challenge_press")?;
    if ch.kind != KIND_TIMED_PRESS {
        return Err(format!("challenge_press: challenge {challenge_id} is not a timed press (kind {})", ch.kind));
    }
    if ctx.timestamp > ch.expires_at {
        return Err("challenge_press: too late, it has expired".into());
    }
    let mut row = ctx.db.timed_press().challenge_id().find(challenge_id).ok_or("challenge_press: it has no sweep")?;
    if row.qualities.len() >= row.rounds as usize {
        return Err("challenge_press: every press is made".into());
    }
    let min_rtt = ctx.db.client_rtt().entity_id().find(entity_id).map(|r| r.min_ms);
    let cap = hot_number(ctx, crate::hot::foundation::PRESS_CREDIT_CAP_MS).max(0.0) as u32;
    let credit = crate::challenge::press_credit_ms(min_rtt, cap);
    let (at, pos) = crate::challenge::judged_position(ms_between(row.starts_at, ctx.timestamp), credit, row.period_ms as f32 / 1000.0);
    let round = row.qualities.len();
    let center = crate::challenge::timing_centers(ch.seed)[round.min(TIMING_ROUNDS - 1)];
    let q = crate::challenge::press_quality(pos, center, row.half_width);
    row.at_ms.push(at.clamp(i32::MIN as i64, i32::MAX as i64) as i32);
    row.positions.push(pos);
    row.qualities.push(q);
    row.credit_ms = credit;
    log::info!("challenge {challenge_id}: press {} at {at} ms (credit {credit} ms): marker {pos:.3}, target {center:.3}, quality {q:.3}",
        round + 1);
    if row.qualities.len() < row.rounds as usize {
        ctx.db.timed_press().challenge_id().update(row);
        return Ok(());
    }
    let quality = row.qualities.iter().sum::<f32>() / row.qualities.len() as f32;
    row.done = true;
    ctx.db.timed_press().challenge_id().update(row);
    ctx.db.challenge().id().delete(challenge_id);
    crate::game::on_challenge_closed(ctx, &ch);
    award_foundation_challenge(ctx, &ch, quality);
    Ok(())
}

/// A challenge is gone (scored, expired, its entity gone): its sweep goes too, after a moment if it
/// was played to the end (so its player's game sees the last press judged).
pub(crate) fn forget_press(ctx: &ReducerContext, challenge_id: u64) {
    ctx.db.unscored_press().challenge_id().delete(challenge_id);
    if let Some(row) = ctx.db.timed_press().challenge_id().find(challenge_id) {
        if !row.done {
            ctx.db.timed_press().challenge_id().delete(challenge_id);
        }
    }
}

/// HOW A TIMED PRESS WENT (DECISIONS #219), for a genre hearing it close (`on_challenge_closed`): the
/// mean quality of its presses when every one was made, None when it ended without them (it ran out of
/// time, its player left). Grade it with `crate::challenge::grade`.
pub fn press_result(ctx: &ReducerContext, challenge_id: u64) -> Option<f32> {
    let row = ctx.db.timed_press().challenge_id().find(challenge_id)?;
    if !row.done || row.qualities.is_empty() {
        return None;
    }
    Some(row.qualities.iter().sum::<f32>() / row.qualities.len() as f32)
}

/// From the prune: sweeps whose challenge has gone, played to the end a few seconds ago, or never.
pub(crate) fn prune_presses(ctx: &ReducerContext) {
    let gone: Vec<u64> = ctx.db.timed_press().iter()
        .filter(|r| ctx.db.challenge().id().find(r.challenge_id).is_none())
        .filter(|r| !r.done || ms_between(r.starts_at, ctx.timestamp) * 1000
            > (r.at_ms.last().copied().unwrap_or(0) as i64 + r.credit_ms as i64) * 1000 + PRESS_LINGER_MICROS)
        .map(|r| r.challenge_id)
        .collect();
    for id in gone {
        ctx.db.timed_press().challenge_id().delete(id);
    }
}
