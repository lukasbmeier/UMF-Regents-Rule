//! HERBALISM'S PULL THE ROOT, THE SERVER'S TWIN of `game/regents/skilling/herbalism/pull_model.gd` (`PullModel`;
//! `HERBALISM_HUNTING_PREP.md` §3, Luke's H3, 2026-11-07; the trowel's work after his play, 2026-11-08). In ticks of
//! 50 ms: a CLUMP (Luke, 2026-11-08), stem after stem, each with its own side roots, until the round's end. The trowel
//! strokes a side: it cuts the side root showing there, else digs that side's packed soil (packed soil holds the root
//! back). Held, the strain rises and the root comes up (faster at a higher strain); let go, or while a stroke runs,
//! it eases; a side root pulled through uncut jumps the strain; past 1000 it snaps (worth part of what came up); up
//! whole it is worth 1000. The rules are written out on `PullModel`.
//! Held to `shared/golden/regents/pull.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

pub const TICK_MS: i64 = 50;
pub const DOWN: i64 = 1;
pub const UP: i64 = 2;
pub const LEFT: i64 = 3;
pub const RIGHT: i64 = 4;
/// Which sides of a stem start LOOSE (Luke, 2026-11-09: "cutaway, no chore") come from their own stream, so the side
/// roots never change: `seed ^ LOOSE_SALT`.
pub const LOOSE_SALT: u64 = 0x6C6F_6F73;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PullParams {
    pub duration_ms: i64,
    pub stroke_ms: i64,
    pub target_plants: i64,
    pub dig_pm: i64,
    pub hold_pm: i64,
    pub strain_rise: i64,
    pub strain_ease: i64,
    pub pull_rate: i64,
    pub pull_gain: i64,
    pub snags: i64,
    pub jump_lo: i64,
    pub jump_hi: i64,
    pub show_depth: i64,
    pub snap_keep_pm: i64,
    /// The chance (thousandths) that each side of a stem starts loose (nothing to dig); 0: both packed, no draw.
    pub loose_pm: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PullResult {
    pub whole: i64,
    pub snapped: i64,
    pub caught: i64,
    pub cut: i64,
    pub dug: i64,
    pub worth: i64,
    pub score_pm: i64,
}

/// A stem's side roots, drawn from where the seed's stream stands: (depths, jumps, sides).
fn draw(st: &mut u32, p: &PullParams) -> (Vec<i64>, Vec<i64>, Vec<i64>) {
    let seg = 900 / p.snags.max(1);
    let (mut depth, mut jump, mut side) = (Vec::new(), Vec::new(), Vec::new());
    for k in 0..p.snags.max(0) {
        depth.push(50 + k * seg + ((next_u32(st) >> 8) as i64) % seg.max(1));
        jump.push(p.jump_lo + ((next_u32(st) >> 8) as i64) % (p.jump_hi - p.jump_lo + 1).max(1));
        side.push(LEFT + ((next_u32(st) >> 8) as i64) % 2);
    }
    (depth, jump, side)
}

/// A stem's soil, from where the soil's stream stands: (left, right), each packed (1000) or loose (0), left drawn first.
fn soil(st: &mut u32, p: &PullParams) -> (i64, i64) {
    if p.loose_pm <= 0 {
        return (1000, 1000);
    }
    let left = if ((next_u32(st) >> 8) as i64) % 1000 < p.loose_pm { 0 } else { 1000 };
    let right = if ((next_u32(st) >> 8) as i64) % 1000 < p.loose_pm { 0 } else { 1000 };
    (left, right)
}

/// The first stem's side roots from the seed: (depths, jumps, sides).
pub fn start(seed: u64, p: &PullParams) -> (Vec<i64>, Vec<i64>, Vec<i64>) {
    draw(&mut seed_state(seed), p)
}

struct Run<'a> {
    p: &'a PullParams,
    st: u32,
    soil_st: u32,
    depth: Vec<i64>,
    jump: Vec<i64>,
    side: Vec<i64>,
    tick: i64,
    down: bool,
    strain: i64,
    up_by: i64,
    next_snag: i64,
    pack_left: i64,
    pack_right: i64,
    stroke_until_ms: i64,
    stroke_to_tick: i64,
    r: PullResult,
}

