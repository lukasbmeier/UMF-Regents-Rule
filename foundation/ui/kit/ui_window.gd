class_name UiWindow extends PanelContainer
## A WINDOW (DECISIONS #265): a framed panel with a title bar (its title, a close button, drag it to move
## it) and a `content` box to fill, drawn by the game's `UiStyle` like everything else. A genre's
## inventory, crafting station, journal: make one, fill `content`, `open()` it.
##
## While open it frees the cursor (`MouseCapture.hold_free`, under its own reason, so two windows and the
## Escape menu do not fight over it), Escape closes it before the Escape menu hears the key, and `closed`
## says so. Put it on a CanvasLayer over the game (a HUD's). A subclass that has its own `_init` calls `super()`
## first: GDScript does not run this one for it, and `content` would not be there.
##
## RESIZED AND REMEMBERED (DECISIONS #310): drag an edge or a corner to resize it, never smaller than `size_min`
## and never off the screen; where it is and its size are kept per window in the player's
## settings file (`Settings.window_place`, keyed by `place_id()`: `window_id`, else a subclass's script, else
## its title) and it opens there next time. Double-click the title bar: back to where the game puts it, at the
## size it needs. Settings, Game, "Remember where windows are" off forgets every window's place. Every game's
## windows do this with no code of their own; `resizable` and `remember` turn either off for one.
##
## IT SCROLLS WHAT IT CANNOT SHOW (DECISIONS #311): `content` sits in a ScrollContainer (`scroller`). The window
## grows to what it holds as rows are added, up to the screen less `SCREEN_MARGIN` on each side, and scrolls
## past that; one the player made smaller than what it holds scrolls too. Up and down by default; sideways only
## when a row cannot wrap to its width. A `content` emptied and filled again in one frame (a game's refresh) keeps
## its scroll where the new rows reach (the ScrollContainer's own; `tests/suites/ui_window.gd` holds it to that).

signal opened()
signal closed()
## The player moved or resized it (`rect` its place and size now), as they let go.
signal placed(rect: Rect2)

enum Place { CENTER, RIGHT, LEFT }

## The edges a resize pulls (`edges_at`): a side alone, or a corner's two.
const EDGE_LEFT: int = 1
const EDGE_RIGHT: int = 2
const EDGE_TOP: int = 4
const EDGE_BOTTOM: int = 8
## How far in from its edge (and out past it) a press resizes it, in pixels.
const GRIP: float = 6.0
## How far from the screen's edges a window that grows to what it holds stops (then it scrolls), in pixels.
const SCREEN_MARGIN: float = 24.0
## UiWindow's own script: a window of this class itself is remembered by its title.
const OWN_SCRIPT: String = "res://foundation/ui/kit/ui_window.gd"

## Its title, in the bar.
@export var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
## Where it opens on screen (the first time, or after a reset).
@export var place: Place = Place.CENTER
## Its smallest size (it grows to fit what is in it).
@export var size_min: Vector2 = Vector2(360, 240)
## Escape closes it.
@export var close_on_escape: bool = true
## Its edges and corners resize it.
@export var resizable: bool = true
## Where it is and its size are remembered (per `place_id()`).
@export var remember: bool = true
## The name it is remembered by. Empty: a subclass's script path, else its title.
@export var window_id: StringName = &""

## What the window shows: add rows here.
var content: VBoxContainer = null
## What holds `content` and scrolls it when it cannot be shown whole.
var scroller: ScrollContainer = null
var _title_label: Label = null
var _close: Button = null
var _bar: PanelContainer = null
var _dragging: bool = false
var _drag_from: Vector2 = Vector2.ZERO
var _placed: bool = false
## The size the player gave it (zero: it fits what it holds).
var _user_size: Vector2 = Vector2.ZERO
## The edges a resize under way pulls (0: none), and where it began.
var _resizing: int = 0
var _resize_mouse: Vector2 = Vector2.ZERO
var _resize_rect: Rect2 = Rect2()
## Which window set the cursor's shape for a resize (its instance id; 0: none), so one never clears another's.
static var _cursor_by: int = 0
## A grow to what it holds is waiting for the end of the frame (`_grow_to_content`).
var _grow_queued: bool = false


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
	scroller = ScrollContainer.new()
	scroller.name = "Scroll"
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroller)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(content)
	# It grows to what it holds as rows come and go (a ScrollContainer passes no minimum size up).
	content.minimum_size_changed.connect(_queue_grow)


