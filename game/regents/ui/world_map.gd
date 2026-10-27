class_name RegentsWorldMap extends UiWindow
## THE WORLD MAP (Luke, 2026-10-26: "M should open full world map with hoverable icons"): the whole level
## from straight above, north up, with an icon for every gathering node, station and point of interest the
## level's bake names, and you (the arrow). Hover an icon for what it is: a node you have DISCOVERED (been
## near: `RegentsDiscovery`) by its name ("Coal rock"), any other by its skill ("Mining ???"). Points of
## interest (a level's `poi` points: the camp, a harvest zone, a skeleton camp) are named on the map. The
## wheel zooms where the mouse is; drag to pan. M (the HUD's) or Escape closes it. Presentation only.

const MAP_PX: Vector2 = Vector2(760, 560)
## Room round the level's points (metres).
const MARGIN_M: float = 80.0
## The picture's side in pixels.
const CAPTURE_PX: int = 2048
## How near the mouse (px) an icon must be to be hovered.
const HOVER_PX: float = 8.0
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 12.0

const POI_KIND: String = "poi"
const POI: Color = Color(1.0, 0.85, 0.35)
const BACKDROP: Color = Color(0.12, 0.2, 0.28)

## The level pictured: its id, the square of the world shown (x, z of its north-west corner, side).
var level_id: int = -1
var area: Rect2 = Rect2()
## The view: how far zoomed in (1: the whole level), and the world point at the canvas's middle.
var zoom: float = 1.0
var centre: Vector2 = Vector2.ZERO
## What the mouse is over: its label, or "".
var hovered: String = ""

var _canvas: Control = null
var _picture: Texture2D = null
var _capture: SubViewport = null
var _icons: Array[Dictionary] = []
var _seen: Dictionary = {}
var _panning: bool = false


func _init() -> void:
	super()
	title = "World map"
	size_min = MAP_PX + Vector2(24, 60)
	_canvas = Control.new()
	_canvas.custom_minimum_size = MAP_PX
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	content.add_child(_canvas)


## Open on level `id` (the one shown), centred on you; the picture is taken again for another level.
func show_level(id: int) -> void:
	var bake: LevelBake = LevelBake.by_id(id)
	if bake == null:
		return
	if id != level_id:
		level_id = id
		area = area_of(bake)
		_icons = icons_of(bake)
		_picture = null
		_take_picture()
	_seen = RegentsDiscovery.seen_points()
	zoom = 1.0
	centre = area.get_center()
	open()


func _process(_delta: float) -> void:
	if is_open():
		_canvas.queue_redraw()


## The square of the world to show for `bake`: all its points and its spawn, with room round them.
static func area_of(bake: LevelBake) -> Rect2:
	var lo := Vector2(bake.spawn.x, bake.spawn.z)
	var hi := lo
	for p: Dictionary in bake.points:
		var v := Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var side: float = maxf(hi.x - lo.x, hi.y - lo.y) + 2.0 * MARGIN_M
	return Rect2((lo + hi) * 0.5 - Vector2(side, side) * 0.5, Vector2(side, side))


## The icons of `bake`'s points: [{at (x, z), kind: "node" | "station" | "poi", name, point, skill, rock}].
static func icons_of(bake: LevelBake) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in bake.points:
		var kind: String = String(p.get("kind", ""))
		var tags: Array = p.get("tags", []) as Array
		var tag: String = String(tags[0]) if not tags.is_empty() else ""
		var at := Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
		match kind:
			"node":
				var def: NodeDef = node_named(tag)
				out.append({"at": at, "kind": kind, "name": def.display_name if def != null else tag, "point": String(p.get("id", "")),
					"skill": def.skill.display_name if def != null and def.skill != null else "?",
					"rock": def != null and def.depleted == NodeDef.Depleted.RUBBLE})
			"station":
				out.append({"at": at, "kind": kind, "name": tag.capitalize(), "point": String(p.get("id", ""))})
			POI_KIND:
				out.append({"at": at, "kind": kind, "name": tag, "point": String(p.get("id", ""))})
	return out


## The node content named `name` (a node point's tag), or null.
static func node_named(name: String) -> NodeDef:
	for d: ContentDef in ContentLibrary.items(&"node"):
		if d is NodeDef and d.display_name == name:
			return d as NodeDef
	return null


## What an icon says when hovered: a node by its name once seen, else its skill and ???.
static func label_of(icon: Dictionary, seen: Dictionary) -> String:
	if String(icon["kind"]) != "node":
		return String(icon["name"])
	return String(icon["name"]) if seen.has(String(icon["point"])) else "%s ???" % String(icon["skill"])


