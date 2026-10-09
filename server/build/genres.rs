//! THIS GAME'S GENRE BUILD STEPS. build.rs (the foundation's) calls `run` with the genres
//! shared/game.json lists; each genre that compiles content in has a file beside this one. This
//! file belongs to the GAME. Each genre's lines are tagged `genre:<name>`, so
//! `tools/template/strip_genre.py` can take a genre out (the template has none).

mod fishing { include!("fishing.rs"); } // genre:fishing

pub fn run(enabled: &[String]) {
    let _ = enabled;
    if enabled.iter().any(|g| g == "fishing") { fishing::fishing_data(); fishing::fight_data(); } // genre:fishing
}
