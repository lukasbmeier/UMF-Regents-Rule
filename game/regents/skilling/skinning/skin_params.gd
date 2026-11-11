@tool
class_name SkinParams extends Resource
## ONE SKINNING ROUND: THE CUT LINE (`SkinModel`; `HERBALISM_HUNTING_PREP.md` H4, Luke 2026-11-07: "DRAG the knife along
## the cut line: a new continuous model (off the line tears the hide)"). The carcass shows a line to cut; HOLD the mouse
## at its start and DRAG the knife along it. The cut follows the knife while the knife stays on the line near the cut's
## end, no faster than the knife cuts; anywhere else in the hide (off the line, or run ahead of the cut) it TEARS the
## hide. Let go to stop safely; press again at the cut's end to go on. A line cut to its end, the next is marked, until
## the round's time runs out. A round SKINS THE WHOLE CARCASS (Luke, 2026-11-10: a deer holds several hides, a better
## round gives more, up to a cap: `NodeDef.whole_round`). Whole numbers only (the server replays it in Rust:
## `genre::regents::skin`). The hide is 1000 wide; lines run across it, left to right or right to left.

@export var display_name: String = "Deer"
## How long the round lasts: lines are cut one after another until it runs out.
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 12000
## Clean lines for a full score: a round's score is what its lines are worth over this many, never past full.
@export_range(1, 50) var target_lines: int = 4

@export_group("The line (drawn from the seed, each its own)")
## How many points a line bends at, its two ends included (from 100 to 900 across the hide).
@export_range(2, 20) var points: int = 5
## How far each point strays up or down from the line's middle (of the hide's 1000).
@export_range(0, 300) var wobble: int = 120

@export_group("The knife")
## How far off the line (of the hide's 1000) the knife still cuts along it. Rank widens it (M3).
@export_range(1, 300) var near: int = 45
## How far from the cut's end the knife may be and still be cutting there (on the line, ahead of it or on the cut).
@export_range(1, 1000) var reach: int = 120
## How far the cut can run each 50 ms (of the hide's 1000): drag faster and the knife runs ahead of it, off the cut,
## and tears. A better knife cuts faster (the tool's speed scales it, as an axe's swing).
@export_range(1, 1000) var cut_speed: int = 30

@export_group("Tears")
## What each 50 ms the knife spends in the hide off the cut costs that line (of its 1000).
@export_range(0, 1000, 1, "suffix:‰") var tear_pm: int = 35
## A line not cut to its end when the time runs out: worth this share of what was cut of it.
@export_range(0, 1000, 1, "suffix:‰") var part_keep_pm: int = 500
