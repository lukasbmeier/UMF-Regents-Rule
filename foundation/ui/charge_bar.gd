class_name ChargeBar extends Control
## A THROW'S CHARGE, ON SCREEN (DECISIONS #249): the bar `source` (an `AimCharge`) fills as it is held,
## red past its overcharge, with the release angle as a tick beneath (left: one way, right: the other).
## Shown only while it charges. A genre puts one in its HUD and points it at its AimCharge; a band it
## marks good (`sweet_from`..`sweet_to`) is drawn behind the fill. Presentation only.

@export var source_path: NodePath
## A band of the bar drawn as the good one (both 0: none).
@export_range(0.0, 1.0, 0.01) var sweet_from: float = 0.0
@export_range(0.0, 1.0, 0.01) var sweet_to: float = 0.0
@export var size_px: Vector2 = Vector2(260, 14)
## How far up from the bottom of the screen.
@export var bottom_margin_px: float = 120.0
@export var fill_color: Color = Color(0.95, 0.85, 0.35)
@export var over_color: Color = Color(0.95, 0.3, 0.25)
@export var sweet_color: Color = Color(0.4, 0.85, 0.45, 0.45)

var source: AimCharge = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if source == null and not source_path.is_empty():
		source = get_node_or_null(source_path) as AimCharge


func _process(_delta: float) -> void:
	var on: bool = source != null and is_instance_valid(source) and source.is_charging()
	if on or visible != on:
		visible = on
		queue_redraw()


## Where the bar is drawn, in this control's space.
func bar_rect() -> Rect2:
	# Its own size once laid out over the screen; the screen's before that (a fresh control is tiny).
	var vp: Vector2 = size if size.x >= size_px.x and size.y >= size_px.y + bottom_margin_px else get_viewport_rect().size
	return Rect2(Vector2((vp.x - size_px.x) * 0.5, vp.y - bottom_margin_px - size_px.y), size_px)


func _draw() -> void:
	if source == null or not source.is_charging():
		return
	var r: Rect2 = bar_rect()
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
	if sweet_to > sweet_from:
		draw_rect(Rect2(r.position + Vector2(r.size.x * sweet_from, 0.0), Vector2(r.size.x * (sweet_to - sweet_from), r.size.y)), sweet_color)
	var v: float = source.meter.value
	draw_rect(Rect2(r.position, Vector2(r.size.x * v, r.size.y)), over_color if source.meter.is_over() else fill_color)
	var over_x: float = r.position.x + r.size.x * source.meter.over_from
	draw_line(Vector2(over_x, r.position.y - 3.0), Vector2(over_x, r.end.y + 3.0), over_color, 2.0)
	if source.angle_from_mouse_y:
		var mid: float = r.position.x + r.size.x * 0.5
		var tick_x: float = mid + source.angle * r.size.x * 0.5
		draw_line(Vector2(mid, r.end.y + 6.0), Vector2(mid, r.end.y + 10.0), Color(1, 1, 1, 0.4), 1.0)
		draw_line(Vector2(tick_x, r.end.y + 4.0), Vector2(tick_x, r.end.y + 14.0), Color.WHITE, 3.0)
