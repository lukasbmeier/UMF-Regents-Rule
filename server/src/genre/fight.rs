//! THE FIGHT: Fishing for Compliments' fifth and final fight, "THE PUMP" — ported, and made
//! something the server can check.
//!
//! PUMP (the cast button) held LOADS the rod: tension climbs, no line comes in. Let go and the
//! pump resolves — graded by where the load was against the catch's SWEET BAND — into SLACK,
//! which only turns into line while the reel is worked (the crank). GIVE (the other button) is
//! the release valve, the answer to a run. Overloading past the band breaks the line — except
//! on a snag, where heaving is the only way out. Fresh, the band sits high and narrow; spent,
//! it slides down and widens. The whole design and its five-version history is in
//! `tools/fishing/gen_fight.py` and FfC's design/data/fight.toml.
//!
//! WHAT CHANGED IN THE PORT, and only this:
//!   - Fishing for Compliments TRUSTED the client's result. Here the client plays the fight for
//!     feel and submits its INPUTS — one entry per tick, run-length encoded — and the module
//!     REPLAYS them through this file to decide what happened. A landed catch is one this
//!     simulation landed.
//!   - So it is deterministic across two languages: `game/fishing/fight_sim.gd` is its twin,
//!     held to it bit for bit by `shared/golden/fishing/fight.json` (every state field, as the
//!     bytes of its f64, at checkpoints through scripted fights). f64 on both sides; min, max,
//!     clamp, lerp and move_toward are written out below exactly as Godot defines them, not
//!     borrowed from either standard library; the random stream is an xorshift32 both can run;
//!     time is a fixed tick (`TICK_HZ`) and never the frame's delta.
//!   - The catch profiles' curves (a logarithm of the weight) are evaluated OFFLINE into
//!     `shared/fishing/fight.json` (`tools/fishing/gen_fight.py`): a transcendental is the one
//!     thing two languages are not guaranteed to agree on.
//!   - Presentation-only state FfC kept here (the rod meters, the old slide) is gone; shake and
//!     hit-stop stay, because hit-stop freezes the fight's time and so is part of the replay.
//!
//! No `spacetimedb` dependency (DECISIONS #27): this is tested natively like `sim` and `challenge`.

use crate::genre::fishing::HookSet;

/// Every tunable the fight reads. `BASE` is `fight.json`'s; `params_for` applies the gear and
/// the hook-set on top, the way FfC's Loadout.apply did.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FightParams {
    pub distance_rate: f64,
    pub give_factor_idle: f64,
    pub give_factor_dead: f64,
    /// THE CAST IS THE FIGHT LENGTH: `fight_length` is this share of the cast's range, never less
    /// than `fight_min_m` (a lob is still a fight) nor more than `fight_max_m` (the range the fight
    /// was tuned against). FfC's rig, `cast_distance_m`.
    pub cast_to_fight: f64,
    pub fight_min_m: f64,
    pub fight_max_m: f64,
    pub spent_power_floor: f64,
    pub spent_wind_penalty: f64,
    pub drag_setting: f64,
    pub tension_response: f64,
    pub tension_release: f64,
    pub drag_slip: f64,
    pub slip_metres: f64,
    pub drag_slip_max: f64,
    pub shock_gain: f64,
    pub shock_threshold: f64,
    pub snap_grace_seconds: f64,
    pub snap_tension: f64,
    pub overload_fatigue: f64,
    pub fatigue_recover: f64,
    pub bare_reel_fraction: f64,
    pub bare_reel_tension: f64,
    /// REEL ANY TIME; IT PAYS WHEN THE FISH IS SPENT. A bare reel's share of the crank rate
    /// against a fully spent fish, and while one rests; how much of its load still reaches the
    /// line then; and how hard winding against a run loads it (`step_bare_reel`).
    pub spent_reel_fraction: f64,
    pub rest_reel_fraction: f64,
    pub spent_reel_strain: f64,
    pub run_reel_strain: f64,
    pub pull_response: f64,
    pub load_rate: f64,
    pub load_slow_start: f64,
    /// THE YELLOW: the least time from the band's edge to its sweet spot. 0 is FfC's lift, which
    /// runs into the band at full speed.
    pub band_approach_s: f64,
    pub overload_limit: f64,
    pub pump_recover: f64,
    pub snag_load_transfer: f64,
    pub snag_break_load: f64,
    pub pump_metres: f64,
    pub weak_yield: f64,
    pub perfect_yield: f64,
    pub perfect_fraction: f64,
    pub load_to_tension: f64,
    pub release_dump: f64,
    pub overload_tension: f64,
    pub pump_stress: f64,
    pub stress_settle: f64,
    pub pump_stamina_mult: f64,
    pub crank_window: f64,
    pub crank_rate: f64,
    pub lateral_speed: f64,
    pub lateral_range: f64,
    pub lateral_run_mult: f64,
    pub wander_min: f64,
    pub wander_max: f64,
    pub give_tension_relief: f64,
    pub give_run_damping: f64,
    pub run_take: f64,
    pub shake_per_pump: f64,
    pub shake_decay: f64,
    pub hitstop_perfect: f64,
    pub hitstop_snag_free: f64,
    pub perfect_drag_bonus: f64,
    pub late_start_tension: f64,
    pub clean_catch_max_peak_tension: f64,
    pub deadlift_load_mult: f64,
    pub deadlift_creep: f64,
    /// Set per fight, not in the file: the hook-set it started from, and whether the catch is
    /// heavier than the line is rated for (rolled at the cast, `genre::fishing`).
    pub perfect_set: bool,
    pub late_set: bool,
    pub deadlift: bool,
}

