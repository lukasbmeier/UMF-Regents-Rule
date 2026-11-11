//! SKINNING'S CUT LINE, THE SERVER'S TWIN of `game/regents/skilling/skinning/skin_model.gd` (`SkinModel`;
//! `HERBALISM_HUNTING_PREP.md` H4, Luke 2026-11-07: "DRAG the knife along the cut line ... off the line tears the
//! hide"). In ticks of 50 ms: the knife held in the hide follows the mouse; on the line near the cut's end it cuts
//! along it (no faster than `cut_speed`), anywhere else it tears; a line cut to its end lifts the knife and the next
//! is drawn, until the round's end. The rules are written out on `SkinModel`.
//! Held to `shared/golden/regents/skin.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

pub const TICK_MS: i64 = 50;
/// The knife lifted: an input's x.
pub const LIFT: i64 = -1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SkinParams {
    pub duration_ms: i64,
    pub target_lines: i64,
    pub points: i64,
    pub wobble: i64,
    pub near: i64,
    pub reach: i64,
    pub cut_speed: i64,
    pub tear_pm: i64,
    pub part_keep_pm: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SkinResult {
    pub lines: i64,
    pub clean: i64,
    pub torn: i64,
    pub worth: i64,
    pub score_pm: i64,
}

/// The integer square root (the floor).
pub fn isqrt(n: i64) -> i64 {
    if n <= 0 {
        return 0;
    }
    let (mut x, mut y) = (n, (n + 1) / 2);
    while y < x {
        x = y;
        y = (x + n / x) / 2;
    }
    x
}

/// A line, drawn from where the seed's stream stands: (xs, ys, each stretch's length).
fn draw(st: &mut u32, p: &SkinParams) -> (Vec<i64>, Vec<i64>, Vec<i64>) {
    let n = p.points.max(2);
    let back = ((next_u32(st) >> 8) as i64) % 2 == 1;
    let (mut xs, mut ys) = (Vec::new(), Vec::new());
    for k in 0..n {
        let u = 100 + k * 800 / (n - 1);
        xs.push(if back { 1000 - u } else { u });
        ys.push(500 + ((next_u32(st) >> 8) as i64) % (2 * p.wobble + 1) - p.wobble);
    }
    let lens = (0..(n - 1) as usize).map(|k| {
        let (dx, dy) = (xs[k + 1] - xs[k], ys[k + 1] - ys[k]);
        isqrt(dx * dx + dy * dy).max(1)
    }).collect();
    (xs, ys, lens)
}

/// The first line from the seed: (xs, ys).
pub fn start(seed: u64, p: &SkinParams) -> (Vec<i64>, Vec<i64>) {
    let (xs, ys, _) = draw(&mut seed_state(seed), p);
    (xs, ys)
}

struct Run<'a> {
    p: &'a SkinParams,
    st: u32,
    xs: Vec<i64>,
    ys: Vec<i64>,
    lens: Vec<i64>,
    tick: i64,
    seg: usize,
    f: i64,
    down: bool,
    kx: i64,
    ky: i64,
    tears: i64,
    r: SkinResult,
}

