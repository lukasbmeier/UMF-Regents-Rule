//! WHAT EACH KIND MAY USE (DECISIONS #207): a kind none of whose characters lists abilities may use
//! every ability (as before characters listed them); one whose characters do, only those.

use umf_module::content::{kind_may_use, KIND_ABILITIES};

#[test]
fn a_kind_that_lists_none_may_use_any() {
    for kind in 0..=255u8 {
        if !KIND_ABILITIES.iter().any(|k| k.0 == kind) {
            assert!(kind_may_use(kind, 0) && kind_may_use(kind, 12345));
        }
    }
}

/// tests/content_test.sh builds against a copy whose humanoid (kind 0) lists only ability 0, and says
/// so here; any other run skips this.
#[test]
fn a_kind_that_lists_some_may_use_only_those() {
    if std::env::var("UMF_EXPECT_KIND0_ONLY_ABILITY_0").is_ok() {
        assert!(kind_may_use(0, 0), "kind 0 lists ability 0");
        assert!(!kind_may_use(0, 7), "and only that");
        assert!(kind_may_use(1, 7), "another kind is not limited by it");
    }
}
