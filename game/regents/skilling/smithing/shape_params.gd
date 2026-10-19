@tool
class_name ShapeParams extends Resource
## ONE PART'S SMITHING ROUND (shape to the outline: `ShapeModel`). The hot bar is a row of columns;
## strike a column and it is beaten down `hammer_drop`, pushing `spread_pct` of that into each
## neighbour. Match the part's `outline` (one height per column). The bar is workable for `heat_ms`;
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
## How much a strike beats a column down, and the share of that pushed into each neighbour.
@export_range(1, 50) var hammer_drop: int = 4
@export_range(0, 50, 1, "suffix:%") var spread_pct: int = 20
## The part's silhouette: one height per column (the bar has as many columns).
@export var outline: PackedInt32Array = PackedInt32Array([22, 20, 16, 12, 10, 10, 10, 10, 10, 10, 12, 14, 18, 22, 24, 24])
## The total height off the outline (summed over the columns) that scores nothing.
@export_range(1, 2000) var error_scale: int = 100
