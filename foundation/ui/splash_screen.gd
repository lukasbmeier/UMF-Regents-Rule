class_name SplashScreen extends CanvasLayer
## THE SPLASH (DECISIONS #183): the game's name for a moment before the connect screen, on a build
## with a window. What it says and shows is set on its scene (`foundation/ui/splash_screen.tscn`):
## a title (empty: the game's own, `shared/game.json` title), a line under it, an image, the
## colours and how long it stays. Any key or click skips it. Boot plays it (its `splash_screen`)
## and carries on when it is `finished`; a harness that connects for the player (`--autoconnect`,
## `--host=`) or says `--no-splash` never sees it.

signal finished()

## The big line. Empty: the game's title from shared/game.json.
@export var title: String = ""
## The smaller line under it.
@export var subtitle: String = ""
## An image above the title (a logo). Optional.
@export var logo: Texture2D
@export var background: Color = Color(0.035, 0.06, 0.1)
## The title's colour, and the ripples'.
@export var accent: Color = Color(0.62, 0.84, 1.0)
## Seconds fully shown, and to fade in and out.
@export var hold_sec: float = 1.6
@export var fade_sec: float = 0.45

var _root: Control = null
var _ripples: Control = null
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
	_ripples = Control.new()
	_ripples.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ripples.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ripples.draw.connect(_draw_ripples)
	_root.add_child(_ripples)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
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
	_root.modulate.a = 0.0
	visible = false


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


## Go now: fade out from wherever it is.
func skip() -> void:
	if _playing and _t < _fade_out_at:
		_fade_out_at = maxf(_t, fade_sec * _root.modulate.a)
		# Fade out from the alpha it has, not from full.
		_t = _fade_out_at + fade_sec * (1.0 - _root.modulate.a)


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var a: float
	if _t < fade_sec:
		a = _t / maxf(fade_sec, 0.001)
	elif _t < _fade_out_at:
		a = 1.0
	else:
		a = 1.0 - (_t - _fade_out_at) / maxf(fade_sec, 0.001)
	_root.modulate.a = clampf(a, 0.0, 1.0)
	_ripples.queue_redraw()
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