impl Run<'_> {
    fn showing(&self) -> i64 {
        let k = self.next_snag;
        if self.up_by <= 0 || k >= self.p.snags || self.depth[k as usize] - self.up_by > self.p.show_depth {
            return 0;
        }
        self.side[k as usize]
    }

    fn advance_to(&mut self, t: i64) {
        let total = self.p.duration_ms / TICK_MS;
        while (self.tick + 1) * TICK_MS <= t && self.tick < total {
            self.step();
            self.tick += 1;
        }
    }

    fn step(&mut self) {
        let p = self.p;
        if !self.down || self.tick < self.stroke_to_tick {
            self.strain = (self.strain - p.strain_ease).max(0);
            return;
        }
        self.strain += p.strain_rise;
        let pack = (self.pack_left + self.pack_right) / 2;
        self.up_by += (p.pull_rate + self.strain * p.pull_gain / 1000) * (1000 - pack * p.hold_pm / 1000) / 1000;
        while self.next_snag < p.snags && self.up_by >= self.depth[self.next_snag as usize] {
            self.strain += self.jump[self.next_snag as usize];
            self.next_snag += 1;
            self.r.caught += 1;
        }
        if self.strain > 1000 {
            self.r.worth += self.up_by.min(1000) * p.snap_keep_pm / 1000;
            self.r.snapped += 1;
            self.next_plant();
        } else if self.up_by >= 1000 {
            self.r.worth += 1000;
            self.r.whole += 1;
            self.next_plant();
        }
    }

    fn next_plant(&mut self) {
        (self.depth, self.jump, self.side) = draw(&mut self.st, self.p);
        self.strain = 0;
        self.up_by = 0;
        self.next_snag = 0;
        (self.pack_left, self.pack_right) = soil(&mut self.soil_st, self.p);
    }

    fn stroke(&mut self, t: i64, code: i64) {
        if t < self.stroke_until_ms {
            return;
        }
        self.stroke_until_ms = t + self.p.stroke_ms;
        self.stroke_to_tick = self.stroke_until_ms / TICK_MS;
        if self.showing() == code {
            self.next_snag += 1;
            self.r.cut += 1;
        } else if code == LEFT && self.pack_left > 0 {
            self.pack_left = (self.pack_left - self.p.dig_pm).max(0);
            self.r.dug += 1;
        } else if code == RIGHT && self.pack_right > 0 {
            self.pack_right = (self.pack_right - self.p.dig_pm).max(0);
            self.r.dug += 1;
        }
    }
}

/// A whole round replayed from its inputs, (time, code) in the order sent, run to its end.
pub fn play(seed: u64, p: &PullParams, inputs: &[(i64, i64)]) -> PullResult {
    let mut st = seed_state(seed);
    let (depth, jump, side) = draw(&mut st, p);
    let mut soil_st = seed_state(seed ^ LOOSE_SALT);
    let (pack_left, pack_right) = soil(&mut soil_st, p);
    let mut run = Run {
        p, st, soil_st, depth, jump, side, tick: 0, down: false, strain: 0, up_by: 0, next_snag: 0, pack_left, pack_right,
        stroke_until_ms: 0, stroke_to_tick: 0, r: PullResult::default(),
    };
    let mut last_t = -1i64;
    for &(t, code) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > p.duration_ms {
            continue;
        }
        run.advance_to(t);
        match code {
            DOWN => run.down = true,
            UP => run.down = false,
            LEFT | RIGHT => run.stroke(t, code),
            _ => {}
        }
    }
    run.advance_to(p.duration_ms / TICK_MS * TICK_MS);
    run.r.worth += run.up_by.min(1000) * p.snap_keep_pm / 1000;
    run.r.score_pm = (run.r.worth / p.target_plants.max(1)).min(1000);
    run.r
}
