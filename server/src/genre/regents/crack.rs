//! MINING'S CRACK THE ROCK (FOLLOW THE SEAM), THE SERVER'S TWIN of
//! `game/regents/skilling/mining/crack_model.gd` (`CrackModel`): a seam of notches runs across the rock
//! face (thousandths); a strike on the next notch opens the crack to it, anywhere else jars the pick; a
//! seam opened end to end splits the rock and the next begins. A strike during a swing or a split is held
//! (the latest) and lands when it ends; one while staggered is lost. Held to
//! `shared/golden/regents/crack.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CrackParams {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub stagger_ms: i64,
    pub split_ms: i64,
    pub notches: i64,
    pub bend_pm: i64,
    pub radius_pm: i64,
    pub margin_pm: i64,
    pub target_hits: i64,
    /// BRITTLE NOTCHES (band 2's new thing for mining, a test, 2026-11-07): how likely a notch is brittle (thousandths;
    /// 0: none), and how long the rock rings after a hit, during which a brittle notch struck cracks wrong (a jar).
    pub brittle_permille: i64,
    pub ring_ms: i64,
}

/// The brittle notches' own stream: the seed folded with this, so the seams never change.
pub const RING_SALT: u64 = 0x7269_6E67;

/// Which of the first `n` notches (over all seams) are brittle; a seam's first never is (none when `brittle_permille`
/// is 0).
pub fn brittle(seed: u64, p: &CrackParams, n: usize) -> Vec<bool> {
    if p.brittle_permille <= 0 {
        return vec![false; n];
    }
    let mut st = seed_state(seed ^ RING_SALT);
    (0..n)
        .map(|i| {
            if (i as i64) % p.notches == 0 {
                return false;
            }
            let r = next_u32(&mut st) as u64;
            (((r >> 8) * 1000) >> 24) < p.brittle_permille as u64
        })
        .collect()
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CrackResult {
    pub hits: i64,
    pub jars: i64,
    pub best_combo: i64,
    pub splits: i64,
    pub score_pm: i64,
}

/// Enough seams for any round: one notch a swing.
pub fn seam_count(p: &CrackParams) -> usize {
    ((p.duration_ms / p.swing_ms + 1) / p.notches + 2) as usize
}

/// `count` seams' notches from the seed: even seams top to bottom, odd ones left to right, each notch
/// wandering up to `bend_pm` across from the last, inside the margins. A prefix does not depend on `count`.
pub fn seams(seed: u64, p: &CrackParams, count: usize) -> Vec<(i64, i64)> {
    let (lo, hi) = (p.margin_pm, 1000 - p.margin_pm);
    let span = (hi - lo).max(0);
    let mut st = seed_state(seed);
    let mut out = Vec::with_capacity(count * p.notches as usize);
    for s in 0..count {
        let mut across = lo + ((next_u32(&mut st) >> 8) as i64) % (span + 1);
        for i in 0..p.notches {
            let along = lo + span * i / (p.notches - 1);
            if i > 0 {
                let r = ((next_u32(&mut st) >> 8) as i64) % (2 * p.bend_pm + 1);
                across = (across + r - p.bend_pm).clamp(lo, hi);
            }
            out.push(if s % 2 == 0 { (across, along) } else { (along, across) });
        }
    }
    out
}

struct Run<'a> {
    p: &'a CrackParams,
    pts: Vec<(i64, i64)>,
    brittle: Vec<bool>,
    last_hit: Option<i64>,
    k: usize,
    r: CrackResult,
    combo: i64,
    next_ok: i64,
    staggered: bool,
}

impl Run<'_> {
    fn strike(&mut self, t: i64, x: i64, y: i64) {
        let p = self.p;
        let at = self.pts[self.k % self.pts.len()];
        let (dx, dy) = (x - at.0, y - at.1);
        let ringing = self.brittle[self.k % self.pts.len()] && self.last_hit.is_some_and(|h| t < h + p.ring_ms);
        if dx * dx + dy * dy <= p.radius_pm * p.radius_pm && !ringing {
            self.last_hit = Some(t);
            self.r.hits += 1;
            self.combo += 1;
            self.r.best_combo = self.r.best_combo.max(self.combo);
            self.k += 1;
            self.staggered = false;
            if self.k as i64 % p.notches == 0 {
                self.r.splits += 1;
                self.next_ok = t + p.swing_ms.max(p.split_ms);
            } else {
                self.next_ok = t + p.swing_ms;
            }
            return;
        }
        self.r.jars += 1;
        self.combo = 0;
        self.next_ok = t + p.stagger_ms;
        self.staggered = true;
    }
}

/// A whole round replayed from its strikes, (time, x, y) in the order sent.
pub fn play(seed: u64, p: &CrackParams, inputs: &[(i64, i64, i64)]) -> CrackResult {
    let pts = seams(seed, p, seam_count(p));
    let brittle = brittle(seed, p, pts.len());
    let mut run = Run { p, pts, brittle, last_hit: None, k: 0, r: CrackResult::default(), combo: 0, next_ok: 0, staggered: false };
    let mut held: Option<(i64, i64, i64)> = None;
    let mut last_t = -1i64;
    let settle = |run: &mut Run, held: &mut Option<(i64, i64, i64)>, t: i64| {
        if let Some((at, x, y)) = *held {
            if at <= t {
                *held = None;
                if at <= p.duration_ms {
                    run.strike(at, x, y);
                }
            }
        }
    };
    for &(t, x, y) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        settle(&mut run, &mut held, t);
        if t < 0 || t > p.duration_ms || !(0..=1000).contains(&x) || !(0..=1000).contains(&y) {
            continue;
        }
        if t < run.next_ok {
            if !run.staggered {
                held = Some((run.next_ok, x, y));
            }
            continue;
        }
        run.strike(t, x, y);
    }
    settle(&mut run, &mut held, p.duration_ms);
    run.r.score_pm = (run.r.hits * 1000 / p.target_hits).min(1000);
    run.r
}
