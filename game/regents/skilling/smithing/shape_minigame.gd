class_name ShapeMinigame extends SkillMinigame
## SMITHING'S SHAPE TO THE OUTLINE, PLAYED (`ShapeModel` says what happens; this draws it and takes the
## strikes). The hot bar is a row of columns on the anvil, the part's outline over it in white; click a
## column to beat it down (some of it spreads into its neighbours). The bar cools as you work: right click
## or R puts it back in the fire. Match the outline: the closer, the better the part.

const HOT: Color = Color(1.0, 0.55, 0.18)
const COLD: Color = Color(0.40, 0.38, 0.38)
const ANVIL: Color = Color(0.22, 0.22, 0.24)

var model: ShapeModel
var last_event: int = ShapeModel.IGNORED
var last_event_ms: int = -100000
var last_column: int = -1
var _acts_seen: int = 0


func part() -> ShapeParams:
	return params as ShapeParams


func duration_ms() -> int:
	return part().duration_ms if part() != null else 0


func title() -> String:
	return "Smithing: %s" % part().display_name if part() != null else "Smithing"


func how_to() -> String:
	return "Click a column to beat it down to the white outline; right click or R to reheat"


func summary(r: Dictionary) -> String:
	return "Strikes %d   Off the outline %d   Reheats %d" % [r.get("strikes", 0), r.get("error", 0), r.get("reheats", 0)]


func _new_model() -> void:
	model = ShapeModel.start(seed_value, part())
	last_event = ShapeModel.IGNORED
	last_event_ms = -100000
	_acts_seen = 0


func _model_result() -> Dictionary:
	return model.result()


## The bar's area on screen, and one column's width.
func bar_rect() -> Rect2:
	return Rect2(size.x * 0.12, 110.0, size.x * 0.76, size.y - 230.0)


func column_at(x: float) -> int:
	var r: Rect2 = bar_rect()
	if x < r.position.x or x >= r.end.x or part() == null:
		return -2
	return int((x - r.position.x) / r.size.x * part().outline.size())


## A strike on `column` (ShapeModel.REHEAT_COLUMN: reheat) at `t_ms`: what clicks call, and tests drive.
func strike_at(t_ms: int, column: int) -> int:
	if state != State.PLAYING:
		return ShapeModel.IGNORED
	record([t_ms, column])
	var ev: int = model.strike(t_ms, column)
	_follow()
	queue_redraw()
	return ev


## Show the strike the model landed last (a click, or one held through a swing).
func _follow() -> void:
	if model.acts == _acts_seen:
		return
	_acts_seen = model.acts
	last_event = model.last_act
	last_event_ms = model.last_act_ms
	last_column = model.last_act_column


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		model.settle(elapsed_ms())
		_follow()
	super(delta)


func _end_model() -> void:
	model.finish()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or state != State.PLAYING:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		strike_at(elapsed_ms(), ShapeModel.REHEAT_COLUMN)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		var c: int = column_at(mb.position.x)
		if c >= 0:
			strike_at(elapsed_ms(), c)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_R and state == State.PLAYING and is_visible_in_tree():
		strike_at(elapsed_ms(), ShapeModel.REHEAT_COLUMN)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.12, 0.12, 0.14))
	if model == null:
		_draw_frame("")
		return
	var r: Rect2 = bar_rect()
	draw_rect(Rect2(r.position.x - 20, r.end.y, r.size.x + 40, 40), ANVIL)
	var n: int = model.heights.size()
	var col_w: float = r.size.x / n
	var top: int = 1
	for h: int in model.heights:
		top = maxi(top, h)
	for h: int in part().outline:
		top = maxi(top, h)
	var px: float = r.size.y / float(top + 4)
	var t: int = elapsed_ms() if state == State.PLAYING else model.last_t_ms
	var heat: float = clampf(float(model.hot_until_ms - t) / float(part().heat_ms), 0.0, 1.0)
	var metal: Color = COLD.lerp(HOT, heat)
	var hover: int = column_at(get_local_mouse_position().x)
	for i: int in n:
		var h: float = model.heights[i] * px
		var c: Color = metal.lightened(0.25) if i == hover else metal
		if i == last_column and t - last_event_ms < 120 and last_event == ShapeModel.STRUCK:
			c = Color.WHITE
		draw_rect(Rect2(r.position.x + i * col_w + 1.0, r.end.y - h, col_w - 2.0, h), c)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var y: float = r.end.y - part().outline[i] * px
		pts.append(Vector2(r.position.x + i * col_w, y))
		pts.append(Vector2(r.position.x + (i + 1) * col_w, y))
	draw_polyline(pts, Color.WHITE, 3.0)
	draw_rect(Rect2(r.position.x, r.end.y + 52, r.size.x * heat, 10), HOT)
	draw_string(font, Vector2(r.position.x, r.end.y + 86), "Hot" if heat > 0.0 else "Cold: right click or R to reheat",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	_draw_frame("Off the outline %d   Strikes %d" % [model.error(), model.strikes])
