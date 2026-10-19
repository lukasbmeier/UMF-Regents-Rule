@tool
class_name ChopParams extends Resource
## ONE TREE'S WOODCUTTING ROUND (the branch-dodge minigame, `ChopModel`): how long a round lasts, how
## fast the axe swings, how branchy the trunk is and how many clean chops a full score takes. A tree
## tier is one of these (`trees/`); a better axe will shorten `swing_ms`. Every number is a whole
## number of milliseconds or a count, because the server replays a round with the same numbers in
## Rust and integers agree exactly on both sides.
##
## A prototype's resource: it becomes the minigame's content (a `MinigameDef`, baked) once the server
## replays rounds; until then edit it in the Inspector and play it in `chop_lab.tscn` (F6).

## The tree's name, as the round shows it.
@export var display_name: String = "Tree"
## How long one round lasts.
@export_range(1000, 60000, 100, "suffix:ms") var duration_ms: int = 10000
## The shortest time between two chops: the axe's swing. A chop pressed sooner is not swung.
@export_range(50, 2000, 10, "suffix:ms") var swing_ms: int = 300
## After a branch hits you, this long before you can swing again.
@export_range(0, 5000, 10, "suffix:ms") var stagger_ms: int = 800
## How likely a piece of trunk is to carry a branch, in thousandths (450 = 45 %).
@export_range(0, 1000, 5, "suffix:‰") var branch_permille: int = 450
## The first pieces of trunk never carry a branch, so a round never opens with a hit.
@export_range(0, 20) var safe_segments: int = 2
## Clean chops for a full score. Fewer score in proportion; more score no higher.
@export_range(1, 500) var target_chops: int = 22
