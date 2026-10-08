//! THE FIGHT (`genre::fight`): its shape, measured with bots the way Fishing for Compliments'
//! tune probe measured it, and the golden file its GDScript twin must reproduce bit for bit.
//!
//!   cargo test --test fight                       check everything, golden included
//!   REGEN_FIGHT_GOLDEN=1 cargo test --test fight  rewrite shared/golden/fishing/fight.json
//!
//! Regenerate only after a DELIBERATE change to the fight or to fight.json, and ship the new file
//! with it: `tests/test_runner.gd` holds `game/fishing/fight_sim.gd` to it at max_err = 0.

// Fishing's rules exist only in a game made with fishing (shared/game.json, DECISIONS #173).
#![cfg(genre_fishing)]

use std::fmt::Write as _;

use umf_module::genre::fight::{
    self, decode_log, encode_log, fight_length, params_for, replay, Behavior, Fight, FightParams, Grade, Profile,
    Run, State,
};
use umf_module::genre::fishing::HookSet;

// --- bots: FfC's probe players ----------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq)]
enum Bot {
    /// Dead centre every beat, gives line on every run, heaves every snag, cranks flat out.
    Ace,
    /// Inside the band, but late in it: good pumps, few perfect ones.
    Good,
    /// Lets go short of the band.
    Sloppy,
    /// Never lets go.
    Masher,
    /// An ace who never gives line.
    Stubborn,
    /// Only ever winds: never loads the rod, never gives line. A pure reeler never tires a fish,
    /// so it must never out-fish heaving.
    Reeler,
}

/// What the bot presses this tick: (pump, give, crank 0..255).
fn decide(bot: Bot, f: &Fight) -> (bool, bool, u8) {
    if !f.is_armed() {
        return (false, false, 0); // let go of the click that set the hook
    }
    if bot == Bot::Masher {
        return (true, false, 0);
    }
    if bot == Bot::Reeler {
        return (false, false, 255);
    }
    if f.behavior == Behavior::Running {
        return if bot == Bot::Stubborn { (false, false, 255) } else { (false, true, 0) };
    }
    if f.behavior == Behavior::Snagged {
        return (true, false, 0); // THE SET
    }
    if f.slack > 0.001 {
        return (false, false, 255);
    }
    // READ THE FISH: while it rests after a run, wind â€” that is when the reel pays.
    if f.behavior == Behavior::Resting && matches!(bot, Bot::Ace | Bot::Good) {
        return (false, false, 255);
    }
    let (lo, hi) = (f.band_lo, f.band_hi);
    if hi <= lo {
        return (false, false, 255);
    }
    let target = match bot {
        Bot::Ace | Bot::Stubborn => (lo + hi) * 0.5,
        Bot::Good => lo + (hi - lo) * 0.85,
        Bot::Sloppy => lo * 0.7,
        Bot::Masher | Bot::Reeler => unreachable!(),
    };
    if f.load < target { (true, false, 0) } else { (false, false, 255) }
}

