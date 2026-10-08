//! A GAME IS A LIST OF GENRES (DECISIONS #173): the claims a genre makes on the foundation's
//! numbers, checked the way `init` checks them, and the build made of what shared/game.json says.
//!   cargo test --test genres

use umf_module::genre::{check_claims, enabled, Claims};

static A: Claims = Claims { name: "a", challenge_kinds: &[100, 101], entity_kinds: &[100], phases: &[4], session_kinds: &[1] };
static B: Claims = Claims { name: "b", challenge_kinds: &[102], entity_kinds: &[101], phases: &[5], session_kinds: &[2] };
static CLASH: Claims = Claims { name: "clash", challenge_kinds: &[101], entity_kinds: &[], phases: &[], session_kinds: &[] };
static GREEDY: Claims = Claims { name: "greedy", challenge_kinds: &[3], entity_kinds: &[1], phases: &[2], session_kinds: &[0] };

#[test]
fn genres_with_their_own_numbers_agree() {
    assert_eq!(check_claims(&[&A, &B]), Ok(()));
}

#[test]
fn two_genres_claiming_one_number_is_refused_by_name() {
    let err = check_claims(&[&A, &CLASH]).unwrap_err();
    assert!(err.contains("clash and a both claim challenge kind 101"), "{err}");
}

#[test]
fn a_genre_may_not_claim_the_foundations_numbers() {
    let err = check_claims(&[&GREEDY]).unwrap_err();
    for what in ["challenge kind 3", "entity kind 1", "phase 2", "session kind 0"] {
        assert!(err.contains(what), "'{what}' not refused: {err}");
    }
}

#[test]
fn the_build_is_made_of_the_genres_game_json_names() {
    let path = std::env::var("UMF_GAME").map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/game.json"));
    let v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let listed: Vec<String> = v["genres"].as_array().unwrap().iter().map(|g| g.as_str().unwrap().to_string()).collect();
    assert_eq!(enabled::ENABLED.iter().map(|s| s.to_string()).collect::<Vec<_>>(), listed);
}

#[cfg(genre_fishing)]
#[test]
fn fishing_claims_only_its_own() {
    assert_eq!(check_claims(&[&umf_module::genre::fishing::CLAIMS]), Ok(()));
    assert_eq!(umf_module::genre::fishing::CLAIMS.challenge_kinds, &[100]);
}
