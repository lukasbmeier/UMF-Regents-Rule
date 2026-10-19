@tool
class_name CrackParams extends Resource
## ONE ROCK'S MINING ROUND (crack the rock: follow the seam, `CrackModel`): a seam runs across the rock's
## face as a faint crack outline of `notches` notches; strike the next one (within `radius_pm`) and the
## crack opens to it. Opened end to end, the seam splits the rock and the next seam shows. A strike off
## the notch jars the pick (`stagger_ms`). Whole numbers only: the server replays a round with the same
## numbers in Rust. Positions are thousandths of the rock face (0..1000).

@export var display_name: String = "Rock"
## How long one round lasts.
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 10000
## The shortest time between two strikes: the pick's swing. A strike sooner is held until it ends.
@export_range(50, 2000, 10, "suffix:ms") var swing_ms: int = 260
## After striking off the seam, this long before the next strike (a strike then is lost).
@export_range(0, 5000, 10, "suffix:ms") var stagger_ms: int = 700
## A seam opened end to end splits the rock: this long before the next seam can be struck.
@export_range(0, 5000, 10, "suffix:ms") var split_ms: int = 600
## Notches along one seam (its first is at one edge of the face, its last at the other).
@export_range(2, 30) var notches: int = 7
## How far each notch may wander across from the last, in thousandths: higher is a wilder seam.
@export_range(0, 500, 5, "suffix:‰") var bend_pm: int = 120
## How close to the next notch a strike must land, in thousandths of the face.
@export_range(10, 400, 5, "suffix:‰") var radius_pm: int = 80
## Seams keep this far from the face's edges.
@export_range(0, 400, 5, "suffix:‰") var margin_pm: int = 120
## How many notches past the next one the faint outline shows (0: only the next one glows). Harder rocks
## show less of where the seam goes.
@export_range(0, 30) var reveal_ahead: int = 6
## Notches opened for a full score.
@export_range(1, 500) var target_hits: int = 16
