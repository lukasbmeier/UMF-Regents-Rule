class_name RegentsMinimap extends Control
## THE MINIMAP (owner, 2026-10-21: "a map overlay in the top right (OSRS style, open for iterations on this
## down the road)"): a round map in the top right corner that turns with the camera, so what is ahead of
## you is up; north is the N on its rim. The ground is the level itself, drawn once from straight above
## when it loads (a hidden camera over the level's bake: its points and spawn, with a margin); on it, a dot
## for everyone and everything nearby: you (the arrow, your facing), other players (white), foes (yellow),
## trees (green), rocks (grey), stations (blue), the training dummy (orange). The mouse wheel over it zooms.
## Presentation only.
##
## A level bigger than one picture (the continent, streamed: only the cells round you are there to picture)
## is pictured round YOU, and pictured again round you as your view nears the picture's edge (Luke's
## playtest, 2026-10-24: "minimap doesn't update out here").
##
## Open for iterations: click-to-walk, a world map (M), markers for orders and quests, the ground's own
## icons, recapturing when trees fall.

const SIZE_PX: float = 196.0
const MARGIN_PX: float = 16.0
## How far its rim is, in metres (the wheel moves it within these).
const RADIUS_MIN_M: float = 15.0
const RADIUS_MAX_M: float = 90.0
## The picture of the level: its side in pixels, and the margin round the bake's points (metres).
const CAPTURE_PX: int = 1024
const CAPTURE_MARGIN_M: float = 30.0
const CAPTURE_MIN_M: float = 80.0
const CAPTURE_MAX_M: float = 400.0
## How long after the level appears its picture is taken (the ground and the trees settle first).
const CAPTURE_AFTER_S: float = 1.5
## Pictured round you (a level bigger than `CAPTURE_MAX_M`): the side, inside the 5 x 5 cells streamed round
## you (320 m), and how long after you near its edge it is taken again (the cells there load first).
const AROUND_M: float = 288.0
const RECAPTURE_AFTER_S: float = 0.75

const PLAYER: Color = Color(1, 1, 1)
const FOE: Color = Color(1.0, 0.86, 0.2)
const TREE: Color = Color(0.35, 0.85, 0.35)
const ROCK: Color = Color(0.72, 0.72, 0.75)
const STATION: Color = Color(0.4, 0.65, 1.0)
const DUMMY: Color = Color(1.0, 0.6, 0.25)
const OUTSIDE: Color = Color(0.09, 0.13, 0.1)
const RIM: Color = Color(0.17, 0.15, 0.12)

## The kinds (regents' character content): the player, a node, a station, the dummy; anything else a foe.
const KIND_PLAYER: int = 0
const KIND_NODE: int = 100
const KIND_STATION: int = 101
const KIND_DUMMY: int = 102

## How far the rim is now (metres).
var radius_m: float = 40.0
## The level's picture: where its top-left corner is (x, z) and how wide it is (metres); none until taken.
var area_origin: Vector2 = Vector2.ZERO
var area_m: float = 0.0
## The dots drawn last frame: [Vector2 on the map (from its centre, pixels), Color], for tests.
var dots: Array = []
## Which way is up on the map: the camera's facing, as an angle from north (radians, clockwise).
var angle: float = 0.0

var _map: TextureRect = null
var _shader: ShaderMaterial = null
var _overlay: Control = null
var _capture: SubViewport = null
var _loader: LevelLoader = null
var _capture_in: float = -1.0
var _captured_level: int = -1
## Whether the level is pictured round you (too big for one picture), and a new picture's countdown.
var _around: bool = false
var _recapture_in: float = -1.0
var _look_in: float = 0.0
## The netcode readout (F3, on in editor runs): while it shows, the map sits under it, not behind it.
var _overlay_panel: Control = null
var _overlay_looked: bool = false


func _init() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -SIZE_PX - MARGIN_PX
	offset_right = -MARGIN_PX
	offset_top = MARGIN_PX
	offset_bottom = MARGIN_PX + SIZE_PX
	_map = TextureRect.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(OUTSIDE)
	_map.texture = ImageTexture.create_from_image(blank)
	_shader = ShaderMaterial.new()
	_shader.shader = _round_shader()
	_shader.set_shader_parameter(&"outside_color", OUTSIDE)
	_shader.set_shader_parameter(&"rim_color", RIM)
	_shader.set_shader_parameter(&"has_map", false)
	_map.material = _shader
	add_child(_map)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_dots)
	add_child(_overlay)
	tooltip_text = "Map: the way you look is up. Mouse wheel: zoom."


