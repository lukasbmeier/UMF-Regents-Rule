//! Runs shared/golden/level/<level>_probes.json against the compiled-in level bakes. The Godot
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
    let doc = load("lakeside");
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
}

/// The shape of the lake, independent of the probe file: if the generator ever writes a bake
/// where these stop being true, the level has changed under the game and someone should look.
#[test]
fn the_lakeside_is_the_level_the_game_describes() {
    let l = bake("lakeside");
    // Players arrive on dry land, at the top of the ramp.
    assert!(!l.is_water(l.spawn[0], l.spawn[2]), "spawn is in the water");
    assert!(l.spawn[1] > l.water_y, "spawn is below the water line");
    // The dock end is fishable, and deep.
    assert!(l.is_water(0.0, 16.0) && l.depth_at(0.0, 16.0) > 3.0);
    // The Deep Hole is the deepest water within 20 m of itself.
    let dh = l.spots.iter().find(|s| s.id == "deep_hole").expect("the lakeside has a Deep Hole");
    let (hx, hz) = (dh.x as f32, dh.z as f32);
    let hole = l.depth_at(hx, hz);
    for (dx, dz) in [(20.0, 0.0), (-20.0, 0.0), (0.0, 20.0), (0.0, -20.0)] {
        assert!(hole > l.depth_at(hx + dx, hz + dz), "deep hole is not deepest toward ({dx}, {dz})");
    }
    // Reed Bay is shallow water, not dry and not deep.
    let bay = l.depth_at(-114.0, 16.0);
    assert!(bay >= 0.6 && bay <= 1.8, "reed bay is {bay} m deep");
    // Rocky Point is land.
    assert!(!l.is_water(85.0, -42.0));
    // The dock stands over water, but a float cannot land on its planks.
    assert!(!l.is_water(0.0, 40.0) && !l.is_water(3.0, 25.0), "the dock's deck counts as water");
    assert!(l.is_water(0.0, 19.0), "but the water just past the end of the dock does");
    // Where a player may stand (REVIEW B2): the module refuses a Tier A claim anywhere else.
    assert!(l.can_stand(l.spawn[0], l.spawn[2]) && l.can_stand(0.0, 40.0) && l.can_stand(3.0, 25.0),
        "the spawn and the dock's planks are ground a player may stand on");
    assert!(!l.can_stand(0.0, 16.0) && !l.can_stand(hx, hz), "past the end of the dock and the Deep Hole are not");
    // Every named spot's centre is fishable water.
    for s in l.spots {
        assert!(l.is_water(s.x as f32, s.z as f32), "spot {} is centred on land", s.id);
        assert_eq!(l.spot_at(s.x as f32, s.z as f32).map(|t| t.id), Some(s.id), "spot {} is shadowed", s.id);
    }
    // Smallest first, so the first match is the most specific.
    for w in l.spots.windows(2) {
        assert!(w[0].radius <= w[1].radius, "spots are not ordered smallest first");
    }
}