struct Played {
    fight: Fight,
    runs: Vec<Run>,
    /// Snapshots every `CHECK_EVERY` ticks, and the last one.
    checks: Vec<(u32, Vec<(&'static str, f64)>)>,
}

const CHECK_EVERY: u32 = 60;

fn play(params: FightParams, profile: Profile, seed: u32, cast_m: f64, bot: Bot) -> Played {
    let mut f = Fight::new(params, profile, seed, cast_m, true);
    let mut runs: Vec<Run> = Vec::new();
    let mut checks = Vec::new();
    while f.state == State::Fighting && f.ticks < fight::max_ticks() {
        let (l, g, c) = decide(bot, &f);
        match runs.last_mut() {
            Some(r) if r.loading == l && r.giving == g && r.crank == c => r.ticks += 1,
            _ => runs.push(Run { ticks: 1, loading: l, giving: g, crank: c }),
        }
        f.tick(l, g, c);
        if f.ticks % CHECK_EVERY == 0 {
            checks.push((f.ticks, f.snapshot()));
        }
    }
    checks.push((f.ticks, f.snapshot()));
    Played { fight: f, runs, checks }
}

fn prof(key: &str) -> Profile {
    *fight::profile(key).unwrap_or_else(|| panic!("no fight profile for {key}"))
}

/// FfC's REFERENCE FIGHT, the one its fight was tuned and measured on: the longest there is
/// (`fight_max_m`, 40 m), from any cast past 44.4 m. A 40 m cast is a 36 m fight now.
const REF_CAST: f64 = 45.0;

fn base() -> FightParams {
    params_for(0, 0, 0, HookSet::Good, false)
}

fn secs(f: &Fight) -> f64 {
    f.ticks as f64 / fight::TICK_HZ as f64
}

// --- the shape of it --------------------------------------------------------------------------

#[test]
fn every_catch_has_a_fight() {
    for key in umf_module::genre::fishing::CATCHES.iter().map(|c| c.id) {
        assert!(fight::profile(key).is_some(), "{key} has no fight profile");
    }
}

/// Median fight length for `bot` over a fixed set of seeds, and how many it landed.
fn median(key: &str, bot: Bot) -> (f64, usize) {
    let mut t: Vec<f64> = Vec::new();
    for seed in 1..=11 {
        let pl = play(base(), prof(key), seed, REF_CAST, bot);
        if pl.fight.state == State::Landed {
            t.push(secs(&pl.fight));
        }
    }
    t.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (if t.is_empty() { f64::INFINITY } else { t[t.len() / 2] }, t.len())
}

#[test]
fn the_ramp() {
    // THE RAMP IS THE POINT (FfC): a bigger catch sits its band higher and starts further out,
    // so the fight grows on both axes at once. On FfC's 40 m reference fight, measured with the
    // live tuning (`cargo test --test fight measure -- --ignored --nocapture` prints the table):
    // an ace lands a bluegill in ~14 s, a bass ~20, a pike ~31, a sturgeon ~54.
    let order = ["bluegill", "largemouth_bass", "northern_pike", "lake_sturgeon"];
    let mut last = 0.0;
    for key in order {
        let (t, landed) = median(key, Bot::Ace);
        assert_eq!(landed, 11, "an ace lands every {key}");
        assert!(t > last, "a {key} ({t:.1} s) is a longer fight than the catch before it ({last:.1} s)");
        last = t;
        let m = play(base(), prof(key), 7, REF_CAST, Bot::Masher);
        assert_eq!(m.fight.state, State::Snapped, "a masher never lets go, and snaps a {key}");
        assert!(secs(&m.fight) < 8.0, "and fast ({:.1} s)", secs(&m.fight));
    }
    // A bound, not a target: FfC's playtest wanted a bluegill in 8-10 s, then raised pump_stress
    // so runs happen on common catches too (GIVE LINE "felt like a dead button"). That costs a
    // bluegill ~4 s. Far past this is a regression, not a tuning choice.
    let (blue, _) = median("bluegill", Bot::Ace);
    assert!(blue < 20.0, "an ace's bluegill is still short ({blue:.1} s)");
    assert!(last < 90.0, "and even a sturgeon fits in a round ({last:.1} s)");
}

#[test]
fn rate_never_beats_depth() {
    // FfC's rule from the probe: spamming shallow pumps must not out-fish timing real ones. And
    // now that the reel pays when a fish is spent, WINDING ALONE must not either: a pure reeler
    // never tires a fish, so it never gets the good rate.
    for key in ["bluegill", "largemouth_bass", "northern_pike"] {
        let ace = play(base(), prof(key), 11, REF_CAST, Bot::Ace);
        let landed_in = |pl: &Played| if pl.fight.state == State::Landed { secs(&pl.fight) } else { f64::INFINITY };
        let sloppy = play(base(), prof(key), 11, REF_CAST, Bot::Sloppy);
        assert!(landed_in(&sloppy) > secs(&ace.fight),
            "{key}: releasing short of the band ({:?}, {:.1} s) is worse than the centre ({:.1} s)",
            sloppy.fight.state, landed_in(&sloppy), secs(&ace.fight));
        let reeler = play(base(), prof(key), 11, REF_CAST, Bot::Reeler);
        assert!(landed_in(&reeler) > 1.5 * secs(&ace.fight),
            "{key}: only winding ({:?}, {:.1} s) is far slower than heaving ({:.1} s)",
            reeler.fight.state, landed_in(&reeler), secs(&ace.fight));
    }
}

/// REEL ANY TIME; IT PAYS WHEN THE FISH IS SPENT. Two seconds flat out on the same reel, the fish
/// held in one state throughout: against a fresh fish it wins little and loads the line; spent, it
/// wins several times as much and barely strains it; resting, more still. Against a RUN it wins
/// nothing â€” the run takes line regardless â€” and only loads the line: give line instead.
#[test]
fn the_reel_pays_when_the_fish_is_spent() {
    let wind = |crank: u8, hold: &dyn Fn(&mut Fight)| -> (f64, f64) {
        let mut f = Fight::new(base(), prof("northern_pike"), 7, REF_CAST, false);
        hold(&mut f);
        let d0 = f.distance;
        let mut peak = 0.0f64;
        for _ in 0..120 {
            f.tick(false, false, crank);
            hold(&mut f);
            peak = peak.max(f.tension);
        }
        (d0 - f.distance, peak)
    };
    let fresh = |_: &mut Fight| {};
    let spent = |f: &mut Fight| f.stamina = 0.0;
    let resting = |f: &mut Fight| {
        f.behavior = Behavior::Resting;
        f.burst = 0.0;
    };
    let running = |f: &mut Fight| {
        f.behavior = Behavior::Running;
        f.burst = 1.0;
    };
    let (w_fresh, t_fresh) = wind(255, &fresh);
    let (w_spent, t_spent) = wind(255, &spent);
    let (w_rest, t_rest) = wind(255, &resting);
    let (w_run, t_run) = wind(255, &running);
    let (w_still, t_still) = wind(0, &running);
    println!("fresh {w_fresh:.2} m ({t_fresh:.2}), spent {w_spent:.2} m ({t_spent:.2}), resting {w_rest:.2} m \
        ({t_rest:.2}), running {w_run:.2} m ({t_run:.2}) vs not winding {w_still:.2} m ({t_still:.2})");
    assert!(w_spent > 3.0 * w_fresh.max(0.1), "spent pays: {w_spent:.2} m against {w_fresh:.2} m fresh");
    assert!(t_spent < t_fresh, "and strains the line less ({t_spent:.2} vs {t_fresh:.2})");
    assert!(w_rest > w_spent && t_rest < t_fresh, "resting pays most ({w_rest:.2} m)");
    assert!(w_run <= w_still + 1e-9, "winding against a run wins nothing ({w_run:.2} vs {w_still:.2} m)");
    assert!(t_run > t_still + 0.1, "and only loads the line ({t_run:.2} vs {t_still:.2})");
}

/// THE YELLOW (Luke: "it goes from yellow to sweet spot pretty quickly"). On a clean lift the band
/// shows for at least `band_approach_s` before its sweet spot, whatever the catch; under FfC's
/// lift a fresh sturgeon's flashed by in six frames.
#[test]
fn the_yellow_is_long_enough_to_see() {
    let yellow = |p: FightParams, key: &str| -> f64 {
        let mut f = Fight::new(p, prof(key), 1, REF_CAST, false);
        let (mut entered, mut sweet) = (None, None);
        for t in 0..600u32 {
            f.tick(true, false, 0);
            f.stress = 0.0;
            let g = f.grade(f.load);
            if entered.is_none() && g != Grade::Early {
                entered = Some(t);
            }
            if g == Grade::Perfect {
                sweet = Some(t);
                break;
            }
        }
        (sweet.expect("reached the sweet spot") - entered.expect("entered the band")) as f64 / fight::TICK_HZ as f64
    };
    let p = base();
    assert!(p.band_approach_s >= 0.3, "the file's floor is {} s", p.band_approach_s);
    for key in ["lake_sturgeon", "northern_pike", "largemouth_bass", "bluegill", "anvil"] {
        let y = yellow(p, key);
        assert!(y >= p.band_approach_s - 1.0 / 60.0, "{key}: {y:.2} s of yellow");
        assert!(y < p.band_approach_s + 0.35, "{key}: {y:.2} s of yellow is a stall, not a warning");
    }
    let mut ffc = p;
    ffc.band_approach_s = 0.0;
    assert!(yellow(ffc, "lake_sturgeon") < 0.15, "FfC's lift flashes the yellow on a fresh sturgeon");
}

#[test]
fn a_perfect_pump_is_a_perfect_grade_and_freezes_time() {
    let mut f = Fight::new(base(), prof("largemouth_bass"), 3, 30.0, false);
    // Load to the middle of the band and let go.
    while f.load < (f.band_lo + f.band_hi) * 0.5 {
        f.tick(true, false, 0);
    }
    let before = f.pumps_good;
    f.tick(false, false, 0);
    assert_eq!(f.last_grade, Some(Grade::Perfect));
    assert_eq!(f.pumps_good, before + 1);
    assert_eq!(f.combo, 1);
    assert!(f.slack > 0.0, "a release hands you slack, not line");
    // HIT-STOP: the next few ticks do not advance the fight's clock.
    let t = f.elapsed;
    for _ in 0..4 {
        f.tick(false, false, 255);
    }
    assert_eq!(f.elapsed, t, "a perfect pump freezes time for a few frames");
    for _ in 0..3 {
        f.tick(false, false, 255);
    }
    assert!(f.elapsed > t, "and then it runs again");
}

#[test]
fn slack_becomes_line_only_while_cranking() {
    let mut f = Fight::new(base(), prof("bluegill"), 5, 30.0, false);
    while f.load < (f.band_lo + f.band_hi) * 0.5 {
        f.tick(true, false, 0);
    }
    f.tick(false, false, 0);
    let d0 = f.distance;
    // Idle through the whole crank window: the slack goes, and the line never came in.
    for _ in 0..(fight::TICK_HZ * 2) {
        f.tick(false, false, 0);
    }
    assert_eq!(f.slack, 0.0, "slack not reeled down in the window is lost");
    assert!(f.distance >= d0, "and nothing came in without the crank ({d0:.2} -> {:.2})", f.distance);
}

#[test]
fn a_run_is_answered_by_giving_line() {
    // FfC: giving line cuts what a run takes to under a third. The stubborn ace never gives.
    let mut lost_give = 0.0;
    let mut lost_stub = 0.0;
    let mut runs = 0;
    for seed in 1..40 {
        let a = play(base(), prof("northern_pike"), seed, REF_CAST, Bot::Ace);
        let s = play(base(), prof("northern_pike"), seed, REF_CAST, Bot::Stubborn);
        runs += a.fight.runs;
        lost_give += a.fight.distance_lost;
        lost_stub += s.fight.distance_lost;
    }
    assert!(runs > 0, "pike RUN when pumped greedily â€” a fight with no runs is a metronome");
    assert!(lost_stub > lost_give * 1.3,
        "not giving line on runs loses more line ({lost_stub:.1} m vs {lost_give:.1} m)");
}

#[test]
fn junk_snags_and_only_the_set_frees_it() {
    // Dead weight snags; a snag closes the band; loading past snag_break_load frees it.
    let p = base();
    let mut f = Fight::new(p, prof("barrel"), 9, 30.0, false);
    let mut snagged_at = None;
    while f.state == State::Fighting && f.ticks < fight::max_ticks() {
        if f.behavior == Behavior::Snagged {
            snagged_at = Some(f.ticks);
            break;
        }
        f.tick(false, false, 0);
    }
    let at = snagged_at.expect("a barrel snags within the fight");
    assert!(f.band_hi <= f.band_lo, "a snag closes the band");
    while f.behavior == Behavior::Snagged && f.load < p.snag_break_load {
        f.tick(true, false, 0);
    }
    assert_eq!(f.behavior, Behavior::Holding, "heaving to {:.2} set it free (snagged at tick {at})", p.snag_break_load);
    let ace = play(p, prof("barrel"), 9, 30.0, Bot::Ace);
    assert_eq!(ace.fight.state, State::Landed, "and an ace lands the barrel");
}

#[test]
fn a_deadlift_is_a_timer() {
    // Over the line's rating the line fails on its own: a ratcheting floor under the tension.
    // FfC: "an ~11.5 s timer a clean rhythm CAN beat". Whatever happens, it is over by then.
    let p = params_for(0, 0, 0, HookSet::Good, true);
    let a = play(p, prof("anvil"), 4, 20.0, Bot::Ace);
    assert!(a.fight.state != State::Fighting, "a deadlift ends");
    assert!(secs(&a.fight) < 12.5, "inside the timer ({:.1} s, {:?})", secs(&a.fight), a.fight.state);
    let slow = play(p, prof("anvil"), 4, REF_CAST, Bot::Good);
    let easy = play(params_for(0, 0, 4, HookSet::Good, false), prof("anvil"), 4, REF_CAST, Bot::Good);
    assert!(easy.fight.state == State::Landed && secs(&easy.fight) > 12.5,
        "the same anvil on a line rated for it is a long fight, not a timer ({:.1} s, {:?})",
        secs(&easy.fight), easy.fight.state);
    assert!(slow.fight.state == State::Snapped || secs(&slow.fight) < 12.5,
        "and on the starting line the timer ends it first ({:?} at {:.1} s)", slow.fight.state, secs(&slow.fight));
}

#[test]
fn gear_changes_the_fight() {
    // ROD: more line per pump. REEL: the crank takes slack faster. LINE: snaps later.
    let key = prof("northern_pike");
    let lift = |rod: u8| -> f64 {
        let mut f = Fight::new(params_for(rod, 0, 0, HookSet::Good, false), key, 21, REF_CAST, false);
        while f.load < (f.band_lo + f.band_hi) * 0.5 {
            f.tick(true, false, 0);
        }
        f.tick(false, false, 0);
        f.slack
    };
    assert!(lift(4) > 1.7 * lift(0), "the best rod lifts more line per pump ({:.2} m vs {:.2} m)", lift(4), lift(0));
    // FfC: "the rod is the lever, the reel is the winch". On the starting reel most of what a big
    // rod lifts is lost when the window shuts; with a reel to wind it in, it lands a big fish in
    // fewer pumps, and sooner.
    let sturgeon = prof("lake_sturgeon");
    let t0 = play(params_for(0, 4, 0, HookSet::Good, false), sturgeon, 21, REF_CAST, Bot::Ace);
    let rod = play(params_for(4, 4, 0, HookSet::Good, false), sturgeon, 21, REF_CAST, Bot::Ace);
    assert!(rod.fight.pumps_total < t0.fight.pumps_total && secs(&rod.fight) < secs(&t0.fight),
        "with the best reel, the best rod lands a sturgeon in fewer pumps ({} vs {}) and sooner ({:.1} s vs {:.1} s)",
        rod.fight.pumps_total, t0.fight.pumps_total, secs(&rod.fight), secs(&t0.fight));
    let masher0 = play(params_for(0, 0, 0, HookSet::Good, false), key, 21, REF_CAST, Bot::Masher);
    let masher4 = play(params_for(0, 0, 4, HookSet::Good, false), key, 21, REF_CAST, Bot::Masher);
    assert!(secs(&masher4.fight) > secs(&masher0.fight),
        "the best line holds a masher longer ({:.2} s vs {:.2} s)", secs(&masher4.fight), secs(&masher0.fight));
    let p = params_for(0, 4, 0, HookSet::Good, false);
    assert!(p.crank_rate > base().crank_rate, "the best reel cranks faster");
}

#[test]
fn the_hook_set_carries_into_the_fight() {
    let late = Fight::new(params_for(0, 0, 0, HookSet::Late, false), prof("bluegill"), 1, 20.0, true);
    let perfect = Fight::new(params_for(0, 0, 0, HookSet::Perfect, false), prof("bluegill"), 1, 20.0, true);
    assert!(late.tension > 0.3, "a late hook-set starts with the line loaded ({:.2})", late.tension);
    assert!(perfect.effective_drag() > late.effective_drag(), "a perfect one starts with more drag");
    let clean = play(params_for(0, 0, 0, HookSet::Late, false), prof("bluegill"), 1, 20.0, Bot::Ace);
    assert!(!clean.fight.was_clean(), "and a late one is never a clean catch");
}

#[test]
fn deterministic_and_seeded() {
    let a = play(base(), prof("largemouth_bass"), 99, 30.0, Bot::Ace);
    let b = play(base(), prof("largemouth_bass"), 99, 30.0, Bot::Ace);
    assert_eq!(a.checks.len(), b.checks.len());
    for ((ta, sa), (tb, sb)) in a.checks.iter().zip(b.checks.iter()) {
        assert_eq!(ta, tb);
        for ((na, va), (_, vb)) in sa.iter().zip(sb.iter()) {
            assert_eq!(va.to_bits(), vb.to_bits(), "{na} differs at tick {ta} between two identical runs");
        }
    }
    let c = play(base(), prof("largemouth_bass"), 100, 30.0, Bot::Ace);
    let lat = |p: &Played| p.checks.iter().map(|(_, s)| s.iter().find(|(n, _)| *n == "lat_target").unwrap().1).collect::<Vec<_>>();
    assert_ne!(lat(&a), lat(&c), "another seed wanders another way");
}

#[test]
fn the_log_round_trips_and_replays() {
    let played = play(base(), prof("northern_pike"), 13, 36.5, Bot::Ace);
    let wire = encode_log(&played.runs);
    let runs = decode_log(&wire).expect("a log we encoded decodes");
    assert_eq!(runs, played.runs);
    let again = replay(base(), prof("northern_pike"), 13, 36.5, &runs);
    assert_eq!(again.state, played.fight.state, "the replay reaches the same end");
    assert_eq!(again.ticks, played.fight.ticks, "on the same tick");
    for ((n, a), (_, b)) in again.snapshot().iter().zip(played.fight.snapshot().iter()) {
        assert_eq!(a.to_bits(), b.to_bits(), "and the same {n}");
    }
    // A log that stops early leaves the fight undecided; one that runs on changes nothing.
    let cut = replay(base(), prof("northern_pike"), 13, 36.5, &runs[..runs.len() / 2]);
    assert_eq!(cut.state, State::Fighting, "a truncated log lands nothing");
    let mut long = runs.clone();
    long.push(Run { ticks: 600, loading: true, giving: false, crank: 0 });
    assert_eq!(replay(base(), prof("northern_pike"), 13, 36.5, &long).ticks, played.fight.ticks,
        "input after the end is ignored");
}

#[test]
fn a_forged_log_is_refused() {
    assert!(decode_log(&[]).is_err(), "nothing at all");
    assert!(decode_log(&[1.0, 10.0, 1.0]).is_err(), "a run cut short");
    assert!(decode_log(&[1.0, 10.5, 1.0, 0.0]).is_err(), "half a tick");
    assert!(decode_log(&[1.0, 10.0, 4.0, 0.0]).is_err(), "flags that mean nothing");
    assert!(decode_log(&[1.0, 10.0, 1.0, 256.0]).is_err(), "a crank past flat out");
    assert!(decode_log(&[1.0, 0.0, 1.0, 0.0]).is_err(), "an empty run");
    assert!(decode_log(&[1.0, f32::NAN, 1.0, 0.0]).is_err(), "not a number");
    let too_long = fight::max_ticks() as f32 + 1.0;
    assert!(decode_log(&[1.0, too_long, 1.0, 0.0]).is_err(), "longer than the longest fight");
    assert!(decode_log(&[2.0, 7000.0, 1.0, 0.0, 7000.0, 0.0, 0.0]).is_err(), "longer, in two runs");
    assert_eq!(decode_log(&[1.0, 60.0, 3.0, 255.0]).unwrap(),
        vec![Run { ticks: 60, loading: true, giving: true, crank: 255 }]);
}

// --- the golden file --------------------------------------------------------------------------

struct Case {
    name: &'static str,
    catch: &'static str,
    gear: (u8, u8, u8),
    hookset: HookSet,
    deadlift: bool,
    cast_cm: u32,
    seed: u32,
    bot: Bot,
}

/// Every branch the fight has, somewhere in here: alive and dead, runs and rests, snags and the
/// set, perfect/good/early/late pumps, hit-stop, the bare reel, a deadlift's ratchet, a snap.
fn cases() -> Vec<Case> {
    let c = |name, catch, gear, hookset, deadlift, cast_cm, seed, bot| Case {
        name, catch, gear, hookset, deadlift, cast_cm, seed, bot,
    };
    vec![
        c("bluegill_ace", "bluegill", (0, 0, 0), HookSet::Perfect, false, 1840, 1, Bot::Ace),
        c("bass_good", "largemouth_bass", (1, 1, 1), HookSet::Good, false, 2215, 2, Bot::Good),
        c("pike_ace_runs", "northern_pike", (2, 2, 2), HookSet::Good, false, 3050, 3, Bot::Ace),
        c("pike_stubborn", "northern_pike", (0, 0, 0), HookSet::Good, false, 2400, 4, Bot::Stubborn),
        c("sturgeon_ace", "lake_sturgeon", (4, 4, 4), HookSet::Perfect, false, 5200, 5, Bot::Ace),
        c("marlin_deadlift", "lake_marlin", (4, 0, 0), HookSet::Good, true, 4700, 6, Bot::Ace),
        c("bass_masher", "largemouth_bass", (0, 0, 0), HookSet::Late, false, 2000, 7, Bot::Masher),
        c("bluegill_sloppy", "bluegill", (0, 0, 0), HookSet::Late, false, 1500, 8, Bot::Sloppy),
        c("barrel_ace_snags", "barrel", (1, 0, 1), HookSet::Good, false, 2600, 9, Bot::Ace),
        c("anvil_deadlift", "anvil", (0, 0, 0), HookSet::Good, true, 2000, 10, Bot::Good),
        c("tankard_ace", "tankard", (0, 0, 0), HookSet::Perfect, false, 900, 11, Bot::Ace),
        c("chest_good", "legendary_chest", (3, 3, 3), HookSet::Good, false, 4100, 12, Bot::Good),
        c("koi_sloppy", "golden_koi", (2, 1, 0), HookSet::Good, false, 3300, 13, Bot::Sloppy),
    ]
}

fn hex(v: f64) -> String {
    v.to_le_bytes().iter().map(|b| format!("{b:02x}")).collect()
}

fn hookset_word(h: HookSet) -> &'static str {
    match h {
        HookSet::Perfect => "perfect",
        HookSet::Good => "good",
        HookSet::Late => "late",
    }
}

fn golden_text() -> String {
    let mut out = String::new();
    out.push_str("{\n \"name\": \"fight\",\n");
    out.push_str(" \"_comment\": \"GENERATED by server/tests/fight.rs (REGEN_FIGHT_GOLDEN=1). genre::fight and game/fishing/fight_sim.gd must reproduce every value exactly: each is the little-endian bytes of an f64, in hex. Inputs are run-length encoded [ticks, flags (1 pump, 2 give), crank 0..255].\",\n");
    // The numbers both sides must have parsed identically before anything else can agree.
    out.push_str(" \"constants\": {");
    let b = fight::BASE;
    let consts = [
        ("load_rate", b.load_rate), ("drag_setting", b.drag_setting), ("pump_stress", b.pump_stress),
        ("give_run_damping", b.give_run_damping), ("deadlift_creep", b.deadlift_creep),
        ("cast_to_fight", b.cast_to_fight), ("fight_min_m", b.fight_min_m), ("fight_max_m", b.fight_max_m),
        ("dt", fight::dt()),
    ];
    for (i, (k, v)) in consts.iter().enumerate() {
        let _ = write!(out, "{}\"{k}\": \"{}\"", if i > 0 { ", " } else { "" }, hex(*v));
    }
    out.push_str("},\n \"cases\": [\n");
    let all = cases();
    for (ci, c) in all.iter().enumerate() {
        let p = params_for(c.gear.0, c.gear.1, c.gear.2, c.hookset, c.deadlift);
        let played = play(p, prof(c.catch), c.seed, c.cast_cm as f64 / 100.0, c.bot);
        let _ = write!(out, "  {{\"name\": \"{}\", \"catch\": \"{}\", \"rod\": {}, \"reel\": {}, \"line\": {}, \"hookset\": \"{}\", \"deadlift\": {}, \"cast_cm\": {}, \"seed\": {},\n",
            c.name, c.catch, c.gear.0, c.gear.1, c.gear.2, hookset_word(c.hookset), c.deadlift, c.cast_cm, c.seed);
        let runs: Vec<String> = played.runs.iter()
            .map(|r| format!("[{},{},{}]", r.ticks, r.loading as u32 | (r.giving as u32) << 1, r.crank))
            .collect();
        let _ = write!(out, "   \"runs\": [{}],\n", runs.join(","));
        out.push_str("   \"checks\": [\n");
        for (ki, (tick, snap)) in played.checks.iter().enumerate() {
            let fields: Vec<String> = snap.iter().map(|(n, v)| format!("\"{n}\": \"{}\"", hex(*v))).collect();
            let _ = write!(out, "    {{\"tick\": {tick}, {}}}{}\n", fields.join(", "),
                if ki + 1 < played.checks.len() { "," } else { "" });
        }
        let _ = write!(out, "   ]}}{}\n", if ci + 1 < all.len() { "," } else { "" });
    }
    out.push_str(" ]\n}\n");
    out
}

#[test]
fn golden_file_is_current() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/golden/fishing/fight.json");
    let now = golden_text();
    if std::env::var("REGEN_FIGHT_GOLDEN").is_ok() {
        std::fs::write(&path, &now).unwrap();
        eprintln!("wrote {}", path.display());
        return;
    }
    let was = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| panic!("{} is missing: REGEN_FIGHT_GOLDEN=1 cargo test --test fight", path.display()))
        .replace("\r\n", "\n");
    assert!(was == now, "the fight no longer reproduces shared/golden/fishing/fight.json. If the change \
        was deliberate, regenerate it (REGEN_FIGHT_GOLDEN=1) and ship it with the GDScript twin's update.");
}

