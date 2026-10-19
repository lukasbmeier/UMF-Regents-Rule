class_name SmeltMinigame extends SkillMinigame
## SMELTING'S BELLOWS THEN POUR, PLAYED (`SmeltModel` says what happens; this draws it and takes presses).
## HEAT: mash Space or click to pump the bellows (every press counts); keep the needle inside the green
## band as it drifts and narrows, never past the red burn line. POUR: a moment after the heat, hold Space
## or the mouse to tilt the crucible, let go to stop, tilt again to top up; end at the mould's line; past
## the brim it spills.

const HOT: Color = Color(1.0, 0.55, 0.15)
const BAND: Color = Color(0.35, 0.85, 0.40, 0.45)
const BURN: Color = Color(0.95, 0.25, 0.20)
const METAL: Color = Color(1.0, 0.70, 0.25)

var model: SmeltModel
var _down: bool = false


func recipe() -> SmeltParams:
	return params as SmeltParams


func duration_ms() -> int:
	return recipe().heat_ms + recipe().pour_ms if recipe() != null else 0


func title() -> String:
	return "Smelting: %s" % recipe().display_name if recipe() != null else "Smelting"


func how_to() -> String:
	return "Mash Space or click to keep the heat in the band; then hold to pour, let go at the line"


func summary(r: Dictionary) -> String:
	return "Heat %d%%   Pour %d%%   (filled %d, the line %d)" % [int(r.get("heat_pm", 0)) / 10, int(r.get("pour_pm", 0)) / 10,
		r.get("fill", 0), r.get("target", 0)]


func _new_model() -> void:
	model = SmeltModel.start(seed_value, recipe())
	_down = false


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()


## An input `code` (PUMP, POUR, STOP) at `t_ms`: what the keys and the mouse call, and what tests drive.
func press_at(t_ms: int, code: int) -> int:
	if state != State.PLAYING:
		return SmeltModel.IGNORED
	record([t_ms, code])
	var ev: int = model.press(t_ms, code)
	queue_redraw()
	return ev


## The button went down or up (Space, the mouse): a pump in the heat, a pour or a stop in the pour.
func button(down: bool) -> void:
	if state != State.PLAYING or down == _down:
		return
	_down = down
	var t: int = elapsed_ms()
	model.advance_to(t)
	if model.in_heat():
		if down:
			press_at(t, SmeltModel.PUMP)
	else:
		press_at(t, SmeltModel.POUR if down else SmeltModel.STOP)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		button(mb.pressed)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or k.echo or k.keycode != KEY_SPACE or state != State.PLAYING or not is_visible_in_tree():
		return
	button(k.pressed)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.PLAYING:
		model.advance_to(elapsed_ms())
	super(delta)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.13, 0.11, 0.10))
	if model == null:
		_draw_frame("")
		return
	var heat_phase: bool = model.in_heat()
	# The furnace's gauge, left.
	var gauge: Rect2 = Rect2(size.x * 0.22, 90.0, 70.0, size.y - 170.0)
	draw_rect(gauge, Color(0.2, 0.18, 0.17))
	var k: int = mini(model.tick, SmeltModel.heat_ticks(recipe()) - 1)
	var b: Vector2i = model.band(k)
	var y_of: Callable = func(v: int) -> float: return gauge.end.y - clampf(float(v) / 1000.0, 0.0, 1.0) * gauge.size.y
	draw_rect(Rect2(gauge.position.x, float(y_of.call(b.x + b.y)), gauge.size.x, float(y_of.call(b.x - b.y)) - float(y_of.call(b.x + b.y))), BAND)
	draw_line(Vector2(gauge.position.x - 8, float(y_of.call(recipe().burn_line))), Vector2(gauge.end.x + 8, float(y_of.call(recipe().burn_line))), BURN, 3.0)
	var hy: float = float(y_of.call(model.heat))
	draw_rect(Rect2(gauge.position.x + 10.0, hy, gauge.size.x - 20.0, gauge.end.y - hy), HOT.darkened(0.15) if heat_phase else HOT.darkened(0.6))
	draw_line(Vector2(gauge.position.x - 14, hy), Vector2(gauge.end.x + 14, hy), Color.WHITE, 3.0)
	draw_string(font, Vector2(gauge.position.x - 20, gauge.end.y + 28), "HEAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE if heat_phase else Color(1, 1, 1, 0.4))
	# The mould, right.
	var mould: Rect2 = Rect2(size.x * 0.62, size.y * 0.35, 150.0, size.y * 0.5)
	draw_rect(mould, Color(0.25, 0.23, 0.22))
	var fy: float = mould.end.y - clampf(float(model.fill) / 1000.0, 0.0, 1.0) * mould.size.y
	draw_rect(Rect2(mould.position.x + 8.0, fy, mould.size.x - 16.0, mould.end.y - fy), METAL)
	var ty: float = mould.end.y - float(model.target) / 1000.0 * mould.size.y
	draw_line(Vector2(mould.position.x - 16, ty), Vector2(mould.end.x + 16, ty), Color.WHITE, 3.0)
	draw_string(font, Vector2(mould.position.x, mould.end.y + 28), "POUR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE if not heat_phase else Color(1, 1, 1, 0.4))
	if model.fill > 1000:
		draw_string(font, Vector2(mould.position.x - 10, mould.position.y - 14), "Spilled!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, BURN)
	# The crucible, tilting while it pours.
	var tilt: float = -0.9 if model.pouring else -0.15
	draw_set_transform(Vector2(mould.position.x - 30.0, mould.position.y - 80.0), tilt)
	draw_rect(Rect2(-60, -40, 90, 70), Color(0.45, 0.42, 0.40))
	draw_rect(Rect2(-54, -34, 78, 20), METAL)
	draw_set_transform(Vector2.ZERO)
	var t: int = elapsed_ms() if state == State.PLAYING else 0
	var hint: String = "Pump: mash Space or click (faster = hotter)"
	if not heat_phase:
		if not model.pour_ready(t):
			hint = "Hands off the bellows... ready to pour"
		elif model.pouring:
			hint = "Pouring... let go at the line"
		elif model.poured:
			hint = "Hold again to top it up, or leave it"
		else:
			hint = "Hold Space or the mouse to pour"
	draw_string(font, Vector2(0, size.y - 24), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color.WHITE)
	_draw_frame("Heat %d%%   Pour %d%%" % [model.heat_score() / 10, model.pour_score() / 10])
