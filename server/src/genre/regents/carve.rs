//! WOODWORKING'S CARVE, THE SERVER'S TWIN of `game/regents/skilling/woodworking/carve_model.gd` (`CarveModel`; Luke,
//! 2026-11-07: a vertical stave, wood off either side, so a bow or a staff may be asymmetric). Rows of a stave, each with
//! a left and a right edge out from the middle line; a cut takes one in (deep or fine), never back; the pattern laid on
//! at the start (no cuts while it is on; each lay after the first costs the ceiling); a cut mid-swing is held to the
//! swing's end (the latest wins); DONE sets it down. The rules are written out on `CarveModel`. Held to
//! `shared/golden/regents/carve.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

pub const DONE: i64 = 5000;
pub const LAY: i64 = 5001;
pub const LIFT: i64 = 5002;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CarveParams<'a> {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub start_half: i64,
    pub start_jitter: i64,
    pub deep_cut: i64,
    pub fine_cut: i64,
    pub left_outline: &'a [i64],
    pub right_outline: &'a [i64],
    pub outline_vary: i64,
    pub error_scale: i64,
    pub hide_outline: i64,
    pub lay_cost_pm: i64,
    /// 1: the seed may swap the two profiles (an unstrung bow's C bends left or right; Luke, 2026-11-07).
    pub mirror: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CarveResult {
    pub error: i64,
    pub cuts: i64,
    pub lays: i64,
    pub ceiling_pm: i64,
    pub score_pm: i64,
}

/// The round's blank and its profiles from the seed: (left edges, right edges, left targets, right targets).
pub fn start(seed: u64, p: &CarveParams) -> (Vec<i64>, Vec<i64>, Vec<i64>, Vec<i64>) {
    let n = p.left_outline.len();
    let mut st = seed_state(seed);
    let j = p.start_jitter.max(0);
    let mut draw = |m: i64| ((next_u32(&mut st) >> 8) as i64) % m.max(1);
    let (mut left, mut right) = (Vec::with_capacity(n), Vec::with_capacity(n));
    for _ in 0..n {
        left.push(p.start_half + draw(2 * j + 1) - j);
        right.push(p.start_half + draw(2 * j + 1) - j);
    }
    // The flip: one draw; with `mirror` on, an odd one swaps the profiles.
    let flip = draw(2) == 1 && p.mirror > 0;
    let (lb, rb) = if flip { (p.right_outline, p.left_outline) } else { (p.left_outline, p.right_outline) };
    let v = p.outline_vary.max(0);
    let mut bent = |base: &[i64]| -> Vec<i64> {
        let r0 = draw(n as i64);
        let a = draw(2 * v + 1) - v;
        (0..n).map(|i| base[i] + a * (3 - (i as i64 - r0).abs()).max(0) / 3).collect()
    };
    let tl = bent(lb);
    let tr = bent(rb);
    (left, right, tl, tr)
}

struct Run<'a> {
    p: &'a CarveParams<'a>,
    left: Vec<i64>,
    right: Vec<i64>,
    laid: bool,
    lays: i64,
    cuts: i64,
    next_ok: i64,
    held: Option<(i64, i64)>,
    done: bool,
}

impl Run<'_> {
    fn apply(&mut self, t: i64, code: i64) {
        let (kind, row) = (code / 1000, (code % 1000) as usize);
        let depth = if kind == 1 || kind == 3 { self.p.deep_cut } else { self.p.fine_cut };
        // Edges are signed (one may cross the middle line, for a curved stave); a cut stops at the other edge.
        if kind <= 2 {
            self.left[row] = (self.left[row] - depth).max(-self.right[row]);
        } else {
            self.right[row] = (self.right[row] - depth).max(-self.left[row]);
        }
        self.cuts += 1;
        self.next_ok = t + self.p.swing_ms;
    }

    fn settle(&mut self, t: i64) {
        if let Some((at, code)) = self.held {
            if at <= t {
                self.held = None;
                if at <= self.p.duration_ms && !self.done && !self.laid {
                    self.apply(at, code);
                }
            }
        }
    }
}

/// A whole round replayed from its inputs, (time, code) in the order sent, run to its end.
pub fn play(seed: u64, p: &CarveParams, inputs: &[(i64, i64)]) -> CarveResult {
    let (left, right, tl, tr) = start(seed, p);
    let n = left.len();
    let mut run = Run { p, left, right, laid: p.hide_outline > 0, lays: 0, cuts: 0, next_ok: 0, held: None, done: false };
    let mut last_t = -1i64;
    for &(t, code) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > p.duration_ms || run.done {
            continue;
        }
        run.settle(t);
        match code {
            DONE => {
                run.done = true;
                run.held = None;
            }
            LAY => {
                if p.hide_outline > 0 && !run.laid {
                    run.laid = true;
                    run.lays += 1;
                }
            }
            LIFT => run.laid = false,
            c if (1000..5000).contains(&c) && ((c % 1000) as usize) < n => {
                if run.laid {
                    continue;
                }
                if t < run.next_ok {
                    run.held = Some((run.next_ok, c));
                    continue;
                }
                run.apply(t, c);
            }
            _ => {}
        }
    }
    if !run.done {
        run.settle(p.duration_ms);
    }
    let error: i64 = (0..n).map(|i| (run.left[i] - tl[i]).abs() + (run.right[i] - tr[i]).abs()).sum();
    let raw = (1000 - error * 1000 / p.error_scale.max(1)).max(0);
    let ceiling = (1000 - run.lays * p.lay_cost_pm).max(0);
    CarveResult { error, cuts: run.cuts, lays: run.lays, ceiling_pm: ceiling, score_pm: raw.min(ceiling) }
}
