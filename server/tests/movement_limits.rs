//! A KIND'S MOVEMENT BOUND (DECISIONS #205): with no movement profile, every kind keeps the
//! default's bound, exactly what the module used before profiles (sprint, no dash, a jump's lift).

use umf_module::content::{movement_limits, DEFAULT_LIMITS, KIND_LIMITS};
use umf_module::movement_config as mc;

#[test]
fn the_default_bound_is_the_default_movement() {
    assert_eq!(DEFAULT_LIMITS.sprint, mc::SPRINT_SPEED);
    let lift = if mc::FLAP_CHARGES > 0 { mc::JUMP_VELOCITY.max(mc::FLAP_VELOCITY) } else { mc::JUMP_VELOCITY };
    assert_eq!(DEFAULT_LIMITS.lift, lift);
    assert_eq!(DEFAULT_LIMITS.burst, mc::DASH_IMPULSE.max(0.0));
}

#[test]
fn a_kind_without_a_profile_takes_the_default() {
    for kind in 0..=255u8 {
        if !KIND_LIMITS.iter().any(|k| k.0 == kind) {
            assert_eq!(movement_limits(kind), DEFAULT_LIMITS);
        }
    }
}

/// tests/content_test.sh builds against a copy whose humanoid (kind 0) links a fast profile and
/// says what kind 0's sprint must then be; any other run skips this.
#[test]
fn a_profiled_kind_takes_its_profiles_bound() {
    if let Ok(v) = std::env::var("UMF_EXPECT_KIND0_SPRINT") {
        let want: f32 = v.parse().expect("UMF_EXPECT_KIND0_SPRINT is a number");
        assert_eq!(movement_limits(0).sprint, want, "kind 0's bound is its character's profile");
        assert_eq!(movement_limits(1), DEFAULT_LIMITS, "a kind with no profiled character keeps the default");
    }
}
