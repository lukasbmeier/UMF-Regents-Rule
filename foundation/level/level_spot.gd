@tool
class_name LevelSpot extends Marker3D
## A NAMED PIECE OF WATER in a level built in the editor (DECISIONS #175): a fishing spot, with its
## own loot table in the genre's data (`shared/fishing/fishing.json` `spots`, by `spot_id`). Its
## circle (`radius`, shown by the gizmo) is what the server calls this spot. Baked by `LevelInfo`.

## Its id: what the genre's data and the server call it.
@export var spot_id: String = "":
	set(v):
		spot_id = v
		update_configuration_warnings()
## What players see.
@export var display_name: String = ""
## Metres: every point of water within this of the marker is the spot.
@export_range(0.5, 200.0, 0.5) var radius: float = 8.0:
	set(v):
		radius = v
		gizmo_extents = v


func _ready() -> void:
	gizmo_extents = radius


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray(["A spot needs a Spot Id."]) if spot_id.is_empty() else PackedStringArray()