impl Run<'_> {
    fn new_line(&mut self) {
        (self.xs, self.ys, self.lens) = draw(&mut self.st, self.p);
        self.seg = 0;
        self.f = 0;
        self.tears = 0;
    }

    fn cuts_at(&self, x: i64, y: i64) -> bool {
        let (p, s) = (self.p, self.seg);
        let (dx, dy) = (self.xs[s + 1] - self.xs[s], self.ys[s + 1] - self.ys[s]);
        let (tx, ty) = (self.xs[s] + dx * self.f / 1000, self.ys[s] + dy * self.f / 1000);
        let (ex, ey) = (x - tx, y - ty);
        if ex * ex + ey * ey > p.reach * p.reach {
            return false;
        }
        let cross = dx * (y - self.ys[s]) - dy * (x - self.xs[s]);
        if cross * cross <= p.near * p.near * (dx * dx + dy * dy) {
            return true;
        }
        if s + 2 < self.xs.len() {
            let (dx2, dy2) = (self.xs[s + 2] - self.xs[s + 1], self.ys[s + 2] - self.ys[s + 1]);
            let cross2 = dx2 * (y - self.ys[s + 1]) - dy2 * (x - self.xs[s + 1]);
            return cross2 * cross2 <= p.near * p.near * (dx2 * dx2 + dy2 * dy2);
        }
        false
    }

    fn past_bend(&self, x: i64, y: i64) -> bool {
        let s = self.seg;
        if s + 2 >= self.xs.len() {
            return false;
        }
        let (dx2, dy2) = (self.xs[s + 2] - self.xs[s + 1], self.ys[s + 2] - self.ys[s + 1]);
        let cross2 = dx2 * (y - self.ys[s + 1]) - dy2 * (x - self.xs[s + 1]);
        let dot2 = dx2 * (x - self.xs[s + 1]) + dy2 * (y - self.ys[s + 1]);
        dot2 > 0 && cross2 * cross2 <= self.p.near * self.p.near * (dx2 * dx2 + dy2 * dy2)
    }

    fn advance_to(&mut self, t: i64) {
        let total = self.p.duration_ms / TICK_MS;
        while (self.tick + 1) * TICK_MS <= t && self.tick < total {
            self.step();
            self.tick += 1;
        }
    }

    fn step(&mut self) {
        if !self.down {
            return;
        }
        let p = self.p;
        if !self.cuts_at(self.kx, self.ky) {
            self.tears += 1;
            self.r.torn += 1;
            return;
        }
        let s = self.seg;
        let (dx, dy) = (self.xs[s + 1] - self.xs[s], self.ys[s + 1] - self.ys[s]);
        let dot = dx * (self.kx - self.xs[s]) + dy * (self.ky - self.ys[s]);
        let mut along = if dot > 0 { dot * 1000 / (dx * dx + dy * dy) } else { 0 };
        if self.past_bend(self.kx, self.ky) {
            along = 1000;   // on the next stretch, past the bend: the cut runs to the bend
        }
        if along <= self.f {
            return;
        }
        self.f = along.min(self.f + (p.cut_speed * 1000 / self.lens[s]).max(1));
        if self.f < 1000 {
            return;
        }
        if s + 2 < self.xs.len() {
            self.seg += 1;
            self.f = 0;
            return;
        }
        self.r.worth += (1000 - self.tears * p.tear_pm).max(0);
        self.r.lines += 1;
        if self.tears == 0 {
            self.r.clean += 1;
        }
        self.down = false;
        self.new_line();
    }
}

/// A whole round replayed from its inputs, (time, x, y) in the order sent, run to its end.
pub fn play(seed: u64, p: &SkinParams, inputs: &[(i64, i64, i64)]) -> SkinResult {
    let mut st = seed_state(seed);
    let (xs, ys, lens) = draw(&mut st, p);
    let mut run = Run { p, st, xs, ys, lens, tick: 0, seg: 0, f: 0, down: false, kx: 0, ky: 0, tears: 0, r: SkinResult::default() };
    let mut last_t = -1i64;
    for &(t, x, y) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > p.duration_ms {
            continue;
        }
        run.advance_to(t);
        if x == LIFT {
            run.down = false;
        } else if (0..=1000).contains(&x) && (0..=1000).contains(&y) {
            run.kx = x;
            run.ky = y;
            run.down = true;
        }
    }
    run.advance_to(p.duration_ms / TICK_MS * TICK_MS);
    let done_pm = (run.seg as i64 * 1000 + run.f) / (run.xs.len() as i64 - 1).max(1);
    run.r.worth += (1000 - run.tears * p.tear_pm).max(0) * done_pm / 1000 * p.part_keep_pm / 1000;
    run.r.score_pm = (run.r.worth / p.target_lines.max(1)).min(1000);
    run.r
}
