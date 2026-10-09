//! THE FOUNDATION'S LEVEL BAKES: every shared/golden/level/<level>_probes.json against the compiled-in
//! bakes, and the example level built in the editor (`foundation/level/example/`). A genre's own
//! levels have their own suite (fishing's: tests/lakeside.rs). The Godot
//! test runner checks the same probes against `foundation/sim/level_bake.gd`; both must match
//! every probe exactly, because a float the client shows landing in the water has to be one the
//! server accepts.
//!   cargo test --test level

use serde::Deserialize;
use std::{fs, path::Path};
use umf_module::level::{self, LevelBake};

#[derive(Deserialize)]
struct Doc {
    level: String,
    probes: Vec<Probe>,
}

#[derive(Deserialize)]
struct Probe {
    name: String,
    x: f32,
    z: f32,
    cell: Option<[usize; 2]>,
    depth_dm: u8,
    is_water: bool,
    spot: Option<String>,
    can_stand: bool,
}

fn load(level: &str) -> Doc {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../shared/golden/level")
        .join(format!("{level}_probes.json"));
    let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    serde_json::from_str(&text).unwrap()
}

fn bake(name: &str) -> &'static LevelBake {
    level::by_name(name).unwrap_or_else(|| panic!("no baked level '{name}'"))
}

#[test]
fn every_probe_matches() {
    // Every level that ships probes and is baked into this build (a genre's levels go with it).
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/golden/level");
    let mut checked = 0;
    for entry in fs::read_dir(&dir).unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Some(level_name) = name.strip_suffix("_probes.json") else { continue };
        if level::by_name(level_name).is_none() {
            continue;
        }
        let doc = load(level_name);
        let l = bake(&doc.level);
        let mut bad = Vec::new();
        for p in &doc.probes {
            let cell = l.cell(p.x, p.z).map(|(i, j)| [i, j]);
            let dm = l.depth_dm_at(p.x, p.z);
            let water = l.is_water(p.x, p.z);
            let spot = l.spot_at(p.x, p.z).map(|s| s.id.to_string());
            let stand = l.can_stand(p.x, p.z);
            if cell != p.cell || dm != p.depth_dm || water != p.is_water || spot != p.spot || stand != p.can_stand {
                bad.push(format!(
                    "{}: ({}, {}) got cell={cell:?} dm={dm} water={water} spot={spot:?} stand={stand}, want cell={:?} dm={} water={} spot={:?} stand={}",
                    p.name, p.x, p.z, p.cell, p.depth_dm, p.is_water, p.spot, p.can_stand
                ));
            }
        }
        println!("level {}: {} probes, {} mismatches", doc.level, doc.probes.len(), bad.len());
        assert!(bad.is_empty(), "\n{}", bad.join("\n"));
        checked += 1;
    }
    assert!(level::by_name("example").is_some() && checked >= 1, "the example level's probes were not checked");
}

#[test]
fn off_the_grid_is_dry_land() {
    let l = bake("example");
    let west = (l.origin_x - l.spacing * 0.5 - 0.01) as f32;
    assert_eq!(l.cell(west, l.origin_z as f32), None);
    assert_eq!(l.depth_dm_at(west, l.origin_z as f32), 0);
    assert!(!l.is_water(1.0e9, -1.0e9));
    // NaN must be OFF the grid, not "some cell that happens to be dry": `NaN as usize` is 0, so
    // an unguarded NaN reads column 0 — dry today only because the grid has a dry margin.
    assert_eq!(l.cell(f32::NAN, 0.0), None, "NaN x must not index the grid");
    assert_eq!(l.cell(0.0, f32::NAN), None, "NaN z must not index the grid");
    assert_eq!(l.cell(f32::INFINITY, 0.0), None);
}

/// A LEVEL BUILT IN THE EDITOR (DECISIONS #175): the foundation's example level, CSG and markers in a
/// scene (`foundation/level/example/example_level.tscn`, level 200), baked from it by
/// `tools/world/bake_level.gd`; the module compiles its bake like any other.
#[test]
fn a_level_built_in_the_editor_is_baked_like_any_other() {
    let m = level::by_id(200).expect("the example level is level 200");
    assert_eq!(m.name, "example");
    assert!(!m.is_water(m.spawn[0], m.spawn[2]), "its spawn is on dry land");
    assert!(m.is_water(0.0, -10.0), "the pond's middle is deep enough for a float");
    assert!(m.depth_dm_at(0.0, 3.0) > 0 && !m.is_water(0.0, 3.0), "its shallows are wet, and too shallow for one");
    assert_eq!(m.spot_at(0.0, -10.0).map(|s| s.id), Some("example_pond"));
    assert_eq!(m.points_of("marker").map(|p| p.id).collect::<Vec<_>>(), vec!["marker_south"]);
    // Where a player may stand (REVIEW B2): the shore and the shallows, not the deep middle.
    assert!(m.can_stand(m.spawn[0], m.spawn[2]) && m.can_stand(0.0, 3.0) && !m.can_stand(0.0, -10.0),
        "the shore and the shallows are standable, the pond's deep middle is not");
    assert!(level::by_id(0).is_none(), "level 0 is the greybox, which has no bake");
}