# --- drawing --------------------------------------------------------------------------------

## Metres per canvas pixel at this zoom.
func _m_per_px() -> float:
	return area.size.x / (minf(MAP_PX.x, MAP_PX.y) * zoom)


func to_canvas(world: Vector2) -> Vector2:
	return MAP_PX * 0.5 + (world - centre) / _m_per_px()


func to_world(px: Vector2) -> Vector2:
	return centre + (px - MAP_PX * 0.5) * _m_per_px()


func _draw_map() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, MAP_PX), BACKDROP)
	if _picture != null:
		_canvas.draw_texture_rect(_picture, Rect2(to_canvas(area.position), area.size / _m_per_px()), false)
	var font: Font = ThemeDB.fallback_font
	var mouse: Vector2 = _canvas.get_local_mouse_position()
	hovered = ""
	var best: float = HOVER_PX
	for icon: Dictionary in _icons:
		var at: Vector2 = to_canvas(icon["at"] as Vector2)
		if at.x < -10.0 or at.y < -10.0 or at.x > MAP_PX.x + 10.0 or at.y > MAP_PX.y + 10.0:
			continue
		match String(icon["kind"]):
			"node":
				var c: Color = RegentsMinimap.ROCK if bool(icon["rock"]) else RegentsMinimap.TREE
				if not _seen.has(String(icon["point"])):
					c = c.darkened(0.45)
				_canvas.draw_circle(at, 3.2, Color(0, 0, 0, 0.8))
				_canvas.draw_circle(at, 2.3, c)
			"station":
				_canvas.draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), RegentsMinimap.STATION)
			POI_KIND:
				var d := PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)])
				_canvas.draw_colored_polygon(d, POI)
				_canvas.draw_string_outline(font, at + Vector2(9, 5), String(icon["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
				_canvas.draw_string(font, at + Vector2(9, 5), String(icon["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, POI)
		var dist: float = at.distance_to(mouse)
		if dist < best:
			best = dist
			hovered = label_of(icon, _seen)
	_draw_me()
	if not hovered.is_empty() and Rect2(Vector2.ZERO, MAP_PX).has_point(mouse):
		var w: float = font.get_string_size(hovered, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var box := Rect2(mouse + Vector2(12, -24), Vector2(w + 12, 22))
		_canvas.draw_rect(box, Color(0.06, 0.06, 0.08, 0.92))
		_canvas.draw_string(font, box.position + Vector2(6, 16), hovered, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85))


## You: an arrow the way you face.
func _draw_me() -> void:
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
	if me == null:
		return
	var at: Vector2 = to_canvas(Vector2(me.global_position.x, me.global_position.z))
	var f3: Vector3 = -me.global_basis.z
	var f := Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.01 else Vector2(0, -1)
	var side := Vector2(-f.y, f.x)
	var tri := PackedVector2Array([at + f * 9.0, at - f * 6.0 + side * 6.0, at - f * 6.0 - side * 6.0])
	_canvas.draw_colored_polygon(tri, Color(0, 0, 0, 0.85))
	_canvas.draw_colored_polygon(PackedVector2Array([at + f * 7.0, at - f * 4.5 + side * 4.5, at - f * 4.5 - side * 4.5]), RegentsMinimap.PLAYER)


func _on_canvas_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before: Vector2 = to_world(mb.position)
			zoom = clampf(zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
			centre += before - to_world(mb.position)   # the point under the mouse stays under it
			_canvas.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _panning:
		centre -= mm.relative * _m_per_px()


## The level from straight above, north up (not headless: nothing is drawn there).
func _take_picture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _capture != null:
		_capture.queue_free()
	_capture = SubViewport.new()
	_capture.size = Vector2i(CAPTURE_PX, CAPTURE_PX)
	_capture.world_3d = get_viewport().world_3d
	_capture.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = area.size.x
	cam.near = 1.0
	cam.far = 1200.0
	cam.position = Vector3(area.get_center().x, 600.0, area.get_center().y)
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	var env: Environment = _capture.world_3d.environment if _capture.world_3d != null else null
	if env != null:
		var clear: Environment = env.duplicate() as Environment
		clear.fog_enabled = false
		clear.volumetric_fog_enabled = false
		cam.environment = clear
	cam.current = true
	_capture.add_child(cam)
	add_child(_capture)
	_picture = _capture.get_texture()