#[test]
fn golden_cases_cover_the_fight() {
    // A golden file that never snags or never runs holds the twin to nothing there.
    let mut landed = 0;
    let mut snapped = 0;
    let (mut runs, mut snags_freed, mut perfect, mut early_or_late, mut hitstops) = (0, 0, 0, 0, 0);
    for c in cases() {
        let p = params_for(c.gear.0, c.gear.1, c.gear.2, c.hookset, c.deadlift);
        let played = play(p, prof(c.catch), c.seed, c.cast_cm as f64 / 100.0, c.bot);
        match played.fight.state {
            State::Landed => landed += 1,
            State::Snapped => snapped += 1,
            State::Fighting => panic!("{} never ended", c.name),
        }
        runs += played.fight.runs;
        perfect += played.fight.pumps_good;
        early_or_late += played.fight.pumps_total - played.fight.pumps_good;
        let snap_names: Vec<f64> = played.checks.iter().map(|(_, s)| s[1].1).collect();
        if snap_names.contains(&(Behavior::Snagged as u8 as f64)) {
            snags_freed += 1;
        }
        if played.checks.iter().any(|(_, s)| s.iter().any(|(n, v)| *n == "hitstop" && *v > 0.0)) {
            hitstops += 1;
        }
    }
    assert!(landed >= 8 && snapped >= 2, "landings {landed} and snaps {snapped}");
    assert!(runs >= 3, "runs happen ({runs})");
    assert!(snags_freed >= 1, "a snag is seen in the checkpoints ({snags_freed})");
    assert!(perfect >= 10 && early_or_late >= 5, "perfect ({perfect}) and imperfect ({early_or_late}) pumps");
    assert!(hitstops >= 1, "hit-stop is in the file ({hitstops})");
    // The reel's other half: a fish resting after a run, which the ace winds in.
    let resting = cases().iter().filter(|c| {
        let p = params_for(c.gear.0, c.gear.1, c.gear.2, c.hookset, c.deadlift);
        play(p, prof(c.catch), c.seed, c.cast_cm as f64 / 100.0, c.bot).checks.iter()
            .any(|(_, s)| s[1].1 == Behavior::Resting as u8 as f64)
    }).count();
    assert!(resting >= 1, "a fish rests in the checkpoints ({resting})");
    // The cast's length rule, at both of its clamps and between them.
    let b = fight::BASE;
    let lengths: Vec<f64> = cases().iter().map(|c| c.cast_cm as f64 / 100.0 * b.cast_to_fight).collect();
    assert!(lengths.iter().any(|l| *l < b.fight_min_m), "a lob shorter than the shortest fight");
    assert!(lengths.iter().any(|l| *l > b.fight_max_m), "a cast longer than the longest fight");
    assert!(lengths.iter().any(|l| *l > b.fight_min_m && *l < b.fight_max_m), "and casts between");
}

