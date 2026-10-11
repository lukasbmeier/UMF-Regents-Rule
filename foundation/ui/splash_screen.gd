class_name SplashScreen extends CanvasLayer
## THE SPLASH (DECISIONS #183, #213): the game's name before the connect screen, on a build with a
## window, with its TIPS AND LORE one after another (a loading card). What it says and shows is set
## on the game's scene (`game/splash_screen.tscn`, made from `foundation/ui/splash_screen.tscn`): a
## title (empty: the game's own, `shared/game.json` title), a line under it, a logo, a picture
## behind it, the lines, the colours, ripples (a water game's) and how long it stays (5 s). Any key
## or click skips it. Boot plays it (its `splash_screen`) and carries on when it is `finished`; a
## player who turned it off (Settings, Game: "Splash screen at start"), a harness that connects for
## the player (`--autoconnect`, `--host=`) or one that says `--no-splash` never sees it.

signal finished()

## The big line. Empty: the game's title from shared/game.json.
@export var title: String = ""
## The smaller line under it.
@export var subtitle: String = ""
## An image above the title (a logo). Optional.
@export var logo: Texture2D
## A picture filling the screen behind it (dimmed by `picture_dim`). Optional: the colour alone.
@export var picture: Texture2D
@export_range(0.0, 1.0, 0.05) var picture_dim: float = 0.45
@export var background: Color = Color(0.035, 0.06, 0.1)
## The title's colour, and the ripples'.
@export var accent: Color = Color(0.62, 0.84, 1.0)
## TIPS AND LORE, shown one at a time near the bottom, from a random one onwards ("Hold E beside a
## downed teammate to help them up", a line of the world's history). Empty: none.
@export_multiline var lines: PackedStringArray = PackedStringArray()
## Seconds each line stays.
@export_range(0.5, 20.0, 0.5, "suffix:s") var line_sec: float = 3.0
## Rings spreading under the title, as on still water (a fishing game's).
@export var ripples: bool = false
## Seconds fully shown, and to fade in and out.
@export var hold_sec: float = 5.0
@export var fade_sec: float = 0.45

var _root: Control = null
## What fades IN (the words, the ripples); the background under it is opaque from the first frame.
var _content: Control = null
var _ripples: Control = null
var _line: Label = null
var _order: Array[int] = []
var _line_at: int = 0
var _t: float = 0.0
var _playing: bool = false
## Seconds into the timeline when it began to fade out (a skip brings it forward).
var _fade_out_at: float = -1.0


func _init() -> void:
	layer = 110   # over everything, the F3 net overlay (100) included


func _ready() -> void:
	_root = Control.new()
	_root.name = "Splash"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = background
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	if picture != null:
		var pic := TextureRect.new()
		pic.name = "Picture"
		pic.texture = picture
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.modulate = Color(1, 1, 1, 1).darkened(picture_dim)
		_root.add_child(pic)
	_ripples = Control.new()
	_ripples.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ripples.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripples.draw.connect(_draw_ripples)
	_ripples.visible = ripples
	# The background (and picture) cover the level from the very first frame; only what is drawn on
	# it fades in. Fading the whole thing in let a frame or two of the level show first (Luke).
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_content.add_child(_ripples)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 14)
	center.add_child(box)
	if logo != null:
		var pic := TextureRect.new()
		pic.name = "Logo"
		pic.texture = logo
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(220, 220)
		box.add_child(pic)
	var big := Label.new()
	big.name = "Title"
	big.text = shown_title()
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override(&"font_size", 64)
	big.add_theme_color_override(&"font_color", accent)
	box.add_child(big)
	if not subtitle.is_empty():
		var small := Label.new()
		small.name = "Subtitle"
		small.text = subtitle
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small.add_theme_font_size_override(&"font_size", 18)
		small.modulate = Color(1, 1, 1, 0.6)
		box.add_child(small)
	_line = Label.new()
	_line.name = "Line"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_line.offset_left = -360
	_line.offset_right = 360
	_line.offset_top = -110
	_line.offset_bottom = -50
	_line.add_theme_font_size_override(&"font_size", 20)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_line)
	for i: int in lines.size():
		_order.append(i)
	_order.shuffle()
	_show_line()
	_content.modulate.a = 0.0
	visible = false


## The tip or lore line showing now ("" when there are none).
func shown_line() -> String:
	return _line.text if _line != null else ""


func _show_line() -> void:
	if _order.is_empty():
		_line.text = ""
		return
	_line.text = lines[_order[_line_at % _order.size()]]


## What the title says: the scene's, else the game's.
func shown_title() -> String:
	if not title.is_empty():
		return title
	var game: String = Genres.title()
	return game if not game.is_empty() else ProjectSettings.get_setting("application/config/name", "")


func play() -> void:
	_t = 0.0
	_fade_out_at = fade_sec + hold_sec
	_playing = true
	visible = true


## Go now: fade out from here.
func skip() -> void:
	if _playing and _t < _fade_out_at:
		_fade_out_at = _t


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	# The words fade in over the opaque background; then the whole of it fades out.
	_content.modulate.a = clampf(_t / maxf(fade_sec, 0.001), 0.0, 1.0)
	_root.modulate.a = 1.0 if _t < _fade_out_at else clampf(1.0 - (_t - _fade_out_at) / maxf(fade_sec, 0.001), 0.0, 1.0)
	if ripples:
		_ripples.queue_redraw()
	# The next line every `line_sec`, fading through the change.
	if not _order.is_empty():
		var n: int = int(_t / maxf(line_sec, 0.1))
		if n != _line_at:
			_line_at = n
			_show_line()
		var into: float = fmod(_t, maxf(line_sec, 0.1))
		_line.modulate.a = clampf(minf(into, line_sec - into) / 0.3, 0.0, 1.0) if _order.size() > 1 else 1.0
	if _t >= _fade_out_at + fade_sec:
		_playing = false
		visible = false
		finished.emit()


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	var key: InputEventKey = event as InputEventKey
	var button: InputEventMouseButton = event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo) or (button != null and button.pressed):
		get_viewport().set_input_as_handled()
		skip()


## Rings spreading under the title, as on still water.
func _draw_ripples() -> void:
	var size: Vector2 = _ripples.size
	var centre: Vector2 = Vector2(size.x * 0.5, size.y * 0.5 + 70.0)
	for i: int in range(4):
		var f: float = fmod(_t * 0.35 + float(i) * 0.25, 1.0)
		var radius: Vector2 = Vector2(80.0 + f * size.x * 0.32, (80.0 + f * size.x * 0.32) * 0.22)
		var colour: Color = Color(accent.r, accent.g, accent.b, 0.22 * (1.0 - f))
		_ellipse(centre, radius, colour)


func _ellipse(centre: Vector2, radius: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	for k: int in range(65):
		var a: float = TAU * float(k) / 64.0
		points.append(centre + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	_ripples.draw_polyline(points, colour, 2.0, true)