/// What a hooked thing IS in a fight. `alive` is the load-bearing property: alive things pull,
/// panic, run and tire; dead weight weighs, never tires, and snags.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Profile {
    pub alive: bool,
    pub distance_scale: f64,
    pub hold_force: f64,
    pub run_power: f64,
    pub rest_force: f64,
    pub band_centre: f64,
    pub band_width: f64,
    pub band_centre_spent: f64,
    pub band_width_spent: f64,
    pub pump_yield: f64,
    pub panic_gain: f64,
    pub burst_drain: f64,
    pub burst_regen: f64,
    pub burst_recover: f64,
    pub stamina_drain: f64,
    pub never_tires: bool,
    pub dead_load: f64,
    pub snag_interval_min: f64,
    pub snag_interval_max: f64,
    pub snag_duration: f64,
    pub snag_load: f64,
}

include!(concat!(env!("OUT_DIR"), "/fight_data.rs"));

/// The fight's fixed timestep.
pub fn dt() -> f64 {
    1.0 / TICK_HZ as f64
}

/// The most ticks the module will replay (`max_fight_s`). Past it the line is cut.
pub fn max_ticks() -> u32 {
    (MAX_FIGHT_S * TICK_HZ as f64) as u32
}

pub fn profile(catch_key: &str) -> Option<&'static Profile> {
    PROFILES.iter().find(|(k, _)| *k == catch_key).map(|(_, p)| p)
}

/// The fight's numbers for this cast: the gear multiplies the tuned defaults (FfC's
/// Loadout.apply) — the ROD how much line a pump lifts, the REEL how fast the crank takes
/// slack, the LINE where it snaps — and the hook-set and the deadlift ride along.
pub fn params_for(rod: u8, reel: u8, line: u8, hookset: HookSet, deadlift: bool) -> FightParams {
    let r = |t: u8, n: usize| (t as usize).min(n - 1);
    let mut p = BASE;
    p.snap_tension = LINE_TENSION_CEILING[r(line, LINE_TENSION_CEILING.len())] / 100.0;
    p.crank_rate = BASE.crank_rate * REEL_SPEED[r(reel, REEL_SPEED.len())];
    p.pump_metres = BASE.pump_metres * ROD_REEL_POWER[r(rod, ROD_REEL_POWER.len())];
    p.perfect_set = hookset == HookSet::Perfect;
    p.late_set = hookset == HookSet::Late;
    p.deadlift = deadlift;
    p
}

/// How much line a cast `cast_m` out puts between the angler and a catch whose `distance_scale`
/// is 1: THE CAST IS THE FIGHT LENGTH, within the range the fight was tuned for. A catch starts
/// its own share of it (a bluegill in the weeds is not hooked at sturgeon range).
pub fn fight_length(p: &FightParams, cast_m: f64) -> f64 {
    clampf(cast_m * p.cast_to_fight, p.fight_min_m, p.fight_max_m)
}

// --- Godot's own definitions, so the twin can match them operation for operation ---------

