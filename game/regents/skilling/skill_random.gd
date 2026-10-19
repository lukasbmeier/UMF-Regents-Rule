class_name SkillRandom extends RefCounted
## The skilling minigames' seeded numbers: challenge.rs's xorshift32 and its seed fold (ChallengeModel
## has the same), so every model's Rust twin draws exactly the same. Every shift is masked to 32 bits,
## since GDScript's `>>` on a negative int is arithmetic and Rust's on a u64 is logical.

const M32: int = 0xFFFFFFFF


static func next_u32(state: int) -> int:
	var x: int = state & M32
	x = (x ^ ((x << 13) & M32)) & M32
	x = x ^ (x >> 17)
	x = (x ^ ((x << 5) & M32)) & M32
	return x


static func seed_state(seed_value: int) -> int:
	var s: int = ((seed_value & M32) ^ ((seed_value >> 32) & M32)) & M32
	return 1 if s == 0 else s
