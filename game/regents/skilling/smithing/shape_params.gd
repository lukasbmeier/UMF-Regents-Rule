@tool
class_name ShapeParams extends Resource
## ONE PART'S SMITHING ROUND (shape to the outline: `ShapeModel`). The hot bar is a row of columns;
## strike a column (the heavy strike) and it is beaten down `hammer_drop`, pushing `spread_pct` of that into each
## neighbor. Match the part's `outline` (one height per column). The bar is workable for `heat_ms`;
## reheating (right click, R) costs `reheat_ms`. Whole numbers only: the server replays it in Rust.

@export var display_name: String = "Part"
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 15000
## The shortest time between two strikes of the hammer.
@export_range(50, 2000, 10, "suffix:ms") var swing_ms: int = 280
## How long the bar stays hot enough to shape, and how long a reheat takes.
@export_range(500, 30000, 50, "suffix:ms") var heat_ms: int = 5000
@export_range(100, 10000, 50, "suffix:ms") var reheat_ms: int = 1500
## The bar's height to start with (every column), and up to this much more at random per column.
@export_range(1, 100) var start_height: int = 20
@export_range(0, 20) var start_jitter: int = 2
## How much a strike beats a column down, and the share of that pushed into each neighbor.
@export_range(1, 50) var hammer_drop: int = 4
@export_range(0, 50, 1, "suffix:%") var spread_pct: int = 20
## THE LIGHT TAP (the second strike, for finishing the line): how much it beats a column down, and the share
## pushed into each neighbor. 0 switches taps off (the round has the one strike, as before 2026-11-05).
@export_range(0, 50) var tap_drop: int = 0
@export_range(0, 50, 1, "suffix:%") var tap_spread_pct: int = 0
## THE BANDS' RULES (2026-11-05, `ShapeModel` says each; 0 is off, as a round from before them).
## HEATS, NOT A CLOCK: how many reheats the round has (then `duration_ms` is only a cap: the smith sets the part down),
## and how much each takes off the best the part can be (thousandths).
@export_range(0, 20) var max_reheats: int = 0
@export_range(0, 300, 1, "suffix:‰") var reheat_cost_pm: int = 0
## THE TEMPLATE: the outline shows only while it is laid on the bar (no strikes then); what each lay costs.
@export_range(0, 1) var hide_outline: int = 0
@export_range(0, 300, 1, "suffix:‰") var lay_cost_pm: int = 0
## THE PATTERN FADES (Luke, 2026-11-09, after playing: remembering a hidden outline made the bands too hard): lifted, the
## outline fades over `pattern_fade_ms` to `pattern_ghost_pm` of full (thousandths) and stays that faint; 0 / 0 is gone at
## once, as before. Only what is drawn: the round, its score and the server's replay are the same either way.
@export_range(0, 10000, 50, "suffix:ms") var pattern_fade_ms: int = 0
@export_range(0, 1000, 1, "suffix:‰") var pattern_ghost_pm: int = 0
## THE OUTLINE VARIES each round by up to this much (the same metal to beat off).
@export_range(0, 8) var outline_vary: int = 0
## HEAT COLORS: the last `red_ms` of a heat the bar is red; a strike then cracks it, costing `crack_cost_pm`.
@export_range(0, 5000, 50, "suffix:ms") var red_ms: int = 0
@export_range(0, 300, 1, "suffix:‰") var crack_cost_pm: int = 0
## THE QUENCH: set down while the bar's heat (thousandths) is in this window, it gains the bonus; outside, it loses
## up to the loss. Both ends 0: no quench.
@export_range(0, 1000, 1, "suffix:‰") var quench_lo_pm: int = 0
@export_range(0, 1000, 1, "suffix:‰") var quench_hi_pm: int = 0
@export_range(0, 300, 1, "suffix:‰") var quench_bonus_pm: int = 0
@export_range(0, 500, 1, "suffix:‰") var quench_loss_pm: int = 0
## The part's silhouette: one height per column (the bar has as many columns).
@export var outline: PackedInt32Array = PackedInt32Array([22, 20, 16, 12, 10, 10, 10, 10, 10, 10, 12, 14, 18, 22, 24, 24])
## The total height off the outline (summed over the columns) that scores nothing.
@export_range(1, 2000) var error_scale: int = 100