/// `MAX(a, b)`: `a > b ? a : b`. Not `f64::max`, whose choice between +0 and -0 is unspecified.
fn maxf(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

/// `MIN(a, b)`: `a < b ? a : b`.
fn minf(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}

/// `CLAMP(v, lo, hi)`: `v < lo ? lo : (v > hi ? hi : v)`.
fn clampf(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo { lo } else if v > hi { hi } else { v }
}

/// `Math::lerp`: `from + (to - from) * weight`.
fn lerpf(from: f64, to: f64, weight: f64) -> f64 {
    from + (to - from) * weight
}

/// `Math::move_toward`: `|to - from| <= delta ? to : from + SIGN(to - from) * delta`.
fn move_toward(from: f64, to: f64, delta: f64) -> f64 {
    let d = to - from;
    if d.abs() <= delta {
        to
    } else {
        let sign = if d == 0.0 { 0.0 } else if d < 0.0 { -1.0 } else { 1.0 };
        from + sign * delta
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Fighting,
    Landed,
    Snapped,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Behavior {
    Holding,
    Running,
    Resting,
    Snagged,
}

/// How a pump was released: short of the band, inside it, the middle slice of it, or past it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Grade {
    Early,
    Good,
    Perfect,
    Late,
}

/// One fight in progress. Every field that the next tick reads is here, and nothing else.
#[derive(Clone, Debug)]
pub struct Fight {
    pub params: FightParams,
    pub profile: Profile,
    pub state: State,
    pub behavior: Behavior,
    pub distance: f64,
    pub start_distance: f64,
    pub tension: f64,
    /// How far the rod is loaded, 0..overload_limit: THE number the player dials.
    pub load: f64,
    pub band_lo: f64,
    pub band_hi: f64,
    /// Metres a pump has made available that the reel has not taken yet.
    pub slack: f64,
    /// A tension floor bought by holding past the band; eases back off.
    pub fatigue: f64,
    pub overloading: bool,
    pub crank_left: f64,
    /// Across the water, -1..1 (× lateral_range). Alive only.
    pub lateral: f64,
    pub combo: u32,
    pub best_combo: u32,
    pub shake: f64,
    pub hitstop: f64,
    pub stress: f64,
    pub burst: f64,
    pub stamina: f64,
    pub elapsed: f64,
    pub peak_tension: f64,
    pub distance_lost: f64,
    pub pumps_good: u32,
    pub pumps_total: u32,
    pub runs: u32,
    pub giving: bool,
    pull: f64,
    pull_prev: f64,
    deadlift_floor: f64,
    over_limit_time: f64,
    snag_at: f64,
    snag_until: f64,
    recover_until: f64,
    was_loading: bool,
    armed: bool,
    bare_pull: f64,
    lat_target: f64,
    lat_timer: f64,
    overload_time: f64,
    rng: u32,
    /// The last pump's grade, for whoever is drawing the fight.
    pub last_grade: Option<Grade>,
    /// Ticks consumed, hit-stop included: the fight's real duration.
    pub ticks: u32,
}

impl Fight {
    /// A fight against `profile` from a cast `cast_m` out. `pump_held`: the button is still down
    /// from the click that set the hook, and must be let go once before it loads the rod — one
    /// press doing two jobs read as a bug in FfC.
    pub fn new(params: FightParams, profile: Profile, seed: u32, cast_m: f64, pump_held: bool) -> Fight {
        let start = fight_length(&params, cast_m) * profile.distance_scale;
        let tension = if params.late_set { params.late_start_tension } else { 0.0 };
        let mut f = Fight {
            params,
            profile,
            state: State::Fighting,
            behavior: Behavior::Holding,
            distance: start,
            start_distance: start,
            tension,
            load: 0.0,
            band_lo: 0.0,
            band_hi: 0.0,
            slack: 0.0,
            fatigue: 0.0,
            overloading: false,
            crank_left: 0.0,
            lateral: 0.0,
            combo: 0,
            best_combo: 0,
            shake: 0.0,
            hitstop: 0.0,
            stress: 0.0,
            burst: 1.0,
            stamina: 1.0,
            elapsed: 0.0,
            peak_tension: tension,
            distance_lost: 0.0,
            pumps_good: 0,
            pumps_total: 0,
            runs: 0,
            giving: false,
            pull: 0.0,
            pull_prev: 0.0,
            deadlift_floor: 0.0,
            over_limit_time: 0.0,
            snag_at: 0.0,
            snag_until: 0.0,
            recover_until: 0.0,
            was_loading: false,
            armed: !pump_held,
            bare_pull: 0.0,
            lat_target: 0.0,
            lat_timer: 0.0,
            overload_time: 0.0,
            rng: if seed == 0 { 0x9E37_79B9 } else { seed },
            last_grade: None,
            ticks: 0,
        };
        f.update_band();
        f.pull = f.target_pull();
        f.pull_prev = f.pull;
        f.schedule_snag();
        f
    }

    // --- the random stream: xorshift32, 24 bits per draw ------------------------------------

    fn next_u32(&mut self) -> u32 {
        let mut x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        x
    }

    fn randf_range(&mut self, from: f64, to: f64) -> f64 {
        let u = (self.next_u32() >> 8) as f64 / 16777216.0;
        from + (to - from) * u
    }

    fn schedule_snag(&mut self) {
        let (lo, hi) = (self.profile.snag_interval_min, self.profile.snag_interval_max);
        self.snag_at = self.elapsed + self.randf_range(lo, hi);
    }

    // --- the tick ---------------------------------------------------------------------------

    /// One fixed step. `loading`: PUMP held. `giving`: GIVE held. `crank`: how hard the reel is
    /// being worked, 0..255 (the log's quantisation; 255 is flat out).
    pub fn tick(&mut self, loading: bool, giving: bool, crank: u8) {
        if self.state != State::Fighting {
            return;
        }
        self.ticks += 1;
        let delta = dt();
        // HIT-STOP: a few frames of frozen time on a perfect pump.
        if self.hitstop > 0.0 {
            self.hitstop = maxf(self.hitstop - delta, 0.0);
            return;
        }
        let crank = crank as f64 / 255.0;
        self.elapsed += delta;
        self.shake = maxf(self.shake - self.params.shake_decay * delta, 0.0);
        self.step_pump(delta, loading, giving);
        self.step_crank(delta, crank);
        // Checked here as well as at the end: a pump can bring the catch to the rod tip, and
        // the drift and the drag both ADD distance below.
        if self.check_landed() {
            return;
        }
        if self.profile.alive {
            self.step_alive(delta);
        } else {
            self.step_dead(delta);
        }
        self.update_band();
        self.step_wander(delta);
        self.step_pull(delta);
        self.step_line(delta, giving);
        self.step_drift(delta, giving);
        self.peak_tension = maxf(self.peak_tension, self.tension);
        self.check_snap(delta);
        self.check_landed();
    }

    fn check_landed(&mut self) -> bool {
        if self.state == State::Fighting && self.distance <= 0.0 {
            self.distance = 0.0;
            self.state = State::Landed;
        }
        self.state != State::Fighting
    }

    fn step_pump(&mut self, delta: f64, loading: bool, giving: bool) {
        self.overloading = false;
        if !self.armed {
            if !loading {
                self.armed = true;
            }
            self.was_loading = false;
            self.giving = giving;
            return;
        }
        let can_load = loading && !giving && self.slack <= 0.001 && self.elapsed >= self.recover_until;
        if can_load {
            // THE LIFT ACCELERATES: slow off the bottom, faster into the band.
            let reach = if self.band_hi > 0.0 { self.band_hi } else { 1.0 };
            let ramp = clampf(self.load / maxf(reach, 0.05), 0.0, 1.0);
            let mut rate = self.params.load_rate * lerpf(self.params.load_slow_start, 1.0, ramp);
            // THE YELLOW: from the band's edge to the sweet spot, never faster than
            // `band_approach_s` — long enough to see it coming with the band hidden.
            if self.params.band_approach_s > 0.0 && self.band_hi > self.band_lo && self.load >= self.band_lo {
                let sweet = self.perfect_lo();
                if self.load < sweet {
                    rate = minf(rate, (sweet - self.band_lo) / self.params.band_approach_s);
                }
            }
            self.load = minf(self.load + rate * delta, self.params.overload_limit);
            if self.behavior == Behavior::Snagged {
                // THE SET: stuck fast, and the only way out is to heave on it.
                self.overload_time += delta;
                if self.load >= self.params.snag_break_load {
                    self.free_snag();
                }
            } else if self.load > self.band_hi {
                self.overloading = true;
                self.fatigue = minf(self.fatigue + self.params.overload_fatigue * delta, self.params.snap_tension);
                self.overload_time += delta;
                let over = if self.band_hi > 0.0 { self.load - self.band_hi } else { self.load * 0.4 };
                self.tension += self.params.overload_tension * over * delta;
                if self.band_hi > 0.0 && self.overload_time > 0.25 {
                    self.overload_time = 0.0;
                }
            }
        } else if self.was_loading && self.load > 0.0 {
            self.resolve_pump();
        }
        self.was_loading = can_load;
        self.giving = giving;
    }

    fn resolve_pump(&mut self) {
        let quality = self.pump_quality(self.load);
        let grade = self.grade(self.load);
        let yield_m = self.params.pump_metres * self.profile.pump_yield * quality;
        self.slack += yield_m;
        self.crank_left = self.params.crank_window;
        self.pumps_total += 1;
        if grade == Grade::Perfect {
            self.pumps_good += 1;
            self.combo += 1;
            self.best_combo = self.best_combo.max(self.combo);
            self.hitstop = self.params.hitstop_perfect;
        } else {
            self.combo = 0;
        }
        self.shake = minf(self.shake + self.params.shake_per_pump * (0.4 + quality), 1.5);
        // Your aggression is what panics it: a greedy rhythm summons the runs that punish it.
        if self.profile.alive && self.behavior != Behavior::Running {
            self.stress = clampf(self.stress + self.params.pump_stress * self.load, 0.0, 1.0);
        }
        if !self.profile.never_tires {
            self.stamina = maxf(
                self.stamina - self.profile.stamina_drain * self.load * self.params.pump_stamina_mult,
                0.0,
            );
        }
        self.tension = maxf(self.tension - self.params.release_dump * 0.35, 0.0);
        self.load = 0.0;
        self.overload_time = 0.0;
        self.recover_until = self.elapsed + self.params.pump_recover;
        self.last_grade = Some(grade);
    }

    /// A hooked fish tracks side to side; dead weight has nothing to swim with and centres.
    fn step_wander(&mut self, delta: f64) {
        if !self.profile.alive {
            self.lateral = move_toward(self.lateral, 0.0, delta * 0.6);
            return;
        }
        self.lat_timer -= delta;
        if self.lat_timer <= 0.0 {
            self.lat_target = self.randf_range(-1.0, 1.0);
            let (lo, hi) = (self.params.wander_min, self.params.wander_max);
            self.lat_timer = self.randf_range(lo, hi);
        }
        let mut speed = self.params.lateral_speed;
        if self.behavior == Behavior::Running {
            speed *= self.params.lateral_run_mult;
        }
        self.lateral = move_toward(self.lateral, self.lat_target, speed * delta);
    }

    /// Winding with nothing on offer. REEL ANY TIME; IT PAYS WHEN THE FISH IS SPENT: against a
    /// fresh fish it barely works and its load goes straight through the line; the more the fish
    /// is spent — or while it rests after a run — the more line it wins and the less it strains.
    /// Against a RUN it wins nothing and loads the line hard: give line instead. Refused outright
    /// once the drag is slipping — the spool is already giving.
    fn step_bare_reel(&mut self, delta: f64, crank: f64) {
        self.bare_pull = 0.0;
        if crank <= 0.01 || self.distance <= 0.0 || self.giving {
            return;
        }
        if self.behavior == Behavior::Running {
            self.bare_pull = crank * self.params.bare_reel_tension * self.params.run_reel_strain;
            return;
        }
        if self.tension > self.effective_drag() {
            return;
        }
        self.distance = maxf(self.distance - crank * self.params.crank_rate * self.bare_reel_win() * delta, 0.0);
        self.bare_pull = crank * self.params.bare_reel_tension * lerpf(1.0, self.params.spent_reel_strain, self.worn());
        self.shake = minf(self.shake + crank * 0.2 * delta, 1.2);
    }

    /// 0 fresh .. 1 spent, as far as winding is concerned: a resting fish counts as spent, dead
    /// weight and a catch that never tires never are.
    pub fn worn(&self) -> f64 {
        if !self.profile.alive || self.profile.never_tires {
            return 0.0;
        }
        if self.behavior == Behavior::Resting {
            return 1.0;
        }
        1.0 - self.stamina
    }

    /// The share of the crank rate a bare reel wins right now (running: none).
    pub fn bare_reel_win(&self) -> f64 {
        match self.behavior {
            Behavior::Running => 0.0,
            Behavior::Resting if self.profile.alive && !self.profile.never_tires => self.params.rest_reel_fraction,
            _ => lerpf(self.params.bare_reel_fraction, self.params.spent_reel_fraction, self.worn()),
        }
    }

    /// THE RETRIEVE. Slack becomes line only while the reel is worked; what is left when the
    /// window shuts is lost.
    fn step_crank(&mut self, delta: f64, crank: f64) {
        if self.crank_left <= 0.0 {
            self.step_bare_reel(delta, crank);
            return;
        }
        self.bare_pull = 0.0;
        self.crank_left -= delta;
        if self.slack > 0.0 && crank > 0.01 {
            let taken = minf(crank * self.params.crank_rate * delta, self.slack);
            self.distance = maxf(self.distance - taken, 0.0);
            self.slack -= taken;
            self.shake = minf(self.shake + crank * 0.5 * delta, 1.2);
        }
        if self.slack <= 0.001 {
            self.slack = 0.0;
            self.crank_left = 0.0;
        } else if self.crank_left <= 0.0 {
            self.slack = 0.0;
        }
    }

    /// 0..perfect_yield. Harsh below the band: rate must never beat depth.
    fn pump_quality(&self, at: f64) -> f64 {
        if at < self.band_lo {
            return self.params.weak_yield * (at / maxf(self.band_lo, 0.001));
        }
        if at <= self.band_hi {
            return if self.is_perfect(at) { self.params.perfect_yield } else { 1.0 };
        }
        maxf(1.0 - (at - self.band_hi) * 2.4, self.params.weak_yield)
    }

    pub fn grade(&self, at: f64) -> Grade {
        if self.band_hi <= self.band_lo {
            return Grade::Late;
        }
        if at < self.band_lo {
            return Grade::Early;
        }
        if at > self.band_hi {
            return Grade::Late;
        }
        if self.is_perfect(at) { Grade::Perfect } else { Grade::Good }
    }

    pub fn is_perfect(&self, at: f64) -> bool {
        let half = (self.band_hi - self.band_lo) * self.params.perfect_fraction * 0.5;
        let mid = (self.band_lo + self.band_hi) * 0.5;
        at >= mid - half && at <= mid + half
    }

    /// Where the sweet spot starts: `is_perfect`'s lower edge, computed the same way.
    fn perfect_lo(&self) -> f64 {
        let half = (self.band_hi - self.band_lo) * self.params.perfect_fraction * 0.5;
        let mid = (self.band_lo + self.band_hi) * 0.5;
        mid - half
    }

    /// THE ARC as a moving target: high and narrow fresh, low and wide spent; shut on a run or
    /// a snag, when reaching for a pump is how the line goes.
    fn update_band(&mut self) {
        let tired = if self.profile.never_tires { 1.0 } else { self.stamina };
        let mut centre = lerpf(self.profile.band_centre_spent, self.profile.band_centre, tired);
        let mut width = lerpf(self.profile.band_width_spent, self.profile.band_width, tired);
        if self.behavior == Behavior::Running || self.behavior == Behavior::Snagged {
            centre = 0.0;
            width = 0.0;
        }
        self.band_lo = maxf(centre - width * 0.5, 0.0);
        self.band_hi = maxf(centre + width * 0.5, 0.0);
    }

    fn free_snag(&mut self) {
        self.behavior = Behavior::Holding;
        self.schedule_snag();
        self.overload_time = 0.0;
        self.load = 0.0;
        self.shake = 1.4;
        self.hitstop = self.params.hitstop_snag_free;
        self.tension = maxf(self.tension - 0.25, 0.0);
    }

    /// What the catch takes back between beats: a rush on a run, a steady drift otherwise.
    fn step_drift(&mut self, delta: f64, giving: bool) {
        if self.behavior == Behavior::Snagged {
            return;
        }
        let mut take = self.pull * self.params.distance_rate * self.params.give_factor_idle;
        if self.behavior == Behavior::Running {
            take = self.params.run_take;
            if giving {
                take *= self.params.give_run_damping;
            }
        } else if !self.profile.alive {
            take = self.pull * self.params.distance_rate * self.params.give_factor_dead;
        }
        self.distance += take * delta;
        self.distance_lost += take * delta;
    }

    /// Runs and rests are not scripted: your pumping panics it, its burst decides how long it
    /// can fight, its stamina how many times.
    fn step_alive(&mut self, delta: f64) {
        let wind_regen = self.profile.burst_regen / lerpf(self.params.spent_wind_penalty, 1.0, self.stamina);
        match self.behavior {
            Behavior::Running => {
                self.burst -= self.profile.burst_drain * delta;
                if self.burst <= 0.0 {
                    self.burst = 0.0;
                    self.behavior = Behavior::Resting;
                    self.stress = 0.0;
                }
            }
            Behavior::Resting => {
                self.burst = minf(self.burst + wind_regen * delta, 1.0);
                self.stress = maxf(self.stress - self.profile.panic_gain * delta, 0.0);
                if self.burst >= self.profile.burst_recover {
                    self.behavior = Behavior::Holding;
                }
            }
            _ => {
                // CHECKED BEFORE THE DECAY: a pump sets stress to exactly 1.0, and settling it
                // first made the trigger unreachable — FfC shipped a version with zero runs.
                if self.stress >= 1.0
                    && self.burst > 0.25
                    && (self.stamina > 0.0 || self.profile.never_tires)
                {
                    self.behavior = Behavior::Running;
                    self.runs += 1;
                    self.shake = 1.2;
                } else {
                    self.stress = maxf(self.stress - self.params.stress_settle * delta, 0.0);
                }
                self.burst = minf(self.burst + wind_regen * 0.5 * delta, 1.0);
            }
        }
    }

    fn step_dead(&mut self, delta: f64) {
        let _ = delta;
        if self.behavior == Behavior::Snagged {
            // Only the SET frees it; the duration is a mercy fallback, not the intended exit.
            if self.elapsed >= self.snag_until {
                self.behavior = Behavior::Holding;
                self.schedule_snag();
            }
            return;
        }
        if self.elapsed >= self.snag_at {
            self.behavior = Behavior::Snagged;
            self.snag_until = self.elapsed + self.profile.snag_duration;
        }
    }

    /// The catch's pull EASES toward its target: a run that began on one frame read as a glitch.
    fn step_pull(&mut self, delta: f64) {
        let target = self.target_pull();
        self.pull = move_toward(self.pull, target, self.params.pull_response * delta);
    }

    fn target_pull(&self) -> f64 {
        let mut f = self.profile.dead_load;
        if self.behavior == Behavior::Snagged {
            return f + self.profile.snag_load;
        }
        if !self.profile.alive {
            return f;
        }
        let tired = if self.profile.never_tires { 1.0 } else { self.stamina };
        let arc = lerpf(self.params.spent_power_floor, 1.0, tired);
        match self.behavior {
            Behavior::Running => f += self.profile.run_power * arc,
            Behavior::Resting => f += self.profile.rest_force,
            _ => f += self.profile.hold_force * arc,
        }
        f
    }

    /// THE LINE: tension tracks the load against a slipping drag.
    fn step_line(&mut self, delta: f64, giving: bool) {
        let p = self.params;
        let mut demand = self.load * p.load_to_tension + self.pull + self.bare_pull;
        if self.behavior == Behavior::Snagged {
            // Heaving on something immovable loads the ROD, not the line.
            demand = self.pull + self.load * p.load_to_tension * p.snag_load_transfer;
        }
        if p.deadlift {
            demand *= p.deadlift_load_mult;
            demand -= self.bare_pull * (p.deadlift_load_mult - 1.0);
            // The line is failing on its own and does not heal: a FLOOR that ratchets.
            self.deadlift_floor += p.deadlift_creep * delta;
        }
        // SHOCK, from the catch's pull alone.
        let pull_rate = (self.pull - self.pull_prev) / maxf(delta, 0.0001);
        if pull_rate > p.shock_threshold {
            self.tension += (pull_rate - p.shock_threshold) * p.shock_gain * delta;
        }
        self.pull_prev = self.pull;
        // Proportional, NOT move_toward: the drag could only slow a constant-rate climb.
        let mut rate = if demand > self.tension { p.tension_response } else { p.tension_release };
        if giving {
            rate = p.give_tension_relief;
            demand = minf(demand, self.pull);
        }
        self.tension += (demand - self.tension) * minf(rate * delta, 1.0);
        let drag = self.effective_drag();
        if self.tension > drag && self.behavior != Behavior::Snagged {
            // The spool can only give so fast: past drag_slip_max tension climbs again.
            let slip = minf((self.tension - drag) * p.drag_slip, p.drag_slip_max) * delta;
            self.tension -= slip;
            let paid = slip * p.slip_metres;
            self.distance += paid;
            self.distance_lost += paid;
        }
        if !self.overloading {
            self.fatigue = maxf(self.fatigue - p.fatigue_recover * delta, 0.0);
        }
        self.tension = maxf(self.tension, maxf(self.deadlift_floor, self.fatigue));
        // Clamped to THIS line's ceiling: a better line breaks later, not never.
        self.tension = clampf(self.tension, 0.0, p.snap_tension);
    }

    fn check_snap(&mut self, delta: f64) {
        if self.tension >= self.params.snap_tension {
            self.over_limit_time += delta;
            if self.over_limit_time >= self.params.snap_grace_seconds {
                self.state = State::Snapped;
            }
        } else {
            self.over_limit_time = 0.0;
        }
    }

    /// False until the button that set the hook has been let go once.
    pub fn is_armed(&self) -> bool {
        self.armed
    }

    /// Every field the next tick reads, by name, as f64 — what the golden file pins and the
    /// GDScript twin is compared on. Same names, same order, on both sides.
    pub fn snapshot(&self) -> Vec<(&'static str, f64)> {
        let b = |v: bool| if v { 1.0 } else { 0.0 };
        vec![
            ("state", self.state as u8 as f64),
            ("behavior", self.behavior as u8 as f64),
            ("distance", self.distance),
            ("start_distance", self.start_distance),
            ("tension", self.tension),
            ("load", self.load),
            ("band_lo", self.band_lo),
            ("band_hi", self.band_hi),
            ("slack", self.slack),
            ("fatigue", self.fatigue),
            ("overloading", b(self.overloading)),
            ("crank_left", self.crank_left),
            ("lateral", self.lateral),
            ("combo", self.combo as f64),
            ("best_combo", self.best_combo as f64),
            ("shake", self.shake),
            ("hitstop", self.hitstop),
            ("stress", self.stress),
            ("burst", self.burst),
            ("stamina", self.stamina),
            ("elapsed", self.elapsed),
            ("peak_tension", self.peak_tension),
            ("distance_lost", self.distance_lost),
            ("pumps_good", self.pumps_good as f64),
            ("pumps_total", self.pumps_total as f64),
            ("runs", self.runs as f64),
            ("giving", b(self.giving)),
            ("pull", self.pull),
            ("pull_prev", self.pull_prev),
            ("deadlift_floor", self.deadlift_floor),
            ("over_limit_time", self.over_limit_time),
            ("snag_at", self.snag_at),
            ("snag_until", self.snag_until),
            ("recover_until", self.recover_until),
            ("was_loading", b(self.was_loading)),
            ("armed", b(self.armed)),
            ("bare_pull", self.bare_pull),
            ("lat_target", self.lat_target),
            ("lat_timer", self.lat_timer),
            ("overload_time", self.overload_time),
            ("rng", self.rng as f64),
            ("ticks", self.ticks as f64),
        ]
    }

    pub fn effective_drag(&self) -> f64 {
        if self.params.perfect_set {
            self.params.drag_setting + self.params.perfect_drag_bonus
        } else {
            self.params.drag_setting
        }
    }

    /// Landed without the line ever near its limit, and not from a late hook-set.
    pub fn was_clean(&self) -> bool {
        self.state == State::Landed
            && !self.params.late_set
            && self.peak_tension <= self.params.clean_catch_max_peak_tension
    }
}

// =============================================================================================
// THE LOG: what the client submits, and the module replays
// =============================================================================================

/// `ticks` consecutive ticks of the same input.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Run {
    pub ticks: u32,
    pub loading: bool,
    pub giving: bool,
    pub crank: u8,
}

/// Most runs a submission may carry: a two-minute fight changing input every tick is 7200, and
/// nobody plays like that; this bounds what one reducer call makes the module do.
pub const MAX_RUNS: usize = 4096;

/// The log as it rides in `submit_challenge_result`'s float array: `[n, (ticks, flags, crank) × n]`,
/// flags bit 0 = PUMP, bit 1 = GIVE. Every value must be a whole number in range — a float that
/// is not is a forged submission, not a rounding error.
pub fn decode_log(values: &[f32]) -> Result<Vec<Run>, &'static str> {
    let whole = |v: f32, max: f32| -> Option<u32> {
        if v.is_finite() && v >= 0.0 && v <= max && v.fract() == 0.0 { Some(v as u32) } else { None }
    };
    let n = whole(*values.first().ok_or("no fight log")?, MAX_RUNS as f32).ok_or("bad run count")? as usize;
    if values.len() != 1 + n * 3 {
        return Err("fight log length does not match its run count");
    }
    let mut runs = Vec::with_capacity(n);
    let mut total: u64 = 0;
    for i in 0..n {
        let base = 1 + i * 3;
        let ticks = whole(values[base], max_ticks() as f32).ok_or("bad tick count")?;
        let flags = whole(values[base + 1], 3.0).ok_or("bad flags")?;
        let crank = whole(values[base + 2], 255.0).ok_or("bad crank")?;
        if ticks == 0 {
            return Err("an empty run");
        }
        total += ticks as u64;
        if total > max_ticks() as u64 {
            return Err("fight log longer than the longest fight");
        }
        runs.push(Run { ticks, loading: flags & 1 != 0, giving: flags & 2 != 0, crank: crank as u8 });
    }
    Ok(runs)
}

/// The inverse, for tests and bots.
pub fn encode_log(runs: &[Run]) -> Vec<f32> {
    let mut out = vec![runs.len() as f32];
    for r in runs {
        out.push(r.ticks as f32);
        out.push((r.loading as u32 | (r.giving as u32) << 1) as f32);
        out.push(r.crank as f32);
    }
    out
}

/// Play a submitted log through a fresh fight, from the hook-set (button still held). Stops
/// consuming input once the fight is decided; a log that ends first leaves it `Fighting`.
pub fn replay(params: FightParams, profile: Profile, seed: u32, cast_m: f64, runs: &[Run]) -> Fight {
    let mut f = Fight::new(params, profile, seed, cast_m, true);
    'log: for r in runs {
        for _ in 0..r.ticks {
            if f.state != State::Fighting {
                break 'log;
            }
            f.tick(r.loading, r.giving, r.crank);
        }
    }
    f
}