func _ready() -> void:
	var style: UiStyle = UiStyle.current()
	# The frame draws the panel; the title bar sits flush in its top, the content inside the padding.
	var frame_style: StyleBoxFlat = style.panel_style()
	frame_style.set_content_margin_all(0)
	add_theme_stylebox_override(&"panel", frame_style)
	var margin: MarginContainer = scroller.get_parent() as MarginContainer
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, style.padding)
	custom_minimum_size = size_min


## Show it (where it was left, the first time: remembered, else where `place` says; where it was dragged after),
## the cursor free.
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
	_end_resize(false)
	MouseCapture.hold_free(_reason(), false)
	closed.emit()


## Shrink (or grow) to what it holds now, where it is (up to the screen less `SCREEN_MARGIN`, scrolling past
## that): call it after filling `content` again. A size the player gave it is kept (what does not fit scrolls).
func fit() -> void:
	var at: Vector2 = position
	reset_size()
	size = _user_size.max(get_combined_minimum_size()) if _user_size != Vector2.ZERO else content_size()
	position = at
	if is_inside_tree():
		var r: Rect2 = kept_on_screen(Rect2(position, size), get_combined_minimum_size(), _screen())
		position = r.position
		size = r.size


## The size that shows all it holds, as far as the screen allows (less `SCREEN_MARGIN` on each side), and never
## under `size_min`.
func content_size() -> Vector2:
	var cap: Vector2 = (_screen() - Vector2(SCREEN_MARGIN, SCREEN_MARGIN) * 2.0) if is_inside_tree() else Vector2(INF, INF)
	return sized_to(content.get_combined_minimum_size(), _chrome(), get_combined_minimum_size(), cap)


## A window's size for content of `need` in a frame of `chrome` (its bar, padding, borders): all of it, but no
## larger than `cap` (what scrolls past that) and no smaller than `min_size`.
static func sized_to(need: Vector2, chrome: Vector2, min_size: Vector2, cap: Vector2) -> Vector2:
	return (need + chrome).min(cap.max(min_size)).max(min_size)


## Whether it scrolls now: what it holds is taller (or wider) than it shows.
func scrolls() -> bool:
	return scroller.get_v_scroll_bar().visible or scroller.get_h_scroll_bar().visible


