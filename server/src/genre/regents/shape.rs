//! SMITHING'S SHAPE TO THE OUTLINE, THE SERVER'S TWIN of `game/regents/skilling/smithing/shape_model.gd`
//! (`ShapeModel`, which says every rule): a strike beats a column of the hot bar down and pushes some into its
//! neighbors; the closer the bar ends to the round's outline, the better. Inputs are (time, column): -1 a reheat,
//! `TAP + c` a light tap, `DONE` set the part down, `LAY` / `LIFT` the template. The bands' rules (2026-11-05: heats
//! that cost the ceiling, the template, a varying outline, red strikes that crack, the quench) are each off at 0,
//! so every round from before them replays unchanged. Held to `shared/golden/regents/shape.json`
//! (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

/// A light tap on column c is sent as column `TAP + c`.
pub const TAP: i64 = 1000;
/// Set the part down (and quench it); lay the template on; lift it off.
pub const DONE: i64 = 2000;
pub const LAY: i64 = 2001;
pub const LIFT: i64 = 2002;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShapeParams {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub heat_ms: i64,
    pub reheat_ms: i64,
    pub start_height: i64,
    pub start_jitter: i64,
    pub hammer_drop: i64,
    pub spread_pct: i64,
    pub tap_drop: i64,
    pub tap_spread_pct: i64,
    pub outline: Vec<i64>,
    pub error_scale: i64,
    pub max_reheats: i64,
    pub reheat_cost_pm: i64,
    pub hide_outline: i64,
    pub lay_cost_pm: i64,
    pub outline_vary: i64,
    pub red_ms: i64,
    pub crack_cost_pm: i64,
    pub quench_lo_pm: i64,
    pub quench_hi_pm: i64,
    pub quench_bonus_pm: i64,
    pub quench_loss_pm: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ShapeResult {
    pub strikes: i64,
    pub colds: i64,
    pub reheats: i64,
    pub lays: i64,
    pub cracks: i64,
    pub error: i64,
    pub ceiling_pm: i64,
    pub quench_pm: i64,
    pub score_pm: i64,
}

/// The bar as it comes out of the fire: every column `start_height` and a little more from the seed.
pub fn start_heights(seed: u64, p: &ShapeParams) -> Vec<i64> {
    let mut st = seed_state(seed);
    p.outline.iter().map(|_| p.start_height + ((next_u32(&mut st) >> 8) as i64) % (p.start_jitter + 1)).collect()
}

/// The round's outline: the part's, moved by up to `outline_vary` in three smooth bumps from the seed (after the
/// bar's own draws), the total kept.
pub fn round_outline(seed: u64, p: &ShapeParams) -> Vec<i64> {
    let n = p.outline.len();
    let mut out = p.outline.clone();
    if p.outline_vary <= 0 || n == 0 {
        return out;
    }
    let mut st = seed_state(seed);
    for _ in 0..n {
        next_u32(&mut st);
    }
    let mut offs = vec![0i64; n];
    for _ in 0..3 {
        let c = (next_u32(&mut st) >> 8) as i64 % n as i64;
        let a = (next_u32(&mut st) >> 8) as i64 % (2 * p.outline_vary + 1) - p.outline_vary;
        for j in -2i64..=2 {
            let k = c + j;
            if k >= 0 && k < n as i64 {
                offs[k as usize] += (if a >= 0 { 1 } else { -1 }) * (a.abs() * (3 - j.abs()) / 3);
            }
        }
    }
    let mut total = 0;
    for i in 0..n {
        out[i] = (p.outline[i] + offs[i]).max(1);
        total += out[i] - p.outline[i];
    }
    let mut at = ((next_u32(&mut st) >> 8) as i64 % n as i64) as usize;
    for _ in 0..100_000 {
        if total == 0 {
            break;
        }
        if total > 0 && out[at] > 1 {
            out[at] -= 1;
            total -= 1;
        } else if total < 0 {
            out[at] += 1;
            total += 1;
        }
        at = (at + 1) % n;
    }
    out
}

struct Run<'a> {
    p: &'a ShapeParams,
    h: Vec<i64>,
    r: ShapeResult,
    hot_until: i64,
    next_ok: i64,
    laid: bool,
}

