class_name ChallengeModel extends RefCounted
## GDScript twin of server/src/challenge.rs. The client plays the minigame against this model;
## the module re-simulates the submission with the Rust side and scores it. Both are checked
## against shared/golden/challenge_timing.json at max_err = 0 (DECISIONS #19, AGENTS rule 7).
##
## RULES — identical in spirit to movement_model.gd:
##  1. f32 only, same operation order as the Rust twin. GDScript floats are f64, so every
##     intermediate is forced back to f32 by routing it through a Vector3 lane (Vector3
##     components are 32-bit). Chaining several ops in f64 and rounding once at the end is
##     double-rounding and WILL drift from Rust.
##  2. TIMING_ROUNDS is 3 precisely so one challenge fits one Vector3 — centres, presses,
##     distances and per-round quality are each a single vector op.
##  3. Any change regenerates shared/golden/challenge_timing.json and must pass on both sides.
##
## Integer note: `seed` arrives as a u64 column, which GDScript holds as a wrapped int64. Every
## shift is masked to 32 bits BEFORE use, because GDScript's `>>` on a negative int is an
## arithmetic shift while Rust's on a u64 is logical — unmasked they disagree for any seed with
## the high bit set.

const KIND_TIMING_BAR: int = 0
const TIMING_ROUNDS: int = 3
const M32: int = 0xFFFFFFFF


static func _next_u32(state: int) -> int:
	var x: int = state & M32
	x = (x ^ ((x << 13) & M32)) & M32
	x = x ^ (x >> 17)
	x = (x ^ ((x << 5) & M32)) & M32
	return x


## Fold a 64-bit seed to a non-zero 32-bit state. See the collision note in challenge.rs:
## seeds 0, 1 and u64::MAX all land here on the same state, by design and pinned by the goldens.
static func _seed_state(seed_value: int) -> int:
	var s: int = ((seed_value & M32) ^ ((seed_value >> 32) & M32)) & M32
	return 1 if s == 0 else s


## Top 24 bits over 2^24 — exact in f32 on both sides, which is why the PRNG is not widened.
static func _unit_from(v: int) -> float:
	return float(v >> 8) / 16777216.0


## Target centres for one challenge, derived from the seed alone.
static func timing_centers(seed_value: int) -> Vector3:
	var st: int = _seed_state(seed_value)
	st = _next_u32(st)
	var u0: float = _unit_from(st)
	st = _next_u32(st)
	var u1: float = _unit_from(st)
	st = _next_u32(st)
	var u2: float = _unit_from(st)
	# Constructing the Vector3 rounds each unit to f32 once; the arithmetic below is then f32.
	var u: Vector3 = Vector3(u0, u1, u2)
	return Vector3(0.15, 0.15, 0.15) + u * 0.7


## Half-width of the hit window. Routed through a Vector3 component so the multiply and the
## subtract each round to f32, matching `0.16f32 - 0.12f32 * difficulty`.
static func timing_half_width(difficulty: float) -> float:
	var d: Vector3 = Vector3(difficulty, 0.0, 0.0)
	return (Vector3(0.16, 0.0, 0.0) - Vector3(0.12, 0.0, 0.0) * d.x).x


## Score a submission. Returns quality in [0,1], or -1.0 if the submission is malformed.
## (-1.0 stands in for Rust's `None`: a rejection, not a zero score. Callers must check.)
static func validate_challenge(kind: int, seed_value: int, difficulty: float,
		result: PackedFloat32Array) -> float:
	if kind != KIND_TIMING_BAR:
		return -1.0
	if result.size() != TIMING_ROUNDS:
		return -1.0
	if not is_finite(difficulty) or difficulty < 0.0 or difficulty > 1.0:
		return -1.0
	for p: float in result:
		if not is_finite(p) or p < 0.0 or p > 1.0:
			return -1.0

	var centers: Vector3 = timing_centers(seed_value)
	var half: float = timing_half_width(difficulty)

	# One lane, one op per line — mirrors the Rust loop body exactly.
	var presses: Vector3 = Vector3(result[0], result[1], result[2])
	var d: Vector3 = (presses - centers).abs()
	var t: Vector3 = d / half
	var q: Vector3 = (Vector3(1.0, 1.0, 1.0) - t).clampf(0.0, 1.0)

	# Left-to-right accumulation: ((q0 + q1) + q2) / 3, rounding to f32 at each step.
	var s01: float = Vector3(q.x + q.y, 0.0, 0.0).x
	var s012: float = Vector3(s01 + q.z, 0.0, 0.0).x
	return Vector3(s012 / 3.0, 0.0, 0.0).x


# --- the server-timed press (DECISIONS #210) ----------------------------------------------------
# The client's twin of `challenge.rs`'s timed press, for drawing the sweep and predicting a press. The
# server judges every press itself (`challenge_press`); this only says what the player will see.

const KIND_TIMED_PRESS: int = 1
## The quality from which a press is Great (above 0: Good; 0: a Miss). The server pays a genre's
## check by the same number (`challenge::GREAT_FROM`, DECISIONS #219).
const GREAT_FROM: float = 0.75


## Where the marker is `elapsed_s` after it began to sweep: 0 at the start, 1 half a period later,
## back to 0 at a full period. 0 before it begins.
static func sweep_position(elapsed_s: float, period_s: float) -> float:
	if elapsed_s <= 0.0 or period_s <= 0.0:
		return 0.0
	var phase: float = fposmod(elapsed_s / period_s, 1.0)
	var up: float = phase * 2.0
	return up if up <= 1.0 else 2.0 - up


## How good one press is: 1 on the target's centre, falling to 0 at `half` from it.
static func press_quality(position: float, center: float, half: float) -> float:
	if half <= 0.0:
		return 0.0
	return clampf(1.0 - absf(position - center) / half, 0.0, 1.0)


## The credit a press is given for its trip to the server, in ms: half the quickest round trip, capped.
static func press_credit_ms(min_rtt_ms: int, cap_ms: int) -> int:
	return mini(min_rtt_ms / 2, cap_ms) if min_rtt_ms > 0 else 0
