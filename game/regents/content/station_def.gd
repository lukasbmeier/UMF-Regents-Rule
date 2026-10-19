@tool
class_name StationDef extends ContentDef
## A STATION (design §7.3): a furnace, an anvil, a workbench. A level places one with a `LevelPoint` of
## kind "station" tagged with its `key`; the recipes made at it name the same key (`RecipeDef.station`).
## At one, Q picks the recipe, tap E works it AFK, hold E plays its round.

@export var key: StringName = &"furnace"
@export_group("How it shows")
## Its look: the pieces it is built of, each placed by its own transform in `piece_transforms`.
@export var pieces: Array[PackedScene] = []
@export var piece_transforms: Array[Transform3D] = []
## A glow inside it (a furnace's fire), off when transparent.
@export var glow_color: Color = Color(0, 0, 0, 0)
## A greybox body under the pieces (a furnace's stone), none when its size is zero.
@export var body_size: Vector3 = Vector3.ZERO
@export var body_color: Color = Color(0.45, 0.43, 0.42)

static var _by_key: Dictionary[StringName, StationDef] = {}


func content_type() -> StringName:
	return &"station"


func why_no_workbench() -> String:
	return "a key and its look; its recipes are tried in the skilling lab"


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "key": String(key)}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (furnace, anvil, workbench)")
	if pieces.size() != piece_transforms.size():
		out.append("one transform per piece (%d pieces, %d transforms)" % [pieces.size(), piece_transforms.size()])
	return out


static func by_key(station_key: StringName) -> StationDef:
	if Engine.is_editor_hint() or _by_key.is_empty():
		var all: Dictionary[StringName, StationDef] = {}
		for d: ContentDef in ContentLibrary.items(&"station"):
			var s: StationDef = d as StationDef
			if s != null:
				all[s.key] = s
		if Engine.is_editor_hint():
			return all.get(station_key, null)
		_by_key = all
	return _by_key.get(station_key, null)
