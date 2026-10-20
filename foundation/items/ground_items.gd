class_name GroundItems extends Node3D
## ITEMS ON THE GROUND, SHOWN (DECISIONS #269): each `ground_item` row this player is sent (theirs, or
## anyone's: the server sends nothing else) is a SACK where it lies, a ring under it glowing in its
## grade's colour (`UiStyle.grade_colors`) and its name above it. Walking over one PICKS IT UP: within
## `foundation.ground_pickup_m` less `INSIDE_M` of it, this client asks the server (`pick_up`), which
## checks the reach itself. Boot adds one to every game with a display.
##
## A game says what its items are called and which grade each is (`name_of`, `grade_of`): the
## foundation knows neither. Presentation only (hard rule 11): the server decides what lies where.

const TABLE: StringName = &"ground_item"
## How far inside the server's reach a walk-over asks (its view of you lags yours a little).
const INSIDE_M: float = 0.75
## Ask again for the same one no sooner than this (a refusal, a slow answer).
const ASK_AGAIN_MSEC: int = 1000

## A GAME'S NAME FOR WHAT LIES THERE: (item_def_id, qty, instance_data) -> String. Unset: "Item <id>".
static var name_of: Callable = Callable()
## A GAME'S GRADE FOR IT: (item_def_id, instance_data) -> int (0 the lowest; -1 none: the style's text
## colour). Unset: none.
static var grade_of: Callable = Callable()

## Walking over one picks it up.
@export var auto_pickup: bool = true

## ground row id -> {"node": Node3D, "pos": Vector3, "item": int, "qty": int}
var _rows: Dictionary[int, Dictionary] = {}
## ground row id -> when it was last asked for (msec).
var _asked: Dictionary[int, int] = {}

signal picking_up(ground_id: int)


func _ready() -> void:
	name = "GroundItems"
	if not EntityRegistry.global_row_event.is_connected(_on_row):
		EntityRegistry.global_row_event.connect(_on_row)


func _exit_tree() -> void:
	if EntityRegistry.global_row_event.is_connected(_on_row):
		EntityRegistry.global_row_event.disconnect(_on_row)


func _process(_delta: float) -> void:
	if not auto_pickup or _rows.is_empty():
		return
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D
	if me != null:
		pick_up_near(me.global_position)


func _on_row(ev: RowEvent) -> void:
	if ev.table != TABLE:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		forget(int(ev.old.get(&"id")) if ev.old != null else -1)
		return
	var row: RefCounted = ev.current()
	if row != null:
		show_row(int(row.get(&"id")), int(row.get(&"item_def_id")), int(row.get(&"qty")), String(row.get(&"instance_data")), row.get(&"pos") as Vector3)


## One lies at `pos` (new, or as it is now).
func show_row(id: int, item_def_id: int, qty: int, instance_data: String, pos: Vector3) -> void:
	var at: Dictionary = _rows.get(id, {})
	var node: Node3D = at.get("node", null) as Node3D
	if node == null:
		node = _sack(item_def_id, qty, instance_data)
		node.name = "Ground_%d" % id
		add_child(node)
	node.position = pos
	_rows[id] = {"node": node, "pos": pos, "item": item_def_id, "qty": qty}


## It is gone (picked up, its time up, out of sight).
func forget(id: int) -> void:
	var at: Dictionary = _rows.get(id, {})
	var node: Node3D = at.get("node", null) as Node3D
	if node != null:
		node.queue_free()
	_rows.erase(id)
	_asked.erase(id)


## ASK FOR what lies within reach of `me` and was not asked for just now. The ids asked for.
func pick_up_near(me: Vector3) -> Array[int]:
	var reach: float = maxf(HotRules.number(&"foundation.ground_pickup_m") - INSIDE_M, 0.5)
	var now: int = Time.get_ticks_msec()
	var asked: Array[int] = []
	for id: int in _rows:
		var pos: Vector3 = _rows[id]["pos"]
		var flat: Vector3 = Vector3(pos.x - me.x, (pos.y - me.y) * 0.5, pos.z - me.z)
		if flat.length() > reach or now - int(_asked.get(id, -ASK_AGAIN_MSEC)) < ASK_AGAIN_MSEC:
			continue
		_asked[id] = now
		SpaceTimeSync.call_reducer(&"pick_up", [id], ["u64"])
		picking_up.emit(id)
		asked.append(id)
	return asked


func count() -> int:
	return _rows.size()


## The sack for row `id`, or null (tests).
func sack(id: int) -> Node3D:
	return _rows.get(id, {}).get("node", null) as Node3D


## A SACK: a squat bag, a glowing ring under it in its grade's colour, its name above.
func _sack(item_def_id: int, qty: int, instance_data: String) -> Node3D:
	var grade: int = int(grade_of.call(item_def_id, instance_data)) if grade_of.is_valid() else -1
	var colour: Color = UiStyle.current().grade_color(grade)
	if colour.a <= 0.0:
		colour = UiStyle.current().text
	var root := Node3D.new()
	var bag := MeshInstance3D.new()
	bag.name = "Bag"
	var shape := SphereMesh.new()
	shape.radius = 0.17
	shape.height = 0.28
	bag.mesh = shape
	bag.position = Vector3(0, 0.14, 0)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.33, 0.2)
	cloth.roughness = 0.95
	bag.material_override = cloth
	root.add_child(bag)
	var ring := MeshInstance3D.new()
	ring.name = "Glow"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.3
	ring.mesh = torus
	ring.position = Vector3(0, 0.02, 0)
	ring.scale = Vector3(1, 0.15, 1)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = colour
	glow.emission_enabled = true
	glow.emission = colour
	ring.material_override = glow
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 0.6
	light.omni_range = 1.2
	light.position = Vector3(0, 0.3, 0)
	root.add_child(light)
	var label := Label3D.new()
	label.name = "Name"
	var called: String = String(name_of.call(item_def_id, qty, instance_data)) if name_of.is_valid() else "Item %d" % item_def_id
	label.text = called if qty <= 1 else "%s x%d" % [called, qty]
	label.modulate = colour
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 40
	label.outline_size = 8
	label.position = Vector3(0, 0.55, 0)
	root.add_child(label)
	return root