#[test]
fn off_the_grid_is_dry_land() {
    let l = bake("lakeside");
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


/// FfC's GATE: where you cast decides what you catch, and "how far your rod throws decides which
/// spots you can reach at all". A spot whose `min_rod` is N (shared/fishing/fishing.json) is out
/// of every lesser rod's reach from anywhere a player can stand, and some of it is in reach of rod
/// N. The level makes that true by where it puts the spot — the first lakeside put its best one a
/// four-metre lob off a beach — so every baked level is held to it here.
///
/// Where a player can stand: land, water shallow enough to wade, and the dock's deck (dry in the
/// bake). The two bounds are not equally strict, on purpose. NO LESSER ROD may reach the spot, so
/// that one assumes the worst: a player anywhere a cell's centre reads up to a decimetre past
/// wading depth (the barrier follows the terrain, not this grid), casting the rod's reach plus the
/// server's slack, with a cell's diagonal given away because a player stands anywhere in a cell
/// and a float lands anywhere in one. ITS OWN ROD must reach it honestly: from ground that is
/// surely shallow enough, at the reach the aim allows.
#[cfg(genre_fishing)]
#[test]
fn every_spot_needs_its_rod_and_no_lesser_one() {
    use umf_module::genre::fishing::{rod, spot_loot, RANGE_SLACK_M};
    for l in level::ALL {
        let (w, h) = (l.width, l.height);
        let dm = |i: usize, j: usize| l.depth_dm[j * w + i];
        let wade_dm = (l.wade_depth * 10.0).round() as u8;
        // The cells of a set that border water outside it: the nearest point of the set to any
        // water is one of these.
        let edges = |stand: &dyn Fn(u8) -> bool| -> Vec<(f64, f64)> {
            let mut out = Vec::new();
            for j in 0..h {
                for i in 0..w {
                    if !stand(dm(i, j)) {
                        continue;
                    }
                    let border = [(0i64, 1i64), (0, -1), (1, 0), (-1, 0)].iter().any(|(di, dj)| {
                        let (ni, nj) = (i as i64 + di, j as i64 + dj);
                        ni >= 0 && nj >= 0 && (ni as usize) < w && (nj as usize) < h && !stand(dm(ni as usize, nj as usize))
                    });
                    if border {
                        out.push((l.origin_x + i as f64 * l.spacing, l.origin_z + j as f64 * l.spacing));
                    }
                }
            }
            out
        };
        let surely = edges(&|d| d < wade_dm);
        let maybe = edges(&|d| d <= wade_dm + 1);
        let nearest = |x: f64, z: f64, set: &[(f64, f64)]| -> f64 {
            set.iter().map(|(sx, sz)| ((x - sx).powi(2) + (z - sz).powi(2)).sqrt()).fold(f64::INFINITY, f64::min)
        };
        let diag = l.spacing * std::f64::consts::SQRT_2;
        let slack = RANGE_SLACK_M as f64;
        let mut report = Vec::new();
        for s in l.spots {
            let need = spot_loot(s.id).min_rod;
            let mut water = Vec::new();
            for j in 0..h {
                for i in 0..w {
                    let (x, z) = (l.origin_x + i as f64 * l.spacing, l.origin_z + j as f64 * l.spacing);
                    if dm(i, j) >= l.min_cast_dm && (x - s.x).powi(2) + (z - s.z).powi(2) <= s.radius * s.radius {
                        water.push((x, z));
                    }
                }
            }
            assert!(!water.is_empty(), "{}: {} has no water a float can land in", l.name, s.id);
            let closest = water.iter().map(|(x, z)| nearest(*x, *z, &maybe)).fold(f64::INFINITY, f64::min);
            let own = rod(need).max_cast_m as f64;
            let in_reach = water.iter().filter(|(x, z)| nearest(*x, *z, &surely) <= own).count();
            report.push(format!("{} {}: needs rod {} ({}), nearest water {:.1} m from where anyone can stand, \
                {} m² in its reach", l.name, s.id, need, rod(need).name, closest, in_reach));
            if need > 0 {
                let lesser = rod(need - 1);
                let reach = lesser.max_cast_m as f64 + slack + diag;
                assert!(closest > reach, "{}: {} needs the {} (min_rod {}), but the {} reaches it: its nearest water is \
                    {:.1} m from where a player can stand, and that rod casts {:.0} m (+{:.0} m slack). Move it out \
                    (tools/world/lakeside_shape.gd SPOTS) or lower its min_rod.", l.name, s.id, rod(need).name, need,
                    lesser.name, closest, lesser.max_cast_m, slack);
            }
            assert!(in_reach >= 20, "{}: {} is meant for the {}, which reaches only {} m² of it", l.name, s.id,
                rod(need).name, in_reach);
        }
        println!("{}", report.join("\n"));
    }
}

/// THE RIVAL REACHES HIS WATER (DECISIONS #169): from where `fishing.json` stands him, his rod
/// reaches water in every spot he fishes, and he stands on dry land. (The lakeside suite checks
/// the height against the terrain.)
#[cfg(genre_fishing)]
#[test]
fn the_rival_reaches_his_spots_from_where_he_stands() {
    use umf_module::genre::fishing::{rod, MIN_RANGE_M, RIVAL};
    let b = level::by_name(RIVAL.level).expect("the rival's level is baked");
    let [sx, _, sz] = RIVAL.stand;
    assert!(!b.is_water(sx, sz), "the rival stands in the water at ({sx}, {sz})");
    let reach = rod(RIVAL.rod_tier).max_cast_m;
    for id in RIVAL.spots {
        let spot = b.spots.iter().find(|s| s.id == *id).unwrap_or_else(|| panic!("no spot '{id}' in {}", b.name));
        let mut reachable = 0;
        for i in 0..64 {
            for ring in 1..=6 {
                let a = i as f32 / 64.0 * std::f32::consts::TAU;
                let d = spot.radius as f32 * 0.7 * ring as f32 / 6.0;
                let (x, z) = (spot.x as f32 + a.cos() * d, spot.z as f32 + a.sin() * d);
                let range = ((x - sx).powi(2) + (z - sz).powi(2)).sqrt();
                if b.is_water(x, z) && range <= reach && range >= MIN_RANGE_M {
                    reachable += 1;
                }
            }
        }
        assert!(reachable >= 20, "from ({sx}, {sz}) only {reachable} points of '{id}' are water in his {reach} m reach");
    }
}

/// A LEVEL BUILT IN THE EDITOR (DECISIONS #175): the meadow was made of CSG and markers in a scene
/// and baked from it (`tools/world/bake_level.gd`); the module compiles its bake like the lakeside's.
#[test]
fn a_level_built_in_the_editor_is_baked_like_any_other() {
    let m = level::by_id(2).expect("the meadow is level 2");
    assert_eq!(m.name, "meadow");
    assert!(!m.is_water(m.spawn[0], m.spawn[2]), "the meadow's spawn is on dry land");
    assert!(m.is_water(0.0, -10.0), "the pond's middle is deep enough for a float");
    assert!(m.depth_dm_at(0.0, 3.0) > 0 && !m.is_water(0.0, 3.0), "its shallows are wet, and too shallow for one");
    assert_eq!(m.spot_at(0.0, -10.0).map(|s| s.id), Some("meadow_pond"));
    assert_eq!(m.points_of("bench").map(|p| p.id).collect::<Vec<_>>(), vec!["bench_south"]);
    assert_eq!(level::by_id(1).map(|l| l.name), Some("lakeside"));
    assert!(level::by_id(0).is_none(), "level 0 is the greybox, which has no bake");
}
