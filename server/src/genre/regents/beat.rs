//! SMELTING AS A RHYTHM TRACK, THE SERVER'S TWIN of `game/regents/skilling/smelting/beat_model.gd` (`BeatModel`;
//! Luke, 2026-11-07: "Full rhythm track"): notes on a seeded beat, pressed (DOWN 1) and let go (UP 2), the long
//! draws held; a press on no note costs; then the pour (as `smelt`). The rules are written out on `BeatModel`.
//! Held to `shared/golden/regents/beat.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

pub const TICK_MS: i64 = 50;
pub const DOWN: i64 = 1;
pub const UP: i64 = 2;
/// SLAG (band 2's new thing for smelting, a test, 2026-11-07): the second button skims a slag note; a round with no
/// slag ignores it (so every round before slag replays as it did).
pub const SKIM: i64 = 3;
/// The slag notes' own stream: the seed folded with this, one draw a note.
pub const SLAG_SALT: u64 = 0x736C_6167;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BeatParams {
    pub beat_ms: i64,
    pub lead_beats: i64,
    pub beats: i64,
    pub rest_pm: i64,
    pub offbeat_pm: i64,
    pub hold_pm: i64,
    pub hold_beats: i64,
    pub perfect_ms: i64,
    pub good_ms: i64,
    pub good_pm: i64,
    pub stray_pm: i64,
    pub pour_ms: i64,
    pub pour_ready_ms: i64,
    pub pour_rate: i64,
    pub target_lo: i64,
    pub target_hi: i64,
    pub pour_tolerance: i64,
    pub track_weight_pct: i64,
    /// How likely a tap note is slag, skimmed with the second button (thousandths; 0: none).
    pub slag_pm: i64,
}

impl BeatParams {
    pub fn track_end_ms(&self) -> i64 {
        (self.lead_beats + self.beats) * self.beat_ms
    }

    pub fn duration_ms(&self) -> i64 {
        self.track_end_ms() + self.pour_ms
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BeatResult {
    pub notes: i64,
    pub perfect: i64,
    pub good: i64,
    pub strays: i64,
    pub fill: i64,
    pub target: i64,
    pub track_pm: i64,
    pub pour_pm: i64,
    pub score_pm: i64,
}

/// The round's seeded track: the mold's line, and each note's (time, end) in order (a tap's end is its time).
pub fn track(seed: u64, p: &BeatParams) -> (i64, Vec<(i64, i64)>) {
    let mut st = seed_state(seed);
    let draw = |st: &mut u32| ((next_u32(st) >> 8) % 1000) as i64;
    let target = p.target_lo + ((next_u32(&mut st) >> 8) as i64) % (p.target_hi - p.target_lo + 1).max(1);
    let mut notes = Vec::new();
    let mut covered = -1i64;
    for i in 0..p.beats.max(0) {
        let r_rest = draw(&mut st);
        let r_off = draw(&mut st);
        let r_hold = draw(&mut st);
        let on_t = (p.lead_beats + i) * p.beat_ms;
        if i > covered && !(i % 4 != 0 && r_rest < p.rest_pm) {
            if p.hold_beats > 0 && r_hold < p.hold_pm && i + p.hold_beats <= p.beats - 1 {
                notes.push((on_t, on_t + p.hold_beats * p.beat_ms));
                covered = i + p.hold_beats;
            } else {
                notes.push((on_t, on_t));
            }
        }
        if i >= covered && r_off < p.offbeat_pm {
            notes.push((on_t + p.beat_ms / 2, on_t + p.beat_ms / 2));
        }
    }
    (target, notes)
}

/// Which notes of `notes` are slag (none when `slag_pm` is 0): one draw a note, only a tap may be.
pub fn slag(seed: u64, p: &BeatParams, notes: &[(i64, i64)]) -> Vec<bool> {
    if p.slag_pm <= 0 {
        return vec![false; notes.len()];
    }
    let mut st = seed_state(seed ^ SLAG_SALT);
    notes.iter().map(|&(t, end)| ((next_u32(&mut st) >> 8) % 1000) < p.slag_pm as u32 && end == t).collect()
}

struct Run<'a> {
    p: &'a BeatParams,
    notes: Vec<(i64, i64)>,
    slag: Vec<bool>,
    got: Vec<i64>,
    perfect: i64,
    good: i64,
    down: bool,
    holding: Option<usize>,
    hold_pts: i64,
    strays: i64,
    pour_tick: i64,
    fill: i64,
    pouring: bool,
}

impl Run<'_> {
    fn advance_to(&mut self, t: i64) {
        if let Some(j) = self.holding {
            if t >= self.notes[j].1 {
                self.got[j] = self.hold_pts;
                self.holding = None;
            }
        }
        let end = self.p.track_end_ms();
        let ticks = self.p.pour_ms / TICK_MS;
        while self.pour_tick < ticks && end + (self.pour_tick + 1) * TICK_MS <= t {
            if self.pouring {
                self.fill += self.p.pour_rate;
            }
            self.pour_tick += 1;
        }
    }