impl Run<'_> {
    fn valid(&self, c: i64) -> bool {
        let (p, n) = (self.p, self.h.len() as i64);
        if c >= DONE {
            return if c == DONE { p.max_reheats > 0 } else { p.hide_outline > 0 && (c == LAY || c == LIFT) };
        }
        if c >= TAP {
            return p.tap_drop > 0 && c - TAP < n;
        }
        (-1..n).contains(&c)
    }

    fn strike(&mut self, t: i64, c: i64) {
        let p = self.p;
        if c == -1 {
            if p.max_reheats > 0 && self.r.reheats >= p.max_reheats {
                return;
            }
            self.r.reheats += 1;
            self.next_ok = t + p.reheat_ms;
            self.hot_until = t + p.reheat_ms + p.heat_ms;
            return;
        }
        if self.laid {
            return; // no strikes while the template is on the bar
        }
        self.next_ok = t + p.swing_ms;
        if t >= self.hot_until {
            self.r.colds += 1;
            return;
        }
        if t >= self.hot_until - p.red_ms {
            self.r.cracks += 1; // struck red: it does not move, it cracks
            return;
        }
        let tap = c >= TAP;
        let i = (if tap { c - TAP } else { c }) as usize;
        let d = self.h[i].min(if tap { p.tap_drop } else { p.hammer_drop });
        self.h[i] -= d;
        let side = d * (if tap { p.tap_spread_pct } else { p.spread_pct }) / 100;
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

    fn heat_pm(&self, t: i64) -> i64 {
        if self.hot_until <= t { 0 } else { ((self.hot_until - t) * 1000 / self.p.heat_ms).min(1000) }
    }
}

/// A whole round replayed from its inputs, (time, column) in the order sent. A strike during a swing or a reheat
/// is held (the latest) and lands when it ends; setting down and the template are instant; after the part is set
/// down, nothing counts.
pub fn play(seed: u64, p: &ShapeParams, inputs: &[(i64, i64)]) -> ShapeResult {
    let mut run = Run {
        p,
        h: start_heights(seed, p),
        r: ShapeResult::default(),
        hot_until: p.heat_ms,
        next_ok: 0,
        laid: p.hide_outline > 0,
    };
    let outline = round_outline(seed, p);
    let (mut held, mut last_t, mut done): (Option<(i64, i64)>, i64, i64) = (None, -1, -1);
    for &(t, c) in inputs {
        if t < last_t || done >= 0 {
            continue;
        }
        last_t = t;
        run.settle(&mut held, t);
        if t < 0 || t > p.duration_ms || !run.valid(c) {
            continue;
        }
        if c == DONE {
            held = None;
            done = t;
            continue;
        }
        if c == LAY || c == LIFT {
            if run.laid != (c == LAY) {
                run.laid = c == LAY;
                run.r.lays += i64::from(c == LAY);
            }
            continue;
        }
        if t < run.next_ok {
            held = Some((run.next_ok, c));
            continue;
        }
        run.strike(t, c);
    }
    if done < 0 {
        run.settle(&mut held, p.duration_ms);
    }
    let mut r = run.r;
    r.error = run.h.iter().zip(&outline).map(|(a, b)| (a - b).abs()).sum();
    r.ceiling_pm = (1000 - r.reheats * p.reheat_cost_pm - r.lays * p.lay_cost_pm - r.cracks * p.crack_cost_pm).max(0);
    if p.quench_hi_pm > 0 {
        let h = run.heat_pm(if done >= 0 { done } else { p.duration_ms });
        let (lo, hi) = (p.quench_lo_pm, p.quench_hi_pm);
        r.quench_pm = if (lo..=hi).contains(&h) {
            p.quench_bonus_pm
        } else {
            let dist = if h < lo { lo - h } else { h - hi };
            -p.quench_loss_pm.min(dist * p.quench_loss_pm / (hi - lo).max(1))
        };
    }
    let raw = (1000 - r.error * 1000 / p.error_scale).max(0);
    r.score_pm = (raw + r.quench_pm).min(r.ceiling_pm).max(0);
    r
}
