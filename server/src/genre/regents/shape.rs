//! SMITHING'S SHAPE TO THE OUTLINE, THE SERVER'S TWIN of `game/regents/skilling/smithing/shape_model.gd`
//! (`ShapeModel`): a strike beats a column of the hot bar down and pushes some into its neighbours; the
//! closer the bar ends to the part's outline, the better. Inputs are (time, column), -1 a reheat. Held to
//! `shared/golden/regents/shape.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShapeParams {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub heat_ms: i64,
    pub reheat_ms: i64,
    pub start_height: i64,
    pub start_jitter: i64,
    pub hammer_drop: i64,
    pub spread_pct: i64,
    pub outline: Vec<i64>,
    pub error_scale: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ShapeResult {
    pub strikes: i64,
    pub colds: i64,
    pub reheats: i64,
    pub error: i64,
    pub score_pm: i64,
}

/// The bar as it comes out of the fire: every column `start_height` and a little more from the seed.
pub fn start_heights(seed: u64, p: &ShapeParams) -> Vec<i64> {
    let mut st = seed_state(seed);
    p.outline.iter().map(|_| p.start_height + ((next_u32(&mut st) >> 8) as i64) % (p.start_jitter + 1)).collect()
}

struct Run<'a> {
    p: &'a ShapeParams,
    h: Vec<i64>,
    r: ShapeResult,
    hot_until: i64,
    next_ok: i64,
}

impl Run<'_> {
    fn strike(&mut self, t: i64, c: i64) {
        let p = self.p;
        if c == -1 {
            self.r.reheats += 1;
            self.next_ok = t + p.reheat_ms;
            self.hot_until = t + p.reheat_ms + p.heat_ms;
            return;
        }
        self.next_ok = t + p.swing_ms;
        if t >= self.hot_until {
            self.r.colds += 1;
            return;
        }
        let i = c as usize;
        let d = self.h[i].min(p.hammer_drop);
        self.h[i] -= d;
        let side = d * p.spread_pct / 100;
        if i > 0 {
            self.h[i - 1] += side;
        }
        if i + 1 < self.h.len() {
            self.h[i + 1] += side;
        }
        self.r.strikes += 1;
    }

    /// Land a held strike whose swing or reheat ended by `t`.
    fn settle(&mut self, held: &mut Option<(i64, i64)>, t: i64) {
        if let Some((at, c)) = *held {
            if at <= t {
                *held = None;
                if at <= self.p.duration_ms {
                    self.strike(at, c);
                }
            }
        }
    }
}

/// A whole round replayed from its strikes, (time, column) in the order sent. A strike during a swing or
/// a reheat is held (the latest) and lands when it ends.
pub fn play(seed: u64, p: &ShapeParams, inputs: &[(i64, i64)]) -> ShapeResult {
    let mut run = Run { p, h: start_heights(seed, p), r: ShapeResult::default(), hot_until: p.heat_ms, next_ok: 0 };
    let (mut held, mut last_t): (Option<(i64, i64)>, i64) = (None, -1);
    for &(t, c) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        run.settle(&mut held, t);
        if t < 0 || t > p.duration_ms || c < -1 || c >= run.h.len() as i64 {
            continue;
        }
        if t < run.next_ok {
            held = Some((run.next_ok, c));
            continue;
        }
        run.strike(t, c);
    }
    run.settle(&mut held, p.duration_ms);
    let (h, mut r) = (run.h, run.r);
    r.error = h.iter().zip(&p.outline).map(|(a, b)| (a - b).abs()).sum();
    r.score_pm = (1000 - r.error * 1000 / p.error_scale).max(0);
    r
}