/// THE CAST IS THE FIGHT LENGTH (FfC's rig), inside the range the fight was tuned for: a lob off
/// the dock is still a fight, and the best rod's longest cast is not a slog past what was tuned.
/// A catch then starts its own share of it (`distance_scale`).
#[test]
fn the_cast_is_the_fight_length() {
    let p = base();
    let bass = prof("largemouth_bass");
    let start = |cast: f64| Fight::new(p, bass, 1, cast, true).start_distance;
    assert_eq!((p.cast_to_fight, p.fight_min_m, p.fight_max_m), (0.9, 10.0, 40.0), "FfC's numbers");
    // A 4 m lob and an 11 m cast are the same, shortest, fight.
    assert_eq!(start(4.0), start(11.0));
    assert_eq!(start(4.0), fight_length(&p, 4.0) * bass.distance_scale);
    assert_eq!(fight_length(&p, 4.0), 10.0);
    // Between the clamps it is the cast.
    assert_eq!(fight_length(&p, 30.0), 30.0 * 0.9);
    assert!(start(11.2) > start(11.0) && start(20.0) > start(11.2) && start(30.0) > start(20.0));
    // The best rod's reach fights FfC's reference fight, and no longer.
    assert_eq!(start(55.0), start(REF_CAST));
    assert_eq!(fight_length(&p, 55.0), 40.0);
    // A longer cast is a longer fight, for the same angler on the same fish.
    let near = play(p, bass, 3, 12.0, Bot::Ace);
    let far = play(p, bass, 3, 40.0, Bot::Ace);
    assert!(near.fight.state == State::Landed && far.fight.state == State::Landed, "both landed");
    assert!(secs(&far.fight) > secs(&near.fight) * 1.5,
        "a 40 m cast ({:.1} s) is a longer fight than a 12 m one ({:.1} s)", secs(&far.fight), secs(&near.fight));
}

