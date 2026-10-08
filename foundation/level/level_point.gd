@tool
class_name LevelPoint extends Marker3D
## ANYTHING ELSE A GENRE NEEDS TO KNOW IS THERE, in a level built in the editor (DECISIONS #175): a
## disc golf basket or tee, a chicken coop, a goal, a respawn point. Its `kind` says what it is to
## the genre that reads it (the server: `LevelBake::points_of`, the client: `LevelBake.points_of`);
## the foundation only carries it. Baked by `LevelInfo`.

## Its id, unique in the level.
@export var point_id: String = "":
	set(v):
		point_id = v
		update_configuration_warnings()
## What it is ("basket", "tee", "coop"...).
@export var kind: String = "":
	set(v):
		kind = v
		update_configuration_warnings()
## A size, if it has one (metres).
@export_range(0.0, 200.0, 0.1) var radius: float = 0.0:
	set(v):
		radius = v
		gizmo_extents = maxf(v, 0.25)
## Anything else its genre wants to know ("hole_3", "par_4").
@export var tags: PackedStringArray = PackedStringArray()


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if point_id.is_empty():
		w.append("A point needs a Point Id.")
	if kind.is_empty():
		w.append("A point needs a Kind (what it is to the genre that reads it).")
	return w
