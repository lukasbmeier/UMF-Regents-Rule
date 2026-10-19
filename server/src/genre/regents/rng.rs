//! The skilling minigames' seeded numbers: challenge.rs's xorshift32 and its seed fold, shared by every
//! model so each agrees with its GDScript twin (`SkillRandom`).

pub fn next_u32(state: &mut u32) -> u32 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    x
}

pub fn seed_state(seed: u64) -> u32 {
    let s = (seed ^ (seed >> 32)) as u32;
    if s == 0 { 1 } else { s }
}

/// A submission as the challenge carries it: flat groups of `arity` f32s, each a whole number inside
/// `lo..=hi` (a time, then its other values). None when it is not one: a ragged length, more groups than
/// `max_groups`, or a value that is not a whole number in range.
pub fn decode_groups(result: &[f32], arity: usize, max_groups: usize, lo: f32, hi: f32) -> Option<Vec<Vec<i64>>> {
    if arity == 0 || result.len() % arity != 0 || result.len() / arity > max_groups {
        return None;
    }
    let mut out = Vec::with_capacity(result.len() / arity);
    for g in result.chunks_exact(arity) {
        if g.iter().any(|v| !v.is_finite() || v.fract() != 0.0 || *v < lo || *v > hi) {
            return None;
        }
        out.push(g.iter().map(|v| *v as i64).collect());
    }
    Some(out)
}