/// FfC's tune probe, here: every bot against the ramp's catches, at the live pump_stress and at
/// the 0.50 FfC's fight.toml documented (which is what its MEASURED table was taken at â€” this
/// port reproduces that table within a second on bluegill and bass).
#[test]
#[ignore]
fn measure() {
    for key in ["bluegill", "largemouth_bass", "northern_pike", "lake_sturgeon", "barrel", "anvil"] {
        for stress in [0.50, 0.72] {
            let mut line = format!("{key:16} stress {stress:.2}:");
            for bot in [Bot::Masher, Bot::Sloppy, Bot::Good, Bot::Ace] {
                let mut t = Vec::new();
                let mut outcomes = (0, 0);
                let mut runs = 0;
                let mut pumps = 0;
                for seed in 1..=21 {
                    let mut p = base();
                    p.pump_stress = stress;
                    let pl = play(p, prof(key), seed, REF_CAST, bot);
                    if pl.fight.state == State::Landed { outcomes.0 += 1; t.push(secs(&pl.fight)); } else { outcomes.1 += 1; }
                    runs += pl.fight.runs;
                    pumps += pl.fight.pumps_total;
                }
                t.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let med = if t.is_empty() { f64::NAN } else { t[t.len() / 2] };
                line.push_str(&format!("  {bot:?} {}/{} med {med:5.1}s runs {runs:3} pumps {pumps:4} |", outcomes.0, outcomes.0 + outcomes.1));
            }
            println!("{line}");
        }
    }
}


