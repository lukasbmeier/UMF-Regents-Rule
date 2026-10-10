//! Challenges: issue, submit, prune (DECISIONS #19). Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// CHALLENGES (DECISIONS #19)
// =============================================================================

/// Default time a player has to complete a challenge.
pub(crate) const CHALLENGE_TTL_MICROS: i64 = 30_000_000;

/// Issue a challenge to an entity. Internal helper — genre reducers call this from whatever
/// action starts the minigame (fishing's `cast`, mining's `interact`).
///
/// The seed mixes the session seed, the entity and the exact issue time. The session seed alone
/// would let everyone in a match precompute each other's challenges; the timestamp is the part
/// the client cannot predict.
pub(crate) fn issue_challenge_internal(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    difficulty: f32,
    payload: String,
    ttl_micros: i64,
) -> Result<u64, String> {
    if !difficulty.is_finite() || !(0.0..=1.0).contains(&difficulty) {
        return Err(format!("difficulty {difficulty} out of range"));
    }
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    let session_seed = ctx
        .db
        .session()
        .world_id()
        .find(ent.world_id)
        .map(|s| s.seed)
        .unwrap_or(0);
    let now = ctx.timestamp.to_micros_since_unix_epoch() as u64;
    let seed = session_seed ^ entity_id.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ now;

    let row = ctx.db.challenge().insert(Challenge {
        id: 0,
        entity_id,
        kind,
        seed,
        difficulty,
        issued_at: ctx.timestamp,
        expires_at: ctx.timestamp + TimeDuration::from_micros(ttl_micros),
        payload,
    });
    if kind == crate::challenge::KIND_TIMED_PRESS {
        start_timed_press(ctx, &row);   // its sweep (DECISIONS #210)
    }
    Ok(row.id)
}

/// The genre layer's way to start a Challenge. Wraps the internal helper so `game/` never
/// depends on module-private functions — the hook surface stays small and documented.
///
/// A SERVER-TIMED PRESS since 0.37.0 (DECISIONS #210): the player presses, the server judges when.
/// (The timing bar it used to issue was judged from where the client said it stopped: an outcome.)
pub fn issue_challenge_for(
    ctx: &ReducerContext,
    entity_id: u64,
    difficulty: f32,
    payload: String,
) -> Result<u64, String> {
    issue_challenge_internal(
        ctx,
        entity_id,
        crate::challenge::KIND_TIMING_BAR,
        difficulty,
        payload,
        CHALLENGE_TTL_MICROS,
    )
}

/// Score a played FOUNDATION challenge (a timing bar, a timed press) for its player, and hand it to the
/// genres (`on_challenge_succeeded`). After the challenge is closed.
pub(crate) fn award_foundation_challenge(ctx: &ReducerContext, ch: &Challenge, quality: f32) {
    // ROUND, not truncate. `as i64` truncates, so a quality of 0.99999994 — one ULP
    // below a perfect play, which is all it takes for a press to be a hair off the
    // centre after a decimal round-trip — scored 99 instead of 100. Losing a whole
    // point to float noise is indistinguishable from a bug to a player.
    let score = (quality * 100.0f32).round() as i64;
    let members: Vec<SessionMember> = ctx.db.session_member().entity_id().filter(ch.entity_id).collect();
    for mut m in members {
        m.score += score;
        m.coins += score / 10;
        ctx.db.session_member().id().update(m);
    }
    log::info!("challenge {}: quality {quality:.4} -> score +{score}", ch.id);
    // Hand the result to the genre. It decides what the play MEANT — a fish, an ore,
    // nothing at all. Deliberately after the generic award and deliberately infallible:
    // a genre bug must not roll back a legitimate play.
    crate::game::on_challenge_succeeded(ctx, ch, quality);
}

/// Start a challenge of the GENRE's own kind (>= `KIND_GENRE_FROM`), with its own lifetime.
/// The genre judges it and pays it out through `game::resolve_challenge`; the foundation only
/// seeds it, keeps it private to its owner (RLS), expires it, and closes it.
pub fn issue_genre_challenge(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    payload: String,
    ttl_micros: i64,
) -> Result<u64, String> {
    if kind < crate::challenge::KIND_GENRE_FROM {
        return Err(format!("challenge kind {kind} belongs to the foundation"));
    }
    if ttl_micros <= 0 || ttl_micros > 600_000_000 {
        return Err(format!("challenge lifetime {ttl_micros} us is out of range"));
    }
    issue_challenge_internal(ctx, entity_id, kind, 0.0, payload, ttl_micros)
}

