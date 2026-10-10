// WHICH STATUS EACH NUMBER IS, IN THIS GAME (DECISIONS #206). Pure (no build-only crates), so
// tests/status_rules.rs checks the rules natively: build.rs's `status_table` (build/content.rs) is the
// only caller. The foundation's statuses are 0-99 and a genre's 100-255; a genre REPLACES one of the
// foundation's by giving its own the same number. Refused: two of one owner with one number, two
// genres with one number, a foundation status at 100 or above, a genre's under 100 that replaces
// nothing, a game with no status 0.

/// `all`: every baked status as (owner, number, name). `listed`: the game's genres, in order. Ok: for
/// each number, the index into `all` of the status the game uses, by number; Err: the first problem,
/// as a sentence.
pub fn choose(all: &[(String, i64, String)], listed: &[String]) -> Result<Vec<(u8, usize)>, String> {
    let rank = |o: &str| if o == "foundation" { 0 } else { 1 + listed.iter().position(|g| g == o).unwrap_or(usize::MAX - 1) };
    let mut order: Vec<usize> = (0..all.len()).collect();
    order.sort_by_key(|i| rank(&all[*i].0));
    let mut chosen: Vec<(u8, usize)> = Vec::new();
    for i in order {
        let (owner, n, name) = &all[i];
        if !(0..=255).contains(n) {
            return Err(format!("{owner}'s status '{name}' has number {n}: a status is 0-255"));
        }
        let n = *n as u8;
        if owner == "foundation" && n >= 100 {
            return Err(format!("the foundation's status '{name}' is number {n}: the foundation's are 0-99"));
        }
        match chosen.iter().position(|c| c.0 == n) {
            None => {
                if owner != "foundation" && n < 100 {
                    return Err(format!("{owner}'s status '{name}' is number {n}, which is the foundation's range (0-99) but replaces none of its statuses: a genre's start at 100"));
                }
                chosen.push((n, i));
            }
            Some(at) => {
                let held = &all[chosen[at].1];
                if held.0 == *owner {
                    return Err(format!("{owner} has two statuses numbered {n}: '{}' and '{name}'", held.2));
                }
                if held.0 != "foundation" {
                    return Err(format!("{} and {owner} both have a status numbered {n}", held.0));
                }
                chosen[at] = (n, i);   // a genre replaces the foundation's
            }
        }
    }
    if !chosen.iter().any(|c| c.0 == 0) {
        return Err("there is no status 0 (normal): it is foundation content (foundation/content/status/normal.tres)".into());
    }
    chosen.sort_by_key(|c| c.0);
    Ok(chosen)
}