/// THE YELLOW, measured: how long the band shows before its sweet spot on a clean lift, fresh and
/// spent, and what a floor on it (`band_approach_s`) does to whole fights.
///   cargo test --test fight approach -- --ignored --nocapture
#[test]
#[ignore]
fn approach() {
    let lift = |p: FightParams, key: &str, spent: bool| -> (f64, f64) {
        let mut f = Fight::new(p, prof(key), 1, REF_CAST, false);
        if spent {
            f.stamina = 0.0;
        }
        let (mut entered, mut sweet, mut left) = (None, None, None);
        for t in 0..600u32 {
            f.tick(true, false, 0);
            // Keep it a lift: no runs, no drift of the band while we time it.
            f.stress = 0.0;
            let g = f.grade(f.load);
            if entered.is_none() && g != Grade::Early { entered = Some(t); }
            if sweet.is_none() && g == Grade::Perfect { sweet = Some(t); }
            if sweet.is_some() && left.is_none() && g != Grade::Perfect { left = Some(t); }
            if left.is_some() { break; }
        }
        let tick = 1.0 / fight::TICK_HZ as f64;
        let e = entered.unwrap_or(0);
        let s0 = sweet.unwrap_or(e);
        ((s0 - e) as f64 * tick, (left.unwrap_or(s0) - s0) as f64 * tick)
    };
    for approach in [0.0, 0.35, 0.6] {
        let mut p = base();
        p.band_approach_s = approach;
        println!("== band_approach_s {approach:.2}");
        for key in ["bluegill", "largemouth_bass", "northern_pike", "lake_sturgeon", "barrel", "anvil"] {
            let (fy, fc) = lift(p, key, false);
            let (sy, sc) = lift(p, key, true);
            let mut line = format!("  {key:16} yellow {fy:.2}s cyan {fc:.2}s fresh | {sy:.2}s {sc:.2}s spent |");
            for bot in [Bot::Good, Bot::Ace, Bot::Reeler] {
                let mut t = Vec::new();
                let (mut landed, mut perfect, mut pumps) = (0, 0, 0);
                for seed in 1..=21 {
                    let pl = play(p, prof(key), seed, REF_CAST, bot);
                    if pl.fight.state == State::Landed { landed += 1; t.push(secs(&pl.fight)); }
                    perfect += pl.fight.pumps_good;
                    pumps += pl.fight.pumps_total;
                }
                t.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let med = if t.is_empty() { f64::NAN } else { t[t.len() / 2] };
                line.push_str(&format!(" {bot:?} {landed:2}/21 {med:5.1}s perf {perfect:3}/{pumps:3} |"));
            }
            println!("{line}");
        }
    }
}

