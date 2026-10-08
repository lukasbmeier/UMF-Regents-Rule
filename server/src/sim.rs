//! FROZEN gravity-only movement twin. Used only by MODULE-authority (Tier A) worlds to keep idle
//! entities under gravity between client inputs. Do not extend: worlds that need real movement
//! run the headless Godot sidecar (docs/SIDECAR_SPEC.md), where client and server share
//! client/foundation/sim/movement_model.gd and collision comes from the level itself.
//!
//! The wire types (`Vector3`, `InputFrame`) are still the schema for `submit_input` and
//! `movement_state`; keep them in sync with input_frame.gd / movement_state.gd.
//!
//! Golden vectors (shared/golden/gravity_only.json) still run against this to catch accidental
//! edits. Rust⇄GDScript parity discipline now lives in the Challenge validators.

// NOT `spacetimedb`: depending on that crate pulls the WASM host ABI (datastore_*, console_log)
// into every native binary, which breaks `cargo test --test golden` at link. spacetimedb-lib
// carries the SpacetimeType derive with no ABI. `#[sats(crate = ...)]` redirects the paths the
// derive emits, which would otherwise point at `::spacetimedb`. Wire format is identical.
use spacetimedb_lib::SpacetimeType;

/// NAME MATTERS. The Godot SDK's codegen maps a SpacetimeType struct literally named
/// `Vector3` (with x/y/z f32) onto Godot's built-in `Vector3` and the BSATN `vector3` encoding.
/// Named anything else — it was `Vec3` — codegen emits a bespoke `Umf<Name>` Resource instead,
/// and every client-side read breaks: `MovementState.from_row()` tries to assign that Resource
/// into a `Vector3` field, and `submit_input` tries the reverse. Do not rename this.
#[derive(SpacetimeType, Clone, Copy, Debug, PartialEq, Default)]
#[sats(crate = spacetimedb_lib)]
pub struct Vector3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vector3 {
    pub const ZERO: Vector3 = Vector3 { x: 0.0, y: 0.0, z: 0.0 };
    pub const fn new(x: f32, y: f32, z: f32) -> Self { Vector3 { x, y, z } }
    pub fn add(self, o: Vector3) -> Vector3 { Vector3::new(self.x + o.x, self.y + o.y, self.z + o.z) }
    pub fn sub(self, o: Vector3) -> Vector3 { Vector3::new(self.x - o.x, self.y - o.y, self.z - o.z) }
    pub fn scale(self, s: f32) -> Vector3 { Vector3::new(self.x * s, self.y * s, self.z * s) }
    pub fn abs(self) -> Vector3 { Vector3::new(self.x.abs(), self.y.abs(), self.z.abs()) }
    pub fn max_component(self) -> f32 { self.x.max(self.y).max(self.z) }
    pub fn length_sq(self) -> f32 { self.x * self.x + self.y * self.y + self.z * self.z }
}

/// Wire shape of one client input tick. Field order matches InputFrame.to_reducer_args().
#[derive(SpacetimeType, Clone, Copy, Debug, PartialEq, Default)]
#[sats(crate = spacetimedb_lib)]
pub struct InputFrame {
    pub seq: u32,
    pub client_tick: u32,
    pub move_x: f32,
    pub move_y: f32,
    pub look_yaw: f32,
    /// Phase 3 Task 1. Carried for aim/raycast use by the sidecar and the action layer; the
    /// frozen gravity-only twin ignores it, which is why the golden values are unchanged.
    pub look_pitch: f32,
    pub jump: bool,
    pub sprint: bool,
    /// MODULE-authority worlds trust this within a per-frame speed envelope. Ignored by the sidecar.
    pub client_pos: Vector3,
    /// The `movement_state.correction_epoch` the client had applied when it produced this frame.
    /// The module bumps the epoch whenever it overrides a client (teleport, speed clamp); frames
    /// from another epoch describe a path the server has already replaced, and are consumed
    /// without moving anything. Wire-only, exactly like `look_pitch`: the frozen twin never
    /// reads it, which is why the golden vectors are unchanged.
    pub epoch: u32,
    /// What the client's model says this frame's movement is (IDLE/WALK/SPRINT/AIR/DASH..., or a
    /// genre state >= 100). Tier A mirrors it onto the row so other clients can animate. Wire-only:
    /// the frozen twin never reads it.
    pub move_state: u8,
    /// Dash pressed (config-gated, PHASE4_SPEC §2.4). Wire-only: the frozen twin never reads it.
    pub dash: bool,
    /// The slow-walk modifier. Wire-only, like the two above: the frozen twin never reads it,
    /// and Tier A only needs it to know which speed the envelope should allow.
    pub slow: bool,
    /// Face `look_yaw` this frame even standing still: something is being AIMED (a cast, a bow,
    /// a throw). Without it the body turns to the camera only while moving (DECISIONS #100).
    /// Wire-only: the frozen twin never reads it; the facing rule in `module.rs` does, and the
    /// client's `_step` applies the same rule to the same frame.
    pub face: bool,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MovementState {
    pub pos: Vector3,
    pub vel: Vector3,
    pub yaw: f32,
    pub grounded: bool,
    pub move_state: u8,
}

impl Default for MovementState {
    fn default() -> Self {
        MovementState { pos: Vector3::ZERO, vel: Vector3::ZERO, yaw: 0.0, grounded: true, move_state: 0 }
    }
}

impl MovementState {
    pub fn max_error(&self, o: &MovementState) -> f32 {
        self.pos.sub(o.pos).abs().max_component().max(self.vel.sub(o.vel).abs().max_component())
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MovementConfig {
    pub walk_speed: f32,
    pub sprint_speed: f32,
    pub acceleration: f32,
    pub friction: f32,
    pub air_control: f32,
    pub jump_velocity: f32,
    pub gravity: f32,
    pub max_slope_deg: f32,
    pub coyote_time_sec: f32,
    pub ground_y: f32,
}

pub fn simulate(state: &MovementState, input: &InputFrame, cfg: &MovementConfig, dt: f32) -> MovementState {
    let mut s = *state;

    // 1. Jump (only from ground)
    if s.grounded && input.jump {
        s.vel = Vector3::new(s.vel.x, cfg.jump_velocity, s.vel.z);
        s.grounded = false;
    }

    // 2. Gravity (airborne only)
    if !s.grounded {
        s.vel = s.vel.sub(Vector3::new(0.0, cfg.gravity, 0.0).scale(dt));
    }

    // 3. Integrate
    s.pos = s.pos.add(s.vel.scale(dt));

    // 4. Flat ground plane
    let ground = Vector3::new(0.0, cfg.ground_y, 0.0);
    if s.pos.y <= ground.y && s.vel.y <= 0.0 {
        s.pos = Vector3::new(s.pos.x, ground.y, s.pos.z);
        s.vel = Vector3::new(s.vel.x, 0.0, s.vel.z);
        s.grounded = true;
    }

    s
}
