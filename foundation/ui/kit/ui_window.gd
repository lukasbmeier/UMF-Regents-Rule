class_name UiWindow extends PanelContainer
## A WINDOW (DECISIONS #265): a framed panel with a title bar (its title, a close button, drag it to move
## it) and a `content` box to fill, drawn by the game's `UiStyle` like everything else. A genre's
## inventory, crafting station, journal: make one, fill `content`, `open()` it.
##
## While open it frees the cursor (`MouseCapture.hold_free`, under its own reason, so two windows and the
## Escape menu do not fight over it), Escape closes it before the Escape menu hears the key, and `closed`
## says so. Put it on a CanvasLayer over the game (a HUD's). A subclass that has its own `_init` calls `super()`
## first: GDScript does not run this one for it, and `content` would not be there.

signal opened()
signal closed()

enum Place { CENTER, RIGHT, LEFT }

## Its title, in the bar.
@export var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
## Where it opens on screen.
@export var place: Place = Place.CENTER
## Its size (it grows to fit what is in it).
@export var size_min: Vector2 = Vector2(360, 240)
## Escape closes it.
@export var close_on_escape: bool = true

## What the window shows: add rows here.
var content: VBoxContainer = null
var _title_label: Label = null
var _close: Button = null
var _bar: PanelContainer = null
var _dragging: bool = false
var _drag_from: Vector2 = Vector2.ZERO
var _placed: bool = false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override(&"separation", 0)
	add_child(frame)
	_bar = PanelContainer.new()
	_bar.theme_type_variation = &"UiTitleBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.gui_input.connect(_on_bar_input)
	frame.add_child(_bar)
	var row := HBoxContainer.new()
	_bar.add_child(row)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"UiTitle"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text = title
	row.add_child(_title_label)
	_close = Button.new()
	_close.name = "Close"
	_close.text = "✕"
	_close.flat = true
	_close.tooltip_text = "Close (Esc)"
	_close.pressed.connect(close)
	row.add_child(_close)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(margin)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)


func _ready() -> void:
	var style: UiStyle = UiStyle.current()
	# The frame draws the panel; the title bar sits flush in its top, the content inside the padding.
	var frame_style: StyleBoxFlat = style.panel_style()
	frame_style.set_content_margin_all(0)
	add_theme_stylebox_override(&"panel", frame_style)
	var margin: MarginContainer = content.get_parent() as MarginContainer
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, style.padding)
	custom_minimum_size = size_min


## Show it (where `place` says, the first time; where it was dragged after), the cursor free.
func open() -> void:
	if visible:
		return
	visible = true
	MouseCapture.hold_free(_reason(), true)
	if not _placed:
		_place.call_deferred()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	MouseCapture.hold_free(_reason(), false)
	closed.emit()


## Shrink (or grow) to what it holds now, where it is: call it after filling `content` again.
func fit() -> void:
	var at: Vector2 = position
	reset_size()
	position = at


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func _exit_tree() -> void:
	MouseCapture.hold_free(_reason(), false)


func _input(event: InputEvent) -> void:
	if not visible or not close_on_escape:
		return
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _reason() -> StringName:
	return StringName("ui_window_%d" % get_instance_id())


func _place() -> void:
	if not is_inside_tree():
		return
	_placed = true
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	var margin: float = 24.0
	match place:
		Place.RIGHT:
			position = Vector2(screen.x - size.x - margin, (screen.y - size.y) * 0.5)
		Place.LEFT:
			position = Vector2(margin, (screen.y - size.y) * 0.5)
		_:
			position = (screen - size) * 0.5
	position = position.max(Vector2.ZERO)


func _on_bar_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		_drag_from = mb.global_position - global_position
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _dragging:
		var screen: Vector2 = get_viewport_rect().size
		global_position = (mm.global_position - _drag_from).clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))