/// The reel's two new numbers against the gear: median seconds for an ace on each rod/reel pair
/// and a good angler on the starting kit, at several settings.
///   cargo test --test fight reel_probe -- --ignored --nocapture
#[test]
#[ignore]
fn reel_probe() {
    for (rest, spent) in [(0.75, 0.60), (0.50, 0.45), (0.40, 0.35), (0.30, 0.30)] {
        println!("== rest {rest:.2} spent {spent:.2}");
        for key in ["bluegill", "largemouth_bass", "northern_pike", "lake_sturgeon"] {
            let mut line = format!("  {key:16}");
            for (rod, reel, bot) in [(0u8, 0u8, Bot::Ace), (4, 0, Bot::Ace), (0, 4, Bot::Ace), (4, 4, Bot::Ace), (0, 0, Bot::Good)] {
                let mut t = Vec::new();
                for seed in 1..=21 {
                    let mut p = params_for(rod, reel, 0, HookSet::Good, false);
                    p.rest_reel_fraction = rest;
                    p.spent_reel_fraction = spent;
                    let pl = play(p, prof(key), seed, REF_CAST, bot);
                    if pl.fight.state == State::Landed { t.push(secs(&pl.fight)); }
                }
                t.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let med = if t.is_empty() { f64::NAN } else { t[t.len() / 2] };
                line.push_str(&format!(" {bot:?} r{rod}/{reel} {med:5.1}s |"));
            }
            println!("{line}");
        }
    }
}