/// Dev/authority entry point so the challenge loop can be exercised before a genre exists.
#[reducer]
pub fn issue_challenge(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    difficulty: f32,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    issue_challenge_internal(ctx, entity_id, kind, difficulty, String::new(), CHALLENGE_TTL_MICROS)?;
    Ok(())
}

/// Submit a played challenge. The server re-simulates it; the client's own opinion of how well
/// it did is never transmitted, only its inputs.
///
/// The challenge is ALWAYS consumed, including when the submission is malformed, and the reducer
/// returns Ok so that the delete commits. Returning Err would roll the delete back and leave the
/// row in place, letting a client submit repeatedly against the same fixed seed and binary-search
/// the hit windows by watching its own score. One shot per issued challenge closes that.
#[reducer]
pub fn submit_challenge_result(
    ctx: &ReducerContext,
    challenge_id: u64,
    result: Vec<f32>,
) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let ch = ctx
        .db
        .challenge()
        .id()
        .find(challenge_id)
        .ok_or("no such challenge")?;
    if ch.entity_id != player.entity_id {
        return Err("not your challenge".into());
    }
    // A timed press is never submitted (DECISIONS #210): its presses are `challenge_press`. One that
    // is, is consumed and judged malformed below, so no outcome a client reports is ever accepted.

    // A GENRE KIND is the genre's to judge and to pay out. It is resolved while the challenge
    // still exists — before `on_challenge_closed` — because a genre keeps its own rows beside a
    // challenge (fishing's cast: what is on the line, when it bit) and cleans them up on close;
    // judging after the close would judge nothing. There is no generic award: what a genre play
    // is worth is the genre's business, and paying it twice was the old behaviour.
    if ch.kind >= crate::challenge::KIND_GENRE_FROM {
        let verdict = if ctx.timestamp > ch.expires_at {
            log::info!("challenge {challenge_id}: expired, no award");
            None
        } else {
            crate::game::resolve_challenge(ctx, &ch, &result)
        };
        ctx.db.challenge().id().delete(challenge_id);
        crate::game::on_challenge_closed(ctx, &ch);
        match verdict {
            Some(q) => log::info!("challenge {challenge_id}: resolved by the genre, quality {q:.3}"),
            None => log::info!("challenge {challenge_id}: the genre awarded nothing"),
        }
        return Ok(());
    }

    ctx.db.challenge().id().delete(challenge_id);
    forget_press(ctx, challenge_id);   // a timed press submitted as a bar: consumed, judged below as malformed
    // Whatever happens next — an award, an expiry, a rejected submission — this challenge is
    // over, and a genre that keeps something beside it has to hear so on every path.
    crate::game::on_challenge_closed(ctx, &ch);

    if ctx.timestamp > ch.expires_at {
        log::info!("challenge {challenge_id}: expired, no award");
        return Ok(());
    }

    match crate::challenge::validate_challenge(ch.kind, ch.seed, ch.difficulty, &result) {
        Some(quality) => award_foundation_challenge(ctx, &ch, quality),
        None => {
            // Malformed or out-of-range submission: a client bug or a probe. Consumed, no award.
            log::warn!(
                "challenge {challenge_id}: rejected submission from entity {} (len {})",
                ch.entity_id,
                result.len()
            );
        }
    }
    Ok(())
}

/// Scheduled cleanup so abandoned challenges do not accumulate.
#[reducer]
pub fn prune_challenges(ctx: &ReducerContext, _sched: ChallengePruneSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("prune_challenges: scheduler only".into());
    }
    let stale: Vec<Challenge> = ctx
        .db
        .challenge()
        .iter()
        .filter(|c| ctx.timestamp > c.expires_at)
        .collect();
    for ch in stale {
        ctx.db.challenge().id().delete(ch.id);
        forget_press(ctx, ch.id);
        crate::game::on_challenge_closed(ctx, &ch);
    }
    prune_presses(ctx);
    Ok(())
}
