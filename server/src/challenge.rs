//! Challenge validators — pure functions re-simulated by the module to score a client-side
//! minigame (ARCHITECTURE §6, DECISIONS #19). The client plays the minigame locally and submits
//! only its inputs; the server recomputes the outcome from `seed` + `difficulty` and never trusts
//! a claimed score. This is the anti-cheat boundary for anything with economic consequences.
//!
//! PARITY RULES (AGENTS hard rule 7). This file has a GDScript twin at
//! `foundation/sim/challenge_model.gd` and both must agree to `max_err = 0` against
//! `shared/golden/challenge_timing.json`:
//!   1. f32 only, identical operation order. Every intermediate is rounded to f32 at each step;
//!      the GDScript side achieves that by doing the arithmetic in `Vector3` lanes, whose
//!      components are f32. Chaining ops in f64 and rounding once at the end is double-rounding
//!      and WILL drift.
//!   2. The PRNG emits 24 bits and divides by 2^24. Both are exactly representable in f32, so
//!      the unit value is bit-identical on both sides. Do not widen it to 32 bits: `u32 as f32`
//!      rounds above 2^24 and GDScript's int->float does not round the same way.
//!   3. Any change regenerates the golden file (see `shared/golden/GENERATE.md`).
//!
//! NO `spacetimedb` DEPENDENCY. Like `sim.rs`, this module is linked by the native golden test,
//! and depending on that crate drags the WASM host ABI into the test binary (DECISIONS #27).

/// `challenge.kind` values owned by the foundation. Genres number their own kinds from 100.
pub const KIND_TIMING_BAR: u8 = 0;

/// The first kind a genre may use. A kind at or above this is validated by the genre's own hook
/// (`game::validate_challenge`), not by `validate_challenge` here, and scores itself: the
/// foundation's generic award is for the foundation's own kinds only.
pub const KIND_GENRE_FROM: u8 = 100;

/// Rounds in one timing-bar challenge. Three so the whole scoring pass fits one Vector3 lane
/// on the GDScript side.
pub const TIMING_ROUNDS: usize = 3;

/// xorshift32. Chosen over anything fancier because it is a handful of integer ops that GDScript
/// can mirror exactly with a 32-bit mask.
#[inline]
fn next_u32(state: &mut u32) -> u32 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    x
}

/// Fold a 64-bit seed into a non-zero 32-bit state (xorshift is degenerate at zero).
///
/// Folding 64 bits into 32 necessarily collides: every seed whose high and low words are equal
/// lands on the same state, so seeds 0, 1 and u64::MAX all produce the same challenge (the
/// golden file pins this). That is acceptable because `session.seed` comes from timestamp
/// micros, whose low word is the fast-moving one — but a genre that seeds challenges from a
/// small counter should mix it first rather than assume distinct seeds give distinct games.
#[inline]
fn seed_state(seed: u64) -> u32 {
    let s = (seed ^ (seed >> 32)) as u32;
    if s == 0 {
        1
    } else {
        s
    }
}

/// Top 24 bits, scaled to [0,1). Exact in f32 — see parity rule 2.
#[inline]
fn unit_from(v: u32) -> f32 {
    ((v >> 8) as f32) / 16_777_216.0f32
}

/// The target centres a timing bar presents this round, derived from the seed alone so the
/// client cannot pick them and the server can recompute them.
pub fn timing_centers(seed: u64) -> [f32; TIMING_ROUNDS] {
    let mut st = seed_state(seed);
    let mut out = [0.0f32; TIMING_ROUNDS];
    for slot in out.iter_mut() {
        let u = unit_from(next_u32(&mut st));
        // Keep centres away from the rail ends so every target is reachable.
        *slot = 0.15f32 + u * 0.7f32;
    }
    out
}

/// Half-width of the hit window. Difficulty 0 is forgiving, 1 is tight.
///
/// RETUNED. The window was 0.30 - 0.22 * difficulty, which at the difficulty the fishing spots
/// actually produced was a target more than half the bar wide — three presses anywhere landed a
/// fish, so the minigame was a keypress tax rather than a game, and better line made a window
/// that was already unmissable slightly more unmissable. At 0.16 - 0.12 * difficulty an easy
/// target is 27% of the bar and a hard one 10%, so timing decides the catch and gear is worth
/// buying. Any change here regenerates `shared/golden/challenge/challenge_timing.json`.
#[inline]
pub fn timing_half_width(difficulty: f32) -> f32 {
    0.16f32 - 0.12f32 * difficulty
}

