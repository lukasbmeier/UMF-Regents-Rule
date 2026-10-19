//! SMELTING'S BELLOWS THEN POUR, THE SERVER'S TWIN of `game/regents/skilling/smelting/smelt_model.gd`
//! (`SmeltModel`), in ticks of 50 ms: keep the heat in a drifting, narrowing band, then pour the
//! crucible to the mould's line (from `pour_ready_ms` after the heat; tilting again tops it up). Inputs
//! are (time, code): 1 pump, 2 pour, 3 stop. Held to
//! `shared/golden/regents/smelt.json` (`game/regents/tests/make_skill_goldens.py`).

use super::rng::{next_u32, seed_state};

pub const TICK_MS: i64 = 50;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SmeltParams {
    pub heat_ms: i64,
    pub pour_ms: i64,
    pub pour_ready_ms: i64,
    pub pump_ms: i64,
    pub pump_heat: i64,
    pub cool_per_tick: i64,
    pub start_heat: i64,
    pub band_center: i64,
    pub band_amp: i64,
    pub band_period_ticks: i64,
    pub band_half_start: i64,
    pub band_half_end: i64,
    pub burn_line: i64,
    pub pour_rate: i64,
    pub target_lo: i64,
    pub target_hi: i64,
    pub pour_tolerance: i64,
    pub heat_weight_pct: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SmeltResult {
    pub in_band: i64,
    pub burnt: i64,
    pub fill: i64,
    pub target: i64,
    pub heat_pm: i64,
    pub pour_pm: i64,
    pub score_pm: i64,
}

fn tri(x: i64, period: i64) -> i64 {
    let u = x % period;
    let v = u * 4000 / period;
    if v <= 1000 {
        v
    } else if v <= 3000 {
        2000 - v
    } else {
        v - 4000
    }
}

/// The round's seeded numbers: the band's phase and the mould's line.
pub fn seeded(seed: u64, p: &SmeltParams) -> (i64, i64) {
    let mut st = seed_state(seed);
    let phase = ((next_u32(&mut st) >> 8) as i64) % p.band_period_ticks.max(1);
    let target = p.target_lo + ((next_u32(&mut st) >> 8) as i64) % (p.target_hi - p.target_lo + 1).max(1);
    (phase, target)
}

/// The band at heat tick `k`: its middle and half-width.
pub fn band(p: &SmeltParams, phase: i64, k: i64) -> (i64, i64) {
    let heat_ticks = (p.heat_ms / TICK_MS).max(1);
    let centre = p.band_center + p.band_amp * tri(k + phase, p.band_period_ticks.max(1)) / 1000;
    let half = p.band_half_start + (p.band_half_end - p.band_half_start) * k / heat_ticks;
    (centre, half)
}

/// The furnace and the mould as a round runs.
struct Run<'a> {
    p: &'a SmeltParams,
    phase: i64,
    heat_ticks: i64,
    total: i64,
    tick: i64,
    heat: i64,
    fill: i64,
    pouring: bool,
    in_band: i64,
    burnt: i64,
}

impl Run<'_> {
    /// Run every tick that ends by `t`.
    fn advance_to(&mut self, t: i64) {
        while (self.tick + 1) * TICK_MS <= t && self.tick < self.total {
            if self.tick < self.heat_ticks {
                self.heat = (self.heat - self.p.cool_per_tick).max(0);
                let (c, h) = band(self.p, self.phase, self.tick);
                if (self.heat - c).abs() <= h {
                    self.in_band += 1;
                }
                if self.heat > self.p.burn_line {
                    self.burnt += 1;
                }
            } else if self.pouring {
                self.fill += self.p.pour_rate;
            }
            self.tick += 1;
        }
    }
}

/// A whole round replayed from its inputs, (time, code) in the order sent, run to its end.
pub fn play(seed: u64, p: &SmeltParams, inputs: &[(i64, i64)]) -> SmeltResult {
    let (phase, target) = seeded(seed, p);
    let heat_ticks = p.heat_ms / TICK_MS;
    let total = heat_ticks + p.pour_ms / TICK_MS;
    let mut run = Run { p, phase, heat_ticks, total, tick: 0, heat: p.start_heat, fill: 0, pouring: false, in_band: 0, burnt: 0 };
    let (mut next_pump, mut last_t) = (0i64, -1i64);
    for &(t, code) in inputs {
        if t < last_t {
            continue;
        }
        last_t = t;
        if t < 0 || t > total * TICK_MS {
            continue;
        }
        run.advance_to(t);
        let in_heat = run.tick < heat_ticks;
        match code {
            1 if in_heat && t >= next_pump => {
                run.heat = (run.heat + p.pump_heat).min(1000);
                next_pump = t + p.pump_ms;
            }
            2 if !in_heat && !run.pouring && t >= p.heat_ms + p.pour_ready_ms => run.pouring = true,
            3 if run.pouring => run.pouring = false,
            _ => {}
        }
    }
    run.advance_to(total * TICK_MS);
    let heat_pm = ((run.in_band - run.burnt) * 1000 / heat_ticks.max(1)).clamp(0, 1000);
    let pour_pm = if run.fill > 1000 { 0 } else { (1000 - (run.fill - target).abs() * 1000 / p.pour_tolerance).max(0) };
    let score_pm = (heat_pm * p.heat_weight_pct + pour_pm * (100 - p.heat_weight_pct)) / 100;
    SmeltResult { in_band: run.in_band, burnt: run.burnt, fill: run.fill, target, heat_pm, pour_pm, score_pm }
}
