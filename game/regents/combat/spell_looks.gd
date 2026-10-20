class_name SpellLooks extends Node3D
## WHAT SPELLS LOOK LIKE IN THE WORLD (owner, 2026-10-20: the Staff): every client draws, from the server's
## rows, a Frost Ring's circle on the ground filling until it lands (`spell_area`), then a flash; and a
## fire on whatever burns (`burning`). Missiles are bodies (their own looks). Presentation only: the server
## decides what lands and what burns. The HUD adds one.

const TABLE_AREA: StringName = &"spell_area"
const TABLE_BURNING: StringName = &"burning"
const RING_COLOR: Color = Color(0.55, 0.8, 1.0)
const FIRE_COLOR: Color = Color(1.0, 0.5, 0.15)
## How long a landed circle flashes.
const FLASH_MSEC: int = 600

## area id -> {"node": Node3D, "fill": MeshInstance3D, "seen_usec": int, "lands_usec": int, "landed_msec": int}
var _areas: Dictionary[int, Dictionary] = {}
## entity id -> its fire
var _fires: Dictionary[int, Node3D] = {}


func _ready() -> void:
	name = "SpellLooks"
	EntityRegistry.global_row_event.connect(_on_global)
	EntityRegistry.entity_row_updated.connect(_on_entity_row)


func _exit_tree() -> void:
	if EntityRegistry.global_row_event.is_connected(_on_global):
		EntityRegistry.global_row_event.disconnect(_on_global)
	if EntityRegistry.entity_row_updated.is_connected(_on_entity_row):
		EntityRegistry.entity_row_updated.disconnect(_on_entity_row)


func _on_global(ev: RowEvent) -> void:
	if ev.table != TABLE_AREA:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		forget_area(int(ev.old.get(&"id")) if ev.old != null else -1)
		return
	var row: RefCounted = ev.current()
	show_area(int(row.get(&"id")), row.get(&"pos") as Vector3, float(row.get(&"radius")), int(row.get(&"lands")), bool(row.get(&"landed")))


func _on_entity_row(ev: RowEvent) -> void:
	if ev.table != TABLE_BURNING:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		put_out(ev.entity_id)
	else:
		set_alight(ev.entity_id)


## A circle at `pos`, `radius` wide, landing at `lands_usec` (the server's clock); `landed` once it has.
func show_area(id: int, pos: Vector3, radius: float, lands_usec: int, landed: bool) -> void:
	var a: Dictionary = _areas.get(id, {})
	if a.is_empty():
		var root := Node3D.new()
		root.name = "Area_%d" % id
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(radius - 0.12, 0.05)
		torus.outer_radius = radius
		ring.mesh = torus
		ring.scale = Vector3(1, 0.1, 1)
		ring.material_override = _glow(RING_COLOR, 1.0)
		root.add_child(ring)
		var fill := MeshInstance3D.new()
		fill.name = "Fill"
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.02
		fill.mesh = disc
		fill.material_override = _glow(Color(RING_COLOR, 0.35), 0.6)
		fill.scale = Vector3(0.01, 1, 0.01)
		root.add_child(fill)
		add_child(root)
		a = {"node": root, "fill": fill, "seen_usec": ClockSync.server_usec(), "lands_usec": lands_usec, "landed_msec": -1}
		_areas[id] = a
	(a["node"] as Node3D).position = pos + Vector3(0, 0.05, 0)
	if landed and int(a["landed_msec"]) < 0:
		a["landed_msec"] = Time.get_ticks_msec()


func forget_area(id: int) -> void:
	var a: Dictionary = _areas.get(id, {})
	if not a.is_empty():
		(a["node"] as Node3D).queue_free()
	_areas.erase(id)


## How far circle `id` has filled, 0..1 (1 when it lands).
func area_fill(id: int) -> float:
	var a: Dictionary = _areas.get(id, {})
	if a.is_empty():
		return 0.0
	var span: float = float(maxi(int(a["lands_usec"]) - int(a["seen_usec"]), 1))
	return clampf(1.0 - float(int(a["lands_usec"]) - ClockSync.server_usec()) / span, 0.0, 1.0)


## Entity `entity_id` burns: a flickering fire on it.
func set_alight(entity_id: int) -> void:
	if _fires.has(entity_id):
		return
	var body: Node3D = EntityRegistry.get_entity(entity_id) as Node3D
	if body == null:
		return
	var fire := Node3D.new()
	fire.name = "Burning"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = FIRE_COLOR
	light.omni_range = 2.5
	light.position = Vector3(0, 1.0, 0)
	fire.add_child(light)
	var core := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.5
	core.mesh = s
	core.position = Vector3(0, 1.1, 0)
	core.material_override = _glow(Color(FIRE_COLOR, 0.55), 2.0)
	fire.add_child(core)
	body.add_child(fire)
	_fires[entity_id] = fire


func put_out(entity_id: int) -> void:
	var f: Node3D = _fires.get(entity_id, null)
	if f != null and is_instance_valid(f):
		f.queue_free()
	_fires.erase(entity_id)


func is_burning(entity_id: int) -> bool:
	return _fires.has(entity_id)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for id: int in _areas:
		var a: Dictionary = _areas[id]
		var fill: MeshInstance3D = a["fill"]
		if int(a["landed_msec"]) >= 0:
			var t: float = clampf(float(now - int(a["landed_msec"])) / float(FLASH_MSEC), 0.0, 1.0)
			fill.scale = Vector3.ONE
			(fill.material_override as StandardMaterial3D).albedo_color = Color(RING_COLOR, 0.7 * (1.0 - t))
		else:
			var k: float = maxf(area_fill(id), 0.01)
			fill.scale = Vector3(k, 1, k)
	for id: int in _fires:
		var f: Node3D = _fires[id]
		if is_instance_valid(f):
			(f.get_node(^"Light") as OmniLight3D).light_energy = 1.2 + 0.5 * sin(float(now) * 0.023) + 0.3 * sin(float(now) * 0.071)


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c, 1.0)
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