## What is round `content`: the title bar, the padding and the borders.
func _chrome() -> Vector2:
	var margin: MarginContainer = scroller.get_parent() as MarginContainer
	var pad := Vector2(margin.get_theme_constant(&"margin_left") + margin.get_theme_constant(&"margin_right"),
		margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom"))
	var panel: StyleBox = get_theme_stylebox(&"panel")
	var scroll_panel: StyleBox = scroller.get_theme_stylebox(&"panel")
	var frame: Vector2 = (panel.get_minimum_size() if panel != null else Vector2.ZERO) \
		+ (scroll_panel.get_minimum_size() if scroll_panel != null else Vector2.ZERO)
	return pad + frame + Vector2(0.0, _bar.get_combined_minimum_size().y)


## As rows come and go: grow to what it holds (never shrink by itself: `fit()` does), at the end of the frame.
func _queue_grow() -> void:
	if not _grow_queued:
		_grow_queued = true
		_grow_to_content.call_deferred()


func _grow_to_content() -> void:
	_grow_queued = false
	if not is_inside_tree() or _user_size != Vector2.ZERO:
		return   # a size the player gave it is kept: what does not fit scrolls
	var want: Vector2 = content_size().max(size)
	if want == size:
		return
	size = want
	var r: Rect2 = kept_on_screen(Rect2(position, size), get_combined_minimum_size(), _screen())
	position = r.position
	size = r.size


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


## The name it is remembered by: `window_id`, else its script's path (a game's own window class), else its title.
## Empty: it is not remembered.
func place_id() -> String:
	if not window_id.is_empty():
		return String(window_id)
	var s: Script = get_script() as Script
	if s != null and not s.resource_path.is_empty() and s.resource_path != OWN_SCRIPT:
		return s.resource_path
	return title


## PUT IT BACK where the game puts it, at the size it needs, and forget where it was left.
func reset_place() -> void:
	Settings.forget_window_place(place_id())
	_user_size = Vector2.ZERO
	_placed = false
	if visible:
		_place()


## The size the player gave it (zero: it fits what it holds).
func user_size() -> Vector2:
	return _user_size


func _exit_tree() -> void:
	MouseCapture.hold_free(_reason(), false)
	_set_cursor(0)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k: InputEventKey = event as InputEventKey
	if k != null:
		if close_on_escape and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		return
	if resizable and resize_input(event):
		get_viewport().set_input_as_handled()


## A mouse event, in the viewport's terms: a press on an edge or a corner begins a resize, motion carries it (or
## shows the resize cursor over an edge), the release ends it and keeps the new size. True when it was the
## resize's (nothing under it hears it). Public so tests can drive it.
func resize_input(event: InputEvent) -> bool:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var edges: int = edges_at(mb.position)
			if edges == 0 or _covered_at(mb.position):
				return false
			_resizing = edges
			_resize_mouse = mb.position
			_resize_rect = get_global_rect()
			return true
		if _resizing != 0:
			_end_resize(true)
			return true
		return false
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm == null:
		return false
	if _resizing != 0:
		var r: Rect2 = resized(_resize_rect, _resizing, mm.position - _resize_mouse, get_combined_minimum_size(), _screen())
		global_position = r.position
		size = r.size
		_user_size = r.size
		return true
	_set_cursor(0 if _covered_at(mm.position) else edges_at(mm.position))
	return false


## Which of its edges a point (in the viewport's terms) is on: within `GRIP` of one, inside or just out.
func edges_at(p: Vector2) -> int:
	return edges_of(get_global_rect(), p, GRIP)


## Which edges of `rect` point `p` is on, `grip` either side of each (a corner: its two). 0: none.
static func edges_of(rect: Rect2, p: Vector2, grip: float) -> int:
	if not rect.grow(grip).has_point(p) or rect.grow(-grip).has_point(p):
		return 0
	var e: int = 0
	if p.x < rect.position.x + grip:
		e |= EDGE_LEFT
	elif p.x > rect.end.x - grip:
		e |= EDGE_RIGHT
	if p.y < rect.position.y + grip:
		e |= EDGE_TOP
	elif p.y > rect.end.y - grip:
		e |= EDGE_BOTTOM
	return e


## `from` resized by pulling `edges` by `delta`: never smaller than `min_size`, never past the screen (`screen`
## from the origin). The edges not pulled stay where they were.
static func resized(from: Rect2, edges: int, delta: Vector2, min_size: Vector2, screen: Vector2) -> Rect2:
	var l: float = from.position.x
	var t: float = from.position.y
	var r: float = from.end.x
	var b: float = from.end.y
	if edges & EDGE_LEFT:
		l = clampf(l + delta.x, 0.0, maxf(r - min_size.x, 0.0))
	if edges & EDGE_RIGHT:
		r = clampf(r + delta.x, l + min_size.x, maxf(screen.x, l + min_size.x))
	if edges & EDGE_TOP:
		t = clampf(t + delta.y, 0.0, maxf(b - min_size.y, 0.0))
	if edges & EDGE_BOTTOM:
		b = clampf(b + delta.y, t + min_size.y, maxf(screen.y, t + min_size.y))
	return Rect2(l, t, r - l, b - t)


## `rect` kept on a screen of `screen`: no larger than it (nor smaller than `min_size`), then moved onto it.
static func kept_on_screen(rect: Rect2, min_size: Vector2, screen: Vector2) -> Rect2:
	var s: Vector2 = rect.size.min(screen).max(min_size)
	var p: Vector2 = rect.position.clamp(Vector2.ZERO, (screen - s).max(Vector2.ZERO))
	return Rect2(p, s)


func _reason() -> StringName:
	return StringName("ui_window_%d" % get_instance_id())


func _screen() -> Vector2:
	return get_viewport_rect().size


## Where it opens: where it was left (remembered), else where `place` says; on the screen either way.
func _place() -> void:
	if not is_inside_tree():
		return
	_placed = true
	reset_size()
	size = content_size()
	var kept: Dictionary = Settings.window_place(place_id()) if remember else {}
	if not kept.is_empty():
		var s: Vector2 = kept["size"] if resizable else Vector2.ZERO
		var need: Vector2 = get_combined_minimum_size()
		# Never resized: the size that shows what it holds (as placed above); resized: the player's.
		var r: Rect2 = kept_on_screen(Rect2(kept["position"], s.max(need) if s != Vector2.ZERO else size), need, _screen())
		position = r.position
		size = r.size
		_user_size = r.size if s != Vector2.ZERO else Vector2.ZERO
		return
	var screen: Vector2 = _screen()
	var margin: float = 24.0
	match place:
		Place.RIGHT:
			position = Vector2(screen.x - size.x - margin, (screen.y - size.y) * 0.5)
		Place.LEFT:
			position = Vector2(margin, (screen.y - size.y) * 0.5)
		_:
			position = (screen - size) * 0.5
	position = position.max(Vector2.ZERO)


## Keep where it is and its size, as the player leaves it.
func _keep_place() -> void:
	if remember:
		Settings.set_window_place(place_id(), position, _user_size)
	placed.emit(get_global_rect())


func _end_resize(keep: bool) -> void:
	if _resizing == 0:
		return
	_resizing = 0
	_set_cursor(0)
	if keep:
		_keep_place()


## Whether another window lies over this one at `p` (a press there is that window's, not this one's edge).
func _covered_at(p: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var over: Control = get_viewport().gui_get_hovered_control()
	while over != null:
		if over == self:
			return false
		if over is UiWindow:
			return (over as UiWindow).get_global_rect().has_point(p)
		over = over.get_parent() as Control
	return false


func _set_cursor(edges: int) -> void:
	var me: int = get_instance_id()
	if edges == 0:
		if _cursor_by == me:
			_cursor_by = 0
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	_cursor_by = me
	var shape: Input.CursorShape = Input.CURSOR_VSIZE
	var h: bool = edges & (EDGE_LEFT | EDGE_RIGHT) != 0
	var v: bool = edges & (EDGE_TOP | EDGE_BOTTOM) != 0
	if h and v:
		var falling: bool = (edges & EDGE_LEFT != 0) == (edges & EDGE_TOP != 0)
		shape = Input.CURSOR_FDIAGSIZE if falling else Input.CURSOR_BDIAGSIZE
	elif h:
		shape = Input.CURSOR_HSIZE
	Input.set_default_cursor_shape(shape)


func _on_bar_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click and mb.pressed:
			_dragging = false
			reset_place()
			return
		if not mb.pressed and _dragging:
			_dragging = false
			_keep_place()
			return
		_dragging = mb.pressed
		_drag_from = mb.global_position - global_position
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _dragging:
		var screen: Vector2 = get_viewport_rect().size
		global_position = (mm.global_position - _drag_from).clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))
