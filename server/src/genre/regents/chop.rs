//! WOODCUTTING'S BRANCH DODGE, THE SERVER'S TWIN of `game/regents/skilling/woodcutting/chop_model.gd`
//! (`ChopModel`): a round decided by its seed, its tree's numbers and the player's inputs alone, each a
//! time since the round began and a side. A clean chop takes the bottom piece off; a branch at the
//! woodcutter's head (the piece above the cut) on the side chopped from hits instead: no chop, staggered.
//! Integers only, and challenge.rs's xorshift32, so the two agree exactly; both are held to
//! `shared/golden/regents/chop.json` (made by a third, Python version: `game/regents/tests/make_chop_golden.py`).
//! Change a rule in all three and regenerate.

pub const BRANCH_NONE: i32 = 0;
pub const BRANCH_LEFT: i32 = 1;
pub const BRANCH_RIGHT: i32 = 2;
/// Pieces of trunk beyond the most a round can chop (the view above the cut, on the client).
pub const VIEW_SEGMENTS: usize = 8;

/// One tree's round: the numbers of its `ChopParams` (the tree's content, `TreeDef.chop`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChopParams {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub stagger_ms: i64,
    pub branch_permille: i64,
    pub safe_segments: i64,
    pub target_chops: i64,
}

/// What a round came to.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ChopResult {
    pub clean: i64,
    pub hits: i64,
    pub best_combo: i64,
    /// Clean chops over the tree's target, in thousandths, at most 1000.
    pub score_pm: i64,
}

fn next_u32(state: &mut u32) -> u32 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    x
}

fn seed_state(seed: u64) -> u32 {
    let s = (seed ^ (seed >> 32)) as u32;
    if s == 0 { 1 } else { s }
}

/// The most clean chops a round of `p` could hold: one at 0 ms and one per swing after it.
pub fn max_chops(p: &ChopParams) -> i64 {
    p.duration_ms / p.swing_ms + 1
}

/// The trunk's first `n` pieces, bottom first. A prefix does not depend on `n`.
pub fn branches(seed: u64, p: &ChopParams, n: usize) -> Vec<i32> {
    let mut out = Vec::with_capacity(n);
    let mut st = seed_state(seed);
    for i in 0..n {
        if (i as i64) < p.safe_segments {
            out.push(BRANCH_NONE);
            continue;
        }
        let r = next_u32(&mut st) as u64;
        if ((r >> 8) * 1000) >> 24 >= p.branch_permille as u64 {
            out.push(BRANCH_NONE);
            continue;
        }
        let s = next_u32(&mut st);
        out.push(if (s >> 31) & 1 == 1 { BRANCH_RIGHT } else { BRANCH_LEFT });
    }
    out
}

/// A whole round replayed from its inputs, (time since the round began, side) in the order sent.
pub fn play(seed: u64, p: &ChopParams, inputs: &[(i64, i32)]) -> ChopResult {
    let seg = branches(seed, p, (max_chops(p) as usize) + 2 + VIEW_SEGMENTS);
    let (mut cut, mut r, mut combo, mut next_ok, mut last_t) = (0usize, ChopResult::default(), 0i64, 0i64, -1i64);
    for &(t, side) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > p.duration_ms || t < next_ok {
            continue;
        }
        if side != BRANCH_LEFT && side != BRANCH_RIGHT {
            continue;
        }
        let head = seg.get(cut + 1).copied().unwrap_or(BRANCH_NONE);
        if head == side {
            r.hits += 1;
            combo = 0;
            next_ok = t + p.stagger_ms;
            continue;
        }
        cut += 1;
        r.clean += 1;
        combo += 1;
        r.best_combo = r.best_combo.max(combo);
        next_ok = t + p.swing_ms;
    }
    r.score_pm = (r.clean * 1000 / p.target_chops).min(1000);
    r
}

/// A submission as the challenge carries it: flat (time, side) pairs as f32. None when it is not one:
/// an odd length, more pairs than `max_pairs`, or a value that is not a whole number in range.
pub fn decode_inputs(result: &[f32], max_pairs: usize) -> Option<Vec<(i64, i32)>> {
    if result.len() % 2 != 0 || result.len() / 2 > max_pairs {
        return None;
    }
    let whole = |v: f32, lo: f32, hi: f32| v.is_finite() && v.fract() == 0.0 && v >= lo && v <= hi;
    let mut out = Vec::with_capacity(result.len() / 2);
    for pair in result.chunks_exact(2) {
        if !whole(pair[0], -600_000.0, 600_000.0) || !whole(pair[1], -16.0, 16.0) {
            return None;
        }
        out.push((pair[0] as i64, pair[1] as i32));
    }
    Some(out)
}
