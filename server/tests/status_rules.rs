//! WHICH STATUS EACH NUMBER IS (DECISIONS #206): the rules build.rs builds a game's statuses by
//! (`build/status_rules.rs`), checked here with genres the template does not have.

#[path = "../build/status_rules.rs"]
mod status_rules;
use status_rules::choose;

fn s(owner: &str, n: i64, name: &str) -> (String, i64, String) {
    (owner.to_string(), n, name.to_string())
}

fn genres(g: &[&str]) -> Vec<String> {
    g.iter().map(|x| x.to_string()).collect()
}

#[test]
fn a_genre_replaces_the_foundations_by_number() {
    let all = vec![s("foundation", 0, "Normal"), s("foundation", 2, "Downed"), s("hens", 2, "Hen downed"), s("hens", 120, "Stashed")];
    let got = choose(&all, &genres(&["hens"])).unwrap();
    assert_eq!(got, vec![(0, 0), (2, 2), (120, 3)], "the hen's downed is status 2; the foundation's is not used");
}

#[test]
fn the_order_of_the_files_does_not_matter() {
    let all = vec![s("hens", 2, "Hen downed"), s("foundation", 2, "Downed"), s("foundation", 0, "Normal")];
    assert_eq!(choose(&all, &genres(&["hens"])).unwrap(), vec![(0, 2), (2, 0)]);
}

#[test]
fn refused() {
    let f0 = s("foundation", 0, "Normal");
    let cases: Vec<(Vec<(String, i64, String)>, &[&str], &str)> = vec![
        (vec![f0.clone(), s("hens", 50, "Stray")], &["hens"], "replaces none"),
        (vec![f0.clone(), s("hens", 120, "A"), s("foxes", 120, "B")], &["hens", "foxes"], "both have a status numbered 120"),
        (vec![f0.clone(), s("foundation", 2, "Downed"), s("hens", 2, "A"), s("foxes", 2, "B")], &["hens", "foxes"], "both have a status numbered 2"),
        (vec![f0.clone(), s("hens", 120, "A"), s("hens", 120, "B")], &["hens"], "two statuses numbered 120"),
        (vec![f0.clone(), s("foundation", 150, "Big")], &[], "the foundation's are 0-99"),
        (vec![s("foundation", 1, "Injured")], &[], "no status 0"),
        (vec![f0.clone(), s("hens", 300, "Huge")], &["hens"], "a status is 0-255"),
    ];
    for (all, g, says) in cases {
        let err = choose(&all, &genres(g)).expect_err(says);
        assert!(err.contains(says), "expected '{says}', got '{err}'");
    }
}
