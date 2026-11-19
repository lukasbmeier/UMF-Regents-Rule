class_name AbilityMoves extends Resource
## WHICH ABILITIES ARE SHOWN AS MOVES (PROGRESS 110): the motion lab's moves (`game/regents/motion/moves/`) on the
## abilities they play for, edited in the Inspector (`ability_moves.tres`). An ability with no row plays its clip as
## before. Read through `of`.

const PATH: String = "res://game/regents/motion/ability_moves.tres"

@export var rows: Array[AbilityMove] = []

static var _by_id: Dictionary[int, AbilityMove] = {}
static var _loaded: bool = false


## The row for ability `ability_id`, or null.
static func of(ability_id: int) -> AbilityMove:
	if not _loaded:
		_loaded = true
		var t: AbilityMoves = load(PATH) as AbilityMoves
		if t != null:
			for r: AbilityMove in t.rows:
				if r != null and r.ability != null:
					_by_id[r.ability.id] = r
	return _by_id.get(ability_id) as AbilityMove