    fn press(&mut self, t: i64, code: i64) {
        self.advance_to(t);
        let p = self.p;
        if code == DOWN {
            if self.down {
                return;
            }
            self.down = true;
            if t >= p.track_end_ms() {
                if !self.pouring && t >= p.track_end_ms() + p.pour_ready_ms {
                    self.pouring = true;
                }
                return;
            }
            let found = (0..self.notes.len()).find(|&j| self.got[j] < 0 && Some(j) != self.holding && !self.slag[j] && (t - self.notes[j].0).abs() <= p.good_ms);
            match found {
                Some(j) => {
                    let perfect = (t - self.notes[j].0).abs() <= p.perfect_ms;
                    let pts = if perfect { 1000 } else { p.good_pm };
                    if perfect {
                        self.perfect += 1;
                    } else {
                        self.good += 1;
                    }
                    if self.notes[j].1 > self.notes[j].0 {
                        self.holding = Some(j);
                        self.hold_pts = pts;
                    } else {
                        self.got[j] = pts;
                    }
                }
                None => self.strays += 1,
            }
        } else if code == SKIM {
            if t >= p.track_end_ms() || p.slag_pm <= 0 {
                return;
            }
            match (0..self.notes.len()).find(|&j| self.got[j] < 0 && self.slag[j] && (t - self.notes[j].0).abs() <= p.good_ms) {
                Some(j) => {
                    if (t - self.notes[j].0).abs() <= p.perfect_ms {
                        self.got[j] = 1000;
                        self.perfect += 1;
                    } else {
                        self.got[j] = p.good_pm;
                        self.good += 1;
                    }
                }
                None => self.strays += 1,
            }
        } else if code == UP {
            if !self.down {
                return;
            }
            self.down = false;
            if self.pouring {
                self.pouring = false;
            } else if let Some(j) = self.holding.take() {
                let (start, end) = self.notes[j];
                self.got[j] = if t >= end - p.good_ms { self.hold_pts } else { self.hold_pts * (t - start).max(0) / (end - start).max(1) };
            }
        }
    }
}

/// A whole round replayed from its inputs, (time, code) in the order sent, run to its end.
pub fn play(seed: u64, p: &BeatParams, inputs: &[(i64, i64)]) -> BeatResult {
    let (target, notes) = track(seed, p);
    let n = notes.len();
    let slag = slag(seed, p, &notes);
    let mut run = Run { p, notes, slag, got: vec![-1; n], perfect: 0, good: 0, down: false, holding: None, hold_pts: 0, strays: 0, pour_tick: 0, fill: 0, pouring: false };
    let mut last_t = -1i64;
    for &(t, code) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > p.duration_ms() {
            continue;
        }
        run.press(t, code);
    }
    run.advance_to(p.duration_ms());
    let sum: i64 = run.got.iter().map(|&g| g.max(0)).sum();
    let track_pm = ((sum - run.strays * p.stray_pm) / (n as i64).max(1)).clamp(0, 1000);
    let pour_pm = if run.fill > 1000 { 0 } else { (1000 - (run.fill - target).abs() * 1000 / p.pour_tolerance).max(0) };
    let w = if p.pour_ms > 0 { p.track_weight_pct } else { 100 };
    let score_pm = (track_pm * w + pour_pm * (100 - w)) / 100;
    BeatResult { notes: n as i64, perfect: run.perfect, good: run.good, strays: run.strays, fill: run.fill, target, track_pm, pour_pm, score_pm }
}
