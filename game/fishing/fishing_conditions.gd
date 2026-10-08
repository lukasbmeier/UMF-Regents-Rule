class_name FishingConditions extends Node
## GENRE CODE. THE ROUND'S TIME OF DAY AND WEATHER, on this client (DECISIONS #168): the server's
## `fishing_conditions` row for our world, read and named. Put one in the game scene; the HUD says
## them and what they favour, and the sky (`SkyDirector`) shows them. They are the SERVER's: it
## rolls them when a round's lobby opens and they change what bites. Nothing here decides anything.

## The conditions changed (a new round's arrived, or we joined).
signal changed()

const TABLE: StringName = &"fishing_conditions"
const GROUP: StringName = &"fishing_conditions"

var known: bool = false
var round_number: int = 0
var time_index: int = 0
var weather_index: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	EntityRegistry.global_row_event.connect(_on_row)
	SpaceTimeSync.connection_state_changed.connect(func(s: SpaceTimeSync.ConnectionState) -> void:
		if s == SpaceTimeSync.ConnectionState.DISCONNECTED and known:
			known = false
			changed.emit())


## The one in this scene, or null.
static func find(tree: SceneTree) -> FishingConditions:
	return tree.get_first_node_in_group(GROUP) as FishingConditions if tree != null else null


## Set them directly (tests, previews).
func set_conditions(p_round: int, time: int, weather: int) -> void:
	known = true
	round_number = p_round
	time_index = time
	weather_index = weather
	changed.emit()


## The condition ids the catalogue's likes are keyed by: [time, weather].
func tags() -> PackedStringArray:
	return PackedStringArray([str(FishingData.time_of_day(time_index).get("id", "")),
		str(FishingData.weather(weather_index).get("id", ""))])


func time_id() -> String:
	return str(FishingData.time_of_day(time_index).get("id", ""))


func weather_id() -> String:
	return str(FishingData.weather(weather_index).get("id", ""))


## "Dusk, rain".
func words() -> String:
	if not known:
		return ""
	return "%s, %s" % [str(FishingData.time_of_day(time_index).get("name", "?")),
		str(FishingData.weather(weather_index).get("name", "?")).to_lower()]


## What these conditions favour, most first ("good fish, Channel Catfish").
func favoured(count: int = 3) -> PackedStringArray:
	return FishingData.favoured_by(tags(), count) if known else PackedStringArray()


## For the HUD: "Dusk, rain: good fish and junk are biting".
func describe() -> String:
	if not known:
		return ""
	var fav: PackedStringArray = favoured(2)
	if fav.is_empty():
		return words()
	return "%s: %s biting" % [words(), " and ".join(fav) + (" are" if fav.size() > 1 else " is")]


func _on_row(ev: RowEvent) -> void:
	if ev.table != TABLE:
		return
	var row: RefCounted = ev.current()
	if ev.kind == RowEvent.Kind.DELETED or row == null:
		return
	if InterestManager.has_world() and int(row.get(&"world_id")) != InterestManager.world_id:
		return
	var r: int = int(row.get(&"round"))
	var t: int = int(row.get(&"time_of_day"))
	var w: int = int(row.get(&"weather"))
	if known and r == round_number and t == time_index and w == weather_index:
		return
	set_conditions(r, t, w)