/// Re-simulate a challenge and score it.
///
/// `result` is the player's submission: one press position in [0,1] per round. Returns the
/// quality in [0,1], or `None` if the submission is malformed — a rejection, not a zero, so the
/// caller can tell "cheated/garbled" from "played badly".
pub fn validate_challenge(kind: u8, seed: u64, difficulty: f32, result: &[f32]) -> Option<f32> {
    if kind != KIND_TIMING_BAR {
        return None;
    }
    if result.len() != TIMING_ROUNDS {
        return None;
    }
    if !difficulty.is_finite() || difficulty < 0.0 || difficulty > 1.0 {
        return None;
    }
    for p in result {
        if !p.is_finite() || *p < 0.0 || *p > 1.0 {
            return None;
        }
    }

    let centers = timing_centers(seed);
    let half = timing_half_width(difficulty);

    // Per-round quality, in order. Each line is one f32 op so the GDScript lane matches.
    let mut q = [0.0f32; TIMING_ROUNDS];
    for i in 0..TIMING_ROUNDS {
        let d = (result[i] - centers[i]).abs();
        let t = d / half;
        let raw = 1.0f32 - t;
        q[i] = if raw < 0.0f32 {
            0.0f32
        } else if raw > 1.0f32 {
            1.0f32
        } else {
            raw
        };
    }

    // Accumulate left to right: ((q0 + q1) + q2) / 3.
    let s01 = q[0] + q[1];
    let s012 = s01 + q[2];
    Some(s012 / 3.0f32)
}

// =============================================================================
// THE SERVER-TIMED PRESS (docs/FOUNDATION_SYSTEMS.md milestone 4, DECISIONS #210)
// =============================================================================
//
// The timing bar above is judged from where the CLIENT says it stopped the marker: an outcome, which
// no validator may accept (OPEN_ITEMS A4). A timed press is judged by the SERVER's clock: the marker
// sweeps from a moment the server chose, the client sends only "pressed", and the server works out
// where the marker was when the player saw it: the press's arrival, less half the player's quickest
// measured round trip (the time it took to reach the server), capped by a rule. The client draws the
// same sweep from the server's clock and predicts its own result; the server's replaces it.

/// `challenge.kind` of a server-timed press.
pub const KIND_TIMED_PRESS: u8 = 1;

/// Where the marker is `elapsed_s` after it began to sweep: 0 at the start, 1 half a period later,
/// back to 0 at a full period (a triangle wave). 0 before it begins.
pub fn sweep_position(elapsed_s: f32, period_s: f32) -> f32 {
    if elapsed_s <= 0.0 || period_s <= 0.0 {
        return 0.0;
    }
    let phase = (elapsed_s / period_s).fract();
    let up = phase * 2.0f32;
    if up <= 1.0f32 { up } else { 2.0f32 - up }
}

/// How good one press is: 1 on the target's centre, falling to 0 at `half` from it.
pub fn press_quality(position: f32, center: f32, half: f32) -> f32 {
    if half <= 0.0 {
        return 0.0;
    }
    (1.0f32 - (position - center).abs() / half).clamp(0.0, 1.0)
}

/// How long a sweep takes at `difficulty` (0 easy, 1 hard), between the easy and the hard period.
pub fn sweep_period_s(difficulty: f32, easy_s: f32, hard_s: f32) -> f32 {
    let d = difficulty.clamp(0.0, 1.0);
    easy_s + (hard_s - easy_s) * d
}

/// The time a press is credited with, in ms: half the player's quickest measured round trip (how long
/// a press takes to reach the server), at most `cap_ms`; none until one has been measured.
pub fn press_credit_ms(min_rtt_ms: Option<u32>, cap_ms: u32) -> u32 {
    min_rtt_ms.map(|r| (r / 2).min(cap_ms)).unwrap_or(0)
}

/// A press arriving `arrived_ms` after the sweep began (negative: before), credited `credit_ms`:
/// when it is judged to have been made, and so where the marker was.
pub fn judged_position(arrived_ms: i64, credit_ms: u32, period_s: f32) -> (i64, f32) {
    let at = arrived_ms - credit_ms as i64;
    (at, sweep_position(at as f32 / 1000.0, period_s))
}
