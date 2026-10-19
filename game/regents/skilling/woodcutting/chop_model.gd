class_name ChopModel extends RefCounted
## WOODCUTTING'S MINIGAME, BRANCH DODGE (owner, 2026-10-18): a 2D trunk; you chop it from the left or
## the right. Each clean chop takes the bottom piece off and the trunk drops one piece. The piece just
## above the cut is at your head: if it carries a branch on the side you chop from, the branch hits you,
## the swing is lost, the trunk does not drop and you are staggered. So: always chop from the side the
## next branch is NOT on.
##
## A PURE MODEL: the round is decided by the seed, the tree's `ChopParams` and the player's inputs
## alone (each a time since the round began and a side), so the server can replay a round from its
## inputs and score it, never trusting a client's score (AGENTS.md rule 13). The live minigame
## (`chop_minigame.gd`) plays through `chop()` on an instance of this, and `play()` replays a whole
## round through the same `chop()`, so what the player saw and what a replay scores cannot differ.
## Integers only, and the generator is challenge.rs's xorshift32, so the Rust twin (written once the
## rules have been playtested) agrees exactly.

const BRANCH_NONE: int = 0
const BRANCH_LEFT: int = 1
const BRANCH_RIGHT: int = 2
## The sides a player chops from: the same numbers as the branches, so a hit is `branch == side`.
const SIDE_LEFT: int = BRANCH_LEFT
const SIDE_RIGHT: int = BRANCH_RIGHT

## What one input did.
const IGNORED: int = 0   # outside the round, out of order, mid-swing or staggered: nothing happens
const CLEAN: int = 1     # the bottom piece is off; the trunk dropped one piece
const HIT: int = 2       # a branch on that side: no chop, staggered
const HELD: int = 3      # pressed mid-swing: held, and swung the moment the swing ends (the latest press wins)

## Pieces of trunk generated beyond the most a round can chop, for the view above the cut.
const VIEW_SEGMENTS: int = 8

var params: ChopParams
## Every piece of trunk, bottom first: BRANCH_NONE, BRANCH_LEFT or BRANCH_RIGHT.
var segments: PackedInt32Array
## The bottom piece still standing (pieces below it are chopped).
var cut: int = 0
## Where the woodcutter stands: the side of the last swing (a round starts on the left).
var side: int = SIDE_LEFT
var clean: int = 0
var hits: int = 0
var combo: int = 0
var best_combo: int = 0
## Earliest time the next swing may land (a swing in progress, or a stagger).
var next_ok_ms: int = 0
## The latest input's time: an earlier one after it is out of order.
var last_t_ms: int = -1
## Whether `next_ok_ms` is a stagger (a press then is lost) rather than a swing (a press then is held).
var staggered: bool = false
## A press held through a swing: whether there is one, when it lands (the swing's end) and its side.
var held: bool = false
var held_at_ms: int = 0
var held_side: int = 0
## Swings landed, counted, and the latest's outcome and time: the live view follows these.
var acts: int = 0
var last_act: int = IGNORED
var last_act_ms: int = 0


## A round of tree `p` from `seed_value`.
static func start(seed_value: int, p: ChopParams) -> ChopModel:
	var m: ChopModel = ChopModel.new()
	m.params = p
	m.segments = branches(seed_value, p, max_chops(p) + 2 + VIEW_SEGMENTS)
	return m


## The most clean chops a round of `p` could hold: one at 0 ms and one per swing after it.
static func max_chops(p: ChopParams) -> int:
	return p.duration_ms / p.swing_ms + 1


## The trunk's first `n` pieces from `seed_value`, bottom first. A prefix does not depend on `n`.
static func branches(seed_value: int, p: ChopParams, n: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(n)
	var st: int = _seed_state(seed_value)
	for i: int in n:
		if i < p.safe_segments:
			out[i] = BRANCH_NONE
			continue
		st = _next_u32(st)
		if ((st >> 8) * 1000) >> 24 >= p.branch_permille:
			out[i] = BRANCH_NONE
			continue
		st = _next_u32(st)
		out[i] = BRANCH_RIGHT if (st >> 31) & 1 == 1 else BRANCH_LEFT
	return out


## The branch at the woodcutter's head: on the piece just above the cut.
func head_branch() -> int:
	return segments[cut + 1] if cut + 1 < segments.size() else BRANCH_NONE


## One press at `t_ms` (milliseconds since the round began) from side `at_side`. Returns what it did.
## Mid-swing it is HELD and swung the moment the swing ends (a later press replaces it); while
## staggered it is lost. So quick side switches never drop a press (owner, 2026-10-19).
func chop(t_ms: int, at_side: int) -> int:
	if t_ms < last_t_ms:
		return IGNORED
	last_t_ms = t_ms
	settle(t_ms)
	if t_ms < 0 or t_ms > params.duration_ms:
		return IGNORED
	if at_side != SIDE_LEFT and at_side != SIDE_RIGHT:
		return IGNORED
	if t_ms < next_ok_ms:
		if staggered:
			return IGNORED
		held = true
		held_at_ms = next_ok_ms
		held_side = at_side
		return HELD
	return _swing(t_ms, at_side)


## Swing a held press whose swing ended by `t_ms`. Returns what it did (IGNORED: nothing landed).
func settle(t_ms: int) -> int:
	if not held or held_at_ms > t_ms:
		return IGNORED
	held = false
	if held_at_ms > params.duration_ms:
		return IGNORED
	return _swing(held_at_ms, held_side)


## The round to its end: a press still held swings if its swing ends in time.
func finish() -> void:
	settle(params.duration_ms)


func _swing(t_ms: int, at_side: int) -> int:
	side = at_side
	acts += 1
	last_act_ms = t_ms
	if head_branch() == at_side:
		hits += 1
		combo = 0
		next_ok_ms = t_ms + params.stagger_ms
		staggered = true
		last_act = HIT
		return HIT
	cut += 1
	clean += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	next_ok_ms = t_ms + params.swing_ms
	staggered = false
	last_act = CLEAN
	return CLEAN


## The round's score in thousandths: clean chops over the tree's target, at most 1000.
func score_pm() -> int:
	return mini(1000, clean * 1000 / params.target_chops)


func result() -> Dictionary:
	return {"clean": clean, "hits": hits, "best_combo": best_combo, "score_pm": score_pm()}


## A whole round replayed from its inputs: `inputs` is flat pairs, time then side, in the order sent.
## What the server will do with a round a client sends.
static func play(seed_value: int, p: ChopParams, inputs: PackedInt32Array) -> Dictionary:
	var m: ChopModel = start(seed_value, p)
	var i: int = 0
	while i + 1 < inputs.size():
		m.chop(inputs[i], inputs[i + 1])
		i += 2
	m.finish()
	return m.result()


# The shared generator (SkillRandom: challenge.rs's xorshift32), kept under these names for the tests.
static func _next_u32(state: int) -> int:
	return SkillRandom.next_u32(state)


static func _seed_state(seed_value: int) -> int:
	return SkillRandom.seed_state(seed_value)
