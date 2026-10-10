// WHICH HOLD A PRESS STARTS, IN THIS GAME (DECISIONS #209). Pure (no build-only crates), so
// tests/hold_rules.rs checks the rules natively: build.rs's `hold_table` (build/content.rs) is the only
// caller. A hold applies to a press of `verb` on an entity of one of its `targets` kinds, by a doer of
// one of its `doers` kinds (none listed: anyone), while the target is in status `when` (None: any).
//
// Two holds one press could start are ambiguous, and refused: within one owner, or between two
// genres. A genre's hold over the foundation's REPLACES it for the presses they share (a genre's own
// "help up" that takes longer), as a genre's status replaces the foundation's of the same number.

/// One baked hold, as the rules need it.
#[derive(Clone, Debug, PartialEq)]
pub struct HoldKey {
    pub owner: String,
    pub name: String,
    pub verb: u8,
    pub targets: Vec<u8>,
    pub doers: Vec<u8>,
    pub when: Option<u8>,
}

/// Whether one press could start both.
pub fn overlap(a: &HoldKey, b: &HoldKey) -> bool {
    a.verb == b.verb
        && a.targets.iter().any(|k| b.targets.contains(k))
        && (a.doers.is_empty() || b.doers.is_empty() || a.doers.iter().any(|k| b.doers.contains(k)))
        && (a.when.is_none() || b.when.is_none() || a.when == b.when)
}

/// `all`: every baked hold. `listed`: the game's genres, in order. Ok: the indexes into `all` in the
/// order a press is matched (every genre's, in the game's order, then the foundation's), so the first
/// that applies is the one; Err: the first problem, as a sentence.
pub fn choose(all: &[HoldKey], listed: &[String]) -> Result<Vec<usize>, String> {
    for h in all {
        if h.targets.is_empty() {
            return Err(format!("{}'s hold '{}' is done to nothing: give it the characters it is done to", h.owner, h.name));
        }
    }
    for (i, a) in all.iter().enumerate() {
        for b in &all[i + 1..] {
            if !overlap(a, b) {
                continue;
            }
            if a.owner == b.owner {
                return Err(format!("{} has two holds one press could start: '{}' and '{}' (verb {}, the same kind, doer and status): tell them apart",
                    a.owner, a.name, b.name, a.verb));
            }
            if a.owner != "foundation" && b.owner != "foundation" {
                return Err(format!("{}'s '{}' and {}'s '{}' could both be started by one press (verb {}): only one genre may have it",
                    a.owner, a.name, b.owner, b.name, a.verb));
            }
        }
    }
    let rank = |o: &str| if o == "foundation" { usize::MAX } else { listed.iter().position(|g| g == o).unwrap_or(usize::MAX - 1) };
    let mut order: Vec<usize> = (0..all.len()).collect();
    order.sort_by_key(|i| rank(&all[*i].owner));
    Ok(order)
}
