@tool
class_name CarveParams extends Resource
## ONE CARVING ROUND (woodworking: `CarveModel`; Luke, 2026-11-07: "have woodcarve/woodworking be vertical and have wood
## you can take off from either side (to allow asymmetry for bows/staffs) instead of just being a duplicate of
## smithing"). A stave stands upright, cut into rows; each row has a LEFT edge and a RIGHT edge, measured out from the
## stave's middle line. Cut a row from the left (its left edge comes in) or from the right, deep or fine, down to the
## part's two profiles, which need not match (a bow's back and belly, a staff's head). Wood never goes back. The pattern
## is laid against the stave at the start: look, lift it, carve from memory. Whole numbers only (the server replays it
## in Rust: `genre::regents::carve`).

@export var display_name: String = "Carving"
## How long the round can last (Enter sets the piece down sooner), and the shortest time between two cuts.
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 16000
@export_range(50, 2000, 10, "suffix:ms") var swing_ms: int = 240
## The blank: each edge's distance from the middle line at the start, give or take `start_jitter` (from the seed).
@export_range(1, 60) var start_half: int = 10
@export_range(0, 10) var start_jitter: int = 1
## How far a deep cut and a fine shave take an edge in.
@export_range(1, 20) var deep_cut: int = 3
@export_range(1, 20) var fine_cut: int = 1
## The part's two profiles, row by row from the top: each edge's distance out from the middle line (NEGATIVE: past it,
## on the other side: a curved stave's edge crosses the line). The same length.
@export var left_outline: PackedInt32Array = PackedInt32Array([4, 5, 6, 6, 5, 4])
@export var right_outline: PackedInt32Array = PackedInt32Array([4, 5, 6, 6, 5, 4])
## Each round the profiles are bent a little from the seed (a bump on each side, up to this far), so none is memorized.
@export_range(0, 10) var outline_vary: int = 2
## The score: how much being off the profiles (summed, both sides) costs: `error_scale` off scores nothing.
@export_range(1, 1000) var error_scale: int = 30
## The pattern: 1 laid on at the start (no cuts while it is on); each lay after the first costs this much of the best the
## piece can be (thousandths). 0: no pattern, the profiles always shown.
@export_range(0, 1) var hide_outline: int = 1
@export_range(0, 1000, 1, "suffix:‰") var lay_cost_pm: int = 30
## THE PATTERN FADES (Luke, 2026-11-09, after playing: remembering a hidden outline made the bands too hard): lifted, the
## outline fades over `pattern_fade_ms` to `pattern_ghost_pm` of full (thousandths) and stays that faint; 0 / 0 is gone at
## once, as before. Only what is drawn: the round, its score and the server's replay are the same either way.
@export_range(0, 10000, 50, "suffix:ms") var pattern_fade_ms: int = 0
@export_range(0, 1000, 1, "suffix:‰") var pattern_ghost_pm: int = 0
## 1: the seed may swap the two profiles, so the piece bends one way or the other (Luke, 2026-11-07: an unstrung bow
## "backwards (curve going right or left)"). 0: always as written.
@export_range(0, 1) var mirror: int = 0
