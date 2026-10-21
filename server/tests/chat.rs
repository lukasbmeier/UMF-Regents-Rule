//! CHAT (DECISIONS #273): what a line may say.

use umf_module::chat::{clean, overflow, MAX_BYTES, MAX_KEPT};

#[test]
fn a_line_is_kept_as_it_was_said() {
    assert_eq!(clean("hello there").as_deref(), Some("hello there"));
    assert_eq!(clean("  hi  ").as_deref(), Some("hi"), "the ends trimmed");
    assert_eq!(clean("café ☕").as_deref(), Some("café ☕"), "any language, any symbol");
}

#[test]
fn nothing_to_say_is_not_a_line() {
    assert_eq!(clean(""), None);
    assert_eq!(clean("   \n\t "), None, "only spaces and breaks");
}

#[test]
fn a_line_is_one_line() {
    assert_eq!(clean("one\ntwo\r\nthree").as_deref(), Some("one two three"), "a break is a space");
    assert_eq!(clean("a\u{1b}[31mred").as_deref(), Some("a [31mred"), "a terminal escape is not sent on");
    assert_eq!(clean("lots     of    room").as_deref(), Some("lots of room"), "a run of spaces is one");
}

#[test]
fn a_long_line_is_cut_on_a_character() {
    let long = "a".repeat(500);
    assert_eq!(clean(&long).map(|s| s.len()), Some(MAX_BYTES));
    let wide = "é".repeat(150); // two bytes each
    let cut = clean(&wide).unwrap();
    assert!(cut.len() <= MAX_BYTES && cut.chars().all(|c| c == 'é'), "never through a character ({} bytes)", cut.len());
    let words = format!("{} {}", "a".repeat(MAX_BYTES - 1), "b");
    assert_eq!(clean(&words).map(|s| s.len()), Some(MAX_BYTES - 1), "and never ends on a space");
}

#[test]
fn a_world_keeps_its_last_lines() {
    let lines = |n: u64| -> Vec<(i64, u64)> { (0..n).map(|i| (1_000 + i as i64, 100 + i)).collect() };
    assert!(overflow(lines(MAX_KEPT as u64)).is_empty(), "up to {MAX_KEPT}: all kept");
    assert_eq!(overflow(lines(MAX_KEPT as u64 + 2)), vec![100, 101], "over it: the oldest go");
    let mut shuffled = lines(MAX_KEPT as u64 + 1);
    shuffled.reverse();
    assert_eq!(overflow(shuffled), vec![100], "whatever order they come in");
}
