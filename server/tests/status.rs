//! STATUSES (DECISIONS #206): what the foundation's statuses let an entity do, and the Tier A bound
//! each gives: a crawl, a burst that ends, a grace after a change that ends too.

use umf_module::content::{MovementLimits, DEFAULT_LIMITS};
use umf_module::status::{self, applied, bound, find, normal};

const KIND: MovementLimits = MovementLimits { run: 5.0, sprint: 8.0, burst: 3.0, lift: 8.0 };

#[test]
fn the_foundation_has_its_seven() {
    let names: Vec<(u8, &str)> = (0..=6).map(|n| (n, find(n).expect("a foundation status").name)).collect();
    assert_eq!(names, vec![(0, "Normal"), (1, "Injured"), (2, "Downed"), (3, "Carried"), (4, "Out"), (5, "Hidden"), (6, "Escaped")]);
    assert_eq!(normal().status, status::NORMAL);
}

#[test]
fn normal_changes_nothing() {
    assert_eq!(applied(KIND, normal(), false), KIND);
    assert_eq!(applied(DEFAULT_LIMITS, normal(), true), DEFAULT_LIMITS, "normal has no burst");
}

#[test]
fn downed_crawls_and_ends_in_out() {
    let d = find(status::DOWNED).unwrap();
    let b = applied(KIND, d, false);
    // A game may replace Downed with its own (Fowl Play's crawls at 0.3 for 120 s): its own numbers.
    assert_eq!(b.run, KIND.run * d.speed);
    assert!(d.speed < 1.0, "a crawl");
    assert_eq!(b.sprint, b.run, "no sprint: bounded by its crawl");
    assert_eq!(b.burst, 0.0, "no dash");
    assert_eq!(b.lift, b.sprint, "no jump: it climbs only what it crawls up");
    assert!(!d.can_act && d.targetable);
    assert!(!d.hittable, "a downed player is not hit again (DECISIONS #226), though they can be helped up");
    assert!(find(status::NORMAL).unwrap().hittable && find(status::INJURED).unwrap().hittable, "a standing one is");
    assert!(!find(status::CARRIED).unwrap().hittable, "nor one being carried");
    assert!(d.lasts_ms > 0 && d.then == status::OUT, "it ends, in out");
}

#[test]
fn out_and_escaped_cannot_move_or_be_reached() {
    for n in [status::OUT, status::ESCAPED] {
        let s = find(n).unwrap();
        let b = applied(KIND, s, false);
        assert_eq!((b.run, b.sprint, b.burst, b.lift), (0.0, 0.0, 0.0, 0.0), "{}", s.name);
        assert!(!s.can_act && !s.targetable, "{}", s.name);
    }
}

#[test]
fn an_injury_bursts_then_ends() {
    let inj = find(status::INJURED).unwrap();
    let start = bound(KIND, inj, inj, 0, 0);
    assert!(inj.burst > 1.0 && inj.burst_ms > 0, "a hit player runs for it");
    assert_eq!(start.sprint, KIND.sprint * inj.burst);
    let mid = bound(KIND, inj, inj, inj.burst_ms as i64 - 1, 0);
    assert_eq!(mid.sprint, KIND.sprint * inj.burst);
    let after = bound(KIND, inj, inj, inj.burst_ms as i64, 0);
    assert_eq!(after, KIND, "and the burst ends on time");
}

#[test]
fn the_grace_after_a_change_is_the_wider_and_ends() {
    let d = find(status::DOWNED).unwrap();
    let n = normal();
    let early = bound(KIND, d, n, 100, 500);
    assert_eq!(early, KIND, "inside the grace a downed player may still move as it did");
    let late = bound(KIND, d, n, 500, 500);
    assert_eq!(late, applied(KIND, d, false), "after it, a crawl");
    let none = bound(KIND, d, n, 0, 0);
    assert_eq!(none, applied(KIND, d, false), "no grace: the change binds at once");
}
