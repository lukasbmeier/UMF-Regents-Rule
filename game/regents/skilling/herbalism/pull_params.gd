@tool
class_name PullParams extends Resource
## ONE HERBALISM ROUND: PULL THE ROOT (`PullModel`; `HERBALISM_HUNTING_PREP.md` §3, Luke's H3, 2026-11-07: "hold to
## pull, strain rises and eases when let go, the plant trembles before a jump, past the top it snaps"). A round is a
## CLUMP (Luke, 2026-11-08): stem after stem until the time runs out. After his first play (2026-11-08: "we use the
## trowel more to outline and dig in the earth, cut roots that are snagging") the TROWEL works too, a stroke at a time,
## on the side pressed (A / D): it DIGS the packed soil on that side (packed soil holds the root: it comes up slower),
## or CUTS the side root about to catch there (the soil cracks on that side as the root nears it). HOLD to pull: the
## strain rises (pulling harder brings the root up faster) and eases when let go; a catch pulled through uncut jumps
## the strain; past the top the stem SNAPS (you keep part of what came up; the next stem starts). While a stroke runs
## the stem is not pulled. Whole numbers only (the server replays it in Rust: `genre::regents::pull`).

@export var display_name: String = "Flax"
## How long the round lasts: stems are pulled one after another until it runs out.
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 15000
## How long one trowel stroke takes (dig or cut; no other stroke and no pulling meanwhile). A better trowel strokes
## faster (the tool's speed scales it, as an axe's swing).
@export_range(50, 2000, 10, "suffix:ms") var stroke_ms: int = 250

@export_group("The clump")
## Whole roots for a full score: a round's score is what its roots are worth over this many (each whole root 1000, a
## snapped one part of what came up), never past full.
@export_range(1, 50) var target_plants: int = 3

@export_group("The soil")
## How much one stroke loosens a side of the stem (a packed side starts at 1000).
@export_range(1, 1000) var dig_pm: int = 500
## LOOSE OR PACKED (Luke, 2026-11-09, "cutaway, no chore": digging both sides of every stem was a chore with no
## choice): the chance (thousandths) that each side of a stem starts LOOSE, nothing to dig there; the cutaway shows
## which. 0: every side packed, as before.
@export_range(0, 1000, 1, "suffix:‰") var loose_pm: int = 0
## How much fully packed soil holds the root back (of its pull, thousandths; both sides averaged): 600 = packed on
## both sides it comes up at 40 % of the pace.
@export_range(0, 1000, 1, "suffix:‰") var hold_pm: int = 600

@export_group("Pulling (each 50 ms held)")
## How much the strain rises each 50 ms held, and eases each 50 ms not pulled (the top is 1000: past it, it snaps).
@export_range(1, 1000) var strain_rise: int = 40
@export_range(1, 1000) var strain_ease: int = 60
## How far the root comes up each 50 ms held in loose soil (the whole root is 1000): `pull_rate`, plus `pull_gain` at
## full strain (in proportion below it): pulling harder pulls faster.
@export_range(0, 1000) var pull_rate: int = 10
@export_range(0, 1000) var pull_gain: int = 40

@export_group("The side roots (drawn from the seed, each stem its own)")
## How many side roots catch each stem's root on the way up (spread from 5 % to 95 % of it, each in its own stretch,
## each on the left or the right).
@export_range(0, 20) var snags: int = 2
## How much the strain jumps when one is pulled through uncut (each somewhere between these).
@export_range(0, 1000) var jump_lo: int = 200
@export_range(0, 1000) var jump_hi: int = 400
## How far below a side root (of the root's 1000) the soil cracks on its side: from there a stroke on that side cuts it.
@export_range(0, 1000) var show_depth: int = 350

@export_group("A snapped root")
## What a root not pulled whole (snapped, or still in the ground at the end) is worth, in thousandths of what came up.
@export_range(0, 1000, 1, "suffix:‰") var snap_keep_pm: int = 250
