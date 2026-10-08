//! Runs shared/golden/challenge_timing.json against the pure `challenge` validator. The Godot
//! test runner executes the same file against `foundation/sim/challenge_model.gd`. Both must
//! read `max_err=0`; a small non-zero value is a parity bug, not a pass.
//!   cargo test --test challenge

use serde::Deserialize;
use std::{fs, path::Path};
use umf_module::challenge::{timing_centers, timing_half_width, validate_challenge, TIMING_ROUNDS};

#[derive(Deserialize)]
struct Doc {
    name: String,
    model_version: String,
    #[serde(default = "default_tol")]
    tolerance: f32,
    cases: Vec<Case>,
    rejects: Vec<Reject>,
}
fn default_tol() -> f32 {
    1e-5
}

fn join_seed(hi: u32, lo: u32) -> u64 {
    ((hi as u64) << 32) | (lo as u64)
}

#[derive(Deserialize)]
struct Case {
    name: String,
    kind: u8,
    /// Seeds are split into 32-bit halves in the golden file: a u64 above 2^53 cannot
    /// round-trip through JSON into GDScript's int64, and both harnesses read the same file.
    seed_hi: u32,
    seed_lo: u32,
    difficulty: f32,
    result: Vec<f32>,
    expected_centers: Vec<f32>,
    expected_half_width: f32,
    expected_quality: f32,
}

#[derive(Deserialize)]
struct Reject {
    name: String,
    kind: u8,
    seed_hi: u32,
    seed_lo: u32,
    difficulty: f32,
    result: Vec<f32>,
}

#[test]
fn challenge_vectors_match() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/golden/challenge/challenge_timing.json");
    let text = fs::read_to_string(&path).expect("shared/golden/challenge_timing.json missing");
    let doc: Doc = serde_json::from_str(&text).expect("bad challenge golden JSON");

    println!(
        "{} (model={}, {} cases, {} rejects)",
        doc.name,
        doc.model_version,
        doc.cases.len(),
        doc.rejects.len()
    );

    let mut failures = 0;
    for c in &doc.cases {
        let mut worst = 0.0f32;

        let seed = join_seed(c.seed_hi, c.seed_lo);
        let centers = timing_centers(seed);
        assert_eq!(c.expected_centers.len(), TIMING_ROUNDS, "{}: bad vector", c.name);
        for i in 0..TIMING_ROUNDS {
            worst = worst.max((centers[i] - c.expected_centers[i]).abs());
        }

        let half = timing_half_width(c.difficulty);
        worst = worst.max((half - c.expected_half_width).abs());

        let quality = validate_challenge(c.kind, seed, c.difficulty, &c.result)
            .unwrap_or_else(|| panic!("{}: validator rejected a valid case", c.name));
        worst = worst.max((quality - c.expected_quality).abs());

        let ok = worst <= doc.tolerance;
        if !ok {
            failures += 1;
        }
        println!("  {:<24} {}  max_err={:e}", c.name, if ok { "ok " } else { "BAD" }, worst);
        assert!(
            ok,
            "{}: quality {} expected {} (max_err {:e})",
            c.name, quality, c.expected_quality, worst
        );
        // The whole point of the harness: bit-equality, not "close enough".
        assert_eq!(worst, 0.0, "{}: drifted from the golden vector by {:e}", c.name, worst);
    }

    for r in &doc.rejects {
        let got = validate_challenge(r.kind, join_seed(r.seed_hi, r.seed_lo), r.difficulty, &r.result);
        assert!(
            got.is_none(),
            "reject case {} was accepted with quality {:?}",
            r.name,
            got
        );
        println!("  {:<24} rejected as expected", r.name);
    }

    assert_eq!(failures, 0);
}

/// A submitted result that is not the centres must never score a perfect 1.0 — guards against a
/// validator that accidentally ignores the player's input.
#[test]
fn quality_responds_to_accuracy() {
    let seed = 4242;
    let centers = timing_centers(seed);
    let perfect = validate_challenge(0, seed, 0.5, &centers).unwrap();
    let offset: Vec<f32> = centers.iter().map(|c| (c + 0.05).min(1.0)).collect();
    let worse = validate_challenge(0, seed, 0.5, &offset).unwrap();
    assert!(perfect > worse, "perfect {perfect} should beat offset {worse}");
    assert!((perfect - 1.0).abs() < 1e-6, "hitting every centre should score 1.0, got {perfect}");
}