static func _round_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform bool has_map = false;
uniform vec2 center_uv = vec2(0.5);
uniform float angle = 0.0;
uniform float view_uv = 0.2;
uniform vec4 outside_color : source_color;
uniform vec4 rim_color : source_color;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float c = cos(angle);
	float s = sin(angle);
	vec2 w = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	vec2 uv = center_uv + w * view_uv;
	bool out_of = uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0 || !has_map;
	vec4 col = out_of ? outside_color : texture(map_tex, uv);
	col = mix(col, rim_color, smoothstep(0.92, 0.95, r));
	col.a *= 1.0 - smoothstep(0.985, 1.0, r);
	COLOR = col;
}
"""
	return sh


## WHERE SOMETHING IS ON THE MAP: `rel` (metres east and south of you) as pixels from the map's centre, the
## map turned so that `facing` (radians clockwise from north) is up, at `px_per_m`.
static func to_map(rel: Vector2, facing: float, px_per_m: float) -> Vector2:
	var c: float = cos(-facing)
	var s: float = sin(-facing)
	return Vector2(rel.x * c - rel.y * s, rel.x * s + rel.y * c) * px_per_m


## Which way a camera looks, as an angle clockwise from north (-Z): 0 north, PI/2 east.
static func facing_of(forward: Vector3) -> float:
	return atan2(forward.x, -forward.z)


## The square of the world to picture for `bake`: its points and spawn with a margin, at least
## `CAPTURE_MIN_M` and at most `CAPTURE_MAX_M` wide. Returns Rect2(x, z of its north-west corner, side, side).
static func area_of(bake: LevelBake) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var spots: Array[Vector2] = []
	if bake != null:
		spots.append(Vector2(bake.spawn.x, bake.spawn.z))
		for p: Dictionary in bake.points:
			spots.append(Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))))
	if spots.is_empty():
		spots.append(Vector2.ZERO)
	for v: Vector2 in spots:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var mid: Vector2 = (lo + hi) * 0.5
	var side: float = clampf(maxf(hi.x - lo.x, hi.y - lo.y) + 2.0 * CAPTURE_MARGIN_M, CAPTURE_MIN_M, CAPTURE_MAX_M)
	return Rect2(mid - Vector2(side, side) * 0.5, Vector2(side, side))


## The dot colour for entity kind `kind` (a node by what works it), or a clear colour for none.
static func colour_of(kind: int, node: NodeComponent = null) -> Color:
	match kind:
		KIND_PLAYER:
			return PLAYER
		KIND_NODE:
			return ROCK if node != null and node.is_rock() else TREE
		KIND_STATION:
			return STATION
		KIND_DUMMY:
			return DUMMY
	return FOE if kind > KIND_DUMMY else Color(0, 0, 0, 0)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		radius_m = clampf(radius_m * (0.85 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85), RADIUS_MIN_M, RADIUS_MAX_M)
		accept_event()


func _process(delta: float) -> void:
	_watch_level(delta)
	_stay_clear()
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
	visible = me != null
	if me == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		angle = facing_of(-cam.global_basis.z)
	var here := Vector2(me.global_position.x, me.global_position.z)
	if area_m > 0.0:
		_shader.set_shader_parameter(&"center_uv", (here - area_origin) / area_m)
		_shader.set_shader_parameter(&"view_uv", radius_m / area_m)
	_shader.set_shader_parameter(&"angle", angle)
	_collect(me, here)
	_overlay.queue_redraw()


## Under the netcode readout while it shows (F3); in the corner when it does not.
func _stay_clear() -> void:
	if not _overlay_looked:
		_overlay_looked = true
		for n: Node in get_tree().root.find_children("*", "", true, false):
			if n is NetDebugOverlay:
				_overlay_panel = n.get_node_or_null(^"Panel") as Control
				break
	var top: float = MARGIN_PX
	if _overlay_panel != null and is_instance_valid(_overlay_panel) and _overlay_panel.is_visible_in_tree():
		var r: Rect2 = _overlay_panel.get_global_rect()
		if r.end.x > get_viewport_rect().size.x - SIZE_PX - MARGIN_PX:
			top = r.end.y + 8.0
	if not is_equal_approx(offset_top, top):
		offset_top = top
		offset_bottom = top + SIZE_PX


## Everyone and everything within the rim, as dots.
func _collect(me: Node3D, here: Vector2) -> void:
	dots.clear()
	var px_per_m: float = (SIZE_PX * 0.5) / radius_m
	var inside: float = SIZE_PX * 0.5 - 5.0
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		if e == null or e == me or not e.is_visible_in_tree() or e.definition == null:
			continue
		var node: NodeComponent = e.find_component(NodeComponent) as NodeComponent if e.definition.kind == KIND_NODE else null
		var colour: Color = colour_of(e.definition.kind, node)
		if colour.a == 0.0 or (node != null and node.depleted):
			continue
		var at: Vector2 = to_map(Vector2(e.global_position.x, e.global_position.z) - here, angle, px_per_m)
		if at.length() <= inside:
			dots.append([at, colour])


func _draw_dots() -> void:
	var c := Vector2(SIZE_PX, SIZE_PX) * 0.5
	for d: Array in dots:
		var at: Vector2 = c + (d[0] as Vector2)
		_overlay.draw_circle(at, 3.4, Color(0, 0, 0, 0.75))
		_overlay.draw_circle(at, 2.4, d[1] as Color)
	# You: an arrow the way you face (your body's yaw, turned as the map is).
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
	if me != null:
		var fwd: Vector3 = -me.global_basis.z
		var dir: Vector2 = to_map(Vector2(fwd.x, fwd.z).normalized(), angle, 1.0)
		var side := Vector2(-dir.y, dir.x)
		var tip: Vector2 = c + dir * 7.0
		var pts := PackedVector2Array([tip, c - dir * 4.0 + side * 4.5, c - dir * 1.5, c - dir * 4.0 - side * 4.5])
		_overlay.draw_colored_polygon(pts, Color(0, 0, 0, 0.8))
		var inner := PackedVector2Array()
		for p: Vector2 in pts:
			inner.append(c + (p - c) * 0.7)
		_overlay.draw_colored_polygon(inner, PLAYER)
	# North on the rim.
	var n: Vector2 = c + to_map(Vector2(0, -1), angle, SIZE_PX * 0.5 - 11.0)
	_overlay.draw_circle(n, 8.0, RIM)
	var font: Font = get_theme_default_font()
	_overlay.draw_string(font, n + Vector2(-4.5, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6))


## THE LEVEL'S PICTURE: taken once a level has shown (and again for another level).
func _watch_level(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _loader == null or not is_instance_valid(_loader):
		# Looked for once a second until found (a script class: `is`, not `find_children`'s type filter).
		_look_in -= delta
		if _look_in > 0.0:
			return
		_look_in = 1.0
		_loader = null
		for n: Node in get_tree().root.find_children("*", "", true, false):
			if n is LevelLoader:
				_loader = n as LevelLoader
				break
		if _loader == null:
			return
	if _loader.level() == null:
		return
	if _loader.level_id() == _captured_level:
		_follow(delta)
		return
	if _capture_in < 0.0:
		_capture_in = CAPTURE_AFTER_S
	_capture_in -= delta
	if _capture_in <= 0.0:
		_capture_in = -1.0
		capture(_loader.level_id())


## A level pictured round you: again, round you, once your view nears the picture's edge.
func _follow(delta: float) -> void:
	if not _around:
		return
	var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
	if me == null:
		return
	var here := Vector2(me.global_position.x, me.global_position.z)
	if _recapture_in < 0.0:
		if leaves_picture(here, RADIUS_MAX_M, area_origin, area_m):
			_recapture_in = RECAPTURE_AFTER_S
		return
	_recapture_in -= delta
	if _recapture_in <= 0.0:
		_recapture_in = -1.0
		capture(_captured_level, here)


## Whether the view round `here` (`view_m` across its radius, with room to walk) reaches past the
## picture's edge (`origin`, `side`): time to picture it again.
static func leaves_picture(here: Vector2, view_m: float, origin: Vector2, side: float) -> bool:
	var room: float = view_m + 20.0
	return here.x - room < origin.x or here.y - room < origin.y or here.x + room > origin.x + side or here.y + room > origin.y + side


## Whether a level's points need more than one picture: then it is pictured round you.
static func is_big(bake: LevelBake) -> bool:
	var whole: Rect2 = area_of(bake)
	return whole.size.x >= CAPTURE_MAX_M


## Picture level `level_id` from straight above, north up, into the map: the whole level, or (one too big
## for a picture) the square `AROUND_M` round `around`.
func capture(level_id: int, around: Variant = null) -> void:
	_captured_level = level_id
	var bake: LevelBake = LevelBake.by_id(level_id)
	_around = is_big(bake)
	var area: Rect2 = area_of(bake)
	if _around:
		var me: Node3D = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as Node3D if EntityRegistry.local_entity_id > 0 else null
		var at: Vector2 = around if around is Vector2 else (Vector2(me.global_position.x, me.global_position.z) if me != null else Vector2.ZERO)
		area = Rect2(at - Vector2(AROUND_M, AROUND_M) * 0.5, Vector2(AROUND_M, AROUND_M))
	area_origin = area.position
	area_m = area.size.x
	if _capture != null:
		_capture.queue_free()
	_capture = SubViewport.new()
	_capture.size = Vector2i(CAPTURE_PX, CAPTURE_PX)
	_capture.world_3d = get_viewport().world_3d
	_capture.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = area_m
	cam.near = 1.0
	cam.far = 800.0   # from 400 m up: the continent's mountains stand well above the camp
	cam.position = Vector3(area.get_center().x, 400.0, area.get_center().y)
	# The level's own light and sky, without its fog: from 80 m up, distance fog washes the ground out.
	var env: Environment = _capture.world_3d.environment if _capture.world_3d != null else null
	if env == null:
		env = _capture.world_3d.fallback_environment if _capture.world_3d != null else null
	if env != null:
		var clear: Environment = env.duplicate() as Environment
		clear.fog_enabled = false
		clear.volumetric_fog_enabled = false
		clear.ssao_enabled = false
		cam.environment = clear
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	cam.current = true
	_capture.add_child(cam)
	add_child(_capture)
	_map.texture = _capture.get_texture()
	_shader.set_shader_parameter(&"map_tex", _map.texture)
	_shader.set_shader_parameter(&"has_map", true)
