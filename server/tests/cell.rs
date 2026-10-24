//! THE WORLD IN SQUARES (template 1.0, DECISIONS #278): which cell a place is in, and the cells round it.
//! The cases in `shared/golden/cells.json` are the client twin's too (`foundation/net/cells.gd`).

use umf_module::cell::{at, axis, chunk_of, ring, squares, CELL_M, GRID};
use umf_module::sim::Vector3;

#[test]
fn the_cell_is_the_games_data() {
    assert_eq!(CELL_M, 64.0, "shared/rules.json cells.cell_m");
    assert_eq!(umf_module::rules::CELL_RING, 1);
    assert_eq!(umf_module::rules::CELL_STREAM_RING, 2);
    assert_eq!(umf_module::rules::CELL_HYSTERESIS_M, 4.0);
}

#[test]
fn every_shared_case_is_in_the_cell_both_sides_say() {
    let doc: serde_json::Value =
        serde_json::from_str(include_str!("../../shared/golden/cells.json")).expect("cells.json");
    assert_eq!(doc["cell_m"].as_f64().unwrap() as f32, CELL_M, "the cases were made for this cell size");
    let cases = doc["cases"].as_array().unwrap();
    assert!(cases.len() >= 10);
    for c in cases {
        let (x, z) = (c["x"].as_f64().unwrap() as f32, c["z"].as_f64().unwrap() as f32);
        assert_eq!(chunk_of(Vector3::new(x, 0.0, z)) as u64, c["chunk"].as_u64().unwrap(), "({x}, {z})");
    }
}

#[test]
fn a_cell_is_its_squares_and_back() {
    for (x, z) in [(0, 0), (-1, 0), (0, -1), (511, -512), (-512, 511), (17, -300)] {
        assert_eq!(squares(at(x, z)), (x, z), "({x}, {z})");
    }
    assert_eq!(axis(-0.001), -1, "west of the origin is the square before it");
    assert_eq!(axis(63.999), 0);
    assert_eq!(at(9999, -9999), at(511, -512), "past the edge is the edge");
    assert_eq!(chunk_of(Vector3::new(0.0, 500.0, 0.0)), chunk_of(Vector3::ZERO), "height is not a cell");
}

#[test]
fn the_ring_is_a_cell_and_its_neighbours() {
    let c = at(3, -7);
    let r1 = ring(c, 1);
    assert_eq!(r1.len(), 9, "3 x 3");
    assert!(r1.contains(&c), "its own");
    for (dx, dz) in [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)] {
        assert!(r1.contains(&at(3 + dx, -7 + dz)), "neighbour ({dx}, {dz})");
    }
    let mut sorted = r1.clone();
    sorted.sort();
    sorted.dedup();
    assert_eq!(sorted.len(), 9, "each once");
    assert_eq!(ring(c, 2).len(), 25, "5 x 5");
    assert!(!r1.contains(&at(5, -7)), "two away is not in a ring of one");
    let corner = at(-(GRID / 2), -(GRID / 2));
    assert_eq!(ring(corner, 1).len(), 4, "at the grid's corner, only the cells that exist");
}
