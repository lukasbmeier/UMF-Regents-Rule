//! CHAT (DECISIONS #273; owner, 2026-10-20, after the friends' playtest: "sorely missed"): what a line
//! may say and how many a world keeps (how long: the hot rule `foundation.chat_keep_s`). The table and
//! the reducer are `module/chat.rs`. Pure, so the native suites check it.

/// The longest line, bytes (cut on a character, never through one).
pub const MAX_BYTES: usize = 200;
/// The most lines a world keeps; the oldest go first.
pub const MAX_KEPT: usize = 50;

/// A line as it is kept: control characters (a newline, a tab, a terminal escape) are spaces, runs of
/// spaces are one, the ends trimmed, then cut to `MAX_BYTES`. None when nothing is left to say.
pub fn clean(text: &str) -> Option<String> {
    let mut out = String::with_capacity(text.len().min(MAX_BYTES));
    let mut space = false;
    for c in text.chars() {
        if c.is_control() || c.is_whitespace() {
            space = !out.is_empty();
            continue;
        }
        let need = c.len_utf8() + usize::from(space);
        if out.len() + need > MAX_BYTES {
            break;
        }
        if space {
            out.push(' ');
            space = false;
        }
        out.push(c);
    }
    if out.is_empty() { None } else { Some(out) }
}

/// Which of a world's lines (`(said at, id)`) go when it has more than `MAX_KEPT`: the oldest.
pub fn overflow(mut kept: Vec<(i64, u64)>) -> Vec<u64> {
    if kept.len() <= MAX_KEPT {
        return Vec::new();
    }
    kept.sort_unstable();
    kept[..kept.len() - MAX_KEPT].iter().map(|&(_, id)| id).collect()
}
