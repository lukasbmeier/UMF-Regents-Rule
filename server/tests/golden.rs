//! Runs the shared golden vectors against the frozen sim::simulate. The Godot test runner executes
//! the same files against movement_model.gd (which is the live model). Failure here means someone
//! edited the frozen twin; failure there means the GDScript model regressed.
//!   cargo test --test golden

use serde::Deserialize;
use std::{fs, path::Path};
use umf_module::sim::{simulate, InputFrame, MovementConfig, MovementState, Vector3};

#[derive(Deserialize)]
struct Doc {
    /// Whether the FROZEN gravity-only twin in sim.rs can reproduce this file. Vectors for
    /// branches that live only in movement_model.gd (horizontal movement, and the Phase 4
    /// config-gated branches) set this false and are skipped here — extending sim.rs to match
    /// them would violate AGENTS rule 7. The Godot runner executes every file regardless.
    #[serde(default)]
    frozen_twin: bool,
    name: String,
    model_version: String,
    dt: f64,
    #[serde(default = "default_tol")]
    tolerance: f32,
    config: serde_json::Value,
    cases: Vec<Case>,
}
fn default_tol() -> f32 { 1e-5 }

#[derive(Deserialize)]
struct Case {
    name: String,
    initial: StateJ,
    inputs: Vec<InputJ>,
    expected_final: StateJ,
    #[serde(default)]
    expected_at: std::collections::HashMap<String, StateJ>,
}

#[derive(Deserialize)]
struct StateJ {
    pos: [f64; 3],
    vel: [f64; 3],
    yaw: f64,
    grounded: bool,
    move_state: u8,
}

#[derive(Deserialize, Default)]
struct InputJ {
    #[serde(default)]
    jump: bool,
    #[serde(default)]
    sprint: bool,
    #[serde(default)]
    move_x: f64,
    #[serde(default)]
    move_y: f64,
    #[serde(default)]
    look_yaw: f64,
    #[serde(default)]
    look_pitch: f64,
}

fn v3(a: [f64; 3]) -> Vector3 { Vector3::new(a[0] as f32, a[1] as f32, a[2] as f32) }

impl From<&StateJ> for MovementState {
    fn from(s: &StateJ) -> Self {
        MovementState { pos: v3(s.pos), vel: v3(s.vel), yaw: s.yaw as f32, grounded: s.grounded, move_state: s.move_state }
    }
}

impl From<&InputJ> for InputFrame {
    fn from(i: &InputJ) -> Self {
        InputFrame {
            jump: i.jump, sprint: i.sprint,
            move_x: i.move_x as f32, move_y: i.move_y as f32, look_yaw: i.look_yaw as f32,
            look_pitch: i.look_pitch as f32,
            ..Default::default()
        }
    }
}

fn cfg_from(v: &serde_json::Value) -> MovementConfig {
    let mut c = umf_module::movement_config::default_config();
    let g = |k: &str, cur: f32| v.get(k).and_then(|x| x.as_f64()).map(|x| x as f32).unwrap_or(cur);
    c.gravity = g("gravity", c.gravity);
    c.jump_velocity = g("jump_velocity", c.jump_velocity);
    c.ground_y = g("ground_y", c.ground_y);
    c.walk_speed = g("walk_speed", c.walk_speed);
    c.sprint_speed = g("sprint_speed", c.sprint_speed);
    c
}

fn assert_close(actual: &MovementState, expected: &MovementState, tol: f32, ctx: &str) -> f32 {
    let err = actual.max_error(expected);
    assert!(err <= tol, "{ctx}: max_err={err:e} > {tol:e}\n  got      {actual:?}\n  expected {expected:?}");
    assert_eq!(actual.grounded, expected.grounded, "{ctx}: grounded mismatch");
    err
}

#[test]
fn golden_vectors_match() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/golden/movement");
    let mut files: Vec<_> = fs::read_dir(&dir).expect("shared/golden missing")
        .filter_map(|e| e.ok()).map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "json").unwrap_or(false))
        .collect();
    files.sort();
    assert!(!files.is_empty(), "no golden files");

    let mut ran = 0;
    for path in files {
        let doc: Doc = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        if !doc.frozen_twin {
            println!("{} — skipped (GDScript-only vectors; sim.rs is frozen)", doc.name);
            continue;
        }
        ran += 1;
        let cfg = cfg_from(&doc.config);
        let dt = doc.dt as f32;
        println!("{} (model={}, {} cases)", doc.name, doc.model_version, doc.cases.len());

        for case in &doc.cases {
            let mut s: MovementState = (&case.initial).into();
            let mut worst = 0.0f32;
            for (i, inp) in case.inputs.iter().enumerate() {
                s = simulate(&s, &inp.into(), &cfg, dt);
                if let Some(exp) = case.expected_at.get(&i.to_string()) {
                    worst = worst.max(assert_close(&s, &exp.into(), doc.tolerance, &format!("{} @frame {i}", case.name)));
                }
            }
            worst = worst.max(assert_close(&s, &(&case.expected_final).into(), doc.tolerance, &format!("{} final", case.name)));
            println!("  {:<28} ok  max_err={worst:e}", case.name);
        }
    }

    // Without this, flipping every file's `frozen_twin` to false would leave sim.rs with no
    // coverage at all and this test would still report success — the worst kind of green.
    assert!(
        ran > 0,
        "every golden file was skipped, so the frozen twin has no coverage. \
         gravity_only.json must keep frozen_twin: true."
    );
}
